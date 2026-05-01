-- ============================================================================
-- Public function lint hardening and admin RPC schema alignment
-- ============================================================================
-- Repairs remaining pg_lint / plpgsql_check failures on production RPCs after
-- the BioPay lint repair. Active admin/group/MoMo functions are preserved and
-- pointed at the live schema. Stale Rayon and gamification RPCs are removed
-- because their product surfaces and backing tables were already purged.
-- ============================================================================

-- The admin savings surfaces expect explicit lifecycle fields. Earlier repair
-- migrations removed references to these columns because they were missing;
-- restoring them is additive and preserves the intended close/reactivate flow.
alter table public.groups
  add column if not exists is_active boolean not null default true;

alter table public.groups
  add column if not exists is_closed boolean not null default false;

alter table public.groups
  alter column is_active set default true,
  alter column is_closed set default false;

comment on column public.groups.is_active is
  'Operational lifecycle flag used by admin savings and group oversight surfaces.';

comment on column public.groups.is_closed is
  'Marks groups closed to new operational activity without deleting historical data.';

create index if not exists idx_groups_savings_lifecycle
  on public.groups (type, is_active, is_closed);

alter table public.group_contributions
  add column if not exists notes text;

comment on column public.group_contributions.notes is
  'Optional admin/operator note captured during manual contribution allocation.';

-- --------------------------------------------------------------------------
-- Savings/admin group RPCs
-- --------------------------------------------------------------------------

create or replace function public.admin_create_savings_group(
  p_name text,
  p_description text default null,
  p_target_amount integer default 0,
  p_monthly_contribution integer default null,
  p_frequency text default 'monthly'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_group_id uuid;
  v_invite_code text;
  v_momo_code text;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'Group name is required.';
  end if;

  select ac.value
  into v_momo_code
  from public.app_config ac
  where ac.key = 'savings_momo_code'
  limit 1;

  v_invite_code := public.generate_invite_code();

  insert into public.groups (
    creator_id,
    name,
    description,
    type,
    visibility,
    amount,
    target_amount,
    monthly_contribution,
    frequency,
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    invite_code,
    country,
    is_active,
    is_closed
  ) values (
    auth.uid(),
    btrim(p_name),
    nullif(btrim(coalesce(p_description, '')), ''),
    'saving',
    'private',
    0,
    coalesce(p_target_amount, 0),
    p_monthly_contribution,
    coalesce(nullif(btrim(p_frequency), ''), 'monthly'),
    v_momo_code,
    v_momo_code,
    'code',
    v_invite_code,
    'RW',
    true,
    false
  )
  returning id into v_group_id;

  insert into public.admin_audit_log (
    actor_id,
    action,
    target_table,
    target_id,
    new_data,
    notes
  ) values (
    auth.uid(),
    'admin_create_savings_group',
    'groups',
    v_group_id::text,
    jsonb_build_object(
      'name', btrim(p_name),
      'target_amount', coalesce(p_target_amount, 0),
      'monthly_contribution', p_monthly_contribution,
      'frequency', coalesce(nullif(btrim(p_frequency), ''), 'monthly')
    ),
    'Savings group created from admin RPC.'
  );

  return jsonb_build_object(
    'status', 'success',
    'group_id', v_group_id,
    'invite_code', v_invite_code
  );
end;
$$;

revoke all on function public.admin_create_savings_group(text, text, integer, integer, text)
  from public;
grant execute on function public.admin_create_savings_group(text, text, integer, integer, text)
  to authenticated;

comment on function public.admin_create_savings_group(text, text, integer, integer, text) is
  'Creates a savings group with centralized MoMo routing and audit logging. Platform admin only.';

create or replace function public.admin_update_savings_group(
  p_group_id uuid,
  p_name text default null,
  p_description text default null,
  p_target_amount integer default null,
  p_monthly_contribution integer default null,
  p_frequency text default null,
  p_is_closed boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_old public.groups%rowtype;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;

  select *
  into v_old
  from public.groups g
  where g.id = p_group_id
    and g.type = 'saving'
  for update;

  if not found then
    raise exception 'Savings group not found.';
  end if;

  update public.groups g
  set
    name = coalesce(nullif(btrim(p_name), ''), g.name),
    description = case
      when p_description is not null then nullif(btrim(p_description), '')
      else g.description
    end,
    target_amount = coalesce(p_target_amount, g.target_amount),
    monthly_contribution = case
      when p_monthly_contribution is not null then p_monthly_contribution
      else g.monthly_contribution
    end,
    frequency = coalesce(nullif(btrim(p_frequency), ''), g.frequency),
    is_closed = coalesce(p_is_closed, g.is_closed),
    is_active = case
      when p_is_closed is true then false
      when p_is_closed is false then true
      else g.is_active
    end,
    updated_at = now()
  where g.id = p_group_id;

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
    auth.uid(),
    'admin_update_savings_group',
    'groups',
    p_group_id::text,
    to_jsonb(v_old),
    to_jsonb(g),
    'Savings group updated from admin RPC.'
  from public.groups g
  where g.id = p_group_id;

  return jsonb_build_object(
    'status', 'success',
    'group_id', p_group_id
  );
end;
$$;

revoke all on function public.admin_update_savings_group(uuid, text, text, integer, integer, text, boolean)
  from public;
grant execute on function public.admin_update_savings_group(uuid, text, text, integer, integer, text, boolean)
  to authenticated;

comment on function public.admin_update_savings_group(uuid, text, text, integer, integer, text, boolean) is
  'Updates savings group fields and lifecycle flags with admin audit logging.';

create or replace function public.admin_allocate_savings_contribution(
  p_group_id uuid,
  p_member_user_id uuid,
  p_amount integer,
  p_reference text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_contribution_id uuid;
  v_reference text;
  v_note text;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  if p_group_id is null or p_member_user_id is null then
    raise exception 'Group id and member user id are required.';
  end if;

  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Amount must be greater than zero.';
  end if;

  if not exists (
    select 1
    from public.groups g
    where g.id = p_group_id
      and g.type = 'saving'
      and g.is_closed = false
  ) then
    raise exception 'Open savings group not found.';
  end if;

  if not exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_member_user_id
  ) then
    raise exception 'User is not a member of this savings group.';
  end if;

  v_reference := coalesce(
    nullif(btrim(p_reference), ''),
    format('ADMIN-%s', gen_random_uuid())
  );
  v_note := coalesce(nullif(btrim(p_note), ''), 'Admin manual allocation');

  insert into public.group_contributions (
    group_id,
    user_id,
    amount,
    status,
    momo_reference,
    notes,
    created_at
  ) values (
    p_group_id,
    p_member_user_id,
    p_amount,
    'confirmed',
    v_reference,
    v_note,
    now()
  )
  returning id into v_contribution_id;

  insert into public.admin_audit_log (
    actor_id,
    action,
    target_table,
    target_id,
    new_data,
    notes
  ) values (
    auth.uid(),
    'admin_allocate_savings_contribution',
    'group_contributions',
    v_contribution_id::text,
    jsonb_build_object(
      'group_id', p_group_id,
      'member_user_id', p_member_user_id,
      'amount', p_amount,
      'reference', v_reference
    ),
    v_note
  );

  return jsonb_build_object(
    'status', 'success',
    'contribution_id', v_contribution_id,
    'group_id', p_group_id,
    'user_id', p_member_user_id,
    'amount', p_amount,
    'reference', v_reference
  );
end;
$$;

revoke all on function public.admin_allocate_savings_contribution(uuid, uuid, integer, text, text)
  from public;
grant execute on function public.admin_allocate_savings_contribution(uuid, uuid, integer, text, text)
  to authenticated;

comment on function public.admin_allocate_savings_contribution(uuid, uuid, integer, text, text) is
  'Manually allocates a savings contribution for a member with audit logging. Platform admin only.';

create or replace function public.admin_get_savings_groups_detail()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_result jsonb;
  v_momo_code text;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  select ac.value
  into v_momo_code
  from public.app_config ac
  where ac.key = 'savings_momo_code'
  limit 1;

  select jsonb_build_object(
    'savings_momo_code', coalesce(v_momo_code, ''),
    'total_savings_groups', (
      select count(*) from public.groups g where g.type = 'saving'
    ),
    'active_savings_groups', (
      select count(*)
      from public.groups g
      where g.type = 'saving'
        and g.is_active = true
        and g.is_closed = false
    ),
    'total_community_groups', (
      select count(*) from public.groups g where g.type = 'community'
    ),
    'total_members_in_savings', (
      select count(*)
      from public.group_members gm
      join public.groups g on g.id = gm.group_id
      where g.type = 'saving'
    ),
    'total_collected', (
      select coalesce(sum(gc.amount), 0)
      from public.group_contributions gc
      join public.groups g on g.id = gc.group_id
      where g.type = 'saving'
        and gc.status = 'confirmed'
    ),
    'savings_groups', coalesce((
      select jsonb_agg(sg order by sg->>'created_at' desc)
      from (
        select jsonb_build_object(
          'id', g.id,
          'name', g.name,
          'description', g.description,
          'target_amount', g.target_amount,
          'monthly_contribution', g.monthly_contribution,
          'frequency', g.frequency,
          'momo_number', g.momo_number,
          'invite_code', g.invite_code,
          'creator_id', g.creator_id,
          'is_closed', g.is_closed,
          'is_active', g.is_active,
          'created_at', g.created_at,
          'member_count', coalesce(mc.cnt, 0),
          'total_collected', coalesce(tc.total, 0),
          'members', coalesce((
            select jsonb_agg(jsonb_build_object(
              'user_id', gm.user_id,
              'display_name', gm.display_name,
              'phone', u.phone,
              'joined_at', gm.joined_at
            ) order by gm.joined_at asc)
            from public.group_members gm
            left join public.users u on u.id = gm.user_id
            where gm.group_id = g.id
          ), '[]'::jsonb)
        ) as sg
        from public.groups g
        left join lateral (
          select count(*) as cnt
          from public.group_members m
          where m.group_id = g.id
        ) mc on true
        left join lateral (
          select coalesce(sum(c.amount), 0) as total
          from public.group_contributions c
          where c.group_id = g.id
            and c.status = 'confirmed'
        ) tc on true
        where g.type = 'saving'
      ) sub
    ), '[]'::jsonb),
    'community_groups', coalesce((
      select jsonb_agg(cg order by cg->>'created_at' desc)
      from (
        select jsonb_build_object(
          'id', g.id,
          'name', g.name,
          'description', g.description,
          'visibility', g.visibility,
          'creator_id', g.creator_id,
          'is_closed', g.is_closed,
          'is_active', g.is_active,
          'created_at', g.created_at,
          'member_count', coalesce(mc.cnt, 0)
        ) as cg
        from public.groups g
        left join lateral (
          select count(*) as cnt
          from public.group_members m
          where m.group_id = g.id
        ) mc on true
        where g.type = 'community'
      ) sub
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_get_savings_groups_detail()
  from public;
grant execute on function public.admin_get_savings_groups_detail()
  to authenticated;

comment on function public.admin_get_savings_groups_detail() is
  'Returns detailed savings and community group data for admin management. Platform admin only.';

create or replace function public.get_admin_groups_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  select jsonb_build_object(
    'total_groups', (
      select count(*) from public.groups
    ),
    'active_groups', (
      select count(*)
      from public.groups g
      where g.is_active = true
        and g.is_closed = false
    ),
    'closed_groups', (
      select count(*) from public.groups g where g.is_closed = true
    ),
    'public_groups', (
      select count(*) from public.groups g where g.visibility = 'public'
    ),
    'private_groups', (
      select count(*) from public.groups g where g.visibility = 'private'
    ),
    'total_members', (
      select count(*) from public.group_members
    ),
    'total_wallets', 0,
    'groups', coalesce((
      select jsonb_agg(g_row order by g_row->>'created_at' desc)
      from (
        select jsonb_build_object(
          'id', g.id,
          'name', g.name,
          'type', g.type,
          'status', case
            when g.is_closed then 'closed'
            when g.is_active then 'active'
            else 'inactive'
          end,
          'visibility', g.visibility,
          'country', g.country,
          'target_amount', g.target_amount,
          'monthly_contribution', g.monthly_contribution,
          'momo_number', g.momo_number,
          'invite_code', g.invite_code,
          'creator_id', g.creator_id,
          'created_at', g.created_at,
          'member_count', coalesce(mc.cnt, 0),
          'wallet_count', 0,
          'is_active', g.is_active,
          'is_closed', g.is_closed
        ) as g_row
        from public.groups g
        left join lateral (
          select count(*) as cnt
          from public.group_members m
          where m.group_id = g.id
        ) mc on true
      ) sub
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_admin_groups_summary()
  from public;
grant execute on function public.get_admin_groups_summary()
  to authenticated;

comment on function public.get_admin_groups_summary() is
  'Returns admin overview of live public.groups data with member counts. Platform admin only.';

-- --------------------------------------------------------------------------
-- MoMo manual review and allocation RPCs
-- --------------------------------------------------------------------------

create or replace function public.admin_reject_momo_sms_manual_review_batch(
  p_review_ids uuid[],
  p_note text default null
)
returns table (
  rejected_count integer
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_now timestamptz := now();
  v_note text;
begin
  if coalesce(array_length(p_review_ids, 1), 0) = 0 then
    return query select 0::integer;
    return;
  end if;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Review rejected because it does not map to an app payment target.'
  );

  return query
  with input_ids as (
    select distinct rid as review_id
    from unnest(p_review_ids) as rid
    where rid is not null
  ),
  eligible_reviews as (
    select mr.id, mr.parsed_sms_id
    from public.momo_reconciliations mr
    join input_ids ids
      on ids.review_id = mr.id
    join public.momo_sms_parsed parsed
      on parsed.id = mr.parsed_sms_id
    left join public.payment_receiver_accounts pra
      on pra.payee_number_or_code = parsed.payee_number_or_code
    where mr.match_status in ('pending_review', 'manual_review')
      and (
        public.is_admin_user()
        or pra.owner_user_id = auth.uid()
      )
    for update of mr
  ),
  updated_reviews as (
    update public.momo_reconciliations mr
    set
      target_table = null,
      target_record_id = null,
      match_type = 'manual_rejection',
      match_status = 'rejected',
      notes = v_note,
      metadata = coalesce(mr.metadata, '{}'::jsonb) || jsonb_build_object(
        'manual_rejection', true,
        'manual_rejection_actor_id', auth.uid(),
        'manual_rejection_source', 'custodian_operations',
        'manual_rejection_reason', 'not_app_linked',
        'rejected_at', v_now
      ),
      reconciled_at = null,
      updated_at = v_now
    from eligible_reviews er
    where mr.id = er.id
    returning mr.id, er.parsed_sms_id
  ),
  updated_ledgers as (
    update public.momo_ledger_entries le
    set
      target_table = null,
      target_record_id = null,
      ledger_status = 'draft',
      metadata = coalesce(le.metadata, '{}'::jsonb) || jsonb_build_object(
        'manual_rejection', true,
        'manual_rejection_actor_id', auth.uid(),
        'manual_rejection_source', 'custodian_operations',
        'manual_rejection_reason', 'not_app_linked',
        'rejected_at', v_now
      ),
      updated_at = v_now
    from updated_reviews ur
    where le.parsed_sms_id = ur.parsed_sms_id
    returning le.id
  )
  select count(*)::integer
  from updated_reviews;
end;
$$;

revoke all on function public.admin_reject_momo_sms_manual_review_batch(uuid[], text)
  from public;
grant execute on function public.admin_reject_momo_sms_manual_review_batch(uuid[], text)
  to authenticated;

comment on function public.admin_reject_momo_sms_manual_review_batch(uuid[], text) is
  'Rejects pending/manual MoMo SMS reviews in bulk while locking only reconciliation rows.';

create or replace function public.allocate_momo_manual_review(
  p_review_id uuid,
  p_intent_id uuid,
  p_note text default null
)
returns table (
  review_id uuid,
  intent_id uuid,
  matched_reference text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_review public.momo_reconciliations%rowtype;
  v_intent public.payment_intents%rowtype;
  v_intent_type text;
  v_amount numeric;
  v_currency text;
  v_tx_datetime timestamptz;
  v_parsed_reference text;
  v_reference text;
  v_note text;
  v_user_id uuid;
  v_now timestamptz := now();
begin
  if p_review_id is null then
    raise exception 'Review id is required.';
  end if;

  if p_intent_id is null then
    raise exception 'Intent id is required.';
  end if;

  if not public.is_admin_user() then
    raise exception 'Admin privileges required to execute generalized manual allocation.';
  end if;

  select *
  into v_review
  from public.momo_reconciliations mr
  where mr.id = p_review_id
  for update;

  if not found then
    raise exception 'Manual review allocation was not found.';
  end if;

  if v_review.match_status not in ('pending_review', 'manual_review') then
    raise exception 'Only pending or manual-review allocations can be resolved.';
  end if;

  select
    parsed.amount,
    parsed.currency,
    coalesce(parsed.tx_datetime, parsed.created_at),
    nullif(parsed.momo_tx_id, ''),
    parsed.user_id
  into
    v_amount,
    v_currency,
    v_tx_datetime,
    v_parsed_reference,
    v_user_id
  from public.momo_sms_parsed parsed
  where parsed.id = v_review.parsed_sms_id;

  if coalesce(v_amount, 0) <= 0 then
    raise exception 'The reviewed payment does not have a usable amount.';
  end if;

  select *
  into v_intent
  from public.payment_intents pi
  where pi.id = p_intent_id
  for update;

  if not found then
    raise exception 'Payment intent was not found.';
  end if;

  if v_intent.status <> 'pending' then
    raise exception 'Only pending payment intents can be allocated to.';
  end if;

  if v_intent.expected_amount <> v_amount then
    raise exception 'Payment intent expected amount (%) does not match SMS amount (%).',
      v_intent.expected_amount,
      v_amount;
  end if;

  v_intent_type := coalesce(
    nullif(v_intent.metadata ->> 'intent_type', ''),
    nullif(v_intent.metadata ->> 'type', ''),
    nullif(v_intent.target_table, ''),
    'intent'
  );

  v_reference := coalesce(
    v_parsed_reference,
    format('MR-%s', v_review.id)
  );

  update public.payment_intents pi
  set
    status = 'completed',
    updated_at = v_now
  where pi.id = v_intent.id;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Admin manually allocated this payment.'
  );

  update public.momo_reconciliations mr
  set
    target_table = coalesce(v_intent.target_table, 'payment_intents'),
    target_record_id = coalesce(v_intent.target_record_id, v_intent.id),
    match_type = format('admin_manual_allocation_to_%s', v_intent_type),
    match_status = 'matched',
    notes = v_note,
    metadata = coalesce(mr.metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_allocation', true,
      'intent_id', p_intent_id,
      'matched_reference', v_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations',
      'intent_type', v_intent_type
    ),
    reconciled_at = v_now,
    updated_at = v_now
  where mr.id = v_review.id;

  insert into public.momo_ledger_entries (
    parsed_sms_id,
    user_id,
    entry_type,
    ledger_scope,
    ledger_status,
    amount,
    currency,
    tx_datetime,
    external_reference,
    target_table,
    target_record_id,
    description,
    metadata,
    created_at,
    updated_at
  ) values (
    v_review.parsed_sms_id,
    v_user_id,
    case when coalesce(v_amount, 0) >= 0 then 'credit' else 'debit' end,
    case
      when v_intent_type in ('group_contribution', 'group_contributions')
        or v_intent.target_table = 'group_contributions' then 'group'
      when v_intent_type in ('subscription', 'subscriptions') then 'subscription'
      when v_intent_type in ('shop_order', 'shop_orders', 'partner_order', 'rs_shop_orders')
        or v_intent.target_table in ('shop_orders', 'partner_orders', 'rs_shop_orders') then 'partner'
      else 'wallet'
    end,
    'posted',
    v_amount,
    coalesce(v_currency, 'RWF'),
    coalesce(v_tx_datetime, v_now),
    v_reference,
    coalesce(v_intent.target_table, 'payment_intents'),
    coalesce(v_intent.target_record_id, v_intent.id),
    'Manual allocation via admin review',
    jsonb_build_object(
      'manual_allocation', true,
      'intent_id', p_intent_id,
      'matched_reference', v_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations',
      'intent_type', v_intent_type
    ),
    v_now,
    v_now
  )
  on conflict (parsed_sms_id) do update set
    target_table = excluded.target_table,
    target_record_id = excluded.target_record_id,
    ledger_status = 'posted',
    ledger_scope = excluded.ledger_scope,
    external_reference = coalesce(public.momo_ledger_entries.external_reference, excluded.external_reference),
    metadata = coalesce(public.momo_ledger_entries.metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_allocation', true,
      'intent_id', p_intent_id,
      'matched_reference', excluded.external_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations',
      'intent_type', v_intent_type
    ),
    updated_at = v_now;

  return query
  select
    v_review.id,
    v_intent.id,
    v_reference;
end;
$$;

revoke all on function public.allocate_momo_manual_review(uuid, uuid, text)
  from public;
grant execute on function public.allocate_momo_manual_review(uuid, uuid, text)
  to authenticated, service_role;

comment on function public.allocate_momo_manual_review(uuid, uuid, text) is
  'Admin-only operation to route a pending manual review SMS to a payment intent and post to the ledger.';

create or replace function public.allocate_transaction_to_member(
  p_ledger_id uuid,
  p_group_id uuid,
  p_member_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_caller_id uuid := auth.uid();
  v_is_group_admin boolean;
  v_is_bank_custody_admin boolean;
  v_member_exists boolean;
  v_now timestamptz := now();
begin
  if p_ledger_id is null then
    raise exception 'Ledger entry id is required.';
  end if;
  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;
  if p_member_user_id is null then
    raise exception 'Member user id is required.';
  end if;

  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_caller_id
      and gm.is_admin = true
  ) into v_is_group_admin;

  select exists (
    select 1
    from public.partners p
    where public.bank_is_partner_admin(p.id)
      and public.group_belongs_to_bank_partner(p_group_id, p.id)
  ) into v_is_bank_custody_admin;

  if not v_is_group_admin and not public.is_admin_user() and not v_is_bank_custody_admin then
    raise exception 'You must be a group admin, bank custody admin, or platform admin to allocate transactions.';
  end if;

  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_member_user_id
  ) into v_member_exists;

  if not v_member_exists then
    raise exception 'The target member is not in this group.';
  end if;

  perform 1
  from public.momo_ledger_entries le
  where le.id = p_ledger_id
  for update;

  if not found then
    raise exception 'Ledger entry not found.';
  end if;

  update public.momo_ledger_entries le
  set
    target_table = 'group_contributions',
    target_record_id = p_group_id,
    user_id = p_member_user_id,
    ledger_scope = 'group',
    ledger_status = 'posted',
    metadata = coalesce(le.metadata, '{}'::jsonb) || jsonb_build_object(
      'group_allocation', true,
      'allocated_group_id', p_group_id,
      'allocated_member_id', p_member_user_id,
      'allocation_actor_id', v_caller_id,
      'allocation_source',
        case
          when v_is_bank_custody_admin then 'bank_admin'
          when v_is_group_admin then 'group_admin'
          else 'platform_admin'
        end,
      'allocated_at', v_now
    ),
    updated_at = v_now
  where le.id = p_ledger_id;

  return jsonb_build_object(
    'status', 'success',
    'ledger_id', p_ledger_id,
    'group_id', p_group_id,
    'member_user_id', p_member_user_id
  );
end;
$$;

revoke all on function public.allocate_transaction_to_member(uuid, uuid, uuid)
  from public;
grant execute on function public.allocate_transaction_to_member(uuid, uuid, uuid)
  to authenticated;

comment on function public.allocate_transaction_to_member(uuid, uuid, uuid) is
  'Assigns an existing MoMo ledger entry to a group member after scoped admin checks.';

-- --------------------------------------------------------------------------
-- General helpers and admin detail RPCs
-- --------------------------------------------------------------------------

create or replace function public.generate_invite_code()
returns text
language plpgsql
set search_path = public
as $$
declare
  v_code text;
  v_attempts integer := 0;
begin
  while v_attempts < 100 loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

    if not exists (
      select 1
      from public.groups g
      where g.invite_code = v_code
    ) then
      return v_code;
    end if;

    v_attempts := v_attempts + 1;
  end loop;

  raise exception 'Could not generate unique invite code after 100 attempts';
  return null;
end;
$$;

grant execute on function public.generate_invite_code()
  to authenticated, service_role;

comment on function public.generate_invite_code() is
  'Generates a unique six-character invite code for public.groups.';

create or replace function public.get_user_detail_for_admin(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user public.users;
  v_result jsonb;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required.';
  end if;

  select *
  into v_user
  from public.users u
  where u.id = p_user_id;

  if not found then
    raise exception 'User not found: %', p_user_id;
  end if;

  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_user.id,
      'phone', v_user.phone,
      'full_name', v_user.full_name,
      'country', v_user.country,
      'language_code', v_user.language_code,
      'momo_number', v_user.momo_number,
      'is_admin', v_user.is_admin,
      'created_at', v_user.created_at,
      'updated_at', v_user.updated_at
    ),
    'groups', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'group_id', g.id,
        'group_name', g.name,
        'is_admin', gm.is_admin,
        'contribution_amount', gm.contribution_amount,
        'joined_at', gm.joined_at,
        'type', g.type,
        'member_count', g.member_count
      )), '[]'::jsonb)
      from public.group_members gm
      join public.groups g on g.id = gm.group_id
      where gm.user_id = p_user_id
    ),
    'contributions_30d', jsonb_build_object(
      'count', (
        select count(*)
        from public.group_contributions gc
        where gc.user_id = p_user_id
          and gc.created_at > now() - interval '30 days'
      ),
      'total_amount', (
        select coalesce(sum(gc.amount), 0)
        from public.group_contributions gc
        where gc.user_id = p_user_id
          and gc.status = 'confirmed'
          and gc.created_at > now() - interval '30 days'
      )
    ),
    'biopay', coalesce((
      select jsonb_build_object(
        'has_enrollment', true,
        'profile_id', bp.id,
        'public_id', bp.public_id,
        'active', bp.active,
        'route_type', bp.route_type,
        'created_at', bp.created_at,
        'revoked_at', bp.revoked_at
      )
      from public.biopay_profiles bp
      where bp.user_id = p_user_id
        and bp.deleted_at is null
      limit 1
    ), jsonb_build_object('has_enrollment', false)),
    'cool_status', jsonb_build_object(
      'total_points', 0,
      'tier', 'blue',
      'current_streak', 0,
      'longest_streak', 0,
      'season_points', 0
    ),
    'roles', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'role', ra.role,
        'partner_scope_id', ra.partner_scope_id,
        'is_active', ra.is_active,
        'granted_at', ra.granted_at
      )), '[]'::jsonb)
      from public.admin_role_assignments ra
      where ra.user_id = p_user_id
        and ra.is_active = true
    ),
    'sms_sync', jsonb_build_object(
      'total_ingested', (
        select count(*) from public.momo_sms_raw raw where raw.user_id = p_user_id
      ),
      'parsed_count', (
        select count(*) from public.momo_sms_parsed parsed where parsed.user_id = p_user_id
      ),
      'last_sync', (
        select max(raw.created_at) from public.momo_sms_raw raw where raw.user_id = p_user_id
      )
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_user_detail_for_admin(uuid)
  from public;
grant execute on function public.get_user_detail_for_admin(uuid)
  to authenticated;

comment on function public.get_user_detail_for_admin(uuid) is
  'Returns admin user detail from live tables; removed gamification tables report neutral status.';

-- --------------------------------------------------------------------------
-- Mock cleanup RPC
-- --------------------------------------------------------------------------

create or replace function public.purge_mock_batch(p_mock_batch text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_batch text := nullif(trim(p_mock_batch), '');
  v_auth_user_ids uuid[] := '{}'::uuid[];
  v_result jsonb := '{}'::jsonb;
  v_count integer := 0;
begin
  if v_batch is null then
    raise exception 'Mock batch is required.';
  end if;

  if not public.is_admin_user() then
    raise exception 'Only admins can purge mock data batches.';
  end if;

  select coalesce(array_agg(distinct candidates.user_id), '{}'::uuid[])
  into v_auth_user_ids
  from (
    select u.id as user_id
    from public.users u
    where u.mock_batch = v_batch
    union
    select au.id as user_id
    from auth.users au
    where coalesce(au.raw_user_meta_data ->> 'mock_batch', '') = v_batch
       or coalesce(au.raw_app_meta_data ->> 'mock_batch', '') = v_batch
  ) candidates;

  delete from public.momo_reconciliations mr
  where mr.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_reconciliations', v_count);

  delete from public.momo_ledger_entries le
  where le.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_ledger_entries', v_count);

  delete from public.momo_sms_parsed parsed
  where parsed.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_sms_parsed', v_count);

  delete from public.momo_sms_raw raw
  where raw.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_sms_raw', v_count);

  delete from public.group_contributions gc
  where gc.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('group_contributions', v_count);

  delete from public.group_members gm
  where gm.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('group_members', v_count);

  delete from public.groups g
  where g.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('groups', v_count);

  delete from public.rs_tickets ticket
  where ticket.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_tickets', v_count);

  delete from public.rs_shop_orders shop_order
  where shop_order.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_shop_orders', v_count);

  delete from public.rs_initiative_contributions initiative_contribution
  where initiative_contribution.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_initiative_contributions', v_count);

  delete from public.rs_achievements achievement
  where achievement.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_achievements', v_count);

  delete from public.rs_fan_club_members fan_club_member
  where fan_club_member.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_fan_club_members', v_count);

  delete from public.rs_fan_memberships fan_membership
  where fan_membership.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_fan_memberships', v_count);

  delete from public.rs_matches match_row
  where match_row.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_matches', v_count);

  delete from public.rs_shop_products product
  where product.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_shop_products', v_count);

  delete from public.nexus_opportunities opportunity
  where opportunity.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('nexus_opportunities', v_count);

  delete from public.partner_services service
  where service.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('partner_services', v_count);

  delete from public.partners partner
  where partner.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('partners', v_count);

  delete from public.season_memberships sm
  where sm.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('season_memberships', v_count);

  delete from public.season_definitions sd
  where sd.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('season_definitions', v_count);

  delete from public.users u
  where u.mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('users', v_count);

  delete from auth.users au
  where au.id = any(v_auth_user_ids);
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('auth_users', v_count);

  insert into public.admin_audit_log (
    actor_id,
    action,
    target_table,
    target_id,
    new_data,
    notes
  ) values (
    auth.uid(),
    'purge_mock_batch',
    'mock_batch',
    v_batch,
    jsonb_build_object('deleted', v_result),
    'Mock batch purged by admin RPC.'
  );

  return jsonb_build_object(
    'success', true,
    'mock_batch', v_batch,
    'deleted', v_result
  );
end;
$$;

revoke all on function public.purge_mock_batch(text)
  from public;
grant execute on function public.purge_mock_batch(text)
  to authenticated;

comment on function public.purge_mock_batch(text) is
  'Purges live mock-batch tables and auth users without referencing purged schemas.';

-- --------------------------------------------------------------------------
-- Stale functions from removed product surfaces
-- --------------------------------------------------------------------------

drop function if exists public.get_rayon_member_registry(
  uuid,
  text,
  text,
  text,
  integer,
  integer
);

drop function if exists public.award_cool_achievement(uuid, text, integer);
