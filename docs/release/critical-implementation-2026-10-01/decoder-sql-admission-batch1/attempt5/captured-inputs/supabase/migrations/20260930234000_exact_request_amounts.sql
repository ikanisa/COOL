begin;

-- Preserve stored values. Validation aborts atomically if existing request or
-- collection configuration amounts need an explicit data correction; no amount
-- is clamped, rounded or rewritten. Existing positive/null rules remain intact.
alter table public.payment_intents add constraint payment_intents_expected_exact_json
 check(expected_amount_rwf is null or expected_amount_rwf<=9007199254740991) not valid;
alter table public.collections add constraint collections_target_exact_json
 check(target_amount_rwf is null or target_amount_rwf<=9007199254740991) not valid;
alter table public.collections add constraint collections_suggested_exact_json
 check(suggested_amount_rwf is null or suggested_amount_rwf<=9007199254740991) not valid;
alter table public.payment_intents validate constraint payment_intents_expected_exact_json;
alter table public.collections validate constraint collections_target_exact_json;
alter table public.collections validate constraint collections_suggested_exact_json;

CREATE OR REPLACE FUNCTION public.create_contribution_intent(collection uuid, p_expected_amount_rwf bigint DEFAULT NULL::bigint, p_sender_phone_hash text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, collection_id uuid, expected_amount_rwf bigint, receiver_momo_number text, receiver_momo_number_hash text, receiver_label text, network text, sender_phone_hash text, status payment_intent_status, contributor_public_id character, created_at timestamp with time zone, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  requested_collection_id uuid := collection;
  verified_sender_phone_hash text;
  receiver_row public.collection_receivers;
  intent_row public.payment_intents;
  member_public_id char(6);
begin
  perform collect_profile_access.assert_ready('rwanda');
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

  -- Numeric JSON receipts must preserve the same exact integer on native and
  -- browser clients. This is a wire precision bound, not a provider limit.
  if p_expected_amount_rwf > 9007199254740991 then
    raise exception 'contribution_amount_not_exact' using errcode='22023';
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
$function$;

notify pgrst,'reload schema';
commit;
