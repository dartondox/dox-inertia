import 'dart:async';

import 'package:dox_core/dox_core.dart';

import 'inertia.dart';

/// Shares props with every page of the routes it runs on, like the
/// signed in user. Extend it and add it to a router or to
/// `globalMiddleware`.
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
abstract class InertiaMiddleware implements IDoxMiddleware {
  /// The props to share. A page prop with the same name wins.
  FutureOr<Map<String, dynamic>> share(DoxRequest req);

  @override
  Future<IDoxRequest> handle(IDoxRequest req) async {
    if (req is DoxRequest) Inertia.share(req, await share(req));
    return req;
  }
}
