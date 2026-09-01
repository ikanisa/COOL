# Collect Google Play and Apple App Store Readiness

Status date: 2026-08-20
Release candidate: `1.2.2+21`
Product boundary: Rwanda MoMo USSD and diaspora bank/Revolut Groups; no in-app payment processor

## Live App Store Connect audit — 2026-08-20

- Version `1.2.2` is `Prepare for Submission`; no item is currently submitted.
- App Store version `1.2.2` still has build 14 selected.
- TestFlight builds 14, 15, and 16 are processed; build 16 is the newest upload,
  is assigned to the Internal group with three testers, and has no recorded
  installs, sessions, crashes, or feedback.
- Current production source is build 21. Build 21 has not yet been uploaded or
  selected, so build 14 must not be submitted as the current product.
- The previous 5 August submission is `Removed`.
- Five iPhone screenshots and five iPad screenshots are populated, but they
  must be regenerated from the current geographic-rail build before submission.
- App Privacy is published with eight linked-to-user data types. It must be
  rechecked against the bank evidence, payer-name/account-last-four, support,
  device token, and user-content paths before republishing.
- App Accessibility has unpublished iPhone and iPad drafts. Claimed features
  remain subject to physical VoiceOver and accessibility evidence.
- App availability is not configured (`Set Up Availability`). Apple Silicon
  Mac and Vision Pro distribution are enabled without recorded compatibility
  testing and must be reviewed before release.
- The app is currently marked DSA non-trader. The Account Holder must make and
  document the legal status decision; repository automation must not change it.
- Manual release remains selected. `Add for Review` was not used during this
  audit.

The build-14 statements below are retained as historical evidence only. They
do not describe the current build-21 candidate.

This is the ordered completion list for full submission. A checked local item
does not clear a provider, physical-device, legal, submission, approval, or
public-release item.

## 0. Candidate freeze and local release evidence

- [x] Freeze version `1.2.2+14` and bind Android technical signing approval to
  that version and the exact APK/AAB hashes.
- [ ] Record final accountable release-owner GO only after all prerequisite
  external gates close; execution authorization is not final sign-off.
- [x] Remove compiled review phone/OTP/local-auth bypasses; use the production
  Supabase OTP gateway with test-only injection.
- [x] Pin GitHub Actions to immutable commits and update vulnerable Ruby
  dependencies; Bundler Audit reports no known vulnerabilities.
- [x] Pass Flutter analysis and the canonical pre-documentation test suite.
- [x] Pass Android JVM tests with debug signing explicitly separated from Play
  app signing.
- [x] Build signed Android APK/AAB 14 from an ephemeral public-config file and
  prove the final packaged binaries contain the reviewed production runtime.
- [x] Pin Android/iOS release wrappers to the exact reviewed production
  Supabase project and require the Play optimization gate before upload.
- [x] Verify upload-certificate pin, merged permissions, R8, signature, target
  SDK 36, 16 KB alignment, App Links, metadata, and Bundletool validation for
  build 14.
- [x] Build the Apple Distribution IPA 14 from an ephemeral public-config file.
- [x] Verify production APNs entitlement, `get-task-allow=false`, Associated
  Domains, provisioning, privacy manifests, dSYMs, packaged production runtime,
  and absence of review-bypass strings for build 14.
- [x] Validate and upload IPA 14 with Apple's official upload tool.
- [x] Confirm TestFlight build 14 is processed and assigned internally.
- [x] Replace historical build 13 with build 14 on App Store version 1.2.2 and
  save accurate review notes.
- [x] Rerun the full canonical suite after the final docs/build-wrapper changes;
  static analysis is clean and all 460 Flutter tests pass.
- [x] Run the release and security diff gates; remediate the backend-selection
  and mutable-approval findings with pinned configuration, mandatory preflight,
  artifact digests, and approval freshness checks.
- [ ] Rerun and retain final gate evidence against the exact committed SHA.

## 1. Reviewer access and backend notification providers

- [x] Accountable owner designated the App Review identity for synthetic,
  least-privilege review use with no real-funds authority.
- [x] Configure a server-authenticated reviewer OTP/test flow in Supabase; keep
  phone, passwords, and OTPs outside source, logs, screenshots, and docs.
- [x] Prove clean-install reviewer login, tappable logout, and cancellable
  account-deletion UI on the exact signed Android build 14 without moving funds
  or submitting a deletion request.
- [ ] Rotate or remove the bounded reviewer credential after App Review closes.
- [x] Register a dedicated Collect APNs key without revoking the two historical
  team keys, install all four required APNs values in Supabase, redeploy the
  notification functions, verify the secret-name inventory, and remove the
  one-time local private-key download.
- [x] Create a least-privilege Firebase/Google service account in the existing
  May2026 project and set `FCM_SERVICE_ACCOUNT_JSON` in production Supabase.
- [ ] Validate APNs and FCM token registration, rotation, sign-out cleanup,
  foreground display, background/terminated delivery, tap routing, deep-link
  routing, collapse/deduplication, opt-out, denial, and settings recovery.
- [ ] Confirm logs and telemetry contain no tokens, message bodies, phone
  numbers, raw SMS, or customer financial data.

No real carrier SMS provider is required. Android `RECEIVE_SMS` handles new
device-delivered messages locally; the final physical-device acceptance run may
use any safe SIM/test message.

## 2. Physical-device and accessibility acceptance

- [ ] Connect at least one current physical Android phone and one supported
  lower/mid-range Android phone; record OS, model, app build, and test date.
- [ ] Run native Android dialogs for SMS, notifications, and camera: first ask,
  allow, deny, permanent deny, rationale, settings recovery, reinstall/reset,
  and lifecycle resume.
- [ ] Receive a new consented SMS on-device; verify local parsing, deduplication,
  privacy redaction, relevant-screen routing, and no inbox-history access.
- [ ] Test FCM foreground/background/terminated delivery, token refresh, tap
  routing, reboot, Doze/battery restriction, and notification-channel settings.
- [ ] Run TalkBack traversal/actions, switch access where available, 200% text,
  contrast, color differentiation, reduced motion, orientation, small/large
  screens, and keyboard focus.
- [ ] Run Android low-storage, offline/online, slow network, interrupted intent,
  process death, long session, memory, CPU, thermal, battery, crash, and ANR
  checks; retain Android Vitals-compatible evidence.
- [ ] Reconnect and unlock the registered iPhone; install TestFlight build 14.
- [ ] Run iOS camera and notification dialogs, allow/deny/recovery, deep links,
  foreground/background/terminated notifications, token refresh, offline/online,
  process termination, and account deletion.
- [ ] Run VoiceOver, Voice Control where available, Larger Text, Bold Text,
  Increase Contrast, Differentiate Without Color, Reduce Motion, portrait/
  landscape, and iPad multitasking checks.
- [ ] Complete at least one internal TestFlight install/session and review
  crashes, screenshots, and feedback for build 14.
- [ ] Record only sanitized screenshots/logs and accountable pass/fail signoff;
  do not convert persona owner waivers into human test claims.

## 3. Apple App Store Connect closure

- [x] Current iPhone/iPad screenshots, description, keywords, support/marketing
  URLs, privacy URL, copyright, category, encryption declaration, age rating,
  privacy disclosures, and manual-release mode are populated.
- [x] Corrected build 14 is processed and selected on version 1.2.2; historical
  build 13 is no longer attached to the version.
- [x] Expire legacy-icon TestFlight build 10 and verify it has zero groups and
  zero individual testers. Apple retains processed-build history and the
  server-side app header; builds 9, 11, 13, and selected build 14 carry the
  official four-member Collect icon.
- [x] Review notes state that no reviewer bypass or credential is embedded.
- [x] The reviewer fields match the validated server-side test-OTP identity;
  values were read and tested without copying them to the repository.
- [ ] Corporate owner completes the DSA trader/non-trader assessment and retains
  the decision basis.
- [ ] Reconcile App Privacy with actual Supabase tables, analytics/crash tools,
  photos, payment/financial data, user/device IDs, support, and user content.
- [ ] Recheck age rating, financial features, content rights, export compliance,
  support contact, territory availability, pricing, and release mode.
- [ ] Confirm App Accessibility declarations only after physical VoiceOver and
  other claimed-feature evidence exists; publish when Apple permits.
- [ ] Add version 1.2.2/build 14 for review and answer the final submission
  prompts. Retain the submission ID, timestamp, and exact state.
- [ ] Monitor `Waiting for Review`, `In Review`, messages, metadata rejections,
  binary rejections, and resolution-center requests; respond without changing
  untested scope.
- [ ] After `Ready for Distribution`, perform the intentional manual release,
  verify the public product page/install, and run a production smoke test.

## 4. Google Play Console closure

- [x] Version 12 full production rollout and receive-only SMS/Advertising ID
  declarations are currently in review.
- [x] Remove all 15 legacy screenshot placements, attach 6 current phone, 5
  current 7-inch, and 5 current 10-inch Collect screenshots, and submit the
  three listing changes by deliberately restarting review. Production version
  12 and all three screenshot changes now appear under `Changes in review`.
- [ ] Wait for Google approval/publication, then verify the public listing no
  longer exposes the 15 legacy screenshots. The public page remains unchanged
  while the replacement assets are in review.
- [x] Version 14 local AAB passes package, signature, target-SDK, 16 KB, packaged
  production runtime, App Links, privacy/account-deletion URLs, metadata,
  screenshot, and Bundletool checks.
- [x] Record and execute the decision to restart version-12 review so the legacy
  screenshots are replaced in the same review package.
- [ ] When Google responds, decide whether to complete the current review and
  then roll version 14, or supersede it with version 14 as the security update.
- [ ] Upload AAB 14 with the registered Play upload key, add changelog 14, and
  verify Play App Signing recognizes the certificate and version code.
- [ ] Reconcile the SMS/Call Log declaration to `RECEIVE_SMS` only, optional
  telephony, consented new-message money-management matching, no `READ_SMS`, and
  no default-SMS-handler claim.
- [ ] Recheck Data safety, privacy policy, account/data deletion, ads=no,
  financial features, target audience, content rating, app access, government
  app, news, health, and all other applicable App content forms.
- [ ] Recheck title, descriptions, icon, feature graphic, phone/tablet
  screenshots, category/tags, contact details, countries, pricing, managed
  publishing, and release notes.
- [ ] Review App Links/domain verification, Play Integrity, automatic
  protection, device catalog/exclusions, app size/download size, form factors,
  and device reach.
- [ ] Run and clear the version-14 pre-launch report: crashes, ANRs,
  accessibility, security/privacy, compatibility, and rendering findings.
- [ ] Authorize the least-privilege Play Developer Reporting API identity or
  capture authenticated Console evidence for crash rate, ANR rate, slow
  rendering/startup, excessive wakeups, and bad-behavior thresholds.
- [ ] Submit the version-14 production change, retain the review timestamp/state,
  respond to policy questions, and verify approval before rollout.
- [ ] After availability, verify store install/update, permission behavior,
  notification delivery, App Links, account deletion, and staged/full rollout
  health before declaring public release.

## 5. Hosted CI and final evidence package

- [ ] Organization owner resolves GitHub Actions `startup_failure` eligibility,
  billing, policy, or runner availability.
- [ ] Commit and push the exact candidate; rerun CI, CodeQL, Supabase readiness,
  public website, and iOS App Store workflows. Retain green job URLs and SHAs.
- [ ] Run the final security diff scan and close/retest every reportable finding.
- [ ] Generate the release status, approval evidence, artifact manifest,
  Supabase readiness, Google optimization, and repo-wide QA packets from the
  same commit and artifacts.
- [ ] Confirm no secrets, credentials, OTPs, provider keys, raw SMS, or customer
  data exist in Git, build logs, CI artifacts, screenshots, or release docs.
- [ ] Record final owner GO only after all preceding provider, device, policy,
  CI, and console gates pass, bound to the exact release artifact hashes.
- [ ] Archive store submissions, provider configuration receipts, physical UAT,
  TestFlight/Play reports, approvals, rollback procedures, and support/on-call
  ownership.

## Definition of done

`Fully submitted` means both store version records contain the exact approved
binary and metadata and show a submitted review state. `Approved` means each
store has accepted the app. `Released` means the approved version is publicly
available in the intended territories. These three states must never be merged
into one claim.
