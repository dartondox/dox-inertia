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
