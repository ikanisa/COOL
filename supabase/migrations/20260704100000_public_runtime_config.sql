begin;

create table if not exists brand_entities (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  display_name text not null,
  legal_name text not null,
  public_url text not null check (public_url ~ '^https://'),
  admin_url text check (admin_url is null or admin_url ~ '^https://'),
  app_download_url text check (app_download_url is null or app_download_url ~ '^https://'),
  regulatory_footer_note text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists support_channels (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  channel_type text not null check (channel_type in ('whatsapp', 'email', 'phone', 'url')),
  label text not null,
  value text not null,
  display_value text,
  sort_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists payment_entrypoints (
  key text primary key check (key ~ '^[a-z0-9_.-]+$'),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  network text not null check (network ~ '^[a-z0-9_]+$'),
  label text not null,
  code text not null,
  display_code text,
  instructions text not null default '',
  sort_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create index if not exists brand_entities_active_idx
  on brand_entities (is_active, key);

create index if not exists support_channels_active_order_idx
  on support_channels (is_active, sort_order, key);

create index if not exists payment_entrypoints_active_country_order_idx
  on payment_entrypoints (is_active, country_code, sort_order, key);

alter table brand_entities enable row level security;
alter table support_channels enable row level security;
alter table payment_entrypoints enable row level security;

drop policy if exists "brand entities public read active" on brand_entities;
create policy "brand entities public read active"
on brand_entities
for select
to anon, authenticated
using (is_active);

drop policy if exists "brand entities admin read all" on brand_entities;
create policy "brand entities admin read all"
on brand_entities
for select
to authenticated
using (public.has_admin_permission('settings.read', (select auth.uid())));

drop policy if exists "brand entities admin insert" on brand_entities;
create policy "brand entities admin insert"
on brand_entities
for insert
to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "brand entities admin update" on brand_entities;
create policy "brand entities admin update"
on brand_entities
for update
to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "brand entities admin delete" on brand_entities;
create policy "brand entities admin delete"
on brand_entities
for delete
to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "support channels public read active" on support_channels;
create policy "support channels public read active"
on support_channels
for select
to anon, authenticated
using (is_active);

drop policy if exists "support channels admin read all" on support_channels;
create policy "support channels admin read all"
on support_channels
for select
to authenticated
using (public.has_admin_permission('settings.read', (select auth.uid())));

drop policy if exists "support channels admin insert" on support_channels;
create policy "support channels admin insert"
on support_channels
for insert
to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "support channels admin update" on support_channels;
create policy "support channels admin update"
on support_channels
for update
to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "support channels admin delete" on support_channels;
create policy "support channels admin delete"
on support_channels
for delete
to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "payment entrypoints public read active" on payment_entrypoints;
create policy "payment entrypoints public read active"
on payment_entrypoints
for select
to anon, authenticated
using (is_active);

drop policy if exists "payment entrypoints admin read all" on payment_entrypoints;
create policy "payment entrypoints admin read all"
on payment_entrypoints
for select
to authenticated
using (public.has_admin_permission('settings.read', (select auth.uid())));

drop policy if exists "payment entrypoints admin insert" on payment_entrypoints;
create policy "payment entrypoints admin insert"
on payment_entrypoints
for insert
to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "payment entrypoints admin update" on payment_entrypoints;
create policy "payment entrypoints admin update"
on payment_entrypoints
for update
to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "payment entrypoints admin delete" on payment_entrypoints;
create policy "payment entrypoints admin delete"
on payment_entrypoints
for delete
to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

create or replace function get_public_runtime_config()
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'brand', coalesce((
      select to_jsonb(b) - 'updated_by' - 'updated_reason'
      from brand_entities b
      where b.key = 'collect'
        and b.is_active
      limit 1
    ), '{}'::jsonb),
    'support_channels', coalesce((
      select jsonb_agg(to_jsonb(s) - 'updated_by' - 'updated_reason' order by s.sort_order, s.key)
      from support_channels s
      where s.is_active
    ), '[]'::jsonb),
    'payment_entrypoints', coalesce((
      select jsonb_agg(to_jsonb(p) - 'updated_by' - 'updated_reason' order by p.sort_order, p.key)
      from payment_entrypoints p
      where p.is_active
    ), '[]'::jsonb)
  );
$$;

revoke execute on function get_public_runtime_config() from public;
grant execute on function get_public_runtime_config() to anon, authenticated;

create or replace function audit_public_runtime_config_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  runtime_key text;
begin
  runtime_key := case when tg_op = 'DELETE' then old.key else new.key end;
  if auth.uid() is not null then
    perform create_audit_log(
      'public_runtime_config.' || lower(tg_op),
      tg_table_name,
      null,
      jsonb_build_object('key', runtime_key)
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function audit_public_runtime_config_change() from public, anon, authenticated;
grant execute on function audit_public_runtime_config_change() to service_role;

drop trigger if exists audit_public_runtime_config_change_trigger on brand_entities;
create trigger audit_public_runtime_config_change_trigger
after insert or update or delete on brand_entities
for each row execute function audit_public_runtime_config_change();

drop trigger if exists audit_public_runtime_config_change_trigger on support_channels;
create trigger audit_public_runtime_config_change_trigger
after insert or update or delete on support_channels
for each row execute function audit_public_runtime_config_change();

drop trigger if exists audit_public_runtime_config_change_trigger on payment_entrypoints;
create trigger audit_public_runtime_config_change_trigger
after insert or update or delete on payment_entrypoints
for each row execute function audit_public_runtime_config_change();

drop trigger if exists app_realtime_event_trigger on brand_entities;
create trigger app_realtime_event_trigger
after insert or update or delete on brand_entities
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on support_channels;
create trigger app_realtime_event_trigger
after insert or update or delete on support_channels
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on payment_entrypoints;
create trigger app_realtime_event_trigger
after insert or update or delete on payment_entrypoints
for each row execute function emit_app_realtime_event('settings');

revoke all on brand_entities from anon, authenticated;
revoke all on support_channels from anon, authenticated;
revoke all on payment_entrypoints from anon, authenticated;
grant select on brand_entities to anon, authenticated;
grant select on support_channels to anon, authenticated;
grant select on payment_entrypoints to anon, authenticated;
grant insert, update, delete on brand_entities to authenticated;
grant insert, update, delete on support_channels to authenticated;
grant insert, update, delete on payment_entrypoints to authenticated;

insert into brand_entities (
  key,
  display_name,
  legal_name,
  public_url,
  admin_url,
  app_download_url,
  regulatory_footer_note,
  metadata,
  is_active
)
values (
  'collect',
  'Collect by IKANISA',
  'IKANISA Ltd.',
  'https://collect.ikanisa.com',
  'https://admin.collect.ikanisa.com',
  'https://play.google.com/store/apps/details?id=app.cool.mobile',
  'IKANISA Ltd. is a registered technology company. Savings, credit and insurance products are provided by licensed partner institutions where approved arrangements apply.',
  '{}'::jsonb,
  true
)
on conflict (key) do update
set display_name = excluded.display_name,
    legal_name = excluded.legal_name,
    public_url = excluded.public_url,
    admin_url = excluded.admin_url,
    app_download_url = excluded.app_download_url,
    regulatory_footer_note = excluded.regulatory_footer_note,
    metadata = excluded.metadata,
    is_active = excluded.is_active,
    updated_at = now();

insert into support_channels (
  key,
  channel_type,
  label,
  value,
  display_value,
  sort_order,
  metadata,
  is_active
)
values
  (
    'support.whatsapp',
    'whatsapp',
    'WhatsApp support',
    '250795588248',
    '+250 795 588 248',
    10,
    '{"default_message":"Hello IKANISA, I need support with Collect."}'::jsonb,
    true
  ),
  (
    'support.email',
    'email',
    'Email support',
    'info@ikanisa.com',
    'info@ikanisa.com',
    20,
    '{"default_subject":"Collect support"}'::jsonb,
    true
  )
on conflict (key) do update
set channel_type = excluded.channel_type,
    label = excluded.label,
    value = excluded.value,
    display_value = excluded.display_value,
    sort_order = excluded.sort_order,
    metadata = excluded.metadata,
    is_active = excluded.is_active,
    updated_at = now();

insert into payment_entrypoints (
  key,
  country_code,
  currency,
  network,
  label,
  code,
  display_code,
  instructions,
  sort_order,
  metadata,
  is_active
)
values (
  'rw.mtn_momo.ussd.collect_2000',
  'RW',
  'RWF',
  'mtn_momo',
  'Collect MoMo USSD',
  '*182*8*1*41258*2000#',
  '*182*8*1*41258*2000#',
  'Dial to save RWF 2,000 into Collect.',
  10,
  '{"amount_rwf":2000}'::jsonb,
  true
)
on conflict (key) do update
set country_code = excluded.country_code,
    currency = excluded.currency,
    network = excluded.network,
    label = excluded.label,
    code = excluded.code,
    display_code = excluded.display_code,
    instructions = excluded.instructions,
    sort_order = excluded.sort_order,
    metadata = excluded.metadata,
    is_active = excluded.is_active,
    updated_at = now();

commit;
