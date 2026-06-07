# Collect Brand Physical Device QA - 2026-06-07

## Result

Status: Passed for the Collect brand/app-icon physical-device visual scope.

This evidence covers the production Android release build installed and visually checked on a real device, not an emulator.

## Device

- Device: Pixel 4a
- Device id: `13111JEC215558`
- OS: Android 13, API 33
- Screen: 1080x2340
- Density: 440 dpi

## Build Artifacts

- APK: `build/app/outputs/flutter-apk/app-production-release.apk`
- APK size: 79.3 MB reported by Flutter build output
- APK SHA-256: `12b585bfa74f90c9136b5e30efe585e440523c5d7443d193c1f3afdd346db968`
- AAB: `build/app/outputs/bundle/productionRelease/app-production-release.aab`
- AAB size: 71.0 MB reported by Flutter build output
- AAB SHA-256: `abe249bbd0ea72f5a8f7b3e9160142adeef09966aee7e7928c46e2f5c25222d3`

## Installed Package

- Package: `app.cool.mobile`
- Version name: `0.1.0`
- Version code: `1`
- Min SDK: 24
- Target SDK: 36
- Install result: `Success`

## Visual Evidence

- Physical device home screen: `docs/design/device_qa/2026-06-07-pixel4a-brand/home-device.png`
- Physical device create-group screen: `docs/design/device_qa/2026-06-07-pixel4a-brand/group-create-device.png`
- Physical device recent-apps icon proof: `docs/design/device_qa/2026-06-07-pixel4a-brand/recent-app-icon-device.png`

## Verification

- `flutter analyze`: passed with no issues.
- `flutter test --reporter expanded`: passed, 188 tests.
- `flutter build apk --release --flavor production -t lib/main.dart`: passed.
- `flutter build appbundle --release --flavor production -t lib/main.dart`: passed.
- APK signature verification: passed with Android APK Signature Scheme v2 and 1 signer.
- AAB signature verification: `jar verified`.

## Notes

- The screenshots were captured from the physical Pixel 4a using the freshly installed production release APK.
- A system accessibility floating button is visible on the device screenshots. It is an OS overlay from the test device, not part of the Collect app UI.
- The recent-apps screenshot is used for physical icon proof because the launcher/app drawer did not expose a clean searchable app icon view during automated capture.
- Gradle emitted future compatibility warnings for dependencies that still apply Kotlin Gradle Plugin. These warnings did not fail the release APK or AAB build.
