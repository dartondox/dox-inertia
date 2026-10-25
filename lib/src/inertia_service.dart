import 'package:dox_core/dox_core.dart';

import 'inertia.dart';
import 'inertia_config.dart';

/// Sets up Inertia in every isolate. Extend it in `lib/` so the
/// generated container finds it.
/// ```
/// class AppInertiaService extends InertiaService {
///   AppInertiaService() : super(inertiaConfig);
/// }
/// ```
class InertiaService implements DoxService {
  InertiaService(this.config);

  final InertiaConfig config;

  @override
  void setup() {
    Inertia.configure(config);
  }
}
