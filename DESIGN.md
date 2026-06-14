---
name: Collect
updated: 2026-06-08
scope: Flutter mobile member app and Flutter web surfaces that share the Collect theme
reference-contract: Revolut screenshots supplied on 2026-06-08 are a UI/UX reference for gradient fintech screens, glass controls, compact finance hierarchy, and thumb-first chrome.
brand-assets:
  launcher-icon: assets/brand/collect_app_icon_static.png
  app-icon-rule: assets/brand/generated/collect_app_icon_rule.png
  mobile-wordmark: assets/brand/generated/collect_wordmark_transparent.png
  reference-sheet: assets/brand/generated/collect_logo_color_variants_sheet.png
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

Collect must feel like a modern fintech mobile app while staying fully Collect-owned. The attached Revolut screenshots are the design reference for quality and structure: gradient page backgrounds, translucent cards, glass pill controls, compact top chrome, clear money hierarchy, rounded bottom navigation, and dense but readable account/payment surfaces. They are not a license to copy Revolut assets, copy, trademarks, icons, colors, exact layouts, or product behavior.

## Non-Negotiables

- Every member-facing production route must render on a gradient background derived from Collect's four primary colors over the Paper canvas.
- Collect keeps four primary colors from the corrected brand assets: Periwinkle `#8885F0`, Mint `#3CD070`, Rose `#D38B96`, and Orange `#FF5E43`.
- Paper `#FAF8F5` is the canvas/foundation color. It is not counted as a primary color.
- Ink `#252044` is the high-contrast text/chrome anchor. It is a support token, not a primary color.
- Secondary/support colors are allowed only as named UI tokens for readable surfaces, borders, focus, and semantic status foreground/container roles. They do not replace or expand the four primary colors.
- Use Collect brand assets only: `CollectBrandMark` renders `assets/brand/generated/collect_wordmark_transparent.png`; launcher/platform icon use stays on generated PNG icon assets.
- Route surfaces must use `ScreenScaffold`, `ScreenScaffoldLayout`, `PremiumScaffold`, or `CollectGradientBackground`.
- Standalone flows that bypass `ScreenScaffold`, such as share/QR export surfaces, must explicitly wrap their page in `CollectGradientBackground`.
- Visible page chrome uses glass tokens: `glassPanel`, `glassPanelStrong`, `glassControl`, and `glassBorder`.
- Primary mobile tabs remain `Home`, `Groups`, and `Settings`.
- Identity remains privacy-safe: Collect ID only. Do not expose raw phone numbers, raw SMS, PINs, OTPs, MoMo transaction IDs, or public member names.
- Admin surfaces may stay dense and operational, but member-facing mobile screens must not revert to generic Material blue, legacy color shells, crypto/wallet branding, or admin-style dashboards.

## Reference Translation

Use the screenshots for these patterns:

- Gradient canvas: every screen starts with a full-height gradient field built from the four primary colors over Paper.
- Top chrome: brand/search/action areas read as compact floating pills or glass controls, not flat app bars.
- Bottom navigation: rounded, translucent, fixed, thumb-first, and visually separated from the gradient.
- Finance hierarchy: the main amount, state, group, or payment action is obvious within the first viewport.
- Cards: content sits on translucent glass surfaces with subtle borders and blur; cards should not fully hide the gradient.
- CTAs: buttons are large, pill-like, reachable, and high-contrast.
- Lists: rows stay compact and scannable, with clear leading icons/avatars and right-aligned amounts/status where relevant.

Do not copy these elements:

- Revolut logo, trademarks, iconography, text, tab names, exact colors, exact card order, account names, crypto/invest labels, or screenshots.
- Any brand palette outside Collect's approved four primary colors, Paper canvas, and named support tokens.

## Color And Gradient Tokens

`CollectColors` is the source of truth.

- `brandPrimaryColors` and `brandPrimaryHexes` lock the four approved primary colors in reference order.
- `screenBase` and `screenGradient` own the page background.
- `glassPanel`, `glassPanelStrong`, `glassControl`, `glassBorder`, and `glassPanelGradient` own translucent surfaces and chrome.
- `surfaceReadable`, `surfaceMuted`, `borderSoft`, `borderAccent`, `focusRing`, and the `semantic*` token constants provide the secondary/support palette.
- `actionColor` remains Orange Red for primary action fills; `success`, `warning`, `danger`, `info`, and status helpers resolve to contrast-safe semantic foregrounds and containers.

Screens should not build page gradients locally. Feature-specific gradients are allowed only for cards, QR assets, cover media, and accent treatments, and they must use Collect tokens.

## Asset Contract

- `assets/brand/collect_app_icon_static.png`: launcher/app icon source.
- `assets/brand/generated/collect_app_icon_rule.png`: generated icon rule reference.
- `assets/brand/generated/collect_wordmark_transparent.png`: in-app mobile wordmark used by `CollectBrandMark`.
- `assets/brand/generated/collect_logo_color_variants_sheet.png`: static color reference sheet.
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
- Cards: `CollectCard` with glass opacity, `CollectBentoGrid`, `BentoMetricCell`, `GroupCard`.
- Controls: `CollectButton`, `SearchWithClearField`, `PremiumSegmentedFilter`, icon buttons styled with `colors.glassControl`.
- Bottom surfaces: `CollectBottomSheet`, `BottomActionSurface`.
- State: `LoadingStatePanel`, `EmptyIllustrationState`, `CollectErrorState`, `InfoSecurityBanner`.
- Payments: `CollectDynamicIsland`, `PaymentPipelineIndicator`, `PaymentVerifiedRing`.

Feature screens may add local layout, but not local design language. If a feature needs a new visual pattern, add it to shared components or tokens first.

## Route Coverage

The production member route list in `lib/app/router.dart` is the design scope. The route-render smoke must cover every registered production route, including onboarding, auth, home, groups, share, payment states, settings, privacy, permissions, offline, notifications, and sync.

Camera preview overlays use tokenized Periwinkle scrims because they sit on top of live camera pixels. Their visible instructional controls still use Collect glass tokens.

## Accessibility And Responsive Rules

- Minimum touch targets: 48x48 logical pixels on Android and 44x44 on iOS.
- Text must survive 200% scaling without clipping critical actions.
- Status must never be color-only; pair color with text and iconography.
- Icon-only controls require tooltips/semantics.
- Motion uses `CollectMotion` and respects reduced-motion settings.
- Screens must render at 390x844 mobile viewport and adapt to compact phones, tall phones, landscape, tablets, and foldables.

## Quality Gates

Before claiming design parity:

- Format touched Dart files with `/Volumes/PRO-G40/flutter_3_44/bin/dart format`.
- Run `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`.
- Run focused widget tests for theme tokens, brand mark, shared components, shell, and touched routes.
- Run `scripts/mobile_route_render_smoke.sh` for all production routes.
- Run `scripts/collect_mobile_design_compliance_audit.sh --json` when route smoke evidence exists.
- Keep code-owned UI proof separate from Android device, Play, Supabase, signing, or production approval blockers.

The mirrored long-form design documentation is `docs/design/DESIGN_SYSTEM.md`.
