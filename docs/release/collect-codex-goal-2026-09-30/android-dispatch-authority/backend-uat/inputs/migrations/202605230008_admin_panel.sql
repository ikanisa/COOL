create table if not exists admin_roles (
  id uuid primary key default gen_random_uuid(),
  name text unique not null check (name ~ '^[a-z_]+$'),
  description text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists admin_permissions (
  name text primary key check (name ~ '^[a-z_]+(\.[a-z_]+)+$'),
  description text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists admin_role_permissions (
  role_id uuid not null references admin_roles(id) on delete cascade,
  permission_name text not null references admin_permissions(name) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_name)
);

create table if not exists admin_user_roles (
  user_id uuid not null references profiles(id) on delete cascade,
  role_id uuid not null references admin_roles(id) on delete cascade,
  granted_by uuid references profiles(id) on delete set null,
  reason text not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references profiles(id) on delete set null,
  revoke_reason text,
  primary key (user_id, role_id, created_at)
);

create table if not exists admin_sensitive_access_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references profiles(id) on delete restrict,
  entity_type text not null,
  entity_id uuid not null,
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists feature_flags (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  enabled boolean not null default false,
  description text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists system_settings (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  value jsonb not null default '{}'::jsonb,
  description text not null default '',
  is_sensitive boolean not null default false,
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists moderation_flags (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  reason text not null,
  created_by uuid references profiles(id) on delete set null,
  resolved_by uuid references profiles(id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists admin_notes (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  body text not null,
  created_by uuid not null references profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists admin_user_roles_user_active_idx on admin_user_roles (user_id, revoked_at);
create index if not exists admin_sensitive_access_actor_idx on admin_sensitive_access_logs (actor_user_id, created_at desc);
create index if not exists moderation_flags_entity_idx on moderation_flags (entity_type, entity_id, status, created_at desc);
create index if not exists admin_notes_entity_idx on admin_notes (entity_type, entity_id, created_at desc);
create index if not exists audit_logs_action_created_idx on audit_logs (action, created_at desc);
create index if not exists raw_sms_ingested_status_idx on raw_payment_sms (parse_status, ingested_at desc);

alter table admin_roles enable row level security;
alter table admin_permissions enable row level security;
alter table admin_role_permissions enable row level security;
alter table admin_user_roles enable row level security;
alter table admin_sensitive_access_logs enable row level security;
alter table feature_flags enable row level security;
alter table system_settings enable row level security;
alter table moderation_flags enable row level security;
alter table admin_notes enable row level security;

create or replace function mask_phone(value text)
returns text
language sql
immutable
as $$
  select case
    when value is null or length(regexp_replace(value, '\D', '', 'g')) < 6 then null
    else '+***' || right(regexp_replace(value, '\D', '', 'g'), 4)
  end;
$$;

insert into admin_permissions (name, description)
values
  ('overview.read', 'Read admin overview'),
  ('public_requests.read', 'Read public listing requests'),
  ('public_requests.review', 'Approve or reject public listing requests'),
  ('collections.read', 'Read collection operations data'),
  ('collections.moderate', 'Moderate collections'),
  ('users.read', 'Read user operations data'),
  ('receivers.read', 'Read receiver metadata'),
  ('sms.metadata.read', 'Read SMS metadata'),
  ('sms.raw.reveal', 'Reveal raw SMS with reason'),
  ('payment_events.read', 'Read parsed payment events'),
  ('payment_events.reparse', 'Reparse payment events'),
  ('payments.read', 'Read payments'),
  ('payments.allocate', 'Manually allocate payments'),
  ('ledger.read', 'Read immutable ledger'),
  ('audit.read', 'Read audit logs'),
  ('feature_flags.read', 'Read feature flags'),
  ('feature_flags.manage', 'Manage feature flags'),
  ('settings.read', 'Read system settings'),
  ('settings.manage', 'Manage system settings'),
  ('system_health.read', 'Read system health'),
  ('admin_users.read', 'Read admin users and roles'),
  ('admin_users.manage', 'Manage admin roles')
on conflict (name) do update set description = excluded.description;

insert into admin_roles (name, description)
values
  ('platform_owner', 'Full platform administration'),
  ('compliance_admin', 'Audit, privacy, sensitive access, and compliance review'),
  ('operations_admin', 'Collection and operational queue management'),
  ('payments_admin', 'Payment event, allocation, payment, and ledger operations'),
  ('moderation_admin', 'Public approval and moderation operations'),
  ('support_admin', 'Read support-oriented users, collections, receivers, and events'),
  ('read_only_admin', 'Read-only operational visibility')
on conflict (name) do update set description = excluded.description;

insert into admin_role_permissions (role_id, permission_name)
select r.id, p.name
from admin_roles r
cross join admin_permissions p
where r.name = 'platform_owner'
on conflict do nothing;

insert into admin_role_permissions (role_id, permission_name)
select r.id, p.name
from admin_roles r
join admin_permissions p on p.name in (
  'overview.read', 'public_requests.read', 'public_requests.review',
  'collections.read', 'collections.moderate', 'users.read', 'receivers.read',
  'sms.metadata.read', 'payment_events.read', 'payment_events.reparse',
  'payments.read', 'payments.allocate', 'ledger.read', 'audit.read',
  'feature_flags.read', 'settings.read', 'system_health.read'
)
where r.name in ('operations_admin', 'payments_admin', 'moderation_admin', 'support_admin', 'read_only_admin')
on conflict do nothing;

create or replace function is_platform_admin(user_uuid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.is_platform_admin from profiles p where p.id = user_uuid), false)
    or exists (
      select 1
      from admin_user_roles aur
      join admin_roles ar on ar.id = aur.role_id
      where aur.user_id = user_uuid
        and aur.revoked_at is null
        and ar.name = 'platform_owner'
    );
$$;

create or replace function has_admin_permission(permission text, user_uuid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin(user_uuid)
    or exists (
      select 1
      from admin_user_roles aur
      join admin_role_permissions arp on arp.role_id = aur.role_id
      where aur.user_id = user_uuid
        and aur.revoked_at is null
        and arp.permission_name = permission
    );
$$;

create or replace function assert_admin_permission(permission text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_admin_permission(permission, auth.uid()) then
    raise exception 'Admin permission % required', permission;
  end if;
end;
$$;

create or replace function create_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_actor uuid default auth.uid()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  audit_id uuid;
begin
  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (p_actor, p_action, p_entity_type, p_entity_id, coalesce(p_metadata, '{}'::jsonb))
  returning id into audit_id;
  return audit_id;
end;
$$;

create or replace function admin_bootstrap_platform_owner(p_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_role_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Bootstrap reason is required';
  end if;
  select id into owner_role_id from admin_roles where name = 'platform_owner';
  insert into admin_user_roles (user_id, role_id, reason)
  values (p_user_id, owner_role_id, p_reason);
  perform create_audit_log('admin.bootstrap.platform_owner', 'profile', p_user_id, jsonb_build_object('reason', p_reason), p_user_id);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function admin_current_user()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then null
    when not public.has_admin_permission('overview.read', auth.uid()) then null
    else jsonb_build_object(
      'user_id', p.id,
      'display_name', coalesce(nullif(p.display_name, ''), 'Collect admin'),
      'phone_masked', mask_phone(p.whatsapp_phone),
      'roles', coalesce((
        select jsonb_agg(distinct ar.name order by ar.name)
        from admin_user_roles aur
        join admin_roles ar on ar.id = aur.role_id
        where aur.user_id = p.id and aur.revoked_at is null
      ), case when p.is_platform_admin then '["platform_owner"]'::jsonb else '[]'::jsonb end),
      'permissions', coalesce((
        select jsonb_agg(distinct arp.permission_name order by arp.permission_name)
        from admin_user_roles aur
        join admin_role_permissions arp on arp.role_id = aur.role_id
        where aur.user_id = p.id and aur.revoked_at is null
      ), case when p.is_platform_admin then (select jsonb_agg(name order by name) from admin_permissions) else '[]'::jsonb end)
    )
  end
  from profiles p
  where p.id = auth.uid();
$$;

create or replace function _admin_row(
  p_id uuid,
  p_title text,
  p_subtitle text default '',
  p_status text default 'unknown',
  p_amount text default '',
  p_created_at timestamptz default null,
  p_extra jsonb default '{}'::jsonb
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_id,
    'title', coalesce(p_title, 'Record'),
    'subtitle', coalesce(p_subtitle, ''),
    'status', coalesce(p_status, 'unknown'),
    'amount', coalesce(p_amount, ''),
    'created_at', p_created_at
  ) || coalesce(p_extra, '{}'::jsonb);
$$;

create or replace function admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('overview.read');
  return jsonb_build_object(
    'metrics', jsonb_build_array(
      jsonb_build_object('label', 'Pending public requests', 'value', (select count(*) from public_collection_requests where status = 'pending'), 'status', 'pending'),
      jsonb_build_object('label', 'Unallocated events', 'value', (select count(*) from parsed_payment_events where allocation_status in ('unallocated', 'ambiguous', 'needs_review')), 'status', 'needs_review'),
      jsonb_build_object('label', 'Posted payments', 'value', (select count(*) from payments where status = 'posted'), 'status', 'posted'),
      jsonb_build_object('label', 'Ledger credits RWF', 'value', coalesce((select sum(amount_rwf) from ledger_entries), 0), 'status', 'healthy')
    )
  );
end;
$$;

create or replace function admin_list_public_requests(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('public_requests.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(r.id, c.title, coalesce(p.display_name, mask_phone(p.whatsapp_phone), 'Requester'), r.status, '', r.requested_at, jsonb_build_object('collection_id', r.collection_id)) order by r.requested_at desc)
    from public_collection_requests r
    join collections c on c.id = r.collection_id
    left join profiles p on p.id = r.requested_by
    where (p_status is null or r.status = p_status)
      and (p_search is null or c.title ilike '%' || p_search || '%')
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_collections(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('collections.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(c.id, c.title, c.category, c.public_status::text, coalesce(c.target_amount_rwf::text || ' RWF', ''), c.created_at) order by c.created_at desc)
    from collections c
    where (p_status is null or c.public_status::text = p_status)
      and (p_search is null or c.title ilike '%' || p_search || '%')
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_users(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('users.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(p.id, coalesce(p.display_name, 'User #' || p.public_id), mask_phone(p.whatsapp_phone), case when p.is_platform_admin then 'admin' else 'active' end, '', p.created_at) order by p.created_at desc)
    from profiles p
    where (p_search is null or p.display_name ilike '%' || p_search || '%' or p.public_id = p_search)
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_payment_events(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('payment_events.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(e.id, coalesce(e.transaction_id, 'Payment event'), coalesce(e.sender_name, 'Unknown sender'), e.allocation_status::text, coalesce(e.amount_rwf::text || ' RWF', ''), e.created_at, jsonb_build_object('collection_id', e.collection_id)) order by e.created_at desc)
    from parsed_payment_events e
    where (p_status is null or e.allocation_status::text = p_status)
      and (p_search is null or e.transaction_id ilike '%' || p_search || '%')
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_unallocated(p_search text default null, p_status text default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select admin_list_payment_events(p_search, coalesce(p_status, 'needs_review'));
$$;

create or replace function admin_list_payments(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('payments.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(p.id, coalesce(p.transaction_id, 'Payment'), p.source, p.status, p.amount_rwf::text || ' RWF', p.created_at) order by p.created_at desc)
    from payments p
    where (p_status is null or p.status = p_status)
      and (p_search is null or p.transaction_id ilike '%' || p_search || '%')
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_ledger(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('ledger.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(le.id, le.entry_type, le.collection_id::text, le.visibility, le.amount_rwf::text || ' RWF', le.created_at) order by le.created_at desc)
    from ledger_entries le
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_receivers(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('receivers.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(cr.id, cr.label, mask_phone(cr.momo_number), case when cr.is_active then 'active' else 'inactive' end, cr.network, cr.created_at) order by cr.created_at desc)
    from collection_receivers cr
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_sms_metadata(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('sms.metadata.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(s.id, coalesce(mask_phone(s.raw_sender), 'SMS'), s.body_hash, s.parse_status, '', s.ingested_at) order by s.ingested_at desc)
    from raw_payment_sms s
    where (p_status is null or s.parse_status = p_status)
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_audit_logs(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('audit.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(a.id, a.action, a.entity_type, 'logged', '', a.created_at) order by a.created_at desc)
    from audit_logs a
    where (p_search is null or a.action ilike '%' || p_search || '%')
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_feature_flags(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('feature_flags.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(gen_random_uuid(), key, description, case when enabled then 'enabled' else 'disabled' end, '', updated_at) order by key)
    from feature_flags
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_settings(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('settings.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(gen_random_uuid(), key, description, case when is_sensitive then 'sensitive' else 'normal' end, '', updated_at) order by key)
    from system_settings
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_admin_users(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('admin_users.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(p.id, coalesce(p.display_name, 'User #' || p.public_id), ar.name, 'admin', '', aur.created_at) order by aur.created_at desc)
    from admin_user_roles aur
    join profiles p on p.id = aur.user_id
    join admin_roles ar on ar.id = aur.role_id
    where aur.revoked_at is null
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_get_collection(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_admin_permission('collections.read');
  return coalesce((select to_jsonb(c) from collections c where c.id = p_id), '{}'::jsonb);
end;
$$;

create or replace function admin_get_user(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_admin_permission('users.read');
  return coalesce((select to_jsonb(p) - 'whatsapp_phone' - 'momo_number' || jsonb_build_object('whatsapp_phone', mask_phone(p.whatsapp_phone), 'momo_number', mask_phone(p.momo_number)) from profiles p where p.id = p_id), '{}'::jsonb);
end;
$$;

create or replace function admin_get_payment(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_admin_permission('payments.read');
  return coalesce((select to_jsonb(p) from payments p where p.id = p_id), '{}'::jsonb);
end;
$$;

create or replace function admin_get_payment_event(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_admin_permission('payment_events.read');
  return coalesce((select to_jsonb(e) from parsed_payment_events e where e.id = p_id), '{}'::jsonb);
end;
$$;

create or replace function admin_get_receiver(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_admin_permission('receivers.read');
  return coalesce((select to_jsonb(cr) - 'momo_number' || jsonb_build_object('momo_number', mask_phone(cr.momo_number)) from collection_receivers cr where cr.id = p_id), '{}'::jsonb);
end;
$$;

create or replace function admin_get_sms_metadata(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_admin_permission('sms.metadata.read');
  return coalesce((
    select jsonb_build_object(
      'id', s.id,
      'collection_id', s.collection_id,
      'receiver_user_id', s.receiver_user_id,
      'raw_sender_masked', mask_phone(s.raw_sender),
      'body_hash', s.body_hash,
      'masked_body', left(regexp_replace(s.raw_body, '[0-9+]{4,}', '***', 'g'), 240),
      'parse_status', s.parse_status,
      'received_at_device', s.received_at_device,
      'ingested_at', s.ingested_at
    )
    from raw_payment_sms s
    where s.id = p_id
  ), '{}'::jsonb);
end;
$$;

create or replace function admin_system_health(p_id text default 'system')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_admin_permission('system_health.read');
  return jsonb_build_object(
    'database', 'healthy',
    'auth', 'configured',
    'parser_pending_sms', (select count(*) from raw_payment_sms where parse_status = 'pending'),
    'failed_sms_parse', (select count(*) from raw_payment_sms where parse_status = 'failed'),
    'unallocated_events', (select count(*) from parsed_payment_events where allocation_status in ('unallocated', 'ambiguous', 'needs_review')),
    'checked_at', now()
  );
end;
$$;

create or replace function admin_review_public_request(p_request_id uuid, p_approved boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin_permission('public_requests.review');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Reason is required';
  end if;
  perform review_public_collection(p_request_id, p_approved, p_reason);
  return jsonb_build_object('ok', true, 'message', 'Public request reviewed');
end;
$$;

create or replace function admin_moderate_collection(p_collection_id uuid, p_status text, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin_permission('collections.moderate');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Reason is required';
  end if;
  if p_status not in ('private', 'public_rejected', 'archived') then
    raise exception 'Unsupported moderation status';
  end if;
  update collections
    set public_status = p_status::collection_visibility,
        visibility = case when p_status = 'archived' then 'archived'::collection_visibility else 'private'::collection_visibility end,
        archived_at = case when p_status = 'archived' then now() else archived_at end
    where id = p_collection_id;
  perform create_audit_log('collection.moderated', 'collection', p_collection_id, jsonb_build_object('status', p_status, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function admin_manual_allocate_payment(p_event_id uuid, p_collection_id uuid, p_payment_intent_id uuid default null, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  payment_id uuid;
begin
  perform assert_admin_permission('payments.allocate');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Reason is required';
  end if;
  payment_id := manual_allocate_parsed_payment_event(p_event_id, p_collection_id, p_payment_intent_id, p_reason);
  return jsonb_build_object('ok', true, 'message', payment_id::text);
end;
$$;

create or replace function admin_reparse_payment_event(p_event_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin_permission('payment_events.reparse');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Reason is required';
  end if;
  update parsed_payment_events
    set allocation_status = 'needs_review',
        review_reason = 'Reparse requested: ' || p_reason
    where id = p_event_id and allocation_status <> 'allocated';
  perform create_audit_log('payment_event.reparse.requested', 'parsed_payment_event', p_event_id, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'message', 'Reparse queued for review');
end;
$$;

create or replace function admin_reveal_raw_sms(p_sms_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  raw_body text;
begin
  perform assert_admin_permission('sms.raw.reveal');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Reason is required';
  end if;
  select s.raw_body into raw_body from raw_payment_sms s where s.id = p_sms_id;
  if raw_body is null then
    raise exception 'Raw SMS not found';
  end if;
  insert into admin_sensitive_access_logs (actor_user_id, entity_type, entity_id, reason)
  values (auth.uid(), 'raw_payment_sms', p_sms_id, p_reason);
  perform create_audit_log('sms.raw.revealed', 'raw_payment_sms', p_sms_id, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'message', raw_body);
end;
$$;

drop policy if exists "admin roles read admins" on admin_roles;
create policy "admin roles read admins" on admin_roles for select to authenticated using (has_admin_permission('admin_users.read'));
drop policy if exists "admin permissions read admins" on admin_permissions;
create policy "admin permissions read admins" on admin_permissions for select to authenticated using (has_admin_permission('admin_users.read'));
drop policy if exists "admin role permissions read admins" on admin_role_permissions;
create policy "admin role permissions read admins" on admin_role_permissions for select to authenticated using (has_admin_permission('admin_users.read'));
drop policy if exists "admin user roles read admins" on admin_user_roles;
create policy "admin user roles read admins" on admin_user_roles for select to authenticated using (has_admin_permission('admin_users.read') or user_id = auth.uid());
drop policy if exists "sensitive access logs read compliance" on admin_sensitive_access_logs;
create policy "sensitive access logs read compliance" on admin_sensitive_access_logs for select to authenticated using (has_admin_permission('audit.read'));
drop policy if exists "feature flags read admins" on feature_flags;
create policy "feature flags read admins" on feature_flags for select to authenticated using (has_admin_permission('feature_flags.read'));
drop policy if exists "system settings read admins" on system_settings;
create policy "system settings read admins" on system_settings for select to authenticated using (has_admin_permission('settings.read'));
drop policy if exists "moderation flags read admins" on moderation_flags;
create policy "moderation flags read admins" on moderation_flags for select to authenticated using (has_admin_permission('collections.moderate'));
drop policy if exists "admin notes read admins" on admin_notes;
create policy "admin notes read admins" on admin_notes for select to authenticated using (has_admin_permission('collections.read') or has_admin_permission('users.read'));

drop policy if exists "raw sms receiver own read" on raw_payment_sms;
drop policy if exists "raw sms metadata scoped read" on raw_payment_sms;
create policy "raw sms metadata scoped read" on raw_payment_sms
for select to authenticated
using (
  receiver_user_id = auth.uid()
  or has_admin_permission('sms.metadata.read')
);

revoke all on raw_payment_sms from anon, authenticated;
grant select (
  id,
  collection_id,
  receiver_user_id,
  raw_sender,
  body_hash,
  receiver_momo_number_hash,
  received_at_device,
  ingested_at,
  parse_status,
  created_at
) on raw_payment_sms to authenticated;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
grant execute on function public.current_user_is_platform_admin() to anon, authenticated;
grant execute on function public.user_is_collection_admin(uuid, uuid) to anon, authenticated;
grant execute on function public.user_can_read_collection(uuid, uuid) to anon, authenticated;
grant execute on function public.user_can_ingest_receiver_sms(text, uuid, uuid) to authenticated;
grant execute on function get_current_profile() to authenticated;
grant execute on function create_collection_with_owner(text, text, text, bigint, text, text, text, text, boolean, jsonb) to authenticated;
grant execute on function create_collection_invite(uuid, text, text, member_role) to authenticated;
grant execute on function create_payment_intent(uuid, bigint, text, text) to authenticated;
grant execute on function create_payment_intent_with_instructions(uuid, bigint, text, text) to authenticated;
grant execute on function report_payment_intent_paid(uuid, text) to authenticated;
grant execute on function request_public_collection(uuid) to authenticated;
grant execute on function review_public_collection(uuid, boolean, text) to authenticated;
grant execute on function manual_allocate_parsed_payment_event(uuid, uuid, uuid, text) to authenticated;
grant execute on function is_platform_admin(uuid) to authenticated;
grant execute on function has_admin_permission(text, uuid) to authenticated;
grant execute on function admin_current_user() to authenticated;
grant execute on function admin_overview() to authenticated;
grant execute on function admin_list_public_requests(text, text) to authenticated;
grant execute on function admin_list_collections(text, text) to authenticated;
grant execute on function admin_list_users(text, text) to authenticated;
grant execute on function admin_list_payment_events(text, text) to authenticated;
grant execute on function admin_list_unallocated(text, text) to authenticated;
grant execute on function admin_list_payments(text, text) to authenticated;
grant execute on function admin_list_ledger(text, text) to authenticated;
grant execute on function admin_list_receivers(text, text) to authenticated;
grant execute on function admin_list_sms_metadata(text, text) to authenticated;
grant execute on function admin_list_audit_logs(text, text) to authenticated;
grant execute on function admin_list_feature_flags(text, text) to authenticated;
grant execute on function admin_list_settings(text, text) to authenticated;
grant execute on function admin_list_admin_users(text, text) to authenticated;
grant execute on function admin_get_collection(uuid) to authenticated;
grant execute on function admin_get_user(uuid) to authenticated;
grant execute on function admin_get_payment(uuid) to authenticated;
grant execute on function admin_get_payment_event(uuid) to authenticated;
grant execute on function admin_get_receiver(uuid) to authenticated;
grant execute on function admin_get_sms_metadata(uuid) to authenticated;
grant execute on function admin_system_health(text) to authenticated;
grant execute on function admin_review_public_request(uuid, boolean, text) to authenticated;
grant execute on function admin_moderate_collection(uuid, text, text) to authenticated;
grant execute on function admin_manual_allocate_payment(uuid, uuid, uuid, text) to authenticated;
grant execute on function admin_reparse_payment_event(uuid, text) to authenticated;
grant execute on function admin_reveal_raw_sms(uuid, text) to authenticated;
