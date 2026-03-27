---
name: Design Foundations
description: >
  Visual design tokens, theme architecture, color system, typography scale,
  spacing, surface language, and atmospheric effects for the COOL Flutter
  super-app. Mobi × Rayon design system — dark-only, high-contrast fintech
  aesthetic. Use when working on colors, fonts, spacing, radius, shadows,
  surfaces, or theme configuration.
---

# Design Foundations

Use this skill when the task involves:

- Creating, modifying, or auditing color tokens
- Changing typography (font, scale, weight)
- Adjusting spacing or radius values
- Working on surface/card/sheet styling
- Shadow recipes or blur values
- Theme configuration (dark-only)
- Partner-specific visual overrides (Rayon typography, brand palette)
- Atmospheric backgrounds, mobi-grid, gradients

This skill is NOT for:

- Screen layout or information hierarchy → use `screen-composition`
- Shared widgets or routing → use `component-navigation`
- Module-specific UX decisions → use `module-partner-ux`

## Design Philosophy

COOL targets a **high-contrast fintech-sports hybrid** — closer to a premium
fintech terminal crossed with a sports club membership. Dark-only, precise,
data-dense.

Core principles:

1. **Precision** — tight radii, clean borders, grid-aligned elements.
2. **High contrast** — true black backgrounds, pure white text, vibrant accents.
3. **Data-first** — monospace for values, uppercase micro-labels, clear hierarchy.
4. **Sporty energy** — condensed uppercase headlines, gold accents, neon status colors.
5. **Dark authority** — single dark theme, no light mode, surfaces layered with subtle borders.

## Product Truths

Non-negotiable constraints the visual system must accommodate:

- Flutter mobile, Android-first, dark-only, EN/FR.
- Portrait-only by product decision.
- Single theme: dark. No light mode.
- Pending, draft, posted, blocked, offline, disabled states shown honestly.
- Widgets render. Providers coordinate state. Repositories own Supabase access.

---

## Color System — `CoolColors`

The production system uses the Mobi × Rayon palette. All screens must use
these semantic tokens.

### Core Palette

| Token | Value | Role |
|---|---|---|
| `surface` | `#050505` | App background (true black) |
| `surfaceAlt` | `#111111` | Elevated surfaces, cards |
| `ink` | `#0A0A0A` | Deep black for specific surfaces |
| `paper` | `#F5F5F5` | Light contrast (rare, data overlays) |
| `line` | `rgba(255, 255, 255, 0.08)` | Grid lines, subtle borders |

### Brand Colors

| Token | Value | Role |
|---|---|---|
| `primary` | `#0047AB` | Deep royal blue — primary CTA, active states |
| `accentGold` | `#FFD700` | Gold accent — highlights, active indicators, premium |

### Text Colors

| Token | Value | Role |
|---|---|---|
| `textPrimary` | `#FFFFFF` | Primary text (pure white) |
| `textSecondary` | `#888888` | Secondary text (muted gray) |

### State Colors

| Token | Value | Role |
|---|---|---|
| `success` | `#00FF00` | Neon green — positive/complete |
| `warning` | `#FFA500` | Bright orange — attention/caution |
| `danger` | `#FF3B30` | iOS red — error/destructive |

### Border System

| Token | Value | Use |
|---|---|---|
| `borderSubtle` | `rgba(255, 255, 255, 0.05)` | Default card/section borders |
| `borderDefault` | `rgba(255, 255, 255, 0.08)` | Grid lines, standard borders |
| `borderMedium` | `rgba(255, 255, 255, 0.10)` | Interactive element borders |
| `borderStrong` | `rgba(255, 255, 255, 0.20)` | Hover/focus/emphasized borders |

### Color Rules

- Reserve `primary` (blue) for primary CTA, active state, or branding.
- Reserve `accentGold` for premium highlights, nav indicators, emphasis only.
- Never rely on color alone for status — always pair with icon, label, or shape.
- No warm/earthy tones. No greens as primary CTA.
- State colors are vibrant/neon — this is intentional (fintech energy).
- `success` (#00FF00) is bright neon — not muted.

---

## Typography

### Font Stack

| Family | Use | Weight Range |
|---|---|---|
| **Inter** | All body text, UI labels, descriptions | 300–800 |
| **Barlow Condensed** | All headings (h1–h6) | 700–800 |
| **Barlow** | Body copy in branded partner contexts | 400–800 |
| **JetBrains Mono** | Financial values, IDs, labels, badges | 400–700 |

### Heading Convention

ALL headings use **Barlow Condensed**, **uppercase**, **font-weight 800**,
**letter-spacing -0.02em**. No exceptions.

```dart
// Every heading widget
style: TextStyle(
  fontFamily: 'BarlowCondensed',
  fontWeight: FontWeight.w800,
  letterSpacing: -0.02 * fontSize,
  // text is always uppercase via .toUpperCase()
)
```

### Type Scale

| Token | Size | Font | Weight | Style | Use |
|---|---|---|---|---|---|
| `displayLarge` | 48 | Barlow Condensed | w800 | uppercase | Hero headlines |
| `displayMedium` | 40 | Barlow Condensed | w800 | uppercase | Section heroes |
| `displaySmall` | 36 | Barlow Condensed | w800 | uppercase | Feature titles |
| `headlineLarge` | 30 | Barlow Condensed | w800 | uppercase | Screen titles |
| `headlineMedium` | 24 | Barlow Condensed | w800 | uppercase | Card titles |
| `headlineSmall` | 20 | Barlow Condensed | w700 | uppercase | Subsection titles |
| `titleLarge` | 18 | Inter | w600 | normal | Row titles |
| `titleMedium` | 16 | Inter | w600 | normal | Button text |
| `titleSmall` | 14 | Inter | w500 | normal | Secondary labels |
| `bodyLarge` | 16 | Inter | w400 | normal | Primary body text |
| `bodyMedium` | 14 | Inter | w500 | normal | Secondary body text |
| `bodySmall` | 12 | Inter | w400 | normal | Captions, timestamps |
| `labelLarge` | 14 | Inter | w600 | normal | Chip text |
| `labelMedium` | 12 | JetBrains Mono | w600 | uppercase, tracking +0.1em | Button labels |
| `labelSmall` | 10 | JetBrains Mono | w600 | uppercase, tracking +0.1em | Micro labels, mobi-label |

### Mobi Micro-Typography

Two signature micro-typography patterns used everywhere:

**mobi-label:**
```dart
TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 10,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.1 * 10, // 1.0
  color: CoolColors.textSecondary,
  // text is always uppercase
)
```

**mobi-value:**
```dart
TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 14,
  fontWeight: FontWeight.w500,
  letterSpacing: -0.02 * 14,
  color: CoolColors.textPrimary,
)
```

### Typography Rules

- **All headings are uppercase.** No mixed-case headings.
- Body text uses Inter at conventional weights (w400–w600).
- All financial values, IDs, codes, counters use JetBrains Mono.
- Labels at 10px are allowed (mobi-label pattern).
- Badge text as small as 9px is allowed.
- Negative letter spacing on headlines, positive letter spacing on labels.

### Partner Typography (Rayon Sports)

Rayon routes use the same system — Barlow Condensed is already the headline font.
No separate partner typography override needed.

---

## Spacing Scale — `CoolSpace`

| Token | Value | Use |
|---|---|---|
| `m1` | 4 | Tight internal padding |
| `m2` | 8 | Compact spacing |
| `m3` | 12 | Standard element gaps |
| `m4` | 16 | Section padding, card internal |
| `m5` | 24 | Page padding, section gaps |
| `m6` | 32 | Major section separation |
| `m7` | 48 | Screen-level breathing room |

### Pre-defined Constants

```dart
CoolSpace.pagePadding    // horizontal: 16–24
CoolSpace.sectionGap     // 24
CoolSpace.cardPadding    // 16
```

### Layout Rules

- Page padding: 16–24dp (high-density, not premium-generous).
- Consistent vertical rhythm using m3–m5 for most gaps.
- Single-column preferred. Grids for homogeneous small items (5-col quick actions).
- Safe bottom spacing for floating pill nav on scrollable screens.

---

## Corner Radius Scale — `CoolRadii`

| Token | Value | Use |
|---|---|---|
| `sm` | **4** | Small badges, micro elements |
| `md` | **8** | Buttons, inputs, toasts |
| `lg` | **12** | Standard cards, containers |
| `xl` | **16** | Large cards, sheets |
| `xxl` | **24** | Hero surfaces, modals |
| `pill` | 999 | Pills, avatars, nav bar, badges |

> **Critical:** These radii are tight and precise — fintech, not playful.
> `sm` starts at 4, not 16. Buttons are `rounded-xl` (12px), not `rounded-3xl`.

---

## Surface Language

### Primary Card — Flat with Subtle Border

```dart
Container(
  decoration: BoxDecoration(
    color: CoolColors.surfaceAlt,          // #111111
    borderRadius: BorderRadius.circular(CoolRadii.xl),  // 16
    border: Border.all(
      color: CoolColors.borderSubtle,      // white/5
      width: 1,
    ),
  ),
)
```

Rules:
- Cards are **flat** — no claymorphism, no clay shadows, no inner highlights.
- Hover/press: border brightens to `white/20`, bg lightens to `#161616`.
- Transition: 200ms `cubic-bezier(0.4, 0, 0.2, 1)`.
- No domain-specific tinted surfaces. Only `surface` and `surfaceAlt`.

### Glass Surface — For Navigation & Overlays

```dart
ClipRRect(
  borderRadius: BorderRadius.circular(CoolRadii.pill),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
          color: CoolColors.borderMedium,  // white/10
          width: 1,
        ),
      ),
    ),
  ),
)
```

Use for: floating nav bar, overlays, sticky headers.

### Mobi Grid Background

Subtle 24px grid overlay for screen backgrounds:

```dart
Container(
  decoration: BoxDecoration(
    image: DecorationImage(
      image: // 24px grid pattern at white/8 opacity
      repeat: ImageRepeat.repeat,
    ),
  ),
)
```

### Atmospheric Background

Blurred radial blobs for visual atmosphere:

```dart
// Blue blob (top-left)
Container(
  width: screenWidth * 0.4,
  height: screenWidth * 0.4,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: CoolColors.primary.withOpacity(0.10),
  ),
  // blur: 120
)

// Gold blob (top-right, delayed pulse)
Container(
  width: screenWidth * 0.3,
  height: screenWidth * 0.3,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: CoolColors.accentGold.withOpacity(0.05),
  ),
  // blur: 100, animateOpacity pulse
)
```

---

## Shadow System

Simplified. No claymorphism.

| Recipe | Use | Values |
|---|---|---|
| `standard` | Cards, buttons | black/50, blur 25, offset (0, 10) |
| `floating` | FABs, floating nav | `shadow-2xl` equivalent + `shadow-black/50` |
| `primary` | Primary CTA buttons | `primary/20`, blur 20, offset (0, 8) |
| `gold` | Accent/gold elements | `accentGold/20`, blur 20, offset (0, 8) |

### Shadow Rules

- Dark-only: shadows must be visible against `#050505` background.
- Use colored shadows for primary/accent buttons (subtle brand glow).
- Never stack multiple shadow recipes on one element.

---

## Blur System

| Token | Value | Use |
|---|---|---|
| `standard` | 24 | Glass nav bar, sticky headers |
| `overlay` | 32 | Modals, full-screen overlays |
| `atmospheric` | 100–150 | Background radial blobs |

---

## Tap Targets — `CoolTapTargets`

| Token | Value | Use |
|---|---|---|
| `minimum` | 48dp | Absolute minimum for any interactive element |
| `comfortable` | 56dp | Standard buttons, list rows |
| `navigation` | 64dp | Bottom nav, primary CTA areas |

---

## Icon Style

- Use **Lucide** icon set (line icons, consistent stroke weight).
- Icon size: 18dp compact, 20dp standard, 24dp emphasis.
- Color: `textSecondary` default, `primary` for active, `textPrimary` for emphasis.
- Stroke width: 2 default, 2.5 for active state.

---

## Motion System

### Duration Scale

| Token | Duration | Use |
|---|---|---|
| `press` | 100ms | Micro-feedback (tap, scale 0.98) |
| `quick` | 200ms | State changes, reveals |
| `standard` | 300ms | Page transitions, expansions |
| `emphasized` | 500ms | Spring animations (nav bar entry) |

### Curves

| Token | Value | Use |
|---|---|---|
| `standard` | `cubic-bezier(0.4, 0, 0.2, 1)` | All standard transitions |
| `spring` | `damping: 20, stiffness: 100` | Nav bar, dramatic entries |

### Animation Patterns

```dart
// Card/button press feedback
active:scale-[0.98]  →  Transform.scale(scale: 0.98)

// Staggered list entry
initial: { opacity: 0, y: 20 }
animate: { opacity: 1, y: 0 }

// Nav bar slide up
initial: { y: 100, opacity: 0 }
animate: { y: 0, opacity: 1 }
transition: spring(damping: 20, stiffness: 100)
```

---

## Flutter Implementation

### Token Access Pattern

```dart
// Colors
CoolColors.surface, CoolColors.surfaceAlt, CoolColors.primary
CoolColors.accentGold, CoolColors.textPrimary, CoolColors.textSecondary
CoolColors.success, CoolColors.warning, CoolColors.danger

// Spacing
CoolSpace.m1, CoolSpace.m4, CoolSpace.pagePadding

// Radius
CoolRadii.sm, CoolRadii.lg, CoolRadii.pill

// Typography (via TextTheme)
Theme.of(context).textTheme.headlineLarge  // Barlow Condensed, uppercase
Theme.of(context).textTheme.bodyMedium     // Inter

// Shadows
CoolShadows.standard, CoolShadows.floating, CoolShadows.primary(color)

// Tap targets
CoolTapTargets.comfortable, CoolTapTargets.navigation
```

### Key Files

| File | Purpose |
|---|---|
| `cool_foundations.dart` | `CoolColors`, `CoolSpace`, `CoolRadii`, `CoolTapTargets`, `CoolShadows`, `CoolBlur` |
| `app_theme_text.dart` | Typography scale: Inter, Barlow Condensed, JetBrains Mono |
| `app_theme.dart` | Theme assembly (`ThemeData` + dark-only) |
| `app_theme_components.dart` | Component-level theme overrides |

### Audit Commands

```sh
# Find hardcoded colors bypassing tokens
rg "Color(0x" lib/ --count
rg "Colors\." lib/ --count

# Find legacy warm palette usage (must be zero)
rg "AppColors\." lib/ --count
rg "coolPalette\|CoolPalette" lib/ --count
rg "CoolSemanticColors" lib/ --count

# Find non-token font families
rg "Manrope\|DM Mono\|fontFamily:" lib/ | grep -v "Inter\|Barlow\|JetBrains\|theme"

# Find oversized radii (old system used 16-36)
rg "circular(1[6-9]\|circular(2[0-9]\|circular(3[0-6]" lib/ --count

# Find claymorphism remnants
rg "CoolShadows.clay\|CoolShadows.glass" lib/ --count
```

---

## Cross-References

- Screen composition and layout hierarchy → `screen-composition` skill
- Component catalog and routing → `component-navigation` skill
- Module-specific visual rules → `module-partner-ux` skill
- Trust design and accessibility → `trust-accessibility` skill
