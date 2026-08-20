# Collect Release Blockers

Status date: 2026-08-20
Release candidate: `1.2.2+14`
Owner decision: **PENDING**
Product boundary: SMS-first Groups

Execution is authorized, but final accountable release-owner GO is not yet
recorded. The table below records the remaining evidence and third-party gates;
none may be cleared by assertion, simulator evidence, or placeholder
credentials.

| Order | ID | Gate | Current evidence | Required closure |
|---:|---|---|---|---|
| 1 | RB-001 | App Review access | The compiled local review bypass is removed. The server-side bounded test OTP and exact signed build-14 clean-install Auth pass. Delete-request cancellation and sign-out actions are tappable above navigation; no deletion request or real-funds action was submitted. | Rotate or remove the bounded reviewer credential after App Review closes. Never store the OTP in source, logs, screenshots, or release docs. |
| 2 | RB-002 | APNs and FCM | Native notification code, entitlements, services, channel UX, permission recovery, and token handling are implemented. Production secret-name inventory confirms the APNs inputs are present, but `FCM_SERVICE_ACCOUNT_JSON` is absent; Google Cloud requires account re-verification before the dedicated sender can be created. | Complete Google Cloud re-verification, create a least-privilege `collect-fcm` sender, install the FCM JSON, rerun strict readiness, and prove APNs/FCM foreground/background/terminated delivery, tap routing, token refresh, opt-out, and recovery on physical devices. |
| 3 | RB-003 | Physical Android | Android 16 emulator signed-APK login, notification/SMS consent, denial/recovery, SMS opt-out, and background/locked synthetic-message lifecycle checks pass. No physical Android is connected. | Run build 14 on supported low/mid/high hardware with native SMS, notification, and camera dialogs; receive a consented new SMS; test permanent denial, settings recovery, reboot, offline/online, background/terminated state, TalkBack, large text, contrast, battery, memory, thermal, crash, and ANR behavior. A real carrier SMS provider integration is not required; a real device/SIM message is acceptance evidence only. |
| 4 | RB-004 | Physical iPhone/TestFlight | Corrected Apple build 14 is validated, processed, assigned internally, and selected on version 1.2.2. Legacy-icon build 10 is expired with zero groups and testers; Apple retains its historical processed row and the server-side app header. The paired iPhone is offline, so build 14 is not physically installed. E-081 is retained historical evidence only. | Reconnect/unlock the iPhone, install build 14 from TestFlight, and complete permissions, VoiceOver, large text, contrast, camera, notification delivery, deep link, offline/online, background/terminated, memory, battery, and crash-free evidence. The selected build already carries the official four-member Collect icon. |
| 5 | RB-005 | Apple legal/store declarations | Privacy disclosures, URLs, screenshots, metadata, encryption declaration, age rating, and manual release mode are populated. The DSA state is non-trader and still requires corporate assessment. | Corporate owner completes and records the DSA trader assessment and rechecks privacy nutrition labels, age rating, financial features, support/contact, export compliance, content rights, and release mode. |
| 6 | RB-006 | Apple submission | Corrected build 14 is processed and selected, and validated reviewer notes are saved. The App Store version remains unsubmitted because provider, physical-device, and accountable declaration gates are open. | After RB-001 through RB-005 pass, add build 14 for review, answer any export/content prompts, and retain submission timestamp/state. Do not submit build 13. |
| 7 | RB-007 | Google restricted SMS/listing | Version 12 and its receive-only SMS declaration are in review. The review was deliberately restarted after removing all 15 legacy screenshot placements and attaching 16 current Collect phone/tablet assets; the three screenshot changes now appear in review. The public listing retains the legacy assets until Google publishes the review. Corrected version 14 is not yet uploaded. | Monitor the current review, verify the public legacy screenshots disappear after publication, then upload or supersede with version 14 under a recorded strategy, re-submit declarations if required, and retain approval/rejection evidence. `RECEIVE_SMS` remains policy-sensitive even without `READ_SMS`. |
| 8 | RB-008 | Play Console quality | Live policy URLs pass. Play reporting API authentication, current pre-launch report, device catalog, integrity, vitals, and final console-surface audit are not closed for version 14. | Authorize the least-privilege reporting/API identity or use authenticated Console readback; resolve pre-launch, ANR/crash, accessibility, security, device-exclusion, and app-size findings; verify Data safety, ads, financial features, target audience, permissions, App Links, store listing, countries, and managed publishing. |
| 9 | RB-009 | Hosted CI | Workflow source is hardened, but GitHub runs fail as `startup_failure` before job creation. Local tests cannot prove hosted CI execution. | Organization owner restores Actions billing/policy/runner eligibility, push the exact reviewed revision, rerun CI/CodeQL/Supabase readiness/website/iOS workflows, and retain green job URLs. |
| 10 | RB-010 | Final accountable approval | Android technical signing approval is bound to the exact current APK/AAB hashes. Final release-owner sign-off is pending and cannot be inferred from general execution authorization. | After RB-001 through RB-009 close, record final GO against version `1.2.2+14`, both current Android hashes, a timestamp after artifact creation, and the reviewed approval packet. |
| 11 | RB-011 | Upstream Android migration | Flutter 3.44.4 builds successfully, but `mobile_scanner` still applies the legacy Kotlin Gradle plugin and AGP reports future built-in-Kotlin migration warnings. | Track the upstream plugin/Flutter migration and rerun compatibility on a governed stable release. This is maintenance risk, not a current build failure. |
| 12 | RB-012 | Stripe diaspora provider readiness | The four Stripe/diaspora Edge Functions are deployed and their 19-file production source inventory matches the repository, but production lacks `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET`. The functions therefore cannot complete live customer, setup, contribution, or webhook flows. | Either keep diaspora contributions outside the release scope, or provision governed live Stripe credentials, configure and verify the webhook endpoint, then run low-value create/setup/contribution/refund/webhook/idempotency/reconciliation UAT. |

## Green evidence that does not clear the table above

- Flutter local unit/widget suite and focused security tests pass.
- Android APK/AAB 14 pass signing, permission, package, runtime, and signed
  Android-16 emulator acceptance checks.
- Production build wrappers pin the reviewed Supabase project; release
  approvals are artifact-hash bound; Play upload paths cannot bypass the
  optimization preflight.
- Apple Distribution IPA 14 passes strict local inspection and Apple's official
  validation; upload, processing, internal assignment, and version selection
  succeeded.
- Native Android and iOS Simulator route matrices have prior 35/35 evidence.
- Android emulator performance passed six scenarios.
- `https://collect.ikanisa.com` and
  `https://admin.collect.ikanisa.com` are live with recorded deployment data.
- Linked Supabase schema/RLS/migration/policy/function checks are exact and all
  deployed Edge source matches the repository; strict readiness remains blocked
  on the FCM service-account JSON and the two Stripe provider secrets.
- All ten UAT personas remain explicitly owner-waived rather than misreported
  as human-tested.

Machine-readable approval and evidence boundaries remain in
`docs/release/RELEASE_STATUS.md`, `docs/release/RELEASE_APPROVALS.json`, and
`docs/release/UAT_EVIDENCE_MANIFEST.json`.
