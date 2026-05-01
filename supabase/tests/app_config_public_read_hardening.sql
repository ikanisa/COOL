-- Verification script for 20260501130000_app_config_public_read_hardening.sql.
-- Run with psql against a migrated database. It raises if the public config
-- contract regresses.

do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'app_config'
      and policyname = 'Public read app_config'
  ) then
    raise exception 'Public read app_config policy must not exist';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'app_config'
      and policyname = 'app_config_select_admin'
      and roles = '{authenticated}'
  ) then
    raise exception 'Missing authenticated admin SELECT policy for app_config';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_public_app_config'
      and p.prosecdef
  ) then
    raise exception 'get_public_app_config must exist as SECURITY DEFINER';
  end if;

  if exists (
    select 1
    from public.get_public_app_config(array['savings_momo_code'])
  ) then
    raise exception 'savings_momo_code must not be exposed through get_public_app_config';
  end if;

  if not exists (
    select 1
    from public.get_public_app_config(array['support_whatsapp'])
  ) then
    raise exception 'support_whatsapp must remain available through get_public_app_config';
  end if;
end $$;
