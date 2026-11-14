import 'dart:io';

import 'package:dox_annotation/command.dart';
import 'package:dox_annotation/install.dart';

/// `dox inertia:install`. `dox add inertia` runs it. It sets up the server
/// side of Inertia in an app: the config, the provider and the root view.
/// It does not make the JavaScript front-end. It never overwrites a file,
/// so it is safe to run twice.
class InertiaInstallCommand extends Command {
  /// [root] is the app folder (the current folder by default). [runner]
  /// runs `dart`, tests pass a fake one.
  InertiaInstallCommand({this.root, this.runner});

  final Directory? root;
  final ProcessRunner? runner;

  @override
  String get name => 'inertia:install';

  @override
  String get description => 'Set up the server side of Inertia in this app';

  @override
  String get usage => 'inertia:install';

  @override
  Future<void> run(List<String> args) async {
    if (args.isNotEmpty) {
      print('Unknown option. inertia:install has no options.');
      exitCode = 1;
      return;
    }
    Installer installer = Installer(root: root, runner: runner);
    String app = installer.appName;

    /// first, so an app without the AppEnv class gets the hint and
    /// nothing else is changed
    for (String getter in envGetters) {
      installer.addEnvGetter(getter);
    }
    if (!installer.ok) {
      installer.printSummary(<String>[
        'lib/config/env.dart has no `abstract class AppEnv`. Run '
            '`dox env:generate` to make it, then run this again.',
      ]);
      return;
    }

    await installer.addDependency('dox_inertia');
    await installer.addDependency('dox_builder', dev: true);
    await installer.addDependency('build_runner', dev: true);

    installer.writeFile('lib/config/inertia.dart', config(app));
    installer.writeFile('lib/providers/inertia_provider.dart', provider(app));
    installer.writeFile('resources/views/app.html', rootView);

    await installer.buildRunner();
    installer.printSummary(<String>[
      'Add `SessionMiddleware`, `CsrfMiddleware` and an `InertiaMiddleware` '
          'to `globalMiddleware` in lib/config/app.dart.',
      'Set up Vite and the client (`@inertiajs/react`, `vue3` or `svelte`) '
          'with the entry file resources/js/app.jsx. Change `entryPoints` in '
          'lib/config/inertia.dart if yours is another file.',
      "Render a page: `return inertia(req, 'Home', <String, dynamic>{});`.",
      'In production, serve public/build at /build/.',
    ]);
  }

  /// the getters of `AppEnv` that `lib/config/inertia.dart` reads
  static const List<String> envGetters = <String>[
    '/// development, staging or production. Not set: production.\n'
        "  String get appEnv => 'production';",
  ];

  /// `lib/config/inertia.dart`, the same as the docs show. The Vite dev
  /// server is used only in development.
  static String config(String app) {
    return '''
import 'package:dox_inertia/dox_inertia.dart';
import 'package:$app/config/app.dart';
import 'package:$app/config/env.dart';

InertiaConfig inertiaConfig = InertiaConfig(
  /// the Vite entry files
  entryPoints: <String>['resources/js/app.jsx'],

  /// load the scripts from the Vite dev server. null in production.
  devServerUrl: (appConfig.isDevelopment || env.appEnv == 'local')
      ? 'http://localhost:5173'
      : null,

  /// add the React Fast Refresh code in dev mode
  reactRefresh: true,
);
''';
  }

  /// `lib/providers/inertia_provider.dart`, the same as the docs show
  static String provider(String app) {
    return '''
import 'package:dox_inertia/dox_inertia.dart';
import 'package:$app/config/inertia.dart';

class AppInertiaProvider extends InertiaProvider {
  AppInertiaProvider() : super(inertiaConfig);
}
''';
  }

  /// `resources/views/app.html`, the root view of the docs
  static const String rootView = '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>My app</title>
    @vite
  </head>
  <body>
    @inertia
  </body>
</html>
''';
}
