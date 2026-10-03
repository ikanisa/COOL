create table if not exists notification_preferences (
  user_id uuid primary key references profiles(id) on delete cascade,
  contribution_confirmations boolean not null default true,
  payment_reminders boolean not null default true,
  group_updates boolean not null default true,
  security_notices boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists notification_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform text not null check (platform in ('android', 'ios', 'web')),
  token_hash text not null,
  token_last_four text,
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token_hash)
);

create table if not exists notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  collection_id uuid references collections(id) on delete cascade,
  type text not null check (type in (
    'contribution_confirmed',
    'payment_reminder',
    'group_update',
    'security_notice'
  )),
  title text not null,
  body text not null,
  deep_link text,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'read')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  read_at timestamptz
);

alter table notification_preferences enable row level security;
alter table notification_device_tokens enable row level security;
alter table notification_events enable row level security;

drop policy if exists "notification preferences own read" on notification_preferences;
create policy "notification preferences own read" on notification_preferences
for select using (user_id = auth.uid());

drop policy if exists "notification preferences own upsert" on notification_preferences;
create policy "notification preferences own upsert" on notification_preferences
for insert with check (user_id = auth.uid());

drop policy if exists "notification preferences own update" on notification_preferences;
create policy "notification preferences own update" on notification_preferences
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "notification device own read" on notification_device_tokens;
create policy "notification device own read" on notification_device_tokens
for select using (user_id = auth.uid());

drop policy if exists "notification device own insert" on notification_device_tokens;
create policy "notification device own insert" on notification_device_tokens
for insert with check (user_id = auth.uid());

drop policy if exists "notification device own update" on notification_device_tokens;
create policy "notification device own update" on notification_device_tokens
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "notification events own read" on notification_events;
create policy "notification events own read" on notification_events
for select using (user_id = auth.uid());

drop policy if exists "notification events own update" on notification_events;
create policy "notification events own update" on notification_events
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create index if not exists notification_events_user_created_idx
on notification_events (user_id, created_at desc);

create or replace function register_notification_device(
  p_platform text,
  p_token_hash text,
  p_token_last_four text default null
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into notification_device_tokens (
    user_id,
    platform,
    token_hash,
    token_last_four,
    enabled,
    last_seen_at,
    updated_at
  )
  values (
    auth.uid(),
    p_platform,
    p_token_hash,
    p_token_last_four,
    true,
    now(),
    now()
  )
  on conflict (user_id, token_hash)
  do update set
    platform = excluded.platform,
    token_last_four = excluded.token_last_four,
    enabled = true,
    last_seen_at = now(),
    updated_at = now();
$$;

create or replace function mark_notification_event_read(p_event_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update notification_events
  set status = 'read',
      read_at = now()
  where id = p_event_id
    and user_id = auth.uid();
$$;

create or replace function enqueue_notification_event(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_collection_id uuid default null,
  p_deep_link text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_id uuid;
begin
  insert into notification_events (
    user_id,
    collection_id,
    type,
    title,
    body,
    deep_link
  )
  values (
    p_user_id,
    p_collection_id,
    p_type,
    p_title,
    p_body,
    p_deep_link
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;

grant execute on function register_notification_device(text, text, text) to authenticated;
grant execute on function mark_notification_event_read(uuid) to authenticated;
grant execute on function enqueue_notification_event(uuid, text, text, text, uuid, text) to service_role;
