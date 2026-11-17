"""No-network, disposable PG17 concurrency checks; invoked only by the guarded harness.

Tests true concurrent transactions against the already-installed synthetic chain.
All object-journal records are artificial, so no external upload is asserted.
"""
import hashlib,json,os,select,subprocess,time,uuid

PRINCIPAL='f3000000-0000-4000-8000-000000000001'
INSTALL='fe900000-0000-4000-8000-000000000071'
ACCOUNT='f7000000-0000-4000-8000-000000000001'
GROUP='buri-qualification-group'
PROFILE='synthetic-approved-v1'

def source_id(request):
 h=hashlib.sha256(('collect.storage.entity.v1\nburimunsi.native.observation.v1\n'+PRINCIPAL+'\n'+request).encode()).hexdigest()
 return h[:8]+'-'+h[8:12]+'-5'+h[13:16]+'-8'+h[17:20]+'-'+h[20:32]

def run_checks(docker,ident,database,source,sql,result,capacity):
 checks=[];children=[];admission=str(uuid.uuid4())
 prefix="BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL ROLE collect_runtime;SET LOCAL collect.edge_verified='true';"
 register=json.loads(result(prefix+"SELECT private.collect_fence_register('%s'::uuid,'%s','http_collect');COMMIT;"%(admission,source)))
 assert register['admissionId']==admission and register['sourceSha256']==source and register['state']=='active'
 epoch=register['epoch']; assert isinstance(epoch,int) and epoch>0
 configs="SELECT set_config('collect.fence_admission_id','%s',true),set_config('collect.fence_epoch','%s',true),set_config('collect.fence_source_sha256','%s',true),set_config('burimunsi.collection_id','%s',true);"%(admission,epoch,source,GROUP)
 assertion="SELECT private.collect_fence_assert_write('%s'::uuid,%s,'%s');"%(admission,epoch,source)
 claim=configs+assertion
 gate="SELECT pg_advisory_xact_lock(734636924058501::bigint);"
 pin="SELECT private.burimunsi_set_pin_context(repeat('1',64),'%s'::uuid,repeat('2',64),'internal_receiver');"%INSTALL
 wire=[*docker,'exec','-i',ident,'psql','-h','127.0.0.1','-p','55439','-U','postgres','-d',database,'-XAtq','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']
 def start(application_name,body,*,lock=True,lease=False):
  capacity();p=subprocess.Popen(wire,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE);children.append(p)
  q=prefix+"SET LOCAL application_name='%s';SET LOCAL statement_timeout='12s';SET LOCAL lock_timeout='10s';"%application_name
  if lease:q+="SELECT pg_advisory_xact_lock_shared(7346371,1);SELECT private.collect_fence_assert_work('%s'::uuid,%s,'%s');"%(admission,epoch,source)
  else:q+=claim+(gate if lock else '')+pin+body
  p.stdin.write((q+'\n\\echo READY\n').encode());p.stdin.flush();return p
 def start_operator(application_name,body):
  capacity();p=subprocess.Popen(wire,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE);children.append(p)
  q="BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL application_name='%s';SET LOCAL statement_timeout='12s';SET LOCAL lock_timeout='10s';"%application_name
  q+="SET LOCAL collect.edge_verified='true';"+configs+body
  p.stdin.write((q+'\n\\echo READY\n').encode());p.stdin.flush();return p
 def marker(p):
  seen=b'';end=time.monotonic()+12
  while b'READY\n' not in seen:
   capacity()
   if p.poll() is not None:raise RuntimeError('concurrent SQL unexpectedly exited: '+p.stderr.read().decode()[-1500:])
   if time.monotonic()>end:raise RuntimeError('concurrent SQL marker timed out')
   ready,_,_=select.select([p.stdout],[],[],0.1)
   if ready:seen+=os.read(p.stdout.fileno(),8192)
  return seen
 def finish(p):
  p.stdin.write(b'COMMIT;\n\\q\n');p.stdin.flush();p.stdin.close();p.wait(timeout=12)
  if p.returncode!=0:raise RuntimeError('concurrent SQL commit failed: '+p.stderr.read().decode()[-1200:])
 def failed(p,expected):
  p.wait(timeout=12);err=p.stderr.read().decode();assert p.returncode!=0 and expected in err,(p.returncode,err[-1500:]);p.stdin.close()
 def wait_blocked(name,p):
  end=time.monotonic()+10
  while time.monotonic()<end:
   capacity()
   if p.poll() is not None:raise RuntimeError('concurrent contender was not blocked: '+p.stderr.read().decode()[-1200:])
   n=result("SELECT count(*) FROM pg_stat_activity WHERE application_name='%s' AND wait_event_type='Lock';"%name)
   if n=='1':return
   time.sleep(0.1)
  raise RuntimeError('concurrent contender did not reach the expected lock')
 def simple(body):return sql(prefix+claim+gate+pin+body+'COMMIT;').stdout
 def prepare(request,generation):
  value=source_id(request)
  return ("SELECT private.burimunsi_observation_prepare('%s'::uuid,repeat('d',64),'%s','%s',"
   "(SELECT encode(sha256(convert_to(profile_json,'UTF8')),'hex') FROM app.momo_receiving_accounts WHERE id='buri-qualification-wallet'),%s);"%(request,value,PROFILE,generation))
 def commit(request,generation):
  value=source_id(request)
  return ("SELECT private.burimunsi_observation_commit('%s'::uuid,repeat('d',64),'%s',repeat('b',64),repeat('c',64),4,'%s',"
   "(SELECT encode(sha256(convert_to(profile_json,'UTF8')),'hex') FROM app.momo_receiving_accounts WHERE id='buri-qualification-wallet'),%s);"%(request,value,PROFILE,generation))
 def blocked_pair(first_sql,second_sql,second_expected=None):
  h=start('buri_race_holder',first_sql);marker(h)
  w=start('buri_race_waiter',second_sql);wait_blocked('buri_race_waiter',w)
  finish(h)
  if second_expected:failed(w,second_expected)
  else:marker(w);finish(w)
 def check_count(expected):
  q=prefix+claim+gate+pin+"SELECT private.burimunsi_observation_page('','all',100,0)->>'totalCount';COMMIT;"
  out=sql(q).stdout.splitlines();assert str(expected) in out,out[-5:]
 try:
  lease=start('buri_race_lease','',lease=True);marker(lease)
  setup="BEGIN;SET LOCAL collect.edge_verified='true';"+configs+"UPDATE app.momo_receiving_accounts SET profile_status='approved',profile_version='%s',"%PROFILE
  setup+="profile_json='{\"sender_allowlist\":[\"Example Money\"],\"incoming_prefixes\":[\"Received\"],\"currency_aliases\":[\"RWF\"],\"transaction_id_prefixes\":[\"Reference:\"],\"date_format\":\"YMD_HMS\",\"utc_offset_minutes\":120}' WHERE id='buri-qualification-wallet';"
  setup+="UPDATE private.burimunsi_scopes SET enabled=false WHERE collection_id='%s' AND active_binding_id IS NULL;"%GROUP
  setup+="SET LOCAL ROLE collect_runtime;"+assertion+"SELECT private.burimunsi_pin_create_session('%s','%s'::uuid,'%s'::uuid,'internal_receiver',"%(GROUP,ACCOUNT,INSTALL)
  setup+="encode(sha256(convert_to(repeat('2',64),'UTF8')),'hex'),1,gen_random_uuid(),encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'),"
  setup+="floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);"
  setup+=pin+"SELECT private.burimunsi_observation_set_consent(true,1);COMMIT;"
  sql(setup)
  request='fe910000-0000-4000-8000-000000000071';sid=source_id(request);key='sms/'+sid
  simple(prepare(request,1))
  # The following three journal rows model a completed upload. They do not call
  # the provider; they exist solely to challenge SQL commit/consent ordering.
  scope="jsonb_build_object('ownerId','%s','purpose','sms_receipt','entityId','%s')"%(PRINCIPAL,sid)
  metadata="jsonb_build_object('sha256',repeat('c',64),'key_id','synthetic-key','source_fingerprint',repeat('a',64))"
  journal="INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body) VALUES('%s',repeat('a',64),%s,'sms:%s:'||repeat('c',64),'synthetic-key',repeat('c',64),'cipher');"%(key,scope,sid)
  journal+="INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state) VALUES('synthetic-concurrent', '%s',repeat('e',64),repeat('f',64),6,%s,'{\"contentType\":\"application/octet-stream\"}',%s,'committed');"%(key,scope,metadata)
  journal+="INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata) VALUES('%s','synthetic-concurrent',repeat('e',64),repeat('f',64),6,%s,'{\"contentType\":\"application/octet-stream\"}',%s);"%(key,scope,metadata)
  simple(journal)
  blocked_pair("SELECT private.burimunsi_observation_set_consent(false,2);",commit(request,1),'42501')
  # Admin sees the durable pending admission even though the uploader is no
  # longer permitted to list its own observations while consent is disabled.
  admin_pending=prefix+claim+gate+"SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001','session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);"
  admin_pending+="SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000001',repeat('a',64),'https://admin.collect.example','f5000000-0000-4000-8000-000000000001');"
  admin_pending+="SELECT private.burimunsi_observation_admin_page('%s',100,0) AS value;COMMIT;"%GROUP
  pages=[json.loads(line) for line in sql(admin_pending).stdout.splitlines() if line.startswith('{') and '"collectionId"' in line]
  assert len(pages)==1 and pages[0]['totalCount']==1 and pages[0]['items'][0]['retentionState']=='unresolved'
  out=sql(prefix+claim+gate+"SELECT sealed_body='cipher' FROM private.storage_payload_reservations WHERE object_key='%s';COMMIT;"%key).stdout.splitlines()
  assert 't' in out,'failed commit must retain the unresolved storage reservation'
  checks.append('revocation_before_commit_denied_and_retained')
  simple("SELECT private.burimunsi_observation_set_consent(true,3);")
  blocked_pair(commit(request,3),"SELECT private.burimunsi_observation_set_consent(false,4);")
  out=sql(prefix+claim+gate+"SELECT sealed_body IS NULL AND cleared_at IS NOT NULL FROM private.storage_payload_reservations WHERE object_key='%s';COMMIT;"%key).stdout.splitlines()
  assert 't' in out,'successful commit must clear its reserved ciphertext'
  checks.append('commit_before_revocation_retained')
  simple("SELECT private.burimunsi_observation_set_consent(true,5);")
  lookup=simple("SELECT private.burimunsi_observation_lookup('%s'::uuid,repeat('d',64))->>'sourceId';"%request).splitlines()
  assert sid in lookup,'same request must reconcile the retained source'
  check_count(1);checks.append('retained_retry_same_source')
  # One retained source does not use the 16-pending cap. Populate 15, then
  # hold the sixteenth transaction while a distinct seventeenth waits.
  for i in range(1,16):simple(prepare('fe920000-0000-4000-8000-%012d'%i,5))
  sixteenth='fe920000-0000-4000-8000-000000000016';seventeenth='fe920000-0000-4000-8000-000000000017'
  blocked_pair(prepare(sixteenth,5),prepare(seventeenth,5),'54000')
  simple(prepare(sixteenth,5))
  check_count(1)
  # Admin metadata includes all retained and unconfirmed admissions.
  admin=prefix+claim+gate+"SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001','session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);"
  admin+="SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000001',repeat('a',64),'https://admin.collect.example','f5000000-0000-4000-8000-000000000001');"
  admin+="SELECT private.burimunsi_observation_admin_page('%s',100,0)->>'totalCount';COMMIT;"%GROUP
  assert '17' in sql(admin).stdout.splitlines()
  checks.append('concurrent_last_slot_exact_retry_and_cap')
  # A profile cannot be inserted in the phantom gap after a canonical profile
  # was read: the operator takes the same scope row exclusively.
  h=start('buri_profile_scope_holder',"SELECT private.burimunsi_observation_context();");marker(h)
  profile="{\"sender_allowlist\":[\"Example Money\"],\"incoming_prefixes\":[\"Received\"],\"currency_aliases\":[\"RWF\"],\"transaction_id_prefixes\":[\"Reference:\"],\"date_format\":\"YMD_HMS\",\"utc_offset_minutes\":120}"
  insert="INSERT INTO private.burimunsi_detection_profiles(collection_id,expected_receiving_account_id,revision,enabled,profile_version,profile_json,evidence_sha256,configured_at) VALUES('%s','buri-qualification-wallet',1,true,'synthetic-detection-v1','%s',repeat('a',64),1);"%(GROUP,profile)
  w=start_operator('buri_profile_insert_waiter',insert);wait_blocked('buri_profile_insert_waiter',w);finish(h);marker(w);finish(w)
  out=simple("SELECT private.burimunsi_observation_context()->>'profile_kind';").splitlines();assert 'detection_only' in out
  checks.append('profile_insert_serializes_with_context')
  # The reverse ordering must also serialize: an operator holding the scope
  # and profile update blocks a later context, which then sees revocation.
  h=start_operator('buri_profile_operator_holder',"UPDATE private.burimunsi_detection_profiles SET enabled=false,revision=revision+1 WHERE collection_id='%s';"%GROUP);marker(h)
  w=start('buri_profile_capture_waiter',"SELECT private.burimunsi_observation_context();")
  wait_blocked('buri_profile_capture_waiter',w);finish(h);failed(w,'55000')
  sql("BEGIN;SET LOCAL collect.edge_verified='true';"+configs+"UPDATE private.burimunsi_detection_profiles SET enabled=true,revision=revision+1 WHERE collection_id='%s';COMMIT;"%GROUP)
  checks.append('profile_update_before_context_blocks_then_denies')
  h=start('buri_profile_revision_holder',"SELECT private.burimunsi_observation_context();");marker(h)
  w=start_operator('buri_profile_revoke_waiter',"UPDATE private.burimunsi_detection_profiles SET enabled=false,revision=revision+1 WHERE collection_id='%s';"%GROUP)
  wait_blocked('buri_profile_revoke_waiter',w);finish(h);marker(w);finish(w)
  denied=sql(prefix+claim+gate+pin+"SELECT private.burimunsi_observation_context();COMMIT;",expect_error=True)
  assert denied.returncode!=0 and 'burimunsi_observation_profile_unavailable' in denied.stderr
  checks.append('profile_revocation_serializes_and_blocks_capture')
  finish(lease)
  closed=json.loads(result(prefix+"SELECT private.collect_fence_close('%s'::uuid,%s,'%s','settled','completed',0,0);COMMIT;"%(admission,epoch,source)))
  assert closed['state']=='settled' and closed['externalDispatches']==0 and closed['uncertainDispatches']==0
  return checks
 finally:
  for p in children:
   if p.poll() is None:
    p.terminate()
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:p.kill();p.wait(timeout=5)
