-- ============================================================================
-- Cool App - MoMo SMS sync audit trail and contribution status alignment
-- ============================================================================

update public.group_contributions
   set status = 'confirmed',
       updated_at = now()
 where status = 'completed';

alter table public.group_contributions
  drop constraint if exists group_contributions_status_check;

alter table public.group_contributions
  add constraint group_contributions_status_check
    check (status in ('pending', 'confirmed', 'failed'));

create or replace function public.confirm_contribution(p_contribution_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_contribution record;
begin
  select id, group_id, amount, status
    into v_contribution
    from public.group_contributions
   where id = p_contribution_id
   for update;

  if v_contribution is null then
    return jsonb_build_object(
      'status',
      'error',
      'message',
      'Contribution not found.'
    );
  end if;

  if v_contribution.status in ('confirmed', 'completed') then
    return jsonb_build_object('status', 'already_confirmed');
  end if;

  if v_contribution.status <> 'pending' then
    return jsonb_build_object(
      'status',
      'error',
      'message',
      format(
        'Cannot confirm contribution with status: %s',
        v_contribution.status
      )
    );
  end if;

  update public.group_contributions
     set status = 'confirmed',
         updated_at = now()
   where id = p_contribution_id;

  update public.groups
     set amount = coalesce(amount, 0) + v_contribution.amount,
         updated_at = now()
   where id = v_contribution.group_id;

  return jsonb_build_object(
    'status',
    'success',
    'amount',
    v_contribution.amount
  );
end;
$function$;

create table if not exists public.momo_sms_sync_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  trigger text not null,
  status text not null default 'succeeded',
  lookback_days integer not null default 365,
  incremental boolean not null default false,
  scan_started_at timestamptz not null default now(),
  scan_completed_at timestamptz,
  scanned_messages integer not null default 0,
  uploaded_messages integer not null default 0,
  duplicate_messages integer not null default 0,
  oldest_message_at timestamptz,
  newest_message_at timestamptz,
  latest_known_message_at timestamptz,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.momo_sms_sync_runs
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists trigger text,
  add column if not exists status text default 'succeeded',
  add column if not exists lookback_days integer default 365,
  add column if not exists incremental boolean default false,
  add column if not exists scan_started_at timestamptz default now(),
  add column if not exists scan_completed_at timestamptz,
  add column if not exists scanned_messages integer default 0,
  add column if not exists uploaded_messages integer default 0,
  add column if not exists duplicate_messages integer default 0,
  add column if not exists oldest_message_at timestamptz,
  add column if not exists newest_message_at timestamptz,
  add column if not exists latest_known_message_at timestamptz,
  add column if not exists error_message text,
  add column if not exists metadata jsonb default '{}'::jsonb,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

alter table public.momo_sms_sync_runs
  alter column user_id set not null,
  alter column trigger set not null,
  alter column status set not null,
  alter column lookback_days set not null,
  alter column incremental set not null,
  alter column scan_started_at set not null,
  alter column scanned_messages set not null,
  alter column uploaded_messages set not null,
  alter column duplicate_messages set not null,
  alter column metadata set not null,
  alter column created_at set not null,
  alter column updated_at set not null;

alter table public.momo_sms_sync_runs
  alter column status set default 'succeeded',
  alter column lookback_days set default 365,
  alter column incremental set default false,
  alter column scan_started_at set default now(),
  alter column scanned_messages set default 0,
  alter column uploaded_messages set default 0,
  alter column duplicate_messages set default 0,
  alter column metadata set default '{}'::jsonb,
  alter column created_at set default now(),
  alter column updated_at set default now();

alter table public.momo_sms_sync_runs
  drop constraint if exists momo_sms_sync_runs_status_check,
  drop constraint if exists momo_sms_sync_runs_trigger_check;

alter table public.momo_sms_sync_runs
  add constraint momo_sms_sync_runs_status_check
    check (status in ('running', 'succeeded', 'failed')),
  add constraint momo_sms_sync_runs_trigger_check
    check (trigger in ('initial_permission_grant', 'manual'));

comment on column public.momo_sms_sync_runs.incremental is
  'True when the device sync used a narrowed window instead of a full 12-month backfill.';

create index if not exists idx_momo_sms_sync_runs_user_created
  on public.momo_sms_sync_runs (user_id, created_at desc);

create index if not exists idx_momo_sms_sync_runs_user_trigger
  on public.momo_sms_sync_runs (user_id, trigger, status, created_at desc);

drop trigger if exists trg_momo_sms_sync_runs_set_updated_at
  on public.momo_sms_sync_runs;

create trigger trg_momo_sms_sync_runs_set_updated_at
  before update on public.momo_sms_sync_runs
  for each row
  execute function public.set_updated_at();

alter table public.momo_sms_sync_runs enable row level security;

drop policy if exists "momo_sms_sync_runs_select_own"
  on public.momo_sms_sync_runs;

create policy "momo_sms_sync_runs_select_own"
  on public.momo_sms_sync_runs for select
  using (auth.uid() = user_id);

drop policy if exists "momo_sms_sync_runs_insert_own"
  on public.momo_sms_sync_runs;

create policy "momo_sms_sync_runs_insert_own"
  on public.momo_sms_sync_runs for insert
  with check (auth.uid() = user_id);

drop policy if exists "momo_sms_sync_runs_delete_own"
  on public.momo_sms_sync_runs;

create policy "momo_sms_sync_runs_delete_own"
  on public.momo_sms_sync_runs for delete
  using (auth.uid() = user_id);
