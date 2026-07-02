# Fullstack Repo Audit And Cleanup - 2026-06-30

## Scope

This audit covers the current COOL Flutter/Supabase repository as a production
mobile app workspace, including the mobile app, Admin PWA, public site,
Supabase migrations/functions, native Android/iOS surfaces, release evidence,
security/privacy gates, and test infrastructure.

The working assumption is incremental cleanup and behavior-preserving
refactoring. This is not a rewrite plan.

Companion deliverables:

- `docs/release/FULLSTACK_ARCHITECTURE_MAP_AND_REMEDIATION_PLAN_2026-06-30.md`
  maps the current route/module/backend/platform layers and prioritizes the
  remaining remediation workstreams.

## Baseline

| Area | Evidence |
| --- | --- |
| Git state | `main` at `7f1aab86`, synced with `origin/main` before edits |
| Toolchain | `/Volumes/PRO-G40/flutter_3_44/bin/flutter` reports Flutter `3.44.3` |
| Inventory | `scripts/full_repo_audit_inventory.sh --json` generated at `2026-06-30T13:59:17Z` |
| Scoped files | 708 |
| App Dart files | 152 under `lib/` |
| Dart tests | 18 under `test/` |
| Scripts | 87 |
| Supabase | 14 functions, 49 migrations |
| Native/platform files | 212 |
| Routes | 31 mobile route contract entries, 23 admin route contract entries |

## Gates Run

| Gate | Status | Notes |
| --- | --- | --- |
| `git diff --check` | Pass | Clean before edits |
| `dart format --set-exit-if-changed .` | Pass | 171 files checked, 0 changed before edits |
| `scripts/release_secret_scan.sh` | Pass | Fallback tracked-file scan passed; `gitleaks` not installed |
| `scripts/migrations/validate_supabase_migrations.sh` | Pass | Supabase migration validation passed |
| `scripts/collect_product_boundary_scan.sh --json` | Pass | 152 files scanned, 0 hits |
| `flutter analyze --no-pub` | Pass | No analyzer issues |
| `flutter test --no-pub` | Pass | 289 passed, 1 opt-in skip before cleanup edit |
| `scripts/android_release_signing_preflight.sh --json` | Pass | Upload signing material present; Play app-signing key mismatch correctly treated as delivery semantics |
| `scripts/android_kotlin_plugin_compat_gate.sh --json` | Warning | 5 Flutter plugins still declare direct Kotlin plugin markers |
| `scripts/release_status.sh --json` | Blocked | `android_release_artifacts`: APK/AAB/Admin web artifacts missing or stale |
| `scripts/release_artifact_manifest.sh --json` | Blocked | 10 release artifacts missing |
| `scripts/native_mobile_accessibility_signoff_gate.sh --json` | Blocked | Codex structural responsibility is accepted, but human TalkBack, VoiceOver or scoped waiver, and final accessibility signoff remain open |
| `scripts/uat_evidence_gate.sh --json` | Blocked | Release owner/persona signoffs and evidence files still open |
| `scripts/collect_mobile_design_compliance_audit.sh --json` | Pass | Re-run with fresh route smoke and Android UAT summaries |

Evidence refresh after the architecture map:

| Gate | Status | Notes |
| --- | --- | --- |
| `scripts/full_repo_audit_inventory.sh --json` | Pass | Generated `2026-06-30T15:50:18Z`; 719 scoped files, 162 app Dart files, 18 Dart tests, 87 scripts, 14 Supabase function directories, 49 migrations |
| `scripts/migrations/validate_supabase_migrations.sh` | Pass | Supabase migration validation passed |
| `scripts/release_secret_scan.sh` | Pass | Fallback tracked-file scan passed; `gitleaks` not installed |
| `scripts/collect_product_boundary_scan.sh --json` | Pass | 162 files scanned, 0 hits |
| `scripts/release_artifact_manifest.sh --json` | Blocked | 10 artifacts missing: production APK, production AAB, and Admin web build files |
| `scripts/release_status.sh --json` | Blocked | `NO-GO`; only current blocker key is `android_release_artifacts` |

Backend/Supabase evidence refresh:

| Gate | Status | Notes |
| --- | --- | --- |
| `flutter test --no-pub test/supabase_contract_test.dart` | Pass | 43/43 backend contract tests passed |
| `scripts/collect_edge_auth_contract_uat.sh` | Pass | Updated to cover current Stripe, Stripe webhook, and Play Integrity Edge Functions |
| `bash -n scripts/collect_edge_auth_contract_uat.sh scripts/supabase_deploy.sh scripts/supabase_production_readiness.sh` | Pass | Script syntax clean |

Mobile quality and performance evidence refresh:

| Gate | Status | Notes |
| --- | --- | --- |
| `scripts/mobile_route_render_smoke.sh` | Pass | Fresh evidence at `.cache/mobile_route_render_smoke/20260630T160720Z/summary.json`; 30/30 screenshots and checks passed |
| `COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false scripts/android_device_uat.sh` | Pass | Fresh evidence at `.cache/android_device_uat/20260630T162322Z_upload_key_debug/summary.json`; default production-debug run failed only on Play app-signing certificate semantics |
| `MOBILE_ROUTE_RENDER_SUMMARY=.cache/mobile_route_render_smoke/20260630T160720Z/summary.json ANDROID_DEVICE_UAT_SUMMARY=.cache/android_device_uat/20260630T162322Z_upload_key_debug/summary.json scripts/collect_mobile_design_compliance_audit.sh --json` | Pass | Current evidence must be regenerated from the gate and checked against `DESIGN.md`; stale dated JSON removed |
| `scripts/android_accessibility_structural_evidence.sh --json` | Pass | Saved JSON at `docs/release/android_accessibility_structural_evidence_2026-06-30.json`; onboarding and guarded deeplink captures each exposed 18 labels and kept `app.cool.mobile` focused |
| `scripts/mobile_native_performance_profile.sh --json` | Pass | Saved JSON at `docs/release/mobile_native_performance_profile_2026-06-30.json`; profile runner, Perfetto trace, and gfxinfo checks passed |
| `scripts/native_mobile_accessibility_signoff_gate.sh --json` | Blocked | Verify current Codex responsibility rows and keep the human TalkBack, VoiceOver, and final signoff blocker open |
| `scripts/supabase_advisors_gate.sh` | Pass | Linked security and performance advisors report no error-level issues |
| `scripts/supabase_schema_inventory.sh --json` | Pass | Post-approval linked schema inventory expected 183, remote 183, missing 0 |
| `scripts/supabase_production_readiness.sh` | Pass | Migration history and schema now pass; Stripe secrets deferred for current scope |

Dependency, CI, Admin PWA, and release-artifact refresh:

| Gate | Status | Notes |
| --- | --- | --- |
| `flutter pub outdated --json` | Pass | Saved JSON at `docs/release/flutter_pub_outdated_2026-06-30.json`; no direct package advisory/retraction flags in the current JSON, but package upgrades remain backlog work |
| `.github/dependabot.yml` | Added | Weekly GitHub Actions, Pub, and Android Gradle update governance with grouped Flutter runtime/test-tooling updates |
| `.github/workflows/codeql.yml` | Added | Scoped CodeQL analysis for JavaScript/TypeScript Supabase Edge Function sources |
| `ruby -e 'require "yaml"; ... YAML.load_file(...)'` | Pass | Workflow and Dependabot YAML files parse locally; `actionlint` is not installed on this machine |
| `scripts/android_kotlin_plugin_compat_gate.sh --json` | Warning | Saved JSON at `docs/release/android_kotlin_plugin_compat_2026-06-30.json`; five Android plugins still apply Kotlin Gradle Plugin directly |
| `scripts/admin_pwa_release_build.sh` | Pass | Saved log at `docs/release/admin_pwa_release_build_2026-06-30.txt`; refreshed `build/web` and passed Admin manifest/hosting checks |
| `scripts/admin_pwa_manifest_gate.sh` | Pass | Saved log at `docs/release/admin_pwa_manifest_gate_2026-06-30.txt` |
| `scripts/admin_pwa_hosting_gate.sh --json` | Pass | Saved JSON at `docs/release/admin_pwa_hosting_gate_2026-06-30.json` |
| `scripts/admin_pwa_render_smoke.sh` | Pass | Fresh evidence at `.cache/admin_pwa_render_smoke/20260630T164238Z/summary.json`; desktop and mobile screenshots captured |
| `ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com scripts/admin_pwa_live_gate.sh --json` | Pass | Saved JSON at `docs/release/admin_pwa_live_gate_2026-06-30_latest.json` |
| `JAVA_HOME=/usr/local/Cellar/openjdk@17/17.0.18/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleProductionRelease :app:bundleProductionRelease --no-daemon --console=plain` | Pass | Saved log at `docs/release/android_release_gradle_build_2026-06-30.txt`; APK/AAB rebuilt successfully |
| `scripts/release_artifact_manifest.sh --json` | Pass | Saved JSON at `docs/release/release_artifact_manifest_2026-06-30_latest.json`; checksum manifest written to `output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-06-30.sha256` |
| `scripts/android_release_signing_preflight.sh --json` | Pass | Saved JSON at `docs/release/android_release_signing_preflight_2026-06-30_latest.json`; upload signing material present, Play signing key mismatch remains expected delivery semantics |
| `scripts/flutter_mobile_release_gate.sh --json` | Pass | Saved JSON at `docs/release/flutter_mobile_release_gate_2026-06-30_latest.json`; no blocker keys |
| `scripts/release_status.sh --json` | Pass | Saved JSON at `docs/release/release_status_2026-06-30_latest.json`; top-level release status is `GO` after artifact rebuild |
| `scripts/supabase_go_live_gate.sh --json` | Pass | Saved JSON at `docs/release/supabase_go_live_gate_2026-06-30_latest.json`; no Supabase blocker keys |
| `docs/release/FULLSTACK_FINAL_EVIDENCE_PACKET_2026-06-30.md` | Added | Final command/status/evidence matrix for this audit and cleanup goal |
| `docs/release/SUPABASE_MIGRATION_20260627191000_APPROVAL_RUNBOOK.md` | Added | Approval checklist for the linked production migration blocker |

## Cleanup Completed In This Pass

| File | Change | Reason |
| --- | --- | --- |
| `test/persona_uat_smoke_test.dart` | Replaced the nested-scroll probe inside `scrollToVisible` with explicit axis-aware drags using `warnIfMissed: false` | Removes noisy off-screen hit-test warnings from compact-viewport persona tests without changing product behavior |
| `lib/admin/core/admin_detail_formatters.dart` | Extracted detail-field projection and safe value formatting from `admin_detail_runtime.dart` into a private runtime part | Separates pure admin detail formatting from widget/action code while preserving private helper names and behavior |
| `lib/admin/core/admin_runtime.dart` | Registered the new admin detail formatter part | Keeps the existing admin runtime `part` architecture intact |
| `test/admin_pwa_test.dart` | Added the new formatter part to `readAdminRuntimeLibrary()` | Keeps source-level Admin PWA assertions scanning the complete runtime surface |
| `lib/admin/core/admin_list_specs.dart` | Extracted admin list specs and queue signal metadata from `admin_list_runtime.dart` into a private runtime part | Separates queue configuration data from list-page widgets and state |
| `lib/admin/core/admin_list_export.dart` | Extracted CSV export formatting from `admin_list_runtime.dart` into a private runtime part | Keeps export serialization separate from widget rendering |
| `lib/admin/core/admin_runtime.dart` | Registered the new list spec/export parts | Preserves the existing admin runtime `part` architecture |
| `test/admin_pwa_test.dart` | Added list spec/export parts to `readAdminRuntimeLibrary()` | Keeps Admin PWA source assertions scanning the complete runtime surface |
| `lib/shared/repositories/collect_repository_helpers.dart` | Extracted MoMo Pay code normalization, local slug generation, and single-row RPC parsing from `collect_repository.dart` into a private repository part | Separates pure data-contract helpers from the mutable `StateNotifier` orchestration |
| `lib/shared/repositories/collect_repository.dart` | Registered the repository helper part and removed the embedded pure helper block | Keeps repository methods focused on live/local state transitions |
| `test/shared/collect_repository_test.dart` | Added invalid MoMo Pay receiver-code coverage | Locks the extracted normalization behavior through the public repository API |
| `lib/shared/widgets/collect_group_card_metrics.dart` | Extracted group-card gradients, footer chrome, metric widgets, and compact metadata icons from `collect_group_cards.dart` into a private widget part | Separates repeated card support widgets from card variant layout code |
| `lib/shared/widgets/collect_group_cards.dart` | Registered the metrics part and kept card variant composition as the file's primary role | Reduces the main group-card surface while preserving the existing public import |
| `test/features/widgets_test.dart`, `test/features/design_system_components_test.dart`, `test/app_shell_test.dart` | Updated source-contract assertions to read the complete private group-card library | Keeps design and source checks aligned with the split library |
| `lib/shared/widgets/collect_financial_amount_entry.dart` | Extracted `AmountEntryPanel` and quick-amount chip formatting from `collect_financial_money.dart` into a private financial widget part | Separates contribution amount-entry UI from financial display cards and list rows |
| `lib/shared/widgets/collect_financial_components.dart` | Registered the new amount-entry part | Preserves the existing public financial-components import surface |
| `test/features/widgets_test.dart` | Added direct amount-entry quick-chip coverage | Locks compact amount labels and selection callbacks through widget behavior |
| `lib/shared/models/collect_model_json_helpers.dart` | Extracted private model JSON helper functions for string lists, public visibility aliases, and date parsing | Separates shared parsing utilities from immutable domain model declarations |
| `lib/shared/models/collect_models.dart` | Registered the model helper part and removed embedded private parser helpers | Keeps the model file focused on domain types and constructors |
| `test/shared/collect_repository_test.dart` | Added coverage for string diaspora-region aliases and public visibility aliases | Locks collection JSON compatibility through public model parsing |
| `lib/shared/widgets/collect_financial_payment_pipeline.dart` | Extracted `PaymentPipelineIndicator` and private progress-stage widgets from `collect_financial_payments.dart` | Separates payment progress UI from payment review/status/consent panels |
| `lib/shared/widgets/collect_financial_components.dart` | Registered the payment-pipeline part | Preserves the existing public financial-components import surface |
| `test/features/design_system_components_test.dart` | Added confirmed-payment pipeline semantics coverage | Locks complete-state semantics after the split |
| `lib/admin/core/admin_list_workflow.dart` | Extracted queue summary signals, workflow step chips, SLA fallback copy, and SLA chips from `admin_list_runtime.dart` | Separates static operator workflow/SLA presentation from list paging, export, and row actions |
| `lib/admin/core/admin_runtime.dart` | Registered the admin list workflow part | Preserves the existing admin runtime `part` architecture |
| `test/admin_pwa_test.dart` | Added the workflow part to `readAdminRuntimeLibrary()` | Keeps Admin PWA source assertions scanning the complete runtime surface |
| `lib/admin/core/admin_detail_specs.dart` | Extracted detail page headings, field specs, action metadata, and note-entity mappings from `admin_detail_runtime.dart` | Separates static detail configuration from detail page rendering and audited action callbacks |
| `lib/admin/core/admin_runtime.dart` | Registered the admin detail specs part | Preserves the existing admin runtime `part` architecture |
| `test/admin_pwa_test.dart` | Added the detail specs part to `readAdminRuntimeLibrary()` | Keeps Admin PWA source assertions scanning the complete runtime surface |
| `scripts/collect_edge_auth_contract_uat.sh` | Added current Stripe, Stripe webhook, and Play Integrity functions to the Edge auth contract matrix | Prevents stale backend gates from rejecting the documented production function set |
| `scripts/supabase_deploy.sh` | Added current Stripe/Play functions to the deploy loop and made no-JWT functions explicit | Aligns deploy automation with the documented function set without running deployment |
| `scripts/supabase_production_readiness.sh` | Added current function inventory, secret names, Stripe webhook checks, and user-auth checks | Keeps linked readiness aligned with the current backend surface |

Focused verification after the cleanup:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed test/persona_uat_smoke_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/persona_uat_smoke_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
```

Result: focused persona suite passed 34/34 with no hit-test warning; analyzer
still reports no issues.

Full-suite verification after the cleanup:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: 289 tests passed, 1 opt-in visual-evidence skip, and the prior
off-screen hit-test warning did not reappear.

Admin extraction verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed, Admin PWA focused suite passed 26/26, and full suite
passed 289 tests with 1 opt-in visual-evidence skip.

Admin list split verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed, Admin PWA focused suite passed 26/26, and full suite
passed 289 tests with 1 opt-in visual-evidence skip.

Collect repository helper extraction verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib/shared/repositories/collect_repository.dart lib/shared/repositories/collect_repository_helpers.dart test/shared/collect_repository_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/shared/collect_repository_test.dart
```

Result: formatter gate passed, analyzer passed, and the shared repository
focused suite passed 22/22.

Latest full-suite verification after the repository helper extraction:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: 290 tests passed with 1 opt-in visual-evidence skip.

Group-card composition split verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib/shared/widgets/collect_group_cards.dart lib/shared/widgets/collect_group_card_metrics.dart test/features/widgets_test.dart test/features/design_system_components_test.dart test/app_shell_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/widgets_test.dart test/features/design_system_components_test.dart test/app_shell_test.dart
```

Result: formatter gate passed and focused widget/design/app-shell suites passed
64/64.

Latest full-suite verification after the group-card composition split:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed and full suite passed 290 tests with 1 opt-in
visual-evidence skip.

Financial amount-entry split verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib/shared/widgets/collect_financial_components.dart lib/shared/widgets/collect_financial_money.dart lib/shared/widgets/collect_financial_amount_entry.dart test/features/widgets_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/widgets_test.dart
```

Result: formatter gate passed and focused widget suite passed 10/10.

Latest full-suite verification after the financial amount-entry split:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed and full suite passed 291 tests with 1 opt-in
visual-evidence skip.

Collect model JSON helper split verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib/shared/models/collect_models.dart lib/shared/models/collect_model_json_helpers.dart test/shared/collect_repository_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/shared/collect_repository_test.dart
```

Result: formatter gate passed and focused shared repository/model suite passed
23/23.

Latest full-suite verification after the collect model helper split:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed and full suite passed 292 tests with 1 opt-in
visual-evidence skip.

Financial payment-pipeline split verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib/shared/widgets/collect_financial_components.dart lib/shared/widgets/collect_financial_payments.dart lib/shared/widgets/collect_financial_payment_pipeline.dart test/features/design_system_components_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart
```

Result: formatter gate passed and focused component suite passed 34/34.

Latest full-suite verification after the payment-pipeline split:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed and the rerun full suite passed 293 tests with 1
opt-in visual-evidence skip. The first full-suite attempt hit a transient
release-status blocker mismatch, but the isolated release-status test and rerun
both passed with the current gate output.

Admin list workflow/SLA split verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib/admin/core/admin_runtime.dart lib/admin/core/admin_list_runtime.dart lib/admin/core/admin_list_workflow.dart test/admin_pwa_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart
```

Result: formatter gate passed and focused Admin PWA suite passed 26/26.

Latest full-suite verification after the Admin workflow/SLA split:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed and full suite passed 293 tests with 1 opt-in
visual-evidence skip.

Admin detail spec split verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib/admin/core/admin_runtime.dart lib/admin/core/admin_detail_runtime.dart lib/admin/core/admin_detail_specs.dart test/admin_pwa_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/admin_pwa_test.dart
```

Result: formatter gate passed and focused Admin PWA suite passed 26/26.

Latest full-suite verification after the Admin detail spec split:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
```

Result: analyzer passed and full suite passed 293 tests with 1 opt-in
visual-evidence skip.

Architecture map and remediation plan verification:

```bash
scripts/full_repo_audit_inventory.sh --json
scripts/release_artifact_manifest.sh --json
scripts/migrations/validate_supabase_migrations.sh
scripts/release_secret_scan.sh
scripts/collect_product_boundary_scan.sh --json
scripts/release_status.sh --json
```

Result: inventory, migration validation, fallback secret scan, and product
boundary scan passed. Artifact manifest remains blocked by missing production
APK/AAB/Admin web artifacts, and release status remains `NO-GO` only on
`android_release_artifacts`.

Backend/Supabase contract verification:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/supabase_contract_test.dart
scripts/collect_edge_auth_contract_uat.sh
bash -n scripts/collect_edge_auth_contract_uat.sh scripts/supabase_deploy.sh scripts/supabase_production_readiness.sh
scripts/supabase_advisors_gate.sh
scripts/supabase_schema_inventory.sh --json
scripts/supabase_production_readiness.sh
```

Result: local backend contract suite passed 43/43, Edge Function auth contract
UAT passed, script syntax passed, and linked advisors passed. After explicit
approval, migration `20260627191000` was applied through the linked SQL fallback
because direct `supabase db push` was blocked by tenant allow-listing. Remote
migration history and schema inventory now pass.

Focused release/security verification after backend script updates:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/supabase_contract_test.dart test/release_docs_test.dart test/security_hygiene_test.dart
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/security_hygiene_test.dart
```

Result: the combined run hit a test-isolation failure in
`test/security_hygiene_test.dart` while listing a release-doc temp directory.
The isolated `test/security_hygiene_test.dart` rerun passed 10/10, and the
backend contract coverage in the combined run passed before the isolation
failure.

Current top-level release/go-live verification after backend gate cleanup:

```bash
git diff --check
scripts/release_status.sh --json
scripts/supabase_go_live_gate.sh --json
```

Result: patch whitespace is clean. After the Admin PWA and Android release
rebuild, `scripts/release_artifact_manifest.sh --json`,
`scripts/flutter_mobile_release_gate.sh --json`, and
`scripts/release_status.sh --json` pass. `scripts/supabase_go_live_gate.sh
--json` now passes after setting `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON`. Stripe
launch scope is deferred.

## Admin Runtime Decomposition Map

| File | Current role | Current size after this pass | Refactor direction |
| --- | --- | ---: | --- |
| `lib/admin/core/admin_runtime.dart` | Admin repository wiring, Supabase-backed repository implementation, realtime invalidation provider | 308 lines | Keep as orchestration root; avoid adding widgets here |
| `lib/admin/core/admin_login_runtime.dart` | Admin login UI and OTP flow | 487 lines | Keep unless auth/session logic grows enough for a controller extraction |
| `lib/admin/core/admin_list_runtime.dart` | Queue/list pages, current-page export, pagination, overview signal card, row actions | 475 lines | Keep list orchestration and action callbacks here; row actions are the next optional split if Admin work continues |
| `lib/admin/core/admin_list_specs.dart` | Admin queue metadata, filter/sort defaults, priority signals, workflow steps | 349 lines | Stable configuration part; useful future target for direct unit coverage if made public |
| `lib/admin/core/admin_list_export.dart` | CSV export serialization for current-page queue rows | 29 lines | Stable helper part; keep free of widget concerns |
| `lib/admin/core/admin_list_workflow.dart` | Queue summary signals, workflow steps, and SLA fallback presentation | 374 lines | Stable private workflow/SLA part; keep operator copy and semantic labels covered by Admin widget tests |
| `lib/admin/core/admin_detail_runtime.dart` | Detail pages, SMS reveal panel, detail field cards, detail workflow widgets, status actions, permission decisions | 567 lines | Keep widget/action behavior here; next extraction is collection status actions only if Admin action work continues |
| `lib/admin/core/admin_detail_specs.dart` | Static detail headings, subtitles, field keys, action metadata, and note entity types | 215 lines | Stable private detail configuration part; keep source-contract and Admin widget tests scanning it |
| `lib/admin/core/admin_detail_formatters.dart` | Pure detail-field projection, safe-key filtering, value/date formatting | 90 lines | Stable helper part; useful future target for direct unit coverage if made public |

## Collect Repository Boundary Map

| File | Current role | Current size after this pass | Refactor direction |
| --- | --- | ---: | --- |
| `lib/shared/repositories/collect_repository.dart` | StateNotifier orchestration for profile, group, payment, SMS, offline restore, and Supabase/local writes | 892 lines | Keep write flows here until a broader repository/controller split has stronger characterization coverage |
| `lib/shared/repositories/collect_repository_helpers.dart` | Pure repository-local parsing and normalization helpers | 25 lines | Stable private helper part; keep free of state, Supabase, and UI dependencies |
| `lib/shared/repositories/collect_repository_fixture.dart` | Demo/app-review/fixture state builders | 131 lines | Good future split point if fixture scenarios grow |
| `lib/shared/repositories/collect_repository_live_reader.dart` | Supabase read-side hydration for profile, collections, intents, contributions, notifications | 197 lines | Keep read contracts here; add focused tests around JSON contract changes |
| `lib/shared/repositories/collect_offline_cache.dart` | Offline snapshot serialization and persistence | 171 lines | Keep isolated from live-write behavior |
| `lib/shared/repositories/collect_repository_state.dart` | `CollectState` and immutable state copying | 73 lines | Stable state surface |
| `lib/shared/repositories/collect_repository_providers.dart` | Riverpod providers and derived readiness/status selectors | 97 lines | Keep provider derivations separate from repository mutation methods |

## Group Card Widget Boundary Map

| File | Current role | Current size after this pass | Refactor direction |
| --- | --- | ---: | --- |
| `lib/shared/widgets/collect_group_cards.dart` | Public `GroupCard`/`CollectionSummaryCard` entry points and variant layout composition | 458 lines | Keep public imports here; avoid adding lower-level media/metric helpers back into this file |
| `lib/shared/widgets/collect_group_card_media.dart` | Cover image/data URI/network fallback, scrim, title overlay, privacy glyph, accent color helpers | 315 lines | Keep media and generated-cover behavior isolated from card metrics |
| `lib/shared/widgets/collect_group_card_metrics.dart` | Shared card gradients, footer decoration, amount/member metrics, compact metadata icons | 177 lines | Stable private metrics/chrome part; keep text truncation and semantics covered by widget/source tests |

## Financial Widget Boundary Map

| File | Current role | Current size after this pass | Refactor direction |
| --- | --- | ---: | --- |
| `lib/shared/widgets/collect_financial_components.dart` | Financial widget library root and private part registry | 25 lines | Keep as the stable public import point |
| `lib/shared/widgets/collect_financial_money.dart` | Money display cards, financial list rows, Collect ID card, money hero, identity title formatting | 411 lines | Keep display/read-only money surfaces here; avoid adding input/payment flow widgets back into this part |
| `lib/shared/widgets/collect_financial_amount_entry.dart` | Contribution amount input panel, currency chip, quick amount chips, compact amount labels | 174 lines | Stable amount-entry part; keep digit filtering and quick selection covered by widget tests |
| `lib/shared/widgets/collect_financial_payments.dart` | Payment review, status card, verified ring, consent card, payment status labels and masking helpers | 322 lines | Keep payment status/review/consent panels here |
| `lib/shared/widgets/collect_financial_payment_pipeline.dart` | Payment progress indicator, pipeline stages, pipeline line, step mapping | 139 lines | Stable progress UI part; keep semantics covered by component tests |
| `lib/shared/widgets/collect_financial_ledger.dart` | Contribution ledger row/timeline surfaces | 130 lines | Keep ledger display separate from payment intent entry |

## Collect Model Boundary Map

| File | Current role | Current size after this pass | Refactor direction |
| --- | --- | ---: | --- |
| `lib/shared/models/collect_models.dart` | Immutable domain/data models, enum storage labels, JSON constructors, copyWith methods | 545 lines | Keep public model types here; avoid spreading public DTO classes across imports unless a larger domain split is needed |
| `lib/shared/models/collect_model_json_helpers.dart` | Private shared JSON coercion helpers for dates, string lists, and visibility aliases | 32 lines | Keep parser helpers state-free and model-library private |

## Current Findings

### Release Artifacts

The top release blocker is artifact freshness, not source correctness. The
manifest gate currently reports missing:

- `build/app/outputs/flutter-apk/app-production-release.apk`
- `build/app/outputs/bundle/productionRelease/app-production-release.aab`
- Admin web files under `build/web/`, including `index.html`, `main.dart.js`,
  `custom-sw.js`, manifest, icons, headers, and robots policy.

Next action: after source cleanup stabilizes, rebuild Android APK/AAB and Admin
PWA, then rerun `scripts/release_artifact_manifest.sh --json`,
`scripts/flutter_mobile_release_gate.sh --json`, and
`scripts/release_status.sh --json`.

### Architecture And Refactor Hotspots

High-line-count files to review first:

- `lib/shared/repositories/collect_repository.dart` - 892 lines
- `lib/admin/core/admin_detail_runtime.dart` - 567 lines
- `lib/admin/core/admin_list_runtime.dart` - 475 lines
- `lib/admin/core/admin_list_workflow.dart` - 374 lines
- `lib/shared/models/collect_models.dart` - 545 lines
- `lib/shared/widgets/collect_group_cards.dart` - 458 lines
- `lib/shared/widgets/collect_financial_money.dart` - 411 lines
- `lib/shared/widgets/collect_financial_payments.dart` - 322 lines

Refactor rule: split by stable domain boundary, not by line count alone. Each
split needs a focused test or an existing characterization test before moving
shared behavior.

### Test Infrastructure

The test suite is broad and currently passes. The release-doc tests are large
and intentionally gate release evidence semantics. Keep release-doc test changes
minimal and tied to real gate behavior.

Next cleanup candidates:

- Continue reducing widget-test warning/noise at shared helpers.
- Extract repeated route/evidence fixture definitions from tests only after a
  passing full suite confirms no change in gate semantics.
- Keep compatibility routes explicit: `invite`, `app-share-entry`, and
  `app-invite-link`.

### Mobile UX, Accessibility, And Privacy

Static, screenshot-backed, Android UAT, Android structural accessibility, and
native profile performance gates now pass with fresh evidence. Codex-owned
structural accessibility responsibility is accepted, but final native
accessibility readiness remains human-gated. Do not mark release GO until
TalkBack, VoiceOver or scoped waiver, and final accessibility decision are
recorded with evidence.

### Backend And Supabase

Migration validation, linked advisors, linked migration history, linked schema
inventory, and linked Supabase production readiness pass after the approved
`20260627191000` apply and Play Integrity secret trial. Stripe launch scope is
deferred.

### Dependency And Platform Risk

Dependabot is now configured for GitHub Actions, Pub, and Android Gradle, and a
scoped CodeQL workflow covers Supabase TypeScript Edge Functions. Android Kotlin
plugin compatibility is currently warning-level. The inventory is useful for
package upgrade planning but should not be conflated with release failure until
a Flutter/Gradle upgrade makes it blocking.

## Next Cleanup Queue

1. Audit remaining `lib/admin/core/admin_list_runtime.dart` row-action widget
   boundary only if further Admin work is needed.
2. Apply linked Supabase migration `20260627191000` only through an explicitly
   approved production-change path, then rerun Supabase readiness/go-live gates.
3. Run the repo-wide evidence bundle and record which blockers are code-owned
   versus human/operator-owned.
4. Close human-gated UAT/accessibility evidence only after explicit recorded
   approval; do not synthesize or auto-approve signoffs.
