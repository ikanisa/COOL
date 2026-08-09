# Collect Release Blockers

Status date: 2026-08-09
Release candidate: `1.2.2+13`
Owner decision: **GO**
Product boundary: SMS-first Groups

The owner decision authorizes release execution. The table below records the
remaining evidence and third-party gates; none may be cleared by assertion,
simulator evidence, or placeholder credentials.

| Order | ID | Gate | Current evidence | Required closure |
|---:|---|---|---|---|
| 1 | RB-001 | App Review access | The compiled local review bypass is removed. App Store Connect is attached to build 13, but the existing reviewer credential pair is not proven against the production Supabase OTP flow. | Accountable owner configures a dedicated least-privilege server review account or server-side test OTP, validates clean-install login and teardown/rotation, and records sanitized evidence. Never store the OTP in source, logs, screenshots, or release docs. |
| 2 | RB-002 | APNs and FCM | Native notification code, entitlements, services, channel UX, permission recovery, and token handling are implemented. Supabase lacks the APNs key values and FCM service-account JSON. | Reuse or rotate APNs only after checking the impact on other apps; create a least-privilege FCM sender credential; set secrets in Supabase; deploy; prove foreground/background/terminated delivery, tap routing, token refresh, opt-out, and recovery on physical devices. |
| 3 | RB-003 | Physical Android | Android 16 emulator permission, route, notification, accessibility structure, and performance checks exist. No physical Android is connected. | Run build 13 on supported low/mid/high hardware with native SMS, notification, and camera dialogs; receive a consented new SMS; test denial, permanent denial, settings recovery, reboot, offline/online, background/terminated state, TalkBack, large text, contrast, battery, memory, thermal, crash, and ANR behavior. A real carrier SMS provider integration is not required; a real device/SIM message is acceptance evidence only. |
| 4 | RB-004 | Physical iPhone/TestFlight | Apple Distribution IPA build 13 is uploaded and `Ready to Submit`; internal TestFlight group assignment exists. The paired iPhone is currently offline and build 13 has no TestFlight installs or sessions. E-081 is retained historical evidence only. | Reconnect/unlock the iPhone, install TestFlight build 13, and complete permissions, VoiceOver, large text, contrast, camera, notification delivery, deep link, offline/online, background/terminated, memory, battery, and crash-free evidence. |
| 5 | RB-005 | Apple legal/store declarations | Privacy disclosures, URLs, screenshots, metadata, encryption declaration, age rating, and manual release mode are populated. The DSA state is non-trader and still requires corporate assessment. | Corporate owner completes and records the DSA trader assessment and rechecks privacy nutrition labels, age rating, financial features, support/contact, export compliance, content rights, and release mode. |
| 6 | RB-006 | Apple submission | Build 13 is selected and saved; the version remains `Developer Rejected`. Review notes now state the real server-authenticated gate. | After RB-001 through RB-005 pass, replace the pending reviewer credential fields with the validated account, save, add build 13 for review, answer any export/content prompts, and retain submission timestamp/state. Do not submit while notes and credentials contradict runtime behavior. |
| 7 | RB-007 | Google restricted SMS | Version 12 and its receive-only SMS declaration are in Google review. Version 13 passes local manifest, signature, Bundletool, 16 KB, target-SDK, URL, screenshots, and metadata checks. | Preserve the active review until Google decides it. Then upload or supersede with version 13 under a recorded strategy, re-submit declarations if required, and retain approval/rejection evidence. `RECEIVE_SMS` remains policy-sensitive even without `READ_SMS`. |
| 8 | RB-008 | Play Console quality | Live policy URLs pass. Play reporting API authentication, current pre-launch report, device catalog, integrity, vitals, and final console-surface audit are not closed for version 13. | Authorize the least-privilege reporting/API identity or use authenticated Console readback; resolve pre-launch, ANR/crash, accessibility, security, device-exclusion, and app-size findings; verify Data safety, ads, financial features, target audience, permissions, App Links, store listing, countries, and managed publishing. |
| 9 | RB-009 | Hosted CI | Workflow source is hardened, but GitHub runs fail as `startup_failure` before job creation. Local tests cannot prove hosted CI execution. | Organization owner restores Actions billing/policy/runner eligibility, push the exact reviewed revision, rerun CI/CodeQL/Supabase readiness/website/iOS workflows, and retain green job URLs. |
| 10 | RB-010 | Upstream Android migration | Flutter 3.44.4 builds successfully, but `mobile_scanner` still applies the legacy Kotlin Gradle plugin and AGP reports future built-in-Kotlin migration warnings. | Track the upstream plugin/Flutter migration and rerun compatibility on a governed stable release. This is maintenance risk, not a current build failure. |

## Green evidence that does not clear the table above

- Flutter local unit/widget suite and focused security tests pass.
- Android production APK/AAB 13 are fresh, signed by the registered upload key,
  R8-shrunk, 16 KB aligned, and Bundletool-valid.
- Apple Distribution IPA 13 passes strict local inspection and Apple's official
  validation; upload and processing succeeded.
- Native Android and iOS Simulator route matrices have prior 35/35 evidence.
- Android emulator performance passed six scenarios.
- `https://collect.ikanisa.com` and
  `https://admin.collect.ikanisa.com` are live with recorded deployment data.
- Linked Supabase schema/RLS/migration checks are healthy; strict notification
  readiness remains blocked on APNs/FCM secrets.
- All ten UAT personas remain explicitly owner-waived rather than misreported
  as human-tested.

Machine-readable approval and evidence boundaries remain in
`docs/release/RELEASE_STATUS.md`, `docs/release/RELEASE_APPROVALS.json`, and
`docs/release/UAT_EVIDENCE_MANIFEST.json`.
