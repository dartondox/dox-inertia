import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dox_core/dox_core.dart';

import 'file_cache.dart';
import 'inertia_config.dart';
import 'inertia_props.dart';
import 'inertia_ssr.dart';
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

  // InertiaMiddleware checks this first. This check is for apps with no
  // InertiaMiddleware.
  DoxResponse? stale = staleVersion(req);
  if (stale != null) return stale;

  Map<String, dynamic> shared = Inertia.shared(req);
  Object? flash = req.hasSession ? req.session.pull(Inertia.flashKey) : null;
  Map<String, dynamic> resolved = await _props(
    req,
    component,
    <String, dynamic>{
      if (req.hasSession) 'errors': AlwaysProp(_errors(req)),
      ...shared,
      ...props,
    },
  );
  Map<String, dynamic> page = <String, dynamic>{
    'component': component,
    'url': url,
    'version': version,
    // read after the props: a prop function can call these too
    'clearHistory': Inertia._takeClearHistory(req),
    'encryptHistory': Inertia._encrypt[req] ?? Inertia.config.encryptHistory,
    ...resolved,
    // the client keeps these props on an instant visit
    if (shared.isNotEmpty) 'sharedProps': shared.keys.toList(),
    if (flash is Map && flash.isNotEmpty) 'flash': flash,
  };

  if (isInertia) {
    // the content stays the page Map: Dox turns it into JSON
    return response(page)
        .header('X-Inertia', 'true')
        .header(HttpHeaders.varyHeader, 'X-Inertia');
  }

  InertiaConfig config = Inertia.config;
  String root = await FileCache.read(Inertia._rootView[req] ?? config.rootView);
  String json = _encode(page);
  SsrPage? ssr = await config.ssr?.render(json);
  String html = Inertia._fill(
    root,
    await Vite(config).tags(),
    ssr?.body ?? _root(json),
    ssr?.head ?? '',
    req,
  );
  return response(html)
      .contentType(ContentType.html)
      .header(HttpHeaders.varyHeader, 'X-Inertia');
}

/// Internal, for `inertia()` and `InertiaMiddleware`: `409` when the
/// browser has old assets and must load the whole page again, else null.
/// The flash data is kept for the next request, so a flash message is not
/// lost on the full page load after a deploy.
DoxResponse? staleVersion(DoxRequest req) {
  if (!Inertia.isInertia(req) ||
      req.method != 'GET' ||
      (req.header('X-Inertia-Version') ?? '') == (Inertia.version ?? '')) {
    return null;
  }
  if (req.hasSession) {
    // ponytail: all() reads the session first. reflash() of dox_core
    // 3.0.2 keeps nothing when the session was not read yet.
    req.session.all();
    req.session.reflash();
  }
  String url = req.uri.hasQuery
      ? '${req.uri.path}?${req.uri.query}'
      : req.uri.path;
  return Inertia.location(req, '${req.scheme()}://${req.host()}$url');
}

/// The flashed validation errors, `{}` when there are none. With the
/// `X-Inertia-Error-Bag` header they are under the name of the bag.
Map<String, dynamic> _errors(DoxRequest req) {
  Map<String, dynamic> errors = req.session.errors;
  String? bag = req.header('X-Inertia-Error-Bag');
  if (errors.isEmpty || bag == null || bag.isEmpty) return errors;
  return <String, dynamic>{bag: errors};
}

/// The [page] as JSON. A prop that can not be turned into JSON throws an
/// error that names the prop.
String _encode(Map<String, dynamic> page) {
  try {
    return jsonEncode(page, toEncodable: _toJson);
  } on JsonUnsupportedObjectError catch (error) {
    Map<String, dynamic> props = page['props'] as Map<String, dynamic>;
    for (MapEntry<String, dynamic> prop in props.entries) {
      try {
        jsonEncode(prop.value, toEncodable: _toJson);
      } on JsonUnsupportedObjectError {
        throw _PropJsonError(prop.key, error);
      }
    }
    rethrow;
  }
}

/// A prop that can not be turned into JSON. It is still a
/// [JsonUnsupportedObjectError], with a message that names the prop.
class _PropJsonError extends JsonUnsupportedObjectError {
  _PropJsonError(this.prop, JsonUnsupportedObjectError error)
    : super(error.unsupportedObject, cause: error.cause);

  final String prop;

  @override
  String toString() {
    String type = unsupportedObject.runtimeType.toString();
    String reason = cause is NoSuchMethodError
        ? '$type has no toJson() method. Add toJson() to $type, or pass a '
              'Map, List, String, num, bool or DateTime.'
        : 'toJson() of $type failed: $cause';
    return 'The Inertia prop "$prop" can not be turned into JSON: $reason';
  }
}

/// The HTML of `@inertia` for Inertia v3: the page [json] in a
/// `<script data-page="app">` tag, then the `<div id="app">` the app
/// renders into.
String _root(String json) {
  // `<`, `>` and `&` only appear inside JSON strings, so the \u escapes
  // keep the same data. With no `<`, a prop can not end the script tag.
  json = json
      .replaceAll('<', r'\u003c')
      .replaceAll('>', r'\u003e')
      .replaceAll('&', r'\u0026');
  return '<script data-page="app" type="application/json">$json</script>'
      '<div id="app"></div>';
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
    bool merges =
        value is MergeProp || (value is DeferProp && value.shouldMerge);
    if (merges && !reset.contains(name)) merge.add(name);
    FutureOr<Object?> resolved = _resolve(value);
    props[name] = resolved is Future<Object?> ? await resolved : resolved;
  }
  return <String, dynamic>{
    'props': props,
    if (merge.isNotEmpty) 'mergeProps': merge,
    if (deferred.isNotEmpty) 'deferredProps': deferred,
  };
}

/// the value of a prop: unwrap it, run it when it is a function, wait
/// for it when it is a Future. Maps and lists in it are resolved too, so
/// `{'auth': {'user': () => ...}}` works.
///
/// It gives the value at once (no Future) when there is nothing to wait
/// for, so a big list of plain row maps does not await once per row.
FutureOr<Object?> _resolve(Object? value) {
  if (value is InertiaProp) value = value.value;
  if (value is Object? Function()) value = value();
  if (value is Future<Object?>) return value.then(_resolveItems);
  return _resolveItems(value);
}

/// the items of a map or a list resolved, else [value] as it is
FutureOr<Object?> _resolveItems(Object? value) {
  if (value is Map) return _resolveMap(value);
  if (value is List) return _resolveList(value);
  return value;
}

/// [value] with each item resolved. It waits only from the first item
/// that gives a Future, so the items still run one after the other.
FutureOr<Object?> _resolveList(List<Object?> value) {
  List<Object?> items = <Object?>[];
  for (int i = 0; i < value.length; i++) {
    FutureOr<Object?> item = _resolve(value[i]);
    if (item is Future<Object?>) return _waitList(value, items, i, item);
    items.add(item);
  }
  return items;
}

Future<Object?> _waitList(
  List<Object?> value,
  List<Object?> items,
  int i,
  Future<Object?> item,
) async {
  items.add(await item);
  for (i++; i < value.length; i++) {
    FutureOr<Object?> next = _resolve(value[i]);
    items.add(next is Future<Object?> ? await next : next);
  }
  return items;
}

/// like [_resolveList], for the values of a map. A map of plain values
/// makes no extra list.
FutureOr<Object?> _resolveMap(Map<Object?, Object?> value) {
  Map<Object?, Object?> map = <Object?, Object?>{};
  Iterator<MapEntry<Object?, Object?>> entries = value.entries.iterator;
  while (entries.moveNext()) {
    MapEntry<Object?, Object?> entry = entries.current;
    FutureOr<Object?> item = _resolve(entry.value);
    if (item is Future<Object?>) {
      // copy the rest before the first await, so a change to [value]
      // while it waits can not break the loop
      List<MapEntry<Object?, Object?>> rest = <MapEntry<Object?, Object?>>[];
      while (entries.moveNext()) {
        rest.add(entries.current);
      }
      return _waitMap(rest, map, entry.key, item);
    }
    map[entry.key] = item;
  }
  return map;
}

Future<Object?> _waitMap(
  List<MapEntry<Object?, Object?>> rest,
  Map<Object?, Object?> map,
  Object? key,
  Future<Object?> item,
) async {
  map[key] = await item;
  for (MapEntry<Object?, Object?> entry in rest) {
    FutureOr<Object?> next = _resolve(entry.value);
    map[entry.key] = next is Future<Object?> ? await next : next;
  }
  return map;
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
  static final Map<String, dynamic> _global = <String, dynamic>{};
  static final Expando<bool> _encrypt = Expando<bool>();
  static final Expando<bool> _clear = Expando<bool>();
  static final Expando<String> _rootView = Expando<String>();
  static final Expando<Map<String, Object?>> _viewData =
      Expando<Map<String, Object?>>();

  /// Use [config] in this isolate. `InertiaProvider` calls it.
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

  /// Share the prop [key] with every page of the app. Call it once at boot, eg.
  /// in the `setup()` of your `InertiaProvider`, so it runs in every isolate.
  ///
  /// Only for app wide values: a constant, or a function that does not
  /// read a request. The value is kept for all users and all requests.
  /// For data of one user, like the signed in user, use
  /// `InertiaMiddleware.share` or `Inertia.share(req, ...)`.
  /// A prop shared for the request, and a page prop, win over it.
  /// ```
  /// Inertia.shareGlobal('appName', 'Dox');
  /// ```
  static void shareGlobal(String key, Object? value) {
    _global[key] = value;
  }

  /// the props of [shareGlobal], plus the props shared with [share] for
  /// this request
  static Map<String, dynamic> shared(DoxRequest req) {
    Map<String, dynamic>? props = _shared[req];
    if (_global.isEmpty) return props ?? const <String, dynamic>{};
    return <String, dynamic>{..._global, ...?props};
  }

  /// The same as `inertia(req, component, props)`.
  static Future<DoxResponse> render(
    DoxRequest req,
    String component, [
    Map<String, dynamic> props = const <String, dynamic>{},
  ]) {
    return inertia(req, component, props);
  }

  /// A prop that is sent only when a partial reload asks for it.
  static OptionalProp optional(Object? Function() callback) {
    return OptionalProp(callback);
  }

  /// The same as [optional].
  static OptionalProp lazy(Object? Function() callback) {
    return OptionalProp(callback);
  }

  /// A prop that loads right after the first visit, in its [group].
  /// With [merge], the page adds it to its old value, like
  /// `Inertia.merge`. `Inertia.defer(fn).merge()` does the same.
  static DeferProp defer(
    Object? Function() callback, {
    String group = 'default',
    bool merge = false,
  }) {
    return DeferProp(callback, group: group, shouldMerge: merge);
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

  /// Use the HTML file at [path] as the root view of this request, in
  /// place of `InertiaConfig.rootView`. Eg. another layout for an admin
  /// area. `RootViewMiddleware` does it for a router.
  ///
  /// Use a fixed [path]. Never pass a value from the request: it could
  /// show any file of the server as the page.
  /// ```
  /// Inertia.setRootView(req, 'resources/views/admin.html');
  /// return inertia(req, 'Admin/Home');
  /// ```
  static void setRootView(DoxRequest req, String path) {
    _rootView[req] = path;
  }

  /// Give [data] to the root view of this request. `{{ key }}` in the
  /// root view becomes the value, HTML escaped. The data is not a page
  /// prop: it is never sent to the browser as JSON. A later call adds
  /// to the data, and the same key wins.
  ///
  /// A key has letters, digits and `_`. `{{ key }}` with a key that is
  /// not in the data stays as it is. `{{ csrfToken }}` is filled with
  /// the CSRF token of the session when the request has a session.
  /// ```
  /// Inertia.withViewData(req, <String, Object?>{'title': 'Users'});
  /// return inertia(req, 'Users/Index');
  /// ```
  static void withViewData(DoxRequest req, Map<String, Object?> data) {
    _viewData[req] = <String, Object?>{...?_viewData[req], ...data};
  }

  static final RegExp _headEnd = RegExp('</head>', caseSensitive: false);
  static final RegExp _placeholder = RegExp(r'\{\{\s*([A-Za-z0-9_]+)\s*\}\}');
  static const HtmlEscape _escape = HtmlEscape(
    HtmlEscapeMode(escapeLtGt: true, escapeQuot: true, escapeApos: true),
  );

  /// The [root] view with the Vite [tags] in place of the first `@vite`,
  /// the [body] in place of the first `@inertia`, the SSR [head] tags
  /// right before the first `</head>` (in any case), and each
  /// `{{ key }}` of the view data of [req] replaced by its value.
  ///
  /// All places are found in [root] before anything is put in.
  /// So text that is put in, like a prop or a title with `@inertia`,
  /// `</head>` or `{{ key }}` in it, is never read as a mark.
  static String _fill(
    String root,
    String tags,
    String body,
    String head,
    DoxRequest req,
  ) {
    // the place in [root] gives the text to put there, and how much of
    // [root] it replaces. Sorted by place.
    SplayTreeMap<int, (int, String)> parts = SplayTreeMap<int, (int, String)>();
    int vite = root.indexOf('@vite');
    if (vite >= 0) parts[vite] = ('@vite'.length, tags);
    int inertia = root.indexOf('@inertia');
    if (inertia >= 0) parts[inertia] = ('@inertia'.length, body);
    int headEnd = head.isEmpty ? -1 : root.indexOf(_headEnd);
    if (headEnd >= 0) parts[headEnd] = (0, '$head\n');
    // a root view with no `{{` (the normal case) skips the search
    if (root.contains('{{')) {
      Map<String, Object?> data = _viewData[req] ?? const <String, Object?>{};
      for (RegExpMatch match in _placeholder.allMatches(root)) {
        String key = match[1]!;
        Object? value;
        if (data.containsKey(key)) {
          value = data[key];
        } else if (key == 'csrfToken' && req.hasSession) {
          // read only when the root view asks for it: the session
          // makes the token on first use
          value = req.session.token;
        } else {
          continue;
        }
        parts[match.start] = (
          match.end - match.start,
          value == null ? '' : _escape.convert('$value'),
        );
      }
    }

    StringBuffer html = StringBuffer();
    int at = 0;
    for (MapEntry<int, (int, String)> part in parts.entries) {
      html.write(root.substring(at, part.key));
      html.write(part.value.$2);
      at = part.key + part.value.$1;
    }
    html.write(root.substring(at));
    return html.toString();
  }

  /// Encrypt the browser history of the page this request renders, or
  /// not with `false`. It wins over `InertiaConfig.encryptHistory`.
  /// The browser only encrypts on HTTPS (and on localhost).
  /// ```
  /// Inertia.encryptHistory(req);
  /// return inertia(req, 'Account/Show', props);
  /// ```
  static void encryptHistory(DoxRequest req, [bool encrypt = true]) {
    _encrypt[req] = encrypt;
  }

  /// The session key of [clearHistory].
  static const String clearHistoryKey = '_inertia_clear_history';

  /// Tell the browser to throw away its encrypted history, eg. on
  /// logout. The next Inertia page carries `clearHistory: true`, once.
  ///
  /// With a session, it is kept until the next page renders, so it
  /// works before a redirect. With no session, it only works when this
  /// same request renders a page.
  /// ```
  /// Inertia.clearHistory(req);
  /// return redirect('/login');
  /// ```
  static void clearHistory(DoxRequest req) {
    if (req.hasSession) {
      req.session.put(clearHistoryKey, true);
    } else {
      _clear[req] = true;
    }
  }

  /// true when [clearHistory] was called for this page. It is read once.
  static bool _takeClearHistory(DoxRequest req) {
    bool stored = req.hasSession && req.session.pull(clearHistoryKey) == true;
    return stored || _clear[req] == true;
  }

  /// The session key of the data from [flash].
  static const String flashKey = '_inertia_flash';

  /// Send [value] as `flash[key]` with the next page, eg. after a
  /// redirect. The page reads it from `page.flash`. It is sent once.
  /// Needs `SessionMiddleware`.
  /// ```
  /// Inertia.flash(req, 'message', 'User saved');
  /// return redirect('/users');
  /// ```
  static void flash(DoxRequest req, String key, Object? value) {
    Object? data = req.session.get(flashKey);
    req.session.flash(flashKey, <String, dynamic>{
      if (data is Map) ...data.cast<String, dynamic>(),
      key: value,
    });
  }
}
