-- Market-expansion foundation: approved collection categories plus
-- Stripe-safe diaspora contribution records. This is intentionally additive
-- and keeps Rwanda MoMo/SMS allocation as the default in-country rail.

alter table collections
  add column if not exists collection_type text not null default 'ikimina'
    check (collection_type in ('ikimina', 'sport', 'church', 'wedding', 'other')),
  add column if not exists category_subtype text,
  add column if not exists purpose_label text,
  add column if not exists suggested_amount_rwf bigint
    check (suggested_amount_rwf is null or suggested_amount_rwf > 0),
  add column if not exists diaspora_enabled boolean not null default false,
  add column if not exists diaspora_regions text[] not null default '{}'::text[],
  add column if not exists moderation_status text not null default 'not_requested'
    check (moderation_status in (
      'not_requested',
      'pending',
      'approved',
      'rejected',
      'restricted'
    ));

update collections
set collection_type = case
  when lower(category) = 'church' then 'church'
  when lower(category) in ('sports team', 'public figure / fan support') then 'sport'
  when lower(category) = 'wedding' then 'wedding'
  when lower(category) in ('family / friends', 'community event') then 'ikimina'
  else collection_type
end
where category is not null
  and collection_type = 'ikimina';

create index if not exists collections_market_type_idx
  on collections (collection_type, created_at desc);

create index if not exists collections_diaspora_enabled_idx
  on collections (diaspora_enabled, collection_type, created_at desc)
  where diaspora_enabled;

grant select (
  collection_type,
  category_subtype,
  purpose_label,
  suggested_amount_rwf,
  diaspora_enabled,
  diaspora_regions,
  moderation_status
) on collections to authenticated;

drop function if exists create_group_with_owner(text, text, text, text, text);

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
  clean_type text := coalesce(nullif(trim(group_collection_type), ''), 'ikimina');
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if clean_type not in ('ikimina', 'sport', 'church', 'wedding', 'other') then
    raise exception 'Unsupported collection type';
  end if;

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
    nullif(trim(group_category_subtype), ''),
    nullif(trim(group_purpose_label), ''),
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
    jsonb_build_object('collection_type', clean_type)
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

drop function if exists update_collection_profile(uuid, text, text, text, text, boolean, text);

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
  clean_type text := nullif(trim(group_collection_type), '');
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
  if clean_type is not null and clean_type not in ('ikimina', 'sport', 'church', 'wedding', 'other') then
    raise exception 'Unsupported collection type';
  end if;

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
    collection_type = coalesce(clean_type, collection_type),
    category_subtype = nullif(trim(group_category_subtype), ''),
    purpose_label = nullif(trim(group_purpose_label), ''),
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
      'collection_type', clean_type
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

drop view if exists member_collections_view;

create view member_collections_view
with (security_invoker = true)
as
select
  c.id,
  c.slug,
  c.creator_user_id,
  c.title,
  c.description,
  c.currency,
  c.collection_type,
  c.category_subtype,
  c.purpose_label,
  c.suggested_amount_rwf,
  c.diaspora_enabled,
  c.diaspora_regions,
  c.moderation_status,
  case
    when public.user_is_collection_admin(c.id, auth.uid())
      or exists (
        select 1
        from collection_receivers receiver_check
        where receiver_check.collection_id = c.id
          and receiver_check.receiver_user_id = auth.uid()
          and receiver_check.is_active
      )
      then cr.momo_number
    else null
  end as receiver_momo_number,
  case
    when public.user_can_read_collection(c.id, auth.uid()) then cr.label
    else null
  end as receiver_display_label,
  cr.network as receiver_network,
  c.created_at,
  c.updated_at,
  c.archived_at,
  c.accent_color_hex,
  c.recurring_cadence
from collections c
left join lateral (
  select
    collection_receivers.momo_number,
    collection_receivers.label,
    collection_receivers.network
  from collection_receivers
  where collection_receivers.collection_id = c.id
    and collection_receivers.is_active
  order by collection_receivers.created_at asc
  limit 1
) cr on true
where public.user_can_read_collection(c.id, auth.uid());

alter view public.member_collections_view set (security_invoker = true);
grant select on member_collections_view to authenticated;

create table if not exists stripe_customers (
  user_id uuid primary key references profiles(id) on delete cascade,
  stripe_customer_id text unique not null,
  livemode boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists stripe_payment_methods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  stripe_customer_id text not null,
  stripe_payment_method_id text unique not null,
  method_type text not null check (method_type in (
    'us_bank_account',
    'acss_debit'
  )),
  region text not null check (region in ('us', 'ca')),
  currency text not null check (currency in ('USD', 'CAD')),
  constraint stripe_payment_methods_domestic_currency_check check (
    (region = 'us' and currency = 'USD' and method_type = 'us_bank_account')
    or (region = 'ca' and currency = 'CAD' and method_type = 'acss_debit')
  ),
  display_bank_name text,
  display_last4 text,
  mandate_reference text,
  status text not null default 'pending_setup' check (status in (
    'pending_setup',
    'active',
    'inactive',
    'revoked',
    'failed'
  )),
  livemode boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists diaspora_contribution_intents (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references collections(id) on delete restrict,
  contributor_user_id uuid not null references profiles(id) on delete restrict,
  stripe_customer_id text not null,
  stripe_payment_method_id text,
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id text unique,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency in ('EUR', 'GBP', 'USD', 'CAD')),
  region text not null check (region in ('eu', 'gb', 'us', 'ca')),
  method_type text not null check (method_type in (
    'us_bank_account',
    'acss_debit',
    'customer_balance_eur_bank_transfer',
    'customer_balance_gbp_bank_transfer'
  )),
  constraint diaspora_contribution_intents_domestic_currency_check check (
    (region = 'eu' and currency = 'EUR' and method_type = 'customer_balance_eur_bank_transfer')
    or (region = 'gb' and currency = 'GBP' and method_type = 'customer_balance_gbp_bank_transfer')
    or (region = 'us' and currency = 'USD' and method_type = 'us_bank_account')
    or (region = 'ca' and currency = 'CAD' and method_type = 'acss_debit')
  ),
  collection_type_snapshot text not null check (collection_type_snapshot in (
    'ikimina',
    'sport',
    'church',
    'wedding',
    'other'
  )),
  status text not null default 'pending' check (status in (
    'pending',
    'requires_action',
    'processing',
    'succeeded',
    'failed',
    'returned',
    'disputed',
    'cancelled',
    'needs_review'
  )),
  failure_code text,
  failure_message text,
  livemode boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists stripe_webhook_events (
  event_id text primary key,
  event_type text not null,
  livemode boolean not null default false,
  related_contribution_intent_id uuid references diaspora_contribution_intents(id) on delete set null,
  processed_at timestamptz,
  processing_status text not null default 'received' check (processing_status in (
    'received',
    'processed',
    'ignored',
    'failed',
    'needs_review'
  )),
  review_reason text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists stripe_payment_methods_user_idx
  on stripe_payment_methods (user_id, region, status);

create index if not exists diaspora_contribution_intents_collection_idx
  on diaspora_contribution_intents (collection_id, status, created_at desc);

create index if not exists diaspora_contribution_intents_contributor_idx
  on diaspora_contribution_intents (contributor_user_id, status, created_at desc);

alter table stripe_customers enable row level security;
alter table stripe_payment_methods enable row level security;
alter table diaspora_contribution_intents enable row level security;
alter table stripe_webhook_events enable row level security;

drop policy if exists stripe_customers_owner_select on stripe_customers;
create policy stripe_customers_owner_select
  on stripe_customers for select
  using (user_id = (select auth.uid()));

drop policy if exists stripe_payment_methods_owner_select on stripe_payment_methods;
create policy stripe_payment_methods_owner_select
  on stripe_payment_methods for select
  using (user_id = (select auth.uid()));

drop policy if exists diaspora_contribution_intents_participant_select
  on diaspora_contribution_intents;
create policy diaspora_contribution_intents_participant_select
  on diaspora_contribution_intents for select
  using (
    contributor_user_id = (select auth.uid())
    or public.user_is_collection_admin(collection_id, (select auth.uid()))
    or public.current_user_is_platform_admin()
  );

drop policy if exists stripe_webhook_events_admin_select on stripe_webhook_events;
create policy stripe_webhook_events_admin_select
  on stripe_webhook_events for select
  using (public.current_user_is_platform_admin());

grant select on stripe_customers to authenticated;
grant select on stripe_payment_methods to authenticated;
grant select on diaspora_contribution_intents to authenticated;
grant select on stripe_webhook_events to authenticated;
grant all on stripe_customers to service_role;
grant all on stripe_payment_methods to service_role;
grant all on diaspora_contribution_intents to service_role;
grant all on stripe_webhook_events to service_role;
