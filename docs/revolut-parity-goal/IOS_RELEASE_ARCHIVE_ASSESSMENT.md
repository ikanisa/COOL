# iOS Release Archive Assessment

## Scope

- Date: 2026-07-24
- Workspace: `ios/Runner.xcworkspace`
- Scheme: `Runner`
- Configuration: `Release`
- Destination: generic iOS device
- Bundle identifier: `app.cool.mobile`
- App version: `1.2.2` (`10`)
- Deployment target: iOS 15.5
- Architecture: arm64
- External mutation: none

The assessment compiled the current checkout for a generic iOS device and
tested the configured signing path. It did not use
`-allowProvisioningUpdates`, upload an archive, change an Apple account, or
submit to TestFlight/App Store.

## Release configuration

The Release build settings resolve to:

- automatic signing;
- development team configured in the Xcode project;
- `Runner/Runner.entitlements`;
- Associated Domains entitlement:
  `applinks:collect.ikanisa.com`;
- whole-module Swift compilation with `-O`;
- store product validation enabled.

## Current unsigned archive

The archive was regenerated after the resolved dependency upgrade and the
`file_saver` 0.4.0 security/platform update. This current archive supersedes
the earlier pre-upgrade archive for source-state evidence.

Command:

```sh
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath .cache/ios_release_archive/20260724-post-upgrade/Collect-unsigned-final.xcarchive \
  -derivedDataPath /Users/jeanbosco/Library/Developer/Xcode/DerivedData/Collect-Release-Archive-Final \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  archive
```

Result: `ARCHIVE SUCCEEDED`.

Retained evidence:

- archive:
  `.cache/ios_release_archive/20260724-post-upgrade/Collect-unsigned-final.xcarchive`;
- archive size: 176 MB;
- application binary SHA-256:
  `8b8c192561289bb9bc84aea771144c7d7312ba6de79c1f1bd4e85a3710c5e12a`;
- application Info.plist SHA-256:
  `e387409f4a0cfbdfeb5c3ba6d796c21d2ea505cda03b43536c0235bb212142bd`;
- dSYM UUID:
  `4EDFC2BD-D3AC-319C-B11F-8866F61FF275`.

The final archive no longer emits the `file_saver` 0.3.1 deprecated
`UIApplication.keyWindow` warning. It retains one upstream `mobile_scanner`
generated Objective-C ownership warning and the existing always-run Flutter
script phase notes; neither prevents archive creation.

The archive is intentionally unsigned and is not distributable.

## Configured signing attempt

The same Release archive command was then run without disabling signing and
without allowing Xcode to update provisioning assets.

Result: `ARCHIVE FAILED`.

Exact blocker:

```text
Provisioning profile "iOS Team Provisioning Profile: *" doesn't include the
Associated Domains capability.

Provisioning profile "iOS Team Provisioning Profile: *" doesn't include the
com.apple.developer.associated-domains entitlement.
```

The local keychain reports one valid code-signing identity, but the available
profile is not compatible with the app's Associated Domains entitlement. No
usable signed archive was produced.

## Closure decision

RT-033 is complete for locally authorized engineering assessment:

- Release device compilation and archive creation pass when signing is
  disabled.
- The configured signed archive path fails for a precise, reproducible
  provisioning-capability mismatch.

Distribution remains externally gated. The release owner must create or select
an App ID/profile for `app.cool.mobile` with Associated Domains enabled, then
rerun the signed archive and distribution validation under authorized Apple
account access.
