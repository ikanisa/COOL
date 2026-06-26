# iOS App Store Readiness - 2026-06-24

## Scope

Target app: Collect

Production bundle identifier: `app.cool.mobile`

Flutter flavor/scheme: `production`

Version in `pubspec.yaml`: `1.2.2+9`

This report covers local readiness and Apple account setup for App Store Connect/TestFlight. It does not record a build upload, filing, legal notice, or App Review submission.

## Apple Account Setup Completed

- Apple Developer team: `IKANISA LTD` / Team ID `63STJ5N27W`.
- Registered explicit App ID in Certificates, Identifiers & Profiles:
  - Description: `Collect`.
  - Bundle ID: `app.cool.mobile`.
  - Capability selected: Associated Domains.
- Created App Store Connect app record:
  - App Store Connect app ID: `6783960331`.
  - Exact public name `Collect` is rejected by Apple as already in use.
  - App Store Connect currently requires either a trademark/name claim or a unique public listing name before exact `Collect` can be saved.
  - Bundle ID: `Collect - app.cool.mobile`.
  - Platform: iOS.
  - Primary language: English (U.K.).
  - SKU: `app.cool.mobile`.
- Apple rejected the exact public App Store name `Collect` because it is already in use. The app binary display name remains `Collect`.
- App Store Connect version metadata saved for iOS version `1.2.2`:
  - Promotional text, description, keywords, support URL, marketing URL, copyright, and manual release selection.
  - App Information subtitle: `Group Savings and Credit`.
  - Primary category: Finance.
  - Age rating: `4+` global rating with regional equivalents.
  - Content Rights: `No, this app does not contain, show, or access third-party content.`
  - App Review contact and notes saved.
  - Reviewer sign-in saved in App Store Connect.
    - Exact reviewer phone and OTP are intentionally not stored in git.
    - Notes explain the review-only OTP path and demo records.
- Public Apple App Site Association file deployed and verified:
  - URL: `https://collect.ikanisa.com/.well-known/apple-app-site-association`.
  - HTTP status: `200`.
  - App ID: `63STJ5N27W.app.cool.mobile`.

## Toolchain

- Flutter upgraded to `3.44.3` stable.
- Dart upgraded through Flutter to `3.12.2`.
- Repo Flutter pin updated in `.fvmrc` from `3.44.0` to `3.44.3`.
- Xcode selected by `xcode-select`: `/Applications/Xcode.app/Contents/Developer`.
- Xcode version: `26.2` build `17C52`.
- Apple SDKs visible through `xcodebuild -showsdks`: iOS `26.2`, iOS Simulator `26.2`.
- Apple Developer team configured in Runner build settings: `IKANISA LTD` / `63STJ5N27W`.
- iOS 26.3.1 simulator runtime downloaded and registered:
  - Runtime: `iOS 26.3 (26.3.1 - 23D8133)`.
  - Simulator devices were created, including iPhone 17 Pro Max.

## Completed Checks

- `flutter pub get`: pass on Flutter `3.44.3` / Dart `3.12.2`.
- `flutter analyze`: pass, no issues found.
- `flutter test`: pass, `260` tests passed, `1` visual-evidence test intentionally skipped.
- Focused reviewer-auth/security tests: pass.
  - `flutter test --no-pub test/features/mobile_completion_test.dart test/shared/collect_repository_test.dart test/security_hygiene_test.dart`
  - Includes fixed Apple reviewer OTP coverage using test-only dummy credentials.
- `flutter analyze --no-pub`: pass, no issues found after reviewer-auth changes.
- Fresh App Store screenshot set generated:
  - Source/final directory: `output/app_store/ios_screenshots/final/`.
  - Five current app screenshots: home, groups, group detail, share, account deletion.
  - All validate at Apple 6.5-inch accepted portrait size: `1242 x 2688`.
- Fastlane iOS automation route prepared:
  - `fastlane ios prepare_app_store_assets` stages the five screenshots in `fastlane/screenshots/en-GB/`.
  - `fastlane ios upload_metadata_screenshots` can upload metadata/screenshots by App Store Connect API key without binary upload or review submission.
  - `fastlane ios build_review_ipa` builds the review IPA with deterministic OTP access enabled.
  - `fastlane ios upload_review_build` uploads the latest signed IPA to TestFlight without review submission.
  - `fastlane ios upload_app_privacy_details` can publish reviewed App Privacy JSON through Apple ID web-session authentication.
- Remote macOS build alternative prepared:
  - `.github/workflows/ios-app-store.yml` is manual-only and can build/upload using GitHub Actions secrets.
  - `ios/ExportOptionsAppStore.plist` records App Store export settings for team `63STJ5N27W`.
- Draft App Privacy upload JSON prepared:
  - `fastlane/app_privacy_details.json`.
  - Requires human approval before publishing because it is an external privacy disclosure.
- Completion alternatives are documented in:
  - `docs/release/IOS_APP_STORE_COMPLETION_ALTERNATIVES_2026-06-25.md`.
- iOS app icon catalog: pass, `25` entries, no missing files, no PNG size mismatches.
- Production iOS config:
  - `APP_BUNDLE_IDENTIFIER=app.cool.mobile`.
  - Display name: `Collect`.
  - Signing style: Automatic.
  - Development team: `63STJ5N27W`.
  - `ITSAppUsesNonExemptEncryption=false`.
  - Minimum iOS deployment target: `15.5`.
  - Device families: iPhone and iPad.
  - App icon set: `AppIcon`.
  - Entitlements include Associated Domains for `applinks:collect.ikanisa.com`.
- Required local privacy permission strings currently present:
  - `NSCameraUsageDescription`.
  - `NSPhotoLibraryUsageDescription`.
- Non-browser Apple App ID registration script added:
  - `scripts/apple_register_app_id.rb`
  - Target defaults: `Collect`, `app.cool.mobile`, `IOS`, `ASSOCIATED_DOMAINS`.
  - This is now a fallback automation path; the App ID was registered successfully through the Apple Developer browser session.

## Current Blockers

1. Xcode destination/platform repair or Xcode update is required before archive/upload.
   - `xcodebuild -downloadPlatform iOS` completed and installed iOS 26.3.1 runtime.
   - After install, `CoreSimulatorService` refuses `simctl` with `NSPOSIXErrorDomain Code=61 Connection refused`.
   - `Simulator.app` fails LaunchServices/code-sign assessment with `CSSMERR_TP_NOT_TRUSTED` / `internal error in Code Signing subsystem`.
   - Copying the external-drive Xcode bundle to `/Applications/Xcode-local.app` did not fix the Simulator trust failure.
   - `xcodebuild -resolvePackageDependencies` now aborts/hangs around DeveloperTools cache/FSEvents setup, including `DVTFilePathFSEvents: Failed to start fs event stream` and `DARWIN_USER_CACHE_DIR ... Input/output error`.
   - This currently blocks simulator build/run and local archive validation.

2. App Store signing is not configured locally.
   - `DEVELOPMENT_TEAM=63STJ5N27W` is now present in the Runner app target build configurations.
   - No Apple Distribution identity was found in Keychain.
   - The only local code-signing identity found was `Inhouse Dev Signing`.
   - No App Store provisioning profile for `app.cool.mobile` was found locally.
   - No App Store Connect API key id, issuer id, `.p8`, or iOS Fastlane lane is configured in this repo for automated upload.
   - Running `scripts/apple_register_app_id.rb` exits blocked until `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_PATH` or `ASC_PRIVATE_KEY` are supplied.

3. Simulator runtime is unavailable to XcodeBuildMCP.
   - The runtime installed, but `CoreSimulatorService` is unhealthy after installation.
   - XcodeBuildMCP cannot list or boot simulators while `simctl` returns `Connection refused`.
   - This blocks simulator launch/screenshot proof from a real iOS runtime.

4. Associated Domains deployment needs verification after Apple tooling is repaired.
   - The app entitlement references `applinks:collect.ikanisa.com`.
   - `https://collect.ikanisa.com/.well-known/apple-app-site-association` now returns HTTP `200`.
   - The live AASA file includes `63STJ5N27W.app.cool.mobile`.
   - Runtime universal-link handoff still needs verification on iOS after Xcode simulator/device support is repaired.

5. Screenshot upload is still pending in App Store Connect.
   - Fresh valid PNGs exist locally in `output/app_store/ios_screenshots/final/`.
   - Fastlane-staged copies exist in `fastlane/screenshots/en-GB/`.
   - App Store Connect still shows `0 of 10 Screenshots`.
   - The in-app browser wrapper did not expose Playwright `setInputFiles`, and browser-side `DataTransfer`/`ClipboardEvent` file injection is unavailable.
   - Upload can now use App Store Connect API/Fastlane once `ASC_KEY_ID`, `ASC_ISSUER_ID`, and a `.p8` private key are available.

6. App Privacy is still pending in App Store Connect.
   - Official Apple documentation says App Privacy details are required.
   - The current App Store Connect sidebar/session did not expose a working App Privacy editor for this app, and direct guessed privacy routes only loaded the shell.
   - Draft Fastlane privacy details JSON now exists, but it has not been published and requires human approval before upload.

7. Swift Package Manager future warning.
   - Flutter warned that `file_saver` does not support Swift Package Manager for iOS.
   - This is not a current failure, but Flutter says it will become an error in a future version.

## App Store Connect Requirements To Complete

Apple's current App Store Connect documentation requires the following before TestFlight/App Review can complete:

- Upload a build with Xcode, Swift Playgrounds, `altool`, Transporter, or App Store Connect API/JWT tooling.
- Provide app privacy details and keep them accurate for the app and third-party SDKs.
- Provide product-page metadata, screenshots/app previews, pricing, and availability.
- For TestFlight, provide test information, upload a build, invite testers, and answer export-compliance/encryption questions where applicable.
- Select an uploaded build on the app version before submitting for review.

Official references:

- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit/

## Next Required Human/Account Actions

1. Repair the local Xcode/CoreSimulator installation. Recommended path:
   - Install a fresh full Xcode into internal `/Applications`, not a symlink to an external `noowners` volume.
   - Open Xcode once to complete first-launch/install tasks.
   - Re-run:
   - `flutter doctor -v`
   - `xcrun simctl list runtimes`
   - `xcodebuild -workspace ios/Runner.xcworkspace -scheme production -configuration Release-production -showdestinations`

2. Configure Apple signing for `app.cool.mobile`:
   - Confirm Xcode can access team `IKANISA LTD` / `63STJ5N27W`.
   - Install an Apple Distribution certificate or enable automatic signing with the correct team in Xcode.
   - Create or refresh the App Store provisioning profile for `app.cool.mobile`.

3. Optional automation hardening: configure App Store Connect API credentials if future non-browser Apple account changes or uploads should be automated:
   - `ASC_KEY_ID=<key-id> ASC_ISSUER_ID=<app-store-connect-issuer-id> ASC_PRIVATE_KEY_PATH=/secure/path/AuthKey_<key-id>.p8 scripts/apple_register_app_id.rb`
   - Use the Issuer ID shown on the App Store Connect API key page; do not assume the membership Developer ID is the same value.
   - The script creates or reuses `app.cool.mobile` and enables `ASSOCIATED_DOMAINS`.

4. After signing and Xcode platform repair, rerun:
  - Review/TestFlight build with deterministic reviewer OTP:
     - `flutter build ipa --flavor production --release --dart-define=APP_REVIEW_AUTH_ENABLED=true --dart-define=APP_REVIEW_AUTH_PHONE="$COLLECT_REVIEW_PHONE" --dart-define=APP_REVIEW_AUTH_OTP="$COLLECT_REVIEW_OTP"`
   - Public production build after review access is no longer needed:
     - `flutter build ipa --flavor production --release --dart-define=APP_REVIEW_AUTH_ENABLED=false`
   - Or archive through Xcode Organizer using scheme `production`.

5. Only after explicit human approval, upload the signed build to App Store Connect/TestFlight and complete App Store Connect metadata/privacy/review fields.

## Current Verdict

Local Flutter/Dart readiness is green, and App Review deterministic OTP access is implemented, tested, and saved in App Store Connect. Apple Developer/App Store Connect setup is complete for the App ID, app record, App Information metadata that was reachable, version metadata, age rating, content rights, review contact/notes, and Associated Domains web verification. App Store upload/submission is still blocked by local Xcode/CoreSimulator trust/service failure, missing Apple Distribution signing/provisioning, missing uploaded screenshots/App Privacy details, no uploaded build, and required human approval before any external submission.
