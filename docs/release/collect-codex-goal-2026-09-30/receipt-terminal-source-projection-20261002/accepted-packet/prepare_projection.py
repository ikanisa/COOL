#!/usr/bin/env python3
"""Exact predecessor-bound additive source maintenance; staged outputs only."""
import hashlib,json,pathlib,re
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
STAGE=pathlib.Path(__file__).resolve().parent
sha=lambda x:hashlib.sha256(x).hexdigest()
bindings={};guards=[]
def read(name):
 p=ROOT/'supabase/migrations'/name;b=p.read_bytes();bindings[str(p.relative_to(ROOT))]=sha(b)
 d=STAGE/'originals'/p.relative_to(ROOT);d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(b);return b.decode()
def definition(text,name):
 m=re.search(r'create(?: or replace)? function '+re.escape(name)+r'\([\s\S]*?as (\$[A-Za-z_0-9]*\$)([\s\S]*?)\1;',text,re.I)
 assert m,name;return m.group(0),m.group(2)
base=read('20261001140000_receipt_deferral_exceptions.sql');bounded=read('20261001210000_receipt_worker_bounded_sweep.sql')
scanner,body=definition(base,'public.process_receipt_deferral_exceptions_v1')
queue,queue_body=definition(base,'collect_ops.queue_receipt_exception_source')
for signature in ['collect_ops.queue_receipt_exception_source()', 'public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamptz)']:
 m=re.search(r"body:=pg_get_functiondef\('"+re.escape(signature)+r"'::regprocedure\);([\s\S]*?)execute replace\(body,needle,replacement\);",bounded)
 assert m,signature
 old=re.search(r'needle:=\$patch\$([\s\S]*?)\$patch\$;',m.group(1)).group(1)
 new=re.search(r'replacement:=\$patch\$([\s\S]*?)\$patch\$;',m.group(1)).group(1)
 if signature.startswith('public.'):
  assert scanner.count(old)==1;scanner=scanner.replace(old,new);body=definition(scanner,'public.process_receipt_deferral_exceptions_v1')[1]
 else:
  assert queue.count(old)==1;queue=queue.replace(old,new);queue_body=definition(queue,'collect_ops.queue_receipt_exception_source')[1]
guards += [('public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamp with time zone)',sha(body.encode())),('collect_ops.queue_receipt_exception_source()',sha(queue_body.encode()))]
for filename,pairs in [
 ('20261002020000_receipt_source_busy_deferral.sql',[('collect_receipt_operations.ensure_snapshot','collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)'),('collect_ops.receipt_exception_source','collect_ops.receipt_exception_source(text,uuid)')]),
 ('20261002030000_receipt_operational_telemetry.sql',[('collect_ops.refresh_source','collect_ops.refresh_source(text,uuid)'),('collect_ops.observe','collect_ops.observe(text,uuid,text[],jsonb)'),('collect_receipt_telemetry.publish','collect_receipt_telemetry.publish(collect_receipt_operations.policy,timestamptz,jsonb)')]),
 ('20261002010000_sms_receipt_language_selection.sql',[('collect_receipt_policy.content_is_valid','collect_receipt_policy.content_is_valid(collect_hybrid.sms_notification_outbox)')]),
 ('20261002040000_receipt_unarmed_closure.sql',[('collect_receipt_successors.fence_transport_insert','collect_receipt_successors.fence_transport_insert()'),('collect_receipt_successors.protect_closed_root','collect_receipt_successors.protect_closed_root()')])]:
 text=read(filename)
 for name,signature in pairs:guards.append((signature,sha(definition(text,name)[1].encode())))
lifecycle=read('20261001120000_operational_exception_lifecycle.sql')
for name,signature in [('public.process_exception_escalations_v1','public.process_exception_escalations_v1(integer)'),('public.admin_read_exception_escalation_v1','public.admin_read_exception_escalation_v1(uuid)'),('collect_ops.protect_escalation','collect_ops.protect_escalation()')]:
 guards.append((signature,sha(definition(lifecycle,name)[1].encode())))
old_event="""   for source in select d.event_id from collect_receipt_operations.event_deferrals d
    where(p.last_id is null or d.event_id>p.last_id)order by d.event_id limit p_limit loop"""
new_event="""   for source in select l.source_id from collect_receipt_source_projection.live l
    where l.source_kind='receipt_event'and l.source_id>=coalesce(p.last_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and(p.last_id is null or l.source_id>p.last_id)order by l.source_id limit p_limit loop"""
old_backlog="""   for source in select b.snapshot_id from collect_ops.receipt_backlog_sweep_sources b
    where b.snapshot_id>=coalesce(p.last_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and(p.last_id is null or b.snapshot_id>p.last_id)order by b.snapshot_id limit p_limit loop"""
new_backlog=new_event.replace("'receipt_event'","'receipt_backlog'")
old_refresh="""   work_outcome:='refreshed';begin"""
new_refresh="""   -- Pending work is independent of the sweep cursor and re-establishes exact
   -- membership after any producer/retirement fast-path race. A contended
   -- publication leaves this original row pending for a later bounded scan.
   if not collect_receipt_source_projection.ensure_work_membership(w.id)then continue;end if;
   work_outcome:='refreshed';begin"""
old_processed="""   update collect_ops.receipt_exception_work set processed_at=clock_timestamp(),outcome=work_outcome,processed_request_id=p_request_id where id=w.id;processed:=processed+1;"""
new_processed=old_processed+"""
   if work_outcome='refreshed'then
    perform collect_receipt_source_projection.try_retire_source(w.source_kind,w.source_id,p_request_id,w.id);
   end if;"""
for old,new in [(old_event,new_event),(old_backlog,new_backlog),(old_refresh,new_refresh),(old_processed,new_processed)]:
 assert scanner.count(old)==1,old;scanner=scanner.replace(old,new)
scanner=re.sub(r'^create function','create or replace function',scanner,count=1)
guard="""begin;
select pg_advisory_xact_lock(hashtext('collect-receipt-exception-worker'));
select pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
do $guard$declare expected record;begin
 for expected in select * from(values
"""+',\n'.join(" ('"+s+"','"+d+"')"for s,d in guards)+"""
 )v(signature,body_sha256)loop
  if to_regprocedure(expected.signature)is null or(select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc
   where oid=to_regprocedure(expected.signature))is distinct from expected.body_sha256 then
   raise exception 'receipt_source_projection_predecessor_drift:%',expected.signature using errcode='55000';end if;
 end loop;
 if(select pg_get_constraintdef(oid)from pg_constraint where conrelid='collect_ops.receipt_exception_work'::regclass and conname='receipt_exception_work_source_kind_check'and convalidated)is distinct from
  $expected$CHECK ((source_kind = ANY (ARRAY['receipt_event'::text, 'receipt_backlog'::text])))$expected$then
  raise exception 'receipt_source_projection_constraint_drift'using errcode='55000';end if;
 if not exists(select 1 from pg_constraint c where c.conrelid='collect_ops.exception_inbox_reads'::regclass and c.contype='f'
  and c.confrelid='collect_ops.exception_inbox_deliveries'::regclass and c.convalidated and c.confdeltype='r'
  and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='escalation_id')]::smallint[]
  and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='escalation_id')]::smallint[])
  or not exists(select 1 from pg_constraint c where c.conrelid='collect_ops.exception_inbox_deliveries'::regclass and c.contype='f'
   and c.confrelid='collect_ops.exception_escalations'::regclass and c.convalidated and c.confdeltype='r'
   and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='escalation_id')]::smallint[]
   and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='id')]::smallint[])then
  raise exception 'receipt_source_projection_inbox_fk_drift'using errcode='55000';end if;
 if exists(select 1 from pg_class c cross join(values('anon'),('authenticated'),('service_role'))r(name)
  where c.oid in('collect_ops.receipt_exception_work'::regclass,'collect_ops.exception_inbox_deliveries'::regclass,
   'collect_ops.exception_inbox_reads'::regclass,'collect_ops.exception_escalations'::regclass,'collect_ops.exception_workflows'::regclass)
   and(not c.relrowsecurity or has_table_privilege(r.name,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
    or has_any_column_privilege(r.name,c.oid,'SELECT,INSERT,UPDATE,REFERENCES')))then
  raise exception 'receipt_source_projection_original_acl_drift'using errcode='55000';end if;
end $guard$;
"""
template=STAGE/'source_projection.sql.in';template_body=template.read_bytes();bindings['stage/source_projection.sql.in']=sha(template_body)
sql=guard+template_body.decode().replace('@SCANNER_PREDECESSOR@',guards[0][1])+'\n'+scanner+"\nnotify pgrst,'reload schema';\ncommit;\n"
out=STAGE/'promote/supabase/migrations/20261002050000_receipt_terminal_source_projection.sql';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(sql)
(STAGE/'predecessor-bindings.json').write_text(json.dumps(dict(inputs=bindings,guards=guards,migration_sha256=sha(sql.encode()),scanner_predecessor_sha256=guards[0][1],scanner_final_sha256=sha(definition(scanner,'public.process_receipt_deferral_exceptions_v1')[1].encode())),indent=2)+'\n')
print(json.dumps(dict(migration_sha256=sha(sql.encode()),guards=len(guards),private_tables=6,old_functions_changed=1)))
