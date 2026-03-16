# Group Savings And Partner Admin Segregation Review

Date: 2026-03-15

Scope:
- Group savings admin and bank custodian admin
- Rayon Sports admin segregation
- Current admin routing, access control, repository structure, UI/UX surfaces, and backend support

## Executive Summary

The repo already has three important building blocks:

1. A working consumer group-savings product
2. A working but globally gated Rayon admin module
3. Backend ledger and reconciliation primitives that can support partner-level finance workspaces

What it does not have is a true segmented admin product.

Today the app still behaves like this:

- one global `/admin` area for platform operators
- one nested Rayon admin branch that is still entered through the global admin path
- no bank-admin workspace for group savings
- no admin UI for manual payment allocation or ledger review
- no direct route model for partner-scoped admins

That means the requested separation cannot be achieved by adding a few more admin cards.
It requires a deliberate split between:

- platform admin
- bank custodian admin
- Rayon partner admin
- group-level captain/admin tools

The good news is that the backend already contains enough low-level primitives to avoid a rewrite. The missing work is mainly:

- access segmentation
- route architecture
- read models and admin repositories
- dedicated admin UX workspaces
- manual allocation tooling
- export flows for partner and bank ledgers

## Current Implementation Snapshot

### 1. Routing and access

Current admin routes are limited to:

- global admin under `lib/core/router/app_router.dart`
- Rayon admin under `/admin/rayon/*`

Evidence:

- `lib/core/router/app_routes.dart`
- `lib/core/router/app_router.dart`
- `docs/ROUTE_INVENTORY.md`

Important constraints in the current router:

- `resolveAppRedirect()` treats every `/admin` route as global-admin-only
- access is gated by `users.is_admin`
- partner admin metadata is only used for scanner access, not for admin routing

This is the first critical mismatch with the requested product.

### 2. Global admin exists, but it is platform-oriented

The current admin dashboard is a generic control surface for:

- users
- partners
- services
- quick actions
- vehicle types
- app config
- operations
- Rayon Sports

Evidence:

- `lib/features/admin/screens/admin_dashboard_screen.dart`
- `lib/features/admin/repositories/admin_repository.dart`
- `lib/features/admin/providers/admin_providers.dart`

This is suitable for platform operators. It is not suitable as the primary entry point for bank or partner-specific admins.

### 3. Rayon admin is real, but not fully segregated

Rayon already has dedicated admin screens:

- matches
- tickets
- shop
- orders
- members
- initiatives

Evidence:

- `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_orders_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_members_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart`
- `lib/features/partners/rayon/providers/rs_admin_provider.dart`
- `lib/features/partners/repositories/rayon_sports_repository_admin.dart`

What is still missing:

- direct partner-admin entry
- non-global access routing
- finance / settlement workspace
- configurable membership package management
- broader partner-admin abstractions that can scale beyond Rayon

### 4. Group savings exists only as a consumer product

Current group routes are:

- `/groups`
- `/groups/create`
- `/groups/:id`
- `/invite/:code`

Evidence:

- `lib/features/groups/screens/groups_screen.dart`
- `lib/features/groups/screens/create_group_screen.dart`
- `lib/features/groups/screens/group_detail_screen.dart`
- `lib/features/groups/providers/groups_provider.dart`
- `lib/features/groups/repositories/group_repository.dart`

The current group repository supports:

- load my groups
- load a single group
- create group
- join group
- contribute

It does not support:

- list all groups by custodian bank
- list all members across groups
- list all contributions across groups
- bank-level ledger queries
- allocation review queues
- admin exports
- admin summaries

### 5. Group-bank linkage removed from mobile contract

The group model previously carried:
- `bankPartner` as a display string
- `institutionId` as an optional field

These have been removed from the mobile model and the create-group contract to focus on direct collection and to avoid unverified partner labeling.

This is the second critical mismatch.

For bank admin to be reliable, group custody must be attached to a stable partner identifier, not a freeform label.

### 6. Ledger primitives already exist

The backend already supports:

- group payment ledgers
- partner payment ledgers
- payee-linked ledger ownership

Evidence:

- `lib/features/momo/repositories/momo_statement_repository.dart`
- `lib/features/momo/providers/momo_statement_providers.dart`
- `supabase/migrations/20260313234500_payee_ledgers_and_payee_route_allocations.sql`

Useful existing functions:

- `get_group_payment_ledger_entries`
- `get_partner_payment_ledger_entries`
- `can_read_group_payment_ledger`
- `can_read_partner_payment_ledger`

This is reusable for the requested bank admin product.

### 7. Reconciliation and allocation primitives already exist

The SMS parsing and reconciliation pipeline already supports:

- auto-match by payee route
- direct group allocation
- direct partner allocation
- `matched`
- `pending_review`
- `manual_review`

Evidence:

- `lib/features/momo/repositories/momo_payment_sync_repository.dart`
- `supabase/functions/parse-momo-sms/reconciliation.ts`
- `supabase/functions/parse-momo-sms/reconciliation_test.ts`

What is missing is the product layer on top:

- admin queue for unresolved items
- operator assignment flow
- approve/reject/reassign actions
- audit trail UI

### 8. Export support exists, but not for partner-admin ledgers

There is already a strong export implementation for:

- wallet statements
- savings statements

Evidence:

- `lib/features/momo/services/momo_statement_export_service.dart`
- `test/features/momo/services/momo_statement_export_service_test.dart`

But there is no direct export path for:

- group payment ledger admin exports
- partner payment ledger admin exports
- unresolved allocation queues

So export is partially reusable, but not complete for the requested bank admin workflows.

### 9. UI/UX debt hotspots matter here

Existing screen budgets show:

- `group_detail_screen.dart` at 1064 LOC
- `create_group_screen.dart` at 1055 LOC
- `groups_screen.dart` at 836 LOC
- `operational_dashboard_screen.dart` at 579 LOC
- several Rayon admin screens in the review range

Evidence:

- `docs/SCREEN_BUDGETS.md`

This matters because the correct move is not to keep growing those screens.
Admin work must be placed in dedicated workspaces, not mixed into already-dense consumer routes.

## Critical Findings

### P0. Access control is too coarse for segmented admin

Current state:

- frontend only recognizes global admin for `/admin/**`
- backend has partner-admin-aware checks, but frontend does not route on them

Impact:

- bank admins cannot get their own workspace without being made full platform admins
- Rayon partner admins cannot cleanly access their workspace without going through the global admin gate

Evidence:

- `lib/core/router/app_redirects.dart`
- `lib/core/router/app_router.dart`
- `supabase/migrations/20260310220000_rayon_sports_schema_lock.sql`

### P0. Group custody is not modeled strongly enough for bank admin

Current state:

- bank custody is effectively represented by a label in group creation
- `institution_id` is dormant
- no repository surface assumes bank partner ownership of groups

Impact:

- no safe way to scope all groups for a specific bank
- fragile reporting and export logic
- impossible to build reliable bank admin access around string labels

Evidence:

- `lib/features/groups/models/group.dart`
- `lib/features/groups/screens/create_group_screen.dart`
- `lib/features/groups/repositories/group_repository.dart`

### P0. Manual allocation is a backend state, not a usable admin workflow

Current state:

- reconciliation can produce `manual_review`
- there is no admin-facing queue, detail view, or action flow

Impact:

- unallocated or ambiguous payments cannot be resolved in-product
- operations remain backend-only or manual-SQL-driven

Evidence:

- `supabase/functions/parse-momo-sms/reconciliation.ts`
- `lib/features/momo/repositories/momo_payment_sync_repository.dart`

### P1. Global admin, partner admin, and bank admin are mixed conceptually

Current state:

- one admin dashboard contains platform and partner concerns
- profile overflow is the primary admin entry

Impact:

- wrong discoverability
- wrong mental model
- poor least-privilege UX

Evidence:

- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/admin/screens/admin_dashboard_screen.dart`

### P1. Rayon admin is partner-specific in data, but not in architecture

Current state:

- Rayon admin exists
- partner-admin RLS helper exists
- frontend still hardcodes it inside the global admin tree

Impact:

- the current implementation does not generalize to other partner-admin workspaces
- Rayon admin is structurally “special-case admin”, not a reusable partner-admin pattern

Evidence:

- `lib/features/partners/rayon/screens/rs_admin_dashboard_screen.dart`
- `lib/features/partners/repositories/rayon_sports_repository_admin.dart`
- `supabase/migrations/20260310220000_rayon_sports_schema_lock.sql`

### P1. Membership package management is not yet an admin capability

Current state:

- Rayon admin can manage members and points
- membership tiers and benefits are code-defined in the UI
- no admin CRUD exists for membership package definitions, benefits, pricing, or on-sale visibility

Impact:

- the user request for “set up member packages” is only partially met today

Evidence:

- `lib/features/partners/rayon/screens/membership_tiers_screen.dart`
- `lib/features/partners/rayon/models/rs_models.dart`
- absence of a repository/admin screen for configurable tier catalog data

### P2. Naming and ownership are leaking Rayon semantics into generic partner admin logic

Current state:

- generic partner ledger auth is using `rs_is_partner_admin()`

Impact:

- poor domain clarity
- future bank/admin expansion becomes harder to reason about

Evidence:

- `supabase/migrations/20260310220000_rayon_sports_schema_lock.sql`
- `supabase/migrations/20260313234500_payee_ledgers_and_payee_route_allocations.sql`

## Recommended Target Operating Model

The app should move to four admin actors.

| Actor | Scope | Can Access |
|---|---|---|
| Platform Admin | Whole app | Users, partners, services, routes, ops, partner workspace entry |
| Bank Custodian Admin | One bank partner | Group directory, group members, contributions, ledgers, exports, allocation queue |
| Partner Admin (Rayon) | One partner | Matches, tickets, members, packages, shop, orders, initiatives, finance |
| Group Captain / Group Admin | One group | Invite, member moderation, group-local summary, optional lightweight ledger |

Important rule:

- platform admin is not the same thing as partner admin
- partner admin is not the same thing as group admin
- bank custodian admin is not the same thing as platform admin

## Recommended Route Architecture

Do not keep expanding the current hardcoded `/admin/rayon` pattern as the only approach.

Use a segmented admin IA like this:

- `/admin`
  - dynamic workspace launcher based on current user privileges
- `/admin/platform`
  - existing platform admin surfaces
- `/admin/partners/:partnerId`
  - shared partner-admin shell
- `/admin/partners/:partnerId/rayon/*`
  - or keep `/admin/rayon/*` as an alias that resolves to the partner workspace
- `/admin/banks/:partnerId`
  - bank custodian workspace
- `/admin/banks/:partnerId/groups`
  - all custodial groups
- `/admin/banks/:partnerId/groups/:groupId`
  - members, contributions, ledger, history
- `/admin/banks/:partnerId/ledgers`
  - bank-wide posted ledger explorer
- `/admin/banks/:partnerId/allocations`
  - manual review and unresolved payment queue
- `/admin/banks/:partnerId/exports`
  - export presets and history

The global `/admin` screen should stop acting like a flat list of every possible admin page.
It should become a workspace launcher.

## UI/UX Plan

### 1. Keep consumer flows and admin flows separate

Do not place bank-admin tools inside:

- `groups_screen.dart`
- `create_group_screen.dart`
- `group_detail_screen.dart`

Those are already large and consumer-focused.

Instead:

- keep consumer group screens as member/captain surfaces
- create a separate admin shell for operational work

### 2. Create one reusable admin workspace shell

Add a shared shell, for example:

- `PartnerAdminShell`
- or `AdminWorkspaceShell`

It should standardize:

- page title and scope badge
- summary metrics strip
- filter/search row
- tab or section rail
- table/list body
- sticky action area
- export entry point

Rayon can reuse this shell.
Bank admin should definitely use it.

### 3. Bank admin UX should be table-first, not card-first

Bank custodians need operational visibility, not storytelling cards.

Recommended bank workspace sections:

1. Overview
2. Groups
3. Members
4. Contributions
5. Ledgers
6. Allocations
7. Exports

Recommended screen shapes:

- overview: KPI cards + exception queues
- groups: searchable table/list with filters
- group detail: tabbed detail surface
- ledgers: dense but readable table with date/status/target filters
- allocations: split view queue + detail review panel
- exports: preset-driven download panel

### 4. Rayon admin should stay role-focused

Current Rayon admin is directionally correct. The next step is structural alignment, not a redesign.

Recommended Rayon sections:

1. Overview
2. Matches
3. Tickets
4. Membership
5. Shop
6. Orders
7. Initiatives
8. Finance

The missing addition is `Finance`:

- partner ledger
- reconciliation status summary
- pending/manual review queue for Rayon-linked payments

### 5. Separate summary from management

Current admin surfaces often mix:

- overview metrics
- list content
- edit controls
- destructive actions

Recommended rule:

- top = summary
- middle = filters
- bottom = data table/list
- edits happen in drawers or dedicated detail panes

This is especially important for:

- bank ledgers
- allocations
- order management
- ticket management

### 6. Use detail drawers instead of giant bottom sheets for dense admin edits

The current admin pattern relies heavily on modal bottom sheets for CRUD forms.
That works for small edits, but it will not scale for:

- allocation review
- ledger inspection
- multi-field membership package config
- group custody edits

Recommended:

- keep bottom sheets for lightweight create/edit flows
- use full screens or side drawers for multi-section operational edits

## Fullstack Changes Required

### A. Access and identity model

Required updates:

- introduce frontend-visible admin capability model
- distinguish:
  - `is_platform_admin`
  - `partner_admin_ids`
  - `bank_admin_ids`
  - optional `group_admin_ids`
- stop relying on `users.is_admin` alone for all `/admin/**` routing

Recommended implementation:

- keep `users.is_admin` for platform admin
- keep JWT `partner_admin_ids` for partner admin
- add bank admin claims or derive them from a DB-backed admin assignment table
- add a dedicated provider to resolve admin workspaces at runtime

Suggested frontend additions:

- `admin_access_provider.dart`
- `AdminWorkspaceAccess`
- `AdminWorkspaceType { platform, partner, bank, group }`

### B. Data model hardening for group custody

Required updates:

- attach each bank-custodied group to a stable bank partner id
- preserve the display label, but make id-based ownership authoritative

Recommended schema direction:

- `groups.partner_id` or `groups.custodian_partner_id uuid`
- keep `bank_partner` only as legacy/display compatibility if needed
- either remove or activate `institution_id` with a clear contract

Required repository updates:

- add bank-scoped group query APIs
- add group-member and group-contribution admin query APIs

### C. Admin repositories and read models

Do not hang this on the current consumer repositories.

Add dedicated admin repositories:

- `bank_admin_repository.dart`
- `partner_admin_repository.dart`
- `group_admin_repository.dart`

Suggested bank read models:

- `BankAdminOverviewData`
- `BankAdminGroupListItem`
- `BankAdminGroupDetailData`
- `BankAdminContributionRow`
- `BankAdminLedgerRow`
- `BankAdminAllocationReviewItem`
- `BankAdminExportPreset`

Suggested Rayon read models:

- `RayonAdminOverviewData`
- `RayonAdminFinanceData`
- `RayonAdminMembershipCatalogData`

### D. Backend RPCs / queries

The app already has usable ledger RPCs.
What is still needed is admin-grade aggregation and workflow support.

Recommended new RPCs or service methods:

- `get_bank_admin_overview(p_partner_id)`
- `get_bank_custody_groups(p_partner_id, filters...)`
- `get_bank_group_members(p_group_id, filters...)`
- `get_bank_group_contributions(p_group_id, filters...)`
- `get_bank_manual_allocation_queue(p_partner_id, filters...)`
- `resolve_manual_allocation(...)`
- `reject_manual_allocation(...)`
- `reassign_manual_allocation(...)`
- `get_partner_reconciliation_queue(p_partner_id, filters...)`

### E. Manual allocation domain support

Today `momo_reconciliations` can represent unresolved cases, but there is no product-grade review model.

Recommended direction:

- keep `momo_reconciliations` as the source event log
- add admin-facing resolution metadata if needed
- expose enough fields to support:
  - assigned reviewer
  - review reason
  - suggested target
  - final action
  - reviewed timestamp

### F. Export support

Recommended additions to export service:

- `buildGroupPaymentLedgerExport(...)`
- `buildPartnerPaymentLedgerExport(...)`
- `buildAllocationQueueExport(...)`

Reuse:

- current Excel/PDF/CSV infrastructure
- current download service

Do not force bank admin exports through the consumer savings statement format.
They need different columns.

### G. Rayon membership package management

If Rayon admin must manage member packages, the current code-defined tier system is not enough.

Recommended options:

Option 1:
- keep tier progression static
- only manage benefits copy and visibility from admin

Option 2:
- create `rs_membership_packages`
- create admin CRUD for package pricing, benefits, and active state
- map fan membership acquisition and presentation onto that catalog

If the requirement is real package setup and pricing control, Option 2 is the correct path.

## Proposed Frontend Workspaces

### Bank Custodian Admin

#### Overview

Show:

- total groups under custody
- total active members
- confirmed contributions this month
- posted ledger volume this month
- pending/manual review counts
- export shortcuts

#### Groups

Show:

- searchable list/table of all groups under this bank
- type
- visibility
- created by
- member count
- contribution total
- latest activity
- status / exceptions

Actions:

- open detail
- export group ledger
- open unresolved items for that group

#### Group Detail

Tabs:

- summary
- members
- contributions
- ledger
- exceptions

This should not reuse the consumer `group_detail_screen.dart`.
It needs an admin detail screen.

#### Ledgers

Show:

- date
- payer
- amount
- currency
- label
- target table
- target record
- external reference
- filters

Actions:

- export current view
- open target entity
- copy reference

#### Allocations

Show:

- unresolved queue
- reason
- suggested match
- payer
- amount
- route
- timestamp

Actions:

- confirm match
- reassign
- reject
- leave internal note

### Rayon Admin

Keep the existing modules, but align them under a role-separated shell.

Add:

- overview summary page
- finance page
- optional membership package page

The current CRUD screens are a valid base and should be refactored, not replaced.

## Recommended Implementation Phases

### Phase 0. Role and route foundation

Deliverables:

- admin workspace access provider
- route segregation plan
- global admin vs partner admin vs bank admin guard logic

Files likely impacted:

- `lib/core/router/app_router.dart`
- `lib/core/router/app_redirects.dart`
- new admin access provider files

### Phase 1. Data-model hardening for group custody

Deliverables:

- stable bank partner linkage on groups
- migration and backfill
- repository query updates

Files likely impacted:

- `supabase/migrations/*`
- `lib/features/groups/models/group.dart`
- `lib/features/groups/repositories/group_repository.dart`

### Phase 2. Bank admin backend and repository layer

Deliverables:

- bank admin repository
- overview/read models
- allocation queue queries
- ledger export support

Files likely impacted:

- new bank admin repository/provider files
- `lib/features/momo/repositories/momo_statement_repository.dart`
- `lib/features/momo/services/momo_statement_export_service.dart`
- Supabase RPCs and functions

### Phase 3. Bank admin UX

Deliverables:

- bank admin workspace shell
- overview
- groups
- group detail
- ledgers
- allocations
- exports

### Phase 4. Rayon admin segregation cleanup

Deliverables:

- make Rayon admin directly accessible to partner admins
- unify admin shell patterns
- add finance workspace
- add membership package management if required

### Phase 5. Test and hardening

Deliverables:

- route access tests
- repository tests
- widget tests for bank admin workspaces
- export tests
- reconciliation workflow tests

## Testing Requirements

Minimum automated coverage should include:

- router access matrix by admin type
- bank admin cannot open platform admin screens
- Rayon admin cannot open unrelated bank admin screens
- bank admin can load only their partner-linked groups
- unresolved allocations appear correctly
- resolve/reassign/reject actions update state correctly
- ledger export produces valid Excel/PDF/CSV output
- existing Rayon admin flows remain intact

## Recommended Order Of Work

The safest order is:

1. access model
2. group custody model
3. bank admin repository layer
4. bank admin overview and groups list
5. bank admin group detail
6. bank admin ledgers and exports
7. bank admin allocations
8. Rayon admin route segregation
9. Rayon finance and membership-package gaps

## Bottom Line

The requested product is feasible with the current repo, but it is not a “small admin UI add-on”.

The current codebase already proves:

- consumer group savings works
- Rayon admin CRUD works
- payee ledgers exist
- reconciliation states exist
- export infrastructure exists

The missing product is the segmentation layer.

The critical path is:

- separate admin identity by scope
- attach groups to real custodial partner ids
- surface ledgers and manual-review queues as first-class admin workspaces
- stop routing all admin work through the same global `/admin` gate

Once that is in place, the bank custodian admin and the Rayon partner admin can both preserve current functionality while operating in separate, cleaner, role-appropriate UI/UX environments.
