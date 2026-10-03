begin;

-- Country scoping is an Admin read concern. Existing list RPCs keep their
-- stable contracts; this wrapper exhausts their server-side pages, resolves a
-- country from the authoritative profile/transaction relationship, filters,
-- and only then applies the requested page window.
create schema if not exists private;
revoke all on schema private from public;

create or replace function private.collect_admin_try_uuid(p_value text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return nullif(btrim(coalesce(p_value, '')), '')::uuid;
exception
  when invalid_text_representation then return null;
end;
$$;

create or replace function private.collect_admin_country_for_row(
  p_rpc_name text,
  p_row jsonb
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_country text := upper(nullif(btrim(coalesce(p_row ->> 'country_code', '')), ''));
  v_rail text := lower(nullif(btrim(coalesce(p_row ->> 'rail', '')), ''));
  v_record_id uuid;
  v_intent_id uuid;
  v_transaction_id uuid;
  v_collection_id uuid;
  v_user_id uuid;
  v_whatsapp_phone text;
  v_platform_sponsored boolean := false;
begin
  if v_country ~ '^[A-Z]{2}$' then
    return v_country;
  end if;

  if v_rail = 'rw_momo' or p_rpc_name = 'admin_list_collect_payees' then
    return 'RW';
  end if;

  if p_rpc_name = 'admin_list_collections' then
    v_record_id := private.collect_admin_try_uuid(p_row ->> 'id');
    select collection.creator_user_id, collection.is_platform_sponsored
      into v_user_id, v_platform_sponsored
    from public.collections collection
    where collection.id = v_record_id;
    if v_platform_sponsored then return 'RW'; end if;
  elsif p_rpc_name = 'admin_list_notifications' then
    v_record_id := private.collect_admin_try_uuid(p_row ->> 'id');
    select event.user_id into v_user_id
    from public.notification_events event
    where event.id = v_record_id;
  elsif p_rpc_name in (
    'admin_list_collect_transactions',
    'admin_list_collect_reconciliations',
    'admin_list_collect_ledgers'
  ) then
    v_intent_id := private.collect_admin_try_uuid(p_row ->> 'payment_intent_id');
    v_transaction_id := private.collect_admin_try_uuid(p_row ->> 'transaction_id');
    v_collection_id := private.collect_admin_try_uuid(p_row ->> 'collection_id');

    if v_intent_id is not null then
      select intent.contributor_user_id into v_user_id
      from public.bank_transfer_intents intent
      where intent.id = v_intent_id;
    end if;

    if v_user_id is null and nullif(btrim(coalesce(p_row ->> 'reference', '')), '') is not null then
      select intent.contributor_user_id into v_user_id
      from public.bank_transfer_intents intent
      where upper(intent.transfer_reference) = upper(btrim(p_row ->> 'reference'))
      order by intent.created_at desc
      limit 1;
    end if;

    if v_user_id is null and v_transaction_id is not null then
      select allocation.contributor_user_id into v_user_id
      from public.bank_transaction_allocations allocation
      where allocation.bank_transaction_id = v_transaction_id
      order by allocation.created_at desc
      limit 1;
    end if;

    if v_user_id is null and v_collection_id is not null then
      select collection.creator_user_id into v_user_id
      from public.collections collection
      where collection.id = v_collection_id;
    end if;
  end if;

  if v_user_id is not null then
    select
      upper(nullif(btrim(profile.country_code), '')),
      profile.whatsapp_phone
      into v_country, v_whatsapp_phone
    from public.profiles profile
    where profile.id = v_user_id;
  end if;

  if v_country ~ '^[A-Z]{2}$' then return v_country; end if;
  if regexp_replace(coalesce(v_whatsapp_phone, ''), '[^0-9+]', '', 'g') like '+250%' then
    return 'RW';
  end if;
  if regexp_replace(coalesce(v_whatsapp_phone, ''), '[^0-9+]', '', 'g') like '+356%' then
    return 'MT';
  end if;

  -- ZZ is an internal safe bucket for an unresolved non-Rwanda/non-Malta row.
  -- It is displayed only through the "Other countries" scope.
  return 'ZZ';
end;
$$;

revoke all on function private.collect_admin_try_uuid(text)
  from public, anon, authenticated;
revoke all on function private.collect_admin_country_for_row(text, jsonb)
  from public, anon, authenticated;

create or replace function public.admin_list_country_scoped(
  p_rpc_name text,
  p_country text,
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
set search_path = ''
as $$
declare
  v_allowed_rpcs constant text[] := array[
    'admin_list_collections',
    'admin_list_users',
    'admin_list_members',
    'admin_list_non_member_users',
    'admin_list_collect_payees',
    'admin_list_collect_transactions',
    'admin_list_collect_reconciliations',
    'admin_list_collect_ledgers',
    'admin_list_notifications'
  ];
  v_country text := upper(btrim(coalesce(p_country, '')));
  v_page_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_page_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_source_offset integer := 0;
  v_source_total integer := 0;
  v_batch jsonb;
  v_all_rows jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if not (p_rpc_name = any(v_allowed_rpcs)) then
    raise exception 'Unsupported country-scoped Admin list';
  end if;
  if v_country not in ('RW', 'MT', 'OTHER') then
    raise exception 'Country scope must be RW, MT, or OTHER';
  end if;

  loop
    v_batch := case p_rpc_name
      when 'admin_list_collections' then public.admin_list_collections(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_users' then public.admin_list_users(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_members' then public.admin_list_members(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_non_member_users' then public.admin_list_non_member_users(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_collect_payees' then public.admin_list_collect_payees(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_collect_transactions' then public.admin_list_collect_transactions(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_collect_reconciliations' then public.admin_list_collect_reconciliations(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_collect_ledgers' then public.admin_list_collect_ledgers(
        p_search, p_status, 100, v_source_offset, p_sort)
      when 'admin_list_notifications' then public.admin_list_notifications(
        p_search, p_status, 100, v_source_offset, p_sort)
    end;

    v_source_total := greatest(
      v_source_total,
      coalesce(nullif(v_batch ->> 'total', '')::integer, 0)
    );
    v_all_rows := v_all_rows || coalesce(v_batch -> 'rows', '[]'::jsonb);
    exit when jsonb_array_length(coalesce(v_batch -> 'rows', '[]'::jsonb)) = 0
      or v_source_offset + 100 >= v_source_total;
    v_source_offset := v_source_offset + 100;
  end loop;

  with enriched as (
    select
      source.ordinality,
      source.value || jsonb_build_object(
        'country_code',
        private.collect_admin_country_for_row(p_rpc_name, source.value)
      ) as row
    from jsonb_array_elements(v_all_rows) with ordinality as source(value, ordinality)
  ), filtered as (
    select enriched.*
    from enriched
    where case v_country
      when 'RW' then enriched.row ->> 'country_code' = 'RW'
      when 'MT' then enriched.row ->> 'country_code' = 'MT'
      else enriched.row ->> 'country_code' not in ('RW', 'MT')
    end
  ), paged as (
    select filtered.*
    from filtered
    order by filtered.ordinality
    limit v_page_limit offset v_page_offset
  )
  select jsonb_build_object(
    'rows', coalesce(
      (select jsonb_agg(paged.row order by paged.ordinality) from paged),
      '[]'::jsonb
    ),
    'total', (select count(*) from filtered)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

revoke all on function public.admin_list_country_scoped(
  text, text, text, text, integer, integer, text
) from public, anon;
grant execute on function public.admin_list_country_scoped(
  text, text, text, text, integer, integer, text
) to authenticated, service_role;

comment on function public.admin_list_country_scoped(
  text, text, text, text, integer, integer, text
) is
  'Country-aware Admin list wrapper. Resolves country from authoritative profiles and financial relationships before pagination.';

commit;
