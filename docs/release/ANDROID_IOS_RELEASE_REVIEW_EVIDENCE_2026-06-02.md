# Android And iOS Release Review Evidence

Prepared: 2026-06-02

Decision impact: this evidence supports Android release-signing review and iOS
release-scope review. It does not approve either gate by itself. Approval must
still be recorded in `docs/release/RELEASE_APPROVALS.json`.

## Android Artifacts

| Artifact | SHA-256 | Signature evidence |
| --- | --- | --- |
| `build/app/outputs/flutter-apk/app-production-release.apk` | `929193c483c62e7ad0e3aa70348babe458a350e1eaa422413184321f48bd1c67` | `apksigner verify --verbose` passed; APK Signature Scheme v2 is verified. |
| `build/app/outputs/bundle/productionRelease/app-production-release.aab` | `36c45e8c370c18c7144ce1bc1b7b687dae3d4a9b841a9ab754e3dec1589c184b` | `jarsigner -verify` passed with `jar verified`. |

Additional evidence:

- `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256` was refreshed
  after rebuilding the production APK and AAB with Gradle release signing.
- `.cache/mobile_release_gate/20260602T050529Z/summary.json` records
  `android_release_artifact_signatures=pass`.
- `.cache/android_install/20260602T050529Z/final_release_summary.json` records
  the rebuilt signed APK installed on Pixel `13111JEC215558` with
  `apkSigningVersion=2`.
- `scripts/flutter_mobile_release_gate.sh --json` now blocks unsigned release
  artifacts before reviewer approval.

Review notes:

- Signing keys, passwords, and keystore contents are not printed or committed.
- The AAB is signed with the local upload key; Play App Signing custody and key
  acceptance still need reviewer confirmation.
- Android release signing remains blocked until
  `android_release_signing_review` is approved in
  `docs/release/RELEASE_APPROVALS.json`.

## iOS Scope

Current iOS release inputs exist:

- `ios/Runner/Info.plist`
- `ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme`
- `ios/Flutter/Release-production.xcconfig`

Product-scope facts:

- Group creation is Android-only because owner-side MoMo SMS access is required
  for automated confirmation.
- iPhone users can join/open groups and contribute, but creator flows must be
  scoped out or separately approved for contributor-only use.
- The product-required iPhone warning remains
  `group creation is available only on Android`.

iOS release scope remains blocked until `ios_release_scope` is approved or
explicitly marked `OUT_OF_SCOPE` in `docs/release/RELEASE_APPROVALS.json`.

## Secret Handling

This evidence intentionally contains only artifact paths, hashes, command
outcomes, and scope facts. It does not contain signing keys, key passwords,
raw SMS bodies, phone/MoMo numbers, service-role keys, provider tokens, or
production customer data.
