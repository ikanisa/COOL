# Tactile Monolith Remediation Plan

Date: 2026-04-10

Related audit:
- [`docs/ui-review-tactile-monolith-audit.md`](/Volumes/PRO-G40/COOL/docs/ui-review-tactile-monolith-audit.md)

Scope:
- Flutter mobile app under `lib/`
- Flutter admin surfaces under `lib/features/admin/`
- PWA/admin panel under `apps/cool-pwa/`

Goal:
- Bring the entire UI implementation into one coherent "Tactile Monolith" system
- Remove structural drift between Flutter mobile, Flutter admin, and PWA/admin
- Fix the specific audit findings without introducing another partial, one-off visual layer

## 1. Implementation Principles

This remediation should be executed as a **system migration**, not as isolated screen polish.

Non-negotiable rules:
- Do not patch individual screens before the shared theme and primitives are fixed.
- Do not let Flutter and PWA evolve separate token definitions for the same concepts.
- Do not keep hard borders as default primitives and then try to “style around” them at the screen level.
- Do not migrate typography partially. The font pipeline must be correct first.

Execution model:
- Phase 1 fixes foundations.
- Phase 2 fixes shared shells and primitives.
- Phase 3 migrates screens in waves.
- Phase 4 adds regression protection so drift does not reappear.

## 2. Workstreams

The work is split into seven implementation workstreams:

1. Design-token and typography reset
2. Shared shell and navigation refactor
3. Primitive/component refactor
4. Flutter mobile screen migration
5. Flutter admin screen migration
6. PWA/admin visual-system migration
7. QA, regression, and governance hardening

## 3. Phase Plan

### Phase 0: Lock Scope And Establish Canonical Spec

Objective:
- Prevent rework while the migration is underway

Actions:
- Declare the current audit as the baseline reference.
- Freeze net-new visual patterns until the shared system is updated.
- Produce one canonical token spec covering:
  - color roles
  - surface hierarchy
  - typography families and scales
  - radii
  - shadow recipes
  - blur values
  - ghost-border usage
  - component state rules

Deliverables:
- Token reference doc checked into the repo
- Mapping table from current tokens to target monolith tokens
- Screen migration tracker

Suggested output files:
- `docs/ui-tactile-monolith-token-spec.md`
- `docs/ui-tactile-monolith-screen-tracker.md`

Exit criteria:
- Engineering and design agree that Flutter and PWA will both target the same system
- No open ambiguity remains around whether the PWA/admin surface is in or out of scope

### Phase 1: Foundation Reset

Objective:
- Fix the shared foundations that currently make compliance impossible

#### 1A. Typography pipeline

Problem:
- Flutter documents Space Grotesk / Manrope / Inter but does not actually apply them.

Primary targets:
- [`app_theme_text.dart`](/Volumes/PRO-G40/COOL/lib/core/theme/app_theme_text.dart)
- [`pubspec.yaml`](/Volumes/PRO-G40/COOL/pubspec.yaml)
- `assets/fonts/`
- [`app.css`](/Volumes/PRO-G40/COOL/apps/cool-pwa/assets/css/app.css)

Actions:
- Add actual font assets for:
  - Space Grotesk
  - Manrope
  - Inter
  - keep DM Mono only where utility/values require it
- Update Flutter `TextTheme` so each role explicitly sets `fontFamily`.
- Remove any dependency on implicit platform font fallback for headline/body/label roles.
- Align PWA headline font from Barlow to Space Grotesk unless a documented exception is approved.
- Define exact family ownership:
  - display/headline: Space Grotesk
  - title/body: Manrope
  - label/utility: Inter
  - mono/IDs/values: DM Mono only by exception

Acceptance criteria:
- A widget test or snapshot proves each text role resolves to the intended family
- The top-level headline on mobile, admin, and PWA all use the same headline family
- No screen relies on Lato for system UI

#### 1B. Token normalization

Problem:
- Flutter and PWA use different palettes and surface logic.

Primary targets:
- `lib/core/theme/`
- [`app.css`](/Volumes/PRO-G40/COOL/apps/cool-pwa/assets/css/app.css)

Actions:
- Define the monolith palette in one canonical token map:
  - `primary`: `#c4c0ff`
  - `primary_container`: `#8781ff`
  - `surface_container_lowest`: `#0d0a27`
  - aligned supporting surface tokens
- Encode layer semantics:
  - Layer 0: base void
  - Layer 1: structural section
  - Layer 2: interactive card
- Introduce matching token names in Flutter semantic colors and PWA CSS custom properties.
- Remove green/cream-first visual authority from the PWA.

Acceptance criteria:
- Flutter and PWA token names map 1:1 for core surface, text, and accent roles
- A reference page in both stacks can render the same sample component set with comparable tone

#### 1C. Depth recipes

Problem:
- The design brief depends on clay/glass recipes, but current shared primitives do not encode them.

Actions:
- Standardize:
  - ambient float shadow
  - glass fill opacity
  - glass blur
  - ghost-border opacity
  - inner highlight
  - inner depth shadow
- Expose them as shared token helpers in Flutter and CSS utility classes in PWA.

Acceptance criteria:
- Cards, sheets, floating nav, and modal surfaces can be built without ad hoc shadow values

### Phase 2: Shared Shell And Primitive Refactor

Objective:
- Replace the generic shell and component layer that currently causes most of the design drift

#### 2A. Shell and navigation refactor

Primary Flutter targets:
- [`core_detail_scaffold.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/core_detail_scaffold.dart)
- [`core_tab_root_scaffold.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/core_tab_root_scaffold.dart)
- [`admin_detail_scaffold.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/admin_detail_scaffold.dart)
- [`dense_admin_workspace_scaffold.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/dense_admin_workspace_scaffold.dart)
- [`shell_route.dart`](/Volumes/PRO-G40/COOL/lib/core/router/shell_route.dart)

Primary PWA targets:
- [`app.css`](/Volumes/PRO-G40/COOL/apps/cool-pwa/assets/css/app.css)
- all `apps/cool-pwa/*/index.html` page shells

Actions:
- Create a single reusable Glass Header implementation for Flutter:
  - frosted violet surface
  - heavy blur
  - optional bottom ghost edge only
  - no hard border by default
- Move all admin screens onto shared admin scaffolds.
- Make shell paddings, title spacing, and action placement consistent across mobile/admin.
- Align the PWA top bar and shell nav to the same glass treatment as the Flutter shell.

Acceptance criteria:
- No route-level screen uses a one-off `AppBar` unless explicitly approved as an exception
- The top navigation language feels like one product across Flutter and PWA

#### 2B. Component primitive refactor

Primary targets:
- [`cool_card.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/cool_card.dart)
- [`cool_button.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/cool_button.dart)
- [`cool_bottom_sheet.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/cool_bottom_sheet.dart)
- [`cool_search_field.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/cool_search_field.dart)
- [`tab_pill.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/tab_pill.dart)
- Flutter input components under shared widgets/theme
- PWA button/card/list/input CSS in [`app.css`](/Volumes/PRO-G40/COOL/apps/cool-pwa/assets/css/app.css)

Actions:
- Rework card variants:
  - default molded card
  - true glass card
  - optional outline card only as exception
- Rework buttons:
  - primary: high-gloss clay pill
  - secondary: glass pill
  - tertiary: text-only utility action
- Rework inputs:
  - sunken surface
  - inner shadow
  - violet ghost-focus border
- Rework chips/pills:
  - full pill geometry
  - no standard hard border
- Remove borders as default separators in lists and grouped settings panels.

Acceptance criteria:
- Shared components can express the design brief without screen-level overrides
- Existing screens can migrate by swapping primitives rather than custom-rebuilding everything

### Phase 3: Flutter Mobile Screen Migration

Objective:
- Recompose mobile screens on top of the corrected shells and primitives

Migration order:

#### Wave 1: Brand-defining screens

Targets:
- [`splash_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/auth/screens/splash_screen.dart)
- [`home_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/home/screens/home_screen.dart)
- [`home_quick_services.dart`](/Volumes/PRO-G40/COOL/lib/features/home/widgets/home_quick_services.dart)
- hero/home supporting widgets under `lib/features/home/widgets/`

Why first:
- These screens already contain the strongest nucleus of the target language
- They become the reference implementation for the rest of the app

Actions:
- Tighten type hierarchy using the real font stack
- Validate card, action, and shell behavior after primitive refactor
- Capture goldens/screenshots to serve as style references

Acceptance criteria:
- Home becomes the canonical visual benchmark for the system

#### Wave 2: Groups and contribution surfaces

Targets:
- [`groups_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/groups/screens/groups_screen.dart)
- [`groups_screen_sections.dart`](/Volumes/PRO-G40/COOL/lib/features/groups/screens/groups_screen_sections.dart)
- [`group_create_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/groups/screens/group_create_screen.dart)
- [`group_detail_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/groups/screens/group_detail_screen.dart)
- [`group_statements_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/groups/screens/group_statements_screen.dart)
- [`referral_screen.dart`](/Volumes/PRO-G40/COOL/lib/core/status/screens/referral_screen.dart)

Actions:
- Replace bordered actions with pill CTAs and tonal grouping
- Normalize chips/badges to pebble/pill style
- Increase contrast between headline and supporting copy
- Remove any remaining divider-line thinking from grouped content sections

Acceptance criteria:
- Groups UI reads as part of the same premium financial command language as Home

#### Wave 3: Profile surfaces

Targets:
- [`profile_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/profile/screens/profile_screen.dart)
- [`profile_detail_screens.dart`](/Volumes/PRO-G40/COOL/lib/features/profile/screens/profile_detail_screens.dart)
- [`profile_sub_screens_account.dart`](/Volumes/PRO-G40/COOL/lib/features/profile/screens/profile_sub_screens_account.dart)

Actions:
- Replace fake glass sections with true glass or molded grouped surfaces
- Standardize icon tiles, row spacing, and section grouping
- Normalize settings groups to the no-line rule via spacing and layered surfaces

Acceptance criteria:
- The profile area no longer mixes naming like “glass” with non-glass implementation

#### Wave 4: BioPay static flows

Targets:
- [`biopay_home_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/biopay/screens/biopay_home_screen.dart)
- [`biopay_register_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/biopay/screens/biopay_register_screen.dart)
- [`biopay_qr_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/biopay/screens/biopay_qr_screen.dart)
- [`biopay_nfc_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/biopay/screens/biopay_nfc_screen.dart)
- [`biopay_enrollment_success_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/biopay/screens/biopay_enrollment_success_screen.dart)

Actions:
- Bring static BioPay screens into the same shell and type authority as core mobile
- Use more deliberate asymmetry and scale contrast where appropriate

Acceptance criteria:
- BioPay static flows look like a specialized feature inside the same product, not a sidecar flow

#### Wave 5: BioPay scanner and camera exceptions

Targets:
- [`biopay_scan_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/biopay/screens/biopay_scan_screen.dart)
- scanner shell widgets under `lib/features/biopay/widgets/`
- [`qr_scanner_screen.dart`](/Volumes/PRO-G40/COOL/lib/shared/widgets/qr_scanner_screen.dart)

Actions:
- Define an explicit “camera-mode exception” spec:
  - reduced chrome
  - still branded typography and accent behavior
  - no generic white-border overlay controls unless justified
- Retain camera legibility while aligning buttons, banners, and overlays with the system

Acceptance criteria:
- Scanner mode is a documented exception, not uncontrolled drift

### Phase 4: Flutter Admin Migration

Objective:
- Convert admin from a set of mixed implementations into one coherent command-center experience

Migration order:

#### Wave 1: Admin shell unification

Targets:
- [`admin_dashboard_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/admin_dashboard_screen.dart)
- [`operational_dashboard_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/operational_dashboard_screen.dart)
- [`admin_workspaces_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/admin_workspaces_screen.dart)
- [`manage_users_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/manage_users_screen.dart)
- [`manage_app_config_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/manage_app_config_screen.dart)
- [`manage_admin_roles_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/manage_admin_roles_screen.dart)
- [`system_analytics_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/system_analytics_screen.dart)
- [`audit_log_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/audit_log_screen.dart)
- [`admin_groups_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/admin_groups_screen.dart)
- [`bank_admin_workspace_screen.dart`](/Volumes/PRO-G40/COOL/lib/features/admin/screens/bank_admin_workspace_screen.dart)

Actions:
- Eliminate route-level ad hoc `Scaffold + AppBar` implementations
- Ensure one header pattern, one content-width strategy, one action placement model
- Introduce one admin density variant that still follows Tactile Monolith

Acceptance criteria:
- All admin screens inherit the same chrome and spacing rules

#### Wave 2: Command-center component language

Actions:
- Build admin-specific variants only where density requires them
- Keep:
  - large headline authority
  - glass header
  - layered surfaces
  - no hard dividers as default
- For tables and logs, allow exception patterns but keep border use low-opacity and deliberate

Acceptance criteria:
- Admin feels operational and premium, not generic enterprise utility

### Phase 5: PWA / Admin Panel Migration

Objective:
- Bring the web surface into the same system instead of leaving it as an alternate brand

Primary targets:
- [`app.css`](/Volumes/PRO-G40/COOL/apps/cool-pwa/assets/css/app.css)
- [`index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/index.html)
- [`home/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/home/index.html)
- [`groups/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/groups/index.html)
- [`momo/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/momo/index.html)
- [`profile/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/profile/index.html)
- [`notifications/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/notifications/index.html)
- [`share/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/share/index.html)
- [`install/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/install/index.html)
- [`offline/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/offline/index.html)
- [`admin/index.html`](/Volumes/PRO-G40/COOL/apps/cool-pwa/admin/index.html)

Actions:
- Replace Barlow headline usage with Space Grotesk.
- Replace green/cream-first color tokens with monolith violet tokens.
- Remove the global grid-line overlay.
- Rebuild:
  - card surfaces
  - button recipes
  - shell nav
  - topbar
  - list items
  - status pills
  - form controls
- Keep HTML structure where possible, but do not preserve old CSS primitives if they block system parity.

Recommended approach:
- Introduce a staged CSS migration:
  - `app.css` token reset
  - shell primitives
  - component class updates
  - page-specific cleanups

Acceptance criteria:
- A user moving from mobile screenshots to PWA pages sees one design language, not two

### Phase 6: Regression Protection And QA

Objective:
- Prevent the repo from falling back into mixed-system drift

Actions:
- Add Flutter golden tests for:
  - home shell
  - grouped settings panel
  - primary/secondary/tertiary buttons
  - glass header
  - admin dashboard shell
- Add PWA screenshot-based visual regression for:
  - overview
  - home
  - groups
  - admin
- Add lint or review checks for anti-patterns:
  - new visible 1px borders in shared components
  - use of wrong headline font
  - ad hoc app bars in admin
- Add a lightweight design review checklist to PR templates.

Acceptance criteria:
- New regressions are caught automatically before merge

## 4. Suggested Execution Order

Recommended order:

1. Phase 0 spec lock
2. Phase 1 typography and token reset
3. Phase 2 shared shell and primitive refactor
4. Flutter mobile Wave 1 and Wave 2
5. Flutter profile and BioPay static flows
6. Flutter admin shell unification
7. PWA/admin migration
8. Scanner/exception cleanup
9. Regression hardening

Rationale:
- Shared foundations and primitives produce the biggest payoff
- Home and Groups become the reference before deeper admin and PWA work
- Admin and PWA should be migrated after the reusable system is stable

## 5. Ownership Model

Recommended owner split:

- Design system owner
  - token spec
  - typography
  - component recipes
  - acceptance criteria

- Flutter UI owner
  - `lib/core/theme/`
  - shared Flutter widgets
  - mobile/admin route migration

- PWA UI owner
  - `apps/cool-pwa/assets/css/`
  - page template migration
  - web visual regressions

- QA owner
  - golden tests
  - screenshot regression
  - accessibility checks

## 6. Acceptance Criteria By Finding

### Finding: typography not wired

Done when:
- Flutter display/headline/title/body/label roles resolve to explicit families
- PWA headline family matches the canonical system
- old fallback family usage is removed from primary UI surfaces

### Finding: shared shell violates glass-header rule

Done when:
- shared Flutter shells use true blur-backed glass
- hard bottom borders are removed as default behavior
- PWA topbar and nav follow the same visual logic

### Finding: shared primitives are flat/bordered

Done when:
- shared cards, buttons, inputs, chips, bottom sheets, and grouped panels no longer rely on standard hard borders
- border-based separation is exception-only

### Finding: admin shell is inconsistent

Done when:
- every admin route inherits shared admin scaffolding
- no admin screen uses a custom route-level shell without explicit exception approval

### Finding: PWA is a different design system

Done when:
- tokens, typography, surface layering, and separation rules match the monolith spec
- the PWA no longer reads as a green editorial system

### Finding: scanner is uncontrolled exception

Done when:
- scanner mode has a documented exception variant
- overlays, buttons, banners, and helper states remain branded and system-aware

## 7. Definition Of Done

The remediation is complete only when all of the following are true:

- Flutter mobile, Flutter admin, and PWA/admin share the same token language
- The correct typography stack is live everywhere
- Shared shells and components enforce the design system by default
- All routed screens in Flutter have been migrated or explicitly documented as exceptions
- All `apps/cool-pwa` pages have been migrated or explicitly documented as exceptions
- Golden/screenshot regression protection exists for the key surfaces
- The audit findings in [`ui-review-tactile-monolith-audit.md`](/Volumes/PRO-G40/COOL/docs/ui-review-tactile-monolith-audit.md) can be marked closed one by one

## 8. Immediate Next Actions

The next implementation step should be:

1. Create the canonical token spec and screen tracker.
2. Wire the real typography stack in Flutter and PWA.
3. Refactor the shared shell/header primitives.
4. Refactor shared cards/buttons/inputs/chips.
5. Migrate Home as the canonical reference screen.

If those five steps are done correctly, the rest of the migration becomes mostly systematic rather than interpretive.
