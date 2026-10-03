begin;

-- Re-declare the reviewed roster writer with an explicit JSONB initializer so
-- PostgreSQL lint and runtime agree on the accumulator type.
create or replace function collect_hybrid.add_roster(
  p_collection_id uuid,
  p_rows jsonb,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb;
  phone text;
  registered_name text;
  display_name text;
  identity_row collect_hybrid.member_momo_identities;
  record_id uuid;
  result_rows jsonb := '[]'::jsonb;
  response jsonb;
  old_batch collect_hybrid.roster_batches;
  input_digest text;
begin
  perform collect_hybrid.assert_onboarding();
  if p_request_id is null
     or p_reason is null
     or char_length(btrim(p_reason)) not between 8 and 500
     or p_rows is null
     or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Invalid reviewed roster request';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 500 then
    raise exception 'Roster must contain 1 to 500 reviewed rows';
  end if;
  perform 1
  from public.collections collection
  where collection.id = p_collection_id
    and collection.creation_origin = 'admin_assisted'
    and collection.archived_at is null
    and collection.public_status = 'private'
    and not collection.diaspora_enabled
  for update;
  if not found then
    raise exception 'Active private assisted Rwanda group required';
  end if;
  input_digest := encode(extensions.digest(
    p_collection_id::text || p_rows::text || btrim(p_reason),
    'sha256'
  ), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    'hybrid-roster:' || p_request_id::text,
    0
  ));
  select batch.* into old_batch
  from collect_hybrid.roster_batches batch
  where batch.request_id = p_request_id;
  if old_batch.request_id is not null then
    if old_batch.input_hash <> input_digest or old_batch.actor_id <> auth.uid() then
      raise exception 'Roster idempotency key conflict';
    end if;
    return old_batch.result || jsonb_build_object('replay', true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('collect-numeric-member-id', 0));
  for row_data in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(row_data) <> 'object' then
      raise exception 'Invalid roster row';
    end if;
    phone := collect_hybrid.canonical_momo_number(row_data->>'momo_number');
    registered_name := btrim(row_data->>'momo_name');
    display_name := btrim(coalesce(
      nullif(row_data->>'member_name', ''),
      registered_name
    ));
    if phone is null
       or registered_name is null
       or char_length(registered_name) not between 2 and 120
       or display_name is null
       or char_length(display_name) not between 2 and 120
       or registered_name ~ '[[:cntrl:]]'
       or display_name ~ '[[:cntrl:]]' then
      raise exception 'Each row requires a valid full MoMo number and names';
    end if;
    select identity.* into identity_row
    from collect_hybrid.member_momo_identities identity
    where identity.momo_number = phone;
    if identity_row.member_id is not null then
      if identity_row.normalized_name <>
          collect_hybrid.normalize_momo_name(registered_name)
         or identity_row.member_name <> display_name then
        raise exception 'Existing MoMo identity differs; review before updating';
      end if;
      record_id := identity_row.member_id;
      if not exists (
        select 1 from collect_hybrid.member_records member
        where member.id = record_id and member.lifecycle = 'active'
      ) then
        raise exception 'Existing member is inactive';
      end if;
    else
      if exists (
        select 1 from public.profiles profile
        where regexp_replace(coalesce(profile.momo_number, ''), '^0', '+250') = phone
      ) then
        raise exception 'Existing app MoMo number requires reviewed identity linking';
      end if;
      insert into collect_hybrid.member_records(collect_id, origin, created_by)
      values (public.generate_public_id(), 'admin_assisted', auth.uid())
      returning id into record_id;
      insert into collect_hybrid.member_momo_identities(
        member_id,
        member_name,
        momo_name,
        momo_number
      ) values (record_id, display_name, registered_name, phone);
    end if;
    if exists (
      select 1 from public.collection_members membership
      where membership.collection_id = p_collection_id
        and membership.member_record_id = record_id
        and membership.role = 'member'
        and membership.status <> 'active'
    ) then
      raise exception 'Existing membership is not active; review before reactivation';
    end if;
    insert into public.collection_members(
      collection_id,
      member_record_id,
      role,
      status
    ) values (p_collection_id, record_id, 'member', 'active')
    on conflict do nothing;
    result_rows := result_rows || jsonb_build_array(jsonb_build_object(
      'member_id', record_id,
      'collect_id', (
        select member.collect_id
        from collect_hybrid.member_records member
        where member.id = record_id
      )
    ));
  end loop;
  response := jsonb_build_object(
    'ok', true,
    'collection_id', p_collection_id,
    'rows', result_rows,
    'replay', false
  );
  insert into collect_hybrid.roster_batches(
    request_id,
    collection_id,
    actor_id,
    input_hash,
    result
  ) values (p_request_id, p_collection_id, auth.uid(), input_digest, response);
  perform public.create_audit_log(
    'collection.assisted.roster_added',
    'collection',
    p_collection_id,
    jsonb_build_object(
      'reason', btrim(p_reason),
      'request_id', p_request_id,
      'row_count', jsonb_array_length(p_rows)
    )
  );
  return response;
end;
$$;

-- The public wrapper is the only browser-callable boundary.  Keep the private
-- helper ungranted so PostgREST cannot expose it directly.
create or replace function public.admin_add_assisted_roster(
  p_collection_id uuid,
  p_rows jsonb,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select collect_hybrid.add_roster(
    p_collection_id,
    p_rows,
    p_request_id,
    p_reason
  );
$$;

create or replace function collect_hybrid.create_assisted_group_with_share(
  p_title text,
  p_reason text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb;
  group_id uuid;
begin
  result := collect_hybrid.create_assisted_group(
    p_title,
    p_reason,
    p_request_id
  );
  group_id := (result->>'collection_id')::uuid;
  insert into public.collection_share_secrets(collection_id, rotated_by)
  values (group_id, auth.uid())
  on conflict (collection_id) do nothing;
  return result || jsonb_build_object('share_code_ready', true);
end;
$$;

create or replace function public.admin_create_assisted_group(
  p_title text,
  p_reason text,
  p_request_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select collect_hybrid.create_assisted_group_with_share(
    p_title,
    p_reason,
    p_request_id
  );
$$;

create function public.admin_create_assisted_group_with_roster(
  p_title text,
  p_rows jsonb,
  p_reason text,
  p_group_request_id uuid,
  p_roster_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  group_result jsonb;
  roster_result jsonb;
begin
  if p_group_request_id is null
     or p_roster_request_id is null
     or p_group_request_id = p_roster_request_id then
    raise exception 'Distinct group and roster request IDs are required';
  end if;
  group_result := collect_hybrid.create_assisted_group_with_share(
    p_title,
    p_reason,
    p_group_request_id
  );
  roster_result := collect_hybrid.add_roster(
    (group_result->>'collection_id')::uuid,
    p_rows,
    p_roster_request_id,
    p_reason
  );
  return group_result || jsonb_build_object(
    'roster', roster_result->'rows',
    'roster_count', jsonb_array_length(roster_result->'rows'),
    'roster_replay', roster_result->'replay'
  );
end;
$$;

-- Converge any earlier local/pilot assisted groups without changing an
-- existing invitation code.
insert into public.collection_share_secrets(collection_id, rotated_by)
select collection.id, collection.creator_user_id
from public.collections collection
where collection.creation_origin = 'admin_assisted'
  and not exists (
    select 1 from public.collection_share_secrets secret
    where secret.collection_id = collection.id
  );

revoke all on function collect_hybrid.create_assisted_group(text, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function collect_hybrid.create_assisted_group_with_share(
  text,
  text,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function collect_hybrid.add_roster(uuid, jsonb, uuid, text)
  from public, anon, authenticated, service_role;

revoke all on function public.admin_add_assisted_roster(uuid, jsonb, uuid, text)
  from public, anon, service_role;
grant execute on function public.admin_add_assisted_roster(uuid, jsonb, uuid, text)
  to authenticated;
revoke all on function public.admin_create_assisted_group(text, text, uuid)
  from public, anon, service_role;
grant execute on function public.admin_create_assisted_group(text, text, uuid)
  to authenticated;
revoke all on function public.admin_create_assisted_group_with_roster(
  text,
  jsonb,
  text,
  uuid,
  uuid
) from public, anon, service_role;
grant execute on function public.admin_create_assisted_group_with_roster(
  text,
  jsonb,
  text,
  uuid,
  uuid
) to authenticated;

comment on function public.admin_create_assisted_group_with_roster(
  text,
  jsonb,
  text,
  uuid,
  uuid
) is
  'Atomically creates a private assisted group, its share code and 1-500 reviewed offline/app-independent member identities; extraction never calls this function automatically.';

commit;
