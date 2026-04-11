# Admin UI Redesign System

## Objective

Redesign the existing production admin panel additively.

Do not rebuild platform logic.
Do not break permissions, routes, or operational flows.
Do replace text-heavy management layouts with a disciplined admin interface built around reusable widgets, tables, filters, badges, drawers, and action surfaces.

This redesign targets:

- higher scan speed
- lower cognitive load
- clearer hierarchy
- fewer repeated controls
- stronger operational feedback
- consistent admin-native patterns across modules

## Current Admin Audit

### Cross-screen issues

- Too much explanatory copy relative to the amount of actionable state.
- Too many one-off layout patterns across users, roles, analytics, and operations.
- Summary information was spread across raw text, ad hoc cards, and long sections instead of a stable KPI system.
- Primary actions were not always surfaced first.
- Status semantics were inconsistent across screens.
- Secondary detail often lived inline instead of behind drawers, rows, or expandable detail surfaces.

### Screen-by-screen audit

#### Admin dashboard

- Navigation was useful but visually flat.
- Module access lacked stronger grouping by urgency and function.
- Important destinations competed equally with low-frequency configuration routes.

#### User management

- Inventory and cleanup actions were separated weakly.
- Search, filter, status, and edit actions were present but not unified under one management pattern.
- MoMo reachability, mock data, and admin status were not surfaced as a compact operational summary.

#### Admin roles

- Role grants and revokes worked, but the surface was more form-led than ledger-led.
- Scope visibility was weaker than it should be for bank-scoped permissions.
- The screen needed stronger emphasis on assignment volume, role distribution, and direct revoke flow.

#### Audit log

- Event data was useful but visually noisy.
- The screen benefited more from timeline cards, compact badges, and expandable payload review than from verbose rows.

#### System analytics

- Counts and distributions existed, but hierarchy between top-line state and detailed breakdowns was not disciplined.
- Repeated count patterns needed a single metric system.

#### Operations

- Operations data was valuable but fragmented across multiple surface styles.
- Release health, triage, sender inventory, manual review, and recent events needed a stronger table-first and queue-first structure.

#### Workspaces

- Workspace access logic was correct, but the entry surface needed stronger structure and calmer navigation cues.

## Admin Design Principles

1. Keep primary screens state-first.
2. Prefer tables, KPI strips, queues, and badges over prose.
3. Show only the next useful decision first.
4. Push secondary context into drawers, expanded rows, and detail panels.
5. Use color only for status, risk, or action confirmation.
6. Reuse one interaction pattern for each admin job type.
7. Make filters persistent and obvious.
8. Preserve production workflows while improving their presentation.
9. Keep typography short, controlled, and operational.
10. Make high-risk actions explicit and hard to confuse.

## Admin Design Tokens

### Layout tokens

- Base layout: wide scaffold with strong outer padding.
- Primary vertical rhythm: `CoolSpace.x4` to `CoolSpace.x6`.
- Section separation: one spacing unit, not extra borders plus shadows plus copy.
- Radius: medium to large, consistent, restrained.
- Elevation: minimal; prefer border and surface contrast over shadow stacks.

### Surface tokens

- `operationalSurface`: page-level hero and command surface.
- `cardSurface`: primary data containers.
- `inputSurface`: lower-emphasis interior surfaces.
- `overlaySurface`: confirmation and modal surfaces.

### Admin tone tokens

- `neutral`: passive state
- `info`: active informational state
- `success`: healthy or completed state
- `warning`: caution or backlog state
- `danger`: failure, blocked, or destructive state
- `accent`: scoped emphasis or selected state

These are implemented through `AdminTone` and consumed by status chips, metric cards, and ranked lists.

## Typography Rules

- Use short labels only.
- Use one strong page title.
- Use one concise subtitle only when it adds operational context.
- Keep metric labels one line.
- Keep table headers terse.
- Prefer nouns and state labels over sentences.
- Use larger type mainly for KPI values and page titles.
- Use subdued secondary text for timestamps, IDs, and supporting metadata.

## Spacing Rules

- Use spacing to create order before adding borders or helper copy.
- Keep section padding uniform.
- Avoid nested container stacks unless they create a clear interaction boundary.
- Use tighter spacing inside dense action zones and slightly larger spacing between functional groups.

## Status And Icon Rules

### Status rules

- Every critical state must have one visual tone and one short label.
- Use chips for status, not freeform colored text.
- Avoid inventing new state colors per screen.
- Use uppercase or short title case only where it improves scan speed.

### Icon rules

- Icons must indicate action type, state type, scope, or module.
- Icons should never be purely decorative.
- Use one icon per status/action surface where possible.
- Pair icons with labels for destructive or privilege-related actions.

## Component Library

### Implemented shared admin components

- `AdminPageHeader`
- `AdminMetricStrip`
- `AdminStatusChip`
- `AdminToolbar`
- `AdminSectionCard`
- `AdminDataTableCard`
- `AdminRankList`
- `AdminActivityTile`
- `AdminPanelSurface`

These now provide the baseline system for admin pages in `lib/shared/widgets/admin_workspace_kit.dart`.

### Required operational component set

- KPI cards
- management tables
- search bars
- filter chip rows
- segmented controls
- status badges
- role chips
- bulk action bars
- quick action panels
- activity timeline cards
- audit event expanders
- confirmation modals
- empty states
- loading states
- warning and error states
- side detail panels
- profile detail panels
- permission scope widgets

### Component guidance

#### KPI strip

- Use for immediate inventory, health, and queue counts.
- Limit top strips to 4-6 metrics.
- Put detail metrics in secondary sections, not the top row.

#### Data table

- Use for user lists, role ledgers, issue queues, and release surfaces.
- Support row actions directly in the last column.
- Keep high-signal columns first.
- Move low-frequency detail out of the main row.

#### Toolbar

- Keep search first.
- Keep filters persistent and chip-based.
- Keep major actions grouped to the right or at the end of the row.

#### Activity tile

- Use for audit streams and recent operations.
- Support expandable payload or metadata review.
- Keep the default collapsed state compact.

## Table System Rules

1. Lead with identity or object name.
2. Put state and severity near the front.
3. Put timestamps after the primary operational fields.
4. Keep freeform notes late in the row.
5. Reserve the last column for actions.
6. Use row height that is spacious enough to scan but not oversized.
7. Use horizontal scrolling for wide admin tables instead of collapsing important columns.
8. Use one empty-state sentence only.
9. Make sortable and filterable structure predictable across modules.
10. Use chips inside cells for status, role, and severity.

## Reusable Widget Patterns

### Dashboard pattern

- page header
- top KPI strip
- 2-4 grouped module cards
- direct route to critical operations

### Ledger pattern

- header
- KPI strip
- toolbar
- table
- footer count

### Queue pattern

- KPI strip
- triage table
- severity chips
- direct action entry points

### Timeline pattern

- compact event cards
- status chips
- timestamp meta
- optional payload expander

### Cleanup pattern

- section card
- concise risk copy
- direct destructive action button
- confirmation modal

## Screen Guidance

### Dashboard

- Group modules into priority, oversight, and configuration.
- Keep the top surface focused on route selection, not narration.
- Promote live operations and review queues above lower-frequency settings.

### User management

- Keep inventory as the primary table.
- Surface `Users`, `Admins`, `Mock`, and `MoMo` in top metrics.
- Keep edit actions inline.
- Keep batch cleanup in a secondary section, not in the table itself.

### Admin roles and permissions

- Treat the screen as a role ledger first.
- Surface total assignments, platform grants, bank grants, and bank scopes.
- Keep assign action available in both header and FAB entry points.
- Keep revocation direct but confirmed.

### Operations and moderation

- Put live health and triage first.
- Use tables for release surfaces and open issues.
- Use section cards for sender audits, review backlogs, and recent events.
- Keep severity and health visible through status chips.

### Audit and logs

- Use activity cards with compact metadata.
- Show actor, action, time, and state immediately.
- Hide payload detail behind expansion.

### Analytics

- Separate top-line platform metrics from deeper distributions.
- Use ranked lists for role and event distributions.
- Use secondary KPI strips for count families.

### Workspaces

- Use the page as a clean access switchboard.
- Show platform and bank workspaces as clearly separated cards.
- Make assigned scopes immediately visible.

## Navigation Simplification Guidance

- Keep top-level admin navigation limited to operational modules.
- Group low-frequency configuration routes behind a clear configuration cluster.
- Keep critical surfaces one click away from the admin landing screen.
- Avoid redundant paths to the same management object.
- Use contextual actions inside screens instead of multiplying sidebar entries.

Recommended top-level grouping:

- Dashboard
- Users
- Roles
- Operations
- Audit
- Analytics
- Settings

Secondary scopes should stay in tabs, drawers, or local cards rather than becoming new first-level modules.

## Incremental Rollout Guidance

### Phase 1

- Introduce the shared admin widget kit.
- Migrate high-traffic admin surfaces first.
- Keep existing data providers, routes, and mutations intact.

### Phase 2

- Normalize status chips, table columns, and toolbar behavior across remaining modules.
- Move repeated patterns out of screen-specific files into shared widgets.

### Phase 3

- Add reusable side drawers for user detail, audit payloads, and queue inspection.
- Add bulk action bars for multi-select flows where operationally safe.

### Phase 4

- Standardize empty, loading, success, warning, and error states across the full admin surface.
- Refine keyboard flow and tablet/desktop density rules.

## Implementation Notes For This Repo

The redesign is implemented additively on top of the current Flutter admin structure.

Primary shared system:

- `lib/shared/widgets/admin_workspace_kit.dart`

Refined screens:

- `lib/features/admin/screens/admin_dashboard_screen.dart`
- `lib/features/admin/screens/admin_workspaces_screen.dart`
- `lib/features/admin/screens/manage_users_screen.dart`
- `lib/features/admin/screens/manage_admin_roles_screen.dart`
- `lib/features/admin/screens/audit_log_screen.dart`
- `lib/features/admin/screens/system_analytics_screen.dart`
- `lib/features/admin/screens/operational_dashboard_screen.dart`

Supporting data fix:

- `AdminUsersRepository.fetchUsers()` now selects `momo_number`
- `admin_user_row_normalizer.dart` now normalizes `momo_number`

## Quality Bar

The admin panel should now move toward this standard:

- less text
- more signal
- better hierarchy
- reusable operational widgets
- stronger tables
- clearer status visibility
- calmer navigation
- faster admin decisions
- production-safe incremental rollout
