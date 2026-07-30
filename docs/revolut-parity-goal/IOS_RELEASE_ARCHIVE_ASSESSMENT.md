# iOS Release Archive Assessment

## Scope

- Date: 2026-07-28
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

The archive was regenerated under E-065 after the Flutter 3.44.4 toolchain
alignment, E-064 semantics correction, clean release-artifact rebuild, and
packaged-payload verification. This archive supersedes the E-057 archive for
current-source evidence.

Command:

```sh
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath .cache/ios_release_archive/20260728-e065/Collect-unsigned.xcarchive \
  -derivedDataPath /Users/jeanbosco/Library/Developer/Xcode/DerivedData/Collect-Release-Archive-E065 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  archive
```

Result: `ARCHIVE SUCCEEDED`.

Retained evidence:

- archive:
  `.cache/ios_release_archive/20260728-e065/Collect-unsigned.xcarchive`;
- archive size: 180,428 KiB;
- application binary SHA-256:
  `047ea05a5ec909381986e23cae3acd676758e0a16773ab1320555e1e47560a99`;
- application Info.plist SHA-256:
  `998e48672822db966eaec5ddd9cfcb63f6d862c865ac05bb508912f631f260a2`;
- archive log SHA-256:
  `3b540f040ac6753a2392654a67cec93a602ded0af72abae9be654ca7034ea3b0`;
- dSYM UUID:
  `D467626B-D459-319F-98B0-4C145E58CF35`.

The archive contains `app_links` 7.2.1, sets
`FlutterDeepLinkingEnabled=false`, and retains only the governed Inter variable
font, tree-shaken Material Icons, and official Collect PNG among relevant
font/product-artwork payload, with no SVG/SVGZ/ICO or legacy typeface. Its app
binary contains neither removed toolbar semantics label. It emits one upstream
`mobile_scanner` generated Objective-C ownership warning, an AppIntents
metadata-skip warning because Collect has no AppIntents dependency, and the
existing always-run Flutter script phase notes; none prevents archive creation.

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
