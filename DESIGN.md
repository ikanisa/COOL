# Universal Mobile App Design Standard 2026

This document is the single design authority for this repository. Any production mobile app, Flutter-first but adaptable to native iOS, Android, React Native, web, or embedded app surfaces, must use this file as its design contract. No secondary design folder, screenshot parity matrix, token JSON, design-system markdown, source-variant asset folder, provenance note, or archived design report may override this standard.

## Universal Design Goal

Build a world-class mobile product that feels calm, fast, premium, trustworthy, and task-focused. The interface should combine modern fintech-grade polish with universal product patterns: compact hierarchy, confident typography, thumb-first actions, resilient state handling, motion that clarifies changes, inclusive accessibility, and adaptive layouts that scale from small phones to tablets, foldables, desktop shells, and landscape modes.

The standard is intentionally universal. Product teams must replace domain examples with their own truthful product data, but must keep the system principles, token model, component contracts, state requirements, quality gates, and Flutter implementation rules.

## Reference Screenshot Lessons

Reference screenshots from premium mobile apps may inspire density, hierarchy, motion, contrast, and interaction polish. They must not become a copied brand, copied content system, copied iconography, or copied regulated product promise. Use references only to extract durable UI lessons:

- Put the primary user value in the first viewport.
- Use compact top chrome with clear account, search, and action affordances.
- Prefer icon-led metadata, concise labels, and readable numbers over verbose instruction blocks.
- Use cards for repeated items and framed tools, not for every page section.
- Keep navigation stable, thumb-accessible, and branch-preserving where depth requires it.
- Make empty, loading, offline, error, disabled, selected, pressed, focused, and permission states feel designed rather than bolted on.
- Use background, elevation, blur, and tonal contrast to separate zones without visual noise.
- Make every screen feel production-ready in both light and dark mode.

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
- loading, empty, error, offline, disabled, focused, selected, and permission-denied states.
- pixel checks for blank screens, clipped text, overlapping controls, missing images, and wrong theme mode.
- accessibility scans for contrast, semantics, focus order, and touch targets.
- performance checks for first frame, animation jank, scroll stability, and memory pressure.

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

## Quality Gates

A product is not design-complete until all Quality Gates pass:

- Single design authority: this `DESIGN.md` is present and no secondary design authority exists.
- Token compliance: runtime UI uses semantic tokens and typed theme APIs.
- Component completeness: Universal Component Library components exist or are intentionally not applicable.
- State completeness: all State Requirements are implemented for screens and components.
- Responsive coverage: 320-374, 375-430, 431-599, 600-719, 720+, Landscape, Foldables, and Keyboard open are verified.
- Accessibility coverage: contrast, semantics, focus, touch targets, text scale, and reduced motion are verified.
- Visual coverage: route screenshot coverage and golden or snapshot tests exist for critical paths.
- Performance coverage: first frame, scroll, animation, and memory behavior are acceptable on representative devices.
- Privacy coverage: screenshots, logs, analytics, and UI mask sensitive data.
- Platform coverage: Android and iOS platform conventions, permissions, status bars, navigation, haptics, and safe areas are respected.

## Universal App Generation Prompt

When generating or rebuilding an app, use this instruction:

Create a production mobile app using the Universal Mobile App Design Standard 2026. Use this `DESIGN.md` as the only design authority. Build the actual usable first screen, not a landing page. Implement a typed token model, app shell, Universal Component Library, all State Requirements, responsive bands from 320 dp through tablet/foldable/landscape, accessibility support, route screenshot coverage, and golden or snapshot tests. Use domain-specific truthful content, sanitize private data, avoid copied brands, and keep Flutter implementation aligned with semantic tokens and reusable components.

## Governance

- This file replaces all old design folders, screenshots-as-authority matrices, token JSON authority files, and provenance markdown.
- Runtime assets needed by the app may remain in the app asset tree, but their design meaning must be documented here or in code comments only where unavoidable.
- Historical release evidence may mention old work, but must not instruct current implementation to use old design authorities.
- Any new design rule must be added to this file first, then implemented in tokens, components, tests, and gates.
- External submissions, regulated claims, app-store assets, public legal notices, and customer-facing professional claims require explicit human approval.
