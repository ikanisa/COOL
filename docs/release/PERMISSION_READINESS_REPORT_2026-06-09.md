# COOL App Permission Readiness Report - 2026-06-09

## Scope

This report covers native app permissions and runtime permission flows for the COOL Flutter app across Android and iOS.

## Implementation Status

| Area | Status | Evidence |
| --- | --- | --- |
| Android production permissions | Complete | Production manifest excludes restricted SMS permissions; release gate passes `production_restricted_sms_permissions_absent`. |
| Android internal SMS receiver scope | Complete | `internal_receiver` flavor manifest contains restricted SMS permissions; release gate passes `internal_receiver_sms_permissions_present`. |
| Android SMS runtime flow | Complete | Native channel requests and verifies SMS runtime grants before enabling ingestion; release gate passes `android_sms_runtime_permission_request`. |
| Android notification runtime | Complete | `flutter_local_notifications` is wired with Android notification permission request, local channel creation, and hashed install registration. |
| Android notification build support | Complete | Core library desugaring is enabled for `flutter_local_notifications`; production APK/AAB builds pass. |
| iOS permission declarations | Complete | `Info.plist` declares camera and photo-library usage only; contacts/NFC/APNs overclaims are absent. |
| iOS notification runtime | Complete | `flutter_local_notifications` iOS implementation builds through Flutter generated Swift package integration; notification permission is requested through the native plugin. |
| Permission recovery UX | Complete | Recovery actions use native OS permission/settings flows instead of setting local provider state directly. |
| Accessibility on permission-adjacent flows | Complete | Legal consent and mobile completion accessibility tests pass after contrast token hardening. |

## Device Evidence

| Evidence | Result | Path |
| --- | --- | --- |
| Pixel 4a signed production APK install and launch smoke | Passed | `.cache/permission_device_evidence/20260609T080100Z/android_permissions.txt` |
| Pixel 4a installed package permission dump | Passed: requested `INTERNET`, `CAMERA`, `POST_NOTIFICATIONS`, `VIBRATE`, dynamic receiver permission, and network state; no `READ_SMS`, `RECEIVE_SMS`, `SEND_SMS`, or `BROADCAST_SMS` in the installed production package. | `.cache/permission_device_evidence/20260609T080100Z/android_permissions.txt` |
| Full Android device UAT | Failed on stale non-permission expectation for text `Contribute`. | `.cache/android_device_uat/20260609T072931Z/summary.json` |
| Android route-matrix device UAT | Timed out before completing Gradle build. | `.cache/android_device_uat/20260609T074504Z/summary.json` |

## Build Evidence

| Command | Result |
| --- | --- |
| `flutter build apk --release --flavor production --no-pub` | Passed; produced `build/app/outputs/flutter-apk/app-production-release.apk`. |
| `flutter build appbundle --release --flavor production --no-pub` | Passed; produced `build/app/outputs/bundle/productionRelease/app-production-release.aab`. |
| `flutter build ios --release --flavor production --no-codesign --no-pub` | Passed; produced `build/ios/iphoneos/Collect.app`. |

## Remaining Release Blockers

These are release-governance blockers, not code-owned permission implementation gaps:

| Blocker | Required action |
| --- | --- |
| `android_release_signing_review` | Record explicit Android release signing / Play App Signing review in `docs/release/RELEASE_APPROVALS.json` with sanitized evidence and no signing-key exposure. |
| `ios_release_scope` | Record signed iOS release-scope evidence or explicitly mark iOS out of scope in `docs/release/RELEASE_APPROVALS.json`. |

Do not mark the release goal complete until the release approval records are valid and the final mobile release gate passes against current source artifacts.
