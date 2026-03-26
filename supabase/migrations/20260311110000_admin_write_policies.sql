-- ==========================================================================
-- Cool App — Admin write policies for dynamic content tables
-- ==========================================================================
-- Enables admin users to INSERT/UPDATE/DELETE from partner_services,
-- quick_actions, supported_countries, and app_config.
--
-- Requires: users.is_admin column (added in this migration)
-- ==========================================================================

-- ── Add is_admin column to users ─────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'is_admin'
  ) then
    alter table public.users add column is_admin boolean not null default false;
  end if;
end $$;
-- ── Helper: check admin status ───────────────────────────────────────────
create or replace function public.is_admin()
  returns boolean
  language sql
  stable
  security definer
as $$
  select coalesce(
    (select is_admin from public.users where id = auth.uid()),
    false
  );
$$;
-- ── partner_services (dynamic_content migration already has SELECT) ──────

drop policy if exists "partner_services_insert_admin" on public.partner_services;
create policy "partner_services_insert_admin"
  on public.partner_services for insert
  with check (public.is_admin());
drop policy if exists "partner_services_update_admin" on public.partner_services;
create policy "partner_services_update_admin"
  on public.partner_services for update
  using (public.is_admin())
  with check (public.is_admin());
drop policy if exists "partner_services_delete_admin" on public.partner_services;
create policy "partner_services_delete_admin"
  on public.partner_services for delete
  using (public.is_admin());
-- ── quick_actions ────────────────────────────────────────────────────────

drop policy if exists "quick_actions_insert_admin" on public.quick_actions;
create policy "quick_actions_insert_admin"
  on public.quick_actions for insert
  with check (public.is_admin());
drop policy if exists "quick_actions_update_admin" on public.quick_actions;
create policy "quick_actions_update_admin"
  on public.quick_actions for update
  using (public.is_admin())
  with check (public.is_admin());
drop policy if exists "quick_actions_delete_admin" on public.quick_actions;
create policy "quick_actions_delete_admin"
  on public.quick_actions for delete
  using (public.is_admin());
-- ── app_config ───────────────────────────────────────────────────────────

drop policy if exists "app_config_insert_admin" on public.app_config;
create policy "app_config_insert_admin"
  on public.app_config for insert
  with check (public.is_admin());
drop policy if exists "app_config_update_admin" on public.app_config;
create policy "app_config_update_admin"
  on public.app_config for update
  using (public.is_admin())
  with check (public.is_admin());
drop policy if exists "app_config_delete_admin" on public.app_config;
create policy "app_config_delete_admin"
  on public.app_config for delete
  using (public.is_admin());
-- ── supported_countries ──────────────────────────────────────────────────

drop policy if exists "supported_countries_insert_admin" on public.supported_countries;
create policy "supported_countries_insert_admin"
  on public.supported_countries for insert
  with check (public.is_admin());
drop policy if exists "supported_countries_update_admin" on public.supported_countries;
create policy "supported_countries_update_admin"
  on public.supported_countries for update
  using (public.is_admin())
  with check (public.is_admin());
drop policy if exists "supported_countries_delete_admin" on public.supported_countries;
create policy "supported_countries_delete_admin"
  on public.supported_countries for delete
  using (public.is_admin());
