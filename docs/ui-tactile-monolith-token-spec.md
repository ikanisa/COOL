# Tactile Monolith — Canonical Token Spec

Date: 2026-04-10

This is the **single source of truth** for all visual tokens used across Flutter and PWA surfaces.
Both platforms must resolve to identical token values.

---

## Color Roles

| Role | Flutter Token | CSS Custom Property | Dark Value |
|------|--------------|-------------------|------------|
| Void / Layer 0 | `appBackground` | `--app-background` | `#0D0A27` |
| Base / surface_dim | `elevatedBackground` | `--elevated-background` | `#110E2D` |
| Layer 1 / structural | `cardSurface` | `--card-surface` | `#1A1640` |
| Layer 2 / interactive | `cardSurfaceStrong` | `--card-surface-strong` | `#252054` |
| Glass surface (60%) | `glassSurface` | `--overlay-surface` @ 78% | `#2A2555 @ 60%` |
| Primary (light source) | `accentStrong` | `--accent-strong` | `#C4C0FF` |
| Primary container (CTA) | `accent` | `--accent` | `#8781FF` |
| Electric violet | `accentDeep` | `--accent-deep` | `#6C63FF` |
| Primary text | `primaryText` | `--primary-text` | `#F7F9FC` |
| Secondary text | `secondaryText` | `--secondary-text` | `#B3AFCC` |
| Tertiary text | `tertiaryText` | `--tertiary-text` | `#8B8A9E` |
| No-Line divider | `divider` | `--divider` | `transparent` |
| No-Line border | `border` | `--border` | `rgba(135,129,255,0.08)` |
| Ghost border (15%) | `borderStrong` | `--border-strong` | `rgba(135,129,255,0.18)` |
| Shadow base (never black) | `shadowColor` | `--shadow` | `#0D0A27` |

## Typography Roles

| Role | Font Family | Weight Range | Flutter Access | PWA |
|------|------------|-------------|---------------|-----|
| Display / Headline | Space Grotesk | w800–w900 | `GoogleFonts.spaceGroteskTextTheme()` | `font-family: "Space Grotesk"` |
| Title / Body | Manrope | w500–w800 | `GoogleFonts.manropeTextTheme()` | `font-family: "Manrope"` |
| Label / Utility | Inter | w500–w700 | `GoogleFonts.interTextTheme()` | `font-family: "Inter"` |
| Mono / IDs / Values | DM Mono | w500–w800 | `AppThemeText.monoFontFamily` | `font-family: "DM Mono"` |

## Radii

| Token | Value | Use Case |
|-------|-------|----------|
| `CoolRadii.xs` / `--radius-sm` | 16px | Small chips, inline notices |
| `CoolRadii.sm` | 20px | Buttons (legacy), badges |
| `CoolRadii.md` / `--radius-md` | 24px | Icon containers, search fields |
| `CoolRadii.lg` / `--radius-lg` | 32px | Inner containers, nested elements |
| `CoolRadii.xl` / `--radius-xl` | **48px** | **THE molded card radius** — all main cards |
| `CoolRadii.pill` | 999px | Navigation pills, action buttons, CTAs |

## Shadow Recipes

| Recipe | Use | Flutter | CSS Equivalent |
|--------|-----|---------|---------------|
| Ambient Float | Glass nav, floating elements | `CoolShadows.ambientFloat()` | `0 20px 80px -10px var(--shadow)` |
| Claymorphic Card | Hero/premium cards with glow | `CoolShadows.claymorphicCard()` | specular + depth + glow bloom |
| Clay Button | Primary/accent CTAs | `CoolShadows.clay()` | void depth + specular + accent bloom |
| Glass | Bottom sheets, overlays | `CoolShadows.glass()` | specular + 40px void shadow |
| Primary Button | Standard primary CTA | `CoolShadows.primary()` | accent glow at 25% + specular |

## Blur Values

| Token | Value | Use |
|-------|-------|-----|
| `CoolBlur.subtle` | 12px | Cards, lightweight glass |
| `CoolBlur.standard` | 24px | Secondary buttons, mid-glass |
| `CoolBlur.overlay` / `heavy` | 32px | Headers, bottom sheets |
| `CoolBlur.glass` | **40px** | Full glassmorphism surfaces |
| `CoolBlur.atmospheric` | 120px | Background atmosphere effects |

## Ghost Border Rules

- **Default**: `BorderSide.none` / `border: none`
- **Ghost (when accessibility requires container definition)**: Use `borderStrong` at **15% opacity** max
- **NEVER**: 100% opaque borders, 1px solid lines as separators
- Content separation is achieved via **surface hierarchy** (Layer 0 → 1 → 2) and **spacing**

## Component State Rules

### Cards
- Default: solid `cardSurface`, no border, `CoolRadii.xl` (48px)
- Glass: `BackdropFilter` blur + `glassSurface`, ghost border at 15%
- Outline: transparent background, `borderStrong` border (exception only)

### Buttons
- Primary: gradient (`accentStrong` → `accent`), pill shape, clay shadow
- Secondary: glass tonal, pill shape, ghost border at 8%
- Ghost: transparent, no border, text only
- Font: **Inter** (label family), w800, letter-spacing 1.2

### Inputs
- Background: `inputSurface` (sunken into void)
- Shadow: inner-shadow simulation (dark top + light bottom lip)
- Focus: `accentDeep` ghost border at 40%
- No visible border in resting state

### Bottom Sheets
- Glass surface with heavy blur (32px)
- Ghost border on top edge only at 15%
- Gradient wash from highlight to glow

### App Bar / Glass Header
- `BackdropFilter` with overlay blur (32px)
- Gradient from glass to background
- Ghost edge at bottom: 15% opacity, 0.75px width
