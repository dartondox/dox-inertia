import 'dart:async';

import 'package:dox_core/dox_core.dart';

import 'inertia.dart';

/// Runs on every Inertia route. Add it to `globalMiddleware` or to a
/// router, after `SessionMiddleware` and `CsrfMiddleware`.
///
/// - When the browser has old assets (an old `X-Inertia-Version`), it
///   sends `409` before the controller runs. See `Asset version` in the
///   README.
/// - It shares the props of [share] with every page.
/// - An Inertia request that gets an empty `200` answer is sent back to
///   the page it came from (`back(req)`), like Laravel does. Only a
///   `Referer` of the same site is used, else it goes to `/`.
/// - After a PUT, PATCH or DELETE Inertia request, it turns a `302`
///   redirect into `303`. Then the browser follows it with GET.
///
/// Extend it to share props, like the signed in user.
/// ```
/// class HandleInertiaRequests extends InertiaMiddleware {
///   @override
///   Map<String, dynamic> share(DoxRequest req) {
///     return <String, dynamic>{
///       'appName': 'Dox',
///       'auth': () => req.auth?.toJson(),
///     };
///   }
/// }
/// ```
class InertiaMiddleware implements IDoxNextMiddleware {
  const InertiaMiddleware();

  /// The props to share. A page prop with the same name wins.
  FutureOr<Map<String, dynamic>> share(DoxRequest req) {
    return const <String, dynamic>{};
  }

  @override
  Future<DoxResponse> handle(DoxRequest req, Next next) async {
    // old assets: send 409 before the controller runs
    DoxResponse? stale = staleVersion(req);
    if (stale != null) return stale;
    Inertia.share(req, await share(req));
    DoxResponse res = await next();
    if (Inertia.isInertia(req) && _isEmpty(res)) {
      // change this answer, not a new one, so the headers and cookies
      // that the controller set on it are kept
      res.statusCode(302).withHeaders(back(req).headers);
    }
    if (res.status == 302 &&
        Inertia.isInertia(req) &&
        const <String>['PUT', 'PATCH', 'DELETE'].contains(req.method)) {
      res.statusCode(303);
    }
    return res;
  }

  /// true for a `200` with no body, eg. a controller that returns nothing
  bool _isEmpty(DoxResponse res) {
    Object? content = res.getContent();
    return (res.status ?? 200) == 200 && (content == null || content == '');
  }
}
