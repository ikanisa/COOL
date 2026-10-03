begin;

-- App/API users mutate token registration only through the validated RPCs.
-- Database/service administrators retain their existing trusted capabilities.
revoke all on public.notification_device_tokens from public, anon, authenticated;

-- Worker RPCs and token registration share device -> delivery -> event lock order.
-- A fence survives disabled-device cancellation until its expiry: signing out
-- cannot make an in-flight token immediately reusable by a different account.
alter table public.notification_deliveries
  add column claim_token uuid,
  add column claim_expires_at timestamptz,
  add column claim_user_id uuid;
update public.notification_deliveries delivery
set claim_token = gen_random_uuid(),
    claim_expires_at = coalesce(delivery.last_attempt_at, clock_timestamp()) + interval '5 minutes',
    claim_user_id = event.user_id
from public.notification_events event
where delivery.event_id = event.id and delivery.status = 'processing';
alter table public.notification_deliveries add constraint notification_delivery_claim_fields
check ((claim_token is null and claim_expires_at is null and claim_user_id is null)
    or (claim_token is not null and claim_expires_at is not null and claim_user_id is not null));

create function public._refresh_notification_event(p_event_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from public.notification_events where id = p_event_id for update;
  update public.notification_events event
  set status = case
        when event.status = 'read' then 'read'
        when exists (select 1 from public.notification_deliveries d
          where d.event_id = event.id and d.status = 'sent') then 'sent'
        when exists (select 1 from public.notification_deliveries d
          where d.event_id = event.id and d.status in ('queued', 'processing')) then 'queued'
        else 'failed' end,
      sent_at = coalesce(event.sent_at, (select min(d.sent_at)
        from public.notification_deliveries d where d.event_id = event.id and d.status = 'sent')),
      last_error_code = case when exists (select 1 from public.notification_deliveries d
        where d.event_id = event.id and d.status = 'sent') then null
        else (select d.last_error_code from public.notification_deliveries d
          where d.event_id = event.id order by d.updated_at desc, d.id limit 1) end
  where event.id = p_event_id;
end $$;
revoke all on function public._refresh_notification_event(uuid) from public, anon, authenticated, service_role;

create function public.guard_notification_device_transition()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  identity_changed boolean := row(new.id, new.user_id, new.provider, new.platform, new.token_hash, new.token, new.environment)
    is distinct from row(old.id, old.user_id, old.provider, old.platform, old.token_hash, old.token, old.environment);
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
create trigger guard_notification_device_transition_trigger
before update on public.notification_device_tokens
for each row execute function public.guard_notification_device_transition();
revoke all on function public.guard_notification_device_transition() from public, anon, authenticated, service_role;

-- A required version prevents old workers from claiming and sending without a fence.
drop function public.claim_notification_deliveries(integer);
create function public.claim_notification_deliveries(p_contract_version integer, p_limit integer)
returns table (
  delivery_id uuid, event_id uuid, device_id uuid, token text, provider text,
  environment text, title text, body text, deep_link text, event_type text,
  attempt_number integer, claim_token uuid
)
language plpgsql security definer set search_path = public as $$
declare
  device_ids uuid[];
  changed_events uuid[] := '{}';
  claimed_ids uuid[] := '{}';
  candidate record;
  affected_event uuid;
  batch_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  current_time_value timestamptz := clock_timestamp();
  final_status text;
  reason text;
begin
  if p_contract_version is distinct from 1 then
    raise exception 'notification_claim_contract_unsupported';
  end if;
  -- Acquire all device locks before touching deliveries. SKIP LOCKED allows
  -- independent devices to make progress during registration or completion.
  select array_agg(locked.id) into device_ids from (
    select device.id from public.notification_device_tokens device
    where exists (select 1 from public.notification_deliveries d
      where d.device_id = device.id and (
        (d.status = 'queued' and d.next_attempt_at <= current_time_value)
        or (d.status = 'processing' and d.claim_expires_at <= current_time_value)))
    order by device.id for update of device skip locked limit batch_limit
  ) locked;
  for candidate in
    select d.*, device.enabled, device.provider, device.token,
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
    elsif candidate.attempt_count >= 5 then
      reason := 'attempts_exhausted';
    elsif candidate.status = 'processing' then
      reason := 'claim_timeout';
    end if;
    if reason is not null then
      final_status := case when reason = 'claim_timeout' then 'queued' else 'failed' end;
      update public.notification_deliveries d set status = final_status,
        next_attempt_at = case when final_status = 'queued' then current_time_value +
          make_interval(secs => least(3600, 30 * (2 ^ candidate.attempt_count)::integer))
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
  return query select d.id, event.id, device.id, device.token, device.provider,
    device.environment, event.title, event.body, event.deep_link, event.type,
    d.attempt_count, d.claim_token
  from public.notification_deliveries d
  join public.notification_events event on event.id = d.event_id
  join public.notification_device_tokens device on device.id = d.device_id
  where d.id = any(claimed_ids) order by d.next_attempt_at, d.created_at, d.id;
end $$;
revoke all on function public.claim_notification_deliveries(integer, integer) from public, anon, authenticated;
grant execute on function public.claim_notification_deliveries(integer, integer) to service_role;

-- Check again immediately before provider work. Token transitions are fenced
-- while a claim is live; this additionally rejects sign-out and expired workers.
create function public.notification_delivery_is_current(
  p_delivery_id uuid, p_claim_token uuid, p_attempt_number integer
) returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.notification_deliveries d
    join public.notification_events event on event.id = d.event_id
    join public.notification_device_tokens device on device.id = d.device_id
    where d.id = p_delivery_id and d.status = 'processing'
      and d.claim_token = p_claim_token and d.attempt_count = p_attempt_number
      and d.claim_expires_at > clock_timestamp() + interval '30 seconds'
      and d.claim_user_id = event.user_id and event.user_id = device.user_id
      and device.enabled and device.token is not null and device.provider in ('apns', 'fcm'));
$$;
revoke all on function public.notification_delivery_is_current(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.notification_delivery_is_current(uuid, uuid, integer) to service_role;

-- Old deployments must stop rather than write an unfenced completion.
drop function public.complete_notification_delivery(uuid, boolean, boolean, text, text, integer);
create function public.complete_notification_delivery(
  p_delivery_id uuid, p_claim_token uuid, p_attempt_number integer,
  p_success boolean, p_retryable boolean default false,
  p_provider_message_id text default null, p_error_code text default null,
  p_latency_ms integer default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  delivery_row public.notification_deliveries;
  device_row public.notification_device_tokens;
  final_status text;
begin
  if p_success is null or p_retryable is null or p_claim_token is null
    or p_attempt_number is null or p_attempt_number < 1 or p_attempt_number > 5 then
    raise exception 'notification_delivery_invalid_completion';
  end if;
  select device.* into device_row from public.notification_device_tokens device
    join public.notification_deliveries d on d.device_id = device.id
    where d.id = p_delivery_id for update of device;
  if not found then raise exception 'notification_delivery_not_claimed'; end if;
  select * into delivery_row from public.notification_deliveries where id = p_delivery_id for update;
  if not found or delivery_row.status <> 'processing'
    or delivery_row.claim_token is distinct from p_claim_token
    or delivery_row.attempt_count is distinct from p_attempt_number
    or delivery_row.claim_expires_at is null or delivery_row.claim_expires_at <= clock_timestamp()
    or not device_row.enabled or device_row.user_id is distinct from delivery_row.claim_user_id
    or not exists (select 1 from public.notification_events e
      where e.id = delivery_row.event_id and e.user_id = delivery_row.claim_user_id) then
    raise exception 'notification_delivery_fence_lost';
  end if;
  final_status := case when p_success then 'sent'
    when p_retryable and delivery_row.attempt_count < 5 then 'queued' else 'failed' end;
  update public.notification_deliveries set status = final_status,
    next_attempt_at = case when final_status = 'queued' then clock_timestamp() +
      make_interval(secs => least(3600, 30 * (2 ^ delivery_row.attempt_count)::integer))
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
revoke all on function public.complete_notification_delivery(uuid, uuid, integer, boolean, boolean, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.complete_notification_delivery(uuid, uuid, integer, boolean, boolean, text, text, integer)
  to service_role;

-- Preserve attempt history on operator retry and never revive another user's
-- token or a canceled claim whose worker may still be sending.
create or replace function public.admin_retry_notification(p_event_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  reason text := trim(coalesce(p_reason, ''));
  device_ids uuid[];
  retried integer;
begin
  perform public.assert_admin_permission('notifications.manage');
  if reason = '' then raise exception 'Reason is required'; end if;
  select array_agg(locked.id) into device_ids from (
    select device.id from public.notification_device_tokens device
    join public.notification_events event on event.user_id = device.user_id and event.id = p_event_id
    where device.enabled and device.provider in ('apns', 'fcm') and device.token is not null
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

commit;
