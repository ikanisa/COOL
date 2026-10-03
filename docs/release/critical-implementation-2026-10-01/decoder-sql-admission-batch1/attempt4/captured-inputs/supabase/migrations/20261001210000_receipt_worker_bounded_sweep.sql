begin;

-- Query-cost maintenance only. This registry has exactly the historical
-- unhandled-backlog/budget-refusal source membership of the prior sweep.
-- Handling a later run never removes the original source from that history.
-- Acquire the scanner lock before producer table locks. Producers continue
-- to append independent work; they never acquire the scanner's queue rows.
select pg_advisory_xact_lock(hashtext('collect-receipt-exception-worker'));
lock table collect_receipt_operations.backlog_results,
 collect_ops.receipt_backlog_budget_deferrals in share row exclusive mode;

-- Refuse an unexpected predecessor before publishing any changed behavior.
do $$declare signature text;expected text;actual text;begin
 for signature,expected in select * from(values
  ('collect_ops.queue_receipt_exception_source()','8a1283f5172d8ce673aba5226244eb051789f050f07cad9b037039472cffec86'),
  ('public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamp with time zone)','aec5fa6d393896200e3f8dc5702b07923f26154048ea8ab9cb0ffd80cd411162'),
  ('collect_ops.receipt_exception_source(text,uuid)','ba8726ded737c014c802b34241b720dfc9a39ce6b4eaa91a9614120ae84820ad'),
  ('collect_ops.receipt_exception_quota_available(text,uuid)','72cdef85c2611a4e36107306dfe58a1740c3987aeb61e04a94469262bf738746')
 )as predecessors(signature,digest)loop
  select encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')into actual
   from pg_proc p where p.oid=to_regprocedure(signature);
  if actual is distinct from expected then
   raise exception 'receipt_worker_bounded_sweep_predecessor_unavailable'using errcode='55000';
  end if;
 end loop;
end$$;

create table collect_ops.receipt_backlog_sweep_sources(
 snapshot_id uuid primary key references collect_hybrid.momo_balance_snapshots(id)on delete restrict);
alter table collect_ops.receipt_backlog_sweep_sources enable row level security;
revoke all on collect_ops.receipt_backlog_sweep_sources from public,anon,authenticated,service_role;
create trigger retain_receipt_backlog_sweep_source before update or delete
 on collect_ops.receipt_backlog_sweep_sources for each row execute function collect_ops.immutable_evidence();
insert into collect_ops.receipt_backlog_sweep_sources(snapshot_id)
 select b.snapshot_id from collect_receipt_operations.backlog_results b where not b.business_handled
 union select b.snapshot_id from collect_ops.receipt_backlog_budget_deferrals b;

create index receipt_worker_jobs_latest on collect_ops.receipt_worker_jobs(created_at desc,request_id desc);
create index receipt_worker_receipts_latest on collect_ops.receipt_worker_receipts(recorded_at desc,request_id desc);
create index receipt_backlog_unhandled_source_latest on collect_receipt_operations.backlog_results(snapshot_id,recorded_at desc,run_id desc)where not business_handled;
create index receipt_backlog_handled_source_first on collect_receipt_operations.backlog_results(snapshot_id,recorded_at,run_id)where business_handled;
create index receipt_backlog_quota_source_latest on collect_receipt_operations.backlog_results(snapshot_id,recorded_at desc,run_id desc)where code='QUOTA_EXHAUSTED';
create index receipt_run_event_quota_source_latest on collect_receipt_operations.run_events(event_id,recorded_at desc,run_id desc)where code='QUOTA_EXHAUSTED';
create index receipt_backlog_budget_source_latest on collect_ops.receipt_backlog_budget_deferrals(snapshot_id,recorded_at desc,run_id desc);

-- Only these fragments change. CREATE OR REPLACE retains the existing OIDs,
-- security-definer owners, signatures and grants; no wire API is introduced.
do $$declare body text;needle text;replacement text;begin
 body:=pg_get_functiondef('collect_ops.queue_receipt_exception_source()'::regprocedure);
 needle:=$patch$ if tg_table_name in('backlog_results','receipt_backlog_budget_deferrals')then
  insert into collect_ops.receipt_exception_work$patch$;
 replacement:=$patch$ if tg_table_name in('backlog_results','receipt_backlog_budget_deferrals')then
  if tg_table_name='receipt_backlog_budget_deferrals'then
   insert into collect_ops.receipt_backlog_sweep_sources(snapshot_id)values(new.snapshot_id)on conflict(snapshot_id)do nothing;
  elsif not new.business_handled then
   insert into collect_ops.receipt_backlog_sweep_sources(snapshot_id)values(new.snapshot_id)on conflict(snapshot_id)do nothing;
  end if;
  insert into collect_ops.receipt_exception_work$patch$;
 if strpos(body,needle)=0 then raise exception 'receipt_worker_bounded_sweep_producer_unavailable'using errcode='55000';end if;
 execute replace(body,needle,replacement);

 body:=pg_get_functiondef('public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamptz)'::regprocedure);
 needle:=$patch$   for source in select distinct x.snapshot_id from(
    select b.snapshot_id from collect_receipt_operations.backlog_results b where not b.business_handled
    union all select b.snapshot_id from collect_ops.receipt_backlog_budget_deferrals b)x
    where p.last_id is null or x.snapshot_id>p.last_id order by x.snapshot_id limit p_limit loop$patch$;
 replacement:=$patch$   for source in select b.snapshot_id from collect_ops.receipt_backlog_sweep_sources b
    where b.snapshot_id>=coalesce(p.last_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and(p.last_id is null or b.snapshot_id>p.last_id)order by b.snapshot_id limit p_limit loop$patch$;
 if strpos(body,needle)=0 then raise exception 'receipt_worker_bounded_sweep_scanner_unavailable'using errcode='55000';end if;
 execute replace(body,needle,replacement);

 -- Each source-local evidence branch contributes only its exact winning row.
 -- The final two-row merge preserves the original timestamp/UUID tie rules.
 body:=pg_get_functiondef('collect_ops.receipt_exception_source(text,uuid)'::regprocedure);
 needle:=$patch$  select x.code into original from(
   select b.code,b.recorded_at,b.run_id from collect_receipt_operations.backlog_results b where b.snapshot_id=s.id and not b.business_handled
   union all select 'QUOTA_EXHAUSTED',b.recorded_at,b.run_id from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id=s.id)x order by x.recorded_at desc,x.run_id desc limit 1;$patch$;
 replacement:=$patch$  select x.code into original from(
   (select b.code,b.recorded_at,b.run_id from collect_receipt_operations.backlog_results b where b.snapshot_id=s.id and not b.business_handled order by b.recorded_at desc,b.run_id desc limit 1)
   union all(select 'QUOTA_EXHAUSTED',b.recorded_at,b.run_id from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id=s.id order by b.recorded_at desc,b.run_id desc limit 1))x order by x.recorded_at desc,x.run_id desc limit 1;$patch$;
 if strpos(body,needle)=0 then raise exception 'receipt_worker_bounded_sweep_source_unavailable'using errcode='55000';end if;
 execute replace(body,needle,replacement);

 body:=pg_get_functiondef('collect_ops.receipt_exception_quota_available(text,uuid)'::regprocedure);
 needle:=$patch$  select x.run_id into run from(
   select b.run_id,b.recorded_at from collect_receipt_operations.backlog_results b where b.snapshot_id=p_source and b.code='QUOTA_EXHAUSTED'
   union all select b.run_id,b.recorded_at from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id=p_source)x order by x.recorded_at desc,x.run_id desc limit 1;$patch$;
 replacement:=$patch$  select x.run_id into run from(
   (select b.run_id,b.recorded_at from collect_receipt_operations.backlog_results b where b.snapshot_id=p_source and b.code='QUOTA_EXHAUSTED'order by b.recorded_at desc,b.run_id desc limit 1)
   union all(select b.run_id,b.recorded_at from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id=p_source order by b.recorded_at desc,b.run_id desc limit 1))x order by x.recorded_at desc,x.run_id desc limit 1;$patch$;
 if strpos(body,needle)=0 then raise exception 'receipt_worker_bounded_sweep_quota_unavailable'using errcode='55000';end if;
 execute replace(body,needle,replacement);
end$$;

commit;
