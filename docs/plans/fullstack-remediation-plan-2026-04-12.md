# Fullstack Remediation Plan

Date: 2026-04-12

Related audit: [docs/audits/full-platform-qa-uat-audit-2026-04-12.md](../audits/full-platform-qa-uat-audit-2026-04-12.md)

## Goal

Close all audit findings and reach a state where the following journeys are fully implemented, testable, and releasable across the Flutter mobile app, Flutter admin surfaces, React admin panel, Supabase backend, and CI/release process:

- WhatsApp login and OTP
- Admin add new admin
- Admin create new group
- User create new group
- User join group
- User contribute
- SMS permission and ingestion
- Allocation of transactions to the correct user and group
- Balance updates
- Duplicate detection
- Admin manual transaction allocation
- Admin create new loan

## Delivery Principles

1. Privileged writes must move through server-owned contracts.
   - No client UI should write privileged columns such as `users.is_admin` directly.
   - Admin role changes, loan creation, manual allocations, and operational mutations should be exposed as RPCs or Edge Functions and consumed by both admin surfaces.

2. One authoritative mutate surface at a time.
   - Short term: Flutter admin remains the trusted mutate surface because it already implements more operational flows.
   - React admin panel is allowed to stay read-only for any module that has not reached parity yet.
   - Once React admin parity is complete and tested, the product can decide whether to keep both mutate surfaces or retire one.

3. No write-heavy UAT on ambiguous environments.
   - The current `.env` points staging and production to the same Supabase project.
   - A real staging backend must exist before repeated mutation UAT is resumed.

4. Every bug fix must land with an executable regression check.
   - Backend changes need Deno tests.
   - Flutter changes need widget/integration coverage.
   - React admin changes need browser automation and component tests.

## Workstream 0: Environment Isolation and Safe UAT Baseline

### Objective

Create a safe non-production path for full mutation UAT and stop relying on a staging flavor that points to production.

### Changes

- Provision a dedicated staging Supabase project and update:
  - repo root `.env`
  - mobile flavor resolution
  - `apps/admin/.env`
  - any deployment/run scripts that currently resolve staging and production to the same backend
- Add a boot-time environment check that logs the resolved project ref for:
  - Flutter app
  - React admin panel
  - device integration scripts
- Add a CI guard that fails if staging and production refs match in checked-in env templates or deployment config.

### Files/Surfaces

- `.env`
- `apps/admin/.env`
- `scripts/lib/_backend_env.sh`
- `scripts/qa/run_device_integration.sh`
- any app bootstrap/config file that resolves Supabase URLs at runtime

### Acceptance Criteria

- Staging and production resolve to different Supabase project refs.
- Staging mobile flavor installs and runs without mutating production data.
- Admin UAT can be executed on staging without ambiguity.

## Workstream 1: WhatsApp OTP and Review Access

### Objective

Restore a reliable end-to-end OTP path for both normal users and review/test users.

### Problems to Fix

- Review-bypass docs say the configured phone/code should work, but real verification fails.
- Review-bypass logic is duplicated in `send-otp` and `verify-otp`.
- OTP/security tests require secrets that are not consistently bootstrapped.
- `VITE_DEV_AUTH_BYPASS` exists in admin env examples but is not implemented in the React codebase.

### Changes

#### Backend

- Replace duplicated review-bypass logic with one shared helper used by both:
  - `supabase/functions/send-otp/index.ts`
  - `supabase/functions/verify-otp/verify_otp_helpers.ts`
- Add a deterministic end-to-end review OTP test that covers:
  - matching configured review phone
  - `send-otp` storing the expected hash
  - `verify-otp` accepting the configured code
  - session creation
- Add structured operational logging for:
  - review bypass used
  - review bypass rejected
  - invalid review secret configuration
  - secret-missing test conditions
- Decide on one development-only admin-login strategy:
  - either implement `VITE_DEV_AUTH_BYPASS` properly for local-only environments
  - or remove it from docs and env examples

#### Mobile and React admin

- Add a shared test fixture for the review phone/code path in:
  - Flutter OTP service/provider tests
  - React browser auth tests
- Improve error surfaces so failed review bypass clearly distinguishes:
  - bad code
  - rate limit
  - secret misconfiguration
  - session establishment failure

#### Test Harness

- Add a standard Deno test env bootstrap for:
  - `OTP_CODE_HASH_SECRET`
  - `AUTH_PHONE_PASSWORD_SECRET`
  - `OTP_TEST_PHONE`
  - `OTP_TEST_CODE`
- Fix `_shared/auth_test.ts` stubs so they satisfy the current `AdminClientLike` contract including `rpc`.

### Files/Surfaces

- `supabase/functions/send-otp/index.ts`
- `supabase/functions/verify-otp/verify_otp_helpers.ts`
- `supabase/functions/_shared/security.ts`
- `supabase/functions/_shared/auth_test.ts`
- `supabase/functions/send-otp/index_test.ts`
- `supabase/functions/verify-otp/index_test.ts`
- `supabase/functions/verify-otp/verify_otp_helpers_test.ts`
- `apps/admin/src/pages/auth/Login.tsx`
- `apps/admin/src/pages/auth/WhatsAppNumber.tsx`
- `apps/admin/src/pages/auth/WhatsAppOTP.tsx`
- `test/core/services/whatsapp_otp_service_test.dart`
- `test/features/auth/whatsapp_otp_provider_test.dart`
- `docs/play_review_access.md`

### Acceptance Criteria

- Documented review credentials work from both mobile and React admin against staging.
- OTP happy path and review-bypass path are both covered by automated tests.
- Deno OTP/security tests run green in CI without manual secret setup.

## Workstream 2: Device Build, Install, and Real-Mobile UAT Harness

### Objective

Make real-device Flutter UAT predictable and split it into meaningful suites instead of one shallow or hanging test target.

### Problems to Fix

- `scripts/qa/run_device_integration.sh` only points at `integration_test/critical_journeys_test.dart`.
- That target currently exercises only shallow BioPay/deep-link checks.
- The attached Android device does not currently end up with `app.cool.mobile.staging` installed during the run.
- SMS inbox sync can self-skip when `READ_SMS` is not granted, masking coverage gaps.

### Changes

#### Scripts

- Replace the current single-target device runner with a preflighted runner that:
  - verifies device presence
  - builds the selected flavor
  - confirms APK install success
  - confirms package presence via `adb shell pm list packages`
  - captures screenshots/logcat on failure
  - runs named suites instead of one default test file
- Add separate scripts or flags for:
  - auth review flow
  - group core journeys
  - MoMo inbox sync
  - admin savings journeys

#### Integration Tests

- Keep `critical_journeys_test.dart` as a smoke test only.
- Add dedicated device integration suites:
  - `integration_test/auth_review_flow_test.dart`
  - `integration_test/group_core_journeys_test.dart`
  - `integration_test/momo_sms_inbox_sync_test.dart`
  - `integration_test/admin_savings_flow_test.dart`
- Ensure SMS tests explicitly fail when permission is expected but unavailable in the dedicated device lane.

#### Runtime Permission Handling

- Add a deterministic preflight for `READ_SMS`:
  - check current permission state
  - fail with a clear reason in device UAT lanes that require SMS
  - optionally automate granting permission on test devices where policy allows

### Files/Surfaces

- `scripts/qa/run_device_integration.sh`
- `integration_test/critical_journeys_test.dart`
- `integration_test/momo_sms_inbox_sync_test.dart`
- new targeted device integration files
- Android install/build scripts under `android/`

### Acceptance Criteria

- Staging APK installs consistently on the target device.
- Device runner fails fast when install or package resolution fails.
- Mobile UAT suite includes real auth, group, contribution, and SMS journeys.

## Workstream 3: React Admin Panel Contract Hardening and Parity

### Objective

Convert the React admin panel from a mostly read-only console with placeholder actions into a supported operational surface.

### Problems to Fix

- Missing assign-admin flow
- Direct `users.is_admin` write from the client
- Placeholder group, transaction, and loan actions
- No project-owned automated tests
- Single large JS bundle

### Changes

#### Admin access and user management

- Replace direct `users` insert in `CreateUser.tsx` with a backend-owned contract.
- Introduce a new admin-safe RPC or Edge Function:
  - `admin_create_user(...)`
  - responsibilities:
    - normalize and validate phone/country
    - create or repair auth identity when required
    - create/update `public.users`
    - optionally assign an admin role using `assign_admin_role`
    - emit audit log entries
- Remove the direct `isAdmin` checkbox write from the client.
- Move admin grants to an explicit assign-role flow using existing RBAC RPCs:
  - `assign_admin_role`
  - `revoke_admin_role`

#### Groups

- Add route `/groups/:groupId`.
- Implement detail view and actions using existing savings-group contracts:
  - `admin_get_savings_groups_detail`
  - `admin_update_savings_group`
  - `admin_bulk_add_group_members`
  - `admin_allocate_savings_contribution`
- Wire existing dropdown actions to:
  - view details
  - edit group
  - manage members
  - close group

#### Transactions and manual review

- Add transaction detail surface and action handlers.
- Split two concepts clearly:
  - confirmed contributions ledger
  - manual-review / unresolved SMS allocations
- Reuse existing backend contracts for manual review queue and rejection:
  - `get_momo_sms_manual_review_queue`
  - `admin_reject_momo_sms_manual_review`
  - `admin_reject_momo_sms_manual_review_batch`
- Add savings-group allocation UI using:
  - `allocate_transaction_to_member`
  - `unallocate_transaction`
- Add bank/manual allocation UI for custodial flows using:
  - `bank_allocate_manual_review_allocation`

#### Tests and performance

- Add React test stack:
  - `vitest`
  - `@testing-library/react`
  - browser E2E via Playwright
- Add route-level lazy loading and manual chunking for heavy modules such as charts, tables, and analytics pages.
- Add bundle budget check for the admin panel.

### Files/Surfaces

- `apps/admin/src/pages/CreateUser.tsx`
- `apps/admin/src/pages/Settings.tsx`
- `apps/admin/src/pages/Groups.tsx`
- `apps/admin/src/pages/Transactions.tsx`
- admin routes/router configuration
- new admin detail pages and test files
- `apps/admin/package.json`

### Acceptance Criteria

- React admin can assign and revoke admin roles through supported RBAC RPCs.
- React admin no longer writes privileged fields directly.
- Group detail/member/allocation actions are functional, not placeholders.
- Transaction/manual-review actions are functional and audited.
- Admin bundle size is reduced via route splitting and budgeted in CI.

## Workstream 4: Flutter Admin Savings and Operations Coverage

### Objective

Keep the stronger Flutter admin surface production-safe by adding the missing regression coverage around mutation flows.

### Changes

- Add widget and repository tests for:
  - add savings-group member
  - remove savings-group member
  - allocate savings contribution
  - close savings group
- Add manual-review tests around admin operational dashboards and MoMo review closures.
- Add test doubles for the repository methods already implemented in:
  - `AdminSavingsRepository`
  - `AdminMomoOpsRepository`

### Files/Surfaces

- `lib/features/admin/screens/admin_savings_detail_screen.dart`
- `lib/features/admin/repositories/admin_savings_repository.dart`
- `lib/features/admin/repositories/admin_momo_ops_repository.dart`
- new tests under `test/features/admin/`

### Acceptance Criteria

- Flutter admin mutation flows are all covered by automated tests.
- A regression in group member management or manual allocation causes CI failure.

## Workstream 5: User Group Journeys and Contribution Flows

### Objective

Turn the implemented Flutter group flows into fully proven user journeys.

### Changes

- Add happy-path tests for:
  - verified user creates a savings group
  - user joins a public group
  - user joins via invite
  - user contributes
  - user sees updated statements/ledger status
- Add negative-path coverage for:
  - unverified user blocked by WhatsApp gate
  - invalid MoMo route
  - duplicate or already-member join attempts

### Files/Surfaces

- `lib/features/groups/screens/group_create_screen.dart`
- `lib/features/groups/screens/groups_screen.dart`
- `lib/features/groups/screens/group_detail_screen.dart`
- `lib/features/groups/repositories/group_repository.dart`
- tests under `test/features/groups/`
- device tests under `integration_test/`

### Acceptance Criteria

- Requested user flows are proven in automation and device UAT.
- Join/create/contribute regressions are caught before release.

## Workstream 6: Loans Module Completion

### Objective

Finish the loans domain so “admin create new loan” and “record repayment / update balances” are real product journeys.

### Problems to Fix

- Current loans migration only provides schema, triggers, RLS, and a summary RPC.
- No create-loan, loan-detail, repayment, or status-update contract exists.
- Seed/demo data lives inside the schema migration.
- React admin loans page is list-only.

### Changes

#### Database and RPCs

- Create a follow-up migration that:
  - removes non-essential demo seeding from the schema path
  - moves any demo data to a non-prod seed path
  - adds write/read RPCs:
    - `admin_create_loan`
    - `admin_get_loan_detail`
    - `admin_record_loan_repayment`
    - `admin_mark_loan_status`
    - optionally `admin_list_loan_repayments`
- Add audit logging around loan creation, repayment, and status transitions.
- Revisit member-read RLS assumptions and ensure `member_id` identity mapping is valid for real users.

#### UI

- React admin:
  - add `New Loan` route and form
  - add loan detail page
  - add repayment modal/page
  - wire existing actions: view, record payment, edit, mark defaulted
- Flutter admin:
  - if loans are meant to exist there too, add parity read/write flows or clearly mark React admin as the sole loan workspace

#### Tests

- Add backend tests for repayment trigger and status transitions.
- Add UI tests for create-loan and record-payment flows.

### Files/Surfaces

- `supabase/migrations/20260412142200_create_loans_module.sql`
- new loan follow-up migration(s)
- `apps/admin/src/pages/Loans.tsx`
- new loan pages/components/tests

### Acceptance Criteria

- Admin can create a loan, view it, record repayment, and see balance/status update correctly.
- Loan write paths are audited and tested.
- Demo seed data is not mixed into production schema rollout.

## Workstream 7: CI, Governance, and Release Gates

### Objective

Make the release pipeline reflect actual product readiness instead of drifting docs and ad hoc local checks.

### Changes

- Update `supabase/migrations/migration_manifest.yaml` for all missing migrations.
- Sync `docs/SCREEN_BUDGETS.md` with current tests or update the tests to the right source of truth.
- Add a Deno test runner in CI that exports required test secrets.
- Add React admin test jobs.
- Promote the device/UAT scripts into explicit CI/release steps where feasible.
- Add a UAT checklist that includes:
  - auth review login
  - Android SMS permission
  - group create/join/contribute
  - manual allocation
  - loan creation and repayment

### Acceptance Criteria

- Governance/doc tests pass.
- Deno/Flutter/admin-panel test jobs are deterministic.
- Release sign-off uses one written UAT matrix instead of tribal knowledge.

## Workstream 8: Observability and Performance

### Objective

Improve diagnosability of auth/SMS failures and reduce admin runtime overhead.

### Changes

- Add operational health events for:
  - OTP review-bypass usage and mismatch
  - OTP secret misconfiguration
  - device UAT install failure
  - SMS ingestion permission missing
  - manual-allocation failures
- Add admin panel bundle budgets and route-level code splitting.
- Add dashboards or queries for:
  - OTP failures by reason
  - SMS duplicate counts
  - manual-review queue volume
  - loan write errors

### Acceptance Criteria

- Failures are diagnosable without reproducing them locally.
- Admin panel initial bundle is materially smaller and budgeted.

## Execution Order

### Phase 1: Release Blockers

- Workstream 0
- Workstream 1
- Workstream 2
- minimum slice of Workstream 7 needed to make tests green again

### Phase 2: Admin Safety and Core Parity

- Workstream 3
- Workstream 4
- Workstream 5

### Phase 3: Loans and Operational Depth

- Workstream 6
- remaining Workstream 3 manual-review and transaction detail work

### Phase 4: Hardening

- remaining Workstream 7
- Workstream 8

## Exit Criteria

The remediation is complete when all of the following are true:

- Review OTP credentials work on staging from both mobile and React admin.
- Staging and production are isolated.
- Device-backed mobile suites run and complete on a real Android device.
- React admin has no placeholder mutate actions for supported modules.
- Flutter admin mutation flows are regression-tested.
- User create/join/contribute flows are automated and device-UATed.
- Loan create/detail/repayment flows are implemented end to end.
- Migration manifest, docs, Deno tests, Flutter tests, and admin tests are all green.
- The UAT checklist can be executed without touching production data.
