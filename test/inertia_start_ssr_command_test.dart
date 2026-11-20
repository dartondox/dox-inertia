import 'dart:async';
import 'dart:io';

import 'package:dox_inertia/commands.dart';
import 'package:test/test.dart';

/// a process that has already ended with [code]
class FakeProcess implements Process {
  /// ends with [code] at once, or when [end] is called
  FakeProcess(this.code, {bool wait = false}) {
    if (!wait) done.complete(code);
  }
  final int code;
  final Completer<int> done = Completer<int>();
  final List<ProcessSignal> killed = <ProcessSignal>[];

  @override
  Future<int> get exitCode => done.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed.add(signal);
    return true;
  }

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
      signals: (ProcessSignal s) => const Stream<ProcessSignal>.empty(),
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

  test('with both files, the newer one wins', () async {
    make('ssr.js');
    make('ssr.mjs');
    File('${root.path}/bootstrap/ssr/ssr.js')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    await start(<String>[]);
    expect(started.single.last, 'bootstrap/ssr/ssr.mjs');
  });

  test('sends SIGINT and SIGTERM to the child, then stops listening', () async {
    make('ssr.js');
    StreamController<ProcessSignal> int = StreamController<ProcessSignal>();
    StreamController<ProcessSignal> term = StreamController<ProcessSignal>();
    FakeProcess child = FakeProcess(0, wait: true);
    Future<void> run = InertiaStartSsrCommand(
      root: root,
      start: (String exe, List<String> a) async => child,
      signals: (ProcessSignal s) =>
          s == ProcessSignal.sigint ? int.stream : term.stream,
    ).run(<String>[]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    int.add(ProcessSignal.sigint);
    if (!Platform.isWindows) term.add(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    child.done.complete(0);
    await run;
    expect(child.killed.first, ProcessSignal.sigint);
    if (!Platform.isWindows) {
      expect(child.killed.last, ProcessSignal.sigterm);
      expect(term.hasListener, isFalse);
    }
    expect(int.hasListener, isFalse);
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
