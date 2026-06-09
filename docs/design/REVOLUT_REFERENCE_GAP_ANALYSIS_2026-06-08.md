# Revolut Reference Gap Analysis - Collect Mobile

Date: 2026-06-08

## Scope

This report compares the current Collect mobile design system against the ten supplied Revolut screenshots. The target is reference-compatible fintech quality, not copying Revolut IP. Collect must keep its own product model, copy, brand assets, icon choices, route map, privacy rules, four primary paint colors, and Paper canvas:

- Periwinkle `#8885F0`
- Mint `#3CD070`
- Rose `#D38B96`
- Orange `#FF5E43`
- Paper canvas `#FAF8F5`

## Reference Patterns From Screenshots

The screenshots consistently show:

- Full-screen vertical gradients or painted canvases with no flat page chrome.
- Floating top chrome: avatar, search pill, circular action buttons, and badge state.
- Very large first-viewport hierarchy: balance, page title, profile identity, or hero offer is the visual anchor.
- Translucent, high-radius cards with subtle borders and visible canvas bleed-through.
- Pill CTAs and rounded bottom navigation that stay reachable and visually separate from page content.
- Dense lists with large leading avatars/icons, bold primary text, muted secondary text, and right-aligned metadata.
- Product-specific color moods while preserving one shared chrome language.
- Minimal explanatory copy. Screens are operational and scannable.

## Current Compatibility Score

Current source-level score after this pass: `82/100`.

This score reflects design-system readiness, not complete visual QA on every rendered route. The core tokens now support the four-paint palette, Paper canvas, glass surfaces, pill CTAs, and larger card radius. Remaining gaps are mostly route composition and screenshot-level polish.

## Gap Matrix

| Area | Current state | Gap | Priority | Required action |
| --- | --- | --- | --- | --- |
| Color contract | Theme and docs previously mixed legacy and five-color language. | Paper must be treated as canvas, not a primary paint swatch. | P0 | Done in this pass: the contract now enforces four primary paint colors plus Paper canvas. |
| Canvas | `CollectGradientBackground` exists and shell routes use it. | Some route-local surfaces can still visually dominate the gradient. | P1 | Reduce opaque card use and prefer `glassPanel` / `glassPanelStrong`. |
| Top chrome | Home has a custom brand header; scaffold headers remain title/action based. | Not yet a universal avatar/search/action cluster like the reference. | P1 | Add a shared `CollectTopChrome` variant and use it on Home, Groups, Settings, and major detail routes. |
| Bottom navigation | Rounded glass nav exists. | Product tabs are Collect-owned and only three items, but selected treatment can be closer to the reference. | P2 | Keep three tabs, tune selected capsule size, icon weight, and active contrast. |
| Cards | Shared `CollectCard` exists with glass opacity and borders. | Radius was smaller than reference and blur is uneven across surfaces. | P1 | Done partly: cards now use larger radii. Next add optional blur for hero/glass cards only. |
| CTAs | Shared buttons exist. | Radius was not pill-like enough for Revolut-style CTAs. | P0 | Done in this pass: shared controls now use pill radius. |
| Lists | Activity and group cards are scannable. | Several secondary routes still read as status panels instead of dense mobile lists. | P1 | Convert secondary state surfaces to list/card patterns with leading symbols and right metadata. |
| Typography | Amount display and tabular numerals exist. | First-viewport hero hierarchy is inconsistent route to route. | P1 | Standardize amount/title hero slots and reduce explanatory body copy above primary actions. |
| Iconography | Central `CollectIcons` exists. | Some feature screens still use generic Material icons and inconsistent filled/outline weight. | P2 | Normalize main actions to tokenized icons in glass/circular controls. |
| Compliance | Existing audit passed the older contract. | Gate name and expected palette were stale. | P0 | Done in this pass: gate now enforces `four_primary_paint_color_contract`. |

## Core Plan To Reach 100 Percent Reference Compatibility

1. Token foundation
   - Keep the four primary paint colors as the only brand paint palette.
   - Keep all page gradients and glass surfaces centralized in `CollectColors`.
   - Keep controls pill-shaped and card radii at 24/28 for member mobile surfaces.

2. Shared chrome
   - Add `CollectTopChrome` with avatar, search/action pill behavior, unread dot, and route-specific actions.
   - Use it consistently on first-level routes and high-value financial routes.

3. Route hierarchy
   - For each production route, ensure the first viewport has one clear hero: total, group state, payment state, privacy/access status, or primary action.
   - Remove redundant instructional text above CTAs unless required for legal/privacy clarity.

4. Surface polish
   - Use glass cards for panels, dense list rows for repeated records, and hero image cards only where a real Collect asset or group image exists.
   - Avoid route-local color literals, route-local gradients, and generic Material surfaces.

5. Validation
   - Run format, analyzer, focused widget tests, and `scripts/collect_mobile_design_compliance_audit.sh --json`.
   - Run route render smoke at 390x844 and manually review screenshots against this matrix.
   - Treat device UAT and release gates separately from visual-system completion.

## Implementation Completed In This Pass

- Kept Paper `#FAF8F5` in `CollectColors.brandPaper` as the canvas/foundation color.
- Updated `brandPrimaryColors`, `brandPrimaryHexes`, and `brandPrimaryOptions` to Periwinkle, Mint, Rose, Orange.
- Updated QR/export gradients and group color swatches to use the four-paint shared palette.
- Updated shared radii so CTAs are pill-shaped and mobile cards use larger Revolut-like radii.
- Updated design docs, legacy design notes, tests, and compliance scripts to the four-paint contract.

## Residual Risk

Automated source checks cannot prove subjective 100 percent visual parity. The remaining proof must come from route screenshots and manual comparison against the supplied reference images after the shared top chrome and route hierarchy pass.
