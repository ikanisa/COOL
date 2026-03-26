# Repo Production Cleanup Plan

Date: 2026-03-23

This plan is based on the current repository state, plus the earlier audit and
remediation docs already in this repo:

- `docs/fullstack_audit_report_2026-03-13.md`
- `docs/fullstack_remediation_implementation_plan_2026-03-13.md`

## Objective

Move this repo from "active build + ongoing cleanup" to a production-grade
state where:

- the repo root contains only durable product assets
- secrets, local artifacts, exports, and backups are removed from version
  control
- duplicate or parallel surfaces have one owner and one source of truth
- dead code is deleted, not left as commented or orphaned branches
- large modules are decomposed into testable units with clear boundaries
- release gates are green and trusted

## Current Repo Reality

Observed on 2026-03-23:

- `git status --short` returns `294` changed paths, so cleanup must start with a
  freeze and inventory, not blind deletion.
- The repo currently contains about `475` Dart source files, `213` test files,
  `136` SQL migrations, and `52` Supabase Edge Function files.
- Local build tooling is noisy: `.dart_tool/` alone is about `653M` in the
  working copy.
- A tracked secret-adjacent file exists: `android/upload-keystore.jks.bak`.
- Dev and design collateral live in the product root: `.agent/`,
  `stitch_exports/`, local logs, and local output directories.
- Static web surfaces are split across `hosting/`, `landing/`, and
  `deeplinks/`.
- Some web pages are exact duplicates:
  `hosting/privacy/index.html` == `landing/privacy/index.html`,
  `hosting/terms/index.html` == `landing/terms/index.html`,
  `hosting/account-deletion/index.html` == `landing/account-deletion/index.html`.
- Theme migration drift is active: `AppColors` and `CoolPalette` still appear
  `292` times across `lib/` and `test/`.
- `part` coupling is widespread: `62` `part` / `part of` declarations currently
  tie screens, controllers, widgets, and repositories together.

## Production End State

The final repo should follow these rules:

1. No tracked secrets, backups, or local credential artifacts.
2. No tracked local logs, generated exports, or design tool output.
3. One authoritative static web surface for legal/support pages.
4. One authoritative deep-link surface generated from release metadata.
5. No deprecated theme APIs used by runtime code.
6. No "god" screens, repositories, or services over the agreed file-size
   budget unless explicitly justified.
7. No dead feature files left behind after refactors.
8. CI is the enforcement layer, not human memory.

## Workstreams

### Phase 0: Freeze And Triage

Goal:
Stop drift and create a safe cleanup baseline.

Tasks:

1. Create a dedicated cleanup branch from the intended production base.
2. Snapshot the current dirty state and classify all `294` changed paths into:
   product changes, cleanup candidates, generated artifacts, local-only files,
   and unresolved conflicts.
3. Block new feature work from landing without tests and doc updates.
4. Create a keep/delete/archive/migrate ledger for every non-runtime root path.

Exit criteria:

- every changed path has an owner and disposition
- no one is deleting files without classification

### Phase 1: Security And Secret Hygiene

Goal:
Remove immediate release and compliance risk before structural refactors.

Immediate blockers:

1. Remove `android/upload-keystore.jks.bak` from Git history and rotate the key
   if it contains real signing material.
2. Confirm `output/play_store/play-store-sa-key.json` is not tracked and move
   that workflow to a secure external secret store only.
3. Verify no tracked `.env`, `.env.json`, Firebase config, or signing material
   remains outside approved templates.
4. Add a CI guard that fails on `*.jks`, `*.keystore`, service-account JSON,
   `.env`, and backup suffixes such as `.bak`, `.old`, `.orig`.

Exit criteria:

- no tracked credentials, keystores, or key backups remain
- secret scanning is part of CI

### Phase 2: Root Hygiene And Artifact Eviction

Goal:
Get the repo root down to product source, durable docs, and build tooling.

Delete from the product repo:

- local logs such as `firebase-debug.log` and `flutter_*.log`
- Kotlin local error logs under `android/.kotlin/errors/`
- `stitch_exports/`
- any transient output folders used only for local release handling

Move out of the product repo or isolate under non-production tooling:

- `.agent/skills/`
- design exports and prompt engineering assets
- ad hoc output payloads used only by a local operator

Keep, but tighten:

- `scripts/`
- `tool/`
- `docs/`

Required changes:

1. Expand `.gitignore` guards for local exports and backups if anything slips
   through today.
2. Add a `make clean-local` or repo script that removes logs, temp output, and
   design exports from a working tree.
3. Document which root folders are production-owned versus local/operator-only.

Exit criteria:

- the root no longer mixes runtime code with local design or operator output
- local clones can be cleaned to a deterministic baseline in one command

### Phase 3: Static Web Consolidation

Goal:
Remove duplicate public web pages and assign one source of truth.

Current problem:

- `hosting/` and `landing/` both carry privacy, terms, and account-deletion
  pages.
- `deeplinks/` is separate and also has hosted metadata and fallback pages.

Recommended target:

1. Keep `deeplinks/` as the only deep-link and `.well-known` release surface.
2. Collapse legal/support pages into one static site surface.
3. Generate shared legal pages from one template or shared content source.
4. Remove duplicate copies after route parity is confirmed.

Suggested final ownership:

- `site/` or `hosting/`: public landing + legal + account deletion
- `deeplinks/`: link association metadata and app install/deeplink fallback only

Exit criteria:

- privacy, terms, and account deletion each exist in one authoritative source
- assetlinks/AASA generation is automated from release metadata

### Phase 4: Flutter Runtime Decomposition

Goal:
Turn the app surface from large coupled files into maintainable feature units.

Priority hotspots by size:

- `lib/features/admin/screens/operational_dashboard_screen.dart` (`1730` lines)
- `lib/features/partners/rayon/screens/rayon_home_screen.dart` (`1428` lines)
- `lib/features/momo/services/momo_statement_export_service.dart` (`1384`
  lines)
- `lib/features/admin/repositories/admin_repository.dart` (`1060` lines)
- `lib/features/partners/rayon/widgets/support_detail_parts.dart` (`1089`
  lines)
- `lib/features/partners/rayon/widgets/shop_checkout_parts.dart` (`1009`
  lines)
- `lib/shared/widgets/qr_scanner_screen.dart` (`971` lines)
- `lib/core/router/app_router.dart` (`903` lines)

Refactor rules:

1. Replace `part`-based screen/controller/widget coupling with explicit private
   widgets, small view models, and injected services.
2. Split screen composition from orchestration logic.
3. Split repositories by bounded context, not by UI page.
4. Remove deprecated theme APIs as part of each touched module.
5. Delete dead files immediately after replacement lands.

Recommended decomposition order:

1. Router and cross-cutting theme cleanup.
2. Admin domain.
3. Rayon/partners domain.
4. MoMo domain.
5. Shared widgets with high coupling.

Exit criteria:

- no runtime file exceeds the agreed complexity budget without explicit waiver
- `part` usage is limited to tightly scoped model families only
- deprecated theme APIs are gone from runtime code

### Phase 5: Backend Surface Cleanup

Goal:
Make the Supabase layer production-maintainable and auditable.

Current pressure points:

- `136` SQL migrations with large seed/demo and repair scripts mixed into the
  main history
- very large function units such as
  `supabase/functions/parse-momo-sms/reconciliation.ts` (`1139` lines) and
  `supabase/functions/wallet-issuer/index.ts` (`1119` lines)
- mock/demo seed migrations mixed near production contracts

Tasks:

1. Separate baseline schema, production contract migrations, demo seed data,
   and emergency repair migrations.
2. Archive one-off demo seed SQL that should not stay in the active production
   chain.
3. Introduce a migration catalog that labels each migration as schema, data,
   seed, repair, or hardening.
4. Split oversized Edge Functions into handler, validation, domain logic, and
   shared adapter layers.
5. Add regression checks for migration ordering and idempotent repair scripts.

Exit criteria:

- migrations are classifiable and explainable
- mock/demo seed paths do not pollute production deploy reasoning
- large Edge Functions are decomposed into testable modules

### Phase 6: Docs And Archive Discipline

Goal:
Keep only current, durable docs in the main docs surface.

Current issue:

- `docs/` already holds `26` Markdown files, including multiple dated audit and
  remediation plans.

Tasks:

1. Split docs into `current/` versus `archive/` semantics, either physically or
   by naming convention.
2. Keep a small set of evergreen documents at the top level:
   `README.md`, release process, permissions, production architecture, and the
   latest active remediation/cleanup plan.
3. Archive superseded dated plans and audit snapshots after their actions are
   absorbed.
4. Ensure generated docs such as route inventory remain machine-produced and not
   hand-edited.

Exit criteria:

- docs explain the current system without forcing readers through stale plans
- historical audits are preserved but clearly non-authoritative

### Phase 7: Production Gate Hardening

Goal:
Make the repo self-defending.

Existing strength:

- CI and release scripts already exist in `.github/workflows/` and
  `scripts/release_readiness.sh`.

Additions needed:

1. secret/binary/backup file scan
2. duplicate legal page ownership check
3. dead-file detection for replaced modules
4. analyzer budget for deprecated theme APIs
5. size budget checks for large Dart and TypeScript files
6. migration classification check
7. docs archive/current structure check

Exit criteria:

- a PR cannot reintroduce the clutter this cleanup removes

## Keep / Delete / Migrate Matrix

Delete now or remove from Git:

- `android/upload-keystore.jks.bak`
- local log files
- local Kotlin error logs
- `stitch_exports/`

Move out of the product repo:

- `.agent/skills/`
- local release output payloads
- design exports and prompt assets that are not runtime or governance inputs

Consolidate before deleting:

- `hosting/privacy/index.html`
- `landing/privacy/index.html`
- `hosting/terms/index.html`
- `landing/terms/index.html`
- `hosting/account-deletion/index.html`
- `landing/account-deletion/index.html`

Keep as production-owned:

- `lib/`
- `supabase/`
- `assets/`
- `scripts/`
- `tool/`
- `test/`
- `integration_test/`
- whichever single public web surface survives consolidation
- `deeplinks/`, if retained as the sole deep-link metadata surface

## Delivery Shape

Recommended sequence of PRs:

1. Freeze + inventory + secret remediation
2. Root artifact cleanup
3. Static web consolidation
4. Theme migration and deprecated API removal
5. Router and app shell decomposition
6. Admin domain split
7. Partners/Rayon domain split
8. MoMo domain split
9. Supabase migration/function cleanup
10. Docs archive and CI hardening

Do not combine all of this into one branch. The repo is already too noisy for
that to review safely.

## Definition Of Done

The repo is ready for a production tag only when all of the following are true:

- working tree is clean from the chosen release branch
- no tracked secret, backup, or local artifact remains
- duplicate public pages are removed or generated from one source
- `flutter analyze --fatal-infos` passes
- Flutter unit, widget, and integration smoke tests pass
- Deno type-check and function tests pass
- release readiness passes
- docs clearly distinguish current guidance from archived investigations
- the next engineer can explain the repo layout in five minutes without caveats
