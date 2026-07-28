# Design System Inventory

## Implemented foundation

| Area | Current source | Current status |
|---|---|---|
| Runtime font | `lib/app/theme/collect_runtime_typography.dart` | Inter configured |
| Flutter font asset | `assets/typefaces/Inter-Variable.ttf` | Bundled |
| Typography | `lib/app/theme/collect_typography.dart`, all `lib/` consumers, `web/index.html`, and `scripts/public_static_site_build.rb` | Inter-only 400-700 hierarchy enforced; raw feature-level typography removed |
| Official brand source | `assets/brand/collect_runtime/app_icons/app-icon-rule.png` | Canonical four-node PNG pinned by SHA-256 |
| Platform icons | Android mipmaps/drawable, iOS AppIcon, web/Admin PNG | Official source derivatives restored and hash-gated; invented `C`/SVG art forbidden |
| Colors and gradients | `lib/app/theme/collect_colors.dart`, `lib/app/theme/collect_theme.dart`, `test/features/theme_contrast_contract_test.dart` | Route-aware palette plus numeric 4.5:1 text and 3:1 essential-control/focus contracts pass in light, dark, and high-contrast modes |
| Spacing | `lib/app/theme/collect_spacing.dart`, `test/features/interaction_target_contract_test.dart` | Central 48 dp primary and 44 dp dense-icon targets enforced across member/public/Admin widget scope |
| Radius | `lib/app/theme/collect_radius.dart` | Routine/featured/sheet radii revised |
| Theme | `lib/app/theme/collect_theme.dart` | Light/dark ThemeData present |
| Shell | `lib/core/widgets/collect_shell.dart` | Five-destination compact shell implemented |
| Top chrome and hero | `lib/shared/widgets/collect_scaffold_chrome.dart` | Revised; semantics improved |
| Dense group list | `lib/shared/widgets/collect_group_cards.dart` | Implemented |
| Financial rows | `lib/shared/widgets/collect_financial_*` | Implemented; state coverage plus Home/Group Detail/Ledger goldens pass |
| Shared list tiles | `lib/shared/widgets/collect_feature_surfaces.dart` | Explicit button semantics added |
| Inputs | `lib/shared/widgets/collect_inputs.dart` | Ledger focus support added |
| Sheets | Shared widget library | Geometry review open |
| Public site font | `web/index.html`, `scripts/public_static_site_build.rb` | Inter declared |

## Open system work

- Complete remaining native/browser high-contrast validation and
  physical-device reduced-motion comfort confirmation.
- Complete five-destination responsive validation across the device matrix.
- Extend the current 13-surface golden matrix only when a new material shared
  component or dense screen is introduced.
- Verify hover/pressed/disabled states, focus restoration, live regions, and
  the locally enforced target sizes on real native/browser renderers.
- Ensure every state surface inherits the final geometry.
