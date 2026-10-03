begin;

-- Protocol 2 binds push payloads to the recipient and removes private preview
-- text. Quiesce old workers before deployment: already accepted/in-flight
-- provider requests cannot be recalled by a database migration.
lock table public.notification_device_tokens in share row exclusive mode;
lock table public.notification_deliveries in share row exclusive mode;

do $$ declare old_claim public.notification_deliveries; affected uuid; begin
  for old_claim in select * from public.notification_deliveries where status = 'processing' for update loop
    insert into public.notification_delivery_attempts(delivery_id, attempt_number, outcome, error_code)
    values (old_claim.id, old_claim.prior_attempt_count + old_claim.attempt_count,
      case when old_claim.attempt_count < 5 then 'retry' else 'failed' end, 'claim_protocol_upgraded')
    on conflict on constraint notification_delivery_attempts_delivery_id_attempt_number_key do nothing;
    update public.notification_deliveries set
      status = case when attempt_count < 5 then 'queued' else 'failed' end,
      next_attempt_at = greatest(next_attempt_at, claim_expires_at, clock_timestamp() + interval '60 seconds'),
      claim_token = gen_random_uuid(), last_error_code = 'claim_protocol_upgraded', updated_at = clock_timestamp()
    where id = old_claim.id;
    perform public._refresh_notification_event(old_claim.event_id);
  end loop;
end $$;

-- Positive jitter never violates a provider's Retry-After floor. An excessive
-- floor is terminalized by completion rather than silently retrying earlier.
create function public._notification_retry_delay(p_attempt integer, p_retry_after integer)
returns integer language plpgsql volatile set search_path = public as $$
declare floor_seconds integer; begin
  if p_attempt is null or p_attempt < 1 or p_attempt > 5 or p_retry_after < 0 or p_retry_after > 3600 then
    raise exception 'notification_retry_delay_invalid';
  end if;
  floor_seconds := greatest(least(3600, 30 * (2 ^ p_attempt)::integer), coalesce(p_retry_after, 0));
  return floor_seconds + floor(random() * (least(3600 - floor_seconds, greatest(1, floor_seconds / 4)) + 1))::integer;
end $$;
revoke all on function public._notification_retry_delay(integer, integer) from public, anon, authenticated, service_role;

drop function public.claim_notification_deliveries(integer, integer);
create function public.claim_notification_deliveries(p_contract_version integer, p_limit integer)
returns table (
  delivery_id uuid, event_id uuid, device_id uuid, user_id uuid, token text, provider text,
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
  if p_contract_version is distinct from 2 then
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

-- Preserve mandatory claim token/attempt fencing while adding a retry floor.
drop function public.complete_notification_delivery(uuid, uuid, integer, boolean, boolean, text, text, integer);
create function public.complete_notification_delivery(
  p_delivery_id uuid, p_claim_token uuid, p_attempt_number integer,
  p_success boolean, p_retryable boolean default false,
  p_provider_message_id text default null, p_error_code text default null,
  p_latency_ms integer default null, p_retry_after_seconds integer default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  delivery_row public.notification_deliveries;
  device_row public.notification_device_tokens;
  final_status text;
begin
  if p_success is null or p_retryable is null or p_claim_token is null
    or p_retry_after_seconds < 0 or p_attempt_number is null or p_attempt_number < 1 or p_attempt_number > 5 then
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

-- Supabase's documented pg_cron + pg_net + Vault pattern. Secrets are resolved
-- at execution, never embedded in cron.job commands, migrations or responses.
-- Provision these Vault names from the EXISTING verified project environment:
-- collect_notification_project_url       = SUPABASE_URL (canonical HTTPS URL)
-- collect_notification_api_key           = project publishable/anon API key
-- collect_notification_internal_secret   = INTERNAL_FUNCTION_SECRET
create function public._notification_dispatch_configuration()
returns jsonb language plpgsql security definer set search_path = public as $$
declare project_url text; api_key text; internal_secret text; begin
  if to_regclass('vault.decrypted_secrets') is null then
    raise exception 'notification_scheduler_not_configured';
  end if;
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'collect_notification_project_url';
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'collect_notification_api_key';
  select decrypted_secret into internal_secret from vault.decrypted_secrets where name = 'collect_notification_internal_secret';
  if project_url is null or project_url !~ '^https://[a-z0-9]{20}\.supabase\.co$'
    or coalesce(length(api_key), 0) < 20 or coalesce(length(internal_secret), 0) < 32
    or api_key ~ '[\r\n]' or internal_secret ~ '[\r\n]' then
    raise exception 'notification_scheduler_not_configured';
  end if;
  return jsonb_build_object('url', project_url || '/functions/v1/dispatch-notifications',
    'headers', jsonb_build_object('Content-Type', 'application/json', 'apikey', api_key, 'x-collect-signature', internal_secret));
end $$;
revoke all on function public._notification_dispatch_configuration() from public, anon, authenticated, service_role;

create function public.run_notification_dispatch_schedule()
returns bigint language plpgsql security definer set search_path = public as $$
declare config jsonb; request_id bigint; begin
  -- Prevent duplicate wake-ups inside one scheduler transaction. Claims remain
  -- independently fenced across overlapping Edge invocations.
  if not pg_try_advisory_xact_lock(193517, 139) then return null; end if;
  config := public._notification_dispatch_configuration();
  if not exists (select 1 from public.notification_deliveries d
    where (d.status = 'queued' and d.next_attempt_at <= clock_timestamp())
       or (d.status = 'processing' and d.claim_expires_at <= clock_timestamp())) then return null; end if;
  select net.http_post(url := config->>'url', headers := config->'headers',
    body := '{"limit":100}'::jsonb, timeout_milliseconds := 65000) into request_id;
  return request_id;
end $$;
revoke all on function public.run_notification_dispatch_schedule() from public, anon, authenticated, service_role;

create function public.configure_notification_dispatch_schedule(p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
declare job_id bigint; begin
  if p_enabled is null then raise exception 'notification_scheduler_enabled_required'; end if;
  if p_enabled then perform public._notification_dispatch_configuration(); end if;
  for job_id in select jobid from cron.job where jobname = 'collect-dispatch-notifications' loop
    perform cron.unschedule(job_id);
  end loop;
  job_id := cron.schedule('collect-dispatch-notifications', '* * * * *',
    'select public.run_notification_dispatch_schedule();');
  perform cron.alter_job(job_id, active := p_enabled);
end $$;
revoke all on function public.configure_notification_dispatch_schedule(boolean) from public, anon, authenticated, service_role;

-- Source is installed deterministically but activation requires verified Vault
-- configuration and coordinated worker rollout. Applying SQL never invents
-- credentials or starts provider calls on an unconfigured environment.
select public.configure_notification_dispatch_schedule(false);

commit;
