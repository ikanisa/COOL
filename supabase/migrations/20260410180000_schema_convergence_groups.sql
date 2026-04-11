-- ============================================================================
-- Cool App - Schema convergence: contribution_groups → groups
-- ============================================================================
-- The remote DB has 'contribution_groups' (from an earlier divergent branch)
-- while all local migrations, Dart code, and Edge Functions reference
-- 'public.groups'. This migration converges the schema.
--
-- Safe to run: contribution_groups has zero rows.
-- ============================================================================

-- 1. Drop FKs, policies, triggers, indexes on contribution_groups
--    (so the rename doesn't carry stale references)

drop trigger if exists trg_contribution_groups_set_updated_at on public.contribution_groups;
drop policy if exists "Public groups are readable by everyone" on public.contribution_groups;
drop policy if exists "Creator can read own groups" on public.contribution_groups;
drop policy if exists "Authenticated users can create groups" on public.contribution_groups;
drop policy if exists "Creator can update own groups" on public.contribution_groups;

-- 2. Rename the table when needed.
-- If both tables exist, only skip the rename when the legacy table is empty.
do $$
declare
  legacy_exists boolean;
  canonical_exists boolean;
  legacy_row_count bigint;
begin
  select exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'contribution_groups'
  ) into legacy_exists;

  select exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'groups'
  ) into canonical_exists;

  if not legacy_exists then
    return;
  end if;

  if canonical_exists then
    execute 'select count(*) from public.contribution_groups'
      into legacy_row_count;

    if legacy_row_count > 0 then
      raise exception
        'Schema convergence blocked: both public.groups and public.contribution_groups exist, and contribution_groups still has % rows.',
        legacy_row_count;
    end if;

    return;
  end if;

  alter table public.contribution_groups rename to groups;
end $$;

-- 3. Ensure canonical columns exist (from initial_schema + later ALTER TABLEs)
--    Using ADD COLUMN IF NOT EXISTS so this is idempotent.
alter table public.groups
  add column if not exists country text not null default 'RW',
  add column if not exists visibility text not null default 'private',
  add column if not exists type text not null default 'saving',
  add column if not exists amount int not null default 0,
  add column if not exists monthly_contribution int,
  add column if not exists bank_partner_id text,
  add column if not exists momo_number text,
  add column if not exists frequency text,
  add column if not exists receiving_momo_route_type text,
  add column if not exists receiving_momo_code text,
  add column if not exists cycle_days int not null default 30,
  add column if not exists contribution_amount int not null default 0;

-- Map 'privacy' → 'visibility' if privacy column exists.
-- contribution_groups used 'privacy'; canonical schema uses 'visibility'.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'groups' and column_name = 'privacy'
  ) then
    update public.groups
    set visibility = case
      when privacy ilike '%public%' then 'public'
      else 'private'
    end
    where visibility = 'private' and privacy is not null and privacy != '';
  end if;
end $$;

-- 4. RLS
alter table public.groups enable row level security;

drop policy if exists "groups_select_public" on public.groups;
create policy "groups_select_public"
  on public.groups for select
  using (
    visibility = 'public'
    or creator_id = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = id and gm.user_id = auth.uid()
    )
  );

drop policy if exists "groups_insert" on public.groups;
create policy "groups_insert"
  on public.groups for insert
  with check (auth.uid() = creator_id);

drop policy if exists "groups_update_creator" on public.groups;
create policy "groups_update_creator"
  on public.groups for update
  using (auth.uid() = creator_id);

-- Admin read access
drop policy if exists "groups_admin_select_all" on public.groups;
create policy "groups_admin_select_all"
  on public.groups for select
  using (public.is_admin_user());

-- 5. Re-create updated_at trigger
drop trigger if exists trg_groups_set_updated_at on public.groups;
create trigger trg_groups_set_updated_at
  before update on public.groups
  for each row
  execute function public.set_updated_at();

-- 6. Re-create member count sync trigger
create or replace function public.sync_group_member_count()
returns trigger
language plpgsql
as $$
declare
  target_group_id uuid := coalesce(new.group_id, old.group_id);
begin
  if target_group_id is null then
    return coalesce(new, old);
  end if;

  update public.groups
  set
    member_count = (
      select count(*)
      from public.group_members gm
      where gm.group_id = target_group_id
    ),
    updated_at = now()
  where id = target_group_id;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_sync_group_member_count on public.group_members;
create trigger trg_sync_group_member_count
  after insert or update or delete on public.group_members
  for each row
  execute function public.sync_group_member_count();

-- 7. Indexes
create index if not exists idx_groups_country on public.groups (country);
create index if not exists idx_groups_visibility on public.groups (visibility);
create index if not exists idx_groups_creator_id on public.groups (creator_id);

-- 8. Update group_members FK if it still references contribution_groups
-- (Postgres auto-updates the FK target when the table is renamed,
--  but verify the constraint name update)
-- No action needed — Postgres handles this automatically on rename.

-- 9. Update group_messages FK if needed
do $$
begin
  if exists (
    select 1 from information_schema.table_constraints
    where table_name = 'group_messages'
      and constraint_type = 'FOREIGN KEY'
  ) then
    -- The FK auto-follows the rename; no action needed.
    null;
  end if;
end $$;
