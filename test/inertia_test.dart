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
    Route.post('/users', (DoxRequest req) {
      return Inertia.redirect(req, '/users');
    });
    Route.put('/users', (DoxRequest req) {
      return Inertia.redirect(req, '/users');
    });
    Route.patch('/users', (DoxRequest req) {
      return Inertia.redirect(req, '/users');
    });
    Route.delete('/users', (DoxRequest req) {
      return Inertia.redirect(req, '/users');
    });
  }
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
        routers: <Router>[InertiaRouter()],
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
}
