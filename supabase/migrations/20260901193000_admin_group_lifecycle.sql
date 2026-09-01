begin;

-- Admins create only Collect-sponsored public groups. Member-created groups
-- continue to use the Android + Play Integrity attested private-group path.
create or replace function public.admin_create_platform_public_group(
  p_title text,
  p_description text,
  p_collection_type text,
  p_category_subtype text,
  p_purpose_label text,
  p_receiver_label text,
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
  clean_title text := btrim(coalesce(p_title, ''));
  clean_description text := btrim(coalesce(p_description, ''));
  clean_type text := lower(btrim(coalesce(p_collection_type, '')));
  clean_subtype text := nullif(btrim(coalesce(p_category_subtype, '')), '');
  clean_purpose text := btrim(coalesce(p_purpose_label, ''));
  clean_receiver text := btrim(coalesce(p_receiver_label, ''));
  clean_code text := regexp_replace(coalesce(p_momo_code, ''), '[^0-9]', '', 'g');
  clean_network text := lower(btrim(coalesce(p_network, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  base_slug text;
  final_slug text;
  created_group_id uuid;
  created_receiver_id uuid;
begin
  perform public.assert_admin_permission('collections.moderate');
  perform public.assert_admin_permission('receivers.manage');

  if char_length(clean_title) not between 3 and 120 then
    raise exception 'Group name must be between 3 and 120 characters';
  end if;
  if char_length(clean_description) > 1000 then
    raise exception 'Group description must be 1000 characters or fewer';
  end if;
  if clean_type not in ('ikimina', 'sport', 'church', 'wedding', 'other') then
    raise exception 'Unsupported collection type';
  end if;
  if char_length(clean_purpose) not between 2 and 120 then
    raise exception 'Purpose label must be between 2 and 120 characters';
  end if;
  if char_length(clean_receiver) not between 2 and 120 then
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
  if not exists (select 1 from public.profiles profile where profile.id = auth.uid()) then
    raise exception 'The signed-in admin does not have a Collect profile';
  end if;

  base_slug := public.normalize_slug(clean_title);
  if base_slug = '' then base_slug := 'group'; end if;
  final_slug := base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);

  insert into public.collections (
    slug,
    creator_user_id,
    title,
    description,
    category,
    currency,
    visibility,
    public_status,
    is_recurring,
    allow_anonymous,
    contribution_visibility,
    allow_public_comments,
    receiver_display_label,
    collection_type,
    category_subtype,
    purpose_label,
    moderation_status,
    diaspora_enabled,
    diaspora_regions,
    is_platform_sponsored,
    archived_at
  ) values (
    final_slug,
    auth.uid(),
    clean_title,
    clean_description,
    case clean_type
      when 'sport' then 'Sports team'
      when 'church' then 'Church'
      when 'wedding' then 'Wedding'
      when 'ikimina' then 'Family / friends'
      else 'Other'
    end,
    'RWF',
    'public_approved',
    'public_approved',
    false,
    true,
    'public_safe',
    false,
    clean_receiver,
    clean_type,
    clean_subtype,
    clean_purpose,
    'approved',
    false,
    '{}'::text[],
    true,
    null
  ) returning id into created_group_id;

  insert into public.collection_members (collection_id, user_id, role, status)
  values (created_group_id, auth.uid(), 'owner', 'active');

  insert into public.collection_receivers (
    collection_id,
    receiver_user_id,
    momo_number,
    momo_number_hash,
    network,
    label,
    is_active
  ) values (
    created_group_id,
    auth.uid(),
    clean_code,
    encode(extensions.digest(clean_code, 'sha256'), 'hex'),
    clean_network,
    clean_receiver,
    true
  ) returning id into created_receiver_id;

  perform public.create_audit_log(
    'collection.platform_public.created',
    'collection',
    created_group_id,
    jsonb_build_object(
      'reason', clean_reason,
      'title', clean_title,
      'collection_type', clean_type,
      'category_subtype', clean_subtype,
      'purpose_label', clean_purpose,
      'receiver_id', created_receiver_id,
      'provider', clean_network,
      'route_immutable', true
    )
  );

  perform public.create_audit_log(
    'payee.official.created',
    'collection_receiver',
    created_receiver_id,
    jsonb_build_object(
      'reason', clean_reason,
      'collection_id', created_group_id,
      'label', clean_receiver,
      'provider', clean_network,
      'route_immutable', true
    )
  );

  return jsonb_build_object(
    'ok', true,
    'collection_id', created_group_id,
    'payee_id', created_receiver_id,
    'status', 'active',
    'visibility', 'public_approved',
    'route_immutable', true
  );
end;
$$;

revoke all on function public.admin_create_platform_public_group(
  text, text, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.admin_create_platform_public_group(
  text, text, text, text, text, text, text, text, text
) to authenticated;

create or replace function public.admin_set_group_active(
  p_collection_id uuid,
  p_active boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  collection_row public.collections;
  clean_reason text := btrim(coalesce(p_reason, ''));
  next_status public.collection_visibility;
begin
  perform public.assert_admin_permission('collections.moderate');
  if char_length(clean_reason) < 8 then
    raise exception 'Lifecycle reason must be at least 8 characters';
  end if;

  select collection.*
  into collection_row
  from public.collections collection
  where collection.id = p_collection_id
  for update;

  if collection_row.id is null then
    raise exception 'Group not found';
  end if;

  if p_active and collection_row.is_platform_sponsored and not exists (
    select 1
    from public.collection_receivers receiver
    where receiver.collection_id = p_collection_id
      and receiver.is_active
  ) then
    raise exception 'Activate an official payee before activating this public group';
  end if;

  next_status := case
    when not p_active then 'archived'::public.collection_visibility
    when collection_row.is_platform_sponsored then 'public_approved'::public.collection_visibility
    else 'private'::public.collection_visibility
  end;

  update public.collections
  set public_status = next_status,
      visibility = next_status,
      moderation_status = case
        when not p_active then moderation_status
        when collection_row.is_platform_sponsored then 'approved'
        else moderation_status
      end,
      archived_at = case when p_active then null else now() end,
      updated_at = now()
  where id = p_collection_id;

  perform public.create_audit_log(
    case when p_active then 'collection.activated' else 'collection.deactivated' end,
    'collection',
    p_collection_id,
    jsonb_build_object(
      'reason', clean_reason,
      'active', p_active,
      'previous_status', collection_row.public_status::text,
      'next_status', next_status::text,
      'is_platform_sponsored', collection_row.is_platform_sponsored
    )
  );

  return jsonb_build_object(
    'ok', true,
    'collection_id', p_collection_id,
    'active', p_active,
    'status', case when p_active then 'active' else 'inactive' end,
    'visibility', next_status::text
  );
end;
$$;

revoke all on function public.admin_set_group_active(uuid, boolean, text)
  from public, anon;
grant execute on function public.admin_set_group_active(uuid, boolean, text)
  to authenticated;

-- Keep catalogue edits separate from lifecycle changes. The existing editor
-- function historically restored public/active state as a side effect; this
-- wrapper restores the exact prior lifecycle state inside the same transaction.
create or replace function public.admin_update_platform_public_group_metadata(
  p_collection_id uuid,
  p_title text,
  p_description text,
  p_collection_type text,
  p_category_subtype text,
  p_purpose_label text,
  p_receiver_label text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  prior_visibility public.collection_visibility;
  prior_public_status public.collection_visibility;
  prior_archived_at timestamptz;
  result jsonb;
begin
  perform public.assert_admin_permission('collections.moderate');

  select collection.visibility, collection.public_status, collection.archived_at
  into prior_visibility, prior_public_status, prior_archived_at
  from public.collections collection
  where collection.id = p_collection_id
    and collection.is_platform_sponsored
  for update;

  if prior_public_status is null then
    raise exception 'Platform-sponsored public group not found';
  end if;

  result := public.admin_update_platform_public_group(
    p_collection_id,
    p_title,
    p_description,
    p_collection_type,
    p_category_subtype,
    p_purpose_label,
    p_receiver_label,
    p_reason
  );

  update public.collections
  set visibility = prior_visibility,
      public_status = prior_public_status,
      archived_at = prior_archived_at,
      updated_at = now()
  where id = p_collection_id;

  return result || jsonb_build_object(
    'visibility', prior_visibility::text,
    'status', case when prior_archived_at is null then 'active' else 'inactive' end
  );
end;
$$;

revoke all on function public.admin_update_platform_public_group_metadata(
  uuid, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.admin_update_platform_public_group_metadata(
  uuid, text, text, text, text, text, text, text
) to authenticated;

commit;
