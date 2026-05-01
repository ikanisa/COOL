# Apps

Production app surfaces live here when they can build and release independently.

## Current apps

- `admin/` — React/Vite admin panel. Browser authorization is convenience-only;
  Supabase RLS and RPC checks remain the source of truth.
- `website/` — public static website for landing, legal, and account deletion
  surfaces.
- `pwa/` — retired Cloudflare Pages stub retained as an explicit fail-closed
  placeholder until an installable PWA is formally revived.
- `mobile/` — ownership marker for the root Flutter app until native/CI paths
  are migrated.

The production status for active, retired, and missing web surfaces is tracked
in [`../docs/product/web-surface-registry.md`](../docs/product/web-surface-registry.md).
Do not create placeholder apps for venue, agent, promotions, or user PWA flows
without the backend, permission, testing, and release criteria documented there.

## Transitional app

The Flutter mobile app still lives at the repository root (`pubspec.yaml`,
`lib/`, `android/`, `ios/`, `web/`, `test/`, `integration_test/`). CI, release
scripts, localization generation, and native build tooling all currently assume
that root layout. Move it to `apps/mobile/` only in a dedicated migration that
updates every script, workflow, asset path, and generated-file reference in the
same change.

## Boundary rules

- App code may depend on shared packages or backend contracts.
- Shared domain, auth, payment, role, and integration logic must not be copied
  across apps.
- UI-specific state belongs in the app. Backend authorization and sensitive
  actions belong in Supabase RLS/RPCs or Edge Functions.
