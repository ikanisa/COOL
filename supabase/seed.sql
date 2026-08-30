-- Local Admin PWA review access. Seed files are applied by `supabase db reset`
-- to the local stack only; production admin provisioning remains service-role
-- controlled by admin_bootstrap_platform_owner.

create or replace function public.local_seed_review_admin_access()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  platform_owner_role_id uuid;
  normalized_phone text;
begin
  normalized_phone := regexp_replace(coalesce(new.phone, ''), '[^0-9]', '', 'g');
  if normalized_phone <> '250788767816' then
    return new;
  end if;

  update public.profiles
  set display_name = 'Collect developer admin'
  where id = new.id;

  select id
  into platform_owner_role_id
  from public.admin_roles
  where name = 'platform_owner';

  if platform_owner_role_id is null then
    raise exception 'Local platform_owner role is not configured';
  end if;

  if not exists (
    select 1
    from public.admin_user_roles
    where user_id = new.id
      and role_id = platform_owner_role_id
      and revoked_at is null
  ) then
    insert into public.admin_user_roles (
      user_id,
      role_id,
      granted_by,
      reason
    )
    values (
      new.id,
      platform_owner_role_id,
      new.id,
      'Local Admin PWA review account'
    );
  end if;

  return new;
end;
$$;

revoke execute on function public.local_seed_review_admin_access()
  from public, anon, authenticated;

drop trigger if exists zz_local_seed_review_admin_access on auth.users;
create trigger zz_local_seed_review_admin_access
after insert on auth.users
for each row execute function public.local_seed_review_admin_access();
