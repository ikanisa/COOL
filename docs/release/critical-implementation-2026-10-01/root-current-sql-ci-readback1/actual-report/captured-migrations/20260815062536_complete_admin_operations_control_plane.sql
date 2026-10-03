begin;

alter table public.notification_deliveries
  add column if not exists prior_attempt_count integer not null default 0
    check (prior_attempt_count >= 0);

-- Complete the admin operations control plane without exposing operational
-- tables directly to browser roles. Every browser entry point remains an
-- authenticated SECURITY DEFINER RPC with an explicit permission assertion.

insert into public.admin_permissions (name, description)
values
  ('notifications.read', 'Read notification event and delivery health'),
  ('notifications.manage', 'Retry failed notification deliveries with a reason')
on conflict (name) do update set description = excluded.description;

insert into public.admin_role_permissions (role_id, permission_name)
select role.id, desired.permission_name
from public.admin_roles role
join (
  values
    ('platform_owner', 'notifications.read'),
    ('platform_owner', 'notifications.manage'),
    ('compliance_admin', 'notifications.read'),
    ('operations_admin', 'notifications.read'),
    ('operations_admin', 'notifications.manage'),
    ('group_ops_admin', 'notifications.read'),
    ('payments_admin', 'notifications.read'),
    ('support_admin', 'notifications.read'),
    ('read_only_admin', 'notifications.read')
) as desired(role_name, permission_name)
  on desired.role_name = role.name
on conflict (role_id, permission_name) do nothing;

-- Legacy platform owners are still supported, but their UI identity must
-- reflect the same effective permissions enforced by has_admin_permission().
create or replace function public.admin_current_user()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  profile_row public.profiles%rowtype;
  legacy_owner boolean;
begin
  if auth.uid() is null then
    return '{}'::jsonb;
  end if;

  select * into profile_row
  from public.profiles
  where id = auth.uid();

  if profile_row.id is null
     or not public.has_admin_permission('overview.read', profile_row.id) then
    return '{}'::jsonb;
  end if;

  legacy_owner := coalesce(profile_row.is_platform_admin, false);

  return jsonb_build_object(
    'user_id', profile_row.id,
    'display_name', 'Collect ID ' || profile_row.public_id,
    'phone_masked', public.mask_phone(profile_row.whatsapp_phone),
    'roles', case
      when legacy_owner then (
        select coalesce(jsonb_agg(role_name order by role_name), '[]'::jsonb)
        from (
          select 'platform_owner'::text as role_name
          union
          select role.name
          from public.admin_user_roles user_role
          join public.admin_roles role on role.id = user_role.role_id
          where user_role.user_id = profile_row.id
            and user_role.revoked_at is null
        ) effective_roles
      )
      else (
        select coalesce(jsonb_agg(role.name order by role.name), '[]'::jsonb)
        from public.admin_user_roles user_role
        join public.admin_roles role on role.id = user_role.role_id
        where user_role.user_id = profile_row.id
          and user_role.revoked_at is null
      )
    end,
    'permissions', case
      when legacy_owner then (
        select coalesce(jsonb_agg(permission.name order by permission.name), '[]'::jsonb)
        from public.admin_permissions permission
      )
      else (
        select coalesce(
          jsonb_agg(distinct role_permission.permission_name order by role_permission.permission_name),
          '[]'::jsonb
        )
        from public.admin_user_roles user_role
        join public.admin_role_permissions role_permission
          on role_permission.role_id = user_role.role_id
        where user_role.user_id = profile_row.id
          and user_role.revoked_at is null
      )
    end
  );
end;
$$;

revoke execute on function public.admin_current_user() from public, anon;
grant execute on function public.admin_current_user() to authenticated;

-- Public collection helpers are intentionally callable from RLS and public
-- views. Fail closed when a browser caller supplies another user's UUID.
create or replace function public.user_is_collection_admin(
  collection uuid,
  user_uuid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.role() = 'service_role'
      or user_uuid is not distinct from auth.uid() then
      public.is_platform_admin(user_uuid)
      or exists (
        select 1
        from public.collections c
        where c.id = collection and c.creator_user_id = user_uuid
      )
      or exists (
        select 1
        from public.collection_members member
        where member.collection_id = collection
          and member.user_id = user_uuid
          and member.status = 'active'
          and member.role in ('owner', 'admin', 'receiver')
      )
    else false
  end;
$$;

create or replace function public.user_can_read_collection(
  collection uuid,
  user_uuid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.role() = 'service_role'
      or user_uuid is not distinct from auth.uid() then
      exists (
        select 1
        from public.collections c
        where c.id = collection
          and (
            c.public_status = 'public_approved'
            or c.creator_user_id = user_uuid
            or public.is_platform_admin(user_uuid)
            or exists (
              select 1
              from public.collection_members member
              where member.collection_id = c.id
                and member.user_id = user_uuid
                and member.status = 'active'
            )
          )
      )
    else false
  end;
$$;

revoke execute on function public.user_is_collection_admin(uuid, uuid) from public;
revoke execute on function public.user_can_read_collection(uuid, uuid) from public;
grant execute on function public.user_is_collection_admin(uuid, uuid) to anon, authenticated, service_role;
grant execute on function public.user_can_read_collection(uuid, uuid) to anon, authenticated, service_role;

comment on function public.user_is_collection_admin(uuid, uuid) is
  'Browser callers may evaluate only auth.uid(); anon may evaluate the null default for public RLS; service_role may evaluate arbitrary users.';
comment on function public.user_can_read_collection(uuid, uuid) is
  'Browser callers may evaluate only auth.uid(); anon may evaluate the null default for public discovery; service_role may evaluate arbitrary users.';

create or replace function public.admin_list_payment_intents(
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
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_sort text := coalesce(nullif(p_sort, ''), 'created_at_desc');
  v_result jsonb;
begin
  perform public.assert_admin_permission('payments.read');
  if v_sort not in ('created_at_desc', 'created_at_asc', 'amount_desc', 'amount_asc') then
    v_sort := 'created_at_desc';
  end if;

  with filtered as (
    select intent.*
    from public.payment_intents intent
    where (p_status is null or intent.status::text = p_status)
      and (
        p_search is null
        or intent.contribution_code ilike '%' || p_search || '%'
        or intent.reported_transaction_id ilike '%' || p_search || '%'
      )
  ), ordered as (
    select filtered.*,
      row_number() over (
        order by
          case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
          case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
          case when v_sort = 'amount_asc' then filtered.expected_amount_rwf end asc nulls last,
          case when v_sort = 'amount_desc' then filtered.expected_amount_rwf end desc nulls last,
          filtered.created_at desc,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
      case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
      case when v_sort = 'amount_asc' then filtered.expected_amount_rwf end asc nulls last,
      case when v_sort = 'amount_desc' then filtered.expected_amount_rwf end desc nulls last,
      filtered.created_at desc,
      filtered.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      public._admin_row(
        ordered.id,
        'Intent ' || ordered.contribution_code,
        'Group ' || left(ordered.collection_id::text, 8),
        ordered.status::text,
        coalesce(ordered.expected_amount_rwf::text || ' RWF', 'Amount not fixed'),
        ordered.created_at,
        jsonb_build_object('expires_at', ordered.expires_at)
      ) order by ordered.admin_rank
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result
  from ordered;

  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

create or replace function public.admin_get_payment_intent(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('payments.read');
  return coalesce((
    select jsonb_build_object(
      'id', intent.id,
      'collection_id', intent.collection_id,
      'contributor_user_id', intent.contributor_user_id,
      'contribution_code', intent.contribution_code,
      'expected_amount_rwf', intent.expected_amount_rwf,
      'reported_transaction_id', intent.reported_transaction_id,
      'status', intent.status,
      'created_at', intent.created_at,
      'expires_at', intent.expires_at
    )
    from public.payment_intents intent
    where intent.id = p_id
  ), '{}'::jsonb);
end;
$$;

create or replace function public.admin_list_payments(
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
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_sort text := coalesce(nullif(p_sort, ''), 'created_at_desc');
  v_result jsonb;
begin
  perform public.assert_admin_permission('payments.read');
  if v_sort not in ('created_at_desc', 'created_at_asc', 'amount_desc', 'amount_asc') then
    v_sort := 'created_at_desc';
  end if;

  with filtered as (
    select payment.*
    from public.payments payment
    where (p_status is null or payment.status = p_status)
      and (p_search is null or payment.transaction_id ilike '%' || p_search || '%')
  ), ordered as (
    select filtered.*,
      row_number() over (
        order by
          case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
          case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
          case when v_sort = 'amount_asc' then filtered.amount_rwf end asc nulls last,
          case when v_sort = 'amount_desc' then filtered.amount_rwf end desc nulls last,
          filtered.created_at desc,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
      case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
      case when v_sort = 'amount_asc' then filtered.amount_rwf end asc nulls last,
      case when v_sort = 'amount_desc' then filtered.amount_rwf end desc nulls last,
      filtered.created_at desc,
      filtered.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      public._admin_row(
        ordered.id,
        coalesce(ordered.transaction_id, 'Posted transaction'),
        ordered.source,
        ordered.status,
        ordered.amount_rwf::text || ' RWF',
        ordered.created_at,
        jsonb_build_object('payment_intent_id', ordered.payment_intent_id)
      ) order by ordered.admin_rank
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result
  from ordered;

  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

create or replace function public.admin_list_admin_users(
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
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  perform public.assert_admin_permission('admin_users.read');

  with admin_profiles as (
    select
      profile.id,
      profile.public_id,
      profile.created_at,
      profile.is_platform_admin,
      coalesce((
        select array_agg(role.name order by role.name)
        from public.admin_user_roles user_role
        join public.admin_roles role on role.id = user_role.role_id
        where user_role.user_id = profile.id and user_role.revoked_at is null
      ), '{}'::text[]) as assigned_roles
    from public.profiles profile
    where coalesce(profile.is_platform_admin, false)
       or exists (
         select 1 from public.admin_user_roles user_role
         where user_role.user_id = profile.id and user_role.revoked_at is null
       )
  ), filtered as (
    select admin_profile.*,
      case
        when admin_profile.is_platform_admin
          and not ('platform_owner' = any(admin_profile.assigned_roles))
        then array_prepend('platform_owner', admin_profile.assigned_roles)
        else admin_profile.assigned_roles
      end as effective_roles
    from admin_profiles admin_profile
    where (
      p_search is null
      or admin_profile.public_id = p_search
      or array_to_string(admin_profile.assigned_roles, ' ') ilike '%' || p_search || '%'
    )
      and (
        p_status is null
        or p_status in ('admin', 'active')
        or (p_status = 'platform_owner' and (
          admin_profile.is_platform_admin
          or 'platform_owner' = any(admin_profile.assigned_roles)
        ))
        or p_status = any(admin_profile.assigned_roles)
      )
  ), ordered as (
    select filtered.*,
      row_number() over (
        order by
          case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc' then filtered.created_at end asc nulls last,
          filtered.created_at desc,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc' then filtered.created_at end asc nulls last,
      filtered.created_at desc,
      filtered.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      public._admin_row(
        ordered.id,
        'Collect ID ' || ordered.public_id,
        array_to_string(ordered.effective_roles, ' • '),
        'active',
        cardinality(ordered.effective_roles)::text || ' roles',
        ordered.created_at,
        jsonb_build_object('roles', to_jsonb(ordered.effective_roles))
      ) order by ordered.admin_rank
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result
  from ordered;

  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

create or replace function public.admin_get_admin_user(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('admin_users.read');
  return coalesce((
    select jsonb_build_object(
      'id', profile.id,
      'public_id', profile.public_id,
      'phone_masked', public.mask_phone(profile.whatsapp_phone),
      'status', case when coalesce(profile.is_platform_admin, false)
        or exists (
          select 1 from public.admin_user_roles active_role
          where active_role.user_id = profile.id and active_role.revoked_at is null
        ) then 'active' else 'revoked' end,
      'legacy_platform_owner', coalesce(profile.is_platform_admin, false),
      'active_roles', (
        select coalesce(jsonb_agg(role_name order by role_name), '[]'::jsonb)
        from (
          select role.name as role_name
          from public.admin_user_roles user_role
          join public.admin_roles role on role.id = user_role.role_id
          where user_role.user_id = profile.id and user_role.revoked_at is null
          union
          select 'platform_owner' where coalesce(profile.is_platform_admin, false)
        ) roles
      ),
      'available_roles', (
        select coalesce(jsonb_agg(role.name order by role.name), '[]'::jsonb)
        from public.admin_roles role
      ),
      'created_at', profile.created_at
    )
    from public.profiles profile
    where profile.id = p_id
  ), '{}'::jsonb);
end;
$$;

create or replace function public.admin_grant_user_role(
  p_user_id uuid,
  p_role_name text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  perform public.assert_admin_permission('admin_users.manage');
  if v_reason = '' then raise exception 'Reason is required'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Admin user profile not found';
  end if;
  select id into v_role_id from public.admin_roles where name = trim(p_role_name);
  if v_role_id is null then raise exception 'Admin role not found'; end if;
  if exists (
    select 1 from public.admin_user_roles
    where user_id = p_user_id and role_id = v_role_id and revoked_at is null
  ) then raise exception 'Admin role is already active'; end if;

  insert into public.admin_user_roles (user_id, role_id, granted_by, reason)
  values (p_user_id, v_role_id, auth.uid(), v_reason);
  perform public.create_audit_log(
    'admin.role.granted', 'profile', p_user_id,
    jsonb_build_object('role', trim(p_role_name), 'reason', v_reason)
  );
  return jsonb_build_object('ok', true, 'status', 'granted');
end;
$$;

create or replace function public.admin_revoke_user_role(
  p_user_id uuid,
  p_role_name text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
  v_reason text := trim(coalesce(p_reason, ''));
  v_effective_owner_count integer;
begin
  perform public.assert_admin_permission('admin_users.manage');
  if v_reason = '' then raise exception 'Reason is required'; end if;
  select id into v_role_id from public.admin_roles where name = trim(p_role_name);
  if v_role_id is null then raise exception 'Admin role not found'; end if;

  if trim(p_role_name) = 'platform_owner' then
    perform pg_advisory_xact_lock(hashtext('collect_admin_platform_owner_roster'));
    if p_user_id = auth.uid() then
      raise exception 'You cannot revoke your own platform owner role';
    end if;
    select count(*) into v_effective_owner_count
    from public.profiles profile
    where coalesce(profile.is_platform_admin, false)
       or exists (
         select 1
         from public.admin_user_roles owner_role
         join public.admin_roles role on role.id = owner_role.role_id
         where owner_role.user_id = profile.id
           and owner_role.revoked_at is null
           and role.name = 'platform_owner'
       );
    if v_effective_owner_count <= 1
       and not coalesce((select is_platform_admin from public.profiles where id = p_user_id), false) then
      raise exception 'The last platform owner cannot be revoked';
    end if;
  end if;

  update public.admin_user_roles
  set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = v_reason
  where user_id = p_user_id and role_id = v_role_id and revoked_at is null;
  if not found then raise exception 'Active admin role not found'; end if;

  perform public.create_audit_log(
    'admin.role.revoked', 'profile', p_user_id,
    jsonb_build_object('role', trim(p_role_name), 'reason', v_reason)
  );
  return jsonb_build_object('ok', true, 'status', 'revoked');
end;
$$;

create or replace function public.admin_list_notifications(
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
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  perform public.assert_admin_permission('notifications.read');
  with filtered as (
    select event.*,
      profile.public_id,
      (select count(*) from public.notification_deliveries delivery where delivery.event_id = event.id) as delivery_count,
      (select count(*) from public.notification_deliveries delivery where delivery.event_id = event.id and delivery.status = 'failed') as failed_count
    from public.notification_events event
    join public.profiles profile on profile.id = event.user_id
    where (p_status is null or event.status = p_status)
      and (
        p_search is null
        or event.type ilike '%' || p_search || '%'
        or profile.public_id = p_search
      )
  ), ordered as (
    select filtered.*,
      row_number() over (
        order by
          case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc' then filtered.created_at end asc nulls last,
          filtered.created_at desc,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc' then filtered.created_at end asc nulls last,
      filtered.created_at desc,
      filtered.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      public._admin_row(
        ordered.id,
        replace(initcap(replace(ordered.type, '_', ' ')), 'Momo', 'MoMo'),
        'Collect ID ' || ordered.public_id || ' • ' || ordered.delivery_count || ' deliveries',
        ordered.status,
        case when ordered.failed_count > 0 then ordered.failed_count || ' failed' else '' end,
        ordered.created_at,
        jsonb_build_object('failed_deliveries', ordered.failed_count)
      ) order by ordered.admin_rank
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result
  from ordered;
  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

create or replace function public.admin_get_notification(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('notifications.read');
  return coalesce((
    select jsonb_build_object(
      'id', event.id,
      'type', event.type,
      'title', event.title,
      'status', event.status,
      'collect_id', profile.public_id,
      'collection_id', event.collection_id,
      'deep_link', event.deep_link,
      'delivery_statuses', coalesce((
        select string_agg(count_rows.status || ': ' || count_rows.delivery_count::text, ', ' order by count_rows.status)
        from (
          select status, count(*) as delivery_count
          from public.notification_deliveries
          where event_id = event.id
          group by status
        ) count_rows
      ), 'No registered delivery'),
      'retryable_count', (
        select count(*)
        from public.notification_deliveries delivery
        join public.notification_device_tokens device on device.id = delivery.device_id
        where delivery.event_id = event.id
          and delivery.status = 'failed'
          and device.enabled
      ),
      'cumulative_attempt_count', coalesce((
        select sum(delivery.prior_attempt_count + delivery.attempt_count)
        from public.notification_deliveries delivery
        where delivery.event_id = event.id
      ), 0),
      'last_error_code', event.last_error_code,
      'created_at', event.created_at,
      'sent_at', event.sent_at,
      'read_at', event.read_at
    )
    from public.notification_events event
    join public.profiles profile on profile.id = event.user_id
    where event.id = p_id
  ), '{}'::jsonb);
end;
$$;

create or replace function public.admin_retry_notification(
  p_event_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := trim(coalesce(p_reason, ''));
  v_retried integer;
begin
  perform public.assert_admin_permission('notifications.manage');
  if v_reason = '' then raise exception 'Reason is required'; end if;

  update public.notification_deliveries delivery
  set status = 'queued',
      prior_attempt_count = delivery.prior_attempt_count + delivery.attempt_count,
      attempt_count = 0,
      next_attempt_at = now(),
      last_attempt_at = null,
      sent_at = null,
      provider_message_id = null,
      last_error_code = null,
      updated_at = now()
  from public.notification_device_tokens device
  where delivery.event_id = p_event_id
    and delivery.device_id = device.id
    and delivery.status = 'failed'
    and device.enabled;
  get diagnostics v_retried = row_count;
  if v_retried = 0 then raise exception 'No retryable failed deliveries'; end if;

  update public.notification_events
  set status = 'queued', last_error_code = null
  where id = p_event_id;
  perform public.create_audit_log(
    'notification.delivery.retried', 'notification_event', p_event_id,
    jsonb_build_object('reason', v_reason, 'delivery_count', v_retried)
  );
  return jsonb_build_object('ok', true, 'status', 'queued', 'delivery_count', v_retried);
end;
$$;

-- Replace static health labels with observed queue counters.
create or replace function public.admin_system_health(p_id text default 'system')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('system_health.read');
  return jsonb_build_object(
    'id', coalesce(nullif(p_id, ''), 'system'),
    'database', 'reachable',
    'auth', case when auth.uid() is null then 'unauthenticated' else 'authenticated' end,
    'parser_pending_sms', (select count(*) from public.raw_payment_sms where parse_status = 'pending'),
    'failed_sms_parse', (select count(*) from public.raw_payment_sms where parse_status = 'failed'),
    'unallocated_events', (select count(*) from public.parsed_payment_events where allocation_status in ('unallocated', 'ambiguous', 'needs_review')),
    'queued_notifications', (select count(*) from public.notification_deliveries where status = 'queued'),
    'processing_notifications', (select count(*) from public.notification_deliveries where status = 'processing'),
    'failed_notifications', (select count(*) from public.notification_deliveries where status = 'failed'),
    'checked_at', now()
  );
end;
$$;

-- Runtime navigation and queue metadata keep the database and Flutter fallback
-- model aligned. Payment intents and posted transactions are separate domains.
update public.admin_navigation_items
set label = 'Payment intents',
    route_path = '/admin/payment-intents',
    required_permission = 'payments.read',
    display_order = 40,
    updated_at = now()
where key = 'payment_intents';

insert into public.admin_navigation_items
  (key, label, icon_key, route_path, required_permission, display_order, enabled)
values
  ('transactions', 'Transactions', 'receipt_long', '/admin/transactions', 'payments.read', 45, true),
  ('notifications', 'Notifications', 'notifications', '/admin/notifications', 'notifications.read', 105, true)
on conflict (key) do update set
  label = excluded.label,
  icon_key = excluded.icon_key,
  route_path = excluded.route_path,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  updated_at = now();

insert into public.admin_queue_specs
  (rpc_name, title, subtitle, required_permission, display_order, enabled)
values
  ('admin_list_payment_intents', 'Payment intents', 'Review contribution intent lifecycle.', 'payments.read', 30, true),
  ('admin_list_payments', 'Transactions', 'Review posted MoMo transactions.', 'payments.read', 35, true),
  ('admin_list_notifications', 'Notifications', 'Monitor event and delivery health.', 'notifications.read', 95, true)
on conflict (rpc_name) do update set
  title = excluded.title,
  subtitle = excluded.subtitle,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  updated_at = now();

delete from public.admin_queue_filter_options
where rpc_name in ('admin_list_payment_intents', 'admin_list_payments', 'admin_list_notifications');

insert into public.admin_queue_filter_options
  (rpc_name, filter_kind, value, label, display_order, enabled)
values
  ('admin_list_payment_intents', 'status', '', 'All', 10, true),
  ('admin_list_payment_intents', 'status', 'pending', 'Pending', 20, true),
  ('admin_list_payment_intents', 'status', 'matched', 'Matched', 30, true),
  ('admin_list_payment_intents', 'status', 'expired', 'Expired', 40, true),
  ('admin_list_payment_intents', 'status', 'cancelled', 'Cancelled', 50, true),
  ('admin_list_payments', 'status', '', 'All', 10, true),
  ('admin_list_payments', 'status', 'posted', 'Posted', 20, true),
  ('admin_list_payments', 'status', 'review', 'Review', 30, true),
  ('admin_list_payments', 'status', 'reversed', 'Reversed', 40, true),
  ('admin_list_notifications', 'status', '', 'All', 10, true),
  ('admin_list_notifications', 'status', 'queued', 'Queued', 20, true),
  ('admin_list_notifications', 'status', 'sent', 'Sent', 30, true),
  ('admin_list_notifications', 'status', 'failed', 'Failed', 40, true),
  ('admin_list_notifications', 'status', 'read', 'Read', 50, true),
  ('admin_list_payment_intents', 'sort', 'created_at_desc', 'Newest', 10, true),
  ('admin_list_payment_intents', 'sort', 'created_at_asc', 'Oldest', 20, true),
  ('admin_list_payment_intents', 'sort', 'amount_desc', 'Amount high', 30, true),
  ('admin_list_payment_intents', 'sort', 'amount_asc', 'Amount low', 40, true),
  ('admin_list_payments', 'sort', 'created_at_desc', 'Newest', 10, true),
  ('admin_list_payments', 'sort', 'created_at_asc', 'Oldest', 20, true),
  ('admin_list_payments', 'sort', 'amount_desc', 'Amount high', 30, true),
  ('admin_list_payments', 'sort', 'amount_asc', 'Amount low', 40, true),
  ('admin_list_notifications', 'sort', 'created_at_desc', 'Newest', 10, true),
  ('admin_list_notifications', 'sort', 'created_at_asc', 'Oldest', 20, true);

insert into public.admin_queue_signals
  (rpc_name, signal_kind, icon_key, label, display_order, enabled)
values
  ('admin_list_payment_intents', 'priority', 'payments', 'Intent lifecycle', 10, true),
  ('admin_list_payment_intents', 'workflow', 'compare_arrows', 'Compare matching transaction', 10, true),
  ('admin_list_notifications', 'priority', 'notifications', 'Delivery health', 10, true),
  ('admin_list_notifications', 'workflow', 'replay', 'Retry failures with reason', 10, true)
on conflict (rpc_name, signal_kind, display_order) do update set
  icon_key = excluded.icon_key,
  label = excluded.label,
  enabled = excluded.enabled,
  updated_at = now();

insert into public.admin_queue_sla_policies (queue_key, target, owner, escalation)
values
  ('admin_list_payment_intents', 'Review pending or expired intents within 1 business day', 'Payments support', 'Escalate duplicate or disputed intent same day'),
  ('admin_list_notifications', 'Review failed delivery within 4 business hours', 'Platform operations', 'Escalate invalid-token spikes immediately')
on conflict (queue_key) do update set
  target = excluded.target,
  owner = excluded.owner,
  escalation = excluded.escalation,
  updated_at = now();

create or replace function public.admin_get_queue_sla(p_queue_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized_queue_key text := trim(coalesce(p_queue_key, ''));
  policy_row public.admin_queue_sla_policies%rowtype;
begin
  case normalized_queue_key
    when 'admin_list_payment_events' then perform public.assert_admin_permission('payment_events.read');
    when 'admin_list_allocations' then perform public.assert_admin_permission('payment_events.read');
    when 'admin_list_unallocated' then perform public.assert_admin_permission('payment_events.read');
    when 'admin_list_sms_metadata' then perform public.assert_admin_permission('sms.metadata.read');
    when 'admin_list_collections' then perform public.assert_admin_permission('collections.read');
    when 'admin_list_users' then perform public.assert_admin_permission('users.read');
    when 'admin_list_payment_intents' then perform public.assert_admin_permission('payments.read');
    when 'admin_list_payments' then perform public.assert_admin_permission('payments.read');
    when 'admin_list_receivers' then perform public.assert_admin_permission('receivers.read');
    when 'admin_list_ledger' then perform public.assert_admin_permission('ledger.read');
    when 'admin_list_notifications' then perform public.assert_admin_permission('notifications.read');
    when 'admin_list_audit_logs' then perform public.assert_admin_permission('audit.read');
    when 'admin_list_settings' then perform public.assert_admin_permission('settings.read');
    when 'admin_list_feature_flags' then perform public.assert_admin_permission('feature_flags.read');
    when 'admin_list_admin_users' then perform public.assert_admin_permission('admin_users.read');
    else raise exception 'Unsupported admin queue SLA key: %', normalized_queue_key;
  end case;
  select * into policy_row
  from public.admin_queue_sla_policies
  where queue_key = normalized_queue_key;
  if not found then return '{}'::jsonb; end if;
  return jsonb_build_object(
    'queue_key', policy_row.queue_key,
    'target', policy_row.target,
    'owner', policy_row.owner,
    'escalation', policy_row.escalation,
    'updated_at', policy_row.updated_at
  );
end;
$$;

alter table public.app_realtime_events
  drop constraint if exists app_realtime_events_area_check;
alter table public.app_realtime_events
  add constraint app_realtime_events_area_check check (area in (
    'profiles', 'collections', 'members', 'payment_intents', 'payments',
    'allocations', 'ledger', 'receivers', 'sms_events', 'admin_roles',
    'audit', 'feature_flags', 'settings', 'system_health', 'notifications'
  ));

drop trigger if exists app_realtime_event_trigger on public.notification_events;
create trigger app_realtime_event_trigger
after insert or update or delete on public.notification_events
for each row execute function public.emit_app_realtime_event('notifications');

drop trigger if exists app_realtime_event_trigger on public.notification_deliveries;
create trigger app_realtime_event_trigger
after insert or update or delete on public.notification_deliveries
for each row execute function public.emit_app_realtime_event('notifications');

revoke execute on function public.admin_list_payment_intents(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_payment_intent(uuid) from public, anon;
revoke execute on function public.admin_list_payments(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_list_admin_users(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_admin_user(uuid) from public, anon;
revoke execute on function public.admin_grant_user_role(uuid, text, text) from public, anon;
revoke execute on function public.admin_revoke_user_role(uuid, text, text) from public, anon;
revoke execute on function public.admin_list_notifications(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_notification(uuid) from public, anon;
revoke execute on function public.admin_retry_notification(uuid, text) from public, anon;
revoke execute on function public.admin_system_health(text) from public, anon;
revoke execute on function public.admin_get_queue_sla(text) from public, anon;

grant execute on function public.admin_list_payment_intents(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_payment_intent(uuid) to authenticated;
grant execute on function public.admin_list_payments(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_list_admin_users(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_admin_user(uuid) to authenticated;
grant execute on function public.admin_grant_user_role(uuid, text, text) to authenticated;
grant execute on function public.admin_revoke_user_role(uuid, text, text) to authenticated;
grant execute on function public.admin_list_notifications(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_notification(uuid) to authenticated;
grant execute on function public.admin_retry_notification(uuid, text) to authenticated;
grant execute on function public.admin_system_health(text) to authenticated;
grant execute on function public.admin_get_queue_sla(text) to authenticated;

commit;
