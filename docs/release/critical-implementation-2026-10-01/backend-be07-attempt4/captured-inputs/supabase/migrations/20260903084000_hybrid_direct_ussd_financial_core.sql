begin;

-- Direct-USSD candidate matching is an additive, disabled-by-default path.
-- Receipt SMS never posts money by itself: every candidate still requires the
-- existing independent provider-confirmation control.
insert into public.feature_flags(key, enabled, description)
values (
  'hybrid_direct_ussd_allocation',
  false,
  'Pilot gate: allow exact MoMo name plus last-three matching only through an explicit active member receiving assignment'
)
on conflict (key) do nothing;

-- Keep installed clients on the existing receipt-ingestion contract until a
-- Play-Integrity-capable build has been distributed and accepted. The new
-- attested path is present after this migration, but the Edge functions only
-- require it after this independently controlled rollout flag is enabled.
insert into public.feature_flags(key, enabled, description)
values (
  'native_sms_attestation_enforcement',
  false,
  'Rollout gate: require a fresh Play Integrity capability for each Android MoMo receipt SMS envelope'
)
on conflict (key) do nothing;

-- Provider SMS is accepted as final evidence only after the exact native
-- envelope has been bound to a fresh Play Integrity verdict. A signed-in user
-- and an arbitrary client-supplied SMS body are not sufficient.
alter table public.native_action_capabilities
  drop constraint if exists native_action_capabilities_action_check;
alter table public.native_action_capabilities
  add constraint native_action_capabilities_action_check
  check (action in ('group.create', 'sms.ingest'));

alter table public.raw_payment_sms
  add column if not exists native_action_capability_id uuid
    references public.native_action_capabilities(id) on delete restrict,
  add column if not exists attestation_request_hash text
    check (attestation_request_hash is null or attestation_request_hash ~ '^[0-9a-f]{64}$'),
  add column if not exists device_attested_at timestamptz;

create unique index if not exists raw_payment_sms_native_capability_unique
  on public.raw_payment_sms(native_action_capability_id)
  where native_action_capability_id is not null;

create or replace function public.mint_native_action_capability(
  capability_user_id uuid,
  capability_action text,
  capability_request_hash text,
  capability_request_payload jsonb,
  capability_receiver_hash text,
  capability_package_name text,
  capability_app_verdict text,
  capability_device_verdicts text[],
  capability_verified_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  capability_id uuid;
  clean_action text := btrim(coalesce(capability_action, ''));
  clean_request_hash text := lower(btrim(coalesce(capability_request_hash, '')));
  clean_receiver_hash text := lower(btrim(coalesce(capability_receiver_hash, '')));
  clean_package_name text := btrim(coalesce(capability_package_name, ''));
  clean_app_verdict text := btrim(coalesce(capability_app_verdict, ''));
  verified_at_value timestamptz := coalesce(capability_verified_at, now());
  latest_consent public.receiver_mode_consents;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if capability_user_id is null
     or clean_action not in ('group.create', 'sms.ingest') then
    raise exception 'Invalid native capability subject or action';
  end if;
  if clean_request_hash !~ '^[0-9a-f]{64}$'
     or clean_receiver_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid native capability binding';
  end if;
  if jsonb_typeof(capability_request_payload) <> 'object'
     or capability_request_payload ->> 'receiver_momo_number_hash'
       <> clean_receiver_hash then
    raise exception 'Invalid native capability request payload';
  end if;
  if clean_action = 'sms.ingest' and not (
    capability_request_payload ? 'client_envelope_id'
    and capability_request_payload ? 'raw_sender'
    and capability_request_payload ? 'raw_body_sha256'
    and capability_request_payload ->> 'raw_body_sha256' ~ '^[0-9a-f]{64}$'
  ) then
    raise exception 'Invalid attested SMS request payload';
  end if;
  if clean_package_name <> 'app.cool.mobile'
     or clean_app_verdict <> 'PLAY_RECOGNIZED'
     or not (
       'MEETS_DEVICE_INTEGRITY' = any(coalesce(capability_device_verdicts, '{}'))
       or 'MEETS_STRONG_INTEGRITY' = any(coalesce(capability_device_verdicts, '{}'))
     ) then
    raise exception 'Play Integrity verdict is not eligible';
  end if;
  if abs(extract(epoch from (now() - verified_at_value))) > 300 then
    raise exception 'Play Integrity verdict is stale';
  end if;

  select consent.* into latest_consent
  from public.receiver_mode_consents consent
  where consent.user_id = capability_user_id
  order by consent.created_at desc, consent.id desc
  limit 1;
  if latest_consent.id is null
     or not latest_consent.enabled
     or lower(coalesce(latest_consent.momo_number_hash, '')) <> clean_receiver_hash
     or (clean_action = 'sms.ingest'
       and latest_consent.created_at < now() - interval '10 minutes') then
    raise exception 'Current MoMo SMS consent is required';
  end if;

  update public.native_action_capabilities
  set expires_at = least(expires_at, now())
  where user_id = capability_user_id
    and action = clean_action
    and consumed_at is null
    and expires_at > now();

  insert into public.native_action_capabilities(
    user_id, action, request_hash, request_payload,
    receiver_momo_number_hash, package_name, app_verdict,
    device_verdicts, verified_at, expires_at
  ) values (
    capability_user_id, clean_action, clean_request_hash,
    capability_request_payload, clean_receiver_hash, clean_package_name,
    clean_app_verdict, coalesce(capability_device_verdicts, '{}'),
    verified_at_value,
    least(verified_at_value + interval '5 minutes', now() + interval '5 minutes')
  ) returning id into capability_id;
  return capability_id;
end;
$$;

revoke all on function public.mint_native_action_capability(
  uuid, text, text, jsonb, text, text, text, text[], timestamptz
) from public, anon, authenticated;
grant execute on function public.mint_native_action_capability(
  uuid, text, text, jsonb, text, text, text, text[], timestamptz
) to service_role;

create function public.ingest_attested_raw_payment_sms(
  p_native_capability_id uuid,
  p_receiver_user_id uuid,
  p_collection_id uuid,
  p_raw_sender text,
  p_raw_body text,
  p_body_hash text,
  p_client_envelope_id uuid,
  p_receiver_momo_number_hash text,
  p_received_at_device text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  capability public.native_action_capabilities;
  expected_payload jsonb;
  result jsonb;
  raw_id uuid;
  existing_raw public.raw_payment_sms;
  clean_body_hash text := lower(btrim(coalesce(p_body_hash, '')));
  clean_receiver_hash text := lower(btrim(coalesce(p_receiver_momo_number_hash, '')));
  clean_received_at text := nullif(btrim(coalesce(p_received_at_device, '')), '');
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_native_capability_id is null
     or p_receiver_user_id is null
     or p_client_envelope_id is null
     or clean_body_hash !~ '^[0-9a-f]{64}$'
     or clean_receiver_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid attested SMS ingestion request';
  end if;
  if clean_received_at is not null then
    perform clean_received_at::timestamptz;
  end if;
  expected_payload := jsonb_build_object(
    'receiver_momo_number_hash', clean_receiver_hash,
    'client_envelope_id', p_client_envelope_id::text,
    'raw_sender', btrim(coalesce(p_raw_sender, '')),
    'raw_body_sha256', clean_body_hash,
    'received_at_device', clean_received_at
  );

  select item.* into capability
  from public.native_action_capabilities item
  where item.id = p_native_capability_id
  for update;
  if capability.id is null
     or capability.user_id <> p_receiver_user_id
     or capability.action <> 'sms.ingest'
     or capability.receiver_momo_number_hash <> clean_receiver_hash
     or capability.request_payload <> expected_payload
     or capability.expires_at <= now() then
    raise exception 'Attested SMS capability is invalid or expired';
  end if;

  if capability.consumed_at is not null then
    select raw.* into existing_raw
    from public.raw_payment_sms raw
    where raw.native_action_capability_id = capability.id;
    if existing_raw.id is null then
      raise exception 'Attested SMS capability was already consumed';
    end if;
    return jsonb_build_object(
      'id', existing_raw.id,
      'parse_status', existing_raw.parse_status,
      'replay', true,
      'attested', true
    );
  end if;

  result := public.ingest_raw_payment_sms(
    p_receiver_user_id, p_collection_id, p_raw_sender, p_raw_body,
    clean_body_hash, p_client_envelope_id, clean_receiver_hash,
    clean_received_at::timestamptz
  );
  raw_id := (result ->> 'id')::uuid;
  select raw.* into existing_raw
  from public.raw_payment_sms raw
  where raw.id = raw_id
  for update;
  if existing_raw.native_action_capability_id is not null
     and existing_raw.native_action_capability_id <> capability.id then
    raise exception 'SMS envelope is already bound to another attestation';
  end if;
  update public.raw_payment_sms
  set native_action_capability_id = capability.id,
      attestation_request_hash = capability.request_hash,
      device_attested_at = capability.verified_at
  where id = raw_id;
  update public.native_action_capabilities
  set consumed_at = now()
  where id = capability.id and consumed_at is null;
  perform public.create_audit_log(
    'sms.provider_evidence_attested', 'raw_payment_sms', raw_id,
    jsonb_build_object(
      'native_capability_id', capability.id,
      'request_hash', capability.request_hash,
      'play_package', capability.package_name,
      'play_app_verdict', capability.app_verdict
    ),
    p_receiver_user_id
  );
  return result || jsonb_build_object('attested', true);
end;
$$;

revoke all on function public.ingest_attested_raw_payment_sms(
  uuid, uuid, uuid, text, text, text, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.ingest_attested_raw_payment_sms(
  uuid, uuid, uuid, text, text, text, uuid, text, text
) to service_role;

create function public.attested_sms_contract_version()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case when coalesce((
    select flag.enabled
    from public.feature_flags flag
    where flag.key = 'native_sms_attestation_enforcement'
  ), false) then 1 else 0 end
$$;
revoke all on function public.attested_sms_contract_version()
  from public, anon, authenticated;
grant execute on function public.attested_sms_contract_version()
  to service_role;

create function public.protect_raw_payment_sms_attestation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.native_action_capability_id is not null
     and (
       new.native_action_capability_id is distinct from old.native_action_capability_id
       or new.attestation_request_hash is distinct from old.attestation_request_hash
       or new.device_attested_at is distinct from old.device_attested_at
     ) then
    raise exception 'Raw SMS attestation is immutable';
  end if;
  if old.native_action_capability_id is null
     and new.native_action_capability_id is not null
     and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required to attest raw SMS evidence';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_raw_payment_sms_attestation_trigger
  on public.raw_payment_sms;
create trigger protect_raw_payment_sms_attestation_trigger
before update of native_action_capability_id, attestation_request_hash, device_attested_at
on public.raw_payment_sms
for each row execute function public.protect_raw_payment_sms_attestation();

revoke all on function public.protect_raw_payment_sms_attestation()
  from public, anon, authenticated, service_role;

-- A provider transaction remains consumed for its complete lifecycle. A
-- compensating reversal changes the accounting result; it must never make the
-- same external transaction eligible to credit the system again.
do $$
begin
  if exists (
    select 1
    from public.payments payment
    where payment.transaction_id is not null
    group by payment.provider_network, upper(btrim(payment.transaction_id))
    having count(*) > 1
  ) then
    raise exception 'Provider transaction duplicates across lifecycle states require reconciliation';
  end if;
end;
$$;

drop index if exists public.payments_provider_transaction_unique;
create unique index payments_provider_transaction_unique
  on public.payments(provider_network, upper(btrim(transaction_id)))
  where transaction_id is not null;

-- Restore the provider-finality boundary removed by the obsolete standalone
-- SMS flow. SMS reserves a candidate transaction in review; only independent
-- provider evidence may transition it to posted.
alter table public.payments alter column posted_at drop not null;

create table public.payment_provider_confirmations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null unique references public.payments(id) on delete restrict,
  provider_network text not null,
  provider_confirmation_id text not null,
  transaction_id text not null,
  receiver_momo_number_hash text not null,
  amount_rwf bigint not null check (amount_rwf > 0),
  currency text not null default 'RWF' check (currency = 'RWF'),
  confirmed_at timestamptz not null,
  evidence_sha256 text check (evidence_sha256 is null or evidence_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_at timestamptz not null default now()
);
create unique index payment_provider_confirmation_reference_unique
  on public.payment_provider_confirmations(provider_network, upper(btrim(provider_confirmation_id)));
create unique index payment_provider_confirmation_transaction_unique
  on public.payment_provider_confirmations(provider_network, upper(btrim(transaction_id)));
alter table public.payment_provider_confirmations enable row level security;
revoke all on public.payment_provider_confirmations
  from public, anon, authenticated, service_role;

-- Legacy ledger rows remain an append-only compatibility projection. One
-- positive and one compensating negative row per payment/type are permitted.
drop index if exists public.ledger_entries_payment_type_unique;
create unique index ledger_entries_payment_type_direction_unique
  on public.ledger_entries(payment_id, entry_type, (amount_rwf > 0));

create function public.prevent_raw_payment_sms_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Raw SMS evidence is retained; deletion requires a governed retention migration';
end;
$$;

create trigger retain_raw_payment_sms_evidence_trigger
before delete on public.raw_payment_sms
for each row execute function public.prevent_raw_payment_sms_delete();

revoke all on function public.prevent_raw_payment_sms_delete()
  from public, anon, authenticated, service_role;

alter table public.payments
  add column member_record_id uuid
    references collect_hybrid.member_records(id) on delete restrict;
alter table public.payment_allocations
  add column member_record_id uuid
    references collect_hybrid.member_records(id) on delete restrict;
alter table public.ledger_entries
  add column member_record_id uuid
    references collect_hybrid.member_records(id) on delete restrict;

create index payments_member_record_idx
  on public.payments(member_record_id, collection_id, posted_at desc);
create index payment_allocations_member_record_idx
  on public.payment_allocations(member_record_id, collection_id, created_at desc);
create index ledger_entries_member_record_idx
  on public.ledger_entries(member_record_id, collection_id, created_at desc);

update public.payments payment
set member_record_id = member.id
from collect_hybrid.member_records member
where payment.member_record_id is null
  and (
    member.linked_user_id = payment.contributor_user_id
    or (
      payment.contributor_user_id is null
      and payment.contributor_public_id is not null
      and member.collect_id = payment.contributor_public_id
    )
  );

update public.payment_allocations allocation
set member_record_id = payment.member_record_id
from public.payments payment
where payment.id = allocation.payment_id
  and allocation.member_record_id is null;

update public.ledger_entries ledger
set member_record_id = payment.member_record_id
from public.payments payment
where payment.id = ledger.payment_id
  and ledger.member_record_id is null;

create function collect_hybrid.bind_payment_member_record()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_member_id uuid;
  resolved_collect_id char(6);
begin
  if new.member_record_id is null and new.contributor_user_id is not null then
    select member.id, member.collect_id
    into resolved_member_id, resolved_collect_id
    from collect_hybrid.member_records member
    where member.linked_user_id = new.contributor_user_id
      and member.lifecycle = 'active';
  elsif new.member_record_id is null and new.contributor_public_id is not null then
    select member.id, member.collect_id
    into resolved_member_id, resolved_collect_id
    from collect_hybrid.member_records member
    where member.collect_id = new.contributor_public_id
      and member.lifecycle = 'active';
  elsif new.member_record_id is not null then
    select member.id, member.collect_id
    into resolved_member_id, resolved_collect_id
    from collect_hybrid.member_records member
    where member.id = new.member_record_id
      and member.lifecycle = 'active';
  end if;

  if new.member_record_id is not null and resolved_member_id is null then
    raise exception 'Active member record required';
  end if;
  if resolved_member_id is not null then
    if new.contributor_user_id is not null and not exists (
      select 1 from collect_hybrid.member_records member
      where member.id = resolved_member_id
        and member.linked_user_id = new.contributor_user_id
    ) then
      raise exception 'Payment account and member record do not match';
    end if;
    if new.contributor_public_id is not null
       and new.contributor_public_id <> resolved_collect_id then
      raise exception 'Payment Collect ID and member record do not match';
    end if;
    new.member_record_id := resolved_member_id;
    new.contributor_public_id := coalesce(new.contributor_public_id, resolved_collect_id);
  end if;
  return new;
end;
$$;

create trigger hybrid_bind_payment_member_record_trigger
before insert or update of member_record_id, contributor_user_id, contributor_public_id
on public.payments
for each row execute function collect_hybrid.bind_payment_member_record();

create function collect_hybrid.bind_payment_child_member_record()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare expected_member_id uuid;
begin
  select payment.member_record_id into expected_member_id
  from public.payments payment
  where payment.id = new.payment_id;
  if not found then raise exception 'Payment required'; end if;
  if new.member_record_id is not null
     and new.member_record_id is distinct from expected_member_id then
    raise exception 'Payment child member record does not match payment';
  end if;
  new.member_record_id := expected_member_id;
  return new;
end;
$$;

create trigger hybrid_bind_allocation_member_record_trigger
before insert or update of payment_id, member_record_id
on public.payment_allocations
for each row execute function collect_hybrid.bind_payment_child_member_record();

create trigger hybrid_bind_ledger_member_record_trigger
before insert or update of payment_id, member_record_id
on public.ledger_entries
for each row execute function collect_hybrid.bind_payment_child_member_record();

create table collect_hybrid.member_receiving_assignments (
  id uuid primary key default gen_random_uuid(),
  member_record_id uuid not null
    references collect_hybrid.member_records(id) on delete restrict,
  collection_id uuid not null
    references public.collections(id) on delete restrict,
  collection_receiver_id uuid not null
    references public.collection_receivers(id) on delete restrict,
  route_key text not null check (route_key ~ '^[0-9a-f]{64}$'),
  status text not null default 'active' check (status in ('active', 'ended')),
  starts_at timestamptz not null default now(),
  ended_at timestamptz,
  reason text not null check (char_length(btrim(reason)) between 8 and 500),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (
    (status = 'active' and ended_at is null)
    or (status = 'ended' and ended_at is not null and ended_at >= starts_at)
  )
);

create unique index hybrid_assignment_member_group_active_unique
  on collect_hybrid.member_receiving_assignments(member_record_id, collection_id)
  where status = 'active';
create unique index hybrid_assignment_member_route_active_unique
  on collect_hybrid.member_receiving_assignments(member_record_id, route_key)
  where status = 'active';
create index hybrid_assignment_route_active_idx
  on collect_hybrid.member_receiving_assignments(route_key, status, starts_at);

create table collect_hybrid.receiving_assignment_requests (
  request_id uuid primary key,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
  result jsonb not null,
  created_at timestamptz not null default now()
);

create function collect_hybrid.validate_receiving_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  route public.collection_receivers;
  expected_key text;
begin
  if tg_op = 'DELETE' then
    raise exception 'Receiving assignments are retained; end the assignment instead';
  end if;

  if tg_op = 'UPDATE' then
    if new.member_record_id is distinct from old.member_record_id
       or new.collection_id is distinct from old.collection_id
       or new.collection_receiver_id is distinct from old.collection_receiver_id
       or new.route_key is distinct from old.route_key
       or new.starts_at is distinct from old.starts_at
       or new.reason is distinct from old.reason
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at
       or old.status <> 'active'
       or new.status <> 'ended'
       or new.ended_at is null then
      raise exception 'Receiving assignment history is immutable';
    end if;
    return new;
  end if;

  select receiver.* into route
  from public.collection_receivers receiver
  where receiver.id = new.collection_receiver_id
    and receiver.collection_id = new.collection_id
    and receiver.is_active;
  if route.id is null then
    raise exception 'Active receiving route for this group required';
  end if;
  if not exists (
    select 1
    from collect_hybrid.member_records member
    join public.collection_members membership
      on membership.member_record_id = member.id
     and membership.collection_id = new.collection_id
     and membership.status = 'active'
    where member.id = new.member_record_id
      and member.lifecycle = 'active'
  ) then
    raise exception 'Active group membership required';
  end if;
  expected_key := encode(
    extensions.digest(
      route.receiver_user_id::text || '|' || route.momo_number_hash || '|' || route.network,
      'sha256'
    ),
    'hex'
  );
  new.route_key := expected_key;
  return new;
end;
$$;

create trigger hybrid_validate_receiving_assignment_trigger
before insert or update or delete
on collect_hybrid.member_receiving_assignments
for each row execute function collect_hybrid.validate_receiving_assignment();

create function public.admin_assign_hybrid_receiving_route(
  p_collection_id uuid,
  p_member_record_id uuid,
  p_collection_receiver_id uuid,
  p_reason text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  clean_reason text := btrim(coalesce(p_reason, ''));
  request_hash text;
  prior collect_hybrid.receiving_assignment_requests;
  route public.collection_receivers;
  route_key_value text;
  current_assignment collect_hybrid.member_receiving_assignments;
  new_assignment_id uuid;
  response jsonb;
begin
  perform public.assert_admin_permission('collections.moderate');
  perform public.assert_admin_permission('users.read');
  if not coalesce((select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_member_onboarding'), false) then
    raise exception 'Hybrid onboarding is disabled pending controlled rollout';
  end if;
  if p_request_id is null or p_collection_id is null or p_member_record_id is null
     or p_collection_receiver_id is null
     or char_length(clean_reason) not between 8 and 500 then
    raise exception 'Complete receiving assignment and audit reason required';
  end if;
  request_hash := encode(extensions.digest(
    jsonb_build_array(p_collection_id, p_member_record_id, p_collection_receiver_id, clean_reason)::text,
    'sha256'
  ), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('hybrid-route-request:' || p_request_id::text, 0));
  select request.* into prior
  from collect_hybrid.receiving_assignment_requests request
  where request.request_id = p_request_id;
  if prior.request_id is not null then
    if prior.actor_id <> actor_id or prior.input_hash <> request_hash then
      raise exception 'Receiving assignment idempotency key conflict';
    end if;
    return prior.result || jsonb_build_object('replay', true);
  end if;

  select receiver.* into route
  from public.collection_receivers receiver
  where receiver.id = p_collection_receiver_id
    and receiver.collection_id = p_collection_id
    and receiver.is_active
  for update;
  if route.id is null then raise exception 'Active receiving route for this group required'; end if;
  route_key_value := encode(extensions.digest(
    route.receiver_user_id::text || '|' || route.momo_number_hash || '|' || route.network,
    'sha256'
  ), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    'hybrid-member-route:' || p_member_record_id::text || ':' || route_key_value,
    0
  ));
  if exists (
    select 1 from collect_hybrid.member_receiving_assignments assignment
    where assignment.member_record_id = p_member_record_id
      and assignment.route_key = route_key_value
      and assignment.status = 'active'
      and assignment.collection_id <> p_collection_id
  ) then
    raise exception 'Member receiving route is already assigned to another group';
  end if;

  select assignment.* into current_assignment
  from collect_hybrid.member_receiving_assignments assignment
  where assignment.member_record_id = p_member_record_id
    and assignment.collection_id = p_collection_id
    and assignment.status = 'active'
  for update;
  if current_assignment.id is not null
     and current_assignment.collection_receiver_id = p_collection_receiver_id then
    new_assignment_id := current_assignment.id;
  else
    if current_assignment.id is not null then
      update collect_hybrid.member_receiving_assignments
      set status = 'ended', ended_at = now()
      where id = current_assignment.id;
    end if;
    insert into collect_hybrid.member_receiving_assignments(
      member_record_id, collection_id, collection_receiver_id, route_key,
      reason, created_by
    ) values (
      p_member_record_id, p_collection_id, p_collection_receiver_id,
      route_key_value, clean_reason, actor_id
    ) returning id into new_assignment_id;
  end if;

  response := jsonb_build_object(
    'ok', true,
    'assignment_id', new_assignment_id,
    'collection_id', p_collection_id,
    'member_record_id', p_member_record_id,
    'collection_receiver_id', p_collection_receiver_id,
    'replay', false
  );
  insert into collect_hybrid.receiving_assignment_requests(request_id, actor_id, input_hash, result)
  values (p_request_id, actor_id, request_hash, response);
  perform public.create_audit_log(
    'collection.hybrid.receiving_assignment_set',
    'collection',
    p_collection_id,
    jsonb_build_object(
      'member_record_id', p_member_record_id,
      'assignment_id', new_assignment_id,
      'collection_receiver_id', p_collection_receiver_id,
      'reason', clean_reason,
      'request_id', p_request_id
    )
  );
  return response;
end;
$$;

create table collect_hybrid.momo_journal_entries (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  parsed_event_id uuid references public.parsed_payment_events(id) on delete restrict,
  collection_id uuid not null references public.collections(id) on delete restrict,
  member_record_id uuid references collect_hybrid.member_records(id) on delete restrict,
  entry_type text not null check (entry_type in ('receipt', 'reversal')),
  amount_rwf bigint not null check (amount_rwf > 0),
  external_reference text not null,
  reverses_entry_id uuid references collect_hybrid.momo_journal_entries(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete set null,
  posted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(payment_id, entry_type),
  check (
    (entry_type = 'receipt' and reverses_entry_id is null)
    or (entry_type = 'reversal' and reverses_entry_id is not null)
  )
);
create unique index hybrid_momo_one_reversal_unique
  on collect_hybrid.momo_journal_entries(reverses_entry_id)
  where reverses_entry_id is not null;
create index hybrid_momo_journal_collection_idx
  on collect_hybrid.momo_journal_entries(collection_id, posted_at desc);
create index hybrid_momo_journal_member_idx
  on collect_hybrid.momo_journal_entries(member_record_id, posted_at desc)
  where member_record_id is not null;

create table collect_hybrid.momo_journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null
    references collect_hybrid.momo_journal_entries(id) on delete restrict,
  account_code text not null check (account_code in (
    'momo_receiving_asset:RWF', 'member_savings_liability:RWF'
  )),
  direction text not null check (direction in ('debit', 'credit')),
  amount_rwf bigint not null check (amount_rwf > 0),
  created_at timestamptz not null default now(),
  unique(journal_entry_id, account_code, direction)
);

create table collect_hybrid.collection_balances (
  collection_id uuid primary key references public.collections(id) on delete restrict,
  confirmed_rwf bigint not null default 0 check (confirmed_rwf >= 0),
  updated_at timestamptz not null default now()
);

create table collect_hybrid.member_balances (
  collection_id uuid not null references public.collections(id) on delete restrict,
  member_record_id uuid not null references collect_hybrid.member_records(id) on delete restrict,
  confirmed_rwf bigint not null default 0 check (confirmed_rwf >= 0),
  updated_at timestamptz not null default now(),
  primary key(collection_id, member_record_id)
);

create table collect_hybrid.momo_balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null unique
    references collect_hybrid.momo_journal_entries(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict,
  collection_id uuid not null references public.collections(id) on delete restrict,
  member_record_id uuid references collect_hybrid.member_records(id) on delete restrict,
  event_type text not null check (event_type in ('receipt', 'reversal')),
  delta_rwf bigint not null check (delta_rwf <> 0),
  member_balance_after_rwf bigint check (member_balance_after_rwf >= 0),
  group_balance_after_rwf bigint not null check (group_balance_after_rwf >= 0),
  captured_at timestamptz not null default now()
);
create index hybrid_momo_snapshots_collection_idx
  on collect_hybrid.momo_balance_snapshots(collection_id, captured_at desc);
create index hybrid_momo_snapshots_member_idx
  on collect_hybrid.momo_balance_snapshots(member_record_id, captured_at desc)
  where member_record_id is not null;

create table collect_hybrid.momo_reconciliation_exceptions (
  id uuid primary key default gen_random_uuid(),
  parsed_event_id uuid not null references public.parsed_payment_events(id) on delete restrict,
  code text not null check (code in (
    'no_candidate', 'ambiguous_candidate', 'intent_direct_disagreement',
    'member_identity_missing', 'route_changed', 'provider_confirmation_pending'
  )),
  details jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open', 'resolved')),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    (status = 'open' and resolved_at is null)
    or (status = 'resolved' and resolved_at is not null)
  )
);
create unique index hybrid_momo_exception_open_unique
  on collect_hybrid.momo_reconciliation_exceptions(parsed_event_id, code)
  where status = 'open';

create table collect_hybrid.momo_reversal_requests (
  request_id uuid primary key,
  payment_id uuid not null references public.payments(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
  result jsonb not null,
  created_at timestamptz not null default now()
);

create function collect_hybrid.prevent_momo_financial_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Posted MoMo journals and snapshots are immutable; post a compensating reversal';
end;
$$;

create trigger hybrid_momo_journal_entries_immutable
before update or delete on collect_hybrid.momo_journal_entries
for each row execute function collect_hybrid.prevent_momo_financial_mutation();
create trigger hybrid_momo_journal_lines_immutable
before update or delete on collect_hybrid.momo_journal_lines
for each row execute function collect_hybrid.prevent_momo_financial_mutation();
create trigger hybrid_momo_snapshots_immutable
before update or delete on collect_hybrid.momo_balance_snapshots
for each row execute function collect_hybrid.prevent_momo_financial_mutation();

create function collect_hybrid.assert_momo_journal_balanced()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_entry_id uuid;
  entry_amount bigint;
  debit_total bigint;
  credit_total bigint;
  line_count integer;
begin
  if tg_table_name = 'momo_journal_entries' then
    target_entry_id := new.id;
  else
    target_entry_id := new.journal_entry_id;
  end if;
  select entry.amount_rwf into entry_amount
  from collect_hybrid.momo_journal_entries entry
  where entry.id = target_entry_id;
  select
    coalesce(sum(line.amount_rwf) filter (where line.direction = 'debit'), 0),
    coalesce(sum(line.amount_rwf) filter (where line.direction = 'credit'), 0),
    count(*)
  into debit_total, credit_total, line_count
  from collect_hybrid.momo_journal_lines line
  where line.journal_entry_id = target_entry_id;
  if line_count <> 2 or debit_total <> entry_amount or credit_total <> entry_amount then
    raise exception 'MoMo journal entry must contain exactly one balanced debit and credit';
  end if;
  return new;
end;
$$;

create constraint trigger hybrid_momo_entry_balanced
after insert on collect_hybrid.momo_journal_entries
deferrable initially deferred
for each row execute function collect_hybrid.assert_momo_journal_balanced();
create constraint trigger hybrid_momo_line_balanced
after insert on collect_hybrid.momo_journal_lines
deferrable initially deferred
for each row execute function collect_hybrid.assert_momo_journal_balanced();

create function collect_hybrid.post_momo_receipt(p_payment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment_row public.payments;
  raw_id uuid;
  journal_id uuid;
  was_inserted boolean := false;
  group_balance bigint;
  member_balance bigint;
begin
  select payment.* into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if payment_row.id is null then raise exception 'Payment not found'; end if;
  if payment_row.status <> 'posted' or payment_row.currency <> 'RWF' then
    raise exception 'Posted RWF payment required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'hybrid-momo-group-balance:' || payment_row.collection_id::text, 0
  ));
  if payment_row.member_record_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'hybrid-momo-member-balance:' || payment_row.collection_id::text || ':' || payment_row.member_record_id::text,
      0
    ));
  end if;
  select event.raw_sms_id into raw_id
  from public.parsed_payment_events event
  where event.id = payment_row.parsed_event_id;

  insert into collect_hybrid.momo_journal_entries(
    payment_id, parsed_event_id, collection_id, member_record_id,
    entry_type, amount_rwf, external_reference
  ) values (
    payment_row.id, payment_row.parsed_event_id, payment_row.collection_id,
    payment_row.member_record_id, 'receipt', payment_row.amount_rwf,
    coalesce(
      nullif(btrim(payment_row.transaction_id), ''),
      case when raw_id is not null then 'raw-sms:' || raw_id::text end,
      'payment:' || payment_row.id::text
    )
  )
  on conflict (payment_id, entry_type) do nothing
  returning id into journal_id;
  was_inserted := journal_id is not null;
  if not was_inserted then
    select entry.id into journal_id
    from collect_hybrid.momo_journal_entries entry
    where entry.payment_id = payment_row.id and entry.entry_type = 'receipt';
    return journal_id;
  end if;

  insert into collect_hybrid.momo_journal_lines(
    journal_entry_id, account_code, direction, amount_rwf
  ) values
    (journal_id, 'momo_receiving_asset:RWF', 'debit', payment_row.amount_rwf),
    (journal_id, 'member_savings_liability:RWF', 'credit', payment_row.amount_rwf);

  insert into collect_hybrid.collection_balances(collection_id, confirmed_rwf)
  values (payment_row.collection_id, payment_row.amount_rwf)
  on conflict (collection_id) do update
  set confirmed_rwf = collect_hybrid.collection_balances.confirmed_rwf + excluded.confirmed_rwf,
      updated_at = now()
  returning confirmed_rwf into group_balance;

  if payment_row.member_record_id is not null then
    insert into collect_hybrid.member_balances(collection_id, member_record_id, confirmed_rwf)
    values (payment_row.collection_id, payment_row.member_record_id, payment_row.amount_rwf)
    on conflict (collection_id, member_record_id) do update
    set confirmed_rwf = collect_hybrid.member_balances.confirmed_rwf + excluded.confirmed_rwf,
        updated_at = now()
    returning confirmed_rwf into member_balance;
  else
    insert into collect_hybrid.momo_reconciliation_exceptions(parsed_event_id, code, details)
    select payment_row.parsed_event_id, 'member_identity_missing',
      jsonb_build_object('payment_id', payment_row.id, 'collection_id', payment_row.collection_id)
    where payment_row.parsed_event_id is not null;
  end if;

  insert into collect_hybrid.momo_balance_snapshots(
    journal_entry_id, payment_id, collection_id, member_record_id,
    event_type, delta_rwf, member_balance_after_rwf, group_balance_after_rwf
  ) values (
    journal_id, payment_row.id, payment_row.collection_id, payment_row.member_record_id,
    'receipt', payment_row.amount_rwf, member_balance, group_balance
  );
  return journal_id;
end;
$$;

create function collect_hybrid.post_momo_receipt_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'posted'
     and new.currency = 'RWF'
     and (tg_op = 'INSERT' or old.status is distinct from 'posted') then
    perform collect_hybrid.post_momo_receipt(new.id);
    update collect_hybrid.momo_reconciliation_exceptions exception
    set status = 'resolved', resolved_at = now()
    where exception.parsed_event_id = new.parsed_event_id
      and exception.status = 'open';
  end if;
  return new;
end;
$$;

create trigger hybrid_post_momo_receipt_trigger
after insert or update of status on public.payments
for each row execute function collect_hybrid.post_momo_receipt_trigger();

-- Converge pre-existing posted RWF payments into the canonical journal. Rows
-- without a resolvable member stay visible as reconciliation exceptions.
select collect_hybrid.post_momo_receipt(payment.id)
from public.payments payment
where payment.status = 'posted' and payment.currency = 'RWF'
order by payment.created_at, payment.id;

create function collect_hybrid.record_momo_exception(
  p_event_id uuid,
  p_code text,
  p_details jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update collect_hybrid.momo_reconciliation_exceptions exception
  set details = coalesce(p_details, '{}'::jsonb)
  where exception.parsed_event_id = p_event_id
    and exception.code = p_code
    and exception.status = 'open';
  if not found then
    insert into collect_hybrid.momo_reconciliation_exceptions(parsed_event_id, code, details)
    values (p_event_id, p_code, coalesce(p_details, '{}'::jsonb));
  end if;
end;
$$;

create or replace function public.post_payment_from_event(
  event_id uuid,
  intent_id uuid,
  target_collection_id uuid,
  allocation_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_row public.parsed_payment_events;
  intent_row public.payment_intents;
  raw_row public.raw_payment_sms;
  receiver_id uuid;
  candidate_payment_id uuid;
begin
  select event.* into event_row
  from public.parsed_payment_events event
  where event.id = event_id
  for update;
  if event_row.id is null then raise exception 'Parsed event not found'; end if;

  select payment.id into candidate_payment_id
  from public.payments payment
  where payment.parsed_event_id = event_id;
  if candidate_payment_id is not null then return candidate_payment_id; end if;

  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.receiver_phone_hash is null
     or event_row.confidence < 0.90 then
    raise exception 'SMS payment evidence is incomplete or below the review threshold';
  end if;

  select intent.* into intent_row
  from public.payment_intents intent
  where intent.id = intent_id
  for update;
  if intent_row.id is null then raise exception 'Payment intent not found'; end if;
  if intent_row.status <> 'pending' or intent_row.expires_at <= now() then
    raise exception 'Payment intent is not active';
  end if;
  if intent_row.collection_id <> target_collection_id
     or intent_row.receiver_momo_number_hash <> event_row.receiver_phone_hash
     or intent_row.expected_amount_rwf <> event_row.amount_rwf then
    raise exception 'Payment intent does not match the SMS evidence';
  end if;
  if not (
    (event_row.sender_phone_hash is not null
      and intent_row.sender_phone_hash = event_row.sender_phone_hash)
    or (event_row.detected_user_public_id is not null
      and intent_row.contributor_public_id = event_row.detected_user_public_id)
  ) then
    raise exception 'Payer identity does not match the payment intent';
  end if;

  select raw.* into raw_row
  from public.raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;
  if raw_row.id is null
     or raw_row.native_action_capability_id is null
     or raw_row.attestation_request_hash is null
     or raw_row.device_attested_at is null
     or coalesce(raw_row.received_at_device, raw_row.ingested_at)
       not between intent_row.created_at - interval '15 minutes'
         and intent_row.expires_at + interval '2 hours' then
    raise exception 'Device-attested SMS evidence is required within the payment intent window';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    event_row.network || ':' || upper(btrim(event_row.transaction_id)), 0
  ));
  select payment.id into candidate_payment_id
  from public.payments payment
  where payment.provider_network = event_row.network
    and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
  order by payment.created_at
  limit 1;
  if candidate_payment_id is not null then
    update public.parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Duplicate provider transaction evidence'
    where id = event_id;
    return candidate_payment_id;
  end if;

  select receiver.receiver_user_id into receiver_id
  from public.collection_receivers receiver
  where receiver.collection_id = target_collection_id
    and receiver.momo_number_hash = event_row.receiver_phone_hash
    and receiver.is_active
  order by receiver.created_at desc
  limit 1;
  if receiver_id is null or receiver_id <> event_row.receiver_user_id then
    raise exception 'SMS receiver is not configured for the target group';
  end if;

  insert into public.payments(
    parsed_event_id, payment_intent_id, collection_id,
    contributor_user_id, contributor_public_id, receiver_user_id,
    receiver_momo_number_hash, amount_rwf, transaction_id,
    provider_network, source, status, anonymity_choice, posted_at
  ) values (
    event_id, intent_id, target_collection_id,
    intent_row.contributor_user_id, intent_row.contributor_public_id, receiver_id,
    event_row.receiver_phone_hash, event_row.amount_rwf, event_row.transaction_id,
    event_row.network, 'sms_auto', 'review', intent_row.anonymity_choice, null
  ) returning id into candidate_payment_id;

  insert into public.payment_allocations(
    payment_id, parsed_event_id, collection_id, payment_intent_id,
    allocated_by, allocation_method, confidence, reason
  ) values (
    candidate_payment_id, event_id, target_collection_id, intent_id,
    null, 'auto_native_sms', event_row.confidence,
    allocation_reason || '; awaiting independent provider confirmation'
  );
  update public.parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = 'Matched to one payer-verified intent; awaiting independent provider confirmation'
  where id = event_id;
  update public.payment_intents set status = 'matched' where id = intent_id;
  perform collect_hybrid.record_momo_exception(
    event_id, 'provider_confirmation_pending',
    jsonb_build_object('payment_id', candidate_payment_id, 'payment_intent_id', intent_id)
  );
  perform public.create_audit_log(
    'payment.awaiting_provider_confirmation', 'payment', candidate_payment_id,
    jsonb_build_object(
      'parsed_event_id', event_id,
      'payment_intent_id', intent_id,
      'method', 'native_sms_candidate',
      'ledger_posted', false
    ),
    null
  );
  return candidate_payment_id;
end;
$$;

create or replace function public.confirm_provider_payment(
  p_payment_id uuid,
  p_provider_network text,
  p_transaction_id text,
  p_provider_confirmation_id text,
  p_receiver_momo_number_hash text,
  p_amount_rwf bigint,
  p_confirmed_at timestamptz,
  p_evidence_sha256 text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment_row public.payments;
  clean_network text := lower(btrim(coalesce(p_provider_network, '')));
  clean_transaction_id text := upper(btrim(coalesce(p_transaction_id, '')));
  clean_confirmation_id text := upper(btrim(coalesce(p_provider_confirmation_id, '')));
  clean_receiver_hash text := lower(btrim(coalesce(p_receiver_momo_number_hash, '')));
  clean_evidence_hash text := lower(btrim(coalesce(p_evidence_sha256, '')));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_payment_id is null
     or char_length(clean_network) not between 2 and 32
     or char_length(clean_transaction_id) not between 3 and 128
     or char_length(clean_confirmation_id) not between 3 and 128
     or clean_receiver_hash !~ '^[0-9a-f]{64}$'
     or p_amount_rwf is null or p_amount_rwf <= 0
     or p_confirmed_at is null or p_confirmed_at > now() + interval '5 minutes'
     or (clean_evidence_hash <> '' and clean_evidence_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid provider confirmation';
  end if;

  select payment.* into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if payment_row.id is null then raise exception 'Payment not found'; end if;
  if payment_row.status = 'posted' then
    if exists (
      select 1 from public.payment_provider_confirmations confirmation
      where confirmation.payment_id = payment_row.id
        and confirmation.provider_network = clean_network
        and upper(btrim(confirmation.provider_confirmation_id)) = clean_confirmation_id
    ) then return payment_row.id; end if;
    raise exception 'Payment was already finalized by a different confirmation';
  end if;
  if payment_row.status <> 'review' then
    raise exception 'Payment is not awaiting provider confirmation';
  end if;
  if lower(payment_row.provider_network) <> clean_network
     or upper(btrim(payment_row.transaction_id)) <> clean_transaction_id
     or payment_row.receiver_momo_number_hash <> clean_receiver_hash
     or payment_row.amount_rwf <> p_amount_rwf then
    raise exception 'Provider confirmation does not match the payment candidate';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(clean_network || ':' || clean_transaction_id, 0));
  insert into public.payment_provider_confirmations(
    payment_id, provider_network, provider_confirmation_id, transaction_id,
    receiver_momo_number_hash, amount_rwf, confirmed_at, evidence_sha256
  ) values (
    payment_row.id, clean_network, clean_confirmation_id, clean_transaction_id,
    clean_receiver_hash, p_amount_rwf, p_confirmed_at, nullif(clean_evidence_hash, '')
  );
  insert into public.ledger_entries(
    payment_id, collection_id, user_id, member_record_id,
    entry_type, amount_rwf, visibility, metadata
  ) values
    (
      payment_row.id, payment_row.collection_id, payment_row.contributor_user_id,
      payment_row.member_record_id, 'collection_credit', payment_row.amount_rwf,
      'public_safe', jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    ),
    (
      payment_row.id, payment_row.collection_id, payment_row.contributor_user_id,
      payment_row.member_record_id, 'member_credit', payment_row.amount_rwf,
      'private', jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    );
  update public.payments
  set status = 'posted', posted_at = p_confirmed_at
  where id = payment_row.id;
  update public.parsed_payment_events
  set allocation_status = 'allocated',
      review_reason = 'Posted after independent provider confirmation'
  where id = payment_row.parsed_event_id;
  perform public.create_audit_log(
    'payment.provider_confirmed', 'payment', payment_row.id,
    jsonb_build_object(
      'provider_network', clean_network,
      'provider_confirmation_id', clean_confirmation_id,
      'confirmed_at', p_confirmed_at,
      'ledger_posted', true
    ),
    null
  );
  return payment_row.id;
end;
$$;

create or replace function public.reject_provider_payment(
  p_payment_id uuid,
  p_reason text,
  p_provider_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment_row public.payments;
  clean_reason text := btrim(coalesce(p_reason, ''));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A bounded rejection reason is required';
  end if;
  select payment.* into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if payment_row.id is null then raise exception 'Payment not found'; end if;
  if payment_row.status = 'reversed' then return payment_row.id; end if;
  if payment_row.status <> 'review' then raise exception 'Only a review payment can be rejected'; end if;

  update public.payments set status = 'reversed', posted_at = null
  where id = payment_row.id;
  update public.parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = 'Provider rejected payment candidate: ' || clean_reason
  where id = payment_row.parsed_event_id;
  update public.payment_intents set status = 'cancelled'
  where id = payment_row.payment_intent_id;
  update collect_hybrid.momo_reconciliation_exceptions
  set status = 'resolved', resolved_at = now()
  where parsed_event_id = payment_row.parsed_event_id
    and status = 'open';
  perform public.create_audit_log(
    'payment.provider_rejected', 'payment', payment_row.id,
    jsonb_build_object(
      'reason', clean_reason,
      'provider_reference', nullif(btrim(coalesce(p_provider_reference, '')), ''),
      'ledger_posted', false
    ),
    null
  );
  return payment_row.id;
end;
$$;

create table public.provider_finality_requests (
  request_id uuid primary key,
  event_type text not null check (event_type in ('payment.confirmed', 'payment.rejected')),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  payment_id uuid not null references public.payments(id) on delete restrict,
  provider_network text check (
    provider_network is null or (
      char_length(provider_network) between 2 and 32 and provider_network ~ '^[a-z0-9_]+$'
    )
  ),
  provider_reference text check (
    provider_reference is null or char_length(provider_reference) between 1 and 128
  ),
  status text not null default 'processing' check (status in ('processing', 'processed')),
  result_payment_id uuid references public.payments(id) on delete restrict,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  check (result_payment_id is null or result_payment_id = payment_id),
  check (
    (status = 'processing' and result_payment_id is null and processed_at is null)
    or (status = 'processed' and result_payment_id is not null and processed_at is not null)
  )
);
alter table public.provider_finality_requests enable row level security;
revoke all on public.provider_finality_requests
  from public, anon, authenticated, service_role;

create function public.process_provider_finality_event(
  p_request_id uuid,
  p_event_type text,
  p_payload_sha256 text,
  p_payment_id uuid,
  p_provider_network text default null,
  p_transaction_id text default null,
  p_provider_confirmation_id text default null,
  p_receiver_momo_number_hash text default null,
  p_amount_rwf bigint default null,
  p_occurred_at timestamptz default null,
  p_evidence_sha256 text default null,
  p_rejection_reason text default null,
  p_provider_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_event_type text := btrim(coalesce(p_event_type, ''));
  clean_payload_sha256 text := lower(btrim(coalesce(p_payload_sha256, '')));
  existing_request public.provider_finality_requests;
  inserted_request_id uuid;
  finalized_payment_id uuid;
  stored_reference text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_request_id is null or p_payment_id is null
     or clean_event_type not in ('payment.confirmed', 'payment.rejected')
     or clean_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider finality request';
  end if;
  stored_reference := case
    when clean_event_type = 'payment.confirmed'
      then nullif(btrim(coalesce(p_provider_confirmation_id, '')), '')
    else nullif(btrim(coalesce(p_provider_reference, '')), '')
  end;
  insert into public.provider_finality_requests(
    request_id, event_type, payload_sha256, payment_id, provider_network, provider_reference
  ) values (
    p_request_id, clean_event_type, clean_payload_sha256, p_payment_id,
    nullif(lower(btrim(coalesce(p_provider_network, ''))), ''), stored_reference
  )
  on conflict (request_id) do nothing
  returning request_id into inserted_request_id;
  if inserted_request_id is null then
    select request.* into existing_request
    from public.provider_finality_requests request
    where request.request_id = p_request_id
    for update;
    if existing_request.event_type <> clean_event_type
       or existing_request.payload_sha256 <> clean_payload_sha256
       or existing_request.payment_id <> p_payment_id then
      raise exception 'Provider finality request id was reused with different content';
    end if;
    if existing_request.status <> 'processed' or existing_request.result_payment_id is null then
      raise exception 'Provider finality request is not complete';
    end if;
    return jsonb_build_object('payment_id', existing_request.result_payment_id, 'replayed', true);
  end if;
  if clean_event_type = 'payment.confirmed' then
    finalized_payment_id := public.confirm_provider_payment(
      p_payment_id, p_provider_network, p_transaction_id,
      p_provider_confirmation_id, p_receiver_momo_number_hash,
      p_amount_rwf, p_occurred_at, p_evidence_sha256
    );
  else
    finalized_payment_id := public.reject_provider_payment(
      p_payment_id, p_rejection_reason, p_provider_reference
    );
  end if;
  update public.provider_finality_requests
  set status = 'processed', result_payment_id = finalized_payment_id, processed_at = now()
  where request_id = p_request_id;
  return jsonb_build_object('payment_id', finalized_payment_id, 'replayed', false);
end;
$$;

create function public.finalize_attested_payment_sms(p_raw_sms_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_row public.raw_payment_sms;
  event_row public.parsed_payment_events;
  payment_row public.payments;
  result jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  select raw.* into raw_row
  from public.raw_payment_sms raw
  where raw.id = p_raw_sms_id
  for update;
  if raw_row.id is null then raise exception 'Raw SMS evidence not found'; end if;
  if raw_row.native_action_capability_id is null
     or raw_row.attestation_request_hash is null
     or raw_row.device_attested_at is null
     or not exists (
       select 1
       from public.native_action_capabilities capability
       where capability.id = raw_row.native_action_capability_id
         and capability.action = 'sms.ingest'
         and capability.user_id = raw_row.receiver_user_id
         and capability.receiver_momo_number_hash = raw_row.receiver_momo_number_hash
         and capability.request_hash = raw_row.attestation_request_hash
         and capability.consumed_at is not null
     ) then
    return jsonb_build_object('status', 'unattested', 'payment_id', null);
  end if;
  select event.* into event_row
  from public.parsed_payment_events event
  where event.raw_sms_id = raw_row.id;
  if event_row.id is null then
    return jsonb_build_object('status', 'parsing_pending', 'payment_id', null);
  end if;
  select payment.* into payment_row
  from public.payments payment
  where payment.parsed_event_id = event_row.id
  for update;
  if payment_row.id is null then
    return jsonb_build_object(
      'status', 'no_candidate',
      'allocation_status', event_row.allocation_status,
      'payment_id', null
    );
  end if;
  if payment_row.status = 'posted' then
    return jsonb_build_object(
      'status', 'posted', 'payment_id', payment_row.id, 'replayed', true
    );
  end if;
  if payment_row.status <> 'review' then
    return jsonb_build_object(
      'status', payment_row.status, 'payment_id', payment_row.id, 'replayed', true
    );
  end if;
  result := public.process_provider_finality_event(
    raw_row.id,
    'payment.confirmed',
    raw_row.attestation_request_hash,
    payment_row.id,
    event_row.network,
    event_row.transaction_id,
    raw_row.id::text,
    event_row.receiver_phone_hash,
    event_row.amount_rwf,
    coalesce(event_row.transaction_time, raw_row.received_at_device, raw_row.ingested_at),
    raw_row.body_hash,
    null,
    null
  );
  return result || jsonb_build_object('status', 'posted');
end;
$$;

create function collect_hybrid.post_direct_ussd_payment(
  p_event_id uuid,
  p_assignment_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_row public.parsed_payment_events;
  assignment collect_hybrid.member_receiving_assignments;
  route public.collection_receivers;
  member collect_hybrid.member_records;
  raw_row public.raw_payment_sms;
  candidate_payment_id uuid;
begin
  if not coalesce((select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_direct_ussd_allocation'), false) then
    raise exception 'Hybrid direct USSD allocation is disabled';
  end if;
  select event.* into event_row
  from public.parsed_payment_events event
  where event.id = p_event_id
  for update;
  if event_row.id is null then raise exception 'Parsed event not found'; end if;
  select payment.id
  into candidate_payment_id
  from public.payments payment
  where payment.parsed_event_id = p_event_id;
  if candidate_payment_id is not null then
    return candidate_payment_id;
  end if;
  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.receiver_phone_hash is null
     or event_row.payer_match_key is null
     or event_row.confidence < 0.90 then
    raise exception 'Direct USSD evidence is incomplete or below the candidate threshold';
  end if;
  select assignment_row.* into assignment
  from collect_hybrid.member_receiving_assignments assignment_row
  where assignment_row.id = p_assignment_id
    and assignment_row.status = 'active'
  for update;
  if assignment.id is null then raise exception 'Active receiving assignment required'; end if;
  select receiver.* into route
  from public.collection_receivers receiver
  where receiver.id = assignment.collection_receiver_id
    and receiver.collection_id = assignment.collection_id
    and receiver.is_active;
  if route.id is null then raise exception 'Assigned receiving route is no longer active'; end if;
  if route.receiver_user_id <> event_row.receiver_user_id
     or route.momo_number_hash <> event_row.receiver_phone_hash
     or route.network <> event_row.network
     or assignment.route_key <> encode(extensions.digest(
       route.receiver_user_id::text || '|' || route.momo_number_hash || '|' || route.network,
       'sha256'
     ), 'hex') then
    raise exception 'Assigned receiving route does not match the receipt';
  end if;
  select member_row.* into member
  from collect_hybrid.member_records member_row
  join collect_hybrid.member_momo_identities identity
    on identity.member_id = member_row.id
   and identity.match_key = event_row.payer_match_key
  join public.collection_members membership
    on membership.member_record_id = member_row.id
   and membership.collection_id = assignment.collection_id
   and membership.status = 'active'
  where member_row.id = assignment.member_record_id
    and member_row.lifecycle = 'active';
  if member.id is null then raise exception 'Assigned payer identity or membership no longer matches'; end if;
  select raw.* into raw_row from public.raw_payment_sms raw where raw.id = event_row.raw_sms_id;
  if raw_row.id is null
     or raw_row.native_action_capability_id is null
     or raw_row.attestation_request_hash is null
     or raw_row.device_attested_at is null then
    raise exception 'Device-attested SMS evidence is required';
  end if;
  if coalesce(raw_row.received_at_device, raw_row.ingested_at) < assignment.starts_at
     or (assignment.ended_at is not null
       and coalesce(raw_row.received_at_device, raw_row.ingested_at) > assignment.ended_at) then
    raise exception 'Receipt falls outside the receiving assignment period';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    event_row.network || ':' || upper(btrim(event_row.transaction_id)), 0
  ));
  if exists (
    select 1 from public.payments payment
    where payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
  ) then
    select payment.id into candidate_payment_id from public.payments payment
    where payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
    order by payment.created_at limit 1;
    update public.parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Provider transaction evidence was already consumed'
    where id = p_event_id;
    return candidate_payment_id;
  end if;

  insert into public.payments(
    parsed_event_id, payment_intent_id, collection_id, member_record_id,
    contributor_user_id, contributor_public_id, receiver_user_id,
    receiver_momo_number_hash, amount_rwf, transaction_id, provider_network,
    source, status, anonymity_choice, posted_at
  ) values (
    event_row.id, null, assignment.collection_id, member.id,
    member.linked_user_id, member.collect_id, route.receiver_user_id,
    route.momo_number_hash, event_row.amount_rwf, event_row.transaction_id,
    event_row.network, 'sms_auto', 'review', 'public_id', null
  ) returning id into candidate_payment_id;

  insert into public.payment_allocations(
    payment_id, parsed_event_id, collection_id, payment_intent_id,
    member_record_id, allocated_by, allocation_method, confidence, reason
  ) values (
    candidate_payment_id, event_row.id, assignment.collection_id, null,
    member.id, null, 'auto_native_sms', event_row.confidence,
    p_reason || '; awaiting independent provider confirmation'
  );
  update public.parsed_payment_events
  set collection_id = assignment.collection_id,
      allocation_status = 'needs_review',
      review_reason = 'Matched to one direct receiving assignment; awaiting independent provider confirmation'
  where id = event_row.id;
  perform collect_hybrid.record_momo_exception(
    event_row.id, 'provider_confirmation_pending',
    jsonb_build_object(
      'payment_id', candidate_payment_id,
      'member_record_id', member.id,
      'assignment_id', assignment.id
    )
  );
  perform public.create_audit_log(
    'payment.awaiting_provider_confirmation', 'payment', candidate_payment_id,
    jsonb_build_object(
      'parsed_event_id', event_row.id,
      'member_record_id', member.id,
      'assignment_id', assignment.id,
      'method', 'direct_ussd_assignment',
      'reason', p_reason,
      'ledger_posted', false
    ),
    null
  );
  return candidate_payment_id;
end;
$$;

create or replace function public.allocate_parsed_payment_event(event_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_row public.parsed_payment_events;
  evidence_time timestamptz;
  intent_count integer := 0;
  intent_id uuid;
  intent_collection_id uuid;
  intent_receiver_hash text;
  intent_member_id uuid;
  direct_count integer := 0;
  direct_assignment_id uuid;
  direct_collection_id uuid;
  direct_member_id uuid;
  direct_enabled boolean;
  result_status text;
  existing_payment_status text;
begin
  select event.* into event_row
  from public.parsed_payment_events event
  where event.id = event_id
  for update;
  if event_row.id is null then raise exception 'Parsed event not found'; end if;
  select coalesce(raw.received_at_device, raw.ingested_at)
  into evidence_time
  from public.raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;
  select payment.status into existing_payment_status
  from public.payments payment
  where payment.parsed_event_id = event_id;
  if existing_payment_status = 'posted'
     or event_row.allocation_status = 'allocated' then
    return 'already_allocated';
  elsif existing_payment_status = 'review' then
    return 'awaiting_provider_confirmation';
  elsif existing_payment_status = 'reversed'
     or event_row.allocation_status = 'ignored' then
    return 'ignored';
  end if;
  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.confidence < 0.90
     or evidence_time is null then
    update public.parsed_payment_events
    set allocation_status = 'needs_review',
        review_reason = 'SMS evidence is incomplete or not reliable enough for candidate matching'
    where id = event_id;
    perform collect_hybrid.record_momo_exception(
      event_id, 'no_candidate', jsonb_build_object('stage', 'evidence_validation')
    );
    return 'needs_review';
  end if;

  -- Serialize every route on the same provider reference and treat the
  -- reference as consumed even after rejection or compensating reversal.
  perform pg_advisory_xact_lock(hashtextextended(
    event_row.network || ':' || upper(btrim(event_row.transaction_id)), 0
  ));
  if exists (
    select 1 from public.payments payment
    where payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
  ) then
    update public.parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Provider transaction evidence was already consumed'
    where id = event_id;
    return 'ignored';
  end if;

  update public.payment_intents set status = 'expired'
  where status = 'pending' and expires_at <= now();
  if event_row.transaction_id is not null then
    with candidates as (
      select distinct
        intent.id,
        intent.collection_id,
        intent.receiver_momo_number_hash,
        intent.contributor_user_id,
        intent.contributor_public_id,
        intent.created_at
      from public.payment_intents intent
      join public.collection_receivers route
        on route.collection_id = intent.collection_id
       and route.momo_number_hash = intent.receiver_momo_number_hash
       and route.is_active
       and route.receiver_user_id = event_row.receiver_user_id
      where intent.status = 'pending'
        and (event_row.collection_id is null or intent.collection_id = event_row.collection_id)
        and (event_row.receiver_phone_hash is null
          or intent.receiver_momo_number_hash = event_row.receiver_phone_hash)
        and intent.expected_amount_rwf = event_row.amount_rwf
        and evidence_time between intent.created_at - interval '15 minutes'
          and intent.expires_at + interval '2 hours'
        and (
          (event_row.sender_phone_hash is not null
            and intent.sender_phone_hash = event_row.sender_phone_hash)
          or (event_row.detected_user_public_id is not null
            and intent.contributor_public_id = event_row.detected_user_public_id)
        )
    )
    select count(*),
      (array_agg(candidate.id order by candidate.created_at))[1],
      (array_agg(candidate.collection_id order by candidate.created_at))[1],
      (array_agg(candidate.receiver_momo_number_hash order by candidate.created_at))[1],
      (array_agg(member.id order by candidate.created_at))[1]
    into intent_count, intent_id, intent_collection_id, intent_receiver_hash, intent_member_id
    from candidates candidate
    left join collect_hybrid.member_records member
      on member.linked_user_id = candidate.contributor_user_id
      or (
        candidate.contributor_user_id is null
        and candidate.contributor_public_id is not null
        and member.collect_id = candidate.contributor_public_id
      );
  end if;

  direct_enabled := coalesce((select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_direct_ussd_allocation'), false);
  if direct_enabled and event_row.transaction_id is not null
     and event_row.receiver_phone_hash is not null
     and event_row.payer_match_key is not null then
    with candidates as (
      select distinct
        assignment.id,
        assignment.collection_id,
        assignment.member_record_id,
        assignment.created_at
      from collect_hybrid.member_receiving_assignments assignment
      join public.collection_receivers route
        on route.id = assignment.collection_receiver_id
       and route.collection_id = assignment.collection_id
       and route.is_active
       and route.receiver_user_id = event_row.receiver_user_id
       and route.momo_number_hash = event_row.receiver_phone_hash
       and route.network = event_row.network
       and assignment.route_key = encode(extensions.digest(
         route.receiver_user_id::text || '|' || route.momo_number_hash || '|' || route.network,
         'sha256'
       ), 'hex')
      join collect_hybrid.member_records member
        on member.id = assignment.member_record_id and member.lifecycle = 'active'
      join collect_hybrid.member_momo_identities identity
        on identity.member_id = member.id and identity.match_key = event_row.payer_match_key
      join public.collection_members membership
        on membership.member_record_id = member.id
       and membership.collection_id = assignment.collection_id
       and membership.status = 'active'
      where assignment.status = 'active'
        and evidence_time >= assignment.starts_at
        and (assignment.ended_at is null or evidence_time <= assignment.ended_at)
        and (event_row.collection_id is null or assignment.collection_id = event_row.collection_id)
    )
    select count(*),
      (array_agg(candidate.id order by candidate.created_at))[1],
      (array_agg(candidate.collection_id order by candidate.created_at))[1],
      (array_agg(candidate.member_record_id order by candidate.created_at))[1]
    into direct_count, direct_assignment_id, direct_collection_id, direct_member_id
    from candidates candidate;
  end if;

  if intent_count > 1 or direct_count > 1 then
    update public.parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'Multiple payer-verified destinations matched this SMS evidence'
    where id = event_id;
    perform collect_hybrid.record_momo_exception(
      event_id, 'ambiguous_candidate',
      jsonb_build_object('intent_candidates', intent_count, 'direct_candidates', direct_count)
    );
    return 'ambiguous';
  end if;
  if intent_count = 1 and direct_count = 1
     and (intent_collection_id <> direct_collection_id
       or intent_member_id is distinct from direct_member_id) then
    update public.parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'Payment intent and direct receiving assignment disagree'
    where id = event_id;
    perform collect_hybrid.record_momo_exception(
      event_id, 'intent_direct_disagreement',
      jsonb_build_object(
        'intent_collection_id', intent_collection_id,
        'direct_collection_id', direct_collection_id,
        'intent_member_record_id', intent_member_id,
        'direct_member_record_id', direct_member_id
      )
    );
    return 'ambiguous';
  end if;
  if intent_count = 1 then
    if event_row.receiver_phone_hash is null then
      update public.parsed_payment_events
      set receiver_phone_hash = intent_receiver_hash,
          collection_id = coalesce(collection_id, intent_collection_id)
      where id = event_id;
    end if;
    perform public.post_payment_from_event(
      event_id, intent_id, intent_collection_id,
      case when direct_count = 1 then
        'Matched by one agreeing payment intent and direct receiving assignment'
      when event_row.receiver_phone_hash is null then
        'Matched by native SMS transaction ID plus one unique owned receiver, amount, payer, and time window'
      else
        'Matched by native SMS transaction ID, receiver, amount, payer, and time window'
      end
    );
    select event.allocation_status::text into result_status
    from public.parsed_payment_events event where event.id = event_id;
    if result_status = 'allocated' then
      update collect_hybrid.momo_reconciliation_exceptions
      set status = 'resolved', resolved_at = now()
      where parsed_event_id = event_id and status = 'open';
      return 'allocated';
    elsif result_status = 'needs_review' then
      return 'awaiting_provider_confirmation';
    end if;
    return 'ignored';
  end if;
  if direct_count = 1 then
    perform collect_hybrid.post_direct_ussd_payment(
      event_id, direct_assignment_id,
      'Matched by exact normalized MoMo name plus last three digits and one explicit active receiving assignment'
    );
    select event.allocation_status::text into result_status
    from public.parsed_payment_events event where event.id = event_id;
    if result_status = 'allocated' then
      return 'allocated';
    elsif result_status = 'needs_review' then
      return 'awaiting_provider_confirmation';
    end if;
    return 'ignored';
  end if;

  update public.parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = case when direct_enabled then
        'No payer-verified payment intent or direct receiving assignment matched this SMS evidence'
      else 'No payer-verified pending payment intent matched this SMS evidence' end
  where id = event_id;
  perform collect_hybrid.record_momo_exception(
    event_id, 'no_candidate',
    jsonb_build_object(
      'intent_candidates', intent_count,
      'direct_candidates', direct_count,
      'direct_allocation_enabled', direct_enabled
    )
  );
  return 'needs_review';
end;
$$;

create function public.admin_reverse_momo_payment(
  p_payment_id uuid,
  p_reason text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  clean_reason text := btrim(coalesce(p_reason, ''));
  input_hash text;
  prior collect_hybrid.momo_reversal_requests;
  payment_row public.payments;
  original_entry collect_hybrid.momo_journal_entries;
  reversal_id uuid;
  group_balance bigint;
  member_balance bigint;
  response jsonb;
begin
  perform public.assert_admin_permission('payments.allocate');
  if p_request_id is null or p_payment_id is null
     or char_length(clean_reason) not between 8 and 500 then
    raise exception 'Payment, request ID and complete reversal reason required';
  end if;
  input_hash := encode(extensions.digest(
    jsonb_build_array(p_payment_id, clean_reason)::text, 'sha256'
  ), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('hybrid-momo-reversal:' || p_request_id::text, 0));
  select request.* into prior
  from collect_hybrid.momo_reversal_requests request
  where request.request_id = p_request_id;
  if prior.request_id is not null then
    if prior.actor_id <> actor_id or prior.payment_id <> p_payment_id
       or prior.input_hash <> input_hash then
      raise exception 'MoMo reversal idempotency key conflict';
    end if;
    return prior.result || jsonb_build_object('replay', true);
  end if;

  select payment.* into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if payment_row.id is null then raise exception 'Payment not found'; end if;
  if payment_row.status <> 'posted' then raise exception 'Only a posted payment can be reversed'; end if;
  select entry.* into original_entry
  from collect_hybrid.momo_journal_entries entry
  where entry.payment_id = payment_row.id and entry.entry_type = 'receipt'
  for share;
  if original_entry.id is null then raise exception 'Canonical receipt journal required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'hybrid-momo-group-balance:' || payment_row.collection_id::text, 0
  ));
  if payment_row.member_record_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'hybrid-momo-member-balance:' || payment_row.collection_id::text || ':' || payment_row.member_record_id::text,
      0
    ));
  end if;

  insert into collect_hybrid.momo_journal_entries(
    payment_id, parsed_event_id, collection_id, member_record_id,
    entry_type, amount_rwf, external_reference, reverses_entry_id, created_by
  ) values (
    payment_row.id, payment_row.parsed_event_id, payment_row.collection_id,
    payment_row.member_record_id, 'reversal', payment_row.amount_rwf,
    'reversal:' || original_entry.id::text, original_entry.id, actor_id
  ) returning id into reversal_id;
  insert into collect_hybrid.momo_journal_lines(
    journal_entry_id, account_code, direction, amount_rwf
  ) values
    (reversal_id, 'member_savings_liability:RWF', 'debit', payment_row.amount_rwf),
    (reversal_id, 'momo_receiving_asset:RWF', 'credit', payment_row.amount_rwf);

  -- Keep every compatibility reader financially equivalent without mutating
  -- the original immutable projection rows.
  insert into public.ledger_entries(
    payment_id, collection_id, user_id, member_record_id,
    entry_type, amount_rwf, currency, visibility, metadata
  )
  select ledger.payment_id, ledger.collection_id, ledger.user_id,
    ledger.member_record_id, ledger.entry_type, -ledger.amount_rwf,
    ledger.currency, ledger.visibility,
    ledger.metadata || jsonb_build_object(
      'compensates_ledger_entry_id', ledger.id,
      'momo_reversal_journal_entry_id', reversal_id,
      'reversal_request_id', p_request_id
    )
  from public.ledger_entries ledger
  where ledger.payment_id = payment_row.id
    and ledger.entry_type in ('collection_credit', 'member_credit')
    and ledger.amount_rwf > 0
  on conflict do nothing;

  update collect_hybrid.collection_balances balance
  set confirmed_rwf = balance.confirmed_rwf - payment_row.amount_rwf,
      updated_at = now()
  where balance.collection_id = payment_row.collection_id
    and balance.confirmed_rwf >= payment_row.amount_rwf
  returning confirmed_rwf into group_balance;
  if group_balance is null then raise exception 'Group balance cannot support this reversal'; end if;
  if payment_row.member_record_id is not null then
    update collect_hybrid.member_balances balance
    set confirmed_rwf = balance.confirmed_rwf - payment_row.amount_rwf,
        updated_at = now()
    where balance.collection_id = payment_row.collection_id
      and balance.member_record_id = payment_row.member_record_id
      and balance.confirmed_rwf >= payment_row.amount_rwf
    returning confirmed_rwf into member_balance;
    if member_balance is null then raise exception 'Member balance cannot support this reversal'; end if;
  end if;
  insert into collect_hybrid.momo_balance_snapshots(
    journal_entry_id, payment_id, collection_id, member_record_id,
    event_type, delta_rwf, member_balance_after_rwf, group_balance_after_rwf
  ) values (
    reversal_id, payment_row.id, payment_row.collection_id, payment_row.member_record_id,
    'reversal', -payment_row.amount_rwf, member_balance, group_balance
  );
  update public.payments set status = 'reversed' where id = payment_row.id;
  response := jsonb_build_object(
    'ok', true,
    'payment_id', payment_row.id,
    'reversal_journal_entry_id', reversal_id,
    'member_balance_after_rwf', member_balance,
    'group_balance_after_rwf', group_balance,
    'replay', false
  );
  insert into collect_hybrid.momo_reversal_requests(request_id, payment_id, actor_id, input_hash, result)
  values (p_request_id, payment_row.id, actor_id, input_hash, response);
  perform public.create_audit_log(
    'payment.reversed.momo', 'payment', payment_row.id,
    jsonb_build_object(
      'reason', clean_reason,
      'request_id', p_request_id,
      'reversal_journal_entry_id', reversal_id
    )
  );
  return response;
end;
$$;

-- The member app reads the canonical RWF balances. Diaspora bank balances
-- remain separately aggregated in their own currency and are never combined.
create or replace function public.list_current_member_collection_balances()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  with visible as (
    select collection.id
    from public.collections collection
    where public.user_can_read_collection(collection.id, auth.uid())
  ), amounts as (
    select balance.collection_id, 'RWF'::text as currency,
      balance.confirmed_rwf::bigint as raised,
      coalesce((
        select sum(member_balance.confirmed_rwf)::bigint
        from collect_hybrid.member_balances member_balance
        join collect_hybrid.member_records member
          on member.id = member_balance.member_record_id
        where member_balance.collection_id = balance.collection_id
          and member.linked_user_id = auth.uid()
      ), 0)::bigint as own
    from collect_hybrid.collection_balances balance
    join visible on visible.id = balance.collection_id
    union all
    select allocation.collection_id, transaction.currency,
      sum(transaction.amount_minor)::bigint,
      coalesce(sum(transaction.amount_minor) filter (
        where allocation.contributor_user_id = auth.uid()
      ), 0)::bigint
    from public.bank_transactions transaction
    join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = transaction.id
    join visible on visible.id = allocation.collection_id
    where transaction.status = 'reconciled'
    group by allocation.collection_id, transaction.currency
  ), contributors as (
    select payment.collection_id, payment.contributor_user_id
    from public.payments payment
    join visible on visible.id = payment.collection_id
    where payment.status = 'posted'
    union all
    select allocation.collection_id, allocation.contributor_user_id
    from public.bank_transactions transaction
    join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = transaction.id
    join visible on visible.id = allocation.collection_id
    where transaction.status = 'reconciled'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'collection_id', visible.id,
    'balances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', amount.currency,
        'amount_raised_minor', amount.raised,
        'current_user_balance_minor', amount.own
      ) order by amount.currency)
      from amounts amount where amount.collection_id = visible.id
    ), '[]'::jsonb),
    'supporter_count', (
      select case when count(*) filter (where contributor_user_id is null) > 0
        then null else count(distinct contributor_user_id) end
      from contributors contributor
      where contributor.collection_id = visible.id
    )
  ) order by visible.id), '[]'::jsonb)
  into result
  from visible;
  return result;
end;
$$;

create or replace function public.list_current_user_collection_summaries()
returns table(
  collection_id uuid,
  amount_raised_rwf bigint,
  supporter_count bigint,
  current_user_balance_rwf bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select collection.id,
    coalesce(balance.confirmed_rwf, 0)::bigint,
    coalesce((
      select count(distinct coalesce(
        payment.contributor_user_id::text,
        payment.transaction_id,
        payment.id::text
      ))
      from public.payments payment
      where payment.collection_id = collection.id
        and payment.status = 'posted'
    ), 0)::bigint,
    coalesce((
      select sum(member_balance.confirmed_rwf)
      from collect_hybrid.member_balances member_balance
      join collect_hybrid.member_records member
        on member.id = member_balance.member_record_id
      where member_balance.collection_id = collection.id
        and member.linked_user_id = auth.uid()
    ), 0)::bigint
  from public.collections collection
  left join collect_hybrid.collection_balances balance
    on balance.collection_id = collection.id
  where auth.uid() is not null
    and collection.archived_at is null
    and public.user_can_read_collection(collection.id, auth.uid());
$$;

-- Admin ledger rows are projected directly from balanced canonical journal
-- entries, so a reversal is visible as its own compensating transaction.
create or replace function public.admin_list_collect_ledgers(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('ledger.read');
  with unified as (
    select
      'momo:' || entry.id::text as id,
      entry.external_reference as title,
      case when entry.entry_type = 'reversal'
        then 'Rwanda · compensating MoMo reversal'
        else 'Rwanda · provider-confirmed MoMo receipt' end as subtitle,
      case when entry.entry_type = 'reversal'
        then 'reversed' else 'balanced' end as status,
      ('RWF ' || case when entry.entry_type = 'reversal' then '-' else '' end
        || to_char(entry.amount_rwf, 'FM999G999G999G999') || ' =') as amount,
      entry.created_at,
      jsonb_build_object(
        'rail', 'rw_momo',
        'payment_id', entry.payment_id,
        'journal_entry_id', entry.id,
        'collection_id', entry.collection_id,
        'debit_total', totals.debit_total,
        'credit_total', totals.credit_total,
        'currency', 'RWF',
        'line_count', totals.line_count,
        'entry_type', entry.entry_type
      ) as extra
    from collect_hybrid.momo_journal_entries entry
    join lateral (
      select
        coalesce(sum(line.amount_rwf) filter (
          where line.direction = 'debit'
        ), 0)::bigint as debit_total,
        coalesce(sum(line.amount_rwf) filter (
          where line.direction = 'credit'
        ), 0)::bigint as credit_total,
        count(*)::bigint as line_count
      from collect_hybrid.momo_journal_lines line
      where line.journal_entry_id = entry.id
    ) totals on true
    union all
    select
      'diaspora:' || journal.id::text,
      coalesce(journal.external_reference, 'Diaspora journal ' || right(journal.id::text, 8)),
      'Diaspora · ' || journal.description,
      case when totals.debit_total = totals.credit_total and totals.debit_total > 0
        then 'balanced' else 'unbalanced' end,
      journal.currency || ' '
        || to_char(totals.debit_total::numeric / 100, 'FM999G999G999D00') || ' =',
      journal.posted_at,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'journal_entry_id', journal.id,
        'transaction_id', journal.bank_transaction_id,
        'collection_id', journal.collection_id,
        'debit_total', totals.debit_total,
        'credit_total', totals.credit_total,
        'currency', journal.currency,
        'line_count', totals.line_count
      )
    from public.journal_entries journal
    join lateral (
      select
        coalesce(sum(line.amount_minor) filter (
          where line.direction = 'debit'
        ), 0)::bigint as debit_total,
        coalesce(sum(line.amount_minor) filter (
          where line.direction = 'credit'
        ), 0)::bigint as credit_total,
        count(*)::bigint as line_count
      from public.journal_lines line
      where line.journal_entry_id = journal.id
    ) totals on true
  ), filtered as (
    select * from unified
    where (nullif(btrim(coalesce(p_status, '')), '') is null
        or status = btrim(p_status))
      and (nullif(btrim(coalesce(p_search, '')), '') is null
        or title ilike '%' || btrim(p_search) || '%'
        or subtitle ilike '%' || btrim(p_search) || '%')
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(jsonb_build_object(
      'id', id,
      'title', title,
      'subtitle', subtitle,
      'status', status,
      'amount', amount,
      'created_at', created_at
    ) || extra order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result
  from counted;
  return result;
end;
$$;

alter table collect_hybrid.member_receiving_assignments enable row level security;
alter table collect_hybrid.receiving_assignment_requests enable row level security;
alter table collect_hybrid.momo_journal_entries enable row level security;
alter table collect_hybrid.momo_journal_lines enable row level security;
alter table collect_hybrid.collection_balances enable row level security;
alter table collect_hybrid.member_balances enable row level security;
alter table collect_hybrid.momo_balance_snapshots enable row level security;
alter table collect_hybrid.momo_reconciliation_exceptions enable row level security;
alter table collect_hybrid.momo_reversal_requests enable row level security;

revoke all on all tables in schema collect_hybrid from public, anon, authenticated, service_role;
revoke all on all functions in schema collect_hybrid from public, anon, authenticated, service_role;
grant execute on function collect_hybrid.create_assisted_group(text, text, uuid),
  collect_hybrid.add_roster(uuid, jsonb, uuid, text) to authenticated;
revoke all on function public.admin_assign_hybrid_receiving_route(uuid, uuid, uuid, text, uuid)
  from public, anon;
grant execute on function public.admin_assign_hybrid_receiving_route(uuid, uuid, uuid, text, uuid)
  to authenticated;
revoke all on function public.admin_reverse_momo_payment(uuid, text, uuid)
  from public, anon;
grant execute on function public.admin_reverse_momo_payment(uuid, text, uuid)
  to authenticated;
revoke all on function public.allocate_parsed_payment_event(uuid)
  from public, anon, authenticated;
grant execute on function public.allocate_parsed_payment_event(uuid)
  to service_role;
revoke all on function public.post_payment_from_event(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.confirm_provider_payment(
  uuid, text, text, text, text, bigint, timestamptz, text
) from public, anon, authenticated;
grant execute on function public.confirm_provider_payment(
  uuid, text, text, text, text, bigint, timestamptz, text
) to service_role;
revoke all on function public.reject_provider_payment(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.reject_provider_payment(uuid, text, text)
  to service_role;
revoke all on function public.process_provider_finality_event(
  uuid, text, text, uuid, text, text, text, text, bigint, timestamptz, text,
  text, text
) from public, anon, authenticated;
grant execute on function public.process_provider_finality_event(
  uuid, text, text, uuid, text, text, text, text, bigint, timestamptz, text,
  text, text
) to service_role;
revoke all on function public.finalize_attested_payment_sms(uuid)
  from public, anon, authenticated;
grant execute on function public.finalize_attested_payment_sms(uuid)
  to service_role;

comment on table collect_hybrid.member_receiving_assignments is
  'Explicit effective-dated member-to-group assignment for one physical MoMo receiving route; never inferred from group order.';
comment on table collect_hybrid.momo_journal_entries is
  'Canonical immutable balanced RWF receipt and compensating-reversal journal.';
comment on table collect_hybrid.momo_balance_snapshots is
  'Immutable after-transaction member and group balances used by delayed notifications and audit readback.';
comment on function public.allocate_parsed_payment_event(uuid) is
  'Creates one provider-confirmation candidate from a payer-verified intent or, when separately enabled, one exact identity plus explicit active receiving assignment; SMS never posts money by itself.';
comment on function public.process_provider_finality_event(
  uuid, text, text, uuid, text, text, text, text, bigint, timestamptz, text,
  text, text
) is 'Replay-safe service-only gateway for independent provider confirmation or rejection.';
comment on function public.finalize_attested_payment_sms(uuid) is
  'Finalizes only an exact MTN/Airtel receipt envelope bound to a consumed, fresh Play Integrity capability; arbitrary signed-in client SMS is never final evidence.';

commit;
