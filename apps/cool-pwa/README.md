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

Use the repo-level [`firebase.pwa.json`](/Volumes/PRO-G40/COOL/firebase.pwa.json) config to deploy this app as a dedicated hosting target.
