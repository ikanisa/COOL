# Web UI Production Audit

Date: 2026-05-01

Scope inspected: `apps/admin`, `apps/website`, `apps/pwa`, `packages/design-system`,
`packages/shared-utils`, shared admin API clients, route guards, admin tables,
public website CSS, build configuration, and frontend safety scripts.

## Surface Inventory

- `apps/admin`: active React/Vite operational admin panel.
- `apps/website`: static public website with dedicated CSS tokens and legal pages.
- `apps/pwa`: placeholder Wrangler boundary; the repo currently does not contain
  an active React PWA user app here.
- Venue dashboard, agent admin console, and dedicated operational consoles are
  not separate web apps in the current source tree; admin routes cover some
  platform, finance, BioPay, health, audit, and role workflows.

## Findings

P1 fixed:

- Settings showed raw app configuration values in the browser, including keys
  that can contain tokens, service-role credentials, webhook secrets, or API
  keys.
- Admin role revocation was a destructive action without an explicit
  confirmation step.
- The Settings route only required `manage_config`, but the page exposed role
  revocation; UI permissions were not aligned with `manage_roles`.
- Health dashboard contained hardcoded status cards for edge function count and
  SMS activity, violating the no-fake-metrics rule.
- Admin entry chunk exceeded the configured bundle budget.

P2 fixed in follow-up:

- Added a shared admin data-table controller and visual controls for
  search/filter/sort/pagination/export state consistency.
- Migrated Users, Members, Loans, Contributions, and Ledger tables to the shared
  table state and controls.
- Added a product-owned web surface registry so venue manager, agent console,
  promotions approval, and user PWA gaps are explicit fail-closed scope instead
  of fake production UI.
- Added activation contracts for the missing venue, agent, promotions, and user
  PWA surfaces so backend ownership and audit requirements are explicit before
  any UI is created.
- Added a website reduced-motion and visual-noise pass for hero glows, animated
  particles, shimmer, hover tilt, and decorative effects.

P2 remaining:

- Dedicated venue manager, agent admin, promotions approval, and user PWA apps
  are still intentionally absent until their activation contracts are satisfied.
- Browser smoke coverage should expand beyond Users, Settings, Health, and Audit
  Log as new critical admin pages are added.

## Changes Made

- Added `ConfirmDialog` for reusable destructive-action confirmation.
- Added config-value masking utilities and Deno coverage for sensitive keys.
- Refactored Settings tabs to render only for matching capabilities and to avoid
  querying hidden configuration/role data.
- Masked sensitive app-config values and added search states to settings tables.
- Replaced the disabled partner Edit button with a read-only state.
- Refactored Health cards to derive all status from operational health events.
- Added health event search and explicit latest-record counts.
- Lazy-loaded auth screens and split icons/notifications into manual chunks so
  the admin entry bundle stays below budget.

## Verification

Passed:

- `npm run lint` in `apps/admin`
- `deno test apps/admin/scripts/frontend-ui-safety-test.ts`
- `deno test apps/admin/scripts/admin-search-filter-test.ts`
- `npm run build` in `apps/admin`
- `npm run check:bundle` in `apps/admin`
- `npm run build` in `apps/website`
- `git diff --check`

## Next Phase

- Add browser-level smoke tests for Settings, Health, Users, and Audit Log.
- Replace remaining page-local loading/error/empty markup with shared state
  components.
- Define backend contracts and release ownership before creating any new venue
  manager, agent admin, promotions, or PWA web apps.
