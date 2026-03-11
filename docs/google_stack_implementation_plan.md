# Google Stack Implementation Plan

## Objective

Implement the Google platform capabilities that most directly improve user experience, reliability, growth, and security in this app, while keeping Supabase as the system of record.

This plan treats a full Google Maps UI migration as a required first workstream, not a later optimization.

## Repo-Specific Starting Point

Current state in this repository:

- The app is Flutter mobile with Supabase as the primary backend.
- Firebase is only partially integrated: `firebase_core`, `firebase_analytics`, and `firebase_remote_config` are present in `pubspec.yaml`.
- Firebase bootstrap is not part of the primary startup path.
- Mobility still uses `flutter_map`, `latlong2`, and Nominatim/OpenStreetMap.
- The partner ticket flow exposes an `Add to Wallet` button, but it is not connected to Google Wallet.
- Notification preferences exist in UI, but FCM is not wired in the current dependency graph.
- Android Firebase config exists in repo, but iOS Firebase registration/config generation appears incomplete.

Primary code touchpoints for this plan:

- `pubspec.yaml`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `lib/core/config/env_config.dart`
- `lib/main.dart`
- `lib/app.dart`
- `lib/core/services/firebase_bootstrap_service.dart`
- `lib/features/mobility/screens/mobility_home_screen.dart`
- `lib/features/mobility/screens/schedule_trip_screen.dart`
- `lib/features/mobility/screens/trip_board_screen.dart`
- `lib/features/mobility/services/place_search_service.dart`
- `lib/features/mobility/providers/mobility_location_provider.dart`
- `lib/features/mobility/models/trip.dart`
- `lib/features/mobility/models/trip_post_request.dart`
- `lib/features/partners/screens/rayon/ticket_confirmation_screen.dart`
- `lib/shared/widgets/rs_membership_card.dart`
- `supabase/functions/`
- `supabase/migrations/`

## Architecture Principle

Use Google as the mobile services, mapping, experimentation, messaging, and wallet layer around Supabase.

Do not turn Firebase into a second source of truth for product data already owned by Supabase.

Recommended split:

- Supabase: auth session, profile data, trip data, partner data, referral state, engagement state, wallet issuance state.
- Firebase/Google: analytics, crash reporting, performance, push transport, App Check, Remote Config rollouts, Maps, Places, Geocoding, Routes, Wallet, selected AI and translation services.

## Program Goals

1. Replace the current map stack with Google Maps end to end.
2. Upgrade place search, reverse geocoding, ETA, and route quality.
3. Add production-grade messaging, observability, and anti-abuse controls.
4. Turn wallet-related partner UX into real Google Wallet issuance.
5. Add experimentation and targeting infrastructure to optimize onboarding, mobility, and partner conversion.

## Workstream 0: Foundation And Cloud Setup

### Deliverables

- Firebase fully configured for Android and iOS.
- Google Cloud project with Maps, Places, Routes, Wallet, Translation, and billing enabled.
- Restricted API keys and map IDs created.
- Secrets management strategy defined for client-side SDK keys and server-side web service keys.
- Baseline monitoring and quota alerts configured.

### Cloud Configuration

Create or confirm one Google Cloud project tied to the Firebase project and enable:

- Maps SDK for Android
- Maps SDK for iOS
- Places API
- Geocoding API
- Routes API
- Google Wallet API
- Cloud Translation API Advanced
- Firebase Analytics
- Firebase Cloud Messaging
- Firebase Crashlytics
- Firebase Performance Monitoring
- Firebase Remote Config
- Firebase App Check
- BigQuery export

Create the following credentials:

- Android native maps key, restricted to package name and SHA certificate fingerprints.
- iOS native maps key, restricted to bundle ID.
- Server-side Maps web service credential stored only in backend secrets.
- Wallet issuer credentials stored only in backend secrets.

Create the following map assets:

- Android map ID for branded production styling.
- iOS map ID for branded production styling.
- Optional staging map IDs for pre-release validation.

### Repo Changes

- Generate `firebase_options.dart` using `flutterfire configure`.
- Move Firebase initialization into the main startup path instead of best-effort lazy initialization.
- Extend `EnvConfig` with explicit keys for:
  - `GOOGLE_MAPS_ANDROID_API_KEY`
  - `GOOGLE_MAPS_IOS_API_KEY`
  - `GOOGLE_MAPS_ANDROID_MAP_ID`
  - `GOOGLE_MAPS_IOS_MAP_ID`
  - `GOOGLE_TRANSLATE_PROJECT_ID`
  - backend endpoint URLs if separate from Supabase

### Acceptance Criteria

- Firebase initializes deterministically on Android and iOS.
- Android and iOS builds both render a Google map with the correct branded style.
- Console quotas and budget alerts are enabled before production traffic starts.

## Workstream 1: Full Google Maps UI Migration

### Goal

Replace `flutter_map` and the current OSM renderer with a full Google Maps UI implementation for the mobility experience.

### Key Design Decision

Do not let map vendor types leak further into domain logic.

Before replacing the renderer, introduce an app-owned coordinate model so location, trip, and repository logic stop depending directly on `latlong2.LatLng`. This prevents the map migration from permanently coupling the app to `google_maps_flutter` types.

### Recommended New Abstractions

Create:

- `lib/core/models/geo_point.dart`
- `lib/features/mobility/models/map_view_state.dart`
- `lib/features/mobility/services/maps_camera_service.dart` if camera orchestration becomes non-trivial

Refactor existing location and trip flows to use `GeoPoint` internally.

### Dependency Changes

Remove or phase out:

- `flutter_map`
- `latlong2`

Add:

- `google_maps_flutter`

Optional later additions only if needed:

- a small local polyline decoding utility
- clustering only if marker density grows beyond the current marketplace scale

### Platform Changes

Android:

- Add the Maps SDK API key metadata to `AndroidManifest.xml`.
- Keep location permissions already in place.
- Add Play Services availability checks if production device coverage reveals issues.

iOS:

- Provide the Maps SDK key during app startup in `AppDelegate.swift`.
- Confirm `Info.plist` location permission copy remains accurate for mobility usage.

### UI Migration Sequence

#### Phase 1A: Map Surface Replacement

Replace the `_MapBox` implementation in `mobility_home_screen.dart` with a `GoogleMap` widget.

Initial feature parity target:

- user location marker
- nearby driver markers
- branded dark-first styling via map ID
- disabled tilt/rotate if they do not add value
- camera initialized around the detected user location
- a visible recenter affordance

#### Phase 1B: Interaction Upgrade

Add interactions that the current OSM card does not offer:

- tap on driver marker opens the driver preview sheet
- tap on trip marker opens the trip preview sheet when trip markers are introduced
- panning and zooming enabled
- camera state preserved when the screen rebuilds

#### Phase 1C: Schedule Trip Map UX

In `schedule_trip_screen.dart`, add an embedded map preview for:

- selected pickup marker
- selected destination marker
- route polyline preview
- ETA and distance summary

This screen should become the highest-value mobility UX surface after migration.

#### Phase 1D: Trip Board Map Preview

In `trip_board_screen.dart`, add optional route preview support for selected trips:

- pickup pinned state becomes a real route preview state
- show route summary when both endpoints exist

### Data Model Changes

Refactor:

- `MobilityLocationState.position`
- `MobilityState.userLocation`
- `Trip.latitude` / `Trip.longitude`
- `Trip.destinationLatitude` / `Trip.destinationLongitude`
- `TripPostRequest` coordinate fields

The domain layer should carry raw doubles or `GeoPoint`, not renderer-specific map types.

### Acceptance Criteria

- The home mobility screen no longer uses `flutter_map`.
- The app renders branded Google maps on Android and iOS.
- The home map is interactive and stable across rebuilds.
- Schedule trip flow shows map-based origin/destination confirmation.
- No business logic outside rendering depends on `google_maps_flutter.LatLng`.

## Workstream 2: Places, Geocoding, And Routes

### Goal

Replace current Nominatim search with higher-quality Google place intelligence and route computation.

### Recommended Architecture

Use a backend proxy for Places, Geocoding, and Routes instead of exposing web service credentials directly in the mobile app.

Recommended implementation:

- Create a `maps-gateway` Supabase Edge Function or a small set of focused map-related Edge Functions.
- Enforce Supabase auth, request logging, rate limits, locale handling, and caching there.
- Keep native restricted SDK keys in the app only for map rendering.

This is the safest fit for the current Supabase-first architecture.

### API Usage Plan

- `Places API (New)`: autocomplete and place details
- `Geocoding API`: reverse geocoding and location-only resolution
- `Routes API`: ETA, route geometry, route matrix for future marketplace ranking

### Current File Replacement

Replace the Nominatim implementation inside:

- `lib/features/mobility/services/place_search_service.dart`

with a Google-backed service contract. Keep the service interface, but change the implementation and returned metadata to include:

- `placeId`
- primary label
- secondary label
- coordinates
- optional structured address

### UX Behavior

Move from explicit tap-to-search toward debounced autocomplete:

- start after 3 characters
- debounce 250 to 350 ms
- bias results to current location when available
- preserve manual text entry fallback if no result is selected

Use Google route services for:

- pickup to destination ETA
- distance summary
- future driver-to-rider matching quality

### Cost And Quota Controls

- Use field masks aggressively for Place Details.
- Use session tokens for Autocomplete flows that require Place Details.
- Cache recent place selections and route summaries in app memory and short-lived backend cache.
- Delay requests until the user has typed enough to make useful predictions.

### Backend Deliverables

Edge function responsibilities:

- validate auth
- validate App Check token once enabled
- normalize locale and country bias
- enforce per-user rate limits
- log request counts and latency
- return only fields needed by the client

### Acceptance Criteria

- Place search quality is better than current Nominatim results for target markets.
- Route preview appears in trip creation when both endpoints are resolved.
- Route and place requests do not expose backend web service credentials in the client app.
- Search latency and failure rates are measurable.

## Workstream 3: Messaging, Reliability, And Security

### Products

- Firebase Cloud Messaging
- Firebase Crashlytics
- Firebase Performance Monitoring
- Firebase App Check
- Google Play Integrity
- BigQuery export

### FCM Plan

Add:

- `firebase_messaging`

Implement:

- permission flow
- foreground, background, and terminated-state handling
- topic or segment strategy
- token refresh handling
- notification deep linking

Persist tokens in Supabase using a dedicated table, for example:

- `device_push_tokens`

Suggested columns:

- `id`
- `user_id`
- `fcm_token`
- `platform`
- `locale`
- `notifications_enabled`
- `app_version`
- `last_seen_at`

Send notifications from backend flows for:

- trip reminders
- ticket reminders
- MoMo sync completion
- referral milestones
- mission or quest unlocks
- partner updates

### Crashlytics Plan

Add:

- `firebase_crashlytics`

Capture:

- Flutter framework errors
- async zone errors
- fatal native crashes
- breadcrumbs from key UX actions

### Performance Monitoring Plan

Add:

- `firebase_performance`

Measure:

- cold start
- auth bootstrap
- mobility home load
- place autocomplete latency
- route preview latency
- partner checkout latency
- Supabase RPC / Edge Function latency where possible

### App Check And Play Integrity Plan

Add:

- `firebase_app_check`

Configure:

- Play Integrity provider on Android
- App Attest or DeviceCheck on Apple platforms

Protect:

- map gateway Edge Functions
- wallet issuance Edge Functions
- AI endpoints
- abuse-sensitive referral and ticket endpoints where practical

### BigQuery Export Plan

Enable export for:

- Analytics
- Crashlytics
- Performance Monitoring
- FCM delivery metrics

Use BigQuery to track:

- crash-free users
- route search conversion
- place selection success
- ticket purchase completion
- wallet add rate
- notification open rate

### Acceptance Criteria

- Crash-free and performance dashboards exist before feature rollout broadens.
- Push tokens are stored and refreshed correctly.
- Notification taps route users to the correct screen.
- High-risk mobile endpoints reject clearly invalid traffic after App Check rollout.

## Workstream 4: Google Wallet

### Goal

Turn existing ticket and membership surfaces into real Wallet passes.

### Products

- Google Wallet Event Tickets
- Google Wallet Generic Passes

### Repo Surfaces

Implement Wallet issuance for:

- Rayon event tickets from `ticket_confirmation_screen.dart`
- membership/status card flows related to `rs_membership_card.dart`

### Recommended Backend Design

Create backend wallet issuance functions that:

- create or update pass classes
- create pass objects for the signed-in user
- return signed `Add to Google Wallet` links
- persist issuance state in Supabase

Recommended Supabase additions:

- `wallet_passes` table
- `wallet_pass_events` table for issuance/update tracking

### UX Enhancements

- actual Add to Wallet flow from ticket confirmation
- app linking from pass back into the app
- wallet update notifications when supported fields change
- ticket reminders handled by Wallet where available

### Acceptance Criteria

- `Add to Wallet` button opens a working pass save flow.
- Ticket objects can be updated after issuance.
- Membership cards can be represented as generic passes where product rules allow.

## Workstream 5: Experimentation And Optimization

### Products

- Firebase Remote Config
- Firebase A/B Testing
- Remote Config Personalization
- Firebase Analytics audiences and user properties
- Cloud Translation API Advanced
- Firebase AI Logic, selectively
- Google Play In-App Updates
- Google Play In-App Review

### Remote Config Expansion

Promote Remote Config from simple flags to a real release-control system.

Initial parameters to define:

- onboarding gate behavior
- profile completion prompts
- place autocomplete debounce timing
- map default zoom
- trip search radius
- referral incentive copy
- ticket promo banners
- quest surfacing rules
- country-specific partner modules

### Analytics Plan

Standardize events around:

- `mobility_map_opened`
- `place_autocomplete_requested`
- `place_selected`
- `route_preview_loaded`
- `trip_post_started`
- `trip_post_completed`
- `wallet_add_started`
- `wallet_add_completed`
- `notification_opened`

Add user properties where useful:

- country
- primary_language
- is_driver
- notification_opt_in
- wallet_user

### Translation Plan

Use Cloud Translation only for dynamic content that is not compiled into app localization files:

- partner descriptions
- campaign copy
- selected support or AI-generated responses

Do not replace the existing ARB localization system for core product UI.

### AI Plan

Keep sensitive parsing and financial interpretation server-side.

Use Firebase AI Logic only for client-facing features such as:

- support assistant
- trip help suggestions
- ticketing help
- onboarding explainer experiences

Gate all AI surfaces behind Remote Config and App Check.

### Play Core UX

Implement:

- in-app review after strong success moments
- in-app updates for required app upgrades

### Acceptance Criteria

- Feature releases can be rolled out gradually and reverted without a store release.
- Growth experiments can be targeted by cohort and measured.
- Dynamic content can be translated without shipping a new binary.

## Rollout Sequence

### Phase 0: Foundation

Estimated duration: 1 week

- finalize Google/Firebase project setup
- generate Firebase config for all mobile platforms
- add env and secrets scaffolding
- create map IDs and API restrictions

### Phase 1: Full Maps UI Migration

Estimated duration: 2 to 3 weeks

- introduce `GeoPoint`
- add `google_maps_flutter`
- replace mobility home map
- add interactivity, marker taps, and recenter
- add schedule-trip map preview

### Phase 2: Places, Geocoding, Routes

Estimated duration: 1.5 to 2 weeks

- build map gateway Edge Functions
- replace Nominatim search
- add route preview and ETA
- instrument latency and success

### Phase 3: Reliability And Messaging

Estimated duration: 1.5 to 2 weeks

- add FCM
- add Crashlytics
- add Performance Monitoring
- add App Check and Play Integrity
- enable BigQuery export

### Phase 4: Wallet

Estimated duration: 1.5 weeks

- implement ticket pass issuance
- implement membership generic passes
- wire production Add to Wallet CTAs

### Phase 5: Optimization Layer

Estimated duration: 1.5 to 2 weeks

- expand Remote Config
- add A/B testing and personalization
- add translation for dynamic content
- add in-app review and updates
- evaluate selective AI features

## First Execution Backlog

These are the first concrete tasks to execute in code and cloud:

1. Run `flutterfire configure` and generate production-ready Firebase config for Android and iOS.
2. Move Firebase initialization into `main.dart` startup flow.
3. Add `google_maps_flutter` and begin removing `flutter_map` and `latlong2`.
4. Introduce `GeoPoint` and refactor mobility location state off vendor-specific map types.
5. Add Android manifest metadata and iOS startup key provisioning for Google Maps.
6. Replace the map renderer in `mobility_home_screen.dart` with an interactive Google map.
7. Create the backend map gateway for autocomplete, place details, reverse geocoding, and routes.
8. Replace the Nominatim-backed `PlaceSearchService` implementation.
9. Add route preview to `schedule_trip_screen.dart`.
10. Add `firebase_messaging`, `firebase_crashlytics`, `firebase_performance`, and `firebase_app_check`.

## Risks And Mitigations

- Billing drift from Maps and Places:
  Use field masks, session tokens, quotas, alerts, and backend caching.

- Credential exposure:
  Keep web service credentials out of the mobile client and proxy through backend functions.

- Migration churn from `LatLng` type replacement:
  Introduce `GeoPoint` first before replacing the renderer.

- UX regressions during map migration:
  Roll out with Remote Config and keep a feature flag for the new mobility map until parity is confirmed.

- iOS delivery gaps for push:
  Upload APNs key before testing FCM on Apple devices.

## Explicit Non-Goals

- Replatforming Supabase product data into Firestore
- Implementing Firebase Dynamic Links
- Introducing Google Pay or gateway-style card processing

## Reference Docs

- Google Maps for Flutter: https://developers.google.com/maps/flutter-package/config
- Map IDs and cloud styling: https://developers.google.com/maps/documentation/android-sdk/map-ids/mapid-over
- Places API (New): https://developers.google.com/maps/documentation/places/web-service
- Geocoding API: https://developers.google.com/maps/documentation/geocoding/overview
- Routes API: https://developers.google.com/maps/documentation/routes
- Google Wallet: https://developers.google.com/wallet
- Play Integrity: https://developer.android.com/google/play/integrity/overview
- Firebase Cloud Messaging for Flutter: https://firebase.google.com/docs/cloud-messaging/flutter/get-started
- Firebase Crashlytics for Flutter: https://firebase.google.com/docs/crashlytics/flutter/get-started
- Firebase Performance Monitoring for Flutter: https://firebase.google.com/docs/perf-mon/flutter/get-started
- Firebase App Check for Flutter: https://firebase.google.com/docs/app-check/flutter/default-providers
- Remote Config rollouts: https://firebase.google.com/docs/remote-config/rollouts
- Remote Config personalization: https://firebase.google.com/docs/remote-config/personalization
- BigQuery export: https://firebase.google.com/docs/projects/bigquery-export
