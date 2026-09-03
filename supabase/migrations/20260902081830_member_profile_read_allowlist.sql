begin;

create or replace function public._member_profile_payload(profile_row public.profiles)
returns jsonb language sql immutable set search_path = ''
as $$
  select case when profile_row.id is null then null else jsonb_build_object(
    'id',profile_row.id,'public_id',profile_row.public_id,
    'whatsapp_phone',profile_row.whatsapp_phone,
    'country_code',profile_row.country_code,'currency_code',profile_row.currency_code,
    'momo_provider',profile_row.momo_provider,'momo_number',profile_row.momo_number,
    'revolut_link',profile_row.revolut_link,'revolut_account',profile_row.revolut_account
  ) end;
$$;
revoke all on function public._member_profile_payload(public.profiles) from public,anon,authenticated;

create or replace function public.get_current_member_profile()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  return (select public._member_profile_payload(profile) from public.profiles profile where profile.id=auth.uid());
end;
$$;

create or replace function public.ensure_current_member_profile(
  p_whatsapp_phone text,
  p_country_code text default null
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare profile_row public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  profile_row := public.ensure_current_profile(p_whatsapp_phone,p_country_code);
  return public._member_profile_payload(profile_row);
end;
$$;
revoke all on function public.get_current_member_profile() from public,anon,authenticated;
revoke all on function public.ensure_current_member_profile(text,text) from public,anon,authenticated;
grant execute on function public.get_current_member_profile() to authenticated;
grant execute on function public.ensure_current_member_profile(text,text) to authenticated;

-- Preserve Admin/SMS names in storage; retire full-row member read surfaces.
revoke execute on function public.get_current_profile() from public,anon,authenticated;
revoke execute on function public.ensure_current_profile(text,text) from public,anon,authenticated;
commit;
