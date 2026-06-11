# Collect Design System

This file mirrors the enforceable contract in `DESIGN.md` and explains how it maps into code.

## Design Direction

The 2026-06-08 Revolut screenshots are a reference for mobile fintech quality: gradient page canvases, floating glass controls, compact account/payment hierarchy, rounded bottom navigation, and translucent content panels. Collect applies those principles with its own product model, assets, copy, four primary paint colors, Paper canvas, and selected supporting surface/status tokens.

Collect does not copy Revolut or Monzo visual assets, logos, trademarks, exact colors, fonts, screens, account labels, crypto/invest tabs, or product layouts.

## Principles

- Gradient first: member-facing screens render on `CollectGradientBackground`.
- Money first: every finance screen starts with the amount, progress, contribution, or payment state that matters most.
- MoMo-first: copy, examples, and payment flows assume RWF and MoMo/USSD where relevant.
- Collect ID only: member identity, receiver visibility, and SMS verification states are privacy-safe.
- Glass chrome: bottom navigation, bottom sheets, action buttons, search fields, and filters use translucent tokenized surfaces.
- Warm precision: user screens feel premium and human; admin/risk screens stay dense and exact.
- Token-only implementation: screens compose centralized tokens and shared components rather than raw colors, spacing, radii, or font sizes.

## Token Map

Tokens live in `lib/app/theme/collect_colors.dart`.

- Primary paint palette: Periwinkle `#8885F0`, Mint `#3CD070`, Rose `#D38B96`, Orange `#FF5E43`.
- Canvas: Paper `#FAF8F5`.
- Page canvas: `screenBase`, `screenGradient`.
- Glass surfaces: `glassPanel`, `glassPanelStrong`, `glassControl`, `glassBorder`, `glassPanelGradient`.
- Secondary/support palette: Ink Primary `#252044`, Ink Secondary `#4B4664`, Ink Muted `#5F5A76`, Surface Readable `#FFFDFB`, Surface Muted `#F1ECF7`, Border Soft `#DED8EA`, Border Accent `#CDC7F5`, Focus Ring `#6F67E8`.
- Semantic palette: Success Foreground `#137A3F` on `#E7F8ED`, Info Foreground `#514DD2` on `#ECEBFF`, Warning Foreground `#B9472E` on `#FFE9E3`, Danger Foreground `#B3261E` on `#FFE5DF`, Neutral Container `#F1ECF7`.
- Runtime contrast: `actionColor`, `success`, `warning`, `danger`, `info`, `textPrimary`, `textSecondary`, `textMuted`, `statusForeground()`, and `statusBackground()`.
- No legacy pastel, generic neutral, Material blue, or alternate low-luminance palette is part of the active token contract.

Do not add route-level gradients in feature files unless the route is a standalone visual/export surface and still uses Collect tokens.

## Asset Map

- Launcher/app icon: `assets/brand/collect_app_icon_static.png`.
- Generated icon rule: `assets/brand/generated/collect_app_icon_rule.png`.
- Mobile wordmark: `assets/brand/generated/collect_wordmark_transparent.png`.
- Reference sheet: `assets/brand/generated/collect_logo_color_variants_sheet.png`.
- Corrected transparent wordmark source: `assets/brand/source_variants/collect_wordmark_transparent_4096.png`.
- Corrected transparent app mark source: `assets/brand/source_variants/collect_mark_transparent_4096.png`.
- Corrected gradient logo source: `assets/brand/source_variants/collect_logo_gradient_4096.png`.
- Supplied checkerboard preview retained as source evidence only: `assets/brand/source_variants/collect_logo_preview_checkerboard_1254.png`.

`CollectBrandMark` owns in-app brand rendering. Feature screens should not hand-place app icon or wordmark assets directly unless the output is an exported/shareable artifact.

## Component Model

Use the shared primitives before local UI:

- `CollectGradientBackground`, `PremiumScaffold`, `ScreenScaffold`, `ScreenScaffoldLayout`.
- `CollectBrandMark`.
- `CollectCard`, `CollectBentoGrid`, `BentoMetricCell`, `GroupCard`.
- `CollectButton`, `SearchWithClearField`, `PremiumSegmentedFilter`.
- `CollectBottomSheet`, `BottomActionSurface`.
- `LoadingStatePanel`, `EmptyIllustrationState`, `CollectErrorState`, `InfoSecurityBanner`.
- `CollectDynamicIsland`, `PaymentPipelineIndicator`, `PaymentVerifiedRing`.

Feature-level widgets may control content density and order, but not introduce a separate visual language.

## Route Rules

- All production member routes registered in `lib/app/router.dart` must be covered by the route render smoke.
- Routes under `ScreenScaffold` inherit the gradient through `PremiumScaffold`.
- Shell routes inherit the gradient through `CollectShell`.
- Standalone routes such as share/export screens must wrap their page with `CollectGradientBackground`.
- Camera preview scrims use tokenized Periwinkle overlays because they sit on top of live camera pixels; their visible labels and panels still use glass tokens.

## Layout Model

- 4/8 grid with `CollectSpacing`.
- Screen padding: 20 compact, 24 expanded.
- Card padding: 16 compact, 24 comfortable.
- Card radii: 24 and 28.
- Controls: pill by default for mobile CTAs, chips, and fintech chrome.
- Bottom sheet radius: 28.
- Shadows stay subtle and are defined in `CollectShadows`.

## Accessibility

- Minimum touch targets: Android 48x48 and iOS 44x44 logical pixels.
- Text must survive 200% scaling without clipped critical actions.
- Custom controls require semantics labels or tooltips.
- Status cannot be color-only.
- Motion must respect `CollectMotion`.

## Compliance Gates

- `dart format` on touched Dart files.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`.
- Focused widget tests for shared components and shell.
- `scripts/mobile_route_render_smoke.sh` for all production member routes.
- `scripts/collect_mobile_design_compliance_audit.sh --json` to verify the palette, docs, shared gradient ownership, route screenshot coverage, and Android evidence when available.
