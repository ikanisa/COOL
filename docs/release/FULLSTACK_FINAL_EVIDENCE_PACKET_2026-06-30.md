# Fullstack Final Evidence Packet - 2026-06-30

## Decision Summary

This packet records the current COOL fullstack audit, cleanup, refactor,
mobile-quality, backend/Supabase, dependency/supply-chain, performance, Admin
PWA, Android release, and final release-gate evidence.

Current automated release status:

- `scripts/release_status.sh --json`: `GO`
- `scripts/release_artifact_manifest.sh --json`: `pass`
- `scripts/flutter_mobile_release_gate.sh --json`: `pass`
- `scripts/supabase_go_live_gate.sh --json`: `NO-GO`
- `scripts/native_mobile_accessibility_signoff_gate.sh --json`: `NO-GO`

The top-level mobile release artifacts are current. Stripe launch scope is
deferred per release-owner direction on 2026-06-30. Linked Supabase production
readiness and Supabase go-live now pass after setting
`PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON`. Full production go-live is still not
complete because native accessibility signoff remains approval-gated.

## Evidence Matrix

| Area | Command / Artifact | Status | Evidence |
| --- | --- | --- | --- |
| Audit tracker | `docs/release/FULLSTACK_REPO_AUDIT_CLEANUP_2026-06-30.md` | Pass | Current audit tracker and remediation notes |
| Architecture map | `docs/release/FULLSTACK_ARCHITECTURE_MAP_AND_REMEDIATION_PLAN_2026-06-30.md` | Pass | Current architecture/remediation map |
| Formatting | `/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed .` | Pass | 181 files checked, 0 changed |
| Analyzer | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` | Pass | No issues found |
| Full tests | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub` | Pass | 293 tests passed; 1 expected opt-in route evidence skip |
| Whitespace | `git diff --check` | Pass | No whitespace errors |
| Secret scan | `scripts/release_secret_scan.sh` | Pass | Fallback tracked-file scan passed; `gitleaks` not installed |
| YAML governance | `ruby -e 'require "yaml"; ... YAML.load_file(...)'` | Pass | Workflows and Dependabot config parse locally |
| Dependency drift | `flutter pub outdated --json` | Pass | `docs/release/flutter_pub_outdated_2026-06-30.json` |
| Kotlin plugin compatibility | `scripts/android_kotlin_plugin_compat_gate.sh --json` | Warning | `docs/release/android_kotlin_plugin_compat_2026-06-30.json`; five plugins still apply KGP directly |
| Dependabot governance | `.github/dependabot.yml` | Added | GitHub Actions, Pub, and Android Gradle weekly update coverage |
| CodeQL governance | `.github/workflows/codeql.yml` | Added | Supabase TypeScript Edge Function analysis |
| Backend contracts | `flutter test --no-pub test/supabase_contract_test.dart` | Pass | 43/43 backend contract tests |
| Edge auth contracts | `scripts/collect_edge_auth_contract_uat.sh` | Pass | Stripe, webhook, SMS, notification, and Play Integrity functions covered |
| Supabase advisors | `scripts/supabase_advisors_gate.sh` | Pass | Linked security/performance advisors have no error-level issues |
| Supabase migration apply | Linked SQL fallback after direct `db push` allow-list failure | Pass | `docs/release/supabase_manual_migration_apply_2026-06-30.json`; remote migration history now contains `20260627191000` |
| Supabase Edge Function deploy | Configured deployment loop from `scripts/supabase_deploy.sh` | Pass | `docs/release/supabase_functions_deploy_2026-06-30_after_manual_db_apply_retry.txt`; all ten configured functions deployed |
| Supabase schema inventory | `scripts/supabase_schema_inventory.sh --json` | Pass | `docs/release/supabase_schema_inventory_2026-06-30_latest.json`; expected 183, remote 183, missing 0 |
| Supabase production readiness | `scripts/supabase_production_readiness.sh` | Pass | `docs/release/supabase_production_readiness_2026-06-30_latest.txt`; Stripe secrets deferred for current scope |
| Supabase go-live | `scripts/supabase_go_live_gate.sh --json` | Pass / GO | `docs/release/supabase_go_live_gate_2026-06-30_latest.json` |
| Supabase evidence bundle | `SUPABASE_EVIDENCE_BUNDLE_DIR=.cache/supabase_go_live_evidence/20260630T_after_db_push scripts/supabase_go_live_evidence_bundle.sh` | Blocked | `.cache/supabase_go_live_evidence/20260630T_after_db_push/summary.json` |
| Mobile route render | `scripts/mobile_route_render_smoke.sh` | Pass | `.cache/mobile_route_render_smoke/20260630T160720Z/summary.json` |
| Android device UAT | `COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false scripts/android_device_uat.sh` | Pass | `.cache/android_device_uat/20260630T162322Z_upload_key_debug/summary.json` |
| Mobile contract compliance | `scripts/universal_contract_audit.sh --json` with fresh route/UAT summaries | Pass | Current gate plus `DESIGN.md`; stale dated JSON removed |
| Android structural accessibility | `scripts/android_accessibility_structural_evidence.sh --json` | Pass | `docs/release/android_accessibility_structural_evidence_2026-06-30.json` |
| Native performance | `scripts/mobile_native_performance_profile.sh --json` | Pass | `docs/release/mobile_native_performance_profile_2026-06-30.json` |
| Native accessibility signoff | `scripts/native_mobile_accessibility_signoff_gate.sh --json` | Blocked | `docs/release/native_mobile_accessibility_signoff_gate_2026-06-30.json` |
| Admin PWA build | `scripts/admin_pwa_release_build.sh` | Pass | `docs/release/admin_pwa_release_build_2026-06-30.txt` |
| Admin PWA manifest | `scripts/admin_pwa_manifest_gate.sh` | Pass | `docs/release/admin_pwa_manifest_gate_2026-06-30.txt` |
| Admin PWA hosting | `scripts/admin_pwa_hosting_gate.sh --json` | Pass | `docs/release/admin_pwa_hosting_gate_2026-06-30.json` |
| Admin PWA render | `scripts/admin_pwa_render_smoke.sh` | Pass | `.cache/admin_pwa_render_smoke/20260630T164238Z/summary.json` |
| Admin PWA live | `ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com scripts/admin_pwa_live_gate.sh --json` | Pass | `docs/release/admin_pwa_live_gate_2026-06-30_latest.json` |
| Android release build | Direct Gradle `assembleProductionRelease` and `bundleProductionRelease` | Pass | `docs/release/android_release_gradle_build_2026-06-30.txt` |
| Android signing preflight | `scripts/android_release_signing_preflight.sh --json` | Pass | `docs/release/android_release_signing_preflight_2026-06-30_latest.json` |
| Release artifact manifest | `scripts/release_artifact_manifest.sh --json` | Pass | `docs/release/release_artifact_manifest_2026-06-30_latest.json` |
| Mobile release gate | `scripts/flutter_mobile_release_gate.sh --json` | Pass | `docs/release/flutter_mobile_release_gate_2026-06-30_latest.json` |
| Release status | `scripts/release_status.sh --json` | Pass / GO | `docs/release/release_status_2026-06-30_latest.json` |

## Release Artifacts

Checksum manifest:

`output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-06-30.sha256`

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `build/app/outputs/flutter-apk/app-production-release.apk` | 88042219 | `2b5aa6744e39486e6adca146083fd0afbd34d610c31c88eb9b9d29a02fc9285f` |
| `build/app/outputs/bundle/productionRelease/app-production-release.aab` | 78758629 | `9901beb31482bc54f7747cacc92107e288cca6a0580b12ba8d5ece4c163441e8` |
| `build/web/index.html` | 706 | `19e613a31813d8bc8c01f06735aa2c187098f761edff83f3043e0ece2192504d` |
| `build/web/flutter_bootstrap.js` | 10123 | `ac253a68d5b4fd72715423516e45e783f5bc1a5d497bbbde0368078456a19878` |
| `build/web/main.dart.js` | 3181082 | `18ad6b5b18e161ba96fe4b6a270347fcccbc52d5c8714a46636f1a15647225dc` |
| `build/web/manifest.json` | 407 | `8ca66c797a54c3d6d69ffa667d353b9aca6fa053a2c20261e271958e33dcd616` |
| `build/web/custom-sw.js` | 5115 | `5ee8320a65d902eb4e317f7866d2cbde475f50dec21afeb1434020e8d04937e3` |
| `build/web/icons/collect-admin.png` | 92022 | `cae23ce3562e8aac2e248e7b22f7feed194f4fcfd2b57725ec1026f064bb0ad9` |
| `build/web/_headers` | 1450 | `57933e212c336a836cef0e2aa25572f6c28db32f5ed6ff74dc25110688f16977` |
| `build/web/robots.txt` | 26 | `331ea9090db0c9f6f597bd9840fd5b171830f6e0b3ba1cb24dfa91f0c95aedc1` |

## Remaining Approval Gates

| Gate | Owner | Required action |
| --- | --- | --- |
| `codex_native_mobile_accessibility_responsibility` | Codex | Codex owns Android, iOS scope, and final native accessibility responsibility through `docs/release/NATIVE_MOBILE_ACCESSIBILITY_SIGNOFF_CHECKLIST_2026-06-30.md`; verify with `scripts/native_mobile_accessibility_signoff_gate.sh --json` |
| External submission | Release owner | No Google Play, App Store, production deploy, or external professional submission without explicit recorded human approval |

## Current Release Interpretation

The local mobile/Admin release artifact path is green. The approved Supabase
migration, Edge Function deploy, Play Integrity secret trial, and Supabase
go-live gate are complete. The full production release path remains gated until
native accessibility signoff is explicitly recorded and revalidated.
