begin;

alter table public.collections
  add column if not exists is_platform_sponsored boolean not null default false;

comment on column public.collections.is_platform_sponsored is
  'True only for Collect-managed public groups. Member-created groups remain private and false.';

create index if not exists collections_public_sponsored_directory_idx
  on public.collections (is_platform_sponsored, public_status, created_at desc)
  where archived_at is null;

do $$
declare
  platform_owner_id uuid;
  buri_munsi_id uuid;
  rayon_sports_id uuid;
  route_id uuid;
begin
  select profile.id
  into platform_owner_id
  from public.profiles profile
  where profile.is_platform_admin
  order by profile.created_at, profile.id
  limit 1;

  if platform_owner_id is null then
    raise exception 'A platform administrator profile is required before seeding public groups';
  end if;

  if exists (
    select 1
    from public.collections collection
    where collection.slug in ('buri-munsi', 'gikundiro')
      and not collection.is_platform_sponsored
  ) then
    raise exception 'A member-owned collection already uses a reserved public group slug';
  end if;

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
    recurring_rule,
    allow_anonymous,
    contribution_visibility,
    allow_public_comments,
    receiver_display_label,
    collection_type,
    category_subtype,
    purpose_label,
    moderation_status,
    recurring_cadence,
    diaspora_enabled,
    diaspora_regions,
    is_platform_sponsored,
    archived_at
  ) values (
    'buri-munsi',
    platform_owner_id,
    'Buri Munsi',
    'Group savings open to everyone.',
    'Family / friends',
    'RWF',
    'public_approved',
    'public_approved',
    true,
    jsonb_build_object('cadence', 'monthly'),
    true,
    'public_safe',
    false,
    'IKANISA LTD',
    'ikimina',
    'group_savings',
    'Group savings',
    'approved',
    'monthly',
    false,
    '{}'::text[],
    true,
    null
  )
  on conflict (slug) do update
  set creator_user_id = excluded.creator_user_id,
      title = excluded.title,
      description = excluded.description,
      category = excluded.category,
      currency = excluded.currency,
      visibility = excluded.visibility,
      public_status = excluded.public_status,
      is_recurring = excluded.is_recurring,
      recurring_rule = excluded.recurring_rule,
      allow_anonymous = excluded.allow_anonymous,
      contribution_visibility = excluded.contribution_visibility,
      allow_public_comments = excluded.allow_public_comments,
      receiver_display_label = excluded.receiver_display_label,
      collection_type = excluded.collection_type,
      category_subtype = excluded.category_subtype,
      purpose_label = excluded.purpose_label,
      moderation_status = excluded.moderation_status,
      recurring_cadence = excluded.recurring_cadence,
      diaspora_enabled = excluded.diaspora_enabled,
      diaspora_regions = excluded.diaspora_regions,
      is_platform_sponsored = true,
      archived_at = null,
      updated_at = now()
  returning id into buri_munsi_id;

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
    recurring_rule,
    allow_anonymous,
    contribution_visibility,
    allow_public_comments,
    receiver_display_label,
    collection_type,
    category_subtype,
    purpose_label,
    moderation_status,
    recurring_cadence,
    diaspora_enabled,
    diaspora_regions,
    is_platform_sponsored,
    archived_at
  ) values (
    'gikundiro',
    platform_owner_id,
    'Gikundiro',
    'Official Rayon Sports supporter group open to everyone.',
    'Sports team',
    'RWF',
    'public_approved',
    'public_approved',
    true,
    jsonb_build_object('cadence', 'monthly'),
    true,
    'public_safe',
    false,
    'Rayon Sports FC',
    'sport',
    'team_support',
    'Team support',
    'approved',
    'monthly',
    false,
    '{}'::text[],
    true,
    null
  )
  on conflict (slug) do update
  set creator_user_id = excluded.creator_user_id,
      title = excluded.title,
      description = excluded.description,
      category = excluded.category,
      currency = excluded.currency,
      visibility = excluded.visibility,
      public_status = excluded.public_status,
      is_recurring = excluded.is_recurring,
      recurring_rule = excluded.recurring_rule,
      allow_anonymous = excluded.allow_anonymous,
      contribution_visibility = excluded.contribution_visibility,
      allow_public_comments = excluded.allow_public_comments,
      receiver_display_label = excluded.receiver_display_label,
      collection_type = excluded.collection_type,
      category_subtype = excluded.category_subtype,
      purpose_label = excluded.purpose_label,
      moderation_status = excluded.moderation_status,
      recurring_cadence = excluded.recurring_cadence,
      diaspora_enabled = excluded.diaspora_enabled,
      diaspora_regions = excluded.diaspora_regions,
      is_platform_sponsored = true,
      archived_at = null,
      updated_at = now()
  returning id into rayon_sports_id;

  update public.collection_receivers
  set is_active = false
  where collection_id = buri_munsi_id;

  select receiver.id
  into route_id
  from public.collection_receivers receiver
  where receiver.collection_id = buri_munsi_id
    and receiver.momo_number = '41258'
  order by receiver.created_at
  limit 1;

  if route_id is null then
    insert into public.collection_receivers (
      collection_id,
      receiver_user_id,
      momo_number,
      momo_number_hash,
      network,
      label,
      is_active
    ) values (
      buri_munsi_id,
      platform_owner_id,
      '41258',
      encode(extensions.digest('41258', 'sha256'), 'hex'),
      'mtn_momo',
      'IKANISA LTD',
      true
    );
  else
    update public.collection_receivers
    set receiver_user_id = platform_owner_id,
        momo_number_hash = encode(extensions.digest('41258', 'sha256'), 'hex'),
        network = 'mtn_momo',
        label = 'IKANISA LTD',
        is_active = true
    where id = route_id;
  end if;

  route_id := null;
  update public.collection_receivers
  set is_active = false
  where collection_id = rayon_sports_id;

  select receiver.id
  into route_id
  from public.collection_receivers receiver
  where receiver.collection_id = rayon_sports_id
    and receiver.momo_number = '008000'
  order by receiver.created_at
  limit 1;

  if route_id is null then
    insert into public.collection_receivers (
      collection_id,
      receiver_user_id,
      momo_number,
      momo_number_hash,
      network,
      label,
      is_active
    ) values (
      rayon_sports_id,
      platform_owner_id,
      '008000',
      encode(extensions.digest('008000', 'sha256'), 'hex'),
      'mtn_momo',
      'Rayon Sports FC',
      true
    );
  else
    update public.collection_receivers
    set receiver_user_id = platform_owner_id,
        momo_number_hash = encode(extensions.digest('008000', 'sha256'), 'hex'),
        network = 'mtn_momo',
        label = 'Rayon Sports FC',
        is_active = true
    where id = route_id;
  end if;
end;
$$;

create or replace function public.enforce_active_contributor_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.contributor_user_id is null then
    raise exception 'Authenticated contributor is required';
  end if;
  if not exists (
    select 1
    from public.collections collection
    where collection.id = new.collection_id
      and collection.archived_at is null
      and (
        collection.public_status = 'public_approved'
        or collection.creator_user_id = new.contributor_user_id
        or exists (
          select 1
          from public.collection_members member_check
          where member_check.collection_id = collection.id
            and member_check.user_id = new.contributor_user_id
            and member_check.status = 'active'
        )
      )
  ) then
    raise exception 'Join this group before creating a contribution request';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_active_contributor_membership()
  from public, anon, authenticated;

create or replace function public.create_contribution_intent(
  collection uuid,
  p_expected_amount_rwf bigint default null,
  p_sender_phone_hash text default null
)
returns table (
  id uuid,
  collection_id uuid,
  expected_amount_rwf bigint,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  network text,
  sender_phone_hash text,
  status public.payment_intent_status,
  contributor_public_id char(6),
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_collection_id uuid := collection;
  verified_sender_phone_hash text;
  receiver_row public.collection_receivers;
  intent_row public.payment_intents;
  member_public_id char(6);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1
    from public.collections collection_row
    where collection_row.id = requested_collection_id
      and collection_row.archived_at is null
      and (
        collection_row.public_status = 'public_approved'
        or collection_row.creator_user_id = auth.uid()
        or exists (
          select 1
          from public.collection_members member_check
          where member_check.collection_id = collection_row.id
            and member_check.user_id = auth.uid()
            and member_check.status = 'active'
        )
      )
  ) then
    raise exception 'Join this group before creating a contribution request';
  end if;
  if p_expected_amount_rwf is null or p_expected_amount_rwf <= 0 then
    raise exception 'Contribution amount must be above zero';
  end if;

  verified_sender_phone_hash := public._authenticated_momo_phone_hash(auth.uid());
  if verified_sender_phone_hash is null then
    raise exception 'Use your verified WhatsApp number as your MoMo payer number before contributing';
  end if;
  if nullif(trim(p_sender_phone_hash), '') is null
     or lower(trim(p_sender_phone_hash)) <> verified_sender_phone_hash then
    raise exception 'Contributor MoMo identity verification failed';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'contribution-intent:' || auth.uid()::text || ':' || requested_collection_id::text,
    0
  ));
  update public.payment_intents intent
  set status = case
    when intent.expires_at <= now() then 'expired'::public.payment_intent_status
    else 'cancelled'::public.payment_intent_status
  end
  where intent.contributor_user_id = auth.uid()
    and intent.collection_id = requested_collection_id
    and intent.status = 'pending'
    and (
      intent.expires_at <= now()
      or intent.sender_phone_hash is distinct from verified_sender_phone_hash
    );

  select profile.public_id into member_public_id
  from public.profiles profile where profile.id = auth.uid();
  if member_public_id is null then
    raise exception 'Collect ID is required before contributing';
  end if;

  select receiver.* into receiver_row
  from public.collection_receivers receiver
  where receiver.collection_id = requested_collection_id
    and receiver.is_active
  order by receiver.created_at
  limit 1
  for update;
  if receiver_row.id is null then raise exception 'Group has no active receiver'; end if;

  select intent.* into intent_row
  from public.payment_intents intent
  where intent.collection_id = requested_collection_id
    and intent.contributor_user_id = auth.uid()
    and intent.expected_amount_rwf = p_expected_amount_rwf
    and intent.receiver_momo_number_hash = receiver_row.momo_number_hash
    and intent.sender_phone_hash = verified_sender_phone_hash
    and intent.status = 'pending'
    and intent.expires_at > now()
  order by intent.created_at desc
  limit 1
  for update;

  if intent_row.id is null then
    insert into public.payment_intents (
      collection_id,
      contributor_user_id,
      contributor_public_id,
      expected_amount_rwf,
      receiver_momo_number_hash,
      sender_phone_hash
    ) values (
      requested_collection_id,
      auth.uid(),
      member_public_id,
      p_expected_amount_rwf,
      receiver_row.momo_number_hash,
      verified_sender_phone_hash
    ) returning * into intent_row;
  end if;

  return query select
    intent_row.id,
    intent_row.collection_id,
    intent_row.expected_amount_rwf,
    receiver_row.momo_number,
    intent_row.receiver_momo_number_hash,
    receiver_row.label,
    receiver_row.network,
    intent_row.sender_phone_hash,
    intent_row.status,
    intent_row.contributor_public_id,
    intent_row.created_at,
    intent_row.expires_at;
end;
$$;

revoke all on function public.create_contribution_intent(uuid, bigint, text)
  from public, anon;
grant execute on function public.create_contribution_intent(uuid, bigint, text)
  to authenticated;

create or replace view public.member_collections_view
with (security_invoker = true)
as
select
  collection.id,
  collection.slug,
  collection.creator_user_id,
  collection.title,
  collection.description,
  collection.currency,
  collection.collection_type,
  collection.category_subtype,
  collection.purpose_label,
  collection.suggested_amount_rwf,
  collection.diaspora_enabled,
  collection.diaspora_regions,
  case when collection.archived_at is not null
    then 'archived' else collection.moderation_status end as moderation_status,
  case
    when public.user_is_collection_admin(collection.id, auth.uid())
      or exists (
        select 1
        from public.collection_receivers receiver_check
        where receiver_check.collection_id = collection.id
          and receiver_check.receiver_user_id = auth.uid()
          and receiver_check.is_active
      ) then receiver.momo_number
    else null
  end as receiver_momo_number,
  receiver.label as receiver_display_label,
  receiver.network as receiver_network,
  collection.created_at,
  collection.updated_at,
  collection.archived_at,
  collection.accent_color_hex,
  collection.recurring_cadence,
  collection.public_status = 'public_approved' as is_public,
  (
    collection.creator_user_id = auth.uid()
    or exists (
      select 1
      from public.collection_members member_check
      where member_check.collection_id = collection.id
        and member_check.user_id = auth.uid()
        and member_check.status = 'active'
    )
  ) as is_member,
  collection.is_recurring,
  collection.public_status::text as visibility_status,
  collection.is_platform_sponsored
from public.collections collection
left join lateral (
  select route.momo_number, route.label, route.network
  from public.collection_receivers route
  where route.collection_id = collection.id
    and route.is_active
  order by route.created_at
  limit 1
) receiver on true
where public.user_can_read_collection(collection.id, auth.uid());

revoke all on public.member_collections_view from public, anon;
grant select on public.member_collections_view to authenticated;

create or replace function public.admin_list_collections(
  p_search text default null,
  p_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('collections.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(
      public._admin_row(
        collection.id,
        collection.title,
        coalesce(receiver.label, collection.purpose_label, collection.category),
        case
          when collection.archived_at is not null then 'archived'
          when collection.public_status = 'public_approved' then 'public_approved'
          else 'private'
        end,
        case
          when receiver.momo_number is null then 'MoMo route missing'
          else 'MoMo ' || receiver.momo_number
        end,
        collection.created_at,
        jsonb_build_object(
          'slug', collection.slug,
          'collection_type', collection.collection_type,
          'category_subtype', collection.category_subtype,
          'purpose_label', collection.purpose_label,
          'is_platform_sponsored', collection.is_platform_sponsored,
          'receiver_label', receiver.label,
          'momo_code', receiver.momo_number
        )
      ) order by collection.is_platform_sponsored desc, collection.created_at desc
    )
    from public.collections collection
    left join lateral (
      select route.label, route.momo_number
      from public.collection_receivers route
      where route.collection_id = collection.id and route.is_active
      order by route.created_at
      limit 1
    ) receiver on true
    where (
      nullif(trim(coalesce(p_search, '')), '') is null
      or collection.title ilike '%' || trim(p_search) || '%'
      or collection.slug ilike '%' || trim(p_search) || '%'
    ) and (
      nullif(trim(coalesce(p_status, '')), '') is null
      or (p_status = 'public_approved' and collection.public_status = 'public_approved')
      or (p_status = 'private' and collection.public_status = 'private')
      or (p_status = 'archived' and collection.archived_at is not null)
    )
  ), '[]'::jsonb));
end;
$$;

create or replace function public.admin_get_collection(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('collections.read');
  return coalesce((
    select jsonb_build_object(
      'id', collection.id,
      'slug', collection.slug,
      'title', collection.title,
      'description', collection.description,
      'creator_user_id', collection.creator_user_id,
      'creator_label', 'Collect ID ' || profile.public_id,
      'collection_type', collection.collection_type,
      'category_subtype', collection.category_subtype,
      'purpose_label', collection.purpose_label,
      'receiver_display_label', receiver.label,
      'receiver_momo_code', receiver.momo_number,
      'receiver_network', receiver.network,
      'is_platform_sponsored', collection.is_platform_sponsored,
      'visibility', collection.visibility,
      'public_status', collection.public_status,
      'status', case
        when collection.archived_at is not null then 'archived'
        else collection.public_status::text
      end,
      'active_receivers', (
        select count(*)
        from public.collection_receivers route
        where route.collection_id = collection.id and route.is_active
      ),
      'active_members', (
        select count(*)
        from public.collection_members member
        where member.collection_id = collection.id and member.status = 'active'
      ),
      'pending_payment_intents', (
        select count(*)
        from public.payment_intents intent
        where intent.collection_id = collection.id and intent.status = 'pending'
      ),
      'created_at', collection.created_at,
      'updated_at', collection.updated_at
    )
    from public.collections collection
    left join public.profiles profile on profile.id = collection.creator_user_id
    left join lateral (
      select route.label, route.momo_number, route.network
      from public.collection_receivers route
      where route.collection_id = collection.id and route.is_active
      order by route.created_at
      limit 1
    ) receiver on true
    where collection.id = p_id
  ), '{}'::jsonb);
end;
$$;

create or replace function public.admin_update_platform_public_group(
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
set search_path = public, extensions
as $$
declare
  collection_row public.collections;
  receiver_row public.collection_receivers;
  clean_type text := lower(trim(coalesce(p_collection_type, '')));
begin
  perform public.assert_admin_permission('collections.moderate');
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Reason is required';
  end if;
  if char_length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'Group name must be between 3 and 120 characters';
  end if;
  if clean_type not in ('ikimina', 'sport', 'church', 'wedding', 'other') then
    raise exception 'Unsupported collection type';
  end if;
  select collection.*
  into collection_row
  from public.collections collection
  where collection.id = p_collection_id
  for update;

  if collection_row.id is null or not collection_row.is_platform_sponsored then
    raise exception 'Platform-sponsored public group not found';
  end if;

  update public.collections
  set title = trim(p_title),
      description = trim(coalesce(p_description, '')),
      category = case clean_type
        when 'sport' then 'Sports team'
        when 'church' then 'Church'
        when 'wedding' then 'Wedding'
        when 'ikimina' then 'Family / friends'
        else 'Other'
      end,
      collection_type = clean_type,
      category_subtype = nullif(trim(coalesce(p_category_subtype, '')), ''),
      purpose_label = nullif(trim(coalesce(p_purpose_label, '')), ''),
      receiver_display_label = trim(p_receiver_label),
      visibility = 'public_approved',
      public_status = 'public_approved',
      moderation_status = 'approved',
      archived_at = null,
      updated_at = now()
  where id = p_collection_id;

  select receiver.*
  into receiver_row
  from public.collection_receivers receiver
  where receiver.collection_id = p_collection_id
    and receiver.is_active
  order by receiver.created_at
  limit 1
  for update;

  if receiver_row.id is null then
    raise exception 'Create the immutable MoMo route from the Payees workspace first';
  end if;

  update public.collection_receivers
  set label = trim(p_receiver_label)
  where id = receiver_row.id
  returning * into receiver_row;

  perform public.create_audit_log(
    'collection.platform_public.updated',
    'collection',
    p_collection_id,
    jsonb_build_object(
      'reason', trim(p_reason),
      'title', trim(p_title),
      'collection_type', clean_type,
      'category_subtype', nullif(trim(coalesce(p_category_subtype, '')), ''),
      'purpose_label', nullif(trim(coalesce(p_purpose_label, '')), ''),
      'receiver_label', trim(p_receiver_label)
    )
  );

  return jsonb_build_object(
    'ok', true,
    'collection_id', p_collection_id,
    'public_status', 'public_approved',
    'receiver_id', receiver_row.id
  );
end;
$$;

revoke all on function public.admin_update_platform_public_group(
  uuid, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.admin_update_platform_public_group(
  uuid, text, text, text, text, text, text, text
) to authenticated;

commit;
