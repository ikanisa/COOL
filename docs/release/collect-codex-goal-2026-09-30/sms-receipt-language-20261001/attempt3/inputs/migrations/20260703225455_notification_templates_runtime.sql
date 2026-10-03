begin;

create table if not exists notification_channels (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  label text not null,
  description text not null,
  platform text not null default 'all' check (platform in ('all', 'android', 'ios', 'web')),
  enabled boolean not null default true,
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists notification_event_types (
  key text primary key check (key in (
    'contribution_confirmed',
    'payment_reminder',
    'group_update',
    'security_notice'
  )),
  preference_key text not null check (preference_key in (
    'contribution_confirmations',
    'payment_reminders',
    'group_updates',
    'security_notices'
  )),
  label text not null,
  description text not null,
  default_channel_key text not null references notification_channels(key) on delete restrict,
  enabled boolean not null default true,
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists notification_templates (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  event_type_key text not null references notification_event_types(key) on delete restrict,
  locale text not null default 'en' check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists notification_template_versions (
  id uuid primary key default gen_random_uuid(),
  template_key text not null references notification_templates(key) on delete cascade,
  version text not null check (version ~ '^[a-zA-Z0-9_.:-]+$'),
  title_template text not null,
  body_template text not null,
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  effective_at timestamptz not null default now(),
  published_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  unique (template_key, version)
);

create index if not exists notification_channels_enabled_order_idx
  on notification_channels (enabled, display_order, key);

create index if not exists notification_event_types_enabled_order_idx
  on notification_event_types (enabled, display_order, key);

create index if not exists notification_templates_lookup_idx
  on notification_templates (event_type_key, locale, enabled, key);

create index if not exists notification_template_versions_active_idx
  on notification_template_versions (template_key, status, effective_at desc, version);

alter table notification_channels enable row level security;
alter table notification_event_types enable row level security;
alter table notification_templates enable row level security;
alter table notification_template_versions enable row level security;

drop policy if exists "notification channels public enabled read" on notification_channels;
create policy "notification channels public enabled read"
on notification_channels for select to anon, authenticated
using (enabled);

drop policy if exists "notification channels admin manage" on notification_channels;
create policy "notification channels admin manage"
on notification_channels for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "notification event types public enabled read" on notification_event_types;
create policy "notification event types public enabled read"
on notification_event_types for select to anon, authenticated
using (enabled);

drop policy if exists "notification event types admin manage" on notification_event_types;
create policy "notification event types admin manage"
on notification_event_types for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "notification templates public enabled read" on notification_templates;
create policy "notification templates public enabled read"
on notification_templates for select to anon, authenticated
using (
  enabled
  and exists (
    select 1
    from notification_event_types net
    where net.key = notification_templates.event_type_key
      and net.enabled
  )
);

drop policy if exists "notification templates admin manage" on notification_templates;
create policy "notification templates admin manage"
on notification_templates for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "notification template versions public published read" on notification_template_versions;
create policy "notification template versions public published read"
on notification_template_versions for select to anon, authenticated
using (
  status = 'published'
  and effective_at <= now()
  and exists (
    select 1
    from notification_templates nt
    join notification_event_types net on net.key = nt.event_type_key
    where nt.key = notification_template_versions.template_key
      and nt.enabled
      and net.enabled
  )
);

drop policy if exists "notification template versions admin manage" on notification_template_versions;
create policy "notification template versions admin manage"
on notification_template_versions for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

create or replace function render_notification_template(
  p_template text,
  p_context jsonb default '{}'::jsonb
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  rendered text := coalesce(p_template, '');
  context_entry record;
begin
  for context_entry in
    select key, value
    from jsonb_each_text(coalesce(p_context, '{}'::jsonb))
  loop
    rendered := replace(rendered, '{{' || context_entry.key || '}}', context_entry.value);
  end loop;
  return rendered;
end;
$$;

create or replace function get_notification_runtime_config(p_locale text default 'en')
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'locale', coalesce(nullif(trim(p_locale), ''), 'en'),
    'channels', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'key', nc.key,
          'label', nc.label,
          'description', nc.description,
          'platform', nc.platform,
          'display_order', nc.display_order
        )
        order by nc.display_order, nc.key
      )
      from notification_channels nc
      where nc.enabled
    ), '[]'::jsonb),
    'event_types', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'key', net.key,
          'preference_key', net.preference_key,
          'label', net.label,
          'description', net.description,
          'default_channel_key', net.default_channel_key,
          'display_order', net.display_order
        )
        order by net.display_order, net.key
      )
      from notification_event_types net
      where net.enabled
    ), '[]'::jsonb)
  );
$$;

create or replace function enqueue_notification_template_event(
  p_user_id uuid,
  p_template_key text,
  p_context jsonb default '{}'::jsonb,
  p_collection_id uuid default null,
  p_deep_link text default null,
  p_locale text default 'en'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  template_row record;
  inserted_id uuid;
  preference_enabled boolean := true;
begin
  select
    nt.key,
    net.key as event_type,
    net.preference_key,
    ntv.title_template,
    ntv.body_template
  into template_row
  from notification_templates nt
  join notification_event_types net on net.key = nt.event_type_key
  join notification_template_versions ntv on ntv.template_key = nt.key
  where nt.key = trim(p_template_key)
    and nt.locale in (coalesce(nullif(trim(p_locale), ''), 'en'), 'en')
    and nt.enabled
    and net.enabled
    and ntv.status = 'published'
    and ntv.effective_at <= now()
  order by
    case when nt.locale = coalesce(nullif(trim(p_locale), ''), 'en') then 0 else 1 end,
    ntv.effective_at desc,
    ntv.version desc
  limit 1;

  if template_row.key is null then
    raise exception 'notification_template_not_found';
  end if;

  select case template_row.preference_key
    when 'contribution_confirmations' then coalesce(contribution_confirmations, true)
    when 'payment_reminders' then coalesce(payment_reminders, true)
    when 'group_updates' then coalesce(group_updates, true)
    when 'security_notices' then coalesce(security_notices, true)
    else true
  end
  into preference_enabled
  from notification_preferences
  where user_id = p_user_id;

  if coalesce(preference_enabled, true) is false then
    return null;
  end if;

  insert into notification_events (
    user_id,
    collection_id,
    type,
    title,
    body,
    deep_link
  )
  values (
    p_user_id,
    p_collection_id,
    template_row.event_type,
    render_notification_template(template_row.title_template, p_context),
    render_notification_template(template_row.body_template, p_context),
    p_deep_link
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;

revoke execute on function render_notification_template(text, jsonb) from public, anon, authenticated;
revoke execute on function get_notification_runtime_config(text) from public, anon, authenticated;
revoke execute on function enqueue_notification_template_event(uuid, text, jsonb, uuid, text, text) from public, anon, authenticated;
grant execute on function get_notification_runtime_config(text) to anon, authenticated;
grant execute on function render_notification_template(text, jsonb) to service_role;
grant execute on function enqueue_notification_template_event(uuid, text, jsonb, uuid, text, text) to service_role;

create or replace function audit_notification_runtime_change()
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
      to_jsonb(old)->>'template_key',
      to_jsonb(old)->>'id'
    )
    else coalesce(
      to_jsonb(new)->>'key',
      to_jsonb(new)->>'template_key',
      to_jsonb(new)->>'id'
    )
  end;

  if auth.uid() is not null then
    perform create_audit_log(
      'notification_runtime.' || lower(tg_op),
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

revoke execute on function audit_notification_runtime_change() from public, anon, authenticated;
grant execute on function audit_notification_runtime_change() to service_role;

drop trigger if exists audit_notification_runtime_change_trigger on notification_channels;
create trigger audit_notification_runtime_change_trigger
after insert or update or delete on notification_channels
for each row execute function audit_notification_runtime_change();

drop trigger if exists audit_notification_runtime_change_trigger on notification_event_types;
create trigger audit_notification_runtime_change_trigger
after insert or update or delete on notification_event_types
for each row execute function audit_notification_runtime_change();

drop trigger if exists audit_notification_runtime_change_trigger on notification_templates;
create trigger audit_notification_runtime_change_trigger
after insert or update or delete on notification_templates
for each row execute function audit_notification_runtime_change();

drop trigger if exists audit_notification_runtime_change_trigger on notification_template_versions;
create trigger audit_notification_runtime_change_trigger
after insert or update or delete on notification_template_versions
for each row execute function audit_notification_runtime_change();

drop trigger if exists app_realtime_event_trigger on notification_channels;
create trigger app_realtime_event_trigger
after insert or update or delete on notification_channels
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on notification_event_types;
create trigger app_realtime_event_trigger
after insert or update or delete on notification_event_types
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on notification_templates;
create trigger app_realtime_event_trigger
after insert or update or delete on notification_templates
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on notification_template_versions;
create trigger app_realtime_event_trigger
after insert or update or delete on notification_template_versions
for each row execute function emit_app_realtime_event('settings');

revoke all on notification_channels from anon, authenticated;
revoke all on notification_event_types from anon, authenticated;
revoke all on notification_templates from anon, authenticated;
revoke all on notification_template_versions from anon, authenticated;
grant select on notification_channels to anon, authenticated;
grant select on notification_event_types to anon, authenticated;
grant select on notification_templates to anon, authenticated;
grant select on notification_template_versions to anon, authenticated;
grant insert, update, delete on notification_channels to authenticated;
grant insert, update, delete on notification_event_types to authenticated;
grant insert, update, delete on notification_templates to authenticated;
grant insert, update, delete on notification_template_versions to authenticated;

insert into notification_channels (key, label, description, platform, display_order, enabled)
values
  (
    'collect_group_updates',
    'Collect group updates',
    'Contribution confirmations, payment reminders, group updates, and security notices.',
    'all',
    10,
    true
  )
on conflict (key) do update
set label = excluded.label,
    description = excluded.description,
    platform = excluded.platform,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into notification_event_types (
  key,
  preference_key,
  label,
  description,
  default_channel_key,
  display_order,
  enabled
)
values
  ('contribution_confirmed', 'contribution_confirmations', 'Contribution confirmed', 'A contribution has been matched and posted.', 'collect_group_updates', 10, true),
  ('payment_reminder', 'payment_reminders', 'Payment reminder', 'A contribution request is still pending.', 'collect_group_updates', 20, true),
  ('group_update', 'group_updates', 'Group update', 'A group profile, member, or status changed.', 'collect_group_updates', 30, true),
  ('security_notice', 'security_notices', 'Security notice', 'A security-sensitive account or group event occurred.', 'collect_group_updates', 40, true)
on conflict (key) do update
set preference_key = excluded.preference_key,
    label = excluded.label,
    description = excluded.description,
    default_channel_key = excluded.default_channel_key,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into notification_templates (key, event_type_key, locale, enabled)
values
  ('contribution.confirmed.default', 'contribution_confirmed', 'en', true),
  ('payment.reminder.default', 'payment_reminder', 'en', true),
  ('group.update.default', 'group_update', 'en', true),
  ('security.notice.default', 'security_notice', 'en', true)
on conflict (key) do update
set event_type_key = excluded.event_type_key,
    locale = excluded.locale,
    enabled = excluded.enabled,
    updated_at = now();

insert into notification_template_versions (
  template_key,
  version,
  title_template,
  body_template,
  status,
  effective_at,
  published_at
)
values
  (
    'contribution.confirmed.default',
    '2026-07-04',
    'Contribution confirmed',
    '{{amount}} has been confirmed for {{group}}.',
    'published',
    '2026-07-04 00:00:00+00',
    '2026-07-04 00:00:00+00'
  ),
  (
    'payment.reminder.default',
    '2026-07-04',
    'Payment reminder',
    '{{group}} is waiting for {{amount}}.',
    'published',
    '2026-07-04 00:00:00+00',
    '2026-07-04 00:00:00+00'
  ),
  (
    'group.update.default',
    '2026-07-04',
    'Group update',
    '{{group}} has a new update.',
    'published',
    '2026-07-04 00:00:00+00',
    '2026-07-04 00:00:00+00'
  ),
  (
    'security.notice.default',
    '2026-07-04',
    'Security notice',
    '{{detail}}',
    'published',
    '2026-07-04 00:00:00+00',
    '2026-07-04 00:00:00+00'
  )
on conflict (template_key, version) do update
set title_template = excluded.title_template,
    body_template = excluded.body_template,
    status = excluded.status,
    effective_at = excluded.effective_at,
    published_at = excluded.published_at,
    updated_at = now();

commit;
