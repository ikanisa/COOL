begin;

-- Display-only forward fix: use effective approval + active owner role, retain
-- identity masking and permission checks, and preserve requested page ordering.
create or replace function public.admin_list_members(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('users.read');
  with base as (
    select
      member.id,
      'Collect ID ' || member.collect_id as title,
      case when coalesce(member.linked_user_id, claim.user_id) is null
        then 'Feature phone • ' || public.mask_phone(identity.momo_number)
        else 'App account • ' || public.mask_phone(
          coalesce(profile.whatsapp_phone, identity.momo_number)
        )
      end as subtitle,
      case when (
        collect_admin_access.approved_identity(profile.id)
        and exists (
          select 1 from public.admin_user_roles assignment
          join public.admin_roles role on role.id = assignment.role_id
          where assignment.user_id = profile.id
            and assignment.revoked_at is null
            and role.name = 'platform_owner'
        )
      )
        then 'admin' else member.lifecycle end as status,
      member.created_at,
      coalesce(membership.active_groups, 0)::integer as active_groups,
      jsonb_build_object(
        'public_id', member.collect_id,
        'display_name', coalesce(identity.member_name, profile.display_name),
        'momo_registered_name', identity.momo_name,
        'whatsapp_masked', case when profile.id is null then null
          else public.mask_phone(profile.whatsapp_phone) end,
        'momo_masked', public.mask_phone(identity.momo_number),
        'country_code', coalesce(profile.country_code, 'RW'),
        'currency_code', coalesce(profile.currency_code, 'RWF'),
        'momo_provider', case when identity.member_id is not null
          then 'mtn_momo' else profile.momo_provider end,
        'account_state', case
          when member.linked_user_id is not null then 'app'
          when claim.user_id is not null then 'app_claimed'
          else 'feature_phone'
        end,
        'active_groups', coalesce(membership.active_groups, 0),
        'is_platform_admin', (
        collect_admin_access.approved_identity(profile.id)
        and exists (
          select 1 from public.admin_user_roles assignment
          join public.admin_roles role on role.id = assignment.role_id
          where assignment.user_id = profile.id
            and assignment.revoked_at is null
            and role.name = 'platform_owner'
        )
      )
      ) as extra
    from collect_hybrid.member_records member
    left join collect_hybrid.member_account_claims claim
      on claim.member_record_id = member.id and claim.user_id is not null
    left join public.profiles profile
      on profile.id = coalesce(member.linked_user_id, claim.user_id)
    left join collect_hybrid.member_momo_identities identity
      on identity.member_id = member.id
    left join lateral (
      select count(distinct membership.collection_id) as active_groups
      from public.collection_members membership
      join public.collections collection
        on collection.id = membership.collection_id
      where membership.member_record_id = member.id
        and membership.status = 'active'
        and collection.archived_at is null
    ) membership on true
    where member.lifecycle = 'active'
      and coalesce(membership.active_groups, 0) > 0
  ), filtered as (
    select * from base
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'display_name', '')
        ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'momo_registered_name', '')
        ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'momo_masked', '')
        ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*,
      row_number() over (order by
        case when p_sort = 'created_at_asc' then created_at end asc nulls last,
        created_at desc, id
      ) as ordinal
    from filtered
    order by ordinal
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      public._admin_row(
        id, title, subtitle, status,
        active_groups::text || ' groups', created_at, extra
      ) order by ordinal
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public._admin_list_people_by_membership(
  p_has_active_group boolean,
  p_search text,
  p_status text,
  p_limit integer,
  p_offset integer,
  p_sort text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('users.read');
  with base as (
    select
      profile.id,
      'Collect ID ' || profile.public_id as title,
      public.mask_phone(profile.whatsapp_phone) as subtitle,
      case
        when (
        collect_admin_access.approved_identity(profile.id)
        and exists (
          select 1 from public.admin_user_roles assignment
          join public.admin_roles role on role.id = assignment.role_id
          where assignment.user_id = profile.id
            and assignment.revoked_at is null
            and role.name = 'platform_owner'
        )
      ) then 'admin'
        when p_has_active_group then 'active'
        else 'registered'
      end as status,
      profile.created_at,
      profile.updated_at,
      coalesce(member_count.active_groups, 0)::integer as active_groups,
      jsonb_build_object(
        'public_id', profile.public_id,
        'display_name', profile.display_name,
        'whatsapp_masked', public.mask_phone(profile.whatsapp_phone),
        'country_code', coalesce(profile.country_code, 'RW'),
        'currency_code', coalesce(profile.currency_code, 'RWF'),
        'momo_provider', profile.momo_provider,
        'momo_masked', public.mask_phone(profile.momo_number),
        'has_revolut_profile',
          profile.revolut_link is not null
          and profile.revolut_account is not null,
        'account_last4', case
          when profile.revolut_account is null then null
          else right(regexp_replace(
            profile.revolut_account, '[^A-Za-z0-9]', '', 'g'
          ), 4)
        end,
        'active_groups', coalesce(member_count.active_groups, 0),
        'is_platform_admin', (
        collect_admin_access.approved_identity(profile.id)
        and exists (
          select 1 from public.admin_user_roles assignment
          join public.admin_roles role on role.id = assignment.role_id
          where assignment.user_id = profile.id
            and assignment.revoked_at is null
            and role.name = 'platform_owner'
        )
      ),
        'updated_at', profile.updated_at
      ) as extra
    from public.profiles profile
    left join lateral (
      select count(distinct membership.collection_id) as active_groups
      from public.collection_members membership
      join public.collections collection
        on collection.id = membership.collection_id
      where (
          membership.user_id = profile.id
          or collect_hybrid.member_record_belongs_to_user(
            membership.member_record_id, profile.id
          )
        )
        and membership.status = 'active'
        and collection.archived_at is null
    ) member_count on true
    where case
      when p_has_active_group then coalesce(member_count.active_groups, 0) > 0
      else coalesce(member_count.active_groups, 0) = 0
    end
  ), filtered as (
    select * from base
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'display_name', '')
        ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'whatsapp_masked', '')
        ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'country_code', '')
        ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*,
      row_number() over (order by
        case when p_sort = 'created_at_asc' then created_at end asc nulls last,
        created_at desc, id
      ) as ordinal
    from filtered
    order by ordinal
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'title', title,
        'subtitle', subtitle,
        'status', status,
        'amount', active_groups::text || ' groups',
        'created_at', created_at
      ) || extra order by ordinal
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into result
  from counted;
  return result;
end;
$$;
revoke all on function public._admin_list_people_by_membership(
  boolean, text, text, integer, integer, text
) from public, anon, authenticated;


update public.admin_queue_specs
set subtitle = 'App and feature-phone members with an active group membership.'
where rpc_name in ('admin_list_members', 'admin_list_users');

commit;
