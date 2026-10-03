begin;

-- Trigger execution does not require a browser-callable function grant.
-- Keep the official route immutability trigger installed and unchanged.
revoke all on function public.enforce_official_payee_route_immutable()
  from public, anon, authenticated;

commit;
