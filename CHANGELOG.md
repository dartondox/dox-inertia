## Unreleased

- Server side rendering (SSR): set `ssr: InertiaSsr()` in `InertiaConfig`. On a first visit, Dox sends the page to the Inertia SSR server (default `http://127.0.0.1:13714/render`). The HTML of the answer goes in place of `@inertia`, and its head tags go right before `</head>`. When the SSR server is down, too slow (`timeout`, default 2 seconds) or gives a bad answer, the normal page is sent, with one warning. SSR is off by default. You run the Node process yourself.
- History encryption: `encryptHistory: true` in `InertiaConfig` turns it on for all pages. `Inertia.encryptHistory(req)` and `Inertia.encryptHistory(req, false)` set it for one page. `EncryptHistoryMiddleware` turns it on for a router.
- `Inertia.clearHistory(req)`: the next Inertia page carries `clearHistory: true`, once. It is kept in the session, so it works before a redirect. With no session, it only works when the same request renders a page.
- New dependency: `http`, for the request to the SSR server.
- Fix: an empty `200` in an Inertia request is sent back to the page it came from. The redirect lost the headers and cookies that the controller set on the empty answer. They are now kept.
- Faster: a prop map with no async values no longer makes an extra list.

## 3.1.0

- `Inertia.render(req, component, props)` does the same as `inertia(...)`. `Inertia.lazy` does the same as `Inertia.optional`.
- `Inertia.shareGlobal(key, value)` shares a prop with every page of the app. It is for app wide constants or functions that do not read a request. Data of one user still goes in `InertiaMiddleware.share`.
- A deferred prop can be merged: `Inertia.defer(fn).merge()` or `Inertia.defer(fn, merge: true)`. When it is sent, it is listed in `mergeProps`.
- An empty `200` answer to an Inertia request now goes back to the page it came from, like Laravel. Only a `Referer` of the same site is used, else it goes to `/`. Requests without `X-Inertia` are not changed.
- A list of plain row maps in a prop is no longer awaited row by row. The props are the same, they are built faster.
- Fix: flash messages are no longer lost after a deploy. When the asset version is old, the session flash data is now kept for the next request before the `409` is sent.
- `InertiaMiddleware` now checks the asset version before the controller runs. A request with an old version gets the `409` at once, and the controller does no work for a page that is never shown.
- An Inertia GET with an old asset version gets the `409` at once, also when the route would redirect. Before, it got a `302` first, and the `409` came on the next page.
- Fix: a function prop inside a map or a list (like `{'auth': {'user': () => ...}}`) is now run too. Before, only top level function props were run, and a nested one failed when the page was turned into JSON.
- Security: when `APP_ENV` is exactly `production`, the Vite `public/hot` file is ignored, with one warning. A hot file left in a deploy no longer makes pages load scripts from its url.
- The root view and the Vite manifest are kept in memory. They are read again only when the file changes.
- A prop that can not be turned into JSON (no `toJson()`) now gives an error that names the prop and its type, on a full page load.

## 3.0.0

- The first stable release.

## 3.0.0-alpha.4

- `InertiaProvider` (was a DoxService): extend it in your app, `shutdown()` is optional.

## 3.0.0-alpha.3

- Needs `dox_core` 3.0.0-alpha.11 (sessions and CSRF).
- Breaking: `InertiaMiddleware` is now an `IDoxNextMiddleware`. It runs code after the controller too. It is not abstract any more: use `const InertiaMiddleware()` when you have no props to share.
- `InertiaMiddleware` turns a `302` into `303` after an Inertia `PUT`, `PATCH` or `DELETE`. So the browser follows the redirect with `GET`.
- Breaking: `Inertia.redirect` is removed. Use `redirect(url)` or `back(req)` from Dox.
- With `SessionMiddleware`, every page gets the `errors` prop: the validation errors of the request before, or `{}`. A failed form post now shows its errors with no extra code. The `X-Inertia-Error-Bag` header puts the errors under the bag name.
- `Inertia.flash(req, key, value)` sends data to the next page in the top level `flash` field of Inertia 3. It is sent once.
- Docs: the setup order `SessionMiddleware`, `CsrfMiddleware`, `InertiaMiddleware`, and the form flow.

## 3.0.0-alpha.2

- Works with the Inertia 3 client (`@inertiajs/react` 3 and others). Before, the app did not start, because the client could not find the first page.
- `@inertia` now writes `<script data-page="app" type="application/json">...</script><div id="app"></div>`, not `<div id="app" data-page="...">`. In the JSON, `<`, `>` and `&` are escaped, so a prop can not end the script tag.
- The Inertia 1 and 2 clients are not supported any more.
- The page has `sharedProps`: the names of the shared props. The client keeps them on an instant visit.
- Docs: `publicDir: false` in the `vite.config.js` sample, so Vite does not copy `public/` into `public/build`.

## 3.0.0-alpha.1

- First version.
- `inertia(req, component, props)` gives the page as JSON to Inertia requests, and as HTML (the root view) to other requests.
- Function props run only when they are sent.
- Partial reloads with `only` and `except`, and `Inertia.optional`, `Inertia.always`, `Inertia.defer` and `Inertia.merge`.
- Shared props with `InertiaMiddleware` or `Inertia.share`.
- Asset version: an old version gets `409` with `X-Inertia-Location`.
- `Inertia.redirect` gives `303` after `PUT`, `PATCH` and `DELETE`. `Inertia.location` goes to an outside url.
- `@vite` in the root view: dev server tags (with React Fast Refresh), or tags from the Vite manifest.
