import 'dart:convert';
import 'dart:io';

import 'package:dox_inertia/dox_inertia.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dox_inertia_vite_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  InertiaConfig config({
    String? devServerUrl,
    bool reactRefresh = false,
    List<String> entryPoints = const <String>['resources/js/app.js'],
  }) {
    return InertiaConfig(
      publicPath: dir.path,
      devServerUrl: devServerUrl,
      reactRefresh: reactRefresh,
      entryPoints: entryPoints,
    );
  }

  Future<void> writeManifest(Map<String, dynamic> manifest) async {
    File file = File('${dir.path}/build/.vite/manifest.json');
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(manifest));
  }

  test('dev server from the config url', () async {
    String tags = await Vite(config(devServerUrl: 'http://localhost:5173/'))
        .tags();
    expect(
      tags,
      '<script type="module" src="http://localhost:5173/@vite/client"></script>\n'
      '<script type="module" src="http://localhost:5173/resources/js/app.js"></script>',
    );
  });

  test('dev server from the hot file, with React refresh', () async {
    await File('${dir.path}/hot').writeAsString('http://[::1]:5173\n');
    String tags = await Vite(config(reactRefresh: true)).tags();
    expect(tags, startsWith('<script type="module">\nimport RefreshRuntime'));
    expect(tags, contains("from 'http://[::1]:5173/@react-refresh'"));
    expect(tags, contains('__vite_plugin_react_preamble_installed__ = true'));
    expect(
      tags,
      endsWith('src="http://[::1]:5173/resources/js/app.js"></script>'),
    );
  });

  test('build tags from the manifest, with css of imported chunks', () async {
    await writeManifest(<String, dynamic>{
      'resources/js/app.js': <String, dynamic>{
        'file': 'assets/app-1.js',
        'isEntry': true,
        'css': <String>['assets/app-1.css'],
        'imports': <String>['_shared.js'],
      },
      '_shared.js': <String, dynamic>{
        'file': 'assets/shared-2.js',
        'css': <String>['assets/shared-2.css', 'assets/app-1.css'],
        'imports': <String>['resources/js/app.js'],
      },
      'resources/css/app.css': <String, dynamic>{
        'file': 'assets/style-3.css',
        'isEntry': true,
      },
    });
    String tags = await Vite(
      config(
        entryPoints: <String>['resources/js/app.js', 'resources/css/app.css'],
      ),
    ).tags();
    expect(
      tags,
      '<link rel="stylesheet" href="/build/assets/app-1.css">\n'
      '<link rel="stylesheet" href="/build/assets/shared-2.css">\n'
      '<link rel="stylesheet" href="/build/assets/style-3.css">\n'
      '<script type="module" src="/build/assets/app-1.js"></script>',
    );
  });

  test('a missing entry or manifest throws', () async {
    expect(Vite(config()).tags(), throwsStateError);
    await writeManifest(<String, dynamic>{});
    expect(Vite(config()).tags(), throwsStateError);
  });

  test('the version is a hash of the manifest', () async {
    expect(Vite(config()).manifestHash(), isNull);
    await writeManifest(<String, dynamic>{'a': 1});
    String? first = Vite(config()).manifestHash();
    expect(first, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(Vite(config()).manifestHash(), first);
    await writeManifest(<String, dynamic>{'a': 2});
    expect(Vite(config()).manifestHash(), isNot(first));

    Inertia.configure(config());
    expect(Inertia.version, Vite(config()).manifestHash());
    Inertia.configure(InertiaConfig(publicPath: dir.path, version: 'v9'));
    expect(Inertia.version, 'v9');
  });
}
