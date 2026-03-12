-- ==========================================================================
-- Cool App - Partner credit applications and handoff records
-- ==========================================================================

create table if not exists public.partner_credit_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  application_type text not null,
  status text not null default 'draft',
  readiness_state text not null default 'building',
  requested_product text,
  applicant_note text,
  official_name text not null default '',
  official_phone text not null default '',
  kyc_status text not null default 'unverified',
  credit_score integer,
  credit_score_band text,
  credit_score_version text,
  score_summary text,
  snapshot_payload jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  last_handoff_at timestamptz,
  last_handoff_channel text,
  last_destination_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint partner_credit_applications_type_check
    check (application_type in ('loan', 'account_opening')),
  constraint partner_credit_applications_status_check
    check (status in ('draft', 'partner_routed', 'in_review', 'partner_contacted', 'closed', 'cancelled')),
  constraint partner_credit_applications_readiness_check
    check (readiness_state in ('ready', 'nearly_ready', 'building', 'action_needed')),
  constraint partner_credit_applications_score_band_check
    check (
      credit_score_band is null or
      credit_score_band in ('limited_history', 'building', 'good', 'excellent')
    )
);

create index if not exists idx_partner_credit_applications_user_created
  on public.partner_credit_applications (user_id, created_at desc);

create index if not exists idx_partner_credit_applications_partner_status
  on public.partner_credit_applications (partner_id, status, created_at desc);

drop trigger if exists trg_partner_credit_applications_set_updated_at on public.partner_credit_applications;
create trigger trg_partner_credit_applications_set_updated_at
  before update on public.partner_credit_applications
  for each row
  execute function public.set_updated_at();

create table if not exists public.partner_application_handoffs (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.partner_credit_applications(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  handoff_channel text not null default 'in_app_redirect',
  destination_path text,
  created_at timestamptz not null default now(),
  constraint partner_application_handoffs_channel_check
    check (handoff_channel in ('in_app_redirect', 'whatsapp', 'phone', 'email', 'branch', 'manual'))
);

create index if not exists idx_partner_application_handoffs_application
  on public.partner_application_handoffs (application_id, created_at desc);

create index if not exists idx_partner_application_handoffs_user_created
  on public.partner_application_handoffs (user_id, created_at desc);

alter table public.partner_credit_applications enable row level security;
alter table public.partner_application_handoffs enable row level security;

drop policy if exists "partner_credit_applications_select_own" on public.partner_credit_applications;
create policy "partner_credit_applications_select_own"
  on public.partner_credit_applications for select
  using (auth.uid() = user_id);

drop policy if exists "partner_application_handoffs_select_own" on public.partner_application_handoffs;
create policy "partner_application_handoffs_select_own"
  on public.partner_application_handoffs for select
  using (auth.uid() = user_id);

create or replace function public.create_partner_credit_application(
  p_partner_id uuid,
  p_application_type text,
  p_readiness_state text,
  p_requested_product text default null,
  p_applicant_note text default null,
  p_submit_now boolean default false,
  p_handoff_channel text default 'in_app_redirect',
  p_destination_path text default null
)
returns public.partner_credit_applications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_profile public.users;
  v_score public.credit_score_runs;
  v_partner public.partners;
  v_application public.partner_credit_applications;
  v_handoff_channel text := coalesce(nullif(trim(p_handoff_channel), ''), 'in_app_redirect');
  v_destination_path text := nullif(trim(p_destination_path), '');
begin
  if v_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if coalesce(p_application_type, '') not in ('loan', 'account_opening') then
    raise exception 'Unsupported application type: %', p_application_type
      using errcode = '22023';
  end if;

  if coalesce(p_readiness_state, '') not in ('ready', 'nearly_ready', 'building', 'action_needed') then
    raise exception 'Unsupported readiness state: %', p_readiness_state
      using errcode = '22023';
  end if;

  if v_handoff_channel not in ('in_app_redirect', 'whatsapp', 'phone', 'email', 'branch', 'manual') then
    raise exception 'Unsupported handoff channel: %', v_handoff_channel
      using errcode = '22023';
  end if;

  select *
  into v_profile
  from public.users
  where id = v_user_id;

  if not found then
    raise exception 'User profile not found'
      using errcode = 'P0002';
  end if;

  select *
  into v_partner
  from public.partners
  where id = p_partner_id
    and is_active = true;

  if not found then
    raise exception 'Partner not found'
      using errcode = 'P0002';
  end if;

  select *
  into v_score
  from public.credit_score_runs
  where user_id = v_user_id
  order by generated_at desc
  limit 1;

  insert into public.partner_credit_applications (
    user_id,
    partner_id,
    application_type,
    status,
    readiness_state,
    requested_product,
    applicant_note,
    official_name,
    official_phone,
    kyc_status,
    credit_score,
    credit_score_band,
    credit_score_version,
    score_summary,
    snapshot_payload,
    submitted_at,
    last_handoff_at,
    last_handoff_channel,
    last_destination_path
  )
  values (
    v_user_id,
    p_partner_id,
    p_application_type,
    case when coalesce(p_submit_now, false) then 'partner_routed' else 'draft' end,
    p_readiness_state,
    nullif(trim(p_requested_product), ''),
    nullif(trim(p_applicant_note), ''),
    coalesce(nullif(trim(v_profile.official_name), ''), nullif(trim(v_profile.full_name), ''), ''),
    coalesce(nullif(trim(v_profile.official_phone), ''), nullif(trim(v_profile.phone), ''), ''),
    v_profile.kyc_status,
    v_score.score,
    v_score.score_band,
    v_score.score_version,
    v_score.score_summary,
    jsonb_build_object(
      'score_run_id', v_score.id,
      'score_generated_at', v_score.generated_at,
      'statement_count', coalesce(v_score.statement_count, 0),
      'group_contribution_count', coalesce(v_score.group_contribution_count, 0),
      'active_month_count', coalesce(v_score.active_month_count, 0),
      'reason_codes', coalesce(to_jsonb(v_score.reason_codes), '[]'::jsonb),
      'factor_payload', coalesce(v_score.factor_payload, '{}'::jsonb),
      'kyc_status', v_profile.kyc_status
    ),
    case when coalesce(p_submit_now, false) then v_now else null end,
    case when coalesce(p_submit_now, false) then v_now else null end,
    case when coalesce(p_submit_now, false) then v_handoff_channel else null end,
    case when coalesce(p_submit_now, false) then v_destination_path else null end
  )
  returning *
  into v_application;

  if coalesce(p_submit_now, false) then
    insert into public.partner_application_handoffs (
      application_id,
      user_id,
      partner_id,
      handoff_channel,
      destination_path
    )
    values (
      v_application.id,
      v_user_id,
      p_partner_id,
      v_handoff_channel,
      v_destination_path
    );
  end if;

  return v_application;
end;
$$;

revoke all on function public.create_partner_credit_application(
  uuid,
  text,
  text,
  text,
  text,
  boolean,
  text,
  text
) from public;

grant execute on function public.create_partner_credit_application(
  uuid,
  text,
  text,
  text,
  text,
  boolean,
  text,
  text
) to authenticated;
