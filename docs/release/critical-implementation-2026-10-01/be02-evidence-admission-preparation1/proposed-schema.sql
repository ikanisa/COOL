-- PROPOSED, UNEXECUTED, ROUTE UNDECIDED. Private preparation only.
-- Additive draft; not a complete installable migration and no live source change.
-- No policy, approval, evidence, source-byte or admission rows are inserted.
-- No API role receives write or admission authority. Trusted adapter and current
-- proposal/approval/finalizer/reversal overrides must be implemented together.
begin;

create schema collect_financial_evidence;
revoke all on schema collect_financial_evidence
  from public, anon, authenticated, service_role;

create table collect_financial_evidence.policies (
  id uuid primary key,
  route_kind text not null check (route_kind in (
    'authenticated_provider_api', 'authenticated_statement',
    'constrained_internal_reconciliation')),
  evidence_level text not null check (evidence_level in (
    'source_authenticated', 'provider_settlement_authenticated',
    'constrained_internal_reconciliation')),
  provider_settlement_verified boolean not null,
  permitted_source_finality_states text[] not null check (
    cardinality(permitted_source_finality_states)>0 and
    permitted_source_finality_states <@ array['settled','not_settled','unknown','internal_record','reversed']::text[]),
  approved_checker_version text not null check (length(approved_checker_version) between 1 and 128),
  approved_checker_artifact_sha256 text not null check (approved_checker_artifact_sha256 ~ '^[a-f0-9]{64}$'),
  approved_time_match_reference text not null check (length(approved_time_match_reference) between 3 and 500),
  rules jsonb not null check (jsonb_typeof(rules) = 'object'),
  rules_sha256 text generated always as
    (encode(extensions.digest(rules::text, 'sha256'), 'hex')) stored,
  custody_profile_reference text not null check (length(custody_profile_reference) between 3 and 500),
  custody_authorization_sha256 text not null check (custody_authorization_sha256 ~ '^[a-f0-9]{64}$'),
  finance_decision_reference text not null check (length(finance_decision_reference) between 3 and 500),
  security_decision_reference text not null check (length(security_decision_reference) between 3 and 500),
  decision_source_sha256 text not null check (decision_source_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default clock_timestamp(),
  check ((evidence_level = 'provider_settlement_authenticated') = provider_settlement_verified),
  check (route_kind <> 'constrained_internal_reconciliation' or
    (evidence_level = 'constrained_internal_reconciliation' and not provider_settlement_verified))
);

-- These append-only events record actual authorization; they do not create it.
-- Future authorized writer serializes on policy:<id> and verifies its authority.
create table collect_financial_evidence.policy_events (
  sequence bigint generated always as identity primary key,
  policy_id uuid not null references collect_financial_evidence.policies(id) on delete restrict,
  decision text not null check (decision in ('approved', 'revoked', 'superseded')),
  actor_authority_reference text not null check (length(actor_authority_reference) between 3 and 500),
  actual_decision_reference text not null check (length(actual_decision_reference) between 3 and 500),
  actual_decision_sha256 text not null check (actual_decision_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default clock_timestamp()
);
create index financial_evidence_policy_events_latest
  on collect_financial_evidence.policy_events(policy_id, sequence desc);

-- A locator/hash is insufficient. Selected adapter must retain private versioned
-- bytes, verify readback, establish provenance and approved custody before insert.
-- Storage provider/location/retention periods are deliberately not selected here.
create table collect_financial_evidence.source_objects (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  policy_id uuid not null references collect_financial_evidence.policies(id) on delete restrict,
  retained_object_reference text not null check (length(retained_object_reference) between 3 and 500),
  retained_object_version text not null check (length(retained_object_version) between 1 and 200),
  byte_sha256 text not null check (byte_sha256 ~ '^[a-f0-9]{64}$'),
  byte_length bigint not null check (byte_length > 0),
  captured_at timestamptz not null check (isfinite(captured_at)),
  provenance jsonb not null check (jsonb_typeof(provenance) = 'object'),
  provenance_sha256 text generated always as
    (encode(extensions.digest(provenance::text, 'sha256'), 'hex')) stored,
  custody_readback_reference text not null check (length(custody_readback_reference) between 3 and 500),
  recorded_at timestamptz not null default clock_timestamp(),
  unique (retained_object_reference, retained_object_version)
);

-- Private owner helper: computes bytes hash/length, does not authenticate bytes.
-- No EXECUTE grant is provided. The selected adapter must enforce approved input
-- limits/reader authority and actual retained-object equality before invoking it.
create function collect_financial_evidence.record_source_object(
  p_policy_id uuid, p_retained_object_reference text, p_retained_object_version text,
  p_bytes bytea, p_captured_at timestamptz, p_provenance jsonb,
  p_custody_readback_reference text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare result_id uuid;
begin
  if p_bytes is null or octet_length(p_bytes) = 0 then
    raise exception 'financial_source_bytes_required' using errcode = '22023';
  end if;
  insert into collect_financial_evidence.source_objects(
    policy_id, retained_object_reference, retained_object_version, byte_sha256,
    byte_length, captured_at, provenance, custody_readback_reference)
  values (p_policy_id, p_retained_object_reference, p_retained_object_version,
    encode(extensions.digest(p_bytes, 'sha256'), 'hex'), octet_length(p_bytes),
    p_captured_at, p_provenance, p_custody_readback_reference)
  returning id into result_id;
  return result_id;
end $$;

create function collect_financial_evidence.record_digest(
  p_object_id uuid, p_row_reference text, p_record_reference text, p_purpose text, p_network text, p_transaction text,
  p_receiver_hash text, p_receiver_authority_reference text, p_amount_rwf bigint, p_currency text,
  p_occurred_at timestamptz, p_authentication_state text, p_finality_state text,
  p_checker_version text, p_checker_artifact_sha256 text
) returns text language sql immutable set search_path = '' as $$
  select encode(extensions.digest(jsonb_build_object(
    'contract_version',1,'source_object_id',p_object_id,
    'source_row_reference',p_row_reference,
    'source_record_reference',p_record_reference,'provider_network',p_network,
    'purpose',p_purpose,
    'transaction_id',p_transaction,'receiver_hash',p_receiver_hash,
    'receiver_authority_reference',p_receiver_authority_reference,
    'amount_rwf',p_amount_rwf,'currency',p_currency,
    'occurred_at_epoch',extract(epoch from p_occurred_at),
    'authentication_state',p_authentication_state,'finality_state',p_finality_state,
    'checker_version',p_checker_version,'checker_artifact_sha256',p_checker_artifact_sha256
  )::text,'sha256'),'hex')
$$;

-- Only the selected trusted adapter may create a source record after verifying
-- the actual source. Client input cannot assert authenticated/settled/matched.
create table collect_financial_evidence.source_records (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  source_object_id uuid not null references collect_financial_evidence.source_objects(id) on delete restrict,
  source_row_reference text not null check (length(source_row_reference) between 1 and 128),
  purpose text not null check (purpose in ('receipt', 'reversal', 'rejection')),
  source_record_reference text not null check
    (length(source_record_reference) between 3 and 128 and source_record_reference = upper(btrim(source_record_reference))),
  provider_network text not null check (provider_network in ('mtn_momo', 'airtel_money')),
  transaction_id text not null check
    (length(transaction_id) between 3 and 128 and transaction_id = upper(btrim(transaction_id))),
  receiver_momo_number_hash text not null check (receiver_momo_number_hash ~ '^[a-f0-9]{64}$'),
  receiver_authority_reference text not null check (length(receiver_authority_reference) between 3 and 500),
  amount_rwf bigint not null check (amount_rwf between 1 and 9007199254740991),
  currency text not null check (currency = 'RWF'),
  occurred_at timestamptz not null check (isfinite(occurred_at)),
  authentication_state text not null check (authentication_state in
    ('authenticated', 'internal_reviewed', 'rejected', 'unverified')),
  finality_state text not null check (finality_state in ('settled', 'not_settled', 'unknown', 'internal_record', 'reversed')),
  checker_artifact_sha256 text not null check (checker_artifact_sha256 ~ '^[a-f0-9]{64}$'),
  checker_version text not null check (length(checker_version) between 1 and 128),
  record_sha256 text generated always as
    (collect_financial_evidence.record_digest(source_object_id, source_row_reference, source_record_reference, purpose,
      provider_network, transaction_id, receiver_momo_number_hash, receiver_authority_reference, amount_rwf,
      currency, occurred_at, authentication_state, finality_state,
      checker_version, checker_artifact_sha256)) stored,
  recorded_at timestamptz not null default clock_timestamp(),
  unique (source_object_id, source_row_reference)
);
create index financial_evidence_source_selector on collect_financial_evidence.source_records
  (source_record_reference, occurred_at, source_object_id);

-- Proposal writes this atomically with the actual immutable review. No backfill
-- of missing historical source/checker facts. Expired reviews can be replaced by
-- fresh reviews using the same real source, but unique consumption permits only
-- one financial use of that source row.
create table collect_financial_evidence.review_bindings (
  review_id uuid primary key references collect_security.reconciliation_reviews(id) on delete restrict,
  source_record_id uuid not null references collect_financial_evidence.source_records(id) on delete restrict,
  matched_payment_fingerprint text not null check (matched_payment_fingerprint ~ '^[a-f0-9]{64}$'),
  match_decision_sha256 text not null check (match_decision_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default clock_timestamp()
);
create table collect_financial_evidence.consumptions (
  source_record_id uuid primary key references collect_financial_evidence.source_records(id) on delete restrict,
  review_id uuid not null unique references collect_security.reconciliation_reviews(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict,
  finality_request_id uuid not null unique references public.provider_finality_requests(request_id) on delete restrict,
  recorded_at timestamptz not null default clock_timestamp()
);

-- The real reversal writer creates an operation binding under the selected
-- policy/authority before the existing request-id signature is used. Purpose,
-- reason, current candidate fingerprint and actual checker are immutable.
create table collect_financial_evidence.operation_bindings (
  request_id uuid primary key,
  payment_id uuid not null references public.payments(id) on delete restrict,
  source_record_id uuid not null references collect_financial_evidence.source_records(id) on delete restrict,
  purpose text not null check (purpose in ('reversal', 'replacement')),
  payment_fingerprint text not null check (payment_fingerprint ~ '^[a-f0-9]{64}$'),
  reason text not null check (length(btrim(reason)) between 8 and 500),
  actor_id uuid not null,
  actor_session_id uuid not null,
  checker_decision_reference text not null check (length(checker_decision_reference) between 3 and 500),
  checker_decision_sha256 text not null check (checker_decision_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default clock_timestamp()
);
create table collect_financial_evidence.correction_lineage (
  operation_request_id uuid primary key references collect_financial_evidence.operation_bindings(request_id) on delete restrict,
  original_payment_id uuid not null references public.payments(id) on delete restrict,
  original_journal_entry_id uuid not null references collect_hybrid.momo_journal_entries(id) on delete restrict,
  reversal_journal_entry_id uuid not null references collect_hybrid.momo_journal_entries(id) on delete restrict,
  replacement_payment_id uuid references public.payments(id) on delete restrict,
  recorded_at timestamptz not null default clock_timestamp(),
  check (original_journal_entry_id <> reversal_journal_entry_id),
  check (replacement_payment_id is null or replacement_payment_id <> original_payment_id)
);

create function collect_financial_evidence.immutable_fact()
returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'financial_evidence_immutable' using errcode = '55000'; end $$;
do $$ declare item text; begin
  foreach item in array array['policies','policy_events','source_objects','source_records',
    'review_bindings','consumptions','operation_bindings','correction_lineage'] loop
    execute format('alter table collect_financial_evidence.%I enable row level security',item);
    execute format('create trigger financial_evidence_immutable before update or delete on collect_financial_evidence.%I for each row execute function collect_financial_evidence.immutable_fact()',item);
  end loop;
end $$;

-- Call only for a NEW posting after existing session/roster/review/payment locks.
-- Already-consumed legacy reviews keep the old acknowledgement before this call.
-- This draft guard is not wired into maintained proposal/approval/finalizer.
create function collect_financial_evidence.require_admitted_review(p_review_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r collect_security.reconciliation_reviews;
  p public.payments;
  b collect_financial_evidence.review_bindings;
  s collect_financial_evidence.source_records;
  o collect_financial_evidence.source_objects;
  policy collect_financial_evidence.policies;
  latest_decision text;
  candidate_count bigint;
begin
  select * into r from collect_security.reconciliation_reviews where id=p_review_id;
  select * into b from collect_financial_evidence.review_bindings where review_id=p_review_id;
  if r.id is null or b.review_id is null then
    raise exception 'financial_source_admission_required' using errcode='22023';
  end if;
  select * into s from collect_financial_evidence.source_records where id=b.source_record_id;
  select * into o from collect_financial_evidence.source_objects where id=s.source_object_id;
  select * into policy from collect_financial_evidence.policies where id=o.policy_id;
  if s.id is null or o.id is null or policy.id is null then
    raise exception 'financial_source_admission_required' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('financial-evidence-policy:'||policy.id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('financial-evidence-source:'||s.id::text,0));
  select decision into latest_decision from collect_financial_evidence.policy_events
    where policy_id=policy.id order by sequence desc limit 1;
  if latest_decision is distinct from 'approved' then
    raise exception 'financial_source_policy_unavailable' using errcode='22023';
  end if;
  if s.purpose<>'receipt'
    or s.checker_version is distinct from policy.approved_checker_version
    or s.checker_artifact_sha256 is distinct from policy.approved_checker_artifact_sha256
    or not (s.finality_state=any(policy.permitted_source_finality_states))
    or (policy.route_kind='constrained_internal_reconciliation' and
      (s.authentication_state<>'internal_reviewed' or s.finality_state<>'internal_record'))
    or (policy.route_kind<>'constrained_internal_reconciliation' and s.authentication_state<>'authenticated')
    or (policy.provider_settlement_verified and s.finality_state<>'settled')
    or s.finality_state in ('not_settled','unknown','reversed') then
    raise exception 'financial_source_not_admitted' using errcode='22023';
  end if;
  select * into p from public.payments where id=r.payment_id;
  if p.id is null or p.status<>'review' or p.currency<>'RWF'
    or collect_security.reconciliation_fingerprint(p) is distinct from r.payment_fingerprint
    or b.matched_payment_fingerprint is distinct from r.payment_fingerprint
    or s.provider_network is distinct from lower(btrim(p.provider_network))
    or s.transaction_id is distinct from upper(btrim(p.transaction_id))
    or s.receiver_momo_number_hash is distinct from p.receiver_momo_number_hash
    or s.amount_rwf is distinct from p.amount_rwf or s.currency is distinct from p.currency
    or o.byte_sha256 is distinct from r.evidence_sha256
    or s.source_record_reference is distinct from upper(btrim(r.source_reference))
    or s.occurred_at is distinct from r.occurred_at
    or s.occurred_at>clock_timestamp()+interval '5 minutes' then
    raise exception 'financial_source_candidate_mismatch' using errcode='22023';
  end if;
  perform collect_member_actions.exact_json_amount(s.amount_rwf);
  select count(*) into candidate_count from public.payments candidate
    where lower(btrim(candidate.provider_network))=s.provider_network
      and upper(btrim(candidate.transaction_id))=s.transaction_id
      and candidate.receiver_momo_number_hash=s.receiver_momo_number_hash
      and candidate.amount_rwf=s.amount_rwf and candidate.currency=s.currency;
  if candidate_count<>1 then
    raise exception 'financial_source_ambiguous' using errcode='22023';
  end if;
  if exists(select 1 from collect_financial_evidence.consumptions where source_record_id=s.id) then
    raise exception 'financial_source_already_consumed' using errcode='22023';
  end if;
  return jsonb_build_object('source_record_id',s.id,'source_record_sha256',s.record_sha256,
    'source_object_id',o.id,'source_bytes_sha256',o.byte_sha256,
    'source_provenance_sha256',o.provenance_sha256,'policy_id',policy.id,
    'policy_rules_sha256',policy.rules_sha256,
    'custody_authorization_sha256',policy.custody_authorization_sha256,
    'evidence_level',policy.evidence_level,
    'provider_settlement_verified',policy.provider_settlement_verified);
end $$;

revoke all on all tables in schema collect_financial_evidence
  from public, anon, authenticated, service_role;
revoke all on all sequences in schema collect_financial_evidence
  from public, anon, authenticated, service_role;
revoke all on all functions in schema collect_financial_evidence
  from public, anon, authenticated, service_role;

-- No PUBLIC RPC/EXECUTE grant, seed/approval, table backfill, adapter endpoint,
-- dispatch authority, retained bytes, source authenticity or settlement created.
commit;
