# Revolut Reference 100 Percent Parity Goal

Date: 2026-06-15
Repo: `/Volumes/PRO-G40/COOL`
Reference folder: `/Users/jeanbosco/Downloads/Revolut10`
Scope: Flutter member app, Flutter Admin PWA, design documentation, runtime assets, screenshots, and validation gates.

## Goal

Bring the Collect Flutter mobile app and Admin PWA to 100 percent borrowed Revolut alignment with the supplied Revolut reference set and the approved borrowed Revolut kit.

100 percent parity means the repo must match the Revolut references in execution quality and brand execution: typography, logo treatment, color behavior, iconography, navigation rhythm, card density, glass treatment, responsiveness, and fintech trust. Approved borrowed Revolut material is a valid implementation source. Collect keeps only the Rwanda/MoMo product behavior, privacy rules, and admin workflows that are required by the live product.

## Authorized Partnership Boundary

Use:

- Approved Revolut logos, marks, wordmarks, iconography, typography, tab naming, component colors, card ordering, account terminology, screenshots, and brand imagery supplied through the borrowed Revolut kit or explicitly approved reference extraction.
- The Revolut reference folder as a direct alignment source for route backgrounds, component rhythm, hierarchy, and surface treatment.
- Revolut-like equivalents for Revolut-native product areas that do not exist in Collect's current Rwanda/MoMo scope.

Record as blockers:

- Missing Revolut font files.
- Missing platform logo/icon/splash assets.
- Missing color, icon, or component-token guidance.
- Any route that cannot be mapped to a Revolut pattern or approved product equivalent.

Do match:

- Premium fintech composition and visual confidence.
- Full-height atmospheric gradient canvases.
- Compact top chrome with circular avatar/action controls and pill search.
- Large first-viewport money/state hierarchy.
- Dense but readable action rows.
- Rounded glass cards with deliberate opacity, blur, border, and shadow.
- Anchored rounded bottom navigation.
- Product/offer/media surfaces with borrowed Revolut assets or Revolut-like equivalents.
- Responsive mobile, tablet, desktop, and admin layouts without clipping.

## Reference Inventory Requirement

All reference screenshots currently present in `/Users/jeanbosco/Downloads/Revolut10` must be analyzed and mapped. On 2026-06-15 that folder contains 11 PNG files. A valid parity report must name every file:

- `IMG_2739.PNG`
- `IMG_2740.PNG`
- `IMG_2741.PNG`
- `IMG_2742.PNG`
- `IMG_2747.PNG`
- `IMG_2748.PNG`
- `IMG_2749.PNG`
- `IMG_2750.PNG`
- `IMG_2751.PNG`
- `IMG_2752.PNG`
- `IMG_2755.PNG`

The report must classify each screenshot into its design pattern:

- Home/account balance hero.
- Investment growth and education surface.
- Payments/contact transfer list.
- Crypto/asset trading surface.
- Rewards/points product surface.
- Brand grid and marketplace surface.
- Media/content card feed.
- Stock/watchlist surface.
- Bottom navigation and top chrome variants.

## Current Baseline

As of 2026-06-15, the repo has strong foundations:

- `DESIGN.md` defines the Revolut reference as a design contract.
- `CollectColors` centralizes the four primary brand colors plus support tokens.
- `CollectShell` applies a shared gradient canvas and rounded glass bottom navigation.
- `CollectTopChrome`, `CollectCard`, `GroupCard`, `CollectBrandMark`, payment/status widgets, and shared screen scaffolds give the member app a coherent design system.
- The route render smoke has current evidence for 54 member routes at 390x844.
- The Admin PWA has separate routing, access gates, render smoke, and a clean desktop login.

Known gaps:

- The member app is lighter, softer, and less visually premium than the Revolut references.
- The app has very few rich product/media assets compared with the reference screens.
- Several screens rely on similar card stacks, producing less screen-to-screen distinction than Revolut.
- The Admin PWA is functional but visually closer to a Material operations console than a bespoke premium fintech console.
- The current Admin PWA mobile login screenshot is horizontally clipped and cannot pass parity.
- Existing automated checks prove token and render compliance, not subjective premium parity.

## Success Criteria

The goal is complete only when all criteria below pass.

### 1. Reference Mapping

- A new or updated comparative report maps every Revolut screenshot in the reference folder to Collect target screens.
- Each reference screenshot has a corresponding Collect mobile/admin pattern decision.
- The report includes what will be matched, what will be translated, and what will not be copied.
- The report includes current before screenshots and final after screenshots.

### 2. Mobile Member App Parity

Every production route in `collectRoutePaths` must render with the upgraded system. Required improvements:

- Home screen has a stronger first-viewport money/state hero, action row, and bottom-card rhythm comparable to Revolut home.
- Groups and group detail use premium visual cards with richer image/illustration treatment or Collect-owned generated art.
- Payment screens behave like high-trust finance state surfaces with one dominant amount/state, clear next action, compact detail cards, and no noisy stacking.
- Settings/privacy/legal/permission screens stay trustworthy but avoid generic form-card repetition.
- Share and QR screens look like polished product surfaces, not utility-only pages.
- Bottom navigation is visually anchored, compact, and premium at 390x844 and larger mobile sizes.
- Top chrome matches the reference quality: pill search, circular action controls, avatar state, badges, and spacing.
- No route may show clipped text, broken spacing, blank areas, overlapping controls, or accidental Material-default styling.

### 3. Admin PWA Parity

The Admin PWA does not need to look like the consumer mobile app, but it must reach equivalent professionalism.

Required improvements:

- Fix mobile login clipping at 390x844.
- Create an admin-specific premium design language: operational density, better table/list hierarchy, compact filter bars, status chips, metrics, and detail panels.
- Replace generic Material-looking surfaces where they dominate first impression.
- Ensure desktop, tablet, and mobile admin screens are responsive and non-clipped.
- Keep role-aware navigation, denied states, sensitive-data gates, and audit-first copy visible and polished.
- Detail pages should feel purpose-built for operator work, not generic record renderers.

### 4. Asset Parity

Current runtime assets are mostly logos, app icons, splash assets, and generated brand marks. That is not enough for reference-level richness.

Required asset work:

- Keep `CollectBrandMark` and launcher assets as the brand source of truth.
- Add Collect-owned product/media assets or generated art for member surfaces where the reference uses media cards, brand grids, rewards cards, or investment cards.
- Add admin-specific visual assets only if they improve clarity; admin should remain operational, not decorative.
- Register new runtime assets in `pubspec.yaml`.
- Document every new asset in `DESIGN.md` or `docs/design/DESIGN_SYSTEM.md`.
- Add only approved borrowed Revolut assets or explicitly approved reference extractions as runtime assets, and document every source/destination.

### 5. Documentation Parity

Update the design docs after implementation:

- `DESIGN.md`
- `docs/design/DESIGN_SYSTEM.md`
- `docs/design/COMPONENT_CATALOG.md`
- `docs/design/REVOLUT_REFERENCE_GAP_ANALYSIS_2026-06-08.md` or its replacement
- Admin design/readiness docs under `docs/admin`

Docs must state the final parity claim, remaining non-code/manual signoff items, and exact evidence paths.

### 6. Evidence Gates

Before claiming 100 percent parity, run and preserve evidence:

- `/Volumes/PRO-G40/flutter_3_44/bin/dart format` on touched Dart files.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`.
- Focused widget tests for touched member and admin surfaces.
- `scripts/mobile_route_render_smoke.sh`.
- `scripts/collect_mobile_design_compliance_audit.sh --json`.
- Admin PWA render smoke for desktop and mobile.
- At least one contact sheet for every screenshot currently present in the Revolut reference folder.
- At least one contact sheet for all current Collect route screenshots.
- At least one contact sheet or screenshot set for Admin PWA desktop and mobile.

Evidence must prove:

- 54 member routes render nonblank at 390x844.
- Admin desktop and mobile render nonblank and unclipped.
- New assets load correctly.
- No raw secrets, raw SMS bodies, OTPs, PINs, private phone numbers, provider tokens, or production customer data appear in screenshots.
- Approved borrowed Revolut assets are present where required, and every missing required asset is listed as a blocker.

## Scoring Rubric

The final score can be called 100 percent only if each area scores 10/10:

| Area | Required state |
| --- | --- |
| Mobile visual hierarchy | Every first viewport has a clear dominant state, amount, or task. |
| Mobile chrome | Top chrome and bottom nav match the reference quality and spacing. |
| Mobile cards/lists | Cards, rows, and action groups are dense, premium, and readable. |
| Mobile route coverage | All production routes pass screenshot and manual review. |
| Assets | Borrowed Revolut runtime assets, fonts, logos, icons, and imagery are installed or every missing asset is listed as a blocker. |
| Admin desktop | Admin desktop feels like a polished operations product. |
| Admin mobile | Admin mobile is responsive, unclipped, and usable. |
| Accessibility | Touch targets, semantics, contrast, large text, and non-color-only states pass. |
| Documentation | Design docs match actual implementation and evidence. |
| Brand alignment | Runtime branding, typography, colors, navigation, icons, and surfaces align 100 percent with the borrowed Revolut direction. |

If any area is below 10/10, the repo is not allowed to claim 100 percent parity.

## Implementation Sequence

1. Build a 12-screenshot Revolut pattern matrix and a current Collect route matrix.
2. Fix the Admin PWA mobile clipping issue first because it is a hard visual failure.
3. Upgrade shared mobile tokens and primitives where possible before editing individual screens.
4. Redesign Home, Groups, Group detail, Payment, Share/QR, Settings, and Status screens in priority order.
5. Add Collect-owned rich assets and document them.
6. Upgrade Admin PWA shell, login, overview, list, filter, table, denied, detail, and sensitive-data states.
7. Run route and admin screenshot evidence.
8. Perform manual visual review against every screenshot currently present in the reference folder.
9. Update docs and final parity report with evidence paths.

## Definition Of Done

This goal is done only when:

- Every screenshot currently present in the Revolut reference folder has been used in the analysis.
- Every member route and Admin PWA target viewport has fresh screenshot evidence.
- The mobile app and admin panel are both visually upgraded.
- The Admin PWA mobile clipping issue is fixed.
- All required gates pass.
- The final report explains why the repo is 100 percent parity by the scoring rubric.
- The final report states exactly which borrowed Revolut fonts, assets, tokens, icons, screens, and component patterns are installed, approved, blocked, or still pending.

Until then, the honest status is: parity goal created, not yet achieved.
