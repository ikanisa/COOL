-- ============================================================================
-- Rayon Sports FC — Schema Lock Migration
-- Absorbs unique content from rs_schema.sql (seed data, partner-admin helper,
-- richer RLS, extra columns) then marks the schema stable.
-- Runs AFTER 200000 (tables) and 213000 (reconciliation / automation).
-- ============================================================================

-- ── Partner admin helper ────────────────────────────────────────────────────

create or replace function public.rs_is_partner_admin(p_partner_id uuid)
returns boolean
language sql
stable
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'is_partner_admin', 'false') = 'true'
    or coalesce(
      (auth.jwt() -> 'app_metadata' -> 'partner_admin_ids') ? p_partner_id::text,
      false
    );
$$;

-- ── Add missing columns to align with richer schema ──────────────────────────

alter table public.rs_fan_clubs
  add column if not exists event_count integer not null default 0,
  add column if not exists rating numeric(3, 2) not null default 0,
  add column if not exists banner_emoji text not null default '🥁';

do $$ begin
  alter table public.rs_fan_clubs
    add constraint rs_fan_clubs_check_event_count check (event_count >= 0);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.rs_fan_clubs
    add constraint rs_fan_clubs_check_rating check (rating >= 0 and rating <= 5);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.rs_fan_clubs
    add constraint rs_fan_clubs_unique_partner_name unique (partner_id, name);
exception when duplicate_object then null;
end $$;

alter table public.rs_shop_products
  add column if not exists bg_color text,
  add column if not exists is_new boolean not null default false;

do $$ begin
  alter table public.rs_shop_products
    add constraint rs_shop_products_unique_partner_name unique (partner_id, name);
exception when duplicate_object then null;
end $$;

alter table public.rs_achievements
  add column if not exists emoji text not null default '🏆',
  add column if not exists name text not null default '',
  add column if not exists description text not null default '',
  add column if not exists is_earned boolean not null default true;

do $$ begin
  alter table public.rs_achievements
    add constraint rs_achievements_unique_user_badge unique (user_id, partner_id, badge_type);
exception when duplicate_object then null;
end $$;

alter table public.rs_matches
  add column if not exists sale_starts_at timestamptz not null default now(),
  add column if not exists capacity integer not null default 0;

do $$ begin
  alter table public.rs_matches
    add constraint rs_matches_check_capacity check (capacity >= 0);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.rs_initiatives
    add constraint rs_initiatives_unique_partner_title unique (partner_id, title);
exception when duplicate_object then null;
end $$;

-- ── Upgrade RLS: public reads for catalog tables ─────────────────────────────

-- Products: anon + authenticated can browse
drop policy if exists "products_public_read" on public.rs_shop_products;
create policy "products_public_read"
  on public.rs_shop_products for select
  to anon, authenticated
  using (true);

-- Matches: anon + authenticated can browse
drop policy if exists "matches_public_read" on public.rs_matches;
create policy "matches_public_read"
  on public.rs_matches for select
  to anon, authenticated
  using (true);

-- Initiatives: anon + authenticated can browse
drop policy if exists "initiatives_public_read" on public.rs_initiatives;
create policy "initiatives_public_read"
  on public.rs_initiatives for select
  to anon, authenticated
  using (true);

-- Fan clubs: anon + authenticated can browse
drop policy if exists "fan_clubs_public_read" on public.rs_fan_clubs;
create policy "fan_clubs_public_read"
  on public.rs_fan_clubs for select
  to anon, authenticated
  using (true);

-- Partner admin can read all memberships (for admin panel)
drop policy if exists "partner_admin_reads_all_memberships" on public.rs_fan_memberships;
create policy "partner_admin_reads_all_memberships"
  on public.rs_fan_memberships for select
  to authenticated
  using ((select public.rs_is_partner_admin(partner_id)));

-- Fan club member delete (leave club)
drop policy if exists "fan_leaves_own_fan_club" on public.rs_fan_club_members;
create policy "fan_leaves_own_fan_club"
  on public.rs_fan_club_members for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- ── Additional indexes ─────────────────────────────────────────────────────

create index if not exists idx_rs_tickets_user_status
  on public.rs_tickets (user_id, status);

create index if not exists idx_rs_tickets_match
  on public.rs_tickets (match_id);

create index if not exists idx_rs_shop_orders_user_status
  on public.rs_shop_orders (user_id, status);

create index if not exists idx_rs_fan_memberships_user_partner
  on public.rs_fan_memberships (user_id, partner_id);

create unique index if not exists idx_rs_tickets_qr_code
  on public.rs_tickets (qr_code)
  where qr_code is not null;

-- ── Seed data: Fan clubs + Initiatives ──────────────────────────────────────

do $$
declare
  rs_partner_id uuid;
begin
  select id
  into rs_partner_id
  from public.partners
  where lower(name) in ('rayon sports fc', 'rayon sports')
  order by created_at
  limit 1;

  if rs_partner_id is null then
    raise notice 'Rayon Sports partner not found – skipping seed data.';
    return;
  end if;

  insert into public.rs_fan_clubs (
    partner_id, name, region, description,
    member_count, event_count, rating, banner_emoji
  )
  values
    (rs_partner_id, 'Gikundiro Kigali Ultra', 'Kigali',
     'The flagship Kigali chapter coordinating matchday convoys, chants, and fan mobilization.',
     420, 28, 4.90, '🏟️'),
    (rs_partner_id, 'Musanze Rayon Fans', 'Northern',
     'A northern supporters chapter known for coordinated away-day travel and drum-led support.',
     210, 16, 4.70, '🥁'),
    (rs_partner_id, 'Western Blue Wave', 'Western',
     'A western Rwanda supporters network organizing buses, fundraising, and community watch parties.',
     160, 12, 4.85, '🌍'),
    (rs_partner_id, 'Huye Blue Army', 'Southern',
     'A southern chapter driving student support, local screenings, and academy outreach.',
     185, 14, 4.60, '💙')
  on conflict (partner_id, name) do update
    set
      region = excluded.region,
      description = excluded.description,
      member_count = excluded.member_count,
      event_count = excluded.event_count,
      rating = excluded.rating,
      banner_emoji = excluded.banner_emoji;

  insert into public.rs_initiatives (
    partner_id, title, description, category,
    target_amount, raised_amount, supporter_count,
    is_active, ends_at
  )
  values
    (rs_partner_id, 'North Stand Renovation',
     'Upgrade seating, barriers, and supporter infrastructure for a louder and safer home stand.',
     'stadium', 25000000, 7800000, 612, true, now() + interval '120 days'),
    (rs_partner_id, 'Academy Equipment Drive',
     'Fund training balls, bibs, cones, and transport support for the club''s youth setup.',
     'youth', 12000000, 4100000, 338, true, now() + interval '90 days'),
    (rs_partner_id, 'Schools Football League',
     'Back a community school competition to widen the club''s local development pipeline.',
     'community', 9000000, 2950000, 241, true, now() + interval '75 days'),
    (rs_partner_id, 'Fan Kit Subsidy Program',
     'Help reduce replica kit costs for loyal fans and youth supporters ahead of major fixtures.',
     'kit', 15000000, 5300000, 402, true, now() + interval '60 days')
  on conflict (partner_id, title) do update
    set
      description = excluded.description,
      category = excluded.category,
      target_amount = excluded.target_amount,
      raised_amount = excluded.raised_amount,
      supporter_count = excluded.supporter_count,
      is_active = excluded.is_active,
      ends_at = excluded.ends_at;
end;
$$;
