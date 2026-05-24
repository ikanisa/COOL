-- Keep read policies single-purpose so the planner does not evaluate multiple
-- permissive SELECT policies for the same role/action.

alter policy "admin user roles read admins" on public.admin_user_roles
  using ((select public.has_admin_permission('admin_users.read')) or user_id = (select auth.uid()));

alter policy "raw sms metadata scoped read" on public.raw_payment_sms
  using (
    receiver_user_id = (select auth.uid())
    or (select public.has_admin_permission('sms.metadata.read'))
  );

drop policy if exists "members manage admins" on public.collection_members;
create policy "members admin insert" on public.collection_members
for insert to authenticated
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "members admin update" on public.collection_members
for update to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "members admin delete" on public.collection_members
for delete to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "receivers manage admins" on public.collection_receivers;
create policy "receivers admin insert" on public.collection_receivers
for insert to authenticated
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "receivers admin update" on public.collection_receivers
for update to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "receivers admin delete" on public.collection_receivers
for delete to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "payment instructions platform admin manage" on public.payment_instruction_templates;
create policy "payment instructions platform admin insert" on public.payment_instruction_templates
for insert to authenticated
with check ((select public.current_user_is_platform_admin()));
create policy "payment instructions platform admin update" on public.payment_instruction_templates
for update to authenticated
using ((select public.current_user_is_platform_admin()))
with check ((select public.current_user_is_platform_admin()));
create policy "payment instructions platform admin delete" on public.payment_instruction_templates
for delete to authenticated
using ((select public.current_user_is_platform_admin()));

drop policy if exists "invites manage admins" on public.collection_invites;
create policy "invites admin insert" on public.collection_invites
for insert to authenticated
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "invites admin update" on public.collection_invites
for update to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "invites admin delete" on public.collection_invites
for delete to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "recurring periods manage admins" on public.recurring_periods;
create policy "recurring periods admin insert" on public.recurring_periods
for insert to authenticated
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "recurring periods admin update" on public.recurring_periods
for update to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "recurring periods admin delete" on public.recurring_periods
for delete to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "obligations manage admins" on public.member_obligations;
create policy "obligations admin insert" on public.member_obligations
for insert to authenticated
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "obligations admin update" on public.member_obligations
for update to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));
create policy "obligations admin delete" on public.member_obligations
for delete to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())));
