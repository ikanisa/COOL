begin;

-- One Admin members queue now projects both app members and account-independent
-- member records. Names are available to authorized operators, but phone data
-- remains masked and no Auth user is fabricated for a feature-phone member.
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
      case when coalesce(profile.is_platform_admin, false)
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
        'is_platform_admin', coalesce(profile.is_platform_admin, false)
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
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc,
      id
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      public._admin_row(
        id, title, subtitle, status,
        active_groups::text || ' groups', created_at, extra
      ) order by created_at desc, id
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create function public.admin_get_member_record(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.assert_admin_permission('users.read');
  return coalesce((
    select jsonb_build_object(
      'id', member.id,
      'collect_id', member.collect_id,
      'member_name', coalesce(identity.member_name, profile.display_name),
      'momo_registered_name', identity.momo_name,
      'momo_masked', public.mask_phone(identity.momo_number),
      'whatsapp_masked', case when profile.id is null then null
        else public.mask_phone(profile.whatsapp_phone) end,
      'account_state', case
        when member.linked_user_id is not null then 'app'
        when claim.user_id is not null then 'app_claimed'
        else 'feature_phone'
      end,
      'origin', member.origin,
      'lifecycle', member.lifecycle,
      'active_groups', (
        select count(distinct membership.collection_id)
        from public.collection_members membership
        join public.collections collection
          on collection.id = membership.collection_id
        where membership.member_record_id = member.id
          and membership.status = 'active'
          and collection.archived_at is null
      ),
      'created_at', member.created_at
    )
    from collect_hybrid.member_records member
    left join collect_hybrid.member_account_claims claim
      on claim.member_record_id = member.id and claim.user_id is not null
    left join public.profiles profile
      on profile.id = coalesce(member.linked_user_id, claim.user_id)
    left join collect_hybrid.member_momo_identities identity
      on identity.member_id = member.id
    where member.id = p_id
  ), '{}'::jsonb);
end;
$$;

revoke all on function public.admin_list_members(
  text, text, integer, integer, text
) from public, anon;
revoke all on function public.admin_get_member_record(uuid)
  from public, anon;
grant execute on function public.admin_list_members(
  text, text, integer, integer, text
) to authenticated, service_role;
grant execute on function public.admin_get_member_record(uuid)
  to authenticated, service_role;

-- Registered-user counts treat a claimed offline membership as a real group
-- membership, so the same account is not incorrectly shown as a non-member.
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
set search_path = public
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
        when profile.is_platform_admin then 'admin'
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
        'is_platform_admin', profile.is_platform_admin,
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
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
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
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result
  from counted;
  return result;
end;
$$;
revoke all on function public._admin_list_people_by_membership(
  boolean, text, text, integer, integer, text
) from public, anon, authenticated;

-- Member-facing rosters include feature-phone members by safe Collect ID and
-- channel state. Full names and MoMo numbers remain Admin-only.
create or replace function collect_member_actions.group_roster(
  p_collection_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  group_row public.collections%rowtype;
  result jsonb;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into group_row
  from public.collections where id = p_collection_id;
  if group_row.id is null
     or not public.user_can_read_collection(p_collection_id, actor) then
    raise exception 'Join this group to view members' using errcode = '42501';
  end if;

  with candidates as (
    select
      coalesce(
        membership.member_record_id::text,
        'user:' || membership.user_id::text
      ) as identity_key,
      membership.member_record_id,
      coalesce(
        membership.user_id, member.linked_user_id, claim.user_id
      ) as account_user_id,
      coalesce(member.collect_id::text, profile.public_id::text) as public_id,
      case when coalesce(
          membership.user_id, member.linked_user_id, claim.user_id
        ) = group_row.creator_user_id then 'owner'
        when membership.role = 'owner' then 'admin'
        else membership.role::text end as role,
      membership.status::text as status,
      membership.created_at as joined_at
    from public.collection_members membership
    left join collect_hybrid.member_records member
      on member.id = membership.member_record_id
    left join collect_hybrid.member_account_claims claim
      on claim.member_record_id = member.id and claim.user_id is not null
    left join public.profiles profile
      on profile.id = coalesce(
        membership.user_id, member.linked_user_id, claim.user_id
      )
    where membership.collection_id = p_collection_id
    union all
    select
      coalesce(member.id::text, 'user:' || group_row.creator_user_id::text),
      member.id,
      group_row.creator_user_id,
      coalesce(member.collect_id::text, profile.public_id::text),
      'owner', 'active', group_row.created_at
    from public.profiles profile
    left join collect_hybrid.member_records member
      on member.linked_user_id = profile.id
    where profile.id = group_row.creator_user_id
      and not exists (
        select 1 from public.collection_members membership
        where membership.collection_id = p_collection_id
          and membership.user_id = group_row.creator_user_id
      )
  ), ranked as (
    select *,
      min(joined_at) over (partition by identity_key) as first_joined_at,
      row_number() over (
        partition by identity_key
        order by
          case status when 'active' then 0 when 'invited' then 1 else 2 end,
          case role when 'owner' then 0 when 'admin' then 1
            when 'receiver' then 2 when 'member' then 3
            when 'contributor' then 4 else 5 end,
          joined_at, status
      ) as priority
    from candidates
    where public_id is not null
  ), roster as (
    select identity_key, member_record_id, account_user_id, public_id,
      role, status, first_joined_at as joined_at
    from ranked where priority = 1
  ), visible_amounts as (
    select roster.identity_key, payment.currency,
      payment.amount_rwf as amount_minor
    from public.payments payment
    join roster on (
      payment.member_record_id = roster.member_record_id
      or (
        payment.member_record_id is null
        and payment.contributor_user_id = roster.account_user_id
      )
    )
    where payment.collection_id = p_collection_id
      and payment.status = 'posted'
      and (
        roster.account_user_id = actor
        or (
          payment.anonymity_choice = 'public_id'
          and payment.contributor_public_id::text = roster.public_id
        )
      )
    union all
    select roster.identity_key, transaction.currency,
      transaction.amount_minor
    from public.bank_transactions transaction
    join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = transaction.id
    join roster on roster.account_user_id = allocation.contributor_user_id
    where allocation.collection_id = p_collection_id
      and transaction.status = 'reconciled'
      and roster.account_user_id = actor
  ), totals as (
    select identity_key, currency, sum(amount_minor)::bigint as amount_minor
    from visible_amounts group by identity_key, currency
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'public_id', roster.public_id,
    'role', roster.role,
    'status', roster.status,
    'joined_at', roster.joined_at,
    'account_state', case when roster.account_user_id is null
      then 'feature_phone' else 'app' end,
    'amount_scope', case when roster.account_user_id = actor then 'own'
      when exists (
        select 1 from totals
        where totals.identity_key = roster.identity_key
      ) then 'shared' else 'hidden' end,
    'contributions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', totals.currency,
        'amount_minor', totals.amount_minor
      ) order by totals.currency)
      from totals where totals.identity_key = roster.identity_key
    ), '[]'::jsonb)
  ) order by roster.public_id), '[]'::jsonb)
  into result from roster;
  return result;
end;
$$;
revoke all on function collect_member_actions.group_roster(uuid)
  from public, anon, authenticated;
grant execute on function collect_member_actions.group_roster(uuid)
  to authenticated;

comment on function public.admin_get_member_record(uuid) is
  'Authorized combined app/feature-phone member detail. MoMo and WhatsApp numbers are masked; raw receipt evidence remains separately controlled.';

commit;
