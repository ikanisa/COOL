# COOL UI Audit
**Date:** 2026-03-23  
**Method:** Repo-grounded audit of routes, theme tokens, shared widgets, representative high-impact screens, and UI test coverage. No linked local Stitch project ID was available, so this audit is based on the implemented Flutter interface.

## Executive Summary
The interface has a strong design language already. The palette, typography, spacing, card geometry, and navigation chrome are coherent enough to feel like a real product system rather than a collection of screens.

The weakness is not visual identity. It is screen-shell governance. The app has enough routes and product families now that hand-built scaffolds, app bars, forms, and list layouts are creating implementation drift even though the underlying tokens are solid.

The highest-value next move is not another visual redesign. It is standardizing page archetypes: core tab root, core detail, admin detail, partner-branded detail, and dense data workspace.

## Scope Snapshot
- Documented routed surface: `82` routes across `4` shell branches in `docs/ROUTE_INVENTORY.md`
- Screen files currently present in code tree: `85`
- Largest feature families: `partners 29`, `admin 20`, `auth 6`, `mobility 6`, `groups 5`
- Screen budget state from `docs/SCREEN_BUDGETS.md`: `1` hotspot, `7` debt screens, `36` review-range screens
- Hotspot concentration:
  - `partners`: `1` hotspot, `2` debt, `14` review
  - `admin`: `3` debt, `8` review
- Shared UI adoption:
  - `CoolScreenScaffold`: `6` screen files
  - `RayonScreenScaffold`: `12` screen files
  - `CoolScreenBackground`: `51` screen files
  - `CoolCard`: `55` screen files
  - `CoolButton`: `36` screen files
  - `CoolTextField`: `4` screen files
  - Raw `TextField`: `15` screen files
  - Raw `TextFormField`: `2` screen files
- Test posture:
  - `19` integration smoke files
  - `25` shared-widget test files
  - `9` theme-system test files
  - `1` golden suite, focused on Rayon consumer screens

## What Is Working
### 1. The design system has a real point of view
The core theme is not generic. `AppTheme`, `AppThemeText`, and `CoolSemanticColors` establish a dark-first, editorial, high-weight system with strong semantics for operational, financial, analytics, commerce, route, and proximity contexts.

Relevant sources:
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/app_theme_text.dart`
- `lib/core/theme/cool_foundations.dart`

### 2. The interface already thinks in semantic surfaces
The color model is more mature than a typical app of this size. It distinguishes command, finance, analytics, route, and contact surfaces instead of reusing one neutral card everywhere. That gives the system room to scale without feeling flat.

### 3. Navigation chrome is distinctive
The shell route uses a floating glass dock with a centered MoMo action. This is one of the most recognizable pieces of the product and should remain a signature pattern.

Relevant source:
- `lib/core/router/shell_route.dart`

### 4. Rayon is a strong controlled variant
Rayon has its own scaffold, type treatment, and brand palette, but it still shares the broader COOL spatial and structural language. This is the right kind of brand deviation.

Relevant sources:
- `lib/features/partners/widgets/rayon_screen_scaffold.dart`
- `lib/features/partners/rayon/screens/rayon_home_screen.dart`

### 5. UI quality gates exist
There is meaningful smoke, accessibility, theme, and shared-widget coverage. The system is not operating without discipline.

Relevant sources:
- `test/integration_smoke/primary_route_accessibility_test.dart`
- `test/shared/widgets/shared_theme_adaptation_test.dart`
- `test/core/theme/design_system_migration_regression_test.dart`

## Priority Findings
### P1. Page shells are fragmented across the interface
This is the main UI risk.

Evidence:
- Only `6` screen files use `CoolScreenScaffold`
- `53` screen files define `Scaffold` directly
- `45` screen files define `AppBar` directly
- `12` Rayon screens use a separate `RayonScreenScaffold`

Representative examples:
- Core shared scaffold usage:
  - `lib/features/profile/screens/profile_screen.dart`
  - `lib/features/biopay/screens/biopay_home_screen.dart`
- Hand-built consumer shells:
  - `lib/features/home/screens/home_screen.dart:65`
  - `lib/features/groups/screens/groups_screen.dart:98`
  - `lib/features/mobility/screens/mobility_home_screen.dart:201`
  - `lib/features/momo/screens/momo_screen.dart:262`
  - `lib/features/partners/screens/partners_screen.dart:52`
- Hand-built admin shells:
  - `lib/features/admin/screens/admin_dashboard_screen.dart:196`
  - `lib/features/admin/screens/operational_dashboard_screen.dart:57`

Impact:
- Inconsistent back/home affordances
- Different title starting positions and top spacing
- Different scroll containers for similar route types
- Higher chance of subtle spacing drift and safe-area bugs
- More expensive future UI polish because fixes must be screen-by-screen

Recommendation:
Create a small, enforced shell family:
- `CoreTabRootScaffold`
- `CoreDetailScaffold`
- `AdminDetailScaffold`
- `DenseAdminWorkspaceScaffold`
- `RayonDetailScaffold`

Each should standardize:
- app bar chrome
- title/subtitle block
- default scroll container
- default page padding
- background treatment
- bottom clearance behavior

### P1. Complexity debt is concentrated exactly where UI coherence matters most
The heaviest route families are partners and admin, which means the biggest surfaces also have the most room to visually drift.

Evidence from `docs/SCREEN_BUDGETS.md`:
- `rayon_home_screen_parts.dart` is the lone hotspot at `1077` LOC
- `operational_dashboard_parts.dart` is `914` LOC
- `rs_admin_initiatives_screen.dart` is `820` LOC
- `operational_dashboard_screen.dart` is `818` LOC
- `club_shop_screen.dart` is `756` LOC
- `manage_missions_screen.dart` is `713` LOC

Feature concentration:
- `partners`: `29` screens
- `admin`: `20` screens

Impact:
- Large files resist visual refactoring
- New UI debt lands in the highest-traffic implementation areas
- Section-level inconsistencies become normal because extraction cost is high

Recommendation:
Break these screens into explicit UI kits, not only helper widgets:
- command hero
- metric summary grid
- filter/search rail
- dense list row
- status chip row
- empty/loading/error stack
- section header with action slot

### P1. Form controls are not standardized enough
The product has a good field component, but it is not the default path yet.

Evidence:
- `CoolTextField` appears in only `4` screen files
- Raw `TextField` appears in `15`
- Raw `TextFormField` appears in `2`

Representative contrast:
- Shared field system:
  - `lib/features/auth/screens/register_screen.dart:274`
  - `lib/features/groups/screens/create_group_screen.dart:246`
- Raw field implementations:
  - `lib/features/admin/screens/manage_users_screen.dart:143`
  - `lib/features/auth/screens/otp_screen.dart:225`
  - `lib/features/auth/screens/otp_verify_screen.dart:337`
  - `lib/features/admin/screens/manage_quick_actions_screen.dart:373`
  - `lib/features/admin/screens/manage_vehicle_types_screen.dart:339`

Impact:
- Search bars, OTP entry, admin editors, and onboarding forms do not fully feel like one system
- Focus behavior, padding, field height, and validation treatment can drift
- Accessibility and theme adaptation become harder to enforce centrally

Recommendation:
Promote a field kit:
- `CoolTextField`
- `CoolSearchField`
- `CoolOtpField`
- `CoolAdminInlineField`
- `CoolFilterDropdown`

Use that kit everywhere instead of custom `InputDecoration` work per screen.

### P2. Visual regression coverage is too narrow for the size of the interface
The codebase has useful smoke and theme tests, but visual regression protection is concentrated in a single branded surface.

Evidence:
- Only `1` golden suite uses `matchesGoldenFile`
- That suite covers Rayon screens:
  - `RayonHomeScreen`
  - `FanClubsScreen`
  - `FanClubDetailScreen`
  - `MemberRegistryScreen`
  - `ClubShopScreen`
  - `TicketsScreen`
  - `ShopCheckoutScreen`
  - `TicketConfirmationScreen`

Relevant source:
- `test/features/partners/rayon_redesign_goldens_test.dart:271`

What is missing:
- Home
- Groups
- Mobility
- MoMo
- Profile
- Auth
- Admin root screens
- Dense admin tables/forms

Impact:
- Core product drift can land without any screenshot-level warning
- Brand polish is protected better than the everyday app shell

Recommendation:
Add golden baselines for one representative screen in each archetype:
- Home tab root
- Groups root
- Mobility root
- MoMo hub
- Profile hub
- Auth form
- Admin dashboard
- Dense admin management screen

### P2. Brand variance is healthy, but it needs explicit governance rules
Rayon is visually stronger than most other branches because it has a dedicated scaffold and brand primitives. That is good. The risk is that other partner surfaces and future branded branches may evolve without the same clarity.

Evidence:
- Core system uses Manrope and semantic COOL surfaces
- Rayon uses `RayonScreenScaffold`, Barlow/Barlow Condensed, and `RsColors`

Relevant sources:
- `lib/core/theme/app_theme_text.dart`
- `lib/features/partners/widgets/rayon_screen_scaffold.dart`
- `lib/features/partners/rayon/screens/rayon_home_screen.dart:50`

Recommendation:
Document a branch policy:
- What brand variants may override
- What they must inherit from COOL
- Which spacing, motion, and touch-target rules are non-negotiable

### P3. Background and effects layering is sometimes duplicated
Some screens are reusing the background system correctly. Others are stacking the same wash twice.

Concrete example:
- `lib/features/momo/screens/momo_screen.dart:262`
- `lib/features/momo/screens/momo_screen.dart:292`

That route wraps the screen in `CoolScreenBackground`, then applies another `CoolScreenBackground` inside the body stack. This may be intentional, but as a pattern it increases the risk of over-glow, inconsistent contrast, and brand wash buildup.

Recommendation:
Make background ownership part of the shell contract:
- shell owns background
- page content never adds another full-screen background unless it is a deliberate variant

## Interface Readiness By Product Family
### Strongest
- Rayon consumer surfaces
- Shared widgets
- Core theme and tokens

### Solid but needs shell cleanup
- Home
- Groups
- Mobility
- Profile
- MoMo

### Most likely to drift next
- Admin
- Partner non-Rayon detail screens
- Any route with dense forms or data editing

## Recommended Roadmap
### Phase 1. Standardize shells
- Build and adopt the 4 to 5 page archetype scaffolds
- Move app-bar, title, padding, and background ownership into those shells
- Migrate Home, Groups, Mobility, MoMo, Admin Dashboard first

### Phase 2. Standardize dense interaction kits
- Formalize shared search/filter/form controls
- Formalize dense admin rows and management cards
- Remove custom `TextField` and `InputDecoration` islands where possible

### Phase 3. Expand visual governance
- Add golden coverage for core non-Rayon archetypes
- Add one dense admin golden
- Add one auth form golden
- Add one tab-root shell golden in light and dark mode

## Stitch Readiness
This repo is ready for Stitch-assisted expansion, but only if prompt generation targets archetypes rather than individual one-off screens.

Use the companion design system file:
- `DESIGN.md`

Best prompt targets:
- core tab root
- core detail flow
- admin detail workspace
- dense admin data manager
- branded partner detail

## Bottom Line
The app does not need a new aesthetic. It needs stronger interface governance around shells, forms, and visual regression coverage.

The underlying design language is already good enough to scale. The current risk is that implementation patterns are scaling faster than the shared page architecture.
