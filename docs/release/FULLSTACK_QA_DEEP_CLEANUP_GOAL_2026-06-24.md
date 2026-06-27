# Fullstack QA and Deep Cleanup Goal - 2026-06-24

## Objective

Bring the COOL repository to a defensible fullstack QA and cleanup state: active app code only, verified navigation and interface behavior, accessible and responsive mobile surfaces, premium Collect-owned visual quality, current security hygiene, clean generated-artifact boundaries, and honest release/governance blockers.

## Non-Negotiable Outcome

- Keep only actively used production source, tests, release gates, migrations, assets, and current operating evidence in the repo.
- Remove or quarantine dead, duplicate, generated, archived, stale, misleading, or redundant material only after reference scans prove it is not active.
- Preserve release safety gates, signing checks, UAT approvals, and evidence redaction. Do not weaken a gate to turn a red status green.
- Separate code-owned blockers from delegated release-owner execution, Play Console, signing, device, and governance blockers.
- Validate with the pinned toolchain: `/Volumes/PRO-G40/flutter_3_44/bin/flutter` and `/Volumes/PRO-G40/flutter_3_44/bin/dart`.

## Workstreams

### 1. Repository Inventory

- Run the repo inventory and record counts for Dart files, tests, scripts, docs, native files, Supabase functions, and migrations.
- Confirm generated folders such as `build/`, `.cache/`, `.dart_tool/`, and `output/` are not tracked.
- Treat forward-only database migrations, release approvals, and signed governance evidence as retained unless a repo owner approves an external archive.

### 2. Active Code Reachability

- Confirm retained Dart files are reachable from `lib/main.dart`, `lib/main_admin.dart`, `lib/main_public.dart`, tests, tooling, or documented integration surfaces.
- Remove dead widgets, placeholders, and duplicated helper APIs only when app/test/doc scans show no active references.
- Keep public barrels stable when moving implementations into focused files.

### 3. Navigation and Interface QA

- Verify member app route registration and unknown-route recovery.
- Run mobile route render smoke for all production routes at compact viewport.
- Verify Admin PWA routing, manifest, hosting, live deployment, and render smoke separately.
- Keep public website routes and Admin PWA routes out of member-app navigation contracts.

### 4. Accessibility and Responsiveness

- Verify semantic labels on non-text controls, large-text behavior, compact viewport rendering, and no color-only status dependence.
- Keep 200 percent text-scale widget tests for payment, profile, home, completion, and shared components.
- Preserve reduced-motion behavior and stable fixed-format UI dimensions.

### 5. Performance and Premium Quality

- Verify public website JS budget, security headers, sitemap, metadata, no Flutter/CanvasKit critical-path files, and public claim guard.
- Verify mobile visual contracts: Collect-owned color tokens, gradient/glass surfaces, brand wordmark, launch splash resources, top chrome, and route screenshot evidence.
- Keep Collect product copy and visual assets distinct from reference-product trademarks.

### 6. Security, Privacy, and Compliance

- Run tracked-file secret scans and product-boundary scans.
- Keep raw SMS, OTP, signing keys, service-role values, receiver private data, and customer data out of logs, docs, and evidence bundles.
- Preserve fail-closed release gates for UAT evidence, UAT signoff, release owner decision, Android signing, artifact freshness, and Supabase/go-live status.

### 7. Release and Device Gates

- Build APK/AAB only with the approved Play/original signing key.
- Keep Android signing fingerprint mismatch as a hard blocker.
- Run device UAT only after signing/build prerequisites are satisfied.
- Regenerate release artifact manifests and checksums after the final successful build.

## Implementation Plan

1. Capture baseline inventory and current worktree status.
2. Run analyzer, focused tests, public website build/quality gate, route render smoke, Admin PWA gates, secret scan, and product-boundary scan.
3. Fix code-owned findings without weakening release/governance checks.
4. Add or update tests/scripts/docs for every source ownership boundary changed.
5. Run focused validation again after fixes.
6. Write the final report with pass/fail evidence, remaining blockers, and the next cleanup/remediation path.

## Success Criteria

- Formatter and analyzer pass.
- Focused app shell, design-system, accessibility/responsiveness, and security tests pass.
- Public website quality gate passes.
- Mobile route render smoke passes for all production routes.
- Admin PWA build, hosting, live, and render gates pass.
- Design compliance source checks pass.
- Any remaining red gates are documented with exact blocker keys and are not caused by avoidable code-owned regressions.

## Current Implementation Result

The first implementation pass is documented in `docs/release/FULLSTACK_QA_DEEP_CLEANUP_REPORT_2026-06-24.md`.

Code-owned fixes completed:

- Formatter drift removed from `test/features/design_system_components_test.dart`.
- Design compliance audit updated to read Dart part files for the refactored `collect_chrome.dart` library.
- Local pinned Flutter checkout aligned to `.fvmrc`: `/Volumes/PRO-G40/flutter_3_44` now reports Flutter `3.44.3` and Dart `3.12.2`.

Remaining blockers:

- Android signing fingerprint mismatch blocks APK/AAB builds and device UAT.
- Human UAT persona signoffs and release owner decision remain incomplete.
- Release artifact manifest and mobile release gate remain blocked until APK/AAB artifacts are rebuilt with the correct signing key.
