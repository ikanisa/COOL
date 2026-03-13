# ARCHIVED — COOL Mobile Dependency, SDK, and Gap Report

Date: 2026-03-12

> Archived on 2026-03-13.
>
> This report is retained for historical context only. It is no longer a
> source of truth for the live SMS and payment implementation.
>
> Known-invalid findings in this report include:
> - the claim that the Android SMS autoread client path was missing
> - the claim that the app code and manifest did not implement SMS-based MoMo
>   ingestion
> - the March 12 release-readiness assumptions that predate the operational
>   health dashboard and current payment observability
>
> Use these instead:
> - `docs/OPERATIONAL_OBSERVABILITY.md`
> - `docs/qa_release_readiness.md`
> - Admin > Operations at `/admin/operations`

## Scope

This report audits the current COOL Flutter repository and compares it against the stack actually required to ship the app across:

- Flutter / Dart
- Android
- iOS
- mobility / maps / geolocation
- NFC
- QR scanning
- Firebase
- Supabase
- app links / universal links
- payments support flows
- external cloud services

This is repo-grounded first, then checked against official or primary-source documentation current as of 2026-03-12.

## Research Method

1. Audited the repository:
   - `pubspec.yaml`
   - Android Gradle, manifest, wrapper, plugin settings
   - iOS Podfile, Podfile.lock, entitlements, Info.plist, AppDelegate
   - Flutter bootstrap and service layer
   - Supabase config and Edge Function secrets
   - deep-link site artifacts and release docs
2. Verified local toolchain with:
   - `flutter --version`
   - `dart --version`
   - `flutter doctor -v`
   - `flutter pub deps --style=compact`
   - `flutter pub outdated --no-dev-dependencies`
3. Cross-checked against primary sources:
   - Flutter install docs for macOS / iOS / Android
   - Firebase Flutter setup and App Check docs
   - Android NFC and App Links docs
   - Apple Universal Links guidance
   - pub.dev package pages for `google_maps_flutter`, `geolocator`, `mobile_scanner`, `flutter_nfc_kit`, `permission_handler`, `flutter_contacts`, `supabase_flutter`
   - Supabase Edge Functions docs
   - Google Wallet docs

## Executive Summary

The Android side is materially closer to production than iOS. The repository already has a solid Flutter toolchain, a modern Android build stack, Google Maps UI, Supabase, Firebase service wrappers, QR scanning, NFC code, and deep-link scaffolding. The major problems are not "missing Flutter packages" in the abstract. They are integration and production-readiness gaps.

The highest-risk gaps are:

1. iOS Firebase is not repo-complete. There is no checked-in `GoogleService-Info.plist` and no generated `firebase_options.dart`, while the app expects Firebase to power Crashlytics, Performance, Messaging, Remote Config, Analytics, and App Check.
2. The repository documentation claims Android SMS-based M-Money verification is a core shipping path, but the current app code and manifest do not implement that path.
3. iOS NFC is not production-ready. The app has NFC usage copy, but the iOS entitlements do not include the required NFC capability.
4. iOS universal links are not production-ready. The entitlements declare associated domains, but the hosted `apple-app-site-association` file is empty.
5. iOS Google Maps key wiring is incomplete. The app looks for `GOOGLE_MAPS_IOS_API_KEY`, but the checked-in xcconfig files leave it blank.
6. The committed iOS pod state does not match the declared Flutter dependency graph. Current `Podfile.lock` reflects only a subset of the Firebase and platform plugins the app declares.

The biggest process problem is documentation drift. Several internal docs and the README describe a stronger production posture than the repo currently implements.

## Current Toolchain Baseline

### Local machine state

| Area | Current state | Status |
| --- | --- | --- |
| Flutter SDK | 3.38.9 | Healthy |
| Dart SDK | 3.10.8 | Healthy |
| FVM | `.fvmrc` pins `3.38.9` | Healthy |
| Android SDK | 36.1.0 | Healthy |
| Java | OpenJDK 17.0.17 | Healthy |
| Xcode | 26.2 | Healthy |
| CocoaPods | 1.16.2 | Healthy |
| Flutter doctor | No issues found | Healthy |

### Repo-pinned native build stack

| Area | Repo state | Evidence | Status |
| --- | --- | --- | --- |
| Android Gradle Plugin | `8.11.1` | `android/settings.gradle.kts:22` | Healthy |
| Kotlin plugin | `2.2.20` | `android/settings.gradle.kts:23` | Healthy |
| Google services plugin | `4.4.2` | `android/settings.gradle.kts:24` | Healthy |
| Firebase Crashlytics plugin | `3.0.3` | `android/settings.gradle.kts:25` | Healthy |
| Firebase Performance plugin | `1.4.2` | `android/settings.gradle.kts:26` | Healthy |
| Gradle wrapper | `8.14` | `android/gradle/wrapper/gradle-wrapper.properties:5` | Healthy |
| Java target | 17 | `android/app/build.gradle.kts:99-107` | Healthy |
| Android min SDK | 26 | `android/app/build.gradle.kts:109-116` | Healthy |
| iOS deployment target | 15.0 | `ios/Podfile:1` | Healthy |

## Required Stack By Capability

This section answers: what does this app actually need in order to function and ship?

### 1. Core app and build tooling

| Capability | Required tools / SDKs / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| Flutter app runtime | Flutter SDK, Dart SDK, FVM | Entire app is Flutter; `.fvmrc` pins the SDK | Implemented |
| Android builds | Android SDK, JDK 17, Gradle 8.x, AGP 8.x, Kotlin 2.x | Required by current plugin stack, especially modern Firebase and NFC packages | Implemented |
| iOS builds | Xcode, CocoaPods, iOS 15+ target | Required by current plugin stack, especially Google Maps and Firebase | Implemented |

### 2. App architecture and state

| Capability | Required packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| State management | `flutter_riverpod`, `equatable` | App-wide state, providers, feature composition | Implemented |
| Navigation | `go_router`, `app_links` | App navigation, deep links, route handoff | Implemented |
| Storage / offline | `hive_flutter` | Local persistence and offline-friendly behavior | Implemented |
| Networking | `dio` | API and gateway requests | Implemented |

### 3. Backend and identity

| Capability | Required services / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| Primary backend | Supabase project, Postgres, Realtime, Storage, Auth, Edge Functions, `supabase_flutter` | System of record for app data and server-side workflows | Implemented |
| Client bootstrap | `SUPABASE_URL`, `SUPABASE_ANON_KEY` | App startup blocks on these | Implemented |
| Server secrets | Supabase service role key and function secrets | Maps gateway, WhatsApp OTP, wallet issuance, AI parsing | Implemented |

### 4. Firebase and Google mobile services

| Capability | Required services / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| Firebase core | `firebase_core`, FlutterFire config, Android `google-services.json`, iOS `GoogleService-Info.plist`, generated `firebase_options.dart` | Base requirement for all Firebase features used in app code | Partial |
| Messaging | `firebase_messaging`, APNs registration on iOS, Android/iOS app registration in Firebase | Push transport and topic subscription | Partial |
| Crash reporting | `firebase_crashlytics` | Production crash capture | Partial |
| Performance | `firebase_performance` | Trace collection for key app flows | Partial |
| Analytics | `firebase_analytics` | Engagement tracking and future Remote Config targeting | Partial |
| Remote Config | `firebase_remote_config` | Feature flags and rollout control | Partial |
| App Check | `firebase_app_check`, Play Integrity, App Attest or DeviceCheck | Anti-abuse / attestation | Partial |

### 5. Mobility, maps, and geolocation

| Capability | Required services / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| In-app map rendering | `google_maps_flutter` plus Maps SDK for Android and iOS | Mobility map surfaces and trip previews | Implemented, with iOS config gap |
| Place search and routing | Google Maps server APIs, `maps-gateway` function, server API key | Autocomplete, place details, reverse geocoding, route preview | Implemented |
| Fallback geocoding | Nominatim / OSM fallback via `dio` | Repo keeps a fallback path for maps-gateway failures | Implemented |
| Device location | `geolocator`, Android location permissions, iOS location usage descriptions | Nearby drivers, trip discovery, recentering | Implemented |

### 6. QR, NFC, contacts, sharing, and device access

| Capability | Required services / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| QR generation | `qr_flutter` | Payment and invite surfaces | Implemented |
| QR scanning | `mobile_scanner`, camera permission | Ticket and MoMo QR scanning | Implemented |
| NFC read/write | `flutter_nfc_kit`, `ndef`, Android NFC permission, iOS NFC capability and usage description | Phone-to-phone or tag-based MoMo flows | Partial |
| Contacts | `flutter_contacts`, `permission_handler`, iOS contacts macro, Android `READ_CONTACTS` | Invite and sharing flows | Partial |
| Sharing / handoff | `share_plus`, `url_launcher` | Share content, open USSD, open store links | Implemented |

### 7. App links and store handoff

| Capability | Required services / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| Android App Links | `app_links`, `intent-filter android:autoVerify`, valid `assetlinks.json`, package fingerprints | Direct open of `https://cool.app/...` on Android | Partial |
| iOS Universal Links | Associated domains entitlement, valid `apple-app-site-association`, App Store app registration | Direct open of `https://cool.app/...` on iPhone | Partial to missing |
| Custom scheme | `cool://` | Fallback deep-link path | Implemented |

### 8. Payments and verification support

| Capability | Required services / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| Mobile Money USSD launch | `url_launcher` | Core payment initiation path | Implemented |
| WhatsApp OTP | WhatsApp Cloud API server credentials | Authentication delivery path | Implemented |
| Android SMS autoread | Android `READ_SMS` / `RECEIVE_SMS`, SMS listener package such as `another_telephony`, parser / ingestion pipeline, Play restricted-permission compliance | Required only if the product truly depends on on-device M-Money SMS confirmation | Missing in current codebase |
| AI SMS parsing | OpenAI or Gemini secret plus parsing function | Server-side parsing of uploaded SMS confirmation text | Implemented server-side, but client ingestion path is missing |

### 9. Wallet and partner capabilities

| Capability | Required services / packages | Why this app needs it | Repo status |
| --- | --- | --- | --- |
| Google Wallet issuance | Google Wallet API, issuer ID, service account credentials, backend issuance function | Partner tickets / wallet passes | Implemented server-side |

## Direct Flutter Dependency Inventory

These are the top-level app dependencies declared in `pubspec.yaml`.

### UI and presentation

- `cupertino_icons: ^1.0.8`
- `google_fonts: ^6.3.2`
- `flutter_animate: ^4.5.0`
- `intl: ^0.20.2`
- `crypto: ^3.0.7`
- `pdf: ^3.11.3`
- `syncfusion_flutter_xlsio: ^32.2.9`

### Architecture and navigation

- `flutter_riverpod: ^2.6.1`
- `equatable: ^2.0.7`
- `go_router: ^16.2.1`
- `app_links: ^6.1.1`

### Backend, storage, and network

- `supabase_flutter: ^2.10.2`
- `dio: ^5.8.0`
- `hive_flutter: ^1.1.0`

### Mobility and device access

- `google_maps_flutter: ^2.15.0`
- `geolocator: ^14.0.2`
- `permission_handler: ^12.0.1`
- `flutter_contacts: ^2.0.0`

### QR, NFC, and sharing

- `qr_flutter: ^4.1.0`
- `mobile_scanner: ^7.2.0`
- `flutter_nfc_kit: ^3.4.0`
- `ndef: ^0.3.1`
- `url_launcher: ^6.3.2`
- `share_plus: ^12.0.1`

### Firebase

- `firebase_core: ^4.5.0`
- `firebase_analytics: ^12.1.3`
- `firebase_remote_config: ^6.2.0`
- `firebase_messaging: ^16.0.0`
- `firebase_crashlytics: ^5.0.0`
- `firebase_performance: ^0.11.1+5`
- `firebase_app_check: ^0.4.1+5`
- `flutter_native_splash: ^2.4.6`

### Dev dependencies

- `flutter_test`
- `integration_test`
- `flutter_lints: ^6.0.0`
- `mocktail: ^1.0.4`
- `shared_preferences: ^2.5.3`
- `flutter_launcher_icons: ^0.14.4`

## What Is Already Implemented Well

### Solid or near-solid

- Flutter toolchain is modern and healthy.
- Android build stack is modern and aligned with current plugin needs.
- Supabase is clearly the primary backend and is wired into app startup.
- Google Maps UI is already in the app, not just planned.
- Maps gateway and Google Maps server-side secret handling exist.
- Location permissions and usage descriptions are present on both platforms.
- Camera permissions and QR scanning flows are implemented.
- Android NFC permission and NDEF intent filter are present.
- Firebase service wrappers exist for Messaging, Crashlytics, Performance, Analytics, Remote Config, and App Check.
- Deep-link domain strategy exists, including Android App Links, iOS associated domains, and `cool://` fallback.
- Google Wallet server-side issuance credentials are modeled.

### Partially implemented but strategically correct

- Mobility map stack is now hybrid-Google-first rather than legacy OSM-only.
- App Check activation logic exists and selects Play Integrity on Android and App Attest on Apple in release builds.
- FCM lifecycle logic is present, including background handler and topic logic.

## Gap Report

### Critical gaps

#### 1. iOS Firebase configuration is incomplete

Severity: Critical

What is required:

- Firebase iOS app registration
- `GoogleService-Info.plist`
- generated `firebase_options.dart`
- deterministic `Firebase.initializeApp(...)`

What exists:

- `ios/Runner/AppDelegate.swift:12-19` calls `FirebaseApp.configure()`
- `lib/main.dart:29-36` initializes Firebase in a `try/catch` and continues on failure
- Android Firebase config files exist

What is missing:

- No `ios/**/GoogleService-Info.plist` found in the repo
- No `lib/firebase_options.dart` found in the repo

Why it matters:

- iOS Crashlytics, Messaging, Remote Config, Performance, Analytics, and App Check are not repo-complete and may silently degrade.

#### 2. Android SMS autoread payment verification is documented as core, but not implemented

Severity: Critical

What is required if this product requirement is real:

- Android `READ_SMS` and `RECEIVE_SMS`
- an SMS listener package such as `another_telephony`
- client-side ingestion and filtering pipeline
- Play Console restricted-permission compliance

What exists:

- README and docs repeatedly describe Android M-Money SMS verification as core behavior
- `.env.example:16-20` still exposes `ENABLE_ANDROID_MOMO_SMS_AUTOREAD`

What is missing in code:

- `android/app/src/main/AndroidManifest.xml` does not declare `READ_SMS` or `RECEIVE_SMS`
- `pubspec.yaml` does not include `another_telephony` or an equivalent SMS listener package
- repo search found no `momo_sms_listener.dart`, `momo_sms_parser.dart`, or `momo_sms_ingestion_repository.dart`

Why it matters:

- The repo and release docs disagree about a payment-critical behavior. This is both a product risk and a compliance risk.

#### 3. iOS NFC is not production-ready

Severity: Critical

What is required:

- `NFCReaderUsageDescription`
- Near Field Communication Tag Reading capability / entitlements

What exists:

- `ios/Runner/Info.plist:39-40` sets `NFCReaderUsageDescription`
- NFC runtime code exists in `lib/features/momo/services/nfc_service.dart`

What is missing:

- `ios/Runner/Runner.entitlements` only contains associated domains and `aps-environment`
- no NFC entitlement is present

Why it matters:

- On iPhone, the code path exists, but the native entitlement layer is incomplete.

#### 4. iOS universal links are not production-ready

Severity: Critical

What is required:

- Associated domains entitlement
- valid `apple-app-site-association` with populated `details`
- final bundle ID / team / app registration alignment

What exists:

- `ios/Runner/Runner.entitlements:5-8` declares `applinks:cool.app` and `applinks:www.cool.app`

What is missing:

- `deeplinks/site/.well-known/apple-app-site-association:1-6` has empty `details`
- `deeplinks/site/download-ios/index.html:83-87` explicitly says iPhone install and universal-link metadata are disabled

Why it matters:

- iPhone deep links are structurally declared but not actually publishable.

### High-severity gaps

#### 5. iOS Google Maps key wiring is incomplete

Severity: High

What is required:

- Maps SDK for iOS enabled
- a native iOS maps API key
- runtime key injection via Info.plist / AppDelegate

What exists:

- `ios/Runner/AppDelegate.swift:15-19` reads `GoogleMapsApiKey` and calls `GMSServices.provideAPIKey(apiKey)`
- `ios/Runner/Info.plist:29-30` expects `$(GOOGLE_MAPS_IOS_API_KEY)`

What is missing:

- `ios/Flutter/Debug.xcconfig:3` sets `GOOGLE_MAPS_IOS_API_KEY=` blank
- `ios/Flutter/Release.xcconfig:3` sets `GOOGLE_MAPS_IOS_API_KEY=` blank
- `scripts/build_ios_production.sh:20-29` passes map IDs but not `GOOGLE_MAPS_IOS_API_KEY`
- `.env.example` documents neither `GOOGLE_MAPS_ANDROID_API_KEY` nor `GOOGLE_MAPS_IOS_API_KEY`

Why it matters:

- The code is ready to consume the key, but the repo’s build path does not provide it.

#### 6. iOS contacts permission macro is missing from Podfile

Severity: High

What is required:

- `NSContactsUsageDescription`
- `permission_handler` iOS contacts macro

What exists:

- `ios/Runner/Info.plist:41-42` sets `NSContactsUsageDescription`
- `lib/core/services/contacts_service.dart:13-20` requests `Permission.contacts`

What is missing:

- `ios/Podfile:49-57` defines camera, location, notifications, photos, but not `PERMISSION_CONTACTS=1`

Why it matters:

- Contacts flows are implemented in Dart but the native iOS permission build flags are not fully aligned.

#### 7. Committed iOS pod state does not match the declared dependency graph

Severity: High

What is required:

- iOS native pod installation consistent with declared Flutter dependencies

What exists:

- `pubspec.yaml` declares `firebase_analytics`, `firebase_remote_config`, `firebase_crashlytics`, `firebase_performance`, `firebase_app_check`, and `google_maps_flutter`

What `ios/Podfile.lock` currently shows:

- `firebase_core`
- `firebase_messaging`
- `flutter_nfc_kit`
- `geolocator_apple`
- `mobile_scanner`
- `permission_handler_apple`
- no `firebase_analytics`
- no `firebase_remote_config`
- no `firebase_crashlytics`
- no `firebase_performance`
- no `firebase_app_check`
- no Google Maps iOS pod

Why it matters:

- The committed iOS native dependency lockfile looks stale or incomplete relative to the app code and `pubspec.yaml`.

#### 8. Android App Links are only partially production-ready

Severity: High

What is required:

- final upload certificate and Play App Signing fingerprint in `assetlinks.json`

What exists:

- `android/app/src/main/AndroidManifest.xml:62-73` declares App Links with `android:autoVerify="true"`
- `deeplinks/site/.well-known/assetlinks.json:1-27` includes one real fingerprint

What is missing:

- `deeplinks/site/.well-known/assetlinks.json:15-24` still contains `REPLACE_WITH_PLAY_APP_SIGNING_SHA256`

Why it matters:

- Store-installed builds may fail link verification until the Play signing fingerprint is added.

### Medium-severity gaps

#### 9. Documentation drift around maps, Firebase, and SMS is significant

Severity: Medium

Examples:

- `docs/google_stack_implementation_plan.md:107-115` correctly says `firebase_options.dart` and explicit maps key envs should exist, but the repo has not completed that work.
- `docs/google_play_sms_declaration.md:68-74` states production builds include `READ_SMS` and `RECEIVE_SMS`, which is false in the current manifest.
- `README.md:118-120` says Android SMS verification uses `another_telephony`, but that package is not in `pubspec.yaml`.

Why it matters:

- Internal release, compliance, and engineering decisions will be made from inaccurate repo documents.

#### 10. Mobility is Google-first, but not fully Google-only

Severity: Medium

What exists:

- `lib/features/mobility/services/place_search_service.dart:30-35` uses a Google Maps gateway first
- `lib/features/mobility/services/place_search_service.dart:32` keeps `NominatimPlaceSearchService` as fallback
- `lib/core/config/env_config.dart:41-49` still defaults geocoding to `https://nominatim.openstreetmap.org`

Why it matters:

- This is not inherently wrong, but it is a mixed architecture. If the target architecture is "Google Maps stack end to end", the repo has not fully converged.

#### 11. Version drift exists in a few direct dependencies

Severity: Medium

`flutter pub outdated --no-dev-dependencies` reported these direct packages behind resolvable latest versions:

- `app_links` `6.4.1` -> latest `7.0.0`
- `flutter_nfc_kit` `3.6.0` -> `3.6.2`
- `flutter_riverpod` `2.6.1` -> `3.3.1`
- `go_router` `16.3.0` -> `17.1.0`
- `google_fonts` `6.3.3` -> `8.0.2`
- `ndef` `0.3.5` -> `0.4.0`

Why it matters:

- These are not the primary blockers, but they represent maintenance drift.

### Low-severity cleanup

#### 12. Some package declarations look suspicious or low-value

Severity: Low

Examples:

- `cupertino_icons` appears unused in app code
- `shared_preferences` is listed under `dev_dependencies`, not `dependencies`, and does not appear to be a core part of the current runtime architecture

## Evidence Snapshot

### Android

- Manifest includes Internet, notifications, location, NFC, contacts, camera, and media permissions:
  - `android/app/src/main/AndroidManifest.xml:3-29`
- Manifest includes Maps API metadata:
  - `android/app/src/main/AndroidManifest.xml:37-39`
- Manifest includes App Links and custom scheme:
  - `android/app/src/main/AndroidManifest.xml:62-81`
- Manifest includes NFC NDEF intent filter:
  - `android/app/src/main/AndroidManifest.xml:83-88`
- Manifest does not include SMS permissions.

### iOS

- `Info.plist` declares camera, location, photos, NFC, contacts, push background mode, and custom URL scheme:
  - `ios/Runner/Info.plist:27-83`
- `Runner.entitlements` only declares associated domains and APS:
  - `ios/Runner/Runner.entitlements:5-11`
- `AppDelegate` configures Firebase and optionally injects the Google Maps API key:
  - `ios/Runner/AppDelegate.swift:12-27`

### Flutter app bootstrap

- `main.dart` performs best-effort Firebase init and continues on failure:
  - `lib/main.dart:29-36`
- App Check uses Play Integrity on Android and App Attest on Apple in release builds:
  - `lib/core/services/app_check_service.dart:23-33`
- Contacts permission is actively requested in runtime code:
  - `lib/core/services/contacts_service.dart:13-20`
- NFC code is implemented:
  - `lib/features/momo/services/nfc_service.dart:159-285`
- Google Maps place resolution uses a server gateway with Nominatim fallback:
  - `lib/features/mobility/services/place_search_service.dart:15-35`

### External service surface modeled by the repo

- Supabase function secrets include WhatsApp, OpenAI or Gemini, Google Maps server key, and Google Wallet credentials:
  - `supabase/functions/.env.example:5-34`
- Supabase local config shows Auth, Realtime, Storage, Studio, Edge Functions, and Postgres 17:
  - `supabase/config.toml:7-247`

## Recommended Remediation Order

### P0: Decide and normalize the payment verification architecture

Pick one:

1. SMS autoread is truly required:
   - implement the Android restricted-permission path for real
   - add the listener package
   - add manifest permissions
   - add consent UX
   - add parser and ingestion pipeline
   - keep Play declaration docs
2. SMS autoread is no longer required:
   - remove the claims from README and release docs
   - remove the `ENABLE_ANDROID_MOMO_SMS_AUTOREAD` flag and related release text
   - reframe reconciliation around a different supported flow

This decision must happen first because it affects compliance, release posture, and product truthfulness.

### P0: Finish Firebase properly for iOS

- register the iOS app in Firebase
- add `GoogleService-Info.plist`
- run `flutterfire configure`
- generate and use `firebase_options.dart`
- move Firebase initialization from best-effort to deterministic startup
- refresh iOS pods and lockfile

### P1: Make iOS platform integrations real, not declarative only

- add NFC capability / entitlements
- complete `apple-app-site-association`
- publish final App Store metadata and bundle alignment
- inject `GOOGLE_MAPS_IOS_API_KEY`
- add `PERMISSION_CONTACTS=1`

### P1: Refresh native iOS dependency state

- run a clean `pod install` after Firebase and maps config are fixed
- commit the resulting `Podfile.lock`
- verify all declared Firebase plugins and Google Maps iOS pods appear

### P2: Clean up config and docs drift

- add missing maps API key documentation to `.env.example`
- fix `assetlinks.json` with Play signing fingerprint
- update README and release docs to match real behavior
- remove stale or unused packages if confirmed unnecessary

### P3: Upgrade non-blocking dependency drift

- upgrade the six direct dependencies that are behind resolvable versions
- run focused regression tests after each major package family upgrade

## Bottom-Line Assessment

The app already has most of the right major building blocks:

- Flutter / Dart
- modern Android build tooling
- Supabase
- Google Maps UI
- Firebase service wrappers
- NFC code
- QR scanning
- deep-link scaffolding

The missing pieces are mostly at the native integration and production-hardening layer, especially on iOS. The repo is not missing an entire mobile stack. It is missing completion, consistency, and a few hard platform artifacts that decide whether features actually work in production.

## Primary Sources

- Flutter install for iOS on macOS:
  - https://docs.flutter.dev/get-started/install/macos/mobile-ios
- Flutter install for Android on macOS:
  - https://docs.flutter.dev/get-started/install/macos/mobile-android
- Firebase setup for Flutter:
  - https://firebase.google.com/docs/flutter/setup
- Firebase App Check for Flutter:
  - https://firebase.google.com/docs/app-check/flutter/default-providers
- Android NFC overview:
  - https://developer.android.com/develop/connectivity/nfc/nfc
- Android App Links overview:
  - https://developer.android.com/training/app-links/about
- Apple Universal Links:
  - https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html
- `google_maps_flutter`:
  - https://pub.dev/packages/google_maps_flutter
- `geolocator`:
  - https://pub.dev/packages/geolocator
- `mobile_scanner`:
  - https://pub.dev/packages/mobile_scanner
- `flutter_nfc_kit`:
  - https://pub.dev/packages/flutter_nfc_kit
- `permission_handler`:
  - https://pub.dev/packages/permission_handler
- `flutter_contacts`:
  - https://pub.dev/packages/flutter_contacts
- `supabase_flutter`:
  - https://pub.dev/packages/supabase_flutter
- Supabase Edge Functions:
  - https://supabase.com/docs/guides/functions
- Google Wallet generic pass flow:
  - https://developers.google.com/wallet/generic/overview/add-to-google-wallet-flow
