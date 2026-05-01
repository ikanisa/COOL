# Supabase Backend Production Audit - 2026-05-01

## Scope Inspected

- `supabase/migrations`: schema, RLS, policies, functions, triggers, indexes, seeds, and cleanup migrations.
- `supabase/functions`: Edge Function auth, input validation, CORS, service-role use, App Check gates, and shared security helpers.
- `supabase/tests` and `test/docs`: migration/static verification coverage.
- Runtime/admin config consumers in `lib/core/config`, `lib/features/admin`, and `apps/admin/src/lib/api`.

## Entity Map

- Identity and admin: `profiles`, `admin_role_assignments`, `admin_sessions`, `admin_browser_events`.
- Content/config: `partner_services`, `supported_countries`, `quick_actions`, `home_banners`, `supported_languages`, `app_config`.
- Groups/savings/payments: `groups`, `group_members`, `group_contributions`, `group_transactions`, `group_messages`, `group_invites`, `bank_payee_accounts`, `payee_ledger_entries`, `momo_*`.
- BioPay: `biopay_profiles`, `biopay_embeddings`, `biopay_payment_intents`, `biopay_match_attempts`, `biopay_match_evidence`.
- Admin/observability: `audit_logs`, `admin_audit_log`, `notification_events`, operational dashboard RPCs, scheduled cleanup metadata.
- Messaging/preferences: notification preference tables, notification events, group feed/message tables.

## RLS Audit

- Most sensitive tables have RLS enabled and are protected through `auth.uid()`, group membership checks, bank/admin checks, or `public.is_admin_user()`.
- Admin writes for app content/config are audited through existing audit triggers and admin audit helpers.
- P0 fixed: `app_config` had a legacy public SELECT policy. That made every current and future config key client-readable, including operational payment routing values such as `savings_momo_code`.
- New contract: `app_config` table SELECT is admin-only; runtime clients call `public.get_public_app_config()` and receive only rows marked `is_public=true`.

## Edge Function Audit

- Shared auth helpers enforce authenticated callers, admin callers, cron secrets, CORS, OTP hashing, and App Check-aware request validation.
- Critical functions inspected include `admin-create-user`, `allocate-contributions`, `biopay-*`, `delete-account`, `generate-ai-content`, `parse-member-list`, `parse-momo-sms`, `record-operational-health`, `send-notification`, `send-otp`, `sms-ingest`, and `verify-otp`.
- No immediate P0 Edge Function bypass was found in the inspected shared auth paths.
- Fixed: `send-notification` now compares its service-role bearer token through the shared constant-time comparison helper.

## Security Fix Implemented

- Added `app_config.is_public boolean not null default false`.
- Backfilled only approved runtime-safe config keys as public.
- Dropped the legacy `"Public read app_config"` RLS policy.
- Added `app_config_select_admin` for authenticated platform admins.
- Added `public.get_public_app_config(p_keys text[] default null)` as the only client runtime config read path.
- Updated `AppConfigRepository` to use the RPC instead of direct table reads.
- Added static and SQL verification coverage for the new config boundary.
- Replaced direct service-role bearer equality in `send-notification` with the shared constant-time comparison helper.
- Hardened generic `payment_intents` so client-owned payment instructions cannot be self-confirmed through direct table updates.
- Normalized legacy `completed` intent writes to canonical `fulfilled` status at the database boundary.
- Added pgTAP coverage for group tenant RLS policy shape, payment status constraints, admin-only update policy, and manual allocation audit contracts.
- Hardened cron-secret comparison to use the shared constant-time comparator.
- Added admin-only OCR upload validation for member-list parsing, including MIME allowlist, base64 validation, 5 MiB limit, and sanitized external AI error logging.
- Added `notification_campaign_approvals` so topic broadcasts require approval, consent basis, expiry, and audit logging before dispatch.
- Sanitized FCM provider errors before durable notification logging.

## Migration

- `supabase/migrations/20260501130000_app_config_public_read_hardening.sql`
- `supabase/migrations/20260501131500_payment_intent_status_transition_hardening.sql`
- `supabase/migrations/20260501133000_notification_campaign_approval_hardening.sql`
- Manifest entry added under `supabase/migrations/migration_manifest.yaml`.
- Verification SQL added at `supabase/tests/app_config_public_read_hardening.sql`.
- pgTAP verification added at `supabase/tests/rls_tenant_payment_status_contract.sql`.
- Security/privacy pgTAP verification added at `supabase/tests/security_privacy_contract.sql`.

## Remaining Backend Risks

- Rotate the Supabase service-role key, database password, and project access token that were exposed in chat before applying further production changes.
- Run `supabase db lint --linked` and `supabase db push --linked` only from a secured operator shell after secret rotation.
- Continue RLS review on public catalog tables to confirm each public read is intentional content, not operational data.
- Add storage bucket policy inventory once production buckets are finalized.
