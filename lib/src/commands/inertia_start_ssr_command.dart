import 'dart:io';

import 'package:dox_annotation/command.dart';

/// starts a process in the foreground. Tests pass a fake one.
typedef SsrProcessStarter = Future<Process> Function(
  String executable,
  List<String> args,
);

/// `dox inertia:start-ssr`. It runs the SSR server that `bun run build:ssr`
/// made, with Bun. `--node` runs it with Node. It stays in the foreground,
/// so run it under Docker, pm2 or systemd like any other process.
class InertiaStartSsrCommand extends Command {
  /// [root] is the app folder (the current folder by default). [start]
  /// starts the process, tests pass a fake one.
  InertiaStartSsrCommand({this.root, this.start});

  final Directory? root;
  final SsrProcessStarter? start;

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
    String? file;
    for (String name in <String>['ssr.js', 'ssr.mjs']) {
      if (File('$base/bootstrap/ssr/$name').existsSync()) {
        file = 'bootstrap/ssr/$name';
        break;
      }
    }
    if (file == null) {
      print(
        'bootstrap/ssr/ssr.js was not found. Build it first with '
        '`bun run build:ssr` (or `npm run build:ssr` with Node).',
      );
      exitCode = 1;
      return;
    }
    try {
      Process process = await (start ?? _start(base))(runtime, <String>[file]);
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
    }
  }

  SsrProcessStarter _start(String base) {
    return (String executable, List<String> args) => Process.start(
      executable,
      args,
      workingDirectory: base,
      mode: ProcessStartMode.inheritStdio,
    );
  }
}
