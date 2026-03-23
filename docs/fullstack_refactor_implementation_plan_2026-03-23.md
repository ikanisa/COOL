# Fullstack Refactor Implementation Plan

Date: 2026-03-23

Source audit:

- `docs/fullstack_refactor_audit_2026-03-23.md`

## Objective

Execute a controlled refactor program that makes the repo:

- structurally clean
- easier to maintain
- safer to release
- easier to reason about across Flutter, Supabase, and static web surfaces

This is a refactor plan, not a rewrite plan. The current product remains the
baseline; cleanup work must preserve behavior while reducing structural risk.

## Success Criteria

The program is complete when all of the following are true:

1. The migration chain is valid, replayable, and free of malformed files.
2. No critical runtime or backend flow depends on screen-owned database access.
3. Oversized runtime files are decomposed into explicit modules with clear
   boundaries.
4. Critical Edge Functions are split into small entrypoints and testable domain
   modules.
5. Static web ownership is consolidated and machine-local paths are removed.
6. CI enforces the new boundaries so the repo does not regress.

## Delivery Principles

1. Fix correctness and release integrity before architecture cleanup.
2. Refactor by bounded context, not by file size alone.
3. Prefer behavior-preserving extraction before behavioral cleanup.
4. Land small slices with tests and enforcement, not a single giant branch.
5. Delete superseded code quickly once replacement is stable.

## Program Structure

### Phase 0: Stabilize The Repo

Duration:

- `1 to 2 days`

Goal:

- remove immediate release blockers and establish a safe baseline

Primary deliverables:

1. Repair the malformed migration:
   - `supabase/migrations/20260322176000_fix_momo_sms_sender_inventory_ambiguity.sql`
2. Verify `20260322177000_fix_momo_sms_sender_inventory_grouping_aliases.sql`
   remains the authoritative follow-up migration.
3. Add CI scan for patch markers:
   - reject `*** Begin Patch`
   - reject `*** Add File`
   - reject `*** Update File`
   - reject `*** End Patch`
4. Remove machine-local paths from:
   - `android/fastlane/Fastfile`
   - `android/fastlane/Appfile`
5. Decide ownership of:
   - `.agent/`
   - `stitch_exports/`
   - local logs
   - `output/`

Exit criteria:

- migration chain is syntactically valid
- release config is portable
- root-level local artifacts have an explicit disposition

### Phase 1: Establish Ownership Boundaries

Duration:

- `3 to 5 days`

Goal:

- make data-access and domain ownership explicit

Primary deliverables:

1. Replace screen-owned Supabase access in:
   - `lib/features/admin/screens/manage_ai_content_screen.dart`
2. Split `AdminRepository` into bounded repositories:
   - `AdminUsersRepository`
   - `AdminPartnersRepository`
   - `AdminAppConfigRepository`
   - `AdminOperationsRepository`
3. Review service-layer write paths and move persistence into repositories where
   appropriate:
   - `lib/core/services/momo_service.dart`
4. Add a lightweight repo rule:
   - screens/widgets must not call `.from(...)` or `.rpc(...)` directly

Recommended sequence:

1. `manage_ai_content`
2. admin partner/config/users split
3. MoMo service persistence cleanup

Exit criteria:

- all new data writes happen through repository or domain-service owners
- screen files are orchestration-only
- admin CRUD ownership is no longer centralized in one god-repository

### Phase 2: Frontend Decomposition

Duration:

- `1 to 2 weeks`

Goal:

- reduce coupling and bring the runtime surface under maintainable file budgets

Priority workstreams:

1. Router decomposition
2. Admin surface decomposition
3. Rayon domain decomposition
4. MoMo domain decomposition
5. Shared widget extraction

#### Workstream 2.1: Router

Target files:

- `lib/core/router/app_router.dart`

Implementation steps:

1. Create domain route modules:
   - auth routes
   - shell routes
   - admin routes
   - partners routes
   - momo and biopay routes
2. Keep redirect resolution centralized, but remove feature-specific route
   construction from one file.
3. Keep route inventories generated from composed route sources.

Exit criteria:

- `app_router.dart` becomes a composition root, not a monolith

#### Workstream 2.2: Admin

Target files:

- `lib/features/admin/screens/manage_app_config_screen.dart`
- `lib/features/admin/screens/operational_dashboard_screen.dart`
- `lib/features/admin/widgets/bank_admin/bank_admin_workspace_parts.dart`
- related `part` files

Implementation steps:

1. Replace `part`-based screen assembly with explicit widgets and controllers.
2. Extract section widgets into feature-local files.
3. Keep view-model logic in dedicated classes instead of inside screen files.
4. Normalize admin screens to one clear pattern:
   - screen shell
   - view model/provider
   - section widgets
   - repository

Exit criteria:

- no admin screen owns large blocks of business logic
- no new admin feature lands via `part` coupling

#### Workstream 2.3: Rayon

Target files:

- `lib/features/partners/providers/rayon_sports_provider.dart`
- `lib/features/partners/repositories/rayon_sports_repository.dart`
- Rayon screen/widget `part` files

Implementation steps:

1. Split providers by concern:
   - identity/bootstrap
   - membership
   - tickets
   - shop
   - initiatives
   - admin
2. Split `RayonSportsRepository` into explicit collaborators instead of
   repository-plus-part extensions.
3. Replace screen/widget `part` files with explicit feature modules.

Exit criteria:

- Rayon becomes a set of bounded modules instead of one large app-inside-the-app

#### Workstream 2.4: MoMo

Target files:

- `lib/features/momo/services/momo_statement_export_service.dart`
- `lib/features/momo/services/momo_sms_autoread_service.dart`
- `lib/features/momo/screens/momo_screen.dart`
- `lib/features/momo/screens/momo_statements_screen.dart`

Implementation steps:

1. Split export service by export type:
   - PDF
   - Excel
   - CSV
   - shared formatting helpers
2. Split SMS auto-read service into:
   - permissions/access
   - inbox scanning
   - dedupe/state tracking
   - sync audit
3. Move statement-screen parts into explicit widget and controller files.

Exit criteria:

- MoMo financial workflows are reviewable without reading thousand-line files

### Phase 3: Backend Modularization

Duration:

- `1 to 2 weeks`

Goal:

- make critical Edge Functions testable, auditable, and easier to extend

Priority workstreams:

1. `wallet-issuer`
2. `parse-momo-sms`
3. `maps-gateway`
4. `biopay-match`

#### Workstream 3.1: Wallet Issuer

Target file:

- `supabase/functions/wallet-issuer/index.ts`

Implementation steps:

1. Extract request parsing and auth.
2. Extract wallet config and readiness inspection.
3. Extract Google Wallet API adapter.
4. Extract ticket pass generation service.
5. Extract membership pass generation service.
6. Keep `index.ts` as thin transport + error boundary.

Exit criteria:

- `index.ts` is small and request-focused
- wallet logic can be unit-tested without the HTTP wrapper

#### Workstream 3.2: M-Money SMS Parse And Reconciliation

Target files:

- `supabase/functions/parse-momo-sms/index.ts`
- `supabase/functions/parse-momo-sms/reconciliation.ts`

Implementation steps:

1. Split parse-attempt lifecycle logic from HTTP handling.
2. Split AI provider orchestration from persistence.
3. Split reconciliation by target family:
   - groups
   - subscriptions
   - partner and Rayon
   - manual review
4. Preserve existing scoring behavior first; optimize later.

Exit criteria:

- parsing, reconciliation, and manual-review decisions are isolated modules

#### Workstream 3.3: Maps Gateway

Target file:

- `supabase/functions/maps-gateway/index.ts`

Implementation steps:

1. Extract one module per action:
   - autocomplete
   - text search
   - place details
   - reverse geocode
   - route compute
2. Keep key resolution and Rwanda scoping as shared guard modules.

Exit criteria:

- new maps actions can be added without editing one monolithic file

#### Workstream 3.4: Test Coverage

Implementation steps:

1. Add tests for critical functions that currently have none or limited
   coverage.
2. Expand beyond the current small TypeScript test set.
3. Define minimum coverage expectations for financial or auth-sensitive
   functions.

Exit criteria:

- critical financial and auth-related functions have direct tests

### Phase 4: Migration And Static-Surface Cleanup

Duration:

- `3 to 5 days`

Goal:

- reduce operational ambiguity in schema history and public web ownership

Primary deliverables:

1. Create a migration catalog:
   - schema
   - seed
   - mock/demo
   - repair
   - hardening
2. Mark or relocate one-off mock/demo migrations from the active production
   reasoning path.
3. Consolidate static web ownership:
   - one landing/legal surface
   - one deeplink association surface
4. Remove or archive duplicate `.well-known` ownership where possible.

Exit criteria:

- migration history is understandable
- web surface ownership is unambiguous

### Phase 5: Enforcement And Regression Prevention

Duration:

- `2 to 3 days`, then ongoing

Goal:

- stop the repo from drifting back into the same shape

Primary deliverables:

1. CI check for patch markers in committed files.
2. CI migration validation step.
3. CI rule blocking direct Supabase access in screens/widgets.
4. CI budget for `part` declarations.
5. File-size budget review:
   - lower soft budgets where decomposition lands
6. Docs update:
   - current architecture
   - ownership map
   - contribution rules

Exit criteria:

- the new boundaries are enforced by automation, not memory

## Suggested Ticket Breakdown

### Epic A: Release Integrity

Tickets:

1. Fix malformed migration and validate replay
2. Add patch-marker CI scan
3. Remove Fastlane absolute paths

### Epic B: Boundary Cleanup

Tickets:

1. Extract AI content config repository
2. Split admin repository by bounded context
3. Remove direct persistence from `MomoService`
4. Add screen-data-access guard

### Epic C: Frontend Decomposition

Tickets:

1. Split app router by domain
2. Decompose admin app-config screen
3. Decompose operational dashboard
4. Decompose Rayon provider graph
5. Decompose MoMo export service

### Epic D: Backend Decomposition

Tickets:

1. Split wallet issuer
2. Split M-Money parser orchestration
3. Split M-Money reconciliation logic
4. Split maps gateway by action
5. Raise backend coverage for critical functions

### Epic E: Repo And Web Cleanup

Tickets:

1. Classify migrations and archive demo/mock reasoning
2. Consolidate landing/legal ownership
3. Consolidate deeplink association ownership
4. Remove tracked local/operator-only assets

## Dependencies

Critical dependencies between phases:

1. Phase 0 must complete before broad refactor work starts.
2. Phase 1 should precede most screen decomposition, otherwise extraction will
   preserve bad ownership boundaries.
3. Phase 3 can run partly in parallel with late Phase 2 if ownership boundaries
   are already defined.
4. Phase 5 should start as soon as the first improved boundary lands.

## Risks

### Risk 1: Refactor branches become too large

Mitigation:

- ship by bounded context
- keep each merge small enough for targeted review

### Risk 2: Cleanup changes alter business behavior

Mitigation:

- preserve behavior first
- add regression tests before major extraction

### Risk 3: Migration cleanup causes environment divergence

Mitigation:

- never rewrite migration history casually
- validate replay on a clean database clone

### Risk 4: Teams keep adding features during cleanup

Mitigation:

- freeze touched domains while their refactor slice is in progress
- require new work to follow the new boundaries

## Recommended Execution Order

If only one team is working on this, use this order:

1. Fix migration corruption and release-path portability
2. Split admin data ownership
3. Decompose router
4. Decompose admin screens
5. Decompose Rayon
6. Decompose MoMo
7. Split critical Edge Functions
8. Clean migration classification and static web ownership
9. Tighten CI and documentation

## Final Recommendation

Start with a strict `Phase 0 + Phase 1` branch and do not mix it with product
feature work.

That first slice will deliver the biggest reduction in risk because it addresses:

- release integrity
- ownership clarity
- portability
- the highest-probability regression sources

After that, the rest of the plan becomes a controlled decomposition program
instead of emergency cleanup.
