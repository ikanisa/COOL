# Flutter 3.44 / Dart 3.12 Research

## Verified SDK

- Installed SDK: `/Volumes/PRO-G40/flutter_3_44`
- Flutter verification: `Flutter 3.44.0`, stable channel, revision `559ffa3f75`
- Dart verification: `Dart SDK version: 3.12.0`
- Existing SDK found but not used: `/Volumes/PRO-G40/Apps/SDKs/flutter`, verified as Flutter `3.38.9` / Dart `3.10.8`

## Official References

- Flutter 3.44 release notes: https://docs.flutter.dev/release/release-notes/release-notes-3.44.0
- Flutter release and breaking-change index: https://docs.flutter.dev/release/release-notes
- Dart 3.12 announcement: https://dart.dev/blog/announcing-dart-3-12
- Dart pubspec SDK constraints: https://dart.dev/tools/pub/pubspec
- Dart and Flutter MCP server: https://docs.flutter.dev/ai/mcp-server
- Codex configuration reference: https://developers.openai.com/codex/config-reference#configtoml

## Migration Notes

- `pubspec.yaml` now requires Dart `^3.12.0`.
- `.fvmrc`, VS Code settings, README, and environment docs were updated for Flutter `3.44.0`; CI keeps the existing `.fvmrc`-driven setup.
- Current Android tooling already uses Gradle `8.14`, AGP `8.11.1`, Kotlin `2.2.20`, Java `17`, and Flutter-managed compile/target SDK values.
- The app module no longer applies `kotlin-android`; its compiler target is configured through `kotlin { compilerOptions { jvmTarget = JVM_17 } }`. Flutter still reports `shared_preferences_android` as a transitive plugin that applies KGP.
- The app has Android, iOS, and web surfaces. There is no `macos/` platform directory in this checkout.
- iOS still uses CocoaPods through the existing `ios/Podfile`; Flutter 3.44 SwiftPM defaults should be reviewed before any future iOS package-manager migration, but this upgrade does not remove the existing Podfile.

## Product Safety Notes

- The later production SMS decision supersedes the original isolation note:
  production and `internal_receiver` declare receive-only `RECEIVE_SMS`, while
  all flavors remain free of inbox-history `READ_SMS`.
- Public Play distribution remains gated on an accepted restricted-SMS
  Permissions Declaration.
- Ledger and payment list reads continue to use safe views/RPCs in repository code and contract tests.
- RWF formatting is integer-only and covered by tests; money logic remains integer RWF with no float conversion.
- Project-level Codex environment placeholders replaced live-looking secrets; real values must stay in ignored local or CI secret stores.

## Dart 3.12 Language Guidance

Dart 3.12 is available through the verified SDK. The codebase should adopt stable language syntax only when it improves clarity or removes analyzer friction. This upgrade intentionally avoids mass rewrites and keeps payment/SMS/allocation logic behavior-preserving.
