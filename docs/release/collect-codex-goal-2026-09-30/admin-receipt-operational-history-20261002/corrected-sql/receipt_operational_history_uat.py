#!/usr/bin/env python3
"""Focused ordinary-owner operational history proof on retained synthetic192.
No hosted URL, JWT verification, managed owner parity or provider/device claim.
"""
import argparse,base64,datetime,hashlib,json,pathlib,re,sys,threading,types,uuid
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
STAGE=pathlib.Path(__file__).resolve().parent
CHECKPOINT=ROOT/'.cache/receipt-operational-telemetry-20261001/sql-attempt3/prerequisite-checkpoint.sql'
sha=lambda b:hashlib.sha256(b).hexdigest();uid=lambda:str(uuid.uuid4());now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def save(p,x):p.write_text(json.dumps(x,indent=2)+'\n')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',type=pathlib.Path,required=True);a=ap.parse_args();report=a.report_dir.resolve();assert not report.exists();report.mkdir();inputs=report/'inputs';inputs.mkdir();commands=report/'commands';commands.mkdir();fixtures=report/'fixtures';fixtures.mkdir()
 bindings={};source_bytes={}
 def capture(p,dest):
  b=p.read_bytes();source_bytes[str(p)]=b;bindings[str(p)]=sha(b);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b);return b
 helper=capture(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py',inputs/'executed-helper.py');capture(pathlib.Path(__file__),inputs/'executed-runner.py');capture(pathlib.Path(sys.executable).resolve(),inputs/'python-runtime');capture(pathlib.Path('/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'),inputs/'docker-runtime');capture(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql',inputs/'row-free-platform.sql')
 checkpoint=capture(CHECKPOINT,inputs/'prerequisite-checkpoint.sql');assert sha(checkpoint)=='0adc7a22e376e48cfc2e889fe17900697f617f9a5c2ddc5d0c22ad0c42b89e5a';receipt=json.loads(capture(CHECKPOINT.with_name('prerequisite-checkpoint-receipt.json'),inputs/'prerequisite-checkpoint-receipt.json'))
 for path,digest in receipt['source_bindings'].items():
  p=pathlib.Path(path)
  if '/supabase/migrations/'in path and p.parent==ROOT/'supabase/migrations':assert sha(capture(p,inputs/'selected-prerequisites'/p.name))==digest
 extra=['20261001160000_receipt_worker_transport_health.sql','20261001233000_assisted_sms_originating_session_fence.sql','20261001234000_play_integrity_admission.sql','20261001235000_admin_audit_read_api_only.sql','20261001235500_roster_decoder_toolchain_admission.sql','20261002030000_receipt_operational_telemetry.sql','20261002031500_privacy_request_intake.sql','20261002040000_receipt_unarmed_closure.sql','20261002041000_receipt_successor_approvals.sql','20261002050000_receipt_terminal_source_projection.sql']
 extras=[(n,capture(ROOT/'supabase/migrations'/n,inputs/n))for n in extra]
 platform=capture(ROOT/'scripts/sql/receipt_transport_platform_prerequisites.sql',inputs/'receipt_transport_platform_prerequisites.sql')
 capture(ROOT/'.cache/receipt-terminal-source-projection-20261002/accepted-packet/receipt_source_projection_uat.py',inputs/'accepted-projection-setup-reference.py');capture(ROOT/'docs/release/rapid-completion-2026-10-02/ordinary-current201-attempt1/current_ordinary_installer_rehearsal.py',inputs/'accepted201-platform-reference.py')
 capture(STAGE/'query_cost_proof.py',inputs/'executed-cost-proof.py')
 migration=capture(STAGE/'promote/supabase/migrations/20261002060000_admin_receipt_operational_history.sql',inputs/'600.sql')
 result=dict(status='running',started_at=now(),checks=[],target={},source_bindings=bindings,
  scope='retained synthetic192 checkpoint plus10 exact selected current definitions then600; actual NOSUPERUSER application install; not complete203 replay or private430 coverage',jwt_verified=False,vault_crypto_verified=False,hosted_written=False,sms_sent=False,device_used=False)
 save(report/'execution-binding.json',result);m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 original=m.command;counter=0
 def recorded(args,text=None,check=True,timeout=120):
  nonlocal counter;counter+=1;prefix=commands/f'{counter:05d}';start=now();r=original(args,text,False,timeout);prefix.with_suffix('.stdout').write_text(r.stdout);prefix.with_suffix('.stderr').write_text(r.stderr)
  if text is not None:prefix.with_suffix('.sql').write_text(text)
  save(prefix.with_suffix('.json'),dict(argv=[x if not x.startswith('POSTGRES_PASSWORD=')else'POSTGRES_PASSWORD=<generated-local-fixture>'for x in args],input_sha256=sha(text.encode())if text is not None else None,started_at=start,finished_at=now(),exit_code=r.returncode))
  if check and r.returncode:raise RuntimeError(r.stderr[-3500:])
  return r
 m.command=recorded
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'operational_history',result['target'])as t:
   t.sql("do $$begin if not exists(select 1 from pg_roles where rolname='supabase_functions_admin')then create user supabase_functions_admin noinherit createrole login noreplication;end if;end$$;",label='declared managed role bootstrap prerequisite')
   wrapper=re.search(r'create or replace function graphql_public\.graphql\([\s\S]*?\$\$;',checkpoint.decode()).group(0);acl='GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO postgres;'
   restore=checkpoint.decode().replace(acl,wrapper+'\nalter function graphql_public.graphql(text,text,jsonb,jsonb)owner to supabase_admin;\n'+acl,1)
   for definition in ['CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;','CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;']:
    assert restore.count(definition)==1;restore=restore.replace(definition,'set role supabase_admin;'+definition+'reset role;',1)
   (inputs/'executed-snapshot-restore.sql').write_text(restore);result['snapshot_restore']=dict(raw_sha256=sha(checkpoint),executed_sha256=sha(restore.encode()),wrapper_sha256=sha(wrapper.encode()),app_or_auth_stub=False)
   t.sql(restore,label='exact retained192 synthetic snapshot restore')
   t.sql('alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;',user='supabase_admin',label='same declared trusted pg_net fixture metadata')
   t.sql(platform.decode(),user='supabase_admin',label='exact reviewed platform table column ACL index prerequisites')
   t.sql('grant execute on function cron.alter_job(bigint,text,text,text,text,boolean)to postgres;',user='supabase_admin',label='declared cron owner API prerequisite')
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='end platform bootstrap demote application installer')
   result['inherited_installer_roles']=t.json("select jsonb_agg(jsonb_build_object('role',rolname,'member',pg_has_role(current_user,oid,'MEMBER'),'usage',pg_has_role(current_user,oid,'USAGE'))order by rolname)from pg_roles;")
   for n,b in extras:
    case(n+' executes as NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t');t.sql(b.decode(),label='exact affected prerequisite '+n)
   t.sql('update auth.sessions set not_after=clock_timestamp()+interval \'2 hours\'where id='+q(m.SID)+'and user_id='+q(m.UID)+';',label='refresh only retained synthetic operator expiry')
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);";svc="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expr,service=False):return t.json('begin;'+(svc if service else auth)+'select '+expr+';commit;')
   def bad(expr,code,label,service=False):
    r=t.sql('begin;'+(svc if service else auth)+'select '+expr+';rollback;',check=False,label=label);case(label,r.returncode!=0 and code in r.stderr)
   tables=[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','sms_notification_outbox'),('collect_receipt_operations','runs'),('collect_receipt_operations','requests'),('collect_receipt_operations','handled_events'),('collect_receipt_operations','run_events'),('collect_receipt_operations','run_batch_events'),('collect_receipt_operations','backlog_results'),('collect_receipt_operations','reservations'),('collect_receipt_operations','event_deferrals'),('collect_ops','receipt_backlog_budget_deferrals')]
   cols=m.columns(t,tables);before=m.fingerprints(t,cols)
   producers=t.json("select jsonb_agg(jsonb_build_object('signature',oid::regprocedure::text,'sha',encode(extensions.digest(prosrc,'sha256'),'hex'),'owner',proowner,'acl',proacl)order by oid)from pg_proc where pronamespace in('collect_receipt_operations'::regnamespace,'collect_receipt_source_projection'::regnamespace,'collect_gateway_dispatch'::regnamespace)or oid='public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)'::regprocedure;")
   case('600 actual installer NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t');t.sql(migration.decode(),label='exact600 ordinary owner read-only migration')
   case('read-only migration preserves all original financial and operational rows',m.fingerprints(t,cols)==before)
   case('private history schema/helpers deny all client/service direct grants',t.scalar("select not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_schema_privilege(r,'collect_receipt_history','USAGE'))and not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_receipt_history'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE'));")=='t')
   for role in ['anon','service_role']:
    case(role+' cannot execute history RPCs',t.scalar("select not exists(select 1 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('admin_list_receipt_operation_starts_v1','admin_get_receipt_operation_run_v1','admin_list_receipt_operation_evidence_v1')and has_function_privilege("+q(role)+",p.oid,'EXECUTE')); ")=='t')
   pref='3059301306072a8648ce3d020106082a8648ce3d03010703420004';point='6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5';key=bytes.fromhex(pref+point);kh=sha(key);pub=base64.b64encode(key).decode()
   enrollment=call('public.admin_enroll_receipt_operations_identity_v3('+','.join([q(uid()),q(pub),q(kh),"clock_timestamp()+interval '1 day'","clock_timestamp()+interval '100 seconds'"])+')');principal=enrollment['principal_id']
   def operation(action,payload=None):
    payload=payload or{};req=uid();v=call('public.receipt_operations_execute_v2('+','.join([q(principal),q(req),q(kh),q(sha(json.dumps([req,action,payload]).encode())),'clock_timestamp()',q(action),q(json.dumps(payload))+'::jsonb'])+')',True);save(fixtures/('producer-'+action+'-'+req+'.json'),v);return v
   operation('prove_key');call('public.admin_activate_receipt_operations_identity_v3('+','.join([q(principal),q(uid()),q(kh),"clock_timestamp()+interval '100 seconds'"])+')');refused=operation('begin_run')
   starts=lambda limit=20,cursor=None:call('public.admin_list_receipt_operation_starts_v1('+str(limit)+','+('null,null'if cursor is None else q(cursor['recorded_at'])+','+q(cursor['evidence_id']))+')')
   page=starts();save(fixtures/'starts-refused.json',page);case('actual refused begin request has no fabricated run',any(x['request_id']==refused['request_id']and x['run_state']=='no_run'and x['run_id']is None for x in page['rows']))
   gp='7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1';gkey=bytes.fromhex(pref+gp);gkh=sha(gkey);gpub=base64.b64encode(gkey).decode()
   device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[uid(),uid(),gpub,gkh,'c'*64]))+')')['device_id']
   hp=dict(sms_permission=True,network='validated',telephony='ready',sim_selected=True,sim_revision_sha256='d'*64,local_pause=False,reported_at=now());call('public.gateway_heartbeat_v1('+','.join(map(q,[device,uid(),sha(json.dumps(hp).encode())]))+','+q(json.dumps(hp))+'::jsonb)',True);call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
   def post(n):
    pid,raw,event=uid(),uid(),uid();ref='HISTORY-'+str(n);wallet=sha(b'+250788971001')
    t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic history proof'","encode(extensions.digest('Synthetic history proof','sha256'),'hex')",q(wallet),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wallet),'100',q(ref),"'unallocated'","'Synthetic history payer'"])+');insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values('+','.join([q(pid),q(event),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wallet),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-'+ref),q(wallet),'100','clock_timestamp()',"repeat('c',64)"])+');commit;',label='actual normal trusted posting '+str(n))
    t.sql("update public.parsed_payment_events set allocation_status='allocated'where id="+q(event)+';',label='normal declared allocation fixture closed onto its actual payment')
    return t.json('select to_jsonb(e)from collect_hybrid.receipt_business_events e where payment_id='+q(pid)+"and event_kind='payment_posted';")
   def post_backlog(n):
    t.sql('update collect_hybrid.sms_receipt_policies set enabled=false,updated_at=clock_timestamp()where collection_id='+q(m.GROUP)+';',label='declared ordinary-owner receipt policy pause before normal posting fixture')
    event=post(n)
    t.sql('update collect_hybrid.sms_receipt_policies set enabled=true,updated_at=clock_timestamp()where collection_id='+q(m.GROUP)+';',label='declared ordinary-owner receipt policy restore for backlog producer proof')
    return event
   normal=post(1);post(2);post(3)
   caps={k:100 for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   caps['run_actions']=10;caps['run_sms_segments']=20
   def configure(mode='Live-limited',custom=None,hours=24):return call('public.admin_configure_receipt_operations_v2('+','.join([q(uid()),t.scalar('select revision from collect_receipt_operations.policy;'),q(mode),'false',"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(custom or caps))+'::jsonb','true',str(hours),"'Synthetic history proof only'","clock_timestamp()+interval '100 seconds'"])+')')
   configured=configure();run=operation('begin_run');rid=run['run_id'];fence=dict(run_id=rid,fence_version=run['fence_version'])
   assigned=operation('list_events',dict(**fence,limit=25));case('actual list producer returns immutable assignments',len(assigned['events'])>0)
   first=next(x for x in assigned['events']if x['event_id']==normal['id']);operation('ensure_receipt',dict(**fence,event_id=first['event_id'],expected_source_version=first['source_version']));operation('reconcile_backlog',dict(**fence,limit=25));closed=operation('complete_run',fence)
   detail=lambda id=rid:call('public.admin_get_receipt_operation_run_v1('+q(id)+')')
   def evidence(section,limit=20,cursor=None,id=rid):return call('public.admin_list_receipt_operation_evidence_v1('+q(id)+','+q(section)+','+str(limit)+','+('null,null'if cursor is None else q(cursor['recorded_at'])+','+q(cursor['evidence_id']))+')')
   saved=detail();save(fixtures/'run-closed.json',saved);case('exact immutable config revision caps and original close summary',saved['historical_config']['request_id']==configured['request_id']and saved['historical_config']['caps']==caps and saved['completion']['request_id']==closed['request_id']and saved['completion']['deferred_count']==closed['deferred_count'])
   for section in ['events','backlog_results','budget_refusals','reservations']:save(fixtures/('evidence-'+section+'.json'),evidence(section))
   changed=dict(caps,global_actions=50);configure(custom=changed);case('changed current caps cannot replace historic immutable caps',detail()['historical_config']['caps']==caps)
   # Fresh per-run quota refusal through actual producer, then repeated exact
   # request identities on one snapshot. The refusal cursor retains both UUIDs.
   qnormal=post_backlog(4);qpending=post_backlog(5);quota_caps=dict(caps,run_actions=1);configure(custom=quota_caps,hours=1);quota_run=operation('begin_run');qrid=quota_run['run_id'];qf=dict(run_id=qrid,fence_version=quota_run['fence_version'])
   operation('list_events',dict(**qf,limit=25));operation('ensure_receipt',dict(**qf,event_id=qnormal['id'],expected_source_version=qnormal['source_version']));operation('ensure_receipt',dict(**qf,event_id=qpending['id'],expected_source_version=qpending['source_version']));operation('reconcile_backlog',dict(**qf,limit=25));operation('reconcile_backlog',dict(**qf,limit=25));save(fixtures/'evidence-quota-events.json',evidence('events',id=qrid));qp=evidence('budget_refusals',1,id=qrid);save(fixtures/'quota-first.json',qp)
   if qp['next_cursor']:
    qnext=evidence('budget_refusals',1,qp['next_cursor'],id=qrid);save(fixtures/'quota-last.json',qnext);case('composite request snapshot cursor preserves repeated immutable refusals',qp['rows'][0]['evidence_id']!=qnext['rows'][0]['evidence_id'])
   else:case('actual budget producer retains immutable quota refusal',len(qp['rows'])>0)
   for _ in range(4):call('public.process_receipt_deferral_exceptions_v1('+q(uid())+",25,clock_timestamp()+interval '100 seconds')",True)
   save(fixtures/'evidence-quota-events.json',evidence('events',id=qrid))
   save(fixtures/'evidence-budget-refusals-with-exceptions.json',evidence('budget_refusals',id=qrid))
   qprefs=evidence('events',id=qrid);case('actual current deferral and supported exception source links coexist',any(x['current_deferral']is not None for x in qprefs['rows'])and any(x['exception_ids']for x in qprefs['rows']))
   all_ids=[];c=None
   while True:
    e=evidence('events',1,c);all_ids.extend(x['evidence_id']for x in e['rows']);c=e['next_cursor']
    if c is None:break
   case('actual limit+1 event pages partition retained identities exactly',len(all_ids)==len(set(all_ids))and set(all_ids)=={x['evidence_id']for x in evidence('events')['rows']})
   fixed=now();tie_prefix='begin;alter table collect_ops.receipt_backlog_budget_deferrals disable trigger retain_receipt_backlog_budget;update collect_ops.receipt_backlog_budget_deferrals set recorded_at='+q(fixed)+'where run_id='+q(qrid)+';alter table collect_ops.receipt_backlog_budget_deferrals enable trigger retain_receipt_backlog_budget;'+auth
   tied=t.json(tie_prefix+'select public.admin_list_receipt_operation_evidence_v1('+q(qrid)+",'budget_refusals',1,null,null);rollback;");save(fixtures/'quota-first-tied.json',tied)
   tc=tied['next_cursor'];tlast=t.json(tie_prefix+'select public.admin_list_receipt_operation_evidence_v1('+q(qrid)+",'budget_refusals',1,"+q(tc['recorded_at'])+','+q(tc['evidence_id'])+');rollback;');save(fixtures/'quota-last-tied.json',tlast)
   case('real reader composite C collation tie cursor loses no refusal',tied['rows'][0]['recorded_at']==tlast['rows'][0]['recorded_at']and tied['rows'][0]['evidence_id']>tlast['rows'][0]['evidence_id'])
   operation('complete_run',qf);save(fixtures/'run-quota-closed.json',detail(qrid))
   # Actual shorter lease: principal expiry is shortened by declared ordinary
   # owner fixture update; the actual begin producer computes LEAST expiry.
   configure();t.sql('begin;alter table collect_supervisor.identities disable trigger retained_supervisor_identity;update collect_supervisor.identities set expires_at=clock_timestamp()+interval \'70 seconds\'where id='+q(principal)+';alter table collect_supervisor.identities enable trigger retained_supervisor_identity;commit;',label='declared installer-only retained identity near expiry fixture; no API can shorten immutable expiry')
   short=operation('begin_run');short_detail=detail(short['run_id']);save(fixtures/'run-short.json',short_detail);case('actual producer lease shorter than120seconds',datetime.datetime.fromisoformat(short_detail['run']['expires_at'].replace('Z','+00:00'))-datetime.datetime.fromisoformat(short_detail['run']['started_at'].replace('Z','+00:00'))<datetime.timedelta(seconds=120))
   for section in ['events','backlog_results','budget_refusals','reservations']:bad('public.admin_list_receipt_operation_evidence_v1('+q(rid)+','+q(section)+",1,clock_timestamp(),null)",'22023','complete cursor pair required '+section)
   bad('public.admin_list_receipt_operation_evidence_v1('+q(rid)+",'events',26,null,null)",'22023','history limit bounded25')
   bad('public.admin_list_receipt_operation_evidence_v1('+q(rid)+",'budget_refusals',1,clock_timestamp(),'bad:uuid')",'22023','composite cursor canonical UUIDs only')
   unavailable=detail(uid());save(fixtures/'run-unavailable.json',unavailable);case('missing run stays unavailable without zero history',unavailable['status']=='unavailable'and unavailable['run']is None and unavailable['quota_usage']is None)
   audits={}
   for kind,id in [('receipt_operation_run',rid),('supervisor_identity',principal),('receipt_operations_policy','00000000-0000-4000-8000-000000000001')]:
    audits[kind]=call('public.admin_get_operator_entity_audit_v1('+q(kind)+','+q(id)+',20,null,null)');save(fixtures/('audit-'+kind+'.json'),audits[kind]);case('actual joined '+kind+' audit lineage is present',len(audits[kind]['rows'])>0)
   sources={x['source']for x in audits['supervisor_identity']['rows']};case('identity lineage includes original operations owner and actual enrollment workflow records',{'receipt_operations_owner_request','receipt_operations_enrollment_workflow'}<=sources)
   # Check current authority using actual role/permission mutation in rollback.
   for permission in ['payments.read','notifications.read','system_health.read']:
    text="begin;delete from public.admin_role_permissions where permission_name="+q(permission)+';' +auth+"select public.admin_get_receipt_operation_run_v1("+q(rid)+');rollback;';r=t.sql(text,check=False,label='real permission removal '+permission);case('missing '+permission+' denied',r.returncode!=0 and '42501'in r.stderr)
   t.sql("begin;delete from public.admin_role_permissions where permission_name='notifications.manage';"+auth+'select public.admin_get_receipt_operation_run_v1('+q(rid)+');rollback;',label='read remains independent of manage permission')
   r=t.sql("begin;delete from public.admin_role_permissions where permission_name='audit.read';"+auth+'select public.admin_get_operator_entity_audit_v1('+q('receipt_operation_run')+','+q(rid)+',20,null,null);rollback;',check=False,label='independent audit permission removed');case('independent audit.read protects joined audit links',r.returncode!=0 and '42501'in r.stderr)
   r=t.sql('begin;update auth.sessions set not_after=clock_timestamp()-interval \'1 second\'where id='+q(m.SID)+';'+auth+'select public.admin_get_receipt_operation_run_v1('+q(rid)+');rollback;',check=False,label='actual current session expiry');case('expired current session cannot read operational history',r.returncode!=0 and '42501'in r.stderr)
   # Old configuration cannot be reconstructed. Mutate only in rollback after
   # disabling retained evidence trigger as an explicit privileged fixture.
   r=t.json('begin;alter table collect_receipt_operations.owner_requests disable trigger operations_evidence_immutable;delete from collect_receipt_operations.owner_requests where request_id='+q(configured['request_id'])+';'+auth+'select public.admin_get_receipt_operation_run_v1('+q(rid)+');rollback;');save(fixtures/'run-config-unavailable.json',r);case('missing old config stays unavailable while run evidence remains',r['historical_config']is None and r['run']is not None)
   from query_cost_proof import run_cost_proof
   cost_cols=m.columns(t,[('collect_receipt_operations','requests'),('collect_receipt_operations','owner_requests')]);cost_before=m.fingerprints(t,cost_cols)
   result['query_cost']=run_cost_proof(t,auth,principal,rid,m,case,report,saved,audits)
   case('rollback cost fixtures preserve exact original producer request and owner history rows',m.fingerprints(t,cost_cols)==cost_before)
   after_producers=t.json("select jsonb_agg(jsonb_build_object('signature',oid::regprocedure::text,'sha',encode(extensions.digest(prosrc,'sha256'),'hex'),'owner',proowner,'acl',proacl)order by oid)from pg_proc where pronamespace in('collect_receipt_operations'::regnamespace,'collect_receipt_source_projection'::regnamespace,'collect_gateway_dispatch'::regnamespace)or oid='public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)'::regprocedure;")
   case('all captured original producer bodies owners and ACL remain exact',after_producers==producers)
   redacted=json.dumps([json.loads(p.read_text())for p in fixtures.glob('*.json')if not p.name.startswith('producer-')]);case('all actual API fixtures omit signing inputs raw content and destinations',all(key not in redacted for key in ['request_sha256','public_key_spki_base64','message_body','destination_e164','raw_body','key_sha256']))
   case('all bound source inputs remain unchanged',all(pathlib.Path(p).read_bytes()==b for p,b in source_bytes.items()));result['fixture_principal']=principal;result['fixture_run']=rid;result['fixture_quota_run']=qrid;result['fixture_short_run']=short['run_id'];result['status']='passed'
 except BaseException as e:result['status']='failed';result['error']=str(e);raise
 finally:result['finished_at']=now();result['command_receipts']=counter;save(report/'result.json',result)
if __name__=='__main__':main()
