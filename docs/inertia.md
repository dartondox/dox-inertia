# Inertia

Inertia lets you build a single page app with React, Vue or Svelte, and keep routes and controllers in Dox.

You do not write an API. A controller gives a page name and its props. Inertia shows the page in the browser.
The first visit gets a full HTML page. After that, links and forms get only JSON, and the page changes without a reload.

The `dox_inertia` package is the server side of Inertia (protocol v2). Use it with the Inertia client for your front-end (`@inertiajs/react`, `@inertiajs/vue3` or `@inertiajs/svelte`) and Vite.

## Install

```bash
dart pub add dox_inertia
```

## Set up

### 1. Root view

The root view is the HTML page of the first visit. Dox puts the script and style tags in place of `@vite`, and the page in place of `@inertia`. It is plain HTML, with no template engine.

```html title="resources/views/app.html"
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

`@inertia` becomes `<div id="app" data-page="..."></div>`. The page data is HTML-escaped.

### 2. Config

```dart title="lib/config/inertia.dart"
import 'package:dox_inertia/dox_inertia.dart';

InertiaConfig inertiaConfig = InertiaConfig(
  /// the Vite entry files
  entryPoints: <String>['resources/js/app.jsx'],

  /// load the scripts from the Vite dev server. null in production.
  devServerUrl: 'http://localhost:5173',

  /// add the React Fast Refresh code in dev mode
  reactRefresh: true,
);
```

| Option | Default | What it does |
| --- | --- | --- |
| `rootView` | `resources/views/app.html` | the HTML page of the first visit |
| `entryPoints` | `['resources/js/app.js']` | the Vite entry files |
| `publicPath` | `public` | the folder of public files |
| `buildDirectory` | `build` | the folder in `publicPath` where `vite build` writes its files |
| `devServerUrl` | `null` | the url of the Vite dev server, see [Vite](#vite) |
| `reactRefresh` | `false` | add the React Fast Refresh code in dev mode |
| `version` | hash of the manifest | the asset version, see [Asset version](#asset-version) |

Paths are from the project root, where the app runs.

### 3. Service

The service sets up Inertia in every isolate. Put it in `lib/` so the generated container finds it.

```dart title="lib/services/inertia_service.dart"
import 'package:dox_inertia/dox_inertia.dart';

import '../config/inertia.dart';

class AppInertiaService extends InertiaService {
  AppInertiaService() : super(inertiaConfig);
}
```

With no service, Dox uses the defaults of `InertiaConfig`.

### 4. Vite

```js title="vite.config.js"
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ command }) => ({
  plugins: [react()],
  // the built files are served from /build/
  base: command === 'build' ? '/build/' : '/',
  server: { origin: 'http://localhost:5173' },
  build: {
    manifest: true,
    outDir: 'public/build',
    rollupOptions: { input: 'resources/js/app.jsx' },
  },
}))
```

```jsx title="resources/js/app.jsx"
import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true })
    return pages[`./Pages/${name}.jsx`]
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
})
```

### 5. Serve the built files

In production the browser loads `/build/assets/...`. Add a route for them, or let your proxy (nginx, Caddy) serve `public/build`.

```dart title="lib/routes/web.dart"
Route.get('/build/{path*}', (String path) {
  if (path.contains('..')) throw NotFoundHttpException();
  // the file names have a hash, so the browser can keep them for a year
  return response(File('public/build/$path')).cache(const Duration(days: 365));
});
```

## Render a page

Give the request, the page name and the props. The page name is the file in `resources/js/Pages`, without the extension.

```dart title="lib/app/http/controllers/user.controller.dart"
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

- A normal request gets the root view as HTML.
- An Inertia request (`X-Inertia: true`) gets the page as JSON, with `X-Inertia: true` and `Vary: X-Inertia`.

A prop can be a function, like `users` above. It runs only when the prop is sent. It can give a `Future`.
Props become JSON. A model or any object with `toJson()` works. A `DateTime` becomes ISO text.

## Shared props

Shared props go to every page, like the signed in user or the app name. Extend `InertiaMiddleware` and add it to a router or to `globalMiddleware`.

```dart title="lib/app/http/middleware/handle_inertia_requests.dart"
import 'package:dox_core/dox_core.dart';
import 'package:dox_inertia/dox_inertia.dart';

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

```dart title="lib/routes/web.dart"
class WebRouter extends Router {
  @override
  List<dynamic> get middleware => <dynamic>[HandleInertiaRequests()];

  @override
  void register() {
    Route.get('/users', (UserController c) => c.index);
  }
}
```

A page prop with the same name wins over a shared prop. `share` can be `async`.
You can also share from any middleware or controller with `Inertia.share(req, {...})`.

## Partial reloads

The client can ask for some props only: `router.reload({ only: ['users'] })`. Dox reads the headers and sends only those props. Function props that are not sent do not run.

Four helpers change when a prop is sent:

```dart
return inertia(req, 'Users/Index', <String, dynamic>{
  /// only when a partial reload asks for it
  'stats': Inertia.optional(() => Stats.load()),

  /// on every request, also on a partial reload that does not ask for it
  'errors': Inertia.always(<String, String>{}),

  /// not on the first visit: the page loads it right after
  'comments': Inertia.defer(() => Comment().query().all()),
  'likes': Inertia.defer(() => Like().query().count(), group: 'side'),

  /// the page adds the new items to the old ones (infinite scroll)
  'posts': Inertia.merge(posts),
});
```

| Helper | First visit | Partial reload |
| --- | --- | --- |
| plain value or function | sent | sent when asked |
| `Inertia.optional` | not sent | sent when asked |
| `Inertia.always` | sent | always sent |
| `Inertia.defer` | not sent, listed in `deferredProps` | sent when asked |
| `Inertia.merge` | sent, listed in `mergeProps` | sent when asked |

Deferred props of the same `group` load in one request. The default group is `default`.

## Redirects

After a form, redirect with `Inertia.redirect`. After `PUT`, `PATCH` or `DELETE`, an Inertia request gets `303`, so the browser follows it with `GET`. Other requests get `302`.

```dart
Future<DoxResponse> update(DoxRequest req, int id) async {
  // ... save the user
  return Inertia.redirect(req, '/users');
}
```

To go to an outside site, or any page that is not an Inertia page, use `Inertia.location`. An Inertia request gets `409` with `X-Inertia-Location`, and the client loads the url with a full page load. Other requests get `302`.

```dart
return Inertia.location(req, 'https://checkout.example.com/pay/1');
```

## Vite

In dev mode, `@vite` loads `@vite/client` and the entry files from the Vite dev server. With `reactRefresh: true` it adds the React Fast Refresh code first.

Dox is in dev mode when:

- `devServerUrl` is set, or
- the file `public/hot` exists. Its text is the dev server url. Some Vite plugins write this file while `vite` runs.

In production (no dev server), Dox reads `public/build/.vite/manifest.json`. `@vite` gives a `<link>` tag for the css of each entry and of the chunks it imports, and a `<script type="module">` tag for each entry.

Set `devServerUrl` from the env, so production does not use it:

```dart title="lib/config/inertia.dart"
InertiaConfig inertiaConfig = InertiaConfig(
  entryPoints: <String>['resources/js/app.jsx'],
  devServerUrl: Env.get<String>('APP_ENV') == 'local'
      ? 'http://localhost:5173'
      : null,
  reactRefresh: true,
);
```

## Asset version

Each page has a version. When you deploy new assets, the version changes. A browser with the old version that makes an Inertia `GET` request gets `409` with `X-Inertia-Location`. The client then loads the whole page again, with the new assets.

The default version is a hash of the Vite manifest. Dox reads it once per isolate, so restart the server after `vite build` (a deploy does this). To set your own, use `version` in the config, eg. the git commit.

## Not included

- Server side rendering (SSR).
- Validation errors and flash messages through the session. Dox has no session. To show errors, catch the `ValidationException` and render the page again with an `errors` prop.
- History encryption. `encryptHistory` and `clearHistory` are always `false`.
