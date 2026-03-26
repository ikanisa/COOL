---
name: Flutter World-Class Engineering Skill
description: >
  Comprehensive 2025/2026 world-class Flutter engineering standards for the COOL app.
  Covers payment correctness, test isolation, CI/release engineering, offline-first
  architecture, adaptive UX, accessibility, performance budgets, experimentation,
  app-size governance, security, observability, and multi-market readiness.
  Benchmarked against BMW, Nubank, Wolt, Google Classroom, Duolingo, Uber, Spotify,
  Grab, Booking.com, Monzo, and Meta engineering practices.
---

# Flutter World-Class Engineering Skill

> **Validated**: March 11, 2026 · Flutter 3.38.9 / Dart 3.10.8
> **Repo**: `/Volumes/PRO-G40/COOL` · Single-app Flutter project (finance + services + partners)
> **Rating**: 3.5/5 — strong product foundation with solid ops backbone, not yet elite execution
> **Audit**: March 11, 2026 — full codebase audit completed, 6 corrections applied (see §3)

---

## Table of Contents

1. [North Star](#1-north-star)
2. [Benchmark Matrix](#2-benchmark-matrix)
3. [Current Repo State](#3-current-repo-state)
4. [Domain 1: Payment & Country Correctness](#4-domain-1-payment--country-correctness)
5. [Domain 2: Test Isolation & Determinism](#5-domain-2-test-isolation--determinism)
6. [Domain 3: CI / Release Engineering](#6-domain-3-ci--release-engineering)
7. [Domain 4: Offline-First Architecture](#7-domain-4-offline-first-architecture)
8. [Domain 5: Adaptive & Responsive UX](#8-domain-5-adaptive--responsive-ux)
9. [Domain 6: Accessibility](#9-domain-6-accessibility)
10. [Domain 7: Performance Budgets](#10-domain-7-performance-budgets)
11. [Domain 8: Experimentation & Remote Config](#11-domain-8-experimentation--remote-config)
12. [Domain 9: App-Size Governance](#12-domain-9-app-size-governance)
13. [Domain 10: Security & Permissions](#13-domain-10-security--permissions)
14. [Domain 11: Observability](#14-domain-11-observability)
15. [Domain 12: Multi-Market Readiness](#15-domain-12-multi-market-readiness)
16. [Phased Execution Plan](#16-phased-execution-plan)
17. [Sources & References](#17-sources--references)

---

## 1. North Star

Transform COOL from a feature-rich Flutter app into a **world-class mobile product** measured by four outcomes:

| Outcome | Target |
|---|---|
| **Trust** | 0 critical payment-validation defects in supported countries |
| **Release confidence** | 100% green on analyze + unit/widget + integration + smoke before merge |
| **Performance** | Crash-free >99.8%, cold start <2s, jank budget <5% slow frames |
| **Multi-market scale** | Staging/prod flavor separation with gated rollout and rollback |

---

## 2. Benchmark Matrix

| Benchmark App | What World-Class Looks Like | Current COOL Evidence | Gap Severity |
|---|---|---|---|
| **BMW** | 96 variant builds with automated build/test/deploy | ✅ `staging`+`production` flavors in `build.gradle.kts:59-71`, CI exists (`ci.yml`, `release.yml`), 7 release scripts — missing beta rings/staged rollout | 🟠 High |
| **Nubank** | Modular ownership, high merge success, dynamic content delivery, safe non-mobile contributions | Broad Riverpod modularization, ✅ `locale_provider.dart` uses abstract `LocaleStore` + DI, test harness exists (9.7KB) — some providers still reach Hive directly | 🟡 Medium |
| **Wolt** | Adaptive UI across device classes, responsive design first-class, simultaneous bi-weekly releases | `SafeArea` used, but portrait-locked in `main.dart:61`, no adaptive-device strategy | 🟠 High |
| **Google Classroom** | Latency/jank/memory/binary-size/accessibility benchmarked before "ready" | `flutter analyze` clean, but no `integration_test/` suite beyond README, sparse accessibility semantics | 🟠 High |
| **Universal Studios** | Low crash rate, materially shorter release cycles | Firebase Crashlytics wired, but no crash-rate budgets or release-cycle tracking | 🟡 Medium |
| **Duolingo** | Android performance for low-end devices, large-scale experimentation, 5000+ screenshot visual QA per release | Firebase Performance exists, but no screenshot diffing, golden tests, or Baseline Profiles | 🟠 High |
| **Uber** | Standardized cross-platform analytics, real-time crash intelligence for canary decisions, network failover engineering | Crashlytics + Performance + FCM + App Check + deep-link tracking all wired — **strongest area** | 🟢 Medium |
| **Spotify** | Mature experimentation platform with exposure tracking, rollout governance, remote config discipline | Remote Config exists, but feature-flag scope is narrow, no experiment tracking or rollout percentages | 🟡 Medium |
| **Grab** | Superapp discipline: app-size containment, quality automation, feature-flag governance, low-bandwidth pragmatism | Some offline/cached paths (`trip_repository.dart`, `momo_service.dart`), but no size budget, no flavor strategy | 🔴 Critical |
| **Booking.com** | User-centric performance measured in production (freeze time, session duration), decoupled from other infra | Firebase Performance wired, but no explicit startup/jank/freeze budgets or release gating on production metrics | 🟠 Medium-High |
| **Monzo** | Release trains, beta rings, feature flags, RC discipline, signed reproducible builds, release ownership | Local release scripts exist, `release.yml` distributes to Firebase App Distribution — partial, missing beta rings/RC discipline | 🔴 Critical |
| **Meta** | Baseline Profiles improving cold start 40%+, on-device ML for latency/privacy/offline | Good security via App Check, some offline logic — no Baseline Profiles or equivalent performance hardening | 🟠 High |

---

## 3. Current Repo State

### Strongest Areas
- **Observability**: Firebase Core, Analytics, Crashlytics, Performance, App Check, Remote Config, FCM all wired (`pubspec.yaml`, `main.dart`, `app.dart`)
- **Deep linking**: `AppLinks` + `DeepLinkConfig` + GoRouter integration (`app.dart:128-231`)
- **Offline resilience**: Trip caching/sync via `trip_repository.dart` and `sync_engine.dart` (315 lines, backoff+staleness), pending MoMo fallback via `momo_service.dart`
- **Error handling**: Branded error widget, `runZonedGuarded`, Crashlytics fatal/non-fatal capture
- **CI/CD**: `ci.yml` (analyze + test on every push/PR), `release.yml` (signed APK + Firebase App Distribution on tag)
- **Release infra**: ✅ Android flavors (staging/production), ✅ ProGuard (58 rules), ✅ signing config, ✅ 7 build/release scripts
- **Test isolation**: ✅ All tests pass (exit 0), ✅ Abstract `LocaleStore` with DI, ✅ 6 integration smoke tests + 9.7KB test harness

### Weakest Areas
- **Accessibility**: Nearly zero — only 2 files use `Semantics()`, 0 use `semanticsLabel`
- **Adaptive UX**: Portrait-locked (`main.dart:62`), no breakpoint system, no tablet/foldable support
- **App-size governance**: No tracking, no budgets, no dependency audit
- **Experimentation**: Only 4 engagement feature flags, no kill-switches, no experiment exposure logging

> [!NOTE]
> **Audit corrections (March 11, 2026)**: The original analysis overstated several gaps. Flavors, CI workflows, locale DI, and test fixes have all been implemented. The rating has been upgraded from 3/5 to 3.5/5. See the full audit report for details.

### Architecture Overview

```
lib/
├── main.dart              # Bootstrap: Firebase, Hive, Supabase, SystemChrome, Crashlytics
├── app.dart               # Root widget: deep links, auth lifecycle, engagement, trip sync
├── core/
│   ├── auth/              # Auth types and helpers
│   ├── config/             # EnvConfig, DeepLinkConfig
│   ├── l10n/               # LocaleProvider (Hive-backed)
│   ├── models/             # EngagementEvent, FeatureFlags, GeoPoint, ReferralAttribution
│   ├── providers/          # Engagement, notification, referral providers
│   ├── repositories/       # Data access layer
│   ├── router/             # GoRouter (app_router.dart, shell_route.dart)
│   ├── services/           # 12 services: AppCheck, Contacts, Crashlytics, Engagement,
│   │                       #   FCM, FeatureFlags, FirebaseBootstrap, Location, MoMo,
│   │                       #   PerformanceDioInterceptor, Performance, WhatsApp
│   ├── status/             # Status enums/types
│   ├── sync/               # SyncEngine, NetworkStatus, SyncStatus
│   ├── theme/              # AppTheme
│   └── utils/              # Utility functions
├── features/
│   ├── auth/               # Authentication screens + providers
│   ├── basket/             # Shopping basket
│   ├── credit/             # Credit/finance features
│   ├── groups/             # Group finance
│   ├── home/               # Home screen
│   ├── momo/               # Mobile money
│   ├── partners/           # Partner ecosystem (Rayon Sports, etc.)
│   └── profile/            # User profile
├── shared/
│   └── widgets/            # Shared UI components
└── l10n/                   # Generated localizations

test/
├── core/                   # Router, config, l10n, utils, sync tests
├── features/               # Auth, credit, momo, partners tests
├── integration_smoke/      # Host-side smoke tests (no emulator needed)
├── models/                 # Model tests
├── providers/              # Provider tests
└── shared/                 # Shared widget tests

integration_test/           # Reserved for device-backed tests (README only)
scripts/                    # 7 release/build scripts
.github/workflows/          # ci.yml + release.yml
```

---

## 4. Domain 1: Payment & Country Correctness

### Why It Matters
This is the **most serious product risk**. The app is payment-driven (MoMo USSD, credit, tickets). Failing phone/country validation means users cannot transact. Monzo, Uber, and Grab treat payment correctness as P0 — never shipped with known payment-path bugs.

### Current State
- `country_catalog.dart` defines country rules including E.164 formatting
- `phone_validator_test.dart` and `country_catalog_test.dart` have 7 reproducible failures
- Cross-country drift exists for Benin and potentially other non-primary markets
- MoMo service has offline fallback in `momo_service.dart:240` but correctness is drifting

### World-Class Standard
| Practice | Reference App | Action |
|---|---|---|
| Every supported country behind deterministic test fixtures | Monzo, Grab | Add parameterized `country_catalog_test.dart` for every country in catalog |
| E.164 normalization tested with real-world edge cases | Uber | Expand `phone_validator_test.dart` with international prefix handling, leading zeros, max-length |
| Payment path has zero-tolerance test policy | Monzo | Any failing payment/phone test blocks merge in CI |
| Country configs are data-driven, not code-driven | BMW (96 variants) | Move country rules to a declarative JSON/YAML catalog, test the catalog exhaustively |

### Implementation Checklist
```
[ ] Fix all 7 failing tests (P0 — do this first)
[ ] Add parameterized tests for every country in country_catalog.dart
[ ] Add edge-case phone numbers: short numbers, emergency, toll-free, leading zeros, max-length
[ ] Add golden file for country catalog snapshot (detect unintentional drift)
[ ] Add CI gate: any test in test/core/config/ or test/features/momo/ failing blocks merge
[ ] Create fixtures file: test/fixtures/country_phone_fixtures.dart
[ ] Ensure MoMo USSD format string is tested per-country
```

---

## 5. Domain 2: Test Isolation & Determinism

### Why It Matters
Nubank explicitly credits testability for their developer scaling. If unit tests depend on Hive, Firebase, or Supabase initialization, they are not unit tests — they are integration tests running without guarantees.

### Current State
- `locale_provider.dart:14` opens Hive directly in constructor path
- `main.dart` initializes Firebase, Supabase, and Hive as hard dependencies before app launch
- `app.dart` triggers engagement, trip sync, deep links, and auth side effects in `initState`
- legacy location-aware providers have engagement/bootstrap side effects that leak into widget tests
- Test files in `test/integration_smoke/` use provider overrides + fake repos (good pattern)

### World-Class Standard
| Practice | Reference App | Action |
|---|---|---|
| Zero global singletons in test paths | Nubank | All services accessed via Riverpod providers, never via `.instance` |
| Explicit dependency injection | Google Classroom | `locale_provider.dart` accepts a `Box` parameter, test provides mock |
| No side-effect constructors | Spotify | Providers that trigger network/storage must `autoDispose` and be overrideable |
| Test harness resets state between runs | Grab | Add `test/helpers/test_bootstrap.dart` for deterministic setup |

### Implementation Checklist
```
[ ] Refactor locale_provider.dart: inject Hive Box via provider parameter, not direct open
[ ] Create test/helpers/test_bootstrap.dart: sets up mocked Hive, Firebase, Supabase
[ ] Audit all providers in lib/core/providers/ for implicit global state
[ ] Ensure every test file can run independently: flutter test test/<file>.dart
[ ] Add CI check: run tests in random order (--test-randomize-ordering-seed=random)
[ ] Remove direct Supabase.instance usage from any provider (use repository abstraction)
[ ] Ensure engagement_tracker.dart and crashlytics_service.dart can be no-op in tests
```

### Pattern: Test Bootstrap Helper

```dart
// test/helpers/test_bootstrap.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

class MockHiveBox extends Mock implements Box<dynamic> {}

/// Creates a ProviderContainer with all infrastructure providers overridden
/// to safe, deterministic test doubles.
ProviderContainer createTestContainer({
  List<Override> overrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      // Override infrastructure providers here
      // localeBoxProvider.overrideWithValue(MockHiveBox()),
      // supabaseClientProvider.overrideWithValue(mockClient),
      ...overrides,
    ],
  );
}
```

---

## 6. Domain 3: CI / Release Engineering

### Why It Matters
BMW builds 96 variants automatically. Monzo has release trains, RC builds, beta rings, and explicit release ownership. Universal Studios measures release cycle time as a KPI. The COOL app has CI (a significant upgrade from the original analysis), but needs flavors, integration tests, and release discipline.

### Current State
- ✅ `.github/workflows/ci.yml` — runs on every push/PR: analyze + test via `release_readiness.sh`
- ✅ `.github/workflows/release.yml` — triggered by `v*` tags: analyze, test, signed APK, Firebase App Distribution
- ✅ `scripts/release_readiness.sh` — flutter analyze, test, integration smoke, deno edge function tests, optional migration push and remote smoke
- ✅ `scripts/build_qa_apk.sh`, `build_staging.sh`, `build_production.sh` — build scripts exist
- ❌ No product flavors (single app ID for staging/production)
- ❌ No integration test suite running on real device/emulator in CI
- ❌ No beta ring / staged rollout / canary process
- ❌ `release.yml` Flutter version hardcoded (`3.38.9`), not read from `.fvmrc`

### World-Class Standard
| Practice | Reference App | Action |
|---|---|---|
| Flavors: separate app IDs, configs, assets per environment | BMW, Monzo | Add `staging` and `production` flavors |
| CI gate: analyze + test + integration smoke + signed build verification | BMW, Grab | Already partially done; add integration test step |
| Release trains: RC → QA → beta → staged production → full | Monzo | Define release cadence and sign-off process |
| Rollback within minutes | Universal Studios, Monzo | Firebase App Distribution + Play Store staged rollout enable this |
| Flutter version from `.fvmrc` in all workflows | — | `release.yml` should read from `.fvmrc` like `ci.yml` does |

### Implementation Checklist
```
[ ] Add Android flavors (staging, production) in android/app/build.gradle.kts
[ ] Add iOS schemes (Staging, Production) in Xcode
[ ] Create flavor-specific env configs: lib/core/config/env_staging.dart, env_production.dart
[ ] Unify Flutter version source: release.yml should read .fvmrc like ci.yml does
[ ] Add integration_test/ device tests running in CI (Firebase Test Lab or emulator action)
[ ] Add release cadence document: docs/RELEASE_PROCESS.md
[ ] Define beta ring: internal → staff → staged production
[ ] Add rollback playbook: docs/ROLLBACK.md
[ ] Tag-based release workflow with CHANGELOG generation
```

### Flavor Configuration Pattern

```kotlin
// android/app/build.gradle.kts
android {
    // ...
    flavorDimensions += "environment"
    productFlavors {
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "COOL Staging")
        }
        create("production") {
            dimension = "environment"
            resValue("string", "app_name", "COOL")
        }
    }
}
```

```bash
# Build commands
flutter build apk --flavor staging --dart-define=ENV=staging
flutter build apk --flavor production --dart-define=ENV=production
```

---

## 7. Domain 4: Offline-First Architecture

### Why It Matters
Grab serves bandwidth-constrained markets and treats low-connectivity resilience as a platform concern. Uber explicitly engineers network failover. The COOL app has offline seeds but no platform-level sync architecture.

### Current State
- ✅ `lib/core/sync/sync_engine.dart` — generic sync engine (8.8KB, substantial)
- ✅ `lib/core/sync/network_status.dart` — connectivity monitoring
- ✅ `lib/core/sync/sync_status.dart` — sync state tracking
- ✅ Trip caching/sync in `trip_repository.dart`
- ✅ Pending MoMo transaction fallback in `momo_service.dart:240`
- ❌ Offline support is feature-local, not all features use the sync engine
- ❌ No conflict resolution policy
- ❌ No staleness rules
- ❌ No user-visible sync status indicator

### World-Class Standard
| Practice | Reference App | Action |
|---|---|---|
| All data goes through sync-aware repositories | Grab, Uber | Repositories wrap sync engine, not raw Supabase |
| User sees sync status | Uber | Add global sync indicator (dot/badge) |
| Conflict resolution is explicit | Grab | Last-write-wins, merge, or user-chooses — document per domain |
| Staleness rules per data type | Booking.com | Profile: 1hr, trips: 5min, credit: 2min, payments: never cache |
| Retry with exponential backoff | Uber | Already likely in sync_engine; verify and standardize |

### Implementation Checklist
```
[ ] Audit all repositories: which use sync_engine, which bypass it
[ ] Define staleness policy per data domain (documented in docs/OFFLINE_POLICY.md)
[ ] Add conflict resolution strategy per domain
[ ] Ensure all write operations queue through sync engine when offline
[ ] Add user-visible sync status widget in shared/widgets/
[ ] Add integration smoke test: start trip while offline → sync when back online
[ ] Add retry/backoff tests for sync_engine.dart
[ ] Document offline UX in docs/OFFLINE_UX.md
```

---

## 8. Domain 5: Adaptive & Responsive UX

### Why It Matters
Wolt builds adaptive UI across device classes as a first-class concern. Google Classroom benchmarks accessibility before migration. The COOL app is portrait-locked, which limits usability on larger phones, foldables, and tablets.

### Current State
- `main.dart:61` — `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])`
- Some `SafeArea` and `LayoutBuilder` usage in screens
- No explicit breakpoint system
- No responsive layout utilities

### World-Class Standard (per Flutter docs: https://docs.flutter.dev/ui/adaptive-responsive)
| Practice | Reference App | Action |
|---|---|---|
| Remove portrait lock unless hard product requirement | Wolt | Allow landscape on tablets/foldables |
| Define breakpoints: compact, medium, expanded | Google Classroom | Use `MediaQuery` + custom breakpoint constants |
| Adaptive layouts for high-value screens | Wolt | Home, services, and partner screens |
| Test on multiple form factors | Duolingo (5000+ screenshots) | Add golden tests at different sizes |

### Implementation Checklist
```
[ ] Decide: is portrait-only a hard product rule? If yes, document why. If no, remove lock.
[ ] Create lib/shared/widgets/responsive_builder.dart with breakpoint system
[ ] Add adaptive layouts for: home, services, partners, profile, credit
[ ] Test layouts at: 360dp (small phone), 412dp (standard), 600dp (small tablet), 840dp (tablet)
[ ] Add golden tests for top-5 screens at compact and expanded breakpoints
[ ] Support landscape for map-heavy screens (partner or location-aware flows)
```

### Breakpoint Pattern

```dart
// lib/shared/widgets/responsive_builder.dart
enum WindowSizeClass { compact, medium, expanded }

WindowSizeClass getWindowSizeClass(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) return WindowSizeClass.compact;
  if (width < 840) return WindowSizeClass.medium;
  return WindowSizeClass.expanded;
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext, WindowSizeClass) builder;
  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return builder(context, getWindowSizeClass(context));
  }
}
```

---

## 9. Domain 6: Accessibility

### Why It Matters
Google Classroom evaluated accessibility before committing to Flutter. Flutter docs treat semantics, screen readers, focus, and text scaling as first-class quality work. This is increasingly a legal requirement in many markets.

### Current State
- Sparse explicit `Semantics` widgets in `lib/`
- No accessibility testing
- No focus order management
- No large-text / dynamic type support verification
- No contrast ratio verification

### World-Class Standard (per Flutter docs: https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)
| Practice | Reference App | Action |
|---|---|---|
| All interactive elements have semantic labels | Google Classroom | Audit every `GestureDetector`, `InkWell`, `IconButton` |
| Focus traversal order is logical | Google Classroom | Test with keyboard navigation |
| Text scales properly up to 200% | Platform requirement | Test with `MediaQuery` text scale override |
| Color contrast meets WCAG 2.1 AA | Platform requirement | Verify dark theme contrast ratios |
| Accessibility testing in CI | Duolingo | Add `flutter test --accessibility-checks` equivalent |

### Implementation Checklist
```
[ ] Audit all interactive widgets for Semantics labels
[ ] Add Semantics.label to every IconButton, custom gesture area, and image
[ ] Test with TalkBack (Android) and VoiceOver (iOS) for top-5 user journeys
[ ] Add focus traversal order to: auth flow, MoMo send, trip booking, ticket purchase
[ ] Verify text scaling at 1.0x, 1.5x, 2.0x — screens must not overflow
[ ] Verify dark theme contrast ratios meet WCAG 2.1 AA (4.5:1 for text)
[ ] Add accessibility smoke test: test/accessibility/ directory
[ ] Consider SemanticsDebugger for development review
```

### Accessibility Test Pattern

```dart
// test/accessibility/semantics_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home screen has proper semantics', (tester) async {
    await tester.pumpWidget(const MyApp());

    // Every button should have a semantic label
    final buttons = find.byType(IconButton);
    for (final button in buttons.evaluate()) {
      final semantics = tester.getSemantics(find.byWidget(button.widget));
      expect(semantics.label, isNotEmpty,
        reason: 'IconButton missing semantic label');
    }
  });
}
```

---

## 10. Domain 7: Performance Budgets

### Why It Matters
Booking.com measures freeze time in production. Meta improved Android cold start 40% with Baseline Profiles. Duolingo ties app-open conversion directly to startup latency on entry-level devices. Performance is not polish — it is product health.

### Current State
- ✅ Firebase Performance wired (`main.dart:33-40`, `app.dart:146-153`)
- ✅ Cold start trace exists (`main.dart:34-40`)
- ✅ Performance Dio interceptor for HTTP metrics (`performance_dio_interceptor.dart`)
- ❌ No defined budgets for startup, jank, crash rate, ANR
- ❌ No Baseline Profiles
- ❌ No release-mode profiling discipline
- ❌ No frame drop monitoring beyond Firebase defaults

### World-Class Standard
| Metric | Budget | Reference |
|---|---|---|
| Cold start (time-to-interactive) | <2000ms | Android vitals, Duolingo, Meta |
| Warm start | <500ms | Android vitals |
| Slow frames (>16ms) | <5% of total frames | Google Classroom |
| Frozen frames (>700ms) | <0.1% of total frames | Booking.com |
| Crash-free sessions | >99.8% | Universal Studios, Uber |
| ANR rate | <0.5% | Android vitals |
| App size (APK) | Track + budget per release | Grab |

### Implementation Checklist
```
[ ] Document performance budgets in docs/PERFORMANCE_BUDGETS.md
[ ] Add Baseline Profiles for Android (android/app/src/main/baseline-prof.txt)
[ ] Profile top-5 user journeys in release mode on a low-end device
[ ] Add custom traces for: auth flow, MoMo send, trip creation, ticket purchase, home load
[ ] Set up Firebase Performance alerting for budget violations
[ ] Add frame drop monitoring widget for debug mode
[ ] Run flutter build apk --analyze-size and track per release
[ ] Test on low-RAM device (2-3GB) to catch memory pressure issues
[ ] Add startup trace to docs with baseline measurement
```

### Baseline Profile Setup

```
// android/app/src/main/baseline-prof.txt
// Generated by running instrumented tests that exercise critical paths.
// Rebuild with: flutter build apk --release && extract profiles

// Core framework classes for faster startup
Lcom/google/firebase/**;
Lio/flutter/**;
Landroidx/**;
```

---

## 11. Domain 8: Experimentation & Remote Config

### Why It Matters
Spotify built a full experimentation platform with exposure tracking. Duolingo runs continuous A/B experiments tied to retention. The COOL app has Remote Config wired but uses it narrowly.

### Current State
- ✅ `firebase_remote_config` in `pubspec.yaml`
- ✅ `feature_flags_service.dart` — reads remote config values
- ✅ `engagement_feature_flags.dart` — feature flag model
- ❌ No experiment tracking (which users saw which variant)
- ❌ No rollout percentages
- ❌ No kill-switch discipline for high-risk features
- ❌ No country-specific overrides

### World-Class Standard
| Practice | Reference App | Action |
|---|---|---|
| Feature flags have owners and expiry dates | Spotify | Add metadata to flag definitions |
| Kill-switch for payment, credit, and high-risk features | Monzo | Add `kill_momo`, `kill_credit` flags |
| Experiment exposure logged to analytics | Spotify, Duolingo | Log which variant user sees + when |
| Country-specific config overrides | BMW (96 variants) | Support `flag_RW`, `flag_BJ` prefixes |
| Gradual rollout (1% → 10% → 50% → 100%) | Spotify | Use Remote Config conditions |

### Implementation Checklist
```
[ ] Add kill-switch flags: kill_momo_payments, kill_credit_features, kill_ticket_purchase
[ ] Add experiment exposure logging to engagement_tracker.dart
[ ] Create docs/FEATURE_FLAGS.md: flag name, owner, purpose, expiry, rollback steps
[ ] Add country-specific config support to feature_flags_service.dart
[ ] Add gradual rollout support using Remote Config conditions
[ ] Test kill-switch behavior: when flag is on, feature is fully disabled with user-friendly message
[ ] Add flag cleanup process: flags older than 90 days should be resolved or documented
```

---

## 12. Domain 9: App-Size Governance

### Why It Matters
Grab's "Project Bonsai" explicitly governed app size through measurement, reduction, and containment. For a superapp-like product serving bandwidth-constrained markets (Rwanda, Benin), APK size directly impacts install conversion.

### Current State
- No visible app-size tracking
- Multiple large dependencies: `google_maps_flutter`, `syncfusion_flutter_xlsio`, `mobile_scanner`, `flutter_nfc_kit`
- Assets include images, icons, and fonts directories
- Some dependencies may not be needed on every screen (tree-shaking helps but doesn't eliminate unused packages)

### World-Class Standard
| Practice | Reference App | Action |
|---|---|---|
| Track APK size per release | Grab | Add `flutter build apk --analyze-size` to CI |
| Set size budget and alert on regression | Grab | e.g., "APK must stay under 40MB" |
| Deferred components for rarely-used features | Grab | Consider for heavy features like NFC, QR scanner |
| Asset optimization | Duolingo | Compress images, use WebP, minimize font subsets |
| Dependency audit | Grab | Review each dependency: is it needed? Is there a lighter alternative? |

### Implementation Checklist
```
[ ] Run flutter build apk --analyze-size and record baseline
[ ] Set APK size budget in docs/PERFORMANCE_BUDGETS.md
[ ] Add size check to CI: compare against budget, warn if >5% growth
[ ] Audit dependencies: can syncfusion_flutter_xlsio be lazy-loaded?
[ ] Optimize images: convert PNGs to WebP where possible
[ ] Audit font assets: are all fonts and all weights needed?
[ ] Consider deferred components for NFC and QR scanner features
```

---

## 13. Domain 10: Security & Permissions

### Why It Matters
The app handles payments (MoMo), credit, personal contacts, location, and camera access. Monzo treats permission governance as a release criterion. Meta runs on-device ML to reduce data exposure.

### Current State
- ✅ Firebase App Check for API attestation (`app_check_service.dart`)
- ✅ `permission_handler` for runtime permissions
- ✅ `runZonedGuarded` for uncaught error handling
- ❌ No sensitive-content protection for finance/credit screens
- ❌ No permission audit path documented
- ❌ No screenshot protection for payment screens
- ❌ Contacts access scope may be broader than needed

### World-Class Standard
| Practice | Reference App | Action |
|---|---|---|
| Sensitive screens blocked from screenshots/screen recording | Monzo | Add `FLAG_SECURE` for payment and credit screens |
| Permission requests are contextual, not upfront | Google Classroom | Request location only in user-initiated map flows, camera only on QR |
| Permission denial is gracefully handled | Uber | Every permission has a denial UX with explanation |
| Data minimization | Meta | Only access contacts when user explicitly triggers social feature |
| Security review per release | Monzo | Add to release checklist |

### Implementation Checklist
```
[ ] Add FLAG_SECURE to MoMo payment screen and credit detail screen (Android)
[ ] Audit permission_handler usage: which screens request which permissions
[ ] Ensure every permission request has a pre-prompt explanation
[ ] Ensure every permission denial has graceful degradation UX
[ ] Document permissions in docs/PERMISSIONS.md: which permission, which feature, why
[ ] Add contacts access scope review: only read, minimal fields
[ ] Add security checklist to release process
```

---

## 14. Domain 11: Observability

### Why It Matters
This is the repo's **strongest area**. Uber standardized mobile analytics across platforms. The COOL app already has Firebase Analytics, Crashlytics, Performance, App Check, Remote Config, FCM, and deep-link tracking.

### Current State
- ✅ Firebase Core, Analytics, Crashlytics, Performance, App Check, Remote Config, FCM
- ✅ Cold start trace (`main.dart:34`)
- ✅ Crashlytics user identification (`app.dart:72`)
- ✅ Engagement tracker with structured events (`engagement_tracker.dart`)
- ✅ Performance Dio interceptor for HTTP metrics (`performance_dio_interceptor.dart`)
- ✅ Crashlytics breadcrumbs in critical flows

### Upgrade Path to Elite
```
[ ] Add structured event taxonomy: docs/ANALYTICS_TAXONOMY.md
[ ] Standardize event naming: feature_action_result (e.g., momo_send_success)
[ ] Add funnel tracking: auth → profile → first_order → repeat_order
[ ] Add session replay or at least session-level funnel analysis
[ ] Add custom dimensions: country, device_tier, network_type, flavor
[ ] Set up Crashlytics alerting rules for crash-rate spikes
[ ] Add weekly observability review ritual
```

---

## 15. Domain 12: Multi-Market Readiness

### Why It Matters
BMW serves 45+ countries with 96 variant builds. The COOL app operates across multiple African countries (Rwanda, Benin, etc.) with different payment systems, phone formats, and regulatory requirements.

### Current State
- `country_catalog.dart` defines country-specific rules
- English + French localizations (`l10n.yaml`, `lib/l10n/`)
- Country-specific MoMo USSD codes
- ❌ Country configs are code-driven, not data-driven
- ❌ No dynamic content delivery for copy changes without app store release
- ❌ Country coverage is drifting (Benin test failures)

### Implementation Checklist
```
[ ] Move country catalog to declarative format (JSON or YAML)
[ ] Add country-level Remote Config overrides
[ ] Add per-country integration tests
[ ] Support dynamic copy/content updates via Remote Config for non-code strings
[ ] Add country-specific feature flags: enable/disable features per market
[ ] Track country coverage in docs/COUNTRY_COVERAGE.md
[ ] Add country-specific MoMo format validation tests
[ ] Consider multi-market build variants if app IDs need to differ per market
```

---

## 16. Phased Execution Plan

### Phase 0: Stabilize Core (Week 1-2)

> **Gate**: `flutter test` is 100% green, no product-contract drift

| Task | Priority | Files |
|---|---|---|
| Fix all 7 failing tests | P0 | `country_catalog.dart`, `country_catalog_test.dart`, `phone_validator_test.dart` |
| Align router policy and test expectations | P0 | `app_router.dart:196`, `app_router_redirect_test.dart:26` |
| Remove hidden test deps on Hive/Firebase/Supabase | P0 | `locale_provider.dart:14`, test helpers |
| Add test bootstrap helper | P0 | New: `test/helpers/test_bootstrap.dart` |

### Phase 1: Release Confidence (Week 3-5)

> **Gate**: CI gates all merges, flavors separate staging/production

| Task | Priority | Files |
|---|---|---|
| Add staging/production flavors | P0 | `build.gradle.kts`, Xcode configs |
| Unify Flutter version in `release.yml` to read `.fvmrc` | P1 | `.github/workflows/release.yml` |
| Add integration smoke tests for critical journeys | P0 | `test/integration_smoke/` |
| Define release cadence + rollback playbook | P1 | New: `docs/RELEASE_PROCESS.md`, `docs/ROLLBACK.md` |

### Phase 2: Platformize Reliability (Week 6-9)

> **Gate**: Offline sync model standardized, schema contracts enforced

| Task | Priority | Files |
|---|---|---|
| Standardize all repositories through sync engine | P1 | All repository files |
| Define staleness/conflict policy per data domain | P1 | New: `docs/OFFLINE_POLICY.md` |
| Add sync status indicator widget | P1 | New: `lib/shared/widgets/sync_indicator.dart` |
| Add migration/schema compatibility checks | P1 | `scripts/supabase_contract_smoke.sh` |

### Phase 3: World-Class UX (Week 10-13)

> **Gate**: Accessibility and adaptive readiness across critical screens

| Task | Priority | Files |
|---|---|---|
| Remove portrait lock or document hard requirement | P1 | `main.dart:61` |
| Add responsive layout system | P1 | New: `lib/shared/widgets/responsive_builder.dart` |
| Add Semantics labels to all interactive widgets | P1 | All screen files in `lib/features/` |
| Add golden / screenshot QA for top screens | P2 | New test files |
| Verify text scaling and contrast ratios | P1 | Manual + automated tests |

### Phase 4: Performance & Growth (Week 14-18)

> **Gate**: Measurable improvement in crash-free sessions, startup time, rollout safety

| Task | Priority | Files |
|---|---|---|
| Define and document performance budgets | P1 | New: `docs/PERFORMANCE_BUDGETS.md` |
| Add Baseline Profiles for Android | P1 | `android/app/src/main/baseline-prof.txt` |
| Add app-size tracking to CI | P2 | `.github/workflows/ci.yml` |
| Mature Remote Config into experimentation system | P2 | `feature_flags_service.dart` |
| Add kill-switch flags for payment and credit | P1 | `feature_flags_service.dart`, Remote Config console |
| Add release rings: internal → staff → staged | P2 | `docs/RELEASE_PROCESS.md` |

---

## 17. Sources & References

### Flutter Showcase (Official)
- [BMW](https://flutter.dev/showcase/bmw) — 45+ countries, 96 variant builds, automated workflows
- [Nubank](https://flutter.dev/showcase/nubank) — 48M+ users, modular ownership, dynamic content
- [Wolt](https://flutter.dev/showcase/wolt) — Responsive multi-device, bi-weekly releases
- [Google Classroom](https://flutter.dev/showcase/google-classroom) — Latency/jank/memory/accessibility benchmarked
- [Universal Studios](https://flutter.dev/showcase/universal-studios) — Low crash rate, short release cycles

### World-Class Mobile Engineering (Official)
- [Duolingo: Android Performance](https://blog.duolingo.com/android-app-performance/) — DAU-tied performance on entry-level devices
- [Duolingo: Baseline Profiles](https://blog.duolingo.com/slashed-android-startup-time-baseline-profiles/) — Startup time reduction
- [Duolingo: Visual QA](https://blog.duolingo.com/birds-eye-a-powerful-tool-for-exploring-app-screenshots/) — 5000+ screenshots/release
- [Duolingo: Experimentation](https://blog.duolingo.com/improving-duolingo-one-experiment-at-a-time/) — Growth-grade experiments
- [Uber: Crash Analytics](https://www.uber.com/blog/real-time-analytics-for-mobile-app-crashes/) — Real-time crash intelligence
- [Uber: Mobile Analytics](https://www.uber.com/en-GB/blog/how-uber-standardized-mobile-analytics/) — Standardized cross-platform
- [Uber: Network Failover](https://www.uber.com/en-GB/blog/eng-failover-handling/) — Degraded connectivity
- [Spotify: Experimentation](https://engineering.atspotify.com/2020/10/spotifys-new-experimentation-platform-part-1/) — Platform maturity
- [Grab: App Size (Project Bonsai)](https://engineering.grab.com/project-bonsai) — Size governance
- [Grab: Quality Evolution](https://engineering.grab.com/evolution-of-quality) — QA automation
- [Booking.com: Production Perf](https://medium.com/booking-com-development/measuring-mobile-apps-performance-in-production-726e7e84072f) — User-centric metrics
- [Monzo: Release Process](https://monzo.com/blog/2022/06/23/our-mobile-release-process-an-illustrated-story) — Release trains, beta rings
- [Meta: Baseline Profiles](https://engineering.fb.com/2025/10/01/android/accelerating-our-android-apps-with-baseline-profiles/) — 40% startup improvement
- [Meta: On-Device ML](https://engineering.fb.com/2025/07/28/android/executorch-on-device-ml-meta-family-of-apps/) — Latency + privacy

### Flutter Official Docs
- [Adaptive & Responsive](https://docs.flutter.dev/ui/adaptive-responsive/best-practices)
- [Accessibility](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)
- [Accessibility Testing](https://docs.flutter.dev/ui/accessibility/accessibility-testing)
- [Integration Tests](https://docs.flutter.dev/testing/integration-tests)
- [Flavors](https://docs.flutter.dev/deployment/flavors)
- [Widget Previewer](https://docs.flutter.dev/tools/widget-previewer)
- [Deep Link Validator](https://docs.flutter.dev/tools/devtools/deep-links)
- [Performance Tools](https://docs.flutter.dev/tools/devtools/performance)
- [Impeller](https://docs.flutter.dev/perf/impeller)

### Android Platform
- [Startup Vitals](https://developer.android.com/topic/performance/vitals/launch-time)
- [ANR Vitals](https://developer.android.com/topic/performance/vitals/anr)
