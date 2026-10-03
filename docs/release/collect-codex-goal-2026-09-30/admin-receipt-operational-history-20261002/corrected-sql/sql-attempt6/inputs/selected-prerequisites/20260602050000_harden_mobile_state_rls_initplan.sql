-- Keep mobile support/deletion request policies aligned with Supabase
-- performance-advisor guidance by evaluating auth.uid() once per statement.

drop policy if exists "account deletion own read" on mobile_account_deletion_requests;
create policy "account deletion own read"
on mobile_account_deletion_requests
for select to authenticated
using (
  user_id = (select auth.uid())
  or is_platform_admin((select auth.uid()))
);

drop policy if exists "support requests own read" on mobile_support_requests;
create policy "support requests own read"
on mobile_support_requests
for select to authenticated
using (
  user_id = (select auth.uid())
  or is_platform_admin((select auth.uid()))
);
