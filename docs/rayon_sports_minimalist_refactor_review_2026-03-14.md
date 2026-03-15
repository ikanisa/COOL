# Rayon Sports Minimalist Refactor Review

Date: 2026-03-14

## Scope

This review covers the Rayon Sports fullstack slice:

- consumer routes
- admin routes
- Riverpod/provider architecture
- repository and Supabase contract shape
- UI density, copy density, and transactional trust

Primary audited files:

- `lib/features/partners/rayon/screens/*.dart`
- `lib/features/partners/screens/rayon/*.dart`
- `lib/features/partners/providers/*.dart`
- `lib/features/partners/repositories/rayon_sports_repository*.dart`
- `supabase/functions/parse-momo-sms/rayon_confirmation.ts`
- `supabase/functions/rs-scan-ticket/index.ts`

## Executive Assessment

The Rayon Sports implementation is feature-rich, but it is not minimal. The
main issue is not color, typography, or brand direction. The main issue is
responsibility overload:

- discovery, identity, transaction, and diagnostics are often mixed in one route
- too many screens present 4 to 8 equal-weight blocks in the first viewport
- backend/payment caveats leak directly into user-facing copy
- the provider layer still contains overlapping patterns from an older
  dashboard-style implementation and a newer lightweight implementation

The right refactor is structural, not cosmetic.

The target state should be:

- one dominant job per route
- one primary CTA above the fold
- no more than three visible blocks above the fold on consumer routes
- discovery routes can stay branded
- money routes must become quiet, literal, and copy-light
- backend contracts should deliver user-ready summaries instead of forcing each
  screen to explain system internals

## Current Baseline

### Route and file pressure

Current Rayon consumer routes:

- `/partners/rayon-sports`
- `/partners/rayon-sports/clubs`
- `/partners/rayon-sports/clubs/:clubId`
- `/partners/rayon-sports/membership`
- `/partners/rayon-sports/profile`
- `/partners/rayon-sports/registry`
- `/partners/rayon-sports/shop`
- `/partners/rayon-sports/shop/checkout`
- `/partners/rayon-sports/support`
- `/partners/rayon-sports/support/:initiativeId`
- `/partners/rayon-sports/tickets`
- `/partners/rayon-sports/tickets/:ticketId/confirm`
- `/partners/rayon-sports/tickets/my-tickets`

Current Rayon admin routes:

- `/admin/rayon`
- `/admin/rayon/initiatives`
- `/admin/rayon/matches`
- `/admin/rayon/members`
- `/admin/rayon/orders`
- `/admin/rayon/shop`
- `/admin/rayon/tickets`

Screen budget hotspots from `docs/SCREEN_BUDGETS.md`:

- `support_detail_screen.dart`: 1140 LOC
- `fan_profile_screen.dart`: 1030 LOC
- `tickets_screen.dart`: 810 LOC
- `shop_checkout_screen.dart`: 780 LOC
- `member_registry_screen.dart`: 718 LOC
- `club_shop_screen.dart`: 576 LOC
- `membership_tiers_screen.dart`: 534 LOC
- `rayon_home_screen.dart`: 526 LOC
- `fan_club_detail_screen.dart`: 507 LOC
- `support_screen.dart`: 427 LOC
- `fan_clubs_screen.dart`: 426 LOC

### Verification result

Rayon-focused test execution did not reach a clean baseline because the branch
has unrelated compile blockers:

- `lib/features/momo/screens/momo_screen.dart:503` references
  `appAccessServiceProvider` without importing the provider
- `lib/shared/widgets/cool_toast.dart:95-109` uses `const _VariantConfig(...)`
  with non-const property access like `CoolPalette.dark.accent`

This means the Rayon simplification program should not start with UI polish.
It should start with baseline stabilization.

## Primary Findings

### P0. The branch is not on a safe simplification baseline

Evidence:

- `lib/features/momo/screens/momo_screen.dart:503`
- `lib/shared/widgets/cool_toast.dart:95-109`

Impact:

- route-level widget tests cannot be trusted as a guardrail
- any visual refactor will be mixed with unrelated compile recovery
- regression attribution becomes ambiguous

Required action:

- fix compile blockers first
- rerun `flutter analyze`
- rerun Rayon and smoke tests before any UI refactor PR

### P0. Transaction routes are overloaded and explain the system instead of guiding the user

Evidence:

- `lib/features/partners/rayon/screens/support_detail_screen.dart:166-347`
- `lib/features/partners/screens/rayon/tickets_screen.dart:116-237`
- `lib/features/partners/screens/rayon/shop_checkout_screen.dart:113-307`

Current pattern:

- hero copy
- payment-routing explanation
- state explanation
- selector UI
- progress or perk content
- activity or history content
- share affordance
- action CTA

Impact:

- the user must parse too much before acting
- payment trust depends on explanatory paragraphs
- branded chrome competes with the moment of commitment

Required action:

- separate discovery from commitment
- standardize transaction routes to:
  - summary
  - selection
  - total
  - confirm CTA
  - status
- move share, perks, and historical activity below the primary action or behind
  disclosure

### P0. The Rayon provider architecture is overlapping and harder than it needs to be

Evidence:

- `lib/features/partners/providers/rayon_sports_provider.dart`
- `lib/features/partners/providers/rayon_providers.dart`
- `lib/features/partners/providers/member_registry_provider.dart`

Observed issues:

- monolithic `rayonSportsProvider` still exists beside newer lightweight
  providers
- composite provider helpers are mixed with route-specific async state
- `memberRegistryProvider` exists in two different files with different state
  models
- some screens invalidate three or more providers after one mutation

Impact:

- state ownership is unclear
- route refactors become riskier than necessary
- loading, retry, and empty-state logic gets duplicated

Required action:

- choose one provider strategy for Rayon
- remove duplicate provider definitions
- introduce route-scoped view models only where a route truly orchestrates a
  multi-step flow
- keep mutations in focused controllers, not in large UI trees

### P1. Rayon home is still a mini-dashboard instead of a clean entry point

Evidence:

- `lib/features/partners/rayon/screens/rayon_home_screen.dart:69-329`

Current structure:

- hero banner
- membership card
- membership recovery card
- plans link
- five service cards
- next match section

Impact:

- too many entry points compete at once
- home behaves like a services dashboard, not a clean club home

Target:

- hero plus one primary entry block
- next match teaser
- one compact services list

### P1. Fan profile is a hotspot because it combines identity, benefits, activity, commerce, and access

Evidence:

- `lib/features/partners/rayon/screens/fan_profile_screen.dart:104-184`

Current structure:

- identity hero
- achievements strip
- recent orders
- benefits
- QR access

Impact:

- “profile” has no single meaning
- high-value identity and QR status are diluted by secondary content

Target:

- top section: membership identity and QR readiness
- second section: benefits
- lower section: activity preview
- move order history to its own route or a smaller “recent activity” preview

### P1. Tickets mixes browsing, membership entitlement, share, switching, and purchase setup

Evidence:

- `lib/features/partners/screens/rayon/tickets_screen.dart:83-237`
- `lib/features/partners/screens/rayon/tickets_screen.dart:289-340`

Current structure:

- gold early-access banner
- routing explainer paragraph
- extra gold card
- 3-tab switcher
- share action
- my tickets shortcut
- purchase sheet

Impact:

- too many decision layers before selecting a match
- the route explains access policy instead of letting the product express it

Target:

- list of sellable matches first
- one compact membership/access status row
- filters or tabs only if they materially reduce scan time
- move “my tickets” to a top-right action or separate segment, not equal weight
  with on-sale browsing

### P1. My tickets is mostly clean, but it still carries unrelated content

Evidence:

- `lib/features/partners/screens/rayon/my_tickets_screen.dart:190-195`
- `lib/features/partners/screens/rayon/my_tickets_screen.dart:231-268`

Issue:

- the “league standings unavailable” card is not part of the ticket job

Target:

- keep pending, ready, and past tickets
- remove unrelated football context entirely

### P1. Support detail should be a multi-step flow, not one long branded page

Evidence:

- `lib/features/partners/rayon/screens/support_detail_screen.dart:171-347`

Current structure:

- branded hero
- category
- title and long description
- progress card
- amount selector
- perks
- MoMo info banner
- CTA
- pending contribution card
- recent support activity
- share card

Impact:

- one scroll tries to do storytelling, conversion, payment education, and social
  proof at the same time

Target:

- step 1: cause summary
- step 2: amount selection
- step 3: payment handoff and pending state
- step 4: optional updates/share/social proof

### P1. Shop routes are still more promotional than task-first

Evidence:

- `lib/features/partners/screens/rayon/club_shop_screen.dart:118-259`
- `lib/features/partners/screens/rayon/shop_checkout_screen.dart:120-307`

Issues:

- catalog hero is visually strong and copy-heavy
- category filters are always visible
- checkout still reads like a long form plus summary plus routing explanation

Target:

- catalog: product grid first, filters secondary
- checkout: order summary first, fulfillment input second, confirm CTA third
- use disclosure for discount math and payment details

### P1. Fan clubs and registry still read like management tools, not lightweight community routes

Evidence:

- `lib/features/partners/screens/rayon/fan_clubs_screen.dart:74-239`
- `lib/features/partners/screens/rayon/fan_club_detail_screen.dart:84-260`
- `lib/features/partners/screens/rayon/member_registry_screen.dart:71-193`

Issues:

- clubs list shows intro copy, filters, create action, my club section, and all
  clubs at once
- club detail mixes profile, stats, achievements, member preview, share, and join
- registry shows header, search, filters, spotlight, list, legend, and paging
  affordances in one dense route

Target:

- clubs list: club directory first, filters in sheet, create under secondary
  action
- club detail: summary plus join CTA first, deeper content lower
- registry: searchable list first, spotlight and legend demoted or moved

### P2. Admin screens are workable but still too form-heavy inside screen files

Evidence:

- `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart:16-125`
- `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart:128-252`
- `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart:126-229`
- `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart:97-184`

Issues:

- modal form construction is embedded directly in route files
- admin pages are centered on cards and ad hoc dialogs instead of simple table
  or list workflows

Target:

- dashboard becomes a neutral operations entry point
- each admin route becomes list/table first
- create/edit forms move into shared sheets or dedicated form widgets

### P2. Backend contracts are still too raw for minimalist screens

Evidence:

- `lib/features/partners/repositories/rayon_sports_repository_dashboard.dart:19-173`
- `lib/features/partners/repositories/rayon_sports_repository_membership.dart:33-159`
- `lib/features/partners/providers/rayon_sports_provider.dart:318-552`

Observed problems:

- home data still loads from many tables at once
- partner resolution is repeatedly derived from `partners`
- payment route resolution is fetched separately and then explained in UI copy
- several screens combine multiple async providers client-side just to render a
  simple summary

Positive note:

- backend transaction state is directionally honest
- `supabase/functions/parse-momo-sms/rayon_confirmation.ts` and
  `supabase/functions/rs-scan-ticket/index.ts` preserve real pending/valid/used
  states instead of faking instant success

Target:

- add summary RPCs or read models for each major route
- return route-ready copy/state fields instead of making each screen compose them
- cache partner and payment route resolution per session

## Page-By-Page Target State

### Consumer routes

`Rayon Home`

- keep: brand hero, membership status, next match
- cut: grid-style service wall
- replace with: one primary CTA plus a short services list

`Membership Tiers`

- keep: tier comparison
- simplify to: current tier, next tier, compact benefit table

`Fan Profile`

- keep: membership identity and QR
- move: orders and long activity history

`Registry`

- keep: search and member list
- demote: spotlight and legend
- move filters into a sheet

`Fan Clubs`

- keep: directory and join
- demote: create flow and region filter chrome

`Fan Club Detail`

- keep: summary, join status, share
- demote: achievements and member preview

`Club Shop`

- keep: product list and cart state
- demote: promo hero and category chrome

`Shop Checkout`

- keep: line items, fulfillment, total, pay CTA
- demote: all explanatory copy that is not actionable

`Support`

- keep: initiative list
- demote: large summary intro

`Support Detail`

- split into summary and checkout states

`Tickets`

- keep: on-sale list and purchase
- demote: entitlement marketing, redundant tabs, large routing explanation

`My Tickets`

- keep: pending/ready/past structure
- remove: standings-related card

`Ticket Confirmation`

- current direction is good
- keep it minimal

### Admin routes

`Admin Dashboard`

- keep: route index
- simplify to utilitarian navigation with smaller stat strip

`Admin Matches`, `Shop`, `Initiatives`

- refactor inline forms into reusable admin editors
- make list, filter, create, and edit states explicit

`Admin Members`, `Orders`, `Tickets`

- keep table/list focus
- standardize status actions and reduce ad hoc chips/buttons

## Robust Refactor Plan

### Phase 0. Stabilize the baseline

Duration: 1 to 2 days

Tasks:

- fix compile blockers in `momo_screen.dart` and `cool_toast.dart`
- rerun `flutter analyze`
- rerun Rayon tests and primary smoke tests
- freeze feature additions on hotspot Rayon routes

Exit criteria:

- branch compiles
- tests for Rayon routes are runnable again

### Phase 1. Collapse the Rayon state architecture

Duration: 2 to 3 days

Tasks:

- pick one provider architecture for Rayon
- remove `rayon_providers.dart` overlap or migrate remaining consumers fully
- keep one `memberRegistryProvider`
- define route-scoped controllers only for multi-step routes:
  - tickets checkout
  - shop checkout
  - support contribution

Exit criteria:

- no duplicate provider names
- no route invalidates multiple unrelated providers to refresh one action

### Phase 2. Define minimalist route rules

Duration: 1 day

Adopt hard rules:

- max 1 primary CTA above the fold
- max 3 above-the-fold blocks on consumer routes
- no permanent helper paragraph explaining backend mechanics when a status badge,
  compact note, or disclosure can do the job
- tabs only for same-shape content sets
- filters go into sheets unless they are the main job of the route
- share is secondary on transaction routes

### Phase 3. Rebuild discovery routes

Duration: 3 to 4 days

Scope:

- `rayon_home_screen.dart`
- `membership_tiers_screen.dart`
- `support_screen.dart`
- `fan_clubs_screen.dart`

Tasks:

- reduce hero height and copy length
- convert service card walls into tighter navigation lists
- make next-match and active-cause previews lighter
- keep brand identity, but reduce chrome density

### Phase 4. Rebuild transaction routes

Duration: 4 to 5 days

Scope:

- `tickets_screen.dart`
- `shop_checkout_screen.dart`
- `club_shop_screen.dart`
- `support_detail_screen.dart`
- `my_tickets_screen.dart`
- `ticket_confirmation_screen.dart`

Tasks:

- standardize transaction shell:
  - summary
  - selection
  - total
  - CTA
  - status
- split `support_detail_screen.dart` into summary and contribution status states
- move ticket purchase from dense route logic into a smaller checkout flow
- remove non-ticket content from `my_tickets_screen.dart`

### Phase 5. Rebuild identity and community routes

Duration: 3 to 4 days

Scope:

- `fan_profile_screen.dart`
- `member_registry_screen.dart`
- `fan_club_detail_screen.dart`

Tasks:

- make profile identity-first
- turn registry into a search-first list
- keep club detail focused on join state and summary

### Phase 6. Simplify admin operations

Duration: 3 days

Tasks:

- extract inline form builders from admin route files
- standardize admin layouts around list/table plus action bar
- keep admin neutral and lower-brand than consumer discovery routes

### Phase 7. Backend contract cleanup

Duration: 3 to 5 days, can overlap with UI work

Introduce focused read models:

- `rayon_home_summary`
- `rayon_profile_summary`
- `rayon_ticket_hub`
- `rayon_support_detail`
- `rayon_registry_page`

Contract goals:

- one request per route where possible
- explicit user-facing state fields
- fewer client-side async joins
- partner and payment route resolved once and cached

### Phase 8. QA and governance

Duration: 2 days

Tasks:

- update smoke tests for each simplified route
- add route-level widget tests for:
  - empty
  - loading
  - happy path
  - pending transaction
- regenerate `docs/ROUTE_INVENTORY.md`
- regenerate `docs/SCREEN_BUDGETS.md`

Success criteria:

- no Rayon consumer screen above 700 LOC after refactor
- no hotspot files remain in Rayon consumer flows
- transactional routes feel quieter than discovery routes
- compile and tests are green

## Recommended Route Reshaping

Do not add more top-level nav destinations. Reshape within Rayon instead.

Recommended route split:

- `/partners/rayon-sports`
- `/partners/rayon-sports/membership`
- `/partners/rayon-sports/profile`
- `/partners/rayon-sports/profile/activity`
- `/partners/rayon-sports/clubs`
- `/partners/rayon-sports/clubs/create`
- `/partners/rayon-sports/clubs/:clubId`
- `/partners/rayon-sports/registry`
- `/partners/rayon-sports/shop`
- `/partners/rayon-sports/shop/cart`
- `/partners/rayon-sports/shop/checkout`
- `/partners/rayon-sports/shop/orders/:orderId`
- `/partners/rayon-sports/support`
- `/partners/rayon-sports/support/:initiativeId`
- `/partners/rayon-sports/support/:initiativeId/status`
- `/partners/rayon-sports/tickets`
- `/partners/rayon-sports/tickets/checkout/:matchId`
- `/partners/rayon-sports/tickets/my-tickets`
- `/partners/rayon-sports/tickets/:ticketId/confirm`

Not every split needs to happen immediately. The important point is to stop
forcing large mixed-purpose routes to carry both browsing and commitment.

## Design Direction

Use this visual rule:

- entry pages can feel like Rayon
- payment pages must feel like trust

Practical translation:

- discovery: richer blue/gold branding is acceptable
- transaction: flatter surfaces, smaller hero areas, less decorative copy,
  clearer totals, fewer badges
- state: pending, valid, used, cancelled should be obvious in one glance
- typography: keep emphasis, but reduce all-caps labels and repeated section
  headers

## First PR Sequence

Recommended first three PRs:

1. Baseline repair
   - fix compile blockers
   - confirm test baseline
2. State architecture cleanup
   - remove duplicate Rayon provider paths
   - keep one route data strategy
3. Transaction simplification
   - `tickets_screen.dart`
   - `shop_checkout_screen.dart`
   - `support_detail_screen.dart`

This order produces the fastest visible reduction in noise while lowering
technical risk for the rest of the module.
