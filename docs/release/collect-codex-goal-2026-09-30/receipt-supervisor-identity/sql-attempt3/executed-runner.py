#!/usr/bin/env python3
"""Task-owned offline supervisor identity UAT. No URL or credentials accepted."""
import argparse,base64,datetime,hashlib,importlib.abc,importlib.util,json,pathlib,sys,time,uuid

ROOT=pathlib.Path(__file__).resolve().parents[2]
DEFAULT=ROOT/'.cache/receipt-supervisor-preparation/supabase/migrations/20260930231804_receipt_supervisor_identity.sql'
EMAIL='99800000-0000-4000-8000-000000000001'
SID='99800000-0000-4000-8000-000000010001'

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--report-dir',required=True,type=pathlib.Path)
 parser.add_argument('--migration',type=pathlib.Path,default=DEFAULT)
 args=parser.parse_args();out=args.report_dir.resolve();assert not out.exists();out.mkdir(parents=True)
 evidence={'kind':'task_owned_supervisor_identity_schema153_subset','cases':[],
  'hosted_mutations':False,'source_rows_copied':False,'auth_provider_or_signed_jwt_tested':False,
  'sql_verifies_signature':False,'private_key_created':False,'sms_or_provider_called':False,
  'scope':'Dedicated read-only shadow principal; no business ACK, enqueue, scheduler or sender authority.'}
 helpers={p.stem:(p,p.read_bytes())for p in(ROOT/'scripts/tests').glob('*.py')}
 executed={}
 class Loader(importlib.abc.MetaPathFinder,importlib.abc.Loader):
  def find_spec(self,fullname,path=None,target=None):
   if fullname in helpers:return importlib.util.spec_from_loader(fullname,self,origin=str(helpers[fullname][0]))
  def create_module(self,spec):return None
  def exec_module(self,module):
   p,b=helpers[module.__name__];module.__file__=str(p);executed[module.__name__]=(p,b)
   exec(compile(b,str(p),'exec'),module.__dict__)
 finder=Loader();sys.meta_path.insert(0,finder)
 import operational_exception_inbox_uat as ops
 import collect_current_release_upgrade_uat as private
 import android_gateway_identity_uat as keys
 f,u,c=ops.foundation,ops.u,ops.fixture
 (out/'executed-helpers').mkdir()
 for name,(p,b)in executed.items():(out/'executed-helpers'/p.name).write_bytes(b)
 evidence['executed_helpers_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(b).hexdigest()for p,b in executed.values()}
 own=pathlib.Path(__file__).read_bytes();(out/'executed-runner.py').write_bytes(own)
 evidence['runner_sha256']=hashlib.sha256(own).hexdigest()
 stages={ROOT/path:(ROOT/path).read_bytes()for path in ops.STAGES}
 migration=args.migration.resolve();assert ROOT in migration.parents and not migration.is_symlink()
 stages[migration]=migration.read_bytes();(out/'executed-migrations').mkdir()
 for p,b in stages.items():(out/'executed-migrations'/p.name).write_bytes(b)
 evidence['executed_migrations_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(b).hexdigest()for p,b in stages.items()}
 db='collect_supervisor_'+uuid.uuid4().hex[:12];target=None;made=False;sessions=[]
 def save():(out/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 def check(x):assert x,x;return True
 def case(name,fn):
  detail=fn();evidence['cases'].append({'name':name,'status':'pass','detail':detail});save();print('PASS '+name,flush=True);return detail
 sql=lambda text:u.psql(db,text).stdout.strip()
 truth=lambda text:check(sql(text)=='t')
 service=lambda text:json.loads(sql(f.service(text)).splitlines()[-1])
 owner=lambda text:u.call(db,text,EMAIL,SID)
 literal=lambda x:"'"+str(x).replace("'","''")+"'"
 utc=lambda:(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='microseconds').replace('+00:00','Z'))
 def spki(n):
  prime=0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
  gx,gy=int(keys.POINTS[0][:64],16),int(keys.POINTS[0][64:],16)
  x,y=gx,gy
  for _ in range(n):
   slope=((3*x*x-3)*pow(2*y,-1,prime))%prime if (x,y)==(gx,gy) else ((gy-y)*pow(gx-x,-1,prime))%prime
   nx=(slope*slope-x-gx)%prime;y=(slope*(x-nx)-y)%prime;x=nx
  point=f'{x:064x}{y:064x}'
  b=bytes.fromhex(keys.PREFIX+point);return base64.b64encode(b).decode(),hashlib.sha256(b).hexdigest()
 try:
  target=private.Target(out,'root_supervisor',evidence.setdefault('offline_target',{}));target.__enter__();u.CONTAINER=target.name
  u.SQL_LOG=out/'queries.log';u.CONCURRENCY_LOG=out/'concurrency.log';f.RAW_QUERY_LOG=out/'queries.sql'
  dump=(c.BASELINE/'schema-only.sql').read_bytes();acl=(c.BASELINE/'api-acl.sql').read_bytes()
  assert c.sha(dump)==c.DUMP_HASH and c.sha(acl)==c.ACL_HASH
  evidence['baseline']={'schema_sha256':c.DUMP_HASH,'acl_sha256':c.ACL_HASH,'schema_migrations':153}
  u.psql('postgres','create database '+db+' template template0;');made=True
  sql('create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+dump.decode()+acl.decode())
  f.seed(db)
  sql("insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values('%s','%s','+250788971001',repeat('a',64),'mtn_momo');"%(f.GROUP,u.UID))
  before=f.business_fingerprint(db)
  for p,b in stages.items():
   result=u.psql(db,b.decode(),False);(out/(p.stem+'.install.log')).write_text(result.stdout+result.stderr)
   assert result.returncode==0,result.stderr
   case(p.name+' preserves existing financial evidence',lambda:check(f.business_fingerprint(db)==before))
  case('identity install provisions no user or supervisor',lambda:truth('select not exists(select 1 from collect_supervisor.identities);'))
  case('private supervisor tables keep RLS and deny direct API grants',lambda:truth("select count(*)=9 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relnamespace='collect_supervisor'::regnamespace and c.relkind='r';"))
  case('private supervisor schema/helpers are not API capabilities',lambda:truth("select not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_schema_privilege(r,'collect_supervisor','USAGE'))and not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_supervisor'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE'));"))
  key,digest=spki(0);expiry=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1)).isoformat(timespec='microseconds')
  request=str(uuid.uuid4())
  enroll=lambda req=request,k=key,h=digest,e=expiry:"select public.admin_enroll_receipt_supervisor_v1('%s','%s','%s','%s');"%(req,k,h,e)
  for role in ['anon','service_role']:
   case(role+' cannot enroll a supervisor',lambda role=role:u.expected_error(db,enroll(),'42501',role=role))
  sql("insert into public.admin_permissions(name,description)values('admin_users.manage','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '%s',name from public.admin_permissions on conflict do nothing;"%f.ROLE)
  case('legacy phone owner cannot enroll the email-owned machine identity',lambda:u.expected_error(db,enroll(),'42501','supervisor_current_email_owner_required'))
  sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values('%s','authenticated','authenticated','info@ikanisa.com',clock_timestamp(),'{}','{}');"%EMAIL)
  service("select public.bootstrap_collect_email_operator_v1('%s');"%EMAIL)
  sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(SID,EMAIL))
  for label,change in [
   ('unverified email',"update auth.users set email_confirmed_at=null where id='%s';"%EMAIL),
   ('expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='%s';"%SID),
   ('revoked email approval',"update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id='%s';"%EMAIL),
   ('revoked owner role',"update public.admin_user_roles set revoked_at=clock_timestamp()where user_id='%s';"%EMAIL),
   ('missing admin management',"delete from public.admin_role_permissions where role_id='%s'and permission_name='admin_users.manage';"%f.ROLE),
   ('missing notification management',"delete from public.admin_role_permissions where role_id='%s'and permission_name='notifications.manage';"%f.ROLE),
   ('missing system health',"delete from public.admin_role_permissions where role_id='%s'and permission_name='system_health.read';"%f.ROLE)]:
   def denied(change=change):
    r=u.psql(db,'begin;'+change+u.auth(EMAIL,SID)+enroll()+'rollback;',False)
    return check(r.returncode!=0 and '42501:'in r.stderr)
   case('enrollment refuses '+label,denied)
  for isolation in ['repeatable read','serializable']:
   r=u.psql(db,'begin isolation level '+isolation+';'+u.auth(EMAIL,SID)+enroll()+'rollback;',False)
   case(isolation+' cannot retain owner authority',lambda r=r:check(r.returncode!=0 and '40001:'in r.stderr))
  before=f.business_fingerprint(db);users=sql('select count(*)from auth.users;')
  enrolled=owner(enroll());principal=enrolled['principal_id'];(out/'observed-enrollment.json').write_text(json.dumps(enrolled,indent=2)+'\n')
  case('enrollment issues only pending narrow public identity metadata',lambda:check(set(enrolled)==set('contract_version principal_id request_id state_at_action scope key_sha256 expires_at recorded_at'.split())and enrolled['state_at_action']=='pending'and enrolled['scope']=='rw_receipt_shadow'))
  case('exact enrollment request replay retains its original receipt',lambda:check(owner(enroll())==enrolled))
  case('owner request conflict cannot change expiry',lambda:u.expected_error(db,enroll(e='2099-01-01T00:00:00Z'),'22023','supervisor_owner_request_conflict',uid=EMAIL,sid=SID))
  offcurve=bytes.fromhex(keys.PREFIX)+bytes(64)
  for label,k,h,e in [('off-curve key',base64.b64encode(offcurve).decode(),hashlib.sha256(offcurve).hexdigest(),expiry),('mismatched digest',key,'a'*64,expiry),('short expiry',key,digest,utc()),('unbounded expiry',key,digest,'infinity')]:
   case('enrollment refuses '+label,lambda k=k,h=h,e=e:u.expected_error(db,enroll(str(uuid.uuid4()),k,h,e),'22023',uid=EMAIL,sid=SID))
  case('owner original-request lookup returns exact immutable receipt',lambda:check(owner("select public.admin_get_receipt_supervisor_owner_request_v1('%s');"%request)['receipt']==enrolled))
  activate=lambda req=str(uuid.uuid4()):"select public.admin_activate_receipt_supervisor_v1('%s','%s','%s');"%(principal,req,digest)
  case('activation requires recent key possession',lambda:u.expected_error(db,activate(),'55000','supervisor_key_possession_required',uid=EMAIL,sid=SID))
  def observe(pid=principal,h=digest,req=None,issued=None,action='shadow_health',sha='a'*64):
   return "select public.receipt_supervisor_observe_v1('%s','%s','%s','%s','%s','%s');"%(pid,req or uuid.uuid4(),h,sha,issued or utc(),action)
  case('pending principal cannot inspect shadow health',lambda:u.expected_error(db,observe(),'42501','supervisor_credential_unavailable',role='service_role',uid=None,sid=None))
  for role in ['anon','authenticated']:
   case(role+' cannot invoke machine service authority',lambda role=role:u.expected_error(db,observe(action='prove_key'),'42501',role=role,uid=EMAIL,sid=SID))
  proof=service(observe(action='prove_key'));(out/'observed-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
  case('proof retains only bounded shadow scope',lambda:check(proof['mode']=='Shadow'and not proof['business_handled']and not proof['send_action']))
  activated=owner(activate());case('activation retains shadow-only identity scope',lambda:check(activated['state_at_action']=='active'and activated['scope']=='rw_receipt_shadow'))
  sql(f.service(f.payment_sql('99800000-0000-4000-8000-000000050001')))
  current=f.business_fingerprint(db);health_request=str(uuid.uuid4());issued=utc();query=observe(req=health_request,issued=issued)
  health=service(query);(out/'observed-health.json').write_text(json.dumps(health,indent=2)+'\n')
  case('health derives Rwanda queue counts without business or send authority',lambda:check(health['queued_count']==1 and health['unknown_count']==0 and health['mode']=='Shadow'and not health['financial_action']and not health['send_action']and not health['business_handled']))
  case('identical request replay never renews sample freshness',lambda:check(service(query)==health))
  case('signed request UUID conflict is denied',lambda:u.expected_error(db,observe(req=health_request,issued=issued,sha='b'*64),'22023','supervisor_request_conflict',role='service_role',uid=None,sid=None))
  case('stale signed-request window is denied',lambda:u.expected_error(db,observe(issued='2020-01-01T00:00:00Z'),'42501','supervisor_request_expired',role='service_role',uid=None,sid=None))
  case('read-only principal has no send/enqueue action alias',lambda:u.expected_error(db,observe(action='send'),'22023','supervisor_request_invalid',role='service_role',uid=None,sid=None))
  reconcile=lambda target,req=None:"select public.receipt_supervisor_reconcile_v1('%s','%s','%s',repeat('c',64),'%s','%s');"%(principal,req or uuid.uuid4(),digest,utc(),target)
  found=service(reconcile(health_request));(out/'observed-reconciled.json').write_text(json.dumps(found,indent=2)+'\n')
  case('uncertain response lookup returns the original immutable observation',lambda:check(found['status']=='recorded'and found['receipt']==health))
  case('unrecorded UUID does not imply business handling',lambda:check(service(reconcile(str(uuid.uuid4())))['status']=='not_recorded'))
  case('identity and shadow reads create no Auth user or financial changes',lambda:check(sql('select count(*)from auth.users;')==users and f.business_fingerprint(db)==current))
  gateway_enroll=lambda k,h:"select public.admin_enroll_gateway_device_v1('%s','%s','%s','%s',repeat('d',64));"%(uuid.uuid4(),uuid.uuid4(),k,h)
  case('gateway enrollment refuses an existing supervisor key',lambda:u.expected_error(db,gateway_enroll(key,digest),'22023','supervisor_key_scope_conflict',uid=EMAIL,sid=SID))
  key4,digest4=spki(3);keyholder=u.Session(db,'dedicated_key_enrollment_holder');keywaiter=u.Session(db,'gateway_dedicated_key_waiter');sessions.extend([keyholder,keywaiter])
  keyholder.write('begin;'+u.auth(EMAIL,SID)+enroll(str(uuid.uuid4()),key4,digest4)+"select 'DEDICATED_KEY_HELD';");keyholder.read('DEDICATED_KEY_HELD')
  keywaiter.write("set application_name='collect_gateway_dedicated_key';begin;"+u.auth(EMAIL,SID)+gateway_enroll(key4,digest4)+"commit;select 'GATEWAY_KEY_ATTEMPT_FINISHED';")
  waited=False;deadline=time.monotonic()+8
  while time.monotonic()<deadline:
   waited=sql("select exists(select 1 from pg_stat_activity where datname='%s'and application_name='collect_gateway_dedicated_key'and wait_event_type='Lock');"%db)=='t'
   if waited:break
   time.sleep(.05)
  case('concurrent gateway enrollment waits behind held supervisor authority',lambda:check(waited))
  keyholder.write("commit;select 'DEDICATED_KEY_COMMITTED';");keyholder.read('DEDICATED_KEY_COMMITTED');key_output=keywaiter.read('GATEWAY_KEY_ATTEMPT_FINISHED')
  case('concurrent gateway enrollment cannot reuse committed supervisor key',lambda:check(any('supervisor_key_scope_conflict'in line for line in key_output)and sql("select count(*)=1 and not exists(select 1 from collect_gateway.devices where key_sha256='%s')from collect_supervisor.identities where key_sha256='%s';"%(digest4,digest4))=='t'))
  key2,digest2=spki(1);gateway=owner("select public.admin_enroll_gateway_device_v1('%s','%s','%s','%s',repeat('d',64));"%(uuid.uuid4(),uuid.uuid4(),key2,digest2))
  case('enrollment refuses a known gateway signing key',lambda:u.expected_error(db,enroll(str(uuid.uuid4()),key2,digest2),'22023','supervisor_enrollment_invalid',uid=EMAIL,sid=SID))
  old_id=str(uuid.uuid4());key3,digest3=spki(2)
  sql("insert into collect_supervisor.identities(id,enrollment_request_id,owner_actor_id,owner_session_id,public_key_spki_base64,key_sha256,state,created_at,expires_at,activated_at)values('%s','%s','%s','%s','%s','%s','active',clock_timestamp()-interval '1 day',clock_timestamp()-interval '1 hour',clock_timestamp()-interval '1 day');"%(old_id,uuid.uuid4(),EMAIL,SID,key3,digest3))
  case('expired principal rejects key readback',lambda:u.expected_error(db,"select public.receipt_supervisor_key_v1('%s');"%old_id,'42501','supervisor_credential_unavailable',role='service_role',uid=None,sid=None))
  case('expired principal cannot prove its key or inspect health',lambda:u.expected_error(db,observe(pid=old_id,h=digest3,action='prove_key'),'42501','supervisor_credential_unavailable',role='service_role',uid=None,sid=None))
  held=u.Session(db,'supervisor_health_holder');revoker=u.Session(db,'supervisor_revoke_waiter');sessions.extend([held,revoker])
  held.write('begin;select set_config(\'request.jwt.claims\',\'{"role":"service_role"}\',true);'+observe()+"select 'SUPERVISOR_HEALTH_HELD';");held.read('SUPERVISOR_HEALTH_HELD')
  revoke_request=str(uuid.uuid4());revoker.write("set application_name='collect_supervisor_revoke';begin;"+u.auth(EMAIL,SID)+"select public.admin_revoke_receipt_supervisor_v1('%s','%s','%s');commit;select 'SUPERVISOR_REVOKED';"%(principal,revoke_request,digest))
  waited=False;deadline=time.monotonic()+8
  while time.monotonic()<deadline:
   waited=sql("select exists(select 1 from pg_stat_activity where datname='%s'and application_name='collect_supervisor_revoke'and wait_event_type='Lock');"%db)=='t'
   if waited:break
   time.sleep(.05)
  case('revocation waits for actual open machine authority boundary',lambda:check(waited))
  held.write("commit;select 'SUPERVISOR_HEALTH_COMMITTED';");held.read('SUPERVISOR_HEALTH_COMMITTED');revoke_output=revoker.read('SUPERVISOR_REVOKED')
  case('revocation commits and prevents all subsequent machine authority',lambda:check(not any('ERROR:'in line for line in revoke_output)and sql("select state='revoked'from collect_supervisor.identities where id='%s';"%principal)=='t'))
  for label,q in [('health',observe()),('key readback',"select public.receipt_supervisor_key_v1('%s');"%principal),('unknown lookup',reconcile(health_request))]:
   case('revoked principal refuses '+label,lambda q=q:u.expected_error(db,q,'42501','supervisor_credential_unavailable',role='service_role',uid=None,sid=None))
  case('owner retains historical revocation request receipt',lambda:check(owner("select public.admin_get_receipt_supervisor_owner_request_v1('%s');"%revoke_request)['receipt']['state_at_action']=='revoked'))
  case('gateway enrollment cannot reuse a revoked supervisor key',lambda:u.expected_error(db,gateway_enroll(key,digest),'22023','supervisor_key_scope_conflict',uid=EMAIL,sid=SID))
  prior_requests=sql('select count(*)from collect_supervisor.requests;')
  sql(f.service(f.payment_sql('99800000-0000-4000-8000-000000050002',amount=200)))
  case('payment and normal paused receipts continue without a supervisor call',lambda:truth("select count(*)=2 and bool_and(p.status='posted'and o.state='queued')from public.payments p join collect_hybrid.sms_notification_outbox o on o.payment_id=p.id where p.id in('99800000-0000-4000-8000-000000050001','99800000-0000-4000-8000-000000050002');"))
  case('payment pipeline never invokes supervisor request records',lambda:check(sql('select count(*)from collect_supervisor.requests;')==prior_requests))
  for label,q in [('owner receipts','delete from collect_supervisor.owner_requests;'),('machine observations','update collect_supervisor.requests set result=null;'),('identity key',"update collect_supervisor.identities set key_sha256=repeat('e',64)where id='%s';"%old_id),('identity lifetime',"update collect_supervisor.identities set expires_at=clock_timestamp()+interval '10 days'where id='%s';"%old_id)]:
   r=u.psql(db,q,False);case(label+' are immutable even to fixture owner',lambda r=r:check(r.returncode!=0 and '55000:'in r.stderr))
  evidence['helper_source_drift']=[str(p.relative_to(ROOT))for p,b in executed.values()if p.read_bytes()!=b]
  evidence['migration_source_drift']=[str(p.relative_to(ROOT))for p,b in stages.items()if p.read_bytes()!=b]
  assert not evidence['helper_source_drift']and not evidence['migration_source_drift']
  evidence['status']='pass'
 except Exception as error:evidence['status']='failed';evidence['error']=str(error);save();raise
 finally:
  for s in sessions:s.close()
  if made:evidence['isolated_database_removed']=u.psql('postgres','drop database '+db+' with(force);',False).returncode==0
  if target is not None:target.close()
  u.SQL_LOG=None;u.CONCURRENCY_LOG=None;f.RAW_QUERY_LOG=None
  sys.meta_path.remove(finder);evidence['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()

if __name__=='__main__':main()
