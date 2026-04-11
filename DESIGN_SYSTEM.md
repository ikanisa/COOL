# Minimalist Mobile UI System

## Objective

Redesign the existing production app additively, not from scratch.

- Preserve business logic, flows, and route architecture.
- Replace visual noise with a disciplined, reusable mobile UI system.
- Reduce text, reduce duplicate patterns, and improve scan speed.
- Make the app feel lighter, calmer, more premium, and more native.

## Product Guardrails

- Keep the current core destinations and user journeys intact unless a path is clearly redundant.
- Prefer refactoring shared primitives before changing feature behavior.
- Move secondary information into chips, badges, expandable sections, or sheets before adding more visible copy.
- Standardize repeated UI first on the highest-frequency surfaces: home, groups, BioPay, profile, then secondary/admin screens.

## Current UI Audit

### App-level issues

- Too many surfaces compete for attention through glass, blur, gradients, glow, and oversized headings.
- Text is often doing structural work that layout and components should do.
- Some screens repeat labels, section titles, and helper text that add density without adding meaning.
- Buttons, pills, tiles, and cards are not always using the same spacing rhythm or emphasis rules.
- Navigation chrome was heavier than necessary and visually louder than the screen content.

### Where text is overused

- Large hero copy where one short title plus one compact status row is enough.
- Repeated section framing such as title plus subtitle plus caption plus badge on the same block.
- Long list subtitles where a chip, badge, icon, or metric row would scan faster.
- Uppercase labels used as decoration rather than information.

### Where widgets should replace raw text

- Status and category labels should become `StatusBadge` or chips.
- Short data summaries should become `CoolMetricRow`.
- Repeated action rows should use `CoolListTile`.
- Quick actions should be compact icon-led cards, not text-led buttons.
- Secondary actions should move into bottom sheets or overflow menus instead of occupying permanent visible space.

### Key screen opportunities

- `Home`: simplify the hero, reduce card noise, use compact quick-action tiles, and make communities/operations scan as lists instead of posters.
- `Groups`: treat group rows as operational list items with clear amount, status, and action, not dense promotional cards.
- `BioPay`: make the payment entry points feel immediate and native through four clean action tiles.
- `Profile`: shorten copy, rely on icon-led settings rows, and keep metadata compact.
- Secondary/admin screens: adopt the same primitives incrementally rather than inventing local patterns.

## Core Design Principles

1. Fewer words.
   Use short labels, not descriptive paragraphs.
2. Widget first.
   Use cards, tiles, chips, badges, segmented controls, sheets, and metric rows before inventing bespoke text layouts.
3. One visual priority at a time.
   Every screen should have a primary action, a primary information block, and quiet secondary detail.
4. Spacing creates hierarchy.
   Use whitespace and grouping instead of more borders and labels.
5. Icons must carry meaning.
   Icons exist to improve scanning, not to decorate.
6. Reuse is mandatory.
   If a pattern appears twice, it should become a shared component.
7. Surface depth stays subtle.
   Use restrained contrast, restrained borders, and restrained elevation.
8. Navigation stays obvious.
   Primary destinations must remain reachable in one tap with low visual friction.

## Design Tokens

### Color roles

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `appBackground` | `#0F141B` | `#F3F5F7` | Main screen background |
| `elevatedBackground` | `#131A23` | `#FFFFFF` | Raised page sections |
| `cardSurface` | `#18212B` | `#FFFFFF` | Default cards |
| `cardSurfaceStrong` | `#202A36` | `#F0F3F6` | Secondary emphasis |
| `overlaySurface` | `#161E28` | `#FFFFFF` | Sheets, dialogs, nav chrome |
| `accent` | `#4D79FF` | `#315EEA` | Primary action |
| `accentDeep` | `#305FE8` | `#2446B9` | Strong accent state |
| `primaryText` | `#F6F8FB` | `#111827` | Primary content |
| `secondaryText` | `#9BA7B4` | `#5E6B7A` | Secondary content |
| `tertiaryText` | `#6D7884` | `#8A96A3` | De-emphasized content |
| `divider` | `#1AFFFFFF` | `#1409111F` | Subtle separation |
| `border` | `#1FFFFFFF` | `#1609111F` | Quiet borders |
| `success` | `#23A26D` | `#1C8C5D` | Positive status |
| `warning` | `#D39A2A` | `#C28212` | Caution |
| `danger` | `#D95C5C` | `#CC5757` | Destructive/error |
| `info` | `#4D79FF` | `#315EEA` | Informational/accent |

### Typography

- Font families:
  - `Manrope` for display, heading, title, and body
  - `Inter` for labels, controls, and utility text
  - `DM Mono` for codes, values, and technical identifiers
- Weight scale:
  - `w500` regular utility/body
  - `w600` emphasis and controls
  - `w700` hero/value emphasis
- Type scale:
  - `displayLarge` 40
  - `displayMedium` 34
  - `displaySmall` 28
  - `headlineLarge` 24
  - `headlineMedium` 20
  - `headlineSmall` 18
  - `titleLarge` 18
  - `titleMedium` 16
  - `titleSmall` 14
  - `bodyLarge` 16
  - `bodyMedium` 14
  - `bodySmall` 14
  - labels all remain at 14

### Spacing

- Grid scale:
  - `x1` 4
  - `x2` 8
  - `x3` 12
  - `x4` 16
  - `x5` 20
  - `x6` 24
  - `x7` 32
  - `x8` 40
  - `x9` 48
  - `x10` 64
- Default page rhythm:
  - `pagePadding` horizontal 20, vertical 16
  - section padding 24
  - dense section padding 20

### Radii

- `xs` 10
- `sm` 14
- `md` 18
- `lg` 22
- `xl` 28
- `xxl` 32
- `pill` 999

### Motion

- Motion should confirm state change, not advertise itself.
- Prefer fast fades, light slides, and subtle press feedback.
- Remove bouncy or theatrical transitions from high-frequency actions.

## Component Library

### Core surfaces

- `CoolCard`
  - default content surface
  - optional outline, accent, or glass variant
- `CoolSectionCard`
  - groups related rows under one quiet section label
- `CoolScreenBackground`
  - provides calm page-level backdrop without visual clutter

### Actions

- `CoolButton`
  - `primary` for one main action per surface
  - `secondary` or `outline` for supporting actions
  - icon-only button only when the action is universally obvious
- Floating action button
  - icon-only
  - only on screens where creation is the dominant action

### Lists and data

- `CoolListTile`
  - standard row for settings, entities, navigation, and operational data
  - title first, subtitle only for real metadata
- `CoolMetricRow`
  - short label/value rows for balances, counts, codes, and targets
- `StatusBadge`
  - short state or category indicator

### Selection and filtering

- `CoolChipBar`
  - segmented selection, tabs, and filters
- `TabPill`
  - use only where an existing tab-pills pattern already exists and should remain

### Icons

- `CoolIcons`
  - one icon per concept across the app
- `CoolIconBox`
  - standardized icon container for rows, tiles, and empty states

### Inputs

- shared text field theme
- `CoolSearchField`
  - compact, bordered, and single-purpose
- helper text only when the task is ambiguous or risky without it

### Feedback states

- `CoolEmptyView`
  - title, one short line, one optional action
- `CoolErrorView`
  - compact retry pattern
- `StatusBadge` + toast/snackbar
  - for success and transient confirmation
- shared loading states
  - skeletons for rows/cards, not spinners for whole pages unless necessary

### Sheets and overlays

- `CoolBottomSheet`
  - default secondary action container
- dialogs
  - only for high-risk confirmation
- sticky bottom action bars
  - only when an action must remain accessible while content scrolls

## Icon Usage Rules

- Use one icon family and one visual weight throughout the app.
- If the label is clear without text, use icon-only for high-frequency actions like back, close, add, search, settings.
- If the action or category may be ambiguous, pair the icon with a short label.
- Do not stack decorative icons around the same concept.
- Do not use icons as illustrations inside dense operational screens unless they improve scan speed.

## Typography Rules

- Prefer one short title per screen.
- Prefer one heading size per section level.
- Avoid uppercase unless it adds utility, such as a tiny section kicker or code-like label.
- Do not add descriptive paragraphs to explain obvious actions.
- Use subtitles only for metadata, not marketing copy.
- Keep titles to 1–3 words where possible.

## Spacing and Hierarchy Rules

- Put 24 between major blocks.
- Put 12 or 16 between related controls.
- Put 8 between tightly related label/value or icon/text elements.
- Use borders sparingly and only at low contrast.
- Let card groups, not dividers, do most of the organizational work.
- Reserve accent color for selection, active state, and primary action.

## Reusable Widget Patterns

### Summary card

- short kicker
- one strong value
- one compact status row or chip
- one immediate action if needed

### Quick action grid

- 2-column compact cards
- icon top-left
- arrow or chevron top-right
- short label only

### Entity list row

- leading icon box
- title
- one line of metadata
- trailing value, badge, or chevron

### Status strip

- badge or chip row for state, visibility, membership, availability

### Compact section

- short header
- optional one-tap trailing control
- list or card body immediately below

### Empty state

- icon
- short title
- one sentence max
- one optional button

## Screen-Level Redesign Guidance

### Home

- Keep one primary summary card for savings.
- Use a 2x2 quick-action grid.
- Show communities as compact operational rows with amount and action.
- Show operations as dense list cards with signed amount and timestamp.
- Remove decorative headers and long introductory copy.

### Groups

- Keep the current groups flow and filters.
- Use chip/segmented switching for "mine" vs "discover".
- Present each group as one compact row-card with name, members, amount, and a single clear action.
- Keep invite handling visible but lightweight.

### BioPay

- Keep the four main payment entry points.
- Use one clean headline and a four-tile action board.
- Use icon-led action cards with short labels only.
- Push secondary explanation into enrollment/setup screens rather than the home entry screen.

### Profile

- Treat settings as grouped `CoolListTile` rows.
- Keep the top summary compact and data-led.
- Hide secondary explanation unless needed for security or destructive actions.

### Secondary and admin screens

- Rebuild repeated metric panels, user rows, and operational dashboards from the same card/tile/badge primitives.
- Replace bespoke section headers with standard header + section card patterns.

## Navigation Guidance

- Keep top-level navigation compact and visually quieter than content.
- Show only the primary destinations in bottom navigation.
- Prefer contextual entry from cards, chips, and quick actions over extra top-level items.
- Put destructive or infrequent actions in sheets or menus.
- Avoid parallel paths to the same task unless one is contextual and clearly faster.

## Incremental Implementation Plan

### Phase 1: Foundation

- theme tokens
- type scale
- spacing and radii
- buttons, cards, badges, tiles, chips, sheets

### Phase 2: High-frequency screens

- home
- groups
- BioPay
- profile

### Phase 3: Secondary feature migration

- settings sub-screens
- group detail and settings
- payment and enrollment flows
- admin/ops screens

### Phase 4: Cleanup

- remove deprecated visual language
- remove duplicated local widgets
- align copy to short-label rules
- refresh goldens and regression tests

## Implementation Rules

- Add new UI through shared primitives first.
- Do not fork local one-off versions of cards, list rows, chips, or icon containers.
- Migrate screen by screen, starting with the most used surfaces.
- Keep old flows running while visual primitives are replaced underneath.
- Every migrated screen should reduce visible copy, visible chrome, or visible decision count.

## File Map

Core implementation lives in:

```text
lib/core/theme/
lib/core/router/shell_route.dart
lib/shared/widgets/cool_card.dart
lib/shared/widgets/cool_button.dart
lib/shared/widgets/cool_chip_bar.dart
lib/shared/widgets/cool_icon_box.dart
lib/shared/widgets/cool_list_tile.dart
lib/shared/widgets/cool_metric_row.dart
lib/shared/widgets/cool_section_card.dart
lib/shared/widgets/status_badge.dart
lib/shared/widgets/cool_empty_view.dart
lib/shared/widgets/cool_bottom_sheet.dart
```

## Final Standard

Every screen should feel reduced to its strongest form:

- less text
- more meaning
- clearer actions
- stronger hierarchy
- quieter surfaces
- faster scanning
- consistent components
- premium mobile-native polish
