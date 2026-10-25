import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dox_core/dox_core.dart';

import 'inertia_config.dart';
import 'inertia_props.dart';
import 'vite.dart';

/// Render the page [component] (eg. `Users/Index`) with [props].
///
/// An Inertia request (with `X-Inertia: true`) gets the page as JSON.
/// Any other request gets the root view as HTML, with the page in it.
/// A prop can be a function: it runs only when the prop is sent.
/// ```
/// Future<DoxResponse> index(DoxRequest req) {
///   return inertia(req, 'Users/Index', <String, dynamic>{
///     'users': () => User().query().all(),
///   });
/// }
/// ```
Future<DoxResponse> inertia(
  DoxRequest req,
  String component, [
  Map<String, dynamic> props = const <String, dynamic>{},
]) async {
  String url = req.uri.hasQuery
      ? '${req.uri.path}?${req.uri.query}'
      : req.uri.path;
  String? version = Inertia.version;
  bool isInertia = Inertia.isInertia(req);

  // the browser has old assets: it must load the whole page again
  if (isInertia &&
      req.method == 'GET' &&
      (req.header('X-Inertia-Version') ?? '') != (version ?? '')) {
    return Inertia.location(req, '${req.scheme()}://${req.host()}$url');
  }

  Map<String, dynamic> page = <String, dynamic>{
    'component': component,
    'url': url,
    'version': version,
    'clearHistory': false,
    'encryptHistory': false,
    ...await _props(req, component, <String, dynamic>{
      ...Inertia.shared(req),
      ...props,
    }),
  };

  if (isInertia) {
    return response(page)
        .header('X-Inertia', 'true')
        .header(HttpHeaders.varyHeader, 'X-Inertia');
  }

  InertiaConfig config = Inertia.config;
  String root = await File(config.rootView).readAsString();
  String json = jsonEncode(page, toEncodable: _toJson);
  String data = const HtmlEscape(HtmlEscapeMode.attribute).convert(json);
  // @vite first: a prop can hold the text "@vite", the tags can not
  // hold "@inertia"
  String html = root
      .replaceFirst('@vite', await Vite(config).tags())
      .replaceFirst('@inertia', '<div id="app" data-page="$data"></div>');
  return response(html)
      .contentType(ContentType.html)
      .header(HttpHeaders.varyHeader, 'X-Inertia');
}

/// `props`, plus `deferredProps` and `mergeProps` when there are any
Future<Map<String, dynamic>> _props(
  DoxRequest req,
  String component,
  Map<String, dynamic> all,
) async {
  bool partial =
      Inertia.isInertia(req) &&
      req.header('X-Inertia-Partial-Component') == component;
  List<String> only = _names(req.header('X-Inertia-Partial-Data'));
  List<String> except = _names(req.header('X-Inertia-Partial-Except'));
  List<String> reset = _names(req.header('X-Inertia-Reset'));

  Map<String, dynamic> props = <String, dynamic>{};
  List<String> merge = <String>[];
  Map<String, List<String>> deferred = <String, List<String>>{};
  for (MapEntry<String, dynamic> prop in all.entries) {
    String name = prop.key;
    Object? value = prop.value;
    bool send = partial
        ? (only.isEmpty || only.contains(name)) && !except.contains(name)
        : value is! OptionalProp;
    if (value is DeferProp && !partial) {
      (deferred[value.group] ??= <String>[]).add(name);
    }
    if (!send && value is! AlwaysProp) continue;
    if (value is MergeProp && !reset.contains(name)) merge.add(name);
    props[name] = await _resolve(value);
  }
  return <String, dynamic>{
    'props': props,
    if (merge.isNotEmpty) 'mergeProps': merge,
    if (deferred.isNotEmpty) 'deferredProps': deferred,
  };
}

/// the value of a prop: unwrap it, run it when it is a function, wait
/// for it when it is a Future
Future<Object?> _resolve(Object? value) async {
  if (value is InertiaProp) value = value.value;
  if (value is Object? Function()) value = value();
  if (value is Future<Object?>) value = await value;
  return value;
}

/// `a, b` gives `['a', 'b']`
List<String> _names(String? header) {
  if (header == null) return <String>[];
  return <String>[
    for (String name in header.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];
}

/// like the JSON of Dox responses: dates as ISO text, objects with toJson
Object? _toJson(Object? value) {
  if (value is DateTime) return value.toIso8601String();
  return (value as dynamic).toJson();
}

/// Inertia settings and helpers.
class Inertia {
  static InertiaConfig _config = const InertiaConfig();
  static String? _version;
  static bool _versionRead = false;
  static final Expando<Map<String, dynamic>> _shared =
      Expando<Map<String, dynamic>>();

  /// Use [config] in this isolate. `InertiaService` calls it.
  /// With no call, the defaults of `InertiaConfig` are used.
  static void configure(InertiaConfig config) {
    _config = config;
    _version = null;
    _versionRead = false;
  }

  /// the config from [configure]
  static InertiaConfig get config => _config;

  /// The asset version: `InertiaConfig.version`, else a hash of the Vite
  /// manifest, else null.
  // ponytail: the manifest hash is read once per isolate. Restart the
  // server after a new `vite build` (a deploy does this).
  static String? get version {
    if (_config.version != null) return _config.version;
    if (!_versionRead) {
      _version = Vite(_config).manifestHash();
      _versionRead = true;
    }
    return _version;
  }

  /// true when the request came from the Inertia client
  static bool isInertia(DoxRequest req) => req.header('X-Inertia') == 'true';

  /// Share [props] with the page this request renders. `InertiaMiddleware`
  /// calls it. A page prop with the same name wins.
  static void share(DoxRequest req, Map<String, dynamic> props) {
    _shared[req] = <String, dynamic>{...?_shared[req], ...props};
  }

  /// the props shared with [share] for this request
  static Map<String, dynamic> shared(DoxRequest req) {
    return _shared[req] ?? const <String, dynamic>{};
  }

  /// A prop that is sent only when a partial reload asks for it.
  static OptionalProp optional(Object? Function() callback) {
    return OptionalProp(callback);
  }

  /// A prop that loads right after the first visit, in its [group].
  static DeferProp defer(
    Object? Function() callback, {
    String group = 'default',
  }) {
    return DeferProp(callback, group: group);
  }

  /// A prop that is sent on every partial reload.
  static AlwaysProp always(Object? value) => AlwaysProp(value);

  /// A prop that the page adds to its old value instead of replacing it.
  static MergeProp merge(Object? value) => MergeProp(value);

  /// Go to [url] with a full page load, eg. an outside site. An Inertia
  /// request gets `409` with `X-Inertia-Location`. Others get a redirect.
  static DoxResponse location(DoxRequest req, String url) {
    if (isInertia(req)) {
      return response('').statusCode(409).header('X-Inertia-Location', url);
    }
    return response('').statusCode(302).header(HttpHeaders.locationHeader, url);
  }

  /// Redirect to [url]. After PUT, PATCH or DELETE an Inertia request gets
  /// `303`, so the browser follows it with GET. Others get `302`.
  static DoxResponse redirect(DoxRequest req, String url) {
    bool seeOther =
        isInertia(req) &&
        const <String>['PUT', 'PATCH', 'DELETE'].contains(req.method);
    return response('')
        .statusCode(seeOther ? 303 : 302)
        .header(HttpHeaders.locationHeader, url);
  }
}
