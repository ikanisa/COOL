-- ==========================================================================
-- Rwanda-only runtime scope contract
-- ==========================================================================
-- Keeps legacy compatibility columns and RPC signatures intact, but hardens
-- the actual runtime contract so local app data can no longer drift back into
-- multi-country semantics.

delete from public.supported_countries
where iso_code <> 'RW';
update public.supported_countries
set
  iso_code = 'RW',
  dial_code = '+250',
  country_name = 'Rwanda',
  currency_code = 'RWF',
  currency_name = 'Rwandan franc',
  is_active = true,
  sort_order = 0,
  updated_at = now()
where iso_code = 'RW';
alter table public.users disable trigger trg_enforce_user_momo_fields;
update public.users
set
  country = 'RW',
  language_code = 'en',
  momo_number = case
    when momo_number is not null
      and public.is_valid_momo_phone_for_country('RW', momo_number) then momo_number
    else null
  end,
  momo_code = case
    when momo_code is not null
      and public.is_valid_momo_code_for_country('RW', momo_code) then momo_code
    else null
  end,
  momo_route_type = case
    when momo_number is not null
      and public.is_valid_momo_phone_for_country('RW', momo_number) then momo_route_type
    when momo_code is not null
      and public.is_valid_momo_code_for_country('RW', momo_code) then momo_route_type
    else null
  end
where
  country is distinct from 'RW'
  or language_code is distinct from 'en';
alter table public.users enable trigger trg_enforce_user_momo_fields;
alter table public.groups disable trigger trg_enforce_group_momo_fields;
update public.groups
set country = 'RW'
where country is distinct from 'RW';
alter table public.groups enable trigger trg_enforce_group_momo_fields;
update public.partners
set country = 'RW'
where country is distinct from 'RW';
update public.partner_services
set country = 'RW'
where country is distinct from 'RW';
with ranked_routes as (
  select
    id,
    row_number() over (
      partition by partner_id
      order by
        case status
          when 'active' then 0
          when 'draft' then 1
          else 2
        end,
        updated_at desc,
        created_at desc,
        id desc
    ) as rn
  from public.partner_payment_routes
)
delete from public.partner_payment_routes route
using ranked_routes ranked
where route.id = ranked.id
  and ranked.rn > 1;
update public.partner_payment_routes
set country = 'RW'
where country is distinct from 'RW';
alter table public.users
  alter column country set default 'RW';
alter table public.users
  alter column language_code set default 'en';
alter table public.groups
  alter column country set default 'RW';
alter table public.partners
  alter column country set default 'RW';
alter table public.partner_services
  alter column country set default 'RW';
alter table public.partner_payment_routes
  alter column country set default 'RW';
alter table public.supported_countries
  drop constraint if exists supported_countries_rwanda_only_check;
alter table public.supported_countries
  add constraint supported_countries_rwanda_only_check
  check (iso_code = 'RW');
alter table public.users
  drop constraint if exists users_country_rwanda_only_check;
alter table public.users
  add constraint users_country_rwanda_only_check
  check (country = 'RW');
alter table public.users
  drop constraint if exists users_language_code_english_only_check;
alter table public.users
  add constraint users_language_code_english_only_check
  check (language_code = 'en');
alter table public.groups
  drop constraint if exists groups_country_rwanda_only_check;
alter table public.groups
  add constraint groups_country_rwanda_only_check
  check (country = 'RW');
alter table public.partners
  drop constraint if exists partners_country_rwanda_only_check;
alter table public.partners
  add constraint partners_country_rwanda_only_check
  check (country = 'RW');
alter table public.partner_services
  drop constraint if exists partner_services_country_rwanda_only_check;
alter table public.partner_services
  add constraint partner_services_country_rwanda_only_check
  check (country = 'RW');
alter table public.partner_payment_routes
  drop constraint if exists partner_payment_routes_country_rwanda_only_check;
alter table public.partner_payment_routes
  add constraint partner_payment_routes_country_rwanda_only_check
  check (country = 'RW');
alter table public.quick_actions
  drop constraint if exists quick_actions_country_local_scope_check;
alter table public.quick_actions
  add constraint quick_actions_country_local_scope_check
  check (country is null or country = 'RW');
alter table public.app_config
  drop constraint if exists app_config_country_local_scope_check;
alter table public.app_config
  add constraint app_config_country_local_scope_check
  check (country is null or country = 'RW');
create or replace function public.enforce_partner_payment_route_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_country public.supported_countries;
begin
  new.country := 'RW';
  new.provider := public.normalize_partner_payment_provider(new.provider);
  new.status := lower(btrim(coalesce(new.status, 'draft')));
  new.reconciliation_label := regexp_replace(
    lower(btrim(coalesce(new.reconciliation_label, ''))),
    '[^a-z0-9]+',
    '_',
    'g'
  );
  new.reconciliation_label := btrim(new.reconciliation_label, '_');
  new.recipient_code := public.normalize_momo_code_for_country(
    new.country,
    new.recipient_code
  );

  select *
  into v_country
  from public.get_supported_country_momo_config('RW');

  if v_country.iso_code is null then
    raise exception 'Rwanda mobile money configuration is missing.';
  end if;

  if new.provider = '' then
    raise exception 'Payment provider is required.';
  end if;

  if new.reconciliation_label = '' then
    raise exception 'Reconciliation label is required.';
  end if;

  if new.status not in ('draft', 'active', 'inactive') then
    raise exception 'Invalid payment route status: %', new.status;
  end if;

  if coalesce(nullif(v_country.momo_code_ussd_template, ''), '') = '' then
    raise exception 'Merchant-code payments are not configured for Rwanda.';
  end if;

  if new.status = 'active' and new.recipient_code is null then
    raise exception 'Active payment routes require a merchant code.';
  end if;

  return new;
end;
$$;
create or replace function public.get_partner_payment_route(
  p_partner_id uuid,
  p_country text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_route record;
begin
  p_country := nullif(btrim(coalesce(p_country, '')), '');

  if p_partner_id is null then
    return null;
  end if;

  select
    ppr.id,
    ppr.partner_id,
    ppr.country,
    ppr.provider,
    ppr.recipient_code,
    ppr.reconciliation_label,
    ppr.status,
    p.name as partner_name,
    p.slug as partner_slug
  into v_route
  from public.partner_payment_routes ppr
  join public.partners p
    on p.id = ppr.partner_id
  where ppr.partner_id = p_partner_id
    and ppr.status = 'active'
    and ppr.recipient_code is not null
    and ppr.country = 'RW'
  order by ppr.updated_at desc
  limit 1;

  if v_route is null then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_route.id,
    'partner_id', v_route.partner_id,
    'partner_name', v_route.partner_name,
    'partner_slug', v_route.partner_slug,
    'country', 'RW',
    'provider', v_route.provider,
    'recipient_code', v_route.recipient_code,
    'reconciliation_label', v_route.reconciliation_label,
    'status', v_route.status
  );
end;
$$;
create or replace function public.create_group_atomic(
  p_name text,
  p_visibility text,
  p_type text,
  p_description text default null,
  p_country text default null,
  p_target_amount integer default 0,
  p_monthly_contribution integer default null,
  p_cycle_days integer default 30,
  p_bank_partner text default null,
  p_momo_number text default null,
  p_receiving_momo_code text default null,
  p_receiving_momo_route_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.users;
  v_group public.groups;
  v_invite_code text;
begin
  p_country := nullif(btrim(coalesce(p_country, '')), '');

  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select *
  into v_user
  from public.users
  where id = auth.uid();

  if v_user.id is null then
    raise exception 'Complete profile before creating a group.';
  end if;

  v_invite_code := public.generate_group_invite_code();

  insert into public.groups (
    creator_id,
    name,
    description,
    country,
    visibility,
    type,
    amount,
    target_amount,
    monthly_contribution,
    contribution_amount,
    cycle_days,
    frequency,
    bank_partner,
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    invite_code
  )
  values (
    auth.uid(),
    nullif(btrim(p_name), ''),
    nullif(btrim(coalesce(p_description, '')), ''),
    'RW',
    coalesce(nullif(btrim(coalesce(p_visibility, '')), ''), 'private'),
    coalesce(nullif(btrim(coalesce(p_type, '')), ''), 'saving'),
    0,
    coalesce(p_target_amount, 0),
    p_monthly_contribution,
    coalesce(p_monthly_contribution, p_target_amount, 0),
    greatest(coalesce(p_cycle_days, 30), 1),
    coalesce(
      nullif(
        btrim(
          case
            when p_cycle_days <= 1 then 'daily'
            when p_cycle_days <= 7 then 'weekly'
            else 'monthly'
          end
        ),
        ''
      ),
      'monthly'
    ),
    nullif(btrim(coalesce(p_bank_partner, '')), ''),
    nullif(btrim(coalesce(p_momo_number, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_code, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_route_type, '')), ''),
    v_invite_code
  )
  returning *
  into v_group;

  insert into public.group_members (
    group_id,
    user_id,
    display_name,
    is_admin,
    is_anonymous,
    contribution_amount,
    joined_at
  )
  values (
    v_group.id,
    auth.uid(),
    coalesce(nullif(btrim(v_user.public_user_id), ''), '000000'),
    true,
    false,
    0,
    now()
  )
  on conflict (group_id, user_id) do update
  set
    is_admin = true,
    display_name = excluded.display_name;

  return jsonb_build_object(
    'status', 'success',
    'group_id', v_group.id,
    'invite_code', v_invite_code
  );
exception
  when others then
    return jsonb_build_object(
      'status', 'error',
      'message', sqlerrm
    );
end;
$$;
