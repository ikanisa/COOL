drop policy if exists "notification preferences own read" on notification_preferences;
create policy "notification preferences own read" on notification_preferences
for select using (user_id = (select auth.uid()));

drop policy if exists "notification preferences own upsert" on notification_preferences;
create policy "notification preferences own upsert" on notification_preferences
for insert with check (user_id = (select auth.uid()));

drop policy if exists "notification preferences own update" on notification_preferences;
create policy "notification preferences own update" on notification_preferences
for update
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "notification device own read" on notification_device_tokens;
create policy "notification device own read" on notification_device_tokens
for select using (user_id = (select auth.uid()));

drop policy if exists "notification device own insert" on notification_device_tokens;
create policy "notification device own insert" on notification_device_tokens
for insert with check (user_id = (select auth.uid()));

drop policy if exists "notification device own update" on notification_device_tokens;
create policy "notification device own update" on notification_device_tokens
for update
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "notification events own read" on notification_events;
create policy "notification events own read" on notification_events
for select using (user_id = (select auth.uid()));

drop policy if exists "notification events own update" on notification_events;
create policy "notification events own update" on notification_events
for update
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
