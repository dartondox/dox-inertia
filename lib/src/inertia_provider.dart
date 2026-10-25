import 'package:dox_core/dox_core.dart';

import 'inertia.dart';
import 'inertia_config.dart';

/// Sets up Inertia in every isolate. Extend it in `lib/` so the
/// generated container finds it.
/// ```
/// class AppInertiaProvider extends InertiaProvider {
///   AppInertiaProvider() : super(inertiaConfig);
/// }
/// ```
class InertiaProvider extends DoxProvider {
  InertiaProvider(this.config);

  final InertiaConfig config;

  @override
  void setup() {
    Inertia.configure(config);
  }
}
