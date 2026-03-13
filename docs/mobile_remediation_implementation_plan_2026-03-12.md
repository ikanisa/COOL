# COOL Mobile Remediation Implementation Plan

Date: 2026-03-12

Based on:

- [mobile_dependency_gap_report_2026-03-12.md](/Volumes/PRO-G40/COOL/docs/mobile_dependency_gap_report_2026-03-12.md)

## Objective

Close the mobile production gaps identified in the dependency audit and bring the app to a consistent, shippable state across Android and iOS without changing the core product architecture:

- Flutter client
- Supabase as system of record
- Google Maps for mobility
- Firebase for mobile services
- WhatsApp OTP
- Mobile Money USSD

## Delivery Principles

1. Resolve product-truth gaps before technical polish.
2. Fix production blockers before version drift.
3. Prefer deterministic native configuration over best-effort fallback.
4. Keep Android and iOS parity where the product actually requires parity.
5. Update docs only after the implementation is true.

## Program Structure

The work should be executed in five workstreams:

1. Payment verification truth and compliance
2. Firebase completion and deterministic bootstrap
3. iOS production-native completion
4. Config, docs, and release hygiene
5. Dependency upgrades and hardening

## Critical Path

This is the required order:

1. Decide whether Android SMS autoread is a real shipping requirement.
2. Complete Firebase iOS registration and app bootstrap.
3. Fix iOS native production gaps: maps key, NFC entitlement, universal links, contacts macro.
4. Regenerate iOS pods and verify all native plugins resolve correctly.
5. Clean up docs and release scripts to match reality.
6. Upgrade non-blocking packages after the app is functionally correct.

## Workstream 0: Decision Gate On SMS Verification

### Purpose

The repository currently contradicts itself. Some docs say Android SMS-based Mobile Money confirmation is core. The shipping code does not implement it.

This is the first decision because it changes:

- Play policy posture
- Android manifest permissions
- dependency graph
- user-consent UX
- payment reconciliation claims

### Decision A: SMS autoread stays in product scope

If this is the decision, implement all of the following:

- add Android `READ_SMS`
- add Android `RECEIVE_SMS`
- add SMS ingestion package such as `another_telephony` or a deliberate alternative
- implement sender-filtered SMS listener
- implement parser and reconciliation upload flow
- implement consent and disclosure UX
- verify Play restricted-permission declaration artifacts

Files likely affected:

- `pubspec.yaml`
- `android/app/src/main/AndroidManifest.xml`
- `lib/app.dart`
- `lib/core/services/`
- `lib/features/momo/repositories/`
- `lib/features/momo/screens/`
- `docs/google_play_sms_declaration.md`
- `docs/google_play_release_2026.md`
- `.env.example`

### Decision B: SMS autoread is removed from scope

If this is the decision, remove all claims that the app depends on it:

- remove SMS-based release language
- remove Play restricted-permission preparation docs
- remove stale feature flags
- remove references to `another_telephony`
- restate reconciliation behavior accurately

Files likely affected:

- `README.md`
- `.env.example`
- `docs/google_play_sms_declaration.md`
- `docs/google_play_release_2026.md`
- `docs/qa_release_readiness.md`
- `scripts/_android_release_build.sh`

### Exit Criteria

- There is one true product statement for payment confirmation behavior.
- Repo docs, app config, and manifest match that statement.

## Workstream 1: Firebase Completion

### Purpose

Firebase is already a real runtime dependency in this app. It must stop being optional and partially configured on iOS.

### Tasks

1. Register the iOS app properly in Firebase.
2. Add `GoogleService-Info.plist` for iOS.
3. Run `flutterfire configure`.
4. Generate `lib/firebase_options.dart`.
5. Replace ad hoc `Firebase.initializeApp()` with deterministic initialization using generated options.
6. Ensure background-message initialization uses the same config path.
7. Verify Messaging, Crashlytics, Performance, Analytics, Remote Config, and App Check start from a known-good state.

### Files to change

- `lib/main.dart`
- `lib/core/services/firebase_bootstrap_service.dart`
- `lib/core/services/fcm_service.dart`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

### Recommended implementation detail

Use one initialization path:

```dart
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

Avoid the current silent-degrade model in release builds for Firebase. If Firebase is required for critical observability and messaging, release startup should fail loudly during QA rather than limp through production.

### Validation

- Launch app on Android and iOS
- verify `Firebase.apps.isNotEmpty`
- verify Crashlytics non-fatal logs
- verify Performance traces are created
- verify Remote Config fetch works
- verify FCM token registration works
- verify App Check activation succeeds in release-like builds

### Exit Criteria

- Firebase is configured on both Android and iOS.
- `firebase_options.dart` exists and is used.
- No iOS Firebase dependency remains “best effort”.

## Workstream 2: iOS Native Production Completion

### Purpose

The iOS app currently has several feature declarations without the final native configuration required to make them work in production.

### Stream 2A: iOS Maps key completion

Tasks:

1. define `GOOGLE_MAPS_IOS_API_KEY`
2. wire it into release and debug xcconfig or a secure CI-driven xcconfig generation path
3. update iOS build scripts to inject the key
4. document the key in `.env.example` or its approved secure equivalent

Files:

- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`
- `ios/Runner/Info.plist`
- `scripts/build_ios_production.sh`
- `.env.example`

Validation:

- run iOS app on device or simulator
- verify map renders
- verify no blank-map or missing-key startup issue

Exit Criteria:

- iOS map rendering works from the standard build path, not just from manual local patching

### Stream 2B: iOS NFC completion

Tasks:

1. add the Core NFC capability in the Xcode project / entitlements
2. verify the entitlement file contains the required NFC capability
3. confirm the package behavior on iOS matches the product promise
4. if iOS write is not truly supported by product intent, make the UI and copy explicit

Files:

- `ios/Runner/Runner.entitlements`
- `ios/Runner.xcodeproj/project.pbxproj`
- `lib/features/momo/services/nfc_service.dart`
- any NFC UX surface that currently implies more than iOS can support

Validation:

- test NFC read on physical iPhone hardware
- verify expected user alert copy
- verify unsupported operations are clearly blocked in UI

Exit Criteria:

- iOS NFC either works as promised or is explicitly scoped to supported operations only

### Stream 2C: iOS Universal Links completion

Tasks:

1. populate `apple-app-site-association`
2. align the app identifier, team, bundle, and path rules
3. confirm associated domains entitlement matches the final production host
4. update the fallback site once iPhone metadata is live

Files:

- `ios/Runner/Runner.entitlements`
- `deeplinks/site/.well-known/apple-app-site-association`
- `deeplinks/site/download-ios/index.html`
- `deeplinks/site/README.md`

Validation:

- install a signed iOS build
- open a supported `https://cool.app/...` route
- confirm it opens in-app instead of Safari

Exit Criteria:

- Universal Links work for the supported route inventory on iPhone

### Stream 2D: iOS contacts permission completion

Tasks:

1. add `PERMISSION_CONTACTS=1` to the iOS permission macros
2. verify contacts permission prompt works at runtime

Files:

- `ios/Podfile`

Validation:

- trigger contacts flow on iOS
- verify permission prompt and successful contact fetch

Exit Criteria:

- Contacts flows work on iOS without native permission mismatch

## Workstream 3: Native Dependency Regeneration and Lockfile Correction

### Purpose

The iOS lockfile appears stale relative to declared Flutter dependencies. That needs to be corrected after the Firebase and iOS native fixes land.

### Tasks

1. run `flutter clean`
2. run `flutter pub get`
3. run `pod install` in `ios/`
4. inspect `ios/Podfile.lock`
5. verify all declared native plugin families appear
6. commit the corrected lockfile

### Expected pod families after correction

At minimum, validate presence of:

- Firebase Core
- Firebase Messaging
- Firebase Crashlytics
- Firebase Performance
- Firebase Analytics
- Firebase Remote Config
- Firebase App Check related dependencies if applicable
- Google Maps iOS native dependencies
- permission handler Apple
- geolocator Apple
- mobile_scanner
- flutter_nfc_kit

### Validation

- `flutter build ios --flavor production --no-codesign`
- confirm generated pods align with `pubspec.yaml`

### Exit Criteria

- `Podfile.lock` reflects the real app dependency graph

## Workstream 4: Config and Release Hygiene

### Purpose

The repo currently contains configuration drift and release artifacts that are only partially complete.

### Stream 4A: Environment and build input cleanup

Tasks:

1. add missing maps env documentation
2. explicitly document which secrets are client-safe and which are server-only
3. remove or update stale flags

Files:

- `.env.example`
- `supabase/functions/.env.example`
- `lib/core/config/env_config.dart`

### Stream 4B: Android App Links completion

Tasks:

1. replace `REPLACE_WITH_PLAY_APP_SIGNING_SHA256`
2. verify the final store-signed package matches `assetlinks.json`

Files:

- `deeplinks/site/.well-known/assetlinks.json`

Validation:

- test store-style Android app-link verification

### Stream 4C: Documentation truth pass

Tasks:

1. update README tech stack to reflect current implementation
2. update Google Play docs to reflect real manifest and permission posture
3. update mobility and Firebase docs to reflect the actual platform configuration

Files:

- `README.md`
- `docs/google_play_sms_declaration.md`
- `docs/google_play_release_2026.md`
- `docs/qa_release_readiness.md`
- `docs/google_stack_implementation_plan.md`

### Exit Criteria

- A new engineer reading the repo would not be misled about shipping behavior

## Workstream 5: Dependency Upgrades and Hardening

### Purpose

Only do this after the production blockers are closed.

### Current direct package drift

- `app_links`
- `flutter_nfc_kit`
- `flutter_riverpod`
- `go_router`
- `google_fonts`
- `ndef`

### Upgrade strategy

1. upgrade low-risk packages first:
   - `flutter_nfc_kit`
   - `ndef`
   - `google_fonts`
2. then routing and state packages:
   - `go_router`
   - `flutter_riverpod`
3. then deep-link package:
   - `app_links`

### Validation after each family

- `flutter test`
- smoke run on Android
- smoke run on iOS
- route, NFC, and deep-link regressions checked explicitly

### Exit Criteria

- Dependency drift is reduced without introducing routing or native integration regressions

## Implementation Sequence By PR

### PR 1: Product truth and docs gate

Scope:

- decide SMS path
- remove or confirm SMS claims
- align docs and flags

Must merge first because it changes the architecture contract.

### PR 2: Firebase completion

Scope:

- `flutterfire configure`
- add `firebase_options.dart`
- add iOS Firebase config
- deterministic bootstrap

### PR 3: iOS native completion

Scope:

- maps key
- NFC entitlement
- contacts macro
- universal links

### PR 4: iOS pods and build stabilization

Scope:

- regenerate pods
- validate lockfile
- confirm clean release build

### PR 5: Config and release hygiene

Scope:

- `.env.example`
- App Links production fingerprint
- release docs

### PR 6: Dependency upgrades

Scope:

- direct package upgrades
- regression fixes if needed

## Verification Matrix

### Android

- app boots with valid Supabase config
- Google map renders
- current location works
- QR scan works
- NFC read works
- App Links open app
- FCM token registers
- notifications work
- payment verification behavior matches the chosen product truth

### iOS

- app boots with Firebase initialized
- Google map renders with valid key
- current location works
- QR scan works
- contacts permission works
- NFC read works on supported hardware
- Universal Links open app
- FCM/APNs registration works
- Crashlytics / Performance / Analytics / Remote Config are active

## Suggested Acceptance Commands

Use these as the minimum engineering validation set:

```bash
flutter clean
flutter pub get
flutter test
flutter build apk --flavor production
flutter build ios --flavor production --no-codesign
cd ios && pod install
```

If SMS autoread remains in scope, add:

```bash
rg -n "READ_SMS|RECEIVE_SMS|another_telephony|momo_sms"
```

If iOS Universal Links are completed, add manual device validation against the final production host.

## Risks

### Highest risks

- keeping SMS autoread in docs but not in code
- partially configured Firebase on iOS masking production failures
- iOS features appearing implemented in Dart while missing native entitlements
- stale iOS pod lock state hiding integration errors until late QA

### Mitigations

- force the SMS decision first
- make Firebase initialization deterministic
- validate iOS features on real hardware
- regenerate and commit native lock state after each platform integration change

## Recommended Immediate Next Step

Start with PR 1 and resolve the SMS verification truth gap before touching package upgrades or cosmetic cleanup.

If the product owner confirms SMS autoread is out of scope, the fastest path to a stable release becomes:

1. remove SMS claims
2. finish Firebase iOS
3. finish iOS native integrations
4. refresh pods
5. clean docs

If SMS autoread stays in scope, implement that path before release work continues.
