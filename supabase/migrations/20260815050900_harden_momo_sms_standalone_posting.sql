begin;

-- Applied to production through the Supabase migration API as version
-- 20260815050900; keep this filename aligned with remote migration history.

-- Raw SMS evidence is immutable, tenant-scoped, and idempotent to the native
-- envelope. Exact body reuse by another receiver must never transfer ownership.
alter table public.raw_payment_sms
  add column if not exists client_envelope_id uuid;

alter table public.raw_payment_sms
  drop constraint if exists raw_payment_sms_body_hash_key;

create unique index if not exists raw_payment_sms_receiver_body_unique
  on public.raw_payment_sms (receiver_user_id, body_hash);
create unique index if not exists raw_payment_sms_receiver_envelope_unique
  on public.raw_payment_sms (receiver_user_id, client_envelope_id)
  where client_envelope_id is not null;

create or replace function public.protect_raw_payment_sms_identity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.collection_id is distinct from old.collection_id
     or new.receiver_user_id is distinct from old.receiver_user_id
     or new.raw_sender is distinct from old.raw_sender
     or new.raw_body is distinct from old.raw_body
     or new.body_hash is distinct from old.body_hash
     or new.client_envelope_id is distinct from old.client_envelope_id
     or new.receiver_momo_number_hash is distinct from old.receiver_momo_number_hash
     or new.received_at_device is distinct from old.received_at_device
     or new.ingested_at is distinct from old.ingested_at
     or new.created_at is distinct from old.created_at then
    raise exception 'Raw SMS evidence identity is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_raw_payment_sms_identity_trigger
  on public.raw_payment_sms;
create trigger protect_raw_payment_sms_identity_trigger
before update on public.raw_payment_sms
for each row execute function public.protect_raw_payment_sms_identity();
revoke execute on function public.protect_raw_payment_sms_identity()
  from public, anon, authenticated;

-- Current consent and ownership of at least one active receiving route are
-- server-side authorization gates. A supplied route must match exactly. When
-- the provider SMS omits its receiving number, allocation may derive the route
-- only from one unique payer-verified intent for this same receiving account.
create or replace function public.user_can_ingest_receiver_sms(
  receiver_hash text default null,
  collection uuid default null,
  user_uuid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select user_uuid is not null
    and coalesce((
      select consent.enabled
      from receiver_mode_consents consent
      where consent.user_id = user_uuid
      order by consent.created_at desc, consent.id desc
      limit 1
    ), false)
    and exists (
      select 1
      from collection_receivers receiver
      where receiver.is_active
        and (
          nullif(trim(receiver_hash), '') is null
          or receiver.momo_number_hash = receiver_hash
        )
        and (collection is null or receiver.collection_id = collection)
        and receiver.receiver_user_id = user_uuid
    );
$$;
revoke execute on function public.user_can_ingest_receiver_sms(text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.user_can_ingest_receiver_sms(text, uuid, uuid)
  to service_role;

create or replace function public.check_sms_ingest_rate_limit(user_uuid uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  hourly_count integer;
  daily_count integer;
begin
  if user_uuid is null then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('sms-ingest:' || user_uuid::text, 0));
  select
    count(*) filter (where ingested_at >= now() - interval '1 hour'),
    count(*) filter (where ingested_at >= now() - interval '24 hours')
  into hourly_count, daily_count
  from raw_payment_sms
  where receiver_user_id = user_uuid
    and ingested_at >= now() - interval '24 hours';
  return hourly_count < 60 and daily_count < 250;
end;
$$;
revoke execute on function public.check_sms_ingest_rate_limit(uuid)
  from public, anon, authenticated;
grant execute on function public.check_sms_ingest_rate_limit(uuid)
  to service_role;

grant select, insert, update on table public.raw_payment_sms to service_role;
grant select, insert, update on table public.parsed_payment_events to service_role;

-- Canonical payment identifiers are scoped to provider and receiver. A single
-- active payment intent may back only one non-reversed payment.
alter table public.payments
  add column if not exists provider_network text not null default 'unknown';
alter table public.payments
  drop constraint if exists payments_provider_network_check;
alter table public.payments
  add constraint payments_provider_network_check
  check (provider_network in ('mtn_momo', 'airtel_money', 'unknown'));

update public.payments payment
set provider_network = event.network
from public.parsed_payment_events event
where event.id = payment.parsed_event_id
  and payment.provider_network = 'unknown';

alter table public.payments
  drop constraint if exists payments_transaction_id_key;
create unique index if not exists payments_receiver_network_transaction_unique
  on public.payments (
    receiver_momo_number_hash,
    provider_network,
    upper(btrim(transaction_id))
  )
  where transaction_id is not null and status <> 'reversed';
create unique index if not exists payments_one_active_per_intent_unique
  on public.payments (payment_intent_id)
  where payment_intent_id is not null and status <> 'reversed';
create unique index if not exists ledger_entries_payment_type_unique
  on public.ledger_entries (payment_id, entry_type);

alter table public.payment_allocations
  drop constraint if exists payment_allocations_allocation_method_check;
alter table public.payment_allocations
  add constraint payment_allocations_allocation_method_check
  check (allocation_method = 'auto_native_sms');

insert into public.ledger_entries (
  payment_id,
  collection_id,
  user_id,
  entry_type,
  amount_rwf,
  visibility,
  metadata
)
select
  payment.id,
  payment.collection_id,
  payment.contributor_user_id,
  'member_credit',
  payment.amount_rwf,
  'private',
  jsonb_build_object('backfill', true, 'source', 'posted_payment')
from public.payments payment
where payment.status = 'posted'
  and payment.contributor_user_id is not null
on conflict (payment_id, entry_type) do nothing;

update public.payment_intents
set status = 'expired'
where status = 'pending' and expires_at <= now();

with duplicate_pending as (
  select id,
    row_number() over (
      partition by contributor_user_id, collection_id, expected_amount_rwf,
        receiver_momo_number_hash, coalesce(sender_phone_hash, '')
      order by created_at desc, id
    ) as duplicate_rank
  from public.payment_intents
  where status = 'pending'
)
update public.payment_intents intent
set status = 'cancelled'
from duplicate_pending duplicate
where duplicate.id = intent.id and duplicate.duplicate_rank > 1;

create unique index if not exists payment_intents_one_active_member_request
  on public.payment_intents (
    contributor_user_id,
    collection_id,
    expected_amount_rwf,
    receiver_momo_number_hash,
    coalesce(sender_phone_hash, '')
  )
  where status = 'pending';

create or replace function public.create_contribution_intent(
  collection uuid,
  p_expected_amount_rwf bigint default null,
  p_sender_phone_hash text default null
)
returns table (
  id uuid,
  collection_id uuid,
  expected_amount_rwf bigint,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  network text,
  sender_phone_hash text,
  status payment_intent_status,
  contributor_public_id char(6),
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  receiver_row collection_receivers;
  intent_row payment_intents;
  member_public_id char(6);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.user_can_read_collection(collection, auth.uid()) then
    raise exception 'Group is not available';
  end if;
  if p_expected_amount_rwf is null or p_expected_amount_rwf <= 0 then
    raise exception 'Contribution amount must be above zero';
  end if;
  if nullif(trim(p_sender_phone_hash), '') is null then
    raise exception 'Contributor MoMo identity is required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('contribution-intent:' || auth.uid()::text || ':' || collection::text, 0)
  );
  update payment_intents
  set status = 'expired'
  where contributor_user_id = auth.uid()
    and collection_id = collection
    and status = 'pending'
    and expires_at <= now();

  select profile.public_id into member_public_id
  from profiles profile where profile.id = auth.uid();
  if member_public_id is null then
    raise exception 'Collect ID is required before contributing';
  end if;

  select * into receiver_row
  from collection_receivers receiver
  where receiver.collection_id = collection and receiver.is_active
  order by receiver.created_at
  limit 1
  for update;
  if receiver_row.id is null then raise exception 'Group has no active receiver'; end if;

  select * into intent_row
  from payment_intents intent
  where intent.collection_id = collection
    and intent.contributor_user_id = auth.uid()
    and intent.expected_amount_rwf = p_expected_amount_rwf
    and intent.receiver_momo_number_hash = receiver_row.momo_number_hash
    and intent.sender_phone_hash = trim(p_sender_phone_hash)
    and intent.status = 'pending'
    and intent.expires_at > now()
  order by intent.created_at desc
  limit 1
  for update;

  if intent_row.id is null then
    insert into payment_intents (
      collection_id, contributor_user_id, contributor_public_id,
      expected_amount_rwf, receiver_momo_number_hash, sender_phone_hash
    ) values (
      collection, auth.uid(), member_public_id, p_expected_amount_rwf,
      receiver_row.momo_number_hash, trim(p_sender_phone_hash)
    ) returning * into intent_row;
  end if;

  return query select
    intent_row.id, intent_row.collection_id, intent_row.expected_amount_rwf,
    receiver_row.momo_number, intent_row.receiver_momo_number_hash,
    receiver_row.label, receiver_row.network, intent_row.sender_phone_hash,
    intent_row.status, intent_row.contributor_public_id,
    intent_row.created_at, intent_row.expires_at;
end;
$$;
revoke execute on function public.create_contribution_intent(uuid, bigint, text)
  from public, anon;
grant execute on function public.create_contribution_intent(uuid, bigint, text)
  to authenticated;

create or replace function public.list_current_user_payment_intents()
returns table (
  id uuid,
  collection_id uuid,
  expected_amount_rwf bigint,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  network text,
  sender_phone_hash text,
  status payment_intent_status,
  contributor_public_id char(6),
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update payment_intents
  set status = 'expired'
  where contributor_user_id = auth.uid()
    and status = 'pending'
    and expires_at <= now();
  return query
  select intent.id, intent.collection_id, intent.expected_amount_rwf,
    receiver.momo_number, intent.receiver_momo_number_hash,
    receiver.label, receiver.network, intent.sender_phone_hash,
    intent.status, intent.contributor_public_id,
    intent.created_at, intent.expires_at
  from payment_intents intent
  join lateral (
    select route.momo_number, route.label, route.network
    from collection_receivers route
    where route.collection_id = intent.collection_id
      and route.momo_number_hash = intent.receiver_momo_number_hash
    order by route.created_at desc
    limit 1
  ) receiver on true
  where intent.contributor_user_id = auth.uid()
  order by intent.created_at desc
  limit 100;
end;
$$;
revoke execute on function public.list_current_user_payment_intents()
  from public, anon;
grant execute on function public.list_current_user_payment_intents()
  to authenticated;

-- A complete, high-confidence native MoMo receipt may post automatically.
-- Incomplete, conflicting, or ambiguous SMS evidence stays in the review queue.
create or replace function public.allocate_parsed_payment_event(event_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row parsed_payment_events;
  evidence_time timestamptz;
  match_intent_id uuid;
  match_collection_id uuid;
  match_receiver_hash text;
  possible_count integer;
  result_status text;
begin
  select * into event_row
  from parsed_payment_events event
  where event.id = event_id
  for update;
  if not found then raise exception 'Parsed event not found'; end if;
  select coalesce(raw.received_at_device, raw.ingested_at)
  into evidence_time
  from raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;
  if event_row.allocation_status = 'allocated' then return 'already_allocated'; end if;

  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.confidence < 0.90 then
    update parsed_payment_events
    set allocation_status = 'needs_review',
        review_reason = 'SMS evidence is incomplete or not reliable enough for candidate matching'
    where id = event_id;
    return 'needs_review';
  end if;

  update payment_intents set status = 'expired'
  where status = 'pending' and expires_at <= now();

  with candidates as (
    select distinct
      intent.id,
      intent.collection_id,
      intent.receiver_momo_number_hash,
      intent.created_at
    from payment_intents intent
    join collection_receivers route
      on route.collection_id = intent.collection_id
     and route.momo_number_hash = intent.receiver_momo_number_hash
     and route.is_active
     and route.receiver_user_id = event_row.receiver_user_id
    where intent.status = 'pending'
      and (
        event_row.collection_id is null
        or intent.collection_id = event_row.collection_id
      )
      and (
        event_row.receiver_phone_hash is null
        or intent.receiver_momo_number_hash = event_row.receiver_phone_hash
      )
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
    (array_agg(candidate.receiver_momo_number_hash order by candidate.created_at))[1]
  into possible_count, match_intent_id, match_collection_id, match_receiver_hash
  from candidates candidate;

  if possible_count = 1 then
    if event_row.receiver_phone_hash is null then
      update parsed_payment_events
      set receiver_phone_hash = match_receiver_hash,
          collection_id = coalesce(collection_id, match_collection_id)
      where id = event_id;
    end if;
    perform post_payment_from_event(
      event_id,
      match_intent_id,
      match_collection_id,
      case
        when event_row.receiver_phone_hash is null then
          'Matched by native SMS transaction ID plus one unique owned receiver, amount, payer, and time window'
        else
          'Matched by native SMS transaction ID, receiver, amount, payer, and time window'
      end
    );
    select allocation_status::text into result_status
    from parsed_payment_events where id = event_id;
    if result_status = 'allocated' then
      return 'allocated';
    end if;
    return 'ignored';
  elsif possible_count > 1 then
    update parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'Multiple payer-verified payment intents matched this SMS evidence'
    where id = event_id;
    return 'ambiguous';
  end if;

  update parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = 'No payer-verified pending payment intent matched this SMS evidence'
  where id = event_id;
  return 'needs_review';
end;
$$;
revoke execute on function public.allocate_parsed_payment_event(uuid)
  from public, anon, authenticated;
grant execute on function public.allocate_parsed_payment_event(uuid)
  to service_role;

drop function if exists public.post_payment_from_event(uuid, uuid, uuid, text, text, uuid);
create or replace function public.post_payment_from_event(
  event_id uuid,
  intent_id uuid,
  target_collection_id uuid,
  allocation_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row parsed_payment_events;
  intent_row payment_intents;
  raw_row raw_payment_sms;
  receiver_id uuid;
  payment_id uuid;
begin
  select * into event_row from parsed_payment_events where id = event_id for update;
  if not found then raise exception 'Parsed event not found'; end if;
  if event_row.allocation_status = 'allocated' then
    select payment.id into payment_id from payments payment
    where payment.parsed_event_id = event_id;
    return payment_id;
  end if;
  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.receiver_phone_hash is null
     or event_row.confidence < 0.90 then
    raise exception 'SMS payment evidence is incomplete or below the posting threshold';
  end if;

  select * into intent_row from payment_intents where id = intent_id for update;
  if not found then raise exception 'Payment intent not found'; end if;
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

  select * into raw_row from raw_payment_sms where id = event_row.raw_sms_id;
  if coalesce(raw_row.received_at_device, raw_row.ingested_at)
     not between intent_row.created_at - interval '15 minutes'
       and intent_row.expires_at + interval '2 hours' then
    raise exception 'SMS evidence timestamp is outside the payment intent window';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      event_row.receiver_phone_hash || ':' || event_row.network || ':' ||
      upper(btrim(event_row.transaction_id)),
      0
    )
  );

  if exists (
    select 1 from payments payment
    where payment.receiver_momo_number_hash = event_row.receiver_phone_hash
      and payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
      and payment.status <> 'reversed'
  ) then
    select payment.id into payment_id
    from payments payment
    where payment.receiver_momo_number_hash = event_row.receiver_phone_hash
      and payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
      and payment.status <> 'reversed'
    order by payment.created_at
    limit 1;
    update parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Duplicate SMS transaction evidence'
    where id = event_id;
    return payment_id;
  end if;

  select receiver.receiver_user_id into receiver_id
  from collection_receivers receiver
  where receiver.collection_id = target_collection_id
    and receiver.momo_number_hash = event_row.receiver_phone_hash
  order by receiver.created_at desc
  limit 1;
  if receiver_id is null or receiver_id <> event_row.receiver_user_id then
    raise exception 'SMS receiver is not configured for the target group';
  end if;

  insert into payments (
    parsed_event_id, payment_intent_id, collection_id,
    contributor_user_id, contributor_public_id, receiver_user_id,
    receiver_momo_number_hash, amount_rwf, transaction_id,
    provider_network, source, anonymity_choice
  ) values (
    event_id, intent_id, target_collection_id,
    intent_row.contributor_user_id, intent_row.contributor_public_id, receiver_id,
    event_row.receiver_phone_hash, event_row.amount_rwf, event_row.transaction_id,
    event_row.network,
    'sms_auto',
    intent_row.anonymity_choice
  ) returning id into payment_id;

  insert into payment_allocations (
    payment_id, parsed_event_id, collection_id, payment_intent_id,
    allocated_by, allocation_method, confidence, reason
  ) values (
    payment_id, event_id, target_collection_id, intent_id,
    null, 'auto_native_sms', event_row.confidence, allocation_reason
  );

  insert into ledger_entries (
    payment_id, collection_id, user_id, entry_type,
    amount_rwf, visibility, metadata
  ) values
    (
      payment_id, target_collection_id, intent_row.contributor_user_id,
      'collection_credit', event_row.amount_rwf, 'public_safe',
      jsonb_build_object('allocation_method', 'auto_native_sms', 'parsed_event_id', event_id)
    ),
    (
      payment_id, target_collection_id, intent_row.contributor_user_id,
      'member_credit', event_row.amount_rwf, 'private',
      jsonb_build_object('allocation_method', 'auto_native_sms', 'parsed_event_id', event_id)
    );

  update parsed_payment_events
  set allocation_status = 'allocated', review_reason = allocation_reason
  where id = event_id;
  update payment_intents set status = 'matched' where id = intent_id;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    null,
    'payment.allocated.auto',
    'payment', payment_id,
    jsonb_build_object(
      'parsed_event_id', event_id,
      'payment_intent_id', intent_id,
      'method', 'auto_native_sms',
      'reason', allocation_reason
    )
  );
  return payment_id;
end;
$$;
revoke execute on function public.post_payment_from_event(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create or replace function public.update_collection_receiver(
  collection uuid,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text default 'Primary MOMO receiver'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can update the receiver';
  end if;
  if nullif(trim(receiver_momo_number), '') is null
     or nullif(trim(receiver_momo_number_hash), '') is null then
    raise exception 'Receiver MoMo number and hash are required';
  end if;
  update payment_intents set status = 'expired'
  where collection_id = collection and status = 'pending' and expires_at <= now();
  if exists (
    select 1 from payment_intents
    where collection_id = collection and status = 'pending'
  ) then
    raise exception 'Receiver cannot change while contribution requests are pending';
  end if;
  update collection_receivers set is_active = false
  where collection_id = collection and is_active;
  insert into collection_receivers (
    collection_id, receiver_user_id, momo_number, momo_number_hash, label, is_active
  ) values (
    collection, auth.uid(), trim(receiver_momo_number),
    trim(receiver_momo_number_hash),
    coalesce(nullif(trim(receiver_label), ''), 'Primary MOMO receiver'), true
  );
  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'collection.receiver_updated', 'collection', collection,
    jsonb_build_object('receiver_label', coalesce(nullif(trim(receiver_label), ''), 'Primary MOMO receiver'))
  );
end;
$$;

drop view if exists public.member_contributions_view;
create view public.member_contributions_view
with (security_invoker = true)
as
select
  payment.collection_id,
  payment.id as payment_id,
  payment.amount_rwf,
  payment.currency,
  payment.status,
  payment.source,
  case
    when payment.contributor_user_id = auth.uid()
      or public.user_is_collection_admin(payment.collection_id, auth.uid())
      then payment.transaction_id
    else null
  end as transaction_id,
  payment.posted_at,
  payment.created_at,
  payment.contributor_user_id = auth.uid() as is_current_user_contribution,
  case
    when payment.contributor_user_id = auth.uid() then 'You'
    when payment.contributor_public_id is not null
      then 'Collect ID ' || payment.contributor_public_id
    else 'Collect member'
  end as supporter_label
from public.payments payment
where payment.status = 'posted'
  and public.user_can_read_collection(payment.collection_id, auth.uid());
revoke all on public.member_contributions_view from public, anon;
grant select on public.member_contributions_view to authenticated;

update public.policy_document_sections section
set body =
  'We share only what is needed with service providers that operate authentication, hosting, storage, messaging, support, analytics, or payment verification. Opted-in MoMo SMS content is sent from Collect servers to the OpenAI API for structured payment parsing. We do not sell personal data.',
  updated_at = now()
from public.policy_documents document
where document.id = section.policy_document_id
  and document.kind = 'privacy'
  and document.status = 'published'
  and section.section_key = 'sharing';

commit;
