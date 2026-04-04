# PWA Web Deploy

Use this flow for the Flutter web app, including admin routes.

## Build

```bash
flutter build web --release
```

This project now ships:

- path-based web routing via `usePathUrlStrategy()`
- a custom bootstrap that registers `custom-sw.js`
- a wrapper service worker that preserves Flutter asset caching and adds deep-link offline fallback

## Firebase Hosting

The checked-in [`firebase.json`](../firebase.json) remains the static legal-site config.

Use [`firebase.webapp.json`](../firebase.webapp.json) for the Flutter web app:

```bash
firebase deploy --config firebase.webapp.json --only hosting
```

## Required Hosting Behavior

- serve `build/web`
- rewrite all app routes to `/index.html`
- serve `custom-sw.js` and `flutter_service_worker.js` with `no-cache`
- keep immutable cache headers for hashed assets

Without SPA rewrites, routes like `/admin`, `/profile`, and `/momo` will fail on hard refresh.
