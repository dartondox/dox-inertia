import 'dart:async';
import 'dart:io';

import 'package:dox_inertia/commands.dart';
import 'package:test/test.dart';

/// a process that has already ended with [code]
class FakeProcess implements Process {
  FakeProcess(this.code);
  final int code;

  @override
  Future<int> get exitCode async => code;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late Directory root;
  late List<List<String>> started;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dox_inertia_ssr_');
    started = <List<String>>[];
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  void make(String name) {
    File('${root.path}/bootstrap/ssr/$name').createSync(recursive: true);
  }

  Future<void> start(List<String> args, {int code = 0, bool missing = false}) {
    return InertiaStartSsrCommand(
      root: root,
      start: (String exe, List<String> a) async {
        started.add(<String>[exe, ...a]);
        if (missing) throw ProcessException(exe, a, 'not found');
        return FakeProcess(code);
      },
    ).run(args);
  }

  test('runs ssr.js with bun and returns its exit code', () async {
    make('ssr.js');
    await start(<String>[], code: 3);
    expect(started, <List<String>>[
      <String>['bun', 'bootstrap/ssr/ssr.js'],
    ]);
    expect(exitCode, 3);
  });

  test('uses ssr.mjs when there is no ssr.js', () async {
    make('ssr.mjs');
    await start(<String>[]);
    expect(started.single, <String>['bun', 'bootstrap/ssr/ssr.mjs']);
    expect(exitCode, 0);
  });

  test('prefers ssr.js over ssr.mjs', () async {
    make('ssr.js');
    make('ssr.mjs');
    await start(<String>[]);
    expect(started.single.last, 'bootstrap/ssr/ssr.js');
  });

  test('--node runs node', () async {
    make('ssr.js');
    await start(<String>['--node']);
    expect(started.single, <String>['node', 'bootstrap/ssr/ssr.js']);
  });

  test('no built file: message and exit code 1', () async {
    await start(<String>[]);
    expect(started, isEmpty);
    expect(exitCode, 1);
  });

  test('unknown option: exit code 1, nothing started', () async {
    make('ssr.js');
    await start(<String>['--deno']);
    expect(started, isEmpty);
    expect(exitCode, 1);
  });

  test('missing bun: exit code 1', () async {
    make('ssr.js');
    await start(<String>[], missing: true);
    expect(exitCode, 1);
  });

  test('missing node: exit code 1', () async {
    make('ssr.js');
    await start(<String>['--node'], missing: true);
    expect(started.single.first, 'node');
    expect(exitCode, 1);
  });
}
