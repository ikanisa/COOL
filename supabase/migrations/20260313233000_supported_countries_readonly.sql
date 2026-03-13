begin;

-- supported_countries remains in the schema only as a Rwanda-only validation
-- reference for MoMo formatting and compatibility views. It is no longer an
-- admin-managed catalog and should not accept authenticated writes.

drop policy if exists "supported_countries_insert_admin"
  on public.supported_countries;
drop policy if exists "supported_countries_update_admin"
  on public.supported_countries;
drop policy if exists "supported_countries_delete_admin"
  on public.supported_countries;
drop policy if exists supported_countries_update_admin
  on public.supported_countries;

comment on table public.supported_countries is
  'read-only Rwanda validation reference for MoMo and phone normalization.';

commit;
