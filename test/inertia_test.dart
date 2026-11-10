import 'dart:convert';
import 'dart:io';

import 'package:dox_core/dox_core.dart';
import 'package:dox_core/testing.dart';
import 'package:dox_inertia/dox_inertia.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const Map<String, String> inertiaHeaders = <String, String>{
  'X-Inertia': 'true',
  'X-Inertia-Version': '1',
};

int calls = 0;

/// a prop value with no toJson()
class NoJson {}

class ShareProps extends InertiaMiddleware {
  @override
  Future<Map<String, dynamic>> share(DoxRequest req) async {
    return <String, dynamic>{'app': 'Dox', 'title': 'shared'};
  }
}

class InertiaRouter extends Router {
  @override
  List<dynamic> get middleware => <dynamic>[ShareProps()];

  @override
  void register() {
    Route.get('/users', (DoxRequest req) {
      return inertia(req, 'Users/Index', <String, dynamic>{
        'title': 'Users',
        'users': () async => <String>['ann', 'bob'],
        'count': () {
          calls++;
          return 2;
        },
        'html': '</div><script>"x" & \'y\'</script> @vite @inertia',
        'stats': Inertia.optional(() => <String, int>{'all': 9}),
        'errors': Inertia.always(<String, String>{}),
        'comments': Inertia.defer(() => <String>['hi']),
        'likes': Inertia.defer(() => 5, group: 'side'),
        'posts': Inertia.merge(<int>[1, 2]),
        'when': DateTime.utc(2026, 1, 2),
      });
    });
    Route.get('/away', (DoxRequest req) {
      return Inertia.location(req, 'https://example.com/pay');
    });
    Route.get('/go', (DoxRequest req) => redirect('/users'));
    Route.post('/users', (DoxRequest req) => redirect('/users'));
    Route.put('/users', (DoxRequest req) => redirect('/users'));
    Route.patch('/users', (DoxRequest req) => redirect('/users'));
    Route.delete('/users', (DoxRequest req) => redirect('/users'));
    Route.get('/bad-prop', (DoxRequest req) {
      return inertia(req, 'Bad', <String, dynamic>{
        'ok': 1,
        'user': () => <String, dynamic>{'pet': NoJson()},
      });
    });
    Route.get('/nested', (DoxRequest req) {
      return inertia(req, 'Nested', <String, dynamic>{
        'auth': <String, dynamic>{
          'user': () => <String, dynamic>{'name': 'ann'},
          'roles': <Object?>[() async => 'admin', 'user'],
        },
      });
    });
    Route.get('/rows', (DoxRequest req) {
      return Inertia.render(req, 'Rows', <String, dynamic>{
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
          <String, dynamic>{'id': 2, 'tag': () async => 'new'},
          <String, dynamic>{
            'id': 3,
            'tags': <String>['a'],
          },
        ],
        'stats': Inertia.lazy(() => 9),
        'feed': Inertia.defer(() => <int>[3, 4]).merge(),
        'more': Inertia.defer(() => <int>[5], merge: true),
      });
    });
    Route.get('/empty', (DoxRequest req) => null);
    Route.put('/empty', (DoxRequest req) => '');
    Route.post('/empty-kept', (DoxRequest req) {
      return response('')
          .header('X-Kept', 'yes')
          .cookie(DoxCookie('kept', '1', encrypt: false));
    });
    Route.get('/counted', (DoxRequest req) {
      calls++;
      return inertia(req, 'Counted');
    });
    Route.get('/no-session', (DoxRequest req) {
      return inertia(req, 'Plain');
    });
    Route.get('/secret', (DoxRequest req) {
      Inertia.encryptHistory(req);
      return inertia(req, 'Secret', <String, dynamic>{
        // slow, so another request runs while this one waits
        'wait': () =>
            Future<int>.delayed(const Duration(milliseconds: 50), () => 1),
      });
    });
    Route.get('/open', (DoxRequest req) {
      Inertia.encryptHistory(req, false);
      return inertia(req, 'Open');
    });
    Route.get('/clear-now', (DoxRequest req) {
      Inertia.clearHistory(req);
      return inertia(req, 'Plain');
    });
  }
}

class EncryptedRouter extends Router {
  @override
  String get prefix => 'e';

  @override
  List<dynamic> get middleware => <dynamic>[const EncryptHistoryMiddleware()];

  @override
  void register() {
    Route.get('/page', (DoxRequest req) => inertia(req, 'Plain'));
  }
}

/// a fake SSR server: counts the calls and keeps the last page it got
class FakeSsr {
  FakeSsr(this.answer);

  final Future<http.Response> Function(http.Request request) answer;
  int calls = 0;
  String? body;

  InertiaSsr get ssr => InertiaSsr(
    timeout: const Duration(milliseconds: 100),
    client: MockClient(handle),
  );

  Future<http.Response> handle(http.Request request) {
    calls++;
    body = request.body;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'http://127.0.0.1:13714/render');
    expect(request.headers['content-type'], contains('application/json'));
    return answer(request);
  }
}

/// a fake HTTP client that counts its calls. With [hang], a request
/// waits until it is aborted, like a real client with a hung server.
class CountingClient extends http.BaseClient {
  CountingClient({this.hang = false});

  final bool hang;
  int sends = 0;
  int aborted = 0;
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    if (hang) {
      await (request as http.Abortable).abortTrigger;
      aborted++;
      throw http.RequestAbortedException(request.url);
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"head":[],"body":"<p>ok</p>"}')),
      200,
    );
  }

  @override
  void close() {
    closes++;
  }
}

class SessionRouter extends Router {
  @override
  String get prefix => 's';

  @override
  List<dynamic> get middleware => <dynamic>[
    const SessionMiddleware(),
    const CsrfMiddleware(),
    ShareProps(),
  ];

  @override
  void register() {
    Route.get('/form', (DoxRequest req) {
      return inertia(req, 'Form', <String, dynamic>{
        'email': req.session.old('email'),
      });
    });
    Future<DoxResponse> save(DoxRequest req) async {
      await req.validateSchema(
        v.object(<String, Schema<Object?>>{'email': v.string().email()}),
      );
      Inertia.flash(req, 'message', 'Saved');
      return redirect('/s/form');
    }

    Route.post('/logout', (DoxRequest req) {
      Inertia.clearHistory(req);
      return redirect('/s/form');
    });
    Route.post('/form', save);
    Route.put('/form', save);
  }
}

/// a client that keeps the cookies of every answer, like a browser
class Browser {
  Browser(this.client);

  final DoxTestClient client;
  final Map<String, String> cookies = <String, String>{};

  Future<TestResponse> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    TestResponse res = await client
        .withCookies(cookies)
        .send(method, path, body: body, headers: headers);
    cookies.addAll(res.cookies);
    return res;
  }

  /// the headers of an Inertia POST, PUT, PATCH or DELETE, with the
  /// token of the `XSRF-TOKEN` cookie, like axios sends it
  Map<String, String> get formHeaders => <String, String>{
    ...inertiaHeaders,
    'X-XSRF-TOKEN': cookies['XSRF-TOKEN']!,
    'Referer': '/s/form',
  };
}

void main() {
  late DoxTestClient client;
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('dox_inertia_');
    await File('${dir.path}/app.html')
        .writeAsString('<html><head>@vite</head><body>@inertia</body></html>');
    client = await DoxTestClient.start(
      AppConfig(
        appKey: '4HyiSrq4N5Nfg6bOadIhbFEI8zbUkpxt',
        routers: <Router>[InertiaRouter(), SessionRouter(), EncryptedRouter()],
      ),
    );
  });

  /// the config of the tests, with [encryptHistory] and [ssr] when given
  void configure({bool encryptHistory = false, InertiaSsr? ssr}) {
    Inertia.configure(
      InertiaConfig(
        rootView: '${dir.path}/app.html',
        publicPath: '${dir.path}/public',
        devServerUrl: 'http://localhost:5173/',
        version: '1',
        encryptHistory: encryptHistory,
        ssr: ssr,
      ),
    );
  }

  setUp(configure);

  tearDownAll(() async {
    await client.close();
    await dir.delete(recursive: true);
  });

  group('first visit', () {
    test('gives HTML with the page in a script tag (Inertia v3)', () async {
      TestResponse res = await client.get('/users?page=2');
      res
          .expectStatus(200)
          .expectHeader('content-type', contains('text/html'))
          .expectHeader('vary', 'X-Inertia');
      RegExpMatch match = RegExp(
        r'<script data-page="app" type="application/json">(.*?)</script>'
        r'<div id="app"></div>',
      ).firstMatch(res.body)!;
      String raw = match[1]!;
      // a prop can not close the script tag or open a comment
      expect(raw, isNot(contains('<')));
      expect(raw, isNot(contains('>')));
      expect(raw, isNot(contains('&')));
      Map<String, dynamic> page = jsonDecode(raw) as Map<String, dynamic>;
      expect(page['component'], 'Users/Index');
      expect(page['url'], '/users?page=2');
      expect(page['version'], '1');
      expect(page['clearHistory'], false);
      expect(page['encryptHistory'], false);
      expect(page['sharedProps'], <String>['app', 'title']);
      Map<String, dynamic> props = page['props'] as Map<String, dynamic>;
      expect(
        props['html'],
        '</div><script>"x" & \'y\'</script> @vite @inertia',
      );
      expect(props['users'], <String>['ann', 'bob']);
      expect(props['when'], '2026-01-02T00:00:00.000Z');
    });

    test('keeps the @vite and @inertia text of a prop', () async {
      TestResponse res = await client.get('/users');
      expect('@vite/client'.allMatches(res.body).length, 1);
      expect(res.body, contains('@vite @inertia'));
    });

    test('reads the root view again only when the file changes', () async {
      File view = File('${dir.path}/app.html');
      String old = await view.readAsString();
      DateTime time = await view.lastModified();
      try {
        expect((await client.get('/users')).body, startsWith('<html>'));
        // same size and time: the cached text is used
        await view.writeAsString(old.replaceFirst('<html>', '<HTML>'));
        await view.setLastModified(time);
        expect((await client.get('/users')).body, startsWith('<html>'));
        // a new time (an edit in dev): the file is read again
        await view.setLastModified(time.add(const Duration(seconds: 5)));
        expect((await client.get('/users')).body, startsWith('<HTML>'));
      } finally {
        await view.writeAsString(old);
      }
    });
  });

  group('inertia request', () {
    test('a prop with no toJson() gives an error that names it', () async {
      Env().env['APP_ENV'] = 'development';
      try {
        TestResponse res = await client.get('/bad-prop');
        res.expectStatus(500);
        expect(
          res.body,
          contains(
            'The Inertia prop "user" can not be turned into JSON: '
            'NoJson has no toJson() method.',
          ),
        );
      } finally {
        Env().env.remove('APP_ENV');
      }
    });

    test('gives the page as JSON', () async {
      TestResponse res = await client.get('/users', headers: inertiaHeaders);
      res
          .expectStatus(200)
          .expectHeader('x-inertia', 'true')
          .expectHeader('vary', 'X-Inertia')
          .expectHeader('content-type', contains('application/json'));
      expect(res.json['component'], 'Users/Index');
      expect(res.json['url'], '/users');
      expect(res.json['version'], '1');
    });

    test('shared props, page props win', () async {
      TestResponse res = await client.get('/users', headers: inertiaHeaders);
      expect(res.json['props']['app'], 'Dox');
      expect(res.json['props']['title'], 'Users');
      expect(res.json['sharedProps'], <String>['app', 'title']);
    });

    test('leaves out optional and deferred props, lists deferred', () async {
      TestResponse res = await client.get('/users', headers: inertiaHeaders);
      Map<String, dynamic> props = res.json['props'] as Map<String, dynamic>;
      expect(props.containsKey('stats'), false);
      expect(props.containsKey('comments'), false);
      expect(props.containsKey('likes'), false);
      expect(props['errors'], <String, String>{});
      expect(res.json['deferredProps'], <String, dynamic>{
        'default': <String>['comments'],
        'side': <String>['likes'],
      });
      expect(res.json['mergeProps'], <String>['posts']);
    });

    test('closures in nested maps and lists are resolved', () async {
      TestResponse res = await client.get('/nested', headers: inertiaHeaders);
      res.expectStatus(200);
      expect(res.json['props']['auth'], <String, dynamic>{
        'user': <String, dynamic>{'name': 'ann'},
        'roles': <String>['admin', 'user'],
      });
    });

    test('old version: 409 before the controller runs', () async {
      calls = 0;
      TestResponse res = await client.get(
        '/counted',
        headers: <String, String>{'X-Inertia': 'true'},
      );
      res.expectStatus(409);
      expect(calls, 0);
    });

    test('old version: a GET route that redirects gets 409, not 302', () async {
      TestResponse res = await client.get(
        '/go',
        headers: <String, String>{
          'X-Inertia': 'true',
          'X-Inertia-Version': 'old',
        },
      );
      res.expectStatus(409).expectHeader('x-inertia-location', endsWith('/go'));
    });

    test('409 when the version is old', () async {
      TestResponse res = await client.get(
        '/users?page=2',
        headers: <String, String>{
          'X-Inertia': 'true',
          'X-Inertia-Version': 'old',
        },
      );
      res
          .expectStatus(409)
          .expectHeader('x-inertia-location', endsWith('/users?page=2'))
          .expectHeader('x-inertia-location', startsWith('http://127.0.0.1:'));
    });
  });

  group('render, lazy, rows and merged defer', () {
    test('a list of row maps keeps its values and order', () async {
      TestResponse res = await client.get('/rows', headers: inertiaHeaders);
      expect(res.json['props'], <String, dynamic>{
        'app': 'Dox',
        'title': 'shared',
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
          <String, dynamic>{'id': 2, 'tag': 'new'},
          <String, dynamic>{
            'id': 3,
            'tags': <String>['a'],
          },
        ],
      });
      expect(res.json['deferredProps'], <String, dynamic>{
        'default': <String>['feed', 'more'],
      });
      expect(res.json.containsKey('mergeProps'), false);
    });

    test('a merged defer prop is in mergeProps when sent', () async {
      TestResponse res = await client.get(
        '/rows',
        headers: <String, String>{
          ...inertiaHeaders,
          'X-Inertia-Partial-Component': 'Rows',
          'X-Inertia-Partial-Data': 'feed,more,stats',
        },
      );
      expect(res.json['props']['feed'], <int>[3, 4]);
      expect(res.json['props']['more'], <int>[5]);
      expect(res.json['props']['stats'], 9);
      expect(res.json['mergeProps'], <String>['feed', 'more']);
    });
  });

  group('partial reload', () {
    Map<String, String> partial(Map<String, String> more) {
      return <String, String>{
        ...inertiaHeaders,
        'X-Inertia-Partial-Component': 'Users/Index',
        ...more,
      };
    }

    test('only sends the asked props, plus always props', () async {
      int before = calls;
      TestResponse res = await client.get(
        '/users',
        headers: partial(<String, String>{
          'X-Inertia-Partial-Data': 'stats, comments',
        }),
      );
      Map<String, dynamic> props = res.json['props'] as Map<String, dynamic>;
      expect(props.keys.toSet(), <String>{'stats', 'comments', 'errors'});
      expect(props['stats'], <String, int>{'all': 9});
      expect(props['comments'], <String>['hi']);
      expect(res.json.containsKey('deferredProps'), false);
      // a lazy prop that is not sent does not run
      expect(calls, before);
    });

    test('except leaves props out', () async {
      TestResponse res = await client.get(
        '/users',
        headers: partial(<String, String>{
          'X-Inertia-Partial-Except': 'users,title,errors',
        }),
      );
      Map<String, dynamic> props = res.json['props'] as Map<String, dynamic>;
      expect(props.containsKey('users'), false);
      expect(props.containsKey('title'), false);
      expect(props['errors'], <String, String>{});
      expect(props['count'], 2);
    });

    test('another component gets all props', () async {
      TestResponse res = await client.get(
        '/users',
        headers: <String, String>{
          ...inertiaHeaders,
          'X-Inertia-Partial-Component': 'Other',
          'X-Inertia-Partial-Data': 'stats',
        },
      );
      Map<String, dynamic> props = res.json['props'] as Map<String, dynamic>;
      expect(props.containsKey('stats'), false);
      expect(props['users'], <String>['ann', 'bob']);
    });

    test('X-Inertia-Reset removes a merge prop from mergeProps', () async {
      TestResponse res = await client.get(
        '/users',
        headers: partial(<String, String>{
          'X-Inertia-Partial-Data': 'posts',
          'X-Inertia-Reset': 'posts',
        }),
      );
      expect(res.json['props']['posts'], <int>[1, 2]);
      expect(res.json.containsKey('mergeProps'), false);
    });
  });

  group('redirects', () {
    test('an empty 200 goes back in an Inertia request', () async {
      (await client.get(
        '/empty',
        headers: <String, String>{...inertiaHeaders, 'Referer': '/users'},
      )).expectStatus(302).expectHeader('location', '/users');
      // after PUT it is a 303, like any other redirect
      (await client.put(
        '/empty',
        headers: <String, String>{...inertiaHeaders, 'Referer': '/users'},
      )).expectStatus(303).expectHeader('location', '/users');
    });

    test('an empty 200 keeps its headers and cookies', () async {
      TestResponse res = await client.post(
        '/empty-kept',
        headers: <String, String>{...inertiaHeaders, 'Referer': '/users'},
      );
      res.expectStatus(302).expectHeader('location', '/users');
      res.expectHeader('x-kept', 'yes');
      expect(res.cookies['kept'], '1');
    });

    test('an empty 200 never goes back to another site', () async {
      for (String referer in <String>[
        'https://evil.com/x',
        '//evil.com',
        '/\\evil.com',
      ]) {
        (await client.get(
          '/empty',
          headers: <String, String>{...inertiaHeaders, 'Referer': referer},
        )).expectStatus(302).expectHeader('location', '/');
      }
    });

    test('an empty 200 is kept without X-Inertia', () async {
      (await client.get('/empty')).expectStatus(200);
    });

    test('303 after PUT, PATCH and DELETE in an Inertia request', () async {
      for (String method in <String>['PUT', 'PATCH', 'DELETE']) {
        TestResponse res = await client.send(
          method,
          '/users',
          headers: inertiaHeaders,
        );
        res.expectStatus(303).expectHeader('location', '/users');
      }
    });

    test('302 after POST, or without X-Inertia', () async {
      (await client.post(
        '/users',
        headers: inertiaHeaders,
      )).expectStatus(302).expectHeader('location', '/users');
      (await client.put('/users')).expectStatus(302);
    });

    test('location gives 409 in an Inertia request', () async {
      (await client.get('/away', headers: inertiaHeaders))
          .expectStatus(409)
          .expectHeader('x-inertia-location', 'https://example.com/pay');
    });

    test('location gives 302 without X-Inertia', () async {
      (await client.get('/away'))
          .expectStatus(302)
          .expectHeader('location', 'https://example.com/pay');
    });
  });

  group('session', () {
    test('no session: no errors prop, no flash', () async {
      TestResponse res = await client.get(
        '/no-session',
        headers: inertiaHeaders,
      );
      expect(res.json['props'], <String, dynamic>{
        'app': 'Dox',
        'title': 'shared',
      });
      expect(res.json.containsKey('flash'), false);
      expect(res.cookies, isEmpty);
    });

    test('errors is {} when there are none', () async {
      TestResponse res = await client.get('/s/form', headers: inertiaHeaders);
      expect(res.json['props']['errors'], <String, dynamic>{});
      expect(res.json.containsKey('flash'), false);
      // errors is not a shared prop: an instant visit must not keep it
      expect(res.json['sharedProps'], <String>['app', 'title']);
    });

    test('a POST with no CSRF token gets 419', () async {
      Browser browser = Browser(client);
      await browser.send('GET', '/s/form', headers: inertiaHeaders);
      TestResponse res = await browser.send(
        'POST',
        '/s/form',
        body: <String, String>{'email': 'a@b.co'},
        headers: inertiaHeaders,
      );
      res.expectStatus(419);
    });

    test('failed POST: redirect back, errors on the next GET', () async {
      Browser browser = Browser(client);
      await browser.send('GET', '/s/form', headers: inertiaHeaders);
      TestResponse post = await browser.send(
        'POST',
        '/s/form',
        body: <String, String>{'email': 'nope'},
        headers: browser.formHeaders,
      );
      post.expectStatus(302).expectHeader('location', '/s/form');

      TestResponse page = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      Map<String, dynamic> props = page.json['props'] as Map<String, dynamic>;
      expect((props['errors'] as Map<String, dynamic>).keys, <String>['email']);
      expect(props['email'], 'nope');

      // flashed errors last one request
      TestResponse again = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      expect(again.json['props']['errors'], <String, dynamic>{});
    });

    test('X-Inertia-Error-Bag puts errors under the bag name', () async {
      Browser browser = Browser(client);
      await browser.send('GET', '/s/form', headers: inertiaHeaders);
      Map<String, String> bag = <String, String>{
        'X-Inertia-Error-Bag': 'login',
      };
      await browser.send(
        'POST',
        '/s/form',
        body: <String, String>{'email': 'nope'},
        headers: <String, String>{...browser.formHeaders, ...bag},
      );
      TestResponse page = await browser.send(
        'GET',
        '/s/form',
        headers: <String, String>{...inertiaHeaders, ...bag},
      );
      Map<String, dynamic> errors =
          page.json['props']['errors'] as Map<String, dynamic>;
      expect(errors.keys, <String>['login']);
      expect((errors['login'] as Map<String, dynamic>).keys, <String>['email']);
    });

    test('failed PUT: 303 back', () async {
      Browser browser = Browser(client);
      await browser.send('GET', '/s/form', headers: inertiaHeaders);
      TestResponse put = await browser.send(
        'PUT',
        '/s/form',
        body: <String, String>{'email': 'nope'},
        headers: browser.formHeaders,
      );
      put.expectStatus(303).expectHeader('location', '/s/form');
    });

    test('Inertia.flash is sent once as page.flash', () async {
      Browser browser = Browser(client);
      await browser.send('GET', '/s/form', headers: inertiaHeaders);
      TestResponse post = await browser.send(
        'POST',
        '/s/form',
        body: <String, String>{'email': 'a@b.co'},
        headers: browser.formHeaders,
      );
      post.expectStatus(302);

      TestResponse page = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      expect(page.json['flash'], <String, dynamic>{'message': 'Saved'});
      expect(page.json['props']['errors'], <String, dynamic>{});

      TestResponse again = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      expect(again.json.containsKey('flash'), false);
    });

    test('old version: the flash is kept for the page after the 409', () async {
      Browser browser = Browser(client);
      await browser.send('GET', '/s/form', headers: inertiaHeaders);
      await browser.send(
        'POST',
        '/s/form',
        body: <String, String>{'email': 'a@b.co'},
        headers: browser.formHeaders,
      );

      TestResponse stale = await browser.send(
        'GET',
        '/s/form',
        headers: <String, String>{'X-Inertia': 'true'},
      );
      stale.expectStatus(409);

      TestResponse page = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      expect(page.json['flash'], <String, dynamic>{'message': 'Saved'});
    });
  });

  group('history encryption', () {
    test('default config: the HTML is the same as with no feature', () async {
      TestResponse res = await client.get('/no-session');
      expect(
        res.body,
        '<html><head>${await Vite(Inertia.config).tags()}</head><body>'
        '<script data-page="app" type="application/json">'
        '{"component":"Plain","url":"/no-session","version":"1",'
        '"clearHistory":false,"encryptHistory":false,'
        '"props":{"app":"Dox","title":"shared"},'
        '"sharedProps":["app","title"]}</script>'
        '<div id="app"></div></body></html>',
      );
    });

    test('encryptHistory is false by default', () async {
      TestResponse res = await client.get('/users', headers: inertiaHeaders);
      expect(res.json['encryptHistory'], false);
      expect(res.json['clearHistory'], false);
    });

    test('the config turns it on, one request turns it off', () async {
      configure(encryptHistory: true);
      TestResponse on = await client.get('/users', headers: inertiaHeaders);
      expect(on.json['encryptHistory'], true);
      TestResponse off = await client.get('/open', headers: inertiaHeaders);
      expect(off.json['encryptHistory'], false);
    });

    test('one request turns it on', () async {
      TestResponse res = await client.get('/secret', headers: inertiaHeaders);
      expect(res.json['encryptHistory'], true);
    });

    test('EncryptHistoryMiddleware turns it on for a router', () async {
      TestResponse res = await client.get('/e/page', headers: inertiaHeaders);
      expect(res.json['encryptHistory'], true);
    });

    test(
      'it does not leak into a request that runs at the same time',
      () async {
        List<TestResponse> all = await Future.wait(<Future<TestResponse>>[
          client.get('/secret', headers: inertiaHeaders),
          client.get('/users', headers: inertiaHeaders),
          client.get('/clear-now', headers: inertiaHeaders),
        ]);
        expect(all[0].json['encryptHistory'], true);
        expect(all[0].json['clearHistory'], false);
        expect(all[1].json['encryptHistory'], false);
        expect(all[1].json['clearHistory'], false);
        expect(all[2].json['encryptHistory'], false);
        expect(all[2].json['clearHistory'], true);
        // and not into a later request
        TestResponse later = await client.get(
          '/users',
          headers: inertiaHeaders,
        );
        expect(later.json['encryptHistory'], false);
        expect(later.json['clearHistory'], false);
      },
    );

    test('clearHistory lives through a redirect and is sent once', () async {
      Browser browser = Browser(client);
      TestResponse first = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      expect(first.json['clearHistory'], false);
      TestResponse post = await browser.send(
        'POST',
        '/s/logout',
        headers: browser.formHeaders,
      );
      post.expectStatus(302).expectHeader('location', '/s/form');

      TestResponse page = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      expect(page.json['clearHistory'], true);
      TestResponse again = await browser.send(
        'GET',
        '/s/form',
        headers: inertiaHeaders,
      );
      expect(again.json['clearHistory'], false);
    });

    test('clearHistory is kept when the next request gets a 409', () async {
      Browser browser = Browser(client);
      await browser.send('GET', '/s/form', headers: inertiaHeaders);
      await browser.send('POST', '/s/logout', headers: browser.formHeaders);
      TestResponse stale = await browser.send(
        'GET',
        '/s/form',
        headers: <String, String>{'X-Inertia': 'true'},
      );
      stale.expectStatus(409);
      // the full page load after the 409
      TestResponse page = await browser.send('GET', '/s/form');
      expect(page.body, contains('"clearHistory":true'));
    });

    test('no session: clearHistory is for this response only', () async {
      TestResponse res = await client.get(
        '/clear-now',
        headers: inertiaHeaders,
      );
      expect(res.json['clearHistory'], true);
      expect(res.cookies, isEmpty);
      TestResponse next = await client.get(
        '/no-session',
        headers: inertiaHeaders,
      );
      expect(next.json['clearHistory'], false);
    });
  });

  group('ssr', () {
    const String plain = '<div id="app"></div>';
    const String rendered =
        '<script data-page="app" type="application/json">{}</script>'
        '<div data-server-rendered="true" id="app"><h1>\u00e9 @vite</h1></div>';

    Future<http.Response> ok(http.Request request) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'head': <String>['<title>Users</title>', '<meta name="a">'],
            'body': rendered,
          }),
        ),
        200,
      );
    }

    test('puts the head before </head> and the body at @inertia', () async {
      FakeSsr fake = FakeSsr(ok);
      configure(ssr: fake.ssr);
      TestResponse res = await client.get('/no-session');
      res.expectStatus(200).expectHeader('vary', 'X-Inertia');
      expect(
        res.body,
        '<html><head>${await Vite(Inertia.config).tags()}'
        '<title>Users</title>\n<meta name="a">\n</head>'
        '<body>$rendered</body></html>',
      );
      expect(fake.calls, 1);
      // the SSR server gets the page object as JSON
      Map<String, dynamic> page =
          jsonDecode(fake.body!) as Map<String, dynamic>;
      expect(page['component'], 'Plain');
      expect(page['url'], '/no-session');
      expect(page['props'], <String, dynamic>{'app': 'Dox', 'title': 'shared'});
      expect(page['encryptHistory'], false);
    });

    test('an Inertia request does not call the SSR server', () async {
      FakeSsr fake = FakeSsr(ok);
      configure(ssr: fake.ssr);
      TestResponse res = await client.get('/users', headers: inertiaHeaders);
      expect(res.json['component'], 'Users/Index');
      expect(fake.calls, 0);
    });

    test('a root view with no </head> gets the body only', () async {
      File view = File('${dir.path}/app.html');
      String old = await view.readAsString();
      try {
        await view.writeAsString('<main>@inertia</main>');
        configure(ssr: FakeSsr(ok).ssr);
        TestResponse res = await client.get('/no-session');
        expect(res.body, '<main>$rendered</main>');
      } finally {
        await view.writeAsString(old);
      }
    });

    Map<String, Future<http.Response> Function(http.Request)> failures =
        <String, Future<http.Response> Function(http.Request)>{
          'server down': (http.Request request) async {
            throw const SocketException('Connection refused');
          },
          'timeout': (http.Request request) {
            return Future<http.Response>.delayed(
              const Duration(seconds: 1),
              () => http.Response('{"head":[],"body":"<p>late</p>"}', 200),
            );
          },
          'status 500': (http.Request request) async {
            return http.Response('{"head":[],"body":"<p>bad</p>"}', 500);
          },
          'bad JSON': (http.Request request) async {
            return http.Response('<html>oops', 200);
          },
          'JSON with no body': (http.Request request) async {
            return http.Response('{"head":["<title>x</title>"]}', 200);
          },
          'JSON that is not a map': (http.Request request) async {
            return http.Response('[1]', 200);
          },
        };
    for (MapEntry<String, Future<http.Response> Function(http.Request)> failure
        in failures.entries) {
      test('${failure.key}: the normal page is sent', () async {
        String normal = (await client.get('/no-session')).body;
        expect(normal, contains(plain));
        FakeSsr fake = FakeSsr(failure.value);
        configure(ssr: fake.ssr);
        TestResponse res = await client.get('/no-session');
        res.expectStatus(200);
        expect(res.body, normal);
        expect(fake.calls, 1);
      });
    }

    test('a partial reload does not call the SSR server', () async {
      FakeSsr fake = FakeSsr(ok);
      configure(ssr: fake.ssr);
      TestResponse res = await client.get(
        '/users',
        headers: <String, String>{
          ...inertiaHeaders,
          'X-Inertia-Partial-Component': 'Users/Index',
          'X-Inertia-Partial-Data': 'stats',
        },
      );
      expect(res.json['props']['stats'], <String, int>{'all': 9});
      expect(fake.calls, 0);
    });

    test('the head goes at the root </head>, not at one in the body', () async {
      File view = File('${dir.path}/app.html');
      String old = await view.readAsString();
      Future<http.Response> tricky(http.Request request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'head': <String>['<title>@inertia @vite </head></title>'],
            'body': '<div id="app">a </head> b @vite</div>',
          }),
          200,
        );
      }

      try {
        // no </head> in the root view: the one in the body is not used
        await view.writeAsString('<main>@inertia</main>');
        configure(ssr: FakeSsr(tricky).ssr);
        expect(
          (await client.get('/no-session')).body,
          '<main><div id="app">a </head> b @vite</div></main>',
        );
        // any case, and the text of the head is not read as a mark
        await view.writeAsString('<HEAD>@vite</HEAD><body>@inertia</body>');
        configure(ssr: FakeSsr(tricky).ssr);
        expect(
          (await client.get('/no-session')).body,
          '<HEAD>${await Vite(Inertia.config).tags()}'
          '<title>@inertia @vite </head></title>\n</HEAD>'
          '<body><div id="app">a </head> b @vite</div></body>',
        );
      } finally {
        await view.writeAsString(old);
      }
    });

    test('the request is aborted at the timeout', () async {
      CountingClient hung = CountingClient(hang: true);
      StringBuffer log = StringBuffer();
      InertiaSsr ssr = InertiaSsr(
        timeout: const Duration(milliseconds: 50),
        client: hung,
        log: log,
      );
      expect(await ssr.render('{}'), isNull);
      expect(hung.sends, 1);
      expect(hung.aborted, 1);
      expect(log.toString(), contains('no answer in 50 ms'));
    });

    test('a url with no scheme or host fails when it is made', () {
      for (String url in <String>[
        '127.0.0.1:13714/render',
        '/render',
        'ftp://127.0.0.1/render',
        'http:///render',
        '',
      ]) {
        expect(() => InertiaSsr(url: url), throwsArgumentError, reason: url);
      }
      expect(InertiaSsr(url: 'https://ssr.example.com/render').url, isNotEmpty);
    });

    test('one warning, then quiet until a render works again', () async {
      bool down = true;
      StringBuffer log = StringBuffer();
      InertiaSsr ssr = InertiaSsr(
        log: log,
        client: MockClient((http.Request request) async {
          if (down) throw const SocketException('Connection refused');
          return ok(request);
        }),
      );
      int warnings() => 'dox_inertia: SSR failed'.allMatches('$log').length;

      expect(await ssr.render('{}'), isNull);
      expect(await ssr.render('{}'), isNull);
      expect(await ssr.render('{}'), isNull);
      expect(warnings(), 1);
      down = false;
      expect((await ssr.render('{}'))!.body, rendered);
      expect(warnings(), 1);
      down = true;
      expect(await ssr.render('{}'), isNull);
      expect(await ssr.render('{}'), isNull);
      expect(warnings(), 2);
    });

    test('one client for all renders, shutdown closes it', () async {
      CountingClient counting = CountingClient();
      InertiaSsr ssr = InertiaSsr(client: counting);
      InertiaProvider provider = InertiaProvider(InertiaConfig(ssr: ssr));
      expect((await ssr.render('{}'))!.body, '<p>ok</p>');
      expect((await ssr.render('{}'))!.body, '<p>ok</p>');
      expect(counting.sends, 2);
      expect(counting.closes, 0);
      provider.shutdown();
      expect(counting.closes, 1);
      // an app with no SSR has nothing to close
      InertiaProvider(const InertiaConfig()).shutdown();
    });

    test('it works again after a failure', () async {
      bool down = true;
      FakeSsr fake = FakeSsr((http.Request request) async {
        if (down) throw const SocketException('Connection refused');
        return ok(request);
      });
      configure(ssr: fake.ssr);
      expect((await client.get('/no-session')).body, contains(plain));
      down = false;
      expect((await client.get('/no-session')).body, contains(rendered));
    });
  });

  // ponytail: last, because a global share stays for the whole isolate
  group('global share', () {
    test('goes to every page, the request share wins', () async {
      Inertia.shareGlobal('version', 'v1');
      Inertia.shareGlobal('title', 'global');
      Inertia.shareGlobal('year', () => 2026);
      TestResponse res = await client.get(
        '/no-session',
        headers: inertiaHeaders,
      );
      expect(res.json['props'], <String, dynamic>{
        'version': 'v1',
        'title': 'shared',
        'year': 2026,
        'app': 'Dox',
      });
      expect(res.json['sharedProps'], <String>[
        'version',
        'title',
        'year',
        'app',
      ]);
    });
  });
}
