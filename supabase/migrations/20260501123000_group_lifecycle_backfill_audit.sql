-- ============================================================================
-- Group lifecycle backfill audit
-- ============================================================================
-- The 20260501120000 hardening migration restored groups.is_active and
-- groups.is_closed as additive lifecycle columns. Existing rows received
-- PostgreSQL defaults because there was no reliable prior closed/open state in
-- the live schema. This migration records that classification explicitly so the
-- production state is auditable.
-- ============================================================================

insert into public.admin_audit_log (
  actor_id,
  action,
  target_table,
  target_id,
  old_data,
  new_data,
  notes
)
select
  null,
  'admin_action',
  'groups',
  g.id::text,
  '{}'::jsonb,
  jsonb_build_object(
    'is_active', g.is_active,
    'is_closed', g.is_closed,
    'migration', '20260501120000_public_function_lint_hardening.sql',
    'event', 'group_lifecycle_backfill_default_open',
    'reason', 'Existing groups had no prior lifecycle columns; defaults preserved open behavior.'
  ),
  'Lifecycle defaults were applied during schema hardening because no prior lifecycle state existed.'
from public.groups g
where not exists (
  select 1
  from public.admin_audit_log log
  where log.action = 'admin_action'
    and log.target_table = 'groups'
    and log.target_id = g.id::text
    and log.new_data ->> 'event' = 'group_lifecycle_backfill_default_open'
);
