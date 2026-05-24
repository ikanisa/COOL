# Collect UAT and Go-Live Packet

Prepared: 2026-05-24

Decision: **NO-GO**

## Scope

This packet covers the current fullstack UAT and production-readiness state for
Collect in `/Volumes/PRO-G40/COOL`: Flutter main app, Flutter admin app,
Supabase schema/RLS/RPCs, Edge Functions, operator platform settings, release
evidence, and go-live gates.

## Changes Made In This Pass

- Fixed the analyzer hygiene issue in `test/supabase_contract_test.dart` by
  changing the double-quoted expectation at line 299 to single quotes.
- Added Flutter SDK `integration_test` to `pubspec.yaml`.
- Added `integration_test/app_uat_smoke_test.dart` with smoke coverage for:
  - main app launch without admin or obvious secret-bearing text;
  - admin app default non-admin boundary showing login, not operations.
- Refreshed `pubspec.lock` with the SDK integration-test dependencies.
- Generated the latest Supabase go-live evidence bundle:
  `.cache/supabase_go_live_evidence/20260524T085150Z`.
- Added and ran local Edge Function auth contract UAT:
  `scripts/collect_edge_auth_contract_uat.sh`.
- Verified Android production APK and AAB builds through direct Gradle with
  JDK 17 after diagnosing the JDK 25 Kotlin parser failure.
- Earlier launch/admin-boundary integration smoke passed on the Pixel 5 API 34
  Android emulator; the expanded persona integration harness is implemented but
  still needs a stable device rerun before it can count as GO evidence.
- Verified the isolated admin web release build from `lib/main_admin.dart`.
- Refreshed `docs/release/UAT_EXECUTION_REPORT.md` with a persona-by-persona
  automated evidence map and remaining human signoff actions.
- Added `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md` for release-owner
  and persona signoff capture.
- Added `docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md` to map each
  objective requirement to current evidence, gaps, and NO-GO status.

## Command Evidence

| Area | Command | Result |
| --- | --- | --- |
| SDK | `/Volumes/PRO-G40/flutter_3_44/bin/flutter --version` | Pass: Flutter `3.44.0`, Dart `3.12.0`, DevTools `2.57.0`. |
| Dependencies | `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get` | Pass; added SDK `integration_test` and transitive test-driver packages. |
| Format | `/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed .` | Pass: `104` files checked, `0` changed. |
| Analyze | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` | Pass: no issues found. |
| Tests | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1` | Pass: `87` tests passed. |
| Persona widget smoke UAT | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/persona_uat_smoke_test.dart` | Pass: 7 route/privacy smoke tests for public supporter, contributor, creator, receiver operator, main app, non-admin admin boundary, and authorized admin moderator/payments/compliance/audit/system-health routes. |
| Integration target discovery, current refresh | `/Volumes/PRO-G40/flutter_3_44/bin/flutter devices`; `/Volumes/PRO-G40/flutter_3_44/bin/flutter emulators`; `/Volumes/PRO-G40/flutter_3_44/bin/flutter emulators --launch Pixel_5_API_34_Lite`; `adb devices`; earlier `xcrun simctl bootstatus` | Blocked for expanded device UAT: current Flutter discovery shows macOS, Chrome, and a wireless iPhone only; `adb devices` is empty; launching `Pixel_5_API_34_Lite` did not attach an Android device. Earlier the same emulator launched once and reported `sys.boot_completed=1`, then disappeared from ADB/Flutter during rerun. The iOS simulator boot stalled at BackBoard. |
| Integration test on Chrome | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub -d chrome integration_test/app_uat_smoke_test.dart` | Blocked: Flutter reports web devices are not supported for integration tests yet. |
| Integration test on macOS | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub -d macos integration_test/app_uat_smoke_test.dart` | Blocked: no macOS desktop project is configured. |
| Integration test on wireless iPhone | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub -d 00008101-001A01A61A22001E integration_test/app_uat_smoke_test.dart` | Blocked: Flutter cannot start app on wirelessly tethered iOS device and suggests an unavailable `--publish-port` option for `flutter test`. |
| Integration test on Android emulator | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart` | Prior pass for 2-test launch/admin-boundary smoke. Expanded persona suite is implemented and analyzer-clean, but current Android rerun is blocked because `emulator-5554` disappeared from ADB/Flutter. |
| Android release APK, first diagnostic | `./gradlew :app:assembleProductionRelease --no-daemon --info --stacktrace` | Fail with `java.lang.IllegalArgumentException: 25.0.1`; default JDK 25 is not a valid Android release-build JDK for this Kotlin/Gradle path. |
| Android release APK, latest refresh | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub` | Pass: built `build/app/outputs/flutter-apk/app-production-release.apk` in `121.9s`; KGP plugin deprecation warning for `shared_preferences_android` recorded. |
| Android release AAB, latest refresh | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub` | Pass: built `build/app/outputs/bundle/productionRelease/app-production-release.aab` in `50.1s`; KGP plugin deprecation warning for `shared_preferences_android` recorded. |
| Admin web release, latest refresh | `/Volumes/PRO-G40/flutter_3_44/bin/flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub` | Pass: built `build/web`, including `build/web/main.dart.js`, in `115.7s`. |
| Build artifact checksums | `shasum -a 256 build/app/outputs/flutter-apk/app-production-release.apk build/app/outputs/bundle/productionRelease/app-production-release.aab build/web/main.dart.js` | Pass: hashes recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| Linked persona rollback UAT | `./scripts/collect_linked_uat.sh` | Pass: rollback UAT passed via linked database query. |
| Secret scan | `make release-secret-scan` | Pass: gitleaks unavailable, fallback redacted scan passed. |
| Supabase acceptance matrix, latest refresh | `make supabase-acceptance-matrix-json` | NO-GO: `7` pass, `5` blocked; blocker key `database_connectivity`. |
| Release status | `make release-status-json` | NO-GO: CAPTCHA, HIBP, plan, and PITR blockers. |
| Final Supabase gate | `make supabase-go-live-gate-json` | NO-GO: non-exceptionable CAPTCHA/HIBP blockers remain. |
| Release status, latest refresh | `make release-status-json` | NO-GO: `database_connectivity`; current runner could not reach Postgres because the Supabase tenant allow-list rejected the client address. Platform controls are `unknown` in this run, not passed. |
| Final Supabase gate, latest refresh | `make supabase-go-live-gate-json` | NO-GO: `database_connectivity`; gate exits non-zero and requires a trusted/allow-listed database query path before final approval can be refreshed. |
| Supabase schema inventory | `make supabase-schema-inventory-json` | Pass: expected objects `160`, remote objects `160`, extra `0`, missing `0`, RLS `28/28`, functions with search path `57/57`. |
| Supabase operational report | `make supabase-operational-report` | Pass: cache hit ratio `1`, `28` tables, slow-query visibility available. |
| Supabase admin/security UAT | `make supabase-admin-uat` | Pass: rollback admin/security UAT passed via linked database query. |
| Edge Function auth contract UAT | `make supabase-edge-auth-uat` | Pass: local contract verifies only the WhatsApp auth hook disables JWT, all user/internal functions return `401` for auth failures, internal functions require `x-collect-signature`, and deploy uses `--no-verify-jwt` only for the signed webhook. |
| Supabase evidence bundle | `make supabase-go-live-evidence` | Pass: latest bundle generated at `.cache/supabase_go_live_evidence/20260524T085150Z`; decision remains NO-GO, acceptance matrix `7` pass / `5` blocked. |

## Current Supabase Evidence

The generated bundle summary reports:

- project ref: `lhbowpbcpwoiparwnwgt`;
- decision: `NO-GO`;
- go-live approved: `false`;
- acceptance matrix: `7` pass, `5` blocked;
- schema contract: expected objects `160`, remote objects `160`, extra `0`,
  missing `0`;
- RLS: `28/28` public base tables enabled;
- policies: `61`;
- views: `9`;
- functions: `57`;
- functions with pinned search path: `57`;
- operational report: cache hit ratio `1`, table count `28`, slow-query
  visibility available;
- code-owned Supabase readiness inside the latest bundle: exit code `1`
  because database connectivity is blocked from this runner;
- Edge Function auth contract UAT inside the latest bundle: exit code `0`;
- release secret scan inside the bundle: exit code `0`.

The latest live refresh stops with blocker key `database_connectivity`: the
Supabase tenant allow-list rejected this client address while falling back to
the pooler path. This is still **NO-GO**. It means code-owned readiness, Edge
Function probes, and platform controls must be rechecked from a trusted
linked-query path or an allow-listed runner before any release-owner approval.
The local Edge Function auth contract is green, but remote endpoint deployment
and secret-name verification still require the trusted database path.

## Release Artifact Inventory

| Artifact | Path or command | Status |
| --- | --- | --- |
| Android APK | `build/app/outputs/flutter-apk/app-production-release.apk` | Built with JDK 17 Gradle release command. |
| Android AAB | `build/app/outputs/bundle/productionRelease/app-production-release.aab` | Built with JDK 17 Gradle release command. |
| Android integration APK | `build/app/outputs/flutter-apk/app-production-debug.apk` | Built and installed by the Android emulator integration smoke run. |
| Admin web bundle | `build/web/main.dart.js` | Built from `lib/main_admin.dart` with `--no-wasm-dry-run --no-pub`. |
| Build artifact checksums | `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256` | SHA-256 manifest for the current APK, AAB, and admin web bundle. |
| Supabase evidence bundle | `.cache/supabase_go_live_evidence/20260524T085150Z` | Generated by `make supabase-go-live-evidence`; final decision remains `NO-GO`. |
| UAT execution report | `docs/release/UAT_EXECUTION_REPORT.md` | Maps ten personas to automated evidence and remaining human signoff. |
| Completion audit | `docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md` | Maps objective requirements to proven, partial, pending, and blocked evidence. |
| Signoff checklist | `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md` | Required before release-owner GO. |
| Platform exception template | `docs/release/SUPABASE_PLATFORM_EXCEPTIONS.example.json` | Only covers Free-plan and PITR/RPO exceptionable risks after CAPTCHA/HIBP are resolved. |

## Device And Browser Matrix

| Target | Evidence | Status | Release interpretation |
| --- | --- | --- | --- |
| Android emulator, `Pixel_5_API_34_Lite` | `flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart`; current `flutter devices`/`adb devices` recheck | Prior pass; expanded rerun blocked | Earlier automated device smoke confirmed main app launch, absence of admin/secret-bearing surface in the main app, and default non-admin admin login boundary on Android. Current discovery has no attached Android device after a fresh launch attempt, so the expanded persona suite still needs a stable attached-device rerun. |
| Android release build | JDK 17 Flutter `build apk` and `build appbundle` for `production` flavor | Pass | Store-ready artifacts exist, subject to final signing/release-owner review; hashes are recorded in `BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| Admin web release | `flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub` | Pass | Static admin bundle builds; server-side Supabase permissions remain authoritative. |
| Chrome integration test target | `flutter test --no-pub -d chrome integration_test/app_uat_smoke_test.dart` | Blocked by toolchain | Flutter reports web devices are not supported for integration tests in this path; admin web build evidence is separate. |
| macOS integration test target | `flutter test --no-pub -d macos integration_test/app_uat_smoke_test.dart` | Blocked by project configuration | No macOS desktop project is configured, so no desktop integration UAT is claimed. |
| Wireless iPhone target | `flutter test --no-pub -d 00008101-001A01A61A22001E integration_test/app_uat_smoke_test.dart` | Blocked by device mode | Flutter cannot start the app on the wireless device with the available `flutter test` options; no iOS device UAT is claimed. |
| Human persona walkthroughs | `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md` | Pending | Required before GO for contributor, creator, recurring admin, public supporter, receiver/SMS operator, moderator, payments admin, compliance admin, non-admin, and edge-case journeys. |

## Test Data Ledger

All automated linked UAT data is synthetic and rollback-scoped. Evidence must
not include raw production SMS, real phone/MOMO numbers, tokens, provider
secrets, service-role keys, OpenAI keys, or WhatsApp/SMS hook secrets.

| Data class | Handling | Evidence |
| --- | --- | --- |
| Users/personas | Generated UUIDs and synthetic Rwanda-format numbers. | `scripts/collect_linked_uat.sh`, `scripts/collect_admin_security_uat.sh`. |
| Collections and public requests | Synthetic private collection, approved public collection, recurring collection, and moderation request rows. | Rollback UAT plus repository tests for private defaults and public request behavior. |
| Payment intents and ledger entries | Synthetic contribution amount, MOMO instructions, parsed event, payment, and exactly one ledger post. | Rollback UAT idempotency checks and repository/widget tests. |
| Receiver/SMS data | Synthetic SMS bodies and hashed receiver/sender values; raw reveal only through compliance permission in rollback. | Admin/security rollback UAT and privacy tests. |
| Edge cases | Duplicate/idempotent allocation, duplicate transaction no double-post, ambiguous payment, expired intent no auto-match, missing receiver authorization, invalid amount, non-Rwanda phone rejection, and failed Edge Function auth have automated assertions. Current runner cannot execute the linked DB script until `database_connectivity` is cleared. | `scripts/collect_linked_uat.sh`, `scripts/collect_edge_auth_contract_uat.sh`, `test/core/phone_and_public_id_test.dart`, `test/shared/collect_repository_test.dart`, `test/supabase_contract_test.dart`. |
| Persistence | Automated linked UAT runs inside explicit rollback transactions. | UAT scripts end with `rollback;`; no production fixture persistence is required. |

## Risk Register

| Risk | Severity | Current status | Required owner action |
| --- | --- | --- | --- |
| CAPTCHA/bot protection disabled | P0 | Non-exceptionable NO-GO blocker. | Configure provider/site key/secret, harden Auth, rebuild Flutter auth config with CAPTCHA enabled, and rerun gates. |
| HIBP leaked-password protection disabled | P0 | Non-exceptionable NO-GO blocker; paid plan required. | Upgrade plan, enable HIBP through `make supabase-auth-harden`, and verify live Auth config. |
| Supabase Free-plan project-pause risk | P0 | Exceptionable only after non-exceptionable blockers are fixed. | Upgrade organization plan or record signed project-pause risk acceptance. |
| PITR/RPO not enabled | P0 | Exceptionable only after non-exceptionable blockers are fixed. | Enable PITR or record signed recovery-objective exception. |
| Current runner database connectivity | P0 | Latest `release-status-json` and `supabase-go-live-gate-json` return `database_connectivity` because Postgres access is not allow-listed for this runner. | Rerun from trusted linked query mode or an allow-listed Supavisor pooler path before final approval. |
| Human persona UAT not signed | P1 | Pending release-owner signoff. | Execute all ten persona walkthroughs and attach sanitized evidence. |
| iOS automated UAT missing | P1 | Wireless device could not be used by `flutter test`. | Run tethered iOS/UAT separately before iOS release claims. |
| Large dirty worktree | P2 | `git status --short` shows broad unrelated drift. | Stage/review intentionally before any release branch or tag. |

## Exception And Signoff Status

- No production GO is approved in this packet.
- No real `docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json` is recorded.
- `docs/release/SUPABASE_PLATFORM_EXCEPTIONS.example.json` is a template only.
- CAPTCHA and HIBP cannot be cleared by exception in the current gate.
- Free-plan and PITR/RPO exceptions can be considered only after CAPTCHA and
  HIBP are resolved and `make supabase-platform-exception-gate` validates the
  signed exception file.
- Human persona signoff remains pending in
  `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md`.

## Rollback And Incident Plan

Use `docs/SUPABASE_OPERATIONS_RUNBOOK.md` as the operating runbook before any
production launch. Minimum release-review expectations:

1. Keep `make supabase-go-live-evidence` output for the reviewed release.
2. Verify Android APK/AAB and admin web artifact checksums against
   `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256` if the release
   owner stages binaries for distribution.
3. For Supabase incidents, run the read-only operational report, classify the
   issue as Auth/config, Edge Function, RLS/RPC, migration, parser/allocation,
   or data-corruption, then follow the corresponding runbook section.
4. For Edge Function regressions, redeploy the prior known-good function set and
   rerun linked UAT plus `make supabase-go-live-gate-json`.
5. For migration/data incidents, stop writes if needed, use PITR only for severe
   corruption/destructive migration incidents, and rehearse restore outside
   production before any live restore.
6. For Flutter release incidents, halt rollout, revert to the last reviewed APK,
   AAB, or admin web bundle, and rerun format/analyze/tests/builds plus Android
   smoke UAT before re-release.

## Remaining Blockers

### P0 Go-Live Blockers

- `auth_captcha_bot_protection`: CAPTCHA/bot protection is disabled, and
  `AUTH_CAPTCHA_SECRET`, `AUTH_CAPTCHA_PROVIDER`, and
  `AUTH_CAPTCHA_SITE_KEY` are missing from the operator inputs.
- `auth_hibp_leaked_password_protection`: HIBP leaked-password protection is
  disabled and requires a paid Supabase plan.
- `supabase_organization_plan`: the Supabase organization remains on the Free
  plan, which carries project-pause and production-support risk.
- `supabase_pitr`: PITR is disabled; either enable PITR or record an accepted
  recovery-objective exception after non-exceptionable blockers are resolved.

CAPTCHA and HIBP are non-exceptionable in the current go-live gate. The final
gate output says a signed exception can only be used for remaining
exceptionable platform risks after non-exceptionable blockers are resolved.

### UAT/Build Blockers

- Full persona UAT is not yet signed. The expanded integration harness is
  implemented and analyzer-clean, and the normal Flutter test suite now covers
  seven widget-level persona smoke paths, but the only device-green automated UAT
  evidence remains the earlier Android launch/admin-boundary smoke. It does not
  replace contributor, creator, recurring admin, public supporter, receiver/SMS
  operator, moderator, payments admin, compliance admin, non-admin, and
  edge-case human UAT.
- `docs/release/UAT_EXECUTION_REPORT.md` now maps each persona to automated
  evidence and remaining human signoff steps. Automated linked rollback UAT is
  not a substitute for signed release-owner/persona acceptance.
- `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md` is the required signoff
  artifact before GO.
- Chrome remains unsupported for Flutter integration tests in this toolchain,
  and the available iPhone was wireless-only. Android emulator coverage is
  therefore the only device-level automated UAT evidence in this pass.
- Full human/persona UAT signoff is not recorded yet for contributor, creator,
  recurring admin, public supporter, receiver/SMS operator, moderator, payments
  admin, compliance admin, non-admin, and edge-case journeys.

## GO Criteria

The release can become GO only after all of the following are true and rerun:

1. `flutter analyze --no-pub`, `dart format --set-exit-if-changed .`, and
   `flutter test --no-pub --concurrency=1` remain green.
2. Persona UAT is executed and signed with sanitized evidence.
3. Supabase CAPTCHA and HIBP blockers are resolved.
4. Supabase plan/PITR risks are resolved or validly exceptioned where allowed.
5. `make supabase-ready-strict`, `make supabase-platform-exception-gate`,
   `make supabase-go-live-gate`, and `make supabase-go-live-evidence` pass.

Until then, the production decision remains **NO-GO**.
