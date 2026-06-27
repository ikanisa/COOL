# iOS App Store Completion Alternatives - 2026-06-25

Target app: `Collect`

Bundle ID: `app.cool.mobile`

Apple team: `IKANISA LTD` / `63STJ5N27W`

App Store Connect app ID: `6783960331`

## Current Machine State

- Flutter is available at `3.44.3` stable with Dart `3.12.2`.
- Xcode is selected at `/Applications/Xcode.app/Contents/Developer` and reports Xcode `26.2`.
- Local Apple tooling is unhealthy:
  - `getconf DARWIN_USER_CACHE_DIR` returns `Input/output error`.
  - `xcrun simctl list runtimes` fails with `CoreSimulatorService` connection refused.
  - Local keychain currently reports `0 valid identities`.
  - No provisioning profiles are installed locally.
- Browser automation is not available for the in-app App Store Connect tab in the current turn.

## Alternative A - Fastlane App Store Connect API Route

Use this when an App Store Connect Team API key is available.

Prepared repo commands:

```bash
ASC_KEY_ID=... \
ASC_ISSUER_ID=... \
ASC_PRIVATE_KEY_PATH=/secure/path/AuthKey_XXXX.p8 \
fastlane ios upload_metadata_screenshots
```

This uploads the prepared metadata and the five staged screenshots without uploading a binary and without submitting for review.

Prepared files:

- `fastlane/Fastfile`
- `fastlane/metadata/en-GB/*`
- `fastlane/screenshots/en-GB/*`
- `output/app_store/ios_screenshots/final/*`

Remaining account inputs:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY_PATH` or `ASC_PRIVATE_KEY`

## Alternative B - Local Xcode Archive After Repair

Use this when the Mac user session and Xcode trust state are repaired.

Checks:

```bash
getconf DARWIN_USER_CACHE_DIR
xcrun simctl list runtimes
security find-identity -v -p codesigning
find "$HOME/Library/MobileDevice/Provisioning Profiles" -name '*.mobileprovision'
```

Build:

```bash
flutter build ipa \
  --flavor production \
  --release \
  --export-options-plist=ios/ExportOptionsAppStore.plist \
  --dart-define=APP_REVIEW_AUTH_ENABLED=true \
  --dart-define=APP_REVIEW_AUTH_PHONE="$COLLECT_REVIEW_PHONE" \
  --dart-define=APP_REVIEW_AUTH_OTP="$COLLECT_REVIEW_OTP"
```

Upload:

```bash
ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_PRIVATE_KEY_PATH=... fastlane ios upload_review_build
```

## Alternative C - GitHub Actions Remote macOS Runner

Use this when the local Mac remains broken.

Prepared workflow:

- `.github/workflows/ios-app-store.yml`

Required GitHub Secrets:

- `APPLE_CERTIFICATE_BASE64`: base64 encoded Apple Distribution `.p12`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`: base64 encoded App Store provisioning profile for `app.cool.mobile`
- `KEYCHAIN_PASSWORD`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY`

The workflow is manual-only. It can build an IPA on GitHub's macOS runner and optionally upload metadata/screenshots and/or the TestFlight build.

## Alternative D - Xcode Cloud

Use this when signing should stay inside Apple instead of this Mac or GitHub.

Required setup in App Store Connect:

- Connect the repository to Xcode Cloud.
- Select the iOS production scheme.
- Configure Flutter install steps before archive.
- Add review Dart defines:
  - `APP_REVIEW_AUTH_ENABLED=true`
  - `APP_REVIEW_AUTH_PHONE` from the approved reviewer credential store.
  - `APP_REVIEW_AUTH_OTP` from the approved reviewer credential store.

This avoids local simulator and keychain issues, but requires App Store Connect/Xcode Cloud setup in the Apple UI.

## Alternative E - Manual App Store Connect Browser Route

Use this if a normal browser session has upload access.

Upload these five screenshots:

- `output/app_store/ios_screenshots/final/01-home-1242x2688.png`
- `output/app_store/ios_screenshots/final/02-groups-1242x2688.png`
- `output/app_store/ios_screenshots/final/03-group-detail-1242x2688.png`
- `output/app_store/ios_screenshots/final/04-share-1242x2688.png`
- `output/app_store/ios_screenshots/final/05-account-delete-1242x2688.png`

Complete App Privacy using the prepared draft:

- `fastlane/app_privacy_details.json`

Do not submit for App Review until the uploaded build, screenshots, App Privacy, build selection, and pricing/availability are complete. App Review submission is delegated to Codex when the required account access, signing assets, and source-of-truth metadata are available.

## Alternative F - Fastlane App Privacy Web-Session Route

Fastlane includes `upload_app_privacy_details_to_app_store`, but this installed version requires Apple ID web-session authentication rather than only an App Store Connect API key.

Prepared command after source-of-truth metadata verification:

```bash
FASTLANE_USER=apple-id-email@example.com fastlane ios upload_app_privacy_details
```

Because App Privacy is an external privacy disclosure, publish it only when `fastlane/app_privacy_details.json` matches the current product data practices and the required Apple account session is available.

## Alternative G - Direct Transporter Upload

Use this only after a signed `.ipa` exists. Transporter does not solve signing, screenshot upload, or App Privacy, but it can upload the binary if Fastlane upload has trouble.

Possible commands after a signed IPA exists:

```bash
xcrun altool --upload-app --type ios --file build/ios/ipa/*.ipa --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

or use Apple's Transporter app with the signed IPA.

## Alternative H - Second Mac Build Station

Use this if GitHub Actions is unavailable and the current Mac remains unhealthy.

Steps:

1. Clone this repo to a clean Mac with full Xcode installed in `/Applications`.
2. Install Flutter `3.44.3` stable from `.fvmrc`.
3. Install Apple Distribution certificate and the App Store provisioning profile for `app.cool.mobile`.
4. Run `fastlane ios prepare_app_store_assets`.
5. Run `fastlane ios build_review_ipa`.
6. Upload with `fastlane ios upload_review_build` or Transporter.

This avoids the current machine's broken `DARWIN_USER_CACHE_DIR`, CoreSimulator, and code-sign trust state.

## Delegated Release Boundary

The repo is prepared for upload paths. App Privacy publication, binary upload, build attachment, TestFlight selection, and App Review submission are delegated Codex-owned release actions when the required credentials, signing assets, account access, and source-of-truth metadata are available.

## References Checked

- Apple App Store Connect Help: upload builds with Xcode, Swift Playgrounds, `altool`, Transporter, or API/JWT tooling.
- Apple Developer Documentation: App Screenshot resources can upload screenshots through the App Store Connect API.
- Apple App Privacy Details: privacy answers are required for new apps and updates.
- Fastlane docs/actions: `deliver`, `pilot`, and `upload_app_privacy_details_to_app_store`.
