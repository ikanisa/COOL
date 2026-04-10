-- ============================================================================
-- Cool App - group access capabilities, member-safe transaction feed, settings
-- ============================================================================

create or replace function public.can_view_group_transaction_feed(
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
    or public.is_group_member(p_group_id)
    or exists (
      select 1
      from public.partners p
      where public.bank_is_partner_admin(p.id)
        and public.group_belongs_to_bank_partner(p_group_id, p.id)
    );
$$;

revoke all on function public.can_view_group_transaction_feed(uuid) from public;
grant execute on function public.can_view_group_transaction_feed(uuid)
  to authenticated, service_role;

create or replace function public.can_manage_group_settings(
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

revoke all on function public.can_manage_group_settings(uuid) from public;
grant execute on function public.can_manage_group_settings(uuid)
  to authenticated, service_role;

create or replace function public.can_export_group_payment_ledger(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.can_manage_group_settings(p_group_id)
    or exists (
      select 1
      from public.partners p
      where public.bank_is_partner_admin(p.id)
        and public.group_belongs_to_bank_partner(p_group_id, p.id)
    );
$$;

revoke all on function public.can_export_group_payment_ledger(uuid) from public;
grant execute on function public.can_export_group_payment_ledger(uuid)
  to authenticated, service_role;

create or replace function public.get_group_access_snapshot(
  p_group_id uuid
)
returns table (
  group_id uuid,
  is_member boolean,
  is_creator boolean,
  is_group_admin boolean,
  is_bank_custody_admin boolean,
  can_view_transactions boolean,
  can_manage_settings boolean,
  can_export_ledger boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with viewer_scope as (
    select g.id
    from public.groups g
    where g.id = p_group_id
      and (
        g.visibility = 'public'
        or g.creator_id = auth.uid()
        or public.is_group_member(g.id)
        or public.is_admin_user()
        or exists (
          select 1
          from public.partners p
          where public.bank_is_partner_admin(p.id)
            and public.group_belongs_to_bank_partner(g.id, p.id)
        )
      )
  )
  select
    scope.id as group_id,
    public.is_group_member(scope.id) as is_member,
    exists (
      select 1
      from public.groups g
      where g.id = scope.id
        and g.creator_id = auth.uid()
    ) as is_creator,
    exists (
      select 1
      from public.group_members gm
      where gm.group_id = scope.id
        and gm.user_id = auth.uid()
        and gm.is_admin = true
    ) as is_group_admin,
    exists (
      select 1
      from public.partners p
      where public.bank_is_partner_admin(p.id)
        and public.group_belongs_to_bank_partner(scope.id, p.id)
    ) as is_bank_custody_admin,
    public.can_view_group_transaction_feed(scope.id) as can_view_transactions,
    public.can_manage_group_settings(scope.id) as can_manage_settings,
    public.can_export_group_payment_ledger(scope.id) as can_export_ledger
  from viewer_scope scope;
$$;

revoke all on function public.get_group_access_snapshot(uuid) from public;
grant execute on function public.get_group_access_snapshot(uuid)
  to authenticated, service_role;

create or replace function public.get_group_transaction_feed_entries(
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

  if auth.uid() is null or not public.can_view_group_transaction_feed(p_group_id) then
    raise exception 'Not authorized to view this group transaction feed.';
  end if;

  return query
  with ledger_rows as (
    select
      ledger.id as ledger_id,
      ledger.user_id as payer_user_id,
      coalesce(
        case
          when coalesce(member.is_anonymous, false) then null
          else nullif(trim(member.display_name), '')
        end,
        case
          when coalesce(member.is_anonymous, false) then null
          else nullif(trim(payer.public_user_id), '')
        end,
        case
          when coalesce(member.is_anonymous, false) then null
          else nullif(trim(payer.full_name), '')
        end,
        'Member'
      ) as payer_name,
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
    left join public.group_members as member
      on member.group_id = p_group_id
      and member.user_id = ledger.user_id
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

revoke all on function public.get_group_transaction_feed_entries(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  integer,
  integer
) from public;
grant execute on function public.get_group_transaction_feed_entries(
  uuid,
  timestamptz,
  timestamptz,
  uuid,
  integer,
  integer
) to authenticated, service_role;

create or replace function public.update_group_savings_settings(
  p_group_id uuid,
  p_name text default null,
  p_description text default null,
  p_target_amount integer default null,
  p_monthly_contribution integer default null,
  p_frequency text default null,
  p_receiving_momo_route_type text default null,
  p_recipient_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.groups%rowtype;
  v_name text;
  v_description text;
  v_frequency text;
  v_route_type text;
  v_recipient text;
begin
  if p_group_id is null then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Group id is required.'
    );
  end if;

  if auth.uid() is null or not public.can_manage_group_settings(p_group_id) then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Not authorized to update this group.'
    );
  end if;

  select *
    into v_group
    from public.groups
   where id = p_group_id
   for update;

  if not found then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Group not found.'
    );
  end if;

  if p_target_amount is not null and p_target_amount < 0 then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Target amount must be zero or greater.'
    );
  end if;

  if p_monthly_contribution is not null and p_monthly_contribution < 0 then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Contribution amount must be zero or greater.'
    );
  end if;

  v_name := nullif(btrim(coalesce(p_name, v_group.name)), '');
  if v_name is null then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Group name is required.'
    );
  end if;

  v_description := case
    when p_description is null then v_group.description
    else nullif(btrim(p_description), '')
  end;

  v_frequency := case
    when p_frequency is null then v_group.frequency
    else nullif(lower(btrim(p_frequency)), '')
  end;

  if v_frequency is not null
     and v_frequency not in ('daily', 'weekly', 'monthly', 'one_off') then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Unsupported frequency.'
    );
  end if;

  v_route_type := case
    when p_receiving_momo_route_type is null then v_group.receiving_momo_route_type
    else nullif(lower(btrim(p_receiving_momo_route_type)), '')
  end;

  if v_route_type is not null and v_route_type not in ('phone_number', 'code') then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Unsupported receiving_momo_route_type.'
    );
  end if;

  v_recipient := case
    when p_recipient_value is null then
      coalesce(
        nullif(btrim(coalesce(v_group.receiving_momo_code, '')), ''),
        nullif(btrim(coalesce(v_group.momo_number, '')), '')
      )
    else
      nullif(btrim(p_recipient_value), '')
  end;

  update public.groups
     set name = v_name,
         description = v_description,
         target_amount = coalesce(p_target_amount, target_amount),
         monthly_contribution = coalesce(p_monthly_contribution, monthly_contribution),
         frequency = coalesce(v_frequency, frequency),
         receiving_momo_route_type = v_route_type,
         receiving_momo_code = case
           when v_route_type = 'code' then v_recipient
           when v_route_type = 'phone_number' then null
           else receiving_momo_code
         end,
         momo_number = case
           when v_route_type = 'phone_number' then v_recipient
           when v_route_type = 'code' then null
           else momo_number
         end,
         updated_at = now()
   where id = p_group_id
   returning * into v_group;

  return jsonb_build_object(
    'status', 'success',
    'group_id', v_group.id::text
  );
end;
$$;

revoke all on function public.update_group_savings_settings(
  uuid,
  text,
  text,
  integer,
  integer,
  text,
  text,
  text
) from public;
grant execute on function public.update_group_savings_settings(
  uuid,
  text,
  text,
  integer,
  integer,
  text,
  text,
  text
) to authenticated, service_role;
