# Codex iOS Development Plan

Status date: 2026-06-29

This plan is for continuing the Collect Flutter iOS app inside Codex. It keeps
the workflow Codex-first, uses the Build iOS Apps plugin where it adds value,
and preserves the repo's existing release approval boundaries.

## Current Baseline

- Repo: `/Volumes/PRO-G40/COOL`
- Branch state when prepared: `main...origin/main`, clean working tree.
- App: Flutter customer app with Admin PWA and public web entrypoints.
- Project SDK: Flutter `/Volumes/PRO-G40/flutter_3_44/bin/flutter`
  (`3.44.3`), Dart `3.12.2`.
- iOS bundle identifier: `app.cool.mobile`.
- iOS project: `ios/Runner.xcodeproj`.
- iOS schemes present: `Runner`, `production`, `staging`, and plugin schemes.
- Existing App Store automation: `fastlane/Fastfile`,
  `fastlane/Appfile`, `ios/ExportOptionsAppStore.plist`, metadata, privacy
  details, and screenshots.
- Current validation snapshot:
  - `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass.
  - `./scripts/flutter_mobile_release_gate.sh --json`: iOS release files pass.
  - `./scripts/release_status.sh --json`: `NO-GO`, blocked by stale Android
    release artifacts, not by current iOS release-scope files.
- Current local Apple tooling issue:
  - XcodeBuildMCP can read the Xcode project and schemes.
  - XcodeBuildMCP simulator listing timed out after 300 seconds, so simulator
    recovery is a first-class workstream before promising live iOS simulator
    proof.

## Approval Boundaries

- Do not upload builds, submit App Store metadata, submit App Privacy details,
  distribute TestFlight builds, or submit for App Review without explicit
  recorded owner approval.
- Fastlane lanes that require Apple credentials remain credential-gated:
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_PATH` or
  `ASC_PRIVATE_KEY`, `FASTLANE_USER`, `COLLECT_REVIEW_PHONE`, and
  `COLLECT_REVIEW_OTP`.
- Do not print signing keys, App Store Connect private keys, Supabase secrets,
  or review OTPs in logs or docs.

## Codex Resources

- Official Codex iOS guide:
  `https://developers.openai.com/codex/use-cases/native-ios-apps`
  - Use a CLI-first build loop.
  - Use native Apple tooling for iOS verification.
  - Add XcodeBuildMCP and focused iOS skills for deeper simulator, build, and
    debugging work.
- Repo environment source:
  `docs/ENVIRONMENT.md`.
- Release state sources:
  `docs/release/RELEASE_STATUS.md`,
  `docs/release/APP_STORE_READINESS.md`,
  `docs/release/RELEASE_APPROVALS.json`,
  `docs/release/UAT_EVIDENCE_MANIFEST.json`.
- App Store automation:
  `fastlane/Fastfile`,
  `fastlane/app_privacy_details.json`,
  `fastlane/metadata/en-GB`,
  `fastlane/screenshots/en-GB`,
  `ios/ExportOptionsAppStore.plist`.
- iOS build configuration:
  `ios/Runner.xcodeproj`,
  `ios/Flutter/Release-production.xcconfig`,
  `ios/Runner/Info.plist`,
  `ios/Podfile`.
- App code:
  `lib/app`,
  `lib/features`,
  `lib/shared`,
  `lib/core`.
- Tests and evidence:
  `test/`,
  `integration_test/`,
  `scripts/mobile_route_render_smoke.sh`,
  `scripts/collect_mobile_design_compliance_audit.sh`,
  `scripts/flutter_mobile_release_gate.sh`,
  `scripts/repo_wide_qa_uat.sh`.

## Tools And Plugins

- Build iOS Apps plugin:
  - XcodeBuildMCP for Xcode project discovery, scheme listing, simulator
    build/run, logs, screenshots, and later UI automation if enabled.
  - iOS Simulator Browser skill when a simulator UDID is healthy and a browser
    mirror is needed for visual proof.
- Flutter tooling:
  - `/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get`
  - `/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed .`
  - `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`
  - `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub`
  - `/Volumes/PRO-G40/flutter_3_44/bin/flutter build ios --flavor production --release --no-codesign`
  - `bundle exec fastlane ios build_review_ipa` only after review env values
    and signing are intentionally available.
- Apple tooling:
  - `xcodebuild`, `xcrun simctl`, CocoaPods through `ios/Podfile`, and Xcode
    project schemes.
  - Prefer XcodeBuildMCP for simulator build/run once defaults are configured
    and simulator enumeration is healthy.
- Repo gates:
  - `./scripts/flutter_mobile_release_gate.sh --json`
  - `./scripts/release_status.sh --json`
  - `./scripts/repo_wide_qa_uat.sh --json`
  - `./scripts/collect_mobile_design_compliance_audit.sh --json`
  - `./scripts/release_secret_scan.sh`
- Skills to use when relevant:
  - `build-ios-apps:ios-simulator-browser` for mirrored simulator proof.
  - `build-ios-apps:ios-debugger-agent` when LLDB/debug inspection is needed.
  - `build-ios-apps:ios-ettrace-performance` when profiling iOS runtime
    performance.
  - `build-ios-apps:ios-memgraph-leaks` when diagnosing memory leaks.
  - `flutter-repo-onboarding-and-architecture-map` for repo mapping and
    architecture-safe changes.
  - `mobile-app-development`, `mobile-architecture`, and
    `adaptive-responsive-platform-native-ui` for product-facing Flutter/iOS
    work.
  - `privacy-permissions-data-governance` and
    `auth-identity-session-passkeys` for auth, reviewer access, privacy, and
    permissions work.

## Workstreams

1. Stabilize the local iOS tool loop.
   - Confirm Xcode, CocoaPods, `xcrun simctl`, and CoreSimulator health.
   - Configure XcodeBuildMCP defaults for:
     - project: `/Volumes/PRO-G40/COOL/ios/Runner.xcodeproj`
     - scheme: `production`
     - simulator: current available iPhone simulator
   - Only after simulator enumeration works, run XcodeBuildMCP
     `build_run_sim` and capture screenshot/log proof.

2. Keep Flutter development source-safe.
   - Use the pinned Flutter SDK from `docs/ENVIRONMENT.md`.
   - Run `flutter pub get` before native iOS builds if generated xcconfig files
     are stale.
   - Make feature changes in `lib/features`, `lib/shared`, or `lib/core`
     following existing Riverpod/GoRouter/theme patterns.
   - Add focused widget/unit tests for every touched flow.

3. Validate iOS build readiness.
   - Run formatting, analysis, focused tests, then full `flutter test --no-pub`.
   - Run `flutter build ios --flavor production --release --no-codesign` as
     the local compile gate.
   - Run XcodeBuildMCP simulator build/run when the simulator layer is healthy.
   - Use the iOS simulator browser only after a real simulator UDID is known and
     rendering has been verified.

4. Prepare App Store readiness without submitting.
   - Keep screenshots and metadata staged through Fastlane.
   - Verify `fastlane ios prepare_app_store_assets`.
   - Validate App Privacy JSON and metadata locally.
   - Build signed IPA only when signing and reviewer env values are explicitly
     available.
   - Stop before upload/submission unless approval is recorded.

5. Preserve cross-release truth.
   - Do not call iOS or Android release-ready unless the current gates pass.
   - Continue reporting the known Android artifact freshness blocker until the
     APK/AAB are rebuilt after the latest Android/mobile source mtimes.
   - Keep `docs/release/RELEASE_STATUS.md` and machine gates as the source of
     release truth.

## Immediate Next Commands

Use this sequence for the next implementation pass:

```sh
git status --short --branch
/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed .
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
./scripts/flutter_mobile_release_gate.sh --json
./scripts/release_status.sh --json
```

Use this sequence for the iOS compile/simulator track after the current Apple
tooling timeout is fixed:

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get
/Volumes/PRO-G40/flutter_3_44/bin/flutter build ios --flavor production --release --no-codesign
```

Then use XcodeBuildMCP:

1. `session_show_defaults`
2. configure project/scheme/simulator defaults if missing
3. `build_run_sim`
4. `screenshot`
5. collect runtime log path from the build/run response

## Done Criteria For The Next iOS Development Milestone

- Working tree changes are scoped and reviewed.
- Format/analyze/tests pass for touched behavior.
- iOS production no-codesign build passes locally, or a concrete Apple tooling
  blocker is recorded with exact command output.
- Simulator run and screenshot proof are captured through XcodeBuildMCP if the
  simulator layer is healthy.
- App Store/TestFlight actions remain unsubmitted unless owner approval is
  explicitly recorded.
- Release status is updated from current machine gates, not historical reports.
