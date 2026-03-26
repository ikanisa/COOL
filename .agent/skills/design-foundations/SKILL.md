---
name: Design Foundations
description: >
  Visual design tokens, theme architecture, color system, typography scale,
  spacing, surface language, and fixed-color exceptions for the COOL Flutter
  super-app. Use when working on colors, fonts, spacing, radius, theme
  switching, or token definitions. Source of truth: DESIGN_SYSTEM.md §1–6.
---

# Design Foundations

Use this skill when the task involves:

- Creating, modifying, or auditing color tokens
- Changing typography (font, scale, weight)
- Adjusting spacing or radius values
- Working on surface/card/sheet styling (claymorphism, glassmorphism)
- Shadow recipes, elevation, or blur values
- Gradient tokens or gradient usage
- Theme switching, light/dark mode, or theme extensions
- Partner-specific visual overrides (Rayon typography, brand palette)
- Fixed-color exception review (QR, PDF, status bar)
- Responsive breakpoints or layout spacing

This skill is NOT for:

- Screen layout or information hierarchy → use `screen-composition`
- Shared widgets or routing → use `component-navigation`
- Module-specific UX decisions → use `module-partner-ux`

## Design Philosophy

COOL targets a refined, institutional aesthetic — closer to a premium banking
app or a high-end sports club membership. Not a decorated fintech startup.

Core principles:

1. **Authority** — every surface projects confidence and control.
2. **Premium minimalism** — fewer elements, larger type, generous space, quiet surfaces.
3. **Trust-first** — money, identity, permissions, and system state are always explicit.
4. **Token-driven** — every color, spacing, radius, shadow, and type value comes from a named token.
5. **Maximum typography** — text should feel oversized, heavy, and commanding everywhere.

## Product Truths

These are non-negotiable constraints the visual system must accommodate:

- Flutter mobile, Android-first, dark-first, EN/FR.
- Portrait-only by product decision.
- Dual-theme (light + dark) — both are first-class citizens with warm earthy tones.
- Pending, draft, posted, blocked, offline, disabled states shown honestly.
- Widgets render. Providers coordinate state. Repositories own Supabase access.

---

## Color System — `CoolSemanticColors`

The production redesign uses `CoolSemanticColors` (in `cool_foundations.dart`),
not the legacy `CoolPalette`. All new and migrated screens must use semantic
tokens.

### Dark Theme

| Token | Role | Value |
|---|---|---|
| `appBackground` | App background | `#070B09` (deep green-black) |
| `elevatedBackground` | Elevated bg | `#0D110E` |
| `cardSurface` | Primary card | `#141A16` |
| `cardSurfaceStrong` | Emphasized card | `#1B221D` |
| `glassSurface` | Glass overlay | `#111713` at 82% opacity |
| `overlaySurface` | Modal/sheet bg | `#111713` |
| `primaryText` | Primary text | `#F4F1E9` (warm white) |
| `secondaryText` | Secondary text | `#C4CBC2` |
| `tertiaryText` | Tertiary/disabled | `#909B91` |
| `accent` | Primary action | `#3A8A5E` (forest green) |
| `accentStrong` | Emphasized accent | `#173726` |
| `accentForeground` | Text on accent | `#F7F3EA` |
| `divider` | Section separators | `#FFFFFF` at 8% |
| `border` | Subtle borders | `#FFFFFF` at 12% |
| `borderStrong` | Emphasized borders | `#FFFFFF` at 20% |

### Light Theme

| Token | Role | Value |
|---|---|---|
| `appBackground` | App background | `#F3F0EA` (warm cream) |
| `elevatedBackground` | Elevated bg | `#FCFAF6` |
| `cardSurface` | Primary card | `#F7F2EA` (warm ivory) |
| `cardSurfaceStrong` | Emphasized card | `#FFFDF9` |
| `glassSurface` | Glass overlay | `#FFFCF7` at 84% opacity |
| `overlaySurface` | Modal/sheet bg | `#FBF8F2` |
| `primaryText` | Primary text | `#0B0F0D` (deep green-black) |
| `secondaryText` | Secondary text | `#465147` |
| `tertiaryText` | Tertiary/disabled | `#6D776E` |
| `accent` | Primary action | `#2F7252` (deep forest green) |
| `accentStrong` | Emphasized accent | `#103322` |
| `accentForeground` | Text on accent | `#F8F5EE` |
| `divider` | Section separators | `#0B0F0D` at 8% |
| `border` | Subtle borders | `#0B0F0D` at 12% |
| `borderStrong` | Emphasized borders | `#0B0F0D` at 18% |

### Semantic State Colors

| Token | Dark | Light | Purpose |
|---|---|---|---|
| `success` | `#58A67B` | `#2F7252` | Positive/complete |
| `warning` | `#D09A4D` | `#A86F26` | Attention/caution |
| `danger` | `#D0727A` | `#A24C54` | Error/destructive |
| `info` | `#7E9CBC` | `#4C6886` | Informational |
| `neutral` | `#98A199` | `#737B74` | Neutral/disabled |

### UI-Specific Tokens

| Token | Purpose |
|---|---|
| `chipBackground` | Chip resting state |
| `chipSelectedBackground` | Chip selected state |
| `buttonPrimaryBackground` | Primary CTA fill |
| `buttonSecondaryBackground` | Secondary button fill |
| `inputSurface` | Text field background |

### Domain-Specific Surface Tokens

These warm-tinted backgrounds distinguish product domains visually:

| Token | Dark | Light | Use |
|---|---|---|---|
| `operationalSurface` | `#0F1814` | `#EEF2F0` | Admin dashboards, ops containers |
| `financialSurface` | `#0E1712` | `#EDF4EF` | Wallets, payments, statements |
| `analyticsSurface` | `#101721` | `#EEF1F5` | Data, analytics panels |
| `teamSurface` | `#151320` | `#F1EEF6` | Team, sports, club containers |
| `commerceSurface` | `#1A1713` | `#F5F0E8` | Marketplace, listings |
| `routeSurface` | `#121814` | `#F1ECE4` | Route summaries, journeys |
| `proximitySurface` | `#0E1813` | `#E7F0EA` | Nearby, proximity indicators |
| `contactSurface` | `#10201A` | `#EAF3ED` | Contact, WhatsApp CTAs |

### Demand Indicators

| Token | Dark | Light | Use |
|---|---|---|---|
| `demandHigh` | `#D0727A` | `#A24C54` | High demand / surge |
| `demandMedium` | `#D09A4D` | `#A86F26` | Moderate demand |
| `demandLow` | `#58A67B` | `#2F7252` | Low demand / available |

### Color Rules

- Reserve accent for primary CTA, active state, or critical status. Not everywhere.
- Never rely on color alone for status. Always pair with icon, label, or shape.
- No glow-heavy or neon-heavy surfaces.
- Stronger brand colors only on partner surfaces that need them.
- Use domain-specific surface tokens to distinguish product categories without heavy color.
- Green success chips must not appear on partner routes with their own brand system.

### Theme Parity

Both themes use a **warm, earthy tone** — cream/ivory in light, green-tinted
darks in dark mode. Both are first-class. Every screen, component, and state
must work in both. The theme toggle must not require manual color overrides.

### Fixed-Color Exceptions

| Location | Color | Reason |
|---|---|---|
| QR code generation/scanning | `Colors.black` / `Colors.white` | Scanner accuracy |
| PDF export surfaces | `Colors.white` | Print fidelity |
| Status bar overlays | `Colors.black` / `Colors.white` | System chrome |

All other colors must use semantic tokens from `CoolSemanticColors`.

---

## Gradient System

`CoolSemanticColors` provides 3 gradient token pairs with convenience getters:

| Gradient | Getter | Direction | Use |
|---|---|---|---|
| Shell | `shellGradient` | Top → Bottom | Full-screen background atmosphere |
| Surface | `surfaceGradient` | TopLeft → BottomRight | Card/container subtle gradient |
| Accent | `accentGradient` | TopLeft → BottomRight | CTA buttons, accent surfaces |

### Gradient Values

| Gradient | Light Top | Light Bottom | Dark Top | Dark Bottom |
|---|---|---|---|---|
| Shell | `#FAF7F2` | `#ECE5DA` | `#141915` | `#060806` |
| Surface | `#FFFDF9` | `#F2ECE3` | `#1A211C` | `#0E120F` |
| Accent | `#2F7252` | `#103322` | `#3A8A5E` | `#173726` |

### Gradient Rules

- Shell gradient: background atmosphere only. Subtle shift, never distracting.
- Surface gradient: adds premium depth to cards/containers. Keep direction consistent.
- Accent gradient: for primary CTAs and accent surfaces. Deepens authority.
- Never stack gradient + heavy shadow + glow on the same element.
- Gradients must work in both themes — both sets are pre-defined.

### Usage

```dart
final sem = context.coolSemanticColors;
Container(
  decoration: BoxDecoration(gradient: sem.shellGradient),
)
```

---

## Shadow System — `CoolShadows`

Three brightness-adaptive shadow recipes, each with adjustable strength:

### Clay Shadow (Claymorphism)

Dual-shadow recipe: **down shadow + inner highlight** for tactile, premium feel.

```dart
CoolShadows.clay(brightness, strength: 1)
```

| Parameter | Dark Mode | Light Mode |
|---|---|---|
| Shadow 1 color alpha | 0.34 | 0.10 |
| Shadow 1 blur | 28 | 28 |
| Shadow 1 spread | -14 | -14 |
| Shadow 1 offset | (0, 18) | (0, 18) |
| Highlight color alpha (white) | 0.05 | 0.68 |
| Highlight blur | 12 | 12 |
| Highlight spread | -10 | -10 |
| Highlight offset | (-3, -4) | (-3, -4) |

Use for: primary cards, buttons, icon containers, selectors, tiles, panels.

### Glass Shadow (Glassmorphism)

Single softer shadow for glass/translucent overlay surfaces.

```dart
CoolShadows.glass(brightness, strength: 1)
```

| Parameter | Dark Mode | Light Mode |
|---|---|---|
| Color alpha | 0.26 | 0.10 |
| Blur | 32 | 32 |
| Spread | -16 | -16 |
| Offset | (0, 18) | (0, 18) |

Use for: overlays, floating filter bars, bottom sheets, modals.

### Floating Shadow

Strongest shadow for floating/elevated elements.

```dart
CoolShadows.floating(brightness, strength: 1)
```

| Parameter | Dark Mode | Light Mode |
|---|---|---|
| Color alpha | 0.30 | 0.12 |
| Blur | 36 | 36 |
| Spread | -18 | -18 |
| Offset | (0, 22) | (0, 22) |

Use for: FABs, sticky action bars, draggable elements.

### Shadow Rules

- All shadows are brightness-aware — dark mode uses higher opacity.
- `strength` parameter scales alpha: use < 1 for subtlety, > 1 for emphasis.
- Light mode clay has a strong white inner highlight (0.68 alpha) — this is the claymorphism "tactile" signal.
- Dark mode inner highlight is subtle (0.05) — refined, not glowing.
- Never add custom shadow colors. Use the recipes.

---

## Elevation System — `CoolElevation`

| Token | Value | Use |
|---|---|---|
| `resting` | 0 | Flat surfaces, inline content |
| `raised` | 8 | Cards, buttons, chips |
| `floating` | 12 | FABs, sticky elements, floating bars |
| `overlay` | 16 | Sheets, modals, critical overlays |

---

## Blur System — `CoolBlur`

| Token | Value | Use |
|---|---|---|
| `subtle` | 12 | Light atmosphere, frosted hints |
| `standard` | 18 | Normal glass surfaces (sheet backgrounds) |
| `overlay` | 22 | Heavy glass (modals, critical overlays) |

### Blur Rules

- Glassmorphism for overlays only. Never on inline cards.
- Keep blur refined and readable. Never frosted to the point of illegibility.
- Pair glass blur with `glassSurface` token at ~82-84% opacity.

---

## Typography

### System Font

**Manrope** is the primary font for all interface text.

### Weight Aliases

The system **maximizes weight** across the board:

| Alias | Weight | Meaning |
|---|---|---|
| `black` | w800 | ExtraBold — used for display |
| `extraBold` | w800 | Same as black — used for headlines |
| `bold` | w700 | Bold — used for titles |
| `semibold` | w700 | Same as bold — used for body emphasis |
| `medium` | w600 | SemiBold — used for labels |
| `regular` | w600 | **Also SemiBold** — even "regular" text is bold |

> **Critical rule:** There is NO w400 (regular) or w300 (light) in the system.
> The minimum weight is w600. This is intentional: maximum authority everywhere.

### Type Scale

| Token | Size | Weight | Letter Spacing | Height | Use |
|---|---|---|---|---|---|
| `displayLarge` | **56** | w800 | -2.0 | 1.1 | Hero headlines, splash |
| `displayMedium` | **48** | w800 | -1.6 | 1.1 | Section heroes |
| `displaySmall` | **40** | w800 | -1.2 | 1.12 | Large feature titles |
| `headlineLarge` | **36** | w800 | -1.0 | 1.15 | Screen titles |
| `headlineMedium` | **30** | w800 | -0.8 | 1.18 | Card titles, sheet headers |
| `headlineSmall` | **26** | w800 | -0.6 | 1.2 | Subsection titles |
| `titleLarge` | **24** | w800 | -0.4 | 1.22 | Row titles, primary labels |
| `titleMedium` | **22** | w700 | -0.3 | 1.24 | Button text, nav labels |
| `titleSmall` | **20** | w700 | -0.2 | 1.25 | Secondary labels |
| `bodyLarge` | **18** | w700 | — | 1.3 | Primary body text |
| `bodyMedium` | **17** | w600 | — | 1.3 | Secondary body text |
| `bodySmall` | **15** | w600 | — | 1.3 | Captions, timestamps |
| `labelLarge` | **16** | w700 | — | — | Chip text, badges |
| `labelMedium` | **15** | w700 | — | — | Button labels |
| `labelSmall` | **14** | w700 | — | — | Overlines, micro labels |

### Typography Rules

- **Maximize size and weight.** Text should feel oversized and commanding.
- **Negative letter spacing** on all headlines — tight tracking = premium signal.
- **Minimum text size is 14dp** (labelSmall). Nothing smaller in the system.
- **Minimum weight is w600.** Even body and caption text feels bold.
- Use `DM Mono` for all financial values, IDs, codes, numeric summaries.
- Headlines: 2–4 words maximum.
- No explanatory paragraph copy when structure can do the work.
- No all-caps labels unless they are status badges or micro-overlines.

### Partner Typography

Rayon Sports routes:
- **Barlow Condensed** for hero and section headlines (w900/w800)
- **Barlow** for body copy and navigation labels
- **DM Mono** only for IDs, counters, seat codes, payment values

Other partners use standard Manrope unless a dedicated brand shell is approved.

---

## Spacing Scale — `CoolSpace`

| Token | Value | Use |
|---|---|---|
| `x1` | 4 | Tight internal padding |
| `x2` | 8 | Compact spacing |
| `x3` | 12 | Standard element gaps |
| `x4` | 16 | Section padding, card internal |
| `x5` | 20 | Comfortable internal padding |
| `x6` | 24 | Page padding, section gaps |
| `x7` | 32 | Major section separation |
| `x8` | 40 | Large section breathing room |
| `x9` | 48 | Screen-level breathing room |
| `x10` | 64 | Hero spacing |

### Pre-defined Padding Constants

```dart
CoolSpace.pagePadding    // horizontal: 24, vertical: 24
CoolSpace.sectionPadding // all: 24
CoolSpace.denseSectionPadding // all: 20
```

### Layout Rules

- **Whitespace is a feature.** Generous spacing improves readability and authority.
- Minimum side padding: 24dp (not 16dp — premium spacing).
- Consistent vertical rhythm using x4–x6 for most gaps.
- Single-column preferred. Grids only for homogeneous small items.
- Safe bottom spacing for shell nav on scrollable screens.

---

## Corner Radius Scale — `CoolRadii`

| Token | Value | Use |
|---|---|---|
| `sm` | **16** | Chips, badges, small controls |
| `md` | **22** | Buttons, inputs, small cards |
| `lg` | **28** | Cards, containers |
| `xl` | **32** | Sheets, modals |
| `xxl` | **36** | Large sheets, hero surfaces |
| `pill` | 999 | Pills, avatars, FABs |

> **Note:** These radii are intentionally large — premium, rounded, soft feel.
> `sm` starts at 16, not 8. This is a deliberate authority choice.

---

## Surface Language

### Primary Surfaces — Refined Claymorphism

```dart
Container(
  decoration: BoxDecoration(
    color: context.coolSemanticColors.cardSurface,
    borderRadius: BorderRadius.circular(CoolRadii.lg),
    border: Border.all(
      color: context.coolSemanticColors.border,
      width: 1,
    ),
    boxShadow: CoolShadows.clay(Theme.of(context).brightness),
  ),
)
```

Rules:
- Cards feel solid, tactile, and institutional — not glossy or playful.
- **Light mode:** strong white inner highlight creates the clay "pillow" feel.
- **Dark mode:** subtle inner highlight keeps refinement without glow.
- One card per section on non-home screens.
- Never stack gradient + heavy shadow + glow on the same element.

### Overlay Surfaces — Restrained Glassmorphism

```dart
ClipRRect(
  borderRadius: BorderRadius.vertical(
    top: Radius.circular(CoolRadii.xl),
  ),
  child: BackdropFilter(
    filter: ImageFilter.blur(
      sigmaX: CoolBlur.standard,
      sigmaY: CoolBlur.standard,
    ),
    child: Container(
      decoration: BoxDecoration(
        color: context.coolSemanticColors.glassSurface,
        border: Border.all(
          color: context.coolSemanticColors.border,
          width: 1,
        ),
        boxShadow: CoolShadows.glass(Theme.of(context).brightness),
      ),
    ),
  ),
)
```

Rules:
- Glassmorphism for overlays only. Never on inline cards.
- Use `CoolBlur.standard` (18) for sheets, `CoolBlur.overlay` (22) for modals.
- Keep blur refined and readable.

### Background

`CoolScreenBackground` is intentionally restrained. The shell gradient
(`shellGradient`) may be used for subtle full-screen atmosphere.

Partner shells (e.g., `RayonShellBackground`) may add subtle branded
atmosphere on entry/discovery surfaces only. Checkout stays quiet.

---

## Responsive System — `CoolResponsive`

| Breakpoint | Padding | Max Content Width |
|---|---|---|
| < 600dp (phone) | 24dp | Full width |
| 600–839dp (small tablet) | 32dp | Full width |
| ≥ 840dp (large tablet) | 40dp | 720dp |

```dart
final padding = CoolResponsive.horizontalPaddingForWidth(
  MediaQuery.sizeOf(context).width,
);
final maxWidth = CoolResponsive.maxContentWidthForWidth(
  MediaQuery.sizeOf(context).width,
);
```

---

## Tap Targets — `CoolTapTargets`

| Token | Value | Use |
|---|---|---|
| `minimum` | 48dp | Absolute minimum for any interactive element |
| `comfortable` | 56dp | Standard buttons, list rows |
| `navigation` | 64dp | Bottom nav, primary CTA areas |

---

## Icon Style

- Prefer outlined/regular weight Material Icons.
- Icon size: 24dp standard, 20dp compact, 28dp emphasis.
- Color: `secondaryText` default, `accent` for active/selected, `primaryText` for emphasis.
- Always pair icons with labels for critical actions.
- Avoid filled icon variants unless indicating active/selected state.

---

## Flutter Implementation

### Token-Driven Architecture

```dart
// Semantic colors (production redesign system)
final sem = context.coolSemanticColors;
sem.cardSurface, sem.primaryText, sem.accent, sem.financialSurface

// Spacing
CoolSpace.x4, CoolSpace.x6, CoolSpace.pagePadding

// Radius
CoolRadii.sm, CoolRadii.lg, CoolRadii.pill

// Shadows
CoolShadows.clay(brightness), CoolShadows.glass(brightness)

// Elevation
CoolElevation.raised, CoolElevation.overlay

// Blur
CoolBlur.standard, CoolBlur.overlay

// Motion
CoolMotion.standard, CoolMotion.enterCurve

// Tap targets
CoolTapTargets.comfortable, CoolTapTargets.navigation

// Responsive
CoolResponsive.horizontalPaddingForWidth(width)

// Typography (via TextTheme)
Theme.of(context).textTheme.headlineLarge
Theme.of(context).textTheme.bodyMedium
```

### Key Files

| File | Purpose |
|---|---|
| `cool_foundations.dart` | `CoolSemanticColors`, `CoolSpace`, `CoolRadii`, `CoolBlur`, `CoolElevation`, `CoolTapTargets`, `CoolMotion`, `CoolResponsive`, `CoolShadows` |
| `app_theme_text.dart` | Typography scale, weight aliases, `TextTheme` builder |
| `cool_palette.dart` | Legacy `CoolPalette` (migration source, do not extend) |
| `app_theme_components.dart` | Component-level theme overrides |
| `app_theme.dart` | Theme assembly (`ThemeData` + extensions) |
| `app_colors.dart` | Legacy static colors (do not extend — migrate away) |
| `cool_layout.dart` | Layout helper constants |
| `rs_colors.dart` | Rayon Sports brand palette |
| `rs_text_styles.dart` | Rayon Sports typography override |

### Audit Commands

```sh
# Find hardcoded colors bypassing tokens
rg "Color(0x" lib/ --count
rg "Colors\." lib/ --count

# Find legacy AppColors usage (should migrate to CoolSemanticColors)
rg "AppColors\." lib/ --count

# Find legacy CoolPalette usage (should migrate to CoolSemanticColors)
rg "coolPalette\|CoolPalette" lib/ --count

# Find non-token font sizes
rg "fontSize:" lib/ | grep -v "Foundations\|theme\|rs_text"

# Find non-token radii
rg "BorderRadius\." lib/ | grep -v "CoolRadii\|Radii\.\|\.circular(Cool"

# Find non-token spacing
rg "EdgeInsets\." lib/ | grep -v "CoolSpace\|Space\.\|pagePadding\|sectionPadding"

# Find non-recipe shadows
rg "BoxShadow\(" lib/ | grep -v "CoolShadows\|Shadows\.\|cool_foundations"
```

---

## Cross-References

- Screen composition and layout hierarchy → `screen-composition` skill
- Component catalog and routing → `component-navigation` skill
- Module-specific visual rules → `module-partner-ux` skill
- Trust design and accessibility → `trust-accessibility` skill
- Full human-readable reference → `DESIGN_SYSTEM.md`
