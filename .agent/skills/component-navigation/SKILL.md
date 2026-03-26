---
name: Component & Navigation
description: >
  Shared widget catalog, navigation structure, routing rules, motion system,
  and state matrix for the COOL Flutter super-app. Use when building or
  modifying shared widgets, changing routes, adjusting bottom nav, implementing
  animations, or defining screen state coverage.
  Source of truth: DESIGN_SYSTEM.md §7–8, §11, §14.
---

# Component & Navigation

Use this skill when the task involves:

- Creating, modifying, or auditing shared widgets in `lib/shared/widgets/`
- Adding, moving, or removing routes in `app_router.dart`
- Changing the bottom navigation shell structure
- Implementing animations or transitions
- Defining state coverage for a screen or flow (loading, empty, error, etc.)

This skill is NOT for:

- Color tokens or typography → use `design-foundations`
- Screen layout or copy budgets → use `screen-composition`
- Module-specific UX decisions → use `module-partner-ux`

## Navigation

### Shell Structure

Bottom navigation: 5 destinations.

| Position | Label | Route |
|---|---|---|
| 1 | Home | `/home` |
| 2 | Groups | `/groups` |
| 3 (center) | MoMo | Pushes `/momo` (standalone) |
| 4 | Services | `/partners` |
| 5 | Profile | `/profile` |

### Navigation Rules

- MoMo is always a standalone pushed route, never a shell branch.
- Standalone routes must always expose a visible exit path (back/close).
- Sheets and QR pages must expose a clear back or close path.
- No competing navigation models in one viewport.
- Max 1 local navigation model per screen body.
- Tabs only for same-shape content sets.
- Filters go into sheets unless they are the main job of the route.

### Route Inventory

The canonical route registry lives in `docs/ROUTE_INVENTORY.md`. Any route
additions or major moves must update that file.

### Route Change Rules

- Route changes must regenerate `docs/ROUTE_INVENTORY.md` from code.
- New user-facing routes must ship with smoke or routing coverage.
- Route changes that grow screen scope must also refresh `docs/SCREEN_BUDGETS.md`.

## Component Library

All reusable components live under `lib/shared/widgets/`. Use existing
primitives before creating new ones.

### Core Primitives

| Component | Purpose | Key Rules |
|---|---|---|
| `CoolButton` | Primary/secondary actions | Restrained style, no glow. Loading/disabled states mandatory. |
| `CoolCard` | Content containers | Quiet surface, subtle shadow. Accept `className`. |
| `CoolTextField` | Text input | Theme-aware, loading/disabled states, explicit labels. |
| `StatusBadge` | Status indicators | Color + label, never color alone. |
| `SectionTitle` | Section headers | Short text, consistent weight. |
| `TabPill` | Segmented selection | Only for same-shape content. |
| `BalanceCard` | Financial summary | Mono font for values. |
| `GroupCard` | Group list items | Compact, state-visible. |
| `DriverCard` | Driver list items | State + distance visible. |
| `TripCard` | Trip list items | Summary-first. |
| `MemberRow` | Member list entries | Identity + role visible. |
| `QrShareSheet` | QR code sharing | Fixed black/white colors for scanner accuracy. |
| `WaButton` | WhatsApp actions | Branded green, specific to WA flows. |
| `VehicleChip` | Vehicle type indicator | Compact, icon-first. |

### Component Creation Rules

- Use composition over inheritance.
- All reusable components must:
  - Accept `className`
  - Support loading and disabled states
  - Support keyboard focus
  - Avoid inline styles (use tokens)
- Do not create a new card or button variant to fix a hierarchy problem.
- Every interactive element must have a unique, descriptive ID.
- Start with existing primitives in `lib/shared/widgets/` before creating new ones.

### Implementation Rules

- Prefer a single scroll model over nested scroll behaviors.
- Be skeptical of `SingleChildScrollView` + large `Column` — likely a dashboard that should be split.
- Replace large `Wrap` clusters with compact summary rows, vertical facts lists, or detail routes.
- If a section exists only to link elsewhere → test if a list row or CTA is cleaner.
- If a route mixes browse, configure, monitor, and transact → split it.

## Motion System — `CoolMotion`

### Principles

Motion should:
- Confirm input
- Preserve continuity
- Guide the next action
- Clarify success or failure

Motion should NOT:
- Trivialize financial risk
- Create false confidence
- Mask slow data loads
- Distract from the primary task

### Duration Scale

| Token | Duration | Use |
|---|---|---|
| `press` | 110ms | Micro-feedback (tap, toggle, press state) |
| `quick` | 180ms | State changes, reveals, chip selections |
| `standard` | 240ms | Page transitions, expansions, tab switches |
| `emphasized` | 300ms | Sheet presentations, large reveals, celebrations |

### Curves

| Token | Value | Use |
|---|---|---|
| `enterCurve` | `Cubic(0.2, 0.0, 0.0, 1.0)` | Elements entering the screen (M3 standard ease) |
| `exitCurve` | `Cubic(0.4, 0.0, 1.0, 1.0)` | Elements leaving the screen (M3 accelerate) |
| `pressCurve` | `Curves.easeInOut` | Press/release micro-animations |

### Reduced Motion

Always support `MediaQuery.disableAnimations`:
- Skip decorative animations entirely
- Keep functional transitions but reduce to instant duration
- Never block interaction behind an animation

## Tap Targets — `CoolTapTargets`

| Token | Value | Use |
|---|---|---|
| `minimum` | 48dp | Absolute minimum for any interactive element |
| `comfortable` | 56dp | Standard buttons, list rows, chips |
| `navigation` | 64dp | Bottom nav items, primary CTA areas |

## State Matrix

Every important screen or flow must define these states:

| State | Description |
|---|---|
| Resting | Normal loaded state |
| Loading / Skeleton | Data being fetched |
| Empty | No data, not a filtering bug |
| Partial data | Some data loaded, some pending |
| Error | Operation failed, actionable copy |
| Offline / Stale | Cached data, explicit staleness |
| Permission-blocked | Missing required permission |
| Rollout-disabled | Not available in this market/config |
| Success | Operation completed, confirmation |

### Critical Flows Requiring Full State Coverage

- MoMo payments
- Mobility (trip scheduling, driver state)
- Tickets and checkout
- Profile and access settings
- Admin configuration

### State Implementation Pattern

```dart
// Use sealed classes or enum + switch for exhaustive state handling
sealed class ScreenState<T> {
  const ScreenState();
}
class Loading<T> extends ScreenState<T> {}
class Loaded<T> extends ScreenState<T> { final T data; const Loaded(this.data); }
class Empty<T> extends ScreenState<T> {}
class Error<T> extends ScreenState<T> { final String message; const Error(this.message); }
class Offline<T> extends ScreenState<T> { final T? staleData; const Offline(this.staleData); }
```

## Audit Commands

```sh
# Count shared widgets
find lib/shared/widgets -type f -name '*.dart' | wc -l

# Route count
rg -o "GoRoute\(" -N lib/core/router/app_router.dart | wc -l

# Shell branch count
rg -o "StatefulShellBranch\(" -N lib/core/router | wc -l

# Widget usage frequency
for w in CoolButton CoolCard StatusBadge SectionTitle TabPill CoolTextField BalanceCard; do
  echo "$w: $(rg -o "${w}\(" -N lib | wc -l | tr -d ' ')"
done

# Missing loading states
rg "CircularProgressIndicator\|LinearProgressIndicator" lib/ --count

# Missing error states (screens without error handling)
find lib/features -name '*screen.dart' -exec grep -L "error\|Error\|catch" {} \;
```

## Cross-References

- Color and typography tokens used by components → `design-foundations` skill
- Screen-level composition using these components → `screen-composition` skill
- Module-specific widget usage → `module-partner-ux` skill
- Full human-readable reference → `DESIGN_SYSTEM.md`
