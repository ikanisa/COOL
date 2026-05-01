-- Approval and audit contract for outbound topic notifications.
--
-- Topic broadcasts can reach users who opted into broad FCM topics, so they
-- require an approved campaign row before the send-notification Edge Function
-- will dispatch them.

create table if not exists public.notification_campaign_approvals (
  id uuid primary key default gen_random_uuid(),
  topic text not null
    check (topic ~ '^[A-Za-z0-9_.~%-]{1,128}$'),
  category text not null
    check (category ~ '^[a-z][a-z0-9_:-]{0,63}$'),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 500),
  approval_status text not null default 'pending'
    check (approval_status in ('pending', 'approved', 'revoked', 'expired')),
  consent_basis text not null default 'topic_opt_in'
    check (consent_basis ~ '^[a-z][a-z0-9_:-]{0,63}$'),
  requested_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  expires_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_campaign_approval_approved_check check (
    approval_status <> 'approved'
    or (approved_by is not null and approved_at is not null)
  ),
  constraint notification_campaign_approval_expiry_check check (
    expires_at is null
    or approved_at is null
    or expires_at > approved_at
  )
);

create index if not exists idx_notification_campaign_approvals_status_topic
  on public.notification_campaign_approvals (
    approval_status,
    topic,
    category,
    expires_at
  );

alter table public.notification_campaign_approvals enable row level security;

drop policy if exists notification_campaign_approvals_admin_all
  on public.notification_campaign_approvals;
create policy notification_campaign_approvals_admin_all
  on public.notification_campaign_approvals
  for all
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists notification_campaign_approvals_service_select
  on public.notification_campaign_approvals;
create policy notification_campaign_approvals_service_select
  on public.notification_campaign_approvals
  for select
  to service_role
  using (true);

create or replace function public.normalize_notification_campaign_approval()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  if new.approval_status = 'approved' then
    new.approved_by := coalesce(new.approved_by, auth.uid());
    new.approved_at := coalesce(new.approved_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_normalize_notification_campaign_approval
  on public.notification_campaign_approvals;
create trigger trg_normalize_notification_campaign_approval
  before insert or update on public.notification_campaign_approvals
  for each row execute function public.normalize_notification_campaign_approval();

create or replace function public.audit_notification_campaign_approval_change()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target_id text;
  v_action text;
begin
  v_target_id := case
    when tg_op = 'DELETE' then old.id::text
    else new.id::text
  end;
  v_action := case tg_op
    when 'INSERT' then 'notification_campaign_approval_create'
    when 'UPDATE' then 'notification_campaign_approval_update'
    when 'DELETE' then 'notification_campaign_approval_delete'
    else 'notification_campaign_approval_change'
  end;

  insert into public.admin_audit_log (
    actor_id,
    action,
    target_table,
    target_id,
    old_data,
    new_data,
    notes
  ) values (
    auth.uid(),
    v_action,
    'notification_campaign_approvals',
    v_target_id,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    'Notification campaign approval changed.'
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_notification_campaign_approval_change
  on public.notification_campaign_approvals;
create trigger trg_audit_notification_campaign_approval_change
  after insert or update or delete on public.notification_campaign_approvals
  for each row execute function public.audit_notification_campaign_approval_change();

alter table public.notification_events
  add column if not exists category text,
  add column if not exists campaign_approval_id uuid
    references public.notification_campaign_approvals(id) on delete set null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'notification_events_category_check'
      and conrelid = 'public.notification_events'::regclass
  ) then
    alter table public.notification_events
      add constraint notification_events_category_check
      check (category is null or category ~ '^[a-z][a-z0-9_:-]{0,63}$')
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'notification_events_topic_approval_check'
      and conrelid = 'public.notification_events'::regclass
  ) then
    alter table public.notification_events
      add constraint notification_events_topic_approval_check
      check (target_type <> 'topic' or campaign_approval_id is not null)
      not valid;
  end if;
end $$;

create index if not exists idx_notification_events_campaign_approval
  on public.notification_events (campaign_approval_id)
  where campaign_approval_id is not null;

comment on table public.notification_campaign_approvals is
  'Admin-approved outbound topic notification campaigns. Topic sends must match an approved row.';

comment on column public.notification_events.campaign_approval_id is
  'Approval record used for topic notifications, when applicable.';
