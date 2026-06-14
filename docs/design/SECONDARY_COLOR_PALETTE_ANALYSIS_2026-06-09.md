# Collect Secondary Color Palette Analysis

Date: 2026-06-09
Scope: Flutter mobile member app and shared Flutter web surfaces
Basis: `DESIGN.md`, `CollectColors`, live Settings screen review, design-system/accessibility audit, and contrast calculations.

## Executive Verdict

Keep the four primary colors exactly as they are:

| Role | Hex | Use |
| --- | --- | --- |
| Periwinkle | `#8885F0` | Brand lead, focus, privacy/info accent, gradient stop |
| Mint green | `#3CD070` | Positive brand accent, success accent, gradient stop |
| Dusty rose | `#D38B96` | Warm secondary brand accent, gradient stop, soft emotional tone |
| Orange red | `#FF5E43` | Main action accent, urgent accent, gradient stop |

The missing piece is not more primary color. The app needs a disciplined secondary system around those four colors: dark ink colors, pale glass/surface washes, border/divider colors, and darker semantic foregrounds for accessibility.

Paper `#FAF8F5` should stay the canvas/foundation color. Ink `#252044` should stay the high-contrast support token. Secondary colors should mostly be quiet support tokens that make the Revolut-style gradient/glass system feel premium, readable, and operational.

## Critical Findings

### 1. The primary paints are not accessible text colors

Contrast against Paper `#FAF8F5`:

| Color | Contrast vs Paper | Result |
| --- | ---: | --- |
| Periwinkle `#8885F0` | `2.97:1` | Fails normal text |
| Mint `#3CD070` | `1.90:1` | Fails normal text |
| Dusty rose `#D38B96` | `2.51:1` | Fails normal text |
| Orange red `#FF5E43` | `2.86:1` | Fails normal text |

This means primary paints should not be the default label/body color on Paper or pale glass panels. They should be accents, icons, outlines, chips, selected states, large decorative type, gradients, and non-text visual anchors.

### 2. White text on the primary paints is also weak

Contrast with white:

| Background | White contrast | Result |
| --- | ---: | --- |
| Periwinkle `#8885F0` | `3.15:1` | Fails normal text |
| Mint `#3CD070` | `2.01:1` | Fails normal text |
| Dusty rose `#D38B96` | `2.66:1` | Fails normal text |
| Orange red `#FF5E43` | `3.03:1` | Fails normal text |

For buttons and cards, use dark ink text or add darker overlay variants. Do not rely on white text over these paints for small labels.

### 3. The current direction is visually close but needs hierarchy discipline

The live Settings screen has the correct general mood: pastel gradient canvas, glass cards, rounded bottom navigation, and compact rows. The weakness is color hierarchy:

- Some list labels and icon treatments can read too close to accent color rather than text color.
- Border and glass colors are too tied to Periwinkle, which makes every panel feel equally important.
- Status colors need accessible foreground versions rather than using the bright brand paints directly.
- The palette needs a quiet neutral system so primary paints can become special again.

## Recommended Secondary Palette

### A. Ink Tokens

These should be the text and icon defaults.

| Token | Hex | Role | Contrast vs Paper |
| --- | --- | --- | ---: |
| `inkPrimary` | `#252044` | Primary headings, body, list labels, active nav label | `14.47:1` |
| `inkSecondary` | `#4B4664` | Secondary text, metadata, less prominent list copy | `8.40:1` |
| `inkMuted` | `#5F5A76` | Captions, helper text, disabled-but-readable labels | `6.17:1` |

Recommendation: keep these. They fit the four-color palette because they are a deep desaturated violet, not generic black or slate. This preserves the premium fintech feel without drifting into Material blue/gray.

### B. Surface And Glass Tokens

These should support the Revolut-style translucent layered UI.

| Token | Hex | Role |
| --- | --- | --- |
| `paper` | `#FAF8F5` | App canvas/foundation |
| `surface` | `#FFFDFB` | Highest readability panels, forms, legal/privacy text |
| `surfaceMuted` | `#F1ECF7` | Soft panels, inactive containers, empty states |
| `glassPanel` | `#FAF8F5` at `0.82` alpha | Primary translucent cards |
| `glassPanelStrong` | `#FAF8F5` at `0.90` alpha | Dense/legal/security panels needing stronger readability |
| `glassControl` | `#FAF8F5` at `0.76` alpha | Pills, nav, small controls |

Recommendation: do not introduce beige, gray, or white-only surfaces. Keep the Paper family, but add stronger surface variants so dense screens do not rely on low-contrast pastel panels.

### C. Border, Divider, And Focus Tokens

| Token | Hex | Role |
| --- | --- | --- |
| `borderSoft` | `#DED8EA` | Default dividers and card separators |
| `borderAccent` | `#CDC7F5` | Glass card outline and selected containers |
| `focusRing` | `#6F67E8` | Keyboard/focus state; darker than brand Periwinkle |
| `pressedScrim` | `#252044` at `0.08` alpha | Pressed/hover state on glass controls |

Recommendation: stop using Periwinkle itself for every border. Use `borderSoft` for ordinary structure and reserve `borderAccent` or `focusRing` for interactive/stateful emphasis.

### D. Accessible Semantic Foregrounds

The bright primary paints can remain brand/status accents, but semantic text/icons need darker paired foregrounds.

| Token | Hex | Role | Contrast vs Paper |
| --- | --- | --- | ---: |
| `successForeground` | `#137A3F` | Confirmed, granted, synced status text/icons | `5.10:1` |
| `infoForeground` | `#514DD2` | Info/privacy/accent status text/icons | `5.93:1` |
| `warningForeground` | `#B9472E` | Pending, needs attention, waiting status text/icons | `4.95:1` |
| `dangerForeground` | `#B3261E` | Failed, blocked, destructive status text/icons | `6.17:1` |

Semantic backgrounds:

| Token | Hex | Role |
| --- | --- | --- |
| `successContainer` | `#E7F8ED` | Success chip/card background |
| `infoContainer` | `#ECEBFF` | Info/privacy chip/card background |
| `warningContainer` | `#FFE9E3` | Waiting/review chip/card background |
| `dangerContainer` | `#FFE5DF` | Error/destructive chip/card background |
| `neutralContainer` | `#F1ECF7` | Neutral state chip/card background |

Recommendation: semantic foregrounds should be dark enough for text. Bright brand paints can still be used as decorative dots, progress fills, large icons, and background gradient ingredients.

### E. Derived Brand Tints

Use these for soft badges, avatar circles, and decorative fills. They should not replace the four primaries.

| Family | Soft tint | Strong tint |
| --- | --- | --- |
| Periwinkle | `#EFEEFF` | `#DCD9FF` |
| Mint | `#E8F9EF` | `#CFF3DD` |
| Rose | `#F8EDEF` | `#F0D7DC` |
| Orange | `#FFECE7` | `#FFD6CB` |

Recommendation: add these as generated/derived tokens or documented static tokens. They make the UI feel richer while keeping the four-color brand identity intact.

## What Not To Add

Do not add these as secondary palette colors:

- Generic Material blue, teal, amber, purple, or gray families.
- Black `#000000` for text; it is too harsh against the Paper/paint system.
- Pure white as the dominant surface; it breaks the warm Paper brand.
- More saturated accent colors such as cyan, lime, yellow, magenta, or royal blue.
- A dark navy/slate dashboard palette. It would fight the current warm gradient and make the app feel less Collect-owned.

## Recommended `CollectColors` Direction

Keep primary fields:

- `brandPeriwinkle`
- `brandMintGreen`
- `brandDustyRose`
- `brandOrangeRed`
- `brandPrimaryColors`
- `brandPrimaryHexes`

Add or formalize secondary fields:

- `inkPrimary`
- `inkSecondary`
- `inkMuted`
- `surfaceReadable`
- `surfaceMuted`
- `borderSoft`
- `borderAccent`
- `focusRing`
- `pressedScrim`
- `successForeground`
- `successContainer`
- `infoForeground`
- `infoContainer`
- `warningForeground`
- `warningContainer`
- `dangerForeground`
- `dangerContainer`
- `neutralContainer`

Update behavior:

- Body/list/card text uses `inkPrimary` or `inkSecondary`, never a primary paint.
- Primary colors remain for gradient stops, hero accents, selected icons, illustration accents, group colors, and major visual anchors.
- Status chips use semantic foreground/container pairs.
- Buttons using Orange should use `inkPrimary` text or a darker Orange action token, not white small text.
- Borders default to `borderSoft`; only selected/focus states use stronger Periwinkle-derived borders.

## Priority Implementation Plan

1. Add secondary token names in `CollectColors` without changing the four primary contract.
2. Replace `statusForeground()` bright returns with darker semantic foregrounds.
3. Replace ordinary card borders from `brandPeriwinkle` to `borderSoft`, leaving `borderAccent` for selected/focus states.
4. Ensure all Settings/list labels use `textPrimary`/`textSecondary`, not primary paint tokens.
5. Add tests asserting:
   - `brandPrimaryColors.length == 4`
   - Paper is not primary
   - text tokens meet contrast on Paper
   - semantic foregrounds meet at least `4.5:1` on Paper
6. Rerun web visual smoke and `collect_mobile_design_compliance_audit.sh`.

## Final Recommendation

The optimal premium palette is:

- Four primary paints only for brand expression.
- Paper as the single warm foundation.
- Violet-black ink for readable hierarchy.
- Pale Paper/lavender glass surfaces.
- Periwinkle-derived borders and focus states.
- Darker semantic foregrounds paired with pale semantic containers.

This keeps the app aligned with the Revolut-style reference principles: vivid gradient canvas, floating glass chrome, compact readable finance hierarchy, and disciplined operational surfaces. It also avoids copying Revolut colors or falling back into generic Material palettes.
