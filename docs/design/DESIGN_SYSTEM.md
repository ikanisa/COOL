# Collect Design System

## Principles

- Money first: every finance screen starts with the amount, progress, or payment state that matters most.
- MoMo-first: copy, examples, and payment flows assume RWF and MoMo/USSD where relevant.
- Collect ID only: member identity, receiver visibility, and SMS verification states are stated in plain language.
- Warm precision: user screens feel human; admin/risk screens stay dense and exact.
- Token-only implementation: screens compose centralized tokens and shared components rather than raw colors, spacing, radii, or font sizes.

## Color Model

Tokens live in `lib/app/theme/collect_colors.dart` and support light/dark schemes. The palette includes ink, navy, blue, aqua, coral, lime, purple, surface, border, success, warning, danger, info, textPrimary, and textSecondary.

## Layout Model

- 4/8 grid with `CollectSpacing`.
- Screen padding: 20 compact, 24 expanded.
- Card padding: 16 compact, 24 comfortable.
- Card radii: 20 and 24.
- Bottom sheet radius: 28.
- Shadows stay subtle and are defined in `CollectShadows`.

## Component Model

Core UI lives in shared widgets and consumes `CollectComponentTokens`. Feature screens should use components for buttons, cards, rows, banners, loading, empty, and error states.

## Brand Boundaries

No Revolut or Monzo visual assets, logos, exact colors, fonts, screen layouts, or trademarks are used. Collect owns its palette, copy, tokens, and product behavior.
