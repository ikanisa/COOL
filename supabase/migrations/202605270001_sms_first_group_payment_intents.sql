-- Align Collect with the SMS-first Groups product contract.
-- Contributions are allocated from pending payment intents and parsed MoMo SMS.
-- Members do not manually report payment references or choose identities.

alter table payment_intents
  add column if not exists contributor_public_id char(6);

alter table collections
  alter column category set default 'Other';

update payment_intents pi
set contributor_public_id = p.public_id
from profiles p
where pi.contributor_user_id = p.id
  and pi.contributor_public_id is null;

create index if not exists payment_intents_member_sms_match_idx
  on payment_intents (
    status,
    receiver_momo_number_hash,
    expected_amount_rwf,
    contributor_public_id,
    created_at
  );

drop function if exists create_payment_intent(uuid, bigint, text, text);
drop function if exists create_payment_intent_with_instructions(uuid, bigint, text, text);
drop function if exists create_contribution_intent(uuid, bigint, text);

alter table payment_allocations
  drop constraint if exists payment_allocations_allocation_method_check;

alter table payment_allocations
  add constraint payment_allocations_allocation_method_check
  check (
    allocation_method in (
      'auto_member_intent',
      'auto_code',
      'auto_unique_amount_time',
      'system_exception'
    )
  ) not valid;

create or replace function create_group_with_owner(
  group_name text,
  group_description text default '',
  receiver_momo_number text default null,
  receiver_momo_number_hash text default null,
  receiver_label text default 'Primary MOMO receiver'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_group_id uuid;
  base_slug text;
  final_slug text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  base_slug := normalize_slug(group_name);
  if base_slug = '' then
    base_slug := 'group';
  end if;
  final_slug := base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into collections (
    slug,
    creator_user_id,
    title,
    description,
    receiver_display_label
  )
  values (
    final_slug,
    auth.uid(),
    group_name,
    coalesce(group_description, ''),
    receiver_label
  )
  returning id into created_group_id;

  insert into collection_members (collection_id, user_id, role, status)
  values (created_group_id, auth.uid(), 'owner', 'active');

  if receiver_momo_number is not null and receiver_momo_number_hash is not null then
    insert into collection_receivers (
      collection_id,
      receiver_user_id,
      momo_number,
      momo_number_hash,
      label
    )
    values (
      created_group_id,
      auth.uid(),
      receiver_momo_number,
      receiver_momo_number_hash,
      receiver_label
    );
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id)
  values (auth.uid(), 'group.created', 'collection', created_group_id);

  return created_group_id;
end;
$$;

create or replace function create_payment_intent(
  collection uuid,
  expected_amount_rwf bigint default null,
  sender_phone_hash text default null
)
returns payment_intents
language plpgsql
security definer
set search_path = public
as $$
declare
  receiver_hash text;
  member_public_id char(6);
  intent payment_intents;
begin
  if not public.user_can_read_collection(collection, auth.uid()) then
    raise exception 'Group is not available';
  end if;

  if expected_amount_rwf is null or expected_amount_rwf <= 0 then
    raise exception 'Contribution amount must be above zero';
  end if;

  select p.public_id into member_public_id
  from profiles p
  where p.id = auth.uid();

  if member_public_id is null then
    raise exception 'Collect ID is required before contributing';
  end if;

  select cr.momo_number_hash
    into receiver_hash
  from collection_receivers cr
  where cr.collection_id = collection and cr.is_active
  order by cr.created_at
  limit 1;

  if receiver_hash is null then
    raise exception 'Group has no active receiver';
  end if;

  insert into payment_intents (
    collection_id,
    contributor_user_id,
    contributor_public_id,
    contribution_code,
    expected_amount_rwf,
    receiver_momo_number_hash,
    sender_phone_hash
  )
  values (
    collection,
    auth.uid(),
    member_public_id,
    generate_contribution_code(),
    expected_amount_rwf,
    receiver_hash,
    null
  )
  returning * into intent;

  return intent;
end;
$$;

create or replace function create_contribution_intent(
  collection uuid,
  p_expected_amount_rwf bigint default null,
  p_sender_phone_hash text default null
)
returns table (
  id uuid,
  collection_id uuid,
  contribution_code text,
  expected_amount_rwf bigint,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  network text,
  sender_phone_hash text,
  status payment_intent_status,
  contributor_public_id char(6),
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  receiver_row collection_receivers;
  intent_row payment_intents;
  member_public_id char(6);
begin
  if not public.user_can_read_collection(collection, auth.uid()) then
    raise exception 'Group is not available';
  end if;

  if p_expected_amount_rwf is null or p_expected_amount_rwf <= 0 then
    raise exception 'Contribution amount must be above zero';
  end if;

  select p.public_id into member_public_id
  from profiles p
  where p.id = auth.uid();

  if member_public_id is null then
    raise exception 'Collect ID is required before contributing';
  end if;

  select *
    into receiver_row
  from collection_receivers cr
  where cr.collection_id = collection and cr.is_active
  order by cr.created_at
  limit 1;

  if receiver_row.id is null then
    raise exception 'Group has no active receiver';
  end if;

  insert into payment_intents (
    collection_id,
    contributor_user_id,
    contributor_public_id,
    contribution_code,
    expected_amount_rwf,
    receiver_momo_number_hash,
    sender_phone_hash
  )
  values (
    collection,
    auth.uid(),
    member_public_id,
    generate_contribution_code(),
    p_expected_amount_rwf,
    receiver_row.momo_number_hash,
    null
  )
  returning * into intent_row;

  return query select
    intent_row.id,
    intent_row.collection_id,
    intent_row.contribution_code,
    intent_row.expected_amount_rwf,
    receiver_row.momo_number,
    intent_row.receiver_momo_number_hash,
    receiver_row.label,
    receiver_row.network,
    null::text,
    intent_row.status,
    intent_row.contributor_public_id,
    intent_row.created_at,
    intent_row.expires_at;
end;
$$;

create or replace function join_group_by_slug(group_slug text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select c.id into group_id
  from collections c
  where c.slug = group_slug;

  if group_id is null then
    raise exception 'Group not found';
  end if;

  if not exists (
    select 1
    from collection_members cm
    where cm.collection_id = group_id
      and cm.user_id = auth.uid()
      and cm.status = 'active'
  ) then
    insert into collection_members (collection_id, user_id, role, status)
    values (group_id, auth.uid(), 'member', 'active')
    on conflict on constraint collection_members_collection_id_user_id_role_key do update
      set status = 'active';

    insert into audit_logs (actor_user_id, action, entity_type, entity_id)
    values (auth.uid(), 'group.joined', 'collection', group_id);
  end if;

  return group_id;
end;
$$;

create or replace function allocate_parsed_payment_event(event_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row parsed_payment_events;
  match_intent_id uuid;
  match_collection_id uuid;
  possible_count int;
begin
  select * into event_row from parsed_payment_events where id = event_id for update;
  if not found then
    raise exception 'Parsed event not found';
  end if;

  if event_row.allocation_status = 'allocated' then
    return 'already_allocated';
  end if;

  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.confidence < 0.72 then
    update parsed_payment_events
      set allocation_status = 'needs_review',
          review_reason = 'Parser result is not reliable enough for automated allocation'
      where id = event_id;
    return 'needs_review';
  end if;

  if event_row.detected_user_public_id is not null
     and event_row.receiver_phone_hash is not null then
    select id, collection_id into match_intent_id, match_collection_id
    from payment_intents
    where status = 'pending'
      and receiver_momo_number_hash = event_row.receiver_phone_hash
      and expected_amount_rwf = event_row.amount_rwf
      and contributor_public_id = event_row.detected_user_public_id
      and event_row.created_at between created_at - interval '15 minutes'
        and expires_at + interval '2 hours'
    order by created_at
    limit 1;

    if match_intent_id is not null then
      perform post_payment_from_event(
        event_id,
        match_intent_id,
        match_collection_id,
        'auto_member_intent',
        'Matched by pending payment intent, receiver, amount, and Collect ID'
      );
      return 'allocated';
    end if;
  end if;

  if event_row.detected_collection_code is not null then
    select id, collection_id into match_intent_id, match_collection_id
    from payment_intents
    where status = 'pending'
      and contribution_code = upper(event_row.detected_collection_code)
      and expected_amount_rwf = event_row.amount_rwf
    limit 1;
    if match_intent_id is not null then
      perform post_payment_from_event(
        event_id,
        match_intent_id,
        match_collection_id,
        'auto_code',
        'Matched by pending payment intent code and amount'
      );
      return 'allocated';
    end if;
  end if;

  if event_row.receiver_phone_hash is not null then
    select
      count(*),
      (array_agg(id order by created_at))[1],
      (array_agg(collection_id order by created_at))[1]
      into possible_count, match_intent_id, match_collection_id
    from payment_intents
    where status = 'pending'
      and receiver_momo_number_hash = event_row.receiver_phone_hash
      and expected_amount_rwf = event_row.amount_rwf
      and event_row.created_at between created_at - interval '15 minutes'
        and expires_at + interval '2 hours';

    if possible_count = 1 then
      perform post_payment_from_event(
        event_id,
        match_intent_id,
        match_collection_id,
        'auto_unique_amount_time',
        'Matched as the only pending intent for receiver, amount, and time window'
      );
      return 'allocated';
    elsif possible_count > 1 then
      update parsed_payment_events
        set allocation_status = 'ambiguous',
            review_reason = 'Multiple pending payment intents matched receiver, amount, and time window'
        where id = event_id;
      return 'ambiguous';
    end if;
  end if;

  update parsed_payment_events
    set allocation_status = 'needs_review',
        review_reason = 'No pending payment intent matched parsed MoMo SMS'
    where id = event_id;
  return 'needs_review';
end;
$$;

revoke execute on function report_payment_intent_paid(uuid, text)
  from public, anon, authenticated;

revoke execute on function manual_allocate_parsed_payment_event(uuid, uuid, uuid, text)
  from public, anon, authenticated;

revoke execute on function admin_manual_allocate_payment(uuid, uuid, uuid, text)
  from public, anon, authenticated;

revoke execute on function request_public_collection(uuid)
  from public, anon, authenticated;

revoke execute on function review_public_collection(uuid, boolean, text)
  from public, anon, authenticated;

revoke execute on function admin_review_public_request(uuid, boolean, text)
  from public, anon, authenticated;

revoke execute on function admin_list_public_requests(text, text)
  from public, anon, authenticated;

revoke execute on function admin_moderate_collection(uuid, text, text)
  from public, anon, authenticated;

revoke execute on function create_collection_with_owner(text, text, text, bigint, text, text, text, text, boolean, jsonb)
  from public, anon, authenticated;

revoke execute on function create_collection_invite(uuid, text, text, member_role)
  from public, anon, authenticated;

revoke all on public_collections_view
  from public, anon, authenticated;

revoke all on member_public_collection_requests_view
  from public, anon, authenticated;

revoke all on collection_summary_view
  from public, anon, authenticated;

revoke all on payment_instruction_templates
  from public, anon, authenticated;

drop function if exists admin_manual_allocate_payment(uuid, uuid, uuid, text);
drop function if exists manual_allocate_parsed_payment_event(uuid, uuid, uuid, text);
drop function if exists report_payment_intent_paid(uuid, text);
drop function if exists admin_moderate_collection(uuid, text, text);
drop function if exists admin_list_public_requests(text, text);
drop function if exists admin_review_public_request(uuid, boolean, text);
drop function if exists review_public_collection(uuid, boolean, text);
drop function if exists request_public_collection(uuid);
drop function if exists create_collection_invite(uuid, text, text, member_role);
drop function if exists create_collection_with_owner(text, text, text, bigint, text, text, text, text, boolean, jsonb);
drop view if exists member_public_collection_requests_view;
drop view if exists public_collections_view;
drop view if exists collection_summary_view;
drop table if exists payment_instruction_templates;
drop table if exists public_collection_requests;

create or replace function admin_current_user()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  profile_row profiles%rowtype;
begin
  if auth.uid() is null then
    return '{}'::jsonb;
  end if;

  select * into profile_row
  from profiles
  where id = auth.uid();

  if profile_row.id is null then
    return '{}'::jsonb;
  end if;

  if not exists (
    select 1
    from admin_user_roles aur
    where aur.user_id = profile_row.id
      and aur.revoked_at is null
  ) and not coalesce(profile_row.is_platform_admin, false) then
    return '{}'::jsonb;
  end if;

  return jsonb_build_object(
    'user_id', profile_row.id,
    'display_name', 'Collect ID ' || profile_row.public_id,
    'phone_masked', mask_phone(profile_row.whatsapp_phone),
    'roles', (
      select coalesce(jsonb_agg(ar.name order by ar.name), '[]'::jsonb)
      from admin_user_roles aur
      join admin_roles ar on ar.id = aur.role_id
      where aur.user_id = profile_row.id
        and aur.revoked_at is null
    ),
    'permissions', (
      select coalesce(jsonb_agg(distinct arp.permission_name order by arp.permission_name), '[]'::jsonb)
      from admin_user_roles aur
      join admin_role_permissions arp on arp.role_id = aur.role_id
      where aur.user_id = profile_row.id
        and aur.revoked_at is null
    )
  );
end;
$$;

create or replace function admin_list_collections(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('collections.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(
      _admin_row(
        c.id,
        c.title,
        coalesce(cr.label, c.receiver_display_label, 'MoMo receiver'),
        case when exists (
          select 1 from payment_intents pi
          where pi.collection_id = c.id and pi.status = 'pending'
        ) then 'pending_intents' else 'active' end,
        coalesce((
          select count(*)::text || ' members'
          from collection_members cm
          where cm.collection_id = c.id and cm.status = 'active'
        ), '0 members'),
        c.created_at,
        jsonb_build_object(
          'slug', c.slug,
          'receiver_count', (
            select count(*)
            from collection_receivers r
            where r.collection_id = c.id and r.is_active
          ),
          'pending_intents', (
            select count(*)
            from payment_intents pi
            where pi.collection_id = c.id and pi.status = 'pending'
          )
        )
      )
      order by c.created_at desc
    )
    from collections c
    left join lateral (
      select label
      from collection_receivers r
      where r.collection_id = c.id and r.is_active
      order by r.created_at desc
      limit 1
    ) cr on true
    where (p_search is null or c.title ilike '%' || p_search || '%' or c.slug ilike '%' || p_search || '%')
      and (p_status is null or p_status in ('active', 'pending_intents'))
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_get_collection(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('collections.read');
  return coalesce((
    select jsonb_build_object(
      'id', c.id,
      'slug', c.slug,
      'title', c.title,
      'description', c.description,
      'creator_user_id', c.creator_user_id,
      'creator_label', 'Collect ID ' || p.public_id,
      'receiver_display_label', c.receiver_display_label,
      'created_at', c.created_at,
      'updated_at', c.updated_at,
      'active_receivers', (
        select count(*)
        from collection_receivers r
        where r.collection_id = c.id and r.is_active
      ),
      'active_members', (
        select count(*)
        from collection_members cm
        where cm.collection_id = c.id and cm.status = 'active'
      ),
      'pending_payment_intents', (
        select count(*)
        from payment_intents pi
        where pi.collection_id = c.id and pi.status = 'pending'
      )
    )
    from collections c
    left join profiles p on p.id = c.creator_user_id
    where c.id = p_id
  ), '{}'::jsonb);
end;
$$;

create or replace function admin_list_users(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('users.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(
      _admin_row(
        p.id,
        'Collect ID ' || p.public_id,
        mask_phone(p.whatsapp_phone),
        case when p.is_platform_admin then 'admin' else 'active' end,
        '',
        p.created_at,
        jsonb_build_object('public_id', p.public_id)
      )
      order by p.created_at desc
    )
    from profiles p
    where (
        p_search is null
        or p.public_id = p_search
        or mask_phone(p.whatsapp_phone) ilike '%' || p_search || '%'
      )
      and (
        p_status is null
        or (p_status = 'admin' and p.is_platform_admin)
        or (p_status = 'active' and not p.is_platform_admin)
      )
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_get_user(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('users.read');
  return coalesce((
    select jsonb_build_object(
      'id', p.id,
      'public_id', p.public_id,
      'public_label', 'Collect ID ' || p.public_id,
      'whatsapp_phone', mask_phone(p.whatsapp_phone),
      'momo_number', mask_phone(p.momo_number),
      'is_platform_admin', p.is_platform_admin,
      'created_at', p.created_at,
      'updated_at', p.updated_at
    )
    from profiles p
    where p.id = p_id
  ), '{}'::jsonb);
end;
$$;

create or replace function admin_list_admin_users(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('admin_users.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(
      _admin_row(
        p.id,
        'Collect ID ' || p.public_id,
        ar.name,
        'admin',
        '',
        aur.created_at,
        jsonb_build_object('public_id', p.public_id)
      )
      order by aur.created_at desc
    )
    from admin_user_roles aur
    join profiles p on p.id = aur.user_id
    join admin_roles ar on ar.id = aur.role_id
    where aur.revoked_at is null
      and (
        p_search is null
        or p.public_id = p_search
        or ar.name ilike '%' || p_search || '%'
      )
      and (
        p_status is null
        or p_status = 'admin'
        or ar.name = p_status
      )
  ), '[]'::jsonb));
end;
$$;

delete from admin_role_permissions arp
using admin_permissions ap
where arp.permission_name = ap.name
  and ap.name in (
    'public_requests.read',
    'public_requests.review',
    'collections.moderate',
    'payments.allocate'
  );

delete from admin_permissions
where name in (
  'public_requests.read',
  'public_requests.review',
  'collections.moderate',
  'payments.allocate'
);

update admin_roles
set name = 'group_ops_admin',
    description = 'Group and SMS-first operations review'
where name = 'moderation_admin';

create or replace function admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('overview.read');
  return jsonb_build_object(
    'metrics', jsonb_build_array(
      jsonb_build_object('label', 'Pending payment intents', 'value', (select count(*) from payment_intents where status = 'pending'), 'status', 'pending'),
      jsonb_build_object('label', 'SMS exceptions', 'value', (select count(*) from parsed_payment_events where allocation_status in ('unallocated', 'ambiguous', 'needs_review')), 'status', 'needs_review'),
      jsonb_build_object('label', 'Posted payments', 'value', (select count(*) from payments where status = 'posted'), 'status', 'posted'),
      jsonb_build_object('label', 'Ledger credits RWF', 'value', coalesce((select sum(amount_rwf) from ledger_entries), 0), 'status', 'healthy')
    )
  );
end;
$$;

create or replace view public_profiles_view
with (security_invoker = true)
as
select
  id,
  'Collect ID ' || public_id as public_label,
  null::text as avatar_url,
  created_at
from profiles;

create or replace view public_contributions_view
with (security_invoker = true)
as
select
  p.id as payment_id,
  p.collection_id,
  p.amount_rwf,
  p.posted_at,
  case
    when p.contributor_public_id is not null
      then 'Collect ID ' || p.contributor_public_id
    else 'Collect member'
  end as supporter_label
from payments p
where p.status = 'posted';

revoke update (display_name, avatar_url, anonymity_default)
  on profiles from authenticated;

grant select on public_profiles_view, public_contributions_view
  to anon, authenticated;

create or replace function record_sms_access_consent(
  enabled boolean,
  momo_number_hash text default null,
  build_channel text default 'android_sms_access',
  device_label text default 'flutter_app'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  consent_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into receiver_mode_consents (
    user_id,
    enabled,
    momo_number_hash,
    build_channel,
    device_label
  )
  values (
    auth.uid(),
    coalesce(enabled, false),
    momo_number_hash,
    nullif(build_channel, ''),
    nullif(device_label, '')
  )
  returning id into consent_id;

  insert into audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    auth.uid(),
    case
      when coalesce(enabled, false) then 'sms_access.enabled'
      else 'sms_access.disabled'
    end,
    'sms_access_consent',
    consent_id,
    jsonb_build_object('build_channel', build_channel, 'device_label', device_label)
  );

  return consent_id;
end;
$$;

revoke execute on function record_receiver_mode_consent(boolean, text, text, text)
  from public, anon, authenticated;

drop function if exists record_receiver_mode_consent(boolean, text, text, text);

insert into feature_flags (key, enabled, description)
values
  (
    'ENABLE_ANDROID_SMS_ACCESS',
    false,
    'Android-only SMS app access for consented MoMo SMS ingestion'
  )
on conflict (key) do update
set description = excluded.description;

delete from feature_flags
where key = 'ENABLE_INTERNAL_RECEIVER_MODE';

insert into system_settings (key, value, description, is_sensitive)
values
  (
    'payments.mode',
    '{"provider":"payment_intent_momo_ussd","country":"RW","currency":"RWF"}'::jsonb,
    'Collect payment mode: payment intent, MoMo USSD launch, and automated SMS allocation',
    false
  )
on conflict (key) do update
set value = excluded.value,
    description = excluded.description,
    is_sensitive = excluded.is_sensitive,
    updated_at = now();

grant execute on function create_group_with_owner(text, text, text, text, text)
  to authenticated;
grant execute on function join_group_by_slug(text)
  to authenticated;
grant execute on function create_payment_intent(uuid, bigint, text)
  to authenticated;
grant execute on function create_contribution_intent(uuid, bigint, text)
  to authenticated;
grant execute on function record_sms_access_consent(boolean, text, text, text)
  to authenticated;
grant execute on function allocate_parsed_payment_event(uuid)
  to service_role;
