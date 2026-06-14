-- Browser admin login must not grant platform-owner privileges.
-- Use admin_bootstrap_platform_owner(p_user_id, p_reason) from a service-role
-- controlled operator path for break-glass or first-owner setup.

create or replace function admin_bootstrap_whatsapp_operator()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'admin_bootstrap_whatsapp_operator is disabled; use the service-role admin bootstrap workflow';
end;
$$;

revoke execute on function admin_bootstrap_whatsapp_operator()
  from public, anon, authenticated;
grant execute on function admin_bootstrap_whatsapp_operator()
  to service_role;
