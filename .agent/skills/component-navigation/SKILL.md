---
name: Component & Navigation
description: >
  Shared widget catalog, navigation structure, routing rules, motion system,
  and state matrix for the COOL Flutter super-app. Mobi × Rayon design —
  18 UI primitives, 3-item floating glass pill nav, gold active indicator.
  Use when building or modifying shared widgets, changing routes, adjusting
  bottom nav, implementing animations, or defining screen state coverage.
---

# Component & Navigation

Use this skill when the task involves:

- Creating, modifying, or auditing shared widgets in `lib/shared/widgets/`
- Adding, moving, or removing routes in `app_router.dart`
- Changing the bottom navigation structure
- Implementing animations or transitions
- Defining state coverage for a screen or flow

This skill is NOT for:

- Color tokens or typography → use `design-foundations`
- Screen layout or copy budgets → use `screen-composition`
- Module-specific UX decisions → use `module-partner-ux`

## Navigation

### Bottom Nav — Floating Glass Pill

3-item floating glass pill navigation, centered at screen bottom.

| Position | Label | Route | Icon |
|---|---|---|---|
| 1 | Home | `/home` | Home (Lucide) |
| 2 | BioPay | `/biopay-hub` | Wallet (Lucide) |
| 3 | Profile | `/fan-profile` | User (Lucide) |

**Visual specification:**
- Floating pill: `max-width: 320px`, centered, `rounded-full`
- Surface: glass (`backdrop-blur-xl`, `bg-white/5`)
- Border: `white/10`, 1px
- Shadow: `shadow-2xl shadow-black/50`
- Padding: `px-6 py-2`
- Entry animation: spring from below (`y: 100 → 0`, damping: 20, stiffness: 100)
- Bottom offset: `p-8` from screen edge

**Nav item specification:**
- Icon: 18dp, stroke-width 2 (active: 2.5)
- Label: 8px, JetBrains Mono, uppercase, letter-spacing 0.1em
- Active: white text, `bg-white/10` behind icon, `scale: 1.1`
- Inactive: `textSecondary`, `opacity: 0.4`
- Active indicator: gold dot (1dp radius) below label, with gold glow shadow
- BioPay label: normal case (exception to uppercase rule)

### Navigation Rules

- All non-tab screens are pushed routes with visible back/close affordance.
- No competing navigation models in one viewport.
- Max 1 local navigation model per screen body.
- Tabs only for same-shape content sets.
- Filters go into sheets unless they are the main job of the route.
- Show bottom nav only on main screens: `home`, `rayon-home`, `fan-profile`, `biopay-hub`.

### Route Inventory

The canonical route registry lives in `docs/ROUTE_INVENTORY.md`.
Route additions or major moves must update that file.

## Component Library

All reusable components live under `lib/shared/widgets/`. 18 primitives matching
the React reference UI kit.

### Core Primitives

| Component | Purpose | Variants |
|---|---|---|
| `CoolCard` | Content containers | default, glass, outline, accent |
| `CoolButton` | Primary/secondary actions | primary, secondary, outline, ghost, accent |
| `CoolBadge` | Status/category indicators | primary, secondary, outline, success, warning, danger, accent |
| `CoolInput` | Text input with label/error/icon | standard with icon slot |
| `CoolTypography` | Text with variant presets | h1, h2, h3, h4, p, lead, large, small, muted, label, value |
| `CoolDialog` | Modal overlays | header, content, footer, trigger |
| `CoolTabs` | Tabbed content switching | list + trigger + content |
| `CoolSelect` | Dropdown selector | trigger, content, items, groups |
| `CoolSwitch` | Toggle control | on/off |
| `CoolCheckbox` | Checkbox control | checked/unchecked |
| `CoolAvatar` | User/entity avatar | image + fallback |
| `CoolProgress` | Progress bar | determinate with value |
| `CoolSeparator` | Section divider | horizontal |
| `CoolTooltip` | Hover/long-press info | trigger + content |
| `CoolSkeleton` | Loading placeholder | rectangular pulse |
| `CoolEmptyState` | Empty data state | icon + title + description |
| `CoolLoadingState` | Loading indicator | spinner + message |
| `CoolMobiGrid` | Background grid overlay | 24px grid pattern |

### Card Variants

```dart
// Default card
CoolCard(
  variant: CoolCardVariant.default_,
  padding: CoolCardPadding.md,
  child: content,
)
// Renders: bg #111111, border white/5, rounded-2xl (16px), p-4

// Glass card
CoolCard(variant: CoolCardVariant.glass)
// Renders: bg white/5, backdrop-blur-xl, border white/10

// Outline card
CoolCard(variant: CoolCardVariant.outline)
// Renders: bg transparent, border white/10

// Accent card
CoolCard(variant: CoolCardVariant.accent)
// Renders: bg primary/5, border primary/20
```

Padding: `none` (0), `sm` (12), `md` (16), `lg` (24).

### Button Specification

```dart
CoolButton(
  variant: CoolButtonVariant.primary,
  size: CoolButtonSize.md,
  isLoading: false,
  onPressed: () {},
  child: Text('ACTION'),
)
```

| Variant | Background | Text | Shadow |
|---|---|---|---|
| primary | `#0047AB` | white | `primary/20` glow |
| secondary | `white/10` | white | none |
| outline | transparent | white | none |
| ghost | transparent | `textSecondary` | none |
| accent | `#FFD700` | black | `gold/20` glow |

| Size | Height | Padding | Font Size |
|---|---|---|---|
| sm | 32 | px-12 | 10px |
| md | 44 | px-24 | 12px |
| lg | 56 | px-32 | 14px |
| icon | 40×40 | 0 | — |

Button text: JetBrains Mono, uppercase, `tracking-widest`, `font-semibold`.
Press feedback: `scale(0.98)`.

### Badge Specification

```dart
CoolBadge(
  variant: CoolBadgeVariant.success,
  size: CoolBadgeSize.sm,
  child: Text('VERIFIED'),
)
```

- Shape: `rounded-full` (pill)
- Font: JetBrains Mono, bold, uppercase, `tracking-widest`
- Size sm: `px-2 py-0.5 text-[9px]`
- Size md: `px-3 py-1 text-[10px]`

### Input Specification

```dart
CoolInput(
  label: 'Email Address',
  placeholder: 'alex@rayon.com',
  icon: Icon(LucideIcons.mail),
  error: 'Required',
)
```

- Height: 48dp
- Background: `white/5`
- Border: `white/10`, focus: `primary/50` ring
- Radius: `rounded-xl` (12px)
- Label: mobi-label style (10px, mono, uppercase)
- Error: 10px, bold, danger color, uppercase

### Component Rules

- All components accept `className` / additional styling parameter.
- All interactive components support loading and disabled states.
- All buttons have press scale feedback (`0.98`).
- Loading state: 16dp spinner (border-2, animate-spin).
- Transitions: 200-300ms, `cubic-bezier(0.4, 0, 0.2, 1)`.
- No claymorphism shadows. Flat borders only.

## Motion System

### Duration Scale

| Token | Duration | Use |
|---|---|---|
| `press` | 100ms | Micro-feedback (tap scale) |
| `quick` | 200ms | State changes, reveals, fades |
| `standard` | 300ms | Page transitions, expansions |
| `emphasized` | 500ms | Spring animations, celebrations |

### Curves

| Token | Value | Use |
|---|---|---|
| `standard` | `Cubic(0.4, 0, 0.2, 1)` | All standard transitions |
| `spring` | `SpringDescription(damping: 20, stiffness: 100)` | Nav entry, dramatic reveals |

### Standard Animation Patterns

| Pattern | Initial | Animate | Duration |
|---|---|---|---|
| Fade in | `opacity: 0` | `opacity: 1` | 200ms |
| Slide from bottom | `y: 10, opacity: 0` | `y: 0, opacity: 1` | 200ms |
| Slide from top | `y: -10, opacity: 0` | `y: 0, opacity: 1` | 200ms |
| Zoom in | `scale: 0.95, opacity: 0` | `scale: 1, opacity: 1` | 200ms |
| Card entry | `y: 20, opacity: 0` | `y: 0, opacity: 1` | 300ms |
| Nav bar entry | `y: 100, opacity: 0` | `y: 0, opacity: 1` | spring |
| Press feedback | scale 1.0 | scale 0.98 | 100ms |
| Hover scale | scale 1.0 | scale 1.1 | 300ms |

### Reduced Motion

Always support `MediaQuery.disableAnimations`:
- Skip decorative animations entirely
- Keep functional transitions but reduce to instant
- Never block interaction behind an animation

## State Matrix

Every important screen must define:

| State | Description |
|---|---|
| Resting | Normal loaded state |
| Loading / Skeleton | Data being fetched (use `CoolSkeleton`) |
| Empty | No data (use `CoolEmptyState`) |
| Error | Operation failed (use error state with retry CTA) |
| Offline / Stale | Cached data, explicit staleness indicator |
| Success | Completed, confirmation |

## Audit Commands

```sh
# Count shared widgets
find lib/shared/widgets -type f -name '*.dart' | wc -l

# Route count
rg -o "GoRoute\(" -N lib/core/router/app_router.dart | wc -l

# Widget usage frequency
for w in CoolCard CoolButton CoolBadge CoolInput CoolDialog CoolTabs CoolSkeleton CoolEmptyState; do
  echo "$w: $(rg -o "${w}\(" -N lib | wc -l | tr -d ' ')"
done

# Missing loading states
rg "CircularProgressIndicator\|CoolLoadingState\|CoolSkeleton" lib/ --count
```

## Cross-References

- Color and typography tokens → `design-foundations` skill
- Screen-level composition → `screen-composition` skill
- Module-specific widget usage → `module-partner-ux` skill
- Trust and accessibility → `trust-accessibility` skill
