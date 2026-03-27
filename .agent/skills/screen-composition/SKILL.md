---
name: Screen Composition
description: >
  Screen structure, copy budgets, simplification rules, anti-patterns, and
  screen LOC governance for the COOL Flutter super-app. Mobi × Rayon dark
  fintech aesthetic — uppercase headings, mobi-grid backgrounds, high-density
  data layouts. Use when building new screens, redesigning screens, auditing
  screen complexity, or reviewing PRs for UI noise.
---

# Screen Composition

Use this skill for Flutter mobile UI structure and cleanup work. The job is
to make every screen feel like a fintech terminal — precise, data-dense,
and immediately actionable on a small phone.

This skill is for:

- Building new screens (enforcing budget rules from the start)
- Redesigning existing screens (simplification priority)
- Auditing screen complexity and noise
- Reviewing PRs for UI clutter, copy violations, or hierarchy problems

This skill is NOT for:

- Color tokens or typography → use `design-foundations`
- Shared widget API changes → use `component-navigation`
- Module-specific UX decisions → use `module-partner-ux`

## North Star

- One obvious task per screen.
- One primary CTA above the fold.
- Dark surface with mobi-grid background.
- Uppercase section headers in Barlow Condensed.
- Mobi-label/mobi-value pairs for structured data.
- Secondary details in drill-downs, sheets, or later steps.
- Floating glass pill nav visible only on main screens.

## Screen Anatomy (Standard Pattern)

```
┌─────────────────────────────┐
│ Sticky Header               │  ← bg-surface/80 backdrop-blur-xl
│ [←] SCREEN TITLE    [Badge] │     border-b border-white/5
├─────────────────────────────┤
│                             │
│  SECTION HEADER             │  ← Barlow Condensed, uppercase, primary color
│  Description text           │  ← Inter, textSecondary, small
│                             │
│  ┌─────────────────────┐    │
│  │ Card (surfaceAlt)   │    │  ← border white/5, rounded-2xl
│  │ Content             │    │
│  └─────────────────────┘    │
│                             │
│  SECTION HEADER             │
│  ┌─────────────────────┐    │
│  │ Card                │    │
│  └─────────────────────┘    │
│                             │
│           ···               │
│                             │
│  [Floating Nav Pill]        │  ← Only on main screens
└─────────────────────────────┘
```

### Sticky Header Pattern

```dart
// Sticky header with blur
Container(
  color: CoolColors.surface.withOpacity(0.80),
  // + BackdropFilter(blur: 24)
  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  border: Border(bottom: BorderSide(color: CoolColors.borderSubtle)),
  child: Row(
    children: [
      BackButton(rounded-xl, bg-white/5),
      Expanded(child: Column(title, subtitle)),
      TrailingWidget,
    ],
  ),
)
```

### Section Header Pattern

```dart
// Section header — Barlow Condensed, uppercase, primary color
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('SECTION TITLE',
      style: TextStyle(
        fontFamily: 'BarlowCondensed',
        fontWeight: FontWeight.w800,
        color: CoolColors.primary,  // blue section headers
        // fontSize from headlineSmall
      ),
    ),
    Text('Brief description',
      style: TextStyle(
        color: CoolColors.textSecondary.withOpacity(0.6),
        fontSize: 14,
      ),
    ),
  ],
)
```

## Above-the-Fold Budget

- **Max 3 visually separate blocks** above the fold.
- **Exactly 1 primary CTA** above the fold.
- **Max 5 primary actions** on a full screen.
- **Max 1 local navigation model** in the body.

## Single-Card Rule

Except Home, every screen uses **one card per section**. No stacked
dual-cards — merge related content into one card with separators.

## Copy Budgets

- Headlines: 2–4 words, **always uppercase**.
- Above-the-fold helper copy: 1 short sentence max, **14px, uppercase, bold**.
- Section descriptions: brief, `textSecondary`, `opacity-60`.
- CTA labels: action-first, specific, uppercase.
- No explanatory paragraph copy when structure can do the work.

## Data Display Patterns

### Mobi Label + Value Pair

The signature data display pattern:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // mobi-label
    Text('TRANSACTION ID',
      style: TextStyle(
        fontFamily: 'JetBrainsMono', fontSize: 10,
        fontWeight: FontWeight.w600, letterSpacing: 1.0,
        color: CoolColors.textSecondary,
      ),
    ),
    // mobi-value
    Text('#TX-8829-AF',
      style: TextStyle(
        fontFamily: 'JetBrainsMono', fontSize: 14,
        fontWeight: FontWeight.w500, letterSpacing: -0.28,
        color: CoolColors.textPrimary,
      ),
    ),
  ],
)
```

### Quick Actions Grid (Home)

5-column grid of icon actions:

```dart
GridView.count(
  crossAxisCount: 5,
  children: [
    QuickAction(icon: Send, label: 'SEND', color: accent),
    QuickAction(icon: Smartphone, label: 'AIRTIME', color: blue/20),
    QuickAction(icon: CreditCard, label: 'PAY', color: orange/20),
    QuickAction(icon: Users, label: 'JOIN', color: success/20),
    QuickAction(icon: PieChart, label: 'SCORE', color: purple/20),
  ],
)
```

Quick action icon container: 56×56, `rounded-md` (8px), colored bg.
Label: 14px, black weight, uppercase, textSecondary.

### Transaction Row

```dart
Row(
  children: [
    // Direction indicator (rounded-pill, success/error tinted)
    Container(40×40, rounded-pill, bg: type==in ? success/10 : error/10),
    // Details
    Column(
      Text(title, 14px, font-black, textPrimary),
      Text(date, 14px, textSecondary, font-semibold),
    ),
    Spacer(),
    Text(amount, 14px, font-black, type==in ? success : textPrimary),
  ],
)
```

## Noise Elimination Checklist

Remove these from every screen:

- [ ] Multiple equal-weight sections fighting for attention
- [ ] Cards inside cards
- [ ] Warm/earthy tones or claymorphism shadows
- [ ] Tab bars + filter chips + inline tiles on the same route
- [ ] Hero banners that restate the title
- [ ] Oversized radii (>16px on cards)
- [ ] Domain-specific tinted backgrounds (financialSurface, etc.)
- [ ] Mixed-case headings (all must be uppercase)
- [ ] Non-mono labels for data values
- [ ] Manrope or DM Mono font usage (must be Inter/Barlow/JetBrains)

## Preferred Screen Patterns

| Screen Type | Pattern |
|---|---|
| Landing / Home | Header → Quick actions grid → Recent activity list |
| Settings / Profile | Avatar card → grouped setting rows → destructive at bottom |
| Workflow | One step → one CTA → progressive disclosure |
| Detail | Sticky header → content card → action footer |
| List / Browse | Sticky header with filter tabs → scrollable card list |
| Admin | Data table cards → action buttons → charts |

## Screen LOC Governance

| Budget | New Screens | Existing Screens |
|---|---|---|
| Target | ≤ 400 LOC | ≤ 700 LOC (stable) |
| Review | 401–700 LOC | 701–1000 LOC (debt) |
| Block | > 700 LOC | > 1000 LOC (hotspot) |

## Background Treatment

Every screen uses:
1. `CoolColors.surface` (#050505) as base background
2. `MobiGrid` overlay (24px gridlines at white/8)
3. Optional `AtmosphericBackground` (blurred radial blobs) on discovery/landing screens

## Anti-Patterns (Reject These)

- Claymorphism or clay shadows on any element
- Warm earthy tones (cream, ivory, green-black)
- Light theme or light mode surfaces
- Oversized border radii (sm=16, md=22, etc.)
- Domain-specific colored backgrounds
- Non-uppercase headings
- Paragraph-length explanatory copy
- Manrope, DM Mono, or any non-system font

## Audit Commands

```sh
# Screen file count
find lib/features -type f -name '*screen.dart' | wc -l

# Largest screen files
find lib -type f -name '*.dart' -print0 | xargs -0 wc -l | sort -nr | head -n 20

# Legacy font usage (must be zero)
rg "Manrope\|DM.Mono\|DMMono" lib/ --count

# Legacy shadow usage (must be zero)
rg "CoolShadows\.clay\|CoolShadows\.glass" lib/ --count

# Claymorphism remnants
rg "claymorphi\|CoolGlassCard" lib/ --count
```

## Cross-References

- Color tokens and typography → `design-foundations` skill
- Shared components → `component-navigation` skill
- Module-specific UX decisions → `module-partner-ux` skill
