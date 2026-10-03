begin;

alter table notification_device_tokens
  drop constraint if exists notification_device_tokens_provider_check;
alter table notification_device_tokens
  add constraint notification_device_tokens_provider_check
  check (provider in ('legacy_local', 'apns', 'fcm')) not valid;

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
  clean_token text := trim(coalesce(p_token, ''));
  clean_environment text := lower(trim(coalesce(p_environment, '')));
  token_digest text;
  registered_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not (
    (clean_platform = 'ios' and clean_provider = 'apns')
    or (clean_platform = 'android' and clean_provider = 'fcm')
  ) then
    raise exception 'unsupported_notification_transport';
  end if;
  if clean_environment not in ('sandbox', 'production') then
    raise exception 'invalid_notification_environment';
  end if;
  if clean_provider = 'apns' and (
    char_length(clean_token) < 64
    or char_length(clean_token) > 512
    or clean_token !~ '^[0-9A-Fa-f]+$'
  ) then
    raise exception 'invalid_notification_token';
  end if;
  if clean_provider = 'fcm' and (
    char_length(clean_token) < 20
    or char_length(clean_token) > 4096
    or clean_token !~ '^[A-Za-z0-9_:\-]+$'
  ) then
    raise exception 'invalid_notification_token';
  end if;

  token_digest := encode(digest(clean_token, 'sha256'), 'hex');
  insert into notification_device_tokens (
    user_id, platform, provider, token, token_hash, token_last_four,
    environment, locale, app_version, enabled, last_seen_at,
    last_registered_at, disabled_at, disabled_reason, updated_at
  ) values (
    current_user_id, clean_platform, clean_provider, clean_token, token_digest,
    right(clean_token, 4), clean_environment,
    coalesce(nullif(trim(p_locale), ''), 'en'),
    nullif(trim(coalesce(p_app_version, '')), ''), true, now(), now(), null,
    null, now()
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
  token_digest text := encode(digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
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
    and device.provider in ('apns', 'fcm')
    and device.token is not null
  on conflict (event_id, device_id) do nothing;
  return new;
end;
$$;

drop function if exists claim_notification_deliveries(integer);
create function claim_notification_deliveries(p_limit integer default 100)
returns table (
  delivery_id uuid,
  event_id uuid,
  device_id uuid,
  token text,
  provider text,
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
    set status = 'queued', next_attempt_at = now(),
        last_error_code = 'claim_timeout', updated_at = now()
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
      and device.provider in ('apns', 'fcm')
      and device.token is not null
      and (select count(*) from recovered) >= 0
    order by delivery.next_attempt_at, delivery.created_at
    for update of delivery skip locked
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ), updated as (
    update notification_deliveries delivery
    set status = 'processing',
        attempt_count = delivery.attempt_count + 1,
        last_attempt_at = now(), updated_at = now()
    from claimed
    where delivery.id = claimed.id
    returning delivery.*
  )
  select updated.id, event.id, device.id, device.token, device.provider,
    device.environment, event.title, event.body, event.deep_link, event.type,
    updated.attempt_count
  from updated
  join notification_events event on event.id = updated.event_id
  join notification_device_tokens device on device.id = updated.device_id;
$$;

create or replace function disable_invalid_notification_device()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.error_code in (
    'BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered', 'UNREGISTERED'
  ) then
    update notification_device_tokens device
    set enabled = false,
        disabled_at = now(),
        disabled_reason = new.error_code,
        updated_at = now()
    from notification_deliveries delivery
    where delivery.id = new.delivery_id
      and device.id = delivery.device_id;
  end if;
  return new;
end;
$$;

drop trigger if exists disable_invalid_notification_device_trigger
  on notification_delivery_attempts;
create trigger disable_invalid_notification_device_trigger
after insert on notification_delivery_attempts
for each row execute function disable_invalid_notification_device();

revoke execute on function register_notification_device(text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function register_notification_device(text, text, text, text, text, text)
  to authenticated;
revoke execute on function unregister_notification_device(text, text)
  from public, anon, authenticated;
grant execute on function unregister_notification_device(text, text)
  to authenticated;
revoke execute on function queue_notification_event_deliveries()
  from public, anon, authenticated;
revoke execute on function claim_notification_deliveries(integer)
  from public, anon, authenticated;
grant execute on function claim_notification_deliveries(integer) to service_role;
revoke execute on function disable_invalid_notification_device()
  from public, anon, authenticated;

commit;
