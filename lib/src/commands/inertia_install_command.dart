import 'dart:convert';
import 'dart:io';

import 'package:dox_annotation/command.dart';
import 'package:dox_annotation/install.dart';

/// `dox inertia:install`. `dox add inertia` runs it. It sets up the server
/// side of Inertia in an app: the config, the provider and the root view.
/// It does not make the JavaScript front-end. It never overwrites a file,
/// so it is safe to run twice.
///
/// `--ssr` also adds the SSR entry file and the `build:ssr` script. Then
/// `dox inertia:start-ssr` runs the SSR server.
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
  String get usage => 'inertia:install [--ssr]';

  @override
  Future<void> run(List<String> args) async {
    if (args.any((String a) => a != '--ssr')) {
      print('Unknown option. inertia:install only has --ssr.');
      exitCode = 1;
      return;
    }
    bool ssr = args.contains('--ssr');
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

    if (ssr) {
      installer.writeFile('resources/js/ssr.jsx', ssrEntry);
      addBuildScript(installer);
    }

    await installer.buildRunner();
    installer.printSummary(<String>[
      'Add `SessionMiddleware`, `CsrfMiddleware` and an `InertiaMiddleware` '
          'to `globalMiddleware` in lib/config/app.dart.',
      'Set up Vite and the client (`@inertiajs/react`, `vue3` or `svelte`) '
          'with the entry file resources/js/app.jsx. Change `entryPoints` in '
          'lib/config/inertia.dart if yours is another file.',
      "Render a page: `return inertia(req, 'Home', <String, dynamic>{});`.",
      'In production, serve public/build at /build/.',
      if (ssr) ...<String>[
        'Set `ssr: InertiaSsr()` in lib/config/inertia.dart.',
        'In resources/js/app.jsx, use `hydrateRoot` in `setup` when '
            "`el.hasAttribute('data-server-rendered')`. See the SSR docs.",
        'Build with `bun run build:ssr` (or `npm run build:ssr` with Node). '
            'Then start the SSR server with `dox inertia:start-ssr` '
            '(`--node` runs it with Node).',
      ],
    ]);
  }

  /// the `build:ssr` script of the docs
  static const String buildSsrScript =
      'vite build && vite build --ssr resources/js/ssr.jsx '
      '--outDir bootstrap/ssr';

  /// adds `build:ssr` to the `scripts` of package.json. It keeps the other
  /// keys and their order. A missing or broken package.json is not touched.
  void addBuildScript(Installer installer) {
    File file = File('${installer.root.path}/package.json');
    if (!file.existsSync()) {
      installer.note('skipped  package.json (not there)');
      installer.note('hint     add "build:ssr": "$buildSsrScript" to scripts');
      return;
    }
    Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException {
      json = null;
    }
    Object? scripts = json is Map<String, dynamic> ? json['scripts'] : null;
    if (json is! Map<String, dynamic> ||
        (json.containsKey('scripts') && scripts is! Map<String, dynamic>)) {
      installer.note('skipped  package.json (not a valid package file)');
      installer.note('hint     add "build:ssr": "$buildSsrScript" to scripts');
      return;
    }
    Map<String, dynamic> map = scripts is Map<String, dynamic>
        ? scripts
        : <String, dynamic>{};
    if (map.containsKey('build:ssr')) {
      installer.note('skipped  package.json build:ssr (already there)');
      return;
    }
    map['build:ssr'] = buildSsrScript;
    json['scripts'] = map;
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
    installer.note('added    build:ssr to package.json');
  }

  /// `resources/js/ssr.jsx`, the same as the docs show
  static const String ssrEntry = '''
import { createInertiaApp } from '@inertiajs/react'
import createServer from '@inertiajs/react/server'
import ReactDOMServer from 'react-dom/server'

createServer(
  (page) =>
    createInertiaApp({
      page,
      render: ReactDOMServer.renderToString,
      resolve: (name) => {
        const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true })
        return pages[`./Pages/\${name}.jsx`]
      },
      setup: ({ App, props }) => <App {...props} />,
    }),
  { host: '127.0.0.1' },
)
''';

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
