-- ============================================================================
-- Cool App - Admin hardening and group contract alignment
-- ============================================================================

alter table public.users
  add column if not exists is_admin boolean not null default false;

create or replace function public.protect_users_is_admin()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' then
    if tg_op = 'INSERT' and coalesce(new.is_admin, false) then
      raise exception 'is_admin can only be assigned by the service role.';
    end if;

    if tg_op = 'UPDATE' and new.is_admin is distinct from old.is_admin then
      raise exception 'is_admin can only be modified by the service role.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_users_is_admin on public.users;
create trigger trg_protect_users_is_admin
  before insert or update on public.users
  for each row
  execute function public.protect_users_is_admin();

create or replace function public.is_admin_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users
    where id = auth.uid()
      and is_admin = true
  );
$$;

grant execute on function public.is_admin_user() to authenticated;

drop policy if exists partners_insert_admin on public.partners;
create policy partners_insert_admin
  on public.partners for insert
  to authenticated
  with check (public.is_admin_user());

drop policy if exists partners_update_admin on public.partners;
create policy partners_update_admin
  on public.partners for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists partners_delete_admin on public.partners;
create policy partners_delete_admin
  on public.partners for delete
  to authenticated
  using (public.is_admin_user());

drop policy if exists partner_services_insert_admin on public.partner_services;
create policy partner_services_insert_admin
  on public.partner_services for insert
  to authenticated
  with check (public.is_admin_user());

drop policy if exists partner_services_update_admin on public.partner_services;
create policy partner_services_update_admin
  on public.partner_services for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists partner_services_delete_admin on public.partner_services;
create policy partner_services_delete_admin
  on public.partner_services for delete
  to authenticated
  using (public.is_admin_user());

drop policy if exists supported_countries_update_admin on public.supported_countries;
create policy supported_countries_update_admin
  on public.supported_countries for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists quick_actions_insert_admin on public.quick_actions;
create policy quick_actions_insert_admin
  on public.quick_actions for insert
  to authenticated
  with check (public.is_admin_user());

drop policy if exists quick_actions_update_admin on public.quick_actions;
create policy quick_actions_update_admin
  on public.quick_actions for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists quick_actions_delete_admin on public.quick_actions;
create policy quick_actions_delete_admin
  on public.quick_actions for delete
  to authenticated
  using (public.is_admin_user());

drop policy if exists vehicle_types_insert_admin on public.vehicle_types;
create policy vehicle_types_insert_admin
  on public.vehicle_types for insert
  to authenticated
  with check (public.is_admin_user());

drop policy if exists vehicle_types_update_admin on public.vehicle_types;
create policy vehicle_types_update_admin
  on public.vehicle_types for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists vehicle_types_delete_admin on public.vehicle_types;
create policy vehicle_types_delete_admin
  on public.vehicle_types for delete
  to authenticated
  using (public.is_admin_user());

drop policy if exists app_config_insert_admin on public.app_config;
create policy app_config_insert_admin
  on public.app_config for insert
  to authenticated
  with check (public.is_admin_user());

drop policy if exists app_config_update_admin on public.app_config;
create policy app_config_update_admin
  on public.app_config for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

drop policy if exists app_config_delete_admin on public.app_config;
create policy app_config_delete_admin
  on public.app_config for delete
  to authenticated
  using (public.is_admin_user());

alter table public.groups
  add column if not exists frequency text not null default 'monthly',
  add column if not exists invite_code text,
  add column if not exists institution_id text;

update public.groups
set
  frequency = coalesce(nullif(frequency, ''), 'monthly'),
  invite_code = coalesce(
    nullif(invite_code, ''),
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
  )
where true;

create unique index if not exists idx_groups_invite_code
  on public.groups (invite_code)
  where invite_code is not null;
