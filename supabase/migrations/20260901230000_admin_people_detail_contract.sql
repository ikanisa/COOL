begin;

-- Keep user and member detail as operational context rather than exposing the
-- internal Collect ID or display-name placeholders used by older Admin RPCs.
create or replace function public.admin_get_user(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('users.read');

  select jsonb_build_object(
    'id', profile.id,
    'phone_masked', public.mask_phone(profile.whatsapp_phone),
    'country_code', upper(coalesce(nullif(btrim(profile.country_code), ''), 'RW')),
    'payment_profile', case
      when upper(coalesce(nullif(btrim(profile.country_code), ''), 'RW')) = 'RW'
        then case
          when nullif(btrim(coalesce(profile.momo_number, '')), '') is null
            then 'MoMo not set'
          else public.mask_phone(profile.momo_number)
        end
      when profile.revolut_link is not null
       and profile.revolut_account is not null
        then 'Revolut ready'
      else 'Revolut not set'
    end,
    'momo_masked', public.mask_phone(profile.momo_number),
    'active_groups', coalesce(membership.active_groups, 0),
    'status', case
      when profile.is_platform_admin then 'admin'
      when coalesce(membership.active_groups, 0) > 0 then 'active'
      else 'registered'
    end,
    'created_at', profile.created_at,
    'updated_at', profile.updated_at
  )
  into result
  from public.profiles profile
  left join lateral (
    select count(distinct member.collection_id)::integer as active_groups
    from public.collection_members member
    join public.collections collection on collection.id = member.collection_id
    where member.user_id = profile.id
      and member.status = 'active'
      and collection.archived_at is null
  ) membership on true
  where profile.id = p_id;

  return coalesce(result, '{}'::jsonb);
end;
$$;

revoke all on function public.admin_get_user(uuid) from public, anon;
grant execute on function public.admin_get_user(uuid) to authenticated, service_role;

comment on function public.admin_get_user(uuid) is
  'Permission-gated Admin people detail with masked identity, country, payment readiness, and membership count.';

commit;
