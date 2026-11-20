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
    String? skipSsr;
    if (ssr && !_isReact(installer.root)) {
      ssr = false;
      skipSsr =
          'SSR scaffolding supports React only. No SSR file was written. '
          'For Vue or Svelte, set up SSR by hand: $docsUrl';
      print(skipSsr);
    }
    _ext = File('${installer.root.path}/resources/js/app.tsx').existsSync()
        ? 'tsx'
        : 'jsx';
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

    bool scriptReady = true;
    if (ssr) {
      installer.writeFile('resources/js/ssr.$_ext', ssrEntryFor(_ext));
      scriptReady = addBuildScript(installer);
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
      ?skipSsr,
      if (ssr) ...<String>[
        'SSR scaffolding is for React and `@inertiajs/react` 3.1.0 or newer '
            '(the `host` option needs it).',
        'Set `ssr: InertiaSsr()` in lib/config/inertia.dart.',
        'In resources/js/app.$_ext, use `hydrateRoot` in `setup` when '
            "`el.hasAttribute('data-server-rendered')`. See the SSR docs.",
        if (!scriptReady)
          'Add this to `scripts` in package.json first: '
              '"build:ssr": "$_script"',
        'Build with `bun run build:ssr` (or `npm run build:ssr` with Node). '
            'Then start the SSR server with `dox inertia:start-ssr` '
            '(`--node` runs it with Node).',
      ],
    ]);
  }

  static const String docsUrl =
      'https://dartondox.dev/the-basic/inertia/#server-side-rendering-ssr';

  /// `jsx`, or `tsx` when the app entry is resources/js/app.tsx
  String _ext = 'jsx';

  /// false only when package.json lists the Vue or Svelte client and not
  /// the React one. No package.json or no client listed: React, as before.
  bool _isReact(Directory folder) {
    File file = File('${folder.path}/package.json');
    if (!file.existsSync()) return true;
    Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return true;
    }
    if (json is! Map<String, dynamic>) return true;
    Set<String> deps = <String>{};
    for (String key in <String>['dependencies', 'devDependencies']) {
      Object? map = json[key];
      if (map is Map<String, dynamic>) deps.addAll(map.keys);
    }
    if (deps.contains('@inertiajs/react')) return true;
    return !deps.contains('@inertiajs/vue3') &&
        !deps.contains('@inertiajs/svelte');
  }

  /// the `build:ssr` script of the docs
  static const String buildSsrScript =
      'vite build && vite build --ssr resources/js/ssr.jsx '
      '--outDir bootstrap/ssr';

  String get _script => buildSsrScript.replaceAll('ssr.jsx', 'ssr.$_ext');

  /// adds `build:ssr` to the `scripts` of package.json. The line is put in
  /// as text, so the indent, the line ends and the other keys stay as they
  /// are. When this cannot be done safely, nothing is changed and a hint is
  /// printed. Returns true when the script is in package.json at the end.
  bool addBuildScript(Installer installer) {
    File file = File('${installer.root.path}/package.json');
    if (!file.existsSync()) {
      installer.note('skipped  package.json (not there)');
      installer.note('hint     add "build:ssr": "$_script" to scripts');
      return false;
    }
    String text = file.readAsStringSync();
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    Object? scripts = json is Map<String, dynamic> ? json['scripts'] : null;
    if (scripts is Map<String, dynamic> && scripts.containsKey('build:ssr')) {
      installer.note('skipped  package.json build:ssr (already there)');
      return true;
    }
    String? changed = scripts is Map<String, dynamic>
        ? _insertScript(text, json as Map<String, dynamic>)
        : null;
    if (changed == null) {
      installer.note('skipped  package.json (could not add build:ssr)');
      installer.note('hint     add "build:ssr": "$_script" to scripts');
      return false;
    }
    file.writeAsStringSync(changed);
    installer.note('added    build:ssr to package.json');
    return true;
  }

  /// [text] with the `build:ssr` line at the start of `"scripts"`, or null
  /// when the result would not be the same JSON plus that one key
  String? _insertScript(String text, Map<String, dynamic> original) {
    for (RegExpMatch match in RegExp(r'"scripts"\s*:\s*\{').allMatches(text)) {
      String? result = _insertAt(text, match.end, original);
      if (result != null) return result;
    }
    return null;
  }

  String? _insertAt(String text, int end, Map<String, dynamic> original) {
    String space = RegExp(r'^\s*').stringMatch(text.substring(end))!;
    bool empty = text.substring(end + space.length).startsWith('}');
    String entry = '"build:ssr": ${jsonEncode(_script)}';
    String unit = RegExp(r'^[ \t]+', multiLine: true).stringMatch(text) ?? '  ';
    String before = text.substring(0, end);
    String after = text.substring(end + space.length);
    String result;
    if (space.contains('\n')) {
      result = empty
          ? '$before$space$unit$entry$space$after'
          : '$before$space$entry,$space$after';
    } else {
      result = empty
          ? '$before$entry$after'
          : '$before$space$entry,${space.isEmpty ? '' : space}$after';
    }
    try {
      Object? now = jsonDecode(result);
      if (now is! Map<String, dynamic>) return null;
      Object? added = (now['scripts'] as Map<String, dynamic>).remove(
        'build:ssr',
      );
      if (added != _script) return null;
      return jsonEncode(now) == jsonEncode(original) ? result : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// `resources/js/ssr.tsx` for a TypeScript app, else `ssr.jsx`
  static String ssrEntryFor(String ext) => ssrEntry.replaceAll('.jsx', '.$ext');

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
