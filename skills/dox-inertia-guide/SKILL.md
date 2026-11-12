---
name: dox-inertia-guide
description: Use when you build pages with Inertia.js (React, Vue or Svelte) in a Dox (Dart) app using dox_inertia. Covers setup, rendering pages from controllers, shared props, partial reloads, deferred props, form errors, flash data, redirects, Vite and SSR.
---

# dox_inertia guide

`dox_inertia` is the server side of Inertia 3. A Dox controller gives a page name and props. The browser app (React, Vue or Svelte) shows the page. You write no API. The first visit gets full HTML. Later links and forms get JSON. For routes and controllers, see the `dox-core-guide` skill.

Use the Inertia 3 client (`@inertiajs/react`, `@inertiajs/vue3` or `@inertiajs/svelte`, version 3) and Vite.

## Install and set up

1. Add the package: `dart pub add dox_inertia`.

2. Root view `resources/views/app.html`. It is plain HTML, not a `.dox.html` template. `@vite` becomes the script and style tags. `@inertia` becomes the page data and `<div id="app">`.

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>My app</title>
    @vite
  </head>
  <body>
    @inertia
  </body>
</html>
```

3. Config `lib/config/inertia.dart`:

```dart
import 'package:dox_core/dox_core.dart';
import 'package:dox_inertia/dox_inertia.dart';

InertiaConfig inertiaConfig = InertiaConfig(
  entryPoints: <String>['resources/js/app.jsx'],
  // null in production
  devServerUrl: Env.get<String>('APP_ENV') == 'local'
      ? 'http://localhost:5173'
      : null,
  reactRefresh: true,
);
```

4. Provider `lib/providers/inertia_provider.dart`. Dox finds every `DoxProvider`. Run `dart run build_runner build` to update `lib/generated/container.g.dart`.

```dart
import 'package:dox_inertia/dox_inertia.dart';
import '../config/inertia.dart';

class AppInertiaProvider extends InertiaProvider {
  AppInertiaProvider() : super(inertiaConfig);
}
```

5. Middleware, in this order, in `globalMiddleware` of `lib/config/app.dart` (or on one router):

```dart
globalMiddleware: <dynamic>[
  const SessionMiddleware(),
  const CsrfMiddleware(),
  HandleInertiaRequests(), // or const InertiaMiddleware()
],
```

`CsrfMiddleware` sets the `XSRF-TOKEN` cookie. The Inertia client sends it back. You write no code for it.

6. Vite: `vite.config.js` needs `publicDir: false`, `base: command === 'build' ? '/build/' : '/'`, and `build: { manifest: true, outDir: 'public/build', rollupOptions: { input: 'resources/js/app.jsx' } }`. In production Dox reads `public/build/.vite/manifest.json`. Serve `public/build` as `/build/` (a route, or nginx/Caddy).

### InertiaConfig options

| Option | Default |
| --- | --- |
| `rootView` | `resources/views/app.html` |
| `entryPoints` | `['resources/js/app.js']` |
| `publicPath` | `public` |
| `buildDirectory` | `build` |
| `devServerUrl` | `null` |
| `reactRefresh` | `false` |
| `version` | hash of the Vite manifest |
| `encryptHistory` | `false` |
| `ssr` | `null` |

## Recipes

### 1. Render a page

The page name is the file in `resources/js/Pages`, without the extension.

```dart
import 'package:dox_core/dox_core.dart';
import 'package:dox_inertia/dox_inertia.dart';

@Inject()
class UserController {
  Future<DoxResponse> index(DoxRequest req) {
    return inertia(req, 'Users/Index', <String, dynamic>{
      'title': 'Users',
      'users': () => User().query().all(),
    });
  }
}
```

A prop can be a function (it can return a `Future`). It runs only when the prop is sent. Props become JSON: models and objects with `toJson()` work, `DateTime` becomes ISO text. An `int` above 2^53 loses precision, so send it as a string. `Inertia.render(req, name, props)` is the same as `inertia(...)`.

### 2. Shared props (on every page)

```dart
class HandleInertiaRequests extends InertiaMiddleware {
  @override
  Map<String, dynamic> share(DoxRequest req) {
    return <String, dynamic>{
      'appName': 'My app',
      'auth': () => req.auth?.toJson(),
    };
  }
}
```

`share` can be `async`. A page prop with the same name wins. `Inertia.share(req, {...})` shares for one request.

For a constant for the whole app, call `Inertia.shareGlobal(key, value)` once in the provider `setup()`:

```dart
class AppInertiaProvider extends InertiaProvider {
  AppInertiaProvider() : super(inertiaConfig);

  @override
  void setup() {
    super.setup();
    Inertia.shareGlobal('appName', 'Dox');
  }
}
```

A global is shared by all users and cannot be removed. Never put user data in it. Put user data in `share`.

### 3. Partial reloads and deferred props

```dart
return inertia(req, 'Users/Index', <String, dynamic>{
  'stats': Inertia.optional(() => Stats.load()),   // only when asked
  'notices': Inertia.always(notices),              // every request
  'comments': Inertia.defer(() => loadComments()), // loaded after first visit
  'likes': Inertia.defer(() => loadLikes(), group: 'side'),
  'feed': Inertia.defer(() => loadFeed()).merge(), // new items are added
  'posts': Inertia.merge(posts),                   // infinite scroll
});
```

`Inertia.lazy` is the same as `Inertia.optional`. Deferred props with the same `group` load in one request. A partial reload (`router.reload({ only: ['users'] })`) sends only the asked props. Function props that are not sent do not run. Ask for top level props only: `only: ['auth']`, not `only: ['auth.user']`.

### 4. Forms and validation errors

No extra code. When validation fails, Dox flashes the errors and old input to the session and redirects back. The page gets the `errors` prop (`{}` when none).

```dart
Future<DoxResponse> store(DoxRequest req) async {
  await req.validateSchema(
    v.object(<String, Schema<Object?>>{
      'name': v.string().min(2),
      'email': v.string().email(),
    }),
  );
  // ... save
  return redirect('/users');
}
```

```jsx
const { data, setData, post, errors } = useForm({ name: '', email: '' })
```

With `errorBag: 'login'` on the client, errors are under `errors.login.email`. Old input is `req.session.old('email')`. Password fields are not kept.

### 5. Redirects

Use `redirect(url)` or `back(req)`. For an Inertia `PUT`, `PATCH` or `DELETE`, `InertiaMiddleware` changes `302` to `303`. An empty `200` answer to an Inertia request goes back to the same-site `Referer` (else `/`).

To go to an outside site, or a non-Inertia page:

```dart
return Inertia.location(req, 'https://checkout.example.com/pay/1');
```

### 6. Flash data

```dart
Inertia.flash(req, 'message', 'User saved'); // needs SessionMiddleware
return redirect('/users');
```

On the page: `const { flash } = usePage()`, then `flash.message`. It shows once.

### 7. Root view values (title, meta)

```html
<title>{{ title }}</title>
<meta name="csrf-token" content="{{ csrfToken }}">
```

```dart
Inertia.withViewData(req, <String, Object?>{'title': 'Users'});
return inertia(req, 'Users/Index');
```

Values are HTML escaped and are not page props. Use them only in text or quoted attributes, never inside `<script>`. Set every `{{ key }}` the file uses. `{{ csrfToken }}` is filled from the session. A title set this way is for the first load only. Use `<Head>` on the client for later visits.

### 8. Another root view

```dart
Inertia.setRootView(req, 'resources/views/admin.html'); // one request
// or on a router:
List<dynamic> get middleware => <dynamic>[
  const RootViewMiddleware('resources/views/admin.html'),
];
```

Use a fixed path. Never use a value from the request.

### 9. History encryption

`InertiaConfig(encryptHistory: true)` for all pages. Or `Inertia.encryptHistory(req)` (pass `false` to turn it off), or `const EncryptHistoryMiddleware()` on a router. Call `Inertia.clearHistory(req)` on logout. It works on HTTPS and `localhost`.

### 10. Server side rendering (SSR)

1. Write `resources/js/ssr.jsx` with `createServer` from `@inertiajs/react/server` (set `host: '127.0.0.1'`). Hydrate in `app.jsx` with `hydrateRoot` when `el.hasAttribute('data-server-rendered')`.
2. Build and run Node yourself: `vite build`, `vite build --ssr resources/js/ssr.jsx --outDir bootstrap/ssr`, `node bootstrap/ssr/ssr.js`. Dox does not start it.
3. Turn on in config:

```dart
InertiaConfig(
  entryPoints: <String>['resources/js/app.jsx'],
  ssr: Env.get<String>('APP_ENV') == 'production' ? InertiaSsr() : null,
);
```

`InertiaSsr` options: `url` (default `http://127.0.0.1:13714/render`, must be full http or https, a bad url stops the app at boot) and `timeout` (default 2 seconds). If the SSR server is down, slow or bad, the visitor gets the normal client-rendered page and one warning goes to stderr. The root view must have `@inertia` and a `</head>` tag. Remove `<title>` from the root view when pages use `<Head>`.

## Gotchas

- Add `SessionMiddleware` before `CsrfMiddleware` and `InertiaMiddleware`. Errors, flash and CSRF need the session.
- Dev mode is on when `devServerUrl` is set or `public/hot` exists. Set `devServerUrl` from the env so production does not use it.
- The asset version is a hash of the Vite manifest, read once per isolate. Restart the server after `vite build`. A stale client gets `409` and does a full reload.
- The root view is not a `.dox.html` template. Only `@vite`, `@inertia` and `{{ key }}` work in it.
- Do not use the Inertia 1 or 2 client. Use version 3.
- Not supported: once props, scroll props, `prependProps`, `deepMergeProps`, `matchPropsOn`, nested `only` keys with dots.
