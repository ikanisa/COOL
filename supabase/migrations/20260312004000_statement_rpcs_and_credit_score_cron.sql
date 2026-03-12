-- ==========================================================================
-- Cool App - Statement RPCs + scheduled credit-score refresh
-- ==========================================================================

create index if not exists idx_momo_ledger_entries_user_posted_statement_at
  on public.momo_ledger_entries (
    user_id,
    ledger_status,
    coalesce(tx_datetime, created_at) desc
  );

create index if not exists idx_group_contributions_user_status_created
  on public.group_contributions (user_id, status, created_at desc);

create or replace function public.get_wallet_statement_entries(
  p_start_at timestamptz default null,
  p_end_before timestamptz default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  id uuid,
  entry_type text,
  ledger_status text,
  amount integer,
  currency text,
  tx_datetime timestamptz,
  external_reference text,
  tx_category text,
  cashflow_bucket text,
  counterparty_name text,
  statement_label text,
  description text,
  created_at timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with statement_rows as (
    select
      ledger.id,
      ledger.entry_type,
      ledger.ledger_status,
      ledger.amount,
      ledger.currency,
      coalesce(ledger.tx_datetime, ledger.created_at) as tx_datetime,
      ledger.external_reference,
      coalesce(
        nullif(trim(ledger.tx_category), ''),
        public.derive_momo_tx_category(
          ledger.entry_type,
          ledger.ledger_scope,
          ledger.target_table
        )
      ) as tx_category,
      coalesce(
        nullif(trim(ledger.cashflow_bucket), ''),
        public.derive_momo_cashflow_bucket(
          coalesce(
            nullif(trim(ledger.tx_category), ''),
            public.derive_momo_tx_category(
              ledger.entry_type,
              ledger.ledger_scope,
              ledger.target_table
            )
          ),
          ledger.entry_type
        )
      ) as cashflow_bucket,
      nullif(trim(ledger.counterparty_name), '') as counterparty_name,
      coalesce(
        nullif(trim(ledger.statement_label), ''),
        nullif(trim(ledger.description), ''),
        initcap(replace(coalesce(ledger.tx_category, ledger.entry_type), '_', ' '))
      ) as statement_label,
      ledger.description,
      ledger.created_at
    from public.momo_ledger_entries as ledger
    where ledger.user_id = auth.uid()
      and ledger.ledger_status = 'posted'
      and (p_start_at is null or coalesce(ledger.tx_datetime, ledger.created_at) >= p_start_at)
      and (p_end_before is null or coalesce(ledger.tx_datetime, ledger.created_at) < p_end_before)
  )
  select
    row.id,
    row.entry_type,
    row.ledger_status,
    row.amount,
    row.currency,
    row.tx_datetime,
    row.external_reference,
    row.tx_category,
    row.cashflow_bucket,
    row.counterparty_name,
    row.statement_label,
    row.description,
    row.created_at,
    count(*) over() as total_count
  from statement_rows as row
  order by row.tx_datetime desc, row.created_at desc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.get_group_savings_statement_entries(
  p_start_at timestamptz default null,
  p_end_before timestamptz default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  id uuid,
  group_id uuid,
  group_name text,
  amount integer,
  status text,
  created_at timestamptz,
  momo_reference text,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with statement_rows as (
    select
      contribution.id,
      contribution.group_id,
      coalesce(nullif(trim(group_item.name), ''), 'Savings group') as group_name,
      contribution.amount,
      contribution.status,
      contribution.created_at,
      contribution.momo_reference
    from public.group_contributions as contribution
    left join public.groups as group_item
      on group_item.id = contribution.group_id
    where contribution.user_id = auth.uid()
      and (p_start_at is null or contribution.created_at >= p_start_at)
      and (p_end_before is null or contribution.created_at < p_end_before)
  )
  select
    row.id,
    row.group_id,
    row.group_name,
    row.amount,
    row.status,
    row.created_at,
    row.momo_reference,
    count(*) over() as total_count
  from statement_rows as row
  order by row.created_at desc, row.id desc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.get_wallet_statement_entries(
  timestamptz,
  timestamptz,
  integer,
  integer
) from public;

grant execute on function public.get_wallet_statement_entries(
  timestamptz,
  timestamptz,
  integer,
  integer
) to authenticated;

revoke all on function public.get_group_savings_statement_entries(
  timestamptz,
  timestamptz,
  integer,
  integer
) from public;

grant execute on function public.get_group_savings_statement_entries(
  timestamptz,
  timestamptz,
  integer,
  integer
) to authenticated;

create or replace function public.refresh_credit_scores_due(
  p_generated_at timestamptz default now(),
  p_max_users integer default 500,
  p_stale_after interval default interval '12 hours'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_generated_at timestamptz := coalesce(p_generated_at, now());
  v_max_users integer := greatest(coalesce(p_max_users, 500), 1);
  v_stale_after interval := coalesce(p_stale_after, interval '12 hours');
  v_user record;
  v_count integer := 0;
begin
  for v_user in
    with recent_activity as (
      select
        activity.user_id,
        max(activity.activity_at) as last_activity_at
      from (
        select
          ledger.user_id,
          coalesce(ledger.tx_datetime, ledger.created_at) as activity_at
        from public.momo_ledger_entries as ledger
        where ledger.ledger_status = 'posted'
          and coalesce(ledger.tx_datetime, ledger.created_at) >= v_generated_at - interval '190 days'

        union all

        select
          contribution.user_id,
          contribution.created_at as activity_at
        from public.group_contributions as contribution
        where contribution.status = 'confirmed'
          and contribution.created_at >= v_generated_at - interval '190 days'
      ) as activity
      where activity.user_id is not null
      group by activity.user_id
    ),
    latest_runs as (
      select distinct on (run.user_id)
        run.user_id,
        run.generated_at
      from public.credit_score_runs as run
      order by run.user_id, run.generated_at desc
    )
    select
      recent_activity.user_id
    from recent_activity
    left join latest_runs
      on latest_runs.user_id = recent_activity.user_id
    where latest_runs.generated_at is null
      or latest_runs.generated_at < greatest(
        recent_activity.last_activity_at,
        v_generated_at - v_stale_after
      )
    order by
      coalesce(latest_runs.generated_at, timestamptz 'epoch') asc,
      recent_activity.last_activity_at desc
    limit v_max_users
  loop
    if public.recompute_credit_score(v_user.user_id, v_generated_at) is not null then
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

-- pg_cron setup — idempotent; may already exist on managed Supabase.
do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;
  grant usage on schema cron to postgres;
  grant all privileges on all tables in schema cron to postgres;
exception when others then
  raise notice 'pg_cron setup skipped: %', sqlerrm;
end;
$$;

select cron.unschedule(jobid)
from cron.job
where jobname = 'refresh-credit-scores-hourly';

select cron.schedule(
  'refresh-credit-scores-hourly',
  '13 * * * *',
  $$
  select public.refresh_credit_scores_due(now(), 500, interval '12 hours');
  $$
)
where not exists (
  select 1
  from cron.job
  where jobname = 'refresh-credit-scores-hourly'
);
