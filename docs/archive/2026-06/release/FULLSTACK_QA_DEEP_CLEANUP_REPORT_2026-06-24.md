# Fullstack QA and Deep Cleanup Report - 2026-06-24

## Scope

This pass reviewed the active Flutter mobile app, Admin PWA, public website, Supabase/release gates, route rendering, accessibility and responsiveness contracts, performance-oriented web checks, security hygiene, repository cleanliness, and active-code cleanup state.

Goal file: `docs/release/FULLSTACK_QA_DEEP_CLEANUP_GOAL_2026-06-24.md`.

Primary evidence bundle: `.cache/repo_wide_qa_uat/20260623T202930Z`.

## Current Verdict

Code-owned QA is mostly green, but the full release/UAT decision remains `FAIL / NO-GO`.

The remaining hard blockers are not dead-code findings. They are release-signing and human-governance gates:

- Android APK/AAB and Android device UAT fail because the configured local signing certificate SHA-256 is `9EE12172C78A8A487906D9159BFDD17B4D78ABA3541F17B410659E6D60DDCC10`, while the guarded expected Play app-signing SHA-256 is `451738E69ADF1B4D3FAA7A659020282E027B47862671C9FC3245AF822B4D2A92`.
- Human UAT evidence and signoff remain blocked: release owner details are missing, release owner decision is not `GO`, and UAT-01 through UAT-10 are still unsigned and have no accepted evidence files in the manifest.
- Release artifact manifest and mobile release gate remain blocked because current Android APK/AAB artifacts were not produced.

## Findings Fixed In This Pass

- Fixed Dart formatter drift in `test/features/runtime_component_contract_test.dart`.
- Fixed `scripts/universal_contract_audit.sh` so the contract audit reads `collect_chrome.dart` plus declared Dart part files. The previous audit only read the barrel file, so it falsely reported that `PremiumScaffold` and `CollectBrandMark` were missing after the recent refactor moved them into `collect_scaffold_chrome.dart` and `collect_top_chrome.dart`.
- Aligned the local pinned Flutter checkout at `/Volumes/PRO-G40/flutter_3_44` with `.fvmrc`: Flutter `3.44.3`, Dart `3.12.2`. The checkout is intentionally detached at the exact `3.44.3` release tag for reproducible validation.

## QA Evidence

- `bash scripts/full_repo_audit_inventory.sh`: pass. Current inventory: 153 library Dart files, 17 Dart tests, 75 scripts, 77 docs, 126 native/platform files, 14 Supabase functions, and 42 Supabase migrations.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass.
- Focused Flutter QA batch: pass, 132 tests passed, 1 route evidence test intentionally skipped because `COLLECT_VISUAL_EVIDENCE_DIR` was not set.
- Post-toolchain alignment focused Flutter QA batch: pass, 59 tests passed across `test/features/mobile_completion_test.dart`, `test/app_shell_test.dart`, `test/security_hygiene_test.dart`, and `test/shared/collect_repository_test.dart`.
- `bash scripts/public_landing_prepare_build.sh`: pass.
- `./scripts/public_website_quality_gate.sh --json`: pass, 34/34 checks passed. Routes, metadata, sitemap, JS budget, security headers, and public claim guard all passed.
- Post-toolchain alignment `./scripts/public_website_quality_gate.sh --json`: pass, 34/34 checks passed.
- `./scripts/release_secret_scan.sh`: pass with tracked-file fallback scanner.
- `git diff --check`: pass.
- `./scripts/repo_wide_qa_uat.sh --json`: fail as expected from release gates. Passing surfaces included Flutter tests, secret scan, product-boundary scan, Admin PWA build/manifest/hosting/live/render smoke, and mobile route render smoke.
- Mobile route render smoke: pass, 58 compact-viewport route screenshots generated and validated.
- Admin PWA live deployment gate: pass.
- Post-fix contract compliance rerun: all source/design checks pass, including gradient/glass, brand asset, semantic palette, route screenshots, and raw UI color checks. The only remaining contract compliance failure is `android_device_uat_evidence`, inherited from the Android signing guard failure.
- Android APK/AAB release builds: fail at signing fingerprint guard.
- Android device UAT: fail at the same signing fingerprint guard.
- Release status and go-live gates: `NO-GO`, blocker key `android_release_artifacts`.

## Cleanup State

The repository does not currently show a broad active-Dart dead-file problem. The prior cleanup baseline already split the largest monoliths and removed unused placeholders/widgets. Current active source weight is concentrated in real app modules, tests, release gates, and governance evidence.

The local generated footprint is not tracked, but running QA creates ignored `build/`, `.dart_tool/`, and `.cache/` output. These should continue to be treated as disposable local evidence/build artifacts, not source.

## Cleanup Plan

1. Release-signing remediation: point `android/key.properties` or `COOL_ANDROID_*` environment values at the approved Play/original release key, then rebuild APK/AAB and rerun `scripts/flutter_mobile_release_gate.sh --json`.
2. Rerun repo-wide QA after signing is corrected: `./scripts/repo_wide_qa_uat.sh --json`, then confirm `summary.json`, `evidence_index.json`, and `commands.tsv`.
3. Close human UAT governance separately: record valid persona evidence for UAT-01 through UAT-10, release owner, signed timestamps, evidence files, and final owner decision. Do not fake these in code.
4. Continue active cleanup by inventory category:
   - Dart: keep only files reachable from `lib/main.dart`, `lib/main_admin.dart`, `lib/main_public.dart`, tests, or documented integration surfaces.
   - Scripts: classify each as CI/release gate, manual operation, evidence generator, superseded, or removable before deletion.
   - Docs: keep current architecture, operations, compliance, release status, and decision evidence; move historical generated evidence out of active docs only after owner approval.
   - Assets: retain only assets referenced by source, native config, public web output, release metadata, or active tests.
5. After each cleanup batch, run the pinned gates from `docs/release/AGGRESSIVE_REPO_CLEANUP_OPTIMIZATION_GOAL_2026-06-23.md` before claiming completion.
