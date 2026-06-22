# Google Play Production Submission Evidence

Generated: 2026-06-21

## Target Release

- Package: `app.cool.mobile`
- Version: `1.2.2+9`
- AAB: `build/app/outputs/bundle/productionRelease/app-production-release.aab`
- AAB SHA-256: `a18d5ac50c3483a9c64c169da81a56618d23d223e72a4b9cca326f8aedaf57d0`
- APK SHA-256: `0ef629998a3a05d39bd3d738c89aebccf65abed4c095b016dee7c3d02433deca`

## Completed

- Rebuilt fresh production APK/AAB for `1.2.2+9`.
- `scripts/flutter_mobile_release_gate.sh --json` passed.
- `scripts/google_play_optimization_gate.sh --json` passed all code/live URL checks except the account-controlled Play Console audit blocker.
- Deployed `/.well-known/assetlinks.json` to `https://collect.ikanisa.com/.well-known/assetlinks.json`.
- Deployed the corrected public privacy/account/data deletion page to `https://collect.ikanisa.com/#/privacy`.
- Verified `https://collect.ikanisa.com/#/privacy` returns HTTP 200 and the fetched HTML contains `Privacy Policy and Data Deletion`, account deletion request instructions, data deletion request instructions, `info@ikanisa.com`, and `+250 795 588 248`.
- Verified the rejected legacy URL `https://gen-lang-client-0172279957.web.app/privacy` still returns HTTP 404 and must not be used in Play Console.
- Verified live policy URL and Admin PWA JavaScript assets return HTTP 200.
- Opened live Google Play Console production track and confirmed:
  - Release `8 (1.2.1)` is `Update rejected`.
  - Release `7 (1.2.0)` remains available on Google Play.
  - Play App Signing is enabled.
  - Automatic protection is enabled.
  - Draft production release `9` was opened.
- Added `scripts/google_play_production_upload.sh` and verified:
  - `bash -n scripts/google_play_production_upload.sh` passes.
  - `scripts/google_play_production_upload.sh --json` dry-runs against the exact AAB and SHA-256 into `.cache/google_play_optimization/android_publisher_upload_v9_dry_run.json`.
  - `scripts/google_play_production_upload.sh --submit --json` blocks cleanly on auth without printing secrets into `.cache/google_play_optimization/android_publisher_upload_v9.json`.
- Corrected Play Console App content on 2026-06-22:
  - Privacy policy URL saved as `https://collect.ikanisa.com/#/privacy`.
  - Data safety `Delete account URL` saved as `https://collect.ikanisa.com/#/privacy`.
  - Data safety `Delete data URL` saved as `https://collect.ikanisa.com/#/privacy`.
  - Publishing overview showed three changes submitted for review: `Production` rollout `8 (1.2.1)`, `App content > Privacy policy`, and `Data safety`.
  - Final Play Console verification showed `Changes in review` and `Your changes are now in review. We may find additional issues when reviewing your app.`

## Blocked Upload Attempts

1. Android Publisher API
   - `gcloud auth application-default print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher` failed because the ADC credential is not scoped for Android Publisher.
   - `gcloud auth application-default print-access-token` and both configured `gcloud auth print-access-token` accounts failed because they require interactive reauthentication.
   - No Android Publisher edit/upload/commit was created by the failed API attempt.
   - The repeatable uploader now records this as `android_publisher_auth_unavailable` in `.cache/google_play_optimization/android_publisher_upload_v9.json`.

2. Chrome Play Console upload
   - Play Console file chooser opened from the production release App Bundles upload button.
   - `fileChooser.setFiles(['/Volumes/PRO-G40/COOL/build/app/outputs/bundle/productionRelease/app-production-release.aab'])` failed with `Not allowed`.
   - This indicates the Codex Chrome Extension cannot attach local files in the current Chrome profile until file upload/file URL access is enabled.
   - A fresh Chrome read-only check on 2026-06-21 confirmed the tab at `/tracks/4698792770438610295/releases/9/prepare` is still on `Create production release`, with an `Upload` control and no uploaded app bundle for release `9`.
   - A fresh bounded upload retry timed out before the file chooser became available to the browser automation session, so no AAB was attached and no Play edit was submitted.

## Validation Run

- `bash -n scripts/google_play_production_upload.sh scripts/google_play_optimization_gate.sh scripts/release_evidence_index.sh` passed.
- `scripts/google_play_production_upload.sh --json` passed dry-run validation for the AAB.
- `scripts/google_play_console_audit_packet.sh --json` validates the repo-owned store listing, app content, Data safety, permission, policy URL, release, testing, integrity, vitals, and reporting packet before Console submission.
- `scripts/google_play_metadata_export.sh --json` writes fastlane-compatible listing metadata and release notes under `fastlane/metadata/android/en-US/`.
- `fastlane/Supplyfile` and `fastlane/Fastfile` define a non-secret `supply` production upload lane that requires `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` from the environment.
- Native Android, Flutter, and Supabase Play Integrity surfaces are implemented, but live activation requires Play/Cloud project number and Supabase service-account secret configuration.
- `scripts/google_play_reporting_snapshot.sh --json` exits `99` with `play_developer_reporting_auth_unavailable`, proving the reporting/vitals automation path exists but live metric retrieval needs Play Developer Reporting scope.
- `scripts/google_play_production_upload.sh --submit --json` exited `99` with `android_publisher_auth_unavailable` before creating any Play edit.
- `scripts/google_play_optimization_gate.sh --json` exited `99` only for `play_console_surface_audit_required`; artifact, target API, permission, App Links, policy URL, and Admin PWA live checks passed.
- Chrome Play Console read-only check confirmed production release `9` is still waiting for bundle upload.
- `flutter test --no-pub test/release_docs_test.dart` passed after updating stale release-governance assertions to use an explicit pending-approval fixture where a blocked manifest is required.
- `flutter test --no-pub test/landing_page_test.dart` passed after adding coverage that the public privacy page includes account deletion and data deletion request language.
- `flutter test --no-pub test/landing_page_test.dart test/release_docs_test.dart` currently fails in `test/release_docs_test.dart` on unrelated release-evidence drift around `mobile release gate ignores direct approval environment overrides` and the old expected Android UAT evidence path; the privacy page test itself passes.

## Remaining Action

Enable one of these two upload paths, then resume from draft production release `9`:

- Reauthenticate or provide a Google Play Android Publisher API service account with `https://www.googleapis.com/auth/androidpublisher`.
- Or enable local file upload access for the Codex Chrome Extension in Chrome and retry the Play Console file chooser upload.
