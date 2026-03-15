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

### android upload_to_play

```sh
[bundle exec] fastlane android upload_to_play
```

Upload AAB to Google Play internal testing track

### android upload_metadata

```sh
[bundle exec] fastlane android upload_metadata
```

Upload store listing metadata and screenshots

### android full_upload

```sh
[bundle exec] fastlane android full_upload
```

Full upload: AAB + metadata + screenshots

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
