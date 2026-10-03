#!/usr/bin/env python3
"""Narrow affected v2 read-plan/RPC comparison; no whole feature-matrix rerun.

Captures helper, row-free schema153 and selected SQL before imports/execution.
Only an owned network-none disposable synthetic target is accepted. Local
fixture owner/claims normalization is explicit and is not production ACL parity.
"""
import argparse, datetime, hashlib, json, pathlib, re, sys, time, types, uuid
ROOT=pathlib.Path(__file__).resolve().parents[2]
FEATURE='supabase/migrations/20261001200000_exception_inbox_audit_v2.sql'
OLD_FEATURE='docs/release/collect-codex-goal-2026-09-30/exception-inbox-audit-v2-20261001/attempt8/executed-inputs/'+FEATURE
STAGES=['20260930213000_operator_email_auth.sql','20260930220527_operator_email_cutover_guard.sql',
 '20260930230100_receipt_backlog_events.sql','20260930230200_admin_receipt_overview.sql',
 '20260930230300_admin_transaction_lifecycle.sql','20260930211605_android_gateway_identity.sql',
 '20261001000100_operational_exception_inbox.sql','20261001000300_admin_exception_reads.sql',
 '20261001000400_receipt_supervisor_identity.sql','20261001000519_safe_unstarted_receipt_cancel.sql',
 '20261001001457_joined_operator_audit.sql','20261001003338_unattended_operating_policy.sql',
 '20261001004651_receipt_cancel_audit_actor.sql','20261001100000_receipt_financial_policy.sql',
 '20261001110000_receipt_operational_authority.sql','20261001120000_operational_exception_lifecycle.sql',
 '20261001140000_receipt_deferral_exceptions.sql','20261001190000_exception_followup_v2.sql']
HELPERS=['shadow_supervisor_uat','receipt_backlog_events_uat','collect_admin_combined_upgrade_uat','collect_current_release_upgrade_uat']
EMAIL='99790000-0000-4000-8000-000000000001';SID='99790000-0000-4000-8000-000000010001'
OTHER='99880000-0000-4000-8000-000000000001';OTHER_SID='99880000-0000-4000-8000-000000010001'
sha=lambda b:hashlib.sha256(b).hexdigest()
q=lambda x:"'"+str(x).replace("'","''")+"'"
ident=lambda:str(uuid.uuid4())
def moment(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report-dir',required=True,type=pathlib.Path);args=p.parse_args()
 report=args.report_dir.resolve();assert not report.exists() and str(report).startswith(str(ROOT/'docs/release')+'/');report.mkdir(parents=True)
 result=dict(kind='schema153_v2_affected_branch_bound_read_plan',status='running',cases=[],target={},hosted_called=False,source_rows_copied=False,device_used=False,provider_called=False,full_candidate_tested=False,fixture_limitations=['Local installer postgres superuser normalization','Owner-normalized retained schema153 plus captured19-file subset','Mock cron catalog shape only; no net/Vault/scheduler invocation','SET LOCAL API roles and synthetic JWT claims; no Auth service/signature verification','Current185 installer blocker and whole187 candidate acceptance remain outside scope'])
 save=lambda:(report/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 paths=['supabase/migrations/'+s for s in STAGES]+[FEATURE,OLD_FEATURE]+['scripts/tests/'+h+'.py'for h in HELPERS]+[str(pathlib.Path(__file__).relative_to(ROOT))]
 bodies={n:(ROOT/n).read_bytes()for n in paths};base=ROOT/'.cache/receipt-foundation-attempt8';baseline={n:(base/n).read_bytes()for n in ['schema-only.sql','api-acl.sql']}
 captured=report/'executed-inputs';captured.mkdir()
 for n,b in bodies.items():x=captured/n;x.parent.mkdir(parents=True,exist_ok=True);x.write_bytes(b)
 for n,b in baseline.items():(captured/n).write_bytes(b)
 result['source_sha256']={n:sha(b)for n,b in bodies.items()};result['baseline_sha256']={n:sha(b)for n,b in baseline.items()};result['cli_provenance']={'path':'/Volumes/PRO-G40/Development/User-Developer/supabase_2_84_2_codex/supabase','version':'2.84.2','generated':'20261001151541_exception_inbox_audit_v2.sql','published':'20261001200000_exception_inbox_audit_v2.sql'};save()
 mods={}
 for h in HELPERS:
  m=types.ModuleType(h);m.__file__=str(ROOT/'scripts/tests'/f'{h}.py');sys.modules[h]=m;exec(compile(bodies['scripts/tests/'+h+'.py'],m.__file__,'exec'),m.__dict__);mods[h]=m
 u=mods[HELPERS[0]];f=mods[HELPERS[1]];fixture=mods[HELPERS[2]];private=mods[HELPERS[3]]
 assert sha(baseline['schema-only.sql'])==fixture.DUMP_HASH and sha(baseline['api-acl.sql'])==fixture.ACL_HASH
 result['tools']={'python':sys.version,'docker_path':u.DOCKER,'docker_sha256':sha(pathlib.Path(u.DOCKER).read_bytes()),'image':private.IMAGE,'image_id':private.IMAGE_ID,'cli_sha256':sha(pathlib.Path(result['cli_provenance']['path']).read_bytes())}
 def case(name,ok):
  result['cases'].append(dict(name=name,status='pass'if ok else'failed'));save();print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 def retain(name,data):(report/name).write_text(json.dumps(data,indent=2)+'\n')
 db='exception_history_'+uuid.uuid4().hex[:12];target=None;sessions=[]
 sql=lambda s:u.psql(db,s).stdout.strip();owner=lambda s:u.call(db,s,EMAIL,SID);other=lambda s:u.call(db,s,OTHER,OTHER_SID)
 service_auth="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
 svc=lambda s:json.loads(sql('begin;'+service_auth+s+';commit;').splitlines()[-1]);fail=lambda s,c,reason=None:u.expected_error(db,s,c,reason,uid=EMAIL,sid=SID)
 finance=lambda:{k:v for k,v in f.business_fingerprint(db).items()if k not in('raw_payment_sms','parsed_payment_events')}
 def raw():
  rid=ident();sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values(%s,%s,%s,'M-Money','Synthetic parser failure',%s,repeat('a',64),'failed');"%(q(rid),q(f.GROUP),q(u.UID),q(sha(rid.encode()))))
  return json.loads(sql('select to_jsonb(e)from collect_ops.exceptions e where source_id='+q(rid)+';'))
 def action(e,rev,op,assignee=EMAIL,request=None):
  return owner('select public.admin_act_exception_workflow_v2(%s,%s,%d,%d,%s,%s,%s,%s,clock_timestamp()+interval \'90 seconds\');'%(q(request or ident()),q(e['id']),e['revision'],rev,q(op),q(assignee)if op=='assign'else'null',"clock_timestamp()+interval '2 hours'"if op=='assign'else'null',q('source_rechecked'if op=='resolve'else'owner_review_required')))
 def audit(e,limit=20,cursor=None):
  return owner('select public.admin_get_exception_entity_audit_v2(%s,%d,%s,%s);'%(q(e['id']),limit,q(cursor['recorded_at'])if cursor else'null',q(cursor['event_id'])if cursor else'null'))
 def inbox(who=owner,limit=20,cursor=None):
  return who('select public.admin_list_exception_escalation_inbox_v2(%d,%s,%s);'%(limit,q(cursor['delivered_at'])if cursor else'null',q(cursor['escalation_id'])if cursor else'null'))
 def shape(snapshot,audit_mode):
  assert snapshot['contract_version']==2 and moment(snapshot['sample_valid_until'])-moment(snapshot['checked_at'])==datetime.timedelta(seconds=60)
  rows=snapshot['rows'];assert len(rows)<=snapshot['limit']
  first='recorded_at'if audit_mode else'delivered_at';second='event_id'if audit_mode else'escalation_id'
  keys=[(moment(r[first]),r[second])for r in rows];assert keys==sorted(set(keys),reverse=True)and all(k[0]<=moment(snapshot['checked_at'])for k in keys)
  if snapshot['next_cursor']:assert len(rows)==snapshot['limit']and snapshot['next_cursor']=={first:rows[-1][first],second:rows[-1][second]}
  if audit_mode:
   assert set(snapshot)=={'contract_version','scope','entity_kind','entity_id','status','checked_at','sample_valid_until','limit','history_complete','financial_action','send_action','rows','next_cursor'}
   assert all(set(r)=={'event_id','source','source_record_id','action','recorded_at','actor_kind','actor_id','request_id','revision','workflow_revision','escalation_id','reason_code','origin','assignee_id','due_at'}for r in rows)
  else:
   assert set(snapshot)=={'contract_version','channel','scope','recipient_id','checked_at','sample_valid_until','limit','rows','next_cursor'}
   assert all(set(r)=={'escalation_id','exception_id','source_revision','reason_code','source_active','current_source_revision','delivered_at','read_at'}for r in rows)
  return True
 try:
  target=private.Target(report,'exception_history',result['target']);target.__enter__();u.CONTAINER=target.name;u.SQL_LOG=report/'queries.log';u.CONCURRENCY_LOG=report/'concurrency.log';f.RAW_QUERY_LOG=report/'queries.sql'
  u.psql('postgres','create database '+db+' template template0;')
  sql('create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+baseline['schema-only.sql'].decode()+baseline['api-acl.sql'].decode())
  f.seed(db);sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+f.service(f.payment_sql('99880000-0000-4000-8000-000000050001',amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values(%s,%s,'+250788971001',repeat('a',64),'mtn_momo');"%(q(f.GROUP),q(u.UID)))
  sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('audit.read','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%q(f.ROLE))
  initial=finance()
  for name in STAGES:
   path='supabase/migrations/'+name;r=u.psql(db,bodies[path].decode(),False);(report/(name+'.install.log')).write_text(r.stdout+r.stderr);case(name+' additive install preserves existing nonempty financial evidence',r.returncode==0 and finance()==initial)
  sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('audit.read','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%q(f.ROLE))
  for uid,email in[(EMAIL,'info@ikanisa.com'),(OTHER,'second-owner@example.invalid')]:
   sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values(%s,'authenticated','authenticated',%s,clock_timestamp(),'{}','{}');"%(q(uid),q(email)))
   if uid==EMAIL:svc('select public.bootstrap_collect_email_operator_v1('+q(uid)+');')
   else:sql("insert into collect_admin_access.email_approvals(user_id,email,reason,approved_at)values(%s,%s,'Synthetic approved owner',clock_timestamp()-interval '2 minutes');insert into public.admin_user_roles(user_id,role_id,reason,created_at)values(%s,%s,'Synthetic current owner',clock_timestamp()-interval '1 minute');"%(q(uid),q(email),q(uid),q(f.ROLE)))
  for uid,sid in[(EMAIL,SID),(OTHER,OTHER_SID)]:sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(q(sid),q(uid)))
  historical=raw();action(historical,0,'assign');historical_esc=action(historical,1,'escalate')['escalation_id'];svc('select public.process_exception_escalations_v1(20);');owner('select public.admin_read_exception_escalation_v1('+q(historical_esc)+');')
  definitions=sql("select jsonb_object_agg(p.oid::regprocedure::text,encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'))from pg_proc p where p.proname in('admin_get_operator_entity_audit_v1','admin_list_exception_escalation_inbox_v1','admin_read_exception_escalation_v1','admin_act_exception_workflow_v1','process_exception_escalations_v1');")
  preserved_tables=['exception_escalations','exception_inbox_deliveries','exception_inbox_reads','exception_workflow_requests','exception_actions']
  evidence_before={t:sql('select md5(coalesce(jsonb_agg(to_jsonb(x)order by to_jsonb(x)::text)::text,\'[]\'))from collect_ops.'+t+' x;')for t in preserved_tables}
  prior_fin=finance();r=u.psql(db,bodies[FEATURE].decode(),False);(report/'feature.install.log').write_text(r.stdout+r.stderr);case('new feature installs without changing financial or prior lifecycle evidence',r.returncode==0 and finance()==prior_fin and evidence_before=={t:sql('select md5(coalesce(jsonb_agg(to_jsonb(x)order by to_jsonb(x)::text)::text,\'[]\'))from collect_ops.'+t+' x;')for t in preserved_tables})
  case('all five original v1 function definitions remain exact',definitions==sql("select jsonb_object_agg(p.oid::regprocedure::text,encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'))from pg_proc p where p.proname in('admin_get_operator_entity_audit_v1','admin_list_exception_escalation_inbox_v1','admin_read_exception_escalation_v1','admin_act_exception_workflow_v1','process_exception_escalations_v1');"));result['original_function_definition_hashes']=json.loads(definitions)
  item=raw();owner('select public.admin_act_operational_exception_v1(%s,%s,%d,\'acknowledge\',\'review_started\');'%(q(ident()),q(item['id']),item['revision']));action(item,0,'assign');escalate=action(item,1,'escalate');svc('select public.process_exception_escalations_v1(25);');owner('select public.admin_read_exception_escalation_v2('+q(escalate['escalation_id'])+');')
  baseline_page=audit(item,25);retain('observed-public-small-page.json',baseline_page);case('normal public v2 page preserves all six typed joined phases',shape(baseline_page,True)and len(baseline_page['rows'])==6)
  # A rollback-only representative equal-time request history reaches the
  # exact inner SELECT of the installed public function, not EXPLAIN of its
  # opaque PL/pgSQL call. No planner switches are changed.
  same_at=sql("select collect_ops.utc(clock_timestamp()-interval '1 second');")
  perf=u.Session(db,'exception_v2_performance');sessions.append(perf)
  performance_ids=','.join(q(uuid.uuid5(uuid.UUID('de24414a-723f-5b17-8b7b-935c5d786b56'),str(n)))for n in range(1,1001))
  perf.write('begin;'+u.auth(EMAIL,SID)+"do $$declare req uuid;begin foreach req in array array["+performance_ids+"]::uuid[]loop perform public.admin_act_operational_exception_v1(req,"+q(item['id'])+","+str(item['revision'])+",'acknowledge','review_started');end loop;end$$;reset role;set local session_replication_role=replica;update collect_ops.exception_actions set recorded_at="+q(same_at)+"where exception_id="+q(item['id'])+";set local session_replication_role=origin;analyze collect_ops.exception_actions;select 'PERF_HELD';");perf.read('PERF_HELD')
  # The same transaction reads its own representative fixture and actual body.
  def bind_query(body):
   query='with scope as materialized'+body.decode().split(' with scope as materialized',1)[1].split('into result;',1)[0]
   bindings={'p_exception_id':q(item['id'])+'::uuid','p_limit':'20','p_before_at':q(same_at)+'::timestamptz','p_before_event_id':q('ffffffff-ffff-ffff-ffff-ffffffffffff')+'::uuid','sample':q(same_at)+'::timestamptz'}
   for name,value in bindings.items():query=re.sub(r'\b'+name+r'\b',value,query)
   return query
  own_query=bind_query(bodies[FEATURE]);old_query=bind_query(bodies[OLD_FEATURE])
  perf.write("select jsonb_build_object('current_user',current_user,'function_owner',(select pg_get_userbyid(proowner)from pg_proc where oid='public.admin_get_exception_entity_audit_v2(uuid,integer,timestamptz,uuid)'::regprocedure),'synthetic_authenticated_actor',auth.uid(),'security_definer',(select prosecdef from pg_proc where oid='public.admin_get_exception_entity_audit_v2(uuid,integer,timestamptz,uuid)'::regprocedure));select 'OWNER_CONTEXT';")
  context=json.loads(perf.read('OWNER_CONTEXT')[0]);retain('observed-inner-query-owner-context.json',context);case('inner SELECT diagnostic runs as exact installed security-definer owner without granting API private reads',context['security_definer']and context['current_user']==context['function_owner']and context['synthetic_authenticated_actor']==EMAIL)
  for label,query in [('before',old_query),('after',own_query)]:
   perf.write('explain(analyze,buffers,format json)'+query+";select 'PLAN_DONE';");lines=perf.read('PLAN_DONE');plan=json.loads('\n'.join(lines[:-1]));retain('observed-inner-query-plan-'+label+'.json',dict(context=context,representative_review_rows=1001,equal_time_installer_reshape_rollback_only=True,planner_switches_changed=False,query=query,plan=plan))
   if label=='after':after_plan=plan
   perf.write(query+";select 'PAGE_DONE';");inner=json.loads(perf.read('PAGE_DONE')[0]);retain('observed-inner-query-page-'+label+'.json',inner)
   if label=='before':before_ids=[r['event_id']for r in inner['rows']]
   else:after_ids=[r['event_id']for r in inner['rows']]
  def nodes(value):
   if isinstance(value,dict):
    if 'Node Type'in value:yield value
    for v in value.values():yield from nodes(v)
   elif isinstance(value,list):
    for v in value:yield from nodes(v)
  scanned=[n['Actual Rows']for n in nodes(after_plan)if n.get('Index Name')=='exception_review_audit_v2_order']
  candidates=[n['Actual Rows']for n in nodes(after_plan)if n.get('Node Type')=='Append']
  case('affected inner query caps review index consumption at21 and union candidates at63 without planner overrides',scanned and max(scanned)<=21 and(not candidates or max(candidates)<=63))
  case('branch bounding preserves exact original inner query page identities',before_ids==after_ids and len(after_ids)==20)
  perf.write(u.auth(EMAIL,SID)+'select public.admin_get_exception_entity_audit_v2('+q(item['id'])+',20,'+q(same_at)+','+q('ffffffff-ffff-ffff-ffff-ffffffffffff')+");select 'PUBLIC_PAGE_DONE';")
  actual_lines=perf.read('PUBLIC_PAGE_DONE');actual=json.loads(actual_lines[-2]);retain('observed-authenticated-public-page.json',actual);case('actual authenticated current-owner RPC returns identical cursor-scoped inner page identities',shape(actual,True)and[r['event_id']for r in actual['rows']]==after_ids)
  perf.write('select public.admin_get_exception_entity_audit_v2('+q(item['id'])+',20,'+q(actual['next_cursor']['recorded_at'])+','+q(actual['next_cursor']['event_id'])+");select 'PUBLIC_OLDER_DONE';")
  older=json.loads(perf.read('PUBLIC_OLDER_DONE')[-2]);retain('observed-authenticated-public-older.json',older);case('equal-time namespace keyset advances public older page without duplicate identities',shape(older,True)and len(older['rows'])==20 and not set(after_ids)&{r['event_id']for r in older['rows']})
  perf.write('reset role;')
  perf.write("rollback;select 'PERF_ROLLED_BACK';");perf.read('PERF_ROLLED_BACK');case('performance fixture rollback preserves immutable original public history',len(audit(item,25)['rows'])==6)
  for table in['exception_escalation_events','exception_workflow_requests','exception_inbox_deliveries','exception_inbox_reads']:
   case(table+' private RLS and no direct API grants',sql("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c where c.oid="+q('collect_ops.'+table)+'::regclass;')=='t')
   r=u.psql(db,'begin;delete from collect_ops.'+table+';rollback;',False);case(table+' immutable even to synthetic owner',r.returncode!=0 and'55000:'in r.stderr)
  case('new private helpers have no API execute access',sql("select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.proname in('capture_escalation_event','exception_event_id','exception_scope_v2','exception_actor_v2')and has_function_privilege(r,p.oid,'EXECUTE')); ")=='t')
  case('all new reads/actions preserve nonempty canonical finance provider primary receipt and send state',finance()==prior_fin);result['financial_before']=prior_fin;result['financial_after']=finance();retain('observed-audit-final.json',audit(item,25));retain('observed-inbox-final.json',inbox());result['status']='pass'
 except BaseException as error:result['status']='failed';result['error']=str(error);raise
 finally:
  for s in sessions:
   try:s.close()
   except Exception as error:result.setdefault('cleanup_errors',[]).append(str(error))
  if target:target.close()
  result['sources_unchanged']=all((ROOT/n).read_bytes()==b for n,b in bodies.items());result['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
if __name__=='__main__':main()
