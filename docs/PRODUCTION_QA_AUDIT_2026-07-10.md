# Collect Production QA Audit - 2026-07-10

## Scope

Audit and repair checkpoint for Collect across the local web app, Flutter code/tests, iOS Simulator, and Android build/emulator readiness.

## Fixes Applied

- Groups page no longer repeats the home hero/action row inside the Groups surface.
- Mobile connectivity warning top padding now clears compact top chrome instead of overlapping it.
- Web QR scanner route now shows a clear mobile-app fallback instead of hanging on camera startup.
- Collect web bootstrap no longer registers the admin-only `custom-sw.js` when the admin service worker version placeholder is not replaced.
- iOS CocoaPods sandbox was refreshed after Xcode reported it was out of sync.
- Android malformed NDK `28.2.13676358` install was moved aside and reinstalled cleanly through `sdkmanager`.

## Evidence

- Web groups fixed: `/tmp/collect-production-audit/screenshots-after-fixes/01-desktop-groups-fixed.png`
- Mobile web groups fixed: `/tmp/collect-production-audit/screenshots-after-fixes/02-mobile-groups-fixed.png`
- Web scanner fallback before polish: `/tmp/collect-production-audit/screenshots-after-fixes/03-desktop-scan-fallback.png`
- Web scanner fallback after polish: `/tmp/collect-production-audit/screenshots-after-fixes/04-desktop-scan-fallback-polished.png`
- iOS Simulator native screenshot: `/var/folders/yx/gzgvttgj2ljd6n_vs2qzdjq80000gn/T/screenshot_optimized_1f1c7cee-eac9-4803-b49f-14bb44f89900.jpg`
- Codex in-app browser iOS mirror: `/tmp/collect-production-audit/screenshots-after-fixes/06-ios-simulator-mirror-live.png`

## Verification Passed

- `flutter analyze`
- `flutter test test/features/mobile_completion_test.dart`
- `flutter test test/supabase_contract_test.dart`
- `flutter test test/app_shell_test.dart test/persona_uat_smoke_test.dart`
- `flutter build web` with local `.env` dart-defines
- iOS Simulator build/run through XcodeBuildMCP:
  - workspace: `ios/Runner.xcworkspace`
  - scheme: `production`
  - simulator: `iPhone 17`
  - bundle id: `app.cool.mobile`

## UX And Accessibility Findings

1. Groups page: healthier after fix. The page now has one clear Groups hero and no duplicate home-style action rail. The empty state is still plain, but it no longer contradicts the navigation structure.
2. QR scanner on web: acceptable fallback after fix. It now tells the user scanning belongs in the mobile app, with no endless spinner. The scanner screen is intentionally sparse on web, so richer web behavior would require a non-camera group-link entry path.
3. iOS sign-in: app launches to the WhatsApp sign-in screen and is visible inside Codex. Visual hierarchy is strong, but the disabled "Send WhatsApp code" state depends entirely on phone entry; full OTP journey still needs live OTP verification.
4. Responsiveness: desktop and compact web screenshots show no obvious overlap after the Groups/connectivity padding changes. Further device-matrix testing still needs emulator/device availability.
5. Accessibility: tests include semantic coverage for the Groups hero. Screenshot-only review cannot prove full keyboard, VoiceOver, focus order, or contrast compliance.

## Remaining Blockers

- Android emulator UAT could not run because `adb devices` showed no attached device and `emulator -list-avds` returned no available AVDs.
- Android debug APK build still did not complete after the NDK repair. Direct Gradle produced normal startup output, then the Java/Gradle worker exited while the shell stayed open with no APK output. This needs a separate Android Gradle cleanup pass.
- Full WhatsApp OTP production verification still requires a successful live OTP send/verify cycle against the configured Supabase/WhatsApp environment.
- App Store upload was not performed in this checkpoint. The iOS simulator build is clean, but App Store upload requires an archive/export/signing flow and App Store Connect credentials/session.

## Next Recommended Fix Goal

1. Clean Android Gradle state and produce a debug APK.
2. Create or start an Android AVD and run login/home/groups/settings UAT on-device.
3. Run the live WhatsApp OTP journey with the dev number and capture Supabase function logs.
4. Archive the iOS `production` scheme, validate signing, and upload a replacement build through the configured App Store path.
