create extension if not exists pgcrypto;

create type collection_visibility as enum ('private', 'public_requested', 'public_approved', 'public_rejected', 'archived');
create type member_role as enum ('owner', 'admin', 'receiver', 'member', 'contributor', 'viewer');
create type member_status as enum ('invited', 'active', 'removed', 'left');
create type payment_intent_status as enum ('pending', 'matched', 'expired', 'cancelled');
create type allocation_status as enum ('unallocated', 'allocated', 'ambiguous', 'needs_review', 'ignored');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  public_id char(6) unique not null,
  display_name text,
  avatar_url text,
  whatsapp_phone text unique,
  momo_number text,
  momo_number_hash text,
  anonymity_default text not null default 'anonymous' check (anonymity_default in ('anonymous', 'public_id', 'display_name')),
  is_platform_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_public_id_digits check (public_id ~ '^[0-9]{6}$')
);

create table collections (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  creator_user_id uuid not null references profiles(id) on delete restrict,
  title text not null check (char_length(trim(title)) between 3 and 120),
  description text not null default '',
  category text not null check (category in (
    'Church',
    'Artist / Creator',
    'Sports team',
    'Wedding',
    'Funeral',
    'Medical support',
    'School / education',
    'Community event',
    'Public figure / fan support',
    'Family / friends',
    'Other'
  )),
  cover_image_url text,
  currency text not null default 'RWF' check (currency = 'RWF'),
  target_amount_rwf bigint check (target_amount_rwf is null or target_amount_rwf > 0),
  deadline_at timestamptz,
  visibility collection_visibility not null default 'private',
  public_status collection_visibility not null default 'private',
  is_recurring boolean not null default false,
  recurring_rule jsonb,
  allow_anonymous boolean not null default true,
  contribution_visibility text not null default 'public_safe' check (contribution_visibility in ('private', 'members', 'public_safe')),
  allow_public_comments boolean not null default false,
  receiver_display_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint collections_visibility_consistency check (
    public_status in ('private', 'public_requested', 'public_approved', 'public_rejected', 'archived')
  )
);

create table collection_members (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  invited_phone_hash text,
  role member_role not null default 'member',
  status member_status not null default 'invited',
  created_at timestamptz not null default now(),
  unique (collection_id, user_id, role)
);

create table collection_receivers (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  receiver_user_id uuid not null references profiles(id) on delete restrict,
  momo_number text not null,
  momo_number_hash text not null,
  network text not null default 'unknown' check (network in ('mtn_momo', 'airtel_money', 'unknown')),
  label text not null default 'Collection receiver',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table payment_instruction_templates (
  id uuid primary key default gen_random_uuid(),
  country_code text not null default 'RW' check (country_code = 'RW'),
  currency text not null default 'RWF' check (currency = 'RWF'),
  network text not null default 'unknown' check (network in ('mtn_momo', 'airtel_money', 'unknown')),
  title text not null,
  body_template text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table collection_invites (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  invite_token_hash text unique not null,
  invited_by uuid not null references profiles(id) on delete restrict,
  invited_phone_hash text,
  role member_role not null default 'member',
  expires_at timestamptz not null default (now() + interval '14 days'),
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table payment_intents (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  contributor_user_id uuid references profiles(id) on delete set null,
  contribution_code text unique not null,
  expected_amount_rwf bigint check (expected_amount_rwf is null or expected_amount_rwf > 0),
  receiver_momo_number_hash text not null,
  sender_phone_hash text,
  reported_transaction_id text,
  status payment_intent_status not null default 'pending',
  anonymity_choice text not null default 'anonymous' check (anonymity_choice in ('anonymous', 'public_id', 'display_name')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create table raw_payment_sms (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid references collections(id) on delete set null,
  receiver_user_id uuid not null references profiles(id) on delete restrict,
  raw_sender text not null,
  raw_body text not null,
  body_hash text unique not null,
  receiver_momo_number_hash text,
  received_at_device timestamptz,
  ingested_at timestamptz not null default now(),
  parse_status text not null default 'pending' check (parse_status in ('pending', 'parsed', 'failed', 'ignored')),
  created_at timestamptz not null default now()
);

create table parsed_payment_events (
  id uuid primary key default gen_random_uuid(),
  raw_sms_id uuid unique references raw_payment_sms(id) on delete cascade,
  collection_id uuid references collections(id) on delete set null,
  receiver_user_id uuid not null references profiles(id) on delete restrict,
  is_mobile_money_payment boolean not null default false,
  network text not null default 'unknown' check (network in ('mtn_momo', 'airtel_money', 'unknown')),
  direction text not null default 'unknown' check (direction in ('incoming', 'outgoing', 'unknown')),
  amount_rwf bigint,
  currency text not null default 'unknown' check (currency in ('RWF', 'unknown')),
  transaction_id text,
  sender_name text,
  sender_phone_hash text,
  receiver_phone_hash text,
  transaction_time timestamptz,
  detected_collection_code text,
  detected_user_public_id text,
  confidence numeric not null default 0 check (confidence >= 0 and confidence <= 1),
  parser_model text,
  parser_schema_version text not null default 'collect.sms_parser.v1',
  parsed_json jsonb not null default '{}'::jsonb,
  allocation_status allocation_status not null default 'unallocated',
  review_reason text,
  created_at timestamptz not null default now()
);

create table payments (
  id uuid primary key default gen_random_uuid(),
  parsed_event_id uuid unique references parsed_payment_events(id) on delete restrict,
  payment_intent_id uuid references payment_intents(id) on delete set null,
  collection_id uuid not null references collections(id) on delete restrict,
  contributor_user_id uuid references profiles(id) on delete set null,
  contributor_public_id char(6),
  receiver_user_id uuid not null references profiles(id) on delete restrict,
  receiver_momo_number_hash text not null,
  amount_rwf bigint not null check (amount_rwf > 0),
  currency text not null default 'RWF' check (currency = 'RWF'),
  transaction_id text unique,
  source text not null check (source in ('sms_auto', 'manual_sms_paste', 'manual_admin', 'import')),
  status text not null default 'posted' check (status in ('posted', 'reversed', 'review')),
  anonymity_choice text not null default 'anonymous' check (anonymity_choice in ('anonymous', 'public_id', 'display_name')),
  posted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references payments(id) on delete restrict,
  parsed_event_id uuid references parsed_payment_events(id) on delete restrict,
  collection_id uuid not null references collections(id) on delete restrict,
  payment_intent_id uuid references payment_intents(id) on delete set null,
  allocated_by uuid references profiles(id) on delete set null,
  allocation_method text not null check (allocation_method in ('auto_exact_txn', 'auto_code', 'auto_phone_amount_time', 'auto_unique_amount_time', 'manual')),
  confidence numeric not null default 1 check (confidence >= 0 and confidence <= 1),
  reason text not null,
  created_at timestamptz not null default now(),
  unique (parsed_event_id)
);

create table ledger_entries (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references payments(id) on delete restrict,
  collection_id uuid not null references collections(id) on delete restrict,
  user_id uuid references profiles(id) on delete set null,
  entry_type text not null check (entry_type in ('collection_credit', 'member_credit')),
  amount_rwf bigint not null check (amount_rwf <> 0),
  currency text not null default 'RWF' check (currency = 'RWF'),
  visibility text not null default 'public_safe' check (visibility in ('private', 'members', 'public_safe')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table recurring_periods (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  expected_amount_rwf bigint check (expected_amount_rwf is null or expected_amount_rwf > 0),
  status text not null default 'open' check (status in ('open', 'closed', 'cancelled')),
  created_at timestamptz not null default now(),
  unique (collection_id, period_start, period_end)
);

create table member_obligations (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  recurring_period_id uuid not null references recurring_periods(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  expected_amount_rwf bigint not null check (expected_amount_rwf >= 0),
  paid_amount_rwf bigint not null default 0 check (paid_amount_rwf >= 0),
  status text not null default 'overdue' check (status in ('paid', 'partial', 'overdue', 'waived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (recurring_period_id, user_id)
);

create table public_collection_requests (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  requested_by uuid not null references profiles(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_user_id uuid references profiles(id) on delete set null,
  admin_note text,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table collection_reports (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete cascade,
  reporter_user_id uuid references profiles(id) on delete set null,
  reason text not null,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  admin_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table receiver_mode_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  enabled boolean not null,
  momo_number_hash text,
  build_channel text not null,
  device_label text,
  created_at timestamptz not null default now()
);

create table otp_rate_limits (
  id uuid primary key default gen_random_uuid(),
  phone_hash text not null,
  ip_hash text,
  requested_at timestamptz not null default now()
);

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

insert into payment_instruction_templates (network, title, body_template)
values
  (
    'mtn_momo',
    'MTN MOMO USSD',
    'Dial *182# or use the MTN MoMo menu, send {{amount}} to {{receiver_number}}, and enter {{code}} in the reason/reference field when available.'
  ),
  (
    'airtel_money',
    'Airtel Money USSD',
    'Use the Airtel Money USSD menu, send {{amount}} to {{receiver_number}}, and include {{code}} as the reference when the menu supports it.'
  ),
  (
    'unknown',
    'Mobile money USSD',
    'Use your mobile-money USSD menu, send {{amount}} to {{receiver_number}}, and include {{code}} as the reason/reference when supported.'
  );

create index collections_creator_idx on collections (creator_user_id);
create index collections_public_idx on collections (public_status, category, created_at desc);
create index collection_members_user_idx on collection_members (user_id, status);
create index payment_intents_match_idx on payment_intents (status, receiver_momo_number_hash, expected_amount_rwf, sender_phone_hash, created_at);
create index payment_intents_code_idx on payment_intents (contribution_code);
create index raw_sms_receiver_idx on raw_payment_sms (receiver_user_id, ingested_at desc);
create index parsed_events_review_idx on parsed_payment_events (allocation_status, created_at desc);
create index parsed_events_txn_idx on parsed_payment_events (transaction_id);
create index payments_collection_idx on payments (collection_id, posted_at desc);
create index ledger_collection_idx on ledger_entries (collection_id, created_at desc);

create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at before update on profiles
for each row execute function touch_updated_at();

create or replace function prevent_client_admin_escalation()
returns trigger
language plpgsql
as $$
begin
  if auth.role() <> 'service_role' and new.is_platform_admin is distinct from old.is_platform_admin then
    raise exception 'Platform admin flag cannot be changed by clients';
  end if;
  return new;
end;
$$;

create trigger profiles_prevent_client_admin_escalation before update on profiles
for each row execute function prevent_client_admin_escalation();

create trigger collections_touch_updated_at before update on collections
for each row execute function touch_updated_at();

create trigger obligations_touch_updated_at before update on member_obligations
for each row execute function touch_updated_at();

create or replace function normalize_slug(value text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(coalesce(value, 'collection')), '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function generate_public_id()
returns char(6)
language plpgsql
as $$
declare
  candidate char(6);
begin
  loop
    candidate := lpad(floor(random() * 1000000)::int::text, 6, '0')::char(6);
    exit when not exists (select 1 from profiles where public_id = candidate);
  end loop;
  return candidate;
end;
$$;

create or replace function create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, public_id, whatsapp_phone, display_name)
  values (
    new.id,
    generate_public_id(),
    nullif(new.phone, ''),
    coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), null)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_collect_profile on auth.users;
create trigger on_auth_user_created_collect_profile
after insert on auth.users
for each row execute function create_profile_for_auth_user();

create or replace function get_current_profile()
returns profiles
language sql
stable
security definer
set search_path = public
as $$
  select *
  from profiles
  where id = auth.uid();
$$;

create or replace function public.current_user_is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_platform_admin from profiles where id = auth.uid()), false);
$$;

create or replace function public.user_is_collection_admin(collection uuid, user_uuid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_is_platform_admin(), false)
    or exists (
      select 1
      from collections c
      where c.id = collection and c.creator_user_id = user_uuid
    )
    or exists (
      select 1
      from collection_members m
      where m.collection_id = collection
        and m.user_id = user_uuid
        and m.status = 'active'
        and m.role in ('owner', 'admin', 'receiver')
    );
$$;

create or replace function public.user_can_read_collection(collection uuid, user_uuid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from collections c
    where c.id = collection
      and (
        c.public_status = 'public_approved'
        or c.creator_user_id = user_uuid
        or public.current_user_is_platform_admin()
        or exists (
          select 1
          from collection_members m
          where m.collection_id = c.id
            and m.user_id = user_uuid
            and m.status = 'active'
        )
      )
  );
$$;

create or replace function public.user_can_ingest_receiver_sms(
  receiver_hash text default null,
  collection uuid default null,
  user_uuid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from collection_receivers cr
    where cr.is_active
      and (collection is null or cr.collection_id = collection)
      and (receiver_hash is null or cr.momo_number_hash = receiver_hash)
      and (
        cr.receiver_user_id = user_uuid
        or public.user_is_collection_admin(cr.collection_id, user_uuid)
      )
  );
$$;

create or replace function create_collection_with_owner(
  title text,
  description text,
  category text,
  target_amount_rwf bigint default null,
  receiver_momo_number text default null,
  receiver_momo_number_hash text default null,
  receiver_label text default 'Primary MOMO receiver',
  cover_image_url text default null,
  is_recurring boolean default false,
  recurring_rule jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_collection_id uuid;
  base_slug text;
  final_slug text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  base_slug := normalize_slug(title);
  if base_slug = '' then
    base_slug := 'collection';
  end if;
  final_slug := base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into collections (
    slug,
    creator_user_id,
    title,
    description,
    category,
    cover_image_url,
    target_amount_rwf,
    receiver_display_label,
    is_recurring,
    recurring_rule
  )
  values (
    final_slug,
    auth.uid(),
    title,
    coalesce(description, ''),
    category,
    nullif(cover_image_url, ''),
    target_amount_rwf,
    receiver_label,
    coalesce(is_recurring, false),
    recurring_rule
  )
  returning id into created_collection_id;

  insert into collection_members (collection_id, user_id, role, status)
  values (created_collection_id, auth.uid(), 'owner', 'active');

  if receiver_momo_number is not null and receiver_momo_number_hash is not null then
    insert into collection_receivers (collection_id, receiver_user_id, momo_number, momo_number_hash, label)
    values (created_collection_id, auth.uid(), receiver_momo_number, receiver_momo_number_hash, receiver_label);
  end if;

  if coalesce(is_recurring, false) then
    insert into recurring_periods (
      collection_id,
      period_start,
      period_end,
      expected_amount_rwf,
      status
    )
    values (
      created_collection_id,
      current_date,
      current_date + interval '1 month' - interval '1 day',
      target_amount_rwf,
      'open'
    );
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id)
  values (auth.uid(), 'collection.created', 'collection', created_collection_id);

  return created_collection_id;
end;
$$;

create or replace function generate_contribution_code()
returns text
language plpgsql
as $$
declare
  candidate text;
begin
  loop
    candidate := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    exit when not exists (select 1 from payment_intents where contribution_code = candidate);
  end loop;
  return candidate;
end;
$$;

create or replace function create_collection_invite(
  collection uuid,
  target_phone_hash text default null,
  target_public_id text default null,
  invite_role member_role default 'member'
)
returns table (
  id uuid,
  invite_token text,
  invite_token_hash text,
  expires_at timestamptz,
  role member_role
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  plain_token text;
  hashed_token text;
  invite_id uuid;
  target_user_id uuid;
  invite_expires_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can invite members';
  end if;

  if invite_role = 'owner' then
    raise exception 'Owner role cannot be granted by invite';
  end if;

  if target_phone_hash is null and target_public_id is null then
    raise exception 'Invite requires a phone number or Collect public ID';
  end if;

  if target_public_id is not null then
    if target_public_id !~ '^[0-9]{6}$' then
      raise exception 'Collect public ID must be 6 digits';
    end if;

    select p.id into target_user_id
    from profiles p
    where p.public_id::text = target_public_id;
  end if;

  plain_token := encode(gen_random_bytes(18), 'hex');
  hashed_token := encode(digest(plain_token, 'sha256'), 'hex');

  insert into collection_invites (
    collection_id,
    invite_token_hash,
    invited_by,
    invited_phone_hash,
    role
  )
  values (
    collection,
    hashed_token,
    auth.uid(),
    target_phone_hash,
    invite_role
  )
  returning collection_invites.id, collection_invites.expires_at
    into invite_id, invite_expires_at;

  if target_user_id is not null then
    insert into collection_members (collection_id, user_id, role, status)
    values (collection, target_user_id, invite_role, 'invited')
    on conflict on constraint collection_members_collection_id_user_id_role_key do update
      set status = 'invited';
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'collection.invite_created',
    'collection',
    collection,
    jsonb_build_object(
      'role', invite_role,
      'target_public_id_present', target_public_id is not null,
      'target_phone_hash_present', target_phone_hash is not null
    )
  );

  return query select
    invite_id,
    plain_token,
    hashed_token,
    invite_expires_at,
    invite_role;
end;
$$;

create or replace function create_payment_intent(
  collection uuid,
  expected_amount_rwf bigint default null,
  sender_phone_hash text default null,
  anonymity_choice text default 'anonymous'
)
returns payment_intents
language plpgsql
security definer
set search_path = public
as $$
declare
  receiver_hash text;
  intent payment_intents;
begin
  if not public.user_can_read_collection(collection, auth.uid()) then
    raise exception 'Collection is not available';
  end if;

  select cr.momo_number_hash
    into receiver_hash
  from collection_receivers cr
  where cr.collection_id = collection and cr.is_active
  order by cr.created_at
  limit 1;

  if receiver_hash is null then
    raise exception 'Collection has no active receiver';
  end if;

  insert into payment_intents (
    collection_id,
    contributor_user_id,
    contribution_code,
    expected_amount_rwf,
    receiver_momo_number_hash,
    sender_phone_hash,
    anonymity_choice
  )
  values (
    collection,
    auth.uid(),
    generate_contribution_code(),
    expected_amount_rwf,
    receiver_hash,
    sender_phone_hash,
    anonymity_choice
  )
  returning * into intent;

  return intent;
end;
$$;

create or replace function create_payment_intent_with_instructions(
  collection uuid,
  p_expected_amount_rwf bigint default null,
  p_sender_phone_hash text default null,
  p_anonymity_choice text default 'anonymous'
)
returns table (
  id uuid,
  collection_id uuid,
  contribution_code text,
  expected_amount_rwf bigint,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  network text,
  instruction_title text,
  instruction_body text,
  sender_phone_hash text,
  status payment_intent_status,
  anonymity_choice text,
  reported_transaction_id text,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  receiver_row collection_receivers;
  intent_row payment_intents;
  template_row payment_instruction_templates;
begin
  if not public.user_can_read_collection(collection, auth.uid()) then
    raise exception 'Collection is not available';
  end if;

  select *
    into receiver_row
  from collection_receivers cr
  where cr.collection_id = collection and cr.is_active
  order by cr.created_at
  limit 1;

  if receiver_row.id is null then
    raise exception 'Collection has no active receiver';
  end if;

  select *
    into template_row
  from payment_instruction_templates pit
  where pit.is_active
    and pit.network in (receiver_row.network, 'unknown')
  order by case when pit.network = receiver_row.network then 0 else 1 end, pit.created_at
  limit 1;

  insert into payment_intents (
    collection_id,
    contributor_user_id,
    contribution_code,
    expected_amount_rwf,
    receiver_momo_number_hash,
    sender_phone_hash,
    anonymity_choice
  )
  values (
    collection,
    auth.uid(),
    generate_contribution_code(),
    p_expected_amount_rwf,
    receiver_row.momo_number_hash,
    p_sender_phone_hash,
    p_anonymity_choice
  )
  returning * into intent_row;

  return query select
    intent_row.id,
    intent_row.collection_id,
    intent_row.contribution_code,
    intent_row.expected_amount_rwf,
    receiver_row.momo_number,
    intent_row.receiver_momo_number_hash,
    receiver_row.label,
    receiver_row.network,
    coalesce(template_row.title, 'Mobile money USSD'),
    replace(
      replace(
        replace(
          coalesce(
            template_row.body_template,
            'Use your mobile-money USSD menu, send {{amount}} to {{receiver_number}}, and include {{code}} as the reason/reference when supported.'
          ),
          '{{amount}}',
          coalesce(intent_row.expected_amount_rwf::text || ' RWF', 'the selected amount')
        ),
        '{{receiver_number}}',
        receiver_row.momo_number
      ),
      '{{code}}',
      intent_row.contribution_code
    ),
    intent_row.sender_phone_hash,
    intent_row.status,
    intent_row.anonymity_choice,
    intent_row.reported_transaction_id,
    intent_row.created_at,
    intent_row.expires_at;
end;
$$;

create or replace function report_payment_intent_paid(
  intent uuid,
  transaction_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  intent_row payment_intents;
  cleaned_transaction_id text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into intent_row
  from payment_intents
  where id = intent
  for update;

  if not found then
    raise exception 'Payment intent not found';
  end if;

  if intent_row.contributor_user_id is distinct from auth.uid()
     and not public.user_is_collection_admin(intent_row.collection_id, auth.uid()) then
    raise exception 'Not authorized to report this payment intent';
  end if;

  if intent_row.status <> 'pending' then
    raise exception 'Only pending payment intents can be reported paid';
  end if;

  cleaned_transaction_id := nullif(upper(trim(coalesce(transaction_id, ''))), '');

  update payment_intents
    set reported_transaction_id = cleaned_transaction_id
    where id = intent;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'payment_intent.reported_paid',
    'payment_intent',
    intent,
    jsonb_build_object('transaction_id_present', cleaned_transaction_id is not null)
  );
end;
$$;

create or replace function post_payment_from_event(
  event_id uuid,
  intent_id uuid,
  target_collection_id uuid,
  method text,
  allocation_reason text,
  actor uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row parsed_payment_events;
  intent_row payment_intents;
  receiver_id uuid;
  contributor_id uuid;
  contributor_pid char(6);
  anonymity text := 'anonymous';
  payment_id uuid;
begin
  select * into event_row from parsed_payment_events where id = event_id for update;
  if not found then
    raise exception 'Parsed event not found';
  end if;

  if event_row.allocation_status = 'allocated' then
    select p.id into payment_id from payments p where p.parsed_event_id = event_id;
    return payment_id;
  end if;

  if event_row.transaction_id is not null and exists (select 1 from payments where transaction_id = event_row.transaction_id) then
    update parsed_payment_events
      set allocation_status = 'allocated', review_reason = 'Duplicate transaction already posted'
      where id = event_id;
    select p.id into payment_id from payments p where p.transaction_id = event_row.transaction_id;
    return payment_id;
  end if;

  if intent_id is not null then
    select * into intent_row from payment_intents where id = intent_id for update;
    if not found then
      raise exception 'Payment intent not found';
    end if;
    if intent_row.collection_id <> target_collection_id then
      raise exception 'Payment intent does not belong to target collection';
    end if;
    contributor_id := intent_row.contributor_user_id;
    anonymity := intent_row.anonymity_choice;
  end if;

  if not exists (
    select 1
    from collection_receivers cr
    where cr.collection_id = target_collection_id
      and cr.is_active
      and cr.receiver_user_id = event_row.receiver_user_id
      and (
        event_row.receiver_phone_hash is null
        or cr.momo_number_hash = event_row.receiver_phone_hash
      )
  ) then
    raise exception 'Parsed event receiver is not configured for target collection';
  end if;

  select cr.receiver_user_id
    into receiver_id
  from collection_receivers cr
  where cr.collection_id = target_collection_id
    and cr.momo_number_hash = coalesce(event_row.receiver_phone_hash, event_row.parsed_json->>'receiver_momo_number_hash', intent_row.receiver_momo_number_hash)
  order by cr.created_at
  limit 1;

  receiver_id := coalesce(receiver_id, event_row.receiver_user_id);

  if contributor_id is not null then
    select public_id into contributor_pid from profiles where id = contributor_id;
  elsif event_row.detected_user_public_id is not null then
    select id, public_id into contributor_id, contributor_pid
    from profiles
    where public_id = event_row.detected_user_public_id::char(6);
  end if;

  insert into payments (
    parsed_event_id,
    payment_intent_id,
    collection_id,
    contributor_user_id,
    contributor_public_id,
    receiver_user_id,
    receiver_momo_number_hash,
    amount_rwf,
    transaction_id,
    source,
    anonymity_choice
  )
  values (
    event_id,
    intent_id,
    target_collection_id,
    contributor_id,
    contributor_pid,
    receiver_id,
    coalesce(event_row.receiver_phone_hash, intent_row.receiver_momo_number_hash, 'unknown'),
    event_row.amount_rwf,
    event_row.transaction_id,
    case when actor is null then 'sms_auto' else 'manual_admin' end,
    anonymity
  )
  returning id into payment_id;

  insert into payment_allocations (
    payment_id,
    parsed_event_id,
    collection_id,
    payment_intent_id,
    allocated_by,
    allocation_method,
    confidence,
    reason
  )
  values (
    payment_id,
    event_id,
    target_collection_id,
    intent_id,
    actor,
    method,
    event_row.confidence,
    allocation_reason
  );

  insert into ledger_entries (
    payment_id,
    collection_id,
    user_id,
    entry_type,
    amount_rwf,
    visibility,
    metadata
  )
  values (
    payment_id,
    target_collection_id,
    contributor_id,
    'collection_credit',
    event_row.amount_rwf,
    'public_safe',
    jsonb_build_object('allocation_method', method, 'parsed_event_id', event_id)
  );

  update parsed_payment_events
    set allocation_status = 'allocated', review_reason = allocation_reason
    where id = event_id;

  if intent_id is not null then
    update payment_intents set status = 'matched' where id = intent_id;
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    actor,
    case when actor is null then 'payment.allocated.auto' else 'payment.allocated.manual' end,
    'payment',
    payment_id,
    jsonb_build_object('parsed_event_id', event_id, 'method', method)
  );

  return payment_id;
end;
$$;

create or replace function allocate_parsed_payment_event(event_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row parsed_payment_events;
  match_intent_id uuid;
  match_collection_id uuid;
  possible_count int;
begin
  select * into event_row from parsed_payment_events where id = event_id for update;
  if not found then
    raise exception 'Parsed event not found';
  end if;

  if event_row.allocation_status = 'allocated' then
    return 'already_allocated';
  end if;

  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.confidence < 0.72 then
    update parsed_payment_events
      set allocation_status = 'needs_review',
          review_reason = 'Parser result is not sufficiently reliable for auto allocation'
      where id = event_id;
    return 'needs_review';
  end if;

  if event_row.transaction_id is not null then
    select id, collection_id into match_intent_id, match_collection_id
    from payment_intents
    where status = 'pending'
      and reported_transaction_id = event_row.transaction_id
    order by created_at
    limit 1;
    if match_intent_id is not null then
      perform post_payment_from_event(event_id, match_intent_id, match_collection_id, 'auto_exact_txn', 'Matched by contributor-reported transaction ID');
      return 'allocated';
    end if;
  end if;

  if event_row.detected_collection_code is not null then
    select id, collection_id into match_intent_id, match_collection_id
    from payment_intents
    where status = 'pending'
      and contribution_code = upper(event_row.detected_collection_code)
    limit 1;
    if match_intent_id is not null then
      perform post_payment_from_event(event_id, match_intent_id, match_collection_id, 'auto_code', 'Matched by contribution code');
      return 'allocated';
    end if;
  end if;

  if event_row.sender_phone_hash is not null and event_row.receiver_phone_hash is not null then
    select id, collection_id into match_intent_id, match_collection_id
    from payment_intents
    where status = 'pending'
      and receiver_momo_number_hash = event_row.receiver_phone_hash
      and expected_amount_rwf = event_row.amount_rwf
      and sender_phone_hash = event_row.sender_phone_hash
      and event_row.created_at between created_at - interval '15 minutes' and expires_at + interval '2 hours'
    order by created_at
    limit 1;
    if match_intent_id is not null then
      perform post_payment_from_event(event_id, match_intent_id, match_collection_id, 'auto_phone_amount_time', 'Matched by receiver, amount, sender phone hash, and time window');
      return 'allocated';
    end if;
  end if;

  if event_row.receiver_phone_hash is not null then
    select
      count(*),
      (array_agg(id order by created_at))[1],
      (array_agg(collection_id order by created_at))[1]
      into possible_count, match_intent_id, match_collection_id
    from payment_intents
    where status = 'pending'
      and receiver_momo_number_hash = event_row.receiver_phone_hash
      and expected_amount_rwf = event_row.amount_rwf
      and event_row.created_at between created_at - interval '15 minutes' and expires_at + interval '2 hours';

    if possible_count = 1 then
      perform post_payment_from_event(event_id, match_intent_id, match_collection_id, 'auto_unique_amount_time', 'Matched as the only plausible pending intent in time window');
      return 'allocated';
    elsif possible_count > 1 then
      update parsed_payment_events
        set allocation_status = 'ambiguous', review_reason = 'Multiple plausible payment intents matched receiver, amount, and time window'
        where id = event_id;
      return 'ambiguous';
    end if;
  end if;

  update parsed_payment_events
    set allocation_status = 'needs_review', review_reason = 'No deterministic match found'
    where id = event_id;
  return 'needs_review';
end;
$$;

create or replace function manual_allocate_parsed_payment_event(
  event_id uuid,
  target_collection_id uuid,
  target_payment_intent_id uuid default null,
  reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if coalesce(trim(reason), '') = '' then
    raise exception 'Manual allocation reason is required';
  end if;
  if not public.user_is_collection_admin(target_collection_id, auth.uid()) then
    raise exception 'Only collection admins can allocate payments';
  end if;
  return post_payment_from_event(event_id, target_payment_intent_id, target_collection_id, 'manual', reason, auth.uid());
end;
$$;

create or replace function request_public_collection(collection uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  request_id uuid;
begin
  if not public.user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can request public listing';
  end if;

  update collections
    set public_status = 'public_requested', visibility = 'public_requested'
    where id = collection;

  insert into public_collection_requests (collection_id, requested_by)
  values (collection, auth.uid())
  returning id into request_id;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id)
  values (auth.uid(), 'collection.public_requested', 'collection', collection);

  return request_id;
end;
$$;

create or replace function review_public_collection(
  request_id uuid,
  approved boolean,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public_collection_requests;
begin
  if not public.current_user_is_platform_admin() then
    raise exception 'Platform admin required';
  end if;

  select * into request_row
  from public_collection_requests
  where id = request_id
  for update;

  if not found then
    raise exception 'Public collection request not found';
  end if;

  update public_collection_requests
    set status = case when approved then 'approved' else 'rejected' end,
        admin_user_id = auth.uid(),
        admin_note = p_admin_note,
        reviewed_at = now()
    where id = request_id;

  update collections
    set public_status = case when approved then 'public_approved'::collection_visibility else 'public_rejected'::collection_visibility end,
        visibility = case when approved then 'public_approved'::collection_visibility else 'private'::collection_visibility end
    where id = request_row.collection_id;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    case when approved then 'collection.public_approved' else 'collection.public_rejected' end,
    'collection',
    request_row.collection_id,
    jsonb_build_object('request_id', request_id, 'admin_note', p_admin_note)
  );
end;
$$;

create or replace function prevent_ledger_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Ledger entries are immutable';
end;
$$;

create trigger ledger_entries_prevent_update before update on ledger_entries
for each row execute function prevent_ledger_mutation();

create trigger ledger_entries_prevent_delete before delete on ledger_entries
for each row execute function prevent_ledger_mutation();

create view public_profiles_view
as
select
  id,
  public_id,
  case
    when anonymity_default = 'display_name' and nullif(display_name, '') is not null then display_name
    when anonymity_default = 'anonymous' then 'Anonymous supporter'
    else 'User #' || public_id
  end as display_alias,
  case when anonymity_default = 'display_name' then avatar_url else null end as avatar_url,
  created_at
from profiles;

create view collection_summary_view
as
select
  c.id as collection_id,
  coalesce(sum(le.amount_rwf) filter (where le.entry_type = 'collection_credit'), 0)::bigint as amount_raised_rwf,
  count(distinct p.id)::bigint as payment_count,
  count(distinct coalesce(p.contributor_user_id::text, p.transaction_id, p.id::text))::bigint as supporter_count
from collections c
left join ledger_entries le on le.collection_id = c.id
left join payments p on p.id = le.payment_id
where c.public_status = 'public_approved'
  and c.archived_at is null
group by c.id;

create view public_collections_view
as
select
  c.id,
  c.slug,
  c.title,
  c.description,
  c.category,
  c.cover_image_url,
  c.target_amount_rwf,
  c.deadline_at,
  c.is_recurring,
  c.created_at,
  pp.display_alias as creator_display_alias,
  csv.amount_raised_rwf,
  csv.supporter_count
from collections c
join public_profiles_view pp on pp.id = c.creator_user_id
join collection_summary_view csv on csv.collection_id = c.id
where c.public_status = 'public_approved'
  and c.archived_at is null;

create view public_contributions_view
as
select
  p.collection_id,
  p.id as payment_id,
  p.amount_rwf,
  p.posted_at,
  case
    when p.anonymity_choice = 'display_name' and p.contributor_user_id is not null then coalesce(pr.display_name, 'User #' || pr.public_id)
    when p.anonymity_choice = 'public_id' and p.contributor_public_id is not null then 'User #' || p.contributor_public_id
    else 'Anonymous supporter'
  end as supporter_label
from payments p
left join profiles pr on pr.id = p.contributor_user_id
join collections c on c.id = p.collection_id
where c.public_status = 'public_approved'
  and p.status = 'posted';

create view member_collection_summary_view
as
select
  c.id as collection_id,
  c.title,
  c.category,
  c.visibility,
  c.public_status,
  c.creator_user_id,
  (
    select coalesce(sum(le.amount_rwf) filter (where le.entry_type = 'collection_credit'), 0)::bigint
    from ledger_entries le
    where le.collection_id = c.id
  ) as amount_raised_rwf,
  (
    select count(distinct coalesce(p.contributor_user_id::text, p.transaction_id, p.id::text))::bigint
    from payments p
    where p.collection_id = c.id
  ) as supporter_count,
  (
    select count(pi.id)::bigint
    from payment_intents pi
    where pi.collection_id = c.id
      and pi.status = 'pending'
  ) as pending_intent_count,
  (
    select count(distinct ppe.id)::bigint
    from collection_receivers cr
    join parsed_payment_events ppe
      on ppe.receiver_user_id = cr.receiver_user_id
     and (
       ppe.collection_id = c.id
       or (
         ppe.collection_id is null
         and ppe.receiver_phone_hash = cr.momo_number_hash
       )
     )
    where cr.collection_id = c.id
      and ppe.allocation_status in ('needs_review', 'ambiguous')
  ) as review_event_count
from collections c
where public.user_can_read_collection(c.id, auth.uid());

create view parsed_payment_events_review_view
as
select distinct on (ppe.id, coalesce(ppe.collection_id, cr.collection_id))
  ppe.id,
  coalesce(ppe.collection_id, cr.collection_id) as collection_id,
  ppe.raw_sms_id,
  ppe.receiver_user_id,
  ppe.is_mobile_money_payment,
  ppe.network,
  ppe.direction,
  ppe.amount_rwf,
  ppe.currency,
  ppe.transaction_id,
  ppe.sender_name,
  ppe.transaction_time,
  ppe.detected_collection_code,
  ppe.detected_user_public_id,
  ppe.confidence,
  ppe.parser_model,
  ppe.parser_schema_version,
  ppe.allocation_status,
  ppe.review_reason,
  ppe.created_at
from parsed_payment_events ppe
left join collection_receivers cr
  on cr.receiver_user_id = ppe.receiver_user_id
 and cr.is_active
 and ppe.collection_id is null
 and ppe.receiver_phone_hash = cr.momo_number_hash
where (
  ppe.collection_id is not null
  and public.user_can_read_collection(ppe.collection_id, auth.uid())
)
or (
  ppe.collection_id is null
  and cr.collection_id is not null
  and public.user_can_read_collection(cr.collection_id, auth.uid())
);

alter table profiles enable row level security;
alter table collections enable row level security;
alter table collection_members enable row level security;
alter table collection_receivers enable row level security;
alter table payment_instruction_templates enable row level security;
alter table collection_invites enable row level security;
alter table payment_intents enable row level security;
alter table raw_payment_sms enable row level security;
alter table parsed_payment_events enable row level security;
alter table payments enable row level security;
alter table payment_allocations enable row level security;
alter table ledger_entries enable row level security;
alter table recurring_periods enable row level security;
alter table member_obligations enable row level security;
alter table public_collection_requests enable row level security;
alter table collection_reports enable row level security;
alter table receiver_mode_consents enable row level security;
alter table otp_rate_limits enable row level security;
alter table audit_logs enable row level security;

create policy "profiles read safe columns" on profiles
for select
using (true);

create policy "profiles update own non-admin" on profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "profiles service insert" on profiles
for insert to service_role
with check (true);

create policy "collections read public or member" on collections
for select
using (public_status = 'public_approved' or public.user_can_read_collection(id, auth.uid()));

create policy "collections insert authenticated" on collections
for insert to authenticated
with check (creator_user_id = auth.uid() and visibility = 'private');

create policy "collections update admins" on collections
for update to authenticated
using (public.user_is_collection_admin(id, auth.uid()))
with check (public.user_is_collection_admin(id, auth.uid()));

create policy "members read scoped" on collection_members
for select to authenticated
using (public.user_can_read_collection(collection_id, auth.uid()));

create policy "members manage admins" on collection_members
for all to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()))
with check (public.user_is_collection_admin(collection_id, auth.uid()));

create policy "receivers read collection admins" on collection_receivers
for select to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()) or receiver_user_id = auth.uid());

create policy "receivers manage admins" on collection_receivers
for all to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()))
with check (public.user_is_collection_admin(collection_id, auth.uid()));

create policy "payment instructions read active" on payment_instruction_templates
for select
using (is_active);

create policy "payment instructions platform admin manage" on payment_instruction_templates
for all to authenticated
using (public.current_user_is_platform_admin())
with check (public.current_user_is_platform_admin());

create policy "invites read admins" on collection_invites
for select to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()));

create policy "invites manage admins" on collection_invites
for all to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()))
with check (public.user_is_collection_admin(collection_id, auth.uid()));

create policy "payment intents read contributor or admin" on payment_intents
for select to authenticated
using (contributor_user_id = auth.uid() or public.user_is_collection_admin(collection_id, auth.uid()));

create policy "payment intents create contributor" on payment_intents
for insert to authenticated
with check (contributor_user_id = auth.uid() and public.user_can_read_collection(collection_id, auth.uid()));

create policy "raw sms service writes" on raw_payment_sms
for all to service_role
using (true)
with check (true);

create policy "raw sms receiver own read" on raw_payment_sms
for select to authenticated
using (receiver_user_id = auth.uid() or public.current_user_is_platform_admin());

create policy "parsed events receiver or admin read" on parsed_payment_events
for select to authenticated
using (receiver_user_id = auth.uid() or public.current_user_is_platform_admin());

create policy "parsed events service writes" on parsed_payment_events
for all to service_role
using (true)
with check (true);

create policy "payments read scoped" on payments
for select to authenticated
using (
  contributor_user_id = auth.uid()
  or public.user_is_collection_admin(collection_id, auth.uid())
);

create policy "payments service writes" on payments
for all to service_role
using (true)
with check (true);

create policy "allocations read collection admins" on payment_allocations
for select to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()) or public.current_user_is_platform_admin());

create policy "allocations service writes" on payment_allocations
for all to service_role
using (true)
with check (true);

create policy "ledger read scoped" on ledger_entries
for select to authenticated
using (
  user_id = auth.uid()
  or public.user_is_collection_admin(collection_id, auth.uid())
);

create policy "ledger service writes" on ledger_entries
for insert to service_role
with check (true);

create policy "recurring periods read scoped" on recurring_periods
for select to authenticated
using (public.user_can_read_collection(collection_id, auth.uid()));

create policy "recurring periods manage admins" on recurring_periods
for all to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()))
with check (public.user_is_collection_admin(collection_id, auth.uid()));

create policy "obligations read own or admin" on member_obligations
for select to authenticated
using (user_id = auth.uid() or public.user_is_collection_admin(collection_id, auth.uid()));

create policy "obligations manage admins" on member_obligations
for all to authenticated
using (public.user_is_collection_admin(collection_id, auth.uid()))
with check (public.user_is_collection_admin(collection_id, auth.uid()));

create policy "public requests read requester or admin" on public_collection_requests
for select to authenticated
using (requested_by = auth.uid() or public.current_user_is_platform_admin() or public.user_is_collection_admin(collection_id, auth.uid()));

create policy "public requests insert requester" on public_collection_requests
for insert to authenticated
with check (requested_by = auth.uid() and public.user_is_collection_admin(collection_id, auth.uid()));

create policy "public requests admin update" on public_collection_requests
for update to authenticated
using (public.current_user_is_platform_admin())
with check (public.current_user_is_platform_admin());

create policy "reports read admins" on collection_reports
for select to authenticated
using (public.current_user_is_platform_admin() or public.user_is_collection_admin(collection_id, auth.uid()) or reporter_user_id = auth.uid());

create policy "reports insert authenticated" on collection_reports
for insert to authenticated
with check (reporter_user_id = auth.uid());

create policy "reports update platform admin" on collection_reports
for update to authenticated
using (public.current_user_is_platform_admin())
with check (public.current_user_is_platform_admin());

create policy "receiver consents own" on receiver_mode_consents
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "otp rate limit service only" on otp_rate_limits
for all to service_role
using (true)
with check (true);

create policy "audit logs platform or scoped collection admins" on audit_logs
for select to authenticated
using (
  public.current_user_is_platform_admin()
  or (
    entity_type = 'collection'
    and entity_id is not null
    and public.user_is_collection_admin(entity_id, auth.uid())
  )
);

create policy "audit logs service writes" on audit_logs
for insert to service_role
with check (true);

revoke all on profiles from anon, authenticated;
revoke all on payment_intents from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant update (display_name, avatar_url, momo_number, momo_number_hash, anonymity_default, updated_at) on profiles to authenticated;
grant select on payment_intents to authenticated;
grant select on public_collections_view, public_contributions_view, collection_summary_view, public_profiles_view to anon, authenticated;
grant select on payment_instruction_templates to anon, authenticated;
grant select on member_collection_summary_view, parsed_payment_events_review_view to authenticated;
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
