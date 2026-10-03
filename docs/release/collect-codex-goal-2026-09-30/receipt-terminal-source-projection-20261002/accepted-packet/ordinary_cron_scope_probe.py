#!/usr/bin/env python3
"""Actual offline SQL projection/retirement proof; exact original service APIs.

Retained192-prerequisite checkpoint plus real160/300/400; no hosted write,
network, GoTrue/JWT, physical device or managed Vault encryption claim.
"""
import argparse,base64,concurrent.futures,datetime,hashlib,json,pathlib,re,sys,threading,time,types,uuid
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
STAGE=pathlib.Path(__file__).resolve().parent
CHECKPOINT=ROOT/'.cache/receipt-operational-telemetry-20261001/sql-attempt3/prerequisite-checkpoint.sql'
sha=lambda b:hashlib.sha256(b).hexdigest()
uid=lambda:str(uuid.uuid4())
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',type=pathlib.Path,required=True);ap.add_argument('--setup-only',action='store_true');a=ap.parse_args()
 report=a.report_dir.resolve();assert not report.exists();report.mkdir();inputs=report/'inputs';inputs.mkdir();commands=report/'commands';commands.mkdir()
 bindings={};source_bytes={}
 def capture(p,dest):
  b=p.read_bytes();source_bytes[str(p)]=b;bindings[str(p)]=sha(b);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b);return b
 helper=capture(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py',inputs/'executed-helper.py')
 capture(pathlib.Path(__file__),inputs/'executed-runner.py');capture(pathlib.Path(sys.executable).resolve(),inputs/'python-runtime')
 capture(pathlib.Path('/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'),inputs/'docker-runtime')
 capture(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql',inputs/'row-free-platform.sql')
 checkpoint=capture(CHECKPOINT,inputs/'prerequisite-checkpoint.sql');assert sha(checkpoint)=='0adc7a22e376e48cfc2e889fe17900697f617f9a5c2ddc5d0c22ad0c42b89e5a'
 receipt=capture(CHECKPOINT.with_name('prerequisite-checkpoint-receipt.json'),inputs/'prerequisite-checkpoint-receipt.json')
 prior_bindings=json.loads(receipt)['source_bindings']
 marker=json.loads(capture(SOURCE/'.collect-release-candidate.json',inputs/'source08-marker.json'))
 original_sources=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=capture(p,inputs/'source08-migrations'/p.name);rel=str(p.relative_to(SOURCE));assert b==(ROOT/rel).read_bytes()and sha(b)==marker['source_files'][rel]['sha256']
  source_bytes[str(ROOT/rel)]=b;bindings[str(ROOT/rel)]=sha(b);original_sources.append(p.name)
 assert len(original_sources)==177
 # Bind exact retained DDL inputs; checkpoint restoration is not a claim of195
 # newly executed migrations or a complete concurrent candidate rehearsal.
 for path,digest in prior_bindings.items():
  p=pathlib.Path(path)
  if '/supabase/migrations/'in path and p.parent==ROOT/'supabase/migrations':
   assert sha(capture(p,inputs/'selected-prerequisites'/p.name))==digest
 extra=['20261001160000_receipt_worker_transport_health.sql','20261001233000_assisted_sms_originating_session_fence.sql','20261001234000_play_integrity_admission.sql','20261001235000_admin_audit_read_api_only.sql','20261001235500_roster_decoder_toolchain_admission.sql','20261002030000_receipt_operational_telemetry.sql','20261002031500_privacy_request_intake.sql','20261002040000_receipt_unarmed_closure.sql','20261002041000_receipt_successor_approvals.sql']
 extras=[(name,capture(ROOT/'supabase/migrations'/name,inputs/name))for name in extra]
 assert sha(extras[5][1])=='008a0507e583c7fc57f64ac3f8db70fb8e27936cae2c7d313fd8fcc3ca2eb00c'
 assert sha(extras[7][1])=='67de6de76ad32cc1f59c394b730c47c3f30b2a7890718050152a846d8d5c280a'
 platform_prerequisite=capture(ROOT/'scripts/sql/receipt_transport_platform_prerequisites.sql',inputs/'receipt_transport_platform_prerequisites.sql')
 platform_reference=capture(ROOT/'docs/release/rapid-completion-2026-10-02/ordinary-current201-attempt1/current_ordinary_installer_rehearsal.py',inputs/'accepted201-platform-reference.py')
 sql=capture(STAGE/'promote/supabase/migrations/20261002050000_receipt_terminal_source_projection.sql',inputs/'500.sql')
 capture(STAGE/'prepare_projection.py',inputs/'prepare_projection.py');capture(STAGE/'source_projection.sql.in',inputs/'source_projection.sql.in')
 cases_body=capture(STAGE/'projection_cases.py',inputs/'projection_cases.py')
 predecessors=json.loads(capture(STAGE/'predecessor-bindings.json',inputs/'predecessor-bindings.json'))
 result=dict(status='running',started_at=now(),checks=[],target={},source_bindings=bindings,migration_sha256=sha(sql),
  scope='192 exact retained prerequisites restored plus nine exact current160/2330/2340/2350/2355/300/315/400/410 DDL; narrow500 actual SQL/service/worker/source-race proof; no newly replayed201/full candidate or hosted/provider/device/store claim',
  prerequisites_count=201,checkpoint_restore=True,jwt_verified=False,vault_crypto_verified=False,hosted_written=False,sms_sent=False,device_used=False)
 save(report/'execution-binding.json',result)
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 original_command=m.command;counter=0;command_lock=threading.Lock()
 def recorded(args,text=None,check=True,timeout=120):
  nonlocal counter
  with command_lock:counter+=1;index=counter
  prefix=commands/f'{index:05d}';start=now();r=original_command(args,text,False,timeout)
  prefix.with_suffix('.stdout').write_text(r.stdout);prefix.with_suffix('.stderr').write_text(r.stderr)
  save(prefix.with_suffix('.json'),dict(argv=[x if not x.startswith('POSTGRES_PASSWORD=')else'POSTGRES_PASSWORD=<generated-local-fixture>'for x in args],input_sha256=sha(text.encode())if text is not None else None,started_at=start,finished_at=now(),exit_code=r.returncode,stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode())))
  if check and r.returncode:raise RuntimeError('recorded command failed: '+r.stderr[-3500:])
  return r
 m.command=recorded
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'source_projection',result['target'])as t:
   save(report/'target-handle.json',result['target'])
   t.sql("do $$begin if not exists(select 1 from pg_roles where rolname='supabase_functions_admin')then create user supabase_functions_admin noinherit createrole login noreplication;end if;end$$;",label='exact cache issue_pg_net_access managed role prerequisite')
   wrapper=re.search(r'create or replace function graphql_public\.graphql\([\s\S]*?\$\$;',checkpoint.decode()).group(0)
   acl='GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO postgres;'
   restore=checkpoint.decode().replace(acl,wrapper+'\nalter function graphql_public.graphql(text,text,jsonb,jsonb)owner to supabase_admin;\n'+acl,1)
   # Match the accepted current201 platform owner at extension creation,
   # rather than granting ordinary app code direct cron table DML.
   cron_create='CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;'
   assert checkpoint.decode().count(cron_create)==1
   restore=restore.replace(cron_create,'set role supabase_admin;'+cron_create+'reset role;',1)
   net_create='CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;'
   assert checkpoint.decode().count(net_create)==1
   restore=restore.replace(net_create,'set role supabase_admin;'+net_create+'reset role;',1)
   (inputs/'executed-snapshot-restore.sql').write_text(restore)
   result['snapshot_restore']=dict(raw_sha256=sha(checkpoint),executed_sha256=sha(restore.encode()),wrapper_sha256=sha(wrapper.encode()),app_or_auth_stub=False)
   t.sql(restore,label='exact captured192-prerequisite synthetic source snapshot restore')
   net_shape=t.json("select jsonb_build_object('extension',(select extversion from pg_extension where extname='pg_net'),'tables',(select jsonb_agg(jsonb_build_object('relation',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl))from pg_class c where c.oid in('net._http_response'::regclass,'net.http_request_queue'::regclass)),'api_rights',(select jsonb_agg(jsonb_build_array(r.name,t.name,has_table_privilege(r.name,t.name,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'),has_any_column_privilege(r.name,t.name,'SELECT,INSERT,UPDATE,REFERENCES')))from(values('anon'),('authenticated'),('service_role'))r(name)cross join(values('net._http_response'),('net.http_request_queue'))t(name))); ")
   save(report/'observed-restored-pg-net-platform.json',net_shape)
   platform_metadata="alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;"
   assert platform_metadata in platform_reference.decode()
   t.sql(platform_metadata,label='same declared retained trusted pg_net metadata as accepted root201 local fixture; not shipping authority')
   result['trusted_pg_net_fixture']='exact owner/definer/search_path metadata setup reused from sealed root201 fixture; runtime managed metadata not attested'
   # Extension-member ACLs are not restored by this pg_dump checkpoint. Apply
   # the real160 private-table platform prerequisite on actual pg_net tables;
   # its original schema/ACL/index validation remains unchanged. This explicit
   # isolated platform normalization is not a managed-host permission claim.
   t.sql(platform_prerequisite.decode(),label='exact reviewed actual pg_net owner-only table/column ACL/read/index prerequisite')
   result['pg_net_platform_normalization']='exact reviewed owner-gated platform table/column ACL/read/index script on real extension tables; managed hosted permissions not attested'
   for name,b in extras:t.sql(b.decode(),label='exact real prerequisite '+name)
   t.sql('update auth.sessions set not_after=clock_timestamp()+interval \'2 hours\'where id='+q(m.SID)+'and user_id='+q(m.UID)+';',label='refresh only retained synthetic approved operator session expiry; no Auth/GoTrue/hosted session claim')
   t.sql('grant execute on function cron.alter_job(bigint,text,text,text,text,boolean)to postgres;',user='supabase_admin',label='exact accepted201 cron owner API execution prerequisite; no direct DML grant')
   save(report/'observed-cron-platform-owner.json',t.json("select jsonb_build_object('extension_owner',(select pg_get_userbyid(extowner)from pg_extension where extname='pg_cron'),'job_owner',(select pg_get_userbyid(relowner)from pg_class where oid='cron.job'::regclass),'schedule_owner',(select pg_get_userbyid(proowner)from pg_proc where oid='cron.schedule(text,text,text)'::regprocedure),'installer_direct_dml',has_table_privilege('postgres','cron.job','INSERT,UPDATE,DELETE,MAINTAIN'));"))
   result['cron_platform_fixture']='same accepted201 supabase_admin extension creation and exact alter_job owner API grant; no direct cron DML or hosted parity'
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='demote actual500 installer to ordinary owner')
   case('500 actual installer is NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t')
   ordinary_cron=t.json("select jsonb_build_object('nosuperuser',not(select rolsuper from pg_roles where rolname=current_user),'extension_owner',(select pg_get_userbyid(extowner)from pg_extension where extname='pg_cron'),'job_owner',(select pg_get_userbyid(relowner)from pg_class where oid='cron.job'::regclass),'schedule_owner',(select pg_get_userbyid(proowner)from pg_proc where oid='cron.schedule(text,text,text)'::regprocedure),'installer_direct_dml',has_table_privilege('postgres','cron.job','INSERT,UPDATE,DELETE,MAINTAIN')); ")
   save(report/'actual-ordinary-cron-owner-readback.json',ordinary_cron)
   case('ordinary application owner has no cron table DML and uses matching platform owner APIs',ordinary_cron==dict(nosuperuser=True,extension_owner='supabase_admin',job_owner='supabase_admin',schedule_owner='supabase_admin',installer_direct_dml=False))
   owner_api=t.json("begin;select cron.schedule('collect-projection-private-owner-probe','0 0 1 1 *','select 1');select jsonb_build_object('creator_owned',exists(select 1 from cron.job where jobname='collect-projection-private-owner-probe'and username=current_user),'unscheduled',cron.unschedule('collect-projection-private-owner-probe'));rollback;")
   save(report/'actual-ordinary-cron-owner-api-probe.json',owner_api)
   case('ordinary application owner schedules and unschedules through real APIs with full rollback',owner_api==dict(creator_owned=True,unscheduled=True)and t.scalar("select not exists(select 1 from cron.job where jobname='collect-projection-private-owner-probe');")=='t')

   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
   svc="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expr,service=False):return t.json('begin;'+(svc if service else auth)+'select '+expr+';commit;')
   def bad(expr,error,label,service=False):
    r=t.sql('begin;'+(svc if service else auth)+'select '+expr+';rollback;',check=False,label=label);case(label,r.returncode!=0 and error in r.stderr)
   # Existing immutable delivered/read evidence is nonempty before500 installs
   # its private mirror. These declared owner-only fixture rows refer to actual
   # baseline source/exception/Auth UUIDs; no external delivery is represented.
   t.sql("select collect_ops.observe('payment',"+q(m.PAYMENT)+",array['VERIFICATION_PENDING'],'{\"pre500_fixture\":true}');")
   original_exception=t.scalar("select id from collect_ops.exceptions where source_kind='payment'and source_id="+q(m.PAYMENT)+"and reason_code='VERIFICATION_PENDING';")
   old_unread,old_read=uid(),uid()
   for escalation,recipient in [(old_unread,m.UID),(old_read,m.OTHER)]:
    t.sql('begin;insert into collect_ops.exception_escalations(id,exception_id,source_revision,recipient_id,reason_code,state,completed_at)select '+q(escalation)+',id,revision,'+q(recipient)+",'operator_escalation','delivered',clock_timestamp()from collect_ops.exceptions where id="+q(original_exception)+';insert into collect_ops.exception_inbox_deliveries values('+q(escalation)+','+q(recipient)+',clock_timestamp());'+('insert into collect_ops.exception_inbox_reads values('+q(escalation)+','+q(recipient)+',clock_timestamp());'if escalation==old_read else'')+'commit;',label='explicit immutable populated checkpoint inbox fixture')
   old_functions=t.json("select jsonb_agg(jsonb_build_object('oid',oid,'owner',proowner,'acl',proacl,'args',proargtypes::text,'result',prorettype,'config',proconfig,'volatile',provolatile,'definer',prosecdef)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_ops'::regnamespace,'collect_receipt_operations'::regnamespace,'collect_receipt_telemetry'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_receipt_successors'::regnamespace);")
   tables=[('public','payments'),('public','payment_provider_confirmations'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','sms_notification_outbox'),('collect_receipt_policy','content_evidence'),('collect_hybrid','receipt_business_events'),('collect_receipt_operations','handled_events'),('collect_receipt_operations','backlog_results'),('collect_ops','receipt_exception_work'),('collect_ops','receipt_exception_scans'),('collect_ops','receipt_exception_scan_observations'),('collect_ops','receipt_backlog_sweep_sources'),('collect_ops','receipt_worker_jobs'),('collect_ops','receipt_worker_dispatches'),('collect_ops','receipt_worker_receipts'),('collect_ops','receipt_worker_expirations'),('collect_ops','exception_inbox_deliveries'),('collect_ops','exception_inbox_reads'),('collect_ops','exception_escalations')]
   columns=m.columns(t,tables);before=m.fingerprints(t,columns)
   stable=t.json("select jsonb_build_object('flags',(select jsonb_agg(to_jsonb(x)order by key)from public.feature_flags x),'policy',(select to_jsonb(x)from collect_receipt_operations.policy x),'worker',(select to_jsonb(x)from collect_ops.receipt_worker_configuration x),'telemetry',(select to_jsonb(x)from collect_receipt_telemetry.configuration x),'successors',(select to_jsonb(x)from collect_receipt_successors.configuration x),'cron',(select jsonb_agg(to_jsonb(x)order by jobid)from cron.job x));")
   # One mutated exact scanner predecessor is sufficient to prove the complete
   # guard loop refuses atomically; every captured actual prosrc is compared.
   signature=predecessors['guards'][0][0];definition=t.json('select to_jsonb(pg_get_functiondef('+q(signature)+'::regprocedure));')
   r=t.sql('begin;'+definition.replace('$function$','$function$-- explicit synthetic predecessor drift\n',1)+';'+sql.decode(),check=False,label='unexpected scanner predecessor refused before publication')
   case('500 drift refuses without private namespace or original journal change',r.returncode!=0 and 'receipt_source_projection_predecessor_drift'in r.stderr and t.scalar("select to_regnamespace('collect_receipt_source_projection')is null;")=='t'and m.fingerprints(t,columns)==before)
   case(str(len(predecessors['guards']))+' exact causal predecessor bodies match before install',all(t.scalar('select encode(extensions.digest(prosrc,\'sha256\'),\'hex\')from pg_proc where oid='+q(sig)+'::regprocedure;')==digest for sig,digest in predecessors['guards']))
   t.sql(sql.decode(),label='exact500 ordinary-owner migration')
   case('500 preserves every captured original financial/source/work/worker journal',m.fingerprints(t,columns)==before)
   functions=t.json("select jsonb_agg(jsonb_build_object('oid',oid,'owner',proowner,'acl',proacl,'args',proargtypes::text,'result',prorettype,'config',proconfig,'volatile',provolatile,'definer',prosecdef)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_ops'::regnamespace,'collect_receipt_operations'::regnamespace,'collect_receipt_telemetry'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_receipt_successors'::regnamespace);")
   case('every original function OID owner ACL signature config and volatility stays exact',functions==old_functions)
   after_stable=t.json("select jsonb_build_object('flags',(select jsonb_agg(to_jsonb(x)order by key)from public.feature_flags x),'policy',(select to_jsonb(x)from collect_receipt_operations.policy x),'worker',(select to_jsonb(x)from collect_ops.receipt_worker_configuration x),'telemetry',(select to_jsonb(x)from collect_receipt_telemetry.configuration x),'successors',(select to_jsonb(x)from collect_receipt_successors.configuration x),'cron',(select jsonb_agg(to_jsonb(x)order by jobid)from cron.job x));")
   case('all flags authority defaults policy and cron stay exact and inactive',stable==after_stable and not after_stable['worker']['enabled']and not after_stable['telemetry']['enabled']and not after_stable['successors']['enabled'])
   for role in ['anon','authenticated','service_role']:
    case(role+' cannot access any private projection table or helper',t.scalar("select not has_schema_privilege("+q(role)+",'collect_receipt_source_projection','USAGE')and not exists(select 1 from pg_class c where c.relnamespace='collect_receipt_source_projection'::regnamespace and c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')))and not exists(select 1 from pg_proc p where p.pronamespace='collect_receipt_source_projection'::regnamespace and has_function_privilege("+q(role)+",p.oid,'EXECUTE'));")=='t')
   case('atomic initial live/admission backfill equals original source membership',t.scalar("with sources as(select 'receipt_event'kind,event_id id from collect_receipt_operations.event_deferrals union select 'receipt_backlog',snapshot_id from collect_ops.receipt_backlog_sweep_sources union select source_kind,source_id from collect_ops.receipt_exception_work where processed_at is null)select not exists((select kind,id from sources except select source_kind,source_id from collect_receipt_source_projection.live)union all(select source_kind,source_id from collect_receipt_source_projection.live except select kind,id from sources))and not exists(select 1 from collect_receipt_source_projection.live l left join collect_receipt_source_projection.admissions a on a.id=l.admission_id and a.source_kind=l.source_kind and a.source_id=l.source_id where a.id is null);")=='t')
   case('atomic populated unread mirror preserves exact immutable recipient delivery/read evidence',t.scalar('select count(*)=1 and bool_and(escalation_id='+q(old_unread)+')from collect_receipt_source_projection.unread_inbox;')=='t')
   t.sql('begin;'+auth+'select public.admin_read_exception_escalation_v1('+q(old_unread)+');rollback;',label='actual Admin read and mirror deletion rollback together')
   case('actual rolled-back Admin read cannot remove original unread hold',t.scalar('select exists(select 1 from collect_receipt_source_projection.unread_inbox where escalation_id='+q(old_unread)+')and not exists(select 1 from collect_ops.exception_inbox_reads where escalation_id='+q(old_unread)+');')=='t')
   rollback_delivery=uid()
   t.sql('begin;insert into collect_ops.exception_escalations(id,exception_id,source_revision,recipient_id,reason_code,state,completed_at)select '+q(rollback_delivery)+',id,revision+1,'+q(m.UID)+",'operator_escalation','delivered',clock_timestamp()from collect_ops.exceptions where id="+q(original_exception)+';insert into collect_ops.exception_inbox_deliveries values('+q(rollback_delivery)+','+q(m.UID)+',clock_timestamp());rollback;',label='original delivery and unread hold rollback together')
   case('rolled-back original delivery cannot leave private mirror membership',t.scalar('select not exists(select 1 from collect_ops.exception_inbox_deliveries where escalation_id='+q(rollback_delivery)+')and not exists(select 1 from collect_receipt_source_projection.unread_inbox where escalation_id='+q(rollback_delivery)+');')=='t')
   bad('public.admin_read_exception_escalation_v1('+q(old_read)+')','exception_escalation_delivery_unavailable','current Admin cannot read another original recipient delivery')
   read=call('public.admin_read_exception_escalation_v1('+q(old_unread)+')')
   case('current Admin original read atomically removes only matching mirror membership',not read['source_resolved']and t.scalar('select not exists(select 1 from collect_receipt_source_projection.unread_inbox)and exists(select 1 from collect_ops.exception_inbox_reads where escalation_id='+q(old_unread)+');')=='t')
   case('real160 transport schema remains installed without causal stub',t.scalar('select collect_ops.receipt_transport_schema_valid();')=='t')
   if a.setup_only:
    result['status']='setup_passed';result['scope']='separate ordinary pg_cron owner/owner-API probe over exact same retained201 prerequisites and500; no main-case rerun/count addition';result['cases_executed']=False
   else:
    # Reuse real SQL enrollment/normal posting/ensure paths. JWT claims here
    # are declared synthetic trusted-edge inputs; this is not JWT validation.
    pref='3059301306072a8648ce3d020106082a8648ce3d03010703420004';point='6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5'
    key=bytes.fromhex(pref+point);kh=sha(key);pub=base64.b64encode(key).decode()
    principal=call('public.admin_enroll_receipt_operations_identity_v2('+','.join([q(uid()),q(pub),q(kh),"clock_timestamp()+interval '1 day'"])+')')['principal_id']
    def operation(action,payload={}):
     req=uid();return call('public.receipt_operations_execute_v2('+','.join([q(principal),q(req),q(kh),q(sha(json.dumps([req,action,payload]).encode())),'clock_timestamp()',q(action),q(json.dumps(payload))+'::jsonb'])+')',True)
    operation('prove_key');call('public.admin_activate_receipt_operations_identity_v2('+','.join(map(q,[principal,uid(),kh]))+')')
    gateway_point='7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1'
    gateway_key=bytes.fromhex(pref+gateway_point);gkh=sha(gateway_key);gateway_pub=base64.b64encode(gateway_key).decode()
    device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[uid(),uid(),gateway_pub,gkh,'c'*64]))+')')['device_id']
    hp=dict(sms_permission=True,network='validated',telephony='ready',sim_selected=True,sim_revision_sha256='d'*64,local_pause=False,reported_at=now())
    call('public.gateway_heartbeat_v1('+','.join(map(q,[device,uid(),sha(json.dumps(hp).encode())]))+','+q(json.dumps(hp))+'::jsonb)',True)
    call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
    caps={k:10 if k=='run_actions'else 20 if k=='run_sms_segments'else 100 for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
    call('public.admin_configure_receipt_operations_v2('+','.join([q(uid()),'1',"'Live-limited'",'false',"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(caps))+'::jsonb','true','24',"'Synthetic projection terminal proof only'","clock_timestamp()+interval '100 seconds'"])+')')
    run=operation('begin_run');fence=dict(run_id=run['run_id'],fence_version=run['fence_version'])
    def post(n):
     pid,raw,event=uid(),uid(),uid();ref='PROJECTION-'+str(n);wallet=sha(b'+250788971001')
     t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic projection proof'","encode(extensions.digest('Synthetic projection proof','sha256'),'hex')",q(wallet),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wallet),'100',q(ref),"'unallocated'","'Synthetic projection payer'"])+');insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values('+','.join([q(pid),q(event),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wallet),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-'+ref),q(wallet),'100','clock_timestamp()',"repeat('c',64)"])+');commit;',label='actual trusted normal posting '+str(n))
     s=t.scalar('select id from collect_hybrid.momo_balance_snapshots where payment_id='+q(pid)+"and event_type='receipt';");e=t.json('select to_jsonb(e)from collect_hybrid.receipt_business_events e where payment_id='+q(pid)+"and event_kind='payment_posted';")
     t.sql("update public.parsed_payment_events set allocation_status='allocated'where id="+q(event)+';',label='explicit normal fixture closes parsed allocation evidence onto its actual posted member payment')
     return dict(payment=pid,snapshot=s,event=e,parsed=event,raw=raw)
    def scan(limit=25,request=None,expires=None):return call('public.process_receipt_deferral_exceptions_v1('+q(request or uid())+','+str(limit)+','+(q(expires)if expires else "clock_timestamp()+interval '100 seconds'")+')',True)
    def live(kind,source):return t.scalar('select exists(select 1 from collect_receipt_source_projection.live where source_kind='+q(kind)+'and source_id='+q(source)+');')=='t'
    def certs(kind,source):return int(t.scalar('select count(*)from collect_receipt_source_projection.certificates where source_kind='+q(kind)+'and source_id='+q(source)+';'))
    def drain(n=8):return [scan()for _ in range(n)]
    normal=post('terminal');ensured=operation('ensure_receipt',dict(**fence,event_id=normal['event']['id'],expected_source_version=normal['event']['source_version']))
    case('real financial/operations path durably handles original terminal event',ensured['business_handled']and ensured['code']in('RECEIPT_ENQUEUED','RECEIPT_EXISTS')and live('receipt_event',normal['event']['id']))
    drain();case('terminal event retires only with exact immutable handled receipt/content proof',not live('receipt_event',normal['event']['id'])and certs('receipt_event',normal['event']['id'])==1)
    cases=types.ModuleType('captured_cases');exec(compile(cases_body,str(inputs/'projection_cases.py'),'exec'),cases.__dict__)
    cases.run(t,m,call,case,scan,drain,live,certs,post,operation,principal,run['run_id'],normal,ensured['receipt_id'],device,save,report)
    result['status']='passed'
   final_bodies=[]
   for signature,digest in predecessors['guards']:
    expected=predecessors['scanner_final_sha256']if signature==predecessors['guards'][0][0]else digest
    observed=t.scalar('select encode(extensions.digest(prosrc,\'sha256\'),\'hex\')from pg_proc where oid='+q(signature)+'::regprocedure;')
    final_bodies.append(dict(signature=signature,expected_sha256=expected,observed_sha256=observed))
   save(report/'unchanged-final-producer-bodies.json',final_bodies)
   case('all original producer bodies remain exact and scanner matches frozen shipping body',all(x['expected_sha256']==x['observed_sha256']for x in final_bodies))
   case('current unread mirror exactly equals original deliveries minus same-recipient immutable reads',t.scalar("with exact as(select d.escalation_id,e.exception_id,d.recipient_id from collect_ops.exception_inbox_deliveries d join collect_ops.exception_escalations e on e.id=d.escalation_id where not exists(select 1 from collect_ops.exception_inbox_reads r where r.escalation_id=d.escalation_id and r.recipient_id=d.recipient_id))select not exists((select *from exact except select *from collect_receipt_source_projection.unread_inbox)union all(select *from collect_receipt_source_projection.unread_inbox except select *from exact));")=='t')
   save(report/'observed-final-private-projection.json',t.json("select jsonb_build_object('live',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from collect_receipt_source_projection.live x),'admissions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from collect_receipt_source_projection.admissions x),'certificates',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from collect_receipt_source_projection.certificates x));"))
   case('every frozen source/tool input remains unchanged',all(pathlib.Path(p).read_bytes()==b for p,b in source_bytes.items()))
 except BaseException as e:
  result['status']='failed';result['error']=str(e);raise
 finally:
  result['finished_at']=now();result['command_receipts']=counter;save(report/'result.json',result)
if __name__=='__main__':main()
