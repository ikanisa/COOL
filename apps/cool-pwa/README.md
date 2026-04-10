# COOL PWA

Standalone Progressive Web App for COOL, added alongside the maintained Flutter client.

This app is intentionally separate from the Flutter codebase:

- Flutter mobile remains the primary native client.
- `apps/cool-pwa` is the world-class web/PWA surface aligned to the April 2026 report.
- The PWA ships as static clean-URL pages with a shared app shell, custom service worker, offline queueing, contextual install UX, web-notification flows, and browser-audit scripts.

## Local Run

```bash
cd apps/cool-pwa
npm install
npm run serve
```

Open `http://127.0.0.1:4173`.

## Verification

```bash
npm test
npm run audit:lighthouse
```

## Deploy

This app is prepared for the existing Cloudflare Pages project `cool`.

```bash
cd apps/cool-pwa
npx wrangler pages deploy
```

Production domains:

- `https://cool.ikanisa.com/` serves the landing page.
- `https://acool.ikanisa.com/` uses the same Pages project and rewrites `/` to `/admin/` for the admin PWA entry.
- `https://cool.ikanisa.com/admin/` remains available for direct QA on the shared project.

Cloudflare-specific files live alongside the app:

- `wrangler.toml`
- `_headers`
- `functions/index.js`
- `landing/index.html`
- `landing-assets/*`
