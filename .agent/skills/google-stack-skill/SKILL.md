---
name: google-stack-skill
description: >
  Implement, extend, and optimize Google APIs, SDKs, Firebase services, and
  Gemini AI tools across the COOL super-app. Covers Maps, Places, Routes,
  Wallet, FCM, Crashlytics, Performance, App Check, Remote Config, Analytics,
  Gemini AI, Cloud Translation, BigQuery, and Play Core. Use when any Google
  service integration is needed — new or existing.
---

# Google Stack Skill

Use this skill when implementing, debugging, extending, or optimizing any
Google platform integration in COOL — including Firebase, Google Maps Platform,
Google Wallet, Gemini AI, Cloud Translation, BigQuery, and Play Core.

> **Repo**: `/Volumes/PRO-G40/COOL`
> **Stack**: Flutter 3.38+ · Supabase (Postgres + Edge Fns) · Firebase · Google Cloud
> **Architecture rule**: Google is the mobile services + AI + mapping + wallet layer around Supabase (system of record). Never duplicate Supabase product data into Firestore.

---

## Selective Reading Rule

Read **only** the sections relevant to the current task.

| Section | Read when |
| --- | --- |
| §1 Architecture | First-time orientation, integration design decisions |
| §2 Implementation Status | Before any Google integration work — know what exists |
| §3 Firebase Foundation | Firebase init, config, env, multi-flavor |
| §4 Google Maps | Map rendering, camera, markers, styling |
| §5 Places + Geocoding + Routes | Search, autocomplete, routing, maps-gateway |
| §6 FCM | Push notifications, tokens, topics, deep-link routing |
| §7 Crashlytics | Crash reporting, breadcrumbs, user identity |
| §8 Performance Monitoring | Custom traces, HTTP monitoring |
| §9 App Check | Attestation, Play Integrity, endpoint protection |
| §10 Remote Config + Feature Flags | Kill switches, staged rollouts, A/B testing |
| §11 Analytics | Events, user properties, audience targeting |
| §12 Google Wallet | Ticket passes, membership passes, issuance flow |
| §13 Gemini AI | SMS parsing, AI-powered features, prompt design |
| §14 Cloud Translation | Dynamic content translation |
| §15 BigQuery | Analytics export, data warehouse |
| §16 Play Core | In-app review, in-app updates |
| §17 Cost + Quota Controls | Billing, field masks, caching, rate limits |
| §18 Secrets + Credentials | API key management, env config |
| §19 Anti-Patterns | What not to do |
| §20 Implementation Gaps | What's not yet built |
| §21 Quality Gate | Checklist for Google integration work |

---

## 1. Architecture

### Split of Responsibility

| Layer | Owns | Does NOT own |
| --- | --- | --- |
| **Supabase** | Auth session, profile data, trips, groups, partners, RS data, engagement state, wallet issuance records | Analytics, crash reports, performance traces, push transport, map rendering |
| **Firebase** | Analytics, Crashlytics, Performance, FCM transport, App Check, Remote Config | Product data, auth tokens, user profiles |
| **Google Cloud** | Maps SDK, Places API, Geocoding, Routes API, Wallet API, Translation API, BigQuery | Application backend logic |
| **Gemini AI** | SMS parsing (server-side), potential client-side AI features | Financial decisions, auth logic |

### Key Principle

> Google services wrap around Supabase — never replace it. Firebase is for observability, experimentation, and transport. Google Cloud is for maps, wallet, AI, and translation.

### Credential Architecture

| Credential | Scope | Storage |
| --- | --- | --- |
| Android Maps SDK key | Map rendering only | `--dart-define` → `AndroidManifest.xml` |
| iOS Maps SDK key | Map rendering only | `--dart-define` → `AppDelegate.swift` |
| Android/iOS Map IDs | Branded map styling | `--dart-define` |
| Server-side Maps API key | Places, Geocoding, Routes | Supabase Edge Function secrets |
| Wallet service account | Pass class/object CRUD, JWT signing | Supabase Edge Function secrets |
| Gemini API key | AI SMS parsing, maps-gateway fallback | Supabase Edge Function secrets |
| Firebase config | All Firebase services | `firebase_options.dart` (generated) |

---

## 2. Implementation Status

### ✅ Fully Implemented

| Service | Status | Key Files |
| --- | --- | --- |
| **Firebase Core** | Multi-flavor bootstrap in main startup | `firebase_bootstrap_service.dart`, `firebase_options.dart` |
| **Firebase Analytics** | Package present, events via `engagement_tracker.dart` | `pubspec.yaml` (firebase_analytics) |
| **Firebase Remote Config** | 20+ feature flags, kill switches, staged rollouts | `feature_flags_service.dart`, `engagement_feature_flags.dart` |
| **Firebase Cloud Messaging** | 722-line service: token lifecycle, topics, deep-link routing, foreground banner | `fcm_service.dart` |
| **Firebase Crashlytics** | User identity, breadcrumbs, non-fatal + fatal errors | `crashlytics_service.dart` |
| **Firebase Performance** | Custom traces, async tracing wrapper | `performance_service.dart`, `performance_dio_interceptor.dart` |
| **Firebase App Check** | Play Integrity (Android), App Attest (iOS), debug provider | `app_check_service.dart` |
| **Google Maps Flutter** | Integrated in mobility screens (replaced `flutter_map`) | `pubspec.yaml` (google_maps_flutter) |
| **Google Maps Map IDs** | Android + iOS map ID env vars | `env_config.dart` |
| **Maps Gateway** | Edge fn proxying Places (New), Geocoding, Routes | `supabase/functions/maps-gateway/index.ts` (14KB) |
| **Google Wallet (Event Tickets)** | RS ticket → Wallet pass with JWT signing, class/object CRUD | `supabase/functions/wallet-issuer/index.ts` (795 lines) |
| **Gemini AI (SMS Parsing)** | Gemini 2.5 Flash for M-Money SMS parsing, OpenAI fallback | `supabase/functions/parse-momo-sms/ai_parser.ts` |

### ⚠️ Partially Implemented

| Service | Current State | Gap |
| --- | --- | --- |
| **Google Maps (Mobility UX)** | Map renders with markers | Route polyline preview in schedule_trip not verified |
| **Analytics Events** | Engagement tracker exists | BigQuery export not enabled |
| **Remote Config** | Feature flags only | A/B Testing and Personalization not configured |
| **FCM** | Full service | Notification rich media and action buttons not implemented |

### ❌ Not Yet Implemented

| Service | Priority | Rationale |
| --- | --- | --- |
| **Cloud Translation API** | Medium | Dynamic partner/campaign content translation |
| **BigQuery Export** | Medium | Analytics + crash + FCM data warehouse |
| **In-App Review** | Low | Post-success engagement prompt |
| **In-App Updates** | Low | Forced update for critical releases |
| **Firebase AI Logic (Client)** | Low | Support assistant, trip help, ticketing help |
| **Wallet (Membership Passes)** | Medium | RS fan membership as generic wallet pass |
| **A/B Testing** | Medium | Onboarding, mobility, partner conversion experiments |
| **Remote Config Personalization** | Low | ML-optimized parameter values |

---

## 3. Firebase Foundation

### Bootstrap Flow

Source: `lib/core/services/firebase_bootstrap_service.dart`

```dart
// Always called in main.dart startup
await FirebaseBootstrapService.ensureInitialized();
// Then: CrashlyticsService, PerformanceService, AppCheckService, FcmService
```

- Uses `DefaultFirebaseOptions.currentPlatformForFlavor(EnvConfig.flavor)` for multi-flavor
- `firebase_options.dart` generated via `flutterfire configure`
- All Firebase services gracefully degrade if Firebase init fails

### Service Init Order

```
1. Firebase.initializeApp()
2. CrashlyticsService.initialize()  — captures framework errors
3. PerformanceService.initialize()  — starts perf collection
4. AppCheckService.initialize()     — activates attestation
5. FcmService.initialize()          — token + permission + topics
6. FeatureFlagsService.initialize() — Remote Config fetch
```

### EnvConfig Keys (Flutter --dart-define)

Source: `lib/core/config/env_config.dart`

| Key | Purpose |
| --- | --- |
| `SUPABASE_URL` | Supabase project URL (critical) |
| `SUPABASE_ANON_KEY` | Supabase anonymous key (critical) |
| `GOOGLE_MAPS_ANDROID_API_KEY` | Android Maps SDK key |
| `GOOGLE_MAPS_IOS_API_KEY` | iOS Maps SDK key |
| `GOOGLE_MAPS_ANDROID_MAP_ID` | Android branded map style |
| `GOOGLE_MAPS_IOS_MAP_ID` | iOS branded map style |
| `FLAVOR` | `staging` or `production` |

### Backend Secrets (Supabase Edge Functions)

Source: `supabase/functions/.env.example`

| Key | Purpose |
| --- | --- |
| `GOOGLE_MAPS_SERVER_API_KEY` | Places, Geocoding, Routes proxy |
| `GEMINI_API_KEY` | Gemini AI SMS parsing + maps-gateway fallback |
| `GEMINI_SMS_PARSE_MODEL` | e.g. `gemini-3.1-pro` |
| `GOOGLE_WALLET_ISSUER_ID` | Wallet issuer identity |
| `GOOGLE_WALLET_ISSUER_NAME` | Display name on passes |
| `GOOGLE_WALLET_SERVICE_ACCOUNT_JSON` | SA credentials for pass issuance |
| `GOOGLE_WALLET_ALLOWED_ORIGINS` | Save URL origin allowlist |
| `COOL_PUBLIC_APP_BASE_URL` | App base URL for wallet links |
| `TICKET_QR_HMAC_SECRET` | QR code signing for tickets |

---

## 4. Google Maps

### Current Implementation

- **Package**: `google_maps_flutter: ^2.15.0`
- **Map rendering**: Mobility home screen with driver markers
- **Map IDs**: Platform-specific via `EnvConfig.googleMapsAndroidMapId` / `googleMapsIosMapId`
- **Dark styling**: Via Cloud-based Map Styling (map IDs)
- **Former stack**: `flutter_map` + `latlong2` fully removed

### Domain Model

- `lib/core/models/geo_point.dart` — app-owned coordinate model (not `google_maps_flutter.LatLng`)
- All trip/location models use raw doubles or `GeoPoint`, not renderer-specific types

### Map Usage Points

| Screen | Map Usage |
| --- | --- |
| `mobility_home_screen.dart` | Full interactive map with driver markers, recenter, zoom |
| `schedule_trip_screen.dart` | Route preview: pickup/destination markers, polyline |
| `trip_board_screen.dart` | Optional route preview for selected trips |

### Implementation Rules

- Map surface gracefully hides if API key is missing (via `EnvConfig.hasEmbeddedGoogleMapsSupport`)
- Never expose `google_maps_flutter.LatLng` in domain models — use `GeoPoint`
- Disable tilt/rotate unless value-adding
- Camera state: preserve across rebuilds
- Map IDs required for branded dark styling — without them, default Google styling applies

### Cost Control

- Use Cloud-based Map Styling (not legacy JSON styling)
- Minimize `onCameraMove` callbacks (debounce)
- Don't re-create markers unnecessarily — diff marker sets

---

## 5. Places + Geocoding + Routes

### Backend Proxy: maps-gateway

Source: `supabase/functions/maps-gateway/index.ts` (14KB)

The gateway proxies all Places/Geocoding/Routes requests through Supabase Edge Functions:

| Endpoint | Google API | Purpose |
| --- | --- | --- |
| `autocomplete` | Places API (New) | Debounced text search with location bias |
| `place-details` | Places API (New) | Resolve place ID to coordinates |
| `reverse-geocode` | Geocoding API | GPS coordinates → address |
| `compute-routes` | Routes API | ETA, distance, polyline |

### API Key Resolution

Maps-gateway uses `GOOGLE_MAPS_SERVER_API_KEY` with `GEMINI_API_KEY` as fallback — both are valid Google Cloud API keys.

### Cost Controls

- **Field masks**: Only request needed fields from Places API responses
- **Session tokens**: For autocomplete → place details flows
- **Location bias**: Bias results to user's current location
- **Debouncing**: 250-350ms client-side, no server-side duplicate requests
- **Caching**: Short-lived backend cache for recent results

### Client Integration

- Client calls Edge Function (authenticated + App Check token)
- Gateway validates auth, normalizes locale, enforces rate limits
- Client receives only needed fields — no raw Google responses

### Implementation Rules

- **Never expose `GOOGLE_MAPS_SERVER_API_KEY` in the mobile app**
- All Places/Geocoding/Routes calls go through `maps-gateway`
- Map rendering uses separate restricted SDK keys
- Log request counts and latency for quota monitoring

---

## 6. Firebase Cloud Messaging (FCM)

### Architecture

Source: `lib/core/services/fcm_service.dart` (722 lines)

**Layered abstractions**:
- `FcmMessagingClient` (interface) → `FirebaseMessagingClient` (production)
- `FcmPreferenceStore` (interface) → `HiveFcmPreferenceStore` (Hive-backed)
- `FcmTokenRepository` (interface) → `SupabaseFcmTokenRepository` (Supabase)

### Token Lifecycle

```
1. FcmService.initialize(userId)
2. Request permission (if not determined)
3. Get FCM token → upsert to Supabase `user_fcm_tokens`
4. Listen for token refresh → auto re-upsert
5. On logout: clearSession → delete token from Supabase + FCM
6. On disable: delete token, unsubscribe topics
```

### Topic Strategy

- Country-based: `country_RW`, `country_CD`, `country_KE`, `country_BJ`
- Auto-subscribe on enable, auto-unsubscribe on country change or disable

### Message Handling

| State | Handler | Behavior |
| --- | --- | --- |
| **Foreground** | `_handleForegroundMessage` | MaterialBanner with title/body + "VIEW" action |
| **Background** | `firebaseMessagingBackgroundHandler` | System notification |
| **Terminated** | `_consumeInitialMessage` | Navigate to route from `data.route` |
| **Tap** | `_handleNotificationTap` | Deep-link routing via `DeepLinkConfig.routeForUri` |

### FCM Deep-Link Routing

Notification `data.route` supports:
- Plain route paths: `/groups/123`
- Full URIs: `https://cool.app/groups/123` or `cool://groups/123`
- Shell routes replace current tab; sub-routes push onto stack

### Notification Use Cases

| Event | Trigger Source |
| --- | --- |
| Trip reminders | Supabase trigger / cron |
| Ticket reminders | Match time approaching |
| MoMo sync completion | `parse-momo-sms` edge fn |
| Referral milestones | Engagement engine |
| Mission/quest unlocks | Engagement engine |
| Partner updates | Admin broadcast |

---

## 7. Crashlytics

Source: `lib/core/services/crashlytics_service.dart` (72 lines)

### Capabilities

- User identity correlation (`identifyUser` / `clearUser`)
- Non-fatal error recording with stack traces
- Custom key-value enrichment (country, feature, screen)
- Breadcrumb logging
- Auto-disabled in debug mode
- Graceful degradation if Firebase unavailable

### Wiring Points

```dart
// In main.dart zone:
FlutterError.onError = (details) => crashlytics.recordError(
  details.exception, stackTrace: details.stack, fatal: true);

// In runZonedGuarded:
crashlytics.recordError(error, stackTrace: stack);
```

### Best Practices

- Always call `identifyUser` after auth success
- Call `clearUser` on logout
- Add breadcrumbs at key flow transitions (MoMo launch, trip request, ticket purchase)
- Set custom keys: `screen`, `country`, `feature`, `provider`

---

## 8. Performance Monitoring

Source: `lib/core/services/performance_service.dart` (103 lines)

### Custom Traces

Predefined trace names:
- `auth_cold_start`
- `momo_ussd_to_confirmation`
- `mobility_search`
- `ticket_purchase`
- `group_contribution`

### HTTP Instrumentation

Source: `lib/core/services/performance_dio_interceptor.dart` (3KB)

Attaches to Dio as an interceptor for automatic HTTP performance traces on all Supabase API calls.

### Usage Pattern

```dart
// Simple named trace
performanceService.startTrace('mobility_search');
// ... do work ...
await performanceService.stopTrace('mobility_search', attributes: {'country': 'RW'});

// Async convenience wrapper
final result = await performanceService.traceAsync('ticket_purchase', () async {
  return await purchaseTicket();
});
```

---

## 9. App Check

Source: `lib/core/services/app_check_service.dart` (51 lines)

### Provider Strategy

| Platform | Release | Debug |
| --- | --- | --- |
| Android | `AndroidPlayIntegrityProvider` | `AndroidDebugProvider` |
| iOS | `AppleAppAttestProvider` | `AppleDebugProvider` |

### Protected Endpoints

App Check tokens should be forwarded to:
- `maps-gateway` Edge Function
- `wallet-issuer` Edge Function
- `parse-momo-sms` Edge Function (AI endpoints)
- Any future abuse-sensitive endpoints (referral, ticket)

### Token Retrieval

```dart
final token = await AppCheckService.getToken();
// Attach to Edge Function calls as header
```

---

## 10. Remote Config + Feature Flags

Source: `lib/core/services/feature_flags_service.dart` (130 lines)

### Architecture

Three-layer resolution:
1. **Defaults** → Hardcoded in `EngagementFeatureFlags.defaults()`
2. **Remote Config** → Firebase Remote Config (fetched every 4 hours)
3. **App Config overrides** → Supabase `app_config` table (admin-controlled)

App Config overrides win over Remote Config, which wins over defaults.

### Current Feature Flags (20+)

| Flag | Type | Purpose |
| --- | --- | --- |
| `engagement_enabled` | bool | Global engagement system toggle |
| `engagement_share_tracking_enabled` | bool | Share event tracking |
| `engagement_group_captain_enabled` | bool | Group captain feature |
| `engagement_rayon_chapter_enabled` | bool | RS chapter feature |
| `kill_momo_payments` | bool | Kill switch: MoMo payments |
| `kill_credit_features` | bool | Kill switch: Credit module |
| `kill_ticket_purchase` | bool | Kill switch: RS tickets |
| `kill_mobility` | bool | Kill switch: Mobility |
| `feature_momo_stage` | string | `off` / `admin_only` / `beta` / `ga` |
| `feature_momo_allowed_countries` | string | Comma-separated country codes |
| `feature_momo_admin_only` | bool | MoMo admin-only gate |
| `feature_credit_stage` | string | Credit rollout stage |
| `feature_credit_allowed_countries` | string | Credit country filter |
| `feature_mobility_stage` | string | Mobility rollout stage |
| `feature_ticket_purchase_stage` | string | Ticket rollout stage |

### Kill Switch Pattern

Kill switches provide immediate disable capability without app update:
- `kill_*` flags are checked in providers before loading feature UI
- `feature_*_stage` enables staged rollout: `off` → `admin_only` → `beta` → `ga`
- `feature_*_allowed_countries` restricts by country code

### Expansion Opportunities

- **A/B Testing**: Onboarding gate behavior, profile completion prompts
- **Personalization**: ML-optimized parameter values per user segment
- **Experimentation parameters**: Place autocomplete debounce timing, map default zoom, trip search radius, referral incentive copy, quest surfacing rules

---

## 11. Analytics

### Current State

- `firebase_analytics` package present
- `engagement_tracker.dart` (6KB) handles structured events
- User properties tracked: country, language, driver status

### Event Naming Convention

```
{module}_{action}_{result}
```

Examples:
- `mobility_map_opened`
- `place_autocomplete_requested`
- `place_selected`
- `route_preview_loaded`
- `trip_post_started` / `trip_post_completed`
- `wallet_add_started` / `wallet_add_completed`
- `notification_opened`
- `momo_ussd_launched`
- `group_contribution_completed`
- `ticket_purchased`

### User Properties

| Property | Values |
| --- | --- |
| `country` | RW, CD, KE, BJ |
| `primary_language` | en, fr |
| `is_driver` | true / false |
| `notification_opt_in` | true / false |
| `wallet_user` | true / false |

---

## 12. Google Wallet

### Event Ticket Passes (RS Tickets) — ✅ Implemented

Source: `supabase/functions/wallet-issuer/index.ts` (795 lines)

#### Issuance Flow

```
1. User purchases RS match ticket → ticket confirmed in Supabase
2. Client calls wallet-issuer Edge Function with ticketId
3. Edge fn authenticates user via Supabase JWT
4. Loads ticket + match data from Supabase
5. Creates eventTicketClass (per match) if not exists
6. Creates eventTicketObject (per ticket) with:
   - QR barcode (HMAC-signed: COOL-TKT:{ticketId}:{matchId}:{timestamp}:{digest})
   - Match summary, kickoff, venue, seat, competition text modules
   - "Open in Cool" link
7. Signs JWT for save URL (RS256 with service account)
8. Returns saveUrl → client opens in browser
9. Persists to wallet_passes + wallet_pass_events tables
```

#### Service Account Auth

- Uses Google OAuth 2.0 JWT assertion flow
- Service account parsed from `GOOGLE_WALLET_SERVICE_ACCOUNT_JSON`
- Access tokens cached with 1-minute early expiry buffer
- Wallet API calls via `walletobjects.googleapis.com/walletobjects/v1`

#### Ticket QR Code

```
Format: COOL-TKT:{ticketId}:{matchId}:{timestampMs}:{hmacDigest12}
Signing: HMAC-SHA256 with TICKET_QR_HMAC_SECRET
Verified by: rs-scan-ticket Edge Function
```

### Membership Generic Passes — ❌ Not Yet Implemented

**Design plan**: RS fan membership cards as Generic Passes
- Show tier (Blue/Silver/Gold/Platinum)
- Show XP / points balance
- Update on tier progression
- Allow app linking back to fan profile

---

## 13. Gemini AI

### SMS Parsing — ✅ Implemented

Source: `supabase/functions/parse-momo-sms/ai_parser.ts`

#### Architecture

```
Client → Android SMS read → Raw M-Money SMS
  → parse-momo-sms Edge Function
    → Gemini API (generateContent) → Structured JSON
    → OpenAI fallback (if Gemini fails)
  → Normalized transaction record → Supabase
```

#### Provider Resolution

1. Explicit `AI_SMS_PARSE_PROVIDER` env var
2. If `gemini` → use Gemini
3. If `openai` → use OpenAI
4. Default: try Gemini, fallback to OpenAI

#### Model Config

- Default: `gemini-2.5-flash` (configurable via `GEMINI_SMS_PARSE_MODEL`)
- Response format: JSON mode (`response_mime_type: application/json`)
- No response schema (unsupported) — prompt engineering for structure

#### API Key Sharing

`GEMINI_API_KEY` is shared between:
- `parse-momo-sms` (AI SMS parsing)
- `maps-gateway` (as fallback for `GOOGLE_MAPS_SERVER_API_KEY`)

### Client-Side AI — ❌ Not Yet Implemented

**Planned use cases** (gate behind Remote Config + App Check):
- Support assistant / chatbot
- Trip help suggestions
- Ticketing help
- Onboarding explainer experiences

**Rules**:
- Keep sensitive parsing and financial interpretation server-side only
- Client-side AI is for help/support, never for financial decisions
- All AI surfaces must be behind Remote Config kill switches

---

## 14. Cloud Translation API — ❌ Not Yet Implemented

### Planned Scope

Use Cloud Translation API Advanced for **dynamic content only**:
- Partner descriptions (from Supabase)
- Campaign copy
- Admin-authored announcements
- AI-generated support responses

### Do NOT Use For

- Core UI strings (use ARB localization files)
- Static labels, buttons, navigation (compile-time i18n)
- Financial amounts or transaction metadata

### Integration Plan

- Backend-only: Supabase Edge Function or cron job
- Translate at write-time, cache translated content in Supabase
- `GOOGLE_TRANSLATE_PROJECT_ID` env var needed
- Language detection for user-submitted content

---

## 15. BigQuery Export — ❌ Not Yet Implemented

### Planned Exports

| Source | Data |
| --- | --- |
| Firebase Analytics | Event data, user properties |
| Firebase Crashlytics | Crash events |
| Firebase Performance | Trace data |
| FCM | Delivery metrics, open rates |

### Use Cases

- Crash-free user rate tracking
- Route search → trip completion conversion
- Place selection success rate
- Ticket purchase completion rate
- Wallet add rate
- Notification open rate
- Country-level engagement analysis

### Configuration

- Enable in Firebase Console → Project Settings → BigQuery
- Schedule daily export
- No code changes needed in the app

---

## 16. Play Core — ❌ Not Yet Implemented

### In-App Review

- **Package**: `in_app_review` (Flutter)
- **Trigger**: After strong success moments (trip completed, ticket purchased, group contribution)
- **Rules**: Max 1 prompt per 30 days, never on first session, never during errors

### In-App Updates

- **Package**: `in_app_update` (Flutter, Android only)
- **Immediate update**: For critical/security releases
- **Flexible update**: For feature releases with download-in-background

---

## 17. Cost + Quota Controls

### Google Maps Platform

| Control | Implementation |
| --- | --- |
| **Field masks** | Places API requests specify only needed fields |
| **Session tokens** | Autocomplete → Place Details flows use session tokens |
| **Backend caching** | Short-lived cache in maps-gateway for recent results |
| **Client debounce** | 250-350ms on autocomplete input |
| **Min characters** | Start autocomplete after 3 characters |
| **Quota alerts** | Google Cloud Console budget alerts |

### Firebase

| Control | Implementation |
| --- | --- |
| **Remote Config fetch interval** | 4 hours minimum |
| **Crashlytics** | Disabled in debug mode |
| **Performance** | Disabled in debug mode |
| **FCM** | Topic-based (not individual targeting) for broadcasts |

### Gemini AI

| Control | Implementation |
| --- | --- |
| **Rate limiting** | Per-user rate limits in parse-momo-sms |
| **Fallback** | OpenAI fallback if Gemini fails |
| **Model selection** | Configurable via env var (use Flash for cost, Pro for quality) |
| **Auth required** | All AI calls require Supabase auth |

---

## 18. Secrets + Credentials Management

### Client-Side (--dart-define)

- Android/iOS Maps SDK keys: restricted to package/bundle ID
- Map IDs: no access restriction needed (styling only)
- Never include server-side keys in client builds

### Server-Side (Supabase Edge Function Secrets)

- `GOOGLE_MAPS_SERVER_API_KEY`: restricted to Maps APIs
- `GEMINI_API_KEY`: restricted to Generative AI + Maps APIs
- `GOOGLE_WALLET_SERVICE_ACCOUNT_JSON`: full SA credentials
- `TICKET_QR_HMAC_SECRET`: 32+ character random secret

### Key Restrictions

| Key | Restrictions |
| --- | --- |
| Android Maps SDK | Package name + SHA fingerprints |
| iOS Maps SDK | Bundle ID |
| Server Maps key | HTTP referrer or IP restriction, API restriction to Places/Geocoding/Routes |
| Gemini key | API restriction to Generative Language + Maps APIs |

### Rotation Protocol

1. Generate new key in Google Cloud Console
2. Add new key to Supabase secrets
3. Deploy edge functions
4. Verify new key works
5. Delete old key

---

## 19. Anti-Patterns

### Architecture Anti-Patterns
- Exposing server-side API keys in mobile client
- Calling Places/Geocoding/Routes directly from Flutter (bypass maps-gateway)
- Using Firestore alongside Supabase for product data
- Hard-coding API keys in source files
- Using `google_maps_flutter.LatLng` in domain models

### Firebase Anti-Patterns
- Initializing Firebase lazily instead of deterministically at startup
- Not disabling Crashlytics/Performance in debug mode
- Ignoring FCM token refresh events
- Storing FCM tokens without user association
- Using Firebase Auth instead of Supabase Auth

### Cost Anti-Patterns
- Places API calls without field masks
- Autocomplete without debouncing or minimum character threshold
- Re-creating map markers on every rebuild
- Fetching Remote Config on every app foreground
- AI calls without rate limiting

### AI Anti-Patterns
- Running financial logic in Gemini (SMS parsing structure ≠ financial decisions)
- Exposing raw AI responses to users without validation
- Client-side AI without Remote Config kill switch
- Using expensive models (Pro/Ultra) for simple tasks (use Flash)

---

## 20. Implementation Gaps — Priority Backlog

### P0 (High Impact, Low Effort)

| Gap | Effort | Impact |
| --- | --- | --- |
| Enable BigQuery export | Console config only | Data warehouse for all Firebase analytics |
| Verify route polyline preview in schedule_trip | Code verification | Core mobility UX |
| Add FCM rich media / action buttons | ~2 days | Better notification engagement |

### P1 (Medium Impact)

| Gap | Effort | Impact |
| --- | --- | --- |
| RS Membership Generic Wallet Passes | ~3 days | Fan engagement, wallet ecosystem |
| Cloud Translation for partner content | ~3 days | Multi-language dynamic content |
| A/B Testing setup (Firebase Console) | ~1 day | Experiment infrastructure |
| Analytics user properties expansion | ~1 day | Better audience targeting |

### P2 (Future Optimization)

| Gap | Effort | Impact |
| --- | --- | --- |
| In-App Review | ~1 day | Store ratings improvement |
| In-App Updates | ~2 days | Forced update capability |
| Firebase AI Logic (client-side) | ~1 week | Support assistant, trip help |
| Remote Config Personalization | Console config | ML-optimized parameters |
| Route matrix for driver matching | ~3 days | Better mobility ranking |

---

## 21. Quality Gate

Before finalizing any Google integration work:

### Security
- [ ] Server-side API keys never appear in client code
- [ ] API keys restricted to minimum required APIs
- [ ] App Check token forwarded to protected Edge Functions
- [ ] Service account credentials stored only in Edge Function secrets
- [ ] No secrets in source control

### Reliability
- [ ] Firebase initializes deterministically in startup path
- [ ] All Google services gracefully degrade if unavailable
- [ ] FCM token lifecycle handles refresh and session clear
- [ ] Crashlytics captures all uncaught exceptions
- [ ] Performance traces have meaningful names and attributes

### Cost
- [ ] Places API uses field masks
- [ ] Autocomplete uses session tokens and debouncing
- [ ] Remote Config respects minimum fetch interval
- [ ] AI calls have rate limiting
- [ ] Budget alerts configured in Google Cloud Console

### UX
- [ ] Maps hide gracefully if API key missing
- [ ] Map uses branded dark styling via Map ID
- [ ] Notifications route to correct screen on tap
- [ ] Wallet passes show correct ticket/membership data
- [ ] AI features gated behind Remote Config

### Testing
- [ ] FCM service testable via injected interfaces
- [ ] Feature flags testable without network
- [ ] Maps fallback tested (missing key, missing Map ID)
- [ ] Wallet issuance tested with mock service account

---

## Relationship to Other Skills

| Skill | Scope | When to use |
| --- | --- | --- |
| **google-stack-skill** (this) | All Google APIs, SDKs, Firebase, Gemini, Wallet, Maps | Any Google service integration work |
| **design-foundations** | Color tokens, typography, spacing, surfaces, theme architecture | Visual design tokens and theme switching |
| **screen-composition** | Screen budgets, copy limits, simplification, anti-patterns | Screen structure and UI noise cleanup |
| **component-navigation** | Shared widgets, routing, motion, state matrix | Widget API or routing changes |
| **trust-accessibility** | Payment displays, permissions, a11y, localization | Trust UX, accessibility, localization |
| **module-partner-ux** | Per-module UX, partner branding, migration rollout | Module-specific design decisions |
| **flutter-skill** | Engineering quality: testing, CI, performance budgets, security | Code quality, release readiness |

### Reference Document

The original implementation plan that informed this skill:
[google_stack_implementation_plan.md](file:///Volumes/PRO-G40/COOL/docs/google_stack_implementation_plan.md)
