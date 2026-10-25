import 'dart:convert';
import 'dart:io';

import 'package:dox_core/dox_core.dart';
import 'package:dox_core/testing.dart';
import 'package:dox_inertia/dox_inertia.dart';
import 'package:test/test.dart';

const Map<String, String> inertiaHeaders = <String, String>{
  'X-Inertia': 'true',
  'X-Inertia-Version': '1',
};

int calls = 0;

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
    Route.post('/users', (DoxRequest req) => redirect('/users'));
    Route.put('/users', (DoxRequest req) => redirect('/users'));
    Route.patch('/users', (DoxRequest req) => redirect('/users'));
    Route.delete('/users', (DoxRequest req) => redirect('/users'));
    Route.get('/no-session', (DoxRequest req) {
      return inertia(req, 'Plain');
    });
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
        routers: <Router>[InertiaRouter(), SessionRouter()],
      ),
    );
  });

  setUp(() {
    Inertia.configure(
      InertiaConfig(
        rootView: '${dir.path}/app.html',
        publicPath: '${dir.path}/public',
        devServerUrl: 'http://localhost:5173/',
        version: '1',
      ),
    );
  });

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
  });

  group('inertia request', () {
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
  });
}
