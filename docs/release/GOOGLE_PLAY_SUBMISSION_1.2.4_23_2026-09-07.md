# Collect 1.2.4 (23) Google Play submission preparation

**Status:** signed candidate and Play metadata prepared; not uploaded, not submitted for review, not approved, and not live.

## Release candidate

| Item | Value |
|---|---|
| Package | `app.cool.mobile` |
| Track | Production draft target |
| Version | `1.2.4 (23)` |
| AAB | `build/app/outputs/bundle/productionRelease/app-production-release.aab` |
| AAB SHA-256 | `0064221fbf0dd23e12f47d5e9d2b90d71e8bc3b89a5d179fca58ffa5d4d2dc34` |
| AAB size | 85,694,410 bytes |
| APK | `build/app/outputs/flutter-apk/app-production-release.apk` |
| APK SHA-256 | `1bc238d8deadb221d0e1ab9ac94ab8484ef93c0e418b6ab098121af8167a9dec` |
| APK size | 95,234,232 bytes |
| Upload certificate SHA-256 | `9EE12172C78A8A487906D9159BFDD17B4D78ABA3541F17B410659E6D60DDCC10` |

The production runtime endpoint is present in the APK and AAB. The APK reports minimum SDK 24, target SDK 36 and compile SDK 36. The APK passes 16 KB zip alignment.

## Listing package

The Fastlane metadata under `fastlane/metadata/android/en-US` contains the current title, short description, full description and version-23 release notes. The full description now matches the Android permission model: a group receiver can optionally allow newly arriving MTN MoMo or Airtel Money transaction-confirmation SMS for candidate reconciliation. It does not claim that the Android app requests no SMS permission.

The listing contains six visually reviewed current-app screenshots in each required form factor:

- Phone: 1080 × 1920
- 7-inch tablet: 1200 × 1920
- 10-inch tablet: 1600 × 2560

The routes are Home, Groups, Featured Groups, Group detail, Rwanda MoMo contribution and Activity. They use the actual `CollectApp`, production router and production widgets with an explicitly synthetic repository. The tracked capture record is `docs/release/GOOGLE_PLAY_SCREENSHOT_CAPTURE_1.2.4_23.json`. The screenshots are store artwork and are not evidence of signed-release mobile-design acceptance.

## Permission and console state

The production APK requests `RECEIVE_SMS` as its only restricted SMS permission. It does not request `READ_SMS`, `SEND_SMS`, `BROADCAST_SMS`, or Call Log access. The SMS receiver is protected by `android.permission.BROADCAST_SMS`; that receiver guard is not an app-requested permission. The manifest parser and its tests fail closed around this distinction.

The live Play Console currently shows `Collect 1.2.2 (21)` active at 100% in 23 countries/regions, with no unpublished changes. The App content page has no item under Need attention. The SMS declaration is actioned with **SMS based money management** selected. Version 23 still needs Play processing and approval after upload.

## Validation result

| Gate | Result |
|---|---|
| Metadata export | Pass |
| Packet fields and text limits | Pass |
| APK/AAB hash binding | Pass |
| Upload-key signing preflight | Pass |
| Screenshot counts, hashes and dimensions | Pass |
| Public website, privacy, deletion and App Links URLs | Pass |
| Production permission scope | Pass |
| Google Play SMS approval for version 23 | Pending upload and Play review |
| Play Developer Reporting snapshot | Blocked by Reporting API authentication |
| Post-upload console surface audit | Pending upload |
| `MOBILE-DESIGN-100` | Blocked; owner acceptance/provenance, 134 Android cases and 23 annotation closures remain open |

`MOBILE-DESIGN-100` is a mandatory production gate. This candidate must not be represented as production approved or submitted until that gate passes. Upload, Play review, approval, rollout and public availability remain separate later states.

## Official policy references

- [Google Play SMS and Call Log permissions policy](https://support.google.com/googleplay/android-developer/answer/10208820?hl=en)
- [Google Play preview asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
- [Android receiver manifest reference](https://developer.android.com/guide/topics/manifest/receiver-element)
