begin;

-- Phase-one foundation only. No allocation, financial posting or SMS dispatch
-- is enabled by this migration. Admin onboarding defaults OFF for pilot gating.
create schema collect_hybrid;
revoke all on schema collect_hybrid from public, anon;
grant usage on schema collect_hybrid to authenticated, service_role;

create table collect_hybrid.member_records (
  id uuid primary key default gen_random_uuid(),
  collect_id char(6) not null unique check (collect_id ~ '^[0-9]{6}$'),
  linked_user_id uuid unique references public.profiles(id) on delete set null,
  lifecycle text not null default 'active' check (lifecycle in ('active', 'inactive')),
  origin text not null check (origin in ('app', 'admin_assisted')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index hybrid_member_created_by_idx on collect_hybrid.member_records(created_by);
insert into collect_hybrid.member_records(id, collect_id, linked_user_id, origin)
select id, public_id, id, 'app' from public.profiles;

create function collect_hybrid.normalize_momo_name(value text) returns text
language sql immutable strict set search_path = ''
as $$ select upper(btrim(regexp_replace(value, '[[:space:]]+', ' ', 'g'))); $$;

create function collect_hybrid.canonical_momo_number(value text) returns text
language plpgsql immutable strict set search_path = '' as $$
declare clean text := regexp_replace(btrim(value), '[[:space:]-]', '', 'g');
begin
  if clean ~ '^07[2389][0-9]{7}$' then return '+250' || substr(clean, 2); end if;
  if clean ~ '^\+2507[2389][0-9]{7}$' then return clean; end if;
  raise exception 'Invalid Rwanda MoMo number';
end; $$;

create table collect_hybrid.member_momo_identities (
  member_id uuid primary key references collect_hybrid.member_records(id) on delete restrict,
  member_name text not null check (char_length(btrim(member_name)) between 2 and 120),
  momo_name text not null check (char_length(btrim(momo_name)) between 2 and 120),
  momo_number text not null unique check (momo_number ~ '^\+2507[2389][0-9]{7}$'),
  normalized_name text generated always as (collect_hybrid.normalize_momo_name(momo_name)) stored,
  last3 text generated always as (right(momo_number, 3)) stored,
  match_key text generated always as (
    encode(extensions.digest(collect_hybrid.normalize_momo_name(momo_name) || '|' || right(momo_number, 3), 'sha256'), 'hex')
  ) stored,
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now()
);
create index hybrid_identity_match_idx on collect_hybrid.member_momo_identities(match_key);

alter table public.collection_members add column member_record_id uuid
  references collect_hybrid.member_records(id) on delete restrict;
create unique index collection_members_record_role_unique
  on public.collection_members(collection_id, member_record_id, role)
  where member_record_id is not null;
create index collection_members_record_idx on public.collection_members(member_record_id);
update public.collection_members set member_record_id = user_id where user_id is not null;

alter table public.collections add column creation_origin text not null default 'member_app'
  check (creation_origin in ('member_app', 'admin_assisted', 'platform_sponsored'));
update public.collections set creation_origin = 'platform_sponsored' where is_platform_sponsored;

create function collect_hybrid.sync_collection_origin() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Preserve origin for future calls to the unchanged public-sponsored RPC.
  if new.is_platform_sponsored then new.creation_origin := 'platform_sponsored'; end if;
  return new;
end; $$;
create trigger hybrid_sync_collection_origin before insert on public.collections
for each row execute function collect_hybrid.sync_collection_origin();

create table collect_hybrid.roster_batches (
  request_id uuid primary key,
  collection_id uuid not null references public.collections(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  input_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
create index hybrid_batches_collection_idx on collect_hybrid.roster_batches(collection_id);
create index hybrid_batches_actor_idx on collect_hybrid.roster_batches(actor_id);

create table collect_hybrid.group_creation_requests (
  request_id uuid primary key,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  input_hash text not null,
  collection_id uuid not null references public.collections(id) on delete restrict,
  result jsonb not null,
  created_at timestamptz not null default now()
);
create index hybrid_creation_actor_idx on collect_hybrid.group_creation_requests(actor_id);
create index hybrid_creation_group_idx on collect_hybrid.group_creation_requests(collection_id);

-- Centralized reservation: the existing app generator and assisted records use
-- the same transaction lock and namespace. Auth deletion never frees an ID.
create or replace function public.generate_public_id() returns char(6)
language plpgsql set search_path = '' as $$
declare candidate char(6); attempts integer := 0;
begin
  perform pg_advisory_xact_lock(hashtextextended('collect-numeric-member-id', 0));
  loop
    candidate := lpad(floor(random() * 1000000)::int::text, 6, '0')::char(6);
    if not exists(select 1 from public.profiles where public_id = candidate)
       and not exists(select 1 from collect_hybrid.member_records where collect_id = candidate) then
      return candidate;
    end if;
    attempts := attempts + 1;
    if attempts >= 1000 then raise exception 'Collect ID allocation requires review'; end if;
  end loop;
end; $$;
revoke all on function public.generate_public_id() from public, anon, authenticated;
grant execute on function public.generate_public_id() to service_role;

create function collect_hybrid.guard_profile_collect_id() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('collect-numeric-member-id', 0));
  if tg_op = 'UPDATE' and new.public_id is distinct from old.public_id then
    raise exception 'Collect identity changes require a reviewed account-link workflow';
  end if;
  if exists(select 1 from collect_hybrid.member_records m where m.collect_id = new.public_id
    and m.linked_user_id is distinct from new.id) then
    raise exception 'Collect ID is already reserved';
  end if;
  return new;
end; $$;
create trigger hybrid_guard_profile_collect_id before insert or update of public_id on public.profiles
for each row execute function collect_hybrid.guard_profile_collect_id();

create function collect_hybrid.register_app_member() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into collect_hybrid.member_records(id, collect_id, linked_user_id, origin)
  values (new.id, new.public_id, new.id, 'app');
  return new;
end; $$;
create trigger hybrid_register_app_member after insert on public.profiles
for each row execute function collect_hybrid.register_app_member();

create function collect_hybrid.bind_app_membership() returns trigger
language plpgsql security definer set search_path = '' as $$
declare registered_id uuid;
begin
  if new.user_id is not null then
    select id into registered_id from collect_hybrid.member_records where linked_user_id = new.user_id;
    if registered_id is null or (new.member_record_id is not null and new.member_record_id <> registered_id) then
      raise exception 'Membership account and record do not match';
    end if;
    new.member_record_id := registered_id;
  end if;
  return new;
end; $$;
create trigger hybrid_bind_app_membership before insert or update of user_id, member_record_id on public.collection_members
for each row execute function collect_hybrid.bind_app_membership();

insert into public.feature_flags(key, enabled, description)
values ('hybrid_member_onboarding', false, 'Pilot gate: private assisted groups and reviewed offline rosters; does not enable payment posting or SMS')
on conflict (key) do nothing;

create function collect_hybrid.assert_onboarding() returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.assert_admin_permission('collections.moderate');
  perform public.assert_admin_permission('users.read');
  if not coalesce((select enabled from public.feature_flags where key='hybrid_member_onboarding'), false) then
    raise exception 'Hybrid onboarding is disabled pending controlled rollout';
  end if;
end; $$;

create function collect_hybrid.create_assisted_group(p_title text, p_reason text, p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  group_id uuid; clean_title text := btrim(p_title); input_digest text; response jsonb;
  prior collect_hybrid.group_creation_requests;
begin
  perform collect_hybrid.assert_onboarding();
  if p_request_id is null or clean_title is null or char_length(clean_title) not between 3 and 120
    or p_reason is null or char_length(btrim(p_reason)) not between 8 and 500 then
    raise exception 'Invalid group name or audit reason';
  end if;
  input_digest := encode(extensions.digest(jsonb_build_array(clean_title, btrim(p_reason))::text, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('hybrid-group-create:' || p_request_id::text, 0));
  select * into prior from collect_hybrid.group_creation_requests where request_id=p_request_id;
  if prior.request_id is not null then
    if prior.actor_id <> auth.uid() or prior.input_hash <> input_digest then raise exception 'Group idempotency key conflict'; end if;
    return prior.result || jsonb_build_object('replay', true);
  end if;
  -- Draft private savings group; no guessed/default payee and no fake owner account.
  insert into public.collections(slug, creator_user_id, title, category, visibility, public_status,
    collection_type, contribution_visibility, allow_anonymous, diaspora_enabled, creation_origin)
  values ('assisted-' || replace(gen_random_uuid()::text, '-', ''), auth.uid(), clean_title,
    'Family / friends', 'private', 'private', 'ikimina', 'members', false, false, 'admin_assisted')
  returning id into group_id;
  insert into public.collection_members(collection_id, user_id, role, status)
  values (group_id, auth.uid(), 'owner', 'active');
  perform public.create_audit_log('collection.assisted.created', 'collection', group_id,
    jsonb_build_object('reason', btrim(p_reason), 'route_ready', false));
  response := jsonb_build_object('ok', true, 'collection_id', group_id, 'visibility', 'private', 'route_ready', false, 'replay', false);
  insert into collect_hybrid.group_creation_requests(request_id, actor_id, input_hash, collection_id, result)
  values (p_request_id, auth.uid(), input_digest, group_id, response);
  return response;
end; $$;

create function public.admin_create_assisted_group(p_title text, p_reason text, p_request_id uuid) returns jsonb
language sql security invoker set search_path = ''
as $$ select collect_hybrid.create_assisted_group(p_title, p_reason, p_request_id); $$;

create function collect_hybrid.add_roster(p_collection_id uuid, p_rows jsonb, p_request_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  row_data jsonb; phone text; registered_name text; display_name text;
  identity_row collect_hybrid.member_momo_identities; record_id uuid;
  result_rows jsonb := '[]'; response jsonb; old_batch collect_hybrid.roster_batches;
  input_digest text;
begin
  perform collect_hybrid.assert_onboarding();
  if p_request_id is null or p_reason is null or char_length(btrim(p_reason)) not between 8 and 500
    or p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Invalid reviewed roster request';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 500 then raise exception 'Roster must contain 1 to 500 reviewed rows'; end if;
  perform 1 from public.collections where id = p_collection_id and creation_origin = 'admin_assisted'
    and archived_at is null and public_status = 'private' and not diaspora_enabled for update;
  if not found then raise exception 'Active private assisted Rwanda group required'; end if;
  input_digest := encode(extensions.digest(p_collection_id::text || p_rows::text || btrim(p_reason), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('hybrid-roster:' || p_request_id::text, 0));
  select * into old_batch from collect_hybrid.roster_batches where request_id = p_request_id;
  if old_batch.request_id is not null then
    if old_batch.input_hash <> input_digest or old_batch.actor_id <> auth.uid() then raise exception 'Roster idempotency key conflict'; end if;
    return old_batch.result || jsonb_build_object('replay', true);
  end if;
  -- Same namespace lock serializes both allocation and duplicate-number checks.
  perform pg_advisory_xact_lock(hashtextextended('collect-numeric-member-id', 0));
  for row_data in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(row_data) <> 'object' then raise exception 'Invalid roster row'; end if;
    phone := collect_hybrid.canonical_momo_number(row_data->>'momo_number');
    registered_name := btrim(row_data->>'momo_name');
    display_name := btrim(coalesce(nullif(row_data->>'member_name', ''), registered_name));
    if phone is null or registered_name is null or char_length(registered_name) not between 2 and 120
      or display_name is null or char_length(display_name) not between 2 and 120
      or registered_name ~ '[[:cntrl:]]' or display_name ~ '[[:cntrl:]]' then
      raise exception 'Each row requires a valid full MoMo number and names';
    end if;
    select * into identity_row from collect_hybrid.member_momo_identities where momo_number = phone;
    if identity_row.member_id is not null then
      if identity_row.normalized_name <> collect_hybrid.normalize_momo_name(registered_name)
        or identity_row.member_name <> display_name then raise exception 'Existing MoMo identity differs; review before updating'; end if;
      record_id := identity_row.member_id;
      if not exists(select 1 from collect_hybrid.member_records where id=record_id and lifecycle='active') then
        raise exception 'Existing member is inactive';
      end if;
    else
      if exists(select 1 from public.profiles where regexp_replace(coalesce(momo_number, ''), '^0', '+250') = phone) then
        raise exception 'Existing app MoMo number requires reviewed identity linking';
      end if;
      insert into collect_hybrid.member_records(collect_id, origin, created_by)
      values (public.generate_public_id(), 'admin_assisted', auth.uid()) returning id into record_id;
      insert into collect_hybrid.member_momo_identities(member_id, member_name, momo_name, momo_number)
      values (record_id, display_name, registered_name, phone);
    end if;
    if exists(select 1 from public.collection_members where collection_id=p_collection_id
      and member_record_id=record_id and role='member' and status <> 'active') then
      raise exception 'Existing membership is not active; review before reactivation';
    end if;
    insert into public.collection_members(collection_id, member_record_id, role, status)
    values (p_collection_id, record_id, 'member', 'active') on conflict do nothing;
    result_rows := result_rows || jsonb_build_array(jsonb_build_object('member_id', record_id,
      'collect_id', (select collect_id from collect_hybrid.member_records where id=record_id)));
  end loop;
  response := jsonb_build_object('ok', true, 'collection_id', p_collection_id, 'rows', result_rows, 'replay', false);
  insert into collect_hybrid.roster_batches(request_id, collection_id, actor_id, input_hash, result)
  values (p_request_id, p_collection_id, auth.uid(), input_digest, response);
  perform public.create_audit_log('collection.assisted.roster_added', 'collection', p_collection_id,
    jsonb_build_object('reason', btrim(p_reason), 'request_id', p_request_id, 'row_count', jsonb_array_length(p_rows)));
  return response;
end; $$;

create function public.admin_add_assisted_roster(p_collection_id uuid, p_rows jsonb, p_request_id uuid, p_reason text)
returns jsonb language sql security invoker set search_path = ''
as $$ select collect_hybrid.add_roster(p_collection_id, p_rows, p_request_id, p_reason); $$;

-- No direct table access, including PII, from the browser or MCP operator.
alter table collect_hybrid.member_records enable row level security;
alter table collect_hybrid.member_momo_identities enable row level security;
alter table collect_hybrid.roster_batches enable row level security;
alter table collect_hybrid.group_creation_requests enable row level security;
revoke all on all tables in schema collect_hybrid from public, anon, authenticated, service_role;
revoke all on all functions in schema collect_hybrid from public, anon, authenticated, service_role;
grant execute on function collect_hybrid.create_assisted_group(text, text, uuid),
  collect_hybrid.add_roster(uuid, jsonb, uuid, text) to authenticated;
revoke all on function public.admin_create_assisted_group(text, text, uuid),
  public.admin_add_assisted_roster(uuid, jsonb, uuid, text) from public, anon;
grant execute on function public.admin_create_assisted_group(text, text, uuid),
  public.admin_add_assisted_roster(uuid, jsonb, uuid, text) to authenticated;

commit;
