#!/usr/bin/env python3
"""Guarded disposable gateway DB UAT. No remote URL or real device accepted."""
import argparse,base64,datetime,hashlib,json,pathlib,time,uuid
import collect_admin_combined_upgrade_uat as c
u=c.u;f=c.foundation;ROOT=u.ROOT
MIGRATION=ROOT/'supabase/migrations/20260930211605_android_gateway_identity.sql'
PREFIX='3059301306072a8648ce3d020106082a8648ce3d03010703420004'
POINTS=[
 '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296'+'4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
 '7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978'+'07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1',
]
def literal(value):return "'"+str(value).replace("'","''")+"'"
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--report-dir',required=True);args=parser.parse_args()
 out=pathlib.Path(args.report_dir).resolve();assert not out.exists();out.mkdir(parents=True)
 evidence={'kind':'gateway_identity_schema153_isolated','production_written':False,'source_written':False,'real_device_enrolled':False,'carrier_called':False,'provider_called':False,'db_signature_verification':False,'cases':[]}
 def save():(out/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 def case(name,fn):
  detail=fn();evidence['cases'].append({'name':name,'status':'pass','detail':detail});save();print('PASS '+name,flush=True);return detail
 db='collect_gateway_identity_'+uuid.uuid4().hex[:12];made=False;sessions=[]
 f.RAW_QUERY_LOG=out/'queries.sql';u.SQL_LOG=out/'queries.log';u.CONCURRENCY_LOG=out/'concurrency.log'
 try:
  labels=json.loads(u.command([u.DOCKER,'inspect',u.CONTAINER,'--format','{{json .Config.Labels}}']).stdout)
  ports=json.loads(u.command([u.DOCKER,'inspect',u.CONTAINER,'--format','{{json .HostConfig.PortBindings}}']).stdout)
  assert labels['com.supabase.cli.project']==u.PROJECT and labels['com.docker.compose.project']==u.PROJECT
  assert all(x['HostPort']=='55722' for x in ports['5432/tcp'])
  config=json.loads(u.psql('postgres',"select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'));").stdout);assert config=={'cron':'off','net':'0'}
  dump=(c.BASELINE/'schema-only.sql').read_bytes();acl=(c.BASELINE/'api-acl.sql').read_bytes();assert c.sha(dump)==c.DUMP_HASH and c.sha(acl)==c.ACL_HASH
  evidence['baseline']={'metadata':{'count':153,'latest':'20260930220000'},'schema_sha256':c.DUMP_HASH,'acl_sha256':c.ACL_HASH,'owners_normalized':True,'excluded_runtime':['pg_cron','pg_net','pg_graphql','pg_stat_statements'],'source':'Frozen attempt8 schema-only capture; no source rows or current catalog copied'}
  evidence['migration_sha256']=c.sha(MIGRATION.read_bytes());evidence['runner_sha256']=c.sha(pathlib.Path(__file__).read_bytes());evidence['database']=db
  u.psql('postgres','create database '+db+' template template0;');made=True
  restored=u.psql(db,'create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+dump.decode()+acl.decode(),False)
  (out/'restore.log').write_text(restored.stdout+restored.stderr);assert restored.returncode==0,restored.stderr[-3000:]
  f.seed(db)
  sql=lambda text:u.psql(db,text).stdout.strip()
  owned=lambda text:json.loads(sql(f.service(text)).splitlines()[-1])
  sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+f.service(f.payment_sql('99710000-0000-4000-8000-000000049999',amount=50)))
  job=sql("select id from collect_hybrid.sms_notification_outbox limit 1;")
  claim=owned("select public.collect_claim_receipt('%s','%s','gateway-synthetic-prior','%s');"%(u.UID,job,uuid.uuid4()))
  exact=owned("select public.collect_get_claimed_receipt('%s','%s','%s',%d);"%(u.UID,job,claim['claim_token'],claim['fence_version']))
  confirmation=str(uuid.uuid4());owned("select public.collect_confirm_receipt('%s','%s','%s',%d,%d,'%s','%s');"%(u.UID,job,claim['claim_token'],claim['fence_version'],exact['destination_revision'],exact['body_sha256'],confirmation))
  attempt=owned("select public.collect_record_send_start('%s','%s','%s',%d,'%s');"%(u.UID,job,claim['claim_token'],claim['fence_version'],confirmation))
  sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
  before=f.business_fingerprint(db);evidence['business_before_install']=before
  installed=u.psql(db,MIGRATION.read_text(),False);(out/'install.log').write_text(installed.stdout+installed.stderr);assert installed.returncode==0,installed.stderr[-5000:]
  case('gateway install preserves nonempty prior financial receipt and attempt',lambda:f.equal(before,f.business_fingerprint(db)))
  run_cases(db,case,evidence,out,sessions,attempt,before)
  evidence['status']='pass'
 except Exception as error:evidence['status']='failed';evidence['failure']=str(error);save();raise
 finally:
  for s in sessions:
   try:s.close()
   except Exception as error:evidence.setdefault('cleanup_errors',[]).append(str(error))
  if made:evidence['isolated_database_removed']=u.psql('postgres','drop database '+db+' with(force);',False).returncode==0
  f.RAW_QUERY_LOG=None;u.SQL_LOG=None;u.CONCURRENCY_LOG=None
  evidence['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();evidence['case_count']=len(evidence['cases']);save()
def run_cases(db,case,evidence,out,sessions,attempt,before):
 sql=lambda text:u.psql(db,text).stdout.strip()
 check=c.check
 truth=lambda text:check(sql(text)=='t')
 def service_sql(text):return 'begin;set local role service_role;select set_config(\'request.jwt.claims\',\'{"role":"service_role"}\',true);'+text+';commit;'
 def service(text):return json.loads(sql(service_sql(text)).splitlines()[-1])
 def error(text,state,reason=None,mode='service'):
  result=u.psql(db,service_sql(text) if mode=='service' else text,False);assert result.returncode and state+':' in result.stderr and (reason is None or reason in result.stderr),result.stderr
  return {'sqlstate':state,'reason':reason}
 def spki(n):
  raw=bytes.fromhex(PREFIX+POINTS[n]);return base64.b64encode(raw).decode(),hashlib.sha256(raw).hexdigest()
 cert='c'*64;key,key_sha=spki(0);install=str(uuid.uuid4());enroll_req=str(uuid.uuid4())
 def enrollment(req=enroll_req,installation=install,public_key=key,digest=key_sha,certificate=cert):return "select public.admin_enroll_gateway_device_v1('%s','%s','%s','%s','%s');"%(req,installation,public_key,digest,certificate)
 def change(device,action,req=None,digest=key_sha,certificate=cert):return "select public.admin_%s_gateway_device_v1('%s','%s','%s','%s');"%(action,device,req or uuid.uuid4(),digest,certificate)
 names=['devices','admin_requests','requests','health_observations','dispatch_arms','segment_callbacks']
 case('six gateway tables have RLS and no API direct grants',lambda:truth("select count(*)=18 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE')) from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relnamespace='collect_gateway'::regnamespace and c.relname in(%s);"%','.join(literal(x)for x in names)))
 case('gateway private schema and helpers expose no API usage or execution',lambda:truth("select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_gateway'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE')) and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_schema_privilege(r,'collect_gateway','USAGE'));"))
 case('owner RPCs grant only authenticated execution',lambda:truth("select count(*)=3 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('admin_enroll_gateway_device_v1','admin_activate_gateway_device_v1','admin_revoke_gateway_device_v1');"))
 case('five service RPCs deny anon and authenticated execution',lambda:truth("select count(*)=5 and bool_and(has_function_privilege('service_role',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE')) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('gateway_device_key_v1','gateway_heartbeat_v1','gateway_reconcile_v1','gateway_callback_v1','gateway_dispatch_grant_v1');"))
 for role in ['anon','service_role']:case(role+' cannot enroll handset owner identity',lambda role=role:u.expected_error(db,enrollment(),'42501',role=role))
 case('missing current owner session cannot enroll',lambda:u.expected_error(db,enrollment(),'42501',sid=str(uuid.uuid4())))
 for label,mutation in [
  ('expired owner session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='%s';"%u.SID),
  ('revoked owner grant',"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='%s';"%u.UID),
  ('revoked current approval',"update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='%s';"%u.UID),
  ('missing notification management',"delete from public.admin_role_permissions where role_id='%s' and permission_name='notifications.manage';"%f.ROLE),
  ('missing system health',"delete from public.admin_role_permissions where role_id='%s' and permission_name='system_health.read';"%f.ROLE),
 ]:
  case('owner enrollment denies '+label,lambda mutation=mutation:error('begin;'+mutation+u.auth()+enrollment()+'rollback;','42501',mode='owner'))
 bad=base64.b64encode(bytes.fromhex(PREFIX)+bytes(64)).decode()
 for label,query in [('wrong key SHA',enrollment(digest='f'*64)),('invalid certificate SHA',enrollment(certificate='invalid')),('off-curve public point',enrollment(public_key=bad,digest=hashlib.sha256(base64.b64decode(bad)).hexdigest())),('non-SPKI key bytes',enrollment(public_key='a'*122+'=='))]:
  case('enrollment refuses '+label,lambda query=query:u.expected_error(db,query,'22023','gateway_enrollment_invalid'))
 enrolled=u.call(db,enrollment());device=enrolled['device_id'];evidence['synthetic_device_id']=device
 (out/'observed-enrollment.json').write_text(json.dumps(enrolled,indent=2)+'\n')
 case('valid synthetic public curve point enrolls pending only',lambda:check(enrolled['state_at_action']=='pending' and not enrolled['replay']))
 replay=u.call(db,enrollment());case('owner enrollment exact replay retains same immutable device',lambda:check(replay['device_id']==device and replay['replay']))
 case('installation cannot silently enroll a replacement key',lambda:u.expected_error(db,enrollment(req=str(uuid.uuid4())),'22023','gateway_installation_already_enrolled'))
 case('owner request UUID cannot change installation binding',lambda:u.expected_error(db,enrollment(installation=str(uuid.uuid4())),'22023','gateway_owner_request_conflict'))
 case('other approved owner cannot replay original owner request',lambda:u.expected_error(db,enrollment(),'22023','gateway_owner_request_conflict',uid=u.OTHER,sid=u.OTHERSID))
 case('activation requires signed-service recent key possession',lambda:u.expected_error(db,change(device,'activate'),'55000','gateway_key_possession_required'))
 lookup=service("select public.gateway_device_key_v1('%s');"%device);(out/'observed-service-public-key.json').write_text(json.dumps(lookup,indent=2)+'\n')
 case('service lookup exposes only public key identity metadata',lambda:check(set(lookup)=={'device_id','state','public_key_spki_base64','key_sha256','installation_id','signing_certificate_sha256'} and lookup['key_sha256']==key_sha))
 for role in ['anon','authenticated']:case(role+' cannot read service gateway key endpoint',lambda role=role:u.expected_error(db,"select public.gateway_device_key_v1('%s');"%device,'42501',role=role))
 def now():return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')
 def health():return {'sms_permission':True,'network':'validated','telephony':'ready','sim_selected':True,'sim_revision_sha256':'a'*64,'local_pause':False,'reported_at':now()}
 def request(action,payload,dev=device,req=None,digest=None):
  req=req or str(uuid.uuid4());digest=digest or hashlib.sha256(json.dumps({'action':action,'device_id':dev,'request_id':req,'issued_at':now(),'payload':payload}).encode()).hexdigest()
  return "select public.gateway_%s_v1('%s','%s','%s',%s::jsonb);"%(action,dev,req,digest,literal(json.dumps(payload)))
 healthy=health();health_req=str(uuid.uuid4());health_query=request('heartbeat',healthy,req=health_req,digest='a'*64)
 recorded=service(health_query);(out/'observed-heartbeat.json').write_text(json.dumps(recorded,indent=2)+'\n')
 case('pending identity records immutable typed device observation',lambda:check(recorded['carrier_proof'] is False and not recorded['replay']))
 case('heartbeat request replay never advances observation time or row count',lambda:check(service(health_query)=={**recorded,'replay':True} and sql('select count(*) from collect_gateway.health_observations;')=='1'))
 case('heartbeat digest collision is refused without overwritten observation',lambda:error(request('heartbeat',healthy,req=health_req,digest='b'*64),'22023','gateway_request_conflict'))
 for label,patch in [('missing field',{'telephony':None}),('string bool',{'sms_permission':'true'}),('unknown network',{'network':'online'}),('null SIM selected',{'sim_revision_sha256':None}),('hash on unselected SIM',{'sim_selected':False}),('unknown field',{'balance_rwf':100}),('wrong timestamp type',{'reported_at':2026}),('invalid UTC date',{'reported_at':'2026-02-31T12:00:00Z'}),('stale report',{'reported_at':'2020-01-01T00:00:00Z'})]:
  case('health rejects '+label,lambda patch=patch:error(request('heartbeat',{**health(),**patch}),'22023'))
 case('activation exact key/cert fingerprints are required',lambda:u.expected_error(db,change(device,'activate',certificate='f'*64),'22023','gateway_identity_mismatch'))
 stale="alter table collect_gateway.health_observations disable trigger user;update collect_gateway.health_observations set ingested_at=clock_timestamp()-interval '3 minutes',reported_at=clock_timestamp()-interval '3 minutes';"
 case('stale server/client health cannot activate identity',lambda:error('begin;'+stale+u.auth()+change(device,'activate')+'rollback;','55000','gateway_key_possession_required',mode='owner'))
 activate_req=str(uuid.uuid4());activated=u.call(db,change(device,'activate',activate_req));(out/'observed-activation.json').write_text(json.dumps(activated,indent=2)+'\n')
 case('current approved owner activates only after recent service health',lambda:check(activated['state_at_action']=='active' and not activated['replay']))
 case('activation exact request replay is stable',lambda:check(u.call(db,change(device,'activate',activate_req))=={**activated,'replay':True}))
 grant_req=str(uuid.uuid4());grant_query=request('dispatch_grant',{},req=grant_req,digest='c'*64);grant=service(grant_query)
 (out/'observed-dispatch-refusal.json').write_text(json.dumps(grant,indent=2)+'\n')
 case('active identity cannot obtain body destination or dispatch grant',lambda:check(grant=={'ok':False,'code':'GATEWAY_DISPATCH_AUTHORITY_PENDING','device_id':device,'request_id':grant_req,'replay':False} and sql('select count(*) from collect_gateway.dispatch_arms;')=='0'))
 case('dispatch refusal exact replay never manufactures grant',lambda:check(service(grant_query)=={**grant,'replay':True} and sql('select count(*) from collect_gateway.dispatch_arms;')=='0'))
 case('client dispatch body destination balance and counts are refused',lambda:error(request('dispatch_grant',{'destination':'private','body':'private','count':1}),'22023','gateway_payload_invalid'))
 reconciliation=service(request('reconcile',{'target_request_id':grant_req}));case('reconciliation reads original durable authority refusal',lambda:check(reconciliation['outcome']=='recorded' and reconciliation['recorded_result']==grant and reconciliation['recorded_action']=='dispatch_grant'))
 case('unknown request reconciliation stays unknown without replaying action',lambda:check(service(request('reconcile',{'target_request_id':str(uuid.uuid4())}))['outcome']=='unknown'))
 key2,sha2=spki(1);enrolled2=u.call(db,enrollment(req=str(uuid.uuid4()),installation=str(uuid.uuid4()),public_key=key2,digest=sha2));device2=enrolled2['device_id']
 case('other device cannot discover first device request outcome',lambda:check(service(request('reconcile',{'target_request_id':grant_req},dev=device2))['outcome']=='unknown'))
 # A duplicate accepted request can arrive while its first transaction is
 # still uncommitted. The device row serializes both durable request writes.
 parallel_req=str(uuid.uuid4());parallel_query=request('heartbeat',health(),dev=device2,req=parallel_req,digest='e'*64)
 pa=u.Session(db,'gateway-heartbeat-first');pb=u.Session(db,'gateway-heartbeat-repeat');sessions.extend([pa,pb])
 pa.write(service_sql(parallel_query).replace(';commit;',';')+"select 'HEARTBEAT_FIRST_HELD';");pa.read('HEARTBEAT_FIRST_HELD')
 pb.write(service_sql(parallel_query)+"select 'HEARTBEAT_REPEAT_DONE';")
 pa.write("commit;select 'HEARTBEAT_FIRST_DONE';");pa.read('HEARTBEAT_FIRST_DONE');repeat=pb.read('HEARTBEAT_REPEAT_DONE')
 case('concurrent exact heartbeat request creates one immutable observation',lambda:truth("select count(*)=1 from collect_gateway.health_observations where request_id='%s';"%parallel_req))
 case('concurrent heartbeat repeat returns replay rather than a new timestamp',lambda:check(any(line.startswith('{') and json.loads(line).get('replay') is True for line in repeat)))
 actual=json.loads(sql("select to_jsonb(a) from collect_hybrid.sms_notification_attempts a where id='%s';"%attempt['attempt_id']))
 def callback(kind='sent',index=0):return {'callback_id':str(uuid.uuid4()),'attempt_id':attempt['attempt_id'],'fence_version':actual['fence_version'],'segment_index':index,'segment_count':1,'body_sha256':actual['body_sha256'],'destination_sha256':actual['destination_sha256'],'callback_kind':kind,'result_code':-1,'tp_status':None,'occurred_at':now()}
 case('signed-service callback without prior arm is denied',lambda:error(request('callback',callback()),'42501','gateway_prior_arm_required'))
 for role in ['authenticated','service_role']:case(role+' cannot insert private dispatch arm',lambda role=role:u.expected_error(db,'insert into collect_gateway.dispatch_arms default values;','42501',role=role))
 # Synthetic historical arm only: no public issuer exists, and no carrier is
 # called. This exercises reconciliation of an already-armed attempt.
 arm_sql="insert into collect_gateway.dispatch_arms(device_id,attempt_id,fence_version,body_sha256,destination_sha256,segment_count) values('%s','%s',%d,'%s','%s',1);"%(device,attempt['attempt_id'],actual['fence_version'],actual['body_sha256'],actual['destination_sha256'])
 sql(arm_sql);(out/'synthetic-prior-arm.sql').write_text('-- Synthetic local-only arm; no sender authority issued through an API.\n'+arm_sql+'\n')
 for label,patch in [('stale fence',{'fence_version':actual['fence_version']+1}),('wrong body',{'body_sha256':'f'*64}),('wrong destination',{'destination_sha256':'f'*64}),('invented segment count',{'segment_count':2}),('out-of-range segment',{'segment_index':1}),('unknown attempt',{'attempt_id':str(uuid.uuid4())})]:
  case('prior arm refuses '+label,lambda patch=patch:error(request('callback',{**callback(),**patch}),'42501','gateway_prior_arm_required'))
 case('other device cannot attach a prior arm callback',lambda:error(request('callback',callback(),dev=device2),'42501','gateway_prior_arm_required'))
 aborted=str(uuid.uuid4());aborted_cb=callback(kind='delivery');aborted_query=request('callback',aborted_cb,req=aborted,digest='f'*64)
 sql(service_sql(aborted_query).replace(';commit;',';rollback;'))
 case('rolled-back callback leaves neither request result nor segment evidence',lambda:truth("select not exists(select 1 from collect_gateway.requests where request_id='%s') and not exists(select 1 from collect_gateway.segment_callbacks where callback_id='%s');"%(aborted,aborted_cb['callback_id'])))
 cb=callback();cb_req=str(uuid.uuid4());cb_query=request('callback',cb,req=cb_req,digest='d'*64)
 ca=u.Session(db,'gateway-callback-first');cr=u.Session(db,'gateway-callback-repeat');sessions.extend([ca,cr])
 ca.write(service_sql(cb_query).replace(';commit;',';')+"select 'CALLBACK_FIRST_HELD';");first_lines=ca.read('CALLBACK_FIRST_HELD')
 cb_result=next(json.loads(line) for line in first_lines if line.startswith('{') and json.loads(line).get('callback_id')==cb['callback_id'])
 cr.write(service_sql(cb_query)+"select 'CALLBACK_REPEAT_DONE';")
 ca.write("commit;select 'CALLBACK_FIRST_DONE';");ca.read('CALLBACK_FIRST_DONE');repeat_lines=cr.read('CALLBACK_REPEAT_DONE')
 case('concurrent callback replay records exactly one segment and one request',lambda:truth("select (select count(*) from collect_gateway.segment_callbacks where callback_id='%s')=1 and(select count(*) from collect_gateway.requests where request_id='%s')=1;"%(cb['callback_id'],cb_req)))
 case('concurrent callback repeat returns original immutable callback result',lambda:check(any(line.startswith('{') and json.loads(line)=={**cb_result,'replay':True} for line in repeat_lines)))
 (out/'observed-callback.json').write_text(json.dumps(cb_result,indent=2)+'\n')
 case('paused existing arm records raw callback without delivery conclusion',lambda:check(cb_result['callback_id']==cb['callback_id'] and cb_result['carrier_proof'] is False and sql("select enabled from public.feature_flags where key='hybrid_sms_notifications';")=='f'))
 case('callback exact UUID/request replay records one immutable segment',lambda:check(service(cb_query)=={**cb_result,'replay':True} and sql('select count(*) from collect_gateway.segment_callbacks;')=='1'))
 case('same callback UUID under new request cannot change journal identity',lambda:error(request('callback',cb),'22023','gateway_callback_conflict'))
 case('second sent callback UUID cannot overwrite a segment outcome',lambda:error(request('callback',callback()),'22023','gateway_callback_conflict'))
 case('gateway identity health refusal and callbacks preserve all sixteen business tables',lambda:f.equal(before,f.business_fingerprint(db)))
 for table in ['admin_requests','requests','health_observations','dispatch_arms','segment_callbacks']:
  case(table+' observations reject mutation even from local fixture owner',lambda table=table:error('delete from collect_gateway.'+table+';','55000','gateway_evidence_immutable',mode='owner'))
 case('retained device cannot be reset to a different key',lambda:error("update collect_gateway.devices set key_sha256=repeat('f',64) where id='%s';"%device,'55000','gateway_identity_immutable',mode='owner'))
 case('retained device cannot be deleted',lambda:error("delete from collect_gateway.devices where id='%s';"%device,'55000','gateway_identity_retained',mode='owner'))
 # Current proof locks serialize service health and owner revocation. After
 # revoke commits, new health is refused but prior-arm evidence is retained.
 a=u.Session(db,'gateway-health-inflight');b=u.Session(db,'gateway-owner-revoke');sessions.extend([a,b])
 inflight=request('heartbeat',health());a.write(service_sql(inflight).replace(';commit;',';')+"select 'HEALTH_HELD';");a.read('HEALTH_HELD')
 revoke_req=str(uuid.uuid4());b.write('begin;'+u.auth()+change(device,'revoke',revoke_req)+"commit;select 'REVOKE_DONE';")
 time.sleep(.2);case('current device health prevents revoke crossing its row lock',lambda:check(service("select public.gateway_device_key_v1('%s');"%device)['state']=='active'))
 a.write("commit;select 'HEALTH_DONE';");a.read('HEALTH_DONE');b.read('REVOKE_DONE')
 case('revoked device retains public identity for reconciliation only',lambda:check(service("select public.gateway_device_key_v1('%s');"%device)['state']=='revoked'))
 case('revoked identity denies new heartbeat',lambda:error(request('heartbeat',health()),'42501','gateway_device_revoked'))
 case('revoked identity denies dispatch even for old refusal request',lambda:error(grant_query,'42501','gateway_device_revoked'))
 case('revoked identity cannot be reactivated',lambda:u.expected_error(db,change(device,'activate'),'55000','gateway_activation_state_invalid'))
 case('revoked identity reconciles an old heartbeat request',lambda:check(service(request('reconcile',{'target_request_id':health_req}))['recorded_result']==recorded))
 delivered=callback(kind='delivery');delivered['tp_status']=0;delivery=service(request('callback',delivered));case('prior arm callback after pause and revocation is durable OS evidence only',lambda:check(delivery['carrier_proof'] is False and sql('select count(*) from collect_gateway.segment_callbacks;')=='2'))
 case('even OS delivery callback leaves existing SMS attempt send_started',lambda:check(sql("select state from collect_hybrid.sms_notification_attempts where id='%s';"%attempt['attempt_id'])=='send_started' and before==f.business_fingerprint(db)))
 case('callback journals survive deletion of original enrollment session',lambda:(sql("delete from auth.sessions where id='%s';"%u.SID),truth("select count(*)=2 from collect_gateway.segment_callbacks;"),truth("select count(*)=1 from collect_gateway.devices where id='%s' and owner_session_id='%s';"%(device,u.SID)))[-1])
 case('device evidence tables have no Auth/session deletion foreign keys',lambda:truth("select not exists(select 1 from pg_constraint c where c.contype='f' and c.connamespace='collect_gateway'::regnamespace and c.confrelid in('auth.users'::regclass,'auth.sessions'::regclass));"))
 case('all gateway work leaves original nonempty canonical finance receipt and attempt unchanged',lambda:f.equal(before,f.business_fingerprint(db)))
 evidence['business_after_gateway']=f.business_fingerprint(db)
 evidence['limits']=['Frozen schema153 plus this gateway migration only; not clean install/full hosted upgrade','Database service role is trusted signature boundary; cryptographic signatures tested separately in Edge unit suite','Known synthetic public points and owner fixtures only; no real enrollment/key/app-certificate/carrier attestation','Synthetic prior arm inserted by isolated fixture owner solely to prove delayed callback handling; no API issuer exists','No Auth credential, SMS send, provider, unattended principal, scheduler, cap/policy grant or outbox/attempt outcome mutation']
if __name__=='__main__':main()
