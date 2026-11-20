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
      bool running = true;
      bool signalled = false;

      /// In a terminal, Ctrl+C already reaches the child through the process
      /// group, so the child can get SIGINT twice. The forward is needed for
      /// `docker stop`, where only PID 1 gets the signal. A second signal
      /// kills a child that does not stop.
      void forward(ProcessSignal signal) {
        if (!running) return;
        process.kill(signalled ? ProcessSignal.sigkill : signal);
        signalled = true;
      }

      for (ProcessSignal signal in <ProcessSignal>[
        ProcessSignal.sigint,
        if (!Platform.isWindows) ...<ProcessSignal>[
          ProcessSignal.sigterm,
          ProcessSignal.sighup,
        ],
      ]) {
        subscriptions.add((signals ?? _watch)(signal).listen(forward));
      }
      int code = await process.exitCode;
      running = false;

      /// Dart gives -15 for a child ended by SIGTERM. A shell gives 143.
      exitCode = code < 0 ? 128 - code : code;
    } on ProcessException catch (e) {
      bool missing =
          e.errorCode == 2 ||
          e.message.contains('No such file') ||
          e.message.contains('not found');
      if (!missing) {
        print('Could not start $runtime: ${e.message}');
      } else if (node) {
        print(
          'Node was not found. Install Node, or run without --node to use Bun.',
        );
      } else {
        print(
          'Bun was not found. Install Bun from https://bun.sh, or use '
          '--node to run with Node.',
        );
      }
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
