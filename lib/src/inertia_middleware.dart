import 'dart:async';

import 'package:dox_core/dox_core.dart';

import 'inertia.dart';

/// Runs on every Inertia route. Add it to `globalMiddleware` or to a
/// router, after `SessionMiddleware` and `CsrfMiddleware`.
///
/// - It shares the props of [share] with every page.
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
    Inertia.share(req, await share(req));
    DoxResponse res = await next();
    if (res.status == 302 &&
        Inertia.isInertia(req) &&
        const <String>['PUT', 'PATCH', 'DELETE'].contains(req.method)) {
      res.statusCode(303);
    }
    return res;
  }
}
