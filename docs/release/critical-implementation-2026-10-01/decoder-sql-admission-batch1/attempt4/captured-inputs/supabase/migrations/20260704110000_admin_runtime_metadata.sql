begin;

create table if not exists admin_navigation_items (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  label text not null,
  icon_key text not null check (icon_key ~ '^[a-z0-9_]+$'),
  route_path text not null unique check (route_path ~ '^/admin'),
  required_permission text not null references admin_permissions(name) on delete restrict,
  display_order integer not null default 100,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists admin_queue_specs (
  rpc_name text primary key check (rpc_name ~ '^admin_list_[a-z0-9_]+$'),
  title text not null,
  subtitle text not null,
  required_permission text not null references admin_permissions(name) on delete restrict,
  display_order integer not null default 100,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists admin_queue_filter_options (
  id uuid primary key default gen_random_uuid(),
  rpc_name text not null references admin_queue_specs(rpc_name) on delete cascade,
  filter_kind text not null check (filter_kind in ('status', 'sort')),
  value text not null,
  label text not null,
  display_order integer not null default 100,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  unique (rpc_name, filter_kind, value)
);

create table if not exists admin_queue_signals (
  id uuid primary key default gen_random_uuid(),
  rpc_name text not null references admin_queue_specs(rpc_name) on delete cascade,
  signal_kind text not null check (signal_kind in ('priority', 'workflow')),
  icon_key text not null check (icon_key ~ '^[a-z0-9_]+$'),
  label text not null,
  display_order integer not null default 100,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  unique (rpc_name, signal_kind, display_order)
);

create index if not exists admin_navigation_items_enabled_order_idx
  on admin_navigation_items (enabled, display_order, key);

create index if not exists admin_queue_specs_enabled_order_idx
  on admin_queue_specs (enabled, display_order, rpc_name);

create index if not exists admin_queue_filter_options_lookup_idx
  on admin_queue_filter_options (rpc_name, filter_kind, enabled, display_order);

create index if not exists admin_queue_signals_lookup_idx
  on admin_queue_signals (rpc_name, signal_kind, enabled, display_order);

alter table admin_navigation_items enable row level security;
alter table admin_queue_specs enable row level security;
alter table admin_queue_filter_options enable row level security;
alter table admin_queue_signals enable row level security;

drop policy if exists "admin navigation read admins" on admin_navigation_items;
create policy "admin navigation read admins"
on admin_navigation_items for select to authenticated
using (public.has_admin_permission('settings.read', (select auth.uid())));

drop policy if exists "admin navigation manage admins" on admin_navigation_items;
create policy "admin navigation manage admins"
on admin_navigation_items for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "admin queue specs read admins" on admin_queue_specs;
create policy "admin queue specs read admins"
on admin_queue_specs for select to authenticated
using (public.has_admin_permission('settings.read', (select auth.uid())));

drop policy if exists "admin queue specs manage admins" on admin_queue_specs;
create policy "admin queue specs manage admins"
on admin_queue_specs for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "admin queue filter options read admins" on admin_queue_filter_options;
create policy "admin queue filter options read admins"
on admin_queue_filter_options for select to authenticated
using (public.has_admin_permission('settings.read', (select auth.uid())));

drop policy if exists "admin queue filter options manage admins" on admin_queue_filter_options;
create policy "admin queue filter options manage admins"
on admin_queue_filter_options for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "admin queue signals read admins" on admin_queue_signals;
create policy "admin queue signals read admins"
on admin_queue_signals for select to authenticated
using (public.has_admin_permission('settings.read', (select auth.uid())));

drop policy if exists "admin queue signals manage admins" on admin_queue_signals;
create policy "admin queue signals manage admins"
on admin_queue_signals for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

create or replace function admin_runtime_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.uid() is null then jsonb_build_object('navigation_items', '[]'::jsonb, 'queue_specs', '[]'::jsonb)
    else jsonb_build_object(
      'navigation_items', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'key', n.key,
            'label', n.label,
            'icon_key', n.icon_key,
            'route_path', n.route_path,
            'required_permission', n.required_permission,
            'display_order', n.display_order
          )
          order by n.display_order, n.key
        )
        from admin_navigation_items n
        where n.enabled
          and public.has_admin_permission(n.required_permission, auth.uid())
      ), '[]'::jsonb),
      'queue_specs', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'rpc_name', q.rpc_name,
            'title', q.title,
            'subtitle', q.subtitle,
            'required_permission', q.required_permission,
            'status_options', coalesce((
              select jsonb_agg(
                jsonb_build_object('value', f.value, 'label', f.label)
                order by f.display_order, f.value
              )
              from admin_queue_filter_options f
              where f.rpc_name = q.rpc_name
                and f.filter_kind = 'status'
                and f.enabled
            ), '[]'::jsonb),
            'sort_options', coalesce((
              select jsonb_agg(
                jsonb_build_object('value', f.value, 'label', f.label)
                order by f.display_order, f.value
              )
              from admin_queue_filter_options f
              where f.rpc_name = q.rpc_name
                and f.filter_kind = 'sort'
                and f.enabled
            ), '[]'::jsonb),
            'priority_signals', coalesce((
              select jsonb_agg(
                jsonb_build_object('icon_key', s.icon_key, 'label', s.label)
                order by s.display_order, s.label
              )
              from admin_queue_signals s
              where s.rpc_name = q.rpc_name
                and s.signal_kind = 'priority'
                and s.enabled
            ), '[]'::jsonb),
            'workflow_steps', coalesce((
              select jsonb_agg(
                jsonb_build_object('icon_key', s.icon_key, 'label', s.label)
                order by s.display_order, s.label
              )
              from admin_queue_signals s
              where s.rpc_name = q.rpc_name
                and s.signal_kind = 'workflow'
                and s.enabled
            ), '[]'::jsonb)
          )
          order by q.display_order, q.rpc_name
        )
        from admin_queue_specs q
        where q.enabled
          and public.has_admin_permission(q.required_permission, auth.uid())
      ), '[]'::jsonb)
    )
  end;
$$;

revoke execute on function admin_runtime_config() from public, anon;
grant execute on function admin_runtime_config() to authenticated;

create or replace function audit_admin_runtime_metadata_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata_key text;
begin
  metadata_key := case
    when tg_op = 'DELETE' then coalesce(
      to_jsonb(old)->>'key',
      to_jsonb(old)->>'rpc_name',
      to_jsonb(old)->>'id'
    )
    else coalesce(
      to_jsonb(new)->>'key',
      to_jsonb(new)->>'rpc_name',
      to_jsonb(new)->>'id'
    )
  end;

  if auth.uid() is not null then
    perform create_audit_log(
      'admin_runtime_metadata.' || lower(tg_op),
      tg_table_name,
      null,
      jsonb_build_object('key', metadata_key)
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function audit_admin_runtime_metadata_change() from public, anon, authenticated;
grant execute on function audit_admin_runtime_metadata_change() to service_role;

drop trigger if exists audit_admin_runtime_metadata_change_trigger on admin_navigation_items;
create trigger audit_admin_runtime_metadata_change_trigger
after insert or update or delete on admin_navigation_items
for each row execute function audit_admin_runtime_metadata_change();

drop trigger if exists audit_admin_runtime_metadata_change_trigger on admin_queue_specs;
create trigger audit_admin_runtime_metadata_change_trigger
after insert or update or delete on admin_queue_specs
for each row execute function audit_admin_runtime_metadata_change();

drop trigger if exists audit_admin_runtime_metadata_change_trigger on admin_queue_filter_options;
create trigger audit_admin_runtime_metadata_change_trigger
after insert or update or delete on admin_queue_filter_options
for each row execute function audit_admin_runtime_metadata_change();

drop trigger if exists audit_admin_runtime_metadata_change_trigger on admin_queue_signals;
create trigger audit_admin_runtime_metadata_change_trigger
after insert or update or delete on admin_queue_signals
for each row execute function audit_admin_runtime_metadata_change();

drop trigger if exists app_realtime_event_trigger on admin_navigation_items;
create trigger app_realtime_event_trigger
after insert or update or delete on admin_navigation_items
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on admin_queue_specs;
create trigger app_realtime_event_trigger
after insert or update or delete on admin_queue_specs
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on admin_queue_filter_options;
create trigger app_realtime_event_trigger
after insert or update or delete on admin_queue_filter_options
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on admin_queue_signals;
create trigger app_realtime_event_trigger
after insert or update or delete on admin_queue_signals
for each row execute function emit_app_realtime_event('settings');

revoke all on admin_navigation_items from anon, authenticated;
revoke all on admin_queue_specs from anon, authenticated;
revoke all on admin_queue_filter_options from anon, authenticated;
revoke all on admin_queue_signals from anon, authenticated;
grant select, insert, update, delete on admin_navigation_items to authenticated;
grant select, insert, update, delete on admin_queue_specs to authenticated;
grant select, insert, update, delete on admin_queue_filter_options to authenticated;
grant select, insert, update, delete on admin_queue_signals to authenticated;

insert into admin_navigation_items (key, label, icon_key, route_path, required_permission, display_order, enabled)
values
  ('overview', 'Overview', 'dashboard', '/admin', 'overview.read', 10, true),
  ('groups', 'Groups', 'groups', '/admin/groups', 'collections.read', 20, true),
  ('members', 'Members', 'members', '/admin/members', 'users.read', 30, true),
  ('payment_intents', 'Payment intents', 'payments', '/admin/payment-intents', 'payments.read', 40, true),
  ('sms_parsing', 'SMS parsing', 'sms_parsing', '/admin/payment-events', 'payment_events.read', 50, true),
  ('allocations', 'Allocations', 'allocations', '/admin/allocations', 'payment_events.read', 60, true),
  ('exceptions', 'Exceptions', 'exceptions', '/admin/exceptions', 'payment_events.read', 70, true),
  ('ledger', 'Ledger', 'ledger', '/admin/ledger', 'ledger.read', 80, true),
  ('receivers', 'Receivers', 'receivers', '/admin/receivers', 'receivers.read', 90, true),
  ('sms', 'SMS', 'sms', '/admin/sms', 'sms.metadata.read', 100, true),
  ('audit_logs', 'Audit logs', 'audit', '/admin/audit-logs', 'audit.read', 110, true),
  ('settings', 'Settings', 'settings', '/admin/settings', 'settings.read', 120, true),
  ('feature_flags', 'Feature flags', 'feature_flags', '/admin/feature-flags', 'feature_flags.read', 130, true),
  ('system_health', 'System health', 'system_health', '/admin/system-health', 'system_health.read', 140, true),
  ('admin_users', 'Admin users', 'admin_users', '/admin/admin-users', 'admin_users.read', 150, true)
on conflict (key) do update
set label = excluded.label,
    icon_key = excluded.icon_key,
    route_path = excluded.route_path,
    required_permission = excluded.required_permission,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into admin_queue_specs (rpc_name, title, subtitle, required_permission, display_order, enabled)
values
  ('admin_list_collections', 'Groups', 'Support group operations.', 'collections.read', 10, true),
  ('admin_list_users', 'Members', 'Support member accounts.', 'users.read', 20, true),
  ('admin_list_payments', 'Payment intents', 'Review MoMo intent states.', 'payments.read', 30, true),
  ('admin_list_payment_events', 'SMS parsing', 'Triage MoMo SMS events.', 'payment_events.read', 40, true),
  ('admin_list_allocations', 'Allocations', 'Review matched payments.', 'payment_events.read', 50, true),
  ('admin_list_unallocated', 'Exceptions', 'Resolve open MoMo events.', 'payment_events.read', 60, true),
  ('admin_list_ledger', 'Ledger', 'Review posted contribution records.', 'ledger.read', 70, true),
  ('admin_list_receivers', 'Receivers', 'Review MoMo receiver routes.', 'receivers.read', 80, true),
  ('admin_list_sms_metadata', 'SMS metadata', 'Review SMS metadata.', 'sms.metadata.read', 90, true),
  ('admin_list_audit_logs', 'Audit logs', 'Review operator and system actions.', 'audit.read', 100, true),
  ('admin_list_settings', 'Settings', 'Review platform configuration.', 'settings.read', 110, true),
  ('admin_list_feature_flags', 'Feature flags', 'Review feature rollout controls.', 'feature_flags.read', 120, true),
  ('admin_list_admin_users', 'Admin users', 'Review operator access.', 'admin_users.read', 130, true)
on conflict (rpc_name) do update
set title = excluded.title,
    subtitle = excluded.subtitle,
    required_permission = excluded.required_permission,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into admin_queue_filter_options (rpc_name, filter_kind, value, label, display_order, enabled)
values
  ('admin_list_collections', 'status', '', 'All', 10, true),
  ('admin_list_collections', 'status', 'pending', 'Pending', 20, true),
  ('admin_list_collections', 'status', 'active', 'Active', 30, true),
  ('admin_list_collections', 'status', 'needs_review', 'Review', 40, true),
  ('admin_list_users', 'status', '', 'All', 10, true),
  ('admin_list_users', 'status', 'pending', 'Pending', 20, true),
  ('admin_list_users', 'status', 'active', 'Active', 30, true),
  ('admin_list_users', 'status', 'needs_review', 'Review', 40, true),
  ('admin_list_payments', 'status', '', 'All', 10, true),
  ('admin_list_payments', 'status', 'pending', 'Pending', 20, true),
  ('admin_list_payments', 'status', 'confirmed', 'Confirmed', 30, true),
  ('admin_list_payments', 'status', 'needs_review', 'Review', 40, true),
  ('admin_list_payments', 'status', 'expired', 'Expired', 50, true),
  ('admin_list_payment_events', 'status', '', 'All', 10, true),
  ('admin_list_payment_events', 'status', 'needs_review', 'Review', 20, true),
  ('admin_list_payment_events', 'status', 'unallocated', 'Unallocated', 30, true),
  ('admin_list_payment_events', 'status', 'ambiguous', 'Ambiguous', 40, true),
  ('admin_list_payment_events', 'status', 'allocated', 'Allocated', 50, true),
  ('admin_list_allocations', 'status', '', 'All', 10, true),
  ('admin_list_allocations', 'status', 'allocated', 'Allocated', 20, true),
  ('admin_list_allocations', 'status', 'needs_review', 'Review', 30, true),
  ('admin_list_unallocated', 'status', '', 'Open', 10, true),
  ('admin_list_unallocated', 'status', 'needs_review', 'Review', 20, true),
  ('admin_list_unallocated', 'status', 'unallocated', 'Unallocated', 30, true),
  ('admin_list_unallocated', 'status', 'ambiguous', 'Ambiguous', 40, true),
  ('admin_list_ledger', 'status', '', 'All', 10, true),
  ('admin_list_ledger', 'status', 'confirmed', 'Confirmed', 20, true),
  ('admin_list_ledger', 'status', 'pending', 'Pending', 30, true),
  ('admin_list_ledger', 'status', 'needs_review', 'Review', 40, true),
  ('admin_list_receivers', 'status', '', 'All', 10, true),
  ('admin_list_receivers', 'status', 'pending', 'Pending', 20, true),
  ('admin_list_receivers', 'status', 'active', 'Active', 30, true),
  ('admin_list_receivers', 'status', 'needs_review', 'Review', 40, true),
  ('admin_list_sms_metadata', 'status', '', 'All', 10, true),
  ('admin_list_sms_metadata', 'status', 'needs_review', 'Review', 20, true),
  ('admin_list_sms_metadata', 'status', 'parsed', 'Parsed', 30, true),
  ('admin_list_sms_metadata', 'status', 'failed', 'Failed', 40, true),
  ('admin_list_audit_logs', 'status', '', 'All', 10, true),
  ('admin_list_audit_logs', 'status', 'logged', 'Logged', 20, true),
  ('admin_list_audit_logs', 'status', 'sensitive', 'Sensitive', 30, true),
  ('admin_list_settings', 'status', '', 'All', 10, true),
  ('admin_list_settings', 'status', 'enabled', 'Enabled', 20, true),
  ('admin_list_settings', 'status', 'disabled', 'Disabled', 30, true),
  ('admin_list_feature_flags', 'status', '', 'All', 10, true),
  ('admin_list_feature_flags', 'status', 'enabled', 'Enabled', 20, true),
  ('admin_list_feature_flags', 'status', 'disabled', 'Disabled', 30, true),
  ('admin_list_admin_users', 'status', '', 'All', 10, true),
  ('admin_list_admin_users', 'status', 'admin', 'Admin', 20, true),
  ('admin_list_admin_users', 'status', 'active', 'Active', 30, true),
  ('admin_list_admin_users', 'status', 'revoked', 'Revoked', 40, true)
on conflict (rpc_name, filter_kind, value) do update
set label = excluded.label,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into admin_queue_filter_options (rpc_name, filter_kind, value, label, display_order, enabled)
select rpc_name, 'sort', 'created_at_desc', 'Newest', 10, true from admin_queue_specs
on conflict (rpc_name, filter_kind, value) do update set label = excluded.label, display_order = excluded.display_order, enabled = excluded.enabled, updated_at = now();

insert into admin_queue_filter_options (rpc_name, filter_kind, value, label, display_order, enabled)
select rpc_name, 'sort', 'created_at_asc', 'Oldest', 20, true from admin_queue_specs
on conflict (rpc_name, filter_kind, value) do update set label = excluded.label, display_order = excluded.display_order, enabled = excluded.enabled, updated_at = now();

insert into admin_queue_filter_options (rpc_name, filter_kind, value, label, display_order, enabled)
values
  ('admin_list_payment_events', 'sort', 'amount_desc', 'Amount high', 30, true),
  ('admin_list_payment_events', 'sort', 'amount_asc', 'Amount low', 40, true),
  ('admin_list_unallocated', 'sort', 'amount_desc', 'Amount high', 30, true),
  ('admin_list_unallocated', 'sort', 'amount_asc', 'Amount low', 40, true),
  ('admin_list_payments', 'sort', 'amount_desc', 'Amount high', 30, true),
  ('admin_list_payments', 'sort', 'amount_asc', 'Amount low', 40, true)
on conflict (rpc_name, filter_kind, value) do update
set label = excluded.label,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into admin_queue_signals (rpc_name, signal_kind, icon_key, label, display_order, enabled)
values
  ('admin_list_collections', 'priority', 'folder_copy', 'Group profile', 10, true),
  ('admin_list_collections', 'workflow', 'open_in_new', 'Open group detail', 10, true),
  ('admin_list_users', 'priority', 'badge', 'Collect ID first', 10, true),
  ('admin_list_users', 'workflow', 'open_in_new', 'Open member detail', 10, true),
  ('admin_list_payments', 'priority', 'payments', 'Intent status', 10, true),
  ('admin_list_payments', 'workflow', 'compare_arrows', 'Compare events', 10, true),
  ('admin_list_payment_events', 'priority', 'rule', 'Ambiguous matches', 10, true),
  ('admin_list_payment_events', 'workflow', 'replay', 'Request reparse with reason', 10, true),
  ('admin_list_allocations', 'priority', 'account_tree', 'Matched events', 10, true),
  ('admin_list_allocations', 'workflow', 'history', 'Review audit trail', 10, true),
  ('admin_list_unallocated', 'priority', 'priority_high', 'Open exceptions', 10, true),
  ('admin_list_unallocated', 'workflow', 'rule_folder', 'Classify exception', 10, true),
  ('admin_list_ledger', 'priority', 'account_balance', 'Ledger-safe view', 10, true),
  ('admin_list_ledger', 'workflow', 'receipt_long', 'Compare source intent', 10, true),
  ('admin_list_receivers', 'priority', 'settings_phone', 'Receiver route', 10, true),
  ('admin_list_receivers', 'workflow', 'fact_check', 'Check owner setup', 10, true),
  ('admin_list_sms_metadata', 'priority', 'sms', 'Metadata only', 10, true),
  ('admin_list_sms_metadata', 'workflow', 'security', 'Gate raw reveal', 10, true),
  ('admin_list_audit_logs', 'priority', 'policy', 'Audit trail', 10, true),
  ('admin_list_audit_logs', 'workflow', 'search', 'Search action', 10, true),
  ('admin_list_settings', 'priority', 'tune', 'Configuration', 10, true),
  ('admin_list_settings', 'workflow', 'fact_check', 'Confirm owner approval', 10, true),
  ('admin_list_feature_flags', 'priority', 'flag', 'Rollout control', 10, true),
  ('admin_list_feature_flags', 'workflow', 'rule', 'Check rollout condition', 10, true),
  ('admin_list_admin_users', 'priority', 'admin_panel_settings', 'Role scope', 10, true),
  ('admin_list_admin_users', 'workflow', 'person_search', 'Review identity', 10, true)
on conflict (rpc_name, signal_kind, display_order) do update
set icon_key = excluded.icon_key,
    label = excluded.label,
    enabled = excluded.enabled,
    updated_at = now();

commit;
