# Monorepo Structure Plan

Date: 2026-05-01

This plan is based on the current source tree. The Flutter app now has an
`apps/mobile` package boundary while historical root paths remain available for
native build and CI compatibility.

## Current Structure

```text
/
  pubspec.yaml                 # Root compatibility path for Flutter tooling
  lib/                         # Root compatibility path for Flutter source
  android/ ios/ web/           # Root compatibility paths for native shells
  test/ integration_test/      # Root compatibility paths for tests
  apps/
    mobile/                    # Runnable Flutter app boundary via symlinks
    admin/                     # React/Vite admin panel
    website/                   # Public static website
    pwa/                       # Retired Cloudflare Pages stub
  supabase/
    migrations/
    functions/
  docs/
  scripts/
  tool/
```

## Target Structure

```text
/apps
  /mobile                      # Flutter app boundary with root-compatible links
  /admin                       # React admin panel
  /website                     # public website
  /pwa                         # future installable PWA if revived
  /venue-dashboard             # future scoped venue/team dashboard
  /agent-console               # future agent operations console

/packages
  /design-system
  /shared-types
  /shared-utils
  /domain
  /api-clients
  /auth
  /payments
  /agent-ui
  /analytics

/supabase
  /migrations
  /functions
  /policies
  /seed
  /tests
  /docs

/agents
  /shared
  /workspaces
  /tools
  /channels
  /memory
  /evals
  /prompts

/integrations
  /whatsapp
  /telegram
  /google-chat
  /teams
  /email
  /voice
  /ussd
  /payments

/docs
  /architecture
  /product
  /security
  /release
  /testing
  /operations

/scripts
  /dev
  /qa
  /deploy
  /migrations
  /lib

/infra
  /ci
  /config
  /monitoring
```

## Dependency Rules

- Apps may depend on packages and backend contracts.
- Packages must not depend on apps.
- Supabase functions may depend on `supabase/functions/_shared` and generated
  shared contracts, but not app UI code.
- Integrations must expose narrow adapters and must not own product journeys.
- Auth, role, payment, and audit decisions must be enforced in Supabase RLS,
  RPCs, or Edge Functions before UI affordances are added.
- Reserved target folders are documentation boundaries only until real shared
  code has at least two consumers.

## Safe Changes Applied In This Pass

- Renamed the legacy React admin app into `apps/admin`.
- Moved the public website into `apps/website`.
- Moved the retired PWA stub to `apps/pwa`.
- Made `apps/mobile` an executable Flutter package boundary that preserves
  historical root compatibility paths.
- Added root `Makefile` workspace commands for common verification tasks.
- Grouped scripts under `scripts/{dev,qa,deploy,migrations,lib}` while keeping
  old-path compatibility wrappers.
- Extracted the admin PostgREST search sanitizer into
  `packages/shared-utils/src/admin-search.ts`.
- Moved the Supabase seed file into `supabase/seed/cool_status.sql`.
- Updated path-based tests and the current audit document for the new paths.
- Added README files for major target folders and docs categories.

## Deferred Moves

- Removal of root Flutter compatibility paths.
  CI workflows, release scripts, generated localization, Android/iOS paths,
  Firebase/App Check verification, and package imports still support the
  historical root path while the app is also runnable from `apps/mobile`.
- Package extraction.
  Only `shared-utils/admin-search` has been extracted. Continue extracting only
  when dependency direction and consumers are proven.

## Next Migration Sequence

1. Add package extraction tests for shared type contracts before moving more
   code.
2. Gradually update CI, release, native, and generated-file paths to use
   `apps/mobile`; remove root compatibility paths only after full mobile builds
   pass from the app boundary.
