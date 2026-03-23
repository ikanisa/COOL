# COOL Design System

Date: 2026-03-22
Version: 1.1

## 1. Purpose

This document describes the design system that the app actually ships today.
It is a coordination document, not a competing source of truth.

If this file conflicts with implementation, code wins. The primary references
are:

- `lib/core/theme/cool_foundations.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/app_theme_text.dart`
- `lib/core/theme/cool_layout.dart`
- `lib/shared/widgets/`

Two migration notes matter:

- `CoolSemanticColors` is the target token API for all new UI.
- `CoolPalette` and `AppColors` still exist to keep older screens compiling, but
  they are migration layers, not the preferred design surface.

## 2. Product Truths

- Platform: Flutter mobile, Android-first, portrait-first.
- Theme support: `system`, `light`, and `dark` are all shipped. Invalid or
  missing stored preference falls back to `dark`.
- Localization: the app currently ships English-only. Copy budgets should still
  avoid bloated strings so future localization remains viable.
- Primary shell: `Home`, `Groups`, center `MoMo`, `Mobility`, `Profile`.
- `MoMo` is a pushed standalone route, not a shell branch.
- Payment verification is Android SMS-based. Permission, blocked, offline,
  pending, and failure states must be visually honest.
- The current visual direction is not neon black fintech. It is warm,
  institutional, tactile, and restrained.

## 3. Visual Direction

The live theme is a premium olive-and-stone system with strong typography,
rounded geometry, clay-like inline surfaces, and restrained glass overlays.

The intended feel is:

- calm, not flashy
- tactile, not glossy
- premium, not decorative
- explicit about trust, state, and money

This means:

- quiet backgrounds with controlled glow
- large, heavy type
- rounded but not bubbly geometry
- semantic color usage instead of brand-color spraying

## 4. Color System

All new UI should consume semantic tokens through `context.coolSemanticColors`.
Do not introduce raw hex values into product UI unless the use case is one of
the documented fixed-color exceptions.

### 4.1 Core Semantic Tokens

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| `appBackground` | `#F3F0EA` | `#070B09` | Root app background |
| `elevatedBackground` | `#FCFAF6` | `#0D110E` | Raised shell/sheet backdrop |
| `cardSurface` | `#F7F2EA` | `#141A16` | Default inline card surface |
| `cardSurfaceStrong` | `#FFFDF9` | `#1B221D` | Higher-emphasis card surface |
| `glassSurface` | `#FFFCF7 @ 84%` | `#111713 @ 82%` | Blur-backed overlay surface |
| `overlaySurface` | `#FBF8F2` | `#111713` | Solid overlay/sheet fallback |
| `primaryText` | `#0B0F0D` | `#F4F1E9` | Primary text |
| `secondaryText` | `#465147` | `#C4CBC2` | Secondary text |
| `tertiaryText` | `#6D776E` | `#909B91` | Muted/disabled text |
| `accent` | `#2F7252` | `#3A8A5E` | Primary action color |
| `accentStrong` | `#103322` | `#173726` | Deep accent anchor |
| `accentForeground` | `#F8F5EE` | `#F7F3EA` | Text/icons on accent surfaces |
| `divider` | `#0B0F0D @ 8%` | `#FFFFFF @ 8%` | Hairline dividers |
| `border` | `#0B0F0D @ 12%` | `#FFFFFF @ 12%` | Standard borders |
| `borderStrong` | `#0B0F0D @ 18%` | `#FFFFFF @ 20%` | Strong borders |
| `success` | `#2F7252` | `#58A67B` | Positive state |
| `warning` | `#A86F26` | `#D09A4D` | Warning state |
| `danger` | `#A24C54` | `#D0727A` | Error/destructive state |
| `info` | `#4C6886` | `#7E9CBC` | Informational state |
| `neutral` | `#737B74` | `#98A199` | Neutral supporting state |

### 4.2 Specialized Surfaces

These exist to support domain-aware cards without inventing one-off palettes:

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `operationalSurface` | `#EEF2F0` | `#0F1814` | Admin/ops surfaces |
| `financialSurface` | `#EDF4EF` | `#0E1712` | Finance summaries |
| `analyticsSurface` | `#EEF1F5` | `#101721` | Charts/analytics |
| `teamSurface` | `#F1EEF6` | `#151320` | Team/community context |
| `commerceSurface` | `#F5F0E8` | `#1A1713` | Commerce/checkout context |
| `routeSurface` | `#F1ECE4` | `#121814` | Mobility/trip context |
| `proximitySurface` | `#E7F0EA` | `#0E1813` | Nearby/location context |
| `contactSurface` | `#EAF3ED` | `#10201A` | Contact/member context |

### 4.3 Interaction and Background Tokens

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `chipBackground` | `#F1ECE3` | `#171E19` | Inactive pills/chips |
| `chipSelectedBackground` | `#E2F0E8` | `#1D3629` | Selected pills/chips |
| `buttonPrimaryBackground` | `#2F7252` | `#3A8A5E` | Primary button base |
| `buttonSecondaryBackground` | `#FCFAF6` | `#141A16` | Secondary button base |
| `inputSurface` | `#FEFBF8` | `#121814` | Text field fill |
| `shellGradientTop` | `#FAF7F2` | `#141915` | Background atmosphere |
| `shellGradientBottom` | `#ECE5DA` | `#060806` | Background atmosphere |
| `surfaceGradientTop` | `#FFFDF9` | `#1A211C` | Card gradient top |
| `surfaceGradientBottom` | `#F2ECE3` | `#0E120F` | Card gradient bottom |
| `accentGradientStart` | `#2F7252` | `#3A8A5E` | Primary CTA gradient |
| `accentGradientEnd` | `#103322` | `#173726` | Primary CTA gradient |

### 4.4 Color Rules

- Accent is for primary action, selected state, or trust-positive emphasis.
- Status must never rely on color alone; pair it with iconography, wording, or
  shape.
- Inline cards use semantic surfaces, not arbitrary gradients.
- Unsupported legacy colors from old docs such as bright teal `#00D4AA` or
  flat black `#0A0A0F` are not the current app palette.

### 4.5 Fixed-Color Exceptions

These remain intentionally hardcoded:

- QR generation and scanning: black/white for scanner reliability
- Print/PDF export: white surfaces for print fidelity
- System overlays and bars: platform-controlled black/white where required

## 5. Typography

### 5.1 Families

- Default UI family: `Manrope`
- Numeric/financial/ID family: `DM Mono` via `context.coolText.mono(...)`
- Rayon partner brand helpers:
  - `context.coolText.rayon(...)`
  - `context.coolText.rayonCondensed(...)`

### 5.2 Type Scale

The shipped scale is large and heavy by default.

| Token | Size | Weight | Letter Spacing | Intended Use |
| --- | --- | --- | --- | --- |
| `displayLarge` | 56 | w800 | -2.0 | Hero display |
| `displayMedium` | 48 | w800 | -1.6 | Large section hero |
| `displaySmall` | 40 | w800 | -1.2 | Large feature title |
| `headlineLarge` | 36 | w800 | -1.0 | Screen title |
| `headlineMedium` | 30 | w800 | -0.8 | Card/sheet title |
| `headlineSmall` | 26 | w800 | -0.5 | Subsection heading |
| `titleLarge` | 24 | w700 | -0.4 | Primary row/title |
| `titleMedium` | 22 | w700 | -0.3 | Strong secondary title |
| `titleSmall` | 20 | w700 | default | Smaller title |
| `bodyLarge` | 18 | w700 | -0.2 | Primary body |
| `bodyMedium` | 17 | w700 | -0.1 | Secondary body |
| `bodySmall` | 15 | w600 | -0.1 | Caption/meta |
| `labelLarge` | 16 | w700 | default | Prominent label |
| `labelMedium` | 15 | w700 | default | Standard label |
| `labelSmall` | 14 | w600 | 0.15 | Overline/micro label |

### 5.3 Weight Aliases

| Alias | Weight |
| --- | --- |
| `black` | w800 |
| `extraBold` | w800 |
| `bold` | w700 |
| `semibold` | w700 |
| `medium` | w600 |
| `regular` | w600 |

### 5.4 Typography Rules

- Minimum functional size is 14dp.
- The system intentionally avoids light weights; even default body styles are
  heavier than typical consumer apps.
- Financial values, counters, IDs, OTPs, and compact metrics should prefer
  `DM Mono`.
- Keep headlines short. The visual hierarchy assumes compact copy.

## 6. Spacing, Shape, Motion

### 6.1 Spacing Scale

| Token | Value |
| --- | --- |
| `x0` | 0 |
| `x1` | 4 |
| `x2` | 8 |
| `x3` | 12 |
| `x4` | 16 |
| `x5` | 20 |
| `x6` | 24 |
| `x7` | 32 |
| `x8` | 40 |
| `x9` | 48 |
| `x10` | 64 |
| `x12` | 12 |
| `x16` | 16 |

Standard insets:

- `CoolSpace.pagePadding`: `EdgeInsets.symmetric(horizontal: 24, vertical: 24)`
- `CoolSpace.sectionPadding`: `EdgeInsets.all(24)`
- `CoolSpace.denseSectionPadding`: `EdgeInsets.all(20)`
- `CoolSpace.scaffoldPadding`: `EdgeInsets.fromLTRB(24, 0, 24, 96)`

### 6.2 Layout Constants

| Token | Value | Use |
| --- | --- | --- |
| `CoolLayout.horizontalPagePadding` | 24 | Standard horizontal inset |
| `CoolLayout.verticalPagePadding` | 24 | Standard vertical inset |
| `CoolLayout.gutter` | 28 | Large section gap |
| `CoolLayout.smallSpacing` | 16 | In-card spacing |
| `CoolLayout.bottomNavHeight` | 88 | Shell chrome height |
| `CoolLayout.bottomNavMargin` | 40 | Extra clearance above shell |
| `CoolLayout.rootBottomClearance` | 128 | Root scroll padding bottom |
| `CoolLayout.fabBottomClearance` | 92 | Floating CTA clearance |

### 6.3 Radius Scale

| Token | Value |
| --- | --- |
| `xs` | 12 |
| `sm` | 16 |
| `md` | 22 |
| `lg` | 28 |
| `xl` | 32 |
| `xxl` | 36 |
| `pill` | 999 |

### 6.4 Blur, Elevation, Touch Targets

| Token | Value | Use |
| --- | --- | --- |
| `CoolBlur.subtle` | 12 | Light atmosphere |
| `CoolBlur.standard` | 18 | Standard glass surface |
| `CoolBlur.overlay` | 22 | Heavy overlay |
| `CoolElevation.resting` | 0 | Flat surface |
| `CoolElevation.raised` | 8 | Card/button layer |
| `CoolElevation.floating` | 12 | Floating controls |
| `CoolElevation.overlay` | 16 | Modal/sheet layer |
| `CoolTapTargets.minimum` | 48 | Accessibility minimum |
| `CoolTapTargets.comfortable` | 56 | Default button/control size |
| `CoolTapTargets.navigation` | 64 | Navigation controls |

### 6.5 Motion

| Token | Duration |
| --- | --- |
| `CoolMotion.press` | 110ms |
| `CoolMotion.quick` | 180ms |
| `CoolMotion.standard` | 240ms |
| `CoolMotion.emphasized` | 300ms |

Curves:

- enter: `Cubic(0.2, 0.0, 0.0, 1.0)`
- exit: `Cubic(0.4, 0.0, 1.0, 1.0)`
- press: `Curves.easeInOut`

### 6.6 Responsive Behavior

The app is portrait-locked, but the shared scaffold still has explicit width
behavior for larger devices:

- `< 600`: 24dp horizontal padding
- `600-839`: 32dp horizontal padding
- `>= 840`: 40dp horizontal padding
- `CoolResponsive.maxContentWidthForWidth(...)`: caps shared content at `720`

`CoolScreenScaffold` uses this width cap and keeps content centered inside a
single-column layout.

## 7. Navigation and Shell

### 7.1 Root Shell

The live shell is not a simple five-equal-tab bar. It is a glass dock with:

- four standard navigation destinations: `Home`, `Groups`, `Mobility`,
  `Profile`
- one empty center slot reserved for the MoMo action
- a separate center-docked MoMo `FloatingActionButton`

This matters because designs should preserve the visual dominance of the MoMo
entry point instead of treating it like an ordinary tab.

### 7.2 Navigation Chrome

Current shell treatment:

- `extendBody: true`
- dock uses `BottomNavigationBar` inside a blurred glass container
- nav blur: `CoolBlur.heavy` (`22`)
- nav radius: `CoolRadii.xl` (`32`)
- nav background: `overlaySurface` at roughly `82%` opacity
- nav shadow: `CoolShadows.glass(...)`
- nav height scales with text size from `84` to `108`
- nav labels scale from `12` to `14`

### 7.3 MoMo FAB

The center action is a distinct floating surface:

- center-docked `FloatingActionButton`
- extent scales from `60` to `70`
- shape radius: `CoolRadii.lg` (`28`)
- fill: `colors.accent`
- icon color: `colors.accentForeground`
- border: `3px` using `elevatedBackground` for separation from the dock

### 7.4 System Chrome

The app uses edge-to-edge transparent system bars:

- transparent status bar
- transparent navigation bar
- automatic light/dark icon switching by active theme
- navigation bar contrast enforcement disabled
- legacy `AppColors` brightness bridge still updates here for older screens

### 7.5 Interaction Feedback

The global theme disables default splash-heavy Material feedback:

- `NoSplash.splashFactory` at the theme layer
- component-level feedback relies on opacity, scale, border, and shadow changes
  instead of loud ripple effects

## 8. Surface Language

### 8.1 Inline Cards

`CoolCard` is the default premium inline surface.

Implementation shape:

- default radius: `CoolRadii.xl` (32)
- border: `1.1`
- fill: `colors.surfaceGradient` by default, or `colors.cardSurface`
- shadow: `CoolShadows.clay(...)`
- overlay wash: subtle highlight-to-shadow vertical wash

Use inline cards for primary content blocks, summaries, and grouped actions.

### 8.2 Overlay Cards

`CoolGlassCard` is the restrained glass surface for overlays.

Implementation shape:

- default radius: `CoolRadii.xl` (32)
- blur: `CoolBlur.standard` (18)
- opacity: `0.84` light, slightly reduced in dark mode
- border: `1.0`
- shadow: `CoolShadows.glass(...)`

Glass is for sheets and overlay moments, not for ordinary inline cards.

### 8.3 Bottom Sheets and Dialogs

Bottom sheets use a slightly stronger overlay treatment than inline glass cards:

- `CoolBottomSheet` default blur: `CoolBlur.overlay` (`22`)
- top-only radius: `CoolRadii.xxl` (`36`)
- overlay surface alpha: about `94%` dark / `98%` light
- top and side borders only
- floating shadow, not clay shadow
- standard padding: `EdgeInsets.fromLTRB(24, 14, 24, 24)`

Dialogs follow the same quiet overlay family with `CoolRadii.xl` and no noisy
surface tint.

### 8.4 Screen Backgrounds

`CoolScreenBackground` provides the atmospheric shell:

- vertical shell gradient
- accent radial glow
- secondary informational radial glow
- optional `showGlow = false` for quieter screens

This is not a flat background system. The background should feel intentional,
but the glow must stay restrained.

## 9. Core Components

### 9.1 Shared Primitives

These are the main reusable building blocks currently present under
`lib/shared/widgets/`:

- `CoolScreenScaffold`
- `CoolScreenBackground`
- `CoolCard`
- `CoolGlassCard`
- `CoolBottomSheet`
- `CoolButton`
- `CoolTextField`
- `StatusBadge`
- `SectionTitle`
- `TabPill`
- `CoolStatusCard`
- `BalanceCard`

### 9.2 Domain Cards and Utilities

The design system also includes domain-flavored shared widgets that should be
reused instead of rebuilt ad hoc:

- `GroupCard`
- `DriverCard`
- `TripCard`
- `MemberRow`
- `VehicleChip`
- `QrShareSheet`
- `WaButton`

### 9.3 Component Behavior Contracts

- Prefer existing shared widgets before creating a new one-off surface.
- Do not invent a new gradient, border recipe, or shadow if a semantic surface
  already covers the use case.
- In Flutter, components expose typed parameters, not CSS-style `className`.
  Do not document or design around web-only conventions here.
- Interactive widgets should expose semantics and meet at least the 48dp touch
  target floor.

## 10. Component Styling Details

### 10.1 Buttons

`CoolButton` is the default action control.

- variants: `primary`, `secondary`
- min height: `CoolTapTargets.comfortable` (56)
- radius: `CoolRadii.md` (22)
- press scale: `1.0 -> 0.97`
- primary uses `colors.accentGradient` and `CoolShadows.floating(...)`
- secondary uses `colors.buttonSecondaryBackground` and
  `CoolShadows.clay(...)`
- labels use large, heavy text with slight negative tracking

### 10.2 Text Inputs

`CoolTextField` is the current default text-entry surface.

- fill: `colors.inputSurface`
- radius: `CoolRadii.md` (22)
- shadow: `CoolShadows.clay(..., strength: 0.45)`
- focused border: accent, width `1.6`
- error border: danger, width `1.0` or `1.6` focused

### 10.3 Badges and Pills

- `StatusBadge` is the status primitive and already includes semantically named
  presets such as `saving`, `community`, `public`, `private`, `online`, and
  `offline`.
- `TabPill` uses chip background tokens and gains border plus clay depth only
  when active.

### 10.4 Section Headers

`SectionTitle` uses `headlineMedium` with strong weight and can pair a single
trailing text action with an accent treatment.

### 10.5 Status and Reward Surfaces

`CoolStatusCard` is a good reference for approved token bending inside the
system:

- it still composes `CoolCard`
- it narrows radius to `CoolRadii.md`
- it introduces a bounded tier-based gradient
- it uses `DM Mono` for token counts and compact stats

This is the preferred pattern for “special” surfaces: start from a shared
primitive, then bend within token limits instead of creating a wholly separate
design language.

### 10.6 Brand Exceptions

The system allows bounded brand exceptions where there is a real product or
partner requirement.

Rayon partner surfaces:

- may use `Barlow Condensed` for high-emphasis headings
- may use `Barlow` helpers through `context.coolText.rayon(...)`
- may introduce Rayon blue/gold atmosphere through `RsColors`
- still reuse shared structure, spacing, and navigation logic where possible

WhatsApp actions:

- `WaButton` intentionally uses a fixed WhatsApp green (`#2E8A57`)
- this is an external brand exception, not a general secondary action color

The rule is controlled deviation, not parallel design systems.

### 10.7 Filter and Selection Chips

`VehicleChip` is the current reference for compact filter chips:

- pill radius
- semantic selected/inactive backgrounds
- border-only emphasis when inactive
- no extra shadow or gradient noise

For same-shape segmented controls, prefer `TabPill`. For lightweight filter
selection, prefer the `VehicleChip` pattern.

### 10.8 Maps and Location Surfaces

`CoolGoogleMap` is a constrained utility surface, not a visual playground.

Current implementation behavior:

- fixed dark JSON map styling is applied as the baseline
- cloud map IDs may layer on top when configured
- zoom controls are off
- map toolbar is off
- tilt, rotation, and compass are off
- a loading placeholder covers the map until it is ready
- default target is Kigali

Design implication:

- maps should support selection and orientation, not dominate the page
- controls around maps should stay sparse and task-focused
- list and summary fallbacks remain mandatory when maps are unavailable or not
  useful for the task

### 10.9 Toasts and Transient Feedback

`CoolToast` is the preferred transient feedback primitive.

Behavior contract:

- supported variants: `success`, `error`, `info`
- success and error trigger light haptic feedback
- messages are announced to assistive tech when supported
- toast surfaces float above content with compact card styling
- error toasts remain visible longer than success/info

Design implication:

- use toasts for short confirmation or lightweight alerting
- do not use toasts for dense explanation, policy, or multi-step recovery
- if the user must act before continuing, use an inline state or sheet instead

### 10.10 Sensitive Surfaces and Error Containment

The design system includes explicit wrappers for high-trust screens.

Sensitive screen protection:

- `SecureScreenWrapper`
- `SecureScreen`
- `SecureScreenMixin`

These are intended for routes that expose financial, identity, or similarly
sensitive content where screenshot and recording protection is required.

Local crash containment:

- `CoolErrorBoundary` provides a branded subtree fallback instead of letting a
  widget-level failure collapse the whole route

Design implication:

- sensitive routes should be intentionally identified and wrapped, not protected
  ad hoc
- failure states inside expensive or risky subtrees should degrade into branded,
  actionable fallback UI instead of raw framework error output

### 10.11 Capability and Permission UX

The app does not treat permissions as a one-time setup wall. The current design
pattern is contextual permissioning with explicit user control.

Reference surfaces:

- `AppAccessOnboardingScreen`
- `ContactPickerSheet`
- `QrScannerScreen`
- `MomoSmsRationaleSheet`

Behavior contract:

- users can review permissions centrally, but permissions are still requested
  from the feature that needs them
- rationale should appear before a system dialog when the capability is
  sensitive or non-obvious
- blocked-in-system and disabled-in-app are distinct states and should remain
  visually distinct
- “Open settings” is a recovery path, not the first action
- permission messaging should explain the user benefit and the data boundary,
  not the framework API

Design implication:

- capability requests should feel reversible and contextual
- permission surfaces should prefer one clear primary action and one defer path
- do not design as if every capability is globally enabled

### 10.12 Scanner and Verification Surfaces

QR and scanner flows are treated as operational tools, not decorative camera
experiences.

Current implementation pattern from `QrScannerScreen`:

- full-screen scanner
- one dominant scan window
- limited controls
- explicit unavailable state when ticket scanning is disabled
- toast feedback for invalid scans and launch outcomes

Design implication:

- scanner screens should prioritize framing, clarity, and result handling
- if scanning cannot proceed, fall back to a clear blocked state rather than a
  half-functional camera UI
- verification outcomes should collapse quickly into a result sheet, route
  action, or explicit error state

### 10.13 Feature Gates and Temporary Unavailability

`KillSwitchGate` is the shared pattern for operationally disabled features.

Behavior contract:

- unavailable features should fail closed
- the blocked surface should state that the feature is temporarily unavailable
- users should always get an immediate exit path
- unavailable does not mean broken; the tone should be calm and explicit

Design implication:

- do not leave dead controls visible when a feature is kill-switched
- prefer a full blocked state over scattered disabled controls when the whole
  feature is unavailable

## 11. Data, Loading, and State UX

### 11.1 Async Rendering Contract

`CoolAsyncView<T>` is the preferred async screen/list wrapper for Riverpod
`AsyncValue` state.

Default behavior:

- loading renders `CoolSkeletonList`
- error renders `CoolErrorView`
- empty data can render `CoolEmptyView`
- refresh keeps stale data by default via `skipLoadingOnRefresh: true`

This is intentional. Screens should avoid flashing back to blank loading states
when a quiet refresh can preserve continuity.

### 11.2 Loading States

`CoolSkeleton` and its list/row variants are the preferred loading surfaces.

- skeletons use semantic surface gradients, not arbitrary shimmer colors
- reduced-motion users get a static placeholder instead of animated shimmer
- loading should preserve layout shape where possible

### 11.3 Empty, Error, Offline, Success

The shared state primitives already establish the preferred emotional tone:

- `CoolEmptyView`: calm, spacious, optionally premium, not apologetic
- `CoolErrorView`: direct, actionable, secondary retry by default
- `CoolStateView`: compact semantic card for loading, empty, offline, error,
  and success

Rules:

- error and offline states should expose a clear next step when one exists
- empty states may carry a primary action if it helps users start the flow
- state messaging should stay short and user-facing, never backend-facing
- live-region semantics matter for loading, error, and offline transitions

## 12. Accessibility and Trust

- Body text must remain readable in both shipped themes.
- States involving money, permissions, connectivity, and sync must be explicit.
- Placeholder-only fields are not acceptable.
- Error states should be actionable, not purely decorative.
- Buttons, badges, and toggles should remain clear without relying only on
  color.

## 13. Screen Governance

### 13.1 Route Truth

The route registry lives in `docs/ROUTE_INVENTORY.md`.

Design implication:

- route additions, removals, or major path moves are design-system events, not
  just router edits
- new user-facing routes should ship with smoke or routing coverage
- shell routes, standalone routes, and partner/admin routes should stay visibly
  distinct in purpose

### 13.2 Screen Size Budgets

Screen budgets live in `docs/SCREEN_BUDGETS.md`.

Current thresholds:

- new screens: target `<= 400`, review `401-700`, block `> 700`
- existing screens: stable `<= 700`, debt `701-1000`, hotspot `> 1000`

Design implication:

- oversized screens are usually information-architecture failures before they
  are styling failures
- if a screen is in debt or hotspot range, new work should simplify or extract
  instead of stacking more blocks into the same file

### 13.3 UI Copy Guard

Visible UI copy is guarded by `tool/ui_copy_guard.dart`.

Current implementation truth:

- the maximum guarded visible UI string length is `16` words
- this applies to literals in widgets and `lib/l10n/app_en.arb`

Design implication:

- default to short labels, short helper text, and compact error copy
- if a surface needs essay-length explanation, the structure is probably wrong

### 13.4 Route Archetypes

The current app already expresses a small set of route patterns. New screens
should usually fit one of them instead of inventing a new composition model.

Auth and entry flow:

- one dominant task
- sparse chrome
- direct progression to the next step
- no dashboard layering

Scanner and verification surface:

- camera or code utility first
- one dominant framing area
- minimal surrounding controls
- result handling immediately after scan or verification
- no decorative chrome competing with the task

Home feed:

- scroll-first
- section titles with one optional trailing action
- mixed priority cards
- lower-priority content pushed below the fold
- refreshable

List plus hero controls:

- large route title
- one hero card for filters, view mode, or primary action
- then either list content or a strong empty state
- good fit for groups-style browse/manage routes

Map plus marketplace:

- route title and short framing copy
- top actions first
- map as support surface, not the whole product
- list, preview, and WhatsApp/contact actions as the real transaction path

Secure transaction hub:

- standalone route, not shell branch
- explicit exit path
- sensitive-content protection when required
- action surfaces for pay, scan, receive, and statements
- permission and access management kept honest and adjacent to the workflow

Operational/admin dashboard:

- quiet background, low decorative atmosphere
- dense metric cards with clear sectioning
- refresh is always visible
- state cards and queues take priority over marketing or illustration

Partner-branded experience:

- partner shell and typography may bend
- core spacing, interaction patterns, and structural discipline remain shared
- brand color is an accent layer, not a license to rebuild the whole system

Detail and drill-in:

- one subject
- one primary action or next decision
- supporting facts below the fold
- good fit for ledgers, records, detail cards, and follow-up routes

Settings and account hub:

- grouped rows
- explicit toggles and management actions
- quiet summaries rather than promotional chrome
- destructive actions clearly isolated

Partner discovery and onboarding:

- browse or compare first
- trusted partner framing
- one clear next enrollment or handoff path

Admin workspace selector:

- role-aware landing surface
- clear workspace grouping
- low atmosphere, high clarity
- direct routing into task-specific admin surfaces

### 13.5 Scroll and Refresh Pattern

Most data-heavy routes follow a consistent interaction model:

- pull-to-refresh on the primary scrollable surface
- root page padding from `CoolLayout`
- clear empty/error/loading substitution rather than nested spinners
- section spacing in `12`, `14`, `20`, `24`, and `32` style steps rather than
  ad hoc values everywhere

Design implication:

- prefer one primary scroll model per route
- avoid stacking a nested scroll view, sheet, tab strip, and inline filter model
  unless the route truly needs all of them

### 13.6 Legacy Drift and Migration Queue

As of 2026-03-22, the codebase still contains meaningful legacy palette drift.

Current file count snapshot:

- `63` Dart files still reference `CoolPalette`, `context.coolPalette`, or
  `AppColors`
- `0` direct legacy palette files were found under `lib/features/home`,
  `lib/features/groups`, `lib/features/momo`, or `lib/features/admin`

Current concentration by file count:

- `lib/features/partners`: `33`
- `lib/features/profile`: `10`
- `lib/core/theme`: `8`
- `lib/features/credit`: `6`
- `lib/features/mobility`: `4`
- `lib/core/status`: `1`

Expected bridge files that may remain temporarily:

- `lib/core/theme/cool_palette.dart`
- `lib/core/theme/app_colors.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/app_theme_components.dart`
- `lib/core/theme/theme_system_chrome.dart`

Highest-value migration targets:

- Rayon consumer and Rayon admin surfaces
- profile/settings widgets and sheets
- mobility listing and driver/list marketplace widgets
- credit score and readiness surfaces
- remaining core status legacy screens

Migration rule:

- do not add new `context.coolPalette` or `AppColors` usage in feature code
- if a drift file must be touched, prefer semantic-token migration over more
  legacy styling
- treat `home`, `groups`, `momo`, and `admin` routes as current reference
  surfaces for semantic-token usage

## 14. Migration Guidance

When building or refactoring UI:

1. Start with `CoolScreenBackground`, `CoolCard`, `CoolButton`,
   `CoolTextField`, and semantic tokens.
2. Prefer `context.coolSemanticColors` and `context.coolText` over legacy
   palette access.
3. Only fall back to `CoolPalette` or deprecated `AppColors` when touching
   older screens that have not migrated yet.
4. If a new primitive is needed, add it to `lib/shared/widgets/` and update
   this file to reflect the new contract.

### 14.1 Primitive Selection Matrix

Use the smallest shared primitive that honestly fits the job.

| If you need | Prefer | Avoid by default |
| --- | --- | --- |
| Root consumer route with shared shell styling | `CoolScreenScaffold` | Ad hoc scaffold + background duplication |
| Root Rayon partner route | `RayonScreenScaffold` | Rebuilding a custom partner shell from scratch |
| Standard inline content block | `CoolCard` | Raw `Container` with custom border/shadow recipe |
| Overlay or premium modal surface | `CoolBottomSheet` or `CoolGlassCard` | Inline glass cards for ordinary list content |
| Primary or secondary action | `CoolButton` | One-off button styling in feature code |
| Text entry | `CoolTextField` | Custom `TextFormField` decoration unless there is a strong reason |
| Async data section | `CoolAsyncView<T>` | Repeating ad hoc `when(loading/error/data)` blocks everywhere |
| Inline empty/offline/error/success state | `CoolStateView` | Hand-built one-off status cards |
| Full empty route or section | `CoolEmptyView` | Copy-heavy placeholder screens |
| Full error route or section | `CoolErrorView` | Raw exception text or framework error output |
| Loading placeholder | `CoolSkeleton`, `CoolSkeletonList`, `CoolSkeletonRow` | Spinners where layout-preserving skeletons are better |
| Status pill | `StatusBadge` | Bare colored text without a shared badge treatment |
| Segmented same-shape view toggle | `TabPill` | Mixing chips, tabs, and buttons for the same choice |
| Compact filter chip | `VehicleChip` pattern | Inventing a second lightweight filter style without a reason |
| Transient confirmation/error/info | `CoolToast` | Raw `ScaffoldMessenger` usage in feature code |
| Kill-switched or temporarily unavailable feature | `KillSwitchGate` | Leaving dead controls scattered across the route |
| Sensitive route | `SecureScreenWrapper`, `SecureScreen`, or `SecureScreenMixin` | Remembering screenshot protection manually in widget code |
| Risky subtree with isolated failure risk | `CoolErrorBoundary` | Letting one widget crash collapse the full route |

### 14.2 Review Checklist

Every new or materially redesigned route should pass this checklist:

- the route clearly fits one documented archetype
- the route has one dominant task above the fold
- semantic tokens are used instead of new raw palette values
- no new `context.coolPalette` or `AppColors` usage was introduced in feature
  code
- loading, empty, and error states are explicit
- copy is compact enough to satisfy the UI copy guard
- navigation and exit paths are obvious
- permission, offline, blocked, and unavailable states are honest if relevant
- sensitive financial or identity content is protected if required
- screen size impact is acceptable against `SCREEN_BUDGETS.md`
- route changes are reflected in `ROUTE_INVENTORY.md` when applicable
- any new shared primitive is documented here

## 15. Outdated Assumptions Removed

The following older assumptions are no longer design truth and should not be
reintroduced:

- the app being dark-first only
- English/French shipping parity
- a bright teal-on-black palette
- web-style `className` expectations on Flutter widgets
- treating deprecated palettes as the preferred token system

## 16. Appendix A: Route-To-Archetype Map

This appendix maps the current route inventory onto the archetypes defined in
Section 13.

| Routes | Archetype | Notes |
| --- | --- | --- |
| `/`, `/onboarding`, `/otp`, `/otp-verify`, `/register` | `Auth and entry flow` | Sparse chrome and one dominant task per step |
| `/invite/:code` | `Detail and drill-in` | One invitation decision and one primary outcome |
| `/scanner` | `Scanner and verification surface` | Full-screen utility route with result handling |
| `/home` | `Home feed` | Mixed-priority feed with sectioned actions and refresh |
| `/groups`, `/groups/create` | `List plus hero controls` | Filter/view hero plus list or create path |
| `/groups/:id`, `/groups/:id/ledger` | `Detail and drill-in` | Focused group follow-up and ledger context |
| `/mobility` | `Map plus marketplace` | Map supports discovery, list and contact actions do the work |
| `/mobility/driver`, `/mobility/driver/subscription`, `/mobility/driver/vehicle`, `/mobility/schedule`, `/mobility/trips` | `Detail and drill-in` | Follow-up routes inside the mobility marketplace |
| `/profile`, `/profile/identity`, `/profile/travel-role`, `/profile/wallet`, `/app-access`, `/kyc/selfie` | `Settings and account hub` | Account management, permissions, identity, and wallet details |
| `/momo`, `/momo/statements` | `Secure transaction hub` | Standalone financial route with explicit exit path |
| `/credit`, `/credit/readiness`, `/missions`, `/referral`, `/tokens`, `/seasons` | `Detail and drill-in` | Supporting program routes with focused state or progression |
| `/partners`, `/partners/:id`, `/partners/:id/onboarding/:type` | `Partner discovery and onboarding` | Trusted partner browse, compare, and handoff |
| `/partners/rayon-sports`, `/partners/rayon-sports/*` | `Partner-branded experience` | Rayon-specific shell and brand bending over shared structure |
| `/admin` | `Admin workspace selector` | Role-aware landing into operational surfaces |
| `/admin/operations` | `Operational/admin dashboard` | Metrics, queues, and release truth |
| `/admin/*` except `/admin/operations` and `/admin/rayon*` | `Detail and drill-in` | Task-specific admin routes under the same operational discipline |
| `/admin/rayon*` | `Partner-branded experience` | Rayon brand system applied to admin workspaces |

## 17. Appendix B: Fast Decisions

Use this appendix when a design or implementation choice is unclear.

| Question | Default answer |
| --- | --- |
| Should this be a shell tab or standalone route? | If it is a high-trust transaction, scanner, or focused workflow, prefer standalone |
| Should this be a card or sheet? | If it interrupts or overlays the current task, use a sheet; otherwise use a card |
| Should this be glass or clay? | Glass for overlays, clay for inline surfaces |
| Should this use a map? | Only if location materially changes selection; otherwise lead with list/summary |
| Should this use a toast? | Only for short confirmation or lightweight alerting |
| Should this request permission now? | Only when the user is at the point of needing that capability |
| Should this use partner brand styling? | Only inside an approved partner experience boundary |
| Should this get a new primitive? | Only after shared primitives clearly fail the use case |
