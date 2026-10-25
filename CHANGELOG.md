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
