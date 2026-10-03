begin;

-- Intake only. No erasure, access restriction, Auth removal, retention approval,
-- principal rewrite, provider operation or completion authority is introduced.
select pg_advisory_xact_lock(193517,141);
create schema collect_privacy;
revoke all on schema collect_privacy from public,anon,authenticated,service_role;

create table collect_privacy.intake_requests(
 request_id uuid primary key references public.mobile_account_deletion_requests(id) on delete restrict,
 subject_id uuid not null unique references public.profiles(id) on delete restrict,
 originating_session_id uuid not null,
 input_sha256 text not null check(input_sha256~'^[a-f0-9]{64}$'),
 reason_supplied boolean not null,
 accepted_at timestamptz not null check(isfinite(accepted_at))
);
create table collect_privacy.intake_submissions(
 submission_id uuid primary key,
 request_id uuid not null references collect_privacy.intake_requests(request_id) on delete restrict,
 originating_session_id uuid not null,
 input_sha256 text not null check(input_sha256~'^[a-f0-9]{64}$'),
 recorded_at timestamptz not null check(isfinite(recorded_at))
);
create index privacy_intake_submission_request on collect_privacy.intake_submissions(request_id);

create function collect_privacy.immutable_intake() returns trigger
language plpgsql set search_path='' as $$begin
 raise exception 'privacy_intake_evidence_immutable' using errcode='55000';
end$$;
do $$declare t text;begin
 foreach t in array array['intake_requests','intake_submissions']loop
  execute format('alter table collect_privacy.%I enable row level security',t);
  execute format('revoke all on collect_privacy.%I from public,anon,authenticated,service_role',t);
  execute format('create trigger immutable_privacy_intake before update or delete on collect_privacy.%I for each row execute function collect_privacy.immutable_intake()',t);
  execute format('create trigger immutable_privacy_intake_truncate before truncate on collect_privacy.%I for each statement execute function collect_privacy.immutable_intake()',t);
 end loop;
end$$;

create function collect_privacy.require_actor(p_fresh boolean) returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare sid uuid; s auth.sessions; jwt_exp text:=auth.jwt()->>'exp';begin
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'privacy_request_snapshot_retry' using errcode='40001';end if;
 if p_fresh is null or current_setting('role',true) is distinct from 'authenticated'
  or auth.role() is distinct from 'authenticated' or auth.uid() is null then
  raise exception 'privacy_request_session_required' using errcode='42501';end if;
 -- Use the existing global Auth-revocation gate before user/session/profile
 -- row locks. An actual logout/ban cannot win between validation and commit.
 perform public._lock_notification_session_gate();
 perform 1 from auth.users where id=auth.uid() for share;
 if not found then raise exception 'privacy_request_session_required' using errcode='42501';end if;
 begin sid:=public._lock_notification_registration_session();
 exception when sqlstate '42501'then
  raise exception 'privacy_request_session_required' using errcode='42501';end;
 select * into s from auth.sessions where id=sid and user_id=auth.uid() for share;
 if jsonb_typeof(auth.jwt()->'exp') is distinct from 'number'
  or jwt_exp is null or jwt_exp!~'^[0-9]{1,12}$'then
  raise exception 'privacy_request_session_required' using errcode='42501';end if;
 if jwt_exp::bigint<=extract(epoch from clock_timestamp()) or jwt_exp::bigint>253402300799
  or s.id is null or s.created_at is null or not isfinite(s.created_at) or s.created_at>clock_timestamp()
  or(s.not_after is not null and(not isfinite(s.not_after)or s.not_after<=clock_timestamp()))then
  raise exception 'privacy_request_session_required' using errcode='42501';end if;
 -- Same ten-minute fresh-session boundary as maintained fresh Auth recovery;
 -- ordinary members do not inherit its platform-owner/roster permissions.
 if p_fresh and s.created_at<clock_timestamp()-interval '10 minutes'then
  raise exception 'privacy_request_fresh_session_required' using errcode='42501';end if;
 perform 1 from public.profiles where id=auth.uid() for share;
 if not found then raise exception 'privacy_request_session_required' using errcode='42501';end if;
 return sid;
end$$;

create function collect_privacy.clean_reason(p_reason text) returns text
language plpgsql immutable set search_path='' as $$begin
 if p_reason is null then return null;end if;
 if char_length(p_reason)>500 or octet_length(p_reason)>2000 or p_reason~'[[:cntrl:]]'then
  raise exception 'privacy_request_reason_invalid' using errcode='22023';end if;
 return nullif(btrim(p_reason),'');
end$$;

create function collect_privacy.receipt(p collect_privacy.intake_requests) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('contract_version',1,'request_id',p.request_id,
  'scope','own_account_eligible_data','state','pending_review',
  'reason_code','account_deletion_requested','reason_supplied',p.reason_supplied,
  'accepted_at',to_char(p.accepted_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'policy_review_pending',true,'subject_scope_review_pending',true,
  'erasure_completed',false,'account_access_restricted',false,'auth_removed',false,
  'retention_approval_granted',false,'processor_operation_started',false)
$$;

create function collect_privacy.submit(p_submission uuid,p_reason text,p_typed boolean) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare sid uuid; subject uuid:=auth.uid(); clean text; fingerprint text;
 existing collect_privacy.intake_requests; prior collect_privacy.intake_submissions;
 legacy_id uuid; reused boolean:=false; at timestamptz;begin
 sid:=collect_privacy.require_actor(true);
 if p_typed is null or(p_typed and p_submission is null)or(not p_typed and p_submission is not null)then
  raise exception 'privacy_request_invalid' using errcode='22023';end if;
 clean:=collect_privacy.clean_reason(p_reason);
 fingerprint:=encode(extensions.digest(jsonb_build_object('contract_version',1,
  'scope','own_account_eligible_data','subject_id',subject,'reason',clean)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-privacy-subject:'||subject::text,0));
 if p_typed then
  perform pg_advisory_xact_lock(hashtextextended('collect-privacy-submission:'||p_submission::text,0));
 end if;
 -- Clock predicates are checked again after a real subject/request wait.
 perform collect_privacy.require_actor(true);
 if p_typed then
  select * into prior from collect_privacy.intake_submissions where submission_id=p_submission;
  if prior.submission_id is not null then
   select * into existing from collect_privacy.intake_requests where request_id=prior.request_id;
   if existing.subject_id is distinct from subject or prior.input_sha256<>fingerprint then
    raise exception 'privacy_request_conflict' using errcode='22023';end if;
   return collect_privacy.receipt(existing)||jsonb_build_object('submission_id',p_submission,
    'replay',true,'equivalent_active_request',true);
  end if;
 end if;
 select * into existing from collect_privacy.intake_requests where subject_id=subject;
 if existing.request_id is not null then
  if existing.input_sha256<>fingerprint then
   raise exception 'privacy_request_active_scope_conflict' using errcode='22023';end if;
  reused:=true;
 else
  -- Reuse an equivalent historical pending request without inventing a
  -- completed outcome, changing its reason/status or copying unbounded text.
  select id into legacy_id from public.mobile_account_deletion_requests
   where user_id=subject and status in('pending','in_review')
    and reason is not distinct from clean
    and char_length(coalesce(reason,''))<=500 and octet_length(coalesce(reason,''))<=2000
   order by created_at,id limit 1 for update;
  reused:=legacy_id is not null;
  if legacy_id is null then
   legacy_id:=case when p_typed then p_submission else gen_random_uuid()end;
   if exists(select 1 from public.mobile_account_deletion_requests where id=legacy_id)then
    raise exception 'privacy_request_conflict' using errcode='22023';end if;
   insert into public.mobile_account_deletion_requests(id,user_id,reason)values(legacy_id,subject,clean);
   insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(subject,'mobile.account_deletion_requested','profile',subject,jsonb_build_object('request_id',legacy_id));
  end if;
  at:=clock_timestamp();
  insert into collect_privacy.intake_requests values(legacy_id,subject,sid,fingerprint,clean is not null,at)
   returning * into existing;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
   values(subject,'mobile.privacy_request_intake_accepted','profile',subject,
    jsonb_build_object('request_id',legacy_id,'scope','own_account_eligible_data','state','pending_review',
     'policy_review_pending',true,'subject_scope_review_pending',true));
 end if;
 if p_typed then
  -- No alternate UUID may claim an unrelated retained legacy request identity.
  if exists(select 1 from public.mobile_account_deletion_requests where id=p_submission and id<>existing.request_id)then
   raise exception 'privacy_request_conflict' using errcode='22023';end if;
  -- Bound alternate client UUIDs; the legacy adapter never allocates aliases.
  if(select count(*)from collect_privacy.intake_submissions where request_id=existing.request_id)>=32 then
   raise exception 'privacy_request_submission_limit' using errcode='54000';end if;
  insert into collect_privacy.intake_submissions values(p_submission,existing.request_id,sid,fingerprint,clock_timestamp());
 end if;
 return collect_privacy.receipt(existing)||jsonb_build_object('submission_id',p_submission,
  'replay',false,'equivalent_active_request',reused);
end$$;

create function public.request_account_deletion_v1(p_request_id uuid,p_reason text default null) returns jsonb
language plpgsql volatile security definer set search_path='' as $$begin
 return collect_privacy.submit(p_request_id,p_reason,true);
end$$;
create or replace function public.request_account_deletion(request_reason text default null) returns uuid
language plpgsql volatile security definer set search_path='' as $$begin
 return(collect_privacy.submit(null,request_reason,false)->>'request_id')::uuid;
end$$;
create function public.get_account_deletion_request_status_v1(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare r collect_privacy.intake_requests;begin
 perform collect_privacy.require_actor(false);
 if p_request_id is null then raise exception 'privacy_request_unavailable' using errcode='42501';end if;
 select * into r from collect_privacy.intake_requests i
  where i.subject_id=auth.uid()and(i.request_id=p_request_id or exists(
   select 1 from collect_privacy.intake_submissions s where s.request_id=i.request_id and s.submission_id=p_request_id));
 perform collect_privacy.require_actor(false);
 if r.request_id is null then raise exception 'privacy_request_unavailable' using errcode='42501';end if;
 return collect_privacy.receipt(r);
end$$;

create function public._account_deletion_read_is_live_v1() returns boolean
language plpgsql volatile security definer set search_path='' as $$begin
 perform collect_privacy.require_actor(false);return true;
exception when sqlstate '42501'then return false;
end$$;
-- Preserve the established support/Admin predicate and SELECT inventory,
-- while binding both own and legitimate Admin reads to an actual live SID.
drop policy "account deletion own read" on public.mobile_account_deletion_requests;
create policy "account deletion own read" on public.mobile_account_deletion_requests
 for select to authenticated using((select public._account_deletion_read_is_live_v1())
  and(user_id=(select auth.uid())or public.is_platform_admin((select auth.uid()))));
revoke all on public.mobile_account_deletion_requests from public,anon,authenticated,service_role;
grant select on public.mobile_account_deletion_requests to authenticated;
revoke all on all functions in schema collect_privacy from public,anon,authenticated,service_role;
revoke all on function public.request_account_deletion(text),public.request_account_deletion_v1(uuid,text),
 public.get_account_deletion_request_status_v1(uuid),public._account_deletion_read_is_live_v1()
 from public,anon,authenticated,service_role;
grant execute on function public.request_account_deletion(text),public.request_account_deletion_v1(uuid,text),
 public.get_account_deletion_request_status_v1(uuid),public._account_deletion_read_is_live_v1() to authenticated;

commit;
