# Rayon Sports Brand-Fit UI/UX Review

Date: 2026-03-15

## Scope

This review covers the current Rayon Sports slice inside the COOL app, with
focus on:

- frontend UI structure and visual identity
- route hierarchy and cross-screen coherence
- shared widgets and theming
- provider/repository architecture that affects UX honesty
- fullstack contract issues that leak backend mechanics into the interface

Primary evidence sources:

- `lib/features/partners/rayon/screens/*.dart`
- `lib/features/partners/screens/rayon/*.dart`
- `lib/features/partners/widgets/partners_screen_sections.dart`
- `lib/core/theme/app_colors.dart`
- `lib/core/theme/rs_colors.dart`
- `lib/shared/widgets/cool_screen_background.dart`
- `lib/features/partners/providers/rayon_sports_provider.dart`
- `lib/features/partners/providers/rayon_providers.dart`
- `lib/features/partners/providers/member_registry_provider.dart`
- `lib/features/partners/repositories/rayon_sports_repository*.dart`
- `docs/SCREEN_BUDGETS.md`
- `docs/ROUTE_INVENTORY.md`

## Executive Assessment

The current Rayon implementation is functionally strong but visually split.
It does not yet read like a dedicated Rayon Sports app. It reads like:

- a generic COOL experience
- with Rayon colors added on some surfaces
- with multiple older and newer Rayon design patterns coexisting

The most important issue is not missing features. The issue is identity
coherence:

- the brand shell is too weak
- the visual language is inconsistent
- COOL semantic accents still bleed into Rayon routes
- payment and provider internals still surface in user-facing copy
- some older Rayon widgets still exist beside the newer minimalist direction

The correct next step is not adding more cards, gradients, or copy. The correct
step is to create one branded Rayon shell and then align every route to it.

## External Brand Cues

Public references point to a brand identity centered on:

- deep royal blue as the dominant color
- white as the main neutral
- gold or yellow as a supporting accent, not the base surface
- heritage and club symbolism as part of the club story
- official contribution and kit communications that feel club-native, not
  fintech-native

That matters because the current app still overuses:

- COOL green accent states
- COOL purple status colors
- generic DM Sans-heavy surfaces
- emoji/icon placeholders where the club crest should anchor recognition

## Critical Findings

### P0. Rayon branding is visually flattened at the shell level

Evidence:

- `lib/shared/widgets/cool_screen_background.dart`
- `lib/features/partners/rayon/screens/rayon_home_screen.dart`
- `lib/features/partners/rayon/screens/fan_profile_screen.dart`
- `lib/features/partners/screens/rayon/club_shop_screen.dart`

Issue:

- Rayon screens pass brand colors into `CoolScreenBackground`, but the widget
  no longer renders a visible branded atmosphere
- this removes club-specific spatial identity before the user even reads the
  content
- the result is a neutral COOL background with isolated Rayon cards on top

Impact:

- the app does not feel like a Rayon-first product
- discovery, identity, and matchday surfaces lose emotional tone
- every screen must overcompensate with heavier card decoration

Required update:

- create a real `RayonShellBackground`
- reintroduce subtle branded atmosphere only on entry and discovery surfaces
- keep checkout and confirmation routes quieter, but still club-native

### P0. Rayon still uses COOL accent semantics instead of a club-owned color system

Evidence:

- `lib/features/partners/rayon/theme/rs_theme.dart`
- `lib/features/partners/rayon/screens/fan_profile_screen.dart`
- `lib/features/partners/rayon/screens/support_detail_screen.dart`
- `lib/features/partners/screens/rayon/ticket_confirmation_screen.dart`
- `lib/features/partners/widgets/partners_screen_sections.dart`

Issue:

- `RsTheme.categoryColor()` still maps categories to COOL green, purple, and
  orange
- multiple Rayon routes still use `AppColors.accent` for positive or primary
  states
- this breaks the illusion of a dedicated club interface

Impact:

- brand tone feels mixed and unstable
- support, confirmation, and activity states look like generic superapp states
  rather than Rayon states

Required update:

- define a Rayon-only semantic token layer
- map positive, warning, and category states to blue, white, gold, and blue
  tints first
- reserve green only for system-wide success where club branding is not the
  dominant concern

### P0. There is no crest or official brand mark pipeline for Rayon

Evidence:

- `lib/features/partners/widgets/partners_screen_sections.dart`
- `lib/features/partners/widgets/partner_brand_mark.dart`
- asset search: bank logo assets exist, Rayon-specific crest assets do not

Issue:

- the Rayon entry card uses generic icon mapping and emoji-driven cues
- `PartnerBrandMark` supports bank logo assets, but Rayon does not yet have an
  equivalent crest asset flow
- the club is the most identity-sensitive partner in the app, but it is the
  least anchored to an official mark

Impact:

- the product misses instant brand recognition
- the UI feels conceptual rather than official

Required update:

- add a Rayon crest asset set
- create `RayonBrandMark` with dark/light/compact variants
- use that mark in the Partners hub, Rayon app bars, ticket confirmation, and
  profile identity surfaces

### P0. Backend/payment mechanics still leak into the UI

Evidence:

- `lib/features/partners/providers/rayon_sports_provider.dart`
- `lib/features/partners/repositories/rayon_sports_repository_dashboard.dart`

Issue:

- checkout completion messages still explain fees, SMS reconciliation, and route
  internals directly in UI-facing success copy
- the repository still exposes a broad `loadData()` model that forces screens
  to assemble user-facing meaning from low-level shapes

Impact:

- transactional trust depends on explanatory copy
- screens feel operational instead of premium
- the frontend remains harder to simplify because it owns too much contract
  translation

Required update:

- create route-ready read models for ticketing, support, and shop
- expose user-ready status labels and totals from the repository layer
- move reconciliation mechanics into lower-level receipts, status rows, or
  support detail, not the primary call-to-action path

### P1. The Partners entry path does not feel like the start of a Rayon app

Evidence:

- `lib/features/partners/screens/partners_screen.dart`
- `lib/features/partners/widgets/partners_screen_sections.dart`

Issue:

- Rayon sits inside a generic football partner card and a generic feature grid
- the route transition into Rayon lacks a dedicated “club handoff”
- typography and surface treatment still match broader COOL patterns

Impact:

- the user never gets a strong “you are entering the Rayon experience now”
  transition
- the brand experience starts too late

Required update:

- turn the Rayon card into a proper club gateway
- use crest, stronger blue-white hierarchy, and a single matchday-forward CTA
- move the four-tile feature grid below the club gateway or into the Rayon home
  route only

### P1. Typography is split between COOL utility styles and Rayon editorial styles

Evidence:

- `lib/features/partners/widgets/partners_screen_sections.dart`
- `lib/features/partners/rayon/screens/rs_admin_*`
- `lib/features/partners/rayon/screens/fan_profile_screen.dart`

Issue:

- Rayon headings often use Barlow Condensed, but many labels, filters, admin
  controls, and summary areas still use DM Sans and DM Mono as the default
- that is fine for IDs and payments, but not for the main club voice

Impact:

- the app sounds like two products at once
- discovery routes feel editorial, while admin and support flows fall back to a
  generic utility tone

Required update:

- define one typography rule:
  - Barlow Condensed for hero and section headlines
  - Barlow for body copy and navigation labels
  - DM Mono only for IDs, counters, seat codes, and payment values

### P1. Route responsibility is still heavy on several high-value screens

Evidence from `docs/SCREEN_BUDGETS.md`:

- `support_detail_screen.dart` — 1215 LOC
- `fan_profile_screen.dart` — 1030 LOC
- `shop_checkout_screen.dart` — 979 LOC
- `tickets_screen.dart` — 858 LOC
- `member_registry_screen.dart` — 718 LOC

Issue:

- even after simplification, the main Rayon surfaces still carry too much
  route-level orchestration
- large screens make it hard to preserve one consistent branded hierarchy

Impact:

- visual drift returns quickly
- every feature addition tends to create another card or another explanation

Required update:

- split large screens into route-specific sections and view models
- keep one route = one primary job
- move secondary utilities into sheets or subordinate routes

### P2. Legacy Rayon widgets are still present and can reintroduce design drift

Evidence:

- `lib/features/partners/rayon/widgets/rs_hero_banner.dart`
- `lib/features/partners/rayon/widgets/rs_membership_card.dart`
- `lib/features/partners/rayon/widgets/rs_service_card.dart`
- `lib/shared/widgets/widgets.dart`

Issue:

- older, higher-chrome Rayon widgets still exist and are still exported
- the newer minimalist routes do not consistently use them anymore
- this leaves two competing Rayon design languages in the repo

Impact:

- future work can accidentally reintroduce old visual density
- the team has no single source of truth for Rayon UI primitives

Required update:

- deprecate or remove legacy Rayon widgets after replacement
- define one approved Rayon primitive set:
  - brand mark
  - overview card
  - row-style navigation card
  - metric pill
  - matchday/ticket summary block
  - admin shell

### P2. Provider duplication still risks frontend inconsistency

Evidence:

- `lib/features/partners/providers/rayon_sports_provider.dart`
- `lib/features/partners/providers/rayon_providers.dart`
- `lib/features/partners/providers/member_registry_provider.dart`

Issue:

- the repo still contains overlapping Rayon provider strategies
- `memberRegistryProvider` exists in two files with different state models
- the old broad load-model path still exists beside newer lightweight routes

Impact:

- design cleanup can be undone by wiring a route to the wrong provider family
- loading, retry, and empty states become inconsistent across similar screens

Required update:

- pick one provider architecture
- keep route-scoped lightweight providers for consumer flows
- keep one focused admin provider layer
- remove dead or legacy Rayon provider paths

## Suggested Frontend Updates

### 1. Create a dedicated Rayon shell

Add:

- `RayonShellScaffold`
- `RayonShellBackground`
- `RayonBrandMark`
- `RayonSectionHeader`

Rules:

- app bars use crest + title, not title only
- discovery routes get subtle blue field texture or stadium light veil
- checkout routes use flatter surfaces with only restrained blue framing

### 2. Replace the current mixed token model with a Rayon semantic palette

Add tokens for:

- `rayonPrimary`
- `rayonPrimarySoft`
- `rayonSurface`
- `rayonSurfaceAlt`
- `rayonTextPrimary`
- `rayonTextSecondary`
- `rayonAccentGold`
- `rayonSuccess`
- `rayonInfo`
- `rayonWarning`

Rules:

- gold is accent, not layout chrome
- green does not appear as the main Rayon CTA color
- purple should disappear from Rayon routes entirely

### 3. Make the Partners hub feel like a real handoff into Rayon

Update:

- the Rayon partner hero card
- the post-card feature grid

Changes:

- replace emoji/icon hero with crest
- add one matchday-forward CTA such as `Open Rayon Sports`
- demote the registry/clubs/tickets/shop grid below the fold or into the Rayon
  home route

### 4. Align discovery, identity, transaction, and admin into separate visual modes

Discovery mode:

- home
- clubs
- membership
- support list
- shop list

Identity mode:

- profile
- registry
- my tickets

Transaction mode:

- tickets
- support detail
- checkout
- confirmation

Admin mode:

- admin dashboard
- matches
- tickets
- members
- shop
- orders
- initiatives

Each mode should have a different density profile but one shared brand system.

### 5. Remove COOL accent bleed from Rayon screens

Replace:

- green success chips with blue or gold-tinted Rayon status chips
- purple shipment or category colors with blue-family or neutral hierarchy
- generic accent gradients with Rayon-only gradients

### 6. Tighten copy to sound like a club product, not an ops console

Use club voice on:

- home
- fan clubs
- membership
- discovery

Use literal low-noise voice on:

- ticket purchase
- support contribution
- checkout
- admin CRUD

Avoid:

- technical payment-route explanations in CTA zones
- long helper paragraphs above totals or purchase actions
- multiple equal-weight subtitles in one viewport

### 7. Add real club imagery and pattern language

Recommended assets:

- crest
- supporter scarf or jersey texture
- subtle field-line pattern
- stadium-light top veil
- optional monochrome archival or crowd imagery for entry surfaces

Do not use:

- flat emoji placeholders as primary identity
- random generic football icons as the club mark

## Fullstack Changes Needed To Support Better UI

### A. Introduce user-ready view models

Instead of returning raw aggregate tables and having screens explain them, add:

- `RayonHomeViewData`
- `RayonTicketHubViewData`
- `RayonCheckoutViewData`
- `RayonSupportViewData`
- `RayonProfileViewData`

These should already contain:

- primary summary string
- clean status label
- CTA-ready totals
- payment status label
- reduced need for route-level composition logic

### B. Collapse legacy provider overlap

Target:

- keep `rayon_sports_provider.dart` as the main current surface
- remove or deprecate `rayon_providers.dart`
- keep a single `memberRegistryProvider`

### C. Separate transaction receipts from transaction CTAs

Keep:

- fees
- route labels
- reconciliation labels
- payment methods

Move them to:

- receipt sections
- status drill-downs
- order or ticket detail

Do not keep them in:

- primary success copy
- hero summaries
- main CTA labels

## What To Preserve

Do not remove:

- route coverage
- existing payment flows
- membership recovery
- fan clubs
- registry
- shop
- support flows
- tickets and confirmations
- admin coverage

The recommendation is to preserve all functionality and reduce friction by
reframing it, not by cutting capability.

## Prioritized Implementation Plan

### Phase 1. Brand system

- add crest assets
- add Rayon shell widgets
- add Rayon semantic tokens
- remove green and purple bleed from Rayon theme helpers

### Phase 2. Entry and discovery

- rebuild the Rayon entry card in the Partners hub
- align Rayon home, fan clubs, membership, and support list to one discovery
  language

### Phase 3. Identity and trust

- align profile, registry, my tickets, and confirmation to one identity/trust
  language
- make QR, membership, and official club affiliation feel first-class

### Phase 4. Transaction quieting

- simplify ticket, support, and shop checkout surfaces
- move payment mechanics out of hero copy and into disclosure/receipt areas

### Phase 5. Admin

- keep the new minimal admin shell
- standardize forms, status chips, and list item density
- remove leftover generic COOL accent usage from admin status indicators

### Phase 6. Repository and provider cleanup

- kill legacy Rayon provider overlap
- replace broad `loadData()` reliance with route-ready read models
- keep frontend state ownership consistent

## References

Public brand context used for this review:

- KT Press: Rayon Sports retained traditional blue and white references in kit
  presentation and official club framing
  - https://www.ktpress.rw/2024/08/rayon-sports-fc-launches-2024-2025-season-jersey/
- InyaRwanda: official logo usage and club identity handling in brand-related
  updates
  - https://inyarwanda.com/inkuru/155454/rayon-sports-ikorwa-mu-jisho-ryerekanwe-nkimpamvu-yibikorwa-byakozwe-bitemewe-byose-bikoresheje-ikirango-cyayo-155454.html
