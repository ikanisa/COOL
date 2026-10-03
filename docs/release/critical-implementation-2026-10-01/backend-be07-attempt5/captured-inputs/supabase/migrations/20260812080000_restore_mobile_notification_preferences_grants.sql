begin;

-- The mobile client reads and upserts only the signed-in user's row. RLS
-- remains the authorization boundary; these table grants merely allow the
-- authenticated role to reach those owner-scoped policies.
revoke all on table public.notification_preferences from anon;
grant select, insert, update on table public.notification_preferences
  to authenticated;

commit;
