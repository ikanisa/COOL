# Collect UAT Execution Report

Audit date: 2026-05-24

Status: **AUTOMATED UAT PARTIAL PASS; LIVE SIGNOFF PENDING**

Public launch remains **NO-GO** until Supabase CAPTCHA/bot protection, HIBP
leaked-password protection, Free-plan project-pause risk, PITR/RPO, current
trusted database verification, and human persona signoff are handled. Earlier
linked rollback UAT exists, the original Android launch/admin-boundary smoke
UAT has pass evidence, and current local Flutter hygiene is green. The Flutter
integration harness has been expanded for public supporter, contributor,
creator share/invite, and receiver/manual-SMS smoke paths, but the expanded
suite is not yet fresh device-green because the Android emulator disappeared
from Flutter/ADB during rerun and the iOS simulator stalled during boot. The
latest Supabase evidence bundle cannot refresh code-owned readiness from this
runner because the database path is blocked by the Supabase tenant allow-list.
Evidence remains sanitized and must not expose raw SMS, phone/MOMO numbers,
tokens, service-role keys, provider secrets, or production data.

## Build And Device Evidence

| Surface | Evidence | Result |
| --- | --- | --- |
| Flutter hygiene | `dart format --set-exit-if-changed .`, `flutter analyze --no-pub`, `flutter test --no-pub --concurrency=1` | Pass: format clean, analyzer clean, `87` tests passed. |
| Persona widget smoke UAT | `flutter test --no-pub test/persona_uat_smoke_test.dart` | Pass: 7 repeatable local smoke tests cover public supporter browsing, contributor intent/MOMO instructions/ledger, creator share/invite, receiver manual SMS review, main app launch, admin non-admin denial, and authorized admin moderator/payments/compliance/audit/system-health routes. |
| Android APK | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub` | Pass: `build/app/outputs/flutter-apk/app-production-release.apk`; SHA-256 recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| Android AAB | `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub` | Pass: `build/app/outputs/bundle/productionRelease/app-production-release.aab`; SHA-256 recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| Android launch/admin-boundary smoke UAT | `flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart` on `Pixel_5_API_34_Lite` / `emulator-5554` | Prior pass: production debug APK built and installed; 2 integration tests passed after bounding startup frame pumping in the harness. |
| Expanded persona integration harness | `integration_test/app_uat_smoke_test.dart`; current `flutter devices`/`adb devices` recheck | Implemented and analyzer-clean with the same route/privacy/admin scope as the persona widget smoke UAT. Current device rerun is blocked because Flutter sees only macOS, Chrome, and a wireless iPhone, `adb devices` is empty, and launching `Pixel_5_API_34_Lite` did not attach an Android device. This is not device GO evidence yet. |
| Other integration targets | `flutter test --no-pub integration_test/app_uat_smoke_test.dart`; `flutter test --no-pub -d macos integration_test/app_uat_smoke_test.dart`; iOS simulator boot | Blocked for non-Android UAT: web integration tests are unsupported, macOS has no desktop project configured, the wireless iPhone path remains device-mode blocked, and the iOS simulator stalled at BackBoard. |
| Admin web release | `flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub` | Pass: `build/web/main.dart.js`; SHA-256 recorded in `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`. |
| Edge Function auth contract UAT | `make supabase-edge-auth-uat` | Pass: local auth contract passed; remote Edge Function endpoint and secret-name probes remain blocked by current runner `database_connectivity`. |
| Supabase evidence bundle | `make supabase-go-live-evidence` | Pass: `.cache/supabase_go_live_evidence/20260524T085150Z`; final decision still `NO-GO`, acceptance matrix `7` pass / `5` blocked due current runner `database_connectivity`. |

## Persona Matrix

| ID | Persona | Required journey | Current automated evidence | Result | Remaining action |
| --- | --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Sign in, open approved collection, create intent, follow MOMO/USSD instructions, mark paid with sanitized reference. | `scripts/collect_linked_uat.sh` creates contributor, approved public collection, payment intent with instructions, paid report, matching parsed event, payment, and ledger entry in a rollback transaction. Repository/widget tests cover intent copy and anonymous supporter label. | Automated pass; live signoff pending | Execute the same flow with a release tester after CAPTCHA/Auth hardening and attach sanitized screenshots/logs. |
| UAT-02 | Creator | Create private collection with receiver MOMO, request public listing, share QR/link. | `scripts/collect_linked_uat.sh` creates private collection, receiver hash, owner membership, public request, and proves requested collection is not public until admin approval. Repository tests prove private default. | Automated pass; live signoff pending | Complete creator walkthrough in the app and capture sanitized evidence, including share link/QR privacy. |
| UAT-03 | Recurring group admin | Create recurring collection and inspect period/obligation behavior. | `scripts/collect_linked_uat.sh` creates recurring collection with monthly rule and verifies an open recurring period. | Automated partial pass; live signoff pending | Human tester must verify the recurring-management UI and member/admin visibility. |
| UAT-04 | Public supporter | Visit public directory and contribute without membership. | `scripts/collect_linked_uat.sh` proves only approved collection appears in `public_collections_view`; widget tests show contribution instructions and no money-moving boundary drift. | Automated pass; live signoff pending | Complete public-supporter walkthrough from directory to payment instructions. |
| UAT-05 | Receiver/SMS operator | Paste sanitized receiver MOMO SMS and review parsed event. | `scripts/collect_linked_uat.sh` verifies receiver SMS authorization, parsed payment event allocation, ambiguous event review, and no auto-post for ambiguous payment. `scripts/collect_admin_security_uat.sh` verifies raw SMS metadata masking. | Automated pass; live signoff pending | Execute controlled receiver/manual SMS flow with sanitized evidence from the app/admin UI. |
| UAT-06 | Moderator | Review public requests/moderation queues. | `scripts/collect_admin_security_uat.sh` assigns moderation admin and approves a public request with audit-sensitive state in rollback UAT. | Automated pass; live signoff pending | Complete human moderator walkthrough and attach sanitized evidence. |
| UAT-07 | Payments admin | Allocate unallocated/ambiguous payment with required reason. | `scripts/collect_admin_security_uat.sh` verifies payments-admin allocation and audit log; `scripts/collect_linked_uat.sh` verifies idempotent allocation and manual allocation reason. | Automated pass; live signoff pending | Complete human payments-admin allocation walkthrough and attach sanitized evidence. |
| UAT-08 | Compliance admin | Reveal raw SMS through controlled path. | `scripts/collect_admin_security_uat.sh` verifies masked metadata, compliance reveal, sensitive-access log, and audit log. | Automated pass; live signoff pending | Complete compliance reveal walkthrough using sanitized data only. |
| UAT-09 | Non-admin | Attempt admin routes/functions. | Android integration smoke verifies default admin app opens at login, not operations. `scripts/collect_admin_security_uat.sh` verifies support admin cannot reveal raw SMS and read-only admin cannot allocate payments. | Automated pass; live signoff pending | Complete non-admin UI/API denial checks in the release environment. |
| UAT-10 | Edge-case user | Duplicate SMS/ref, bad amount, non-Rwanda phone, expired intent, ambiguous amount, missing receiver authorization, failed Edge Function auth. | `scripts/collect_linked_uat.sh` now includes rollback assertions for allocation idempotency, duplicate transaction no double-post, expired intent no auto-match, missing receiver authorization, and ambiguous event no auto-post. `scripts/collect_edge_auth_contract_uat.sh` proves the local Edge Function auth contract returns `401` for user/internal auth failures and keeps unauthenticated mode limited to the signed WhatsApp hook. Unit tests prove non-Rwanda phone rejection and bad contribution amount rejection. Parser fallback tests prove no raw phone persistence in parsed JSON. | Automation present; trusted DB rerun pending for linked DB edge cases | Rerun linked rollback UAT from an allow-listed/trusted DB path, then complete edge-case UI/API walkthrough before GO. |

## Test Data Ledger

All linked database UAT scripts run inside explicit rollback transactions. They
create synthetic users, synthetic Rwanda-format phone numbers, synthetic
collection titles, synthetic transaction IDs, and synthetic SMS bodies. No
production raw SMS or customer phone/MOMO numbers are required for automated
UAT.

| Data class | Current handling |
| --- | --- |
| UAT users | Generated UUIDs and synthetic `+250781...` phone values inside rollback SQL. |
| Receiver/sender values | Synthetic Rwanda-format numbers hashed before storage checks. |
| SMS body | Synthetic text; raw reveal tested only through compliance permission and rollback. |
| Transaction references | Synthetic `UAT-*` and `ADMIN-UAT-*` identifiers, including duplicate-transaction no-double-post checks. |
| Expired intents | Synthetic expired payment intent stays unposted and moves parsed event to review in rollback UAT. |
| Missing receiver authorization | Synthetic non-receiver user is denied receiver SMS ingestion in rollback UAT. |
| Failed Edge Function auth | Local static UAT verifies JWT/auth-hook modes, internal signatures, and `401` error mapping without calling production endpoints. |
| Persistence | Automated linked UAT scripts end with `rollback;`. |

## Remaining Launch Preconditions

- Configure CAPTCHA provider/site key/secret and rerun `make supabase-ready-strict`.
- Upgrade to a paid Supabase plan, enable HIBP leaked-password protection with
  `make supabase-auth-harden`, and rerun `make supabase-ready-strict`.
- Upgrade the Supabase organization plan or record an accepted project-pause
  risk exception after non-exceptionable blockers are resolved.
- Enable PITR or record a signed recovery-objective exception after
  non-exceptionable blockers are resolved.
- Complete human persona UAT from a trusted operator environment and record
  sanitized signoff evidence for all ten UAT rows above.
- Rerun Supabase readiness from trusted linked query mode or an allow-listed
  Supavisor/direct database path so `database_connectivity` is cleared and
  platform controls can be rechecked.
