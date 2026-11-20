import 'dart:async';
import 'dart:io';

import 'package:dox_annotation/command.dart';

/// starts a process in the foreground. Tests pass a fake one.
typedef SsrProcessStarter = Future<Process> Function(
  String executable,
  List<String> args,
);

/// gives the stream of one signal. Tests pass a fake one.
typedef SsrSignalSource = Stream<ProcessSignal> Function(ProcessSignal signal);

/// `dox inertia:start-ssr`. It runs the SSR server that `bun run build:ssr`
/// made, with Bun. `--node` runs it with Node. It stays in the foreground,
/// so run it under Docker, pm2 or systemd like any other process. A stop
/// signal (SIGINT or SIGTERM) is sent on to the SSR process, so it does not
/// stay alive and keep the port.
class InertiaStartSsrCommand extends Command {
  /// [root] is the app folder (the current folder by default). [start]
  /// starts the process and [signals] gives the stop signals. Tests pass
  /// fake ones.
  InertiaStartSsrCommand({this.root, this.start, this.signals});

  final Directory? root;
  final SsrProcessStarter? start;
  final SsrSignalSource? signals;

  @override
  String get name => 'inertia:start-ssr';

  @override
  String get description => 'Start the Inertia SSR server (Bun, or Node)';

  @override
  String get usage => 'inertia:start-ssr [--node]';

  @override
  Future<void> run(List<String> args) async {
    if (args.any((String a) => a != '--node')) {
      print('Unknown option. inertia:start-ssr only has --node.');
      exitCode = 1;
      return;
    }
    bool node = args.contains('--node');
    String runtime = node ? 'node' : 'bun';
    String base = (root ?? Directory.current).absolute.path;
    String? file = _builtFile(base);
    if (file == null) {
      print(
        'bootstrap/ssr/ssr.js or bootstrap/ssr/ssr.mjs was not found. '
        'Build it first with `bun run build:ssr` (or `npm run build:ssr` '
        'with Node).',
      );
      exitCode = 1;
      return;
    }
    print('Starting $runtime $file');
    List<StreamSubscription<ProcessSignal>> subscriptions =
        <StreamSubscription<ProcessSignal>>[];
    try {
      Process process = await (start ?? _start(base))(runtime, <String>[file]);
      for (ProcessSignal signal in <ProcessSignal>[
        ProcessSignal.sigint,
        if (!Platform.isWindows) ProcessSignal.sigterm,
      ]) {
        subscriptions.add(
          (signals ?? _watch)(signal).listen((ProcessSignal s) {
            process.kill(s);
          }),
        );
      }
      exitCode = await process.exitCode;
    } on ProcessException {
      print(
        node
            ? 'Node was not found. Install Node, or run without --node '
                  'to use Bun.'
            : 'Bun was not found. Install Bun from https://bun.sh, or use '
                  '--node to run with Node.',
      );
      exitCode = 1;
    } finally {
      for (StreamSubscription<ProcessSignal> sub in subscriptions) {
        await sub.cancel();
      }
    }
  }

  /// the built file that changed last, so an old one does not win
  String? _builtFile(String base) {
    File? newest;
    for (String name in <String>['ssr.js', 'ssr.mjs']) {
      File file = File('$base/bootstrap/ssr/$name');
      if (!file.existsSync()) continue;
      if (newest == null ||
          file.lastModifiedSync().isAfter(newest.lastModifiedSync())) {
        newest = file;
      }
    }
    return newest == null
        ? null
        : 'bootstrap/ssr/${newest.uri.pathSegments.last}';
  }

  Stream<ProcessSignal> _watch(ProcessSignal signal) => signal.watch();

  SsrProcessStarter _start(String base) {
    return (String executable, List<String> args) => Process.start(
      executable,
      args,
      workingDirectory: base,
      mode: ProcessStartMode.inheritStdio,
    );
  }
}
