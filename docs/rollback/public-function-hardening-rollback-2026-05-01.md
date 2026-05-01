# Public Function Hardening Rollback

Date: 2026-05-01

This repo does not roll back production Supabase changes with `db reset`,
`migration repair`, or destructive history edits. If the 2026-05-01 public
function hardening needs rollback, create a new timestamped migration that
compensates forward.

## Scope

Affected applied migrations:

- `20260501120000_public_function_lint_hardening.sql`
- `20260501121500_generate_invite_code_lint_cleanup.sql`
- `20260501123000_group_lifecycle_backfill_audit.sql`

## Forward Rollback Template

Create a new migration, for example:

```sql
-- supabase/migrations/YYYYMMDDHHMMSS_rollback_public_function_hardening.sql
begin;

-- 1. Restore specific RPC definitions from the last known-good release tag.
-- Do not paste from production introspection unless the source release tag is
-- unavailable; the repo release tag is the source of truth.

-- create or replace function public.<function_name>(...) ...

-- 2. Preserve additive columns unless a production incident proves they are
-- unsafe. Existing deployed admin screens now depend on these fields.
-- If disabling lifecycle behavior is required, prefer default/value changes:
--
-- alter table public.groups alter column is_active set default true;
-- alter table public.groups alter column is_closed set default false;

-- 3. Record the rollback.
insert into public.admin_audit_log (
  actor_id,
  action,
  target_table,
  target_id,
  new_data,
  notes
) values (
  null,
  'rollback_public_function_hardening',
  'schema_migration',
  '20260501120000',
  jsonb_build_object(
    'rollback_migration', 'YYYYMMDDHHMMSS_rollback_public_function_hardening.sql',
    'reason', '<incident-or-release-ticket>'
  ),
  'Forward rollback applied for 2026-05-01 public function hardening.'
);

commit;
```

## Verification

Run these before and after applying the rollback migration:

```bash
bash scripts/migrations/validate_supabase_migrations.sh
supabase db push --db-url "$SUPABASE_DB_URL" --dry-run
supabase db push --db-url "$SUPABASE_DB_URL" --yes
supabase db lint --db-url "$SUPABASE_DB_URL" --schema public --fail-on warning
flutter analyze
```

For runtime smoke, use an authenticated admin session and verify:

- `get_admin_groups_summary`
- `admin_get_savings_groups_detail`
- `get_user_detail_for_admin`
- `allocate-contributions`
- `evaluate-transfer-risk`
