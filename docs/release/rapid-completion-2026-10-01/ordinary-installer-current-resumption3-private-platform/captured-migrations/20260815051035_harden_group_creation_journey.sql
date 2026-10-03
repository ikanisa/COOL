begin;

-- Applied to production through the Supabase migration API as version
-- 20260815051035; keep this filename aligned with remote migration history.

-- SMS-first removed the legacy public-request queue and its permissions, but
-- later group-support RPCs continued to require those deleted permission keys.
-- Restore only the two action permissions needed by the current group workflow.
insert into public.admin_permissions (name, description)
values
  ('public_requests.review', 'Approve or reject a group public-discovery request'),
  ('collections.moderate', 'Set private or archive a group')
on conflict (name) do update set description = excluded.description;

insert into public.admin_role_permissions (role_id, permission_name)
select role.id, permission.permission_name
from public.admin_roles role
cross join (
  values
    ('group_ops_admin', 'public_requests.review'),
    ('group_ops_admin', 'collections.moderate'),
    ('platform_owner', 'public_requests.review'),
    ('platform_owner', 'collections.moderate')
) as permission(role_name, permission_name)
where role.name = permission.role_name
on conflict (role_id, permission_name) do nothing;

-- Private groups use an independently rotatable, high-entropy bearer code.
-- Keeping the code outside `collections` prevents ordinary table SELECT grants
-- from exposing private invitations when new columns are added.
create table if not exists public.collection_share_secrets (
  collection_id uuid primary key references public.collections(id) on delete cascade,
  share_code uuid not null default gen_random_uuid(),
  rotated_at timestamptz not null default now(),
  rotated_by uuid references public.profiles(id) on delete set null,
  unique (share_code)
);

alter table public.collection_share_secrets enable row level security;
revoke all on table public.collection_share_secrets
  from public, anon, authenticated;

insert into public.collection_share_secrets (collection_id, rotated_by)
select c.id, c.creator_user_id
from public.collections c
where not exists (
  select 1
  from public.collection_share_secrets secret
  where secret.collection_id = c.id
);

create or replace function public.get_group_share_code(p_collection_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  code uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.user_can_read_collection(p_collection_id, auth.uid())
     or not exists (
       select 1
       from public.collections c
       where c.id = p_collection_id
         and c.archived_at is null
         and (
           c.creator_user_id = auth.uid()
           or exists (
             select 1
             from public.collection_members member_check
             where member_check.collection_id = c.id
               and member_check.user_id = auth.uid()
               and member_check.status = 'active'
           )
         )
     ) then
    raise exception 'Active group membership required';
  end if;

  select secret.share_code
  into code
  from public.collection_share_secrets secret
  where secret.collection_id = p_collection_id;

  if code is null then
    raise exception 'Group share code not found';
  end if;
  return code::text;
end;
$$;

revoke all on function public.get_group_share_code(uuid)
  from public, anon;
grant execute on function public.get_group_share_code(uuid)
  to authenticated;

create or replace function public.rotate_group_share_code(p_collection_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  code uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.user_is_collection_admin(p_collection_id, auth.uid()) then
    raise exception 'Only group admins can rotate the share link';
  end if;
  if exists (
    select 1 from public.collections c
    where c.id = p_collection_id and c.archived_at is not null
  ) then
    raise exception 'Archived groups cannot be shared';
  end if;

  insert into public.collection_share_secrets (
    collection_id,
    share_code,
    rotated_at,
    rotated_by
  )
  values (p_collection_id, gen_random_uuid(), now(), auth.uid())
  on conflict (collection_id) do update
  set share_code = gen_random_uuid(),
      rotated_at = now(),
      rotated_by = auth.uid()
  returning share_code into code;

  perform public.create_audit_log(
    'group.share_link_rotated',
    'collection',
    p_collection_id,
    jsonb_build_object('rotated_at', now())
  );
  return code::text;
end;
$$;

revoke all on function public.rotate_group_share_code(uuid)
  from public, anon;
grant execute on function public.rotate_group_share_code(uuid)
  to authenticated;

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
    select c.*
    into group_row
    from public.collection_share_secrets secret
    join public.collections c on c.id = secret.collection_id
    where secret.share_code = parsed_code;
  else
    -- Slug joining is discovery-only. Private slugs are not bearer secrets.
    select c.*
    into group_row
    from public.collections c
    where c.slug = clean_code
      and c.public_status = 'public_approved';
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
  do update set status = 'active';
  newly_joined := true;

  perform public.create_audit_log(
    'group.joined',
    'collection',
    group_row.id,
    jsonb_build_object('join_method', case when parsed_code is null then 'public_slug' else 'share_code' end)
  );

  if newly_joined and group_row.creator_user_id <> auth.uid() then
    perform public.enqueue_notification_template_event(
      group_row.creator_user_id,
      'group.update.default',
      jsonb_build_object('group', group_row.title),
      group_row.id,
      '/groups/' || group_row.id::text || '/members',
      'en'
    );
  end if;

  return group_row.id;
end;
$$;

revoke all on function public.join_group_by_share_code(text)
  from public, anon;
grant execute on function public.join_group_by_share_code(text)
  to authenticated;

-- Replace the legacy slug join entry point with the safe semantics so older
-- clients cannot use a visible private slug or reactivate removed membership.
create or replace function public.join_group_by_slug(group_slug text)
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.join_group_by_share_code(group_slug);
$$;

revoke all on function public.join_group_by_slug(text)
  from public, anon;
grant execute on function public.join_group_by_slug(text)
  to authenticated;

drop function if exists public.create_group_with_owner(
  text, text, text, text, text, text, text, text
);

create function public.create_group_with_owner(
  group_name text,
  group_description text default '',
  receiver_momo_number text default null,
  receiver_momo_number_hash text default null,
  receiver_label text default 'Primary MoMo receiver',
  group_collection_type text default 'ikimina',
  group_category_subtype text default null,
  group_purpose_label text default null,
  group_is_public boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  created_group_id uuid;
  base_slug text;
  final_slug text;
  catalog_choice jsonb;
  clean_type text;
  clean_subtype text;
  clean_purpose_label text;
  clean_title text := trim(coalesce(group_name, ''));
  clean_description text := trim(coalesce(group_description, ''));
  clean_receiver_label text := trim(coalesce(receiver_label, ''));
  receiver_digits text := regexp_replace(coalesce(receiver_momo_number, ''), '[^0-9]', '', 'g');
  profile_receiver_digits text;
  canonical_receiver text;
  computed_receiver_hash text;
  receiver_is_code boolean;
  next_visibility public.collection_visibility := case
    when coalesce(group_is_public, false) then 'public_requested'::public.collection_visibility
    else 'private'::public.collection_visibility
  end;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if char_length(clean_title) not between 3 and 120 then
    raise exception 'Group name must be between 3 and 120 characters';
  end if;
  if char_length(clean_description) > 1000 then
    raise exception 'Group description must be 1000 characters or fewer';
  end if;
  if clean_receiver_label = '' or receiver_digits = '' then
    raise exception 'A linked MoMo receiver is required';
  end if;
  if not coalesce((
    select consent.enabled
    from public.receiver_mode_consents consent
    where consent.user_id = auth.uid()
    order by consent.created_at desc, consent.id desc
    limit 1
  ), false) then
    raise exception 'Enable MoMo SMS access before creating a group';
  end if;

  receiver_is_code := lower(clean_receiver_label) like '%code%';
  if receiver_is_code then
    if receiver_digits !~ '^[0-9]{4,9}$' then
      raise exception 'MoMo code must be between 4 and 9 digits';
    end if;
    select regexp_replace(coalesce(p.momo_pay_code, ''), '[^0-9]', '', 'g')
    into profile_receiver_digits
    from public.profiles p
    where p.id = auth.uid();
    canonical_receiver := '+' || receiver_digits;
  else
    if receiver_digits ~ '^250[0-9]{9}$' then
      canonical_receiver := '+' || receiver_digits;
    elsif receiver_digits ~ '^0[0-9]{9}$' then
      canonical_receiver := '+250' || substr(receiver_digits, 2);
    else
      raise exception 'Use a valid Rwanda MoMo number';
    end if;
    select regexp_replace(coalesce(p.momo_number, ''), '[^0-9]', '', 'g')
    into profile_receiver_digits
    from public.profiles p
    where p.id = auth.uid();
    if profile_receiver_digits ~ '^250[0-9]{9}$' then
      profile_receiver_digits := substr(profile_receiver_digits, 4);
    elsif profile_receiver_digits ~ '^0[0-9]{9}$' then
      profile_receiver_digits := substr(profile_receiver_digits, 2);
    end if;
    if receiver_digits ~ '^250' then
      receiver_digits := substr(receiver_digits, 4);
    elsif receiver_digits ~ '^0' then
      receiver_digits := substr(receiver_digits, 2);
    end if;
  end if;

  if coalesce(profile_receiver_digits, '') = ''
     or profile_receiver_digits <> receiver_digits then
    raise exception 'Group receiver must match the MoMo receiver linked to your profile';
  end if;

  computed_receiver_hash := encode(digest(canonical_receiver, 'sha256'), 'hex');
  if nullif(trim(coalesce(receiver_momo_number_hash, '')), '') is not null
     and lower(trim(receiver_momo_number_hash)) <> computed_receiver_hash then
    raise exception 'Receiver verification failed';
  end if;

  catalog_choice := public.resolve_collection_catalog_choice(
    group_collection_type,
    group_category_subtype,
    group_purpose_label,
    'RW'
  );
  clean_type := catalog_choice->>'collection_type';
  clean_subtype := catalog_choice->>'category_subtype';
  clean_purpose_label := catalog_choice->>'purpose_label';

  base_slug := public.normalize_slug(clean_title);
  if base_slug = '' then base_slug := 'group'; end if;
  final_slug := base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);

  insert into public.collections (
    slug,
    creator_user_id,
    title,
    description,
    collection_type,
    category_subtype,
    purpose_label,
    receiver_display_label,
    visibility,
    public_status
  ) values (
    final_slug,
    auth.uid(),
    clean_title,
    clean_description,
    clean_type,
    clean_subtype,
    clean_purpose_label,
    clean_receiver_label,
    case
      when next_visibility = 'public_approved' then 'public_approved'::public.collection_visibility
      else 'private'::public.collection_visibility
    end,
    next_visibility
  ) returning id into created_group_id;

  insert into public.collection_members (collection_id, user_id, role, status)
  values (created_group_id, auth.uid(), 'owner', 'active');

  insert into public.collection_receivers (
    collection_id,
    receiver_user_id,
    momo_number,
    momo_number_hash,
    label
  ) values (
    created_group_id,
    auth.uid(),
    trim(receiver_momo_number),
    computed_receiver_hash,
    clean_receiver_label
  );

  insert into public.collection_share_secrets (collection_id, rotated_by)
  values (created_group_id, auth.uid());

  perform public.create_audit_log(
    'group.created',
    'collection',
    created_group_id,
    jsonb_build_object(
      'collection_type', clean_type,
      'category_subtype', clean_subtype,
      'purpose_label', clean_purpose_label,
      'public_status', next_visibility::text,
      'sms_access_verified', true
    )
  );
  return created_group_id;
end;
$$;

revoke all on function public.create_group_with_owner(
  text, text, text, text, text, text, text, text, boolean
) from public, anon;
grant execute on function public.create_group_with_owner(
  text, text, text, text, text, text, text, text, boolean
) to authenticated;

drop function if exists public.update_collection_profile(
  uuid, text, text, text, text, boolean, text, text, text, text
);

create function public.update_collection_profile(
  collection uuid,
  group_name text,
  group_description text,
  group_image_url text default null,
  group_accent_color_hex text default null,
  group_is_public boolean default false,
  group_recurring_cadence text default 'monthly',
  group_collection_type text default null,
  group_category_subtype text default null,
  group_purpose_label text default null,
  group_is_recurring boolean default true
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  clean_name text := trim(coalesce(group_name, ''));
  clean_description text := trim(coalesce(group_description, ''));
  clean_cadence text := coalesce(nullif(trim(group_recurring_cadence), ''), 'monthly');
  clean_type text;
  clean_subtype text;
  clean_purpose_label text;
  catalog_choice jsonb;
  current_row public.collections;
  next_public_status public.collection_visibility;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can update the group profile';
  end if;
  if char_length(clean_name) not between 3 and 120 then
    raise exception 'Group name must be between 3 and 120 characters';
  end if;
  if char_length(clean_description) > 1000 then
    raise exception 'Group description must be 1000 characters or fewer';
  end if;
  if clean_cadence not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unsupported recurring cadence';
  end if;

  select c.* into current_row from public.collections c where c.id = collection;
  if current_row.id is null then raise exception 'Group not found'; end if;
  if current_row.archived_at is not null then raise exception 'Archived groups cannot be updated'; end if;

  next_public_status := case
    when not coalesce(group_is_public, false) then 'private'::public.collection_visibility
    when current_row.public_status = 'public_approved' then 'public_approved'::public.collection_visibility
    else 'public_requested'::public.collection_visibility
  end;

  catalog_choice := public.resolve_collection_catalog_choice(
    coalesce(nullif(trim(group_collection_type), ''), current_row.collection_type),
    coalesce(nullif(trim(group_category_subtype), ''), current_row.category_subtype),
    coalesce(nullif(trim(group_purpose_label), ''), current_row.purpose_label),
    'RW'
  );
  clean_type := catalog_choice->>'collection_type';
  clean_subtype := catalog_choice->>'category_subtype';
  clean_purpose_label := catalog_choice->>'purpose_label';

  update public.collections
  set title = clean_name,
      description = clean_description,
      cover_image_url = nullif(trim(group_image_url), ''),
      accent_color_hex = nullif(trim(group_accent_color_hex), ''),
      public_status = next_public_status,
      visibility = case
        when next_public_status = 'public_approved' then 'public_approved'::public.collection_visibility
        else 'private'::public.collection_visibility
      end,
      is_recurring = coalesce(group_is_recurring, false),
      recurring_cadence = clean_cadence,
      recurring_rule = case
        when coalesce(group_is_recurring, false)
          then jsonb_build_object('cadence', clean_cadence)
        else null
      end,
      collection_type = clean_type,
      category_subtype = clean_subtype,
      purpose_label = clean_purpose_label,
      updated_at = now()
  where id = collection;

  perform public.create_audit_log(
    'collection.profile_updated',
    'collection',
    collection,
    jsonb_build_object(
      'public_status', next_public_status::text,
      'is_recurring', coalesce(group_is_recurring, false),
      'recurring_cadence', clean_cadence,
      'collection_type', clean_type,
      'category_subtype', clean_subtype,
      'purpose_label', clean_purpose_label
    )
  );
end;
$$;

revoke all on function public.update_collection_profile(
  uuid, text, text, text, text, boolean, text, text, text, text, boolean
) from public, anon;
grant execute on function public.update_collection_profile(
  uuid, text, text, text, text, boolean, text, text, text, text, boolean
) to authenticated;

create or replace function public.admin_update_collection_support_status(
  p_collection_id uuid,
  p_status text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_row public.collections;
  owner_user_id uuid;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Reason is required'; end if;
  if p_status not in ('private', 'public_approved', 'public_rejected', 'archived') then
    raise exception 'Unsupported collection support status';
  end if;
  if p_status in ('public_approved', 'public_rejected') then
    perform public.assert_admin_permission('public_requests.review');
  else
    perform public.assert_admin_permission('collections.moderate');
  end if;

  select c.* into current_row from public.collections c where c.id = p_collection_id;
  if current_row.id is null then raise exception 'Collection not found'; end if;
  if p_status in ('public_approved', 'public_rejected')
     and current_row.public_status <> 'public_requested'::public.collection_visibility then
    raise exception 'Group does not have a pending public request';
  end if;

  update public.collections
  set public_status = p_status::public.collection_visibility,
      visibility = case
        when p_status = 'public_approved' then 'public_approved'::public.collection_visibility
        when p_status = 'archived' then 'archived'::public.collection_visibility
        else 'private'::public.collection_visibility
      end,
      archived_at = case when p_status = 'archived' then now() else null end,
      updated_at = now()
  where id = p_collection_id
  returning creator_user_id into owner_user_id;

  perform public.create_audit_log(
    'collection.support_status.updated',
    'collection',
    p_collection_id,
    jsonb_build_object('status', p_status, 'reason', trim(p_reason))
  );

  perform public.enqueue_notification_template_event(
    owner_user_id,
    'group.update.default',
    jsonb_build_object('group', current_row.title),
    p_collection_id,
    '/groups/' || p_collection_id::text,
    'en'
  );
  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;

revoke all on function public.admin_update_collection_support_status(uuid, text, text)
  from public, anon;
grant execute on function public.admin_update_collection_support_status(uuid, text, text)
  to authenticated;

-- Server-owned totals ensure an ordinary member sees the group balance without
-- receiving another member's private payment or payer identity.
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
    c.id,
    coalesce((
      select sum(entry.amount_rwf)
      from public.ledger_entries entry
      where entry.collection_id = c.id
        and entry.entry_type = 'collection_credit'
    ), 0)::bigint,
    coalesce((
      select count(distinct member_row.user_id)
      from public.collection_members member_row
      where member_row.collection_id = c.id
        and member_row.status = 'active'
    ), 0)::bigint,
    coalesce((
      select sum(entry.amount_rwf)
      from public.ledger_entries entry
      where entry.collection_id = c.id
        and entry.entry_type = 'member_credit'
        and entry.user_id = auth.uid()
    ), 0)::bigint
  from public.collections c
  where auth.uid() is not null
    and c.archived_at is null
    and public.user_can_read_collection(c.id, auth.uid());
$$;

revoke all on function public.list_current_user_collection_summaries()
  from public, anon;
grant execute on function public.list_current_user_collection_summaries()
  to authenticated;

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
    from public.collections c
    where c.id = new.collection_id
      and c.archived_at is null
      and (
        c.creator_user_id = new.contributor_user_id
        or exists (
          select 1
          from public.collection_members member_check
          where member_check.collection_id = c.id
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

drop trigger if exists enforce_active_contributor_membership_trigger
  on public.payment_intents;
create trigger enforce_active_contributor_membership_trigger
before insert or update of collection_id, contributor_user_id
on public.payment_intents
for each row execute function public.enforce_active_contributor_membership();
revoke all on function public.enforce_active_contributor_membership()
  from public, anon, authenticated;

-- Qualify the requested collection through a uniquely named local variable.
-- The prior function compared `collection_id = collection`, which PostgreSQL
-- correctly rejected as ambiguous once invoked.
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
  receiver_row public.collection_receivers;
  intent_row public.payment_intents;
  member_public_id char(6);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1
    from public.collections c
    where c.id = requested_collection_id
      and c.archived_at is null
      and (
        c.creator_user_id = auth.uid()
        or exists (
          select 1
          from public.collection_members member_check
          where member_check.collection_id = c.id
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
  if nullif(trim(p_sender_phone_hash), '') is null then
    raise exception 'Contributor MoMo identity is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'contribution-intent:' || auth.uid()::text || ':' || requested_collection_id::text,
    0
  ));
  update public.payment_intents intent
  set status = 'expired'
  where intent.contributor_user_id = auth.uid()
    and intent.collection_id = requested_collection_id
    and intent.status = 'pending'
    and intent.expires_at <= now();

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
    and intent.sender_phone_hash = trim(p_sender_phone_hash)
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
      trim(p_sender_phone_hash)
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

create or replace function public.list_current_user_payment_intents()
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
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.payment_intents intent
  set status = 'expired'
  where intent.contributor_user_id = auth.uid()
    and intent.status = 'pending'
    and intent.expires_at <= now();
  return query
  select
    intent.id,
    intent.collection_id,
    intent.expected_amount_rwf,
    receiver.momo_number,
    intent.receiver_momo_number_hash,
    receiver.label,
    receiver.network,
    intent.sender_phone_hash,
    intent.status,
    intent.contributor_public_id,
    intent.created_at,
    intent.expires_at
  from public.payment_intents intent
  join lateral (
    select route.momo_number, route.label, route.network
    from public.collection_receivers route
    where route.collection_id = intent.collection_id
      and route.momo_number_hash = intent.receiver_momo_number_hash
    order by route.created_at desc
    limit 1
  ) receiver on true
  where intent.contributor_user_id = auth.uid()
  order by intent.created_at desc
  limit 100;
end;
$$;

revoke all on function public.list_current_user_payment_intents()
  from public, anon;
grant execute on function public.list_current_user_payment_intents()
  to authenticated;

create or replace view public.member_collections_view
with (security_invoker = true)
as
select
  c.id,
  c.slug,
  c.creator_user_id,
  c.title,
  c.description,
  c.currency,
  c.collection_type,
  c.category_subtype,
  c.purpose_label,
  c.suggested_amount_rwf,
  c.diaspora_enabled,
  c.diaspora_regions,
  case when c.archived_at is not null then 'archived' else c.moderation_status end as moderation_status,
  case
    when public.user_is_collection_admin(c.id, auth.uid())
      or exists (
        select 1 from public.collection_receivers receiver_check
        where receiver_check.collection_id = c.id
          and receiver_check.receiver_user_id = auth.uid()
          and receiver_check.is_active
      ) then cr.momo_number
    else null
  end as receiver_momo_number,
  case when public.user_can_read_collection(c.id, auth.uid()) then cr.label else null end
    as receiver_display_label,
  cr.network as receiver_network,
  c.created_at,
  c.updated_at,
  c.archived_at,
  c.accent_color_hex,
  c.recurring_cadence,
  c.public_status = 'public_approved' as is_public,
  (
    c.creator_user_id = auth.uid()
    or exists (
      select 1 from public.collection_members member_check
      where member_check.collection_id = c.id
        and member_check.user_id = auth.uid()
        and member_check.status = 'active'
    )
  ) as is_member,
  c.is_recurring,
  c.public_status::text as visibility_status
from public.collections c
left join lateral (
  select receiver.momo_number, receiver.label, receiver.network
  from public.collection_receivers receiver
  where receiver.collection_id = c.id and receiver.is_active
  order by receiver.created_at asc
  limit 1
) cr on true
where public.user_can_read_collection(c.id, auth.uid());

alter view public.member_collections_view set (security_invoker = true);
revoke all on public.member_collections_view from public, anon;
grant select on public.member_collections_view to authenticated;

commit;
