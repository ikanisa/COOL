-- ==========================================================================
-- Cool App — Admin RPC for MoMo validation issues
-- ==========================================================================
-- Exposes the momo_validation_issues view to authenticated admin users
-- through a security-definer RPC without broadening direct table/view access.
-- ==========================================================================

create or replace function public.get_momo_validation_issues()
returns setof public.momo_validation_issues
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  return query
  select *
  from public.momo_validation_issues
  order by
    issue_code asc,
    country asc,
    record_type asc,
    record_id asc;
end;
$$;

revoke all on function public.get_momo_validation_issues() from public;
grant execute on function public.get_momo_validation_issues() to authenticated;
