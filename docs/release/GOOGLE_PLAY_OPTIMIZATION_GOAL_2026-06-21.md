# Google Play Optimization Goal

Generated: 2026-06-21

## Objective

Make Collect's Google Play production setup complete, evidence-backed, and repeatable across release, policy, quality, growth, integrity, and monitoring surfaces for package `app.cool.mobile`.

## Current State

- Earlier Play Console publishing overview was observed in Chrome with `Changes in review`, including `Production` and `App content` changes.
- Managed publishing was observed as off in that earlier Chrome check.
- Live Play Console production track was rechecked on 2026-06-21: release `8 (1.2.1)` is `Update rejected`, and release `7 (1.2.0)` remains available on Google Play.
- A fresh production APK/AAB build is available at version `1.2.2+9`.
- `https://collect.ikanisa.com/#/privacy` is the official Play privacy, account deletion, and data deletion URL, and the public fallback contains deletion request instructions for automated review.
- On 2026-06-22, Play Console App content was updated so Privacy policy URL, Data safety Delete account URL, and Data safety Delete data URL all use `https://collect.ikanisa.com/#/privacy`.
- Publishing overview then showed these App content changes under `Changes in review`; final browser verification said `Your changes are now in review. We may find additional issues when reviewing your app.`
- `https://admin.collect.ikanisa.com/custom-sw.js` and `https://admin.collect.ikanisa.com/main.dart.js` return HTTP 200.
- `https://collect.ikanisa.com/.well-known/assetlinks.json` is now deployed and returns HTTP 200.
- Play Console draft release `9` was opened for the production track. A fresh Chrome check on 2026-06-21 confirmed it is still on `Create production release` with an `Upload` control and no uploaded app bundle for release `9`; local browser upload is blocked by Chrome automation file-chooser/file-access behavior and Android Publisher API auth is expired/non-interactive.

## Official Source Map

- Target API requirements: https://support.google.com/googleplay/android-developer/answer/11926878
- 16 KB page size readiness: https://developer.android.com/guide/practices/page-sizes
- Android App Links: https://developer.android.com/training/app-links
- Play Console Deep links page: https://support.google.com/googleplay/android-developer/answer/12463044
- Play Integrity API: https://developer.android.com/google/play/integrity
- Android vitals: https://developer.android.com/topic/performance/vitals
- Play Developer Reporting API: https://developers.google.com/play/developer/reporting
- Core app quality: https://developer.android.com/docs/quality-guidelines/core-app-quality
- Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Android Publisher API: https://developers.google.com/android-publisher
- Android Publisher REST resources: https://developers.google.com/android-publisher/api-ref/rest
- Managed publishing: https://support.google.com/googleplay/android-developer/answer/9859654
- Open, closed, and internal testing tracks: https://support.google.com/googleplay/android-developer/answer/9845334
- Store listing customizations: https://support.google.com/googleplay/android-developer/answer/9867158
- Permissions declarations: https://support.google.com/googleplay/android-developer/answer/9214102

## Implemented Repo Controls

- Added `web/.well-known/assetlinks.json` for verified Android App Links on `collect.ikanisa.com`.
- Updated `scripts/public_landing_prepare_build.sh` so the asset links file is copied into every public web build.
- Added `scripts/google_play_optimization_gate.sh` to verify:
  - APK package identity, version, compile SDK, target SDK, and permissions.
  - Fresh APK/AAB relative to Android, Dart, pubspec, and assetlinks sources.
  - 16 KB APK packaging alignment with `zipalign -P 16`.
  - Restricted SMS permissions excluded from production and isolated to the internal receiver flavor.
  - Play policy URLs and Admin PWA live assets.
  - App Links source and live deployment state.
  - Required Play Console surfaces still needing recorded live audit evidence.
- Added `scripts/google_play_production_upload.sh` as a repeatable Android Publisher API uploader with dry-run mode, service-account support, scoped ADC/gcloud token support, sanitized evidence output, and failed-edit cleanup.
- Added `docs/release/GOOGLE_PLAY_PRODUCTION_SUBMISSION_2026-06-21.md` to keep the production upload evidence and current blockers separate from general optimization planning.
- Added `docs/release/GOOGLE_PLAY_OPTIMIZATION_SURFACE_MATRIX_2026-06-21.md` as the current capability-by-capability audit matrix for release, listing, policy, vitals, integrity, deep links, testing, distribution, monetization, analytics, and evidence automation.
- Added `docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET_2026-06-21.json` and `scripts/google_play_console_audit_packet.sh` to make store listing, app content, Data safety, policy, release, growth, testing, integrity, vitals, and reporting surfaces machine-checkable without storing Play credentials or customer data.
- Added `scripts/google_play_metadata_export.sh` to generate fastlane-compatible Play listing metadata and release notes from the Console audit packet.
- Added `fastlane/Supplyfile` and `fastlane/Fastfile` for a standard, non-secret `supply` upload path after Play service-account JSON is available through the environment.
- Added `scripts/google_play_reporting_snapshot.sh` and `docs/release/GOOGLE_PLAY_OPERATIONAL_READINESS_2026-06-21.md` for Android vitals/reporting automation, Play Integrity rollout design, testing-track use, distribution review, and monetization readiness.
- Added native Android, Flutter, and Supabase Play Integrity implementation surfaces: `collect/play_integrity`, `PlayIntegrityService`, and `verify-play-integrity`.

## Play Console Completion Workstreams

1. Release management
   - Rebuild APK/AAB after current repo changes.
   - Increment version code above `8`.
   - Upload the new AAB only after local gates pass.
   - Confirm production track rollout, release notes, country availability, managed publishing choice, and review status.

2. App content and policy
   - Confirm privacy policy URL is `https://collect.ikanisa.com/#/privacy`.
   - Confirm account deletion and data deletion URLs are `https://collect.ikanisa.com/#/privacy`.
   - Complete Data safety for account, financial/group ledger, device, camera, notification, and SMS-evidence processing exactly as implemented.
   - Confirm permissions declaration does not request restricted production SMS permissions.
   - Confirm financial features, content rating, target audience, ads, news, health, government, and data deletion answers match the app.

3. Store growth surfaces
   - Main store listing: title, short description, full description, icon, feature graphic, phone screenshots, category, tags, contact email, and website.
   - Custom store listings: Rwanda community groups, diaspora group savings, and provider/partner-facing variants if Play eligibility allows.
   - Store listing experiments: screenshot/short-description tests after baseline listing is approved.
   - Promotional content and deep-link campaigns only after production listing is live.

4. Quality and diagnostics
   - Android vitals: crash rate, ANR rate, excessive wakeups, slow rendering, frozen frames, and bad behavior thresholds.
   - Pre-launch report: accessibility, security, stability, performance, and device compatibility findings.
   - Device catalog and app size: review unsupported devices, form factors, and delivery splits from the AAB.
   - 16 KB page-size readiness: keep local `zipalign -P 16` proof and Play pre-launch/device proof.

5. Integrity and security
   - Play App Signing review remains recorded in `docs/release/RELEASE_APPROVALS.json`.
   - Enable or verify Play Integrity API strategy before relying on production attestation for abuse controls.
   - Review automatic integrity protection / Protect with Play options in Console.
   - Keep release service-account credentials out of the repo; only store secret paths in local environment or CI secrets.

6. Reporting and automation
   - Keep `scripts/google_play_optimization_gate.sh --json` in the release evidence bundle.
   - If a Play Developer API service account is available, add a non-secret uploader wrapper for Android Publisher API/fastlane supply.
   - Record Play Console screenshots or exported metadata for the surfaces listed in the gate before marking this goal complete.

## Current Blockers

- `google_play_upload_auth`: `gcloud auth application-default print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher` is rejected because ADC was not granted the Android Publisher scope; unscoped ADC and both local gcloud user accounts require interactive reauthentication.
- `chrome_file_upload_permission`: Play Console file chooser opens, but `fileChooser.setFiles` fails with `Not allowed`, which indicates the Codex Chrome Extension cannot attach local files from this Chrome profile until file URL access/upload permission is enabled.
- `play_console_surface_audit_required`: account-controlled Play Console pages still need recorded current audit evidence after the new build is uploaded/submitted.
- `google_play_review_pending`: Publishing overview shows the privacy/Data safety correction under `Changes in review`; Google review has not yet accepted or published the corrected policy metadata.
- `play_integrity_live_config`: Play App Signing and automatic protection are enabled in Console, and native/server Play Integrity code now exists, but live activation still needs `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER`, a deployed `verify-play-integrity` function, and a Supabase `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON` secret.
- `play_reporting_api_auth`: Android vitals reporting can be automated through the Play Developer Reporting API, but the same Play developer auth blocker prevents live metric retrieval.

## Done Criteria

- `scripts/google_play_optimization_gate.sh --json` exits pass.
- Existing mobile release gate exits pass.
- Public landing deploy serves policy pages and `/.well-known/assetlinks.json` with HTTP 200.
- New AAB `1.2.2+9` is uploaded to the appropriate Play production workflow.
- Publishing overview shows the intended changes submitted for review or published.
- Play Console audit evidence is recorded for release, app content, store listing, deep links, Android vitals, pre-launch report, app integrity, device catalog, and experiments/growth surfaces.
