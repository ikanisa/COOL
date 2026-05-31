---
name: Collect
colors:
  surface: '#fcf9f8'
  surface-dim: '#dcd9d9'
  surface-bright: '#fcf9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f2'
  surface-container: '#f0edec'
  surface-container-high: '#ebe7e7'
  surface-container-highest: '#e5e2e1'
  on-surface: '#1c1b1b'
  on-surface-variant: '#5d3e42'
  inverse-surface: '#313030'
  inverse-on-surface: '#f3f0ef'
  outline: '#926e71'
  outline-variant: '#e7bcc0'
  surface-tint: '#bd0044'
  primary: '#b90042'
  on-primary: '#ffffff'
  primary-container: '#e70054'
  on-primary-container: '#fffbff'
  inverse-primary: '#ffb2bb'
  secondary: '#b22548'
  on-secondary: '#ffffff'
  secondary-container: '#fd5f7d'
  on-secondary-container: '#63001f'
  tertiary: '#006a3c'
  on-tertiary: '#ffffff'
  tertiary-container: '#00864e'
  on-tertiary-container: '#f6fff5'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffd9dc'
  primary-fixed-dim: '#ffb2bb'
  on-primary-fixed: '#400011'
  on-primary-fixed-variant: '#910032'
  secondary-fixed: '#ffd9dc'
  secondary-fixed-dim: '#ffb2bb'
  on-secondary-fixed: '#400011'
  on-secondary-fixed-variant: '#900332'
  tertiary-fixed: '#84fab1'
  tertiary-fixed-dim: '#67dd97'
  on-tertiary-fixed: '#00210f'
  on-tertiary-fixed-variant: '#00522d'
  background: '#fcf9f8'
  on-background: '#1c1b1b'
  surface-variant: '#e5e2e1'
typography:
  display:
    fontFamily: Hanken Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Hanken Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Hanken Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-md:
    fontFamily: Hanken Grotesk
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Hanken Grotesk
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  unit: 8px
  container-max: 1120px
  gutter: 32px
  margin-mobile: 20px
  margin-desktop: 64px
  section-gap: 128px
---

## Brand & Style

The design system is rooted in **Extreme Minimalism**. It is designed for a highly focused user base that values clarity over decoration. The aesthetic is "Quiet, Precise, and Premium," prioritizing content and utility through surgical precision in layout and typography.

Visual noise is eliminated by removing extraneous borders, backgrounds, and icons. Instead, the design system utilizes intentional whitespace as a primary structural element to guide the eye and define relationships between information. The emotional response is one of calm, intellectual control, and effortless efficiency.

## Colors

The palette is strictly monochromatic with a single high-intent accent.

- **Primary (#FF005E):** Reserved exclusively for critical actions, active states, and focus indicators. Its scarcity ensures high impact.
- **Neutral (#121212):** Used for primary text and structural lines to maintain high contrast.
- **Background (#FFFFFF):** The vast majority of the UI surface. Whitespace is not "empty"—it is a functional component.
- **Subtle Surface (#F5F5F5):** Used sparingly for secondary containers or hover states where a flat panel distinction is required.

## Typography

This design system uses a high-contrast typographic scale to create hierarchy without the need for visual dividers.

**Hanken Grotesk** provides a sharp, contemporary feel for both headlines and body copy, ensuring legibility at all weights. **JetBrains Mono** is introduced for labels and metadata to inject a "precise" and "technical" character to secondary information. All caps and increased letter spacing are used for labels to differentiate them from body content without increasing font size.

## Layout & Spacing

The layout follows a **Fixed Grid** philosophy on desktop to ensure content remains centered and readable, transitioning to a fluid model on mobile.

Spacing is generous. We use a base-8 unit system, but emphasize "macro-spacing" (64px+) to separate distinct thoughts or sections.
- **Mobile:** 4-column grid with 20px margins.
- **Tablet:** 8-column grid with 32px margins.
- **Desktop:** 12-column grid within a 1120px max-width container to prevent line lengths from becoming excessive.

Elements should be aligned to a strict vertical rhythm. Use negative space to indicate grouping rather than boxes or lines whenever possible.

## Elevation & Depth

To maintain the minimalist aesthetic, depth is achieved through **Tonal Layers** and **Low-Contrast Outlines**.

- **Level 0 (Base):** White background.
- **Level 1 (Subtle Focus):** Instead of a shadow, use a 1px solid border in `#F5F5F5` or a very soft `#000000 / 0.04` shadow with a 20px blur and 0 offset.
- **Overlays:** Use a subtle backdrop blur (10px) with a semi-transparent white fill to maintain context of the layer below without adding visual weight.

Avoid heavy drop shadows or glows. The interface should feel flat, like a physical piece of paper or a precision-machined surface.

## Shapes

The shape language is "Soft but Disciplined."

Standard elements like buttons and input fields use a `0.25rem` (4px) radius. This provides a hint of approachability while maintaining the overall architectural and "precise" feel. Large cards or containers, when used, may scale up to `0.5rem` (8px). Circles are used exclusively for user avatars or icon backgrounds to provide a sharp contrast to the rectangular grid.

## Components

- **Buttons:** Primary buttons are solid `#121212` with white text. The singular accent color `#FF005E` is used only for the most critical CTA on a page. Secondary buttons are outlined with 1px `#EEEEEE`.
- **Input Fields:** Minimalist design—bottom border only (1px `#121212`) that thickens to 2px on focus. No background fill unless in a "disabled" state.
- **Lists:** No dividers. Use 24px of vertical padding between list items to create separation. Use the primary accent color only for active list selections.
- **Chips:** Text-only with a subtle grey underline or a `#F5F5F5` background. No borders.
- **Checkboxes/Radios:** Small, precise 16px squares/circles. When checked, they fill with `#FF005E` to provide an unmistakable state change.
- **Cards:** No borders or shadows. Cards are defined by a light grey `#F5F5F5` background and generous internal padding (32px+).
