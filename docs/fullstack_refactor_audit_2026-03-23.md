# Fullstack Refactor Audit

Date: 2026-03-23

## Scope

This audit reviews the current Flutter app, Supabase backend, static web
surfaces, repository hygiene, and enforcement tooling.

Primary verification sources:

- `flutter analyze`
- `lib/**`
- `supabase/functions/**`
- `supabase/migrations/**`
- `.github/workflows/**`
- `scripts/**`
- `hosting/`, `landing/`, `deeplinks/site/`

## Executive Summary

The repo is not in a broadly broken state. `flutter analyze` currently reports
only `8` issues, mostly legacy-theme deprecations plus one unused import.

The real problem is structural concentration:

- `462` Dart files under `lib/`
- `191` Dart test files under `test/`
- `56` files under `supabase/functions/`
- `137` SQL migrations
- `75` Dart files over `500` lines
- `22` Dart files over `800` lines
- `9` Edge Function TypeScript files over `500` lines
- `70` `part` / `part of` declarations in `lib/`
- `29` Edge Function entrypoints but only `8` TypeScript test files

This is a repo with decent local guardrails but too many large ownership
surfaces. It needs a focused refactor plan, not a rewrite.

## Verified Signals

### Static analysis

- `flutter analyze` completed in about `78s` with `8` issues.
- Findings were:
  - `1` unused import in `integration_test/critical_journeys_test.dart`
  - deprecated theme API usage in `lib/core/theme/app_theme.dart`
  - deprecated theme API usage in `lib/core/theme/cool_palette.dart`
  - deprecated theme API usage in `lib/core/theme/theme_system_chrome.dart`

### Repo structure pressure

- Frontend hotspots:
  - `lib/features/momo/services/momo_statement_export_service.dart` (`1194`)
  - `lib/features/admin/repositories/admin_repository.dart` (`1060`)
  - `lib/core/router/app_router.dart` (`903`)
  - `lib/features/partners/providers/rayon_sports_provider.dart` (`854`)
  - `lib/features/admin/screens/operational_dashboard_screen.dart` + parts (`1730` combined)
- Backend hotspots:
  - `supabase/functions/parse-momo-sms/reconciliation.ts` (`1139`)
  - `supabase/functions/wallet-issuer/index.ts` (`1119`)
  - `supabase/functions/maps-gateway/index.ts` (`783`)
  - `supabase/functions/biopay-match/index.ts` (`600`)
  - `supabase/functions/parse-momo-sms/index.ts` (`526`)

### CI and repo policy state

- CI already enforces secret-pattern blocking, theme-budget checks, and large
  file warnings in `.github/workflows/ci.yml`.
- Release readiness already expects `flutter analyze`, `flutter test`,
  integration-smoke tests, deep-link checks, and Deno checks in
  `scripts/release_readiness.sh`.
- The main gap is not lack of policy. It is that the implementation has drifted
  beyond the clean boundaries those policies imply.

## Critical Findings

### 1. A committed SQL migration is malformed

Severity: Critical

`supabase/migrations/20260322176000_fix_momo_sms_sender_inventory_ambiguity.sql`
contains a raw patch marker:

- `*** Add File: /Volumes/PRO-G40/COOL/supabase/migrations/20260322177000_fix_momo_sms_sender_inventory_grouping_aliases.sql`

This appears inline at line `129` inside a SQL function body. That is not valid
SQL and makes the migration chain unreliable.

Why this matters:

- migration replay can fail or diverge between environments
- production schema trust is broken if committed migrations are not guaranteed
  to be executable
- it also suggests the repo lacks a migration-lint or dry-run step that would
  catch committed patch artifacts

Immediate action:

1. Repair or replace the malformed migration.
2. Add a CI check that rejects `*** Begin Patch`, `*** Add File`, and similar
   markers anywhere in committed source or SQL.
3. Add a migration replay validation step before release.

### 2. The frontend architecture is concentrated into a few oversized ownership files

Severity: High

The frontend has too many oversized runtime files and too much `part`-based
coupling:

- `lib/core/router/app_router.dart`
- `lib/features/admin/screens/manage_app_config_screen.dart`
- `lib/features/admin/screens/operational_dashboard_screen.dart`
- `lib/features/admin/widgets/bank_admin/bank_admin_workspace_parts.dart`
- `lib/features/partners/providers/rayon_sports_provider.dart`
- `lib/features/momo/services/momo_statement_export_service.dart`

The router alone imports nearly every feature screen and owns auth snapshot
derivation, kill-switch wrapping, shell branches, and route construction in one
file. Admin screens often pull controllers and widget trees into `part` files
instead of moving logic behind clearer component boundaries.

Why this matters:

- high regression surface for every route or admin change
- slow code review because screens, controller logic, and UI composition are
  interleaved
- `part` files hide ownership boundaries and make refactors harder to stage

Refactor direction:

1. Split router declarations by domain and compose them centrally.
2. Replace screen `part` graphs with explicit widgets, view-model classes, and
   feature-local components.
3. Set hard budgets for screen, provider, and service file size.

### 3. Data-access ownership is inconsistent

Severity: High

The repo says repositories own Supabase access, but the implementation has
drifted:

- `lib/features/admin/screens/manage_ai_content_screen.dart` reads and writes
  `ai_content_generation_config` directly and invokes the `generate-ai-content`
  function from the screen.
- `lib/core/services/momo_service.dart` writes directly to
  legacy subscription tables.
- `lib/features/admin/repositories/admin_repository.dart` has become a generic
  multi-table admin gateway for users, partners, routes, quick actions, and
  more.

Why this matters:

- the same table can be changed from screen, service, or repository layers
- validation and authorization assumptions get duplicated
- tests become broad and UI-coupled because business rules are not centered in
  one domain owner

Refactor direction:

1. Move screen-owned Supabase access into dedicated repositories or commands.
2. Split `AdminRepository` by bounded context:
   - partners
   - app config
   - users and roles
   - operational controls
3. Keep services focused on orchestration, not persistence contracts.

### 4. The backend is carrying too much behavior per function and too many migration types in one chain

Severity: High

The Edge Functions layer is operationally important but structurally dense:

- `wallet-issuer/index.ts` handles auth, config loading, Google Wallet object
  management, token caching, API calls, persistence, telemetry, and readiness
  inspection in one file.
- `parse-momo-sms/index.ts` mixes request handling, parse-attempt bookkeeping,
  provider fallback logic, parsed-row upserts, reconciliation, and telemetry.
- `parse-momo-sms/reconciliation.ts` contains heavy scoring and target-specific
  reconciliation logic across groups, subscriptions, and partner flows.
- `maps-gateway/index.ts` bundles action routing and all Google Maps request
  variants in one file.

The migration chain also mixes production schema, mock/demo seed data, repair
scripts, hotfixes, and repeated fix migrations. At least `19` migration files
currently match `demo|mock|seed|repair|hotfix|fix_`.

Why this matters:

- deploy reasoning is harder than it should be
- on-call debugging requires loading too much unrelated logic
- hotfixes accumulate as permanent structure
- demo or repair SQL obscures the production contract chain

Refactor direction:

1. Split each large Edge Function into:
   - transport entrypoint
   - request validation
   - domain service
   - external adapter
   - telemetry wrapper
2. Introduce a migration catalog:
   - schema
   - seed
   - demo
   - repair
   - hardening
3. Move long-lived demo/mock data out of the main production migration story.

### 5. Repo ownership is fragmented across product, web, design, and operator surfaces

Severity: Medium

The repo root currently mixes runtime code and operator-local state:

- tracked `.agent/skills/**`
- `hosting/`
- `landing/`
- `deeplinks/site/`
- local logs such as `flutter_01.log` and `flutter_02.log`
- `stitch_exports/`
- local `.env` and `.env.json`
- local `output/`

There are also overlapping public-web responsibilities:

- `hosting/.well-known/assetlinks.json`
- `deeplinks/site/.well-known/assetlinks.json`
- `landing/.well-known/assetlinks.json`

`hosting` and `deeplinks/site` currently share the same `assetlinks.json`
payload hash, while `landing` has a different copy.

Why this matters:

- hard to tell which root paths are product-owned
- documentation and release ownership become ambiguous
- static web changes can drift because landing, legal, and deeplink concerns
  are split across three roots

Refactor direction:

1. Decide whether `.agent/` is product-owned or local tooling. If local, remove
   it from version control.
2. Collapse public web ownership:
   - one site for landing and legal
   - one site for deeplink association and fallback
3. Keep local operator output outside the product root or clean it in one
   command.

### 6. Device-surface coverage is too thin relative to the feature surface

Severity: Medium

The app depends on SMS access, NFC, camera, biometric flows, QR scanning,
location, Firebase, and deep links, but only `2` files exist under
`integration_test/`.

One of those files, `integration_test/critical_journeys_test.dart`, is largely
mocked and exercises widget-level journey assembly more than real device
integration. The second file, `integration_test/momo_sms_inbox_sync_test.dart`,
focuses on Android SMS sync specifically.

Why this matters:

- the highest-risk behaviors are device and platform behaviors
- widget and smoke tests do not replace release-device coverage for SMS, camera,
  NFC, and auth handoffs
- the repo gives a strong impression of broad test coverage while true device
  coverage remains narrow

Refactor direction:

1. Promote real-device critical flows into a small but deliberate device suite:
   - auth
   - QR scan
   - SMS permission and sync
   - BioPay capture and match
   - deep-link handoff
2. Keep widget/smoke tests for fast regressions, but stop treating them as full
   end-to-end confidence.

### 7. Tooling and documentation still contain machine-specific paths

Severity: Medium

Examples:

- `android/fastlane/Fastfile`
- `android/fastlane/Appfile`
- `README.md`

The Fastlane setup hardcodes `/Volumes/PRO-G40/COOL/output/play_store/...`.
The README also embeds machine-local absolute paths in many markdown links.

Why this matters:

- breaks portability across machines and CI runners
- makes repository docs less useful on GitHub and external review surfaces
- signals that operator-local workflow assumptions have leaked into committed
  config

Refactor direction:

1. Replace absolute paths with repo-relative or environment-driven values.
2. Normalize docs to relative links.

## Recommended Critical Refactor Plan

### Phase 0: Stop-the-line fixes

Target: `1-2 days`

1. Repair the malformed migration and verify the chain replays cleanly.
2. Add a CI guard for patch markers in SQL and source files.
3. Remove absolute-path release config from Fastlane.
4. Decide ownership for `.agent/`, `stitch_exports/`, and local output roots.

Exit criteria:

- migration chain is executable
- no machine-local release path remains in committed config
- root ownership is explicit

### Phase 1: Boundary cleanup

Target: `3-5 days`

1. Move direct Supabase access out of `ManageAiContentScreen`.
2. Split `AdminRepository` into bounded repositories.
3. Pull persistence work out of `MomoService` where it represents domain
   storage rather than transport orchestration.
4. Document one owner per table or RPC contract.

Exit criteria:

- screens no longer write to Supabase directly
- admin CRUD is split by domain
- domain write paths are discoverable and testable

### Phase 2: Frontend decomposition

Target: `1-2 weeks`

Priority order:

1. `lib/core/router/app_router.dart`
2. admin screens and admin parts
3. Rayon providers and repository parts
4. MoMo export and sync surfaces

Rules:

- replace `part` coupling with explicit widgets and classes
- separate composition from orchestration
- keep domain logic out of screen files
- keep route declarations domain-local

Exit criteria:

- no runtime screen or provider file over agreed budget without waiver
- `part` usage limited to narrow model-only cases

### Phase 3: Backend decomposition

Target: `1-2 weeks`

1. Split `wallet-issuer` into request, config, Google Wallet adapter,
   persistence, and telemetry modules.
2. Split `parse-momo-sms` into attempt lifecycle, AI provider orchestration,
   reconciliation dispatcher, and target-specific matching.
3. Split `maps-gateway` by supported action.
4. Increase function test coverage to cover the highest-risk entrypoints.

Exit criteria:

- each critical Edge Function has a small entrypoint and testable domain module
- backend tests cover the main happy and failure paths of each financial flow

### Phase 4: Migration and repo hygiene

Target: `3-5 days`

1. Classify migrations and separate demo or repair concerns from the active
   production contract story.
2. Consolidate static web ownership.
3. Move stale or dated docs into archive semantics.
4. Remove tracked non-product assets that should be local-only.

Exit criteria:

- migration intent is legible
- public web has clear ownership
- docs root is current, not historically layered

### Phase 5: Enforcement

Target: ongoing

1. Add migration replay validation to CI.
2. Add a patch-marker scan.
3. Add a stricter `part` budget.
4. Add a direct-Supabase-in-screens check.
5. Raise backend coverage expectations for critical financial functions.

Exit criteria:

- structural drift is blocked automatically
- repo cleanup becomes durable, not one-time

## Final Assessment

This repo does not need a rewrite.

It does need a disciplined cleanup program centered on:

1. migration integrity
2. ownership boundaries
3. oversized file decomposition
4. backend modularization
5. root-surface consolidation

If those five areas are handled in order, the repo can become clean and
maintainable without destabilizing the current product surface.
