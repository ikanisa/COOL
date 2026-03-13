# Frontend Fullstack Architecture

Use this file when the task needs implementation guidance across Flutter UI, Riverpod state, services, sync, lifecycle, and route ownership.

## App Bootstrap

Bootstrap happens in `lib/main.dart`.

Core boot order:

1. Flutter binding
2. environment validation
3. Firebase bootstrap
4. App Check
5. Crashlytics and performance hooks
6. system chrome
7. Supabase init
8. Hive init
9. `ProviderScope` launch

Implications:

- do not design flows that assume the app can function without core config unless a dedicated config-error state exists
- startup changes must respect crash, performance, and environment warnings

## App Root

`lib/app.dart` mounts:

- `MaterialApp.router`
- GoRouter
- locale provider
- dark theme
- lifecycle binding

This means:

- app-wide UX changes usually route through providers and router, not app-local widget state
- localization is part of root app state, not a per-screen patch

## State Ownership

### Preferred ownership model

- widgets render and dispatch intent
- providers coordinate state and invalidation
- repositories own Supabase access
- services handle lifecycle, device APIs, or cross-cutting behavior

### Do not do

- direct Supabase calls inside widgets
- giant screen-local orchestration when provider or service ownership is clearer
- duplicate business logic in screen and repository layers

## Router And Navigation

The router is in `lib/core/router/app_router.dart`.

Key rules:

- shell branches are limited and intentional
- `MoMo` is a pushed route, not a shell tab
- quick actions should shell-switch only for shell-root locations
- route additions must update `docs/ROUTE_INVENTORY.md`

When adding or redesigning a flow:

- decide whether it is shell, standalone route, or sheet
- preserve escape routes for high-focus standalone screens
- do not force profile completion after OTP verification

## Lifecycle And Coordinators

Lifecycle is wired through `lib/core/providers/app_lifecycle_providers.dart`.

Important coordinators:

- app lifecycle coordinator
- app session coordinator
- deep-link coordinator
- trip sync coordinator
- MoMo SMS autoread service

Design implication:

- many UX outcomes depend on app resume, auth change, or session state
- if a feature depends on resume behavior, test it on device

## Sync Model

The sync engine is explicit, not magical.

- offline writes queue in Hive
- callers flush by domain
- stale entries are discarded
- no background auto-sync

Implications:

- offline UX must explain stale or pending state clearly
- queued actions should not be presented as fully complete until the server confirms
- do not design around hidden background reconciliation that the app does not have

## Cross-Cutting Services

The app already has important service boundaries for:

- App Check
- Crashlytics
- Performance
- FCM
- MoMo
- location
- NFC
- deep links
- trip sync

Use service ownership when:

- the work crosses screens
- it depends on device APIs
- it needs lifecycle awareness

## Feature Flags And Gates

The app uses rollout gates and kill-switch patterns.

Design implication:

- every gated feature needs an unavailable state
- do not assume all routes or modules are active in every build
- map, mobility, MoMo, ticketing, or credit behavior may vary by config

## Screen Budget Discipline

The repo already documents oversized route hotspots. When touching a hotspot:

- simplify route responsibility first
- extract widgets and services before adding new sections
- avoid growing files over budget unless the work is explicitly a simplification pass

High-risk screens include:

- schedule trip
- profile
- driver profile
- trip board
- mobility home
- bank partner
- credit score
- credit readiness
- prisma partner
- MoMo

## Testing Expectations

At minimum, feature work should consider:

- route smoke or widget smoke for new routes
- targeted widget or provider tests for changed logic
- device-backed UAT for payment, access, map, scanner, or lifecycle-sensitive flows

Release-quality work should also respect:

- `flutter analyze`
- `flutter test`
- Deno checks for critical edge functions

## Fullstack Design Rule

When a user reports a UI problem, check these layers in order:

1. screen composition
2. provider invalidation or caching
3. repository query or filter logic
4. backend object availability
5. edge-function deployment or secret configuration

In this app, many “UI bugs” are actually filtering, routing, or backend-contract mismatches.

## Common Failure Modes

### UI shows empty state while data exists

Check:

- provider query parameters
- repository filters
- local caching
- route state or date-window keys

### User cannot exit a route

Check:

- shell vs push navigation choice
- `context.go` vs `context.push`
- app bar `Back` and `Home` affordances

### Payment appears broken

Check:

- USSD launch path
- Android SMS permission and autoread service
- raw SMS ingestion
- parsed or reconciled ledger state
- whether the UI is hiding draft rows

### Mobility appears broken

Check:

- location permission
- map key availability
- list fallback
- route-summary fallback

### Partner flow appears broken

Check:

- pending confirmation state
- deployed edge functions
- backend entity status
- wallet-pass or ticket enablement gates

## Output Guidance

When producing implementation guidance:

- identify the route and owning feature
- identify provider, repository, and service boundaries
- call out backend dependencies explicitly
- specify test coverage and UAT scope
- mention rollout, permission, and offline implications when relevant
