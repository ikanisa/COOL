# Web Surface Registry

This registry is the source of truth for web surfaces that can be linked,
deployed, tested, or described as production-ready. It prevents placeholder web
apps from becoming production paths.

The machine-readable registry lives in
[`web-surface-registry.json`](./web-surface-registry.json). CI and release
checks should treat this file as authoritative.

Activation requirements for missing or retired surfaces live in
[`web-surface-activation-contracts.md`](./web-surface-activation-contracts.md).

## Active Surfaces

- `apps/admin`: active React/Vite platform admin for operations, finance,
  roles, audit, health, BioPay, and support workflows. Browser permission checks
  are convenience only; Supabase RLS, RPCs, and Edge Functions remain the source
  of truth for sensitive actions.
- `apps/website`: active static public website for landing, legal, account
  deletion, and public information surfaces.
- Repository root Flutter app: active mobile app. It remains at the root until a
  dedicated mobile move updates native projects, CI, release scripts, generated
  files, and asset paths in one migration.

## Inactive Or Missing Surfaces

- `apps/pwa`: retired fail-closed user PWA stub. It must not contain production
  UI unless the PWA is formally revived with real backend state, permissions,
  tests, security headers, and release ownership.
- Venue manager dashboard: not implemented as a separate web app.
- Agent admin console: not implemented as a separate web app.
- Promotions approval console: not implemented as a separate web app.

## Promotion Criteria

A missing or retired surface can become active only when the same change adds:

- a real source path and release owner;
- route ownership and backend authorization/RLS or Edge Function enforcement;
- loading, empty, error, success, disabled, and permission-denied UI states;
- no hardcoded users, venues, teams, menus, drivers, predictions, agents, or
  metrics;
- build, lint, and test commands in the registry;
- audit logging for sensitive actions;
- documentation in this file and the release runbook.

Do not create shell apps, dead navigation, or "coming soon" production pages to
satisfy product-surface inventory gaps.
