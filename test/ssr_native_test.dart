import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dox_inertia/dox_inertia.dart';
import 'package:test/test.dart';

/// SSR with its own client (the native client of dox_http_client) and a
/// real SSR server on a socket. The other tests pass a fake client.
void main() {
  late HttpServer server;
  List<String> pages = <String>[];
  Set<int> connections = <int>{};

  setUp(() async {
    pages.clear();
    connections.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      connections.add(request.connectionInfo!.remotePort);
      pages.add(await utf8.decoder.bind(request).join());
      if (request.uri.path != '/render') {
        request.response.statusCode = 500;
        return request.response.close();
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object>{
          'head': <String>['<title>é</title>'],
          'body': '<h1>é ${pages.length}</h1>',
        }),
      );
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  String url([String path = '/render']) {
    return 'http://127.0.0.1:${server.port}$path';
  }

  test('render posts the page and reads the answer', () async {
    InertiaSsr ssr = InertiaSsr(url: url(), log: StringBuffer());
    addTearDown(ssr.close);
    SsrPage? page = await ssr.render('{"component":"é"}');
    expect(page!.head, '<title>é</title>');
    expect(page.body, '<h1>é 1</h1>');
    expect(pages, <String>['{"component":"é"}']);
    // the next renders use the same connection
    expect((await ssr.render('{}'))!.body, '<h1>é 2</h1>');
    expect((await ssr.render('{}'))!.body, '<h1>é 3</h1>');
    expect(connections, hasLength(1));
  });

  test('an error status and a server that is down give null', () async {
    StringBuffer log = StringBuffer();
    InertiaSsr ssr = InertiaSsr(url: url('/other'), log: log);
    addTearDown(ssr.close);
    expect(await ssr.render('{}'), isNull);
    expect(log.toString(), contains('status 500'));

    ServerSocket socket = await ServerSocket.bind('127.0.0.1', 0);
    int port = socket.port;
    await socket.close();
    InertiaSsr down = InertiaSsr(
      url: 'http://127.0.0.1:$port/render',
      log: StringBuffer(),
    );
    addTearDown(down.close);
    expect(await down.render('{}'), isNull);
  });

  test('a server that hangs: null at the timeout, the socket closes', () async {
    // accepts, reads the page, never answers
    ServerSocket hung = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(hung.close);
    Completer<void> closed = Completer<void>();
    hung.listen((Socket socket) {
      socket.listen((List<int> _) {}, onDone: closed.complete);
    });
    StringBuffer log = StringBuffer();
    InertiaSsr ssr = InertiaSsr(
      url: 'http://127.0.0.1:${hung.port}/render',
      timeout: const Duration(milliseconds: 100),
      log: log,
    );
    addTearDown(ssr.close);
    Stopwatch watch = Stopwatch()..start();
    expect(await ssr.render('{}'), isNull);
    expect(watch.elapsedMilliseconds, lessThan(1500));
    expect(log.toString(), contains('no answer in 100 ms'));
    // so a hung SSR server does not keep one open socket per visit
    await closed.future.timeout(const Duration(seconds: 5));
  });
}
