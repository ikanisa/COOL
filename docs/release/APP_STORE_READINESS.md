# Collect Google Play and Apple App Store Readiness

Status date: 2026-08-09
Release candidate: `1.2.2+13`
Product boundary: SMS-first Groups

This is the ordered completion list for full submission. A checked local item
does not clear a provider, physical-device, legal, submission, approval, or
public-release item.

## 0. Candidate freeze and local release evidence

- [x] Freeze version `1.2.2+13` and bind the owner approval to that version.
- [x] Remove compiled review phone/OTP/local-auth bypasses; use the production
  Supabase OTP gateway with test-only injection.
- [x] Pin GitHub Actions to immutable commits and update vulnerable Ruby
  dependencies; Bundler Audit reports no known vulnerabilities.
- [x] Pass Flutter analysis and the canonical pre-documentation test suite.
- [x] Pass Android JVM tests with debug signing explicitly separated from Play
  app signing.
- [x] Build signed Android APK/AAB 13 from an ephemeral public-config file.
- [x] Verify upload-certificate pin, merged permissions, R8, signature, target
  SDK 36, 16 KB alignment, App Links, metadata, and Bundletool validation.
- [x] Build the Apple Distribution IPA 13 from an ephemeral public-config file.
- [x] Verify production APNs entitlement, `get-task-allow=false`, Associated
  Domains, provisioning, privacy manifests, dSYMs, and absence of review-bypass
  strings.
- [x] Validate and upload IPA 13 with Apple's official transporter.
- [x] Confirm TestFlight build 13 is `Ready to Submit` and assigned internally.
- [x] Attach build 13 to App Store version 1.2.2 and save accurate review notes.
- [x] Rerun the full canonical suite after the final docs/build-wrapper changes;
  static analysis is clean and all 459 Flutter tests pass.
- [ ] Run the release, artifact, and security diff gates on the exact committed
  revision and retain their evidence with the commit SHA.

## 1. Reviewer access and backend notification providers

- [ ] Accountable owner creates or designates a dedicated least-privilege review
  identity with synthetic data and no authority over real funds or customers.
- [ ] Configure a server-authenticated reviewer OTP/test flow in Supabase; keep
  phone, passwords, and OTPs outside source, logs, screenshots, and docs.
- [ ] Prove clean-install reviewer login, logout, account deletion, disabled
  real-money actions, and post-review credential rotation/removal.
- [ ] Select the APNs key strategy: recover the existing private key or rotate
  only after assessing impact on other apps sharing the team keys.
- [ ] Set `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, and
  `APNS_PRIVATE_KEY_BASE64` in Supabase secrets; deploy notification functions.
- [ ] Create a least-privilege Firebase/Google service account and set
  `FCM_SERVICE_ACCOUNT_JSON` in Supabase secrets.
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
- [ ] Reconnect and unlock the registered iPhone; install TestFlight build 13.
- [ ] Run iOS camera and notification dialogs, allow/deny/recovery, deep links,
  foreground/background/terminated notifications, token refresh, offline/online,
  process termination, and account deletion.
- [ ] Run VoiceOver, Voice Control where available, Larger Text, Bold Text,
  Increase Contrast, Differentiate Without Color, Reduce Motion, portrait/
  landscape, and iPad multitasking checks.
- [ ] Complete at least one internal TestFlight install/session and review
  crashes, screenshots, and feedback for build 13.
- [ ] Record only sanitized screenshots/logs and accountable pass/fail signoff;
  do not convert persona owner waivers into human test claims.

## 3. Apple App Store Connect closure

- [x] Current iPhone/iPad screenshots, description, keywords, support/marketing
  URLs, privacy URL, copyright, category, encryption declaration, age rating,
  privacy disclosures, and manual-release mode are populated.
- [x] Build 13 is selected on version 1.2.2; build 10 is no longer selected.
- [x] Review notes state that build 13 has no embedded reviewer bypass.
- [ ] Replace the pending reviewer fields with the validated dedicated account
  from section 1 and re-read the saved values without copying them to the repo.
- [ ] Corporate owner completes the DSA trader/non-trader assessment and retains
  the decision basis.
- [ ] Reconcile App Privacy with actual Supabase tables, analytics/crash tools,
  photos, payment/financial data, user/device IDs, support, and user content.
- [ ] Recheck age rating, financial features, content rights, export compliance,
  support contact, territory availability, pricing, and release mode.
- [ ] Confirm App Accessibility declarations only after physical VoiceOver and
  other claimed-feature evidence exists; publish when Apple permits.
- [ ] Add version 1.2.2/build 13 for review and answer the final submission
  prompts. Retain the submission ID, timestamp, and exact state.
- [ ] Monitor `Waiting for Review`, `In Review`, messages, metadata rejections,
  binary rejections, and resolution-center requests; respond without changing
  untested scope.
- [ ] After `Ready for Distribution`, perform the intentional manual release,
  verify the public product page/install, and run a production smoke test.

## 4. Google Play Console closure

- [x] Version 12 full production rollout and receive-only SMS/Advertising ID
  declarations are currently in review.
- [x] Version 13 local AAB passes package, signature, target-SDK, 16 KB, App
  Links, privacy/account-deletion URLs, metadata, screenshot, and Bundletool
  checks.
- [ ] Do not disturb the active version-12 review without recording the decision.
  When Google responds, decide whether to replace the draft/review immediately
  with version 13 or complete review and then roll version 13 as the security
  update.
- [ ] Upload AAB 13 with the registered Play upload key, add changelog 13, and
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
- [ ] Run and clear the version-13 pre-launch report: crashes, ANRs,
  accessibility, security/privacy, compatibility, and rendering findings.
- [ ] Authorize the least-privilege Play Developer Reporting API identity or
  capture authenticated Console evidence for crash rate, ANR rate, slow
  rendering/startup, excessive wakeups, and bad-behavior thresholds.
- [ ] Submit the version-13 production change, retain the review timestamp/state,
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
- [ ] Archive store submissions, provider configuration receipts, physical UAT,
  TestFlight/Play reports, approvals, rollback procedures, and support/on-call
  ownership.

## Definition of done

`Fully submitted` means both store version records contain the exact approved
binary and metadata and show a submitted review state. `Approved` means each
store has accepted the app. `Released` means the approved version is publicly
available in the intended territories. These three states must never be merged
into one claim.
