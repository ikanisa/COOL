-- ==========================================================================
-- Cool App - Rayon admin finance access and membership packages
-- ==========================================================================

drop policy if exists partner_payment_routes_select_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_select_admin
  on public.partner_payment_routes for select
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
drop policy if exists partner_payment_routes_insert_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_insert_admin
  on public.partner_payment_routes for insert
  to authenticated
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
drop policy if exists partner_payment_routes_update_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_update_admin
  on public.partner_payment_routes for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
drop policy if exists partner_payment_routes_delete_admin
  on public.partner_payment_routes;
create policy partner_payment_routes_delete_admin
  on public.partner_payment_routes for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
create table if not exists public.rs_membership_packages (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  tier text not null
    check (tier in ('blue', 'silver', 'gold', 'platinum')),
  title text not null,
  subtitle text not null,
  description text,
  benefits jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (partner_id, tier)
);
create index if not exists idx_rs_membership_packages_partner
  on public.rs_membership_packages (partner_id, sort_order, tier);
drop trigger if exists trg_rs_membership_packages_set_updated_at
  on public.rs_membership_packages;
create trigger trg_rs_membership_packages_set_updated_at
  before update on public.rs_membership_packages
  for each row
  execute function public.set_updated_at();
alter table public.rs_membership_packages enable row level security;
drop policy if exists rs_membership_packages_select_authenticated
  on public.rs_membership_packages;
create policy rs_membership_packages_select_authenticated
  on public.rs_membership_packages for select
  to authenticated
  using (
    is_active
    or public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
drop policy if exists rs_membership_packages_insert_admin
  on public.rs_membership_packages;
create policy rs_membership_packages_insert_admin
  on public.rs_membership_packages for insert
  to authenticated
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
drop policy if exists rs_membership_packages_update_admin
  on public.rs_membership_packages;
create policy rs_membership_packages_update_admin
  on public.rs_membership_packages for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
drop policy if exists rs_membership_packages_delete_admin
  on public.rs_membership_packages;
create policy rs_membership_packages_delete_admin
  on public.rs_membership_packages for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );
insert into public.rs_membership_packages (
  partner_id,
  tier,
  title,
  subtitle,
  description,
  benefits,
  is_active,
  sort_order
)
select
  partner.id,
  package_seed.tier,
  package_seed.title,
  package_seed.subtitle,
  package_seed.description,
  package_seed.benefits,
  true,
  package_seed.sort_order
from (
  values
    (
      'blue',
      'Blue Membership',
      'Free - every fan starts here',
      'Entry tier for all Rayon Sports supporters.',
      '[
        {"title":"Standard Tickets","description":"Buy match tickets at regular pricing."},
        {"title":"Club Shop Access","description":"Browse and purchase official Rayon merch."},
        {"title":"Fan Points","description":"Earn points from attendance, purchases, and support."}
      ]'::jsonb,
      0
    ),
    (
      'silver',
      'Silver Membership',
      '1,000 pts - dedicated supporter',
      'Priority access and profile recognition for active supporters.',
      '[
        {"title":"5% Ticket Discount","description":"Save on every match ticket purchase."},
        {"title":"Priority Queue","description":"Jump the queue when tickets open for big matches."},
        {"title":"Silver Badge","description":"Exclusive silver badge on your fan profile."}
      ]'::jsonb,
      1
    ),
    (
      'gold',
      'Gold Membership',
      '2,000 pts - elite supporter',
      'Higher-value supporter benefits for loyal matchday and shop activity.',
      '[
        {"title":"Priority Tickets","description":"Get earlier access to on-sale match entries."},
        {"title":"10% Shop Discount","description":"Unlock supporter pricing on official club gear."},
        {"title":"VIP Events","description":"Access select fan sessions and special event queues."}
      ]'::jsonb,
      2
    ),
    (
      'platinum',
      'Platinum Membership',
      '5,000 pts - ultimate fan',
      'Top-tier supporter access across tickets, events, and season recognition.',
      '[
        {"title":"Priority Tickets + 15% Off","description":"Best pricing and first access to all matches."},
        {"title":"Meet & Greet","description":"Join premium player and club meetups when available."},
        {"title":"Free Kit","description":"Receive one complimentary official kit each season."},
        {"title":"All Gold Benefits","description":"VIP events, shop discounts, and everything from lower tiers."}
      ]'::jsonb,
      3
    )
) as package_seed(
  tier,
  title,
  subtitle,
  description,
  benefits,
  sort_order
)
join public.partners partner
  on partner.slug = 'rayon-sports'
on conflict (partner_id, tier) do update
set
  title = excluded.title,
  subtitle = excluded.subtitle,
  description = excluded.description,
  benefits = excluded.benefits,
  sort_order = excluded.sort_order,
  updated_at = now();
