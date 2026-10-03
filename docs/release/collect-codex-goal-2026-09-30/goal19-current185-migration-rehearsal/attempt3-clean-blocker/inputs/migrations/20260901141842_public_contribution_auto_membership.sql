-- Public groups are open contribution destinations. The first contribution
-- intent atomically creates the contributor's membership; there is no separate
-- join prerequisite. Private groups remain membership-gated.

create or replace function public.ensure_public_contributor_membership(
  p_collection_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  group_row public.collections%rowtype;
  prior_status text;
  changed_rows integer := 0;
begin
  if p_user_id is null then
    raise exception 'Authenticated contributor is required';
  end if;

  select collection.* into group_row
  from public.collections collection
  where collection.id = p_collection_id
    and collection.archived_at is null
    and collection.public_status = 'public_approved'
  for update;

  if group_row.id is null or group_row.creator_user_id = p_user_id then
    return false;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'public-contributor-membership:' || p_user_id::text || ':' || p_collection_id::text,
    0
  ));

  select member.status::text into prior_status
  from public.collection_members member
  where member.collection_id = p_collection_id
    and member.user_id = p_user_id
    and member.role = 'member'
  for update;

  if prior_status = 'removed' then
    raise exception 'Membership was removed by a group administrator';
  end if;
  if prior_status = 'active' then
    return false;
  end if;

  insert into public.collection_members (collection_id, user_id, role, status)
  values (p_collection_id, p_user_id, 'member', 'active')
  on conflict on constraint collection_members_collection_id_user_id_role_key
  do update set status = 'active'
  where collection_members.status <> 'active';
  get diagnostics changed_rows = row_count;

  if changed_rows > 0 then
    perform public.create_audit_log(
      'group.joined',
      'collection',
      p_collection_id,
      jsonb_build_object('join_method', 'initial_contribution')
    );
    perform public.enqueue_notification_template_event(
      group_row.creator_user_id,
      'group.update.default',
      jsonb_build_object('group', group_row.title),
      p_collection_id,
      '/groups/' || p_collection_id::text || '/members',
      'en'
    );
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.ensure_public_contributor_membership(uuid, uuid)
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
    raise exception 'Private group membership is required';
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

  perform public.ensure_public_contributor_membership(
    requested_collection_id,
    auth.uid()
  );

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

create or replace function public.create_bank_transfer_intent(
  p_collection_id uuid,
  p_amount_minor bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  collection_row public.collections%rowtype;
  destination public.bank_transfer_destinations%rowtype;
  intent public.bank_transfer_intents%rowtype;
  reference_value text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Contribution amount must be above zero';
  end if;
  if p_amount_minor > 999999999999 then
    raise exception 'Contribution amount exceeds the supported limit';
  end if;
  if not coalesce((
    select enabled from public.feature_flags where key = 'bank_transfer_v1'
  ), false) then
    raise exception 'Bank transfers are not active yet';
  end if;

  select * into collection_row
  from public.collections
  where id = p_collection_id
    and archived_at is null
    and public_status <> 'archived';
  if collection_row.id is null then
    raise exception 'Collection is unavailable';
  end if;
  if collection_row.public_status <> 'public_approved'
     and collection_row.creator_user_id <> auth.uid()
     and not exists (
       select 1 from public.collection_members member
       where member.collection_id = collection_row.id
         and member.user_id = auth.uid()
         and member.status = 'active'
     ) then
    raise exception 'Private group membership is required';
  end if;

  select * into destination
  from public.bank_transfer_destinations
  where currency = 'EUR'
    and status = 'active'
    and not is_placeholder
  order by version desc
  limit 1;
  if destination.id is null then
    raise exception 'Approved bank transfer details are not available';
  end if;

  perform public.ensure_public_contributor_membership(
    collection_row.id,
    auth.uid()
  );

  update public.bank_transfer_intents
  set status = 'expired', updated_at = now()
  where contributor_user_id = auth.uid()
    and status in ('awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence')
    and expires_at <= now();

  select * into intent
  from public.bank_transfer_intents
  where collection_id = collection_row.id
    and contributor_user_id = auth.uid()
    and destination_id = destination.id
    and amount_minor = p_amount_minor
    and currency = 'EUR'
    and status in ('awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence')
    and expires_at > now()
  order by created_at desc
  limit 1;

  if intent.id is null then
    loop
      reference_value := 'COL-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
      exit when not exists (
        select 1 from public.bank_transfer_intents where transfer_reference = reference_value
      );
    end loop;

    insert into public.bank_transfer_intents (
      collection_id,
      contributor_user_id,
      destination_id,
      destination_snapshot,
      transfer_reference,
      amount_minor,
      currency
    ) values (
      collection_row.id,
      auth.uid(),
      destination.id,
      public.bank_transfer_destination_json(destination),
      reference_value,
      p_amount_minor,
      'EUR'
    ) returning * into intent;

    perform public.create_audit_log(
      'bank_transfer.intent.created',
      'bank_transfer_intent',
      intent.id,
      jsonb_build_object(
        'collection_id', intent.collection_id,
        'amount_minor', intent.amount_minor,
        'currency', intent.currency,
        'destination_version', destination.version
      )
    );
  end if;

  return to_jsonb(intent) || jsonb_build_object(
    'destination', public.bank_transfer_destination_json(destination),
    'collection_title', collection_row.title
  );
end;
$$;

revoke execute on function public.create_bank_transfer_intent(uuid, bigint)
  from public, anon;
grant execute on function public.create_bank_transfer_intent(uuid, bigint)
  to authenticated;
