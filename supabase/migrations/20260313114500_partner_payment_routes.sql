-- ============================================================================
-- Cool App — Partner payment routing
-- ----------------------------------------------------------------------------
-- Admin-managed partner payment routes used by frontend checkout flows.
-- Keeps routing mutable in Supabase so recipient changes do not require an app
-- release.
-- ============================================================================

create extension if not exists pgcrypto;
create table if not exists public.partner_payment_routes (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  country text not null,
  provider text not null,
  recipient_code text,
  reconciliation_label text not null,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (partner_id, country)
);
comment on table public.partner_payment_routes is
  'Admin-managed mobile money routing per partner and country.';
comment on column public.partner_payment_routes.provider is
  'Human and app-facing provider identifier such as mtn_rwanda.';
comment on column public.partner_payment_routes.recipient_code is
  'Merchant/payment code used for USSD mobile money checkout.';
comment on column public.partner_payment_routes.reconciliation_label is
  'Stable label used to explain how receipts are reconciled.';
create index if not exists idx_partner_payment_routes_partner_status
  on public.partner_payment_routes (partner_id, status, country);
create or replace function public.normalize_partner_payment_provider(p_value text)
returns text
language sql
immutable
as $$
  select lower(btrim(coalesce(p_value, '')))
$$;
create or replace function public.enforce_partner_payment_route_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_country public.supported_countries;
begin
  new.country := public.normalize_country_code(new.country);
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
  from public.get_supported_country_momo_config(new.country);

  if v_country.iso_code is null then
    raise exception 'Unsupported country code for partner payment route: %',
      coalesce(nullif(btrim(coalesce(new.country, '')), ''), '(blank)');
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
    raise exception 'Merchant-code payments are not configured for %.',
      v_country.country_name;
  end if;

  if new.status = 'active' and new.recipient_code is null then
    raise exception 'Active payment routes require a merchant code.';
  end if;

  return new;
end;
$$;
drop trigger if exists trg_partner_payment_routes_validate
  on public.partner_payment_routes;
create trigger trg_partner_payment_routes_validate
  before insert or update on public.partner_payment_routes
  for each row
  execute function public.enforce_partner_payment_route_fields();
drop trigger if exists trg_partner_payment_routes_set_updated_at
  on public.partner_payment_routes;
create trigger trg_partner_payment_routes_set_updated_at
  before update on public.partner_payment_routes
  for each row
  execute function public.set_updated_at();
alter table public.partner_payment_routes enable row level security;
drop policy if exists partner_payment_routes_select_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_select_admin
  on public.partner_payment_routes for select
  to authenticated
  using (public.is_admin_user());
drop policy if exists partner_payment_routes_insert_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_insert_admin
  on public.partner_payment_routes for insert
  to authenticated
  with check (public.is_admin_user());
drop policy if exists partner_payment_routes_update_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_update_admin
  on public.partner_payment_routes for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());
drop policy if exists partner_payment_routes_delete_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_delete_admin
  on public.partner_payment_routes for delete
  to authenticated
  using (public.is_admin_user());
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
  v_requested_country text;
begin
  if p_partner_id is null then
    return null;
  end if;

  v_requested_country := case
    when nullif(btrim(coalesce(p_country, '')), '') is null then null
    else public.normalize_country_code(p_country)
  end;

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
    and (
      v_requested_country is null
      or ppr.country = v_requested_country
      or ppr.country = public.normalize_country_code(p.country)
    )
  order by
    case
      when v_requested_country is not null and ppr.country = v_requested_country
        then 0
      when ppr.country = public.normalize_country_code(p.country)
        then 1
      else 2
    end,
    ppr.updated_at desc
  limit 1;

  if v_route is null then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_route.id,
    'partner_id', v_route.partner_id,
    'partner_name', v_route.partner_name,
    'partner_slug', v_route.partner_slug,
    'country', v_route.country,
    'provider', v_route.provider,
    'recipient_code', v_route.recipient_code,
    'reconciliation_label', v_route.reconciliation_label,
    'status', v_route.status
  );
end;
$$;
revoke all on function public.get_partner_payment_route(uuid, text) from public;
grant execute on function public.get_partner_payment_route(uuid, text)
  to authenticated, service_role;
insert into public.partner_payment_routes (
  partner_id,
  country,
  provider,
  recipient_code,
  reconciliation_label,
  status
)
select
  p.id,
  'RW',
  'mtn_rwanda',
  '008000',
  'rayon_sports',
  'active'
from public.partners p
where p.slug = 'rayon-sports'
   or p.name = 'Rayon Sports FC'
order by case when p.slug = 'rayon-sports' then 0 else 1 end
limit 1
on conflict (partner_id, country) do update
set
  provider = excluded.provider,
  recipient_code = excluded.recipient_code,
  reconciliation_label = excluded.reconciliation_label,
  status = excluded.status,
  updated_at = now();
