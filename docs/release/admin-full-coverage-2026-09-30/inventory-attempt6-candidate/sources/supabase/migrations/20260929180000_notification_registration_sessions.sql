begin;

-- Global revocation gate precedes Auth, roster, device and delivery locks.
-- Namespace (193517,141) is distinct from scheduler (193517,139).
select pg_advisory_xact_lock(193517,141);
lock table auth.users in share row exclusive mode;
lock table auth.sessions in share row exclusive mode;
lock table public.notification_device_tokens in share row exclusive mode;

-- Preserve the revoked session ID as evidence; no FK may cascade/delete the
-- token or delivery history. Existing rows get no guessed session backfill.
alter table public.notification_device_tokens add column registration_session_id uuid,
  add column registration_session_created_at timestamptz;
create index notification_device_registration_session_idx
  on public.notification_device_tokens(registration_session_id) where registration_session_id is not null;


-- Notification operations share this gate. A bulk Auth mutation takes it
-- exclusively BEFORE locking its first row, so it cannot interleave opposite
-- per-session/device lock orders across rows. Provider HTTP is outside SQL.
create function public._lock_notification_session_gate()
returns void language sql security definer set search_path='' as $$
  select pg_catalog.pg_advisory_xact_lock_shared(193517,141);
$$;
revoke all on function public._lock_notification_session_gate() from public,anon,authenticated,service_role;

create function public.lock_notification_auth_revocation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- A multi-statement Auth transaction may already hold a shared activity
  -- gate. Never wait while upgrading that lock: another shared reader could
  -- be waiting for this transaction's Auth row. Abort atomically for a whole
  -- transaction retry instead of forming an upgrade deadlock.
  if exists(select 1 from pg_catalog.pg_locks where locktype='advisory'
      and pid=pg_catalog.pg_backend_pid() and classid=193517 and objid=141
      and objsubid=2 and mode='ShareLock' and granted)
    and not exists(select 1 from pg_catalog.pg_locks where locktype='advisory'
      and pid=pg_catalog.pg_backend_pid() and classid=193517 and objid=141
      and objsubid=2 and mode='ExclusiveLock' and granted) then
    if not pg_catalog.pg_try_advisory_xact_lock(193517,141) then
      raise exception 'notification_auth_revocation_retry' using errcode='40001';
    end if;
  else
    perform pg_catalog.pg_advisory_xact_lock(193517,141);
  end if;
  return null;
end $$;
revoke all on function public.lock_notification_auth_revocation() from public,anon,authenticated,service_role;
create trigger a_notification_auth_session_revocation_gate
before delete or update of id,user_id,created_at,aal,not_after on auth.sessions
for each statement execute function public.lock_notification_auth_revocation();
-- DELETE is gated before the user row and its cascading session/profile work.
-- Refresh metadata/last_sign_in_at updates share the activity gate below;
-- they do not acquire an exclusive gate or disable notification tokens.
create trigger a_notification_auth_user_revocation_gate
before delete or update of id,phone,phone_confirmed_at,email_confirmed_at,deleted_at,banned_until,is_anonymous on auth.users
for each statement execute function public.lock_notification_auth_revocation();

-- Even ordinary Auth writes must enter the shared gate before their row/FK
-- locks: a later revocation in the same transaction uses the safe upgrade
-- above. Alphabetical trigger order acquires an exclusive revocation gate
-- first when both triggers apply; no shared-to-exclusive upgrade is needed
-- for a standalone logout or ban.
create function public.lock_notification_auth_activity()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform public._lock_notification_session_gate();
  return null;
end $$;
revoke all on function public.lock_notification_auth_activity() from public,anon,authenticated,service_role;
create trigger b_notification_auth_user_activity_gate
before insert or update or delete on auth.users
for each statement execute function public.lock_notification_auth_activity();
create trigger b_notification_auth_session_activity_gate
before insert or update or delete on auth.sessions
for each statement execute function public.lock_notification_auth_activity();

create function public._notification_session_is_live(p_session uuid, p_user uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists(select 1 from auth.sessions s join auth.users u on u.id=s.user_id
    where s.id=p_session and s.user_id=p_user and s.created_at is not null and isfinite(s.created_at)
      and s.aal::text in ('aal1','aal2')
      and (s.not_after is null or s.not_after>clock_timestamp())
      and u.deleted_at is null and not coalesce(u.is_anonymous,false)
      and (u.phone_confirmed_at is not null or u.email_confirmed_at is not null)
      and (u.banned_until is null or u.banned_until<=clock_timestamp()));
$$;
revoke all on function public._notification_session_is_live(uuid,uuid) from public,anon,authenticated,service_role;

create function public._lock_notification_registration_session()
returns uuid language plpgsql security definer set search_path = public as $$
declare session_text text:=auth.jwt()->>'session_id'; session_id uuid; begin
  perform public._lock_notification_session_gate();
  if auth.role() is distinct from 'authenticated' or auth.uid() is null
    or session_text is null or session_text !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
    raise exception 'notification_registration_session_required' using errcode='42501';
  end if;
  session_id:=session_text::uuid;
  -- SHARE blocks both deletion and non-key revocation updates before we lock
  -- a token. A late registration sees the deletion after waiting and refuses.
  perform 1 from auth.sessions s where s.id=session_id and s.user_id=auth.uid() for share;
  if not found or not public._notification_session_is_live(session_id,auth.uid()) then
    raise exception 'notification_registration_session_required' using errcode='42501';
  end if;
  return session_id;
end $$;
revoke all on function public._lock_notification_registration_session() from public,anon,authenticated,service_role;

create or replace function public.guard_notification_device_transition()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  identity_changed boolean := row(new.id, new.user_id, new.provider, new.platform, new.token_hash, new.token, new.environment, new.registration_session_id, new.registration_session_created_at)
    is distinct from row(old.id, old.user_id, old.provider, old.platform, old.token_hash, old.token, old.environment, old.registration_session_id, old.registration_session_created_at);
  affected_event uuid;
  delivery_row public.notification_deliveries;
  reason text;
begin
  if not identity_changed and not (old.enabled and not new.enabled) then return new; end if;
  if identity_changed and exists (select 1 from public.notification_deliveries d
      where d.device_id = old.id and d.claim_expires_at > clock_timestamp()) then
    raise exception 'notification_device_in_flight';
  end if;
  reason := case when identity_changed then 'device_owner_or_route_changed' else 'device_disabled' end;
  for delivery_row in select * from public.notification_deliveries d
      where d.device_id = old.id and d.status in ('queued', 'processing')
      order by d.id for update loop
    update public.notification_deliveries set status = 'failed', last_error_code = reason,
      updated_at = clock_timestamp()
    where id = delivery_row.id;
    if delivery_row.status = 'processing' and delivery_row.attempt_count > 0 then
      insert into public.notification_delivery_attempts(delivery_id, attempt_number, outcome, error_code)
      values (delivery_row.id, delivery_row.prior_attempt_count + delivery_row.attempt_count, 'failed', reason)
      on conflict on constraint notification_delivery_attempts_delivery_id_attempt_number_key do nothing;
    end if;
  end loop;
  for affected_event in select distinct d.event_id from public.notification_deliveries d
      where d.device_id = old.id order by d.event_id loop
    perform public._refresh_notification_event(affected_event);
  end loop;
  return new;
end $$;
revoke all on function public.guard_notification_device_transition() from public, anon, authenticated, service_role;


-- Disable existing unbound tokens and cancel pending work via the existing
-- device guard. Live expiry fences and cumulative attempt records are retained.
update public.notification_device_tokens set enabled=false, disabled_at=clock_timestamp(),
  disabled_reason='registration_session_required', updated_at=clock_timestamp()
where registration_session_id is null and enabled;
alter table public.notification_device_tokens add constraint notification_device_session_binding_check
  check(not enabled or (registration_session_id is not null and registration_session_created_at is not null
    and isfinite(registration_session_created_at)));

create function public.revoke_notification_session_devices()
returns trigger language plpgsql security definer set search_path = public as $$
declare device_id uuid; begin
  if tg_op='UPDATE' and new.id=old.id and new.user_id=old.user_id
    and new.created_at is not distinct from old.created_at
    and new.aal::text in ('aal1','aal2')
    and (new.not_after is null or new.not_after>clock_timestamp()) then return new; end if;
  -- The Auth row is already locked by DELETE/UPDATE. Stable device order matches
  -- worker and registration session -> device -> delivery/event locking.
  for device_id in select device.id from public.notification_device_tokens device
      where device.registration_session_id=old.id order by device.id for update loop
    update public.notification_device_tokens set enabled=false, disabled_at=clock_timestamp(),
      disabled_reason='registration_session_revoked', updated_at=clock_timestamp()
    where id=device_id and registration_session_id=old.id;
  end loop;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
revoke all on function public.revoke_notification_session_devices() from public,anon,authenticated,service_role;
create trigger revoke_notification_session_devices_trigger
before delete or update of id,user_id,created_at,aal,not_after on auth.sessions
for each row execute function public.revoke_notification_session_devices();


-- Ordinary Auth banning/deletion/identity revocation also cancels queued work.
-- Only current ownership is disabled; A revocation never disables B's token.
create function public.revoke_notification_user_devices()
returns trigger language plpgsql security definer set search_path=public as $$
declare device_id uuid;
begin
  if new.id=old.id and new.deleted_at is null and not coalesce(new.is_anonymous,false)
    and (new.phone_confirmed_at is not null or new.email_confirmed_at is not null)
    and (new.banned_until is null or new.banned_until<=clock_timestamp()) then return new; end if;
  for device_id in select device.id from public.notification_device_tokens device
      where device.user_id=old.id and device.enabled order by device.id for update loop
    update public.notification_device_tokens set enabled=false,disabled_at=clock_timestamp(),
      disabled_reason='registration_user_revoked',updated_at=clock_timestamp()
      where id=device_id and user_id=old.id and enabled;
  end loop;
  return new;
end $$;
revoke all on function public.revoke_notification_user_devices() from public,anon,authenticated,service_role;
create trigger revoke_notification_user_devices_trigger
before update of id,phone_confirmed_at,email_confirmed_at,deleted_at,banned_until,is_anonymous on auth.users
for each row execute function public.revoke_notification_user_devices();

create or replace function public.register_notification_device(
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
  current_session_id uuid;
  current_session_created_at timestamptz;
  clean_platform text := lower(trim(coalesce(p_platform, '')));
  clean_provider text := lower(trim(coalesce(p_provider, '')));
  clean_token text := trim(coalesce(p_token, ''));
  clean_environment text := lower(trim(coalesce(p_environment, '')));
  token_digest text;
  registered_id uuid;
begin
  current_session_id := public._lock_notification_registration_session();
  select created_at into strict current_session_created_at from auth.sessions where id=current_session_id;
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

  token_digest := encode(extensions.digest(clean_token, 'sha256'), 'hex');
  insert into notification_device_tokens (
    user_id, registration_session_id, registration_session_created_at, platform, provider, token, token_hash, token_last_four,
    environment, locale, app_version, enabled, last_seen_at,
    last_registered_at, disabled_at, disabled_reason, updated_at
  ) values (
    current_user_id, current_session_id, current_session_created_at, clean_platform, clean_provider, clean_token, token_digest,
    right(clean_token, 4), clean_environment,
    coalesce(nullif(trim(p_locale), ''), 'en'),
    nullif(trim(coalesce(p_app_version, '')), ''), true, now(), now(), null,
    null, now()
  )
  on conflict (provider, token_hash)
  do update set
    user_id = excluded.user_id,
    registration_session_id = excluded.registration_session_id,
    registration_session_created_at = excluded.registration_session_created_at,
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
  -- Compare after acquiring the conflicting token row lock. A delayed request
  -- from a still-live older session cannot undo a newer account/session switch.
  where notification_device_tokens.registration_session_id=excluded.registration_session_id
     or notification_device_tokens.registration_session_created_at is null
     or excluded.registration_session_created_at>notification_device_tokens.registration_session_created_at
  returning id into registered_id;
  if registered_id is null then
    raise exception 'notification_registration_session_stale' using errcode='42501';
  end if;
  return registered_id;
end;
$$;

create or replace function public.unregister_notification_device(
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
  current_session_id uuid;
  clean_provider text := lower(trim(coalesce(p_provider, '')));
  token_digest text := encode(
    extensions.digest(trim(coalesce(p_token, '')), 'sha256'),
    'hex'
  );
begin
  current_session_id := public._lock_notification_registration_session();
  update notification_device_tokens
  set enabled = false,
      disabled_at = now(),
      disabled_reason = 'user_signed_out',
      updated_at = now()
  where user_id = current_user_id
    and registration_session_id = current_session_id
    and provider = clean_provider
    and token_hash = token_digest;
end;
$$;

revoke execute on function public.register_notification_device(text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.register_notification_device(text, text, text, text, text, text)
  to authenticated;
revoke execute on function public.unregister_notification_device(text, text)
  from public, anon, authenticated;
grant execute on function public.unregister_notification_device(text, text)
  to authenticated;


create or replace function public.claim_notification_deliveries(p_contract_version integer, p_limit integer)
returns table (
  delivery_id uuid, event_id uuid, device_id uuid, user_id uuid, token text, provider text,
  environment text, title text, body text, deep_link text, event_type text,
  attempt_number integer, claim_token uuid
)
language plpgsql security definer set search_path = public as $$
declare
  device_ids uuid[];
  session_ids uuid[];
  changed_events uuid[] := '{}';
  claimed_ids uuid[] := '{}';
  candidate record;
  affected_event uuid;
  batch_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  current_time_value timestamptz := clock_timestamp();
  final_status text;
  reason text;
begin
  perform public._lock_notification_session_gate();
  if p_contract_version is distinct from 2 then
    raise exception 'notification_claim_contract_unsupported';
  end if;
  -- Lock sessions before devices; skip a session being logged out rather than
  -- invert the Auth-trigger lock order. Missing bindings are terminalized below.
  select array_agg(locked.id) into session_ids from (
    select s.id from auth.sessions s where exists (
      select 1 from public.notification_device_tokens device
      join public.notification_deliveries d on d.device_id=device.id
      where device.registration_session_id=s.id and (
        (d.status='queued' and d.next_attempt_at<=current_time_value)
        or (d.status='processing' and d.claim_expires_at<=current_time_value)))
    order by s.id for share of s skip locked limit 500
  ) locked;
  select array_agg(locked.id) into device_ids from (
    select device.id from public.notification_device_tokens device
    where (device.registration_session_id=any(session_ids)
      or device.registration_session_id is null
      or not exists(select 1 from auth.sessions s where s.id=device.registration_session_id))
    and exists (select 1 from public.notification_deliveries d
      where d.device_id = device.id and (
        (d.status = 'queued' and d.next_attempt_at <= current_time_value)
        or (d.status = 'processing' and d.claim_expires_at <= current_time_value)))
    order by device.id for update of device skip locked limit batch_limit
  ) locked;
  for candidate in
    select d.*, device.enabled, device.provider, device.token, device.registration_session_id,
      device.user_id as device_user_id, event.user_id as event_user_id
    from public.notification_deliveries d
    join public.notification_device_tokens device on device.id = d.device_id
    join public.notification_events event on event.id = d.event_id
    where d.device_id = any(device_ids) and (
      (d.status = 'queued' and d.next_attempt_at <= current_time_value)
      or (d.status = 'processing' and d.claim_expires_at <= current_time_value))
    order by d.next_attempt_at, d.created_at, d.id
    for update of d skip locked limit batch_limit
  loop
    reason := null;
    if candidate.event_user_id is distinct from candidate.device_user_id then
      reason := 'device_owner_changed';
    elsif not candidate.enabled or candidate.provider not in ('apns', 'fcm') or candidate.token is null then
      reason := 'device_unavailable';
    elsif not public._notification_session_is_live(candidate.registration_session_id,candidate.device_user_id) then
      reason := 'registration_session_revoked';
    elsif candidate.attempt_count >= 5 then
      reason := 'attempts_exhausted';
    elsif candidate.status = 'processing' then
      reason := 'claim_timeout';
    end if;
    if reason is not null then
      final_status := case when reason = 'claim_timeout' then 'queued' else 'failed' end;
      update public.notification_deliveries d set status = final_status,
        next_attempt_at = case when final_status = 'queued' then current_time_value +
          make_interval(secs => public._notification_retry_delay(candidate.attempt_count, null))
          else d.next_attempt_at end,
        claim_token = null, claim_expires_at = null, claim_user_id = null,
        last_error_code = reason, updated_at = current_time_value
      where d.id = candidate.id;
      if candidate.status = 'processing' and candidate.attempt_count > 0 then
        insert into public.notification_delivery_attempts(delivery_id, attempt_number, outcome, error_code)
        values (candidate.id, candidate.prior_attempt_count + candidate.attempt_count,
          case when final_status = 'queued' then 'retry' else 'failed' end, reason)
        on conflict on constraint notification_delivery_attempts_delivery_id_attempt_number_key do nothing;
      end if;
    else
      update public.notification_deliveries d set status = 'processing',
        attempt_count = d.attempt_count + 1, last_attempt_at = current_time_value,
        claim_token = gen_random_uuid(), claim_expires_at = current_time_value + interval '5 minutes',
        claim_user_id = candidate.event_user_id, updated_at = current_time_value
      where d.id = candidate.id;
      claimed_ids := array_append(claimed_ids, candidate.id);
    end if;
    changed_events := array_append(changed_events, candidate.event_id);
  end loop;
  for affected_event in select distinct unnest(changed_events) order by 1 loop
    perform public._refresh_notification_event(affected_event);
  end loop;
  return query select d.id, event.id, device.id, event.user_id, device.token, device.provider,
    device.environment, 'Collect'::text, 'Open Collect to view your updates'::text, event.deep_link, event.type,
    d.attempt_count, d.claim_token
  from public.notification_deliveries d
  join public.notification_events event on event.id = d.event_id
  join public.notification_device_tokens device on device.id = d.device_id
  where d.id = any(claimed_ids) order by d.next_attempt_at, d.created_at, d.id;
end $$;
revoke all on function public.claim_notification_deliveries(integer, integer) from public, anon, authenticated;
grant execute on function public.claim_notification_deliveries(integer, integer) to service_role;


-- A final pre-send check observes expiry even when no Auth UPDATE occurs.
create or replace function public.notification_delivery_is_current(
  p_delivery_id uuid, p_claim_token uuid, p_attempt_number integer
) returns boolean language plpgsql security definer set search_path = public as $$
declare session_id uuid; begin
  perform public._lock_notification_session_gate();
  select device.registration_session_id into session_id from public.notification_device_tokens device
    join public.notification_deliveries d on d.device_id=device.id where d.id=p_delivery_id;
  if session_id is null then return false; end if;
  perform 1 from auth.sessions s where s.id=session_id
    and (s.not_after is null or s.not_after>clock_timestamp()+interval '30 seconds') for share;
  if not found then return false; end if;
  return exists(select 1 from public.notification_deliveries d
    join public.notification_events event on event.id=d.event_id
    join public.notification_device_tokens device on device.id=d.device_id
    where d.id=p_delivery_id and d.status='processing' and d.claim_token=p_claim_token
      and d.attempt_count=p_attempt_number and d.claim_expires_at>clock_timestamp()+interval '30 seconds'
      and d.claim_user_id=event.user_id and event.user_id=device.user_id
      and device.enabled and device.token is not null and device.provider in ('apns','fcm')
      and device.registration_session_id=session_id
      and public._notification_session_is_live(session_id,device.user_id));
end $$;
revoke all on function public.notification_delivery_is_current(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.notification_delivery_is_current(uuid,uuid,integer) to service_role;

create or replace function public.complete_notification_delivery(
  p_delivery_id uuid, p_claim_token uuid, p_attempt_number integer,
  p_success boolean, p_retryable boolean default false,
  p_provider_message_id text default null, p_error_code text default null,
  p_latency_ms integer default null, p_retry_after_seconds integer default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  delivery_row public.notification_deliveries;
  device_row public.notification_device_tokens;
  final_status text;
  session_id uuid;
begin
  perform public._lock_notification_session_gate();
  if p_success is null or p_retryable is null or p_claim_token is null
    or p_retry_after_seconds < 0 or p_attempt_number is null or p_attempt_number < 1 or p_attempt_number > 5 then
    raise exception 'notification_delivery_invalid_completion';
  end if;
  select device.registration_session_id into session_id from public.notification_device_tokens device
    join public.notification_deliveries d on d.device_id=device.id where d.id=p_delivery_id;
  perform 1 from auth.sessions s where s.id=session_id for share;
  if not found then raise exception 'notification_delivery_fence_lost'; end if;
  select device.* into device_row from public.notification_device_tokens device
    join public.notification_deliveries d on d.device_id = device.id
    where d.id = p_delivery_id for update of device;
  if not found then raise exception 'notification_delivery_not_claimed'; end if;
  select * into delivery_row from public.notification_deliveries where id = p_delivery_id for update;
  if not found or delivery_row.status <> 'processing'
    or delivery_row.claim_token is distinct from p_claim_token
    or delivery_row.attempt_count is distinct from p_attempt_number
    or delivery_row.claim_expires_at is null or delivery_row.claim_expires_at <= clock_timestamp()
    or device_row.registration_session_id is distinct from session_id
    or not public._notification_session_is_live(session_id,device_row.user_id)
    or not device_row.enabled or device_row.user_id is distinct from delivery_row.claim_user_id
    or not exists (select 1 from public.notification_events e
      where e.id = delivery_row.event_id and e.user_id = delivery_row.claim_user_id) then
    raise exception 'notification_delivery_fence_lost';
  end if;
  final_status := case when p_success then 'sent'
    when p_retryable and coalesce(p_retry_after_seconds, 0) <= 3600 and delivery_row.attempt_count < 5 then 'queued' else 'failed' end;
  if not p_success and p_retry_after_seconds > 3600 then p_error_code := 'retry_after_exceeds_budget'; end if;
  update public.notification_deliveries set status = final_status,
    next_attempt_at = case when final_status = 'queued' then clock_timestamp() +
      make_interval(secs => public._notification_retry_delay(delivery_row.attempt_count, p_retry_after_seconds))
      else next_attempt_at end,
    sent_at = case when p_success then clock_timestamp() else sent_at end,
    provider_message_id = nullif(trim(coalesce(p_provider_message_id, '')), ''),
    last_error_code = nullif(trim(coalesce(p_error_code, '')), ''),
    claim_token = null, claim_expires_at = null, claim_user_id = null, updated_at = clock_timestamp()
  where id = p_delivery_id;
  insert into public.notification_delivery_attempts(delivery_id, attempt_number, outcome,
    provider_message_id, error_code, latency_ms)
  values (p_delivery_id, delivery_row.prior_attempt_count + delivery_row.attempt_count,
    case when p_success then 'sent' when final_status = 'queued' then 'retry' else 'failed' end,
    nullif(trim(coalesce(p_provider_message_id, '')), ''),
    nullif(trim(coalesce(p_error_code, '')), ''), p_latency_ms);
  perform public._refresh_notification_event(delivery_row.event_id);
end $$;
revoke all on function public.complete_notification_delivery(uuid, uuid, integer, boolean, boolean, text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.complete_notification_delivery(uuid, uuid, integer, boolean, boolean, text, text, integer, integer)
  to service_role;


create or replace function public.admin_retry_notification(p_event_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  reason text := trim(coalesce(p_reason, ''));
  device_ids uuid[];
  session_ids uuid[];
  retried integer;
begin
  perform public._lock_notification_session_gate();
  perform public.assert_admin_permission('notifications.manage');
  if reason = '' then raise exception 'Reason is required'; end if;
  select array_agg(locked.id) into session_ids from (
    select s.id from auth.sessions s where exists(select 1 from public.notification_device_tokens device
      join public.notification_deliveries d on d.device_id=device.id
      where device.registration_session_id=s.id and d.event_id=p_event_id and d.status='failed')
    order by s.id for share of s
  ) locked;
  select array_agg(locked.id) into device_ids from (
    select device.id from public.notification_device_tokens device
    join public.notification_events event on event.user_id = device.user_id and event.id = p_event_id
    where device.registration_session_id=any(session_ids)
      and public._notification_session_is_live(device.registration_session_id,device.user_id)
      and device.enabled and device.provider in ('apns', 'fcm') and device.token is not null
      and exists (select 1 from public.notification_deliveries d where d.device_id = device.id
        and d.event_id = p_event_id and d.status = 'failed'
        and (d.claim_expires_at is null or d.claim_expires_at <= clock_timestamp()))
    order by device.id for update of device
  ) locked;
  update public.notification_deliveries d set status = 'queued',
    prior_attempt_count = d.prior_attempt_count + d.attempt_count, attempt_count = 0,
    next_attempt_at = clock_timestamp(), last_attempt_at = null, sent_at = null,
    provider_message_id = null, last_error_code = null,
    claim_token = null, claim_expires_at = null, claim_user_id = null, updated_at = clock_timestamp()
  where d.event_id = p_event_id and d.device_id = any(device_ids) and d.status = 'failed'
    and (d.claim_expires_at is null or d.claim_expires_at <= clock_timestamp());
  get diagnostics retried = row_count;
  if retried = 0 then raise exception 'No retryable failed deliveries'; end if;
  perform public._refresh_notification_event(p_event_id);
  perform public.create_audit_log('notification.delivery.retried', 'notification_event', p_event_id,
    jsonb_build_object('reason', reason, 'delivery_count', retried));
  return jsonb_build_object('ok', true, 'status', 'queued', 'delivery_count', retried);
end $$;


create or replace function public.admin_get_notification(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  perform public._lock_notification_session_gate();
  perform public.assert_admin_permission('notifications.read');
  return coalesce((
    select jsonb_build_object(
      'id', event.id,
      'type', event.type,
      'title', event.title,
      'status', event.status,
      'collect_id', profile.public_id,
      'collection_id', event.collection_id,
      'deep_link', event.deep_link,
      'delivery_statuses', coalesce((
        select string_agg(count_rows.status || ': ' || count_rows.delivery_count::text, ', ' order by count_rows.status)
        from (
          select status, count(*) as delivery_count
          from public.notification_deliveries
          where event_id = event.id
          group by status
        ) count_rows
      ), 'No registered delivery'),
      'retryable_count', (
        select count(*)
        from public.notification_deliveries delivery
        join public.notification_device_tokens device on device.id = delivery.device_id
        where delivery.event_id = event.id
          and delivery.status = 'failed'
          and public._notification_session_is_live(device.registration_session_id,device.user_id)
          and device.enabled
          and device.user_id = event.user_id
          and device.provider in ('apns', 'fcm')
          and device.token is not null
          and (delivery.claim_expires_at is null
            or delivery.claim_expires_at <= clock_timestamp())
      ),
      'cumulative_attempt_count', coalesce((
        select sum(delivery.prior_attempt_count + delivery.attempt_count)
        from public.notification_deliveries delivery
        where delivery.event_id = event.id
      ), 0),
      'last_error_code', event.last_error_code,
      'created_at', event.created_at,
      'sent_at', event.sent_at,
      'read_at', event.read_at
    )
    from public.notification_events event
    join public.profiles profile on profile.id = event.user_id
    where event.id = p_id
  ), '{}'::jsonb);
end;
$$;

revoke execute on function public.admin_get_notification(uuid) from public, anon;
grant execute on function public.admin_get_notification(uuid) to authenticated;


-- These existing entry points can hold Auth rows and the Admin roster before
-- entering notification work (or another gated Admin helper). Gate them before
-- either lock family to avoid introducing a reconciliation/logout inversion.
create or replace function collect_security.require_reconciliation_actor()
returns uuid language plpgsql security definer set search_path='' as $$
declare session_text text:=auth.jwt()->>'session_id'; session_id uuid;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'authenticated' or auth.uid() is null
   or auth.jwt()->>'aal' is distinct from 'aal2' or session_text is null
   or session_text !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
  raise exception 'reconciliation_step_up_required' using errcode='42501';
 end if;
 session_id:=session_text::uuid;
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if not collect_security.reconciliation_actor_current(auth.uid(),session_id) then
  raise exception 'reconciliation_actor_unavailable' using errcode='42501';
 end if;
 return session_id;
end $$;

create or replace function public.finalize_approved_reconciliation_v2(p_review_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r collect_security.reconciliation_reviews; p public.payments; result jsonb;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'reconciliation_service_required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 select * into r from collect_security.reconciliation_reviews where id=p_review_id for update;
 if r.id is null or r.approved_by is null or r.approved_by=r.proposed_by
   or r.proposed_session_id is null or r.approved_session_id is null
   or not isfinite(r.occurred_at) or r.occurred_at>clock_timestamp()+interval '5 minutes' then
  raise exception 'reconciliation_approved_evidence_required' using errcode='22023'; end if;
 -- Recheck both recorded sessions as well as durable roles/identities.
 if not collect_security.reconciliation_actor_current(r.proposed_by,r.proposed_session_id)
   or not collect_security.reconciliation_actor_current(r.approved_by,r.approved_session_id) then
  raise exception 'reconciliation_actor_unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:'||r.payment_id::text,0));
 select * into p from public.payments where id=r.payment_id for update;
 if r.consumed_at is not null then
  return jsonb_build_object('review_id',r.id,'payment_id',r.payment_id,'replayed',true,
    'payment_status',p.status,'evidence_level','independently_reconciled');
 end if;
 if r.approved_at<clock_timestamp()-interval '15 minutes' or r.proposed_at<clock_timestamp()-interval '24 hours' then
  raise exception 'reconciliation_approval_expired' using errcode='22023'; end if;
 if p.id is null or p.status<>'review' or collect_security.reconciliation_fingerprint(p) is distinct from r.payment_fingerprint then
  raise exception 'reconciliation_payment_changed' using errcode='22023'; end if;
 result:=public.process_provider_finality_event(r.id,'payment.confirmed',r.evidence_sha256,p.id,
   p.provider_network,p.transaction_id,r.source_reference,p.receiver_momo_number_hash,p.amount_rwf,
   r.occurred_at,r.evidence_sha256,null,null);
 update collect_security.reconciliation_reviews set consumed_at=clock_timestamp() where id=r.id;
 perform public.create_audit_log('reconciliation.finalized','payment',p.id,
  jsonb_build_object('review_id',r.id,'evidence_sha256',r.evidence_sha256,
    'proposed_by',r.proposed_by,'approved_by',r.approved_by),r.approved_by);
 return result||jsonb_build_object('review_id',r.id,'payment_status','posted','evidence_level','independently_reconciled');
end $$;

create or replace function collect_admin_access.approve_whatsapp(
  p_user uuid,p_phone text,p_reason text,p_expires_at timestamptz,p_bootstrap boolean
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  phone text := btrim(coalesce(p_phone,''));
  reason_text text := btrim(coalesce(p_reason,''));
  prior collect_admin_access.whatsapp_approvals%rowtype;
begin
 perform public._lock_notification_session_gate();
  -- All access/approval mutations serialize, and caller authority is checked
  -- AFTER waiting so a revoked operator cannot finish a queued grant.
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  if p_bootstrap then
    if auth.jwt()->>'role' is distinct from 'service_role' then
      raise exception 'Service role required' using errcode='42501';
    end if;
    if exists(select 1 from public.admin_user_roles ur join public.admin_roles r on r.id=ur.role_id
      where ur.revoked_at is null and r.name='platform_owner'
        and collect_admin_access.approved_identity(ur.user_id)) then
      raise exception 'An approved Admin already exists' using errcode='42501';
    end if;
  else
    perform public.assert_admin_permission('admin_users.manage');
    if p_user=auth.uid() then
      raise exception 'Another Admin must approve your identity' using errcode='42501';
    end if;
  end if;
  if length(reason_text) not between 1 and 1000
    or phone !~ '^\+[1-9][0-9]{7,14}$'
    or (p_expires_at is not null and p_expires_at <= clock_timestamp()) then
    raise exception 'Verified international WhatsApp number and reason required' using errcode='22023';
  end if;
  perform 1 from auth.users where id=p_user for update;
  if phone is distinct from collect_admin_access.verified_phone(p_user) then
    raise exception 'WhatsApp identity could not be verified' using errcode='22023';
  end if;
  select * into prior from collect_admin_access.whatsapp_approvals where user_id=p_user;
  if prior.user_id is not null and prior.revoked_at is null and prior.phone_e164=phone
    and prior.expires_at is not distinct from p_expires_at
    and (prior.expires_at is null or prior.expires_at > statement_timestamp()) then
    return jsonb_build_object('ok',true,'status','approved','user_id',p_user);
  end if;
  insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_by,reason,expires_at)
  values(p_user,phone,auth.uid(),reason_text,p_expires_at)
  on conflict(user_id) do update set phone_e164=excluded.phone_e164,
    approved_at=clock_timestamp(),approved_by=excluded.approved_by,reason=excluded.reason,
    expires_at=excluded.expires_at,revoked_at=null,revoked_by=null,revoke_reason=null;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'admin.whatsapp.approved','profile',p_user,
    jsonb_build_object('phone_masked',public.mask_phone(phone),'reason',reason_text,
      'expires_at',p_expires_at,'service_bootstrap',p_bootstrap));
  -- Approval alone never creates or reactivates an Admin role.
  return jsonb_build_object('ok',true,'status','approved','user_id',p_user);
end;
$$;

create or replace function collect_admin_access.set_user_access(p_user uuid,p_active boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_role_id uuid; reason_text text := btrim(coalesce(p_reason,''));
begin
 perform public._lock_notification_session_gate();
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  perform public.assert_admin_permission('admin_users.manage');
  if p_active is null or length(reason_text) not between 1 and 1000 then
    raise exception 'Active state and reason are required' using errcode='22023';
  end if;
  select id into v_role_id from public.admin_roles where name='platform_owner';
  if v_role_id is null or not exists(select 1 from public.profiles where id=p_user) then
    raise exception 'Admin account unavailable' using errcode='22023';
  end if;
  if p_active then
    perform 1 from auth.users where id=p_user for update;
    if not collect_admin_access.approved_identity(p_user) then
      raise exception 'Pre-approved verified WhatsApp identity required' using errcode='42501';
    end if;
    if not exists(select 1 from public.admin_user_roles ur
      where ur.user_id=p_user and ur.role_id=v_role_id and ur.revoked_at is null) then
      insert into public.admin_user_roles(user_id,role_id,granted_by,reason,created_at)
      values(p_user,v_role_id,auth.uid(),reason_text,clock_timestamp());
      insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
      values(auth.uid(),'admin.access.activated','profile',p_user,jsonb_build_object('reason',reason_text));
    end if;
    return jsonb_build_object('ok',true,'status','active');
  end if;
  if p_user=auth.uid() then
    raise exception 'You cannot deactivate your own Admin access' using errcode='42501';
  end if;
  -- The caller is an approved active Admin, so deactivating a different account
  -- cannot remove the last approved Admin. This remains true under the lock.
  update public.admin_user_roles ur set revoked_at=clock_timestamp(),revoked_by=auth.uid(),revoke_reason=reason_text
    where ur.user_id=p_user and ur.revoked_at is null;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'admin.access.deactivated','profile',p_user,jsonb_build_object('reason',reason_text));
  end if;
  return jsonb_build_object('ok',true,'status','revoked');
end;
$$;

create or replace function collect_admin_access.revoke_whatsapp(p_user uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare reason_text text := btrim(coalesce(p_reason,''));
begin
 perform public._lock_notification_session_gate();
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  perform public.assert_admin_permission('admin_users.manage');
  if p_user=auth.uid() then
    raise exception 'You cannot revoke your own WhatsApp approval' using errcode='42501';
  end if;
  if length(reason_text) not between 1 and 1000 then
    raise exception 'Reason required' using errcode='22023';
  end if;
  update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp(),revoked_by=auth.uid(),revoke_reason=reason_text
    where user_id=p_user and revoked_at is null;
  if found then
    perform collect_admin_access.set_user_access(p_user,false,reason_text);
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'admin.whatsapp.revoked','profile',p_user,jsonb_build_object('reason',reason_text));
  end if;
  return jsonb_build_object('ok',true,'status','revoked','user_id',p_user);
end;
$$;

create or replace function collect_admin_access.bootstrap_owner(p_user uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_role_id uuid;
begin
 perform public._lock_notification_session_gate();
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_reason,''))) not between 1 and 1000
    or not collect_admin_access.approved_identity(p_user) then
    raise exception 'Pre-approved verified identity and reason required' using errcode='42501';
  end if;
  select id into v_role_id from public.admin_roles where name='platform_owner';
  if not exists(select 1 from public.admin_user_roles ur where ur.user_id=p_user
    and ur.role_id=v_role_id and ur.revoked_at is null) then
    insert into public.admin_user_roles(user_id,role_id,reason,created_at)
    values(p_user,v_role_id,p_reason,clock_timestamp());
    insert into public.audit_logs(action,entity_type,entity_id,metadata)
    values('admin.bootstrap.platform_owner','profile',p_user,jsonb_build_object('reason',p_reason));
  end if;
  return jsonb_build_object('ok',true);
end;
$$;


commit;
