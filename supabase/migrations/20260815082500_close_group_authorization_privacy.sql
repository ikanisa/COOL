begin;

-- Server-minted, short-lived, single-use capabilities bind Android-only group
-- creation to a Play-recognized app/device verification event. The table is
-- deliberately service-only: authenticated clients can neither mint nor read
-- capabilities directly.
create table if not exists public.native_action_capabilities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  action text not null check (action in ('group.create')),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  request_payload jsonb not null
    check (jsonb_typeof(request_payload) = 'object'),
  receiver_momo_number_hash text not null
    check (receiver_momo_number_hash ~ '^[0-9a-f]{64}$'),
  package_name text not null,
  app_verdict text not null,
  device_verdicts text[] not null default '{}',
  verified_at timestamptz not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > verified_at),
  check (expires_at <= verified_at + interval '5 minutes')
);

create index if not exists native_action_capabilities_user_action_idx
  on public.native_action_capabilities (user_id, action, expires_at desc)
  where consumed_at is null;

alter table public.native_action_capabilities enable row level security;
revoke all on public.native_action_capabilities
  from public, anon, authenticated;

create or replace function public.mint_native_action_capability(
  capability_user_id uuid,
  capability_action text,
  capability_request_hash text,
  capability_request_payload jsonb,
  capability_receiver_hash text,
  capability_package_name text,
  capability_app_verdict text,
  capability_device_verdicts text[],
  capability_verified_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  capability_id uuid;
  clean_action text := trim(coalesce(capability_action, ''));
  clean_request_hash text := lower(trim(coalesce(capability_request_hash, '')));
  clean_receiver_hash text := lower(trim(coalesce(capability_receiver_hash, '')));
  clean_package_name text := trim(coalesce(capability_package_name, ''));
  clean_app_verdict text := trim(coalesce(capability_app_verdict, ''));
  verified_at_value timestamptz := coalesce(capability_verified_at, now());
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if capability_user_id is null or clean_action <> 'group.create' then
    raise exception 'Invalid native capability subject or action';
  end if;
  if clean_request_hash !~ '^[0-9a-f]{64}$'
     or clean_receiver_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid native capability binding';
  end if;
  if jsonb_typeof(capability_request_payload) <> 'object'
     or capability_request_payload ->> 'receiver_momo_number_hash'
       <> clean_receiver_hash then
    raise exception 'Invalid native capability request payload';
  end if;
  if clean_package_name <> 'app.cool.mobile'
     or clean_app_verdict <> 'PLAY_RECOGNIZED'
     or not (
       'MEETS_DEVICE_INTEGRITY' = any(coalesce(capability_device_verdicts, '{}'))
       or 'MEETS_STRONG_INTEGRITY' = any(coalesce(capability_device_verdicts, '{}'))
     ) then
    raise exception 'Play Integrity verdict is not eligible';
  end if;
  if abs(extract(epoch from (now() - verified_at_value))) > 300 then
    raise exception 'Play Integrity verdict is stale';
  end if;
  if not exists (
    select 1
    from public.receiver_mode_consents consent
    where consent.user_id = capability_user_id
      and consent.enabled
      and lower(coalesce(consent.momo_number_hash, '')) = clean_receiver_hash
      and consent.created_at >= now() - interval '10 minutes'
  ) then
    raise exception 'Current MoMo SMS consent is required';
  end if;

  -- Limit one live capability per user/action/receiver. Re-verification
  -- invalidates any older unused capability instead of creating a replay pool.
  update public.native_action_capabilities
  set expires_at = least(expires_at, now())
  where user_id = capability_user_id
    and action = clean_action
    and consumed_at is null
    and expires_at > now();

  insert into public.native_action_capabilities (
    user_id,
    action,
    request_hash,
    request_payload,
    receiver_momo_number_hash,
    package_name,
    app_verdict,
    device_verdicts,
    verified_at,
    expires_at
  ) values (
    capability_user_id,
    clean_action,
    clean_request_hash,
    capability_request_payload,
    clean_receiver_hash,
    clean_package_name,
    clean_app_verdict,
    coalesce(capability_device_verdicts, '{}'),
    verified_at_value,
    least(verified_at_value + interval '5 minutes', now() + interval '5 minutes')
  ) returning id into capability_id;

  return capability_id;
end;
$$;

revoke all on function public.mint_native_action_capability(
  uuid, text, text, jsonb, text, text, text, text[], timestamptz
) from public, anon, authenticated;
grant execute on function public.mint_native_action_capability(
  uuid, text, text, jsonb, text, text, text, text[], timestamptz
) to service_role;

-- The old RPC is retained as an internal implementation so its existing
-- validation remains centralized, but authenticated callers must use the
-- capability-consuming entry point below.
revoke execute on function public.create_group_with_owner(
  text, text, text, text, text, text, text, text, boolean
) from authenticated;

create or replace function public.create_group_with_owner_attested(
  group_name text,
  group_description text,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  group_collection_type text,
  group_category_subtype text,
  group_purpose_label text,
  group_is_public boolean,
  native_capability uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  capability_row public.native_action_capabilities;
  created_group_id uuid;
  clean_receiver_hash text := lower(trim(coalesce(receiver_momo_number_hash, '')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if native_capability is null or clean_receiver_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Verify this Android device before creating a group';
  end if;

  select capability.*
  into capability_row
  from public.native_action_capabilities capability
  where capability.id = native_capability
  for update;

  if capability_row.id is null
     or capability_row.user_id <> auth.uid()
     or capability_row.action <> 'group.create'
     or capability_row.receiver_momo_number_hash <> clean_receiver_hash
     or capability_row.request_payload <> jsonb_build_object(
       'group_name', trim(coalesce(group_name, '')),
       'group_description', trim(coalesce(group_description, '')),
       'receiver_momo_number', trim(coalesce(receiver_momo_number, '')),
       'receiver_momo_number_hash', clean_receiver_hash,
       'receiver_label', trim(coalesce(receiver_label, '')),
       'group_collection_type', trim(coalesce(group_collection_type, '')),
       'group_category_subtype', nullif(trim(coalesce(group_category_subtype, '')), ''),
       'group_purpose_label', nullif(trim(coalesce(group_purpose_label, '')), ''),
       'group_is_public', coalesce(group_is_public, false)
     )
     or capability_row.consumed_at is not null
     or capability_row.expires_at <= now()
     or capability_row.verified_at < now() - interval '5 minutes' then
    raise exception 'Android verification is invalid, expired, or already used';
  end if;

  update public.native_action_capabilities
  set consumed_at = now()
  where id = capability_row.id;

  created_group_id := public.create_group_with_owner(
    group_name,
    group_description,
    receiver_momo_number,
    receiver_momo_number_hash,
    receiver_label,
    group_collection_type,
    group_category_subtype,
    group_purpose_label,
    group_is_public
  );

  update public.audit_logs
  set metadata = metadata || jsonb_build_object(
    'native_capability_id', capability_row.id,
    'play_package', capability_row.package_name,
    'play_app_verdict', capability_row.app_verdict
  )
  where entity_type = 'collection'
    and entity_id = created_group_id
    and action = 'group.created';

  return created_group_id;
end;
$$;

revoke all on function public.create_group_with_owner_attested(
  text, text, text, text, text, text, text, text, boolean, uuid
) from public, anon;
grant execute on function public.create_group_with_owner_attested(
  text, text, text, text, text, text, text, text, boolean, uuid
) to authenticated;

-- Join membership and its audit/notification side effects now share one atomic
-- transition decision. A concurrent loser returns the group without emitting
-- duplicate trusted side effects.
create or replace function public.join_group_by_share_code(p_group_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_code text := lower(trim(coalesce(p_group_code, '')));
  parsed_code uuid;
  group_row public.collections;
  newly_joined boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if clean_code = '' or char_length(clean_code) > 140 then
    raise exception 'Group link is invalid';
  end if;

  if clean_code ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    parsed_code := clean_code::uuid;
    select collection.*
    into group_row
    from public.collection_share_secrets secret
    join public.collections collection on collection.id = secret.collection_id
    where secret.share_code = parsed_code;
  else
    select collection.*
    into group_row
    from public.collections collection
    where collection.slug = clean_code
      and collection.public_status = 'public_approved';
  end if;

  if group_row.id is null then
    raise exception 'Group link is invalid or has expired';
  end if;
  if group_row.archived_at is not null
     or group_row.public_status = 'archived'::public.collection_visibility then
    raise exception 'This group is archived';
  end if;
  if group_row.creator_user_id = auth.uid()
     or exists (
       select 1
       from public.collection_members active_member
       where active_member.collection_id = group_row.id
         and active_member.user_id = auth.uid()
         and active_member.status = 'active'
     ) then
    return group_row.id;
  end if;
  if exists (
    select 1
    from public.collection_members removed_member
    where removed_member.collection_id = group_row.id
      and removed_member.user_id = auth.uid()
      and removed_member.status = 'removed'
  ) then
    raise exception 'Membership was removed by a group admin';
  end if;

  insert into public.collection_members (collection_id, user_id, role, status)
  values (group_row.id, auth.uid(), 'member', 'active')
  on conflict on constraint collection_members_collection_id_user_id_role_key
  do update set status = 'active'
  where collection_members.status <> 'active'
  returning true into newly_joined;

  newly_joined := coalesce(newly_joined, false);
  if newly_joined then
    perform public.create_audit_log(
      'group.joined',
      'collection',
      group_row.id,
      jsonb_build_object(
        'join_method',
        case when parsed_code is null then 'public_slug' else 'share_code' end
      )
    );

    if group_row.creator_user_id <> auth.uid() then
      perform public.enqueue_notification_template_event(
        group_row.creator_user_id,
        'group.update.default',
        jsonb_build_object('group', group_row.title),
        group_row.id,
        '/groups/' || group_row.id::text || '/members',
        'en'
      );
    end if;
  end if;

  return group_row.id;
end;
$$;

revoke all on function public.join_group_by_share_code(text)
  from public, anon;
grant execute on function public.join_group_by_share_code(text)
  to authenticated;

-- Financial receiver rotation is creator-owner-only and derives the route from
-- the owner's verified profile. Caller-supplied numbers/hashes are used only
-- as equality assertions and can no longer redirect the authoritative route.
create or replace function public.update_collection_receiver(
  collection uuid,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text default 'Primary MOMO receiver'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  collection_row public.collections;
  clean_label text := coalesce(
    nullif(trim(receiver_label), ''),
    'Primary MOMO receiver'
  );
  submitted_digits text := regexp_replace(
    coalesce(receiver_momo_number, ''),
    '[^0-9]',
    '',
    'g'
  );
  profile_digits text;
  canonical_receiver text;
  computed_receiver_hash text;
  previous_receiver_hash text;
  previous_receiver_user_id uuid;
  receiver_is_code boolean;
  member_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select collection_row_value.*
  into collection_row
  from public.collections collection_row_value
  where collection_row_value.id = collection
  for update;

  if collection_row.id is null or collection_row.creator_user_id <> auth.uid() then
    raise exception 'Only the group owner can update the receiver';
  end if;

  receiver_is_code := lower(clean_label) like '%code%';
  if receiver_is_code then
    select regexp_replace(coalesce(profile.momo_pay_code, ''), '[^0-9]', '', 'g')
    into profile_digits
    from public.profiles profile
    where profile.id = auth.uid();
    if profile_digits !~ '^[0-9]{4,9}$' then
      raise exception 'Link a valid MoMo code to your profile first';
    end if;
    canonical_receiver := '+' || profile_digits;
  else
    select regexp_replace(coalesce(profile.momo_number, ''), '[^0-9]', '', 'g')
    into profile_digits
    from public.profiles profile
    where profile.id = auth.uid();
    if profile_digits ~ '^250[0-9]{9}$' then
      canonical_receiver := '+' || profile_digits;
    elsif profile_digits ~ '^0[0-9]{9}$' then
      canonical_receiver := '+250' || substr(profile_digits, 2);
    else
      raise exception 'Link a valid Rwanda MoMo number to your profile first';
    end if;
  end if;

  if submitted_digits <> regexp_replace(canonical_receiver, '[^0-9]', '', 'g')
     and not (
       not receiver_is_code
       and submitted_digits ~ '^0[0-9]{9}$'
       and substr(submitted_digits, 2) = substr(
         regexp_replace(canonical_receiver, '[^0-9]', '', 'g'),
         4
       )
     ) then
    raise exception 'Receiver must match the MoMo receiver linked to your profile';
  end if;

  computed_receiver_hash := encode(digest(canonical_receiver, 'sha256'), 'hex');
  if lower(trim(coalesce(receiver_momo_number_hash, ''))) <> computed_receiver_hash then
    raise exception 'Receiver verification failed';
  end if;

  select route.momo_number_hash, route.receiver_user_id
  into previous_receiver_hash, previous_receiver_user_id
  from public.collection_receivers route
  where route.collection_id = collection
    and route.is_active
  order by route.created_at desc
  limit 1;

  -- A profile-only save must not rotate an unchanged financial route or be
  -- blocked by pending intents. Label changes are non-financial metadata.
  if previous_receiver_hash = computed_receiver_hash
     and previous_receiver_user_id = auth.uid() then
    update public.collection_receivers
    set label = clean_label
    where collection_id = collection
      and is_active;
    update public.collections
    set receiver_display_label = clean_label,
        updated_at = now()
    where id = collection;
    return;
  end if;

  update public.payment_intents
  set status = 'expired'
  where collection_id = collection
    and status = 'pending'
    and expires_at <= now();
  if exists (
    select 1
    from public.payment_intents intent
    where intent.collection_id = collection
      and intent.status = 'pending'
  ) then
    raise exception 'Receiver cannot change while contribution requests are pending';
  end if;

  update public.collection_receivers
  set is_active = false
  where collection_id = collection
    and is_active;

  insert into public.collection_receivers (
    collection_id,
    receiver_user_id,
    momo_number,
    momo_number_hash,
    label,
    is_active
  ) values (
    collection,
    auth.uid(),
    canonical_receiver,
    computed_receiver_hash,
    clean_label,
    true
  );

  update public.collections
  set receiver_display_label = clean_label,
      updated_at = now()
  where id = collection;

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  ) values (
    auth.uid(),
    'collection.receiver_updated',
    'collection',
    collection,
    jsonb_build_object(
      'receiver_label', clean_label,
      'previous_receiver_hash', previous_receiver_hash,
      'new_receiver_hash', computed_receiver_hash,
      'profile_derived', true,
      'owner_only', true
    )
  );

  for member_user_id in
    select distinct member.user_id
    from public.collection_members member
    where member.collection_id = collection
      and member.status = 'active'
      and member.user_id <> auth.uid()
  loop
    perform public.enqueue_notification_template_event(
      member_user_id,
      'group.update.default',
      jsonb_build_object('group', collection_row.title),
      collection,
      '/groups/' || collection::text,
      'en'
    );
  end loop;
end;
$$;

revoke all on function public.update_collection_receiver(uuid, text, text, text)
  from public, anon;
grant execute on function public.update_collection_receiver(uuid, text, text, text)
  to authenticated;

revoke execute on function public.update_collection_profile(
  uuid, text, text, text, text, boolean, text, text, text, text, boolean
) from authenticated;

create or replace function public.update_collection_profile_and_receiver(
  collection uuid,
  group_name text,
  group_description text,
  group_image_url text,
  group_accent_color_hex text,
  group_is_public boolean,
  group_recurring_cadence text,
  group_collection_type text,
  group_category_subtype text,
  group_purpose_label text,
  group_is_recurring boolean,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (
    select 1
    from public.collections collection_row
    where collection_row.id = collection
      and collection_row.creator_user_id = auth.uid()
      and collection_row.archived_at is null
  ) then
    raise exception 'Only the current group owner can update group settings';
  end if;

  perform public.update_collection_profile(
    collection,
    group_name,
    group_description,
    group_image_url,
    group_accent_color_hex,
    group_is_public,
    group_recurring_cadence,
    group_collection_type,
    group_category_subtype,
    group_purpose_label,
    group_is_recurring
  );
  perform public.update_collection_receiver(
    collection,
    receiver_momo_number,
    receiver_momo_number_hash,
    receiver_label
  );
end;
$$;

revoke all on function public.update_collection_profile_and_receiver(
  uuid, text, text, text, text, boolean, text, text, text, text, boolean,
  text, text, text
) from public, anon;
grant execute on function public.update_collection_profile_and_receiver(
  uuid, text, text, text, text, boolean, text, text, text, text, boolean,
  text, text, text
) to authenticated;

drop view if exists public.member_contributions_view;
create view public.member_contributions_view
with (security_invoker = true)
as
select
  payment.collection_id,
  payment.id as payment_id,
  payment.amount_rwf,
  payment.currency,
  payment.status,
  payment.source,
  case
    when payment.contributor_user_id = auth.uid()
      or public.user_is_collection_admin(payment.collection_id, auth.uid())
      then payment.transaction_id
    else null
  end as transaction_id,
  payment.posted_at,
  payment.created_at,
  payment.contributor_user_id = auth.uid() as is_current_user_contribution,
  case
    when payment.contributor_user_id = auth.uid() then 'You'
    when payment.anonymity_choice = 'public_id'
      and payment.contributor_public_id is not null
      then 'Collect ID ' || payment.contributor_public_id
    else 'Anonymous supporter'
  end as supporter_label
from public.payments payment
where payment.status = 'posted'
  and public.user_can_read_collection(payment.collection_id, auth.uid());

revoke all on public.member_contributions_view from public, anon;
grant select on public.member_contributions_view to authenticated;

-- supporter_count means distinct contributors with a posted contribution, not
-- the number of active group memberships.
create or replace function public.list_current_user_collection_summaries()
returns table (
  collection_id uuid,
  amount_raised_rwf bigint,
  supporter_count bigint,
  current_user_balance_rwf bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    collection.id,
    coalesce((
      select sum(entry.amount_rwf)
      from public.ledger_entries entry
      where entry.collection_id = collection.id
        and entry.entry_type = 'collection_credit'
    ), 0)::bigint,
    coalesce((
      select count(distinct coalesce(
        payment.contributor_user_id::text,
        payment.transaction_id,
        payment.id::text
      ))
      from public.payments payment
      where payment.collection_id = collection.id
        and payment.status = 'posted'
    ), 0)::bigint,
    coalesce((
      select sum(entry.amount_rwf)
      from public.ledger_entries entry
      where entry.collection_id = collection.id
        and entry.entry_type = 'member_credit'
        and entry.user_id = auth.uid()
    ), 0)::bigint
  from public.collections collection
  where auth.uid() is not null
    and collection.archived_at is null
    and public.user_can_read_collection(collection.id, auth.uid());
$$;

revoke all on function public.list_current_user_collection_summaries()
  from public, anon;
grant execute on function public.list_current_user_collection_summaries()
  to authenticated;

-- Include the state fields consumed by the collection approval and moderation
-- controls so live admin UI cannot silently hide authorized actions.
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
      'receiver_display_label', collection.receiver_display_label,
      'visibility', collection.visibility,
      'public_status', collection.public_status,
      'status', case
        when collection.archived_at is not null
          or collection.public_status = 'archived'::public.collection_visibility
          then 'archived'
        else 'active'
      end,
      'archived_at', collection.archived_at,
      'created_at', collection.created_at,
      'updated_at', collection.updated_at,
      'active_receivers', (
        select count(*)
        from public.collection_receivers receiver
        where receiver.collection_id = collection.id
          and receiver.is_active
      ),
      'active_members', (
        select count(*)
        from public.collection_members member
        where member.collection_id = collection.id
          and member.status = 'active'
      ),
      'pending_payment_intents', (
        select count(*)
        from public.payment_intents intent
        where intent.collection_id = collection.id
          and intent.status = 'pending'
      )
    )
    from public.collections collection
    left join public.profiles profile on profile.id = collection.creator_user_id
    where collection.id = p_id
  ), '{}'::jsonb);
end;
$$;

revoke all on function public.admin_get_collection(uuid)
  from public, anon;
grant execute on function public.admin_get_collection(uuid)
  to authenticated;

commit;
