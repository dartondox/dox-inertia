## 3.0.0-alpha.1

- First version.
- `inertia(req, component, props)` gives the page as JSON to Inertia requests, and as HTML (the root view) to other requests.
- Function props run only when they are sent.
- Partial reloads with `only` and `except`, and `Inertia.optional`, `Inertia.always`, `Inertia.defer` and `Inertia.merge`.
- Shared props with `InertiaMiddleware` or `Inertia.share`.
- Asset version: an old version gets `409` with `X-Inertia-Location`.
- `Inertia.redirect` gives `303` after `PUT`, `PATCH` and `DELETE`. `Inertia.location` goes to an outside url.
- `@vite` in the root view: dev server tags (with React Fast Refresh), or tags from the Vite manifest.
