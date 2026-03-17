-- ============================================================================
-- Rayon Sports FC — Audit Fix Migration
-- Addresses: admin write RLS (C1), analytics RPC (C2), CHECK constraints
-- (C3/C4), missing columns (C7/C9/C10/C11/C12), stock decrement (C5),
-- and capacity check (C6).
-- ============================================================================

-- ── C1. Admin Write RLS Policies ─────────────────────────────────────────────

-- rs_matches: admin insert/update/delete
drop policy if exists rs_matches_insert_admin on public.rs_matches;
create policy rs_matches_insert_admin
  on public.rs_matches for insert
  to authenticated
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_matches_update_admin on public.rs_matches;
create policy rs_matches_update_admin
  on public.rs_matches for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_matches_delete_admin on public.rs_matches;
create policy rs_matches_delete_admin
  on public.rs_matches for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

-- rs_shop_products: admin insert/update/delete
drop policy if exists rs_shop_products_insert_admin on public.rs_shop_products;
create policy rs_shop_products_insert_admin
  on public.rs_shop_products for insert
  to authenticated
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_shop_products_update_admin on public.rs_shop_products;
create policy rs_shop_products_update_admin
  on public.rs_shop_products for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_shop_products_delete_admin on public.rs_shop_products;
create policy rs_shop_products_delete_admin
  on public.rs_shop_products for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

-- rs_fan_clubs: admin insert/update/delete
drop policy if exists rs_fan_clubs_insert_admin on public.rs_fan_clubs;
create policy rs_fan_clubs_insert_admin
  on public.rs_fan_clubs for insert
  to authenticated
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_fan_clubs_update_admin on public.rs_fan_clubs;
create policy rs_fan_clubs_update_admin
  on public.rs_fan_clubs for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_fan_clubs_delete_admin on public.rs_fan_clubs;
create policy rs_fan_clubs_delete_admin
  on public.rs_fan_clubs for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

-- rs_initiatives: admin insert/update/delete
drop policy if exists rs_initiatives_insert_admin on public.rs_initiatives;
create policy rs_initiatives_insert_admin
  on public.rs_initiatives for insert
  to authenticated
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_initiatives_update_admin on public.rs_initiatives;
create policy rs_initiatives_update_admin
  on public.rs_initiatives for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_initiatives_delete_admin on public.rs_initiatives;
create policy rs_initiatives_delete_admin
  on public.rs_initiatives for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

-- rs_achievements: admin insert/update/delete
drop policy if exists rs_achievements_insert_admin on public.rs_achievements;
create policy rs_achievements_insert_admin
  on public.rs_achievements for insert
  to authenticated
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_achievements_update_admin on public.rs_achievements;
create policy rs_achievements_update_admin
  on public.rs_achievements for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_achievements_delete_admin on public.rs_achievements;
create policy rs_achievements_delete_admin
  on public.rs_achievements for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

-- rs_fan_memberships: admin update (insert already has user policy)
drop policy if exists rs_fan_memberships_update_admin on public.rs_fan_memberships;
create policy rs_fan_memberships_update_admin
  on public.rs_fan_memberships for update
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  )
  with check (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_fan_memberships_delete_admin on public.rs_fan_memberships;
create policy rs_fan_memberships_delete_admin
  on public.rs_fan_memberships for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

-- rs_tickets: admin update/delete
drop policy if exists rs_tickets_update_admin on public.rs_tickets;
create policy rs_tickets_update_admin
  on public.rs_tickets for update
  to authenticated
  using (
    (select auth.uid()) = user_id
    or public.is_admin_user()
    -- tickets link to partner via match; check match's partner_id
    or exists (
      select 1 from public.rs_matches m
      where m.id = rs_tickets.match_id
        and public.rs_is_partner_admin(m.partner_id)
    )
  );

drop policy if exists rs_tickets_delete_admin on public.rs_tickets;
create policy rs_tickets_delete_admin
  on public.rs_tickets for delete
  to authenticated
  using (
    public.is_admin_user()
    or exists (
      select 1 from public.rs_matches m
      where m.id = rs_tickets.match_id
        and public.rs_is_partner_admin(m.partner_id)
    )
  );

-- rs_shop_orders: admin update/delete (need partner_id column first — see C7)
-- These policies will be created AFTER the partner_id column is added below.

-- ── C3. Fix CHECK constraint for rs_tickets to include voided/refunded ───────

alter table public.rs_tickets
  drop constraint if exists rs_tickets_status_check;

alter table public.rs_tickets
  add constraint rs_tickets_status_check
  check (status in ('pending', 'valid', 'used', 'cancelled', 'voided', 'refunded'));

-- ── C4. Fix CHECK constraint for rs_shop_orders ─────────────────────────────

alter table public.rs_shop_orders
  drop constraint if exists rs_shop_orders_status_check;

alter table public.rs_shop_orders
  add constraint rs_shop_orders_status_check
  check (
    status in (
      'pending', 'paid', 'confirmed', 'packed',
      'shipped', 'fulfilled', 'delivered', 'cancelled'
    )
  );

-- ── C7. Add partner_id to rs_shop_orders ────────────────────────────────────

alter table public.rs_shop_orders
  add column if not exists partner_id uuid references public.partners(id);

create index if not exists idx_rs_shop_orders_partner
  on public.rs_shop_orders (partner_id);

-- Backfill existing orders: derive partner_id from the items' product
update public.rs_shop_orders
set partner_id = (
  select p.partner_id
  from public.rs_shop_products p
  where p.id::text = (
    rs_shop_orders.items -> 0 ->> 'product_id'
  )
  limit 1
)
where partner_id is null
  and items is not null
  and jsonb_array_length(items) > 0;

-- Now add admin RLS for rs_shop_orders
drop policy if exists rs_shop_orders_update_admin on public.rs_shop_orders;
create policy rs_shop_orders_update_admin
  on public.rs_shop_orders for update
  to authenticated
  using (
    (select auth.uid()) = user_id
    or public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

drop policy if exists rs_shop_orders_delete_admin on public.rs_shop_orders;
create policy rs_shop_orders_delete_admin
  on public.rs_shop_orders for delete
  to authenticated
  using (
    public.is_admin_user()
    or public.rs_is_partner_admin(partner_id)
  );

-- ── C9. Add supporter_name to rs_initiative_contributions ───────────────────

alter table public.rs_initiative_contributions
  add column if not exists supporter_name text;

-- ── C10. Add expires_at to rs_fan_memberships ───────────────────────────────

alter table public.rs_fan_memberships
  add column if not exists expires_at timestamptz;

-- ── C11. Add sort_order, image_url, available_sizes to rs_shop_products ─────

alter table public.rs_shop_products
  add column if not exists sort_order integer not null default 0,
  add column if not exists image_url text,
  add column if not exists available_sizes text[];

-- ── C12. Add discount_amount, delivery_fee, referral_invite_id to orders ────

alter table public.rs_shop_orders
  add column if not exists discount_amount integer not null default 0,
  add column if not exists delivery_fee integer not null default 0,
  add column if not exists referral_invite_id uuid;

-- ── C2. Fix get_rs_fan_analytics RPC ────────────────────────────────────────

create or replace function public.get_rs_fan_analytics()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'total_fans', (select count(*) from public.rs_fan_memberships),
    'active_memberships', (select count(*) from public.rs_fan_memberships),
    'total_tickets_sold', (
      select count(*) from public.rs_tickets
      where status in ('valid', 'used')
    ),
    'ticket_revenue', (
      select coalesce(sum(amount_paid), 0)
      from public.rs_tickets
      where status in ('valid', 'used')
    ),
    'total_initiatives', (select count(*) from public.rs_initiatives),
    'total_contributions', (
      select coalesce(sum(amount), 0)
      from public.rs_initiative_contributions
      where status = 'confirmed'
    ),
    'total_shop_revenue', (
      select coalesce(sum(total), 0)
      from public.rs_shop_orders
      where status in ('paid', 'confirmed', 'packed', 'fulfilled', 'delivered')
    ),
    'tier_breakdown', (
      select coalesce(
        jsonb_object_agg(tier, cnt),
        '{}'::jsonb
      )
      from (
        select tier, count(*) as cnt
        from public.rs_fan_memberships
        group by tier
      ) t
    )
  ) into v_result;

  return v_result;
end;
$$;

-- ── C5. Stock Decrement Trigger on Shop Orders ──────────────────────────────

create or replace function public.rs_decrement_stock_on_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
begin
  if new.items is null or jsonb_array_length(new.items) = 0 then
    return new;
  end if;

  for v_item in select * from jsonb_array_elements(new.items)
  loop
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_quantity := coalesce((v_item ->> 'quantity')::integer, 1);

    update public.rs_shop_products
    set stock = greatest(stock - v_quantity, 0)
    where id = v_product_id;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_rs_shop_orders_decrement_stock
  on public.rs_shop_orders;

create trigger trg_rs_shop_orders_decrement_stock
  after insert on public.rs_shop_orders
  for each row
  execute function public.rs_decrement_stock_on_order();

-- ── C6. Capacity Check Trigger on Ticket Insert ─────────────────────────────

create or replace function public.rs_check_ticket_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capacity integer;
  v_sold integer;
begin
  select capacity
  into v_capacity
  from public.rs_matches
  where id = new.match_id;

  -- If capacity is 0 or null, treat as unlimited
  if coalesce(v_capacity, 0) = 0 then
    return new;
  end if;

  select count(*)
  into v_sold
  from public.rs_tickets
  where match_id = new.match_id
    and status in ('pending', 'valid', 'used');

  if v_sold >= v_capacity then
    raise exception 'Match is sold out. Capacity: %, Sold: %',
      v_capacity, v_sold;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_rs_tickets_check_capacity
  on public.rs_tickets;

create trigger trg_rs_tickets_check_capacity
  before insert on public.rs_tickets
  for each row
  execute function public.rs_check_ticket_capacity();
