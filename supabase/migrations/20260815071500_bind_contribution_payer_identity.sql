begin;

-- Derive payer identity only when the profile MoMo number matches the phone
-- confirmed by Supabase Auth. The caller parameter remains as a compatibility
-- and consistency check for installed clients; an editable profile field alone
-- is not proof that the contributor owns the payer number.
create or replace function public._authenticated_momo_phone_hash(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, auth, extensions
as $$
declare
  profile_digits text;
  auth_digits text;
  canonical_profile_phone text;
  canonical_auth_phone text;
  auth_phone_confirmed_at timestamptz;
begin
  select
    regexp_replace(coalesce(profile.momo_number, ''), '[^0-9]', '', 'g'),
    regexp_replace(coalesce(auth_user.phone, ''), '[^0-9]', '', 'g'),
    auth_user.phone_confirmed_at
    into profile_digits, auth_digits, auth_phone_confirmed_at
  from public.profiles profile
  join auth.users auth_user on auth_user.id = profile.id
  where profile.id = p_user_id;

  if profile_digits ~ '^250[0-9]{9}$' then
    canonical_profile_phone := '+' || profile_digits;
  elsif profile_digits ~ '^0[0-9]{9}$' then
    canonical_profile_phone := '+250' || substr(profile_digits, 2);
  elsif profile_digits ~ '^[0-9]{9}$' then
    canonical_profile_phone := '+250' || profile_digits;
  else
    return null;
  end if;

  if auth_digits ~ '^250[0-9]{9}$' then
    canonical_auth_phone := '+' || auth_digits;
  elsif auth_digits ~ '^0[0-9]{9}$' then
    canonical_auth_phone := '+250' || substr(auth_digits, 2);
  elsif auth_digits ~ '^[0-9]{9}$' then
    canonical_auth_phone := '+250' || auth_digits;
  else
    return null;
  end if;

  if auth_phone_confirmed_at is null
     or canonical_profile_phone <> canonical_auth_phone then
    return null;
  end if;

  return encode(extensions.digest(canonical_auth_phone, 'sha256'), 'hex');
end;
$$;

revoke all on function public._authenticated_momo_phone_hash(uuid)
  from public, anon, authenticated;

-- A pending intent with an unverified payer hash must not remain eligible for
-- automatic allocation after this control is installed.
update public.payment_intents intent
set status = 'cancelled'
where intent.status = 'pending'
  and intent.sender_phone_hash is distinct from
    public._authenticated_momo_phone_hash(intent.contributor_user_id);

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

comment on function public.create_contribution_intent(uuid, bigint, text) is
  'Creates an idempotent contribution intent whose payer phone matches the phone confirmed by authentication.';

commit;
