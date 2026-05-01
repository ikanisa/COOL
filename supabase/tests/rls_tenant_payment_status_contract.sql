-- pgTAP verification for tenant isolation and payment status boundaries.
-- Run against a migrated test database:
--   psql "$DATABASE_URL" -f supabase/tests/rls_tenant_payment_status_contract.sql

begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.groups'::regclass),
  'groups has RLS enabled'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.group_members'::regclass),
  'group_members has RLS enabled'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.group_contributions'::regclass),
  'group_contributions has RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'groups'
      and policyname = 'groups_select_public'
      and qual like '%is_group_member%'
      and qual not in ('true', '(true)')
  ),
  'private group reads are scoped through is_group_member'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'group_members'
      and policyname = 'group_members_select'
      and qual like '%is_group_member%'
      and qual not in ('true', '(true)')
  ),
  'group member reads are scoped through is_group_member'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'group_contributions'
      and policyname = 'contributions_select'
      and qual like '%is_group_member%'
      and qual not in ('true', '(true)')
  ),
  'group contribution reads are scoped through group membership'
);

select ok(
  exists (
    select 1
    from information_schema.table_constraints
    where table_schema = 'public'
      and table_name = 'group_contributions'
      and constraint_name = 'fk_group_contributions_status'
  ),
  'group contribution status uses the shared transaction_statuses lookup'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'payment_intents'
      and policyname = 'payment_intents_update_auth'
  ),
  'payment intents do not allow owner-side direct status updates'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'payment_intents'
      and policyname = 'payment_intents_update_admin'
      and qual like '%is_admin_user%'
      and with_check like '%is_admin_user%'
  ),
  'payment intent direct updates are limited to platform admins'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgname = 'trg_enforce_payment_intent_status_transition'
      and tgrelid = 'public.payment_intents'::regclass
      and not tgisinternal
  ),
  'payment intents have a status transition trigger'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'enforce_payment_intent_status_transition'
      and p.prosecdef
      and pg_get_functiondef(p.oid) like '%new.status := ''fulfilled''%'
  ),
  'payment status trigger normalizes legacy completed to fulfilled'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'payment_intents_status_check'
      and conrelid = 'public.payment_intents'::regclass
      and pg_get_constraintdef(oid) like '%fulfilled%'
      and pg_get_constraintdef(oid) not like '%completed%'
  ),
  'payment intent statuses use canonical pending/fulfilled/expired/cancelled values'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_allocate_savings_contribution'
      and p.prosecdef
      and pg_get_functiondef(p.oid) like '%public.admin_audit_log%'
      and pg_get_functiondef(p.oid) like '%admin_allocate_savings_contribution%'
  ),
  'manual savings allocations are security-definer and audit logged'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'allocate_momo_manual_review'
      and p.prosecdef
      and pg_get_functiondef(p.oid) like '%v_intent.status <> ''pending''%'
      and pg_get_functiondef(p.oid) like '%allocation_actor_id%'
      and pg_get_functiondef(p.oid) like '%allocation_source%'
  ),
  'manual payment review allocation requires pending intents and records actor/source metadata'
);

select * from finish();

rollback;
