-- ============================================================================
-- Rayon Sports FC reconciliation + schema normalization
-- ============================================================================

insert into public.partners (
  name,
  category,
  country,
  description,
  fan_count,
  club_count,
  game_count
)
select
  'Rayon Sports FC',
  'football',
  'RW',
  'Gikundiro supporter services: registry, clubs, initiatives, tickets, and shop.',
  0,
  0,
  0
where not exists (
  select 1
  from public.partners
  where lower(name) in ('rayon sports fc', 'rayon sports')
);

-- ── Align tables created by the earlier migration with the later app model ──

alter table public.rs_fan_memberships
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.rs_fan_memberships
set
  created_at = coalesce(created_at, joined_at, now()),
  updated_at = coalesce(updated_at, joined_at, now());

alter table public.rs_fan_clubs
  add column if not exists updated_at timestamptz not null default now();

update public.rs_fan_clubs
set updated_at = coalesce(updated_at, created_at, now());

alter table public.rs_shop_products
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.rs_shop_products
set
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, created_at, now());

alter table public.rs_shop_orders
  add column if not exists updated_at timestamptz not null default now();

update public.rs_shop_orders
set updated_at = coalesce(updated_at, created_at, now());

alter table public.rs_initiatives
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.rs_initiatives
set
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, created_at, now());

alter table public.rs_initiative_contributions
  add column if not exists updated_at timestamptz not null default now();

update public.rs_initiative_contributions
set updated_at = coalesce(updated_at, created_at, now());

alter table public.rs_matches
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.rs_matches
set
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, created_at, now());

alter table public.rs_tickets
  add column if not exists updated_at timestamptz not null default now();

update public.rs_tickets
set updated_at = coalesce(updated_at, purchased_at, now());

alter table public.rs_tickets
  alter column qr_code drop not null;

alter table public.rs_shop_orders
  drop constraint if exists rs_shop_orders_status_check;

alter table public.rs_shop_orders
  add constraint rs_shop_orders_status_check
  check (
    status in (
      'pending',
      'paid',
      'confirmed',
      'packed',
      'fulfilled',
      'cancelled'
    )
  );

alter table public.rs_tickets
  drop constraint if exists rs_tickets_status_check;

alter table public.rs_tickets
  add constraint rs_tickets_status_check
  check (status in ('pending', 'valid', 'used', 'cancelled'));

create index if not exists idx_rs_shop_orders_momo_reference
  on public.rs_shop_orders (momo_reference)
  where momo_reference is not null;

create index if not exists idx_rs_initiative_contributions_momo_reference
  on public.rs_initiative_contributions (momo_reference)
  where momo_reference is not null;

create index if not exists idx_rs_tickets_momo_reference
  on public.rs_tickets (momo_reference)
  where momo_reference is not null;

-- ── Membership tier + points automation ────────────────────────────────────

create or replace function public.rs_membership_tier_for_points(p_points int)
returns text
language sql
immutable
as $$
  select case
    when greatest(coalesce(p_points, 0), 0) >= 5000 then 'platinum'
    when greatest(coalesce(p_points, 0), 0) >= 2000 then 'gold'
    when greatest(coalesce(p_points, 0), 0) >= 1000 then 'silver'
    else 'blue'
  end;
$$;

create or replace function public.rs_sync_membership_fields()
returns trigger
language plpgsql
as $$
begin
  new.points := greatest(coalesce(new.points, 0), 0);
  new.tier := public.rs_membership_tier_for_points(new.points);

  if new.chapter is null or btrim(new.chapter) = '' then
    new.chapter := 'Kigali Central';
  end if;

  if new.membership_number is null or btrim(new.membership_number) = '' then
    new.membership_number := 'RS-' ||
      to_char(coalesce(new.joined_at, now()), 'YYYY') ||
      '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  end if;

  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
    new.joined_at := coalesce(new.joined_at, new.created_at, now());
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_rs_fan_memberships_sync_fields
  on public.rs_fan_memberships;

create trigger trg_rs_fan_memberships_sync_fields
  before insert or update on public.rs_fan_memberships
  for each row
  execute function public.rs_sync_membership_fields();

drop trigger if exists trg_rs_fan_clubs_set_updated_at on public.rs_fan_clubs;
create trigger trg_rs_fan_clubs_set_updated_at
  before update on public.rs_fan_clubs
  for each row
  execute function public.set_updated_at();

drop trigger if exists trg_rs_shop_products_set_updated_at on public.rs_shop_products;
create trigger trg_rs_shop_products_set_updated_at
  before update on public.rs_shop_products
  for each row
  execute function public.set_updated_at();

drop trigger if exists trg_rs_shop_orders_set_updated_at on public.rs_shop_orders;
create trigger trg_rs_shop_orders_set_updated_at
  before update on public.rs_shop_orders
  for each row
  execute function public.set_updated_at();

drop trigger if exists trg_rs_initiatives_set_updated_at on public.rs_initiatives;
create trigger trg_rs_initiatives_set_updated_at
  before update on public.rs_initiatives
  for each row
  execute function public.set_updated_at();

drop trigger if exists trg_rs_initiative_contributions_set_updated_at
  on public.rs_initiative_contributions;
create trigger trg_rs_initiative_contributions_set_updated_at
  before update on public.rs_initiative_contributions
  for each row
  execute function public.set_updated_at();

drop trigger if exists trg_rs_matches_set_updated_at on public.rs_matches;
create trigger trg_rs_matches_set_updated_at
  before update on public.rs_matches
  for each row
  execute function public.set_updated_at();

drop trigger if exists trg_rs_tickets_set_updated_at on public.rs_tickets;
create trigger trg_rs_tickets_set_updated_at
  before update on public.rs_tickets
  for each row
  execute function public.set_updated_at();

create or replace function public.rs_apply_membership_points(
  p_user_id uuid,
  p_partner_id uuid,
  p_points int,
  p_chapter text default null
)
returns public.rs_fan_memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membership public.rs_fan_memberships;
  v_chapter text := coalesce(nullif(btrim(coalesce(p_chapter, '')), ''), 'Kigali Central');
begin
  insert into public.rs_fan_memberships (
    user_id,
    partner_id,
    points,
    chapter,
    membership_number,
    joined_at,
    created_at,
    updated_at
  )
  values (
    p_user_id,
    p_partner_id,
    greatest(coalesce(p_points, 0), 0),
    v_chapter,
    'RS-' || to_char(now(), 'YYYY') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)),
    now(),
    now(),
    now()
  )
  on conflict (partner_id, user_id) do update
    set
      points = greatest(public.rs_fan_memberships.points + coalesce(p_points, 0), 0),
      chapter = coalesce(
        nullif(btrim(public.rs_fan_memberships.chapter), ''),
        excluded.chapter
      ),
      updated_at = now()
  returning * into v_membership;

  return v_membership;
end;
$$;
