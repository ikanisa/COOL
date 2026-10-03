begin;

-- Localized profile readiness: Rwanda MoMo; all other supported countries
-- require only an account number. No personal names or payment links are
-- collected by this contract. Apply before the updated member app.
create schema if not exists collect_profile_access;
revoke all on schema collect_profile_access from public, anon, authenticated, service_role;

create function collect_profile_access.normalize_account_number(value text)
returns text language sql immutable set search_path = ''
as $$ select upper(regexp_replace(btrim(coalesce(value, '')), '[[:space:]-]', '', 'g')); $$;

create function collect_profile_access.valid_account_number(value text)
returns boolean language sql immutable set search_path = ''
as $$
  select collect_profile_access.normalize_account_number(value) ~ '^[A-Z0-9]{4,34}$'
    and collect_profile_access.normalize_account_number(value) ~ '[0-9]';
$$;

-- Internal-only helper: no caller-supplied user id. The row lock makes a
-- concurrent profile edit wait until the join/intent/create transaction ends.
create function collect_profile_access.assert_ready(required_rail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  profile_row public.profiles%rowtype;
  country_rule public.profile_country_rules%rowtype;
  local_momo text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into profile_row from public.profiles where id = auth.uid() for share;
  select * into country_rule from public.profile_country_rules
    where country_code = profile_row.country_code and enabled;
  if profile_row.id is null or profile_row.public_id !~ '^[0-9]{6}$'
     or nullif(btrim(profile_row.whatsapp_phone), '') is null
     or country_rule.country_code is null
     or profile_row.currency_code is distinct from country_rule.currency_code then
    raise exception 'Choose your country and complete your profile first.';
  end if;
  if profile_row.country_code = 'RW' then
    local_momo := public._rwanda_momo_local(profile_row.momo_number);
    if local_momo is null
       or profile_row.momo_provider is null
       or profile_row.momo_provider not in ('mtn_momo', 'airtel_money')
       or (profile_row.momo_provider = 'mtn_momo' and local_momo !~ '^07[89][0-9]{7}$')
       or (profile_row.momo_provider = 'airtel_money' and local_momo !~ '^07[23][0-9]{7}$')
       or profile_row.momo_number_hash is distinct from
          encode(extensions.digest('+250' || substr(local_momo, 2), 'sha256'), 'hex') then
      raise exception 'Complete your profile with a valid MoMo number first.';
    end if;
    if required_rail = 'diaspora' then
      raise exception 'Rwanda profiles contribute using MoMo.';
    end if;
  else
    if not collect_profile_access.valid_account_number(profile_row.revolut_account) then
      raise exception 'Complete your profile with an account number first.';
    end if;
    if required_rail = 'rwanda' then
      raise exception 'This action requires a Rwanda MoMo profile.';
    end if;
  end if;
end;
$$;

revoke all on function collect_profile_access.normalize_account_number(text),
  collect_profile_access.valid_account_number(text),
  collect_profile_access.assert_ready(text)
from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_current_member_profile(p_country_code text, p_momo_provider text DEFAULT NULL::text, p_momo_number text DEFAULT NULL::text, p_revolut_link text DEFAULT NULL::text, p_revolut_account text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  profile_row public.profiles%rowtype;
  country_rule public.profile_country_rules%rowtype;
  auth_phone text;
  clean_auth_momo text;
  clean_country text := upper(btrim(coalesce(p_country_code, '')));
  clean_provider text := lower(nullif(btrim(coalesce(p_momo_provider, '')), ''));
  clean_momo text := public._rwanda_momo_local(p_momo_number);
  clean_revolut_account text := nullif(collect_profile_access.normalize_account_number(p_revolut_account), '');
  previous_country text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into country_rule from public.profile_country_rules
  where country_code = clean_country and enabled;
  if country_rule.country_code is null then raise exception 'Unsupported profile country'; end if;

  if clean_country = 'RW' then
    if clean_provider is null or clean_provider not in ('mtn_momo', 'airtel_money') then
      raise exception 'Choose MTN MoMo or Airtel Money';
    end if;
    if clean_momo is null then
      raise exception 'Use a valid Rwanda MoMo number';
    end if;
    if (clean_provider = 'mtn_momo' and clean_momo !~ '^07[89][0-9]{7}$')
       or (clean_provider = 'airtel_money' and clean_momo !~ '^07[23][0-9]{7}$') then
      raise exception 'MoMo provider does not match the Rwanda mobile number';
    end if;
  elsif not collect_profile_access.valid_account_number(clean_revolut_account) then
    raise exception 'Enter a valid account number.';

  end if;

  select country_code into previous_country from public.profiles where id = auth.uid();
  select phone into auth_phone from auth.users where id = auth.uid();
  clean_auth_momo := public._rwanda_momo_local(auth_phone);

  update public.profiles
  set country_code = country_rule.country_code,
      currency_code = country_rule.currency_code,
      momo_provider = case when clean_country = 'RW' then clean_provider else null end,
      momo_number = case when clean_country = 'RW' then clean_momo else null end,
      momo_number_hash = case when clean_country = 'RW' then
        encode(extensions.digest('+250' || substr(clean_momo, 2), 'sha256'), 'hex')
        else null end,
      momo_number_verified_at = case
        when clean_country = 'RW' and clean_momo = clean_auth_momo
          then coalesce(momo_number_verified_at, now())
        else null
      end,
      -- Preserve legacy data, but ignore the retired link input.
      revolut_link = case when clean_country <> 'RW' then revolut_link else null end,
      revolut_account = case when clean_country <> 'RW' then clean_revolut_account else null end,
      updated_at = now()
  where id = auth.uid()
  returning * into profile_row;
  if profile_row.id is null then raise exception 'Collect profile not found'; end if;

  insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'profile.payment_route.updated', 'profile', auth.uid(),
    jsonb_build_object(
      'previous_country_code', previous_country,
      'country_code', profile_row.country_code,
      'currency_code', profile_row.currency_code,
      'payment_rail', case when clean_country = 'RW' then 'momo_ussd_sms' else 'diaspora_bank_revolut' end,
      'momo_provider', profile_row.momo_provider,
      'momo_number_matches_whatsapp', profile_row.momo_number_verified_at is not null,
      'has_revolut_link', profile_row.revolut_link is not null,
      'has_revolut_account', profile_row.revolut_account is not null
    )
  );

  -- Explicit allowlist: no profile names or private Admin evidence in response.
  return jsonb_build_object(
    'id', profile_row.id,
    'public_id', profile_row.public_id,
    'whatsapp_phone', profile_row.whatsapp_phone,
    'country_code', profile_row.country_code,
    'currency_code', profile_row.currency_code,
    'momo_provider', profile_row.momo_provider,
    'momo_number', profile_row.momo_number,
    'revolut_link', profile_row.revolut_link,
    'revolut_account', profile_row.revolut_account
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.join_group_by_share_code(p_group_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  clean_code text := lower(trim(coalesce(p_group_code, '')));
  parsed_code uuid;
  group_row public.collections;
  newly_joined boolean := false;
begin
  perform collect_profile_access.assert_ready(null);
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
$function$;

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

CREATE OR REPLACE FUNCTION public.create_bank_transfer_intent(p_collection_id uuid, p_amount_minor bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  collection_row public.collections%rowtype;
  destination public.bank_transfer_destinations%rowtype;
  intent public.bank_transfer_intents%rowtype;
  reference_value text;
begin
  perform collect_profile_access.assert_ready('diaspora');
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
$function$;

CREATE OR REPLACE FUNCTION public.create_private_group_with_owner_attested(group_name text, group_description text, receiver_momo_number text, receiver_momo_number_hash text, receiver_label text, group_collection_type text, group_category_subtype text, group_purpose_label text, native_capability uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  created_group_id uuid;
  profile_provider text;
begin
  perform collect_profile_access.assert_ready('rwanda');
  select profile.momo_provider into profile_provider
  from public.profiles profile
  where profile.id = auth.uid() and profile.country_code = 'RW';
  if profile_provider not in ('mtn_momo', 'airtel_money') then
    raise exception 'Complete the Rwanda MoMo profile before creating a group';
  end if;

  created_group_id := public.create_group_with_owner_attested(
    group_name,
    group_description,
    receiver_momo_number,
    receiver_momo_number_hash,
    receiver_label,
    group_collection_type,
    group_category_subtype,
    group_purpose_label,
    false,
    native_capability
  );
  update public.collection_receivers
  set network = profile_provider
  where collection_id = created_group_id
    and receiver_user_id = auth.uid();
  return created_group_id;
end;
$function$;

-- Existing RPC identities and explicit authenticated grants are preserved.
-- No table grants, Admin approvals, receipts or balances are changed.
notify pgrst, 'reload schema';
commit;
