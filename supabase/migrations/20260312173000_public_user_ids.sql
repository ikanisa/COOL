-- ==========================================================================
-- Public 6-digit user IDs for all in-app identity surfaces
-- ==========================================================================

create sequence if not exists public.public_user_id_seq
  as integer
  minvalue 1
  maxvalue 999999
  start with 1
  increment by 1
  no cycle;

create or replace function public.next_public_user_id()
returns text
language plpgsql
security definer
set search_path = public
as $create_group_atomic$
declare
  v_next integer;
begin
  v_next := nextval('public.public_user_id_seq');
  return lpad(v_next::text, 6, '0');
end;
$create_group_atomic$;

revoke all on function public.next_public_user_id() from public;
grant execute on function public.next_public_user_id() to authenticated;

alter table public.users
  add column if not exists public_user_id text;

alter table public.users
  alter column public_user_id set default public.next_public_user_id();

create or replace function public.assign_public_user_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $join_group_via_invite$
begin
  if coalesce(btrim(new.public_user_id), '') = '' then
    new.public_user_id := public.next_public_user_id();
  end if;

  return new;
end;
$join_group_via_invite$;

drop trigger if exists trg_assign_public_user_id on public.users;
create trigger trg_assign_public_user_id
  before insert or update of public_user_id
  on public.users
  for each row
  execute function public.assign_public_user_id();

do $$
declare
  has_momo_trigger boolean;
begin
  select exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.users'::regclass
      and tgname = 'trg_enforce_user_momo_fields'
      and not tgisinternal
  )
  into has_momo_trigger;

  if has_momo_trigger then
    execute 'alter table public.users disable trigger trg_enforce_user_momo_fields';
  end if;

  update public.users
  set public_user_id = null
  where coalesce(btrim(public_user_id), '') <> ''
    and public_user_id !~ '^[0-9]{6}$';

  update public.users
  set public_user_id = public.next_public_user_id()
  where coalesce(btrim(public_user_id), '') = '';

  if has_momo_trigger then
    execute 'alter table public.users enable trigger trg_enforce_user_momo_fields';
  end if;
exception
  when others then
    if has_momo_trigger then
      execute 'alter table public.users enable trigger trg_enforce_user_momo_fields';
    end if;
    raise;
end;
$$;

select setval(
  'public.public_user_id_seq',
  greatest(
    coalesce(
      (
        select max(public_user_id::integer) + 1
        from public.users
        where public_user_id ~ '^[0-9]{6}$'
      ),
      1
    ),
    1
  ),
  false
);

alter table public.users
  drop constraint if exists users_public_user_id_format_check;

alter table public.users
  add constraint users_public_user_id_format_check
    check (public_user_id ~ '^[0-9]{6}$');

create unique index if not exists idx_users_public_user_id
  on public.users (public_user_id);

alter table public.users
  alter column public_user_id set not null;

do $$
declare
  has_group_count_trigger boolean;
begin
  select exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.group_members'::regclass
      and tgname = 'trg_sync_group_member_count'
      and not tgisinternal
  )
  into has_group_count_trigger;

  if has_group_count_trigger then
    execute 'alter table public.group_members disable trigger trg_sync_group_member_count';
  end if;

  update public.group_members as membership
  set display_name = profile.public_user_id
  from public.users as profile
  where profile.id = membership.user_id
    and coalesce(membership.display_name, '') is distinct from profile.public_user_id;

  if has_group_count_trigger then
    execute 'alter table public.group_members enable trigger trg_sync_group_member_count';
  end if;
exception
  when others then
    if has_group_count_trigger then
      execute 'alter table public.group_members enable trigger trg_sync_group_member_count';
    end if;
    raise;
end;
$$;
