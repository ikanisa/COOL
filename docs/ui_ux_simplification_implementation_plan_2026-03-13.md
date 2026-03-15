# UI/UX Simplification Implementation Plan

Date: 2026-03-13

Based on:

- [`ui_ux_simplification_audit_2026-03-13.md`](./ui_ux_simplification_audit_2026-03-13.md)
- [`frontend_ui_simplification_audit.md`](./frontend_ui_simplification_audit.md)
- [`ROUTE_INVENTORY.md`](./ROUTE_INVENTORY.md)
- [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md)

## Objective

Move the app from a multi-dashboard, high-density mobile product to a simpler
task-first experience that feels clean, minimal, and trustworthy without
requiring a wholesale redesign of the design system.

The target state is:

- one dominant user job per screen
- one primary CTA above the fold
- no more than three distinct content blocks above the fold on core routes
- fewer equal-weight cards, chips, banners, and helper paragraphs
- quieter transactional surfaces after discovery
- truthful, smaller backend contracts so the UI does not need to explain system complexity

## Non-Goals

This program should not:

- introduce a new visual identity or theme system before structural cleanup
- increase feature scope while simplification is in progress
- add more top-level navigation destinations
- preserve every current card, tab, or chip pattern out of fear of regression
- let partner branding override transaction clarity

## Planning Principles

1. Simplify structure before styling.
2. Fix the baseline first so simplification work happens on a green branch.
3. Treat oversized routes as decomposition problems, not cosmetic problems.
4. Prefer progressive disclosure over equal-weight sections.
5. Move orchestration out of widget trees and into focused view models or route-level controllers.
6. Keep the current shell model unless user testing proves it wrong.

## Recommended Delivery Shape

This should run as a five-phase program over roughly 4 to 6 weeks.

Suggested ownership:

- one mobile lead for route decomposition and shared UI rules
- one product/design owner for prioritization and copy reduction
- one backend owner for summary contracts and state honesty where screens are being simplified
- one QA owner for smoke coverage and UAT across all simplified flows

## Program Success Criteria

The program is complete when:

- `flutter analyze` passes
- `flutter test` passes
- governance docs are regenerated and in sync
- the core audited routes each present one dominant task above the fold
- secondary actions move into overflow, sheets, tabs, or lower-priority routes
- the largest P0 and P1 screens are decomposed into smaller focused sections
- the app feels more list-first, action-first, and copy-light across home, profile, groups, mobility, and partner transactions

## Phase 0: Baseline Restoration And Guardrails

### Goal

Restore a trustworthy baseline before any simplification PRs start.

### Duration

2 to 3 working days

### Tasks

1. Fix stale auth smoke expectations in [`test/integration_smoke/auth_flow_test.dart`](../test/integration_smoke/auth_flow_test.dart) so tests match the intentionally simplified auth flow.
2. Regenerate [`ROUTE_INVENTORY.md`](./ROUTE_INVENTORY.md) and [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md) from [`tool/governance_docs.dart`](../tool/governance_docs.dart).
3. Re-run `flutter analyze` and `flutter test` and keep both green before starting UI cleanup.
4. Freeze ad hoc UI additions to the current hotspot screens during this program unless they directly support simplification.
5. Adopt the audit checklist in [`frontend_ui_simplification_audit.md`](./frontend_ui_simplification_audit.md) as the review gate for affected routes.

### Exit Criteria

- baseline tests and docs are green
- current route and screen budgets are trustworthy
- the team is no longer simplifying on top of stale product assumptions

## Phase 1: Core Shell Surface Simplification

### Goal

Reduce the density of the most frequently visited user routes first.

### Duration

1 to 1.5 weeks

### Scope

- [`home_screen.dart`](../lib/features/home/screens/home_screen.dart)
- [`profile_screen.dart`](../lib/features/profile/screens/profile_screen.dart)
- [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart)
- [`momo_statements_screen.dart`](../lib/features/momo/screens/momo_statements_screen.dart)

### Workstream 1A: Home

Implementation:

1. Keep only overview, quick actions, and one recent activity preview above the fold.
2. Move seasonal promotion and missions below the fold or convert them into one small teaser row.
3. Merge statement/history affordances into the overview or activity area instead of creating another equal-weight section.
4. Extract large sections from the route so the screen stops owning all orchestration directly.

Acceptance:

- one quick-action cluster is clearly primary
- no more than three visible blocks above the fold
- discovery or campaign content is visually subordinate to action

### Workstream 1B: Profile

Implementation:

1. Reduce the root route to identity summary, money summary, and one primary next action.
2. Move support, app access, destructive actions, and secondary tools into dedicated routes or sheets.
3. Split long mixed-purpose sections so the route stops behaving like a settings dashboard and an account hub at the same time.
4. Reuse the existing sheets and dialogs only where they reduce cognitive load, not where they create another layer of navigation noise.

Acceptance:

- the root profile route reads as an account home, not a long utility hub
- access and support actions are still reachable but no longer compete with the main task
- destructive actions are demoted

### Workstream 1C: MoMo

Implementation:

1. Keep send money and truthful balance or activity entry points primary on [`momo_screen.dart`](../lib/features/momo/screens/momo_screen.dart).
2. Move QR, NFC, request payment, and lower-frequency tools under a shared secondary tools pattern.
3. Simplify statements to one period selector plus one optional filter sheet, instead of persistent equal-weight chips and controls.
4. Collapse summary cards where a single headline balance or recent activity preview is enough.

Acceptance:

- the MoMo hub emphasizes one primary action path
- statements become easier to scan and filter
- non-primary tools remain available without dominating the route

## Phase 2: Groups And Mobility Flow Simplification

### Goal

Turn the most overloaded multi-step consumer flows into clearer sequences.

### Duration

1 to 1.5 weeks

### Scope

- [`groups_screen.dart`](../lib/features/groups/screens/groups_screen.dart)
- [`create_group_screen.dart`](../lib/features/groups/screens/create_group_screen.dart)
- [`group_detail_screen.dart`](../lib/features/groups/screens/group_detail_screen.dart)
- [`mobility_home_screen.dart`](../lib/features/mobility/screens/mobility_home_screen.dart)
- [`trip_board_screen.dart`](../lib/features/mobility/screens/trip_board_screen.dart)
- [`schedule_trip_screen.dart`](../lib/features/mobility/screens/schedule_trip_screen.dart)
- [`driver_profile_screen.dart`](../lib/features/mobility/screens/driver_profile_screen.dart)

### Workstream 2A: Groups

Implementation:

1. Replace the five-way visual filter emphasis on the root groups route with a simpler `My Groups` and `Discover` split.
2. Convert advanced filters into a sheet instead of always-visible pills.
3. Break create-group into progressive steps:
   - step 1: type, name, target
   - step 2: contribution model and collection path
   - step 3: optional visibility and advanced settings
4. Reduce group detail to summary, one primary CTA, and concise facts.
5. Move share and invite into overflow or a bottom sheet so `Contribute` remains dominant.

Acceptance:

- the groups list feels easier to scan
- create-group no longer asks for every decision at once
- group detail is contribution-first instead of action-cluster-first

### Workstream 2B: Mobility

Implementation:

1. Reduce the mobility home route to route intent, location context, and one primary launch action.
2. Move browse controls, driver controls, and advanced result filtering out of the main hero area.
3. Make trip board list-first and move advanced filters into a sheet or separate control surface.
4. Split schedule-trip into smaller steps so the route no longer carries every setup and explanation on one scroll.
5. Simplify driver profile to trust summary, availability, and one next action before deeper metrics.

Acceptance:

- mobility routes stop combining map, toolbelt, browse controls, and long forms in one viewport
- scheduling feels guided instead of encyclopedic
- driver trust details remain available without crowding the route

## Phase 3: Rayon And Partner Transactional Simplification

### Goal

Keep discovery branded, but make money, support, ticketing, and checkout surfaces calmer and easier to trust.

### Duration

1 to 1.5 weeks

### Scope

- [`rayon_home_screen.dart`](../lib/features/partners/rayon/screens/rayon_home_screen.dart)
- [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart)
- [`club_shop_screen.dart`](../lib/features/partners/screens/rayon/club_shop_screen.dart)
- [`shop_checkout_screen.dart`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart)
- [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart)
- [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart)

### Workstream 3A: Discovery Versus Transaction Split

Implementation:

1. Keep stronger partner branding on entry routes such as Rayon home.
2. Tone down visual chrome on purchase, support, and checkout routes.
3. Standardize transactional layout across tickets, shop checkout, and support:
   - summary
   - amount or selection
   - confirmation CTA
   - secondary details below or behind disclosure

Acceptance:

- the user can tell when they are browsing and when they are committing money
- branding no longer competes with payment meaning

### Workstream 3B: P0 Hotspot Decomposition

Implementation:

1. Split [`support_detail_screen.dart`](../lib/features/partners/rayon/screens/support_detail_screen.dart) into focused sections or subroutes:
   - campaign summary
   - contribution amount picker
   - confirmation state
   - perks or recent supporters as lower-priority content
2. Split [`fan_profile_screen.dart`](../lib/features/partners/rayon/screens/fan_profile_screen.dart) so membership identity, benefits, activity, and support tools are not all equal-weight on first load.
3. Simplify [`tickets_screen.dart`](../lib/features/partners/screens/rayon/tickets_screen.dart) to event summary, ticket choice, and checkout path with secondary event context lower in the flow.
4. Simplify [`shop_checkout_screen.dart`](../lib/features/partners/screens/rayon/shop_checkout_screen.dart) with progressive disclosure for fees, fulfillment, and policy text.

Acceptance:

- P0 partner transaction screens are no longer mini-dashboards
- large hotspot screens are decomposed into smaller route sections or route-adjacent widgets
- the first scroll answers only the question required to continue

## Phase 4: Admin And Secondary Surface Cleanup

### Goal

Bring internal and secondary routes into the same simpler interaction model.

### Duration

4 to 6 working days

### Scope

- [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart)
- [`operational_dashboard_screen.dart`](../lib/features/admin/screens/operational_dashboard_screen.dart)
- [`manage_app_config_screen.dart`](../lib/features/admin/screens/manage_app_config_screen.dart)
- lower-priority partner and utility routes after the core consumer surfaces are done

### Tasks

1. Reduce dashboards to headline metrics, urgent states, and deep links instead of wide card grids.
2. Push dense configuration and support tools into drill-down sections instead of one long management route.
3. Align internal routes with the same card, copy, and action hierarchy rules used on consumer routes.
4. Remove decorative consumer chrome from surfaces that are operational by nature.

### Exit Criteria

- admin routes feel faster to scan
- internal tools stop inheriting unnecessary consumer presentation patterns

## Cross-Cutting Engineering Work

The UI simplification program needs supporting code changes beyond layout edits.

### Route And State Ownership

1. Move orchestration out of oversized screen widgets into smaller route controllers, presenters, or section view models.
2. Standardize route states to `loading`, `ready`, `empty`, and `error`.
3. Remove compatibility copy and backend explanations from user-facing routes unless they are operationally required.

### Summary Contracts

1. Add or refine smaller summary contracts for home, profile, group detail, mobility launch, and partner transactions.
2. Avoid stitching multiple repository responses together in the widget tree when a single summary payload would make the UI simpler and more truthful.
3. Ensure summary data answers the main route question first; move historical and diagnostic data to dedicated routes.

### Shared UI Rules

1. Prefer rows, lists, and grouped sections over stacks of cards.
2. Use one primary button style and one quiet secondary style on core routes.
3. Move share, invite, export, and advanced filters into overflow or bottom sheets by default.
4. Keep helper copy to one sentence above the fold.
5. Do not place tabs, chips, banners, and card navigation on the same first viewport unless the route absolutely requires it.

## PR Sequencing Recommendation

Use small, reviewable PRs instead of one broad redesign branch.

Recommended order:

1. Baseline fix PR: tests, governance docs, and checklist adoption.
2. Shared simplification rules PR: card and button usage rules, shared overflow patterns, and any low-risk shared layout helpers.
3. Home and profile PR.
4. MoMo and statements PR.
5. Groups PR.
6. Mobility PR.
7. Rayon transaction PR.
8. Admin and residual cleanup PR.

For hotspot routes, prefer a two-step sequence:

1. behavior-preserving extraction of sections and state helpers
2. visible simplification of hierarchy, copy, and action placement

## QA And UAT Plan

Every phase should include:

- widget tests for the simplified route hierarchy where practical
- smoke validation of the main happy path
- manual UAT for content density, action clarity, and regression risk

Minimum UAT paths:

1. onboarding to OTP entry and verify
2. home to MoMo primary action
3. group discovery to group contribution
4. mobility launch to trip scheduling
5. Rayon discovery to ticket or support checkout
6. profile to support, access, and money actions

Each audited route should be reviewed against the checklist in [`frontend_ui_simplification_audit.md`](./frontend_ui_simplification_audit.md) before sign-off.

## Final Recommendation

Start with baseline recovery, then simplify the core shell routes before touching partner and admin surfaces.

Do not begin by tuning colors, gradients, or animations. The fastest path to a
clean app is:

1. reduce route responsibility
2. demote secondary actions
3. split oversized screens
4. simplify contracts so the UI can stay small and honest

If sequencing becomes constrained, keep this priority order:

1. baseline restoration
2. home
3. profile
4. groups
5. mobility
6. support detail and fan profile
7. tickets and checkout
8. admin cleanup
