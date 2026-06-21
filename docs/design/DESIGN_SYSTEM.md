# Collect Design System

This file mirrors the enforceable contract in `DESIGN.md` and explains how it maps into code.

## Design Direction

The 11 Revolut screenshots in `/Users/jeanbosco/Downloads/Revolut10` are the active mobile UI/UX contract for fintech execution quality: vertical gradient page canvases, floating black glass controls, compact account/payment hierarchy, rounded bottom navigation, media-rich cards, and translucent content panels. Collect applies those patterns to its own product model: group collections, MoMo receiver setup, QR scan/share, contribution flows, member activity, profile, settings, notifications, and admin operations.

Collect does not copy Revolut or Monzo visual assets, logos, trademarks, component colors, fonts, screens, account labels, crypto/invest tabs, or product layouts. Screen-background colors are the explicit exception: they are matched to the supplied Revolut reference screenshots while the product, brand, copy, components, and assets remain Collect-owned.

## Principles

- Gradient first: member-facing screens render on `CollectGradientBackground`.
- Reference first: page backgrounds are route-mapped from the supplied Revolut screenshots and stay vertical, atmospheric, and full-screen.
- Distinct modes: light mode uses bright readable glass surfaces over the route gradients; dark mode uses night surfaces, pale text, darker borders, and stronger finance chrome. Both modes stay Revolut-like in gradient structure while using Collect-owned components.
- Money first: every finance screen starts with the amount, progress, contribution, or payment state that matters most.
- MoMo-first: copy, examples, and payment flows assume RWF and MoMo/USSD where relevant.
- Collect ID only: member identity, receiver visibility, and SMS verification states are privacy-safe. Payment-state screenshots must use masked MoMo display such as `+250***3456`, not full receiver numbers.
- Glass chrome: bottom navigation, bottom sheets, action buttons, search fields, and filters use translucent tokenized surfaces.
- Top chrome: profile, search, and action controls are compact, visible, tappable, and semantically named. Profile controls route to profile.
- Bottom dock: navigation remains Collect-owned in destination mapping, but visually follows the Revolut floating black glass dock with a selected capsule, one-line labels, stable touch targets, and safe-area anchoring.
- Plain route headers: shared secondary-route headers use a back arrow, one-line title, optional one-line subtitle, and tokenized action circles. They must not be decorative brand cards on utility, legal, permission, profile, create, or scanner routes.
- Rich surfaces: home, Home Momentum, group, contribution, payment-state, settings, privacy, support, notification, and legal surfaces use Collect-owned generated visuals where the Revolut reference uses media, marketplace, reward, or product cards. Image-less group cards use generated Collect media instead of blank covers.
- Compact labels: visible labels, helper text, chips, card titles, table cells, and admin status copy stay one line with ellipsis when constrained. Avoid explanatory in-app paragraphs where a concise label, state, icon, or command is enough.
- Warm precision: user screens feel premium and human; admin/risk screens stay dense and exact.
- Token-only implementation: screens compose centralized tokens and shared components rather than raw colors, spacing, radii, or font sizes.
- MOBI benchmark: use `/Volumes/PRO-G40/MOBI/mobi_app` as the process reference for route matrices, shared shell primitives, route visual coverage, and current evidence gates. Do not paste MOBI UI code or product concepts into Collect.

## Token Map

Tokens live in `lib/app/theme/collect_colors.dart`.

- Primary palette: Periwinkle `#8885F0`, Mint `#3CD070`, Rose `#D38B96`, Orange `#FF5E43`.
- Canvas: Paper `#FAF8F5`.
- Page canvas: `screenBase`, `screenGradient`, and `adminScreenGradient` use extracted Revolut reference background colors: Account Navy `#000840`, Payments Purple `#181038`, Asset Navy `#101830`, Rewards Violet `#302878`, Wealth Teal `#102028`, and Stock Teal-Black `#001010`. Paper remains the brand and launch foundation, not the runtime screen canvas.
- Theme modes: `CollectColors.light` and `CollectColors.dark` intentionally differ in surfaces, text, borders, semantic containers, and glass values. `AppTheme.light()` and `AppTheme.dark()` are both registered by member and admin apps through the persisted `collectThemeModeProvider`, which defaults to dark and exposes an in-app Settings toggle.
- Glass surfaces: `glassPanel`, `glassPanelStrong`, `glassControl`, `glassBorder`, `glassPanelGradient`.
- Secondary/support palette: Ink Primary `#252044`, Ink Secondary `#4B4664`, Ink Muted `#5F5A76`, Surface Readable `#FFFDFB`, Surface Muted `#F1ECF7`, Border Soft `#DED8EA`, Border Accent `#CDC7F5`, Focus Ring `#6F67E8`.
- Semantic palette: Success Foreground `#137A3F` on `#E7F8ED`, Info Foreground `#514DD2` on `#ECEBFF`, Warning Foreground `#B9472E` on `#FFE9E3`, Danger Foreground `#B3261E` on `#FFE5DF`, Neutral Container `#F1ECF7`.
- Runtime contrast: `actionColor`, `success`, `warning`, `danger`, `info`, `textPrimary`, `textSecondary`, `textMuted`, `statusForeground()`, and `statusBackground()`.
- No legacy pastel, generic neutral, Material blue, or alternate low-luminance palette is part of the active token contract.

Do not add route-level gradients in feature files unless the route is a standalone visual/export surface and still uses Collect tokens.

### Route Background Map

`CollectColors.screenGradientForPath()` is the enforceable route map for the supplied Revolut background families:

| Reference screenshots | Background colors | Route family |
| --- | --- | --- |
| `IMG_2739.PNG` | `#0818A0`, `#0F198E`, `#000838`, `#000030` | Home, onboarding, auth |
| `IMG_2741.PNG`, `IMG_2747.PNG`, `IMG_2750.PNG` | `#302848`, `#181038`, `#100820` | Groups, group detail, member/share entry points, public group links |
| `IMG_2742.PNG`, `IMG_2748.PNG` | `#303870`, `#202858`, `#101830`, `#000818` | Contribution, payment status, payment state, support payment, ledger |
| `IMG_2749.PNG` | `#9838F0`, `#7050E8`, `#302878`, `#100820` | Group QR/share, invite/share recovery, settings root |
| `IMG_2740.PNG` | `#204050`, `#183848`, `#102028`, `#081820` | Group creation, profile, readiness, SMS/device/camera/notification permission recovery, iPhone create-unavailable |
| `IMG_2751.PNG`, `IMG_2752.PNG` | `#303020`, `#181038`, `#101018` | Settings account, privacy, help, legal |
| `IMG_2755.PNG` | `#202828`, `#102028`, `#001010` | Offline and sync |

The current route is provided by `CollectBackgroundRouteScope` in the shell and consumed by `CollectGradientBackground`, so shared scaffolds inherit the correct background without duplicating gradients in feature files.

## Asset Map

- Launcher/app icon: `assets/brand/collect_app_icon_static.png`.
- Generated icon rule: `assets/brand/generated/collect_app_icon_rule.png`.
- Mobile wordmark: `assets/brand/generated/collect_wordmark_transparent.png`.
- Reference sheet: `assets/brand/generated/collect_logo_color_variants_sheet.png`.
- MoMo signal visual: `assets/brand/generated/collect_visual_momo_signal.png`.
- Group momentum visual: `assets/brand/generated/collect_visual_group_momentum.png`.
- QR share visual: `assets/brand/generated/collect_visual_qr_share.png`.
- Corrected transparent wordmark source: `assets/brand/source_variants/collect_wordmark_transparent_4096.png`.
- Corrected transparent app mark source: `assets/brand/source_variants/collect_mark_transparent_4096.png`.
- Corrected gradient logo source: `assets/brand/source_variants/collect_logo_gradient_4096.png`.
- Supplied checkerboard preview retained as source evidence only: `assets/brand/source_variants/collect_logo_preview_checkerboard_1254.png`.

`CollectBrandMark` owns in-app brand rendering. Feature screens should not hand-place app icon or wordmark assets directly unless the output is an exported/shareable artifact.

## Component Model

Use the shared primitives before local UI:

- `CollectGradientBackground`, `PremiumScaffold`, `ScreenScaffold`, `ScreenScaffoldLayout`.
- `CollectBrandMark`.
- `ScreenHeader` and `CollectPlainPageHeader` provide the shared plain header for secondary routes: back arrow, one-line title, optional one-line subtitle, and no decorative card shell.
- `CollectCard`, `CollectVisualFeatureCard`, `CollectBentoGrid`, `BentoMetricCell`, `GroupCard`.
- `CollectButton`, `SearchWithClearField`, `PremiumSegmentedFilter`.
- Home rich visual rail cards, Home Momentum cards, image-backed `GroupCard` covers, and `CollectVisualFeatureCard` use runtime assets from `assets/brand/generated/` and Flutter-rendered text.
- QR scanner surfaces use the shared plain header plus a camera-first preview with dark overlay, corner guides, torch and camera-switch icon controls, gallery QR decoding where supported, and compact link/code entry fallback. Fallback copy must stay about group links/codes, not payment proof.
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
- Permission routes are recovery/status surfaces only. Native SMS, camera, gallery, and notification prompts are triggered by the related action flow: group creation, QR scanning/gallery import, or notification enablement.

## Layout Model

- 4/8 grid with `CollectSpacing`.
- Screen padding: 20 compact, 24 expanded.
- Card padding: 16 compact, 24 comfortable.
- Card radii: 24 and 28.
- Controls: pill by default for mobile CTAs, chips, and fintech chrome.
- Labels: one line by default with ellipsis for bounded controls, cards, chips, and tables.
- Bottom sheet radius: 28.
- Shadows stay subtle and are defined in `CollectShadows`.

## Accessibility

- Minimum touch targets: Android 48x48 and iOS 44x44 logical pixels.
- Text must survive 200% scaling without clipped critical actions. Rich Home cards must expose semantics for amount/progress/supporter context while preserving masked/private receiver data.
- Custom controls require semantics labels or tooltips.
- Status cannot be color-only.
- Motion must respect `CollectMotion`.

## Compliance Gates

- `dart format` on touched Dart files.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`.
- Focused widget tests for shared components and shell.
- Focused dark/light widget checks for shell, top chrome, cards, and route background families, including `test/features/theme_mode_visual_parity_test.dart`.
- `scripts/mobile_route_render_smoke.sh` for all production member routes.
  It builds with sanitized fixture evidence mode through
  `COLLECT_MOBILE_EVIDENCE_MODE=true`, so screenshots show realistic Collect
  groups, balances, payment states, and activity without using production data.
- `scripts/android_route_visual_evidence.sh` for physical Android route PNG evidence and route contact sheets when device proof is required or local Chromium/CDP is unavailable.
- `scripts/admin_pwa_authenticated_render_smoke.sh` for authenticated Admin PWA browser PNG evidence with masked evidence-mode data.
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 scripts/collect_visual_evidence_capture.sh` for non-Chrome member-shell PNG/contact-sheet evidence when local Chromium/CDP is unavailable.
- `scripts/collect_mobile_design_compliance_audit.sh --json` to verify the palette, docs, shared gradient ownership, dark/light theme parity gate, route screenshot coverage, and Android evidence when available.

## 10/10 Parity Ownership

The current mobile design pass is code-owned complete when the implementation
passes analyzer, focused widget/accessibility checks, visual route evidence, and
the design compliance audit. External release approval, store submission, or
public marketing claims remain governance actions, not engineering blockers.

Keep these as regression blockers so they do not re-enter:

- A route uses a generic or unmapped page background.
- A first viewport lacks a dominant amount, group, QR/share, profile, or payment
  state.
- Top chrome profile/action controls are visually hidden, unclickable, or
  missing semantics.
- Bottom navigation looks like a generic app nav instead of anchored fintech
  glass chrome.
- Cards look like plain Material cards instead of translucent finance/media
  surfaces.
- Labels wrap where the contract requires one-line ellipsis.
- Dark and light modes are not visually distinguishable.
- Any production member route, Admin PWA mobile viewport, or Admin PWA desktop
  viewport lacks fresh screenshot evidence.
