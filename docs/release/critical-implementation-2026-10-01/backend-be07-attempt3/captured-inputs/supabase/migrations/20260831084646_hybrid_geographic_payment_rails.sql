begin;

-- Collect has two geography-specific payment rails:
--   * Rwanda members: RWF MoMo USSD plus consented Android receipt SMS.
--   * Diaspora members: governed EUR bank transfer with Revolut hand-off.
-- Profile country selects the member journey; it never changes the rail of an
-- already-created financial record.

alter table public.profiles
  add column if not exists momo_provider text,
  add column if not exists momo_number_verified_at timestamptz,
  add column if not exists revolut_link text,
  add column if not exists revolut_account text;

alter table public.profiles
  drop constraint if exists profiles_momo_provider_check,
  drop constraint if exists profiles_momo_provider_number_match,
  drop constraint if exists profiles_momo_number_rw_format,
  drop constraint if exists profiles_revolut_link_format,
  drop constraint if exists profiles_revolut_account_length;

-- Normalize legacy values before validating the Rwanda-only MoMo contract.
-- Formatting variants keep the same number; non-Rwanda/invalid values are
-- cleared so an operator never mistakes them for an allocatable MoMo route.
with normalized as (
  select
    profile.id,
    case
      when regexp_replace(coalesce(profile.momo_number, ''), '[^0-9]', '', 'g')
        ~ '^2507[2389][0-9]{7}$'
        then '0' || substr(
          regexp_replace(profile.momo_number, '[^0-9]', '', 'g'), 4
        )
      when regexp_replace(coalesce(profile.momo_number, ''), '[^0-9]', '', 'g')
        ~ '^07[2389][0-9]{7}$'
        then regexp_replace(profile.momo_number, '[^0-9]', '', 'g')
      when regexp_replace(coalesce(profile.momo_number, ''), '[^0-9]', '', 'g')
        ~ '^7[2389][0-9]{7}$'
        then '0' || regexp_replace(profile.momo_number, '[^0-9]', '', 'g')
      else null
    end as momo_number
  from public.profiles profile
  where profile.momo_number is not null
)
update public.profiles profile
set momo_number = normalized.momo_number,
    momo_number_hash = case
      when normalized.momo_number is null then null
      else encode(
        extensions.digest(
          '+250' || substr(normalized.momo_number, 2), 'sha256'
        ),
        'hex'
      )
    end,
    momo_provider = case
      when normalized.momo_number ~ '^07[23]' then 'airtel_money'
      when normalized.momo_number ~ '^07[89]' then 'mtn_momo'
      else null
    end,
    momo_number_verified_at = case
      when normalized.momo_number is null then null
      else profile.momo_number_verified_at
    end,
    updated_at = now()
from normalized
where profile.id = normalized.id
  and (
    profile.momo_number is distinct from normalized.momo_number
    or profile.momo_provider is distinct from case
      when normalized.momo_number ~ '^07[23]' then 'airtel_money'
      when normalized.momo_number ~ '^07[89]' then 'mtn_momo'
      else null
    end
  );

alter table public.profiles
  add constraint profiles_momo_provider_check check (
    momo_provider is null or momo_provider in ('mtn_momo', 'airtel_money')
  ) not valid,
  add constraint profiles_momo_provider_number_match check (
    momo_provider is null or momo_number is null
    or (momo_provider = 'mtn_momo' and momo_number ~ '^(\+250|0)7[89][0-9]{7}$')
    or (momo_provider = 'airtel_money' and momo_number ~ '^(\+250|0)7[23][0-9]{7}$')
  ) not valid,
  add constraint profiles_momo_number_rw_format check (
    momo_number is null
    or momo_number ~ '^07[2389][0-9]{7}$'
    or momo_number ~ '^\+2507[2389][0-9]{7}$'
  ) not valid,
  add constraint profiles_revolut_link_format check (
    revolut_link is null
    or revolut_link ~ '^https://([a-z0-9-]+\.)?revolut\.me/[A-Za-z0-9._~-]+/?$'
  ) not valid,
  add constraint profiles_revolut_account_length check (
    revolut_account is null
    or char_length(btrim(revolut_account)) between 4 and 120
  ) not valid;

alter table public.profiles
  validate constraint profiles_momo_provider_check,
  validate constraint profiles_momo_provider_number_match,
  validate constraint profiles_momo_number_rw_format,
  validate constraint profiles_revolut_link_format,
  validate constraint profiles_revolut_account_length;

comment on column public.profiles.momo_provider is
  'Rwanda contribution provider. Null outside the Rwanda USSD rail.';
comment on column public.profiles.momo_number is
  'User-configured Rwanda MoMo payer number in local 07XXXXXXXX form.';
comment on column public.profiles.momo_number_verified_at is
  'Set when the MoMo number equals the Supabase-confirmed WhatsApp identity.';
comment on column public.profiles.revolut_link is
  'Diaspora Revolut.me payment profile link; not a payment authorization secret.';
comment on column public.profiles.revolut_account is
  'Diaspora-facing Revolut account descriptor; never banking credentials.';

create or replace function public._rwanda_momo_local(p_value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  digits text := regexp_replace(coalesce(p_value, ''), '[^0-9]', '', 'g');
begin
  if digits ~ '^2507[2389][0-9]{7}$' then
    return '0' || substr(digits, 4);
  end if;
  if digits ~ '^07[2389][0-9]{7}$' then
    return digits;
  end if;
  if digits ~ '^7[2389][0-9]{7}$' then
    return '0' || digits;
  end if;
  return null;
end;
$$;

revoke all on function public._rwanda_momo_local(text)
  from public, anon, authenticated;

create or replace function public.ensure_current_profile(
  p_whatsapp_phone text default null,
  p_country_code text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  profile_row public.profiles%rowtype;
  country_rule public.profile_country_rules%rowtype;
  requested_phone text := nullif(btrim(coalesce(p_whatsapp_phone, '')), '');
  verified_phone text;
  clean_phone text;
  clean_country text := upper(nullif(btrim(coalesce(p_country_code, '')), ''));
  resolved_country text;
  default_momo text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select nullif(btrim(phone), '') into verified_phone
  from auth.users where id = auth.uid();
  clean_phone := coalesce(verified_phone, requested_phone);

  if clean_country is not null then
    select * into country_rule from public.profile_country_rules
    where country_code = clean_country and enabled;
    if country_rule.country_code is null then
      raise exception 'Unsupported profile country';
    end if;
  end if;

  select * into profile_row from public.profiles where id = auth.uid();
  resolved_country := coalesce(profile_row.country_code, clean_country);
  if resolved_country is not null
     and country_rule.country_code is distinct from resolved_country then
    select * into country_rule from public.profile_country_rules
    where country_code = resolved_country and enabled;
  end if;
  default_momo := case
    when resolved_country = 'RW' then public._rwanda_momo_local(clean_phone)
    else null
  end;

  if profile_row.id is null then
    insert into public.profiles (
      id, public_id, whatsapp_phone, country_code, currency_code,
      momo_provider, momo_number, momo_number_hash, momo_number_verified_at
    ) values (
      auth.uid(), public.generate_public_id(), clean_phone, resolved_country,
      country_rule.currency_code,
      case
        when resolved_country <> 'RW' then null
        when default_momo ~ '^07[23]' then 'airtel_money'
        else 'mtn_momo'
      end,
      default_momo,
      case when default_momo is null then null else
        encode(extensions.digest('+250' || substr(default_momo, 2), 'sha256'), 'hex')
      end,
      case when default_momo is null then null else now() end
    ) returning * into profile_row;
  else
    update public.profiles
    set whatsapp_phone = case
          when verified_phone is not null then verified_phone
          when coalesce(profile_row.whatsapp_phone, '') = '' then clean_phone
          else profile_row.whatsapp_phone
        end,
        country_code = resolved_country,
        currency_code = coalesce(profile_row.currency_code, country_rule.currency_code),
        momo_provider = case
          when resolved_country <> 'RW' then null
          when profile_row.momo_provider is not null then profile_row.momo_provider
          when coalesce(profile_row.momo_number, default_momo) ~ '^07[23]'
            then 'airtel_money'
          else 'mtn_momo'
        end,
        momo_number = case
          when resolved_country = 'RW' then coalesce(profile_row.momo_number, default_momo)
          else null
        end,
        momo_number_hash = case
          when resolved_country <> 'RW' then null
          when profile_row.momo_number_hash is not null then profile_row.momo_number_hash
          when default_momo is not null then
            encode(extensions.digest('+250' || substr(default_momo, 2), 'sha256'), 'hex')
          else null
        end,
        momo_number_verified_at = case
          when resolved_country <> 'RW' then null
          when profile_row.momo_number_verified_at is not null
            then profile_row.momo_number_verified_at
          when default_momo is not null then now()
          else null
        end,
        revolut_name = case when resolved_country = 'RW' then null else profile_row.revolut_name end,
        revolut_link = case when resolved_country = 'RW' then null else profile_row.revolut_link end,
        revolut_account = case when resolved_country = 'RW' then null else profile_row.revolut_account end,
        updated_at = now()
    where id = auth.uid()
    returning * into profile_row;
  end if;
  return profile_row;
end;
$$;

revoke all on function public.ensure_current_profile(text, text)
  from public, anon, authenticated;
grant execute on function public.ensure_current_profile(text, text)
  to authenticated;

drop function if exists public.update_current_profile(text, text, text);

create or replace function public.update_current_profile(
  p_display_name text,
  p_country_code text,
  p_momo_provider text default null,
  p_momo_number text default null,
  p_revolut_name text default null,
  p_revolut_link text default null,
  p_revolut_account text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  profile_row public.profiles%rowtype;
  country_rule public.profile_country_rules%rowtype;
  auth_phone text;
  clean_auth_momo text;
  clean_display text := btrim(coalesce(p_display_name, ''));
  clean_country text := upper(btrim(coalesce(p_country_code, '')));
  clean_provider text := lower(nullif(btrim(coalesce(p_momo_provider, '')), ''));
  clean_momo text := public._rwanda_momo_local(p_momo_number);
  clean_revolut_name text := nullif(btrim(coalesce(p_revolut_name, '')), '');
  clean_revolut_link text := nullif(btrim(coalesce(p_revolut_link, '')), '');
  clean_revolut_account text := nullif(btrim(coalesce(p_revolut_account, '')), '');
  previous_country text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(clean_display) not between 2 and 80 then
    raise exception 'Display name must be between 2 and 80 characters';
  end if;
  select * into country_rule from public.profile_country_rules
  where country_code = clean_country and enabled;
  if country_rule.country_code is null then raise exception 'Unsupported profile country'; end if;

  if clean_country = 'RW' then
    if clean_provider not in ('mtn_momo', 'airtel_money') then
      raise exception 'Choose MTN MoMo or Airtel Money';
    end if;
    if clean_momo is null then
      raise exception 'Use a Rwanda MoMo number such as 078XXXXXXX';
    end if;
    if (clean_provider = 'mtn_momo' and clean_momo !~ '^07[89][0-9]{7}$')
       or (clean_provider = 'airtel_money' and clean_momo !~ '^07[23][0-9]{7}$') then
      raise exception 'MoMo provider does not match the Rwanda mobile number';
    end if;
  elsif clean_revolut_name is null
     or char_length(clean_revolut_name) not between 2 and 100
     or clean_revolut_link is null
     or clean_revolut_link !~ '^https://([a-z0-9-]+\.)?revolut\.me/[A-Za-z0-9._~-]+/?$'
     or clean_revolut_account is null
     or char_length(clean_revolut_account) not between 4 and 120 then
    raise exception 'Diaspora profiles require a Revolut name, Revolut.me link, and account details';
  end if;

  select country_code into previous_country from public.profiles where id = auth.uid();
  select phone into auth_phone from auth.users where id = auth.uid();
  clean_auth_momo := public._rwanda_momo_local(auth_phone);

  update public.profiles
  set display_name = clean_display,
      country_code = country_rule.country_code,
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
      revolut_name = case when clean_country <> 'RW' then clean_revolut_name else null end,
      revolut_link = case when clean_country <> 'RW' then clean_revolut_link else null end,
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
  return profile_row;
end;
$$;

revoke all on function public.update_current_profile(
  text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.update_current_profile(
  text, text, text, text, text, text, text
) to authenticated;

-- The existing hardened intent function uses this helper. A user may edit the
-- MoMo number as requested; edited numbers are explicitly audited above. Exact
-- receiver, amount, payer, time-window, transaction-id and uniqueness checks
-- still gate automatic posting, while non-unique evidence remains in review.
create or replace function public._authenticated_momo_phone_hash(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when profile.country_code = 'RW'
      and profile.momo_number_hash ~ '^[0-9a-f]{64}$'
      then profile.momo_number_hash
    else null
  end
  from public.profiles profile
  where profile.id = p_user_id
$$;

revoke all on function public._authenticated_momo_phone_hash(uuid)
  from public, anon, authenticated;

-- Only the Play-Integrity-bound Android flow can create a user group. The
-- wrapper deliberately omits a visibility argument and always binds `false`.
create or replace function public.create_private_group_with_owner_attested(
  group_name text,
  group_description text,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  group_collection_type text,
  group_category_subtype text,
  group_purpose_label text,
  native_capability uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_group_id uuid;
  profile_provider text;
begin
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
$$;

revoke all on function public.create_private_group_with_owner_attested(
  text, text, text, text, text, text, text, text, uuid
) from public, anon, authenticated;
grant execute on function public.create_private_group_with_owner_attested(
  text, text, text, text, text, text, text, text, uuid
) to authenticated;

-- Remove the non-attested bank-era creation bypass and the legacy public flag.
revoke execute on function public.create_bank_transfer_group(
  text, text, text, text, text, boolean, text, text
) from authenticated;
revoke execute on function public.create_group_with_owner_attested(
  text, text, text, text, text, text, text, text, boolean, uuid
) from authenticated;

-- Member-created groups are private by database contract, not just by the
-- Android presentation layer. Retire every legacy authenticated path that can
-- request public visibility or mutate a collection outside the reviewed RPCs.
do $$
declare
  legacy_function record;
begin
  for legacy_function in
    select procedure.oid::regprocedure as signature
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any (array[
        'request_public_collection',
        'update_collection_profile',
        'update_collection_profile_and_receiver'
      ])
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      legacy_function.signature
    );
  end loop;
end;
$$;
revoke insert, update, delete on public.collections from anon, authenticated;

drop policy if exists "collections insert authenticated" on public.collections;
create policy "collections insert authenticated" on public.collections
for insert to authenticated
with check (
  creator_user_id = (select auth.uid())
  and visibility = 'private'::public.collection_visibility
  and public_status = 'private'::public.collection_visibility
);

comment on policy "collections insert authenticated" on public.collections is
  'Defense in depth: authenticated inserts, if ever re-granted, remain owner-bound and private. Normal creation uses the Android-attested private-group RPC.';

create or replace function public.update_bank_transfer_group_profile(
  p_collection_id uuid,
  p_group_name text,
  p_group_description text,
  p_group_image_url text default null,
  p_group_accent_color_hex text default null,
  p_group_is_public boolean default false,
  p_group_recurring_cadence text default 'monthly',
  p_group_collection_type text default null,
  p_group_category_subtype text default null,
  p_group_purpose_label text default null,
  p_group_is_recurring boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  preserve_platform_public boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.collections collection
    where collection.id = p_collection_id
      and collection.creator_user_id = auth.uid()
      and collection.archived_at is null
  ) then raise exception 'Only the current group owner can update group settings'; end if;
  select collection.public_status = 'public_approved'
  into preserve_platform_public
  from public.collections collection
  where collection.id = p_collection_id;
  perform public.update_collection_profile(
    p_collection_id, p_group_name, p_group_description,
    p_group_image_url, p_group_accent_color_hex,
    preserve_platform_public, p_group_recurring_cadence, p_group_collection_type,
    p_group_category_subtype, p_group_purpose_label, p_group_is_recurring
  );
end;
$$;

-- Restore the member-safe Rwanda read models while retaining the bank RPCs for
-- diaspora profiles. The security-invoker view remains governed by collection
-- RLS and user_can_read_collection().
drop view if exists public.member_collections_view;
create view public.member_collections_view
with (security_invoker = true)
as
select
  c.id, c.slug, c.creator_user_id, c.title, c.description, c.currency,
  c.collection_type, c.category_subtype, c.purpose_label,
  c.suggested_amount_rwf, c.diaspora_enabled, c.diaspora_regions,
  case when c.archived_at is not null then 'archived' else c.moderation_status end
    as moderation_status,
  case
    when public.user_is_collection_admin(c.id, auth.uid())
      or exists (
        select 1 from public.collection_receivers receiver_check
        where receiver_check.collection_id = c.id
          and receiver_check.receiver_user_id = auth.uid()
          and receiver_check.is_active
      ) then receiver.momo_number
    else null
  end as receiver_momo_number,
  receiver.label as receiver_display_label,
  receiver.network as receiver_network,
  c.created_at, c.updated_at, c.archived_at,
  c.accent_color_hex, c.recurring_cadence,
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
  select route.momo_number, route.label, route.network
  from public.collection_receivers route
  where route.collection_id = c.id and route.is_active
  order by route.created_at asc
  limit 1
) receiver on true
where public.user_can_read_collection(c.id, auth.uid());

revoke all on public.member_collections_view from public, anon;
grant select on public.member_collections_view to authenticated;
grant select on public.member_contributions_view,
  public.member_collection_summary_view to authenticated;

-- Browser clients use only member-safe views/RPCs. Raw evidence tables remain
-- denied. Service-role Edge functions own ingestion, parsing, and allocation.
grant execute on function public.create_contribution_intent(uuid, bigint, text)
  to authenticated;
grant execute on function public.list_current_user_payment_intents()
  to authenticated;
grant execute on function public.record_sms_access_consent(boolean, text, text, text)
  to authenticated;
grant execute on function public.ingest_raw_payment_sms(
  uuid, uuid, text, text, text, uuid, text, timestamptz
) to service_role;
grant execute on function public.claim_raw_payment_sms_for_parse(uuid, uuid)
  to service_role;
grant execute on function public.allocate_parsed_payment_event(uuid)
  to service_role;
comment on function public.allocate_parsed_payment_event(uuid) is
  'Matches one complete deterministic MoMo receipt to one pending payer intent and posts the balanced ledger atomically.';
grant execute on function public.post_payment_from_event(uuid, uuid, uuid, text)
  to service_role;
grant execute on function public.mint_native_action_capability(
  uuid, text, text, jsonb, text, text, text, text[], timestamptz
) to service_role;

do $$
declare
  restored record;
begin
  for restored in
    select procedure.oid::regprocedure as signature
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any (array[
        'admin_list_payment_intents', 'admin_get_payment_intent',
        'admin_list_payments', 'admin_get_payment',
        'admin_list_payment_events', 'admin_get_payment_event',
        'admin_list_allocations', 'admin_list_unallocated',
        'admin_list_ledger', 'admin_list_receivers', 'admin_get_receiver',
        'admin_list_sms_metadata', 'admin_get_sms_metadata',
        'admin_reparse_payment_event', 'admin_reveal_raw_sms'
      ])
  loop
    execute format('grant execute on function %s to authenticated', restored.signature);
  end loop;
end;
$$;

update public.admin_navigation_items
set enabled = true, updated_at = now(),
    updated_reason = 'Restored for Rwanda MoMo and SMS operations'
where key in (
  'payment_intents', 'transactions', 'sms_parsing', 'allocations',
  'exceptions', 'ledger', 'receivers', 'sms'
);

update public.admin_navigation_items
set metadata = coalesce(metadata, '{}'::jsonb) || '{"rail":"rw_momo"}'::jsonb,
    updated_at = now()
where key in (
  'payment_intents', 'transactions', 'sms_parsing', 'allocations',
  'exceptions', 'ledger', 'receivers', 'sms'
);

update public.admin_navigation_items
set label = mapped.label,
    route_path = mapped.route_path,
    updated_at = now()
from (values
  ('payment_intents', 'MoMo intents', '/admin/momo-intents'),
  ('transactions', 'MoMo transactions', '/admin/momo-transactions'),
  ('sms_parsing', 'MoMo SMS parsing', '/admin/momo-parsing'),
  ('allocations', 'MoMo allocations', '/admin/momo-allocations'),
  ('exceptions', 'MoMo exceptions', '/admin/momo-exceptions'),
  ('ledger', 'Rwanda ledger', '/admin/momo-ledger'),
  ('receivers', 'MoMo receivers', '/admin/momo-receivers'),
  ('sms', 'Raw SMS metadata', '/admin/momo-sms')
) as mapped(key, label, route_path)
where public.admin_navigation_items.key = mapped.key;

update public.admin_queue_specs
set enabled = true, updated_at = now(),
    updated_reason = 'Restored for Rwanda MoMo and SMS operations'
where rpc_name in (
  'admin_list_payment_intents', 'admin_list_payments',
  'admin_list_payment_events', 'admin_list_allocations',
  'admin_list_unallocated', 'admin_list_ledger',
  'admin_list_receivers', 'admin_list_sms_metadata'
);

update public.feature_flags
set enabled = true,
    updated_reason = 'Rwanda Android MoMo receipt ingestion restored',
    updated_at = now()
where key in ('enable_android_sms_access', 'enable_sms_reader');

update public.payment_entrypoints
set is_active = true,
    updated_reason = 'Rwanda USSD contribution rail restored',
    updated_at = now()
where network = 'mtn_momo' or key like 'rw.mtn_momo.%';

update public.system_settings
set value = '{"rwanda":{"provider":"momo_ussd_sms","currency":"RWF"},"diaspora":{"provider":"sepa_credit_transfer","currency":"EUR","handoff":"revolut_app"}}'::jsonb,
    description = 'Geography-specific Rwanda MoMo and diaspora bank transfer modes',
    updated_at = now()
where key = 'payments.mode';

insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
values (
  null, 'payments.geographic_rails.restored', 'system_setting', null,
  '{"rwanda":"momo_ussd_sms","diaspora":"sepa_revolut","user_groups":"private_android_only"}'::jsonb
);

commit;
