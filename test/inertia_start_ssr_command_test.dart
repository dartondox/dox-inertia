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

  Future<void> start(
    List<String> args, {
    int code = 0,
    ProcessException? fail,
    bool missing = false,
  }) {
    return InertiaStartSsrCommand(
      root: root,
      start: (String exe, List<String> a) async {
        started.add(<String>[exe, ...a]);
        if (missing) throw ProcessException(exe, a, 'No such file', 2);
        if (fail != null) throw fail;
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
      signals: (ProcessSignal s) => s == ProcessSignal.sigint
          ? int.stream
          : s == ProcessSignal.sigterm
          ? term.stream
          : const Stream<ProcessSignal>.empty(),
    ).run(<String>[]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    int.add(ProcessSignal.sigint);
    if (!Platform.isWindows) term.add(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    child.done.complete(0);
    await run;
    expect(child.killed.first, ProcessSignal.sigint);
    if (!Platform.isWindows) {
      expect(child.killed.last, ProcessSignal.sigkill);
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

  test('a child ended by a signal gives 128 + the signal', () async {
    make('ssr.js');
    await start(<String>[], code: -15);
    expect(exitCode, 143);
    await start(<String>[], code: -2);
    expect(exitCode, 130);
  });

  test('another start error is not called "not found"', () async {
    make('ssr.js');
    await start(
      <String>[],
      fail: ProcessException('bun', <String>[], 'Permission denied', 13),
    );
    expect(exitCode, 1);
  });

  Future<
    (
      FakeProcess,
      Map<ProcessSignal, StreamController<ProcessSignal>>,
      Future<void>,
    )
  >
  running() async {
    make('ssr.js');
    Map<ProcessSignal, StreamController<ProcessSignal>> sources =
        <ProcessSignal, StreamController<ProcessSignal>>{};
    FakeProcess child = FakeProcess(0, wait: true);
    Future<void> done = InertiaStartSsrCommand(
      root: root,
      start: (String exe, List<String> a) async => child,
      signals: (ProcessSignal s) =>
          (sources[s] = StreamController<ProcessSignal>()).stream,
    ).run(<String>[]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return (child, sources, done);
  }

  test('forwards SIGHUP, and a second signal sends SIGKILL', () async {
    (
      FakeProcess,
      Map<ProcessSignal, StreamController<ProcessSignal>>,
      Future<void>,
    )
    r = await running();
    FakeProcess child = r.$1;
    Map<ProcessSignal, StreamController<ProcessSignal>> sources = r.$2;
    Future<void> done = r.$3;
    if (!Platform.isWindows) {
      sources[ProcessSignal.sighup]!.add(ProcessSignal.sighup);
    }
    sources[ProcessSignal.sigint]!.add(ProcessSignal.sigint);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(child.killed, <ProcessSignal>[
      if (!Platform.isWindows) ProcessSignal.sighup else ProcessSignal.sigint,
      ProcessSignal.sigkill,
    ]);
    child.done.complete(0);
    await done;
  });

  test('a signal after the child ended does not kill or throw', () async {
    (
      FakeProcess,
      Map<ProcessSignal, StreamController<ProcessSignal>>,
      Future<void>,
    )
    r = await running();
    FakeProcess child = r.$1;
    Map<ProcessSignal, StreamController<ProcessSignal>> sources = r.$2;
    Future<void> done = r.$3;
    StreamController<ProcessSignal> c = sources[ProcessSignal.sigint]!;
    child.done.complete(0);
    await done;
    expect(c.hasListener, isFalse);
    expect(child.killed, isEmpty);
  });
}
