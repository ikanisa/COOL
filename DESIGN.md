# Universal App Design Standard 2026

This document is the single design authority for this repository. Any production mobile app, Flutter TV app, admin panel, Flutter-first web shell, native iOS or Android app, React Native app, or embedded app surface must use this file as its design contract. No secondary design folder, screenshot parity matrix, token JSON, design-system markdown, source-variant asset folder, provenance note, or archived design report may override this standard.

This standard is built from current platform guidance, local implementation evidence, and the supplied Revolut reference screenshot grammar. The screenshot base is mandatory as a quality and interaction target: dark immersive shells, compact command chrome, large first-viewport value, circular quick actions, restrained copy, translucent panels, stable navigation, and premium state handling. Product teams must adapt those lessons to their truthful domain, roles, data, permissions, and compliance boundaries.

## Universal Design Goal

Build a world-class product suite that feels calm, fast, premium, trustworthy, and task-focused across mobile, TV, and admin surfaces. The interface should combine modern fintech-grade polish with universal product patterns: compact hierarchy, confident typography, thumb-first and remote-first actions, resilient state handling, motion that clarifies changes, inclusive accessibility, and adaptive layouts that scale from small phones to tablets, foldables, desktop shells, large-screen TVs, and dense operator consoles.

The standard is intentionally universal. Product teams must replace domain examples with their own truthful product data, but must keep the system principles, token model, component contracts, state requirements, quality gates, and Flutter implementation rules.

## Source Evidence And Research Baseline

This file is grounded in these evidence inputs:

- Local reference screenshots: `/Volumes/PRO-G40/MEMORIES/tmp/revolut10-contact-sheet.png`, a contact sheet of Revolut reference captures that shows account, invest, payments, crypto, rewards, analytics, contact detail, and profile surfaces.
- Local implementation evidence: `/Volumes/PRO-G40/COOL/DESIGN.md`, COOL route/admin screenshots under `.cache/repo_wide_qa_uat/`, and COOL token seeds in `lib/app/theme/collect_colors.dart`.
- Prior comparative audits: MOBI Revolut comparison docs under `/Volumes/PRO-G40/MOBI/mobi_app/docs/product/`, especially the reference-gap and Flutter/admin audit reports.
- Current platform guidance checked on 2026-07-02: Flutter adaptive/responsive design, Flutter accessibility, Flutter focus and shortcuts, Apple Human Interface Guidelines, Apple tvOS HIG, Android TV design/navigation, Material 3 adaptive navigation, and WCAG 2.2.

Authoritative external references:

- Flutter adaptive and responsive design: https://docs.flutter.dev/ui/adaptive-responsive
- Flutter accessibility: https://docs.flutter.dev/ui/accessibility
- Flutter focus system: https://docs.flutter.dev/ui/interactivity/focus
- Flutter Actions and Shortcuts: https://docs.flutter.dev/ui/interactivity/actions-and-shortcuts
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Apple tvOS design: https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos
- Android TV design: https://developer.android.com/design/ui/tv
- Android TV navigation: https://developer.android.com/training/tv/get-started/navigation
- Material 3 navigation rail: https://m3.material.io/components/navigation-rail/overview
- WCAG 2.2: https://www.w3.org/TR/WCAG22/

## Reference Screenshot Lessons

The Revolut screenshot base defines the required interaction grammar for this system. It is not optional inspiration; it is the benchmark for density, hierarchy, motion, contrast, command chrome, navigation, and polish. Use it to extract durable UI rules while replacing all product data, copy, regulated claims, brand marks, icons, and unsupported flows with truthful product-owned content.

The visible reference grammar is:

- Put the primary user value in the first viewport.
- Use a saturated top gradient that resolves into a near-black lower shell when the product surface benefits from a premium immersive frame.
- Keep top chrome compact: avatar or identity marker, black search pill, and one or two circular command actions.
- Use one dominant hero value, object, title, or identity moment before secondary lists.
- Prefer four or fewer circular quick actions with short labels and clear icon roles.
- Prefer icon-led metadata, concise labels, and readable numbers over verbose instruction blocks.
- Use full-width dark translucent panels with restrained borders for grouped content.
- Use cards for repeated items and framed tools, not for every page section.
- Use white, black, or tonal pill CTAs before saturated rectangular buttons unless a semantic status requires color.
- Keep bottom navigation floating, dark, stable, thumb-accessible, and branch-preserving where depth requires it.
- Make empty, loading, offline, error, disabled, selected, pressed, focused, and permission states feel designed rather than bolted on.
- Use background, elevation, blur, opacity, and tonal contrast to separate zones without visual noise.
- Make every screen feel production-ready in both light and dark mode, even if the primary brand expression is dark-first.

The screenshot base also defines what not to do:

- Do not fill screens with explanatory copy when a hero, action row, chip, or state panel can carry the meaning.
- Do not create generic Material pages that ignore the immersive shell.
- Do not mix an unrelated light/blue product subsystem into the same app unless the surface has an explicit, tokenized reason.
- Do not add fake finance, crypto, rewards, card, or regulated product concepts to mimic a reference screenshot.
- Do not use decorative gradients, cards, or glass effects without a role in hierarchy, state, or navigation.

## Screen Archetypes

Every app must define and implement these Screen Archetypes before feature work is considered complete:

- Home or dashboard: a compact overview with the user's next best action and current state.
- Detail screen: a focused object view with clear status, metadata, history, and primary actions.
- List or feed: scan-friendly rows or cards with filtering, sorting, pagination or lazy loading, and empty states.
- Create or edit flow: progressive fields, validation, save states, draft safety, and cancellation handling.
- Search and discovery: query input, recent items, filters, loading, empty, and no-results states.
- Transaction or checkout flow: amount, counterparty, review, confirmation, failure recovery, and receipt.
- Profile and settings: identity, preferences, privacy, security, notifications, support, and legal links.
- Permissions and onboarding: minimal steps, clear value, deny/retry paths, and no dark patterns.
- Notifications and inbox: grouped events, read/unread states, actions, and deep links.
- Help and support: self-serve answers, contact options, incident states, and escalation.
- Offline and recovery: cached data, retry affordances, sync status, and conflict handling.
- Admin or operator screens, if present: dense, accessible, auditable, and visually separate from consumer mobile surfaces.
- TV home: remote-first content or action hub with clear focused item, large readable hierarchy, and no dependence on touch gestures.
- TV detail: 10-foot object view with focus-safe actions, large media or state preview, and predictable back behavior.
- Admin dashboard: dense operational overview with key metrics, alerts, filters, and one clear next action.
- Admin list and queue: sortable, filterable, paginated, auditable records with bulk actions and detail panels.
- Admin detail and audit trail: object state, owner, risk, history, permissions, attachments, and reversible operator actions.

## Cross-Surface Product Architecture

Mobile, TV, and admin must share one semantic design system while serving different jobs:

- Flutter mobile app: consumer or field-user experience. Prioritize thumb reach, compact command chrome, first-viewport value, quick actions, protected routes, offline/retry states, and native Android/iOS behavior.
- Flutter TV app: living-room or shared-screen experience. Prioritize D-pad focus, 10-foot readability, large focus states, remote shortcuts, horizontal content rows, safe overscan margins, and minimal text entry.
- Admin panel or Admin PWA: operator experience. Prioritize density, scanning, filtering, auditability, permission clarity, bulk action safety, keyboard support, and desktop/tablet responsiveness.

Shared rules:

- All surfaces use the same semantic tokens, typography scale, icon roles, motion durations, status taxonomy, and accessibility requirements.
- Consumer mobile and TV surfaces must never expose admin-only routes, data, permissions, or affordances.
- Admin surfaces may be denser than mobile, but they must still use the same premium dark shell grammar, concise copy, stable navigation, tokenized panels, and designed states.
- A feature is not design-complete until its mobile, TV where applicable, and admin/operator implications are either implemented or explicitly marked not applicable in this file or the product source of truth.

## Design Principles

- Clarity first: a user should understand the screen's purpose in three seconds.
- Compact but breathable: use dense information hierarchy without cramping touch targets.
- One primary action per screen state: secondary actions may exist, but the main path must be obvious.
- Real data over decoration: imagery, icons, and motion must clarify product state or emotion.
- Trust through restraint: use consistent tokens, predictable patterns, and strong feedback.
- Local-first respect: design for language length, currency, region, network reliability, and device class.
- Privacy by default: mask sensitive values and avoid exposing private identifiers in UI, logs, screenshots, and analytics.
- Accessibility is structural: accessible text, focus, contrast, semantics, and reduced motion are built into components.
- Performance is a design feature: loading, animation, scroll, and input latency must feel immediate.
- The app must work before it explains itself: do not add visible instructional copy when state, layout, or action labels can carry the meaning.

## Universal Token Model

The Universal Token Model is the only approved way to express visual style. Product code must consume semantic tokens rather than hardcoded colors, radii, shadows, text styles, durations, or spacing.

### Color Tokens

- `color.background.canvas`: base app canvas.
- `color.background.elevated`: elevated surfaces.
- `color.background.overlay`: modal, sheet, and scrim overlays.
- `color.surface.default`: cards, panels, list containers.
- `color.surface.strong`: stronger grouped surfaces.
- `color.surface.glass`: translucent surfaces when supported.
- `color.text.primary`: main readable text.
- `color.text.secondary`: supporting text.
- `color.text.muted`: low-emphasis text that still passes contrast.
- `color.text.inverse`: text over dark or accent fills.
- `color.border.subtle`: dividers and quiet outlines.
- `color.border.strong`: selected, focused, or emphasized outlines.
- `color.action.primary`: main action.
- `color.action.secondary`: secondary action.
- `color.action.destructive`: destructive action.
- `color.status.success`, `warning`, `danger`, `info`, `neutral`: semantic status roles.
- `color.focus.ring`: visible focus outline.

Each token must have Light mode and Dark mode values. High contrast mode should increase contrast without changing product meaning.

### Reference Palette Seeds

These seed colors define the default premium reference family. Teams may adapt hue for their brand, but the roles and contrast relationships must remain intact:

- Deep chrome black `#050510`: bottom navigation, command pills, modal chrome, TV focus backplates, and admin shell rails.
- Immersive ink `#252044`: deep background, admin shell depth, dark text on pale export surfaces.
- Account blue `#0818A0`: high-energy account or primary-value gradient stops.
- Deep account navy `#000840`: top gradient depth and account-value hero fields.
- Payments purple `#181038`: primary dark app canvas and payment/action zones.
- Deep payments purple `#100820`: lower-shell depth, cards behind hero sections, grouped dark panels.
- Rewards violet `#7050E8` and hot violet `#9838F0`: reward, upgrade, or accent gradients when the product owns that meaning.
- Wealth teal `#204050`: invest, growth, or calm informational zones where applicable.
- Paper `#FAF8F5`: high-contrast pill CTA fill, export canvas, QR backgrounds, and readable inverse surfaces.
- Mint success `#3CD070`, orange-red warning/danger `#FF5E43`, dusty rose `#D38B96`, and periwinkle `#8885F0`: semantic accent seeds, not page-wide decoration.

Implementation rule: code must expose these as semantic roles such as `color.chrome.default`, `color.hero.gradientStart`, `color.hero.gradientEnd`, `color.surface.glass`, `color.action.pill`, `color.tv.focus`, and `color.admin.rail`, not as feature-screen hardcoded literals.

### Typography Tokens

- `type.display`: only for true hero or high-value first-viewport moments.
- `type.title.lg`, `type.title.md`, `type.title.sm`: screen and section hierarchy.
- `type.body.lg`, `type.body.md`, `type.body.sm`: readable content.
- `type.label.lg`, `type.label.md`, `type.label.sm`: controls, chips, tabs, badges.
- `type.number.lg`, `type.number.md`, `type.number.sm`: financial, metric, timer, count, and score values.
- Letter spacing is `0` unless a platform text style requires otherwise.
- Do not scale font size with viewport width. Use responsive layout, wrapping, truncation, or alternate component density.

### Spacing And Shape Tokens

- Base spacing step is 4 dp; common values are 4, 8, 12, 16, 20, 24, 32, 40, 48.
- Icon buttons are at least 44 x 44 dp; primary touch targets are at least 48 x 48 dp.
- Cards use 8 dp radius or less unless a platform-native component requires a larger shape.
- Large decorative rounded rectangles must not become the default layout language.
- Use aspect ratio, min/max constraints, and stable dimensions for boards, grids, counters, tiles, and toolbars.

### Elevation, Blur, And Motion Tokens

- Elevation must reflect interaction depth, not decoration.
- Blur is allowed only where readability and performance are proven.
- Motion durations: `fast` 120-180 ms, `standard` 200-280 ms, `slow` 320-420 ms.
- Motion easing should be platform-native or cubic standard; avoid bounce effects in serious workflows.
- Reduced motion replaces spatial transitions with fades, opacity, and instant layout changes.

## App Shell Standard

- The app opens directly into the usable product experience, not a marketing landing page.
- Top chrome is compact: account/profile, title or search, and one or two contextual actions.
- Bottom navigation is stable for primary destinations; nested flows preserve branch state where possible.
- Use tabs, segmented controls, menus, toggles, sliders, steppers, and icon buttons according to familiar mobile patterns.
- Avoid visible in-app text that describes UI features, keyboard shortcuts, visual styling, or how to use the app.
- Skeletons and optimistic updates must preserve layout stability.
- Sheets, dialogs, snackbars, toasts, and banners must have clear severity and recovery behavior.
- Destructive or irreversible actions require review, confirmation, or undo according to risk.

## Universal Component Library

The Universal Component Library is the minimum component inventory for any production app:

- App shell: top bar, bottom nav, side rail for large screens, safe-area wrapper, keyboard-aware scaffold.
- Buttons: primary, secondary, tertiary, destructive, icon-only, split, loading, disabled.
- Inputs: text, number, money, phone, email, password, date, time, search, multiline, OTP, file/media picker.
- Selection: checkbox, radio, switch, segmented control, chips, tabs, menus.
- Feedback: banner, snackbar, toast, inline validation, progress indicator, skeleton, empty state, error state.
- Data display: list row, card, table row, metric, avatar, badge, timeline, receipt, activity item.
- Navigation: list item, breadcrumb for large screens, back button, deep-link recovery, route transition.
- Overlays: dialog, bottom sheet, popover, action sheet, command menu.
- Media: image, video thumbnail, document preview, avatar, icon, QR or barcode surface if relevant.
- Security and privacy: masked value, reveal control, session timeout, permission prompt, consent review.
- Semantic icons: every repeated metadata concept must use one stable semantic icon role, not one-off artwork.

Each component must define default, hover where applicable, focused, pressed, selected, disabled, loading, success, warning, error, empty, offline, permission denied, and skeleton states.

## State Requirements

Every screen and reusable component must cover these State Requirements:

- Loading: skeleton or progress that preserves layout and labels the pending action for assistive tech.
- Empty: clear zero-data state with one useful next action.
- Error: human-readable cause, retry, support, and technical trace only where safe.
- Offline: cached content where possible, sync status, retry, and clear disabled network actions.
- Permission denied: explain consequence, provide settings path, and keep alternate routes usable.
- Disabled: visible, semantic, and accompanied by context when the reason is not obvious.
- Focused: visible focus ring for keyboard, switch, screen reader, and desktop modes.
- Pressed: immediate tactile visual feedback.
- Selected: persistent state with semantic selection labels.
- Large text: layouts survive at least 200 percent text scale without overlap.
- Reduced motion: all motion-heavy transitions have a reduced alternative.
- Dark mode: intentional token values, not inverted light mode.
- Light mode: complete parity with dark mode.
- Syncing: nonblocking progress for background refresh.
- Conflict: explicit resolution UI for stale or conflicting data.
- Security timeout: predictable locked or re-auth state.

## Responsive And Adaptive Standard

The responsive contract covers these viewport bands:

- 320-374 dp: compact phones. Single-column layout, shorter labels, no text overlap, no horizontal scrolling except intentional carousels.
- 375-430 dp: standard phones. Primary optimized design target.
- 431-599 dp: large phones. Add breathing room without stretching controls.
- 600-719 dp: small tablets and foldable half-screen. Consider two-pane layouts only when hierarchy improves.
- 720+ dp: tablets, foldables, desktop shells. Use adaptive columns, side rails, persistent secondary panes, and larger hit areas.
- Landscape: preserve primary task flow, keyboard safety, and top/bottom chrome stability.
- Foldables: avoid hinge-obscured content, support posture changes, and preserve route state.
- Keyboard open: inputs remain visible with error text and submit controls reachable.

No text, icon, media, chip, badge, or button label may overlap or overflow its parent in these bands.

## Flutter TV Standard

Flutter TV surfaces must be designed as 10-foot, remote-first products rather than stretched mobile screens.

### TV Layout

- Primary canvas targets are 1280 x 720 and 1920 x 1080, with safe margins that keep important content away from screen edges.
- The first viewport must show the current focus, the selected object or value, and the next likely action without scrolling.
- Prefer horizontal rows, rails, carousels, and large tiles over long vertical forms.
- Use stable row heights, tile aspect ratios, and focus-safe spacing so scale effects do not cause layout shifts.
- Text must remain readable from a living-room distance: larger titles, fewer lines, stronger contrast, and no small helper copy.
- Avoid dense tables, small chips, text-entry-heavy workflows, hover-only affordances, and hidden gestures.

### TV Focus And Remote Interaction

- Every interactive element must be reachable by D-pad, arrow keys, select/enter, and back.
- The focused item must be visually obvious through scale, outline, elevation, glow, or tonal change; color alone is not enough.
- Focus traversal must follow spatial layout and preserve focus memory when returning to a row, tab, or detail surface.
- Back returns to the previous view or parent surface without losing context.
- Search and text entry must offer voice input, recent queries, suggestions, QR handoff, or mobile companion entry where possible.
- Remote shortcuts must be implemented through Flutter focus, `Shortcuts`, and `Actions`, with tests for directional navigation.

### TV State And Performance

- Loading states must reserve tile sizes and row positions.
- Empty and error states must have one large primary recovery action.
- Media, images, and previews must have placeholders and error fallbacks.
- Scrolling must be virtualized for large rows and never jank under remote repeat input.
- Reduced motion replaces parallax, scale, and spatial transitions with simpler focus outlines and fades.

## Admin Panel Standard

Admin panels must use the same premium design system without pretending to be consumer mobile screens. The goal is calm operational density: fast scanning, strong hierarchy, safe actioning, and complete auditability.

### Admin Information Architecture

- Use a persistent side rail or sidebar on desktop and tablet, with compact top chrome for account, search, alerts, and command actions.
- Use bottom navigation only on narrow admin mobile fallback views, and only for essential admin destinations.
- Organize around queues, records, dashboards, reports, audit logs, settings, and support tools.
- Keep list surfaces summary-first; move detail, history, permissions, and destructive actions into a detail panel, drawer, sheet, or route.
- Separate consumer/user flows from admin/operator flows in route guards, navigation, copy, analytics, screenshots, and tests.

### Admin Data Surfaces

- Tables must support sorting, filtering, search, pagination or virtualization, column priority, empty/error/loading/offline states, and keyboard navigation.
- Compact card/list mode is required below tablet width; columns must not squeeze until text overlaps.
- Bulk actions require selection count, scope summary, permission check, review step, undo or confirmation, and audit event.
- Metrics must show label, value, trend, time window, freshness, and failure/degraded state.
- Audit logs must be readable by default, with raw JSON or technical metadata collapsed behind an explicit control.

### Admin Visual Language

- Use dark immersive shell, translucent panels, concise headers, chips, badges, and pill controls from the shared system.
- Admin may use higher density and stronger grid alignment, but it must not use unrelated colors, shapes, table styles, or modal patterns.
- Primary destructive actions must never sit visually next to harmless actions without a confirmation pattern.
- Admin routes must include permission denied, unauthenticated, out-of-role, stale data, partial failure, empty queue, and high-volume states.

## Accessibility Standard

- Meet WCAG 2.2 AA contrast for text and meaningful UI controls.
- Support screen readers with meaningful labels, roles, values, hints, and traversal order.
- Every icon-only button has a semantic label and tooltip where applicable.
- Focus order follows visual and task order.
- Touch targets are at least 48 dp, with 44 dp as the minimum only for dense icon controls.
- Dynamic type must preserve layout at 200 percent text scale.
- Color is never the only way to convey state.
- Error messages are programmatically associated with fields.
- Motion respects reduced motion settings.
- Haptics must not be required to understand state.
- Forms support autofill, platform keyboards, input masks, and validation timing appropriate to field risk.

## Visual QA Standard

Visual QA Standard gates must include:

- route screenshot coverage for every production route and critical modal/sheet state.
- golden or snapshot tests for shared components and design tokens.
- light and dark screenshots for all primary screen archetypes.
- small phone, standard phone, large phone, tablet, landscape, and keyboard-open screenshots.
- TV screenshots for 720p, 1080p, focused, unfocused, row-scrolled, detail, search, empty, loading, error, and reduced-motion states where a TV surface exists.
- Admin screenshots for desktop, tablet, compact fallback, dense table, card/list fallback, filter open, detail panel, bulk selection, permission denied, stale data, and high-volume states.
- loading, empty, error, offline, disabled, focused, selected, and permission-denied states.
- pixel checks for blank screens, clipped text, overlapping controls, missing images, and wrong theme mode.
- accessibility scans for contrast, semantics, focus order, touch targets, keyboard operation, D-pad operation, screen reader labels, large text, and reduced motion.
- performance checks for first frame, animation jank, scroll stability, memory pressure, large lists, remote repeat input, and admin table virtualization.

Visual evidence must use sanitized data. Screenshots must not expose secrets, raw phone numbers, OTPs, private customer data, production tokens, or private account identifiers.

## Flutter Implementation Standard

Flutter apps must implement this standard with a typed theme and component architecture:

- Use `ThemeData` plus one or more `ThemeExtension` classes for semantic tokens.
- Put design tokens under app/theme or an equivalent shared design package.
- Avoid raw `Color(...)`, hardcoded radii, one-off text styles, and magic spacing in feature screens.
- Use reusable scaffolds for safe area, navigation, keyboard behavior, backgrounds, and route transitions.
- Use responsive constraints through `LayoutBuilder`, `MediaQuery`, `Sliver` patterns, and adaptive breakpoints.
- Use `Semantics`, tooltips, focus nodes, and shortcuts/actions where needed.
- Use platform-aware input types, autofill hints, validation, and error semantics.
- Keep animations interruptible, testable, and disabled or simplified under reduced motion.
- Images must declare stable dimensions, placeholders, error states, and cache behavior.
- Lists must be virtualized, paged, or otherwise bounded for performance.
- State management must expose loading, data, empty, error, offline, and refreshing distinctly.
- Navigation must support deep links, back behavior, restoration where needed, and protected routes.
- Testing must cover widgets, golden/snapshot surfaces, navigation smoke, accessibility, and route screenshot coverage.

Recommended Flutter package boundaries:

- `app/theme`: tokens, typography, colors, elevations, motion, icons.
- `app/router`: routes, deep links, guards, transitions.
- `shared/widgets`: reusable components and screen scaffolds.
- `shared/state`: async state wrappers, offline/sync state, permission state.
- `features/<feature>`: product logic and feature-specific screens only.
- `test/goldens` or equivalent: component and route visual baselines.

## Robust Implementation Goal

Goal: build one comprehensive, reference-backed UI/UX system for Flutter mobile, Flutter TV, and admin panel surfaces, using the Revolut screenshot grammar as the baseline for premium interaction quality while preserving product-owned content, role boundaries, accessibility, and platform-native behavior.

Completion requires all of the following:

- One authoritative `DESIGN.md` governs mobile, TV, and admin surfaces.
- The Revolut screenshot grammar is converted into semantic tokens, app shell rules, component contracts, state requirements, and QA gates.
- Flutter mobile routes use the shared dark/premium shell, compact command chrome, first-viewport value, circular quick actions, floating navigation, and complete state handling.
- Flutter TV routes use D-pad focus, 10-foot readability, focus memory, remote shortcuts, large stable tiles, and TV-safe navigation.
- Admin routes use dense but calm operator layouts: sidebar/rail, dashboards, tables, queues, detail panels, audit logs, filters, bulk action review, and permission-safe states.
- Consumer mobile and TV apps contain no admin-only routes or affordances.
- Admin panel exposes no consumer-only shortcuts that bypass permissions, audit trails, or review steps.
- All components consume semantic tokens rather than hardcoded colors, radii, text styles, shadows, durations, or breakpoints.
- Accessibility is verified for WCAG 2.2 AA, screen reader semantics, focus order, target size, large text, reduced motion, non-color-only state, and keyboard/remote operation.
- Visual evidence exists for mobile, TV, and admin breakpoints, including light/dark or dark/high-contrast modes, state variants, and route-level screenshots.

## Robust Implementation Plan

### Phase 0: Evidence Inventory

- Collect the current Revolut reference screenshots into a stable local evidence folder with filenames, dimensions, and contact sheet.
- Collect current mobile route screenshots, admin PWA screenshots, and any TV prototype screenshots.
- Create a route inventory for mobile, TV, and admin, including hidden, guarded, modal, sheet, and error routes.
- Mark every route as consumer, TV, admin, shared, or not applicable.

### Phase 1: Token And Theme Consolidation

- Map the reference palette seeds into semantic token roles.
- Add typed Flutter `ThemeExtension` classes for color, spacing, shape, typography, motion, elevation, focus, TV, and admin density.
- Remove hardcoded color, radius, shadow, and text-style literals from feature screens.
- Define high contrast and reduced motion token variants.

### Phase 2: Shared Shell And Components

- Build or standardize app shell, top command chrome, search pill, circular command button, quick action row, floating navigation, side rail, admin sidebar, TV rail, sheets, dialogs, banners, skeletons, empty states, and error states.
- Ensure components expose all default, focused, pressed, selected, disabled, loading, offline, empty, success, warning, danger, permission denied, and skeleton states.
- Add semantic icon roles for repeated concepts.

### Phase 3: Flutter Mobile Upgrade

- Apply the shared shell to all mobile routes.
- Ensure every primary mobile screen has a first-viewport value, concise top chrome, one primary action, state-safe async loading, and stable navigation.
- Verify compact, standard, large phone, tablet, landscape, keyboard-open, large-text, and offline states.
- Block admin routes and admin affordances from the consumer mobile route tree.

### Phase 4: Flutter TV Upgrade

- Define the TV route map and not-applicable mobile features.
- Build TV-specific shell, focus ring, content rows, large tiles, remote shortcut handling, search/text-entry alternatives, and back behavior.
- Test D-pad traversal, select, back, focus memory, row scrolling, loading placeholders, empty/error states, reduced motion, and overscan-safe layout.

### Phase 5: Admin Panel Upgrade

- Apply the shared admin shell to all operator routes.
- Add dashboard, list, table, queue, detail, audit, permission, and bulk-action patterns.
- Verify desktop, tablet, compact fallback, keyboard, screen reader, high data volume, empty queue, partial failure, stale data, unauthenticated, and out-of-role states.
- Ensure every consequential action records a review, confirmation, undo where possible, and audit trail.

### Phase 6: Evidence And Release Gates

- Generate route screenshots for every mobile, TV, and admin route and critical modal/sheet state.
- Generate component goldens or snapshots for shared primitives and high-risk states.
- Run accessibility checks for contrast, semantics, focus order, target size, large text, reduced motion, keyboard, and D-pad.
- Run performance checks for first frame, scroll, animation, memory pressure, remote repeat input, and large admin datasets.
- Publish a design-compliance report that maps every route to screenshot evidence, state evidence, accessibility evidence, and remaining exceptions.

## Quality Gates

A product is not design-complete until all Quality Gates pass:

- Single design authority: this `DESIGN.md` is present and no secondary design authority exists.
- Reference grammar compliance: screenshots and implementation preserve the required dark immersive shell, compact command chrome, hero hierarchy, circular quick actions, translucent panels, stable navigation, and concise state language unless a product-specific exception is documented.
- Token compliance: runtime UI uses semantic tokens and typed theme APIs.
- Component completeness: Universal Component Library components exist or are intentionally not applicable.
- State completeness: all State Requirements are implemented for screens and components.
- Responsive coverage: 320-374, 375-430, 431-599, 600-719, 720+, Landscape, Foldables, and Keyboard open are verified.
- TV coverage: D-pad focus, remote select/back, focus memory, 720p/1080p layout, safe margins, reduced motion, and large readable type are verified where TV exists.
- Admin coverage: desktop/tablet/compact admin layouts, keyboard operation, tables, filters, detail panels, bulk actions, permission states, and audit trails are verified where admin exists.
- Accessibility coverage: contrast, semantics, focus, touch targets, text scale, and reduced motion are verified.
- Visual coverage: route screenshot coverage and golden or snapshot tests exist for critical paths.
- Performance coverage: first frame, scroll, animation, and memory behavior are acceptable on representative devices.
- Privacy coverage: screenshots, logs, analytics, and UI mask sensitive data.
- Platform coverage: Android and iOS platform conventions, permissions, status bars, navigation, haptics, and safe areas are respected.

## Universal App Generation Prompt

When generating or rebuilding an app, use this instruction:

Create a production app using the Universal App Design Standard 2026. Use this `DESIGN.md` as the only design authority. Build the actual usable first screen, not a landing page. Use the Revolut reference screenshot grammar as the premium baseline for shell, hierarchy, command chrome, action rows, panels, navigation, density, and state polish. Implement a typed token model, app shell, Universal Component Library, all State Requirements, mobile responsive bands from 320 dp through tablet/foldable/landscape, Flutter TV focus/remote behavior where applicable, admin panel density and auditability where applicable, accessibility support, route screenshot coverage, and golden or snapshot tests. Use domain-specific truthful content, sanitize private data, avoid unsupported regulated claims, and keep Flutter implementation aligned with semantic tokens and reusable components.

## Governance

- This file replaces all old design folders, screenshots-as-authority matrices, token JSON authority files, and provenance markdown.
- Runtime assets needed by the app may remain in the app asset tree, but their design meaning must be documented here or in code comments only where unavoidable.
- Historical release evidence may mention old work, but must not instruct current implementation to use old design authorities.
- Any new design rule must be added to this file first, then implemented in tokens, components, tests, and gates.
- External submissions, regulated claims, app-store assets, public legal notices, and customer-facing professional claims require explicit human approval.
