"""Isolated PostgreSQL staff-phone races; only called by the guarded harness."""
import json,os,select,subprocess,time,uuid

def run_checks(D,ident,database,source,sql,result,capacity):
 admission=str(uuid.uuid4());prefix="BEGIN;SET LOCAL ROLE collect_runtime;SET LOCAL collect.edge_verified='true';"
 reg=json.loads(result(prefix+"SELECT private.collect_fence_register('%s'::uuid,'%s','http_collect');COMMIT;"%(admission,source)))
 epoch=reg['epoch'];assert reg['state']=='active' and reg['sourceSha256']==source
 group='buri-qualification-group';install='fe910000-0000-4000-8000-000000000061'
 admin='f7000000-0000-4000-8000-000000000001';target1='fe710000-0000-4000-8000-000000000061';target2='fe710000-0000-4000-8000-000000000062'
 config="SELECT set_config('collect.fence_admission_id','%s',true),set_config('collect.fence_epoch','%s',true),set_config('collect.fence_source_sha256','%s',true),set_config('burimunsi.collection_id','%s',true);"%(admission,epoch,source,group)
 assertwork="SELECT private.collect_fence_assert_write('%s'::uuid,%s,'%s');"%(admission,epoch,source)
 gate='SELECT pg_advisory_xact_lock(734636924058501::bigint);'
 pin="SELECT private.burimunsi_set_pin_context(repeat('1',64),'%s'::uuid,repeat('2',64),'internal_receiver');"%install
 wire=[*D,'exec','-i',ident,'psql','-h','127.0.0.1','-p','55439','-U','postgres','-d',database,'-XAtq','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']
 children=[]
 def start(label,body,lease=False):
  capacity();p=subprocess.Popen(wire,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE);children.append(p)
  s=prefix+"SET LOCAL application_name='%s';SET LOCAL statement_timeout='15s';SET LOCAL lock_timeout='12s';"%label
  s+=("SELECT pg_advisory_xact_lock_shared(7346371,1);SELECT private.collect_fence_assert_work('%s'::uuid,%s,'%s');"%(admission,epoch,source)) if lease else config+assertwork+gate+pin+body
  p.stdin.write((s+'\n\\echo READY\n').encode());p.stdin.flush();return p
 def ready(p):
  buf=b'';deadline=time.monotonic()+15
  while b'READY\n' not in buf:
   capacity()
   if p.poll() is not None:raise RuntimeError('staff phone SQL exited: '+p.stderr.read().decode()[-1800:])
   if time.monotonic()>deadline:raise RuntimeError('staff phone READY timeout')
   ok,_,_=select.select([p.stdout],[],[],0.1)
   if ok:buf+=os.read(p.stdout.fileno(),8192)
  return buf.decode()
 def finish(p):
  p.stdin.write(b'COMMIT;\n\\q\n');p.stdin.flush();p.stdin.close();p.wait(timeout=15)
  if p.returncode:raise RuntimeError('staff phone commit: '+p.stderr.read().decode()[-1500:])
 def blocked(name,p):
  deadline=time.monotonic()+12
  while time.monotonic()<deadline:
   capacity()
   if p.poll() is not None:raise RuntimeError('staff phone competitor failed before wait: '+p.stderr.read().decode()[-1500:])
   if result("SELECT count(*) FROM pg_stat_activity WHERE application_name='%s' AND wait_event_type='Lock';"%name)=='1':return
   time.sleep(.1)
  raise RuntimeError('staff phone competitor did not block')
 def simple(body):return sql(prefix+config+assertwork+gate+pin+body+'COMMIT;').stdout
 def helper(target,phone):return "private.burimunsi_pin_staff_phone_available('%s','%s'::uuid,'%s')"%(group,target,phone)
 def change(target,phone):return "UPDATE private.burimunsi_accounts SET phone='%s',version=version+1,credential_version=credential_version+1,updated_at=updated_at+1 WHERE id='%s'::uuid;"%(phone,target)
 def expect(value,label):return "DO $test$ BEGIN IF NOT (%s) THEN RAISE EXCEPTION '%s'; END IF; END $test$;"%(value,label)
 def race(winner,loser,phone):
  h=start('staff_phone_holder',expect(helper(winner,phone),'winner unavailable')+change(winner,phone));ready(h)
  w=start('staff_phone_waiter',expect('NOT '+helper(loser,phone),'duplicate admitted'));blocked('staff_phone_waiter',w)
  finish(h);ready(w);finish(w)
  out=simple("SELECT count(*) FROM private.burimunsi_accounts WHERE phone='%s' AND active AND NOT removed;"%phone).splitlines()
  assert '1' in out,'two edits claimed the same phone'
 try:
  lease=start('staff_phone_lease','',True);ready(lease)
  setup=prefix+config+assertwork+gate+"SELECT private.burimunsi_pin_create_session('%s','%s'::uuid,'%s'::uuid,'internal_receiver',"%(group,admin,install)
  setup+="encode(sha256(convert_to(repeat('2',64),'UTF8')),'hex'),1,gen_random_uuid(),encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'),"
  setup+="floor(extract(epoch FROM clock_timestamp())*1000)::bigint-1000,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1799000,1);"+pin
  for n,acct in [(61,target1),(62,target2)]:
   setup+="WITH target AS (SELECT private.burimunsi_pin_resolve_staff('%s',api.current_session_id()::uuid,api.current_principal_id(),'Synthetic Staff %s','+2507800000%s',ARRAY['records.read'],'fe610000-0000-4000-8000-0000000000%s'::uuid) AS v) "%(group,n,n,n)
   setup+="INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at) SELECT '%s'::uuid,'%s',v->>'id','+2507800000%s','Synthetic Staff','staff',ARRAY['records.read'],'{\"synthetic\":true}'::jsonb,1,1 FROM target;"%(acct,group,n)
  sql(setup+'COMMIT;')
  race(target1,target2,'+250780000063')
  simple(change(target1,'+250780000061'))
  race(target2,target1,'+250780000064')
  h=start('staff_phone_holder',"UPDATE private.burimunsi_accounts SET active=false WHERE id='%s'::uuid;"%target1);ready(h)
  w=start('staff_phone_waiter',"SELECT "+helper(target1,'+250780000065')+';');blocked('staff_phone_waiter',w);finish(h)
  w.wait(timeout=15);err=w.stderr.read().decode();assert w.returncode!=0 and '42501' in err,(w.returncode,err[-1200:])
  w.stdin.close()
  h=start('staff_phone_holder',expect(helper(target2,'+250780000065'),'edit unavailable')+change(target2,'+250780000065'));ready(h)
  w=start('staff_phone_waiter',"UPDATE private.burimunsi_accounts SET active=false WHERE id='%s'::uuid;"%target2)
  blocked('staff_phone_waiter',w);finish(h);ready(w);finish(w)
  out=simple("SELECT count(*) FROM private.burimunsi_accounts WHERE id='%s'::uuid AND phone='+250780000065' AND NOT active;"%target2).splitlines()
  assert '1' in out,'later revocation did not take effect'
  finish(lease)
  closed=json.loads(result(prefix+"SELECT private.collect_fence_close('%s'::uuid,%s,'%s','settled','completed',0,0);COMMIT;"%(admission,epoch,source)))
  assert closed['state']=='settled' and closed['externalDispatches']==0
  return ['first_edit_wins_collision','second_edit_wins_collision','target_revocation_wins_edit','edit_before_target_revocation']
 finally:
  for p in children:
   if p.poll() is None:p.terminate();p.wait(timeout=5)
