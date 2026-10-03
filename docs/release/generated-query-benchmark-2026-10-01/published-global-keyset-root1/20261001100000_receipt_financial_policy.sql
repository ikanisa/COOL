begin;
-- Owner-delegated content decisions; no scheduler, dispatch grant, backfill or
-- external settlement/delivery attestation is created by this migration.
create schema collect_receipt_policy;
revoke all on schema collect_receipt_policy from public,anon,authenticated,service_role;
create table collect_receipt_policy.decisions(
 version integer primary key check(version=2),
 approval_method text not null check(approval_method='user_delegated_policy_selection'),
 owner_message text not null,
 choices jsonb not null check(jsonb_typeof(choices)='object'),
 recorded_at timestamptz not null default clock_timestamp());
insert into collect_receipt_policy.decisions(version,approval_method,owner_message,choices)values(
 2,'user_delegated_policy_selection',
 'fix these as well you have full authorisation and approval from me. Hosted email authentication is still disabled; the operator session, financial policies, real Android gateway tests and release acceptance remain outstanding',
 '{"event":"existing_rwanda_canonical_posting_with_bound_recorded_confirmation","balance":"immutable_member_savings_snapshot_in_this_group","recipient":"active_allocated_account_independent_member_current_contact_and_explicit_consent","disclosure":"member_only_no_group_total","wording":"recorded_savings_no_external_settlement_claim","default_language":"rw","explicit_helpers":["rw","en","fr"],"historical_auto_catchup":false,"correction_or_resend":false,"unknown_resolution":"manual_evidence_review_no_blind_retry","dispatch_authority_created":false}'::jsonb);
create table collect_receipt_policy.content_evidence(
 outbox_id uuid primary key references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 content_version integer not null references collect_receipt_policy.decisions(version),
 language text not null check(language='rw'),
 snapshot_recorded_at timestamptz not null check(isfinite(snapshot_recorded_at)),
 body_sha256 text not null check(body_sha256~'^[0-9a-f]{64}$'));
alter table collect_receipt_policy.decisions enable row level security;
alter table collect_receipt_policy.content_evidence enable row level security;
revoke all on all tables in schema collect_receipt_policy from public,anon,authenticated,service_role;
create function collect_receipt_policy.immutable_evidence()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'receipt_content_evidence_immutable'using errcode='55000';end$$;
create trigger receipt_content_decisions_immutable before update or delete on collect_receipt_policy.decisions
 for each row execute function collect_receipt_policy.immutable_evidence();
create trigger receipt_content_proof_immutable before update or delete on collect_receipt_policy.content_evidence
 for each row execute function collect_receipt_policy.immutable_evidence();
-- Collection configuration1 is deliberately distinct from approved content2.
-- Existing immutable rows and lifetime primary/snapshot constraints are retained.
alter table collect_hybrid.sms_notification_outbox
 drop constraint sms_notification_outbox_template_version_check;
alter table collect_hybrid.sms_notification_outbox add constraint sms_notification_outbox_template_version_check
 check(template_version in(1,2));
create function collect_receipt_policy.render_v2(p_amount_rwf bigint,p_member_balance_rwf bigint,
 p_recorded_at timestamptz,p_reference text,p_language text default 'rw')returns text
language plpgsql immutable set search_path=''as $$
declare ref text:=btrim(coalesce(p_reference,''));at_text text;amount text;balance text;begin
 if p_amount_rwf is null or p_amount_rwf<=0 or p_member_balance_rwf is null or p_member_balance_rwf<0
  or p_recorded_at is null or not isfinite(p_recorded_at)
  or ref!~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'or p_language is null or p_language not in('rw','en','fr')then
  raise exception 'receipt_content_input_invalid'using errcode='22023';end if;
 at_text:=to_char(p_recorded_at at time zone 'Africa/Kigali','YYYY-MM-DD HH24:MI')||' CAT';
 amount:=to_char(p_amount_rwf,'FM9,999,999,999,999,999,990');
 balance:=to_char(p_member_balance_rwf,'FM9,999,999,999,999,999,990');
 return case p_language
  when 'rw'then 'BuriMunsi: Ubwizigame bwa '||amount||' RWF bwanditswe. Igiteranyo cyawe cyanditswe muri iri tsinda ku '||at_text||': '||balance||' RWF. Ref: '||ref||'.'
  when 'en'then 'BuriMunsi: Savings recorded: '||amount||' RWF. Your recorded savings in this group at '||at_text||': '||balance||' RWF. Ref: '||ref||'.'
  when 'fr'then 'BuriMunsi: Épargne enregistrée: '||amount||' RWF. Votre épargne enregistrée dans ce groupe au '||at_text||': '||balance||' RWF. Réf: '||ref||'.'end;
end$$;
create function collect_receipt_policy.render_snapshot(p_snapshot collect_hybrid.momo_balance_snapshots,
 p_version integer,p_reference text)returns text language sql stable security definer set search_path=''as $$
 select case p_version when 1 then collect_hybrid.render_buri_munsi_receipt(p_snapshot.delta_rwf,
  p_snapshot.member_balance_after_rwf,p_snapshot.group_balance_after_rwf,p_reference)
 when 2 then collect_receipt_policy.render_v2(p_snapshot.delta_rwf,p_snapshot.member_balance_after_rwf,
  p_snapshot.captured_at,p_reference,'rw')else null end
$$;
create function collect_receipt_policy.body_for_job(p_job collect_hybrid.sms_notification_outbox)
returns text language sql stable security definer set search_path=''as $$
 select collect_receipt_policy.render_snapshot(s,p_job.template_version,p_job.reference)
 from collect_hybrid.momo_balance_snapshots s where s.id=p_job.snapshot_id
$$;
create function collect_receipt_policy.snapshot_is_eligible(p_snapshot collect_hybrid.momo_balance_snapshots)
returns boolean language sql stable security definer set search_path=''as $$
 select exists(select 1 from public.payments p
 join public.collections c on c.id=p.collection_id
 join collect_hybrid.member_records m on m.id=p.member_record_id
 join collect_hybrid.momo_journal_entries j on j.id=p_snapshot.journal_entry_id
 join public.payment_provider_confirmations pc on pc.payment_id=p.id
 where p.id=p_snapshot.payment_id and p.status='posted'and p.currency='RWF'
  and p.amount_rwf>0 and p_snapshot.event_type='receipt'
  and p.collection_id=p_snapshot.collection_id and p.member_record_id=p_snapshot.member_record_id
  and p_snapshot.delta_rwf=p.amount_rwf and p_snapshot.member_balance_after_rwf is not null
  and isfinite(p_snapshot.captured_at)
  and c.collection_type='ikimina'and c.archived_at is null
  and m.lifecycle='active'and not collect_hybrid.member_record_has_account(m.id)
  and exists(select 1 from public.collection_members cm where cm.collection_id=p.collection_id
   and cm.member_record_id=p.member_record_id and cm.status='active')
  and collect_ops.payment_scope(p.id)
  and(p.parsed_event_id is null or collect_ops.transaction_sms_id('payment',p.id)is not null)
  and pc.provider_network=p.provider_network and upper(btrim(pc.transaction_id))=upper(btrim(p.transaction_id))
  and pc.receiver_momo_number_hash=p.receiver_momo_number_hash and pc.amount_rwf=p.amount_rwf and pc.currency='RWF'
  and j.payment_id=p.id and j.collection_id=p.collection_id and j.member_record_id=p.member_record_id
  and j.entry_type='receipt'and j.amount_rwf=p.amount_rwf
  and not exists(select 1 from collect_hybrid.momo_journal_entries r where r.payment_id=p.id and r.entry_type='reversal')
  and(select count(*)=2 and count(*)filter(where
   (l.account_code='momo_receiving_asset:RWF'and l.direction='debit')or
   (l.account_code='member_savings_liability:RWF'and l.direction='credit'))=2
   and min(l.amount_rwf)=p.amount_rwf and max(l.amount_rwf)=p.amount_rwf
   from collect_hybrid.momo_journal_lines l where l.journal_entry_id=j.id))
$$;
create function collect_receipt_policy.content_is_valid(p_job collect_hybrid.sms_notification_outbox)
returns boolean language sql stable security definer set search_path=''as $$
 select coalesce(p_job.template_version=2 and exists(select 1 from collect_receipt_policy.content_evidence e
 join collect_hybrid.momo_balance_snapshots s on s.id=p_job.snapshot_id
 where e.outbox_id=p_job.id and e.content_version=2 and e.language='rw'
  and e.snapshot_recorded_at=s.captured_at and e.body_sha256=p_job.body_sha256
  and p_job.message_body=collect_receipt_policy.render_snapshot(s,2,p_job.reference)
  and p_job.body_sha256=encode(extensions.digest(p_job.message_body,'sha256'),'hex')),false)
$$;
create function collect_receipt_policy.content_is_current(p_job collect_hybrid.sms_notification_outbox)
returns boolean language sql stable security definer set search_path=''as $$
 select collect_receipt_policy.content_is_valid(p_job)and exists(select 1 from collect_hybrid.momo_balance_snapshots s
 where s.id=p_job.snapshot_id and collect_receipt_policy.snapshot_is_eligible(s))
$$;
create function collect_receipt_policy.verify_new_content()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.template_version=2 and new.message_body is not null
  and not collect_receipt_policy.content_is_valid(new)then
  raise exception 'receipt_content_evidence_invalid'using errcode='55000';end if;return null;end$$;
create constraint trigger receipt_content_insert_proof after insert on collect_hybrid.sms_notification_outbox
 deferrable initially deferred for each row execute function collect_receipt_policy.verify_new_content();
create or replace function collect_hybrid.enqueue_sms_receipt_from_snapshot()returns trigger
language plpgsql security definer set search_path=''as $$
declare payment public.payments;identity collect_hybrid.member_momo_identities;
 policy collect_hybrid.sms_receipt_policies;consent collect_hybrid.sms_receipt_member_consents;
 message text;reference_value text;job_id uuid;begin
 -- No caller-supplied contact, amount, balance, text or language is accepted.
 -- Pausing dispatch preserves newly eligible work; historical catch-up is closed.
 if not collect_receipt_policy.snapshot_is_eligible(new)then return new;end if;
 select * into policy from collect_hybrid.sms_receipt_policies where collection_id=new.collection_id
  and enabled and template_key='buri_munsi.payment_received'and template_version=1;
 if policy.collection_id is null then return new;end if;
 select * into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=new.member_record_id and enabled;
 if consent.member_record_id is null then return new;end if;
 select * into identity from collect_hybrid.member_momo_identities where member_id=new.member_record_id;
 if identity.member_id is null then return new;end if;
 select * into payment from public.payments where id=new.payment_id;
 reference_value:=btrim(coalesce(payment.transaction_id,''));
 if reference_value~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then
  message:=collect_receipt_policy.render_v2(payment.amount_rwf,new.member_balance_after_rwf,new.captured_at,reference_value,'rw');
 end if;
 insert into collect_hybrid.sms_notification_outbox(payment_id,snapshot_id,collection_id,member_record_id,
  destination_e164,destination_sha256,destination_revision,policy_revision,consent_revision,
  template_key,template_version,amount_rwf,member_balance_rwf,group_balance_rwf,reference,
  message_body,body_sha256,state,suppression_reason)
 values(payment.id,new.id,new.collection_id,new.member_record_id,identity.momo_number,
  encode(extensions.digest(identity.momo_number,'sha256'),'hex'),identity.revision,policy.revision,consent.revision,
  policy.template_key,2,payment.amount_rwf,new.member_balance_after_rwf,new.group_balance_after_rwf,
  coalesce(nullif(reference_value,''),'invalid'),message,
  case when message is not null then encode(extensions.digest(message,'sha256'),'hex')end,
  case when message is null then 'suppressed'else 'queued'end,
  case when message is null then 'Provider reference is not safe for the canonical receipt template'end)
 on conflict(payment_id,template_key)do nothing returning id into job_id;
 if job_id is not null and message is not null then
  insert into collect_receipt_policy.content_evidence(outbox_id,content_version,language,snapshot_recorded_at,body_sha256)
  values(job_id,2,'rw',new.captured_at,encode(extensions.digest(message,'sha256'),'hex'));
 end if;
 return new;end$$;
create or replace function collect_hybrid.sms_receipt_job_is_current(p_job_id uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select coalesce((select true from collect_hybrid.sms_notification_outbox job
 join collect_hybrid.member_momo_identities identity on identity.member_id=job.member_record_id
 join collect_hybrid.sms_receipt_policies policy on policy.collection_id=job.collection_id
 join collect_hybrid.sms_receipt_member_consents consent on consent.member_record_id=job.member_record_id
 where job.id=p_job_id and collect_receipt_policy.content_is_current(job)
  and coalesce((select enabled from public.feature_flags where key='hybrid_sms_notifications'),false)
  and identity.revision=job.destination_revision and identity.momo_number=job.destination_e164
  and encode(extensions.digest(identity.momo_number,'sha256'),'hex')=job.destination_sha256
  and policy.enabled and policy.revision=job.policy_revision and policy.template_key=job.template_key
  and policy.template_version=1 and consent.enabled and consent.revision=job.consent_revision),false)
$$;

create or replace function public.collect_claim_receipt(
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
  perform collect_hybrid.require_receipt_dispatch_enabled();
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
  if job.template_version is distinct from 2 then
    raise exception 'CONTENT_POLICY_REVIEW_REQUIRED' using errcode='55000';
  end if;
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

create or replace function collect_hybrid.guard_receipt_dispatch_transition()returns trigger
language plpgsql security definer set search_path=''as $$
declare job collect_hybrid.sms_notification_outbox;begin
 if tg_table_name='sms_notification_attempts'then
  perform collect_hybrid.require_receipt_dispatch_enabled();
  select * into job from collect_hybrid.sms_notification_outbox where id=new.outbox_id;
  if job.template_version is distinct from 2 then raise exception 'CONTENT_POLICY_REVIEW_REQUIRED'using errcode='55000';end if;
  if not collect_hybrid.sms_receipt_job_is_current(job.id)then raise exception 'receipt_content_authority_invalid'using errcode='55000';end if;
 elsif new.state in('awaiting_confirmation','send_started')and(tg_op='INSERT'or new.state is distinct from old.state)then
  perform collect_hybrid.require_receipt_dispatch_enabled();
  if new.template_version is distinct from 2 then raise exception 'CONTENT_POLICY_REVIEW_REQUIRED'using errcode='55000';end if;
  if not collect_hybrid.sms_receipt_job_is_current(new.id)then raise exception 'receipt_content_authority_invalid'using errcode='55000';end if;
 end if;return new;end$$;

create or replace function collect_receipt_actions.ineligible_reason(p_job collect_hybrid.sms_notification_outbox)
returns text language sql stable security definer set search_path=''as $$
 select case
  when exists(select 1 from collect_receipt_actions.cancellations where outbox_id=p_job.id)then 'already_cancelled'
  when p_job.state is distinct from 'queued'then 'state_not_queued'
  when p_job.fence_version is distinct from 0 or p_job.attempt_count is distinct from 0
   or p_job.claim_token is not null or p_job.claimed_by is not null or p_job.claim_expires_at is not null
   or p_job.observed_sent_at is not null or p_job.suppression_reason is not null
   or exists(select 1 from collect_hybrid.sms_notification_claim_requests where outbox_id=p_job.id)
   or exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id=p_job.id)
   or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=p_job.id)
   or exists(select 1 from collect_gateway.dispatch_arms g join collect_hybrid.sms_notification_attempts a
    on a.id=g.attempt_id where a.outbox_id=p_job.id)then 'prior_transport_evidence'
  when not exists(select 1 from public.payments p
   join collect_hybrid.momo_balance_snapshots s on s.id=p_job.snapshot_id
   join collect_hybrid.momo_journal_entries j on j.id=s.journal_entry_id
   where p.id=p_job.payment_id and p.status='posted'and p.currency='RWF'
    and collect_receipt_actions.rwanda_source(p_job)
    and p.collection_id=p_job.collection_id and p.member_record_id=p_job.member_record_id
    and p.amount_rwf=p_job.amount_rwf
    and p_job.reference=coalesce(nullif(btrim(p.transaction_id),''),p.id::text)
    and s.payment_id=p.id and s.collection_id=p_job.collection_id and s.member_record_id=p_job.member_record_id
    and s.event_type='receipt'and s.delta_rwf=p_job.amount_rwf
    and s.member_balance_after_rwf=p_job.member_balance_rwf and s.group_balance_after_rwf=p_job.group_balance_rwf
    and j.payment_id=p.id and j.collection_id=p_job.collection_id and j.member_record_id=p_job.member_record_id
    and j.entry_type='receipt'and j.amount_rwf=p_job.amount_rwf
    and not exists(select 1 from collect_hybrid.momo_journal_entries r where r.payment_id=p.id and r.entry_type='reversal')
    and(select count(*)=2 and count(*)filter(where
      (l.account_code='momo_receiving_asset:RWF'and l.direction='debit')or
      (l.account_code='member_savings_liability:RWF'and l.direction='credit'))=2
     and min(l.amount_rwf)=p_job.amount_rwf and max(l.amount_rwf)=p_job.amount_rwf
     from collect_hybrid.momo_journal_lines l where l.journal_entry_id=j.id)
    and p_job.destination_sha256=encode(extensions.digest(p_job.destination_e164,'sha256'),'hex')
    and p_job.message_body=case when btrim(p_job.reference)~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then
      collect_receipt_policy.body_for_job(p_job)else null end
    and p_job.body_sha256=encode(extensions.digest(p_job.message_body,'sha256'),'hex'))then 'source_evidence_invalid'
  else 'eligible'end
$$;
create or replace function public.admin_get_collect_investigation_v1(p_kind text,p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
set timezone='UTC' as $$
declare payment_access boolean; receipt_access boolean; result jsonb; checked timestamptz;
begin
 if p_kind is null or p_kind not in ('transaction','receipt') or p_id is null then
  raise exception 'investigation_target_invalid' using errcode='22023';end if;
 payment_access:=collect_security.transaction_read_authority('payments.read');
 receipt_access:=collect_security.transaction_read_authority('notifications.read');
 if (p_kind='transaction' and not payment_access) or (p_kind='receipt' and not receipt_access) then
  raise exception 'investigation_permission_required' using errcode='42501';end if;

 -- Every section shares one statement snapshot. checked_at is captured after
 -- this read; it is measurement time, never a substituted business timestamp.
 with target as (
  select sms.id sms_id,e.id event_id,p.id payment_id,
   coalesce(p.collection_id,e.collection_id,sms.collection_id) collection_id,
   p.member_record_id,o.id outbox_id,
   collect_security.rwanda_sms_scope(sms.id) supported
  from public.raw_payment_sms sms
  left join public.parsed_payment_events e on e.raw_sms_id=sms.id
  left join public.payments p on p.parsed_event_id=e.id
  left join collect_hybrid.sms_notification_outbox o on o.payment_id=p.id
   and o.template_key='buri_munsi.payment_received'
  where p_kind='transaction' and sms.id=p_id
  union all
  select sms.id,e.id,p.id,o.collection_id,o.member_record_id,o.id,
   coalesce(collect_security.rwanda_sms_scope(sms.id),false)
  from collect_hybrid.sms_notification_outbox o
  join public.payments p on p.id=o.payment_id
  left join public.parsed_payment_events e on e.id=p.parsed_event_id
  left join public.raw_payment_sms sms on sms.id=e.raw_sms_id
  where p_kind='receipt' and o.id=p_id
 ), payment_section as (
  select jsonb_build_object(
   'payment_id',t.payment_id,'raw_sms_id',t.sms_id,'event_id',t.event_id,
   'collection_id',t.collection_id,'member_record_id',t.member_record_id,
   'lifecycle',case when t.sms_id is not null then
    collect_security.transaction_lifecycle(t.sms_id,receipt_access) else null end,
   'times',jsonb_build_object('received_at_device',sms.received_at_device,
    'ingested_at',sms.ingested_at,'parsed_recorded_at',e.created_at,
    'allocation_recorded_at',a.created_at,'provider_confirmed_at',pc.confirmed_at,
    'confirmation_recorded_at',pc.recorded_at,'rejection_occurred_at',pr.occurred_at,
    'rejection_recorded_at',pr.recorded_at,
    'payment_posted_at',case when p.status in ('posted','reversed') then p.posted_at else null end),
   'journals',coalesce((select jsonb_agg(jsonb_build_object(
    'id',j.id,'entry_type',j.entry_type,'amount_rwf',j.amount_rwf::text,'posted_at',j.posted_at,
    'snapshot',case when s.id is null then null else jsonb_build_object(
     'id',s.id,'captured_at',s.captured_at,'delta_rwf',s.delta_rwf::text,
     'member_balance_rwf',s.member_balance_after_rwf::text,
     'group_balance_rwf',s.group_balance_after_rwf::text) end)
    order by j.posted_at,j.id) from collect_hybrid.momo_journal_entries j
    left join collect_hybrid.momo_balance_snapshots s on s.journal_entry_id=j.id
    where j.payment_id=t.payment_id),'[]'::jsonb),
   'current_balances',jsonb_build_object(
    'member_rwf',mb.confirmed_rwf::text,'member_updated_at',mb.updated_at,
    'group_rwf',gb.confirmed_rwf::text,'group_updated_at',gb.updated_at)) value
  from target t left join public.raw_payment_sms sms on sms.id=t.sms_id
  left join public.parsed_payment_events e on e.id=t.event_id
  left join public.payments p on p.id=t.payment_id
  left join public.payment_allocations a on a.payment_id=t.payment_id
   and a.parsed_event_id=t.event_id
  left join public.payment_provider_confirmations pc on pc.payment_id=t.payment_id
  left join collect_hybrid.payment_provider_rejections pr on pr.payment_id=t.payment_id
  left join collect_hybrid.member_balances mb on mb.collection_id=t.collection_id
   and mb.member_record_id=t.member_record_id
  left join collect_hybrid.collection_balances gb on gb.collection_id=t.collection_id
  where payment_access and t.supported
 ), receipt_section as (
  select jsonb_build_object('id',o.id,'payment_id',o.payment_id,'snapshot_id',o.snapshot_id,
   'collection_id',o.collection_id,'member_record_id',o.member_record_id,'state',o.state,
   'template_key',o.template_key,'template_version',o.template_version,
   'created_at',o.created_at,'updated_at',o.updated_at,'observed_sent_at',o.observed_sent_at,
   'masked_destination','+250•••'||right(o.destination_e164,3),
   'amount_rwf',o.amount_rwf::text,'member_balance_rwf',o.member_balance_rwf::text,
   'group_balance_rwf',o.group_balance_rwf::text,
   'snapshot_captured_at',s.captured_at,
   'preview_source',case when s.id is not null then 'immutable_posting_snapshot' else 'snapshot_unavailable' end,
   'masked_snapshot_preview',case when s.id is not null then
    collect_receipt_policy.render_snapshot(s,o.template_version,'snapshot-'||right(s.id::text,8)) else null end,
   'approvals',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,
    'approved_at',c.approved_at,'expires_at',c.expires_at,'consumed_at',c.consumed_at)
    order by c.approved_at desc,c.id desc) from (select *
     from collect_hybrid.sms_notification_confirmations where outbox_id=o.id
     order by approved_at desc,id desc limit 50)c),'[]'::jsonb),
   'approval_total',(select count(*) from collect_hybrid.sms_notification_confirmations where outbox_id=o.id),
   'attempts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,
    'attempt_number',a.attempt_number,'state',a.state,'send_started_at',a.send_started_at,
    'outcome_at',a.outcome_at) order by a.attempt_number desc) from
     (select * from collect_hybrid.sms_notification_attempts where outbox_id=o.id
      order by attempt_number desc limit 50)a),'[]'::jsonb),
   'attempt_total',(select count(*) from collect_hybrid.sms_notification_attempts where outbox_id=o.id)) value
  from target t join collect_hybrid.sms_notification_outbox o on o.id=t.outbox_id
  -- Reconstruction is allowed only from the matching immutable receipt snapshot.
  left join collect_hybrid.momo_balance_snapshots s on s.id=o.snapshot_id
   and s.payment_id=o.payment_id and s.collection_id=o.collection_id
   and s.member_record_id=o.member_record_id and s.event_type='receipt'
   and s.delta_rwf=o.amount_rwf and s.member_balance_after_rwf=o.member_balance_rwf
   and s.group_balance_after_rwf=o.group_balance_rwf
   and exists(select 1 from collect_hybrid.momo_journal_entries j
    where j.id=s.journal_entry_id and j.payment_id=o.payment_id
     and j.collection_id=o.collection_id and j.member_record_id=o.member_record_id
     and j.entry_type='receipt' and j.amount_rwf=o.amount_rwf)
  where receipt_access and t.supported
 ) select jsonb_build_object(
  'contract_version',1,'scope',case when exists(select 1 from target where supported)
   then 'rwanda_momo' else 'unclassified' end,'kind',p_kind,'target_id',p_id,'history_limit',50,
  'payment_state',case when not payment_access then 'denied'
   when not exists(select 1 from target) then 'missing'
   when not exists(select 1 from target where supported) then 'unsupported' else 'available' end,
  'payment',(select value from payment_section limit 1),
  'receipt_state',case when not receipt_access then 'denied'
   when exists(select 1 from target) and not exists(select 1 from target where supported) then 'unsupported'
   when exists(select 1 from receipt_section) then 'available' else 'missing' end,
  'receipt',(select value from receipt_section limit 1)) into result;
 checked:=clock_timestamp();
 return result||jsonb_build_object('checked_at',checked,'sample_valid_until',checked+interval '60 seconds');
end $$;

create function public.admin_receipt_content_policy_v1()returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare t timestamptz;begin
 perform collect_receipt_actions.actor(false);t:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'scope','rw_receipt_content_policy',
  'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'collection_configuration_version',1,'content_policy_version',2,
  'approval_method','user_delegated_policy_selection','default_language','rw','explicit_languages',jsonb_build_array('rw','en','fr'),
  'balance_disclosure','member_only','financial_evidence','existing_canonical_posting_bound_recorded_confirmation',
  'provider_settlement_verified',false,'historical_auto_catchup',false,'correction_or_resend',false,
  'unknown_resolution','manual_evidence_review_no_blind_retry','dispatch_authority_created',false,
  'legacy_new_authority_reason','CONTENT_POLICY_REVIEW_REQUIRED');
exception when lock_not_available then raise exception 'receipt_policy_authority_busy'using errcode='55P03';end$$;
revoke all on all functions in schema collect_receipt_policy from public,anon,authenticated,service_role;
revoke all on function public.admin_receipt_content_policy_v1()from public,anon,authenticated,service_role;
grant execute on function public.admin_receipt_content_policy_v1()to authenticated;
commit;
