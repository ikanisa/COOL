#!/usr/bin/env python3
"""Exact captured163 + gateway read upgrade in a private network-none container.

No source/shared/hosted database, credentials, signed JWT, OTP or device is used.
The 124 predecessor financial examples are synthetic trusted-boundary fixtures.
"""
import argparse,base64,datetime,hashlib,json,pathlib,queue,subprocess,threading,time,uuid
import jsonschema
import collect_current_release_upgrade_uat as upgrade
ROOT=upgrade.ROOT
PACKET=ROOT/'docs/release/collect-codex-goal-2026-09-30/current-full-upgrade'
PACKET_MANIFEST_SHA='418583055173d7c1ffbd7ecb60880de79c6624d56f9498f83755d6750a3d8d09'
MIGRATION=ROOT/'supabase/migrations/20261001000200_admin_gateway_reads.sql'
SCHEMA=ROOT/'contracts/collect-admin-gateway-v1.schema.json'
UID,SID,OTHER=upgrade.UID,upgrade.SID,upgrade.OTHER
OTHERSID='99780000-0000-4000-8000-000000010002'
NEW_SESSION='99780000-0000-4000-8000-000000010003'
PREFIX='3059301306072a8648ce3d020106082a8648ce3d03010703420004'
POINTS=[
 '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296'+'4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
 '7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978'+'07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1']
q=upgrade.quoted

def now():return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')
def ts(value):return datetime.datetime.fromisoformat(value.replace('Z','+00:00'))
def auth(uid=UID,sid=SID,role='authenticated'):
 claims={'sub':uid,'session_id':sid,'role':role,'aal':'aal1','exp':int(time.time())+3600}
 return 'set local role '+role+';select set_config(\'request.jwt.claims\','+q(json.dumps(claims))+',true);'
def service():return "set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"

class Session:
 def __init__(self,target,name):
  self.target=target;self.name=name;self.lines=queue.Queue()
  self.p=subprocess.Popen([upgrade.DOCKER,'exec','-i',target.name,'psql','-XqAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=0','-v','VERBOSITY=verbose'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
  threading.Thread(target=lambda:[self.lines.put(line.rstrip())for line in self.p.stdout],daemon=True).start()
 def write(self,sql):
  with(self.target.report/'concurrency-queries.sql').open('a')as log:log.write('-- '+self.name+'\n'+sql+'\n')
  self.p.stdin.write(sql+'\n');self.p.stdin.flush()
 def read(self,marker,timeout=15):
  lines=[];end=time.monotonic()+timeout
  while time.monotonic()<end:
   try:line=self.lines.get(timeout=max(.01,end-time.monotonic()))
   except queue.Empty:break
   lines.append(line)
   with(self.target.report/'concurrency.log').open('a')as log:log.write(self.name+': '+line+'\n')
   if line==marker:return lines
  raise RuntimeError('Concurrency marker timeout: '+marker+' '+repr(lines))
 def close(self):
  if self.p.poll()is None:self.write('rollback;\\q');self.p.wait(timeout=10)

def validate(value,schema):
 jsonschema.Draft202012Validator(schema,format_checker=jsonschema.FormatChecker()).validate(value)
 checked=ts(value['checked_at']);assert ts(value['sample_valid_until'])==checked+datetime.timedelta(seconds=60)
 def identity(i):assert set(i)=={'device_id','installation_id','key_sha256','signing_certificate_sha256'}
 def receipt(r,device=None,request=None,action=None):
  assert ts(r['recorded_at'])<=checked and r['replay']is False
  if device:assert r['device_id']==device
  if request:assert r['request_id']==request
  if action:assert r['state_at_action']=={'enroll':'pending','activate':'active','revoke':'revoked'}[action]
 if 'rows'in value:
  keys=[(ts(r['enrolled_at']),r['device_id'])for r in value['rows']];assert keys==sorted(keys,reverse=True)and len(keys)==len(set(keys))
  assert len(keys)<=value['limit']and value['total']>=len(keys)
  if value['next_cursor']:
   assert len(keys)==value['limit'];assert value['next_cursor']=={'enrolled_at':value['rows'][-1]['enrolled_at'],'device_id':value['rows'][-1]['device_id']}
  for r in value['rows']:
   enrolled=ts(r['enrolled_at']);assert enrolled<=checked
   if r['state']=='pending':assert r['activated_at']is None and r['revoked_at']is None
   if r['state']=='active':assert r['activated_at']is not None and enrolled<=ts(r['activated_at'])<=checked and r['revoked_at']is None
   if r['state']=='revoked':
    assert r['revoked_at']is not None and enrolled<=ts(r['revoked_at'])<=checked
    if r['activated_at']:assert enrolled<=ts(r['activated_at'])<=ts(r['revoked_at'])
   if r['health']:
    h=r['health'];reported,ingested=ts(h['reported_at']),ts(h['ingested_at']);expiry=min(reported,ingested)+datetime.timedelta(seconds=120)
    assert ingested<=checked and ingested-datetime.timedelta(seconds=120)<=reported<=ingested+datetime.timedelta(seconds=30)
    assert ts(h['observation_valid_until'])==expiry and h['freshness']==('fresh'if checked<expiry else'stale')
   c=r['callback_observations'];assert c['total']==c['sent']+c['delivery']
   if r['last_owner_action']:
    a=r['last_owner_action'];receipt(a['receipt'],r['device_id'],action=a['action'])
 else:
  if value['outcome']=='recorded':
   identity(value['identity']);receipt(value['receipt'],value['identity']['device_id'],value['request_id'],value['action'])
  else:assert value['action']is value['receipt']is value['identity']is None
 return True

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--report-dir',required=True);args=parser.parse_args()
 report=pathlib.Path(args.report_dir).resolve();assert not report.exists(),'Fresh report required';report.mkdir(parents=True)
 evidence={'kind':'captured163_plus_gateway_reads_private_upgrade','started_at':now(),'production_written':False,'shared_database_written':False,'source_rows_copied':False,'provider_called':False,'carrier_called':False,'otp_sent':False,'signed_jwt_tested':False,'real_device_enrolled':False,'scheduler_executed':False,'cases':[]}
 sessions=[];target=None
 def save():(report/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 def case(name,test=True):
  value=test()if callable(test)else test;assert value is not False,name
  evidence['cases'].append({'name':name,'status':'pass','detail':value});save();print('PASS '+name,flush=True);return value
 try:
  assert upgrade.sha((PACKET/'MANIFEST.json').read_bytes())==PACKET_MANIFEST_SHA
  source=json.loads((PACKET/'result.json').read_text());assert source['status']=='pass'and len(source['source_inventory'])==163
  items=[]
  for item in source['source_inventory']:
   body=(PACKET/'captured-source'/pathlib.Path(item['path']).name).read_bytes();assert upgrade.sha(body)==item['sha256'];items.append({**item,'body':body.decode()})
  migration=MIGRATION.read_bytes();schema_bytes=SCHEMA.read_bytes();schema=json.loads(schema_bytes)
  evidence['baseline']={'manifest_sha256':PACKET_MANIFEST_SHA,'exact_application_migrations':163,'source_sha256':{i['path']:i['sha256']for i in items},'not_attested':'Complete managed-host platform/data/runtime parity'}
  evidence['selected_source_sha256']={str(MIGRATION.relative_to(ROOT)):upgrade.sha(migration),str(SCHEMA.relative_to(ROOT)):upgrade.sha(schema_bytes)}
  evidence['runner_sha256']=upgrade.sha(pathlib.Path(__file__).read_bytes())
  (report/'captured-source').mkdir();(report/'captured-source'/MIGRATION.name).write_bytes(migration);(report/'captured-source'/SCHEMA.name).write_bytes(schema_bytes)
  for name in['collect-admin-gateway-v1.fixture.json','collect-admin-gateway-owner-request-v1.fixture.json']:
   fixture=(ROOT/'contracts'/name).read_bytes();(report/'captured-source'/name).write_bytes(fixture);case('published synthetic fixture validates: '+name,validate(json.loads(fixture),schema))
  jsonschema.Draft202012Validator.check_schema(schema)
  with upgrade.Target(report,'gateway',evidence.setdefault('target',{}))as target:
   platform,provenance=upgrade.platform_shape();evidence['platform_bootstrap']=provenance;target.sql(platform,label='schema-only platform bootstrap')
   install={};upgrade.apply(target,items[:124],install);upgrade.seed_populated(target,evidence,case);upgrade.apply(target,items[124:],install);evidence['prerequisite_install']=install
   # Existing verified email operator fixtures, not account provisioning. Their
   # original phone identities remain canonical receiving-route evidence.
   target.sql("""update auth.users set email='gateway-owner@collect.example',email_confirmed_at=clock_timestamp(),phone_confirmed_at=null where id=%s;
insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(%s,'gateway-owner@collect.example',clock_timestamp()-interval '2 minutes','Synthetic already-verified gateway owner');
update public.profiles set is_platform_admin=true,country_code='RW',currency_code='RWF' where id=%s;
update auth.users set email='gateway-other@collect.example',email_confirmed_at=clock_timestamp(),phone_confirmed_at=null where id=%s;
insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(%s,'gateway-other@collect.example',clock_timestamp()-interval '2 minutes','Synthetic already-verified second owner');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)select %s,id,'Synthetic second gateway owner',clock_timestamp()-interval '1 minute'from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
"""%tuple(map(q,[UID,UID,OTHER,OTHER,OTHER,OTHER,OTHERSID,OTHER])),label='synthetic verified email owners and fresh sessions')
   def call(sql,uid=UID,sid=SID):return json.loads(target.sql('begin;'+auth(uid,sid)+sql+';commit;',label='authenticated actual gateway operation').stdout.strip().splitlines()[-1])
   def serviced(sql):return json.loads(target.sql('begin;'+service()+sql+';commit;',label='trusted service fixture, no signature or provider').stdout.strip().splitlines()[-1])
   call("select public.admin_set_operator_email_mode_v1('Synthetic gateway email-only fixture');")
   financial_before=upgrade.fingerprints(target,evidence['preserved_columns'])
   installed=target.sql(migration.decode(),check=False,label=MIGRATION.name);(report/'install.log').write_text(installed.stdout+installed.stderr);assert installed.returncode==0,installed.stderr[-4000:]
   case('new read migration preserves all18 nonempty financial receipt Auth projections',upgrade.fingerprints(target,evidence['preserved_columns'])==financial_before)
   run_cases(target,case,evidence,report,call,serviced,schema,sessions)
   evidence['selected_source_after_sha256']={str(MIGRATION.relative_to(ROOT)):upgrade.sha(MIGRATION.read_bytes()),str(SCHEMA.relative_to(ROOT)):upgrade.sha(SCHEMA.read_bytes())};assert evidence['selected_source_after_sha256']==evidence['selected_source_sha256'],'Owned source changed during UAT'
   evidence['baseline_source_drift']=[i['path']for i in items if upgrade.sha((ROOT/i['path']).read_bytes())!=i['sha256']]
   evidence['later_migrations_outside_capture']=[str(p.relative_to(ROOT))for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))if str(p.relative_to(ROOT))not in evidence['baseline']['source_sha256']and p!=MIGRATION]
   case('private cron/net remain disabled with no recorded scheduler execution',target.json("select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'runs',(select count(*)from cron.job_run_details));")=={'cron':'off','net':'0','runs':0})
   for session in sessions:session.close()
   sessions.clear()
  evidence['status']='pass'
 except Exception as error:evidence['status']='failed';evidence['failure']=str(error);save();raise
 finally:
  for s in sessions:
   try:s.close()
   except Exception as error:evidence.setdefault('cleanup_errors',[]).append(str(error))
  if target:target.close()
  evidence['case_count']=len(evidence['cases']);evidence['completed_at']=now();save()

def run_cases(target,case,evidence,report,call,serviced,schema,sessions):
 def truth(sql):return target.scalar(sql)=='t'
 def error(sql,state='42501',reason=None,uid=UID,sid=SID,role='authenticated',mutation=''):
  result=target.sql('begin;'+mutation+auth(uid,sid,role)+sql+';rollback;',check=False,label='expected refusal '+str(reason));assert result.returncode and state+':'in result.stderr and(reason is None or reason in result.stderr),result.stderr;return {'sqlstate':state,'reason':reason}
 def valid(sql,uid=UID,sid=SID):
  result=call(sql,uid,sid);validate(result,schema);return result
 list_sql='select public.admin_list_gateway_devices_v1()'
 unknown_req=str(uuid.uuid4());get_sql="select public.admin_get_gateway_owner_request_v1(%s)"%q(unknown_req)
 empty=valid(list_sql);(report/'observed-empty.json').write_text(json.dumps(empty,indent=2)+'\n');case('empty list is genuinely empty with coherent read TTL',empty['rows']==[]and empty['total']==0 and empty['next_cursor']is None)
 case('read execution belongs only to authenticated role',truth("select count(*)=2 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('service_role',p.oid,'EXECUTE'))from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('admin_list_gateway_devices_v1','admin_get_gateway_owner_request_v1');"))
 for role in['anon','service_role']:
  for name,query in[('list',list_sql),('request',get_sql)]:case(role+' cannot execute gateway '+name,lambda query=query,role=role:error(query,role=role))
 for helper in['collect_gateway.read_actor()','collect_gateway.read_count(bigint)','collect_gateway.public_identity(collect_gateway.devices)','collect_gateway.public_owner_receipt(jsonb)']:
  case('private helper has no API execution: '+helper,truth("select bool_and(not has_function_privilege(role,%s,'EXECUTE'))from unnest(array['anon','authenticated','service_role'])role;"%q(helper)))
 for table in['devices','admin_requests','requests','health_observations','dispatch_arms','segment_callbacks']:
  case('RLS and no API direct table access: '+table,truth("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role'])role where has_table_privilege(role,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c where c.relnamespace='collect_gateway'::regnamespace and c.relname=%s;"%q(table)))
 role=target.scalar("select id from public.admin_roles where name='platform_owner';")
 mutations=[('expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=%s;"%q(SID)),('revoked grant',"update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=%s;"%q(UID)),('changed role identity',"update public.admin_roles set name='fixture_gateway_role' where id=%s;"%q(role)),('revoked email',"update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=%s;"%q(UID)),('expired email',"update collect_admin_access.email_approvals set expires_at=clock_timestamp()-interval '1 second'where user_id=%s;"%q(UID)),('unverified email',"update auth.users set email_confirmed_at=null where id=%s;"%q(UID)),('changed email',"update auth.users set email='changed-gateway@collect.example'where id=%s;"%q(UID)),('missing notification read',"delete from public.admin_role_permissions where role_id=%s and permission_name='notifications.read';"%q(role)),('missing health read',"delete from public.admin_role_permissions where role_id=%s and permission_name='system_health.read';"%q(role))]
 for label,mutation in mutations:
  for name,query in[('list',list_sql),('request',get_sql)]:case('gateway '+name+' rejects '+label,lambda query=query,mutation=mutation:error(query,mutation=mutation))
 case('wrong bound session cannot list',lambda:error(list_sql,sid=OTHERSID))
 for query in[list_sql,get_sql]:case('caller-created old snapshot is refused: '+query,lambda query=query:error(query,'40001','gateway_read_snapshot_retry',mutation='set transaction isolation level repeatable read;'))
 for args in['null','0','51','1,null,\'%s\''%uuid.uuid4(),"1,clock_timestamp(),null","1,'infinity',%s"%q(uuid.uuid4())]:
  case('invalid bounded list input '+args,lambda args=args:error('select public.admin_list_gateway_devices_v1('+args+')','22023','gateway_read_query_invalid'))
 case('null owner request is refused',lambda:error('select public.admin_get_gateway_owner_request_v1(null)','22023','gateway_owner_request_invalid'))
 case('count exact cap remains representable',target.scalar('select collect_gateway.read_count(1000000000);')=='1000000000')
 for n in['null','-1','1000000001']:
  result=target.sql('select collect_gateway.read_count('+n+');',check=False,label='counter fail closed');case('counter refuses '+n,result.returncode!=0 and'55000:'in result.stderr)
 def enroll(n):
  raw=bytes.fromhex(PREFIX+POINTS[n]);public_key=base64.b64encode(raw).decode();key_sha=hashlib.sha256(raw).hexdigest();req=str(uuid.uuid4());installation=str(uuid.uuid4());cert=str(n+1)*64
  sql="select public.admin_enroll_gateway_device_v1(%s,%s,%s,%s,%s)"%tuple(map(q,[req,installation,public_key,key_sha,cert]));receipt=call(sql)
  return {'device_id':receipt['device_id'],'request_id':req,'installation_id':installation,'key_sha256':key_sha,'signing_certificate_sha256':cert,'receipt':receipt,'sql':sql}
 devices=[enroll(0),enroll(1)];first,second=devices;device=first['device_id']
 def change(action,dev=first,req=None):
  req=req or str(uuid.uuid4());sql="select public.admin_%s_gateway_device_v1(%s,%s,%s,%s)"%(action,q(dev['device_id']),q(req),q(dev['key_sha256']),q(dev['signing_certificate_sha256']));return call(sql),sql
 def request(action,payload,dev=device,req=None):
  req=req or str(uuid.uuid4());digest=hashlib.sha256((action+dev+req+json.dumps(payload)).encode()).hexdigest()
  return "select public.gateway_%s_v1(%s,%s,%s,%s::jsonb)"%(action,q(dev),q(req),q(digest),q(json.dumps(payload)))
 pending=valid(list_sql);(report/'observed-pending.json').write_text(json.dumps(pending,indent=2)+'\n');case('pending identities expose no invented health or dispatch capability',all(r['health']is None and r['state']=='pending'and not r['dispatch_available']for r in pending['rows']))
 enroll_read=valid("select public.admin_get_gateway_owner_request_v1(%s)"%q(first['request_id']));case('original owner reconciles exact enrollment without SPKI or replay',enroll_read['receipt']==first['receipt']and enroll_read['identity']=={k:first[k]for k in['device_id','installation_id','key_sha256','signing_certificate_sha256']})
 case('unknown original request remains unknown',valid(get_sql)['outcome']=='unknown')
 other_read=valid("select public.admin_get_gateway_owner_request_v1(%s)"%q(first['request_id']),OTHER,OTHERSID);case('other current owner cannot discover original request result',other_read['outcome']=='unknown')
 healthy={'sms_permission':False,'network':'unvalidated','telephony':'unknown','sim_selected':False,'sim_revision_sha256':None,'local_pause':True,'reported_at':now()}
 hb=serviced(request('heartbeat',healthy));activated,activate_sql=change('activate')
 active=valid(list_sql);(report/'observed-active.json').write_text(json.dumps(active,indent=2)+'\n');row=next(r for r in active['rows']if r['device_id']==device)
 case('actual device dimensions stay independent including false and unknown',row['health']['observation_id']==hb['observation_id']and row['health']['sms_permission']is False and row['health']['network']=='unvalidated'and row['health']['telephony']=='unknown'and row['health']['sim_selected']is False and row['health']['local_pause']is True)
 case('identity activation does not grant dispatch or carrier proof',row['state']=='active'and row['dispatch_authority']=='pending'and row['dispatch_available']is False and row['health']['carrier_proof']is False)
 activate_read=valid("select public.admin_get_gateway_owner_request_v1(%s)"%q(activated['request_id']));case('activation uncertainty read retains original receipt',activate_read['receipt']==activated)
 # Actual existing sender-boundary fixture: no SMS API is called. Retained arm
 # is inserted only by this private fixture owner, as no public issuer exists.
 target.sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
 job=target.scalar('select id from collect_hybrid.sms_notification_outbox order by created_at,id limit 1;')
 claim=serviced("select public.collect_claim_receipt(%s,%s,'synthetic-gateway-read-prior',%s)"%(q(UID),q(job),q(uuid.uuid4())))
 exact=serviced("select public.collect_get_claimed_receipt(%s,%s,%s,%d)"%(q(UID),q(job),q(claim['claim_token']),claim['fence_version']))
 confirm=str(uuid.uuid4());serviced("select public.collect_confirm_receipt(%s,%s,%s,%d,%d,%s,%s)"%(q(UID),q(job),q(claim['claim_token']),claim['fence_version'],exact['destination_revision'],q(exact['body_sha256']),q(confirm)))
 started=serviced("select public.collect_record_send_start(%s,%s,%s,%d,%s)"%(q(UID),q(job),q(claim['claim_token']),claim['fence_version'],q(confirm)))
 target.sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
 attempt=target.json('select to_jsonb(a)from collect_hybrid.sms_notification_attempts a where id=%s;'%q(started['attempt_id']))
 arm="insert into collect_gateway.dispatch_arms(device_id,attempt_id,fence_version,body_sha256,destination_sha256,segment_count)values(%s,%s,%d,%s,%s,1);"%(q(device),q(attempt['id']),attempt['fence_version'],q(attempt['body_sha256']),q(attempt['destination_sha256']))
 target.sql(arm,label='synthetic prior arm only; no public grant or sender authority');(report/'synthetic-prior-arm.sql').write_text(arm+'\n')
 revoked,revoke_sql=change('revoke')
 for kind in['sent','delivery']:
  payload={'callback_id':str(uuid.uuid4()),'attempt_id':attempt['id'],'fence_version':attempt['fence_version'],'segment_index':0,'segment_count':1,'body_sha256':attempt['body_sha256'],'destination_sha256':attempt['destination_sha256'],'callback_kind':kind,'result_code':-1 if kind=='sent'else 5,'tp_status':None,'occurred_at':now()};serviced(request('callback',payload))
 actual=valid(list_sql);(report/'observed-revoked-callbacks.json').write_text(json.dumps(actual,indent=2)+'\n');row=next(r for r in actual['rows']if r['device_id']==device)
 case('revoked paused identity retains exactly two raw OS observations',row['state']=='revoked'and row['callback_observations']=={'total':2,'sent':1,'delivery':1})
 case('last owner action is actual immutable revocation receipt',row['last_owner_action']=={'action':'revoke','receipt':revoked})
 revoked_read=valid("select public.admin_get_gateway_owner_request_v1(%s)"%q(revoked['request_id']));(report/'observed-owner-request.json').write_text(json.dumps(revoked_read,indent=2)+'\n');case('revocation reconciliation returns immutable identity and original request',revoked_read['receipt']==revoked and revoked_read['identity']['device_id']==device)
 old_enroll=valid("select public.admin_get_gateway_owner_request_v1(%s)"%q(first['request_id']));case('original enrollment receipt stays pending after later revoke',old_enroll['receipt']['state_at_action']=='pending'and old_enroll['receipt']['replay']is False)
 extra="alter table collect_gateway.admin_requests disable trigger user;update collect_gateway.admin_requests set result=result||jsonb_build_object('unreviewed_private_detail','synthetic protected')where request_id=%s;"%q(first['request_id'])
 extra_read=json.loads(target.sql('begin;'+extra+auth()+"select public.admin_get_gateway_owner_request_v1(%s);rollback;"%q(first['request_id']),label='rollback-only unexpected source result field').stdout.strip().splitlines()[-1]);case('source extra receipt fields cannot escape whitelist projection',validate(extra_read,schema)and extra_read['receipt']==first['receipt'])
 # Projection can read stale historical evidence without advancing it. The
 # artificial age change is an explicit rollback-only fixture fault injection.
 baseline=upgrade.fingerprints(target,evidence['preserved_columns'])
 gateway_spec=upgrade.columns(target,[('collect_gateway',t)for t in['devices','admin_requests','requests','health_observations','dispatch_arms','segment_callbacks']])
 gateway_before=upgrade.fingerprints(target,gateway_spec);evidence['original_session_json']=target.scalar('select to_jsonb(s)from auth.sessions s where id=%s;'%q(SID));evidence['business_before_read_checks']=baseline;evidence['gateway_before_read_checks']=gateway_before
 stale_sql="alter table collect_gateway.health_observations disable trigger user;update collect_gateway.health_observations set ingested_at=ingested_at-interval '4 minutes',reported_at=reported_at-interval '4 minutes'where device_id=%s;"%q(device)
 stale=json.loads(target.sql('begin;'+stale_sql+auth()+list_sql+';rollback;',label='rollback-only stale observation').stdout.strip().splitlines()[-1]);validate(stale,schema);case('stale persisted health remains stale despite fresh read TTL',next(r for r in stale['rows']if r['device_id']==device)['health']['freshness']=='stale')
 case('rollback restores immutable observation bytes',upgrade.fingerprints(target,gateway_spec)==gateway_before)
 page=valid('select public.admin_list_gateway_devices_v1(1)');cursor=page['next_cursor'];case('one-row first page advertises actual next paired cursor',page['total']==2 and cursor is not None)
 page2=valid('select public.admin_list_gateway_devices_v1(1,%s,%s)'%(q(cursor['enrolled_at']),q(cursor['device_id'])));case('second keyset page has stable total and no duplicated identity',page2['total']==2 and page2['next_cursor']is None and page2['rows'][0]['device_id']!=page['rows'][0]['device_id'])
 last=page2['rows'][-1];end=valid('select public.admin_list_gateway_devices_v1(1,%s,%s)'%(q(last['enrolled_at']),q(last['device_id'])));case('empty later window retains total without inventing more rows',end['total']==2 and end['rows']==[] and end['next_cursor']is None)
 denied={'public_key_spki_base64','actor_id','owner_actor_id','owner_session_id','session_id','input','sim_revision_sha256','destination_e164','body_sha256','destination_sha256','message_body','claim_token','result_code','tp_status','worker_id'}
 def redacted(v):return not(set(v)&denied)and all(redacted(x)for x in v.values())if isinstance(v,dict)else all(redacted(x)for x in v)if isinstance(v,list)else True
 case('every read projection omits raw keys credentials payloads callbacks conclusions and identity actors',all(redacted(x)for x in[actual,old_enroll,revoked_read,stale]))
 no_manage="delete from public.admin_role_permissions where role_id=%s and permission_name='notifications.manage';"%q(role)
 limited=json.loads(target.sql('begin;'+no_manage+auth()+list_sql+';rollback;').stdout.strip().splitlines()[-1]);case('read authority does not require notification management',validate(limited,schema))
 case('read-only owner cannot mutate gateway identity',lambda:error(second['sql'],mutation=no_manage))
 # Single-statement source reads remain coherent when a service heartbeat and
 # owner action exist in concurrent, as-yet-uncommitted transactions.
 a=Session(target,'heartbeat-held');sessions.append(a);query=request('heartbeat',{**healthy,'reported_at':now(),'network':'offline'},dev=second['device_id'])
 a.write('begin;'+service()+query+";select 'HEARTBEAT_HELD';");a.read('HEARTBEAT_HELD')
 before_commit=valid(list_sql);case('uncommitted heartbeat cannot leak a partial health row',next(r for r in before_commit['rows']if r['device_id']==second['device_id'])['health']is None)
 a.write("commit;select 'HEARTBEAT_DONE';");a.read('HEARTBEAT_DONE');after_commit=valid(list_sql);case('committed heartbeat has coherent checked_at and observation dimensions',next(r for r in after_commit['rows']if r['device_id']==second['device_id'])['health']['network']=='offline')
 # Read authority proof locks prevent concurrent grant revocation from crossing
 # an accepted read. After commit, the same bound session must be denied.
 reader=Session(target,'read-authority-held');revoker=Session(target,'grant-revocation-wait');sessions.extend([reader,revoker])
 reader.write('begin;'+auth()+list_sql+";select 'READ_HELD';");reader.read('READ_HELD')
 revoker.write('begin;update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=%s;commit;select \'REVOKE_DONE\';'%q(UID))
 time.sleep(.15);case('accepted read holds proof rows against concurrent revocation',truth("select exists(select 1 from public.admin_user_roles where user_id=%s and revoked_at is null);"%q(UID)))
 reader.write("commit;select 'READ_DONE';");reader.read('READ_DONE');revoker.read('REVOKE_DONE');case('committed grant revocation denies subsequent list',lambda:error(list_sql))
 target.sql("update public.admin_user_roles set revoked_at=null where user_id=%s;"%q(UID),label='restore isolated authority fixture only')
 # Another still-current owner can see retained global device evidence after
 # deleting the original session. Request reads still remain actor-bound.
 target.sql('delete from auth.sessions where id=%s;'%q(SID),label='synthetic old session deletion')
 retained=valid(list_sql,OTHER,OTHERSID);case('durable gateway identity and receipts survive original session deletion',len(retained['rows'])==2 and next(r for r in retained['rows']if r['device_id']==device)['last_owner_action']['receipt']==revoked)
 target.sql('insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval \'1 hour\',\'aal1\');'%(q(NEW_SESSION),q(UID)))
 recovered=valid("select public.admin_get_gateway_owner_request_v1(%s)"%q(first['request_id']),UID,NEW_SESSION);case('same original actor can reconcile retained request after fresh sign-in',recovered['outcome']=='recorded')
 # Restore solely the original session fixture to compare protected tables.
 target.sql("delete from auth.sessions where id=%s;insert into auth.sessions select * from jsonb_populate_record(null::auth.sessions,%s::jsonb);"%(q(NEW_SESSION),q(evidence['original_session_json'])),label='restore original synthetic session for final fingerprint')
 case('all18 nonempty business tables preserve exact bytes after read checks',upgrade.fingerprints(target,evidence['preserved_columns'])==baseline)
 # Concurrency heartbeat is an authorized observation write, explicitly exclude
 # it from immutable-read equality and retain actual new evidence as its own FP.
 evidence['business_after_read_checks']=upgrade.fingerprints(target,evidence['preserved_columns']);evidence['gateway_after_authorized_heartbeat']=upgrade.fingerprints(target,gateway_spec)
 case('paused prior journals remain balanced with canonical850RWF',truth("select (select confirmed_rwf=850 from collect_hybrid.member_balances where collection_id=%s and member_record_id=%s)and not exists(select 1 from collect_hybrid.momo_journal_entries j join collect_hybrid.momo_journal_lines l on l.journal_entry_id=j.id group by j.id having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else-l.amount_rwf end)<>0);"%(q(upgrade.GROUP),q(upgrade.MEMBER))))
 navigation=target.json("select to_jsonb(n)from public.admin_navigation_items n where key='sms_gateway';");case('canonical gateway navigation is persisted with governed permission',navigation['route_path']=='/admin/sms-gateway'and navigation['icon_key']=='router'and navigation['required_permission']=='notifications.read'and navigation['enabled']is True)
 # Re-exercise exactly the idempotent navigation fragment rather than replaying
 # non-idempotent function creation. A skipped insert must not alter governance.
 body=MIGRATION.read_text();nav=body[body.index('lock table public.admin_navigation_items'):body.index("notify pgrst")]
 target.sql("begin;update public.admin_navigation_items set enabled=false,label='Synthetic customized gateway',updated_reason='Synthetic preserve disabled navigation'where key='sms_gateway';commit;")
 config_tables=upgrade.columns(target,[('public','admin_navigation_items'),('collect_security','runtime_control_heads'),('collect_security','runtime_control_events')])
 preserved=upgrade.fingerprints(target,config_tables);target.sql('begin;'+nav+'commit;',label='exact skipped navigation conflict guard');case('disabled customized navigation and governance state survive idempotent conflict',upgrade.fingerprints(target,config_tables)==preserved)
 for s in sessions:s.close()
 sessions.clear()

if __name__=='__main__':main()
