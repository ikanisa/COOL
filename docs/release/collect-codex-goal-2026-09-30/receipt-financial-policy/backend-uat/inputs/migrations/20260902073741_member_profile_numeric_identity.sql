begin;

-- Member profiles use numeric Collect IDs, never user-entered names.
-- Historical names and Admin SMS/reconciliation evidence are left untouched.
-- Release this migration before the member app that calls this RPC.
create or replace function public.update_current_member_profile(
  p_country_code text,
  p_momo_provider text default null,
  p_momo_number text default null,
  p_revolut_link text default null,
  p_revolut_account text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_row public.profiles%rowtype;
  country_rule public.profile_country_rules%rowtype;
  auth_phone text;
  clean_auth_momo text;
  clean_country text := upper(btrim(coalesce(p_country_code, '')));
  clean_provider text := lower(nullif(btrim(coalesce(p_momo_provider, '')), ''));
  clean_momo text := public._rwanda_momo_local(p_momo_number);
  clean_revolut_link text := nullif(btrim(coalesce(p_revolut_link, '')), '');
  clean_revolut_account text := nullif(btrim(coalesce(p_revolut_account, '')), '');
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
  elsif clean_revolut_link is null
     or clean_revolut_link !~ '^https://([a-z0-9-]+\.)?revolut\.me/[A-Za-z0-9._~-]+/?$'
     or clean_revolut_account is null
     or char_length(clean_revolut_account) not between 4 and 120 then
    raise exception 'Add your Revolut.me link and account details';
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
$$;

revoke all on function public.update_current_member_profile(text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.update_current_member_profile(text, text, text, text, text)
  to authenticated;

-- Retire member name submission; do not drop historical columns or data.
revoke execute on function public.update_current_profile(text, text, text, text, text, text, text)
  from public, anon, authenticated;
revoke update (display_name) on public.profiles from authenticated;

commit;
