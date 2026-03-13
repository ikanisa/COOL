-- ==========================================================================
-- Cool App - Payee ledgers and payee-route allocation support
-- ==========================================================================

alter table public.momo_ledger_entries
  add column if not exists payee_group_id uuid references public.groups(id) on delete set null,
  add column if not exists payee_partner_id uuid references public.partners(id) on delete set null;

create index if not exists idx_momo_ledger_entries_payee_group
  on public.momo_ledger_entries (
    payee_group_id,
    ledger_status,
    coalesce(tx_datetime, created_at) desc
  )
  where payee_group_id is not null;

create index if not exists idx_momo_ledger_entries_payee_partner
  on public.momo_ledger_entries (
    payee_partner_id,
    ledger_status,
    coalesce(tx_datetime, created_at) desc
  )
  where payee_partner_id is not null;

update public.momo_ledger_entries as ledger
set payee_group_id = contribution.group_id
from public.group_contributions as contribution
where ledger.target_table = 'group_contributions'
  and ledger.target_record_id = contribution.id
  and ledger.payee_group_id is null;

update public.momo_ledger_entries as ledger
set payee_partner_id = route.partner_id
from public.partner_payment_routes as route
where ledger.target_table = 'partner_payment_routes'
  and ledger.target_record_id = route.id
  and ledger.payee_partner_id is null;

update public.momo_ledger_entries as ledger
set payee_partner_id = matched.partner_id
from public.rs_tickets as ticket
join public.rs_matches as matched
  on matched.id = ticket.match_id
where ledger.target_table = 'rs_tickets'
  and ledger.target_record_id = ticket.id
  and ledger.payee_partner_id is null;

update public.momo_ledger_entries as ledger
set payee_partner_id = initiative.partner_id
from public.rs_initiative_contributions as contribution
join public.rs_initiatives as initiative
  on initiative.id = contribution.initiative_id
where ledger.target_table = 'rs_initiative_contributions'
  and ledger.target_record_id = contribution.id
  and ledger.payee_partner_id is null;

update public.momo_ledger_entries as ledger
set payee_partner_id = nullif(ledger.metadata ->> 'partner_id', '')::uuid
where ledger.payee_partner_id is null
  and nullif(ledger.metadata ->> 'partner_id', '') is not null;

create or replace function public.can_read_group_payment_ledger(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin_user()
    or exists (
      select 1
      from public.groups g
      where g.id = p_group_id
        and g.creator_id = auth.uid()
    )
    or exists (
      select 1
      from public.group_members gm
      where gm.group_id = p_group_id
        and gm.user_id = auth.uid()
        and gm.is_admin = true
    );
$$;

revoke all on function public.can_read_group_payment_ledger(uuid) from public;
grant execute on function public.can_read_group_payment_ledger(uuid)
  to authenticated, service_role;

create or replace function public.can_read_partner_payment_ledger(
  p_partner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin_user()
    or public.rs_is_partner_admin(p_partner_id);
$$;

revoke all on function public.can_read_partner_payment_ledger(uuid) from public;
grant execute on function public.can_read_partner_payment_ledger(uuid)
  to authenticated, service_role;

create or replace function public.get_group_payment_ledger_entries(
  p_group_id uuid,
  p_start_at timestamptz default null,
  p_end_before timestamptz default null,
  p_payer_user_id uuid default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  ledger_id uuid,
  payer_user_id uuid,
  payer_name text,
  payer_phone text,
  amount integer,
  currency text,
  tx_datetime timestamptz,
  external_reference text,
  tx_category text,
  cashflow_bucket text,
  statement_label text,
  counterparty_name text,
  target_table text,
  target_record_id uuid,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;

  if auth.uid() is null or not public.can_read_group_payment_ledger(p_group_id) then
    raise exception 'Not authorized to view this group payment ledger.';
  end if;

  return query
  with ledger_rows as (
    select
      ledger.id as ledger_id,
      ledger.user_id as payer_user_id,
      coalesce(
        nullif(trim(payer.full_name), ''),
        nullif(trim(payer.official_name), ''),
        'Member'
      ) as payer_name,
      nullif(trim(coalesce(payer.official_phone, payer.phone)), '') as payer_phone,
      ledger.amount,
      ledger.currency,
      coalesce(ledger.tx_datetime, ledger.created_at) as tx_datetime,
      ledger.external_reference,
      ledger.tx_category,
      ledger.cashflow_bucket,
      ledger.statement_label,
      ledger.counterparty_name,
      ledger.target_table,
      ledger.target_record_id
    from public.momo_ledger_entries as ledger
    left join public.users as payer
      on payer.id = ledger.user_id
    where ledger.payee_group_id = p_group_id
      and ledger.ledger_status = 'posted'
      and (p_start_at is null or coalesce(ledger.tx_datetime, ledger.created_at) >= p_start_at)
      and (p_end_before is null or coalesce(ledger.tx_datetime, ledger.created_at) < p_end_before)
      and (p_payer_user_id is null or ledger.user_id = p_payer_user_id)
  )
  select
    row.ledger_id,
    row.payer_user_id,
    row.payer_name,
    row.payer_phone,
    row.amount,
    row.currency,
    row.tx_datetime,
    row.external_reference,
    row.tx_category,
    row.cashflow_bucket,
    row.statement_label,
    row.counterparty_name,
    row.target_table,
    row.target_record_id,
    count(*) over() as total_count
  from ledger_rows as row
  order by row.tx_datetime desc, row.ledger_id desc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_group_payment_ledger_entries(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  integer,
  integer
) from public;

grant execute on function public.get_group_payment_ledger_entries(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  integer,
  integer
) to authenticated, service_role;

create or replace function public.get_partner_payment_ledger_entries(
  p_partner_id uuid,
  p_start_at timestamptz default null,
  p_end_before timestamptz default null,
  p_payer_user_id uuid default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  ledger_id uuid,
  payer_user_id uuid,
  payer_name text,
  payer_phone text,
  amount integer,
  currency text,
  tx_datetime timestamptz,
  external_reference text,
  tx_category text,
  cashflow_bucket text,
  statement_label text,
  counterparty_name text,
  target_table text,
  target_record_id uuid,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_partner_id is null then
    raise exception 'Partner id is required.';
  end if;

  if auth.uid() is null or not public.can_read_partner_payment_ledger(p_partner_id) then
    raise exception 'Not authorized to view this partner payment ledger.';
  end if;

  return query
  with ledger_rows as (
    select
      ledger.id as ledger_id,
      ledger.user_id as payer_user_id,
      coalesce(
        nullif(trim(payer.full_name), ''),
        nullif(trim(payer.official_name), ''),
        'Member'
      ) as payer_name,
      nullif(trim(coalesce(payer.official_phone, payer.phone)), '') as payer_phone,
      ledger.amount,
      ledger.currency,
      coalesce(ledger.tx_datetime, ledger.created_at) as tx_datetime,
      ledger.external_reference,
      ledger.tx_category,
      ledger.cashflow_bucket,
      ledger.statement_label,
      ledger.counterparty_name,
      ledger.target_table,
      ledger.target_record_id
    from public.momo_ledger_entries as ledger
    left join public.users as payer
      on payer.id = ledger.user_id
    where ledger.payee_partner_id = p_partner_id
      and ledger.ledger_status = 'posted'
      and (p_start_at is null or coalesce(ledger.tx_datetime, ledger.created_at) >= p_start_at)
      and (p_end_before is null or coalesce(ledger.tx_datetime, ledger.created_at) < p_end_before)
      and (p_payer_user_id is null or ledger.user_id = p_payer_user_id)
  )
  select
    row.ledger_id,
    row.payer_user_id,
    row.payer_name,
    row.payer_phone,
    row.amount,
    row.currency,
    row.tx_datetime,
    row.external_reference,
    row.tx_category,
    row.cashflow_bucket,
    row.statement_label,
    row.counterparty_name,
    row.target_table,
    row.target_record_id,
    count(*) over() as total_count
  from ledger_rows as row
  order by row.tx_datetime desc, row.ledger_id desc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_partner_payment_ledger_entries(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  integer,
  integer
) from public;

grant execute on function public.get_partner_payment_ledger_entries(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  integer,
  integer
) to authenticated, service_role;
