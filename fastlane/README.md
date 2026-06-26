fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android play_validate_local

```sh
[bundle exec] fastlane android play_validate_local
```

Validate Google Play metadata and AAB paths without submitting to Play

### android play_production_submit

```sh
[bundle exec] fastlane android play_production_submit
```

Upload Collect production AAB and metadata to Google Play after credentials are available

----


## iOS

### ios prepare_app_store_assets

```sh
[bundle exec] fastlane ios prepare_app_store_assets
```

Stage Collect App Store screenshots into Fastlane's upload layout

### ios upload_metadata_screenshots

```sh
[bundle exec] fastlane ios upload_metadata_screenshots
```

Upload Collect App Store metadata and screenshots without a binary or review submission

### ios build_review_ipa

```sh
[bundle exec] fastlane ios build_review_ipa
```

Build the App Review IPA with deterministic reviewer OTP access enabled

### ios upload_review_build

```sh
[bundle exec] fastlane ios upload_review_build
```

Upload the latest signed IPA to TestFlight without submitting for App Review

### ios upload_app_privacy_details

```sh
[bundle exec] fastlane ios upload_app_privacy_details
```

Upload App Privacy details using an Apple ID web session and a reviewed JSON answers file

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
