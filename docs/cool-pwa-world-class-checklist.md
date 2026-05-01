# COOL Admin PWA Checklist Mapping

This document maps the April 2026 PWA hardening work to the admin-only web
client in `apps/pwa/`.

## Scope

- Flutter mobile remains the primary end-user client.
- `apps/pwa/` is now admin-only.
- All active PWA routes live under `/admin/*`.
- Public landing, profile, notifications, groups, MoMo, install, share, legal,
  and account-deletion pages were removed from the PWA.

## Route Inventory

- `/admin/` — workspace selector
- `/admin/platform/` — platform command center
- `/admin/users/` — user management
- `/admin/app-config/` — rollout and routing controls
- `/admin/operations/` — release blockers, alerts, and incident handling
- `/admin/roles/` — admin permission assignment
- `/admin/analytics/` — platform metrics
- `/admin/audit-log/` — evidence trail
- `/admin/groups/` — group oversight
- `/admin/offline/` — offline fallback

## Coverage

### Performance

- Static route documents are present for every admin domain.
- Route-level JSON payloads in `apps/pwa/data/*.json` keep shell delivery
  light.
- Local fonts, static assets, and app-shell CSS remain self-hosted.
- Browser and Lighthouse verification remain in
  `apps/pwa/scripts/` and `.github/workflows/cool-pwa-ci.yml`.

### Installability

- `manifest.webmanifest` now identifies the app as `COOL Admin Console`.
- `start_url` is `/admin/?source=pwa` and scope is `/admin/`.
- App shortcuts point only to admin routes.
- Install UX still exists through shared shell banners and iOS guidance dialogs.

### Offline and Reliability

- `service-worker.js` precaches only admin routes plus `/` and `/index.html`
  for redirect support.
- Offline fallback moved to `/admin/offline/`.
- Replay-safe queueing, sync, periodic refresh hooks, and update activation
  remain enabled.

### Security

- Hosting headers are enforced through Cloudflare Pages `_headers` and
  `functions/index.js` (root redirect + security headers).
- All admin pages include `noindex,nofollow`.
- `robots.txt` disallows crawling for the whole app.
- Admin alerts, queue state, drafts, and telemetry use IndexedDB-backed storage.
- Admin sessions use HttpOnly cookies — no tokens stored client-side.

### UX and Design

- Shared admin shell navigation spans workspaces, command, users, config, ops,
  roles, analytics, audit, and groups.
- Responsive layout, focus states, reduced motion handling, theme persistence,
  and install/update banners remain intact.
- Forms are admin-task oriented and queue offline-safe mutations rather than
  public product actions.

### Engagement

- Alerts remain available for admin operations through browser notifications and
  in-app fallback.
- Web Share remains available for copying admin route links, but manifest share
  target support was removed with the public share page.
- Success-moment and install-prompt timing still exist for the admin shell.

### Discoverability

- Sitemap now lists only admin routes.
- Root path redirects directly to `/admin/`.
- The app is intentionally not discoverable through search indexing.

### Platform and Distribution

- **Deployment target: Cloudflare Pages** (`wrangler.toml`, `functions/`).
- CI runs contract tests, browser checks, and Lighthouse via `.github/workflows/cool-pwa-ci.yml`.
- The app remains installable and packaging-ready as an internal admin shell.

## Verification Commands

```bash
cd apps/pwa && npm test
cd apps/pwa && npm run audit:lighthouse
flutter analyze
flutter test test/docs/pwa_web_assets_test.dart
```

## Current Boundary

- The PWA is an admin control plane only.
- End-user product experiences remain in Flutter mobile, not in this PWA.
- Frontend governance, backend readiness, release control, and operational
  tooling are represented through the admin route set instead of any public web
  routes.
