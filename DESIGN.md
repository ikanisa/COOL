---
name: Collect
updated: 2026-06-17
scope: Flutter mobile member app and Flutter web surfaces that share the Collect theme
reference-contract: The 11 Revolut screenshots in /Users/jeanbosco/Downloads/Revolut10 are the active UI/UX contract for mobile gradient backgrounds, glass chrome, compact finance hierarchy, media-rich cards, and thumb-first navigation adapted to Collect group collections.
brand-assets:
  launcher-icon: assets/brand/collect_app_icon_static.png
  app-icon-rule: assets/brand/generated/collect_app_icon_rule.png
  mobile-wordmark: assets/brand/generated/collect_wordmark_transparent.png
  reference-sheet: assets/brand/generated/collect_logo_color_variants_sheet.png
  visual-momo-signal: assets/brand/generated/collect_visual_momo_signal.png
  visual-group-momentum: assets/brand/generated/collect_visual_group_momentum.png
  visual-qr-share: assets/brand/generated/collect_visual_qr_share.png
  source-wordmark: assets/brand/source_variants/collect_wordmark_transparent_4096.png
  source-mark: assets/brand/source_variants/collect_mark_transparent_4096.png
  source-gradient-logo: assets/brand/source_variants/collect_logo_gradient_4096.png
  source-preview: assets/brand/source_variants/collect_logo_preview_checkerboard_1254.png
canvas:
  paper: '#FAF8F5'
primary-colors:
  periwinkle: '#8885F0'
  mint-green: '#3CD070'
  dusty-rose: '#D38B96'
  orange-red: '#FF5E43'
secondary-support-colors:
  ink-primary: '#252044'
  ink-secondary: '#4B4664'
  ink-muted: '#5F5A76'
  surface-readable: '#FFFDFB'
  surface-muted: '#F1ECF7'
  border-soft: '#DED8EA'
  border-accent: '#CDC7F5'
  focus-ring: '#6F67E8'
  success-foreground: '#137A3F'
  info-foreground: '#514DD2'
  warning-foreground: '#B9472E'
  danger-foreground: '#B3261E'
  success-container: '#E7F8ED'
  info-container: '#ECEBFF'
  warning-container: '#FFE9E3'
  danger-container: '#FFE5DF'
  neutral-container: '#F1ECF7'
tokens:
  flutter-theme-extension: lib/app/theme/collect_colors.dart
  flutter-theme: lib/app/theme/collect_theme.dart
  shell: lib/core/widgets/collect_shell.dart
  shared-components: lib/shared/widgets/collect_components.dart
  compliance-audit: scripts/collect_mobile_design_compliance_audit.sh
---

# Collect Mobile Design System

Collect must feel like a premium fintech mobile app while staying fully Collect-owned. The Revolut screenshots are not moodboard inspiration; they are a route-by-route quality contract for background families, first-viewport hierarchy, translucent cards, black glass chrome, compact top controls, rounded bottom navigation, visual density, and finance-grade trust. This is not a license to copy Revolut assets, trademarks, product behavior, icons, copy, or proprietary screen content. Collect keeps its own product model: group collections, MoMo receiver setup, QR scan/share, contribution flows, member activity, profile, settings, notifications, and admin operations.

The implementation target is 10/10 Revolut-reference execution quality adapted to Collect. For code-owned work, the app can be treated as complete when every supplied screenshot is mapped into Collect-owned design rules, every production member route has fresh visual evidence, dark and light modes pass automated review, and the design compliance audit is green. External release or public marketing claims still require explicit approval, but they are not engineering blockers.

## Non-Negotiables

- Every member-facing production route must render on a gradient background using the extracted Revolut reference screen-background colors. Collect's four primary colors are used for components, actions, brand accents, chips, and illustrations, not for the screen canvas.
- Light and dark modes must be visually distinct like a premium fintech app: light mode uses bright readable glass surfaces over the reference gradients; dark mode uses dark surfaces, pale text, darker borders, and stronger night chrome over the same route-specific reference gradient families.
- Reference gradients are vertical mobile atmospheres. Do not replace them with local diagonal feature gradients on page canvases.
- The first viewport of every primary route must have a dominant financial state, group state, QR/share state, or account/profile state. Empty explanatory cards are not acceptable first-viewport content.
- Top chrome must use a compact profile control, optional black pill search, and circular action buttons. Profile controls must be visible, tappable, and route to profile.
- Bottom navigation must remain functionally Collect-owned while visually matching the Revolut floating black glass dock: anchored, rounded, bordered, selected capsule, one-line labels, and stable touch targets.
- Collect keeps four primary colors from the corrected brand assets: Periwinkle `#8885F0`, Mint `#3CD070`, Rose `#D38B96`, and Orange `#FF5E43`.
- Paper `#FAF8F5` is the canvas/foundation color. It is not counted as a primary color. Native Android launch uses Collect Periwinkle `#8885F0` instead of paper so cold starts do not flash a white screen before Flutter paints.
- Ink `#252044` is the high-contrast text/chrome anchor. It is a support token, not a primary color.
- Secondary/support colors are allowed only as named UI tokens for readable surfaces, borders, focus, and semantic status foreground/container roles. They do not replace or expand the four primary colors.
- Use Collect brand assets only: `CollectBrandMark` renders `assets/brand/generated/collect_wordmark_transparent.png`; launcher/platform icon use stays on generated PNG icon assets.
- Route surfaces must use `ScreenScaffold`, `ScreenScaffoldLayout`, `PremiumScaffold`, or `CollectGradientBackground`.
- Standalone flows that bypass `ScreenScaffold`, such as share/QR export surfaces, must explicitly wrap their page in `CollectGradientBackground`.
- Visible page chrome uses glass tokens: `glassPanel`, `glassPanelStrong`, `glassControl`, and `glassBorder`.
- Secondary-route headers use a plain finance-grade row: back arrow, one-line title, optional one-line subtitle, and tokenized action circles. Utility, legal, permission, profile, create, and scanner routes must not use decorative brand header cards.
- Visible labels must stay compact: use one line with ellipsis for section headers, chips, tiles, status labels, table cells, card titles, and explanatory helper copy. Do not add verbose instructional text inside the app when an icon, state, or concise command can carry the meaning.
- Primary mobile destinations remain Collect-owned. The current functional destinations are `Home`, `Groups`, and `Settings`; any additional dock action must map to an existing Collect task such as scan, notifications, or share, not invented Revolut product tabs.
- Identity remains privacy-safe: Collect ID only. Do not expose raw phone numbers, raw receiver MoMo numbers, raw SMS, PINs, OTPs, MoMo transaction IDs, or public member names. Payment-state surfaces that must show receiver context use masked MoMo display such as `+250***3456`.
- Admin surfaces may stay dense and operational, but member-facing mobile screens must not revert to generic Material blue, legacy color shells, crypto/wallet branding, or admin-style dashboards.

## Reference Translation

Use the screenshots for these patterns:

- Gradient canvas: every screen starts with a full-height gradient field built from the extracted reference background families: account navy `#000840`, payments purple `#181038`, asset navy `#101830`, rewards violet `#302878`, wealth teal `#102028`, and stock teal-black `#001010`.
- Top chrome: brand/search/action areas read as compact floating pills or glass controls, not flat app bars.
- Bottom navigation: rounded, translucent, fixed, thumb-first, and visually separated from the gradient.
- Finance hierarchy: the main amount, state, group, or payment action is obvious within the first viewport.
- Cards: content sits on translucent glass surfaces with subtle borders and blur; cards should not fully hide the gradient.
- Rich product surfaces: where the reference uses media, marketplace, rewards, or content cards, Collect must use Collect-owned generated product visuals through shared components such as `CollectVisualFeatureCard`, image-backed `GroupCard` covers, and the Home Momentum feed instead of copied screenshots or generic decoration. Utility routes should stay plain and scannable when review notes call for headers plus back navigation only.
- CTAs: buttons are large, pill-like, reachable, and high-contrast.
- Lists: rows stay compact and scannable, with clear leading icons/avatars and right-aligned amounts/status where relevant.
- Copy density: labels, helper text, and admin table/status copy are concise, one-line, and ellipsized when constrained.

Use the MOBI repo as the implementation benchmark for process, not as code to paste. MOBI's stronger Revolut work is the contract shape: route matrix, shared shell, shared gradient background, shared glass cards, bottom-nav primitive, preview/golden coverage, and current evidence reports. COOL must follow that discipline with Collect-owned routes and assets.

Do not copy these elements:

- Revolut logo, trademarks, iconography, text, tab names, component colors, exact card order, account names, crypto/invest labels, or screenshots.
- Any brand/component palette outside Collect's approved four primary colors, Paper canvas, named support tokens, and the reference-derived screen-background tokens.

## Color And Gradient Tokens

`CollectColors` is the source of truth.

- `brandPrimaryColors` and `brandPrimaryHexes` lock the four approved primary colors in reference order.
- `screenBase`, `screenGradient`, and `adminScreenGradient` own the page background using the extracted Revolut reference screen-background colors, not Collect primary colors.
- `screenGradientForPath()` applies the extracted background families by route, so screenshots do not collapse into one generic dark canvas.
- `CollectColors.light` and `CollectColors.dark` must stay distinct for surfaces, text, borders, semantic containers, and glass panels; `AppTheme` must expose both and app shells must use the persisted `collectThemeModeProvider` with a dark-first default.
- `glassPanel`, `glassPanelStrong`, `glassControl`, `glassBorder`, and `glassPanelGradient` own translucent surfaces and chrome.
- `surfaceReadable`, `surfaceMuted`, `borderSoft`, `borderAccent`, `focusRing`, and the `semantic*` token constants provide the secondary/support palette.
- `actionColor` remains Orange Red for primary action fills; `success`, `warning`, `danger`, `info`, and status helpers resolve to contrast-safe semantic foregrounds and containers.

Screens should not build page gradients locally. Feature-specific gradients are allowed only for cards, QR assets, cover media, and accent treatments, and they must use Collect tokens.

### Reference Background Route Map

| Reference screenshots | Extracted background family | Collect routes |
| --- | --- | --- |
| `IMG_2739.PNG` | Account blue/navy: `#0818A0`, `#0F198E`, `#000838`, `#000030` | `/home`, onboarding, auth |
| `IMG_2741.PNG`, `IMG_2747.PNG`, `IMG_2750.PNG` | Payments purple: `#302848`, `#181038`, `#100820` | `/groups`, `/groups/:id`, `/groups/:id/members`, `/c/:slug` |
| `IMG_2742.PNG`, `IMG_2748.PNG` | Asset navy: `#303870`, `#202858`, `#101830`, `#000818` | contribution, payment, payment-state, support-payment, and ledger routes |
| `IMG_2749.PNG` | Rewards violet: `#9838F0`, `#7050E8`, `#302878`, `#100820` | group share/invite routes, public share states, `/settings` |
| `IMG_2740.PNG` | Wealth teal: `#204050`, `#183848`, `#102028`, `#081820` | group creation, profile/readiness, SMS/device/camera/notification permission routes, iPhone create-unavailable route |
| `IMG_2751.PNG`, `IMG_2752.PNG` | Content dark: `#303020`, `#181038`, `#101018` | settings account, privacy, help, legal routes |
| `IMG_2755.PNG` | Invest teal-black: `#202828`, `#102028`, `#001010` | offline and sync routes |

The app shell passes the active route through `CollectBackgroundRouteScope` in `lib/core/widgets/collect_shell.dart`; `CollectGradientBackground` consumes it in `lib/shared/widgets/collect_components.dart`.

## Asset Contract

- `assets/brand/collect_app_icon_static.png`: launcher/app icon source.
- `assets/brand/generated/collect_app_icon_rule.png`: generated icon rule reference.
- `assets/brand/generated/collect_wordmark_transparent.png`: in-app mobile wordmark used by `CollectBrandMark`.
- `assets/brand/generated/collect_logo_color_variants_sheet.png`: static color reference sheet.
- `assets/brand/generated/collect_visual_momo_signal.png`: Collect-owned rich product visual for MoMo verification and payment-state surfaces.
- `assets/brand/generated/collect_visual_group_momentum.png`: Collect-owned rich product visual for group momentum and public-support surfaces.
- `assets/brand/generated/collect_visual_qr_share.png`: Collect-owned rich product visual for QR sharing and invite surfaces.
- `assets/brand/source_variants/collect_wordmark_transparent_4096.png`: corrected transparent wordmark source.
- `assets/brand/source_variants/collect_mark_transparent_4096.png`: corrected transparent launcher/app mark source.
- `assets/brand/source_variants/collect_logo_gradient_4096.png`: corrected gradient logo source for reference.
- `assets/brand/source_variants/collect_logo_preview_checkerboard_1254.png`: supplied preview image retained only as source evidence, not as a runtime logo.
- No live SVG launcher fallback.
- Generated brand assets must remain PNG/GIF only unless a platform-specific build pipeline requires otherwise.

## Component Contract

Use these shared primitives first:

- Page canvas: `CollectGradientBackground`, `PremiumScaffold`, `ScreenScaffold`, `ScreenScaffoldLayout`.
- Brand: `CollectBrandMark`.
- Cards: `CollectCard` with glass opacity, `CollectVisualFeatureCard`, `CollectBentoGrid`, `BentoMetricCell`, `GroupCard`. Image-less group cards must fall back to Collect-owned generated media, not blank blocks.
- Controls: `CollectButton`, `SearchWithClearField`, `PremiumSegmentedFilter`, icon buttons styled with `colors.glassControl`.
- Headers: `ScreenHeader` and `CollectPlainPageHeader` provide the shared plain secondary header with back navigation and one-line title text.
- Bottom surfaces: `CollectBottomSheet`, `BottomActionSurface`.
- State: `LoadingStatePanel`, `EmptyIllustrationState`, `CollectErrorState`, `InfoSecurityBanner`.
- Payments: `PaymentPipelineIndicator`, `PaymentVerifiedRing`.
- Scanner: QR joining is camera-first with a dark live-preview overlay, corner guides, torch and camera-switch controls, gallery QR decode where the platform supports file analysis, and a compact link/code entry fallback. Scanner copy must not imply manual payment proof or SMS paste workflows.

Feature screens may add local layout, but not local design language. If a feature needs a new visual pattern, add it to shared components or tokens first.

## Route Coverage

The production member route list in `lib/app/router.dart` is the design scope. The route-render smoke must cover every registered production route, including onboarding, auth, home, groups, share, payment states, settings, privacy, permissions, offline, notifications, and sync.

Camera preview overlays use tokenized Periwinkle scrims because they sit on top of live camera pixels. Their visible instructional controls still use Collect glass tokens.

Permission routes are recovery/status surfaces only. Native SMS, camera, and notification prompts are triggered by the related action flow: group creation, QR scanning/gallery access, or notification enablement.

## Accessibility And Responsive Rules

- Minimum touch targets: 48x48 logical pixels on Android and 44x44 on iOS.
- Text must survive 200% scaling without clipping critical actions. Rich Home surfaces, including the visual story rail and Momentum feed, must expose semantics that summarize amount/progress context without leaking private receiver data.
- Status must never be color-only; pair color with text and iconography.
- Icon-only controls require tooltips/semantics.
- Motion uses `CollectMotion` and respects reduced-motion settings.
- Screens must render at 390x844 mobile viewport and adapt to compact phones, tall phones, landscape, tablets, and foldables.

## Quality Gates

Before claiming design parity:

- Format touched Dart files with `/Volumes/PRO-G40/flutter_3_44/bin/dart format`.
- Run `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`.
- Run focused widget tests for theme tokens, brand mark, shared components, shell, and touched routes.
- Run dark and light mode checks for shared shell/card/top chrome states.
- Run `test/features/theme_mode_visual_parity_test.dart` to enforce strong
  luminance separation between light and dark glass surfaces while preserving
  the same Revolut-derived route background families.
- Run `scripts/mobile_route_render_smoke.sh` for all production routes.
- Run `scripts/android_route_visual_evidence.sh` for physical-device mobile route PNG evidence when Android device proof is required or browser route capture is unstable.
- Run `scripts/admin_pwa_authenticated_render_smoke.sh` for authenticated Admin PWA browser screenshots using masked evidence-mode data.
- Run `scripts/collect_mobile_design_compliance_audit.sh --json` when route smoke evidence exists.
- Keep code-owned UI proof separate from Android device, Play, Supabase, signing, or production approval blockers.

## Current 10/10 Goal Status

Status: code-owned implementation complete for the current mobile design pass.

Owned completion evidence:

- All production member routes have fresh Flutter-rendered PNG evidence.
- Design compliance audit passes against the current route evidence.
- Dark/light parity, shared component semantics, analyzer, and focused widget
  tests pass.
- Public release, store submission, legal marketing copy, and final external
  approval remain separate governance actions, not code blockers.

Regression blockers to prevent from re-entering:

- Any page whose background does not match its mapped Revolut reference family.
- Any visible verbose helper copy that can be replaced by a concise label, icon,
  state, or one-line ellipsis.
- Any profile/avatar/action icon that is too dark, hidden, unclickable, or not
  semantically named.
- Any card that reads as a generic Material utility card instead of a
  finance-grade glass/media surface.
- Any member route with no fresh route screenshot evidence.
- Any admin mobile or desktop screen with clipped content, generic operational
  tables, or weak hierarchy.
- Any failed dark/light contrast or large-text route evidence.

The mirrored long-form design documentation is `docs/design/DESIGN_SYSTEM.md`.
