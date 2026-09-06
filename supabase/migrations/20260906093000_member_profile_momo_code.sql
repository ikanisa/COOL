begin;

-- Reconnect the existing optional merchant-code column through the private
-- member profile API. Apply before clients send p_momo_pay_code.
create or replace function public._member_profile_payload(profile_row public.profiles)
returns jsonb language sql immutable set search_path = ''
as $$
  select case when profile_row.id is null then null else jsonb_build_object(
    'id',profile_row.id,'public_id',profile_row.public_id,
    'whatsapp_phone',profile_row.whatsapp_phone,
    'country_code',profile_row.country_code,'currency_code',profile_row.currency_code,
    'momo_provider',profile_row.momo_provider,'momo_number',profile_row.momo_number,
    'momo_pay_code',case when profile_row.country_code='RW' then profile_row.momo_pay_code else null end,
    'revolut_link',profile_row.revolut_link,'revolut_account',profile_row.revolut_account
  ) end;
$$;
revoke all on function public._member_profile_payload(public.profiles)
  from public, anon, authenticated;

-- Keep the five-argument RPC for older clients. All six parameters here are
-- required, so PostgREST can resolve old and new calls without ambiguity.
create or replace function public.update_current_member_profile(
  p_country_code text,
  p_momo_provider text,
  p_momo_number text,
  p_revolut_link text,
  p_revolut_account text,
  p_momo_pay_code text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  profile_row public.profiles%rowtype;
  clean_code text := nullif(btrim(coalesce(p_momo_pay_code, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if upper(btrim(p_country_code)) <> 'RW' then clean_code := null; end if;
  if clean_code is not null and clean_code !~ '^[0-9]{4,9}$' then
    raise exception 'Enter a MoMo code with 4 to 9 digits.';
  end if;

  -- The existing RPC owns country, phone/provider validation, identity,
  -- account rules and the payment-route audit. Both writes are atomic.
  perform public.update_current_member_profile(
    p_country_code, p_momo_provider, p_momo_number,
    p_revolut_link, p_revolut_account
  );
  update public.profiles set momo_pay_code=clean_code
    where id=auth.uid() returning * into profile_row;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'profile.momo_code.updated','profile',auth.uid(),
      jsonb_build_object('has_momo_code',clean_code is not null));
  return public._member_profile_payload(profile_row);
end;
$$;
revoke all on function public.update_current_member_profile(text,text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.update_current_member_profile(text,text,text,text,text,text)
  to authenticated;

commit;
