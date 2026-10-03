create index if not exists audit_logs_collection_entity_idx
  on audit_logs (entity_id, created_at desc)
  where entity_type = 'collection';

create index if not exists collection_invites_collection_idx
  on collection_invites (collection_id, created_at desc);

create index if not exists collection_members_collection_status_idx
  on collection_members (collection_id, status);

create index if not exists collection_receivers_collection_idx
  on collection_receivers (collection_id, is_active);

create index if not exists collection_receivers_receiver_idx
  on collection_receivers (receiver_user_id, is_active);

create index if not exists collection_reports_collection_idx
  on collection_reports (collection_id, created_at desc);

create index if not exists collection_reports_reporter_idx
  on collection_reports (reporter_user_id, created_at desc);

create index if not exists member_obligations_collection_user_idx
  on member_obligations (collection_id, user_id, status);

create index if not exists parsed_events_receiver_idx
  on parsed_payment_events (receiver_user_id, created_at desc);

create index if not exists payment_allocations_collection_idx
  on payment_allocations (collection_id, created_at desc);

create index if not exists payment_intents_collection_status_idx
  on payment_intents (collection_id, status, created_at desc);

create index if not exists payment_intents_contributor_idx
  on payment_intents (contributor_user_id, created_at desc);

create index if not exists payments_contributor_idx
  on payments (contributor_user_id, posted_at desc);

create index if not exists public_collection_requests_collection_idx
  on public_collection_requests (collection_id, status, requested_at desc);

create index if not exists public_collection_requests_requester_idx
  on public_collection_requests (requested_by, requested_at desc);

create index if not exists receiver_mode_consents_user_idx
  on receiver_mode_consents (user_id, created_at desc);

create index if not exists recurring_periods_collection_status_idx
  on recurring_periods (collection_id, status, period_start desc);

drop policy if exists "profiles update own non-admin" on profiles;
create policy "profiles update own non-admin" on profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists "collections read public or member" on collections;
create policy "collections read public or member" on collections
for select
using (
  public_status = 'public_approved'
  or public.user_can_read_collection(id, (select auth.uid()))
);

drop policy if exists "collections insert authenticated" on collections;
create policy "collections insert authenticated" on collections
for insert to authenticated
with check (
  creator_user_id = (select auth.uid())
  and visibility = 'private'
);

drop policy if exists "collections update admins" on collections;
create policy "collections update admins" on collections
for update to authenticated
using (public.user_is_collection_admin(id, (select auth.uid())))
with check (public.user_is_collection_admin(id, (select auth.uid())));

drop policy if exists "members read scoped" on collection_members;
create policy "members read scoped" on collection_members
for select to authenticated
using (public.user_can_read_collection(collection_id, (select auth.uid())));

drop policy if exists "members manage admins" on collection_members;
create policy "members manage admins" on collection_members
for all to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "receivers read collection admins" on collection_receivers;
create policy "receivers read collection admins" on collection_receivers
for select to authenticated
using (
  public.user_is_collection_admin(collection_id, (select auth.uid()))
  or receiver_user_id = (select auth.uid())
);

drop policy if exists "receivers manage admins" on collection_receivers;
create policy "receivers manage admins" on collection_receivers
for all to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "payment instructions platform admin manage" on payment_instruction_templates;
create policy "payment instructions platform admin manage" on payment_instruction_templates
for all to authenticated
using ((select public.current_user_is_platform_admin()))
with check ((select public.current_user_is_platform_admin()));

drop policy if exists "invites read admins" on collection_invites;
create policy "invites read admins" on collection_invites
for select to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "invites manage admins" on collection_invites;
create policy "invites manage admins" on collection_invites
for all to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "payment intents read contributor or admin" on payment_intents;
create policy "payment intents read contributor or admin" on payment_intents
for select to authenticated
using (
  contributor_user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "payment intents create contributor" on payment_intents;
create policy "payment intents create contributor" on payment_intents
for insert to authenticated
with check (
  contributor_user_id = (select auth.uid())
  and public.user_can_read_collection(collection_id, (select auth.uid()))
);

drop policy if exists "payment intents update contributor txn or admin" on payment_intents;
create policy "payment intents update contributor txn or admin" on payment_intents
for update to authenticated
using (
  contributor_user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
)
with check (
  contributor_user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "raw sms receiver own read" on raw_payment_sms;
create policy "raw sms receiver own read" on raw_payment_sms
for select to authenticated
using (
  receiver_user_id = (select auth.uid())
  or (select public.current_user_is_platform_admin())
);

drop policy if exists "parsed events receiver or admin read" on parsed_payment_events;
create policy "parsed events receiver or admin read" on parsed_payment_events
for select to authenticated
using (
  receiver_user_id = (select auth.uid())
  or (select public.current_user_is_platform_admin())
);

drop policy if exists "payments read scoped" on payments;
create policy "payments read scoped" on payments
for select to authenticated
using (
  contributor_user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "allocations read collection admins" on payment_allocations;
create policy "allocations read collection admins" on payment_allocations
for select to authenticated
using (
  public.user_is_collection_admin(collection_id, (select auth.uid()))
  or (select public.current_user_is_platform_admin())
);

drop policy if exists "ledger read scoped" on ledger_entries;
create policy "ledger read scoped" on ledger_entries
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "recurring periods read scoped" on recurring_periods;
create policy "recurring periods read scoped" on recurring_periods
for select to authenticated
using (public.user_can_read_collection(collection_id, (select auth.uid())));

drop policy if exists "recurring periods manage admins" on recurring_periods;
create policy "recurring periods manage admins" on recurring_periods
for all to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "obligations read own or admin" on member_obligations;
create policy "obligations read own or admin" on member_obligations
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "obligations manage admins" on member_obligations;
create policy "obligations manage admins" on member_obligations
for all to authenticated
using (public.user_is_collection_admin(collection_id, (select auth.uid())))
with check (public.user_is_collection_admin(collection_id, (select auth.uid())));

drop policy if exists "public requests read requester or admin" on public_collection_requests;
create policy "public requests read requester or admin" on public_collection_requests
for select to authenticated
using (
  requested_by = (select auth.uid())
  or (select public.current_user_is_platform_admin())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "public requests insert requester" on public_collection_requests;
create policy "public requests insert requester" on public_collection_requests
for insert to authenticated
with check (
  requested_by = (select auth.uid())
  and public.user_is_collection_admin(collection_id, (select auth.uid()))
);

drop policy if exists "public requests admin update" on public_collection_requests;
create policy "public requests admin update" on public_collection_requests
for update to authenticated
using ((select public.current_user_is_platform_admin()))
with check ((select public.current_user_is_platform_admin()));

drop policy if exists "reports read admins" on collection_reports;
create policy "reports read admins" on collection_reports
for select to authenticated
using (
  (select public.current_user_is_platform_admin())
  or public.user_is_collection_admin(collection_id, (select auth.uid()))
  or reporter_user_id = (select auth.uid())
);

drop policy if exists "reports insert authenticated" on collection_reports;
create policy "reports insert authenticated" on collection_reports
for insert to authenticated
with check (reporter_user_id = (select auth.uid()));

drop policy if exists "reports update platform admin" on collection_reports;
create policy "reports update platform admin" on collection_reports
for update to authenticated
using ((select public.current_user_is_platform_admin()))
with check ((select public.current_user_is_platform_admin()));

drop policy if exists "receiver consents own" on receiver_mode_consents;
create policy "receiver consents own" on receiver_mode_consents
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "audit logs platform or scoped collection admins" on audit_logs;
create policy "audit logs platform or scoped collection admins" on audit_logs
for select to authenticated
using (
  (select public.current_user_is_platform_admin())
  or (
    entity_type = 'collection'
    and entity_id is not null
    and public.user_is_collection_admin(entity_id, (select auth.uid()))
  )
);
