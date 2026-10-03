begin;

create table if not exists collection_type_catalog (
  key text primary key check (key in ('ikimina', 'sport', 'church', 'wedding', 'other')),
  label text not null,
  short_purpose text not null,
  icon_key text not null check (icon_key ~ '^[a-z0-9_]+$'),
  default_category_subtype text not null check (default_category_subtype ~ '^[a-z0-9_.-]+$'),
  default_purpose_template_key text not null check (default_purpose_template_key ~ '^[a-z0-9_.-]+$'),
  display_order integer not null default 100,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text
);

create table if not exists collection_category_subtypes (
  collection_type_key text not null references collection_type_catalog(key) on delete cascade,
  key text not null check (key ~ '^[a-z0-9_.-]+$'),
  label text not null,
  display_order integer not null default 100,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  primary key (collection_type_key, key)
);

create table if not exists collection_purpose_templates (
  collection_type_key text not null references collection_type_catalog(key) on delete cascade,
  key text not null check (key ~ '^[a-z0-9_.-]+$'),
  label text not null,
  display_order integer not null default 100,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  primary key (collection_type_key, key)
);

create table if not exists collection_type_country_rules (
  collection_type_key text not null references collection_type_catalog(key) on delete cascade,
  country_code text not null default 'RW' check (country_code ~ '^[A-Z]{2}$'),
  enabled boolean not null default true,
  min_suggested_amount_rwf bigint check (min_suggested_amount_rwf is null or min_suggested_amount_rwf > 0),
  max_suggested_amount_rwf bigint check (max_suggested_amount_rwf is null or max_suggested_amount_rwf > 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id) on delete set null,
  updated_reason text,
  primary key (collection_type_key, country_code),
  constraint collection_type_country_rules_amount_order_check check (
    min_suggested_amount_rwf is null
    or max_suggested_amount_rwf is null
    or min_suggested_amount_rwf <= max_suggested_amount_rwf
  )
);

create index if not exists collection_type_catalog_enabled_order_idx
  on collection_type_catalog (enabled, display_order, key);

create index if not exists collection_category_subtypes_lookup_idx
  on collection_category_subtypes (
    collection_type_key,
    enabled,
    display_order,
    key
  );

create index if not exists collection_purpose_templates_lookup_idx
  on collection_purpose_templates (
    collection_type_key,
    enabled,
    display_order,
    key
  );

create index if not exists collection_type_country_rules_lookup_idx
  on collection_type_country_rules (
    country_code,
    enabled,
    collection_type_key
  );

alter table collection_type_catalog enable row level security;
alter table collection_category_subtypes enable row level security;
alter table collection_purpose_templates enable row level security;
alter table collection_type_country_rules enable row level security;

drop policy if exists "collection type catalog public enabled read" on collection_type_catalog;
create policy "collection type catalog public enabled read"
on collection_type_catalog for select to anon, authenticated
using (enabled);

drop policy if exists "collection type catalog admin manage" on collection_type_catalog;
create policy "collection type catalog admin manage"
on collection_type_catalog for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "collection category subtypes public enabled read" on collection_category_subtypes;
create policy "collection category subtypes public enabled read"
on collection_category_subtypes for select to anon, authenticated
using (
  enabled
  and exists (
    select 1
    from collection_type_catalog ctc
    where ctc.key = collection_category_subtypes.collection_type_key
      and ctc.enabled
  )
);

drop policy if exists "collection category subtypes admin manage" on collection_category_subtypes;
create policy "collection category subtypes admin manage"
on collection_category_subtypes for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "collection purpose templates public enabled read" on collection_purpose_templates;
create policy "collection purpose templates public enabled read"
on collection_purpose_templates for select to anon, authenticated
using (
  enabled
  and exists (
    select 1
    from collection_type_catalog ctc
    where ctc.key = collection_purpose_templates.collection_type_key
      and ctc.enabled
  )
);

drop policy if exists "collection purpose templates admin manage" on collection_purpose_templates;
create policy "collection purpose templates admin manage"
on collection_purpose_templates for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "collection type country rules public enabled read" on collection_type_country_rules;
create policy "collection type country rules public enabled read"
on collection_type_country_rules for select to anon, authenticated
using (
  enabled
  and exists (
    select 1
    from collection_type_catalog ctc
    where ctc.key = collection_type_country_rules.collection_type_key
      and ctc.enabled
  )
);

drop policy if exists "collection type country rules admin manage" on collection_type_country_rules;
create policy "collection type country rules admin manage"
on collection_type_country_rules for all to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));

create or replace function get_collection_type_catalog(
  p_country_code text default 'RW',
  p_locale text default 'en'
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'country_code', upper(coalesce(nullif(trim(p_country_code), ''), 'RW')),
    'locale', coalesce(nullif(trim(p_locale), ''), 'en'),
    'types', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'key', ctc.key,
          'label', ctc.label,
          'short_purpose', ctc.short_purpose,
          'icon_key', ctc.icon_key,
          'default_category_subtype', ctc.default_category_subtype,
          'default_purpose_template_key', ctc.default_purpose_template_key,
          'display_order', ctc.display_order,
          'subtypes', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'key', ccs.key,
                'label', ccs.label,
                'display_order', ccs.display_order
              )
              order by ccs.display_order, ccs.key
            )
            from collection_category_subtypes ccs
            where ccs.collection_type_key = ctc.key
              and ccs.enabled
          ), '[]'::jsonb),
          'purpose_templates', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'key', cpt.key,
                'label', cpt.label,
                'display_order', cpt.display_order
              )
              order by cpt.display_order, cpt.key
            )
            from collection_purpose_templates cpt
            where cpt.collection_type_key = ctc.key
              and cpt.enabled
          ), '[]'::jsonb)
        )
        order by ctc.display_order, ctc.key
      )
      from collection_type_catalog ctc
      where ctc.enabled
        and exists (
          select 1
          from collection_type_country_rules ctcr
          where ctcr.collection_type_key = ctc.key
            and ctcr.enabled
            and ctcr.country_code = upper(coalesce(nullif(trim(p_country_code), ''), 'RW'))
        )
    ), '[]'::jsonb)
  );
$$;

create or replace function resolve_collection_catalog_choice(
  p_collection_type text default 'ikimina',
  p_category_subtype text default null,
  p_purpose_label text default null,
  p_country_code text default 'RW'
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  clean_type text := coalesce(nullif(trim(p_collection_type), ''), 'ikimina');
  clean_subtype text := nullif(trim(p_category_subtype), '');
  clean_purpose text := nullif(trim(p_purpose_label), '');
  clean_country text := upper(coalesce(nullif(trim(p_country_code), ''), 'RW'));
  catalog_row collection_type_catalog%rowtype;
  subtype_row collection_category_subtypes%rowtype;
  purpose_row collection_purpose_templates%rowtype;
begin
  select *
  into catalog_row
  from collection_type_catalog ctc
  where ctc.key = clean_type
    and ctc.enabled
    and exists (
      select 1
      from collection_type_country_rules ctcr
      where ctcr.collection_type_key = ctc.key
        and ctcr.country_code = clean_country
        and ctcr.enabled
    );

  if catalog_row.key is null then
    raise exception 'Unsupported collection type';
  end if;

  clean_subtype := coalesce(clean_subtype, catalog_row.default_category_subtype);
  select *
  into subtype_row
  from collection_category_subtypes ccs
  where ccs.collection_type_key = clean_type
    and ccs.key = clean_subtype
    and ccs.enabled;

  if subtype_row.key is null then
    raise exception 'Unsupported collection subtype';
  end if;

  if clean_purpose is null then
    select *
    into purpose_row
    from collection_purpose_templates cpt
    where cpt.collection_type_key = clean_type
      and cpt.key = catalog_row.default_purpose_template_key
      and cpt.enabled;
  else
    select *
    into purpose_row
    from collection_purpose_templates cpt
    where cpt.collection_type_key = clean_type
      and cpt.label = clean_purpose
      and cpt.enabled;
  end if;

  if purpose_row.key is null then
    raise exception 'Unsupported collection purpose';
  end if;

  return jsonb_build_object(
    'collection_type', clean_type,
    'category_subtype', subtype_row.key,
    'purpose_label', purpose_row.label
  );
end;
$$;

revoke execute on function get_collection_type_catalog(text, text) from public, anon, authenticated;
revoke execute on function resolve_collection_catalog_choice(text, text, text, text) from public, anon, authenticated;
grant execute on function get_collection_type_catalog(text, text) to anon, authenticated;
grant execute on function resolve_collection_catalog_choice(text, text, text, text) to authenticated;

create or replace function audit_collection_catalog_change()
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
      to_jsonb(old)->>'collection_type_key'
    )
    else coalesce(
      to_jsonb(new)->>'key',
      to_jsonb(new)->>'collection_type_key'
    )
  end;

  if auth.uid() is not null then
    perform create_audit_log(
      'collection_catalog.' || lower(tg_op),
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

revoke execute on function audit_collection_catalog_change() from public, anon, authenticated;
grant execute on function audit_collection_catalog_change() to service_role;

drop trigger if exists audit_collection_catalog_change_trigger on collection_type_catalog;
create trigger audit_collection_catalog_change_trigger
after insert or update or delete on collection_type_catalog
for each row execute function audit_collection_catalog_change();

drop trigger if exists audit_collection_catalog_change_trigger on collection_category_subtypes;
create trigger audit_collection_catalog_change_trigger
after insert or update or delete on collection_category_subtypes
for each row execute function audit_collection_catalog_change();

drop trigger if exists audit_collection_catalog_change_trigger on collection_purpose_templates;
create trigger audit_collection_catalog_change_trigger
after insert or update or delete on collection_purpose_templates
for each row execute function audit_collection_catalog_change();

drop trigger if exists audit_collection_catalog_change_trigger on collection_type_country_rules;
create trigger audit_collection_catalog_change_trigger
after insert or update or delete on collection_type_country_rules
for each row execute function audit_collection_catalog_change();

drop trigger if exists app_realtime_event_trigger on collection_type_catalog;
create trigger app_realtime_event_trigger
after insert or update or delete on collection_type_catalog
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on collection_category_subtypes;
create trigger app_realtime_event_trigger
after insert or update or delete on collection_category_subtypes
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on collection_purpose_templates;
create trigger app_realtime_event_trigger
after insert or update or delete on collection_purpose_templates
for each row execute function emit_app_realtime_event('settings');

drop trigger if exists app_realtime_event_trigger on collection_type_country_rules;
create trigger app_realtime_event_trigger
after insert or update or delete on collection_type_country_rules
for each row execute function emit_app_realtime_event('settings');

revoke all on collection_type_catalog from anon, authenticated;
revoke all on collection_category_subtypes from anon, authenticated;
revoke all on collection_purpose_templates from anon, authenticated;
revoke all on collection_type_country_rules from anon, authenticated;
grant select on collection_type_catalog to anon, authenticated;
grant select on collection_category_subtypes to anon, authenticated;
grant select on collection_purpose_templates to anon, authenticated;
grant select on collection_type_country_rules to anon, authenticated;
grant insert, update, delete on collection_type_catalog to authenticated;
grant insert, update, delete on collection_category_subtypes to authenticated;
grant insert, update, delete on collection_purpose_templates to authenticated;
grant insert, update, delete on collection_type_country_rules to authenticated;

insert into collection_type_catalog (
  key,
  label,
  short_purpose,
  icon_key,
  default_category_subtype,
  default_purpose_template_key,
  display_order,
  enabled
)
values
  ('ikimina', 'Ikimina', 'Group savings', 'savings', 'group_savings', 'group_savings', 10, true),
  ('sport', 'Sport', 'Fan club support', 'sport', 'fan_club', 'fan_club_support', 20, true),
  ('church', 'Church', 'Offering and donations', 'church', 'offering', 'offering_and_donations', 30, true),
  ('wedding', 'Wedding', 'Wedding contributions', 'wedding', 'committee', 'wedding_contributions', 40, true),
  ('other', 'Other', 'Custom collection', 'collections', 'custom', 'custom_collection', 50, true)
on conflict (key) do update
set label = excluded.label,
    short_purpose = excluded.short_purpose,
    icon_key = excluded.icon_key,
    default_category_subtype = excluded.default_category_subtype,
    default_purpose_template_key = excluded.default_purpose_template_key,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into collection_category_subtypes (
  collection_type_key,
  key,
  label,
  display_order,
  enabled
)
values
  ('ikimina', 'group_savings', 'Group savings', 10, true),
  ('ikimina', 'family_friends', 'Family or friends', 20, true),
  ('ikimina', 'community_event', 'Community event', 30, true),
  ('sport', 'fan_club', 'Fan club', 10, true),
  ('sport', 'team_support', 'Team support', 20, true),
  ('sport', 'away_travel', 'Away travel', 30, true),
  ('church', 'offering', 'Offering', 10, true),
  ('church', 'tithe', 'Tithe', 20, true),
  ('church', 'project_support', 'Project support', 30, true),
  ('wedding', 'committee', 'Committee', 10, true),
  ('wedding', 'gift', 'Gift', 20, true),
  ('wedding', 'ceremony_support', 'Ceremony support', 30, true),
  ('other', 'custom', 'Custom', 10, true)
on conflict (collection_type_key, key) do update
set label = excluded.label,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into collection_purpose_templates (
  collection_type_key,
  key,
  label,
  display_order,
  enabled
)
values
  ('ikimina', 'group_savings', 'Group savings', 10, true),
  ('ikimina', 'member_support', 'Member support', 20, true),
  ('sport', 'fan_club_support', 'Fan club support', 10, true),
  ('sport', 'away_travel', 'Away travel', 20, true),
  ('church', 'offering_and_donations', 'Offering and donations', 10, true),
  ('church', 'church_project', 'Church project', 20, true),
  ('wedding', 'wedding_contributions', 'Wedding contributions', 10, true),
  ('wedding', 'wedding_gifts', 'Wedding gifts', 20, true),
  ('other', 'custom_collection', 'Custom collection', 10, true)
on conflict (collection_type_key, key) do update
set label = excluded.label,
    display_order = excluded.display_order,
    enabled = excluded.enabled,
    updated_at = now();

insert into collection_type_country_rules (
  collection_type_key,
  country_code,
  enabled,
  min_suggested_amount_rwf,
  max_suggested_amount_rwf
)
select key, 'RW', true, 100, null
from collection_type_catalog
on conflict (collection_type_key, country_code) do update
set enabled = excluded.enabled,
    min_suggested_amount_rwf = excluded.min_suggested_amount_rwf,
    max_suggested_amount_rwf = excluded.max_suggested_amount_rwf,
    updated_at = now();

create or replace function create_group_with_owner(
  group_name text,
  group_description text default '',
  receiver_momo_number text default null,
  receiver_momo_number_hash text default null,
  receiver_label text default 'Primary MOMO receiver',
  group_collection_type text default 'ikimina',
  group_category_subtype text default null,
  group_purpose_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  created_group_id uuid;
  base_slug text;
  final_slug text;
  catalog_choice jsonb;
  clean_type text;
  clean_subtype text;
  clean_purpose_label text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  catalog_choice := resolve_collection_catalog_choice(
    group_collection_type,
    group_category_subtype,
    group_purpose_label,
    'RW'
  );
  clean_type := catalog_choice->>'collection_type';
  clean_subtype := catalog_choice->>'category_subtype';
  clean_purpose_label := catalog_choice->>'purpose_label';

  base_slug := normalize_slug(group_name);
  if base_slug = '' then
    base_slug := 'group';
  end if;
  final_slug := base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into collections (
    slug,
    creator_user_id,
    title,
    description,
    collection_type,
    category_subtype,
    purpose_label,
    receiver_display_label
  )
  values (
    final_slug,
    auth.uid(),
    trim(group_name),
    coalesce(group_description, ''),
    clean_type,
    clean_subtype,
    clean_purpose_label,
    receiver_label
  )
  returning id into created_group_id;

  insert into collection_members (collection_id, user_id, role, status)
  values (created_group_id, auth.uid(), 'owner', 'active');

  if receiver_momo_number is not null and receiver_momo_number_hash is not null then
    insert into collection_receivers (
      collection_id,
      receiver_user_id,
      momo_number,
      momo_number_hash,
      label
    )
    values (
      created_group_id,
      auth.uid(),
      receiver_momo_number,
      receiver_momo_number_hash,
      receiver_label
    );
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'group.created',
    'collection',
    created_group_id,
    jsonb_build_object(
      'collection_type', clean_type,
      'category_subtype', clean_subtype,
      'purpose_label', clean_purpose_label
    )
  );

  return created_group_id;
end;
$$;

revoke execute on function create_group_with_owner(
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text
) from public, anon, authenticated;
grant execute on function create_group_with_owner(
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated;

create or replace function update_collection_profile(
  collection uuid,
  group_name text,
  group_description text,
  group_image_url text default null,
  group_accent_color_hex text default null,
  group_is_public boolean default false,
  group_recurring_cadence text default 'monthly',
  group_collection_type text default null,
  group_category_subtype text default null,
  group_purpose_label text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  clean_cadence text := coalesce(
    nullif(trim(group_recurring_cadence), ''),
    'monthly'
  );
  clean_type text;
  clean_subtype text;
  clean_purpose_label text;
  catalog_choice jsonb;
  current_type text;
  current_subtype text;
  current_purpose_label text;
  next_public_status collection_visibility := case
    when coalesce(group_is_public, false) then 'public_requested'::collection_visibility
    else 'private'::collection_visibility
  end;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can update the group profile';
  end if;
  if nullif(trim(group_name), '') is null then
    raise exception 'Group name is required';
  end if;
  if clean_cadence not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unsupported recurring cadence';
  end if;

  select c.collection_type, c.category_subtype, c.purpose_label
  into current_type, current_subtype, current_purpose_label
  from collections c
  where c.id = collection;

  if current_type is null then
    raise exception 'Group not found';
  end if;

  catalog_choice := resolve_collection_catalog_choice(
    coalesce(nullif(trim(group_collection_type), ''), current_type),
    coalesce(nullif(trim(group_category_subtype), ''), current_subtype),
    coalesce(nullif(trim(group_purpose_label), ''), current_purpose_label),
    'RW'
  );
  clean_type := catalog_choice->>'collection_type';
  clean_subtype := catalog_choice->>'category_subtype';
  clean_purpose_label := catalog_choice->>'purpose_label';

  update collections
  set
    title = trim(group_name),
    description = trim(coalesce(group_description, '')),
    cover_image_url = nullif(trim(group_image_url), ''),
    accent_color_hex = nullif(trim(group_accent_color_hex), ''),
    public_status = next_public_status,
    visibility = next_public_status,
    is_recurring = true,
    recurring_cadence = clean_cadence,
    recurring_rule = jsonb_build_object('cadence', clean_cadence),
    collection_type = clean_type,
    category_subtype = clean_subtype,
    purpose_label = clean_purpose_label,
    updated_at = now()
  where id = collection;

  if not found then
    raise exception 'Group not found';
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'collection.profile_updated',
    'collection',
    collection,
    jsonb_build_object(
      'is_public', coalesce(group_is_public, false),
      'public_status', next_public_status::text,
      'recurring_cadence', clean_cadence,
      'collection_type', clean_type,
      'category_subtype', clean_subtype,
      'purpose_label', clean_purpose_label
    )
  );
end;
$$;

revoke execute on function update_collection_profile(
  uuid,
  text,
  text,
  text,
  text,
  boolean,
  text,
  text,
  text,
  text
) from public, anon, authenticated;
grant execute on function update_collection_profile(
  uuid,
  text,
  text,
  text,
  text,
  boolean,
  text,
  text,
  text,
  text
) to authenticated;

commit;
