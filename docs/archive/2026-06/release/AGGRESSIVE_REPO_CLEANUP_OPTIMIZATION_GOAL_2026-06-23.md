# Aggressive Repo Cleanup and Optimization Goal - 2026-06-23

## Objective

Crank the COOL repository down to actively used, production-relevant code and assets only. Remove dead, duplicated, archived, generated, redundant, stale, or misleading material. Refactor active code that is too large, poorly grouped, hard to test, or harmful to UI/UX iteration speed. Keep the product behavior intact through evidence-backed checks, not assumptions.

## Non-Negotiable Outcome

- Every retained Dart source file must be reachable from an app entrypoint, imported by a verified test/tooling contract, or explicitly documented as an intentionally retained integration surface.
- Every retained script must have a current caller, CI/release role, documented manual operation, or replacement plan.
- Every retained doc must be current product, architecture, operations, compliance, or release-decision evidence. Historical/generated evidence must leave active source paths unless governance requires retention.
- Every retained asset must be referenced by source, native config, public web output, release metadata, or an active design/test contract.
- Oversized active modules must be split by product route group, component family, data boundary, or admin workflow until files are small enough to review and test without carrying unrelated behavior.

## Aggressive Cleanup Rules

1. Delete when reference scans, route scans, tests, and release docs show no active use.
2. Refactor when a file is active but combines unrelated route groups, UI components, business rules, or evidence generation.
3. Move generated output to ignored `output/`, `.cache/`, or `build/` paths. Do not keep generated screenshots, Lighthouse JSON, checksums, or browser evidence under active docs unless explicitly approved.
4. Keep forward-only database migrations, release approvals, signoff evidence, Play Integrity integration surfaces, and native platform resource variants unless a stronger product/governance reason exists.
5. Update tests and docs in the same pass when the source ownership boundary moves.
6. Use the pinned toolchain only: `/Volumes/PRO-G40/flutter_3_44/bin/flutter` and `/Volumes/PRO-G40/flutter_3_44/bin/dart`.

## Workstreams

### 1. Active Code Reachability

- Maintain a Dart reachability inventory from `lib/main.dart`, `lib/main_admin.dart`, and `lib/main_public.dart`.
- Remove unreachable files unless they are intentionally retained integration surfaces.
- Current retained exception: `lib/core/security/play_integrity_service.dart`, because tests, native Android, Supabase, and Google Play readiness docs lock that surface.

### 2. Shared UI and UX Component Optimization

- Continue splitting `lib/shared/widgets/collect_components.dart` by component family.
- Keep the public barrel stable while moving implementation into focused files.
- Remove unused widgets after exact app/test/doc reference scans.
- Preserve accessibility labels, large-text behavior, stable dimensions, and route-level UI tests.

### 3. Feature and Route Module Structure

- Keep route groups in feature-local files instead of monolith route dumps.
- Continue the completed status-screen split pattern for other large feature files.
- Move real branching and reusable decisions into view-model/state helpers only where it reduces widget complexity.
- Preserve Riverpod and the existing repository pattern; do not introduce another state framework.

### 4. Admin Runtime Reduction

- Reduce `lib/admin/core/admin_runtime.dart` by extracting focused admin operation helpers, view models, and data-shaping utilities.
- Keep permission, sensitive-data, and role checks explicit and test-covered.
- Do not weaken admin PWA security or evidence-mode boundaries.

### 5. Scripts and Release Gates

- Classify scripts as active CI/release gate, manual operation, evidence generator, superseded, or obsolete.
- Move scripts into purpose folders after reference scans are complete.
- Remove superseded scripts only after docs/tests/CI references are updated.

### 6. Docs and Evidence Hygiene

- Keep active docs focused on current architecture, release status, public website status, Play readiness, Supabase operations, privacy/compliance, and current audit reports.
- Move or delete generated dated evidence bundles from tracked active docs.
- Keep narrative historical docs only when they explain current decisions.

### 7. Assets and Native Resource Review

- Scan assets and native resources for source references, generated output references, and platform requirements.
- Remove duplicate/generated design evidence from active docs.
- Keep native density/resource variants when Android/iOS requires them even if hashes look duplicate.

## Required Proof Gates

Run the relevant subset after each batch, and the full set before claiming the goal complete:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/security_hygiene_test.dart
bash scripts/public_landing_prepare_build.sh
./scripts/public_website_quality_gate.sh --json
```

Before any release/go-live claim, also run the repo-wide release/UAT harness and report remaining blockers separately from code-owned proof.

## Completion Definition

This goal is complete only when:

- Active Dart reachability has no unexplained orphan files.
- Dead shared widgets/components are removed or documented as active.
- Oversized monoliths have been split until each file has one clear responsibility.
- Generated output is absent from active tracked source paths.
- Script/doc/asset inventories have active ownership labels or removal decisions.
- Analyzer and focused test gates pass.
- The cleanup audit report states exactly what was removed, what was refactored, what remains intentionally retained, and what still needs product/governance approval.

## Current Next Batch

1. Continue splitting `lib/shared/widgets/collect_components.dart` by component family.
2. Reduce `lib/admin/core/admin_runtime.dart` by extracting admin workflow helpers.
3. Add or harden route/user-journey manifest coverage for mobile, admin, and public website surfaces.
4. Classify scripts and docs into active, generated, historical, superseded, and removable.
