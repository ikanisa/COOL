# Google Play Optimization Surface Matrix

Generated: 2026-06-21

Package: `app.cool.mobile`

Target build: `1.2.2+9`

## Source Baseline

Official references used for this matrix:

- Google Play target API requirements: https://support.google.com/googleplay/android-developer/answer/11926878
- Android 16 KB page-size guidance: https://developer.android.com/guide/practices/page-sizes
- Android App Links: https://developer.android.com/training/app-links
- Play Console Deep links page: https://support.google.com/googleplay/android-developer/answer/12463044
- Google Digital Asset Links: https://developers.google.com/digital-asset-links/v1/getting-started
- Play Integrity API: https://developer.android.com/google/play/integrity
- Android vitals: https://developer.android.com/topic/performance/vitals
- Play Developer Reporting API: https://developers.google.com/play/developer/reporting
- Core app quality: https://developer.android.com/docs/quality-guidelines/core-app-quality
- Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- App review readiness: https://support.google.com/googleplay/android-developer/answer/9859455
- Account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Permissions declarations: https://support.google.com/googleplay/android-developer/answer/9214102
- Managed publishing: https://support.google.com/googleplay/android-developer/answer/9859654
- Android Publisher API: https://developers.google.com/android-publisher
- Android Publisher REST API: https://developers.google.com/android-publisher/api-ref/rest
- Testing tracks: https://support.google.com/googleplay/android-developer/answer/9845334
- Custom store listings: https://support.google.com/googleplay/android-developer/answer/9867158

## Audit Matrix

| Surface | Current evidence | Status | Required next proof |
| --- | --- | --- | --- |
| Release management | Production APK/AAB `1.2.2+9`; AAB SHA-256 `c403edcd24fab2fb7b11d1306ade42bfaa149a27b5e2c28cd064c6da1f048e0b`; live Console shows release `8 (1.2.1)` rejected and release `7 (1.2.0)` available. | Blocked by upload auth/file permission | Upload AAB to draft release `9`, submit production update, then record Publishing overview state. |
| Publisher API automation | `scripts/google_play_production_upload.sh --json` validates the bundle into `.cache/google_play_optimization/android_publisher_upload_v9_dry_run.json`; `--submit --json` writes sanitized submit evidence into `.cache/google_play_optimization/android_publisher_upload_v9.json` without creating an edit when auth is unavailable. | Implemented, auth blocked | Re-run `scripts/google_play_production_upload.sh --submit --json` after Android Publisher credentials are available. |
| Managed publishing | Earlier Console check observed managed publishing off. | Console-controlled | Decide whether to turn managed publishing on before production submission; record current state from Publishing overview. |
| Target API and Android compatibility | Gate reads APK metadata: package `app.cool.mobile`, versionCode `9`, versionName `1.2.2`, compileSdk `36`, targetSdk `36`, minSdk `24`. | Pass | Keep gate in release evidence for every production submission. |
| 16 KB page-size readiness | `zipalign -P 16` passes; AAB includes native libraries. | Pass | Confirm Play pre-launch/device catalog after upload. |
| Production permissions | APK excludes restricted SMS permissions; production permissions are Internet, Camera, Notifications, Vibration, Network State, and app dynamic receiver permission. | Pass | Verify Play permissions declaration after AAB upload; keep SMS receiver isolated to `internal_receiver`. |
| Policy URLs | `https://collect.ikanisa.com/privacy/`, `/account-deletion/`, and `/data-deletion/` return HTTP 200. | Pass | Confirm these exact URLs in Play App content and Store settings. |
| Data safety/App content | `docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET_2026-06-21.json` now records privacy, deletion, Data safety categories, app access prompt, policy declarations, and production permission scope. | Repo packet pass, Console audit pending | Confirm the packet values in Play App content and record current Console evidence. |
| App access | No login credentials were recorded for reviewers in this evidence bundle. | Needs Console audit | Verify whether Play requires app access instructions for review, especially if reviewer cannot reach post-login flows. |
| Deep links/App Links | Manifest has `android:autoVerify="true"` for `https://collect.ikanisa.com/c`; live `assetlinks.json` returns HTTP 200 and includes package/fingerprint. | Repo/live pass | Verify Play Console Deep links app configuration and web URL status after AAB upload. |
| Store listing | Public landing and assets exist; app icon source exists; `docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET_2026-06-21.json` records title, descriptions, category, contact details, listing assets, custom listing ideas, and experiment candidates. `scripts/google_play_metadata_export.sh --json` writes fastlane-compatible metadata under `fastlane/metadata/android/en-US/`. | Repo packet and metadata pass, Console audit pending | Confirm title, descriptions, category, tags, contact details, website, icon, feature graphic, and screenshots in Play Console. |
| Custom store listings | Product segments are identified: Rwanda community groups, diaspora savings, provider/partner-facing credit readiness. | Not configured in repo | Create only after default listing is approved and Console eligibility allows custom listings. |
| Store listing experiments | No baseline experiment evidence. | Not started | Run icon/screenshot/short-description experiments after production listing is approved and traffic is sufficient. |
| Testing tracks | Console packet now requires internal, closed/open testing, tester list, and opt-in link evidence. Production track was inspected; internal/closed/open tracks were not audited in this run. | Repo packet pass, Console audit pending | Verify internal testing for smoke AABs, closed/open testing eligibility, tester lists, and opt-in links. |
| Distribution/device catalog | AAB build exists; Console packet requires device reach, exclusions, form-factor support, country distribution, and app-size evidence. | Repo packet pass, Console audit pending | Record device reach, excluded devices, Android XR/ChromeOS/tablet compatibility, countries/regions, and app size after upload. |
| Pre-launch report | Not available until Play processes an uploaded release. | Pending upload | Review stability, security, accessibility, and device-language results before widening rollout. |
| Android vitals | `scripts/google_play_reporting_snapshot.sh --json` queries crash, ANR, slow start, slow rendering, excessive wakeup, stuck background wakelock, and error count metric sets when Play Developer Reporting credentials are available. | Auth blocked | Query crash, ANR, wakeup/wakelock, slow/frozen frame, and bad behavior thresholds when Play reporting credentials work. |
| Crash/performance telemetry | No Firebase Crashlytics, Firebase Analytics, Sentry, or Performance dependency found in `pubspec.yaml`. | Product gap | Add telemetry intentionally only after privacy/Data safety updates and owner approval for data collection. |
| Play Integrity/security | Console showed Play App Signing and automatic protection enabled. Native Android token request, Flutter service contract, and Supabase `verify-play-integrity` token verification endpoint are implemented without embedded secrets. | Repo implementation pass, deploy/config pending | Configure `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` at build time and `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON` as a Supabase secret, deploy the function, then verify live verdicts for abuse-prone actions. |
| Monetization/readiness | No Play Billing dependency; current product appears non-IAP. | Not applicable now | Do not enable Play Billing until product scope requires paid digital goods/subscriptions; record monetization status in Console. |
| Analytics/reporting | No app analytics SDK found; release scripts write local evidence. | Partial | Add privacy-safe analytics only after Data safety alignment, or rely on Play acquisition/reporting exports through account APIs. |
| Repo evidence | `scripts/google_play_optimization_gate.sh`, `scripts/google_play_production_upload.sh`, `scripts/google_play_console_audit_packet.sh`, this matrix, and the Console audit packet now define release evidence surfaces. | Implemented | Keep generated JSON outputs in `.cache/google_play_optimization/` and summarize durable results in `docs/release/`. |

## Immediate Submission Commands

Dry-run:

```bash
scripts/google_play_production_upload.sh --json
scripts/google_play_console_audit_packet.sh --json
```

Submit after credentials are available:

```bash
scripts/google_play_production_upload.sh --submit --json
```

The script supports `GOOGLE_APPLICATION_CREDENTIALS` service-account JSON, scoped ADC/gcloud auth, `ANDROID_PUBLISHER_ACCESS_TOKEN`, or `ANDROID_PUBLISHER_ACCESS_TOKEN_CMD`. It intentionally omits tokens, credential paths, signing keys, cookies, and customer data from evidence output.
