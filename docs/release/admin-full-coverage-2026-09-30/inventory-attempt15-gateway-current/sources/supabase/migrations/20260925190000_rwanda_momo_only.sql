begin;

-- Historical payment rows remain available for controlled audit retention.
-- New member profiles and all new payment activity are Rwanda MoMo only.
update public.profile_country_rules
set enabled = (country_code = 'RW'), updated_at = now();
delete from public.profile_country_rules where country_code <> 'RW';

update public.feature_flags
set enabled = false,
    updated_reason = 'Rwanda MoMo USSD is the only contribution rail',
    updated_at = now()
where key = 'bank_transfer_v1';
delete from public.feature_flags where key = 'bank_transfer_v1';

update public.system_settings
set value = '{"rwanda":{"provider":"momo_ussd_sms","currency":"RWF"}}'::jsonb,
    description = 'Rwanda MoMo USSD contributions only',
    updated_at = now()
where key = 'payments.mode';

alter table public.profiles
  add constraint profiles_rwanda_momo_only
  check (country_code is not null and currency_code is not null
    and country_code = 'RW' and currency_code = 'RWF') not valid;

alter table public.collections
  add constraint collections_rwanda_momo_only
  check (currency = 'RWF' and not diaspora_enabled) not valid;

create or replace function public._member_profile_payload(profile_row public.profiles)
returns jsonb language sql immutable set search_path = ''
as $$
  select case when profile_row.id is null or profile_row.country_code <> 'RW'
    then null else jsonb_build_object(
      'id', profile_row.id,
      'public_id', profile_row.public_id,
      'whatsapp_phone', profile_row.whatsapp_phone,
      'country_code', 'RW',
      'currency_code', 'RWF',
      'momo_provider', profile_row.momo_provider,
      'momo_number', profile_row.momo_number,
      'momo_pay_code', profile_row.momo_pay_code
    ) end;
$$;

create or replace function public.ensure_current_member_profile(
  p_whatsapp_phone text, p_country_code text default null
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare profile_row public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_country_code is not null and upper(btrim(p_country_code)) <> 'RW' then
    raise exception 'Collect supports Rwanda profiles only';
  end if;
  profile_row := public.ensure_current_profile(p_whatsapp_phone, 'RW');
  if coalesce((
    select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_verified_account_claim'
  ), false) then
    perform collect_hybrid.claim_verified_current_account();
  end if;
  return public._member_profile_payload(profile_row);
end;
$$;

create or replace function collect_profile_access.assert_ready(required_rail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  profile_row public.profiles%rowtype;
  local_momo text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if required_rail is not null and required_rail <> 'rwanda' then
    raise exception 'Only Rwanda MoMo contributions are supported';
  end if;
  select * into profile_row from public.profiles where id = auth.uid() for share;
  if profile_row.id is null or profile_row.country_code <> 'RW'
     or profile_row.currency_code <> 'RWF'
     or profile_row.public_id !~ '^[0-9]{6}$'
     or nullif(btrim(profile_row.whatsapp_phone), '') is null then
    raise exception 'Complete your Rwanda MoMo profile first';
  end if;
  local_momo := public._rwanda_momo_local(profile_row.momo_number);
  if local_momo is null
     or profile_row.momo_provider not in ('mtn_momo', 'airtel_money')
     or (profile_row.momo_provider = 'mtn_momo' and local_momo !~ '^07[89][0-9]{7}$')
     or (profile_row.momo_provider = 'airtel_money' and local_momo !~ '^07[23][0-9]{7}$')
     or profile_row.momo_number_hash is distinct from
        encode(extensions.digest('+250' || substr(local_momo, 2), 'sha256'), 'hex') then
    raise exception 'Complete your profile with a valid MoMo number first';
  end if;
end;
$$;
revoke all on function collect_profile_access.assert_ready(text)
  from public, anon, authenticated, service_role;

create function collect_profile_access.require_rwanda_momo_collection()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.collections collection
    where collection.id = new.collection_id
      and collection.currency = 'RWF'
      and not collection.diaspora_enabled
  ) then
    raise exception 'Only Rwanda MoMo groups accept new payment activity';
  end if;
  return new;
end;
$$;
revoke all on function collect_profile_access.require_rwanda_momo_collection()
  from public, anon, authenticated, service_role;
create trigger payment_intents_rwanda_momo_only
  before insert on public.payment_intents
  for each row execute function collect_profile_access.require_rwanda_momo_collection();
create trigger payments_rwanda_momo_only
  before insert on public.payments
  for each row execute function collect_profile_access.require_rwanda_momo_collection();

-- The four-argument member API owns validation and writes only Rwanda fields.
-- Older APIs lose client execution privileges below.
create function public.update_current_member_profile(
  p_country_code text, p_momo_provider text,
  p_momo_number text, p_momo_pay_code text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  profile_row public.profiles%rowtype;
  clean_provider text := lower(btrim(coalesce(p_momo_provider, '')));
  clean_momo text := public._rwanda_momo_local(p_momo_number);
  clean_code text := nullif(btrim(coalesce(p_momo_pay_code, '')), '');
  auth_phone text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if upper(btrim(coalesce(p_country_code, ''))) <> 'RW' then
    raise exception 'Collect supports Rwanda profiles only';
  end if;
  if clean_provider not in ('mtn_momo', 'airtel_money') or clean_momo is null
     or (clean_provider = 'mtn_momo' and clean_momo !~ '^07[89][0-9]{7}$')
     or (clean_provider = 'airtel_money' and clean_momo !~ '^07[23][0-9]{7}$') then
    raise exception 'Choose a valid Rwanda MoMo provider and number';
  end if;
  if clean_code is not null and clean_code !~ '^[0-9]{4,9}$' then
    raise exception 'Enter a MoMo code with 4 to 9 digits';
  end if;
  select phone into auth_phone from auth.users where id = auth.uid();
  update public.profiles
  set country_code = 'RW',
      currency_code = 'RWF',
      momo_provider = clean_provider,
      momo_number = clean_momo,
      momo_number_hash = encode(
        extensions.digest('+250' || substr(clean_momo, 2), 'sha256'), 'hex'
      ),
      momo_number_verified_at = case
        when clean_momo = public._rwanda_momo_local(auth_phone)
          then coalesce(momo_number_verified_at, now())
        else null end,
      momo_pay_code = clean_code,
      revolut_link = null,
      revolut_account = null,
      updated_at = now()
  where id = auth.uid()
  returning * into profile_row;
  if profile_row.id is null then raise exception 'Collect profile not found'; end if;
  insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'profile.rwanda_momo.updated', 'profile', auth.uid(),
    jsonb_build_object(
      'country_code', 'RW', 'currency_code', 'RWF',
      'momo_provider', clean_provider,
      'momo_number_matches_whatsapp', profile_row.momo_number_verified_at is not null,
      'has_momo_code', clean_code is not null
    )
  );
  return public._member_profile_payload(profile_row);
end;
$$;
revoke all on function public.update_current_member_profile(text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.update_current_member_profile(text,text,text,text)
  to authenticated;
drop function if exists public.update_current_member_profile(text,text,text,text,text,text);
drop function if exists public.update_current_member_profile(text,text,text,text,text);

create function public.update_rwanda_momo_group_profile(
  p_collection_id uuid, p_group_name text, p_group_description text,
  p_group_image_url text default null, p_group_accent_color_hex text default null,
  p_group_is_public boolean default false,
  p_group_recurring_cadence text default 'monthly',
  p_group_collection_type text default null,
  p_group_category_subtype text default null,
  p_group_purpose_label text default null,
  p_group_is_recurring boolean default true
)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform collect_profile_access.assert_ready('rwanda');
  if not exists (
    select 1 from public.collections collection
    where collection.id = p_collection_id
      and collection.creator_user_id = auth.uid()
      and collection.archived_at is null
      and collection.currency = 'RWF'
      and not collection.diaspora_enabled
  ) then
    raise exception 'Only the current Rwanda group owner can update group settings';
  end if;
  perform public.update_collection_profile(
    p_collection_id, p_group_name, p_group_description,
    p_group_image_url, p_group_accent_color_hex,
    (select public_status = 'public_approved' from public.collections where id = p_collection_id),
    p_group_recurring_cadence, p_group_collection_type,
    p_group_category_subtype, p_group_purpose_label, p_group_is_recurring
  );
end;
$$;
revoke all on function public.update_rwanda_momo_group_profile(
  uuid,text,text,text,text,boolean,text,text,text,text,boolean
) from public, anon, authenticated, service_role;
grant execute on function public.update_rwanda_momo_group_profile(
  uuid,text,text,text,text,boolean,text,text,text,text,boolean
) to authenticated;

create or replace function public.public_collection_payment_route(
  p_collection_id uuid
)
returns table (
  payment_rail text,
  settlement_currency text,
  receiver_momo_number text,
  receiver_display_label text,
  receiver_network text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    'rwanda_momo'::text,
    'RWF'::text,
    receiver.momo_number,
    receiver.label,
    receiver.network
  from public.collections collection
  join lateral (
    select route.momo_number, route.label, route.network
    from public.collection_receivers route
    where route.collection_id = collection.id
      and route.is_active
      and route.network in ('mtn_momo', 'airtel_money')
    order by route.created_at
    limit 1
  ) receiver on true
  where collection.id = p_collection_id
    and collection.public_status = 'public_approved'
    and collection.is_platform_sponsored
    and collection.archived_at is null
    and collection.currency = 'RWF'
    and not collection.diaspora_enabled;
$$;

-- Retain compatibility columns in the existing views with inert values while
-- excluding retired groups from every member and public directory.
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
  false::boolean as diaspora_enabled,
  '{}'::text[] as diaspora_regions,
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
where public.user_can_read_collection(collection.id, auth.uid())
  and collection.currency = 'RWF' and not collection.diaspora_enabled;

create or replace view public.public_collections_view
with (security_invoker = true, security_barrier = true)
as
select
  collection.id,
  collection.slug,
  collection.title,
  collection.description,
  collection.category,
  collection.cover_image_url,
  collection.target_amount_rwf,
  collection.deadline_at,
  collection.is_recurring,
  collection.created_at,
  collection.collection_type,
  collection.category_subtype,
  collection.purpose_label,
  collection.suggested_amount_rwf,
  collection.accent_color_hex,
  collection.recurring_cadence,
  collection.is_platform_sponsored,
  false::boolean as diaspora_enabled,
  '{}'::text[] as diaspora_regions,
  coalesce(route.payment_rail, 'unavailable') as payment_rail,
  coalesce(route.settlement_currency, collection.currency) as settlement_currency,
  route.receiver_momo_number,
  route.receiver_display_label,
  route.receiver_network
from public.collections collection
left join lateral public.public_collection_payment_route(collection.id) route
  on true
where collection.public_status = 'public_approved'
  and collection.is_platform_sponsored
  and collection.archived_at is null
  and collection.currency = 'RWF' and not collection.diaspora_enabled;

create or replace function public.list_current_user_collections(
  p_collection_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select coalesce(jsonb_agg(
    (to_jsonb(collection) - 'diaspora_enabled' - 'diaspora_regions')
      || jsonb_strip_nulls(jsonb_build_object(
        'payment_rail', route.payment_rail,
        'settlement_currency', route.settlement_currency,
        'receiver_momo_number', route.receiver_momo_number,
        'receiver_display_label', route.receiver_display_label,
        'receiver_network', route.receiver_network
      )) order by collection.created_at desc, collection.id
  ), '[]'::jsonb)
  into result
  from public.member_collections_view collection
  left join lateral public.public_collection_payment_route(collection.id) route on true
  where (p_collection_id is null or collection.id = p_collection_id)
    and public.user_can_read_collection(collection.id, auth.uid());
  return result;
end;
$$;

-- The member history and aggregates keep only posted Rwanda MoMo activity.
-- Retained financial records stay in the database for controlled audit access.
create or replace function collect_member_actions.payment_history()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare actor uuid := auth.uid(); result jsonb;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  with readable as materialized (
    select collection.id from public.collections collection
    where public.user_can_read_collection(collection.id, actor)
  ), history as (
    select payment.posted_at as happened_at, jsonb_build_object(
      'payment_id', 'momo:' || payment.id,
      'collection_id', payment.collection_id,
      'amount_minor', payment.amount_rwf,
      'currency', 'RWF',
      'rail', 'rwanda_momo',
      'posted_at', payment.posted_at,
      'transaction_id', case when payment.contributor_user_id = actor
        then payment.transaction_id end,
      'is_current_user_contribution', coalesce(payment.contributor_user_id = actor, false),
      'supporter_label', case when payment.contributor_user_id = actor then 'You'
        when payment.anonymity_choice = 'public_id'
          and payment.contributor_public_id is not null
          then 'Collect ID ' || payment.contributor_public_id
        else 'Anonymous supporter' end
    ) as item
    from public.payments payment
    where payment.status = 'posted' and payment.currency = 'RWF'
      and (payment.contributor_user_id = actor
        or payment.collection_id in (select id from readable))
  )
  select coalesce(jsonb_agg(item order by happened_at desc, item->>'payment_id'), '[]'::jsonb)
  into result from history;
  return result;
end;
$$;

create or replace function public.list_current_member_payment_intents()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', intent.id,
    'collection_id', intent.collection_id,
    'rail', 'rwanda_momo',
    'amount_minor', intent.expected_amount_rwf,
    'currency', 'RWF',
    'receiver_momo_number', receiver.momo_number,
    'receiver_label', receiver.label,
    'network', receiver.network,
    'status', case when intent.status = 'pending' and intent.expires_at <= now()
      then 'expired' else intent.status::text end,
    'created_at', intent.created_at,
    'expires_at', intent.expires_at
  ) order by intent.created_at desc, intent.id), '[]'::jsonb)
  into result
  from public.payment_intents intent
  left join lateral (
    select route.momo_number, route.label, route.network
    from public.collection_receivers route
    where route.collection_id = intent.collection_id
      and route.momo_number_hash = intent.receiver_momo_number_hash
    order by route.created_at desc, route.id limit 1
  ) receiver on true
  where intent.contributor_user_id = auth.uid();
  return result;
end;
$$;

create or replace function public.list_current_member_collection_balances()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  with visible as (
    select collection.id from public.collections collection
    where public.user_can_read_collection(collection.id, auth.uid())
      and collection.currency = 'RWF' and not collection.diaspora_enabled
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'collection_id', visible.id,
    'balances', jsonb_build_array(jsonb_build_object(
      'currency', 'RWF',
      'amount_raised_minor', coalesce(balance.confirmed_rwf, 0),
      'current_user_balance_minor', coalesce((
        select sum(member_balance.confirmed_rwf)::bigint
        from collect_hybrid.member_balances member_balance
        where member_balance.collection_id = visible.id
          and collect_hybrid.member_record_belongs_to_user(
            member_balance.member_record_id, auth.uid()
          )
      ), 0)
    )),
    'supporter_count', (
      select case when count(*) filter (where payment.contributor_user_id is null) > 0
        then null else count(distinct payment.contributor_user_id) end
      from public.payments payment
      where payment.collection_id = visible.id and payment.status = 'posted'
        and payment.currency = 'RWF'
    )
  ) order by visible.id), '[]'::jsonb)
  into result
  from visible
  left join collect_hybrid.collection_balances balance on balance.collection_id = visible.id;
  return result;
end;
$$;

-- Retire every direct bank operation, including service-role ingest calls.
-- Revoke table access as well, while retaining historic rows for audit duties.
do $$
declare fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ~ '(bank|diaspora|stripe|sepa)'
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', fn.signature);
  end loop;
end;
$$;

do $$
declare tbl record;
begin
  for tbl in
    select format('%I.%I', schemaname, tablename) as relation
    from pg_tables
    where schemaname = 'public' and tablename ~ '^(bank_|daily_bank_)'
  loop
    execute format('revoke all on table %s from public, anon, authenticated, service_role', tbl.relation);
  end loop;
end;
$$;

commit;
