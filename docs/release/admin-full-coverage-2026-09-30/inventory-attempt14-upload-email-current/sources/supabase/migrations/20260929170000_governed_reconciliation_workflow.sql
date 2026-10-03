begin;
-- Additive governed reconciliation. Operator evidence is independently sourced;
-- this workflow records review authority, not provider authenticity by itself.
create schema if not exists collect_security;
revoke all on schema collect_security from public, anon, authenticated, service_role;
create or replace function collect_security.reconciliation_fingerprint(p public.payments)
returns text language sql immutable security invoker set search_path='' as $$
 select encode(extensions.digest(jsonb_build_object(
   'id',p.id,'collection_id',p.collection_id,'amount_rwf',p.amount_rwf,
   'network',p.provider_network,'transaction_id',p.transaction_id,
   'receiver_user_id',p.receiver_user_id,'receiver_hash',p.receiver_momo_number_hash,
   'contributor_user_id',p.contributor_user_id,'member_record_id',p.member_record_id,
   'parsed_event_id',p.parsed_event_id,'payment_intent_id',p.payment_intent_id,
   'source',p.source,'currency',p.currency
 )::text,'sha256'),'hex')
$$;
revoke all on function collect_security.reconciliation_fingerprint(public.payments) from public,anon,authenticated,service_role;

create table if not exists collect_security.reconciliation_reviews (
 id uuid primary key default pg_catalog.gen_random_uuid(),
 payment_id uuid not null references public.payments(id) on delete restrict,
 payment_fingerprint text not null check(payment_fingerprint ~ '^[a-f0-9]{64}$'),
 evidence_sha256 text not null check(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 source_reference text not null check(length(btrim(source_reference)) between 3 and 128),
 occurred_at timestamptz not null,
 proposal_reason text not null check(length(btrim(proposal_reason)) between 10 and 500),
 approval_reason text check(length(btrim(approval_reason)) between 10 and 500),
 proposed_by uuid not null, proposed_at timestamptz not null default clock_timestamp(),
 approved_by uuid, approved_at timestamptz, consumed_at timestamptz,
 check(approved_by is null or approved_by<>proposed_by)
);
-- Existing staged rows remain intact. Missing historical session evidence is
-- never invented: those reviews require a new proposal and independent approval.
alter table collect_security.reconciliation_reviews add column if not exists proposed_session_id uuid;
alter table collect_security.reconciliation_reviews add column if not exists approved_session_id uuid;
-- A fresh proposal must be possible after expiry/revocation without rewriting
-- the former approval. Exact current retries are deduplicated under the roster lock.
do $$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='collect_security.reconciliation_reviews'::regclass
   and contype='u' and pg_get_constraintdef(oid)='UNIQUE (payment_id, evidence_sha256, source_reference)' loop
   execute format('alter table collect_security.reconciliation_reviews drop constraint %I',c.conname);
 end loop;
end $$;
create index if not exists reconciliation_reviews_payment_created_idx
 on collect_security.reconciliation_reviews(payment_id,proposed_at desc,id);
alter table collect_security.reconciliation_reviews enable row level security;
revoke all on collect_security.reconciliation_reviews from public,anon,authenticated,service_role;

create or replace function collect_security.guard_reconciliation_review()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'reconciliation_evidence_immutable' using errcode='55000'; end if;
 if row(new.id,new.payment_id,new.payment_fingerprint,new.evidence_sha256,new.source_reference,
   new.occurred_at,new.proposal_reason,new.proposed_by,new.proposed_at,new.proposed_session_id)
  is distinct from row(old.id,old.payment_id,old.payment_fingerprint,old.evidence_sha256,old.source_reference,
   old.occurred_at,old.proposal_reason,old.proposed_by,old.proposed_at,old.proposed_session_id)
  or (old.approved_by is not null and row(new.approved_by,new.approved_at,new.approval_reason,new.approved_session_id)
    is distinct from row(old.approved_by,old.approved_at,old.approval_reason,old.approved_session_id))
  or (old.consumed_at is not null and new.consumed_at is distinct from old.consumed_at)
  or (new.approved_by is not null and (new.approved_by=new.proposed_by or new.approved_at is null
    or new.approved_session_id is null or length(btrim(coalesce(new.approval_reason,''))) not between 10 and 500))
  or (new.consumed_at is not null and new.approved_by is null) then
   raise exception 'reconciliation_evidence_immutable' using errcode='55000';
 end if;
 return new;
end $$;
drop trigger if exists reconciliation_review_immutable on collect_security.reconciliation_reviews;
create trigger reconciliation_review_immutable before update or delete on collect_security.reconciliation_reviews
 for each row execute function collect_security.guard_reconciliation_review();
revoke all on function collect_security.guard_reconciliation_review() from public,anon,authenticated,service_role;

-- Call with the Admin roster lock held. Row share locks serialize with Auth
-- session deletion/expiry/AAL change and verified-identity changes, which do not
-- take the roster advisory lock. Session IDs are retained as audit facts without
-- an FK so logout can delete Auth sessions without deleting review evidence.
create or replace function collect_security.reconciliation_actor_current(p_actor uuid,p_session uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare u auth.users; s auth.sessions;
begin
 if p_actor is null or p_session is null then return false; end if;
 select * into u from auth.users where id=p_actor for share;
 select * into s from auth.sessions where id=p_session and user_id=p_actor for share;
 if u.id is null or s.id is null or s.aal::text is distinct from 'aal2'
   or (s.not_after is not null and s.not_after<=clock_timestamp())
   or u.deleted_at is not null or u.phone_confirmed_at is null or coalesce(u.is_anonymous,false)
   or (u.banned_until is not null and u.banned_until>clock_timestamp()) then return false; end if;
 return exists(select 1 from collect_admin_access.whatsapp_approvals a
   join public.admin_user_roles ur on ur.user_id=a.user_id and ur.revoked_at is null
   join public.admin_roles r on r.id=ur.role_id and r.name='platform_owner'
   join public.admin_role_permissions rp on rp.role_id=r.id and rp.permission_name='payments.allocate'
   where a.user_id=p_actor and a.revoked_at is null
     and a.phone_e164='+'||ltrim(u.phone,'+')
     and (a.expires_at is null or a.expires_at>clock_timestamp())
     and s.created_at>=a.approved_at and s.created_at>=ur.created_at);
end $$;
revoke all on function collect_security.reconciliation_actor_current(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function collect_security.require_reconciliation_actor()
returns uuid language plpgsql security definer set search_path='' as $$
declare session_text text:=auth.jwt()->>'session_id'; session_id uuid;
begin
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
revoke all on function collect_security.require_reconciliation_actor() from public,anon,authenticated,service_role;

create or replace function public.propose_payment_reconciliation_v2(p_payment_id uuid,p_evidence_sha256 text,p_source_reference text,p_occurred_at timestamptz,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare session_id uuid; payment_row public.payments; prior collect_security.reconciliation_reviews;
 result_id uuid; evidence text:=lower(btrim(coalesce(p_evidence_sha256,'')));
 reference_text text:=upper(btrim(coalesce(p_source_reference,''))); reason_text text:=btrim(coalesce(p_reason,''));
 fingerprint text;
begin
 session_id:=collect_security.require_reconciliation_actor();
 if p_payment_id is null or evidence !~ '^[a-f0-9]{64}$'
   or length(reference_text) not between 3 and 128 or length(reason_text) not between 10 and 500
   or p_occurred_at is null or not isfinite(p_occurred_at) or p_occurred_at>clock_timestamp()+interval '5 minutes' then
  raise exception 'reconciliation_invalid_evidence' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:'||p_payment_id::text,0));
 select * into payment_row from public.payments where id=p_payment_id for update;
 if payment_row.id is null or payment_row.status<>'review' or payment_row.currency<>'RWF'
   or payment_row.provider_network not in ('mtn_momo','airtel_money')
   or payment_row.amount_rwf<=0 or payment_row.transaction_id is null
   or length(btrim(payment_row.transaction_id)) not between 3 and 128
   or payment_row.receiver_momo_number_hash is null or payment_row.receiver_momo_number_hash !~ '^[a-f0-9]{64}$' then
  raise exception 'reconciliation_payment_not_reviewable' using errcode='22023'; end if;
 fingerprint:=collect_security.reconciliation_fingerprint(payment_row);
 select * into prior from collect_security.reconciliation_reviews where payment_id=p_payment_id
   and proposed_by=auth.uid() and proposed_session_id=session_id and payment_fingerprint=fingerprint
   and evidence_sha256=evidence and source_reference=reference_text and occurred_at=p_occurred_at
   and proposal_reason=reason_text and consumed_at is null
   and proposed_at>=clock_timestamp()-interval '24 hours'
   and (approved_at is null or approved_at>=clock_timestamp()-interval '15 minutes')
   order by proposed_at desc,id limit 1;
 if prior.id is not null and (prior.approved_by is null
   or collect_security.reconciliation_actor_current(prior.approved_by,prior.approved_session_id)) then return prior.id; end if;
 insert into collect_security.reconciliation_reviews(payment_id,payment_fingerprint,evidence_sha256,
   source_reference,occurred_at,proposal_reason,proposed_by,proposed_session_id)
 values(p_payment_id,fingerprint,evidence,reference_text,p_occurred_at,reason_text,auth.uid(),session_id)
 returning id into result_id;
 perform public.create_audit_log('reconciliation.proposed','payment',p_payment_id,
  jsonb_build_object('review_id',result_id,'evidence_sha256',evidence,'source_reference',reference_text,
    'reason',reason_text,'session_id',session_id),auth.uid());
 return result_id;
end $$;

create or replace function public.approve_payment_reconciliation_v2(p_review_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path='' as $$
declare session_id uuid; r collect_security.reconciliation_reviews; p public.payments;
 reason_text text:=btrim(coalesce(p_reason,''));
begin
 session_id:=collect_security.require_reconciliation_actor();
 if p_review_id is null or length(reason_text) not between 10 and 500 then
  raise exception 'reconciliation_invalid_reason' using errcode='22023'; end if;
 select * into r from collect_security.reconciliation_reviews where id=p_review_id for update;
 if r.id is null or r.proposed_by=auth.uid() or r.consumed_at is not null
   or r.proposed_at<clock_timestamp()-interval '24 hours'
   or not isfinite(r.occurred_at) or r.occurred_at>clock_timestamp()+interval '5 minutes' then
  raise exception 'reconciliation_independent_approval_required' using errcode='22023'; end if;
 if not collect_security.reconciliation_actor_current(r.proposed_by,r.proposed_session_id) then
  raise exception 'reconciliation_actor_unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:'||r.payment_id::text,0));
 select * into p from public.payments where id=r.payment_id for update;
 if p.id is null or p.status<>'review' or collect_security.reconciliation_fingerprint(p) is distinct from r.payment_fingerprint then
  raise exception 'reconciliation_payment_changed' using errcode='22023'; end if;
 if r.approved_by is not null then
  if r.approved_by=auth.uid() and r.approved_session_id=session_id and r.approval_reason=reason_text
     and r.approved_at>=clock_timestamp()-interval '15 minutes' then return true; end if;
  raise exception 'reconciliation_approval_conflict' using errcode='22023'; end if;
 update collect_security.reconciliation_reviews set approved_by=auth.uid(),approved_session_id=session_id,
  approved_at=clock_timestamp(),approval_reason=reason_text where id=r.id;
 perform public.create_audit_log('reconciliation.approved','payment',r.payment_id,
  jsonb_build_object('review_id',r.id,'evidence_sha256',r.evidence_sha256,'reason',reason_text,
    'session_id',session_id),auth.uid());
 return true;
end $$;

create or replace function public.authorize_reconciliation_finalization_v2(p_review_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare session_id uuid; r collect_security.reconciliation_reviews;
begin
 session_id:=collect_security.require_reconciliation_actor();
 select * into r from collect_security.reconciliation_reviews where id=p_review_id;
 if r.id is null or r.approved_by is distinct from auth.uid() or r.approved_session_id is distinct from session_id then
  raise exception 'reconciliation_approver_required' using errcode='42501'; end if;
 -- A consumed review is a read-only acknowledgement; service finalization
 -- reports its current payment state instead of creating a second posting.
 if r.consumed_at is null and (r.approved_at<clock_timestamp()-interval '15 minutes'
   or r.proposed_at<clock_timestamp()-interval '24 hours') then
  raise exception 'reconciliation_approval_expired' using errcode='22023'; end if;
 return true;
end $$;

create or replace function public.finalize_approved_reconciliation_v2(p_review_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r collect_security.reconciliation_reviews; p public.payments; result jsonb;
begin
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

create or replace function public.list_payment_reconciliations_v2(p_payment_id uuid default null,p_limit integer default 25,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if not coalesce(public.has_admin_permission('payments.read'),false) then
  raise exception 'reconciliation_permission_required' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset<0 or p_offset>100000 then
  raise exception 'reconciliation_invalid_page' using errcode='22023'; end if;
 select jsonb_build_object('total',(select count(*) from collect_security.reconciliation_reviews where p_payment_id is null or payment_id=p_payment_id),
  'rows',coalesce((select jsonb_agg(rowdata order by proposed_at desc,id) from (
   select r.id,r.proposed_at,jsonb_build_object('id',r.id,'payment_id',r.payment_id,'source_reference',r.source_reference,
    'evidence_sha256',r.evidence_sha256,'occurred_at',r.occurred_at,'proposed_by',r.proposed_by,
    'proposed_at',r.proposed_at,'approved_by',r.approved_by,'approved_at',r.approved_at,'consumed_at',r.consumed_at,
    'status',case when r.consumed_at is not null then 'finalized'
      when r.proposed_session_id is null or (r.approved_by is not null and r.approved_session_id is null) then 'legacy_review_required'
      when r.proposed_at<clock_timestamp()-interval '24 hours' or r.approved_at<clock_timestamp()-interval '15 minutes' then 'expired'
      when r.approved_by is not null then 'approved' else 'proposed' end,
    'payment_status',p.status,'amount_rwf',p.amount_rwf,'currency',p.currency) rowdata
   from collect_security.reconciliation_reviews r join public.payments p on p.id=r.payment_id
   where p_payment_id is null or r.payment_id=p_payment_id
   order by r.proposed_at desc,r.id limit p_limit offset p_offset
  ) page),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.get_payment_reconciliation_v2(p_review_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r collect_security.reconciliation_reviews; p public.payments;
begin
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if not coalesce(public.has_admin_permission('payments.read'),false) then
  raise exception 'reconciliation_permission_required' using errcode='42501'; end if;
 select * into r from collect_security.reconciliation_reviews where id=p_review_id;
 if r.id is null then raise exception 'reconciliation_review_unavailable' using errcode='22023'; end if;
 select * into p from public.payments where id=r.payment_id;
 return (to_jsonb(r)-'proposed_session_id'-'approved_session_id')||jsonb_build_object(
  'payment_status',p.status,'collection_id',p.collection_id,'amount_rwf',p.amount_rwf,'currency',p.currency,
  'transaction_id',p.transaction_id,'provider_network',p.provider_network,
  'parsed_event_id',p.parsed_event_id,'payment_intent_id',p.payment_intent_id,
  'raw_sms_id',(select e.raw_sms_id from public.parsed_payment_events e where e.id=p.parsed_event_id),
  'receiver_routes',coalesce((select jsonb_agg(jsonb_build_object('id',rte.id,'network',rte.network,'is_active',rte.is_active) order by rte.id)
    from public.collection_receivers rte where rte.collection_id=p.collection_id and rte.receiver_user_id=p.receiver_user_id
      and rte.momo_number_hash=p.receiver_momo_number_hash and rte.network=p.provider_network),'[]'::jsonb),
  'receiver_user_id',p.receiver_user_id,'member_record_id',p.member_record_id,
  'audit',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'action',a.action,'actor_user_id',a.actor_user_id,
    'created_at',a.created_at,'metadata',a.metadata-'session_id') order by a.created_at,a.id)
    from public.audit_logs a where a.entity_id=p.id and a.action like 'reconciliation.%'
      and a.metadata->>'review_id'=r.id::text),'[]'::jsonb),
  'journals',coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'entry_type',j.entry_type,'amount_rwf',j.amount_rwf)
   order by j.created_at,j.id) from collect_hybrid.momo_journal_entries j where j.payment_id=p.id),'[]'::jsonb));
end $$;

revoke all on function public.propose_payment_reconciliation_v2(uuid,text,text,timestamptz,text),
 public.approve_payment_reconciliation_v2(uuid,text),public.authorize_reconciliation_finalization_v2(uuid),
 public.finalize_approved_reconciliation_v2(uuid),public.list_payment_reconciliations_v2(uuid,integer,integer),
 public.get_payment_reconciliation_v2(uuid) from public,anon,authenticated,service_role;
grant execute on function public.propose_payment_reconciliation_v2(uuid,text,text,timestamptz,text),
 public.approve_payment_reconciliation_v2(uuid,text),public.authorize_reconciliation_finalization_v2(uuid),
 public.list_payment_reconciliations_v2(uuid,integer,integer),public.get_payment_reconciliation_v2(uuid) to authenticated;
grant execute on function public.finalize_approved_reconciliation_v2(uuid) to service_role;
-- Preserve provider finality only behind the independently approved wrapper.
revoke execute on function public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text),
 public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text),
 public.reject_provider_payment(uuid,text,text) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
