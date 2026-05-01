# UI Front-End Review: Tactile Monolith Audit

Date: 2026-04-10
Last Updated: 2026-04-10 (post-remediation pass)

> **Remediation Status (2026-04-10)**
>
> The following findings from this audit have been **resolved** during the remediation pass:
>
> - ✅ **Finding #1 (Typography)**: `AppThemeText` now uses `GoogleFonts` for Space Grotesk, Manrope, Inter. Stale Lato font assets removed.
> - ✅ **Finding #2 (Glass header border)**: Reduced from 0.9 to 0.15 opacity across all screens.
> - ✅ **Finding #3 (CoolCard glass border)**: Reduced from 0.82 to 0.15 opacity.
> - ✅ **Finding #4 (Bottom sheet border)**: Reduced from 0.92 to 0.15 opacity.
> - ✅ **Finding #5 (Admin scaffold fragmentation)**: All admin screens now use AdminDetailScaffold or DenseAdminWorkspaceScaffold.
> - ✅ **Finding #6 (Profile fake glass)**: Now uses real GlassCard with BackdropFilter.
> - ✅ **Finding #7 (TabPill borders)**: Now uses tonal surfaces with no stroke.
> - ✅ **PWA palette**: Migrated from Barlow/green to Space Grotesk/violet. Borders normalized to ghost-level.
> - ✅ **CoolButton font**: Now explicitly uses Inter (label font family).
> - ✅ **Groups screen**: Card radius xl, pill buttons, branded loading state.
>
> Remaining items tracked in: `docs/ui-tactile-monolith-screen-tracker.md`

Scope:
- Flutter mobile app route tree and shared UI primitives under `lib/`
- Flutter admin route tree and admin-specific surfaces under `lib/features/admin/`
- PWA/admin panel pages and shared CSS under `apps/pwa/`

Method:
- Static implementation audit of routers, screen files, shared widgets, and page CSS
- Screen inventory built from the route tree in `lib/core/router/app_router.dart`, `lib/core/router/app_shell_branches.dart`, and `lib/core/router/admin_routes.dart`
- Page inventory built from `apps/pwa/**/*.html`
- This is not a runtime screenshot pass, so the review focuses on how the UI is implemented, themed, and composed in code

## Executive Summary

The repo does **not** currently implement one consistent "Tactile Monolith" system across the entire product.

The Flutter mobile app contains the strongest expression of the target language, especially the home shell, glass bottom navigation, and several hero or quick-action surfaces. However, the implementation is uneven: typography is documented as Space Grotesk + Manrope + Inter but is not actually wired into the Flutter `TextTheme`, several shared scaffolds still use hard borders instead of true glass headers, and multiple primitives still default to flat bordered controls instead of soft tactile surfaces.

The Flutter admin area is more fragmented. A few screens use the intended admin scaffolds, but most admin screens fall back to ad hoc `Scaffold + AppBar` implementations, which creates visible inconsistency even before comparing them to the design brief.

The PWA/admin panel under `apps/pwa/` is effectively a separate design system. It uses a different palette, different headline font family, visible borders and divider language, and a lighter editorial tone. It is internally consistent, but it is not "Tactile Monolith."

## Highest-Severity Findings

### 1. Typography authority is specified but not actually implemented

The design system explicitly depends on Space Grotesk for display/headline, Manrope for title/body, and Inter for labels. In Flutter, the typography file documents that intent, but the built `TextTheme` never assigns `fontFamily` on the text styles. It only changes sizes, weights, spacing, and color.

Evidence:
- `lib/core/theme/app_theme_text.dart:5-10`
- `lib/core/theme/app_theme_text.dart:42-157`

This means the mobile app is relying on whatever the platform/base theme resolves to, not the intended type system.

The asset side also does not support the stated typography stack. `pubspec.yaml` exposes font assets, but the repository font assets only include Lato, not Space Grotesk, Manrope, or Inter.

Evidence:
- `pubspec.yaml:17-30`
- `pubspec.yaml:111-114`
- `assets/fonts/Lato-Regular.ttf`
- `assets/fonts/Lato-Bold.ttf`

Impact:
- The single most important "Maximum Authority" lever is missing at runtime
- The visual hierarchy described in the design brief cannot be guaranteed across devices

### 2. Shared Flutter shell scaffolds break the Glass Header and No-Line rules

The common tab and detail scaffolds use a translucent app bar background, but they define separation with an explicit bottom border and do not apply a backdrop blur. That is not the requested "fixed frosted violet glass" header treatment.

Evidence:
- `lib/shared/widgets/core_detail_scaffold.dart:113-127`
- `lib/shared/widgets/core_tab_root_scaffold.dart:96-110`

Impact:
- This affects multiple screens at once because these scaffolds sit beneath major app surfaces
- Even well-designed individual screens inherit a flatter, more standard shell than the brief calls for

### 3. Shared primitives still encode a flatter bordered system

Several reusable components still default to visible borders, smaller radii, and flat surfaces that contradict the clay/glass brief.

Evidence:
- `lib/shared/widgets/cool_card.dart:9-21`
- `lib/shared/widgets/cool_card.dart:39-42`
- `lib/shared/widgets/cool_card.dart:75-108`
- `lib/shared/widgets/cool_button.dart:125-153`
- `lib/shared/widgets/cool_bottom_sheet.dart:23-41`
- `lib/shared/widgets/tab_pill.dart:17-40`

Key mismatches:
- `CoolCard` comments explicitly say "Flat borders, no claymorphism"
- `CoolButton` defaults to 8px radii in places where the design system calls for pill or large molded radii
- `CoolBottomSheet` uses explicit borders, stronger than the "ghost border fallback"
- `TabPill` relies on a visible stroke rather than separation via surface hierarchy

Impact:
- Even when a screen tries to read as premium, the shared building blocks pull it back toward a standard UI toolkit look

### 4. The PWA/admin panel is a different visual language

The PWA CSS establishes a warm neutral/green system with Barlow headlines, Manrope body, DM Mono utilities, visible borders, and a decorative 1px grid overlay. That directly conflicts with the nocturnal violet, no-line, tactile monolith system.

Evidence:
- `apps/pwa/assets/css/app.css:5-31`
- `apps/pwa/assets/css/app.css:33-69`
- `apps/pwa/assets/css/app.css:135-157`
- `apps/pwa/assets/css/app.css:272-323`
- `apps/pwa/assets/css/app.css:333-341`
- `apps/pwa/assets/css/app.css:362-370`
- `apps/pwa/assets/css/app.css:469-500`
- `apps/pwa/assets/css/app.css:541-547`

Direct conflicts with the brief:
- Barlow instead of Space Grotesk for hero/headline typography
- Green/cream palette instead of deep violet monolith palette
- Repeated explicit borders on cards, nav, buttons, list items, and brand marks
- `body::before` draws a 1px grid across the interface, which directly violates the "No-Line Rule"

Impact:
- The mobile app and PWA/admin panel do not read as one product family
- Any design system compliance claim would currently only be partial and mobile-biased

### 5. Admin UI implementation is structurally inconsistent

Only a subset of admin screens use the shared admin scaffolds. The rest build separate `Scaffold + AppBar` structures. That means the admin panel is inconsistent even before evaluating visual details.

Evidence:
- Shared admin scaffold usage:
  - `lib/features/admin/screens/admin_dashboard_screen.dart:39`
  - `lib/features/admin/screens/operational_dashboard_screen.dart:63`
  - `lib/features/admin/screens/admin_workspaces_screen.dart:42`
- Ad hoc scaffold usage:
  - `lib/features/admin/screens/manage_users_screen.dart:44`
  - `lib/features/admin/screens/manage_app_config_screen.dart:60`
  - `lib/features/admin/screens/manage_admin_roles_screen.dart:36`
  - `lib/features/admin/screens/system_analytics_screen.dart:40`
  - `lib/features/admin/screens/audit_log_screen.dart:46`
  - `lib/features/admin/screens/admin_groups_screen.dart:48`
  - `lib/features/admin/screens/bank_admin_workspace_screen.dart:52`

Impact:
- Screen-to-screen admin transitions will feel like different products or different generations of the same product
- Any attempt to harden the admin design language will be slowed down by shell fragmentation

## Where The System Is Working

These areas are the closest to the stated design brief:

1. Bottom navigation glass pill
   - `lib/core/router/shell_route.dart:101-145`
   - `lib/core/router/shell_route.dart:161-236`
   - This is one of the cleanest implementations of refined glass, ambient depth, and premium floating navigation in the repo.

2. Home quick action grid
   - `lib/features/home/widgets/home_quick_services.dart:87-149`
   - The tiles use real blur, layered highlights, generous radii, and ambient float shadows.

3. Parts of the mobile hero treatment
   - Home and splash surfaces use stronger scale, glow, and premium spacing than the rest of the app.

4. Some group and admin cards
   - Several surfaces already rely on tonal layers and generous spacing rather than crowded layouts, which is compatible with the minimalist command-center direction.

## Design-System Pillar Assessment

### Maximum Authority

Status: **Partially implemented**

What works:
- Several Flutter screens use large, bold headline scales
- Home and some admin headings have strong top-of-screen presence

What fails:
- The actual Space Grotesk / Manrope / Inter pipeline is missing in Flutter
- The PWA/admin panel uses Barlow, not Space Grotesk
- Many supporting screens fall back to medium-weight utility typography, which weakens the intended scale contrast

### Soft Tactility

Status: **Partially implemented**

What works:
- Home quick actions and some hero cards show soft ambient shadowing and rounded, molded surfaces
- Some cards use large radii that move toward the clay direction

What fails:
- The shared card system explicitly avoids claymorphism
- Inner-shadow "sunken" input and clay card treatments are not a consistent primitive
- Multiple screens still use flat outlined controls

### Refined Glass

Status: **Inconsistently implemented**

What works:
- Flutter bottom nav
- Home quick actions
- A few floating overlays

What fails:
- Shared app bars do not actually use blur-based glass headers
- Several components named as glass are not true glass surfaces
- Example: `_GlassCard` in profile is just `CoolCard(backgroundColor: colors.cardSurfaceStrong)`
  - `lib/features/profile/screens/profile_screen.dart:347-365`

### Minimalist Command Center

Status: **Mixed**

What works:
- Home and some admin dashboards use large whitespace and modular blocks effectively
- Several screens avoid dense overpopulation

What fails:
- Admin shells are inconsistent
- Groups and admin management screens often introduce extra visual noise through bordered controls and local stylistic drift
- The PWA/admin panel reads more like an editorial dashboard than a premium operational monolith

### No-Line Rule

Status: **Not consistently enforced**

What works:
- Some Flutter cards avoid dividers and rely on spacing
- Profile even comments on the no-line rule in one divider helper

What fails:
- Shared scaffolds use borders
- Buttons, chips, pills, sheets, list items, and PWA cards repeatedly use visible strokes
- The PWA background grid is a literal line-based separation system

## Screen-by-Screen Coverage Matrix

### Flutter Mobile App

| Screen | File | Alignment | Notes |
| --- | --- | --- | --- |
| Splash | `lib/features/auth/screens/splash_screen.dart` | Strong | Best early expression of cinematic brand direction and premium hierarchy. |
| Home | `lib/features/home/screens/home_screen.dart` | Strong | Strongest route-level implementation of Tactile Monolith in the app. |
| QR Scanner | `lib/shared/widgets/qr_scanner_screen.dart` | Partial | Functional full-screen utility shell; less branded and more utilitarian than the design brief. |
| Groups list | `lib/features/groups/screens/groups_screen.dart` | Partial | Solid spacing and dark surface hierarchy, but action controls drift back to outlined defaults. |
| Group create | `lib/features/groups/screens/group_create_screen.dart` | Partial | Form surface is coherent, but input and action patterns do not fully express the clay/sunken system. |
| Group detail | `lib/features/groups/screens/group_detail_screen.dart` | Partial | Reasonable hierarchy and space, but not a full tactile/glass composition. |
| Group statements | `lib/features/groups/screens/group_statements_screen.dart` | Partial | Data-forward and restrained, but closer to utility finance UI than the monolith brief. |
| Referral | `lib/core/status/screens/referral_screen.dart` | Partial | Simple and serviceable, but lighter than the stated premium editorial ambition. |
| BioPay home | `lib/features/biopay/screens/biopay_home_screen.dart` | Partial | Shares premium shell language, but does not push type and surface drama as far as home. |
| BioPay register | `lib/features/biopay/screens/biopay_register_screen.dart` | Partial | Branded enough for the feature, but input and CTA system still feel inherited from generic primitives. |
| BioPay QR | `lib/features/biopay/screens/biopay_qr_screen.dart` | Partial | Cleaner alignment than scan mode, but still not an especially tactile or layered surface. |
| BioPay scan | `lib/features/biopay/screens/biopay_scan_screen.dart` | Weak | Operational camera shell is intentionally black/white and breaks from the violet tactile system. |
| BioPay NFC | `lib/features/biopay/screens/biopay_nfc_screen.dart` | Partial | More branded than scan mode, but still lighter than the design brief. |
| BioPay success | `lib/features/biopay/screens/biopay_enrollment_success_screen.dart` | Partial | Good opportunity for a celebratory tactile finish, but implemented more conservatively. |
| Profile | `lib/features/profile/screens/profile_screen.dart` | Partial | Structure is clean, but "glass" sections are not actually glass and the surface hierarchy is flatter than intended. |
| Profile wallet | `lib/features/profile/screens/profile_detail_screens.dart` | Partial | Good informational clarity, but not strongly differentiated as a premium command surface. |
| Account details | `lib/features/profile/screens/profile_sub_screens_account.dart` | Partial | Utility-first form/detail presentation, moderate alignment only. |
| BioPay profile | `lib/features/biopay/screens/biopay_profile_screen.dart` | Not in route tree | Present in repo but not referenced from the current router inventory. |

### Flutter Admin Screens

| Screen | File | Alignment | Notes |
| --- | --- | --- | --- |
| Admin workspaces | `lib/features/admin/screens/admin_workspaces_screen.dart` | Partial | Uses shared workspace scaffold and is one of the more coherent admin entries. |
| Admin dashboard | `lib/features/admin/screens/admin_dashboard_screen.dart` | Partial to strong | Best admin implementation; closer to the "command center" direction than the rest of admin. |
| Manage users | `lib/features/admin/screens/manage_users_screen.dart` | Partial | Functionally dense and useful, but implemented via ad hoc scaffold and flatter controls. |
| Manage app config | `lib/features/admin/screens/manage_app_config_screen.dart` | Partial | Similar pattern: solid utility, weaker design-system fidelity. |
| Operational dashboard | `lib/features/admin/screens/operational_dashboard_screen.dart` | Partial to strong | One of the better matches for the operational brief, though still not fully tactile in primitives. |
| Manage admin roles | `lib/features/admin/screens/manage_admin_roles_screen.dart` | Partial | Coherent data tooling surface, but shell and controls are not consistently monolithic. |
| System analytics | `lib/features/admin/screens/system_analytics_screen.dart` | Partial | Data-forward and readable, but more conventional dashboard than tactile monolith. |
| Audit log | `lib/features/admin/screens/audit_log_screen.dart` | Partial | Utility-first audit view; intentionally plain, but outside the premium material language. |
| Admin groups | `lib/features/admin/screens/admin_groups_screen.dart` | Partial | Same issue as other management screens: solid operations UI, weaker system fidelity. |
| Bank admin workspace | `lib/features/admin/screens/bank_admin_workspace_screen.dart` | Partial | Good structural clarity, but implemented in its own shell instead of shared admin framing. |

### PWA / Admin Panel Pages

| Page | File | Alignment | Notes |
| --- | --- | --- | --- |
| PWA overview | `apps/pwa/index.html` | Weak | Consistent with PWA CSS, but not with Tactile Monolith palette, typography, or line rules. |
| Home | `apps/pwa/home/index.html` | Weak | Editorial and well-organized, but belongs to the green/cream PWA system. |
| Groups | `apps/pwa/groups/index.html` | Weak | Same system as above; repeated bordered panels and list items. |
| MoMo | `apps/pwa/momo/index.html` | Weak | Operational page, but rendered in the alternate PWA design language. |
| Profile | `apps/pwa/profile/index.html` | Weak | Clean information architecture, weak alignment to the requested brand system. |
| Notifications | `apps/pwa/notifications/index.html` | Weak | Structured well, but visually outside the target system. |
| Share | `apps/pwa/share/index.html` | Weak | Utility page, still styled via the alternate PWA system. |
| Install | `apps/pwa/install/index.html` | Weak | Same issue: cohesive internally, off-brief system-wide. |
| Offline | `apps/pwa/offline/index.html` | Weak | Good fallback UX, but still not in the target visual language. |
| Admin | `apps/pwa/admin/index.html` | Weak | The clearest "admin panel" HTML page, but it is not Tactile Monolith in palette, typography, or boundaries. |

## Concrete Implementation Notes By Surface

### Home and shell navigation

Strongest implementation in the repo.

Evidence:
- `lib/core/router/shell_route.dart:161-236`
- `lib/features/home/widgets/home_quick_services.dart:87-149`

Why it works:
- Real blur-backed glass
- Soft highlights and ambient shadows
- Large pill navigation
- Minimal chrome around key actions

### Groups

Closest to the target system in layout, but still compromised by bordered utility controls.

Evidence:
- `lib/features/groups/screens/groups_screen_sections.dart:33-39`
- `lib/features/groups/screens/groups_screen_sections.dart:68-82`
- `lib/features/groups/screens/groups_screen_sections.dart:163-173`

Why it misses:
- Visibility chip radius is too small and reads as a badge, not a smooth pebble
- Outlined primary action reintroduces line-based separation

### Profile

Composition is clean but materially flatter than advertised.

Evidence:
- `lib/features/profile/screens/profile_screen.dart:165-225`
- `lib/features/profile/screens/profile_screen.dart:347-365`

Why it misses:
- `_GlassCard` is not glass
- Rows are polished, but the section material is a standard solid card

### BioPay scan mode

Purpose-built and functional, but clearly a branded exception rather than a system-aligned state.

Evidence:
- `lib/features/biopay/screens/biopay_scan_screen.dart:454-515`
- `lib/features/biopay/widgets/biopay_scanner_shell_parts.dart`

Why it misses:
- Black shell with white borders
- More camera-tool overlay than premium violet command surface

### PWA/admin shell

Internally consistent, externally off-brief.

Evidence:
- `apps/pwa/assets/css/app.css:217-227`
- `apps/pwa/assets/css/app.css:272-323`
- `apps/pwa/assets/css/app.css:333-341`
- `apps/pwa/assets/css/app.css:491-517`

Why it misses:
- Borders are first-class primitives
- Glass is lighter and greener than the monolith brief
- The overall tone is "crafted dashboard" rather than "massive tactile authority"

## Recommended Remediation Order

### Priority 1: Fix the typography pipeline

Do this first because it changes the visual hierarchy everywhere with the smallest structural blast radius.

Actions:
- Add actual Space Grotesk, Manrope, and Inter assets or wire them through `google_fonts`
- Assign `fontFamily` at the style level in `AppThemeText.build`
- Mirror the same family roles in the PWA CSS if the PWA is supposed to share the system

### Priority 2: Replace the shared shell/header primitives

Actions:
- Convert `core_detail_scaffold.dart` and `core_tab_root_scaffold.dart` to a true glass header
- Use blur, toned glass fill, and only a low-opacity ghost edge when accessibility requires it
- Remove bottom hard borders as default shell behavior

### Priority 3: Normalize component primitives

Actions:
- Rework `CoolCard`, `CoolButton`, `CoolBottomSheet`, `TabPill`, and form controls around the design brief
- Promote large radii, tonal separation, inner-shadow input states, and pill CTAs
- Make bordered variants opt-in exceptions, not defaults

### Priority 4: Unify the admin shell

Actions:
- Move all admin screens onto shared admin scaffolds
- Establish a single command-center admin variant of Tactile Monolith
- Keep density where needed, but stop letting each admin route define its own chrome

### Priority 5: Decide whether the PWA/admin panel belongs to this design system

Right now it does not.

You need a product decision:
- Either migrate `apps/pwa/` to the same system
- Or formally document it as a separate visual language with a separate design brief

Trying to treat it as compliant with the current brief would be misleading.

### Priority 6: Define intentional exceptions

Some screens may need controlled divergence:
- Camera/scanner surfaces
- Audit-heavy admin tables
- System recovery/offline states

If those are valid exceptions, document them as such. Right now they read as drift, not policy.

## Bottom Line

If the benchmark is the supplied "Tactile Monolith" brief, the repo is **partially compliant in Flutter mobile**, **inconsistently compliant in Flutter admin**, and **not compliant in the PWA/admin panel**.

The strongest nucleus already exists in the mobile home shell and a few premium glass surfaces. The main issue is not absence of taste; it is lack of end-to-end system enforcement. Typography, shell chrome, shared primitives, and the PWA/admin stack all need to be brought under one design authority before the product will read as one coherent monolithic system.
