-- ==========================================================================
-- Cool App - Credit scoring foundation and transaction analysis metadata
-- ==========================================================================

alter table public.users
  add column if not exists official_name text,
  add column if not exists official_phone text,
  add column if not exists kyc_status text not null default 'unverified',
  add column if not exists kyc_verified_at timestamptz,
  add column if not exists credit_consent_granted_at timestamptz;
-- Temporarily disable the MoMo validation trigger so the backfill UPDATEs
-- don't fire it on rows with pre-existing invalid MoMo data.
alter table public.users disable trigger trg_enforce_user_momo_fields;
update public.users
set official_name = full_name
where coalesce(trim(official_name), '') = ''
  and coalesce(trim(full_name), '') <> '';
update public.users
set official_phone = phone
where coalesce(trim(official_phone), '') = ''
  and coalesce(trim(phone), '') <> '';
alter table public.users enable trigger trg_enforce_user_momo_fields;
alter table public.users
  drop constraint if exists users_kyc_status_check;
alter table public.users
  add constraint users_kyc_status_check
    check (kyc_status in ('unverified', 'pending_review', 'verified', 'rejected'));
create index if not exists idx_users_kyc_status
  on public.users (kyc_status);
alter table public.momo_sms_parsed
  add column if not exists tx_category text not null default 'uncategorized',
  add column if not exists cashflow_bucket text not null default 'unknown',
  add column if not exists counterparty_name text,
  add column if not exists ai_summary text,
  add column if not exists recurring_pattern_hint text;
alter table public.momo_sms_parsed
  drop constraint if exists momo_sms_parsed_cashflow_bucket_check;
alter table public.momo_sms_parsed
  add constraint momo_sms_parsed_cashflow_bucket_check
    check (cashflow_bucket in ('income', 'expense', 'savings', 'transfer', 'loan', 'fees', 'unknown'));
create index if not exists idx_momo_sms_parsed_category
  on public.momo_sms_parsed (tx_category, cashflow_bucket);
alter table public.momo_ledger_entries
  add column if not exists tx_category text not null default 'uncategorized',
  add column if not exists cashflow_bucket text not null default 'unknown',
  add column if not exists counterparty_name text,
  add column if not exists statement_label text;
alter table public.momo_ledger_entries
  drop constraint if exists momo_ledger_entries_cashflow_bucket_check;
alter table public.momo_ledger_entries
  add constraint momo_ledger_entries_cashflow_bucket_check
    check (cashflow_bucket in ('income', 'expense', 'savings', 'transfer', 'loan', 'fees', 'unknown'));
create index if not exists idx_momo_ledger_entries_statement
  on public.momo_ledger_entries (user_id, ledger_status, tx_datetime desc);
create index if not exists idx_momo_ledger_entries_category
  on public.momo_ledger_entries (tx_category, cashflow_bucket);
create or replace function public.derive_momo_tx_category(
  p_tx_type text,
  p_tx_direction text,
  p_target_table text default null
)
returns text
language sql
immutable
as $$
  select case
    when lower(coalesce(p_target_table, '')) = 'group_contributions' then 'group_contribution'
    when lower(coalesce(p_target_table, '')) = 'driver_subscriptions' then 'subscription'
    when lower(coalesce(p_tx_type, '')) in ('salary', 'payroll') then 'salary'
    when lower(coalesce(p_tx_type, '')) in ('subscription', 'bundle') then 'subscription'
    when lower(coalesce(p_tx_type, '')) in ('cash_in', 'deposit') then 'cash_in'
    when lower(coalesce(p_tx_type, '')) in ('cash_out', 'withdrawal') then 'cash_out'
    when lower(coalesce(p_tx_type, '')) in ('merchant_payment', 'bill_payment', 'payment') then 'merchant_payment'
    when lower(coalesce(p_tx_type, '')) in ('transfer', 'send_money', 'received_money') then
      case
        when lower(coalesce(p_tx_direction, '')) = 'credit' then 'transfer_in'
        when lower(coalesce(p_tx_direction, '')) = 'debit' then 'transfer_out'
        else 'transfer'
      end
    when lower(coalesce(p_tx_type, '')) in ('airtime', 'bundle_purchase') then 'airtime'
    when lower(coalesce(p_tx_type, '')) in ('bank_transfer', 'bank_deposit') then 'bank_transfer'
    when lower(coalesce(p_tx_type, '')) in ('fee', 'charge') then 'fees'
    when lower(coalesce(p_tx_type, '')) in ('loan', 'loan_repayment', 'loan_disbursement') then lower(coalesce(p_tx_type, ''))
    when lower(coalesce(p_tx_direction, '')) = 'credit' then 'transfer_in'
    when lower(coalesce(p_tx_direction, '')) = 'debit' then 'transfer_out'
    else 'uncategorized'
  end;
$$;
create or replace function public.derive_momo_cashflow_bucket(
  p_tx_category text,
  p_tx_direction text
)
returns text
language sql
immutable
as $$
  select case
    when lower(coalesce(p_tx_category, '')) in ('salary', 'cash_in', 'transfer_in', 'loan_disbursement') then 'income'
    when lower(coalesce(p_tx_category, '')) in ('group_contribution', 'savings') then 'savings'
    when lower(coalesce(p_tx_category, '')) in ('loan', 'loan_repayment') then 'loan'
    when lower(coalesce(p_tx_category, '')) in ('fees', 'charge') then 'fees'
    when lower(coalesce(p_tx_category, '')) in ('transfer_in', 'transfer_out', 'transfer', 'bank_transfer') then 'transfer'
    when lower(coalesce(p_tx_category, '')) in ('merchant_payment', 'cash_out', 'airtime', 'subscription') then 'expense'
    when lower(coalesce(p_tx_direction, '')) = 'credit' then 'income'
    when lower(coalesce(p_tx_direction, '')) = 'debit' then 'expense'
    else 'unknown'
  end;
$$;
with parsed_backfill as (
  select
    id,
    public.derive_momo_tx_category(tx_type, tx_direction, null) as derived_category,
    public.derive_momo_cashflow_bucket(
      public.derive_momo_tx_category(tx_type, tx_direction, null),
      tx_direction
    ) as derived_bucket,
    case
      when tx_direction = 'credit' then coalesce(nullif(trim(payer_name), ''), nullif(trim(payee_name), ''))
      when tx_direction = 'debit' then coalesce(nullif(trim(payee_name), ''), nullif(trim(payer_name), ''))
      else coalesce(nullif(trim(payer_name), ''), nullif(trim(payee_name), ''))
    end as derived_counterparty,
    coalesce(
      nullif(trim(narrative), ''),
      case
        when tx_direction = 'credit' then 'Incoming mobile money transaction'
        when tx_direction = 'debit' then 'Outgoing mobile money transaction'
        else 'Mobile money transaction'
      end
    ) as derived_summary,
    case
      when lower(coalesce(tx_type, '')) in ('salary', 'subscription', 'bundle') then 'recurring'
      when lower(coalesce(tx_type, '')) in ('loan', 'loan_repayment', 'loan_disbursement') then 'seasonal'
      else 'one_off'
    end as derived_pattern
  from public.momo_sms_parsed
)
update public.momo_sms_parsed as parsed
set
  tx_category = backfill.derived_category,
  cashflow_bucket = backfill.derived_bucket,
  counterparty_name = backfill.derived_counterparty,
  ai_summary = backfill.derived_summary,
  recurring_pattern_hint = backfill.derived_pattern
from parsed_backfill as backfill
where backfill.id = parsed.id;
update public.momo_ledger_entries as ledger
set
  tx_category = coalesce(parsed.tx_category, public.derive_momo_tx_category(parsed.tx_type, parsed.tx_direction, ledger.target_table)),
  cashflow_bucket = coalesce(parsed.cashflow_bucket, public.derive_momo_cashflow_bucket(parsed.tx_category, parsed.tx_direction)),
  counterparty_name = parsed.counterparty_name,
  statement_label = coalesce(parsed.ai_summary, parsed.narrative, initcap(replace(coalesce(parsed.tx_type, ledger.entry_type), '_', ' ')))
from public.momo_sms_parsed as parsed
where parsed.id = ledger.parsed_sms_id;
create table if not exists public.credit_score_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  score_version text not null default 'momo_v1',
  score integer not null,
  score_band text not null,
  score_summary text,
  statement_count integer not null default 0,
  group_contribution_count integer not null default 0,
  active_month_count integer not null default 0,
  cashflow_stability integer not null default 0,
  savings_discipline integer not null default 0,
  group_reliability integer not null default 0,
  profile_strength integer not null default 0,
  reason_codes text[] not null default '{}'::text[],
  factor_payload jsonb not null default '{}'::jsonb,
  scoring_window_start timestamptz not null,
  scoring_window_end timestamptz not null,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text,
  constraint credit_score_runs_score_check
    check (score between 300 and 850),
  constraint credit_score_runs_score_band_check
    check (score_band in ('limited_history', 'building', 'good', 'excellent')),
  constraint credit_score_runs_factor_range_check
    check (
      cashflow_stability between 0 and 100 and
      savings_discipline between 0 and 100 and
      group_reliability between 0 and 100 and
      profile_strength between 0 and 100
    )
);
create index if not exists idx_credit_score_runs_user_generated
  on public.credit_score_runs (user_id, generated_at desc);
create index if not exists idx_credit_score_runs_band
  on public.credit_score_runs (score_band, generated_at desc);
drop trigger if exists trg_credit_score_runs_set_updated_at on public.credit_score_runs;
create trigger trg_credit_score_runs_set_updated_at
  before update on public.credit_score_runs
  for each row
  execute function public.set_updated_at();
alter table public.credit_score_runs enable row level security;
drop policy if exists "credit_score_runs_select_own" on public.credit_score_runs;
create policy "credit_score_runs_select_own"
  on public.credit_score_runs for select
  using (auth.uid() = user_id);
create or replace function public.credit_score_band(p_score integer)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_score, 0) >= 720 then 'excellent'
    when coalesce(p_score, 0) >= 640 then 'good'
    when coalesce(p_score, 0) >= 560 then 'building'
    else 'limited_history'
  end;
$$;
create or replace function public.credit_score_summary(
  p_score integer,
  p_reason_codes text[] default '{}'::text[]
)
returns text
language plpgsql
immutable
as $$
declare
  v_band text := public.credit_score_band(p_score);
  v_reason_codes text[] := coalesce(p_reason_codes, '{}'::text[]);
  v_suffix text := 'Keep verified wallet activity and savings contributions consistent.';
begin
  if array_position(v_reason_codes, 'profile_verification_needed') is not null then
    v_suffix := 'Complete official profile verification to strengthen loan-readiness.';
  elsif array_position(v_reason_codes, 'group_savings_missing') is not null then
    v_suffix := 'Add more confirmed group savings activity to build reliability.';
  elsif array_position(v_reason_codes, 'savings_pattern_thin') is not null then
    v_suffix := 'Steadier savings behaviour will lift the next score run.';
  elsif array_position(v_reason_codes, 'income_history_thin') is not null then
    v_suffix := 'More regular incoming wallet activity is needed to confirm cash-flow stability.';
  elsif array_position(v_reason_codes, 'wallet_activity_low') is not null then
    v_suffix := 'More posted mobile-money activity is needed before the score can strengthen.';
  end if;

  return case v_band
    when 'excellent' then 'Strong verified wallet and savings behaviour. ' || v_suffix
    when 'good' then 'Healthy activity with a few gaps still to close. ' || v_suffix
    when 'building' then 'The credit file is forming, but it is still thin. ' || v_suffix
    else 'Limited verified history is available right now. ' || v_suffix
  end;
end;
$$;
create or replace function public.recompute_credit_score(
  p_user_id uuid,
  p_generated_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_generated_at timestamptz := coalesce(p_generated_at, now());
  v_window_start timestamptz := date_trunc('day', v_generated_at - interval '180 days');
  v_statement_count integer := 0;
  v_credit_entry_count integer := 0;
  v_debit_entry_count integer := 0;
  v_credit_total bigint := 0;
  v_debit_total bigint := 0;
  v_active_month_count integer := 0;
  v_credit_month_count integer := 0;
  v_debit_month_count integer := 0;
  v_group_contribution_count integer := 0;
  v_group_active_month_count integer := 0;
  v_group_total bigint := 0;
  v_average_group_contribution numeric := 0;
  v_has_official_name boolean := false;
  v_has_official_phone boolean := false;
  v_has_momo_profile boolean := false;
  v_kyc_status text := 'unverified';
  v_is_mock boolean := false;
  v_mock_batch text := null;
  v_cashflow_stability integer := 0;
  v_savings_discipline integer := 0;
  v_group_reliability integer := 0;
  v_profile_strength integer := 0;
  v_score integer := 300;
  v_score_band text := 'limited_history';
  v_reason_codes text[] := '{}'::text[];
  v_summary text;
  v_run_id uuid;
begin
  if p_user_id is null then
    return null;
  end if;

  select
    coalesce(nullif(trim(coalesce(official_name, full_name)), ''), '') <> '',
    coalesce(nullif(trim(coalesce(official_phone, phone)), ''), '') <> '',
    coalesce(nullif(trim(coalesce(momo_number, momo_code, '')), ''), '') <> '',
    kyc_status,
    coalesce(is_mock, false),
    mock_batch
  into
    v_has_official_name,
    v_has_official_phone,
    v_has_momo_profile,
    v_kyc_status,
    v_is_mock,
    v_mock_batch
  from public.users
  where id = p_user_id;

  if not found then
    return null;
  end if;

  select
    count(*)::int,
    count(*) filter (where entry_type = 'credit')::int,
    count(*) filter (where entry_type = 'debit')::int,
    coalesce(sum(amount) filter (where entry_type = 'credit'), 0)::bigint,
    coalesce(sum(amount) filter (where entry_type = 'debit'), 0)::bigint,
    count(distinct date_trunc('month', coalesce(tx_datetime, created_at)))::int,
    count(distinct date_trunc('month', coalesce(tx_datetime, created_at)))
      filter (where entry_type = 'credit')::int,
    count(distinct date_trunc('month', coalesce(tx_datetime, created_at)))
      filter (where entry_type = 'debit')::int
  into
    v_statement_count,
    v_credit_entry_count,
    v_debit_entry_count,
    v_credit_total,
    v_debit_total,
    v_active_month_count,
    v_credit_month_count,
    v_debit_month_count
  from public.momo_ledger_entries
  where user_id = p_user_id
    and ledger_status = 'posted'
    and coalesce(tx_datetime, created_at) >= v_window_start
    and coalesce(tx_datetime, created_at) <= v_generated_at;

  select
    count(*)::int,
    count(distinct date_trunc('month', created_at))::int,
    coalesce(sum(amount), 0)::bigint,
    coalesce(avg(amount), 0)::numeric
  into
    v_group_contribution_count,
    v_group_active_month_count,
    v_group_total,
    v_average_group_contribution
  from public.group_contributions
  where user_id = p_user_id
    and status = 'confirmed'
    and created_at >= v_window_start
    and created_at <= v_generated_at;

  if v_statement_count = 0 and v_group_contribution_count = 0 then
    return null;
  end if;

  v_cashflow_stability := least(
    100,
    greatest(
      0,
      round(
        least(v_active_month_count, 6) * 40.0 / 6 +
        least(v_credit_month_count, 6) * 35.0 / 6 +
        least(v_statement_count, 60) * 25.0 / 60
      )::int
    )
  );

  v_savings_discipline := least(
    100,
    greatest(
      0,
      round(
        least(greatest(v_group_active_month_count, v_debit_month_count), 6) * 45.0 / 6 +
        least(v_group_contribution_count, 12) * 35.0 / 12 +
        least(coalesce(v_average_group_contribution, 0), 50000) * 20.0 / 50000
      )::int
    )
  );

  v_group_reliability := least(
    100,
    greatest(
      0,
      round(
        least(v_group_active_month_count, 6) * 60.0 / 6 +
        least(v_group_contribution_count, 12) * 40.0 / 12
      )::int
    )
  );

  v_profile_strength := 0;
  if v_has_official_name then
    v_profile_strength := v_profile_strength + 40;
  end if;
  if v_has_official_phone then
    v_profile_strength := v_profile_strength + 25;
  end if;
  if v_has_momo_profile then
    v_profile_strength := v_profile_strength + 20;
  end if;
  if v_kyc_status = 'verified' then
    v_profile_strength := v_profile_strength + 15;
  elsif v_kyc_status = 'pending_review' then
    v_profile_strength := v_profile_strength + 8;
  end if;

  if v_statement_count < 12 then
    v_reason_codes := array_append(v_reason_codes, 'wallet_activity_low');
  end if;
  if v_credit_month_count < 3 then
    v_reason_codes := array_append(v_reason_codes, 'income_history_thin');
  end if;
  if v_savings_discipline < 60 then
    v_reason_codes := array_append(v_reason_codes, 'savings_pattern_thin');
  end if;
  if v_group_contribution_count = 0 then
    v_reason_codes := array_append(v_reason_codes, 'group_savings_missing');
  elsif v_group_reliability < 60 then
    v_reason_codes := array_append(v_reason_codes, 'group_activity_low');
  end if;
  if v_profile_strength < 70 then
    v_reason_codes := array_append(v_reason_codes, 'profile_verification_needed');
  end if;
  if coalesce(array_length(v_reason_codes, 1), 0) = 0 then
    v_reason_codes := array['healthy_verified_history'];
  end if;

  v_score := least(
    850,
    greatest(
      300,
      300 + round(
        v_cashflow_stability * 2.1 +
        v_savings_discipline * 1.7 +
        v_group_reliability * 1.1 +
        v_profile_strength * 0.6
      )::int
    )
  );

  if v_statement_count < 4 and v_group_contribution_count < 2 then
    v_score := least(v_score, 560);
  elsif v_active_month_count < 2 then
    v_score := least(v_score, 610);
  end if;

  v_score_band := public.credit_score_band(v_score);
  v_summary := public.credit_score_summary(v_score, v_reason_codes);

  insert into public.credit_score_runs (
    user_id,
    score_version,
    score,
    score_band,
    score_summary,
    statement_count,
    group_contribution_count,
    active_month_count,
    cashflow_stability,
    savings_discipline,
    group_reliability,
    profile_strength,
    reason_codes,
    factor_payload,
    scoring_window_start,
    scoring_window_end,
    generated_at,
    is_mock,
    mock_batch
  )
  values (
    p_user_id,
    'momo_v1',
    v_score,
    v_score_band,
    v_summary,
    v_statement_count,
    v_group_contribution_count,
    greatest(v_active_month_count, v_group_active_month_count),
    v_cashflow_stability,
    v_savings_discipline,
    v_group_reliability,
    v_profile_strength,
    v_reason_codes,
    jsonb_build_object(
      'credit_entry_count', v_credit_entry_count,
      'debit_entry_count', v_debit_entry_count,
      'credit_total', v_credit_total,
      'debit_total', v_debit_total,
      'group_total', v_group_total,
      'average_group_contribution', v_average_group_contribution,
      'kyc_status', v_kyc_status
    ),
    v_window_start,
    v_generated_at,
    v_generated_at,
    v_is_mock,
    v_mock_batch
  )
  returning id into v_run_id;

  return v_run_id;
end;
$$;
create or replace function public.recompute_credit_scores_for_all_users(
  p_generated_at timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user record;
  v_run_id uuid;
  v_count integer := 0;
begin
  for v_user in
    select id
    from public.users
  loop
    v_run_id := public.recompute_credit_score(v_user.id, p_generated_at);
    if v_run_id is not null then
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;
insert into public.credit_score_runs (
  user_id,
  score_version,
  score,
  score_band,
  score_summary,
  statement_count,
  group_contribution_count,
  active_month_count,
  cashflow_stability,
  savings_discipline,
  group_reliability,
  profile_strength,
  reason_codes,
  factor_payload,
  scoring_window_start,
  scoring_window_end,
  generated_at,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  legacy.user_id,
  'legacy_credit_scores_v0',
  least(850, greatest(300, legacy.score)),
  public.credit_score_band(least(850, greatest(300, legacy.score))),
  public.credit_score_summary(
    least(850, greatest(300, legacy.score)),
    array_remove(
      array[
        case when legacy.payment_history < 60 then 'wallet_activity_low' else null end,
        case when legacy.saving_consistency < 60 then 'savings_pattern_thin' else null end,
        case when legacy.group_participation < 60 then 'group_activity_low' else null end,
        case when legacy.community_activity < 60 then 'profile_verification_needed' else null end
      ]::text[],
      null
    )
  ),
  0,
  0,
  0,
  greatest(0, least(100, legacy.payment_history)),
  greatest(0, least(100, legacy.saving_consistency)),
  greatest(0, least(100, legacy.group_participation)),
  greatest(0, least(100, legacy.community_activity)),
  coalesce(
    nullif(
      array_remove(
        array[
          case when legacy.payment_history < 60 then 'wallet_activity_low' else null end,
          case when legacy.saving_consistency < 60 then 'savings_pattern_thin' else null end,
          case when legacy.group_participation < 60 then 'group_activity_low' else null end,
          case when legacy.community_activity < 60 then 'profile_verification_needed' else null end
        ]::text[],
        null
      ),
      '{}'::text[]
    ),
    array['healthy_verified_history']
  ),
  jsonb_build_object(
    'legacy_source', 'credit_scores',
    'saving_consistency', legacy.saving_consistency,
    'group_participation', legacy.group_participation,
    'payment_history', legacy.payment_history,
    'community_activity', legacy.community_activity
  ),
  legacy.recorded_at - interval '90 days',
  legacy.recorded_at,
  legacy.recorded_at,
  legacy.recorded_at,
  legacy.recorded_at,
  coalesce(legacy.is_mock, false),
  legacy.mock_batch
from public.credit_scores as legacy
where not exists (
  select 1
  from public.credit_score_runs as existing
  where existing.user_id = legacy.user_id
    and existing.score_version = 'legacy_credit_scores_v0'
    and existing.generated_at = legacy.recorded_at
);
select public.recompute_credit_scores_for_all_users(now());
