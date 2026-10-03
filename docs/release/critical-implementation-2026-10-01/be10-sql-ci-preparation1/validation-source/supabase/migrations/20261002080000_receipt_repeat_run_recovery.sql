begin;
set local lock_timeout='2s';
select pg_advisory_xact_lock(hashtext('collect-receipt-repeat-run-recovery'));
lock table collect_receipt_operations.requests,collect_receipt_operations.reservations,collect_receipt_operations.backlog_results,collect_ops.receipt_backlog_budget_deferrals in share row exclusive mode;
do $guard$declare e record;begin
 for e in select *from(values
('public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)','976035f110ddf0bc66db9740548cf5b596c0a4a4180d7a3d5dac727515b6d6bd'), 
('collect_ops.capture_receipt_backlog_budget_refusal()','81b2a894c03d74e6394b893da730d7b405c0d65ded6ac8adb57e2c0e2a4c4190'), 
('public.admin_list_receipt_operation_evidence_v1(uuid,text,integer,timestamptz,text)','e3aba82f32570be3d8987e75f3ac81113497af8165c46208c4e184558f96cbe9'), 
('collect_receipt_operations.require_run(uuid,bigint,uuid)','ba72bca1a106782ba84cc7a8828c948f6839c9f3d4b55b8f830b9e914d023f9a'), 
('collect_receipt_operations.reserve_budget(uuid,bigint,uuid,uuid,uuid,integer,integer)','31c2b94098a18086c9cc851804ce1b69bb3d7939bb3c41140c0caaa4197ef7c3'), 
('collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)','12912903ceedef3bfe389a0398d69c7e19a109b70cf4f72a57b4e839e2c4bd94')
 )v(signature,body_sha256)loop
  if to_regprocedure(e.signature)is null or(select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc where oid=to_regprocedure(e.signature))is distinct from e.body_sha256 then
   raise exception 'receipt_repeat_run_predecessor_drift:%',e.signature using errcode='55000';end if;
 end loop;
 if not exists(select 1 from pg_trigger where tgrelid='collect_receipt_operations.requests'::regclass and tgname='receipt_backlog_budget_refusal'and tgfoid='collect_ops.capture_receipt_backlog_budget_refusal()'::regprocedure and tgtype=5 and tgenabled='O'and tgnargs=0 and tgconstraint=0)
 or not exists(select 1 from pg_trigger where tgrelid='collect_ops.receipt_backlog_budget_deferrals'::regclass and tgname='receipt_exception_budget'and tgfoid='collect_ops.queue_receipt_exception_source()'::regprocedure and tgtype=5 and tgenabled='O'and tgnargs=0 and tgconstraint=0)
 then raise exception 'receipt_repeat_run_trigger_drift'using errcode='55000';end if;
end$guard$;

-- New immutable provenance; no legacy reservation or outcome is moved/backfilled.
create table collect_receipt_operations.backlog_attempts(
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 snapshot_id uuid not null references collect_hybrid.momo_balance_snapshots(id)on delete restrict,
 reservation_id uuid not null unique references collect_receipt_operations.reservations(id)on delete restrict,
 request_id uuid not null references collect_receipt_operations.requests(request_id)on delete restrict deferrable initially deferred,
 recorded_at timestamptz not null check(isfinite(recorded_at)),primary key(run_id,snapshot_id),
 foreign key(run_id,snapshot_id)references collect_receipt_operations.backlog_results(run_id,snapshot_id)on delete restrict);
alter table collect_receipt_operations.backlog_attempts enable row level security;
revoke all on collect_receipt_operations.backlog_attempts from public,anon,authenticated,service_role;
create index receipt_backlog_attempt_request on collect_receipt_operations.backlog_attempts(request_id,run_id,snapshot_id);
create index receipt_backlog_first_handled on collect_receipt_operations.backlog_results(snapshot_id,recorded_at,run_id)where business_handled;
create function collect_receipt_operations.backlog_inspection_id(p_run uuid,p_snapshot uuid)returns uuid
language sql immutable strict set search_path=''as $$select extensions.uuid_generate_v5('c1c49625-b8d9-4278-998e-6758a0b945d4'::uuid,p_run::text||':'||p_snapshot::text)$$;
create function collect_receipt_operations.backlog_attempt_immutable()returns trigger
language plpgsql set search_path=''as $$begin raise exception 'receipt_backlog_attempt_immutable'using errcode='42501';end$$;
create trigger receipt_backlog_attempt_retained before update or delete on collect_receipt_operations.backlog_attempts for each row execute function collect_receipt_operations.backlog_attempt_immutable();
create trigger receipt_backlog_attempt_no_truncate before truncate on collect_receipt_operations.backlog_attempts for each statement execute function collect_receipt_operations.backlog_attempt_immutable();
create function collect_receipt_operations.validate_backlog_attempt()returns trigger
language plpgsql security definer set search_path=''as $$
declare request collect_receipt_operations.requests;run collect_receipt_operations.runs;charge collect_receipt_operations.reservations;
 source collect_hybrid.momo_balance_snapshots;outcome collect_receipt_operations.backlog_results;n integer;done integer;deferred integer;begin
 select *into request from collect_receipt_operations.requests where request_id=new.request_id;
 select *into run from collect_receipt_operations.runs where id=new.run_id;
 select *into charge from collect_receipt_operations.reservations where id=new.reservation_id;
 select *into source from collect_hybrid.momo_balance_snapshots where id=new.snapshot_id;
 select *into outcome from collect_receipt_operations.backlog_results where run_id=new.run_id and snapshot_id=new.snapshot_id;
 if request.request_id is null or run.id is null or charge.id is null or source.id is null or outcome.snapshot_id is null
 or request.action<>'reconcile_backlog'or request.principal_id<>run.principal_id
 or request.input->>'run_id'is distinct from run.id::text or request.input->>'fence_version'is distinct from run.fence_version::text
 or request.result->>'run_id'is distinct from run.id::text or request.result->>'fence_version'is distinct from run.fence_version::text
 or charge.run_id<>run.id or charge.fence_version<>run.fence_version or charge.collection_id<>source.collection_id
 or not charge.collection_id=any(run.collection_ids)or charge.device_id is distinct from run.device_id
 or charge.actions<>1 or charge.sms_segments<>0 or source.event_type<>'receipt'
 or new.reservation_id<>collect_receipt_operations.backlog_inspection_id(run.id,source.id)
 or new.recorded_at<charge.recorded_at or new.recorded_at<outcome.recorded_at or new.recorded_at>request.recorded_at
 then raise exception 'receipt_backlog_attempt_provenance_invalid'using errcode='23514';end if;
 -- Probe at most26 mapped results; the public batch contract permits at most25.
 select count(*),count(*)filter(where business_handled),count(*)filter(where not business_handled)into n,done,deferred
 from(select b.business_handled from collect_receipt_operations.backlog_attempts a join collect_receipt_operations.backlog_results b
  on b.run_id=a.run_id and b.snapshot_id=a.snapshot_id where a.request_id=new.request_id limit 26)bounded;
 if n>25 or n is distinct from(request.result->>'examined')::integer
 or done is distinct from(request.result->>'handled')::integer or deferred is distinct from(request.result->>'deferred')::integer
 or n>(request.input->>'limit')::integer then raise exception 'receipt_backlog_attempt_counts_invalid'using errcode='23514';end if;
 return new;end$$;
create constraint trigger receipt_backlog_attempt_provenance after insert on collect_receipt_operations.backlog_attempts deferrable initially deferred for each row execute function collect_receipt_operations.validate_backlog_attempt();
create function collect_receipt_operations.backlog_reservation_snapshot(p_reservation uuid,p_run uuid)returns uuid
language sql stable set search_path=''as $$select s.id from collect_hybrid.momo_balance_snapshots s
 where s.id=coalesce((select a.snapshot_id from collect_receipt_operations.backlog_attempts a where a.reservation_id=p_reservation and a.run_id=p_run),p_reservation)
 and collect_operator_audit.exception_scope_v2('receipt_backlog',s.id)$$;
revoke all on function collect_receipt_operations.backlog_inspection_id(uuid,uuid),collect_receipt_operations.backlog_attempt_immutable(),collect_receipt_operations.validate_backlog_attempt(),collect_receipt_operations.backlog_reservation_snapshot(uuid,uuid)from public,anon,authenticated,service_role;

do $patch$declare body text;needle text:=$old$snapshot collect_hybrid.momo_balance_snapshots;v_payment_id uuid;$old$;replacement text:=$new$snapshot collect_hybrid.momo_balance_snapshots;backlog_reservation uuid;backlog_refused_snapshot uuid;v_payment_id uuid;$new$;begin
 body:=pg_get_functiondef('public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)'::regprocedure);
 if(length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'receipt_repeat_run_patch_drift'using errcode='55000';end if;
 execute replace(body,needle,replacement);end$patch$;
do $patch$declare body text;needle text:=$old$  elsif p_action='reconcile_backlog'then
   perform collect_gateway.payload_keys(p_payload,array['run_id','fence_version','limit']);lim:=collect_gateway.payload_int(p_payload,'limit',1,25);
   if p.catchup_enabled and r.mode in('Live','Live-limited')then
    for snapshot in select s.* from collect_hybrid.momo_balance_snapshots s
     where s.event_type='receipt'and s.collection_id=any(r.collection_ids)and s.captured_at>=clock_timestamp()-make_interval(hours=>p.catchup_hours)
     and not exists(select 1 from collect_hybrid.sms_notification_outbox o where o.payment_id=s.payment_id and o.template_key='buri_munsi.payment_received')
     and not exists(select 1 from collect_receipt_operations.backlog_results b where b.run_id=r.id and b.snapshot_id=s.id)
     order by s.captured_at,s.id limit lim loop
     if not collect_receipt_operations.reserve_budget(r.id,r.fence_version,snapshot.id,snapshot.collection_id,r.device_id,1,0)then exit;end if;
     row:=collect_receipt_operations.ensure_snapshot(snapshot.id,true);examined:=examined+1;handled:=(row->>'business_handled')::boolean;
     if handled then done:=done+1;else deferred:=deferred+1;end if;
     insert into collect_receipt_operations.backlog_results values(r.id,snapshot.id,row->>'code',handled,(row->>'receipt_id')::uuid,clock_timestamp());
    end loop;
   end if;result:=base||jsonb_build_object('examined',examined,'handled',done,'deferred',deferred);
$old$;replacement text:=$new$  elsif p_action='reconcile_backlog'then
   perform collect_gateway.payload_keys(p_payload,array['run_id','fence_version','limit']);lim:=collect_gateway.payload_int(p_payload,'limit',1,25);
   if p.catchup_enabled and r.mode in('Live','Live-limited')then
    for snapshot in select s.* from collect_hybrid.momo_balance_snapshots s
     where s.event_type='receipt'and s.collection_id=any(r.collection_ids)and s.captured_at>=clock_timestamp()-make_interval(hours=>p.catchup_hours)
     and not exists(select 1 from collect_hybrid.sms_notification_outbox o where o.payment_id=s.payment_id and o.template_key='buri_munsi.payment_received')
     and not exists(select 1 from collect_receipt_operations.backlog_results b where b.run_id=r.id and b.snapshot_id=s.id)
     and not exists(select 1 from collect_receipt_operations.backlog_results b where b.snapshot_id=s.id and b.business_handled)
     order by s.captured_at,s.id limit lim loop
     backlog_reservation:=collect_receipt_operations.backlog_inspection_id(r.id,snapshot.id);
     -- Refuse unrelated/colliding charges and inconsistent legacy same-run
     -- charges; never adopt, release, move or recharge an unknown old attempt.
     if exists(select 1 from collect_receipt_operations.reservations where id=backlog_reservation)
      or exists(select 1 from collect_receipt_operations.reservations where id=snapshot.id and run_id=r.id)then
      raise exception 'operations_budget_conflict'using errcode='22023';end if;
     if not collect_receipt_operations.reserve_budget(r.id,r.fence_version,backlog_reservation,snapshot.collection_id,r.device_id,1,0)then
      backlog_refused_snapshot:=snapshot.id;exit;end if;
     row:=collect_receipt_operations.ensure_snapshot(snapshot.id,true);examined:=examined+1;handled:=(row->>'business_handled')::boolean;
     if handled then done:=done+1;else deferred:=deferred+1;end if;
     insert into collect_receipt_operations.backlog_results values(r.id,snapshot.id,row->>'code',handled,(row->>'receipt_id')::uuid,clock_timestamp());
     insert into collect_receipt_operations.backlog_attempts values(r.id,snapshot.id,backlog_reservation,p_request_id,clock_timestamp());
    end loop;
   end if;result:=base||jsonb_build_object('examined',examined,'handled',done,'deferred',deferred);
$new$;begin
 body:=pg_get_functiondef('public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)'::regprocedure);
 if(length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'receipt_repeat_run_patch_drift'using errcode='55000';end if;
 execute replace(body,needle,replacement);end$patch$;
do $patch$declare body text;needle text:=$old$ insert into collect_receipt_operations.requests values(p_request_id,p_principal_id,p_action,p_request_sha256,p_payload,p_issued_at,clock_timestamp(),result);$old$;replacement text:=$new$ insert into collect_receipt_operations.requests values(p_request_id,p_principal_id,p_action,p_request_sha256,p_payload,p_issued_at,clock_timestamp(),result);
 if backlog_refused_snapshot is not null then
  insert into collect_ops.receipt_backlog_budget_deferrals(request_id,run_id,snapshot_id)values(p_request_id,r.id,backlog_refused_snapshot);end if;$new$;begin
 body:=pg_get_functiondef('public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)'::regprocedure);
 if(length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'receipt_repeat_run_patch_drift'using errcode='55000';end if;
 execute replace(body,needle,replacement);end$patch$;
do $patch$declare body text;needle text:=$old$
declare r collect_receipt_operations.runs;p collect_receipt_operations.policy;s collect_hybrid.momo_balance_snapshots;begin
 if new.action<>'reconcile_backlog'then return new;end if;
 r:=collect_receipt_operations.require_run((new.input->>'run_id')::uuid,(new.input->>'fence_version')::bigint,new.principal_id);
 select * into p from collect_receipt_operations.policy where singleton;
 if p.catchup_enabled and r.mode in('Live','Live-limited')and(new.result->>'examined')::integer<(new.input->>'limit')::integer then
  select * into s from collect_hybrid.momo_balance_snapshots snapshot
   where snapshot.event_type='receipt'and snapshot.collection_id=any(r.collection_ids)
    and snapshot.captured_at>=clock_timestamp()-make_interval(hours=>p.catchup_hours)
    and not exists(select 1 from collect_hybrid.sms_notification_outbox o where o.payment_id=snapshot.payment_id and o.template_key='buri_munsi.payment_received')
    and not exists(select 1 from collect_receipt_operations.backlog_results b where b.run_id=r.id and b.snapshot_id=snapshot.id)
   order by snapshot.captured_at,snapshot.id limit 1;
  if s.id is not null and not collect_ops.receipt_exception_run_budget_available(r.id,s.collection_id)then
   insert into collect_ops.receipt_backlog_budget_deferrals(request_id,run_id,snapshot_id)values(new.request_id,r.id,s.id);
  end if;
 end if;return new;end$old$;replacement text:=$new$
declare r collect_receipt_operations.runs;begin
 if new.action<>'reconcile_backlog'then return new;end if;
 -- Keep the original unconditional final current lease/policy/principal guard.
 -- The exact reserve_budget false candidate is inserted by the producer after
 -- its original request row exists; no later-clock/four-action-cap inference.
 r:=collect_receipt_operations.require_run((new.input->>'run_id')::uuid,(new.input->>'fence_version')::bigint,new.principal_id);
 return new;end$new$;begin
 body:=pg_get_functiondef('collect_ops.capture_receipt_backlog_budget_refusal()'::regprocedure);
 if(length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'receipt_repeat_run_patch_drift'using errcode='55000';end if;
 execute replace(body,needle,replacement);end$patch$;
do $patch$declare body text;needle text:=$old$case when exists(select 1 from collect_hybrid.momo_balance_snapshots s where s.id=shown.id and collect_operator_audit.exception_scope_v2('receipt_backlog',s.id))then shown.id end$old$;replacement text:=$new$collect_receipt_operations.backlog_reservation_snapshot(shown.id,shown.run_id)$new$;begin
 body:=pg_get_functiondef('public.admin_list_receipt_operation_evidence_v1(uuid,text,integer,timestamptz,text)'::regprocedure);
 if(length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'receipt_repeat_run_patch_drift'using errcode='55000';end if;
 execute replace(body,needle,replacement);end$patch$;
commit;
