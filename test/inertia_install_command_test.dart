import 'dart:convert';
import 'dart:io';

import 'package:dox_annotation/install.dart';
import 'package:dox_inertia/commands.dart';
import 'package:test/test.dart';

/// records the `dart` commands, runs nothing
class FakeRunner extends ProcessRunner {
  final List<String> calls = <String>[];

  @override
  Future<int> run(String executable, List<String> args, String folder) async {
    calls.add(args.join(' '));
    return 0;
  }
}

void main() {
  late Directory root;
  late FakeRunner runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dox_inertia_install_');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: my_app\n\ndependencies:\n  dox_core: ^3.1.0\n');
    File('${root.path}/lib/config/env.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('abstract class AppEnv {\n}\n');
    runner = FakeRunner();
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  String read(String path) => File('${root.path}/$path').readAsStringSync();

  Future<void> install(List<String> args) {
    return InertiaInstallCommand(root: root, runner: runner).run(args);
  }

  /// every file of the app and its text
  Map<String, String> snapshot() {
    Map<String, String> files = <String, String>{};
    for (FileSystemEntity f in root.listSync(recursive: true)) {
      if (f is File) files[f.path] = f.readAsStringSync();
    }
    return files;
  }

  test('sets up the server side', () async {
    await install(<String>[]);
    expect(exitCode, 0);
    expect(runner.calls, <String>[
      'pub add dox_inertia',
      'pub add --dev dox_builder',
      'pub add --dev build_runner',
      'run build_runner build',
    ]);
    expect(
      read('lib/config/inertia.dart'),
      contains("import 'package:my_app/config/env.dart';"),
    );
    expect(
      read('lib/providers/inertia_provider.dart'),
      contains("import 'package:my_app/config/inertia.dart';"),
    );
    expect(read('resources/views/app.html'), contains('@inertia'));
    expect(read('lib/config/env.dart'), contains('String get appEnv'));
  });

  test('dev mode comes from appConfig, not an AppEnv getter', () async {
    await install(<String>[]);
    String config = read('lib/config/inertia.dart');
    // computed values come from config, the same as the app template
    expect(config, contains("import 'package:my_app/config/app.dart';"));
    expect(
      config,
      contains("(appConfig.isDevelopment || env.appEnv == 'local')"),
    );
    expect(config, isNot(contains('env.isDevelopment')));
    expect(read('lib/config/env.dart'), isNot(contains('isDevelopment')));
  });

  test('an AppEnv with the old isDevelopment getter is kept', () async {
    String mine =
        'abstract class AppEnv {\n'
        "  String get appEnv => 'production';\n\n"
        "  bool get isDevelopment => appEnv == 'development';\n"
        '}\n';
    File('${root.path}/lib/config/env.dart').writeAsStringSync(mine);
    await install(<String>[]);
    expect(exitCode, 0);
    expect(read('lib/config/env.dart'), mine);
  });

  test(
    'without AppEnv it gives a hint, exit code 1, and changes nothing',
    () async {
      for (String? env in <String?>[null, 'class Other {\n}\n']) {
        File file = File('${root.path}/lib/config/env.dart');
        if (env == null) {
          file.deleteSync();
        } else {
          file.writeAsStringSync(env);
        }
        Map<String, String> before = snapshot();
        await install(<String>[]);
        expect(exitCode, 1);
        expect(runner.calls, isEmpty);
        expect(snapshot(), before);
        exitCode = 0;
      }
    },
  );

  test('a second run changes nothing', () async {
    await install(<String>[]);
    File('${root.path}/resources/views/app.html').writeAsStringSync('mine');
    File('${root.path}/lib/config/inertia.dart').writeAsStringSync('// {');
    Map<String, String> before = snapshot();
    await install(<String>[]);
    expect(exitCode, 0);
    expect(snapshot(), before);
  });

  test('any option stops with exit code 1 and writes nothing', () async {
    for (List<String> args in <List<String>>[
      <String>['--x'],
      <String>['x'],
      <String>['--x='],
    ]) {
      Map<String, String> before = snapshot();
      await install(args);
      expect(exitCode, 1, reason: '$args');
      expect(runner.calls, isEmpty, reason: '$args');
      expect(snapshot(), before, reason: '$args');
      exitCode = 0;
    }
  });

  group('--ssr', () {
    test('writes ssr.jsx and adds the build:ssr script', () async {
      File('${root.path}/package.json').writeAsStringSync(
        '{"name":"x","scripts":{"dev":"vite"},"type":"module"}',
      );
      await install(<String>['--ssr']);
      expect(exitCode, 0);
      expect(read('resources/js/ssr.jsx'), contains('createServer'));
      Map<String, dynamic> json =
          jsonDecode(read('package.json')) as Map<String, dynamic>;
      expect(json.keys.toList(), <String>['name', 'scripts', 'type']);
      Map<String, dynamic> scripts = json['scripts'] as Map<String, dynamic>;
      expect(scripts.keys.toList(), <String>['dev', 'build:ssr']);
      expect(scripts['build:ssr'], InertiaInstallCommand.buildSsrScript);
      expect(read('package.json'), contains('\n  "name"'));
    });

    test('adds scripts when package.json has none', () async {
      File('${root.path}/package.json').writeAsStringSync('{"name":"x"}');
      await install(<String>['--ssr']);
      expect(read('package.json'), contains('"build:ssr"'));
    });

    test('keeps an existing ssr.jsx and build:ssr', () async {
      File('${root.path}/resources/js/ssr.jsx')
        ..createSync(recursive: true)
        ..writeAsStringSync('mine');
      String pkg = '{"scripts":{"build:ssr":"mine"}}';
      File('${root.path}/package.json').writeAsStringSync(pkg);
      await install(<String>['--ssr']);
      expect(read('resources/js/ssr.jsx'), 'mine');
      expect(read('package.json'), pkg);
    });

    test('no package.json: not created', () async {
      await install(<String>['--ssr']);
      expect(File('${root.path}/package.json').existsSync(), isFalse);
      expect(read('resources/js/ssr.jsx'), isNotEmpty);
      expect(exitCode, 0);
    });

    test('invalid package.json is not touched', () async {
      File('${root.path}/package.json').writeAsStringSync('{ nope');
      await install(<String>['--ssr']);
      expect(read('package.json'), '{ nope');
      expect(exitCode, 0);
    });

    test('without --ssr nothing SSR is written', () async {
      await install(<String>[]);
      expect(File('${root.path}/resources/js/ssr.jsx').existsSync(), isFalse);
    });

    test('unknown option is rejected', () async {
      Map<String, String> before = snapshot();
      await install(<String>['--ssr', '--foo']);
      expect(exitCode, 1);
      expect(snapshot(), before);
    });
  });
}
