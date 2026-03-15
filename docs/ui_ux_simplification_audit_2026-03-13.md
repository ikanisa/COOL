# COOL UI/UX Simplification Audit

Date: 2026-03-13

Grounding:
- [`.agent/skills/cool-superapp-design/SKILL.md`](../.agent/skills/cool-superapp-design/SKILL.md)
- [`.agent/skills/frontend-ui-simplification/SKILL.md`](../.agent/skills/frontend-ui-simplification/SKILL.md)
- [`docs/ROUTE_INVENTORY.md`](./ROUTE_INVENTORY.md)
- [`docs/SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md)

## Scope

This audit reviews the full Flutter app with emphasis on:

- route ownership and shell clarity
- screen composition and above-the-fold noise
- duplicated navigation, tools, and summaries
- frontend/state/backend boundaries that affect UI honesty
- governance debt that will block safe simplification work

## Repo Baseline

- `51` `GoRoute` declarations in [`app_router.dart`](../lib/core/router/app_router.dart)
- `4` shell branches plus pushed standalone routes
- `51` `*screen.dart` files under `lib/features/**/screens`
- `117` `CoolCard` usages
- `73` `CoolButton` usages
- `39` `Wrap` usages in feature code
- `46` `SingleChildScrollView` usages
- `22` `CustomScrollView` usages
- Screen-budget hotspots documented in [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md#L29)

Quality baseline:

- `flutter analyze`: passes clean
- `flutter test`: fails with `4` issues
- Failing area 1: outdated auth smoke expectations in [`test/integration_smoke/auth_flow_test.dart`](../test/integration_smoke/auth_flow_test.dart)
- Failing area 2: stale generated governance snapshot in [`docs/SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md) checked by [`test/docs/governance_docs_sync_test.dart`](../test/docs/governance_docs_sync_test.dart)

## Executive Assessment

The app's main UI problem is not visual styling. The shared design primitives are already fairly restrained. The real issue is compositional overload inside large routes:

- too many screens still behave like mini-dashboards
- too many secondary tools are given equal visual weight to the main task
- transactional routes still carry discovery, status, education, and diagnostics in the same viewport
- partner-branded routes often drift from COOL's calmer trust model into higher-chrome layouts

The right direction is not a new design system. The right direction is to reduce route responsibility, collapse repeated summaries, and move secondary actions into sheets, drill-downs, or later steps.

## Primary Findings

### 1. Navigation model is correct, but route responsibility is still too broad

The shell is directionally right in [`app_router.dart`](../lib/core/router/app_router.dart#L232):

- `Home`
- `Groups`
- pushed `MoMo`
- `Mobility`
- `Profile`

The problem is not the shell. The problem is that several standalone or branch routes still try to do too many jobs at once:

- [`home_screen.dart`](../lib/features/home/screens/home_screen.dart#L40) stacks overview, quick actions, recent activity, seasonal content, and missions
- [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart#L372) mixes identity, money, role setup, permissions, tools, support, and destructive actions
- [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart#L209) combines launch actions, driver mode, browse controls, result content, and optional maps
- [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart#L166) combines campaign storytelling, progress, amount selection, perks, payment explanation, pending state, recent activity, and share

Recommendation:

- keep the shell structure
- reduce each route to one dominant job
- move share, filters, export, advanced setup, and secondary tools out of the initial viewport

### 2. The shared component system is not the main source of noise

Shared primitives are already relatively quiet:

- [`cool_screen_background.dart`](../lib/shared/widgets/cool_screen_background.dart) is flat and intentionally restrained
- [`cool_card.dart`](../lib/shared/widgets/cool_card.dart) is low-chrome
- [`cool_screen_scaffold.dart`](../lib/shared/widgets/cool_screen_scaffold.dart) is simple

Noise is coming from how screens compose those primitives:

- too many `CoolCard`s per screen
- too many stacked sections before scroll
- too many `Wrap` clusters for filters, badges, facts, and metadata
- too many routes using cards as navigation instead of rows or one clear CTA

Recommendation:

- solve hierarchy structurally before touching theme tokens
- reduce cards, chips, and helper copy before creating new variants

### 3. COOL has too many equal-weight secondary tools

This shows up repeatedly:

- [`momo_cards_widgets.dart`](../lib/features/momo/widgets/momo_cards_widgets.dart#L104) gives statements, QR, request payment, scan QR, and NFC similar visual weight
- [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart#L380) exposes money, identity, preferences, support, more tools, and app access within one long hub
- [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) puts contribute, share, and invite in the same top action area

Recommendation:

- one primary CTA above the fold
- all secondary tools move to a shared "More tools" or overflow pattern
- share and invite should rarely sit beside the main transactional CTA

### 4. Partner and Rayon surfaces are over-branded for transactional work

Brand expression is strongest where the app needs the most trust clarity:

- [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart)
- [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart)
- [`club_shop_screen.dart`](../lib/features/partners/screens/rayon/club_shop_screen.dart)
- [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart)
- [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart)

The issue is not branding itself. The issue is when brand chrome competes with payment meaning, state meaning, or task clarity.

Recommendation:

- keep strong branding on entry surfaces such as Rayon home
- tone down transactional routes such as checkout, support contribution, and ticket selection
- use COOL's quieter transactional surfaces once the user is past discovery

### 5. Route size confirms responsibility drift

The current budget file already identifies the main risk set in [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md#L40):

- Hotspot: [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart)
- Hotspot: [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart)
- Debt: [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart)
- Debt: [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart)
- Debt: [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart)
- Debt: [`home_screen.dart`](../lib/features/home/screens/home_screen.dart)
- Debt: [`shop_checkout_screen.dart`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart)

These are not isolated refactor opportunities. They are the main simplification program.

## Module Audit

### Auth

Primary task:
- start OTP as fast as possible

Current clutter:
- low on surface clutter
- medium on governance drift because tests still expect an older, denser auth surface

Keep:
- single-CTA onboarding in [`onboarding_screen.dart`](../lib/features/auth/screens/onboarding_screen.dart#L22)
- direct WhatsApp framing in [`otp_screen.dart`](../lib/features/auth/screens/otp_screen.dart#L146)
- no forced register redirect after OTP

Remove:
- stale test assumptions that expect two onboarding CTAs and older Rwanda/global explainer copy

Move:
- nothing major in the product UI

Merge:
- "new user" and "existing user" entry path into one CTA, which the product already does

Primary CTA:
- `Get Started` on onboarding
- `Continue` on OTP

Recommendation:
- keep auth visually simple
- update tests to reflect the now-simpler auth model

### Home

Primary task:
- orient the user and launch one useful action quickly

Current clutter:
- overview
- quick actions
- recent activity
- seasonal banner
- missions carousel

Keep:
- overview trust card
- top quick actions
- recent activity

Remove:
- none of the features, but remove equal weight between them

Move:
- season banner below fold
- missions below fold or reduce to one inline teaser row

Merge:
- statements affordance into recent activity or overview area, not as another separate destination cue

Primary CTA:
- one quick-action cluster

New above-the-fold structure:
- overview
- quick actions
- one recent activity preview

Relevant file:
- [`home_screen.dart`](../lib/features/home/screens/home_screen.dart#L40)

### Groups

Primary task:
- manage groups, create one, or contribute to one

Current clutter:
- [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart) uses five tab pills plus create banner plus list
- [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart) mixes type, target, frequency, bank, collection route, advanced settings, and visibility in one scroll
- [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart) gives contribute, share, invite, members, and history near-equal emphasis

Keep:
- strong group trust summary
- invite capability
- contribution flow

Remove:
- five-way filter emphasis on the root groups screen
- top-level duplication between share and invite

Move:
- advanced create-group settings into step 2
- invite-from-contacts into overflow or a bottom sheet

Merge:
- `All`, `Saving`, `Community`, `Public`, `Private` into a simpler `My Groups` / `Discover` split with optional filters in a sheet

Primary CTA:
- `Create Group` on the list route
- `Contribute` on detail

New above-the-fold structure:
- Groups list: segmented `My Groups` / `Discover`, then list
- Create group: type choice, name, target, continue
- Group detail: hero, one CTA, concise facts

### MoMo

Primary task:
- send money and access truthful statement history

Current clutter:
- the hub is acceptable, but the tools cluster still gives too much weight to non-primary actions
- statements screen combines overview, period chips, party filter, sort, export buttons, tabs, and lists

Keep:
- standalone route with back and home affordances in [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart)
- statements as a first-class route

Remove:
- equal visual weight across all secondary tools

Move:
- QR, request payment, scan QR, and NFC under a `More tools` sheet or grouped secondary route
- export actions from the main statement controls card into overflow

Merge:
- filter controls into one filter sheet instead of chips plus dropdowns plus exports on the same card

Primary CTA:
- `Send money`

New above-the-fold structure:
- send-money card
- recent statement summary
- compact secondary tools entry

Relevant files:
- [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart)
- [`momo_cards_widgets.dart`](../lib/features/momo/widgets/momo_cards_widgets.dart)
- [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart)

### Mobility

Primary task:
- find a ride or post a ride

Current clutter:
- mobility home mixes launch actions, driver online state, browse controls, trip content, and optional map
- trip board adds another mode switcher on top of the broader branch navigation
- driver setup and driver operations are better contained, but still connected too early from the browse route

Keep:
- schedule-trip step flow
- driver overview/manage split in [`driver_profile_screen.dart`](../lib/features/mobility/screens/driver_profile_screen.dart)
- list-first fallback when maps are unavailable

Remove:
- browse plus monitor plus manage responsibilities from the same viewport

Move:
- driver online/status controls to the driver route
- map toggle into list header or secondary entry point

Merge:
- `MobilityHome` and `TripBoard` mental models into one clearer browse surface

Primary CTA:
- `Find a ride` or `Post a ride`

New above-the-fold structure:
- mode selector
- one main CTA
- one list result block

Relevant files:
- [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart#L209)
- [`trip_board_screen.dart`](../lib/features/mobility/screens/trip_board_screen.dart)
- [`schedule_trip_screen.dart`](../lib/features/mobility/screens/schedule_trip_screen.dart)

### Profile

Primary task:
- manage account and access settings

Current clutter:
- profile is cleaner than older dashboard patterns, but still broad
- facts card, account, money, preferences, support, tools, access, travel role, and destructive actions still live in one place

Keep:
- grouped row-based settings
- one travel-role control
- more-tools section collapsed by default

Remove:
- duplicate identity/account facts between header, facts card, and row values

Move:
- MoMo QR, credit readiness, cool status, driver tools, and app access into dedicated secondary tools routes or sheets

Merge:
- identity and money into one `Account` section
- support and app access into one `Support and access` section

Primary CTA:
- none should dominate visually on profile; it should behave as a settings hub, not a dashboard

New above-the-fold structure:
- header
- one concise account summary
- one account settings section

Relevant files:
- [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart#L372)
- [`profile_app_access_sheet.dart`](../lib/features/profile/widgets/profile_app_access_sheet.dart)

### Credit

Primary task:
- explain the user's score and next step

Current clutter:
- relatively controlled
- some duplication remains between score explanation, next steps, readiness, and history sections

Keep:
- score hero
- next-step card
- readiness handoff

Remove:
- unnecessary section proliferation if the same story can be told with fewer headings

Move:
- deeper report detail behind drill-down if this surface grows

Merge:
- `Top factors` and `Report details` if they remain short

Primary CTA:
- `Open readiness`

Relevant files:
- [`credit_score_screen.dart`](../lib/features/credit/screens/credit_score_screen.dart)
- [`credit_readiness_screen.dart`](../lib/features/credit/screens/credit_readiness_screen.dart)

### Partners and Rayon

Primary task:
- discover partner services, then complete focused partner flows

Current clutter:
- generic partners route still uses tab-like segmentation despite a relatively small surface area
- Rayon routes are the biggest density cluster in the app

Keep:
- Rayon as a dedicated branded ecosystem
- partner-specific routes where the flow is truly different

Remove:
- dashboard-style service density from transactional Rayon routes

Move:
- benefits, achievements, order history, perks, and recent supporter activity into lower-priority routes or expandable sections

Merge:
- discovery chrome on `Club Shop`, `Tickets`, and `Support Detail` into simpler transaction-first layouts

Primary CTA:
- Tickets: seat and buy
- Shop: add to cart / checkout
- Support: choose amount and pay

High-priority Rayon hotspots:
- [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart#L166)
- [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart)
- [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart)
- [`shop_checkout_screen.dart`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart)
- [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart)

### Admin

Primary task:
- configure and operate the system clearly

Current clutter:
- admin dashboard is okay
- operational and config routes repeat a lot of explainer copy above lists and cards

Keep:
- utilitarian card/list style
- sectioned config categories

Remove:
- storytelling copy that sits before every operational list

Move:
- explanatory details into info icons, small inline captions, or docs links

Merge:
- repetitive admin section subtitles into one concise page intro

Primary CTA:
- edit or repair actions only where needed

Relevant files:
- [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart)
- [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart)
- [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart)

## Cross-Cutting Simplification Rules

Adopt these repo-wide:

1. Max three visually distinct blocks above the fold.
2. Exactly one primary CTA above the fold on task routes.
3. No more than one local navigation model per route.
4. Replace `Wrap` metadata clusters with:
   - a two- or three-metric row
   - a vertical facts list
   - a filter sheet
5. If a card exists only to route elsewhere, convert it to a row or secondary CTA.
6. Do not let branded gradients dominate payment, checkout, or settings routes.
7. Keep share, export, invite, and advanced configuration out of the first viewport unless they are the main task.

## Fullstack Implications

This simplification work should also tighten ownership boundaries:

- hotspot screens should shed orchestration into providers, repositories, or services before new UI work lands
- payment, ticketing, support, and checkout routes must keep pending versus confirmed language explicit
- mobility routes must preserve list fallback when embedded maps are unavailable
- permission-sensitive routes should keep truthful blocked and settings states
- feature-gated surfaces should expose unavailable states directly, not via empty dashboards

This is especially important for:

- MoMo
- support contributions
- ticket and shop checkout
- profile app access
- mobility location-dependent views

## Priority Order

### P0

- Refresh stale tests and docs so the simplification program has a clean baseline
- Simplify Home, Profile, and MoMo above the fold without changing route map
- Regenerate [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md) after any line-count-affecting work

### P1

- Split or compress `Create Group` and `Group Detail`
- Simplify `Mobility Home` and align it with `Trip Board`
- Simplify Rayon `Tickets` and `Shop Checkout`

### P2

- Decompose `Support Detail` and `Fan Profile`
- Reduce Rayon discovery chrome outside the home route
- Normalize secondary tools into reusable sheet patterns

### P3

- Tighten admin copy density
- Revisit generic partners taxonomy once partner inventory stabilizes

## Suggested Acceptance Criteria

- `Home`, `Profile`, `Mobility`, `MoMo`, `Group Detail`, `Tickets`, and `Checkout` each have one dominant job
- `support_detail_screen.dart` and `fan_profile_screen.dart` drop below hotspot threshold
- debt screen count drops from `6` to `<= 2`
- `Wrap` usage in feature code drops materially
- no route shows tab bar plus chips plus multiple equal-weight card groups in one viewport
- `flutter analyze` remains clean
- auth smoke tests reflect the simplified auth flow
- governance docs stay in sync with generated inventories

## Final Recommendation

Do not start with a visual redesign pass.

Start with a structural simplification pass:

- trim route responsibilities
- demote secondary tools
- reduce dashboard behavior
- split the Rayon hotspots
- keep the app's trust surfaces quiet and transactional

If this order is respected, the app will already feel more minimalist and cleaner before any additional visual polish is attempted.
