-- pgTAP verification for security/privacy contracts added during appsec hardening.

begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

select ok(
  (select relrowsecurity
   from pg_class
   where oid = 'public.notification_campaign_approvals'::regclass),
  'notification campaign approvals have RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_campaign_approvals'
      and policyname = 'notification_campaign_approvals_admin_all'
      and qual like '%is_admin_user%'
      and with_check like '%is_admin_user%'
  ),
  'campaign approvals are admin-managed'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgname = 'trg_audit_notification_campaign_approval_change'
      and tgrelid = 'public.notification_campaign_approvals'::regclass
      and not tgisinternal
  ),
  'campaign approval changes are audit logged'
);

select ok(
  exists (
    select 1
    from pg_attribute
    where attrelid = 'public.notification_events'::regclass
      and attname = 'campaign_approval_id'
      and not attisdropped
  ),
  'notification events link topic sends to approval records'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.notification_events'::regclass
      and conname = 'notification_events_topic_approval_check'
      and pg_get_constraintdef(oid) like '%campaign_approval_id IS NOT NULL%'
  ),
  'topic notification events require campaign approval linkage'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.notification_campaign_approvals'::regclass
      and conname = 'notification_campaign_approval_approved_check'
  ),
  'approved campaigns require approver metadata'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.notification_campaign_approvals'::regclass
      and conname = 'notification_campaign_approval_expiry_check'
  ),
  'approved campaigns cannot expire before approval'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'normalize_notification_campaign_approval'
      and p.prosecdef
      and pg_get_functiondef(p.oid) like '%approved_by := coalesce%'
  ),
  'approval normalization records approver metadata'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'audit_notification_campaign_approval_change'
      and p.prosecdef
      and pg_get_functiondef(p.oid) like '%public.admin_audit_log%'
  ),
  'campaign approval audit function writes admin audit logs'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_events'
      and policyname = 'Users read own notification events'
      and qual like '%auth.uid() = user_id%'
  ),
  'users only read their own notification events'
);

select * from finish();

rollback;
