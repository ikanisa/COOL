begin;

-- Manual cancellation only. Preserve the existing receipt identity, immutable
-- financial/payload evidence and seven-state transport contract. No retry,
-- correction, resend, policy approval or dispatch authority is introduced.
create schema collect_receipt_actions;
revoke all on schema collect_receipt_actions from public,anon,authenticated,service_role;
create table collect_receipt_actions.revisions(
 outbox_id uuid primary key references collect_hybrid.sms_notification_outbox(id) on delete restrict,
 revision bigint not null check(revision between 1 and 1000000000)
);
create table collect_receipt_actions.cancellations(
 request_id uuid primary key,
 outbox_id uuid not null unique references collect_hybrid.sms_notification_outbox(id) on delete restrict,
 expected_revision bigint not null check(expected_revision between 1 and 999999999),
 revision bigint not null check(revision=expected_revision+1 and revision<=1000000000),
 reason_code text not null check(reason_code in('operator_cancelled','recipient_review_required','content_review_required')),
 actor_id uuid not null,
 session_id uuid not null,
 recorded_at timestamptz not null check(isfinite(recorded_at))
);
alter table collect_receipt_actions.revisions enable row level security;
alter table collect_receipt_actions.cancellations enable row level security;
revoke all on collect_receipt_actions.revisions,collect_receipt_actions.cancellations
 from public,anon,authenticated,service_role;

create function collect_receipt_actions.immutable_cancellation()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'receipt_action_evidence_retained'using errcode='55000';end$$;
create trigger immutable_receipt_cancellation before update or delete on collect_receipt_actions.cancellations
 for each row execute function collect_receipt_actions.immutable_cancellation();
create function collect_receipt_actions.protect_revision()returns trigger
language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'or new.outbox_id is distinct from old.outbox_id
  or new.revision is distinct from old.revision+1 then
  raise exception 'receipt_action_revision_invalid'using errcode='55000';end if;
 return new;end$$;
create trigger monotonic_receipt_action_revision before update or delete on collect_receipt_actions.revisions
 for each row execute function collect_receipt_actions.protect_revision();
create function collect_receipt_actions.advance_revision()returns trigger
language plpgsql security definer set search_path=''as $$declare value bigint;begin
 -- Existing rows have implicit revision1 without an install-time row write.
 -- Their first UPDATE therefore installs revision2, not revision1.
 insert into collect_receipt_actions.revisions(outbox_id,revision)
 values(new.id,case when tg_op='INSERT'then 1 else 2 end)
 on conflict(outbox_id)do update set revision=revisions.revision+1
  where revisions.revision<1000000000 returning revision into value;
 if value is null then raise exception 'receipt_action_revision_exhausted'using errcode='55000';end if;
 return new;end$$;
create trigger zzzzz_receipt_action_revision after insert or update on collect_hybrid.sms_notification_outbox
 for each row execute function collect_receipt_actions.advance_revision();
create function collect_receipt_actions.protect_cancelled_receipt()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.state is distinct from 'suppressed'and exists(select 1 from collect_receipt_actions.cancellations
  where outbox_id=old.id)then
  raise exception 'receipt_manual_cancellation_final'using errcode='55000';end if;
 return new;end$$;
create trigger receipt_manual_cancellation_final before update on collect_hybrid.sms_notification_outbox
 for each row execute function collect_receipt_actions.protect_cancelled_receipt();

create function collect_receipt_actions.actor(p_mutation boolean)returns uuid
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;permissions text[]:=array['payments.read','notifications.read','system_health.read'];begin
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'receipt_action_snapshot_retry'using errcode='40001';end if;
 sid:=public._lock_notification_registration_session();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if p_mutation then permissions:=array_append(permissions,'notifications.manage');end if;
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',permissions);
 -- No legacy phone approval fallback, including while transition mode remains.
 if not collect_admin_access.email_identity(auth.uid())then
  raise exception 'receipt_action_current_email_owner_required'using errcode='42501';end if;
 return sid;end$$;

create function collect_receipt_actions.ineligible_reason(p_job collect_hybrid.sms_notification_outbox)
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
    and collect_ops.payment_scope(p.id)
    and(p.parsed_event_id is null or collect_ops.transaction_sms_id('payment',p.id)is not null)
    and p.collection_id=p_job.collection_id and p.member_record_id=p_job.member_record_id
    and p.amount_rwf=p_job.amount_rwf
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
      collect_hybrid.render_buri_munsi_receipt(p_job.amount_rwf,
       p_job.member_balance_rwf,p_job.group_balance_rwf,p_job.reference)else null end
    and p_job.body_sha256=encode(extensions.digest(p_job.message_body,'sha256'),'hex'))then 'source_evidence_invalid'
  else 'eligible'end
$$;

create function collect_receipt_actions.receipt(p_action collect_receipt_actions.cancellations)
returns jsonb language sql immutable set search_path=''as $$
 select jsonb_build_object('contract_version',1,'scope','rw_receipt_manual_cancel',
  'request_id',p_action.request_id,'outbox_id',p_action.outbox_id,'expected_revision',p_action.expected_revision,
  'revision',p_action.revision,'action','cancel_unstarted','reason_code',p_action.reason_code,
  'recorded_at',collect_ops.utc(p_action.recorded_at),'state_before','queued','state_after','suppressed',
  'financial_action',false,'send_action',false,'provider_delivery_verified',false,'primary_receipt_retained',true)
$$;

create function public.admin_inspect_unstarted_receipt_v1(p_outbox_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare job collect_hybrid.sms_notification_outbox;result jsonb;begin
 perform collect_receipt_actions.actor(false);
 if p_outbox_id is null then raise exception 'receipt_action_input_invalid'using errcode='22023';end if;
 -- The same actual outbox lock protects the source/head pair used by cancel.
 select * into job from collect_hybrid.sms_notification_outbox where id=p_outbox_id for share;
 with sample as materialized(select clock_timestamp()at),
 source as materialized(select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=job.id),1)revision,
  collect_receipt_actions.ineligible_reason(job)reason
  where job.id is not null and collect_ops.payment_scope(job.payment_id)),
 data as materialized(select revision,case when revision=1000000000 then 'revision_exhausted'else reason end reason from source)
 select jsonb_build_object('contract_version',1,'scope','rw_receipt_manual_cancel',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'outbox_id',p_outbox_id,'status',case when exists(select 1 from data)then 'available'else 'unavailable'end,
  'receipt',(select jsonb_build_object('outbox_id',job.id,'revision',data.revision,'state',job.state,
    'can_cancel',data.reason='eligible','reason_code',data.reason)from data))into result from sample;
 return result;
exception when lock_not_available then raise exception 'receipt_action_authority_busy'using errcode='55P03';end$$;

create function public.admin_cancel_unstarted_receipt_v1(p_request_id uuid,p_outbox_id uuid,
 p_expected_revision bigint,p_reason_code text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;job collect_hybrid.sms_notification_outbox;prior collect_receipt_actions.cancellations;
 before_revision bigint;after_revision bigint;at timestamptz;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_outbox_id is null or p_expected_revision is null
  or p_expected_revision not between 1 and 999999999 or p_reason_code is null
  or p_reason_code not in('operator_cancelled','recipient_review_required','content_review_required')then
  raise exception 'receipt_action_input_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-cancel-request:'||p_request_id::text,0));
 select * into prior from collect_receipt_actions.cancellations where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.outbox_id<>p_outbox_id or prior.expected_revision<>p_expected_revision
   or prior.reason_code<>p_reason_code then raise exception 'receipt_action_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);
  return collect_receipt_actions.receipt(prior);
 end if;
 select * into job from collect_hybrid.sms_notification_outbox where id=p_outbox_id for update;
 -- Revalidate natural expiry after waiting, without changing the lock order:
 -- all authority proof locks were already held before the request/outbox lock.
 perform collect_receipt_actions.actor(true);
 select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=job.id),1)into before_revision;
 if job.id is null or not collect_ops.payment_scope(job.payment_id)then
  raise exception 'receipt_action_unavailable'using errcode='55000';end if;
 if before_revision<>p_expected_revision then raise exception 'receipt_action_source_changed'using errcode='55000';end if;
 if collect_receipt_actions.ineligible_reason(job)is distinct from 'eligible'then
  raise exception 'receipt_not_cancellable'using errcode='55000';end if;
 update collect_hybrid.sms_notification_outbox set state='suppressed',suppression_reason='manual_pre_send_cancel'
  where id=job.id;
 select revision into after_revision from collect_receipt_actions.revisions where outbox_id=job.id;
 if after_revision is distinct from before_revision+1 then
  raise exception 'receipt_action_revision_invalid'using errcode='55000';end if;
 at:=clock_timestamp();
 insert into collect_receipt_actions.cancellations(request_id,outbox_id,expected_revision,revision,
  reason_code,actor_id,session_id,recorded_at)
 values(p_request_id,job.id,before_revision,after_revision,p_reason_code,auth.uid(),sid,at)returning * into prior;
 perform public.create_audit_log('notification.sms.cancelled_unstarted','sms_notification_outbox',job.id,
  jsonb_build_object('request_id',p_request_id,'expected_revision',before_revision,'revision',after_revision,
   'reason_code',p_reason_code,'financial_action',false,'send_action',false),null);
 return collect_receipt_actions.receipt(prior);
end$$;

create function public.admin_get_unstarted_receipt_action_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare result jsonb;acquired boolean;begin
 perform collect_receipt_actions.actor(false);
 if p_request_id is null then raise exception 'receipt_action_input_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-cancel-request:'||p_request_id::text,0));
 with sample as materialized(select clock_timestamp()at),
 prior as materialized(select * from collect_receipt_actions.cancellations
  where acquired and request_id=p_request_id and actor_id=auth.uid())
 select jsonb_build_object('contract_version',1,'scope','rw_receipt_manual_cancel',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'request_id',p_request_id,'status',case when not acquired then 'in_progress'
    when exists(select 1 from prior)then 'recorded'else 'not_recorded'end,
  'receipt',(select collect_receipt_actions.receipt(p)from prior p))into result from sample;
 return result;
exception when lock_not_available then raise exception 'receipt_action_authority_busy'using errcode='55P03';end$$;

revoke all on all functions in schema collect_receipt_actions from public,anon,authenticated,service_role;
revoke all on function public.admin_inspect_unstarted_receipt_v1(uuid),
 public.admin_cancel_unstarted_receipt_v1(uuid,uuid,bigint,text),public.admin_get_unstarted_receipt_action_v1(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_inspect_unstarted_receipt_v1(uuid),
 public.admin_cancel_unstarted_receipt_v1(uuid,uuid,bigint,text),public.admin_get_unstarted_receipt_action_v1(uuid)to authenticated;
commit;
