begin;

-- Purpose-built Admin list contracts for Transactions, Groups, and Members.
-- List RPCs expose only permission-safe operational fields. Private phone and
-- MoMo identifiers stay masked; diaspora account data is reduced to readiness
-- and last-four metadata.

create or replace function public.admin_list_collect_transactions(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('payments.read');

  with unified as (
    select
      'momo:' || sms.id::text as id,
      coalesce(event.transaction_id, 'Receipt ' || right(sms.body_hash, 8)) as title,
      'Rwanda · ' || case event.network
        when 'mtn_momo' then 'MTN MoMo'
        when 'airtel_money' then 'Airtel Money'
        else 'MoMo SMS'
      end || ' · ' || coalesce(collection.title, 'Payee not linked') as subtitle,
      coalesce(event.allocation_status::text, sms.parse_status) as status,
      case when event.amount_rwf is null then ''
        else 'RWF ' || to_char(event.amount_rwf, 'FM999G999G999G999') end as amount,
      coalesce(sms.received_at_device, sms.ingested_at) as created_at,
      event.amount_rwf::numeric as sort_amount,
      jsonb_build_object(
        'rail', 'rw_momo',
        'source_label', case event.network
          when 'mtn_momo' then 'MTN MoMo receipt SMS'
          when 'airtel_money' then 'Airtel Money receipt SMS'
          else 'MoMo receipt SMS'
        end,
        'raw_sms_id', sms.id,
        'event_id', event.id,
        'payment_id', payment.id,
        'collection_id', coalesce(payment.collection_id, event.collection_id, sms.collection_id),
        'payment_intent_id', payment.payment_intent_id,
        'reference', event.transaction_id,
        'sender_masked', public.collect_admin_mask_sender(sms.raw_sender),
        'group_name', collection.title,
        'payee_label', receiver.label
      ) as extra
    from public.raw_payment_sms sms
    left join public.parsed_payment_events event on event.raw_sms_id = sms.id
    left join public.payments payment on payment.parsed_event_id = event.id
    left join public.collections collection
      on collection.id = coalesce(payment.collection_id, event.collection_id, sms.collection_id)
    left join lateral (
      select route.label
      from public.collection_receivers route
      where route.collection_id = collection.id and route.is_active
      order by route.created_at desc
      limit 1
    ) receiver on true

    union all

    select
      'diaspora:' || evidence.id::text,
      coalesce(bank_transaction.bank_transaction_id, event.transfer_reference,
        'Account receipt ' || right(evidence.body_hash, 8)),
      'Diaspora · ' || upper(evidence.channel) || ' · ' ||
        coalesce(collection.title, destination.beneficiary_name, 'Payee not linked'),
      coalesce(event.allocation_status, bank_transaction.status, evidence.parse_status),
      case when coalesce(bank_transaction.amount_minor, event.amount_minor) is null then ''
        else coalesce(bank_transaction.currency, event.currency, 'EUR') || ' ' ||
          to_char(coalesce(bank_transaction.amount_minor, event.amount_minor)::numeric / 100,
            'FM999G999G999D00') end,
      evidence.received_at,
      coalesce(bank_transaction.amount_minor, event.amount_minor)::numeric,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'source_label', 'Revolut EUR account transfer',
        'raw_bank_event_id', event.id,
        'raw_evidence_id', evidence.id,
        'transaction_id', bank_transaction.id,
        'collection_id', allocation.collection_id,
        'payment_intent_id', allocation.bank_transfer_intent_id,
        'reference', coalesce(bank_transaction.transfer_reference, event.transfer_reference),
        'sender_masked', public.collect_admin_mask_sender(evidence.raw_sender),
        'group_name', collection.title,
        'payee_label', destination.beneficiary_name
      )
    from public.raw_payment_evidence evidence
    left join public.bank_evidence_events event on event.raw_evidence_id = evidence.id
    left join public.payment_evidence_links evidence_link
      on evidence_link.evidence_event_id = event.id
    left join public.bank_transactions bank_transaction
      on bank_transaction.id = evidence_link.bank_transaction_id
    left join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = bank_transaction.id
    left join public.collections collection on collection.id = allocation.collection_id
    left join public.bank_transfer_destinations destination
      on destination.id = bank_transaction.destination_id
  ), filtered as (
    select * from unified
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'reference', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'group_name', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'payee_label', '') ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      case when p_sort = 'amount_asc' then sort_amount end asc nulls last,
      case when p_sort = 'amount_desc' then sort_amount end desc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id, 'title', title, 'subtitle', subtitle,
        'status', status, 'amount', amount, 'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_list_collections(
  p_search text,
  p_status text,
  p_limit integer,
  p_offset integer,
  p_sort text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('collections.read');

  with base as (
    select
      collection.id,
      collection.title,
      coalesce(collection.purpose_label, collection.category, 'Community group') as subtitle,
      case
        when collection.archived_at is not null then 'archived'
        when collection.public_status = 'public_approved' then 'public_approved'
        else 'private'
      end as status,
      collection.created_at,
      collection.updated_at,
      coalesce(member_count.active_members, 0)::integer as active_members,
      jsonb_build_object(
        'slug', collection.slug,
        'collection_type', collection.collection_type,
        'category_subtype', collection.category_subtype,
        'purpose_label', collection.purpose_label,
        'visibility', case
          when collection.public_status = 'public_approved' then 'public'
          else 'private'
        end,
        'is_platform_sponsored', collection.is_platform_sponsored,
        'creator_label', case
          when collection.is_platform_sponsored then 'Collect platform'
          else 'Collect ID ' || coalesce(profile.public_id, 'unavailable')
        end,
        'active_members', coalesce(member_count.active_members, 0),
        'receiver_label', receiver.label,
        'receiver_network', receiver.network,
        'momo_identifier', case
          when receiver.momo_number is null then null
          when collection.is_platform_sponsored then receiver.momo_number
          else public.mask_phone(receiver.momo_number)
        end,
        'route_ready', receiver.momo_number is not null,
        'updated_at', collection.updated_at
      ) as extra
    from public.collections collection
    left join public.profiles profile on profile.id = collection.creator_user_id
    left join lateral (
      select route.label, route.momo_number, route.network
      from public.collection_receivers route
      where route.collection_id = collection.id and route.is_active
      order by route.created_at desc
      limit 1
    ) receiver on true
    left join lateral (
      select count(*) as active_members
      from public.collection_members member
      where member.collection_id = collection.id and member.status = 'active'
    ) member_count on true
  ), filtered as (
    select * from base
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'slug', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'creator_label', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'receiver_label', '') ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'title', title,
        'subtitle', subtitle,
        'status', status,
        'amount', active_members::text || ' members',
        'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_list_collections(
  p_search text default null,
  p_status text default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.admin_list_collections(
    p_search,
    p_status,
    100,
    0,
    'created_at_desc'
  );
$$;

create or replace function public.admin_list_users(
  p_search text,
  p_status text,
  p_limit integer,
  p_offset integer,
  p_sort text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('users.read');

  with base as (
    select
      profile.id,
      'Collect ID ' || profile.public_id as title,
      public.mask_phone(profile.whatsapp_phone) as subtitle,
      case when profile.is_platform_admin then 'admin' else 'active' end as status,
      profile.created_at,
      profile.updated_at,
      coalesce(member_count.active_groups, 0)::integer as active_groups,
      jsonb_build_object(
        'public_id', profile.public_id,
        'display_name', profile.display_name,
        'whatsapp_masked', public.mask_phone(profile.whatsapp_phone),
        'country_code', coalesce(profile.country_code, 'RW'),
        'currency_code', coalesce(profile.currency_code, 'RWF'),
        'momo_provider', profile.momo_provider,
        'momo_masked', public.mask_phone(profile.momo_number),
        'has_revolut_profile',
          profile.revolut_link is not null and profile.revolut_account is not null,
        'account_last4', case
          when profile.revolut_account is null then null
          else right(regexp_replace(profile.revolut_account, '[^A-Za-z0-9]', '', 'g'), 4)
        end,
        'active_groups', coalesce(member_count.active_groups, 0),
        'is_platform_admin', profile.is_platform_admin,
        'updated_at', profile.updated_at
      ) as extra
    from public.profiles profile
    left join lateral (
      select count(distinct member.collection_id) as active_groups
      from public.collection_members member
      where member.user_id = profile.id and member.status = 'active'
    ) member_count on true
  ), filtered as (
    select * from base
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'display_name', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'whatsapp_masked', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'country_code', '') ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'title', title,
        'subtitle', subtitle,
        'status', status,
        'amount', active_groups::text || ' groups',
        'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_list_users(
  p_search text default null,
  p_status text default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.admin_list_users(
    p_search,
    p_status,
    100,
    0,
    'created_at_desc'
  );
$$;

insert into public.admin_queue_filter_options
  (rpc_name, filter_kind, value, label, display_order, enabled)
values
  ('admin_list_collect_transactions', 'sort', 'amount_desc', 'Amount high', 30, true),
  ('admin_list_collect_transactions', 'sort', 'amount_asc', 'Amount low', 40, true),
  ('admin_list_collect_transactions', 'status', 'unallocated', 'Unallocated', 25, true),
  ('admin_list_collect_transactions', 'status', 'parse_failed', 'Parse failed', 40, true),
  ('admin_list_users', 'status', '', 'All', 10, true),
  ('admin_list_users', 'status', 'active', 'Active', 20, true),
  ('admin_list_users', 'status', 'admin', 'Admin', 30, true)
on conflict (rpc_name, filter_kind, value) do update set
  label = excluded.label,
  display_order = excluded.display_order,
  enabled = excluded.enabled;

revoke all on function public.admin_list_collect_transactions(text, text, integer, integer, text)
  from public, anon;
revoke all on function public.admin_list_collections(text, text, integer, integer, text)
  from public, anon;
revoke all on function public.admin_list_users(text, text, integer, integer, text)
  from public, anon;

grant execute on function public.admin_list_collect_transactions(text, text, integer, integer, text)
  to authenticated, service_role;
grant execute on function public.admin_list_collections(text, text, integer, integer, text)
  to authenticated, service_role;
grant execute on function public.admin_list_users(text, text, integer, integer, text)
  to authenticated, service_role;

commit;
