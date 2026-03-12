---
name: frontend-ui-simplification
description: >
  Audit and simplify Flutter mobile UIs by eliminating noise, collapsing
  competing sections, enforcing one-task-per-screen hierarchy, and applying
  world-class mobile product standards. Use when the user asks to simplify
  screens, reduce clutter, clean up flows, remove excessive cards or chips,
  sharpen copy, or turn a UI audit into concrete cleanup work.
---

# Frontend UI Simplification

Use this skill for Flutter mobile UI cleanup work. The job is not to make the UI more decorated. The job is to remove friction, reduce visible decisions, and make the primary task obvious on a small phone.

This skill is designed to work in any Flutter mobile repo, but it is grounded in the current structure and failure modes of `COOL`.

## North Star

- One obvious task per screen.
- One primary CTA above the fold.
- Quiet surfaces and restrained accents.
- Short copy with no backend or policy exposition in the main path.
- Secondary details moved into drill-downs, sheets, or later steps.
- Stable navigation with no competing navigation models in one viewport.

## Non-Goals

- Do not add a new visual style to solve an information hierarchy problem.
- Do not increase motion, gradients, or decorative chrome to make a crowded screen feel "premium".
- Do not preserve every existing section by shrinking it.
- Do not treat feature density as value. World-class mobile apps win by compression and deferral.

## Required Workflow

1. Ground the audit in code before making claims.
2. Diagnose noise at the system, screen, and component levels.
3. Simplify structure before styling.
4. Implement the smallest structural change that materially reduces noise.
5. Verify the main task is clearer, not just different.

## Quick Audit Commands

Use these before writing conclusions so the audit stays code-grounded.

```sh
rg -o "GoRoute\\(" -N lib/core/router/app_router.dart | wc -l
find lib/features -type f -name '*screen.dart' | wc -l
find lib -type f -name '*.dart' -print0 | xargs -0 wc -l | sort -nr | head -n 20
rg -o "CoolCard\\(" -N lib | wc -l
rg -o "CoolButton\\(" -N lib | wc -l
rg -o "Wrap\\(" -N lib/features | wc -l
rg -o "SingleChildScrollView\\(" -N lib | wc -l
rg -o "CustomScrollView\\(" -N lib | wc -l
rg -n "SectionTitle\\(|Wrap\\(|GridView\\.(count|builder)\\(|ChoiceChip\\(|FilterChip\\(|TabBar\\(|TabPill\\(" lib/features
```

For a target screen, also collect:

- file length
- number of local private widget classes
- number of visible sections
- count of primary and secondary actions
- count of chips, badges, and summary pills
- whether the screen mixes browse, setup, transact, and monitor responsibilities

## Audit Model

Always evaluate the target UI in this order.

### 1. System

- app shell and top-level navigation
- shared widgets in `lib/shared/widgets/`
- theme tokens in `lib/core/theme/`
- route structure in `lib/core/router/`

### 2. Screen

- purpose of the route
- first action above the fold
- section count
- competing summaries
- local navigation inside the screen body

### 3. Component

- chips, badges, pills, and wraps
- cards that only route elsewhere
- duplicate tap targets
- long helper copy
- decorative gradients, emojis, and status chrome

If the system is already reasonably restrained, spend effort on screen composition first.

## Hard Standards

### Screen Budgets

- Max 3 visually separate blocks above the fold.
- Exactly 1 primary CTA above the fold.
- Max 5 primary actions on a full screen.
- Max 1 local navigation model in the body.
- No stacked hero, quick actions, stats, and list all competing before scroll.
- No duplicate action path unless the card tap and button perform meaningfully different actions.

### Copy Budgets

- Headline: 2 to 6 words.
- Above-the-fold helper copy: 1 short sentence max.
- Use user language, not implementation language.
- If text explains sync behavior, backend source, internal workflow, or policy nuance, move it out of the main path.
- CTA labels should be action-first and specific.

### Visual Budgets

- Accent color is for the primary CTA, active state, or critical status only.
- Gradients are off by default. Use them only for brand moments, one hero, or explicit celebration.
- Do not stack glow, gradient, border, and shadow on the same element by default.
- Chips and badges exist to help a decision, not to decorate metadata.
- Emoji are allowed only when they materially improve recognition, such as country flags, branded content, or a deliberate empty-state illustration.

### Form Budgets

- Initial step shows only essential fields.
- If the first step exceeds 6 inputs, split it.
- Optional detail belongs behind `Add details`, a sheet, or a later step.
- Helper text should stay adjacent to the field and stay short.

### List And Data Budgets

- A row should answer: what is it, what is the state, what can I do.
- Any summary cluster should show 2 to 3 metrics max.
- Historical data belongs below current state or on a dedicated route.
- Filters should exist only for dimensions users actually switch during a session.

## Eliminate These Noise Patterns

- Multiple equal-weight sections fighting for attention.
- Cards inside cards.
- `Wrap` used as a dumping ground for metadata.
- Tab bars plus filter chips plus inline tiles on the same route.
- Hero banners that restate the title without helping a decision.
- Big explanatory cards for features already represented by a direct action.
- Partner and admin surfaces using consumer marketing chrome.
- Duplicate summaries repeated in the header, chips, and detail rows.
- Tappable cards that also contain the same primary button.

## Prefer These Patterns

- Landing screen: summary, primary action cluster, recent items.
- Settings screen: grouped rows, quiet header, destructive actions isolated at the bottom.
- Workflow screen: one step, one CTA, progressive disclosure for optional details.
- Service detail screen: compact brand context, one primary path, supporting facts below.
- Discovery screen: one filter model, one results list, optional map only if it materially changes selection.

## Flutter Implementation Rules

- Start with existing primitives in `lib/shared/widgets/`.
- Do not create a new card or button variant to fix a hierarchy problem.
- Prefer a single scroll model over nested scroll behaviors.
- Be skeptical of `SingleChildScrollView` plus a large `Column`; it often hides a dashboard that should be split or reduced.
- Replace large `Wrap` clusters with one of these:
  - a compact 2 to 3 item summary row
  - a vertical facts list
  - a dedicated detail route or sheet
- If a section exists only to link elsewhere, test whether it should become a list row or a single CTA.
- If the same route mixes browse, configure, monitor, and transact, split it.

## Decision Rules

Apply these in order.

1. If a section does not help the main task, remove it from the route.
2. If two sections say similar things, merge them.
3. If a section is useful but not needed before the main action, move it below the fold or into a sheet.
4. If a route contains both setup and usage, split them.
5. If a route contains both browse and transact, make the transaction path dominant and demote browse.
6. If a card only exists to route to another screen, test whether a row or CTA is cleaner.
7. If a proposed fix adds more components than it removes, reject it.

## Output Format For Simplification Work

When asked to simplify a route or flow, use this structure in your analysis or implementation plan:

```md
Primary task:
Current clutter:
Keep:
Remove:
Move:
Merge:
Primary CTA:
New above-the-fold structure:
Risks:
```

Keep the analysis blunt and structural. Avoid long aesthetic commentary.

## COOL Repo Grounding

Recompute these numbers before citing them, but use them to understand the current shape of the app.

- Roughly `55` routes in `lib/core/router/app_router.dart`
- Roughly `53` screen files in `lib/features/`
- Roughly `121` `CoolCard` usages
- Roughly `74` `CoolButton` usages
- Roughly `43` `Wrap` usages in screen files
- Roughly `33` `SingleChildScrollView` usages
- Roughly `22` `CustomScrollView` usages

Interpretation:

- The main visual primitives are already quieter than older versions of the app.
- The bigger problem now is compositional overload inside large routes.
- Cleanup work should target screen responsibilities first, then micro-visual polish.

## COOL Hotspots

Treat these as redesign targets, not polish targets.

- `lib/features/mobility/screens/schedule_trip_screen.dart`
  Current signal: about `2670` lines and about `26` local classes.
- `lib/features/profile/screens/profile_screen.dart`
  Current signal: about `1839` lines and about `20` local classes.
- `lib/features/mobility/screens/driver_profile_screen.dart`
  Current signal: about `1597` lines with heavy section density.
- `lib/features/mobility/screens/trip_board_screen.dart`
  Current signal: about `1536` lines.
- `lib/features/mobility/screens/mobility_home_screen.dart`
  Current signal: about `1494` lines; mixes discovery, driver state, tabs, filters, results, and map toggle.
- `lib/features/credit/screens/credit_readiness_screen.dart`
  Current signal: about `1476` lines; mixes snapshot, next step, checklist, applications, and partner discovery.
- `lib/features/partners/screens/bank_partner_screen.dart`
  Current signal: about `1349` lines; mixes hero, quick actions, content source, grouped services, and support.
- `lib/features/credit/screens/credit_score_screen.dart`
  Current signal: about `1318` lines with multiple summary layers.
- `lib/features/partners/screens/prisma_partner_screen.dart`
  Current signal: about `1241` lines with similar density patterns.
- `lib/features/momo/screens/momo_screen.dart`
  Current signal: about `1149` lines and very high equal-weight module density.

## COOL-Specific Anti-Patterns

- `lib/features/mobility/screens/mobility_home_screen.dart`
  Driver mode, online status, tab section, filter bar, results, and map toggle all live on one route.
- `lib/features/credit/screens/credit_readiness_screen.dart`
  Banner, overview, next step, checklist, applications, and partner discovery compete on one long screen.
- `lib/features/partners/screens/bank_partner_screen.dart`
  Promotional hero and dense service browsing are fused instead of staged.
- `lib/features/partners/screens/partners_screen.dart`
  In-screen segmented tabs are doing work that clearer routing could do.
- `lib/features/profile/screens/profile_screen.dart`
  Settings hub, payments hub, QR utility, support, status, admin tools, and danger zone all live in one scroll path.
- `lib/features/momo/screens/momo_screen.dart`
  Statements, USSD, QR, and NFC are surfaced as equal-weight modules.

## Important Correction To The Existing Audit

`docs/frontend_ui_simplification_audit.md` is directionally useful, but do not repeat it blindly.

Several shared-widget conclusions in that document are now stale:

- `lib/shared/widgets/cool_screen_background.dart` is already flattened to a plain background.
- `lib/shared/widgets/cool_card.dart` already uses restrained shadows and a quiet default surface.
- `lib/shared/widgets/cool_button.dart` is already materially calmer than an older glow-heavy style.

Implication:

- Do not spend the next cleanup wave re-solving shared chrome that is already mostly fixed.
- Spend it on route architecture, section reduction, copy compression, and progressive disclosure.

## Acceptance Checklist

A simplification pass is not done until all are true:

- The route purpose is obvious in under 3 seconds.
- Above the fold presents one clear decision.
- Secondary sections no longer compete visually with the primary action.
- The copy is shorter than before.
- The number of visible blocks or controls is materially lower.
- No new style system or decorative device was introduced without a system reason.
- No important capability was removed without an alternate path.
- The screen feels calmer on a small phone, not just prettier on a large simulator.

## When To Load More Context

- Read `docs/frontend_ui_simplification_audit.md` when you need the older screen-by-screen baseline.
- Read the target screen file and shared widgets before trusting any old audit statement.
- If a route is brand-heavy, inspect the partner-specific widgets before suggesting generic simplification.
