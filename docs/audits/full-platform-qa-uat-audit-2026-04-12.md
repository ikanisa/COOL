# Full Platform QA/UAT Audit

Date: 2026-04-12

## Scope

- Flutter mobile app
- Flutter admin surfaces
- React admin panel in `apps/cool-admin`
- Supabase migrations, RPCs, and Edge Functions
- User journeys requested for validation:
  - WhatsApp login and OTP
  - Admin add new admin
  - Admin create new group
  - User create new group
  - User join group
  - User contribute
  - SMS access and SMS ingestion
  - Transaction allocation to correct user/group
  - Balance updates
  - Duplicate detection
  - Admin manual allocation
  - Admin create new loan

## What Was Executed

- Flutter static analysis via Dart MCP: no analyzer errors.
- Supabase migration validation script: passed for 176 migration files.
- React admin panel:
  - `npm run lint`: passed
  - `npm run build`: passed with large bundle warning
- Flutter test buckets:
  - Passed: `test/features/admin`, `test/features/auth`, `test/features/groups`, `test/features/home`
  - Passed: `test/features/momo`, `test/features/profile`, `test/accessibility`, `test/integration_smoke`
  - Passed: selected shared widget tests
  - Failed: `test/core`, `test/docs`, `test/models`, `test/providers`
  - Failed: `test/features/biopay/biopay_screen_goldens_test.dart`
- Deno tests:
  - Passed when isolated: `parse-momo-sms/reconciliation_test.ts`, `parse-momo-sms/ai_parser_test.ts`, `sms-ingest/rules_test.ts`, `send-otp/index_test.ts`, `verify-otp/index_test.ts`
  - Failed/blocked: `_shared/auth_test.ts` compile contract drift, `verify_otp_helpers_test.ts` secret dependency
- Browser UAT against local admin panel at `http://localhost:3002`
  - Reached WhatsApp number and OTP screens
  - `send-otp` returned success
  - `verify-otp` rejected documented review code with `Invalid OTP code`
- Android device-backed run
  - `scripts/run_device_integration.sh` for staging remained stuck loading `integration_test/critical_journeys_test.dart`
  - Device inspection could not find installed package `app.cool.mobile.staging`

## Findings

### Critical

1. Review OTP bypass is not working end-to-end.
   - Repo docs say reviewers should use phone `+250788767816` and code `123456`.
   - Browser probe recorded `send-otp` success followed by `verify-otp` HTTP 400 with `Invalid OTP code`.
   - Evidence:
     - [play_review_access.md](/Volumes/PRO-G40/COOL/docs/play_review_access.md:15)
     - [admin_otp_probe.json](/Volumes/PRO-G40/COOL/output/playwright/admin_otp_probe.json:1)
   - Impact:
     - Blocks admin-panel UAT past login.
     - Blocks Play-review access path described in docs.

2. Device-backed mobile UAT is not release-ready.
   - The staging device run hangs on the only wired device integration script.
   - The attached Android device does not currently have `app.cool.mobile.staging` installed, so SMS permission and inbox-sync UAT cannot be completed on-device.
   - Evidence:
     - [critical_journeys_test.dart](/Volumes/PRO-G40/COOL/integration_test/critical_journeys_test.dart:14)
   - Impact:
     - Real-device validation for mobile auth, permissions, SMS ingestion, and payment confirmation is not complete.

3. The React admin panel does not implement several required admin journeys.
   - `New Loan` exists as a button but has no handler or route.
   - Loan row actions are display-only menu items.
   - Group row actions are display-only menu items.
   - Contribution row actions are display-only menu items.
   - Roles page supports revoke only; there is no assign-admin flow in the React admin panel.
   - Evidence:
     - [Loans.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/Loans.tsx:190)
     - [Loans.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/Loans.tsx:277)
     - [Groups.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/Groups.tsx:163)
     - [Transactions.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/Transactions.tsx:174)
     - [Settings.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/Settings.tsx:125)
   - Impact:
     - Requested flows such as admin add new admin, admin manage members, admin allocate transactions manually, and admin create new loan are not fully testable in this surface because they are not fully implemented there.

### High

4. React admin user creation bypasses the newer RBAC model and directly writes `public.users.is_admin`.
   - The page inserts directly into `users` and toggles `is_admin` itself.
   - It also exposes `Malta` as a country option even though the codebase is otherwise Rwanda-scoped.
   - Evidence:
     - [CreateUser.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/CreateUser.tsx:39)
     - [CreateUser.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/CreateUser.tsx:83)
   - Impact:
     - Can drift from `admin_role_assignments`-based access control and regional invariants.

5. Release-governance checks are currently red.
   - Missing migrations in `supabase/migrations/migration_manifest.yaml`:
     - `20260412131500_fix_admin_panel_schema_gaps.sql`
     - `20260412135400_standardize_admin_checks.sql`
     - `20260412140700_fix_savings_groups_detail_columns.sql`
     - `20260412142200_create_loans_module.sql`
   - `docs/SCREEN_BUDGETS.md` is out of sync with governance tests.
   - Impact:
     - Fails CI-quality gates and weakens release traceability.

6. The new loans module is only partially operationalized.
   - Backend schema and summary RPC exist.
   - React admin panel lists loans but does not create or manage them.
   - Migration seeds demo loans inside the schema migration.
   - Evidence:
     - [Loans.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/Loans.tsx:63)
     - [Loans.tsx](/Volumes/PRO-G40/COOL/apps/cool-admin/src/pages/Loans.tsx:190)
   - Impact:
     - “Admin create new loan” is not complete as an end-to-end product journey.

### Medium

7. Mobile admin savings operations are implemented but under-tested.
   - Flutter admin has working flows for add member, remove member, allocate contribution, and close group.
   - Existing admin tests cover admin-role management, but there are no dedicated tests for the savings detail mutation flows.
   - Evidence:
     - [admin_savings_detail_screen.dart](/Volumes/PRO-G40/COOL/lib/features/admin/screens/admin_savings_detail_screen.dart:616)
     - [manage_admin_roles_screen.dart](/Volumes/PRO-G40/COOL/lib/features/admin/screens/manage_admin_roles_screen.dart:27)
     - [manage_admin_roles_screen_test.dart](/Volumes/PRO-G40/COOL/test/features/admin/manage_admin_roles_screen_test.dart:98)
   - Impact:
     - Mobile admin surface is materially stronger than the React admin panel, but still lacks mutation-path regression coverage.

8. User group creation exists and is gated behind verified WhatsApp auth, but test coverage is shallow.
   - Flutter `GroupCreateScreen` validates and calls `createGroup`.
   - Existing widget test only checks rendering/state changes; it does not execute successful submission.
   - Evidence:
     - [group_create_screen.dart](/Volumes/PRO-G40/COOL/lib/features/groups/screens/group_create_screen.dart:76)
     - [group_create_screen_test.dart](/Volumes/PRO-G40/COOL/test/features/groups/group_create_screen_test.dart)
   - Impact:
     - “User create new group” is implemented, but not strongly proven by automated UAT.

9. SMS inbox sync test is real, but self-skips unless `READ_SMS` is granted.
   - The integration test intentionally exits when SMS permission is missing.
   - Evidence:
     - [momo_sms_inbox_sync_test.dart](/Volumes/PRO-G40/COOL/integration_test/momo_sms_inbox_sync_test.dart:55)
   - Impact:
     - A green integration run is not guaranteed to mean SMS ingestion actually ran on-device.

10. Edge-function tests depend on secrets or shared stub shape that are not fully codified in the test harness.
   - `_shared/auth_test.ts` expects `rpc` on the admin client stub.
   - `security.ts` hard-fails when `OTP_CODE_HASH_SECRET` and `AUTH_PHONE_PASSWORD_SECRET` are missing.
   - Evidence:
     - [auth_test.ts](/Volumes/PRO-G40/COOL/supabase/functions/_shared/auth_test.ts:120)
     - [security.ts](/Volumes/PRO-G40/COOL/supabase/functions/_shared/security.ts:3)
   - Impact:
     - Broad Deno test runs can fail for harness/config reasons unrelated to production behavior.

11. React admin panel appears to have no project-owned automated tests.
   - Search only surfaced test files from `node_modules`.
   - Impact:
     - The admin panel’s biggest gaps are not protected by local regression coverage.

## Coverage Summary By Requested Journey

- Admin add new admin:
  - Flutter admin: implemented and widget-tested.
  - React admin panel: revoke-only, not fully implemented.
- Admin create new group:
  - React admin panel: implemented via `admin_create_savings_group`.
  - Not browser-UATed past auth because OTP blocker prevented login.
- User create new group:
  - Flutter: implemented, auth-gated, limited widget coverage.
- User join group:
  - Flutter: implemented via public join and invite join; not fully device-UATed in this pass.
- User contribute:
  - Backend/group allocation plumbing exists; React contribution actions are incomplete.
- WhatsApp login and OTP:
  - Mobile service/provider tests pass.
  - Admin-panel real login UAT currently fails on review bypass.
- SMS access and ingestion:
  - Parsing and ingestion rules are tested.
  - Real-device inbox-sync UAT is blocked by build/install/permission readiness.
- Transaction allocation to correct user/group:
  - Backend allocation RPCs and parser reconciliation tests exist and pass.
  - React admin panel does not expose the full allocation workflow.
- Balance update:
  - Loan repayment trigger and contribution summaries exist in schema, but not fully UATed across surfaces.
- Duplicate detection:
  - SMS duplicate handling and dedupe counters are present and covered in MoMo tests.
- Admin allocate transaction manually:
  - Backend RPCs exist.
  - Flutter admin/manual-review surfaces exist.
  - React admin panel does not provide the requested full manual allocation workflow.
- Admin create new loan:
  - Not complete end-to-end.

## Recommended Next Steps

1. Fix the review OTP bypass immediately and re-validate the documented reviewer credentials in both mobile and admin surfaces.
2. Unstick the staging Android device build/install path, then run:
   - `integration_test/momo_sms_inbox_sync_test.dart`
   - the full WhatsApp OTP flow on-device
   - group create/join/contribute flows on-device
3. Decide which admin surface is authoritative:
   - Flutter admin already contains more real operational workflows.
   - React admin panel currently has several placeholder actions and missing mutation flows.
4. Repair release-gate drift:
   - update `migration_manifest.yaml`
   - sync `docs/SCREEN_BUDGETS.md`
   - fix `_shared/auth_test.ts`
   - provide deterministic test secrets/mocks for OTP/security helpers.
5. Add automated coverage for:
   - React admin pages
   - Flutter admin savings detail mutations
   - user create/join/contribute happy paths
   - loan creation and payment management flows
