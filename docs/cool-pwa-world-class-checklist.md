# COOL PWA World-Class Checklist Mapping

This document maps the April 2026 `WorldClass_PWA_Report.docx.md` guidance to the standalone PWA added in `apps/cool-pwa/`.

## Scope

- Flutter app remains the maintained primary client.
- The separate PWA lives in `apps/cool-pwa/`.
- Static hosting and security enforcement for the PWA live in `firebase.pwa.json`.
- CI and verification live in `.github/workflows/cool-pwa-ci.yml` and `apps/cool-pwa/scripts/`.

## 1. Performance

- Implemented in repo:
  - Static route documents with clean URLs: `apps/cool-pwa/index.html`, `apps/cool-pwa/home/index.html`, `apps/cool-pwa/groups/index.html`, `apps/cool-pwa/momo/index.html`, `apps/cool-pwa/profile/index.html`, `apps/cool-pwa/notifications/index.html`, `apps/cool-pwa/install/index.html`.
  - Route-level data split into small JSON files: `apps/cool-pwa/data/*.json`.
  - Local font hosting with `font-display: swap`: `apps/cool-pwa/assets/css/app.css`.
  - Hero image preload and WebP fallback: `apps/cool-pwa/index.html`.
  - Local icon/image/font assets for low-latency shell delivery: `apps/cool-pwa/assets/`.
  - Cache-friendly static asset handling in service worker: `apps/cool-pwa/service-worker.js`.
  - Performance audit automation: `apps/cool-pwa/scripts/run-lighthouse.mjs`, `.github/workflows/cool-pwa-ci.yml`.
  - Basic RUM-style vitals capture hooks for LCP, INP, CLS, FCP, and TTFB: `apps/cool-pwa/assets/js/app.js`.
- Deployment enforced:
  - Immutable caching for static assets: `firebase.pwa.json`.
  - Revalidation for HTML, manifest, XML, and JSON: `firebase.pwa.json`.
- Operator validation after deploy:
  - Lighthouse mobile score target and Core Web Vitals field validation still need to be checked against the real hosted origin.
  - HTTP/3 + QUIC depends on the final hosting platform and CDN, not local source files.

## 2. Installability

- Implemented in repo:
  - Full manifest with `name`, `short_name`, `start_url`, `scope`, `display`, `background_color`, `theme_color`, `description`, and categories: `apps/cool-pwa/manifest.webmanifest`.
  - Icons in `192`, `256`, `384`, `512`, and `1024`: `apps/cool-pwa/assets/icons/`.
  - Maskable icons: `apps/cool-pwa/assets/icons/Icon-maskable-192.png`, `apps/cool-pwa/assets/icons/Icon-maskable-512.png`.
  - App shortcuts: `apps/cool-pwa/manifest.webmanifest`.
  - Install screenshots: `apps/cool-pwa/manifest.webmanifest`, `apps/cool-pwa/assets/screenshots/`.
  - Deferred Chromium install prompt capture and custom banner flow: `apps/cool-pwa/assets/js/app.js`.
  - iOS Add to Home Screen guidance and dialogs: `apps/cool-pwa/install/index.html`, `apps/cool-pwa/assets/js/app.js`.
  - Apple-specific meta tags and touch icon coverage on primary routes: `apps/cool-pwa/index.html`, `apps/cool-pwa/home/index.html`, `apps/cool-pwa/groups/index.html`, `apps/cool-pwa/momo/index.html`, `apps/cool-pwa/profile/index.html`, `apps/cool-pwa/notifications/index.html`, `apps/cool-pwa/install/index.html`.
- Deployment enforced:
  - HTTPS requirement is satisfied by production hosting, not local file serving.
- Verified in CI:
  - Manifest completeness and installability contracts: `apps/cool-pwa/scripts/pwa-contracts.test.mjs`.

## 3. Offline and Reliability

- Implemented in repo:
  - Service worker registration on first visit: `apps/cool-pwa/assets/js/app.js`.
  - App shell precache: `apps/cool-pwa/service-worker.js`.
  - Custom branded offline fallback page: `apps/cool-pwa/offline/index.html`, `apps/cool-pwa/service-worker.js`.
  - Cache-first or stale-while-revalidate handling for static assets: `apps/cool-pwa/service-worker.js`.
  - Network-first handling for dynamic route JSON: `apps/cool-pwa/service-worker.js`.
  - IndexedDB persistence for settings, drafts, queue, notifications, shares, events, and passkeys: `apps/cool-pwa/assets/js/idb.js`.
  - Replay-safe foreground and background queue flush: `apps/cool-pwa/assets/js/app.js`, `apps/cool-pwa/service-worker.js`.
  - Periodic background refresh hook: `apps/cool-pwa/service-worker.js`.
  - Update prompt plus `skipWaiting` activation flow: `apps/cool-pwa/assets/js/app.js`, `apps/cool-pwa/service-worker.js`.
  - Cache versioning and purge on activate: `apps/cool-pwa/service-worker.js`.
  - Offline shell presence asserted in browser CI through Cache Storage inspection: `apps/cool-pwa/scripts/verify-browser.mjs`.
- Notes:
  - Offline authentication is represented by passkey-ready client UX and persisted local state, but production token/session strategy depends on the eventual backend.

## 4. Security

- Implemented in repo:
  - Strict hosting headers: HSTS, CSP, `X-Content-Type-Options`, `X-Frame-Options`, `Permissions-Policy`, `Referrer-Policy`, `Cross-Origin-Opener-Policy`, `Cross-Origin-Resource-Policy`: `firebase.pwa.json`.
  - No third-party runtime scripts, which removes the current need for SRI.
  - WebAuthn/passkey registration and verification UX: `apps/cool-pwa/assets/js/app.js`, `apps/cool-pwa/profile/index.html`.
  - Sensitive state is stored in IndexedDB stores rather than `localStorage`, except for the non-sensitive install-prompt dismissal timestamp used only for UX throttling: `apps/cool-pwa/assets/js/app.js`, `apps/cool-pwa/assets/js/idb.js`.
  - Dependency audit point in CI package workflow via lockfile-managed Node dependencies: `apps/cool-pwa/package-lock.json`.
- Deployment or backend follow-through:
  - CORS, rate-limiting, and CSRF protection apply to real API endpoints and must be enforced by the eventual backend because this PWA is currently static-first with demo queue endpoints.

## 5. UX and Design

- Implemented in repo:
  - Mobile-first responsive layout and route shell: `apps/cool-pwa/assets/css/app.css`.
  - Minimum touch target sizing: `apps/cool-pwa/assets/css/app.css`.
  - Skip link, visible focus states, semantic forms, and keyboard-reachable controls: route HTML files and `apps/cool-pwa/assets/css/app.css`.
  - Reduced motion handling: `apps/cool-pwa/assets/css/app.css`.
  - Dark mode with CSS variables and persisted theme toggle: `apps/cool-pwa/assets/css/app.css`, `apps/cool-pwa/assets/js/app.js`.
  - App-like navigation with clean path routes: route HTML files.
  - Skeleton placeholders for route collections: route HTML files.
  - Optimistic local queueing before replay: `apps/cool-pwa/assets/js/app.js`.
  - Form typing, autocomplete, and anti-zoom support: route HTML files and `apps/cool-pwa/assets/css/app.css`.
  - Friendly loading and error toasts instead of raw failures: `apps/cool-pwa/assets/js/app.js`.
  - Cross-session continuity for scroll, theme, drafts, install state, and notification/read state: `apps/cool-pwa/assets/js/app.js`, `apps/cool-pwa/assets/js/idb.js`.

## 6. Engagement

- Implemented in repo:
  - Contextual notification permission request, not on first load: `apps/cool-pwa/notifications/index.html`, `apps/cool-pwa/assets/js/app.js`.
  - Rich notification payload shape with title, body, icon, badge, actions, and deep links: `apps/cool-pwa/assets/js/app.js`, `apps/cool-pwa/service-worker.js`.
  - Background Sync hooks for queued mutations: `apps/cool-pwa/service-worker.js`, `apps/cool-pwa/assets/js/app.js`.
  - App badge updates: `apps/cool-pwa/assets/js/app.js`.
  - Manifest share target: `apps/cool-pwa/manifest.webmanifest`.
  - Web Share API outbound sharing: `apps/cool-pwa/assets/js/app.js`.
  - Periodic refresh hook: `apps/cool-pwa/service-worker.js`.
  - Success-moment tracking and install prompt timing: `apps/cool-pwa/assets/js/app.js`.
  - Deep-linkable content via route-per-view structure: route HTML files.
  - In-app alert fallback when system notifications are unavailable: `apps/cool-pwa/assets/js/app.js`.
- Backend follow-through:
  - Real push subscription storage and re-targeting require a server endpoint and VAPID infrastructure.

## 7. SEO and Discoverability

- Implemented in repo:
  - Static HTML for all primary content routes: route HTML files.
  - Unique titles and descriptions per route: route HTML files.
  - Open Graph and Twitter Card tags on shareable routes: route HTML files.
  - Canonical URLs: route HTML files.
  - Software application structured data on the landing page: `apps/cool-pwa/index.html`.
  - XML sitemap: `apps/cool-pwa/sitemap.xml`.
  - `robots.txt`: `apps/cool-pwa/robots.txt`.
  - `noindex,nofollow` on utility routes that should not rank: `apps/cool-pwa/admin/index.html`, `apps/cool-pwa/share/index.html`, `apps/cool-pwa/offline/index.html`.
  - Clean non-hash routing: route HTML files.
  - Above-the-fold content rendered directly in HTML rather than hidden behind JavaScript.
- Operator validation after deploy:
  - Search Console submission, field CWV visibility, and optional hreflang are deployment and content-ops follow-through items.

## 8. Platform and Distribution

- Implemented in repo:
  - Browser install guidance for Chromium and Safari: `apps/cool-pwa/install/index.html`.
  - iOS-specific fullscreen and icon meta tags on primary routes: route HTML files.
  - Lighthouse, browser, and contract automation in CI: `.github/workflows/cool-pwa-ci.yml`, `apps/cool-pwa/scripts/`.
  - Firebase Hosting config dedicated to the PWA: `firebase.pwa.json`.
  - Install funnel analytics hooks for impression, prompt result, dismissal, and success: `apps/cool-pwa/assets/js/app.js`.
- Packaging readiness:
  - The app is structured for PWABuilder or TWA packaging because it provides a compliant manifest, standalone routes, icons, screenshots, clean URLs, and HTTPS-ready hosting config.
- External follow-through:
  - Actual Play Store, Microsoft Store, or iOS packaging is a release operation after deploy, not a local source code change.
  - Real-device matrix testing on Safari, Samsung Internet, Firefox Mobile, and device farms still needs to be run against the hosted domain.

## Verification Commands

Run from repo root unless noted:

```bash
cd apps/cool-pwa && npm test
cd apps/cool-pwa && npm run audit:lighthouse
flutter analyze
flutter test test/docs/pwa_web_assets_test.dart
```

## Current Intentional Boundary

- The PWA is fully implemented as a second client application in this repo without replacing or degrading the Flutter app.
- Client-side checklist coverage is encoded directly in source, browser tests, contract tests, CI workflow, and hosting config.
- Production-only and backend-only items are prepared where possible and explicitly called out above so they can be closed during deployment rather than left implicit.
