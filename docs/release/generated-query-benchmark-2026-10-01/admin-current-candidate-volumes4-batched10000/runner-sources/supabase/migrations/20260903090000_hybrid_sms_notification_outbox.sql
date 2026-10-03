begin;

-- SMS delivery is a separately controlled channel. Creating the durable queue
-- does not enable sending, configure a collection, or replay old payments.
insert into public.feature_flags(key, enabled, description)
values (
  'hybrid_sms_notifications',
  false,
  'Pilot gate: enqueue deterministic Buri Munsi receipts for account-independent members with recorded consent'
)
on conflict (key) do nothing;

create table collect_hybrid.sms_receipt_policies (
  collection_id uuid primary key references public.collections(id) on delete restrict,
  enabled boolean not null default false,
  template_key text not null default 'buri_munsi.payment_received',
  template_version integer not null default 1 check (template_version = 1),
  revision integer not null default 1 check (revision > 0),
  reason text not null check (char_length(btrim(reason)) between 8 and 500),
  updated_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  check (template_key = 'buri_munsi.payment_received')
);

create table collect_hybrid.sms_receipt_member_consents (
  member_record_id uuid primary key
    references collect_hybrid.member_records(id) on delete restrict,
  enabled boolean not null default false,
  capture_method text not null check (
    capture_method in ('verbal', 'written', 'sms_request', 'other')
  ),
  revision integer not null default 1 check (revision > 0),
  reason text not null check (char_length(btrim(reason)) between 8 and 500),
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  recorded_at timestamptz not null default now()
);

create table collect_hybrid.sms_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  snapshot_id uuid not null unique
    references collect_hybrid.momo_balance_snapshots(id) on delete restrict,
  collection_id uuid not null references public.collections(id) on delete restrict,
  member_record_id uuid not null
    references collect_hybrid.member_records(id) on delete restrict,
  destination_e164 text not null check (destination_e164 ~ '^\+2507[2389][0-9]{7}$'),
  destination_sha256 text not null check (destination_sha256 ~ '^[0-9a-f]{64}$'),
  destination_revision integer not null check (destination_revision > 0),
  policy_revision integer not null check (policy_revision > 0),
  consent_revision integer not null check (consent_revision > 0),
  template_key text not null check (template_key = 'buri_munsi.payment_received'),
  template_version integer not null check (template_version = 1),
  amount_rwf bigint not null check (amount_rwf > 0),
  member_balance_rwf bigint not null check (member_balance_rwf >= 0),
  group_balance_rwf bigint not null check (group_balance_rwf >= 0),
  reference text not null,
  message_body text,
  body_sha256 text check (body_sha256 is null or body_sha256 ~ '^[0-9a-f]{64}$'),
  state text not null default 'queued' check (state in (
    'queued', 'awaiting_confirmation', 'send_started', 'observed_sent',
    'failed_no_send', 'uncertain', 'suppressed'
  )),
  suppression_reason text,
  fence_version integer not null default 0 check (fence_version >= 0),
  claim_token uuid,
  claimed_by text,
  claim_expires_at timestamptz,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  observed_sent_at timestamptz,
  unique(payment_id, template_key),
  check (
    (state = 'suppressed' and suppression_reason is not null)
    or (state <> 'suppressed' and message_body is not null and body_sha256 is not null)
  ),
  check (
    (state = 'awaiting_confirmation' and claim_token is not null
      and claimed_by is not null and claim_expires_at is not null)
    or state <> 'awaiting_confirmation'
  )
);
create index hybrid_sms_outbox_pending_idx
  on collect_hybrid.sms_notification_outbox(state, created_at, id)
  where state in ('queued', 'awaiting_confirmation', 'send_started', 'uncertain');

create table collect_hybrid.sms_notification_claim_requests (
  request_id uuid primary key,
  operator_user_id uuid not null references public.profiles(id) on delete restrict,
  outbox_id uuid not null references collect_hybrid.sms_notification_outbox(id) on delete restrict,
  worker_id text not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);

create table collect_hybrid.sms_notification_confirmations (
  id uuid primary key,
  outbox_id uuid not null references collect_hybrid.sms_notification_outbox(id) on delete restrict,
  operator_user_id uuid not null references public.profiles(id) on delete restrict,
  claim_token uuid not null,
  fence_version integer not null check (fence_version > 0),
  destination_revision integer not null check (destination_revision > 0),
  body_sha256 text not null check (body_sha256 ~ '^[0-9a-f]{64}$'),
  approved_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  unique(outbox_id, claim_token, fence_version),
  check (expires_at > approved_at)
);

create table collect_hybrid.sms_notification_attempts (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null references collect_hybrid.sms_notification_outbox(id) on delete restrict,
  confirmation_id uuid not null unique
    references collect_hybrid.sms_notification_confirmations(id) on delete restrict,
  operator_user_id uuid not null references public.profiles(id) on delete restrict,
  worker_id text not null,
  claim_token uuid not null,
  fence_version integer not null check (fence_version > 0),
  attempt_number integer not null check (attempt_number > 0),
  destination_sha256 text not null check (destination_sha256 ~ '^[0-9a-f]{64}$'),
  destination_revision integer not null check (destination_revision > 0),
  body_sha256 text not null check (body_sha256 ~ '^[0-9a-f]{64}$'),
  state text not null default 'send_started' check (state in (
    'send_started', 'observed_sent', 'failed_no_send', 'uncertain'
  )),
  send_started_at timestamptz not null default clock_timestamp(),
  outcome_at timestamptz,
  evidence_reference text,
  outcome_note text,
  unique(outbox_id, attempt_number),
  check (
    (state = 'send_started' and outcome_at is null)
    or (state <> 'send_started' and outcome_at is not null)
  )
);

create table collect_hybrid.sms_operator_heartbeats (
  worker_id text primary key,
  operator_user_id uuid not null references public.profiles(id) on delete restrict,
  run_id uuid not null,
  mode text not null check (mode in ('no_send', 'assisted_send')),
  observed_at timestamptz not null default clock_timestamp(),
  safe_status jsonb not null default '{}'::jsonb,
  check (worker_id ~ '^[A-Za-z0-9._:-]{3,80}$'),
  check (jsonb_typeof(safe_status) = 'object')
);

alter table collect_hybrid.sms_receipt_policies enable row level security;
alter table collect_hybrid.sms_receipt_member_consents enable row level security;
alter table collect_hybrid.sms_notification_outbox enable row level security;
alter table collect_hybrid.sms_notification_claim_requests enable row level security;
alter table collect_hybrid.sms_notification_confirmations enable row level security;
alter table collect_hybrid.sms_notification_attempts enable row level security;
alter table collect_hybrid.sms_operator_heartbeats enable row level security;
revoke all on collect_hybrid.sms_receipt_policies,
  collect_hybrid.sms_receipt_member_consents,
  collect_hybrid.sms_notification_outbox,
  collect_hybrid.sms_notification_claim_requests,
  collect_hybrid.sms_notification_confirmations,
  collect_hybrid.sms_notification_attempts,
  collect_hybrid.sms_operator_heartbeats
from public, anon, authenticated, service_role;

create function collect_hybrid.render_buri_munsi_receipt(
  p_amount_rwf bigint,
  p_member_balance_rwf bigint,
  p_group_balance_rwf bigint,
  p_reference text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  clean_reference text := btrim(coalesce(p_reference, ''));
begin
  if p_amount_rwf is null or p_amount_rwf <= 0
     or p_member_balance_rwf is null or p_member_balance_rwf < 0
     or p_group_balance_rwf is null or p_group_balance_rwf < 0
     or clean_reference !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$' then
    raise exception 'Invalid Buri Munsi receipt snapshot';
  end if;
  return 'BuriMunsi: Twakiriye ubwizigame bwawe bwa '
    || to_char(p_amount_rwf, 'FM999,999,999,999,999,990')
    || ' RWF. Balance yawe: '
    || to_char(p_member_balance_rwf, 'FM999,999,999,999,999,990')
    || ' RWF; balance y''itsinda: '
    || to_char(p_group_balance_rwf, 'FM999,999,999,999,999,990')
    || ' RWF. Ref: ' || clean_reference || '.';
end;
$$;

create function collect_hybrid.protect_sms_outbox_core()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'SMS notification evidence is retained';
  end if;
  if new.payment_id is distinct from old.payment_id
     or new.snapshot_id is distinct from old.snapshot_id
     or new.collection_id is distinct from old.collection_id
     or new.member_record_id is distinct from old.member_record_id
     or new.destination_e164 is distinct from old.destination_e164
     or new.destination_sha256 is distinct from old.destination_sha256
     or new.destination_revision is distinct from old.destination_revision
     or new.policy_revision is distinct from old.policy_revision
     or new.consent_revision is distinct from old.consent_revision
     or new.template_key is distinct from old.template_key
     or new.template_version is distinct from old.template_version
     or new.amount_rwf is distinct from old.amount_rwf
     or new.member_balance_rwf is distinct from old.member_balance_rwf
     or new.group_balance_rwf is distinct from old.group_balance_rwf
     or new.reference is distinct from old.reference
     or new.message_body is distinct from old.message_body
     or new.body_sha256 is distinct from old.body_sha256
     or (
       new.suppression_reason is distinct from old.suppression_reason
       and not (
         old.suppression_reason is null
         and new.state = 'suppressed'
         and char_length(btrim(coalesce(new.suppression_reason, ''))) between 8 and 500
       )
     )
     or new.created_at is distinct from old.created_at then
    raise exception 'SMS notification payload and ledger snapshot are immutable';
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;
create trigger protect_sms_outbox_core_trigger
before update or delete on collect_hybrid.sms_notification_outbox
for each row execute function collect_hybrid.protect_sms_outbox_core();

create function collect_hybrid.protect_sms_attempt_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then raise exception 'SMS attempt evidence is retained'; end if;
  if new.outbox_id is distinct from old.outbox_id
     or new.confirmation_id is distinct from old.confirmation_id
     or new.operator_user_id is distinct from old.operator_user_id
     or new.worker_id is distinct from old.worker_id
     or new.claim_token is distinct from old.claim_token
     or new.fence_version is distinct from old.fence_version
     or new.attempt_number is distinct from old.attempt_number
     or new.destination_sha256 is distinct from old.destination_sha256
     or new.destination_revision is distinct from old.destination_revision
     or new.body_sha256 is distinct from old.body_sha256
     or new.send_started_at is distinct from old.send_started_at then
    raise exception 'SMS send-start evidence is immutable';
  end if;
  if old.state <> 'send_started' then
    raise exception 'SMS attempt outcome is final';
  end if;
  return new;
end;
$$;
create trigger protect_sms_attempt_history_trigger
before update or delete on collect_hybrid.sms_notification_attempts
for each row execute function collect_hybrid.protect_sms_attempt_history();

create function collect_hybrid.operator_authorized(
  p_operator_user_id uuid,
  p_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.role() = 'service_role'
    and collect_admin_access.permission_allowed(p_permission, p_operator_user_id), false);
$$;

create function public.admin_set_sms_receipt_policy(
  p_collection_id uuid,
  p_enabled boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_reason text := btrim(coalesce(p_reason, ''));
  policy collect_hybrid.sms_receipt_policies;
begin
  perform public.assert_admin_permission('notifications.manage');
  perform public.assert_admin_permission('collections.moderate');
  if p_collection_id is null or p_enabled is null
     or char_length(clean_reason) not between 8 and 500 then
    raise exception 'Collection, state and audit reason are required';
  end if;
  if not exists (
    select 1 from public.collections collection
    where collection.id = p_collection_id
      and collection.collection_type = 'ikimina'
      and collection.archived_at is null
  ) then
    raise exception 'Active group savings collection required';
  end if;
  insert into collect_hybrid.sms_receipt_policies(
    collection_id, enabled, reason, updated_by
  ) values (
    p_collection_id, p_enabled, clean_reason, auth.uid()
  )
  on conflict (collection_id) do update
  set enabled = excluded.enabled,
      revision = collect_hybrid.sms_receipt_policies.revision + 1,
      reason = excluded.reason,
      updated_by = excluded.updated_by,
      updated_at = clock_timestamp()
  returning * into policy;
  perform public.create_audit_log(
    'collection.sms_receipt_policy.changed', 'collection', p_collection_id,
    jsonb_build_object(
      'enabled', policy.enabled,
      'template_key', policy.template_key,
      'template_version', policy.template_version,
      'revision', policy.revision,
      'reason', clean_reason
    )
  );
  return jsonb_build_object(
    'ok', true, 'collection_id', policy.collection_id,
    'enabled', policy.enabled, 'revision', policy.revision,
    'template_key', policy.template_key,
    'template_version', policy.template_version
  );
end;
$$;

create function public.admin_set_member_sms_receipt_consent(
  p_member_record_id uuid,
  p_enabled boolean,
  p_capture_method text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_method text := lower(btrim(coalesce(p_capture_method, '')));
  clean_reason text := btrim(coalesce(p_reason, ''));
  consent collect_hybrid.sms_receipt_member_consents;
begin
  perform public.assert_admin_permission('notifications.manage');
  perform public.assert_admin_permission('users.read');
  if p_member_record_id is null or p_enabled is null
     or clean_method not in ('verbal', 'written', 'sms_request', 'other')
     or char_length(clean_reason) not between 8 and 500 then
    raise exception 'Member, consent state, capture method and audit reason are required';
  end if;
  if not exists (
    select 1
    from collect_hybrid.member_records member
    join collect_hybrid.member_momo_identities identity
      on identity.member_id = member.id
    where member.id = p_member_record_id
      and member.lifecycle = 'active'
      and member.linked_user_id is null
  ) then
    raise exception 'Active account-independent MoMo member required';
  end if;
  insert into collect_hybrid.sms_receipt_member_consents(
    member_record_id, enabled, capture_method, reason, recorded_by
  ) values (
    p_member_record_id, p_enabled, clean_method, clean_reason, auth.uid()
  )
  on conflict (member_record_id) do update
  set enabled = excluded.enabled,
      capture_method = excluded.capture_method,
      revision = collect_hybrid.sms_receipt_member_consents.revision + 1,
      reason = excluded.reason,
      recorded_by = excluded.recorded_by,
      recorded_at = clock_timestamp()
  returning * into consent;
  perform public.create_audit_log(
    case when consent.enabled
      then 'member.sms_receipt_consent.enabled'
      else 'member.sms_receipt_consent.disabled'
    end,
    'member_record', p_member_record_id,
    jsonb_build_object(
      'enabled', consent.enabled,
      'capture_method', consent.capture_method,
      'revision', consent.revision,
      'reason', clean_reason
    )
  );
  return jsonb_build_object(
    'ok', true,
    'member_record_id', consent.member_record_id,
    'enabled', consent.enabled,
    'capture_method', consent.capture_method,
    'revision', consent.revision,
    'recorded_at', consent.recorded_at
  );
end;
$$;

create function collect_hybrid.sms_receipt_job_is_current(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select true
    from collect_hybrid.sms_notification_outbox job
    join public.payments payment on payment.id = job.payment_id
    join collect_hybrid.member_records member on member.id = job.member_record_id
    join collect_hybrid.member_momo_identities identity
      on identity.member_id = member.id
    join collect_hybrid.sms_receipt_policies policy
      on policy.collection_id = job.collection_id
    join collect_hybrid.sms_receipt_member_consents consent
      on consent.member_record_id = job.member_record_id
    where job.id = p_job_id
      and coalesce((
        select flag.enabled from public.feature_flags flag
        where flag.key = 'hybrid_sms_notifications'
      ), false)
      and payment.status = 'posted'
      and payment.amount_rwf = job.amount_rwf
      and member.lifecycle = 'active'
      and member.linked_user_id is null
      and identity.revision = job.destination_revision
      and identity.momo_number = job.destination_e164
      and encode(extensions.digest(identity.momo_number, 'sha256'), 'hex') = job.destination_sha256
      and policy.enabled
      and policy.revision = job.policy_revision
      and policy.template_key = job.template_key
      and policy.template_version = job.template_version
      and consent.enabled
      and consent.revision = job.consent_revision
  ), false);
$$;

create function collect_hybrid.enqueue_sms_receipt_from_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment public.payments;
  member collect_hybrid.member_records;
  identity collect_hybrid.member_momo_identities;
  policy collect_hybrid.sms_receipt_policies;
  consent collect_hybrid.sms_receipt_member_consents;
  message text;
  reference_value text;
begin
  if new.event_type <> 'receipt' or new.member_record_id is null
     or new.member_balance_after_rwf is null then
    return new;
  end if;
  if not coalesce((
    select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_sms_notifications'
  ), false) then
    return new;
  end if;
  select item.* into policy
  from collect_hybrid.sms_receipt_policies item
  where item.collection_id = new.collection_id and item.enabled;
  if policy.collection_id is null then return new; end if;
  select item.* into payment from public.payments item where item.id = new.payment_id;
  select item.* into member
  from collect_hybrid.member_records item
  where item.id = new.member_record_id and item.lifecycle = 'active';
  if payment.id is null or payment.status <> 'posted' or member.id is null then
    return new;
  end if;
  -- App-linked members already use the existing contribution-confirmed push
  -- pipeline. SMS is reserved for account-independent members.
  if member.linked_user_id is not null then return new; end if;
  select item.* into identity
  from collect_hybrid.member_momo_identities item
  where item.member_id = member.id;
  if identity.member_id is null then return new; end if;
  select item.* into consent
  from collect_hybrid.sms_receipt_member_consents item
  where item.member_record_id = member.id and item.enabled;
  if consent.member_record_id is null then return new; end if;
  reference_value := btrim(coalesce(payment.transaction_id, ''));
  if reference_value !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$' then
    insert into collect_hybrid.sms_notification_outbox(
      payment_id, snapshot_id, collection_id, member_record_id,
      destination_e164, destination_sha256, destination_revision,
      policy_revision, consent_revision, template_key, template_version, amount_rwf,
      member_balance_rwf, group_balance_rwf, reference, state,
      suppression_reason
    ) values (
      payment.id, new.id, new.collection_id, member.id,
      identity.momo_number,
      encode(extensions.digest(identity.momo_number, 'sha256'), 'hex'),
      identity.revision, policy.revision, consent.revision, policy.template_key,
      policy.template_version, payment.amount_rwf,
      new.member_balance_after_rwf, new.group_balance_after_rwf,
      coalesce(nullif(reference_value, ''), 'invalid'), 'suppressed',
      'Provider reference is not safe for the canonical receipt template'
    ) on conflict (payment_id, template_key) do nothing;
    return new;
  end if;
  message := collect_hybrid.render_buri_munsi_receipt(
    payment.amount_rwf, new.member_balance_after_rwf,
    new.group_balance_after_rwf, reference_value
  );
  insert into collect_hybrid.sms_notification_outbox(
    payment_id, snapshot_id, collection_id, member_record_id,
    destination_e164, destination_sha256, destination_revision,
    policy_revision, consent_revision, template_key, template_version, amount_rwf,
    member_balance_rwf, group_balance_rwf, reference,
    message_body, body_sha256
  ) values (
    payment.id, new.id, new.collection_id, member.id,
    identity.momo_number,
    encode(extensions.digest(identity.momo_number, 'sha256'), 'hex'),
    identity.revision, policy.revision, consent.revision, policy.template_key,
    policy.template_version, payment.amount_rwf,
    new.member_balance_after_rwf, new.group_balance_after_rwf,
    reference_value, message,
    encode(extensions.digest(message, 'sha256'), 'hex')
  ) on conflict (payment_id, template_key) do nothing;
  return new;
end;
$$;
create trigger enqueue_sms_receipt_from_snapshot_trigger
after insert on collect_hybrid.momo_balance_snapshots
for each row execute function collect_hybrid.enqueue_sms_receipt_from_snapshot();

create function public.collect_notification_health(
  p_operator_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.read'
  ) then raise exception 'Notification operator read permission required'; end if;
  return jsonb_build_object(
    'enabled', coalesce((select flag.enabled from public.feature_flags flag
      where flag.key = 'hybrid_sms_notifications'), false),
    'queued', (select count(*) from collect_hybrid.sms_notification_outbox where state = 'queued'),
    'awaiting_confirmation', (select count(*) from collect_hybrid.sms_notification_outbox where state = 'awaiting_confirmation'),
    'send_started', (select count(*) from collect_hybrid.sms_notification_outbox where state = 'send_started'),
    'uncertain', (select count(*) from collect_hybrid.sms_notification_outbox where state = 'uncertain'),
    'suppressed', (select count(*) from collect_hybrid.sms_notification_outbox where state = 'suppressed'),
    'oldest_queued_at', (select min(created_at) from collect_hybrid.sms_notification_outbox where state = 'queued'),
    'active_workers', (select count(*) from collect_hybrid.sms_operator_heartbeats where observed_at > clock_timestamp() - interval '3 minutes'),
    'observed_at', clock_timestamp()
  );
end;
$$;

create function public.collect_list_pending_receipts(
  p_operator_user_id uuid,
  p_limit integer default 20,
  p_after_created_at timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.read'
  ) then raise exception 'Notification operator read permission required'; end if;
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception 'Pending receipt page size must be 1 to 50';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'job_id', candidate.id,
      'state', candidate.state,
      'destination_masked', left(candidate.destination_e164, 4) || '•••' || right(candidate.destination_e164, 3),
      'created_at', candidate.created_at,
      'amount_rwf', candidate.amount_rwf,
      'template_key', candidate.template_key,
      'template_version', candidate.template_version
    ) order by candidate.created_at, candidate.id)
    from (
      select item.*
      from collect_hybrid.sms_notification_outbox item
      where item.state = 'queued'
        and (p_after_created_at is null or item.created_at > p_after_created_at)
      order by item.created_at, item.id
      limit p_limit
    ) candidate
  ), '[]'::jsonb);
end;
$$;

create function public.collect_claim_receipt(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_worker text := btrim(coalesce(p_worker_id, ''));
  job collect_hybrid.sms_notification_outbox;
  prior collect_hybrid.sms_notification_claim_requests;
  token uuid;
  result jsonb;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  if p_job_id is null or p_request_id is null
     or clean_worker !~ '^[A-Za-z0-9._:-]{3,80}$' then
    raise exception 'Valid job, worker and request IDs are required';
  end if;
  select item.* into prior
  from collect_hybrid.sms_notification_claim_requests item
  where item.request_id = p_request_id;
  if prior.request_id is not null then
    if prior.operator_user_id <> p_operator_user_id
       or prior.outbox_id <> p_job_id or prior.worker_id <> clean_worker then
      raise exception 'Notification claim idempotency key conflict';
    end if;
    return prior.result || jsonb_build_object('replay', true);
  end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id
  for update;
  if job.id is null then raise exception 'Notification job not found'; end if;
  if job.state = 'awaiting_confirmation'
     and job.claim_expires_at <= clock_timestamp()
     and not exists (
       select 1 from collect_hybrid.sms_notification_attempts attempt
       where attempt.outbox_id = job.id
     ) then
    update collect_hybrid.sms_notification_outbox
    set state = 'queued', claim_token = null, claimed_by = null,
        claim_expires_at = null
    where id = job.id;
    job.state := 'queued';
  end if;
  if job.state = 'queued'
     and not collect_hybrid.sms_receipt_job_is_current(job.id) then
    update collect_hybrid.sms_notification_outbox
    set state = 'suppressed',
        suppression_reason = 'Consent, collection policy, destination or payment state changed before claim',
        claim_token = null,
        claimed_by = null,
        claim_expires_at = null
    where id = job.id
    returning * into job;
    result := jsonb_build_object(
      'ok', false,
      'job_id', job.id,
      'state', 'suppressed',
      'replay', false
    );
    insert into collect_hybrid.sms_notification_claim_requests(
      request_id, operator_user_id, outbox_id, worker_id, result
    ) values (p_request_id, p_operator_user_id, job.id, clean_worker, result);
    perform public.create_audit_log(
      'notification.sms.suppressed', 'sms_notification_outbox', job.id,
      jsonb_build_object(
        'reason', job.suppression_reason,
        'fence_version', job.fence_version
      ),
      p_operator_user_id
    );
    return result;
  end if;
  if job.state <> 'queued' then
    raise exception 'Notification job is not available to claim';
  end if;
  token := gen_random_uuid();
  update collect_hybrid.sms_notification_outbox
  set state = 'awaiting_confirmation', claim_token = token,
      claimed_by = clean_worker, claim_expires_at = clock_timestamp() + interval '5 minutes',
      fence_version = fence_version + 1
  where id = job.id
  returning * into job;
  result := jsonb_build_object(
    'ok', true, 'job_id', job.id, 'claim_token', token,
    'fence_version', job.fence_version,
    'claim_expires_at', job.claim_expires_at,
    'destination_masked', left(job.destination_e164, 4) || '•••' || right(job.destination_e164, 3),
    'replay', false
  );
  insert into collect_hybrid.sms_notification_claim_requests(
    request_id, operator_user_id, outbox_id, worker_id, result
  ) values (p_request_id, p_operator_user_id, job.id, clean_worker, result);
  return result;
end;
$$;

create function public.collect_get_claimed_receipt(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_claim_token uuid,
  p_fence_version integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare job collect_hybrid.sms_notification_outbox;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id;
  if job.id is null or job.state <> 'awaiting_confirmation'
     or job.claim_token is distinct from p_claim_token
     or job.fence_version <> p_fence_version
     or job.claim_expires_at <= clock_timestamp()
     or not collect_hybrid.sms_receipt_job_is_current(job.id) then
    raise exception 'Current notification claim required';
  end if;
  return jsonb_build_object(
    'job_id', job.id,
    'destination_e164', job.destination_e164,
    'destination_revision', job.destination_revision,
    'message_body', job.message_body,
    'body_sha256', job.body_sha256,
    'template_key', job.template_key,
    'template_version', job.template_version,
    'amount_rwf', job.amount_rwf,
    'member_balance_rwf', job.member_balance_rwf,
    'group_balance_rwf', job.group_balance_rwf,
    'reference', job.reference,
    'fence_version', job.fence_version,
    'claim_expires_at', job.claim_expires_at
  );
end;
$$;

create function public.collect_confirm_receipt(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_claim_token uuid,
  p_fence_version integer,
  p_destination_revision integer,
  p_body_sha256 text,
  p_confirmation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  job collect_hybrid.sms_notification_outbox;
  confirmation collect_hybrid.sms_notification_confirmations;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  if p_confirmation_id is null then raise exception 'Confirmation ID required'; end if;
  select item.* into confirmation
  from collect_hybrid.sms_notification_confirmations item
  where item.id = p_confirmation_id;
  if confirmation.id is not null then
    if confirmation.outbox_id <> p_job_id
       or confirmation.operator_user_id <> p_operator_user_id
       or confirmation.claim_token <> p_claim_token
       or confirmation.fence_version <> p_fence_version
       or confirmation.destination_revision <> p_destination_revision
       or confirmation.body_sha256 is distinct from lower(btrim(coalesce(p_body_sha256, ''))) then
      raise exception 'Notification confirmation idempotency key conflict';
    end if;
    return jsonb_build_object(
      'ok', true, 'confirmation_id', confirmation.id,
      'expires_at', confirmation.expires_at, 'replay', true
    );
  end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id
  for update;
  if job.id is null or job.state <> 'awaiting_confirmation'
     or job.claim_token is distinct from p_claim_token
     or job.fence_version <> p_fence_version
     or job.claim_expires_at <= clock_timestamp()
     or job.destination_revision <> p_destination_revision
     or job.body_sha256 is distinct from lower(btrim(coalesce(p_body_sha256, '')))
     or not collect_hybrid.sms_receipt_job_is_current(job.id) then
    raise exception 'Exact current notification confirmation required';
  end if;
  insert into collect_hybrid.sms_notification_confirmations(
    id, outbox_id, operator_user_id, claim_token, fence_version,
    destination_revision, body_sha256, expires_at
  ) values (
    p_confirmation_id, job.id, p_operator_user_id, p_claim_token,
    p_fence_version, p_destination_revision, job.body_sha256,
    least(job.claim_expires_at, clock_timestamp() + interval '2 minutes')
  ) returning * into confirmation;
  return jsonb_build_object(
    'ok', true, 'confirmation_id', confirmation.id,
    'expires_at', confirmation.expires_at, 'replay', false
  );
end;
$$;

create function public.collect_record_send_start(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_claim_token uuid,
  p_fence_version integer,
  p_confirmation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  job collect_hybrid.sms_notification_outbox;
  confirmation collect_hybrid.sms_notification_confirmations;
  attempt collect_hybrid.sms_notification_attempts;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  select item.* into attempt
  from collect_hybrid.sms_notification_attempts item
  where item.confirmation_id = p_confirmation_id;
  if attempt.id is not null then
    if attempt.outbox_id <> p_job_id
       or attempt.operator_user_id <> p_operator_user_id
       or attempt.claim_token <> p_claim_token
       or attempt.fence_version <> p_fence_version
       or attempt.confirmation_id <> p_confirmation_id then
      raise exception 'Send-start confirmation conflict';
    end if;
    return jsonb_build_object(
      'ok', true, 'attempt_id', attempt.id,
      'state', attempt.state, 'replay', true
    );
  end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id
  for update;
  select item.* into confirmation
  from collect_hybrid.sms_notification_confirmations item
  where item.id = p_confirmation_id
  for update;
  -- Freeze the current authorization rows across the durable pre-send
  -- transition. Revocation or payment reversal must complete before or after
  -- this boundary, never race invisibly through it.
  perform 1 from public.payments item
  where item.id = job.payment_id
  for share;
  perform 1 from collect_hybrid.member_records item
  where item.id = job.member_record_id
  for share;
  perform 1 from collect_hybrid.member_momo_identities item
  where item.member_id = job.member_record_id
  for share;
  perform 1 from collect_hybrid.sms_receipt_policies item
  where item.collection_id = job.collection_id
  for share;
  perform 1 from collect_hybrid.sms_receipt_member_consents item
  where item.member_record_id = job.member_record_id
  for share;
  if job.id is null or confirmation.id is null
     or job.state <> 'awaiting_confirmation'
     or job.claim_token is distinct from p_claim_token
     or job.fence_version <> p_fence_version
     or job.claim_expires_at <= clock_timestamp()
     or confirmation.outbox_id <> job.id
     or confirmation.operator_user_id <> p_operator_user_id
     or confirmation.claim_token <> p_claim_token
     or confirmation.fence_version <> p_fence_version
     or confirmation.destination_revision <> job.destination_revision
     or confirmation.body_sha256 <> job.body_sha256
     or confirmation.expires_at <= clock_timestamp()
     or confirmation.consumed_at is not null
     or not collect_hybrid.sms_receipt_job_is_current(job.id) then
    raise exception 'Fresh exact receipt confirmation required before send start';
  end if;
  insert into collect_hybrid.sms_notification_attempts(
    outbox_id, confirmation_id, operator_user_id, worker_id,
    claim_token, fence_version, attempt_number, destination_sha256,
    destination_revision, body_sha256
  ) values (
    job.id, confirmation.id, p_operator_user_id, job.claimed_by,
    p_claim_token, p_fence_version, job.attempt_count + 1,
    job.destination_sha256, job.destination_revision, job.body_sha256
  ) returning * into attempt;
  update collect_hybrid.sms_notification_confirmations
  set consumed_at = clock_timestamp()
  where id = confirmation.id;
  update collect_hybrid.sms_notification_outbox
  set state = 'send_started', attempt_count = attempt.attempt_number
  where id = job.id;
  return jsonb_build_object(
    'ok', true, 'attempt_id', attempt.id,
    'job_id', job.id, 'state', 'send_started', 'replay', false
  );
end;
$$;

create function public.collect_record_observed_outcome(
  p_operator_user_id uuid,
  p_attempt_id uuid,
  p_outcome text,
  p_evidence_reference text,
  p_outcome_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_outcome text := lower(btrim(coalesce(p_outcome, '')));
  clean_evidence text := btrim(coalesce(p_evidence_reference, ''));
  clean_note text := nullif(btrim(coalesce(p_outcome_note, '')), '');
  attempt collect_hybrid.sms_notification_attempts;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  if clean_outcome not in ('observed_sent', 'failed_no_send', 'uncertain')
     or char_length(clean_evidence) not between 8 and 500
     or (clean_note is not null and char_length(clean_note) > 500) then
    raise exception 'Valid outcome and bounded evidence reference required';
  end if;
  select item.* into attempt
  from collect_hybrid.sms_notification_attempts item
  where item.id = p_attempt_id
  for update;
  if attempt.id is null then raise exception 'SMS attempt not found'; end if;
  if attempt.operator_user_id <> p_operator_user_id then
    raise exception 'SMS attempt belongs to another operator';
  end if;
  if attempt.state <> 'send_started' then
    if attempt.state <> clean_outcome then
      raise exception 'SMS attempt outcome is already final';
    end if;
    if attempt.evidence_reference is distinct from clean_evidence
       or attempt.outcome_note is distinct from clean_note then
      raise exception 'SMS attempt outcome idempotency conflict';
    end if;
    return jsonb_build_object(
      'ok', true, 'attempt_id', attempt.id,
      'state', attempt.state, 'replay', true
    );
  end if;
  update collect_hybrid.sms_notification_attempts
  set state = clean_outcome, outcome_at = clock_timestamp(),
      evidence_reference = clean_evidence, outcome_note = clean_note
  where id = attempt.id;
  update collect_hybrid.sms_notification_outbox
  set state = clean_outcome,
      observed_sent_at = case when clean_outcome = 'observed_sent'
        then clock_timestamp() else null end,
      claim_expires_at = null
  where id = attempt.outbox_id and state = 'send_started';
  return jsonb_build_object(
    'ok', true, 'attempt_id', attempt.id,
    'state', clean_outcome, 'replay', false
  );
end;
$$;

create function public.collect_release_unsent_claim(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_claim_token uuid,
  p_fence_version integer,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_reason text := btrim(coalesce(p_reason, ''));
  job collect_hybrid.sms_notification_outbox;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  if char_length(clean_reason) not between 8 and 500 then
    raise exception 'A bounded release reason is required';
  end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id
  for update;
  if job.id is null or job.state <> 'awaiting_confirmation'
     or job.claim_token is distinct from p_claim_token
     or job.fence_version <> p_fence_version
     or exists (
       select 1 from collect_hybrid.sms_notification_attempts attempt
       where attempt.outbox_id = job.id
     ) then
    raise exception 'Only a current safely unsent claim can be released';
  end if;
  update collect_hybrid.sms_notification_confirmations
  set expires_at = least(expires_at, clock_timestamp())
  where outbox_id = job.id and claim_token = p_claim_token and consumed_at is null;
  update collect_hybrid.sms_notification_outbox
  set state = 'queued', claim_token = null, claimed_by = null,
      claim_expires_at = null
  where id = job.id;
  perform public.create_audit_log(
    'notification.sms.claim_released', 'sms_notification_outbox', job.id,
    jsonb_build_object('reason', clean_reason, 'fence_version', p_fence_version),
    p_operator_user_id
  );
  return jsonb_build_object('ok', true, 'job_id', job.id, 'state', 'queued');
end;
$$;

create function public.collect_worker_heartbeat(
  p_operator_user_id uuid,
  p_worker_id text,
  p_run_id uuid,
  p_mode text,
  p_safe_status jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_worker text := btrim(coalesce(p_worker_id, ''));
  clean_mode text := lower(btrim(coalesce(p_mode, '')));
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.read'
  ) then raise exception 'Notification operator read permission required'; end if;
  if clean_worker !~ '^[A-Za-z0-9._:-]{3,80}$'
     or p_run_id is null or clean_mode not in ('no_send', 'assisted_send')
     or jsonb_typeof(coalesce(p_safe_status, '{}'::jsonb)) <> 'object' then
    raise exception 'Valid worker heartbeat required';
  end if;
  insert into collect_hybrid.sms_operator_heartbeats(
    worker_id, operator_user_id, run_id, mode, safe_status
  ) values (
    clean_worker, p_operator_user_id, p_run_id, clean_mode,
    coalesce(p_safe_status, '{}'::jsonb)
  )
  on conflict (worker_id) do update
  set operator_user_id = excluded.operator_user_id,
      run_id = excluded.run_id,
      mode = excluded.mode,
      safe_status = excluded.safe_status,
      observed_at = clock_timestamp();
  return jsonb_build_object(
    'ok', true, 'worker_id', clean_worker,
    'mode', clean_mode, 'observed_at', clock_timestamp()
  );
end;
$$;

revoke all on function collect_hybrid.render_buri_munsi_receipt(bigint, bigint, bigint, text)
  from public, anon, authenticated, service_role;
revoke all on function collect_hybrid.protect_sms_outbox_core()
  from public, anon, authenticated, service_role;
revoke all on function collect_hybrid.protect_sms_attempt_history()
  from public, anon, authenticated, service_role;
revoke all on function collect_hybrid.operator_authorized(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function collect_hybrid.sms_receipt_job_is_current(uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.admin_set_sms_receipt_policy(uuid, boolean, text)
  from public, anon;
grant execute on function public.admin_set_sms_receipt_policy(uuid, boolean, text)
  to authenticated;
revoke all on function public.admin_set_member_sms_receipt_consent(uuid, boolean, text, text)
  from public, anon;
grant execute on function public.admin_set_member_sms_receipt_consent(uuid, boolean, text, text)
  to authenticated;

revoke all on function public.collect_notification_health(uuid)
  from public, anon, authenticated;
revoke all on function public.collect_list_pending_receipts(uuid, integer, timestamptz)
  from public, anon, authenticated;
revoke all on function public.collect_claim_receipt(uuid, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.collect_get_claimed_receipt(uuid, uuid, uuid, integer)
  from public, anon, authenticated;
revoke all on function public.collect_confirm_receipt(uuid, uuid, uuid, integer, integer, text, uuid)
  from public, anon, authenticated;
revoke all on function public.collect_record_send_start(uuid, uuid, uuid, integer, uuid)
  from public, anon, authenticated;
revoke all on function public.collect_record_observed_outcome(uuid, uuid, text, text, text)
  from public, anon, authenticated;
revoke all on function public.collect_release_unsent_claim(uuid, uuid, uuid, integer, text)
  from public, anon, authenticated;
revoke all on function public.collect_worker_heartbeat(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.collect_notification_health(uuid),
  public.collect_list_pending_receipts(uuid, integer, timestamptz),
  public.collect_claim_receipt(uuid, uuid, text, uuid),
  public.collect_get_claimed_receipt(uuid, uuid, uuid, integer),
  public.collect_confirm_receipt(uuid, uuid, uuid, integer, integer, text, uuid),
  public.collect_record_send_start(uuid, uuid, uuid, integer, uuid),
  public.collect_record_observed_outcome(uuid, uuid, text, text, text),
  public.collect_release_unsent_claim(uuid, uuid, uuid, integer, text),
  public.collect_worker_heartbeat(uuid, text, uuid, text, jsonb)
to service_role;

comment on table collect_hybrid.sms_notification_outbox is
  'Private durable SMS receipt queue with immutable destination, English-only body and financial snapshot; requires explicit member consent and is never proof of handset delivery.';
comment on function public.collect_record_send_start(uuid, uuid, uuid, integer, uuid) is
  'Consumes a fresh exact-recipient/exact-body confirmation and records the pre-send boundary; it does not send SMS.';

commit;
