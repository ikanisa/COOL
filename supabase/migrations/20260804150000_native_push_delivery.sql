begin;

alter table notification_device_tokens
  add column if not exists provider text not null default 'legacy_local',
  add column if not exists token text,
  add column if not exists environment text not null default 'production',
  add column if not exists locale text not null default 'en',
  add column if not exists app_version text,
  add column if not exists last_registered_at timestamptz not null default now(),
  add column if not exists disabled_at timestamptz,
  add column if not exists disabled_reason text;

update notification_device_tokens
set enabled = false,
    disabled_at = coalesce(disabled_at, now()),
    disabled_reason = coalesce(disabled_reason, 'legacy_token_not_deliverable')
where provider = 'legacy_local';

alter table notification_device_tokens
  drop constraint if exists notification_device_tokens_user_id_token_hash_key;

alter table notification_device_tokens
  drop constraint if exists notification_device_tokens_provider_check;
alter table notification_device_tokens
  add constraint notification_device_tokens_provider_check
  check (provider in ('legacy_local', 'apns')) not valid;

alter table notification_device_tokens
  drop constraint if exists notification_device_tokens_environment_check;
alter table notification_device_tokens
  add constraint notification_device_tokens_environment_check
  check (environment in ('sandbox', 'production')) not valid;

create unique index if not exists notification_device_tokens_provider_hash_uidx
  on notification_device_tokens (provider, token_hash);
create index if not exists notification_device_tokens_active_user_idx
  on notification_device_tokens (user_id, provider, environment, last_seen_at desc)
  where enabled;

drop policy if exists "notification device own read" on notification_device_tokens;
drop policy if exists "notification device own insert" on notification_device_tokens;
drop policy if exists "notification device own update" on notification_device_tokens;
revoke all on notification_device_tokens from anon, authenticated;

drop function if exists register_notification_device(text, text, text);

create or replace function register_notification_device(
  p_platform text,
  p_provider text,
  p_token text,
  p_environment text default 'production',
  p_locale text default 'en',
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  clean_platform text := lower(trim(coalesce(p_platform, '')));
  clean_provider text := lower(trim(coalesce(p_provider, '')));
  clean_token text := lower(trim(coalesce(p_token, '')));
  clean_environment text := lower(trim(coalesce(p_environment, '')));
  token_digest text;
  registered_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if clean_platform <> 'ios' or clean_provider <> 'apns' then
    raise exception 'unsupported_notification_transport';
  end if;
  if clean_environment not in ('sandbox', 'production') then
    raise exception 'invalid_notification_environment';
  end if;
  if char_length(clean_token) < 64
     or char_length(clean_token) > 512
     or clean_token !~ '^[0-9a-f]+$' then
    raise exception 'invalid_notification_token';
  end if;

  token_digest := encode(digest(clean_token, 'sha256'), 'hex');

  insert into notification_device_tokens (
    user_id,
    platform,
    provider,
    token,
    token_hash,
    token_last_four,
    environment,
    locale,
    app_version,
    enabled,
    last_seen_at,
    last_registered_at,
    disabled_at,
    disabled_reason,
    updated_at
  )
  values (
    current_user_id,
    clean_platform,
    clean_provider,
    clean_token,
    token_digest,
    right(clean_token, 4),
    clean_environment,
    coalesce(nullif(trim(p_locale), ''), 'en'),
    nullif(trim(coalesce(p_app_version, '')), ''),
    true,
    now(),
    now(),
    null,
    null,
    now()
  )
  on conflict (provider, token_hash)
  do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    token = excluded.token,
    token_last_four = excluded.token_last_four,
    environment = excluded.environment,
    locale = excluded.locale,
    app_version = excluded.app_version,
    enabled = true,
    last_seen_at = now(),
    last_registered_at = now(),
    disabled_at = null,
    disabled_reason = null,
    updated_at = now()
  returning id into registered_id;

  return registered_id;
end;
$$;

create or replace function unregister_notification_device(
  p_provider text,
  p_token text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  clean_provider text := lower(trim(coalesce(p_provider, '')));
  token_digest text := encode(
    digest(lower(trim(coalesce(p_token, ''))), 'sha256'),
    'hex'
  );
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  update notification_device_tokens
  set enabled = false,
      disabled_at = now(),
      disabled_reason = 'user_signed_out',
      updated_at = now()
  where user_id = current_user_id
    and provider = clean_provider
    and token_hash = token_digest;
end;
$$;

revoke execute on function register_notification_device(text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function register_notification_device(text, text, text, text, text, text)
  to authenticated;
revoke execute on function unregister_notification_device(text, text)
  from public, anon, authenticated;
grant execute on function unregister_notification_device(text, text)
  to authenticated;

alter table notification_events
  add column if not exists last_error_code text;

alter table notification_events
  drop constraint if exists notification_events_deep_link_check;
alter table notification_events
  add constraint notification_events_deep_link_check check (
    deep_link is null
    or deep_link ~ '^/(home|activity|groups(/[A-Za-z0-9_-]+(/(ledger|members|profile))?)?|settings/notifications)$'
  ) not valid;
alter table notification_events
  drop constraint if exists notification_events_copy_length_check;
alter table notification_events
  add constraint notification_events_copy_length_check check (
    char_length(trim(title)) between 1 and 120
    and char_length(trim(body)) between 1 and 500
  ) not valid;

drop policy if exists "notification events own update" on notification_events;
revoke update, insert, delete on notification_events from anon, authenticated;
grant select on notification_events to authenticated;

create table if not exists notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references notification_events(id) on delete cascade,
  device_id uuid not null references notification_device_tokens(id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz not null default now(),
  last_attempt_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, device_id)
);

create table if not exists notification_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references notification_deliveries(id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  outcome text not null check (outcome in ('sent', 'retry', 'failed')),
  provider_message_id text,
  error_code text,
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  attempted_at timestamptz not null default now(),
  unique (delivery_id, attempt_number)
);

create index if not exists notification_deliveries_claim_idx
  on notification_deliveries (status, next_attempt_at, created_at)
  where status in ('queued', 'processing');
create index if not exists notification_deliveries_device_idx
  on notification_deliveries (device_id);
create index if not exists notification_delivery_attempts_delivery_idx
  on notification_delivery_attempts (delivery_id, attempted_at desc);

alter table notification_deliveries enable row level security;
alter table notification_delivery_attempts enable row level security;
revoke all on notification_deliveries from public, anon, authenticated;
revoke all on notification_delivery_attempts from public, anon, authenticated;

create or replace function queue_notification_event_deliveries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notification_deliveries (event_id, device_id)
  select new.id, device.id
  from notification_device_tokens device
  where device.user_id = new.user_id
    and device.enabled
    and device.provider = 'apns'
    and device.token is not null
  on conflict (event_id, device_id) do nothing;
  return new;
end;
$$;

drop trigger if exists queue_notification_event_deliveries_trigger
  on notification_events;
create trigger queue_notification_event_deliveries_trigger
after insert on notification_events
for each row execute function queue_notification_event_deliveries();

create or replace function claim_notification_deliveries(p_limit integer default 100)
returns table (
  delivery_id uuid,
  event_id uuid,
  device_id uuid,
  token text,
  environment text,
  title text,
  body text,
  deep_link text,
  event_type text,
  attempt_number integer
)
language sql
security definer
set search_path = public
as $$
  with recovered as (
    update notification_deliveries stale
    set status = 'queued',
        next_attempt_at = now(),
        last_error_code = 'claim_timeout',
        updated_at = now()
    where stale.status = 'processing'
      and stale.last_attempt_at < now() - interval '5 minutes'
    returning stale.id
  ), claimed as (
    select delivery.id
    from notification_deliveries delivery
    join notification_device_tokens device on device.id = delivery.device_id
    where delivery.status = 'queued'
      and delivery.next_attempt_at <= now()
      and delivery.attempt_count < 5
      and device.enabled
      and device.provider = 'apns'
      and device.token is not null
      and (select count(*) from recovered) >= 0
    order by delivery.next_attempt_at, delivery.created_at
    for update of delivery skip locked
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ), updated as (
    update notification_deliveries delivery
    set status = 'processing',
        attempt_count = delivery.attempt_count + 1,
        last_attempt_at = now(),
        updated_at = now()
    from claimed
    where delivery.id = claimed.id
    returning delivery.*
  )
  select
    updated.id,
    event.id,
    device.id,
    device.token,
    device.environment,
    event.title,
    event.body,
    event.deep_link,
    event.type,
    updated.attempt_count
  from updated
  join notification_events event on event.id = updated.event_id
  join notification_device_tokens device on device.id = updated.device_id;
$$;

create or replace function complete_notification_delivery(
  p_delivery_id uuid,
  p_success boolean,
  p_retryable boolean default false,
  p_provider_message_id text default null,
  p_error_code text default null,
  p_latency_ms integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  delivery_row notification_deliveries;
  final_status text;
begin
  select * into delivery_row
  from notification_deliveries
  where id = p_delivery_id
  for update;
  if not found or delivery_row.status <> 'processing' then
    raise exception 'notification_delivery_not_claimed';
  end if;

  final_status := case
    when p_success then 'sent'
    when p_retryable and delivery_row.attempt_count < 5 then 'queued'
    else 'failed'
  end;

  update notification_deliveries
  set status = final_status,
      next_attempt_at = case
        when final_status = 'queued' then
          now() + make_interval(secs => least(3600, 30 * (2 ^ delivery_row.attempt_count)::integer))
        else next_attempt_at
      end,
      sent_at = case when p_success then now() else sent_at end,
      provider_message_id = nullif(trim(coalesce(p_provider_message_id, '')), ''),
      last_error_code = nullif(trim(coalesce(p_error_code, '')), ''),
      updated_at = now()
  where id = p_delivery_id;

  insert into notification_delivery_attempts (
    delivery_id,
    attempt_number,
    outcome,
    provider_message_id,
    error_code,
    latency_ms
  ) values (
    p_delivery_id,
    delivery_row.attempt_count,
    case when p_success then 'sent' when final_status = 'queued' then 'retry' else 'failed' end,
    nullif(trim(coalesce(p_provider_message_id, '')), ''),
    nullif(trim(coalesce(p_error_code, '')), ''),
    p_latency_ms
  );

  if not p_success and p_error_code in (
    'BadDeviceToken',
    'DeviceTokenNotForTopic',
    'Unregistered'
  ) then
    update notification_device_tokens
    set enabled = false,
        disabled_at = now(),
        disabled_reason = p_error_code,
        updated_at = now()
    where id = delivery_row.device_id;
  end if;

  update notification_events event
  set status = case
        when event.status = 'read' then 'read'
        when exists (
          select 1 from notification_deliveries sent
          where sent.event_id = event.id and sent.status = 'sent'
        ) then 'sent'
        when exists (
          select 1 from notification_deliveries pending
          where pending.event_id = event.id and pending.status in ('queued', 'processing')
        ) then 'queued'
        else 'failed'
      end,
      sent_at = case when p_success then coalesce(event.sent_at, now()) else event.sent_at end,
      last_error_code = case when p_success then null else nullif(trim(coalesce(p_error_code, '')), '') end
  where event.id = delivery_row.event_id;
end;
$$;

revoke execute on function queue_notification_event_deliveries()
  from public, anon, authenticated;
revoke execute on function claim_notification_deliveries(integer)
  from public, anon, authenticated;
grant execute on function claim_notification_deliveries(integer) to service_role;
revoke execute on function complete_notification_delivery(uuid, boolean, boolean, text, text, integer)
  from public, anon, authenticated;
grant execute on function complete_notification_delivery(uuid, boolean, boolean, text, text, integer)
  to service_role;

create or replace function enqueue_contribution_confirmation_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  group_title text;
begin
  if new.status <> 'posted' or new.contributor_user_id is null then
    return new;
  end if;
  select title into group_title from collections where id = new.collection_id;
  perform enqueue_notification_template_event(
    new.contributor_user_id,
    'contribution.confirmed.default',
    jsonb_build_object(
      'amount', 'RWF ' || new.amount_rwf::text,
      'group', coalesce(group_title, 'your group')
    ),
    new.collection_id,
    '/groups/' || new.collection_id::text || '/ledger',
    'en'
  );
  return new;
end;
$$;

drop trigger if exists enqueue_contribution_confirmation_notification_trigger
  on payments;
create trigger enqueue_contribution_confirmation_notification_trigger
after insert on payments
for each row execute function enqueue_contribution_confirmation_notification();
revoke execute on function enqueue_contribution_confirmation_notification()
  from public, anon, authenticated;

commit;
