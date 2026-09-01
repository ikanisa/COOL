begin;

insert into public.admin_permissions (name, description)
values (
  'receivers.manage',
  'Create, rename, activate, and deactivate official payees without changing their MoMo route'
)
on conflict (name) do update set description = excluded.description;

insert into public.admin_role_permissions (role_id, permission_name)
select role.id, 'receivers.manage'
from public.admin_roles role
where role.name in ('platform_owner', 'operations_admin')
on conflict (role_id, permission_name) do nothing;

create or replace function public.enforce_official_payee_route_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.collections collection
    where collection.id = old.collection_id
      and collection.is_platform_sponsored
  ) and (
    new.momo_number is distinct from old.momo_number
    or new.momo_number_hash is distinct from old.momo_number_hash
    or new.network is distinct from old.network
  ) then
    raise exception 'Official payee MoMo number or code and provider are immutable; deactivate the route instead';
  end if;
  return new;
end;
$$;

drop trigger if exists collection_receivers_official_route_immutable
on public.collection_receivers;

create trigger collection_receivers_official_route_immutable
before update of momo_number, momo_number_hash, network
on public.collection_receivers
for each row execute function public.enforce_official_payee_route_immutable();

create or replace function public.admin_list_collect_payees(
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
  perform public.assert_admin_permission('receivers.read');

  with official_payees as (
    select
      'momo:' || receiver.id::text as id,
      receiver.label as title,
      collection.title || ' · ' || case receiver.network
        when 'mtn_momo' then 'MTN MoMo'
        when 'airtel_money' then 'Airtel Money'
        else 'MoMo'
      end || ' · code ' || receiver.momo_number || ' · route locked' as subtitle,
      case when receiver.is_active then 'active' else 'inactive' end as status,
      'Rwanda · MoMo USSD' as amount,
      receiver.created_at,
      jsonb_build_object(
        'rail', 'rw_momo',
        'payee_id', receiver.id,
        'collection_id', receiver.collection_id,
        'collection_title', collection.title,
        'provider', receiver.network,
        'momo_code', receiver.momo_number,
        'route_locked', true,
        'is_platform_sponsored', true
      ) as extra
    from public.collection_receivers receiver
    join public.collections collection on collection.id = receiver.collection_id
    where collection.is_platform_sponsored
      and collection.archived_at is null
  ), filtered as (
    select *
    from official_payees
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
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
        'amount', amount,
        'created_at', created_at
      ) || extra
      order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  )
  into result
  from counted;

  return result;
end;
$$;

create or replace function public.admin_list_platform_payee_candidates(
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
  perform public.assert_admin_permission('receivers.manage');

  with candidates as (
    select
      collection.id::text as id,
      collection.title,
      'Platform-sponsored public group with no payee route'::text as subtitle,
      'eligible'::text as status,
      'Rwanda · MoMo USSD'::text as amount,
      collection.created_at
    from public.collections collection
    where collection.is_platform_sponsored
      and collection.public_status = 'public_approved'
      and collection.archived_at is null
      and not exists (
        select 1
        from public.collection_receivers receiver
        where receiver.collection_id = collection.id
      )
  ), filtered as (
    select *
    from candidates
    where (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
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
        'amount', amount,
        'created_at', created_at
      )
      order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  )
  into result
  from counted;

  return result;
end;
$$;

create or replace function public.admin_create_collect_payee(
  p_collection_id uuid,
  p_label text,
  p_momo_code text,
  p_network text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  collection_row public.collections;
  receiver_id uuid;
  clean_label text := btrim(coalesce(p_label, ''));
  clean_code text := regexp_replace(coalesce(p_momo_code, ''), '[^0-9]', '', 'g');
  clean_network text := lower(btrim(coalesce(p_network, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
begin
  perform public.assert_admin_permission('receivers.manage');
  if char_length(clean_label) not between 2 and 120 then
    raise exception 'Official payee name must be between 2 and 120 characters';
  end if;
  if clean_code !~ '^[0-9]{4,12}$' then
    raise exception 'MoMo number or code must contain 4 to 12 digits';
  end if;
  if clean_network not in ('mtn_momo', 'airtel_money') then
    raise exception 'Unsupported MoMo provider';
  end if;
  if char_length(clean_reason) < 8 then
    raise exception 'Creation reason must be at least 8 characters';
  end if;

  select collection.*
  into collection_row
  from public.collections collection
  where collection.id = p_collection_id
    and collection.is_platform_sponsored
    and collection.public_status = 'public_approved'
    and collection.archived_at is null
  for update;

  if collection_row.id is null then
    raise exception 'Eligible platform-sponsored public group not found';
  end if;
  if exists (
    select 1
    from public.collection_receivers receiver
    where receiver.collection_id = p_collection_id
  ) then
    raise exception 'This group already has an immutable payee route; reactivate it instead';
  end if;

  insert into public.collection_receivers (
    collection_id,
    receiver_user_id,
    momo_number,
    momo_number_hash,
    network,
    label,
    is_active
  ) values (
    p_collection_id,
    collection_row.creator_user_id,
    clean_code,
    encode(extensions.digest(clean_code, 'sha256'), 'hex'),
    clean_network,
    clean_label,
    true
  )
  returning id into receiver_id;

  update public.collections
  set receiver_display_label = clean_label,
      updated_at = now()
  where id = p_collection_id;

  perform public.create_audit_log(
    'payee.official.created',
    'collection_receiver',
    receiver_id,
    jsonb_build_object(
      'reason', clean_reason,
      'collection_id', p_collection_id,
      'label', clean_label,
      'provider', clean_network,
      'route_immutable', true
    )
  );

  return jsonb_build_object(
    'ok', true,
    'payee_id', receiver_id,
    'status', 'active',
    'route_immutable', true
  );
end;
$$;

create or replace function public.admin_update_collect_payee(
  p_payee_id uuid,
  p_label text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_label text := btrim(coalesce(p_label, ''));
  clean_reason text := btrim(coalesce(p_reason, ''));
  target_collection_id uuid;
begin
  perform public.assert_admin_permission('receivers.manage');
  if char_length(clean_label) not between 2 and 120 then
    raise exception 'Official payee name must be between 2 and 120 characters';
  end if;
  if char_length(clean_reason) < 8 then
    raise exception 'Change reason must be at least 8 characters';
  end if;

  select receiver.collection_id
  into target_collection_id
  from public.collection_receivers receiver
  join public.collections collection on collection.id = receiver.collection_id
  where receiver.id = p_payee_id
    and collection.is_platform_sponsored
  for update of receiver;

  if target_collection_id is null then
    raise exception 'Official payee not found';
  end if;

  update public.collection_receivers
  set label = clean_label
  where id = p_payee_id;

  update public.collections collection
  set receiver_display_label = clean_label,
      updated_at = now()
  where collection.id = target_collection_id;

  perform public.create_audit_log(
    'payee.official.renamed',
    'collection_receiver',
    p_payee_id,
    jsonb_build_object(
      'reason', clean_reason,
      'collection_id', target_collection_id,
      'label', clean_label,
      'route_immutable', true
    )
  );

  return jsonb_build_object(
    'ok', true,
    'payee_id', p_payee_id,
    'label', clean_label,
    'route_immutable', true
  );
end;
$$;

create or replace function public.admin_set_collect_payee_status(
  p_payee_id uuid,
  p_active boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_reason text := btrim(coalesce(p_reason, ''));
  target_collection_id uuid;
begin
  perform public.assert_admin_permission('receivers.manage');
  if char_length(clean_reason) < 8 then
    raise exception 'Status reason must be at least 8 characters';
  end if;

  select receiver.collection_id
  into target_collection_id
  from public.collection_receivers receiver
  join public.collections collection on collection.id = receiver.collection_id
  where receiver.id = p_payee_id
    and collection.is_platform_sponsored
  for update of receiver;

  if target_collection_id is null then
    raise exception 'Official payee not found';
  end if;

  if p_active then
    update public.collection_receivers receiver
    set is_active = false
    where receiver.collection_id = target_collection_id
      and receiver.id <> p_payee_id
      and receiver.is_active;
  end if;

  update public.collection_receivers
  set is_active = p_active
  where id = p_payee_id;

  perform public.create_audit_log(
    case when p_active then 'payee.official.activated'
      else 'payee.official.deactivated' end,
    'collection_receiver',
    p_payee_id,
    jsonb_build_object(
      'reason', clean_reason,
      'collection_id', target_collection_id,
      'active', p_active,
      'route_immutable', true
    )
  );

  return jsonb_build_object(
    'ok', true,
    'payee_id', p_payee_id,
    'status', case when p_active then 'active' else 'inactive' end,
    'route_immutable', true
  );
end;
$$;

comment on function public.admin_create_collect_payee(uuid, text, text, text, text) is
  'Creates an official platform payee. The MoMo number or code and provider are immutable after insert.';
comment on function public.enforce_official_payee_route_immutable() is
  'Rejects attempts to change the MoMo number, code hash, or provider of a platform-sponsored official payee.';
comment on function public.admin_update_collect_payee(uuid, text, text) is
  'Updates only an official payee display name. The MoMo route cannot be edited.';
comment on function public.admin_set_collect_payee_status(uuid, boolean, text) is
  'Activates or deactivates an official payee without changing its MoMo route.';

revoke execute on function public.admin_list_collect_payees(text, text, integer, integer, text)
  from public, anon;
revoke execute on function public.admin_list_platform_payee_candidates(text, text, integer, integer, text)
  from public, anon;
revoke execute on function public.admin_create_collect_payee(uuid, text, text, text, text)
  from public, anon;
revoke execute on function public.admin_update_collect_payee(uuid, text, text)
  from public, anon;
revoke execute on function public.admin_set_collect_payee_status(uuid, boolean, text)
  from public, anon;

grant execute on function public.admin_list_collect_payees(text, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_list_platform_payee_candidates(text, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_create_collect_payee(uuid, text, text, text, text)
  to authenticated;
grant execute on function public.admin_update_collect_payee(uuid, text, text)
  to authenticated;
grant execute on function public.admin_set_collect_payee_status(uuid, boolean, text)
  to authenticated;

commit;
