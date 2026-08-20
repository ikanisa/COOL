# Collect Release Status

Status date: 2026-08-20
Release candidate: **none — current source is not artifact-frozen**
Product boundary: SMS-first Groups

Current override: the build-14 and earlier build-20 records below are retained
as historical store/artifact evidence. They predate the current attested group
creation, provider-finality, atomic SMS ingestion and release-control changes
and cannot authorize the present source. The current decision is **NO-GO**
pending authorized production/public deployment, provider reconciliation, fresh
artifact-bound physical/TalkBack UAT, Google restricted-SMS/release approval,
public availability and monitored staged rollout.

Fresh local `1.2.2+20` artifacts now exist for the current source checkpoint:
APK SHA-256
`85515923a7ca76dd03cb3443abb07236b609ab321b4e4062b9dd9db5c27e8bdb`
and AAB SHA-256
`0922a26c55ce57629a848074b715476a2cf0ce3b13e99b4286eb3669fb30ef74`.
The production build wrapper, embedded-runtime assertion, upload-key preflight,
signature checks and nine-artifact Android/Admin manifest pass. The mobile
release gate remains blocked because `android_release_signing_review` is still
bound to historical build 14 rather than these hashes. No upload occurred.

The current read-only backend recheck is also fail-closed: production has
321/341 expected schema objects and 10/11 expected Edge Functions. The missing
Edge Function is `provider-finality`; required-secret name inventory also lacks
`PAYMENT_PROVIDER_FINALITY_SECRET_CURRENT` and the previously open
`FCM_SERVICE_ACCOUNT_JSON`. No production mutation or secret-value read was
performed.

Canonical machine-readable inputs:

- `docs/release/RELEASE_APPROVALS.json`
- `docs/release/UAT_EVIDENCE_MANIFEST.json`
- `docs/release/RELEASE_APPROVAL_PACKET.md`
- `docs/release/LIVE_DEPLOYMENTS.json`

## Executive status

The historical `1.2.2+14` candidate had artifact-bound Android technical
signing approval. Final accountable release-owner sign-off for a new candidate is intentionally
**PENDING** until provider setup, physical-device testing, CI, policy/legal
attestations, and the remaining store-console checks are complete. General
execution authorization is not treated as final go-live approval.

The current submission status is:

- **Apple:** historical build 13 is superseded and must not be submitted.
  Corrected build 14 was archived,
  cloud-signed with Apple Distribution, validated without errors by Apple's
  official upload tool, and uploaded under delivery UUID
  `f56beeda-cdba-4963-98a9-4f063c3a7c9e`. Apple processing completed, build 14
  is selected on version 1.2.2, and the corrected reviewer notes are saved.
  The APNs server credential is now configured in Supabase; physical-device
  delivery/TestFlight evidence and the DSA trader assessment remain open.
  Legacy-icon TestFlight build 10 is expired with zero
  groups and zero individual testers. Apple retains the historical processed
  build row and currently retains the server-side app header image; the
  official four-member Collect icon is in builds 9, 11, 13, and 14 and is the
  icon attached to the selected release binary.
- **Google:** production version 12 remains in Google review with the
  receive-only SMS declaration and Advertising ID declaration. All 15 legacy
  screenshot placements were removed and replaced by 6 phone, 5 seven-inch,
  and 5 ten-inch current Collect assets. The three screenshot changes are now
  in review with version 12; the public listing still shows the prior assets
  until Google approves and publishes the changes. Version 14 is the corrected
  local Play candidate and has not been uploaded.
- **Public release:** neither store has approved or publicly released version
  14. Store approval and public availability must remain separate claims.

## Current implementation and artifact evidence

- All local App Review phone, OTP, and deterministic-auth bypass code was
  removed. Production sign-in now delegates to the real Supabase OTP gateway;
  tests inject a bounded fake gateway without adding a runtime bypass.
- The App Review test-OTP mapping is configured server-side with a bounded
  expiry. Direct Auth REST and current Supabase Dart requests pass, and a clean
  signed Android install completed confirmation, OTP verification, and Home
  routing without storing reviewer credentials in the app or repository.
- Signed Android device inspection found and fixed stale Gradle packaging that
  omitted the production runtime from final APK/AAB files. Both store wrappers
  now assert the endpoint in the final packaged AOT binary. It also found and
  fixed the account action sheet being covered by the tab bar by presenting it
  on the root navigator.
- Android and iOS production build wrappers now accept only the dedicated
  production Supabase variables and require the exact reviewed production
  project URL. Google Play upload entry points run the pinned optimization gate
  before any publisher operation.
- Android production requests only `RECEIVE_SMS`, `CAMERA`, and
  `POST_NOTIFICATIONS` from the user. It excludes `READ_SMS`, `SEND_SMS`, Call
  Log, contacts, storage, microphone, location, NFC, and Advertising ID access.
  Telephony and camera remain optional device features.
- Android includes the native exported `BROADCAST_SMS` receiver, consent and
  denial/recovery UX, lifecycle resynchronization, Firebase messaging services,
  notification channel metadata, verified HTTPS App Links, Play Integrity,
  `allowBackup=false`, R8/resource shrinking, and 16 KB native-library
  alignment.
- Final signed build-14 Android hashes are
  `abf5a610b6dee60227a33aa6de534622b130b0115d495a95df7a4146580dbe6f`
  (APK) and
  `da98b062e43c08a2086450decb704b6990807d382786eaab48119284ec369f4f`
  (AAB). Both final archives contain the reviewed production runtime.
- The Android upload certificate matches the pinned Google Play upload
  certificate. APK Signature Scheme v2 verification, `zipalign -P 16`, official
  Bundletool 1.18.3 validation, and the merged AAB manifest inspection pass.
- Android signing and final owner approvals are cryptographically bound to the
  current APK/AAB SHA-256 values and must be timestamped after those artifacts;
  stale or replayed approval metadata fails closed.
- The uploaded corrected IPA build 14 has SHA-256
  `bf9c578d0b39c02da13810009fc7fdbfaf1a53ea4f0bb517422c25d03e1185d2`.
  It passes strict signature, production APNs, Associated Domains,
  `get-task-allow=false`, provisioning, privacy-manifest, packaged production
  runtime, no-review-bypass, official validation, and upload checks. A
  post-upload reproducibility export from the same build-14 archive using
  Xcode's current `app-store-connect` method has SHA-256
  `cee88db38c533430c0c62f77086f10a709b4ee29c67c1976d2d44c72da800ca8`;
  signature timestamps make the archive bytes differ and that second export
  was not uploaded.
- Flutter analysis passes and the exact build-14 revision passes all 460
  canonical Flutter tests. Android production-debug JVM tests pass with the
  explicit non-Play-signing debug override.
- The Android 16 emulator performance profile passed all six scenarios. That
  is emulator evidence, not physical-hardware jank, thermal, memory, battery,
  accessibility, or long-session evidence.
- GitHub Actions are pinned to immutable commit SHAs. The Ruby dependency audit
  reports no known vulnerabilities with Fastlane 2.237.0 and Excon 1.7.0.
- Live Supabase reconciliation passes 62/62 migrations, 313/313 schema objects,
  58/58 RLS-enabled public tables, the 153-policy privilege contract, linked
  SMS/Admin rollback UAT, and error-level security/performance advisors. All 11
  Edge Functions were redeployed and their downloaded production source matches
  the repository exactly across 19 deployed files.
- A dedicated Collect APNs key is installed in Supabase. Strict Supabase
  readiness now stops only on the missing least-privilege FCM service-account
  JSON; see `docs/release/SUPABASE_PRODUCTION_AUDIT_2026-08-09.md`.

## Remaining external and acceptance gates

The exact ordered closure list is maintained in
`docs/release/APP_STORE_READINESS.md`. The current high-level gates are:

1. Rotate or remove the bounded reviewer credential after App Review closes;
   exact build-14 clean-install login, deletion-request cancellation, and
   tappable sign-out are already evidenced on the signed Android candidate.
2. Complete Google Cloud re-verification, create the dedicated least-privilege
   FCM sender, install `FCM_SERVICE_ACCOUNT_JSON`, and prove APNs/FCM foreground,
   background, terminated-state, tap-routing, token-refresh, and denial/recovery
   delivery. APNs is already configured. Separately, the current SMS-first
   payment journey requires an approved provider/bank settlement source for the
   signed finality gateway; SMS alone cannot authorize a balance change.
3. Complete fresh physical Android and iPhone UAT, including native permission
   dialogs, TalkBack/VoiceOver, large text, offline recovery, lifecycle, camera,
   notification, and Android receive-only SMS acceptance. The current physical
   iPhone is offline and no physical Android is connected.
4. Install the processed internal build 14 through TestFlight and retain
   physical install/session/crash/feedback proof.
5. Have the accountable corporate owner complete the Apple DSA trader
   self-assessment and confirm all store declarations.
6. Add Apple build 14 for review only after gates 1-5 pass.
7. Let Google's restarted version-12 restricted-SMS and screenshot review
   finish, verify the public legacy assets are gone, then upload/supersede with
   version 14 under the controlled release strategy and re-verify every
   Play Console surface, pre-launch report, device catalog, integrity, vitals,
   Data safety, and policy declaration.
8. Restore GitHub-hosted Actions eligibility and rerun the pushed revision; the
   current failures occur as `startup_failure` before any job is created.
9. Record final accountable release-owner GO only after the external gates
   above have closed against the exact artifact hashes.

## Current human and legal boundary

Jean Bosco authorized execution of the `1.2.2+14` release workflow; that is not
recorded as final release-owner GO. Password entry, identity
verification, one-time codes, biometric consent, the Apple DSA trader
attestation, and provider-key impact decisions remain accountable-owner actions.
No report may describe an owner waiver, simulator run, local build, uploaded
binary, or store processing state as physical testing, provider delivery,
review approval, or public release.

E-081 remains retained historical physical-iPhone evidence. It does not replace
the required fresh build-14 physical and TestFlight runs.
