# Design System Strategy: The Tactile Monolith

## 1. Overview & Creative North Star

This design system is built upon the concept of **"The Tactile Monolith."** It is a visual language that balances the immovable authority of massive, condensed typography with the ethereal, soft-touch physics of claymorphism and glassmorphism.

We are moving away from the "standard SaaS template" look. To achieve this, you must embrace intentional asymmetry and dramatic scale shifts. The goal is to make the interface feel like a physical object carved from violet light and frosted glass. We break the grid through overlapping elements—letting large headlines bleed behind glass containers or allowing buttons to float with deep, ambient shadows. This is not just a UI; it is an editorial experience that commands attention while remaining soft to the touch.

## 2. Colors

Our palette is rooted in a nocturnal, authoritative foundation. The depth is created through atmospheric layers rather than flat shapes.

*   **Primary Authority:** We use `primary` (#c4c0ff) and `primary_container` (#8781ff) to draw the eye. These are not just colors; they are light sources.
*   **The Deep Base:** The `surface_container_lowest` (#0d0a27) acts as our infinite void. All other surfaces must feel like they are floating above this base.
*   **The "No-Line" Rule:** Under no circumstances are you to use 1px solid borders to section off content. Boundaries must be defined solely by shifting between surface tokens (e.g., placing a `surface_container_high` card against a `surface` background).
*   **Surface Hierarchy & Nesting:** Treat the UI as a physical stack.
    *   **Layer 0:** `surface_dim` (The base).
    *   **Layer 1:** `surface_container_low` (Large structural sections).
    *   **Layer 2:** `surface_container_highest` (Interactive cards/elements).
*   **The "Glass & Gradient" Rule:** Floating elements (modals, navigation bars) should utilize glassmorphism. Use `surface_bright` at 60% opacity with a `backdrop-blur` of 20px–40px. Use a subtle gradient from `primary` to `primary_container` at a 135-degree angle for hero CTAs to give them a "glowing" soul.

### Implementation Token Map

| Strategy Name | Token | Dark Hex |
| --- | --- | --- |
| surface_container_lowest (void) | `appBackground` | `#0D0A27` |
| surface_dim (base) | `elevatedBackground` | `#110E2D` |
| surface_container_low (Layer 1) | `cardSurface` | `#1A1640` |
| surface_container_highest (Layer 2) | `cardSurfaceStrong` | `#252054` |
| surface_bright @ 60% (glass) | `glassSurface` | `#2A2555 @ 60%` |
| primary (light source) | `accentStrong` | `#C4C0FF` |
| primary_container (CTA) | `accent` | `#8781FF` |
| electric violet (gradient depth) | `accentDeep` | `#6C63FF` |
| No-Line divider | `divider` | `transparent` |
| No-Line border | `border` | `transparent` |
| Ghost border (15%) | `borderStrong` | `#8781FF @ 15%` |
| Void shadow base | `shadowColor` | `#0D0A27` |

## 3. Typography

The typography is our primary tool for "Maximum Authority." We pair the brutalist weight of Space Grotesk with the technical clarity of Manrope and Inter.

### 3.1 Typography Constraints (Hard Rules)

| Constraint | Value | Rationale |
| --- | --- | --- |
| **Maximum font weight** | `w700` (Bold) | w700 provides full authority with optimal stroke clarity on mobile OLED screens. **No w800 or w900 anywhere in UI code.** |
| **Minimum font size** | `14px` | Accessibility and legibility floor for mobile-first PWA. **No text below 14px anywhere in UI code.** |

### 3.2 Optimised 3-Tier Weight Scale

The system uses exactly 3 weights with a 300-unit spread for maximum visual hierarchy contrast:

| Tier | Weight | Alias | Usage |
| --- | --- | --- | --- |
| **Hero** | `w700` (Bold) | `black`, `extraBold`, `bold` | Display titles, CTAs, hero amounts, key actions |
| **Emphasis** | `w600` (SemiBold) | `semibold` | Section headings, card titles, action labels |
| **Body** | `w400` (Regular) | `regular` | Labels, metadata, descriptions, utility text |

*Exceptions:* PDF export code (using `pw.FontWeight`) and emoji-only text spans are exempt from these constraints.

*   **Display & Headline (Space Grotesk):** These must be used at "maximum impact." Do not be afraid of `display-lg` (3.5rem). Use tight letter-spacing (-0.04em) and w700 Bold to create a "condensed monolith" effect. Headlines should feel like they are "stamped" into the clay surfaces.
*   **Title & Body (Manrope):** This provides the premium, editorial feel. Manrope's geometric nature complements the rounded corners of our UI.
*   **Label (Inter):** Used for micro-copy and functional data. It provides a "utility" contrast to the expressive headlines.
*   **Hierarchy Note:** Use extreme contrast in size. If a headline is `display-lg`, the subtext should be `body-md`. Avoid "middle-ground" font sizes that dilute the authority of the layout.

### Implementation Font Map

| Role | Font | Access |
| --- | --- | --- |
| Display / Headline | Space Grotesk w600–w700 | `context.coolText.headline(...)` |
| Title / Body | Manrope w400–w600 | `context.coolText.display(...)` |
| Label / Utility | Inter w400–w600 | Theme default |
| Numeric / Mono | DM Mono w600–w700 | `context.coolText.mono(...)` |

## 4. Elevation & Depth

In this system, depth is not an effect—it is the architecture.

*   **The Layering Principle:** Depth is achieved by "stacking" the surface-container tiers. Place a `surface_container_lowest` card on a `surface_container_low` section to create a "sunken" clay effect.
*   **Claymorphism (Soft 3D):** To achieve the "soft tactile" look, use two inner shadows on cards: one light (top-left) to simulate a highlight and one dark (bottom-right) to simulate depth. Use `xl` (3rem) or `lg` (2rem) corner rounding to reinforce the organic, molded feel.
*   **Ambient Shadows:** For floating elements, use extra-diffused shadows.
    *   *Shadow Token:* `box-shadow: 0 20px 80px -10px rgba(13, 10, 39, 0.4);`
    *   Shadows should never be black; they should be a darker, desaturated version of the background color.
*   **The "Ghost Border" Fallback:** If accessibility requires a container definition, use `outline_variant` at 15% opacity. Never use 100% opaque borders.
*   **Glassmorphism:** Use `surface_variant` with 40% opacity and a heavy blur for secondary floating panels. This allows the deep violet backgrounds to "bleed" through, softening the interface.

### Implementation Radius & Shadow Map

| Token | Value | Use |
| --- | --- | --- |
| `CoolRadii.xs` | 16px | Small chips |
| `CoolRadii.sm` | 20px | Buttons, inputs |
| `CoolRadii.md` | 24px | Icon containers |
| `CoolRadii.lg` | 32px | Operation cards |
| `CoolRadii.xl` | 48px | Hero cards, main cards (molded clay) |
| `CoolRadii.pill` | 999px | Nav pills, action pills |
| `CoolBlur.glass` | 40px | Floating glass surfaces |
| `CoolShadows.claymorphicCard()` | — | Tactile hero cards with glow |
| `CoolShadows.ambientFloat()` | — | Ultra-diffused float for glass |

## 5. Components

### Buttons
*   **Primary:** High-gloss clay effect. Background: `primary_container`. Rounded: `full`. Large horizontal padding (2.5rem).
*   **Secondary:** Glassmorphic. Background: `surface_bright` (20% opacity) with backdrop blur. Text color: `on_surface`.
*   **Tertiary:** No container. Text color: `primary`. Use `label-md` for a technical, high-end feel.

### Cards
*   Forbid the use of divider lines. Separate content using `surface_container` shifts or vertical whitespace from the Spacing Scale (32px+).
*   Corner Radius: Always `xl` (3rem) for main cards to maintain the "molded" aesthetic.

### Input Fields
*   **State:** "Sunken" into the surface.
*   **Style:** Use `surface_container_lowest` with a subtle inner shadow. When active, use an `electric violet` (#6C63FF) "Ghost Border" at 40% opacity.

### Chips
*   Pill-shaped (`full` rounding). Use `secondary_container` for the background. They should look like small, smooth pebbles.

### Additional Signature Component: The "Glass Header"
*   A fixed top navigation using `surface` color at 50% opacity, a 40px backdrop blur, and a `Ghost Border` on the bottom edge only. It should feel like a pane of frosted violet glass sliding over the content.

## 6. Do's and Don'ts

### Do:
*   **DO** use whitespace aggressively. High-end design needs room to breathe.
*   **DO** overlap elements. Let a massive `display-lg` headline sit partially behind a glassmorphic card.
*   **DO** use `surface_container_highest` for "Hover" states to create a physical "lift" feeling.

### Don't:
*   **DON'T** use 1px solid borders. Ever.
*   **DON'T** use flat, opaque backgrounds without depth layering.
*   **DON'T** use small, timid typography. The hierarchy must be dramatic.
*   **DON'T** use `FontWeight.w800` or `FontWeight.w900`. Maximum allowed weight is `w700` (Bold).
*   **DON'T** use font sizes below `14px`. Every text element must be ≥ 14px for mobile legibility.
*   **DON'T** use black shadows. Use the void color (#0D0A27).
*   **DON'T** create parallel palette classes. Use `context.coolSemanticColors` only.
*   **DON'T** reference old design system names (ROUGEBLACK, Mobi × Partner).

---

## Appendix: Code Reference

All tokens are accessed via:

```dart
final colors = context.coolSemanticColors;
final text = context.coolText;
```

Source files:

```
lib/core/theme/
├── cool_foundations.dart          ← barrel export (import this)
├── cool_semantic_colors.dart      ← THE palette
├── cool_spacing.dart              ← CoolRadii, CoolSpace
├── cool_motion_and_effects.dart   ← CoolShadows, CoolBlur, CoolMotion
├── cool_text_styles.dart          ← typography helpers
├── app_theme_text.dart            ← TextTheme builder
└── app_theme_components.dart      ← M3 component overrides
```

Deleted legacy references (do not re-introduce):
- `HomeVisualPalette` — deleted
- `CoolPalette` — deprecated, do not use
- `AppColors` — deprecated, do not use
- `ROUGEBLACK` naming — replaced
- `Mobi × Partner` naming — replaced
