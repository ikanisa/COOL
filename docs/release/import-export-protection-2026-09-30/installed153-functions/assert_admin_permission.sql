CREATE OR REPLACE FUNCTION public.assert_admin_permission(permission text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_admin_permission(permission, auth.uid()) then
    raise exception 'Admin permission % required', permission;
  end if;
end;
$function$