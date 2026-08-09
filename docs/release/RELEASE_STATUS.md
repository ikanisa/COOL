# Collect Release Status

Status date: 2026-08-09
Release candidate: `1.2.2+13`
Product boundary: SMS-first Groups

Canonical machine-readable inputs:

- `docs/release/RELEASE_APPROVALS.json`
- `docs/release/UAT_EVIDENCE_MANIFEST.json`
- `docs/release/RELEASE_APPROVAL_PACKET.md`
- `docs/release/LIVE_DEPLOYMENTS.json`

## Executive status

The release-owner decision remains **GO** for the exact `1.2.2+13` candidate.
That decision authorizes inspection, signing, upload, and submission work; it is
not evidence that provider setup, physical-device testing, CI, legal
attestations, or store review has passed.

The current submission status is:

- **Apple:** build 13 was signed, validated by Apple's transporter, uploaded,
  processed to `Ready to Submit`, assigned to the internal TestFlight group,
  and attached to App Store version 1.2.2. The App Store version is still
  `Developer Rejected` and has not been added for review again. Submission is
  intentionally paused until dedicated server-authenticated reviewer access,
  APNs delivery, device/TestFlight evidence, and the DSA trader assessment are
  closed.
- **Google:** production version 12 remains in Google review with the
  receive-only SMS declaration and Advertising ID declaration. Version 13 is a
  validated local Play candidate and has not been uploaded, so it has not
  interrupted or superseded the active version-12 review.
- **Public release:** neither store has approved or publicly released version
  13. Store approval and public availability must remain separate claims.

## Current implementation and artifact evidence

- All local App Review phone, OTP, and deterministic-auth bypass code was
  removed. Production sign-in now delegates to the real Supabase OTP gateway;
  tests inject a bounded fake gateway without adding a runtime bypass.
- Android production requests only `RECEIVE_SMS`, `CAMERA`, and
  `POST_NOTIFICATIONS` from the user. It excludes `READ_SMS`, `SEND_SMS`, Call
  Log, contacts, storage, microphone, location, NFC, and Advertising ID access.
  Telephony and camera remain optional device features.
- Android includes the native exported `BROADCAST_SMS` receiver, consent and
  denial/recovery UX, lifecycle resynchronization, Firebase messaging services,
  notification channel metadata, verified HTTPS App Links, Play Integrity,
  `allowBackup=false`, R8/resource shrinking, and 16 KB native-library
  alignment.
- The final signed APK and AAB are version `1.2.2+13`, target/compile SDK 36,
  min SDK 24. Their SHA-256 values are:
  - APK: `78a15aef91d9badaebb7c8b351ef92bbad0f220cc5da09116036fa250c6fbba8`
  - AAB: `21ccc635e8be5d11606ee815b403fa5f5c5285256b64e4f299ffba4d947ba02b`
- The Android upload certificate matches the pinned Google Play upload
  certificate. APK Signature Scheme v2 verification, `zipalign -P 16`, official
  Bundletool 1.18.3 validation, and the merged AAB manifest inspection pass.
- The Apple Distribution IPA is version `1.2.2 (13)`, bundle ID
  `app.cool.mobile`, deployment target iOS 15.5, and SHA-256
  `616ffed72efbfd793fd11ff85729108a27afbdaed8af9426783f789aef260ea4`.
  The exported IPA has production APNs entitlement, `get-task-allow=false`,
  Associated Domains for `collect.ikanisa.com`, the App Store provisioning
  profile, privacy manifests, and archived dSYMs. Apple's transporter reported
  both `VERIFY SUCCEEDED` and `UPLOAD SUCCEEDED`.
- Flutter analysis passes. The canonical Flutter suite passed 456/456 before
  the Android production-build wrapper test was added; the focused updated
  security suite passes 15/15. A final canonical rerun is required after this
  documentation refresh. Android production-debug JVM tests pass with the
  explicit non-Play-signing debug override.
- The Android 16 emulator performance profile passed all six scenarios. That
  is emulator evidence, not physical-hardware jank, thermal, memory, battery,
  accessibility, or long-session evidence.
- GitHub Actions are pinned to immutable commit SHAs. The Ruby dependency audit
  reports no known vulnerabilities with Fastlane 2.237.0 and Excon 1.7.0.

## Remaining external and acceptance gates

The exact ordered closure list is maintained in
`docs/release/APP_STORE_READINESS.md`. The current high-level gates are:

1. Configure dedicated, least-privilege, server-authenticated App Review access
   and validate it on a clean install. Do not embed or retain reviewer
   credentials in source or binaries.
2. Configure real APNs and FCM server credentials in Supabase and prove
   foreground, background, terminated-state, tap-routing, token-refresh, and
   denial/recovery delivery. No real carrier SMS provider is required for this
   release.
3. Complete fresh physical Android and iPhone UAT, including native permission
   dialogs, TalkBack/VoiceOver, large text, offline recovery, lifecycle, camera,
   notification, and Android receive-only SMS acceptance. The current physical
   iPhone is offline and no physical Android is connected.
4. Install TestFlight build 13 and retain install/session/crash/feedback proof.
5. Have the accountable corporate owner complete the Apple DSA trader
   self-assessment and confirm all store declarations.
6. Add Apple build 13 for review only after gates 1-5 pass.
7. Let Google's version-12 restricted-SMS review finish, then upload/supersede
   with version 13 under the controlled release strategy and re-verify every
   Play Console surface, pre-launch report, device catalog, integrity, vitals,
   Data safety, and policy declaration.
8. Restore GitHub-hosted Actions eligibility and rerun the pushed revision; the
   current failures occur as `startup_failure` before any job is created.

## Current human and legal boundary

Jean Bosco authorized the `1.2.2+13` release workflow. Password entry, identity
verification, one-time codes, biometric consent, the Apple DSA trader
attestation, and provider-key impact decisions remain accountable-owner actions.
No report may describe an owner waiver, simulator run, local build, uploaded
binary, or store processing state as physical testing, provider delivery,
review approval, or public release.

E-081 remains retained historical physical-iPhone evidence. It does not replace
the required fresh build-13 physical and TestFlight runs.
