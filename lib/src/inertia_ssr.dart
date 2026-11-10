import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Server side rendering (SSR). Dox sends the page to the Inertia SSR
/// server, a Node process that your app runs. The answer is the HTML of
/// the page, so the first visit shows the page before the scripts load.
///
/// Set it in `InertiaConfig.ssr`. With no `ssr`, SSR is off.
/// ```
/// InertiaConfig inertiaConfig = InertiaConfig(
///   ssr: InertiaSsr(),
/// );
/// ```
/// When the SSR server does not answer in time, or gives a bad answer,
/// the visitor gets the normal page, and the browser renders it.
class InertiaSsr {
  /// Throws an [ArgumentError] when [url] is not a full http or https
  /// url. So a wrong url stops the app at boot, not on the first visit.
  InertiaSsr({
    this.url = 'http://127.0.0.1:13714/render',
    this.timeout = const Duration(seconds: 2),
    this._client,
    this._log,
  }) : _uri = _parse(url);

  /// The render url of the SSR server.
  final String url;

  final Uri _uri;

  /// Where the warnings go. Default: stderr. Tests pass a buffer.
  final StringSink? _log;

  static Uri _parse(String url) {
    Uri? uri = Uri.tryParse(url);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return uri;
    }
    throw ArgumentError.value(
      url,
      'url',
      'The url of InertiaSsr must be a full http or https url, like '
          'http://127.0.0.1:13714/render',
    );
  }

  /// How long to wait for the SSR server.
  final Duration timeout;

  /// One client for all requests, made on first use. Tests pass a fake.
  http.Client? _client;

  /// true after a failure, until the SSR server works again
  bool _failed = false;

  /// Render the page [json] on the SSR server. Null when it fails: then
  /// the caller sends the normal page.
  Future<SsrPage?> render(String json) async {
    // at the timeout the request is aborted, so a hung SSR server does
    // not keep one open socket per visit
    Completer<void> abort = Completer<void>();
    Timer timer = Timer(timeout, abort.complete);
    try {
      http.AbortableRequest request =
          http.AbortableRequest('POST', _uri, abortTrigger: abort.future)
            ..headers[HttpHeaders.contentTypeHeader] = 'application/json'
            ..body = json;
      // timeout() too: a client that can not abort must not make the
      // visitor wait
      http.Response res = await _send(request).timeout(timeout);
      if (res.statusCode != 200) return _fail('status ${res.statusCode}');
      Object? data = jsonDecode(utf8.decode(res.bodyBytes));
      Object? body = data is Map ? data['body'] : null;
      Object? head = data is Map ? data['head'] : null;
      if (body is! String || body.isEmpty) return _fail('no "body" text');
      _failed = false;
      return SsrPage(head is List ? head.join('\n') : '', body);
    } on Exception catch (error) {
      if (abort.isCompleted) {
        return _fail('no answer in ${timeout.inMilliseconds} ms');
      }
      return _fail(error);
    } finally {
      timer.cancel();
    }
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    return http.Response.fromStream(
      await (_client ??= http.Client()).send(request),
    );
  }

  /// Close the client. `InertiaProvider` calls it when the app stops.
  void close() {
    _client?.close();
    _client = null;
  }

  /// Print one warning for the first failure. No more warnings until a
  /// render works again, so a stopped SSR server does not fill the log.
  SsrPage? _fail(Object reason) {
    if (!_failed) {
      _failed = true;
      (_log ?? stderr).writeln(
        'dox_inertia: SSR failed at $url ($reason). Pages are sent '
        'without SSR until the SSR server works again.',
      );
    }
    return null;
  }
}

/// The answer of the SSR server for one page.
class SsrPage {
  const SsrPage(this.head, this.body);

  /// The tags for `<head>`, like `<title>`. Can be empty.
  final String head;

  /// The HTML that goes in place of `@inertia`.
  final String body;
}
