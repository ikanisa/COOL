---
name: Screen Composition
description: >
  Screen structure, copy budgets, simplification rules, anti-patterns, and
  screen LOC governance for the COOL Flutter super-app. Use when building new
  screens, redesigning screens, auditing screen complexity, or reviewing PRs
  for UI noise. Replaces the legacy frontend-ui-simplification skill.
  Source of truth: DESIGN_SYSTEM.md §9–10, §17.
---

# Screen Composition

Use this skill for Flutter mobile UI structure and cleanup work. The job is
not to make the UI more decorated. The job is to remove friction, reduce
visible decisions, and make the primary task obvious on a small phone.

This skill is for:

- Building new screens (enforcing budget rules from the start)
- Redesigning existing screens (simplification priority)
- Auditing screen complexity and noise
- Reviewing PRs for UI clutter, copy violations, or hierarchy problems
- Enforcing copy, form, and list budgets

This skill is NOT for:

- Color, font, or spacing token changes → use `design-foundations`
- Shared widget API changes → use `component-navigation`
- Module-specific UX decisions → use `module-partner-ux`

## North Star

- One obvious task per screen.
- One primary CTA above the fold.
- Quiet surfaces and restrained accents.
- Short copy with no backend or policy exposition in the main path.
- Secondary details in drill-downs, sheets, or later steps.
- Stable navigation with no competing models in one viewport.

## Non-Goals

- Do not add a new visual style to solve an information hierarchy problem.
- Do not increase motion, gradients, or chrome to make a crowded screen feel "premium."
- Do not preserve every existing section by shrinking it.
- Do not treat feature density as value. World-class apps win by compression and deferral.

## Above-the-Fold Budget

- **Max 3 visually separate blocks** above the fold.
- **Exactly 1 primary CTA** above the fold.
- **Max 5 primary actions** on a full screen.
- **Max 1 local navigation model** in the body.
- No stacked hero, quick actions, stats, and list all competing before scroll.

## Single-Card Rule

Except Home, every screen/sheet uses **one card per section**. No stacked
dual-cards — merge related content into one card with dividers.

## Copy Budgets

- **No visible UI copy may exceed 4 words.** Enforced by `dart tool/ui_copy_guard.dart`.
- Headlines: 2–4 words.
- Above-the-fold helper copy: 1 short sentence max.
- Use user language, not implementation language.
- Backend/sync/policy explanation → move out of the main path.
- CTA labels: action-first and specific.

## Form Budgets

- First step shows only essential fields.
- If the first step exceeds 6 inputs, split it.
- Optional detail behind `Add details`, a sheet, or a later step.
- Helper text stays adjacent and short.

## List & Data Budgets

- A row answers: what is it, what is the state, what can I do.
- Summary clusters: 2–3 metrics max.
- Historical data below current state or on a dedicated route.
- Filters only for dimensions users actually switch during a session.

## Simplification Decision Rules (Apply in Order)

1. If a section does not help the main task → **remove** it.
2. If two sections say similar things → **merge** them.
3. If a section is useful but not needed before the main action → **move** below fold or into sheet.
4. If a route contains both setup and usage → **split** them.
5. If a route contains both browse and transact → make transaction dominant, **demote** browse.
6. If a card only exists to route elsewhere → test if a **row or CTA** is cleaner.
7. If a proposed fix adds more components than it removes → **reject** it.

## Noise Elimination Checklist

Remove these from every screen:

- [ ] Multiple equal-weight sections fighting for attention
- [ ] Cards inside cards
- [ ] `Wrap` used as a metadata dumping ground
- [ ] Tab bars + filter chips + inline tiles on the same route
- [ ] Hero banners that restate the title without helping a decision
- [ ] Big explanatory cards for features already represented by a direct action
- [ ] Partner/admin surfaces using consumer marketing chrome
- [ ] Duplicate summaries in header, chips, AND detail rows
- [ ] Tappable cards that also contain the same primary button
- [ ] Multiple dashboards stacked before scroll
- [ ] Repeated summary pills and duplicate metadata
- [ ] Chips + tabs + segmented controls on the same screen without strong reason
- [ ] Empty states caused by bad filtering rather than missing data

## Domain Surface Usage

Screens should use dedicated `CoolSemanticColors` surface tokens to visually
distinguish product domains without heavy color usage:

| Screen Category | Surface Token | Example |
|---|---|---|
| Financial/wallet | `financialSurface` | MoMo balance card, statement list |
| Admin/operational | `operationalSurface` | Dashboard panels, config cards |
| Analytics/data | `analyticsSurface` | Charts, metrics panels |
| Mobility/routes | `routeSurface` | Trip cards, route summaries |
| Team/sports | `teamSurface` | Match cards, standings |
| Commerce/listings | `commerceSurface` | Product cards, marketplace |
| Proximity | `proximitySurface` | Nearby indicators |
| Contact/CTA | `contactSurface` | WhatsApp buttons, call CTAs |

Default to `cardSurface` if no domain-specific token applies.

## Preferred Screen Patterns

| Screen Type | Pattern |
|---|---|
| Landing | Summary → primary action cluster → recent items |
| Settings | Grouped rows → quiet header → destructive actions at bottom |
| Workflow | One step → one CTA → progressive disclosure for optional details |
| Service detail | Compact brand context → one primary path → facts below |
| Discovery | One filter model → one results list → optional map |
| Transaction | Summary → selection → total → confirm CTA → status |

## Screen LOC Governance

Budgets tracked in `docs/SCREEN_BUDGETS.md`:

| Budget | New Screens | Existing Screens |
|---|---|---|
| Target | ≤ 400 LOC | ≤ 700 LOC (stable) |
| Review | 401–700 LOC | 701–1000 LOC (debt) |
| Block | > 700 LOC | > 1000 LOC (hotspot) |

Do not grow hotspot files unless the work explicitly simplifies them.

## Anti-Patterns (Reject These)

- Generic "super-app" advice that ignores COOL's payment model
- Shell-tab treatment for every route
- Map-first UX without a working fallback
- Fake permission surfaces or counts
- Marketing-heavy partner screens hiding transactional clarity
- Giant multi-purpose profile, home, or admin screens that keep growing
- UI proposals assuming background sync the app does not have
- "Completed" payment states before SMS or backend confirmation
- Giant `Wrap` clusters as metadata dumps
- New visual styles to solve hierarchy problems
- Preserving every existing section by shrinking it

## Required Workflow

1. **Ground the audit in code** before making claims.
2. **Diagnose noise** at system, screen, and component levels.
3. **Simplify structure** before styling.
4. **Implement** the smallest structural change that materially reduces noise.
5. **Verify** the main task is clearer, not just different.

## Quick Audit Commands

```sh
# Route count
rg -o "GoRoute\(" -N lib/core/router/app_router.dart | wc -l

# Screen file count
find lib/features -type f -name '*screen.dart' | wc -l

# Largest screen files
find lib -type f -name '*.dart' -print0 | xargs -0 wc -l | sort -nr | head -n 20

# Widget usage counts
rg -o "CoolCard\(" -N lib | wc -l
rg -o "CoolButton\(" -N lib | wc -l
rg -o "StatusBadge\(" -N lib | wc -l
rg -o "SectionTitle\(" -N lib | wc -l
rg -o "TabPill\(" -N lib | wc -l

# Copy violations (lines with long visible strings)
dart tool/ui_copy_guard.dart

# Cards-inside-cards pattern
rg "CoolCard" lib/ -l | xargs rg "CoolCard" --count | awk -F: '$2 > 2'
```

## Cross-References

- Color tokens and typography used by screens → `design-foundations` skill
- Shared components referenced in screen patterns → `component-navigation` skill
- Module-specific UX decisions → `module-partner-ux` skill
- Full human-readable reference → `DESIGN_SYSTEM.md`
