-- Anonymous readers need collection-scope helper functions for public views,
-- but they do not need direct RPC access to the platform-admin helper.
revoke execute on function public.current_user_is_platform_admin() from anon;
