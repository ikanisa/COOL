from pathlib import Path
import hashlib,json,os,re,select,subprocess,time,uuid,traceback,threading
ROOT=Path('/Volumes/COLLECT-STAGING-20261109/main-source')
OUT=Path(os.environ['NATIVE_AUTO_TEST_OUTPUT'])
EXTERNAL_OUTPUT=os.environ.get('NATIVE_AUTO_EXTERNAL_OUTPUT')=='1' and OUT.resolve().is_relative_to(Path('/Volumes/PRO-G40'))
DRAFT=Path('/Users/jeanbosco/Documents/Supabase/burimunsi-unresolved-sms-design-20261111')
D=['docker','--context','colima-supabase-local']
IMAGE='sha256:c141fd17ac6a76c4323e90b3aee8ff1a23d2e89e547c2b963cfadc309c079cc2'
op=str(uuid.uuid4());name='collect-owner-synthetic-'+op[:8];ident=None;database='collect_sms_content_test';stage='source admission';checks=[]
# Explicitly provided authorized owner address; fixture identity only. The
# isolated container has no external networking or real Auth/email services.
fixture_owner=os.environ.get('COLLECT_SYNTHETIC_OWNER_EMAIL','')
sha=lambda b:hashlib.sha256(b).hexdigest()
def save(name,obj):
 p=OUT/name
 with open(p,'w') as f: os.chmod(p,0o600);json.dump(obj,f,indent=2);f.write('\n')
def capacity(start=False):
 # This rehearsal uses a memory-limited Docker guest on SupaRuntime. Permit a
 # smaller internal reserve only when its outputs are on the external drive;
 # every volume is still watched continuously and the normal guard is unchanged.
 internal=(3.0 if start else 2.5) if EXTERNAL_OUTPUT else (4.5 if start else 3.5)
 thresholds={'/':internal,'/Volumes/T7':2.1,'/Volumes/PRO-G40':2.1,'/Volumes/SupaRuntime':2.1,'/Volumes/COLLECT-STAGING-20261109/main-source':2.1}
 free={}
 for path,minimum in thresholds.items():
  st=os.statvfs(path);free[path]=st.f_bavail*st.f_frsize
  if free[path]<minimum*1024**3:raise RuntimeError('CAPACITY_GUARD '+path)
 return free['/']
stopwatch=threading.Event();tripped=threading.Event();trip_error=[]
def watch():
 while not stopwatch.wait(0.25):
  try:capacity()
  except Exception as e:
   trip_error.append(str(e));tripped.set()
   try:
    if ident:
     raw=subprocess.run(D+['inspect',ident],capture_output=True,text=True,timeout=5)
     if raw.returncode==0:
      c=json.loads(raw.stdout)[0]
      if c['Id']==ident and c['Name']=='/'+name and c['Image']==IMAGE and c['Config'].get('Labels',{}).get('io.collect.observation-synthetic')==op:
       subprocess.run(D+['kill',ident],capture_output=True,text=True,timeout=8)
   except Exception:pass
   return
def run(*args,input=None,timeout=120,check=True):
 p=subprocess.run(D+list(args),input=input,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
 if check and p.returncode:raise RuntimeError('docker '+args[0]+' failed: '+p.stderr[:1800])
 return p

def owned():
 c=json.loads(run('inspect',ident).stdout)[0];h=c['HostConfig'];cfg=c['Config'];n=c['NetworkSettings']
 assert c['Id']==ident and c['Name']=='/'+name and c['Image']==IMAGE and c['State']['Running']
 assert cfg['User']=='postgres' and cfg['Labels']['io.collect.observation-synthetic']==op
 assert h['NetworkMode']=='none' and h['ReadonlyRootfs'] and h['Memory']==402653184
 assert not h.get('PortBindings') and not any((n.get('Ports') or {}).values())
 assert h['Tmpfs']=={'/var/lib/postgresql':'rw,size=268435456,mode=0700,uid=100,gid=101','/tmp':'rw,size=16777216,mode=1777'}
 assert not any(m.get('Type')!='tmpfs' for m in c.get('Mounts',[]))

def sql(text,user='postgres',db=None,expect_error=False,timeout=120):
 owned();capacity()
 p=run('exec','-i',ident,'psql','-h','127.0.0.1','-p','55439','-U',user,'-d',db or database,'-XAtqb','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose',input=text,check=not expect_error,timeout=timeout)
 return p

def result(q,user='postgres',db=None):return sql(q,user,db).stdout.strip()
def apply(row,user):
 text=contents[row['name']]
 if row['transaction']=='wrap':text='BEGIN;\n'+text+'\nCOMMIT;\n'
 sql(text,user)
 checks.append({'migration':row['name'],'sha256':row['sha256'],'status':'pass','owner':user})
 print('applied',len(checks),'of 40',row['name'],flush=True)

def fence_state():return json.loads(result("SELECT json_build_object('mode',mode,'epoch',epoch,'source',source_sha256) FROM private.collect_fence_control WHERE singleton;"))

def checked_fenced_apply(row):
 c=fence_state();assert c['mode']=='open' and c['source']==source;epoch=c['epoch'];fop=str(uuid.uuid4())
 b=json.loads(result("SELECT private.collect_fence_begin_quiesce('%s'::uuid,%s::bigint,'%s');"%(fop,epoch,source)));assert b['mode']=='quiescing'
 d=json.loads(result("SELECT private.collect_fence_drain('%s'::uuid,%s::bigint,'%s');"%(fop,epoch,source)));assert d['mode']=='fenced'
 apply(row,'postgres')
 release=json.loads(result("SELECT private.collect_fence_release('%s'::uuid,%s::bigint,'%s');"%(uuid.uuid4(),epoch,source)))
 assert release['mode']=='open' and release['epoch']==epoch+1

try:
 assert ROOT.resolve()==ROOT and OUT.is_dir() and OUT.stat().st_mode&0o077==0
 free=capacity(start=True)
 mem=run('exec','supabase_db_local-app','cat','/proc/meminfo').stdout
 available=int(re.search(r'^MemAvailable:\s+(\d+)\s+kB$',mem,re.M).group(1))*1024
 if available<3*1024**3:raise RuntimeError('guest memory below 3 GiB reserve')
 reviewed=subprocess.run(['node','-e',"import('./scripts/supabase/testing/self-hosted-current-schema.mjs').then(async m=>console.log((await m.reviewedCurrentMigrations()).length))"],cwd=ROOT,capture_output=True,text=True,timeout=25,check=True)
 assert reviewed.stdout.strip()=='49'
 lock=json.loads((ROOT/'deploy/self-hosted/migrations.lock.json').read_text());all_rows=lock['migrations'];assert len(all_rows)==49 and lock['original_count']==16
 rows=all_rows[:40]
 contents={}
 for row in rows:
  p=ROOT/'supabase/migrations'/row['name'];assert p.resolve()==p
  data=p.read_bytes();assert sha(data)==row['sha256'];contents[row['name']]=data.decode()
 # Do not weaken or rewrite the reviewed owner check. Verify that the explicit
 # fixture value equals the exact reviewed SQL condition before a container is
 # created. This is an isolated synthetic identity, not a real Auth user.
 if not re.fullmatch(r'[a-z0-9][a-z0-9._+\-]{0,63}@[a-z0-9][a-z0-9.\-]{0,189}',fixture_owner):
  raise RuntimeError('explicit COLLECT_SYNTHETIC_OWNER_EMAIL required')
 owner_sql=contents['20261023002500_collect_admin_recent_email_source_upgrade.sql']
 actor=re.search(r'CREATE OR REPLACE FUNCTION private\.admin_invitation_actor\(.*?END\$\$;',owner_sql,re.S)
 assert actor is not None
 owner_matches=re.findall(r"actor->>'identity_value' IS DISTINCT FROM '([^']+)'",actor.group(0))
 if len(owner_matches)!=1 or fixture_owner!=owner_matches[0]:raise RuntimeError('synthetic owner does not match reviewed owner condition')
 auth=(ROOT/'supabase/tests/sql/00_local_auth_fixture.sql').read_bytes();assert sha(auth)=='b935e17f44219f018cf1a864505d1895d71903885ca6c61c039d7ab6596117ea'
 plan=json.loads((ROOT/'scripts/supabase/testing/member-realtime-fixture-plan.json').read_text())
 interface=(ROOT/'scripts/supabase/testing/member-realtime-interface.sql').read_bytes();assert sha(interface)==plan['interface_sha256']
 meta=(ROOT/'scripts/supabase/testing/member-realtime-metadata.sql').read_bytes();assert sha(meta)==plan['metadata_expression_sha256']
 original=contents[rows[9]['name']];assert sha(original.encode())==plan['hosted_sql_sha256']
 old="'"+plan['hosted_metadata_sha256']+"'";new="'"+plan['synthetic_metadata_sha256']+"'"
 assert original.count(old)==plan['metadata_literal_occurrences']==2
 synthetic=original.replace(old,new);assert sha(synthetic.encode())==plan['synthetic_sql_sha256'] and synthetic.replace(new,old)==original
 source='a'*64  # synthetic-only fence identity used by the actual HTTP fixture
 assert run('image','inspect',IMAGE,'--format','{{json .Config.Volumes}}').stdout.strip()=='null'
 drafts={p.name:p.read_text() for p in (DRAFT/'private-quarantine.draft.sql',DRAFT/'private-quarantine-managed-admin.draft.sql')}
 retention_draft=os.environ.get('SYNTHETIC_RETENTION_DRAFT')=='1'
 if retention_draft:
  p=DRAFT/'retention-inspection.draft.sql';drafts[p.name]=p.read_text()
 owner_draft=os.environ.get('SYNTHETIC_OWNER_DRAFT')=='1'
 if owner_draft:
  assert retention_draft
  p=ROOT/'supabase/migrations/20261111121400_collect_protected_owner_identity.sql';assert p.read_bytes()==(DRAFT/'owner-identity.draft.sql').read_bytes();drafts['owner-identity.draft.sql']=p.read_text()
 promotion_draft=os.environ.get('SYNTHETIC_PROMOTION_DRAFT')=='1'
 if promotion_draft:
  p=DRAFT/'native-promotion-context.draft.sql';drafts[p.name]=p.read_text()
 clock_fix=True
 p=ROOT/'supabase/migrations/20261111121300_burimunsi_pin_clock_skew.sql'
 drafts['pin-clock-skew.draft.sql']=p.read_text()
 for key,migration_file in (('pin-bound-clock.draft.sql','20261111121500_burimunsi_pin_bound_clock.sql'),
  ('pin-rotation-expiry.draft.sql','20261111121600_burimunsi_pin_rotation_expiry.sql'),
  ('staff-phone-uniqueness.draft.sql','20261111121700_burimunsi_staff_phone_preservation.sql')):
  p=ROOT/'supabase/migrations'/migration_file;assert p.read_bytes()==(DRAFT/key).read_bytes();drafts[key]=p.read_text()
 draft_hashes={k:sha(v.encode()) for k,v in drafts.items()}
 registered={'private-quarantine.draft.sql':'20261111121000_burimunsi_private_observations.sql',
  'private-quarantine-managed-admin.draft.sql':'20261111121100_burimunsi_admin_observations.sql',
  'retention-inspection.draft.sql':'20261111121200_burimunsi_retention_inspection.sql',
  'pin-clock-skew.draft.sql':'20261111121300_burimunsi_pin_clock_skew.sql',
  'owner-identity.draft.sql':'20261111121400_collect_protected_owner_identity.sql',
  'pin-bound-clock.draft.sql':'20261111121500_burimunsi_pin_bound_clock.sql',
  'pin-rotation-expiry.draft.sql':'20261111121600_burimunsi_pin_rotation_expiry.sql',
  'staff-phone-uniqueness.draft.sql':'20261111121700_burimunsi_staff_phone_preservation.sql'}
 assert retention_draft
 assert [row['name'] for row in all_rows[40:48]]==list(registered.values())
 assert all_rows[48]['name']=='20261112200100_burimunsi_native_auto_transactions.sql'
 assert (ROOT/'supabase/migrations'/all_rows[48]['name']).read_bytes()==(ROOT/'docs/implementation/burimunsi-android/drafts/native-auto-transactions.draft.sql').read_bytes()
 for draft,migration_name in registered.items():
  assert sha((ROOT/'supabase/migrations'/migration_name).read_bytes())==draft_hashes[draft]
 race_path=OUT/'observation-races.py';race_source=race_path.read_text();race_hash=sha(race_source.encode())
 race_namespace={'__name__':'synthetic_observation_races'};exec(compile(race_source,str(race_path),'exec'),race_namespace)
 save('intent.json',{'draft_hashes':draft_hashes,'registered_names':registered,'memory_limit_bytes':402653184,'postgres_tmpfs_bytes':268435456,'tmp_tmpfs_bytes':16777216,'start_internal_gib':3.0 if EXTERNAL_OUTPUT else 4.5,'stop_internal_gib':2.5 if EXTERNAL_OUTPUT else 3.5,'minimum_external_gib':2.1,'pro_early_stop_gib':2.1,'operation':op,'container_name':name,'image':IMAGE,'internal_available_bytes':free,'guest_available_bytes':available,'synthetic_only':True,'owner_fixture_matches_reviewed_condition':True,'owner_fixture_is_synthetic':True,'owner_fixture_email_sha256':sha(fixture_owner.encode()),'email_sent':False,'real_auth_users_queried':False,'network':'none','persistent_mounts':False,'predecessor_fixture':'reviewed original16 with synthetic Auth and reviewed Realtime metadata substitution','reviewed_chain':all_rows,'source_identity_sha256':source,'production_acceptance':False})
 stage='create isolated container'
 capacity(start=True)
 recheck=run('exec','supabase_db_local-app','cat','/proc/meminfo').stdout
 if int(re.search(r'^MemAvailable:\s+(\d+)\s+kB$',recheck,re.M).group(1))*1024<3*1024**3:raise RuntimeError('guest memory below 3 GiB reserve')
 ident=run('create','--pull','never','--name',name,'--label','io.collect.observation-synthetic='+op,'--network','none','--memory','384m','--cpus','2','--user','postgres','--read-only','--tmpfs','/var/lib/postgresql:rw,size=268435456,mode=0700,uid=100,gid=101','--tmpfs','/tmp:rw,size=16777216,mode=1777','--entrypoint','/bin/sh',IMAGE,'-c','sleep 86400').stdout.strip()
 assert re.fullmatch('[a-f0-9]{64}',ident);save('container.json',{'id':ident,'operation':op})
 capacity(start=True)
 run('start',ident);threading.Thread(target=watch,daemon=True).start();owned();capacity()
 assert run('exec',ident,'stat','-f','-c','%T','/var/lib/postgresql').stdout.strip()=='tmpfs'
 stage='initialize fresh PostgreSQL'
 run('exec',ident,'initdb','-D','/var/lib/postgresql/data','-U','collect_test','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-instructions',timeout=90)
 run('exec',ident,'pg_ctl','-D','/var/lib/postgresql/data','-l','/tmp/pg.log','-o','-h 127.0.0.1 -p 55439 -k /tmp -c shared_buffers=32MB -c max_connections=30','start',timeout=45)
 identity=json.loads(result("SELECT json_build_object('user',current_user,'session',session_user,'db',current_database(),'host',host(inet_server_addr()),'port',inet_server_port(),'version',current_setting('server_version_num')::int/10000,'super',(SELECT rolsuper AND rolbypassrls FROM pg_roles WHERE rolname=current_user));",'collect_test','postgres'))
 assert identity=={'user':'collect_test','session':'collect_test','db':'postgres','host':'127.0.0.1','port':55439,'version':17,'super':True}
 sql('CREATE DATABASE "'+database+'" OWNER collect_test TEMPLATE template0 ENCODING \'UTF8\';','collect_test','postgres')
 stage='synthetic managed Auth and baseline 1-9'
 sql(auth.decode(),'collect_test')
 flags=json.loads(result("SELECT row_to_json(r) FROM (SELECT rolcanlogin,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolbypassrls,rolreplication FROM pg_roles WHERE rolname='postgres')r;",'collect_test'))
 assert not any(flags.values())
 for row in rows[:9]:apply(row,'collect_test')
 stage='reviewed Realtime interface and hosted refusal'
 sql(interface.decode(),'collect_test')
 refused=sql(original,'collect_test',expect_error=True)
 if refused.returncode==0 or '55000' not in refused.stderr or 'member_realtime_metadata_not_reviewed' not in refused.stderr:raise RuntimeError('Hosted metadata refusal mismatch: '+refused.stderr[-1200:])
 assert result("SELECT (to_regclass('private.member_realtime_control') IS NULL AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='realtime.messages'::regclass));",'collect_test')=='t'
 sql(synthetic,'collect_test');checks.append({'migration':rows[9]['name'],'sha256':rows[9]['sha256'],'status':'pass_reviewed_synthetic_binding','synthetic_sha256':plan['synthetic_sql_sha256'],'hosted_rejected_sqlstate':'55000'})
 print('applied 10 of 40 with reviewed synthetic metadata binding',flush=True)
 for row in rows[10:13]:apply(row,'collect_test')
 stage='transfer fresh fixture ownership to restricted postgres'
 transfer="""DO $owner$ DECLARE r record;BEGIN
 IF current_user<>'collect_test' OR session_user<>'collect_test' OR current_database()<>'%s' OR host(inet_server_addr())<>'127.0.0.1' THEN RAISE EXCEPTION 'OWNED_NEW_FIXTURE_REQUIRED';END IF;
 FOR r IN SELECT nspname FROM pg_namespace WHERE nspowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND nspname NOT LIKE 'pg_%%' AND nspname<>'information_schema' LOOP EXECUTE format('ALTER SCHEMA %%I OWNER TO postgres',r.nspname);END LOOP;
 FOR r IN SELECT c.oid::regclass object,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%%' AND n.nspname<>'information_schema' AND c.relkind IN('r','p','v','m','f') LOOP EXECUTE format('ALTER %%s %%s OWNER TO postgres',CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,r.object);END LOOP;
 FOR r IN SELECT c.oid::regclass object FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%%' AND n.nspname<>'information_schema' AND c.relkind='S' LOOP EXECUTE format('ALTER SEQUENCE %%s OWNER TO postgres',r.object);END LOOP;
 FOR r IN SELECT p.oid::regprocedure object FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%%' AND n.nspname<>'information_schema' AND p.prokind='f' LOOP EXECUTE format('ALTER FUNCTION %%s OWNER TO postgres',r.object);END LOOP;
 END;$owner$;"""%database
 sql(transfer,'collect_test');sql('ALTER DATABASE "'+database+'" OWNER TO postgres;','collect_test','postgres')
 sql("ALTER ROLE postgres LOGIN NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION PASSWORD '"+uuid.uuid4().hex+uuid.uuid4().hex+"';",'collect_test','postgres')
 flags=json.loads(result("SELECT row_to_json(r) FROM (SELECT current_user,session_user,host(inet_server_addr()) AS host,inet_server_port() AS port,(SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) AS privileged)r;"))
 assert flags=={'current_user':'postgres','session_user':'postgres','host':'127.0.0.1','port':55439,'privileged':False}
 stage='complete baseline 14-16'
 for row in rows[13:16]:apply(row,'postgres')
 init=json.loads(result("SELECT private.collect_fence_initialize('%s'::uuid,'%s','dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3');"%(uuid.uuid4(),source)));assert init['mode']=='open'
 sql('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz; ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false;')
 fenced=set('''20261109234517_burimunsi_native_operator_schema.sql 20261110030800_burimunsi_sms_source_scope.sql 20261110032620_burimunsi_native_provisioning.sql 20261110040728_burimunsi_gateway_classification.sql 20261110052756_burimunsi_dynamic_scope_setup.sql 20261110093218_burimunsi_managed_email_preauth.sql 20261110143000_burimunsi_native_phone_pin.sql 20261110181002_collect_local_stopped_admission.sql 20261110181003_burimunsi_gateway_handoff.sql 20261110193000_burimunsi_canonical_receipt_adoption.sql 20261111043455_collect_admin_email_otp_lifetime.sql 20261111120000_collect_admin_persistent_sessions.sql 20261111120200_burimunsi_native_session_renewal.sql 20261111120400_burimunsi_passcode_session_rotation.sql 20261111120500_burimunsi_native_logout_barrier.sql'''.split())
 stage='reviewed additive schema 17-40'
 for row in rows[16:]:
  stage='migration '+row['name']
  (checked_fenced_apply if row['name'] in fenced else lambda r:apply(r,'postgres'))(row)
 stage='current schema completeness'
 complete=result("SELECT to_regclass('private.collect_fence_admission_archive') IS NOT NULL AND to_regclass('private.guest_upgrade_challenges') IS NOT NULL AND to_regclass('app.notification_email_job_dispatches') IS NOT NULL AND to_regclass('collect_sms.messages') IS NOT NULL AND to_regclass('private.collect_deployment_identity') IS NOT NULL AND to_regclass('private.retention_inventory_manifests') IS NOT NULL AND to_regclass('private.retention_row_plans') IS NOT NULL AND to_regclass('private.collect_sms_fence_admissions') IS NOT NULL AND to_regclass('private.burimunsi_pin_session_links') IS NOT NULL AND to_regclass('private.burimunsi_gateway_handoffs') IS NOT NULL;")
 assert complete=='t' and len(checks)==40
 capacity();used=run('exec',ident,'df','-k','/var/lib/postgresql').stdout
 save('chain-result.json',{'status':'pass','synthetic':True,'migration_count':len(checks),'migrations':checks,'hosted_realtime_metadata_rejected':True,'synthetic_realtime_metadata_reviewed':True,'additive_owner':'postgres NOSUPERUSER NOBYPASSRLS','fence_state':fence_state(),'tmpfs_df':used,'real_data_capture':False,'production_acceptance':False})
 print('FULL 40 MIGRATION CHAIN PASSED',flush=True)
 # Retention predecessor bodies and metadata are captured only from this new,
 # synthetic, isolated fixture, never from a retained/live database.
 function_snapshot=json.loads(result("SELECT json_agg(json_build_object('signature',p.oid::regprocedure::text,'body',p.prosrc,'body_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'volatility',p.provolatile,'config',p.proconfig,'acl',p.proacl::text) ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN('_retention_manifest_catalog_v2','_retention_manifest_rows_v2','retention_capture_inventory_v2');"))
 assert len(function_snapshot)==3
 save('retention-predecessor-functions.json',{'synthetic_only':True,'functions':function_snapshot})
 # Inventory only function definitions/constraints in this isolated fixture.
 owner_functions=json.loads(result("SELECT coalesce(json_agg(json_build_object('signature',p.oid::regprocedure::text,'body',p.prosrc,'sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),'owner',pg_get_userbyid(p.proowner),'language',l.lanname,'definer',p.prosecdef,'parallel',p.proparallel,'volatility',p.provolatile,'config',p.proconfig,'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text),'[]') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang WHERE n.nspname IN('app','private','api') AND p.prosrc LIKE '%"+fixture_owner+"%';"))
 owner_constraints=json.loads(result("SELECT coalesce(json_agg(json_build_object('name',c.conname,'definition',pg_get_constraintdef(c.oid)) ORDER BY c.conname),'[]') FROM pg_constraint c WHERE c.conrelid='app.admin_users'::regclass;"))
 owner_triggers=json.loads(result("SELECT coalesce(json_agg(json_build_object('relation',c.oid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) ORDER BY c.oid::regclass::text,t.tgname),'[]') FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgisinternal AND c.oid IN('app.admin_users'::regclass,'app.admin_principal_links'::regclass,'app.admin_owner_bootstrap_claims'::regclass);"))
 save('owner-predecessor-synthetic.json',{'synthetic_only':True,'functions':owner_functions,'constraints':owner_constraints,'triggers':owner_triggers})
 stage='draft predecessor guard and fenced installation'
 def apply_draft(name,text,preflight_probe=False):
  c=fence_state();assert c['mode']=='open' and c['source']==source;epoch=c['epoch'];fop=str(uuid.uuid4())
  assert json.loads(result("SELECT private.collect_fence_begin_quiesce('%s'::uuid,%s::bigint,'%s');"%(fop,epoch,source)))['mode']=='quiescing'
  assert json.loads(result("SELECT private.collect_fence_drain('%s'::uuid,%s::bigint,'%s');"%(fop,epoch,source)))['mode']=='fenced'
  if preflight_probe is True:
   rejected=sql("BEGIN; ALTER TABLE private.storage_payload_reservations DISABLE TRIGGER storage_payload_identity;\n"+text,expect_error=True)
   assert rejected.returncode!=0 and '55000' in rejected.stderr and 'burimunsi_observation_install_precondition' in rejected.stderr
   assert result("SELECT tgenabled='O' FROM pg_trigger WHERE tgrelid='private.storage_payload_reservations'::regclass AND tgname='storage_payload_identity';")=='t'
   assert result("SELECT to_regclass('private.burimunsi_observation_requests') IS NULL;")=='t'
  elif preflight_probe=='owner':
   rejected=sql('BEGIN; ALTER FUNCTION private.admin_invitation_actor(text,text,text,text) STABLE;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'owner_identity_predecessor_changed' not in rejected.stderr:
    raise RuntimeError('Owner predecessor probe mismatch: '+rejected.stderr[-1200:])
   rejected=sql('BEGIN; GRANT EXECUTE ON FUNCTION private.admin_invitation_actor(text,text,text,text) TO anon;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'owner_identity_predecessor_changed' not in rejected.stderr:
    raise RuntimeError('Owner ACL probe mismatch: '+rejected.stderr[-1200:])
  elif preflight_probe=='boundclock':
   sig='private.burimunsi_pin_bound_session(text,uuid,text,text)'
   for command in ('ALTER FUNCTION '+sig+' STABLE','GRANT EXECUTE ON FUNCTION '+sig+' TO anon',
    'ALTER FUNCTION private.burimunsi_pin_session_context(text,uuid,text,text) STABLE'):
    rejected=sql('BEGIN; '+command+';\n'+text,expect_error=True)
    if rejected.returncode==0 or 'burimunsi_pin_bound_clock_predecessor_changed' not in rejected.stderr:
     raise RuntimeError('PIN bound clock preflight mismatch: '+rejected.stderr[-1200:])
  elif preflight_probe=='expiry':
   sig='private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint)'
   rejected=sql('BEGIN; ALTER FUNCTION '+sig+' STABLE;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'burimunsi_rotation_expiry_predecessor_changed' not in rejected.stderr:raise RuntimeError('Expiry predecessor probe mismatch')
   rejected=sql('BEGIN; GRANT EXECUTE ON FUNCTION '+sig+' TO anon;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'burimunsi_rotation_expiry_predecessor_changed' not in rejected.stderr:raise RuntimeError('Expiry ACL probe mismatch')
  elif preflight_probe=='clock':
   sig='private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint)'
   rejected=sql('BEGIN; ALTER FUNCTION '+sig+' STABLE;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'burimunsi_session_clock_predecessor_changed' not in rejected.stderr:
    raise RuntimeError('Clock predecessor probe mismatch: '+rejected.stderr[-1200:])
   rejected=sql('BEGIN; GRANT EXECUTE ON FUNCTION '+sig+' TO anon;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'burimunsi_session_clock_predecessor_changed' not in rejected.stderr:
    raise RuntimeError('Clock ACL probe mismatch: '+rejected.stderr[-1200:])
  elif preflight_probe=='retention':
   rejected=sql('BEGIN; ALTER FUNCTION private._retention_manifest_catalog_v2() VOLATILE;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'burimunsi_retention_inspection_predecessor_changed' not in rejected.stderr:
    raise RuntimeError('Retention preflight probe mismatch: '+rejected.stderr[-1200:])
   rejected=sql('BEGIN; GRANT EXECUTE ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer) TO anon;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'burimunsi_retention_inspection_predecessor_changed' not in rejected.stderr:
    raise RuntimeError('Retention ACL probe mismatch: '+rejected.stderr[-1200:])
   rejected=sql('BEGIN; ALTER TABLE private.burimunsi_observation_consents RENAME TO synthetic_missing_observation_consents;\n'+text,expect_error=True)
   if rejected.returncode==0 or 'burimunsi_retention_inspection_schema_changed' not in rejected.stderr:
    raise RuntimeError('Retention partial-cohort probe mismatch: '+rejected.stderr[-1200:])
  sql(text);checks.append({'migration':name,'sha256':draft_hashes[name],'status':'pass_registered_testing' if name in registered else 'pass_synthetic_draft','owner':'postgres'})
  assert json.loads(result("SELECT private.collect_fence_release('%s'::uuid,%s::bigint,'%s');"%(uuid.uuid4(),epoch,source)))['mode']=='open'
  print('DRAFT INSTALLED',name,flush=True)
 apply_draft('private-quarantine.draft.sql',drafts['private-quarantine.draft.sql'],True)
 apply_draft('private-quarantine-managed-admin.draft.sql',drafts['private-quarantine-managed-admin.draft.sql'])
 stage='retention catalog coverage after drafts'
 catalog=json.loads(result('SELECT private._retention_manifest_catalog_v2();'))
 actual=set(json.loads(result("SELECT coalesce(jsonb_agg(c.relname ORDER BY c.relname),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relkind IN ('r','p','v');")))
 js=json.loads((ROOT/'supabase/retention-inventory.json').read_text())
 sql_private={r['relation'].split('.',1)[1] for r in catalog['private_classes'] if r['relation'].startswith('private.')}
 js_private={r['relation'].split('.',1)[1] for r in js['classes'] if r['relation'].startswith('private.')}
 new_classes={'burimunsi_observation_consents','burimunsi_observation_requests','burimunsi_unresolved_observations','burimunsi_detection_profiles'}
 sql_missing=sorted(x for x in actual-sql_private if x.startswith('burimunsi_'))
 js_missing=sorted(x for x in actual-js_private if x.startswith('burimunsi_'))
 assert len(sql_missing)==len(js_missing)==33 and set(sql_missing)==set(js_missing) and new_classes.issubset(sql_missing)
 retention_refusal=sql('SELECT private._retention_manifest_schema_v2();',expect_error=True)
 assert retention_refusal.returncode!=0 and 'retention_manifest_unknown_private_relation' in retention_refusal.stderr
 retention={'synthetic':True,'predecessor_missing_count':29,'new_missing_count':4,'missing_private_relations':sql_missing,
  'js_and_sql_catalogs_agree':True,'fail_closed_error':'retention_manifest_unknown_private_relation','production_acceptance':False}
 save('retention-after-drafts.json',retention)
 print('RETENTION GAP VERIFIED: 29 predecessor plus 4 observation/detection classes remain uncataloged',flush=True)
 if retention_draft:
  stage='retention inspection draft predecessor and catalog'
  # Probe only inside an aborted transaction while the fixture fence is held.
  apply_draft('retention-inspection.draft.sql',drafts['retention-inspection.draft.sql'],'retention')
  new_catalog=json.loads(result('SELECT private._retention_manifest_catalog_v2();'))
  classified={e['relation'].split('.',1)[1] for e in new_catalog['private_classes'] if e.get('scope')=='unmapped_private' and e.get('blocked') is True}
  assert classified==set(sql_missing)
  post_functions=json.loads(result("SELECT json_agg(json_build_object('signature',p.oid::regprocedure::text,'body',p.prosrc,'sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),'owner',pg_get_userbyid(p.proowner),'language',l.lanname,'definer',p.prosecdef,'parallel',p.proparallel,'volatility',p.provolatile,'config',p.proconfig,'acl',p.proacl::text) ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang WHERE n.nspname='private' AND p.proname IN('_retention_manifest_catalog_v2','_retention_manifest_rows_v2','retention_capture_inventory_v2');"))
  save('retention-post-draft-synthetic.json',{'synthetic_only':True,'functions':post_functions})
  unknown=sql('BEGIN;CREATE TABLE private.synthetic_unknown_relation(id text);SELECT private._retention_manifest_schema_v2();',expect_error=True)
  assert unknown.returncode!=0 and 'retention_manifest_unknown_private_relation' in unknown.stderr
  print('RETENTION INSPECTION DRAFT INSTALLED; UNKNOWN RELATIONS REJECTED',flush=True)
 if promotion_draft:
  stage='unregistered native promotion assessment context'
  apply_draft('native-promotion-context.draft.sql',drafts['native-promotion-context.draft.sql'])
  print('UNREGISTERED PROMOTION CONTEXT DRAFT INSTALLED',flush=True)
 if clock_fix:
  stage='registered native session clock correction'
  apply_draft('pin-clock-skew.draft.sql',drafts['pin-clock-skew.draft.sql'],'clock')
  print('REGISTERED NATIVE CLOCK MIGRATION INSTALLED',flush=True)
 alternate_owner=os.environ.get('SYNTHETIC_ALTERNATE_OWNER')=='1'
 if alternate_owner:
  assert owner_draft
  stage='fresh synthetic alternative owner draft'
  apply_draft('owner-identity.draft.sql',drafts['owner-identity.draft.sql'],'owner')
  # A distinct reserved-domain identity is supplied only to this disposable DB.
  alt='synthetic-owner@example.invalid'
  assert result("SELECT private.collect_initialize_owner('f9000000-0000-4000-8000-000000000001'::uuid,'f4000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','"+alt+"','pbkdf2-sha256$600000$synthetic','Synthetic owner','synthetic-bootstrap');")=='t'
  print('FRESH ALTERNATE OWNER INITIALIZED WITHOUT EMAIL',flush=True)
 stage='PIN bound clock draft'
 apply_draft('pin-bound-clock.draft.sql',drafts['pin-bound-clock.draft.sql'],'boundclock')
 stage='registered PIN rotation actual-expiry migration'
 apply_draft('pin-rotation-expiry.draft.sql',drafts['pin-rotation-expiry.draft.sql'],'expiry')
 stage='registered staff phone migration'
 apply_draft('staff-phone-uniqueness.draft.sql',drafts['staff-phone-uniqueness.draft.sql'])
 stage='synthetic operator seed'
 # The historical Auth double has no AMR id; a nullable synthetic compatibility
 # column lets the retained-schema qualification seed run without touching shipping SQL.
 sql('ALTER TABLE auth.mfa_amr_claims ADD COLUMN id uuid UNIQUE;')
 seed=(ROOT/'supabase/tests/burimunsi/operator-seed.sql').read_text()
 if owner_matches[0] not in seed:raise RuntimeError('reviewed seed owner identity mismatch')
 seed=seed.replace(owner_matches[0],alt if alternate_owner else fixture_owner)
 # This synthetic owner already has a consumed OTP from the seed. Place that
 # prior challenge outside the real 60-second cooldown while preserving its
 # original valid session/auth time, so a second synthetic session can acquire
 # its own independent email proof without sleeping or changing production SQL.
 old_challenge='auth_at-1,auth_at+299,1,auth_at'
 new_challenge='auth_at-100,auth_at+299,1,auth_at'
 assert seed.count(old_challenge)==1
 seed=seed.replace(old_challenge,new_challenge)
 if alternate_owner:
  # Bootstrap already created these exact synthetic app identities; preserve the
  # rest of the real seed, including its confirmed Auth/session proof, unchanged.
  for subject,expected in [('f3000000-0000-4000-8000-000000000001',1),('f4000000-0000-4000-8000-000000000001',2)]:
   seed,n=re.subn(r"^ \('"+subject+r"',.*\),\n",'',seed,flags=re.M)
   assert n==expected,(subject,n)
  marker='SET LOCAL search_path=app,pg_catalog;'
  assert seed.count(marker)==1
  seed=seed.replace(marker,marker+"\nUPDATE app.users SET email='"+alt+"' WHERE id='f3000000-0000-4000-8000-000000000001';")
 sql(seed)
 print('SYNTHETIC OPERATOR SEED PASSED; PRIOR CHALLENGE OUTSIDE COOLDOWN',flush=True)
 if owner_draft and not alternate_owner:
  stage='operator-protected owner identity draft'
  apply_draft('owner-identity.draft.sql',drafts['owner-identity.draft.sql'],'owner')
  print('OWNER IDENTITY DRAFT INSTALLED',flush=True)

 stage='unregistered native automatic transactions migration'
 native_auto=ROOT/'docs/implementation/burimunsi-android/drafts/native-auto-transactions.draft.sql'
 native_text=native_auto.read_text();draft_hashes['native-auto-transactions.draft.sql']=sha(native_text.encode())
 apply_draft('native-auto-transactions.draft.sql',native_text)
 stage='synthetic auto worker contract'
 prefix="BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL ROLE collect_runtime;SET LOCAL collect.edge_verified='true';"
 leases=[]
 admissions={}
 try:
  for kind in ('http_collect','jobs'):
   admission=str(uuid.uuid4())
   record=json.loads(result(prefix+"SELECT private.collect_fence_register('%s'::uuid,'%s','%s');COMMIT;"%(admission,source,kind)))
   epoch=record['epoch'];admissions[kind]=(admission,epoch)
   leaseq=prefix+"SET LOCAL statement_timeout='5s';SET LOCAL lock_timeout='5s';SELECT pg_advisory_xact_lock_shared(7346371,1);SELECT private.collect_fence_assert_work('%s'::uuid,%s,'%s');\n\\echo LEASE_READY\n"%(admission,epoch,source)
   err=open(OUT/('lease-'+kind+'.stderr'),'w');os.chmod(err.name,0o600)
   lease=subprocess.Popen(D+['exec','-i',ident,'psql','-h','127.0.0.1','-p','55439','-U','postgres','-d',database,'-XAtq','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err)
   leases.append((lease,err,admission,epoch));lease.stdin.write(leaseq.encode());lease.stdin.flush();obs=b'';deadline=time.monotonic()+10
   while b'LEASE_READY\n' not in obs:
    if lease.poll() is not None or time.monotonic()>deadline:raise RuntimeError('Scoped lease unavailable '+kind)
    ready,_,_=select.select([lease.stdout],[],[],deadline-time.monotonic())
    if ready:obs+=os.read(lease.stdout.fileno(),8192)
  text=(ROOT/'docs/implementation/burimunsi-android/drafts/native-auto-contract.sql').read_text()
  replacements={'ADMISSION_ID':admissions['http_collect'][0],'ADMISSION_EPOCH':str(admissions['http_collect'][1]),
   'ADMISSION_SOURCE':source,'JOB_ADMISSION_ID':admissions['jobs'][0],'JOB_ADMISSION_EPOCH':str(admissions['jobs'][1])}
  for key,value in replacements.items():
   assert '__'+key+'__' in text;text=text.replace('__'+key+'__',value)
  admin_query=subprocess.run(['node','--input-type=module','-e',
   "import {momoTransactionSql} from './supabase/functions/_shared/domain/admin_momo.js'; console.log(momoTransactionSql({BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true'}))"],
   cwd=ROOT,capture_output=True,text=True,timeout=25,check=True).stdout.strip()
  assert admin_query.startswith('SELECT ') and ';' not in admin_query and text.count('ROLLBACK;')==1
  admin_check="SELECT pg_temp.check_observation((SELECT count(*) FROM ("+admin_query+") AS projected WHERE id=current_setting('qualification.source_1') AND native_group_id='buri-qualification-group' AND status='recorded')=1,'live Admin SQL projects the native transaction');\n"
  text=text.replace('ROLLBACK;',admin_check+'ROLLBACK;')
  sql(text,timeout=120)
  for lease,err,admission,epoch in leases:
   lease.stdin.write(b'COMMIT;\n\\q\n');lease.stdin.flush();lease.wait(timeout=10);assert lease.returncode==0
   closed=json.loads(result(prefix+"SELECT private.collect_fence_close('%s'::uuid,%s,'%s','settled','completed',0,0);COMMIT;"%(admission,epoch,source)))
   assert closed['state']=='settled'
  cross_layer=os.environ.get('NATIVE_AUTO_CROSS_LAYER')=='1'
  if cross_layer:
   stage='synthetic native worker cross-layer contract'
   import importlib.util
   spec=importlib.util.spec_from_file_location('native_auto_cross_layer',ROOT/'docs/implementation/burimunsi-android/drafts/native-auto-cross-layer.py')
   cross=importlib.util.module_from_spec(spec);spec.loader.exec_module(cross)
   cross.qualify(ROOT,OUT,D,ident,database,source,sql,result)
   print('NATIVE AUTO POSTGRES AND WORKER CROSS-LAYER PASSED',flush=True)
  provider_test=os.environ.get('BURI_AUTO_REAL_AI')=='1'
  save('result.json',{'status':'pass','chain_count':49,'draft_sha256':sha(native_text.encode()),
   'contract_sha256':sha(text.encode()),'admin_query_sha256':sha(admin_query.encode()),
   'cross_layer_executed':cross_layer,'synthetic_only':True,
   'network':'provider API plus isolated loopback DB bridge' if provider_test else 'isolated loopback DB bridge only',
   'provider_test':provider_test,'production_acceptance':False})
  print('NATIVE AUTO MIGRATION AND SYNTHETIC WORKER CONTRACT PASSED',flush=True)
 finally:
  for lease,err,_,_ in leases:
   if lease.poll() is None:lease.terminate();lease.wait(timeout=5)
   err.close()
except Exception as e:
 save('failure.json',{'status':'unconfirmed','stage':stage,'error':str(e),'traceback':traceback.format_exc(),'operation':op,'container_id':ident,'completed_migrations':checks,'guard_tripped':tripped.is_set(),'guard_error':trip_error,'synthetic_only':True,'production_acceptance':False})
 print('FAILED at',stage,':',str(e),flush=True)
 raise SystemExit(1)
finally:
 stopwatch.set()
 if ident:
  try:
   r=run('inspect',ident,check=False)
   if r.returncode==0:
    c=json.loads(r.stdout)[0]
    if c['Id']!=ident or c['Name']!='/'+name or c['Image']!=IMAGE or c['Config'].get('Labels',{}).get('io.collect.observation-synthetic')!=op:raise RuntimeError('OWNED_CONTAINER_IDENTITY_MISMATCH')
    run('rm','-f',ident,timeout=30);print('OWNED SYNTHETIC CONTAINER REMOVED',flush=True)
  except Exception as e:
   save('cleanup-error.json',{'operation':op,'container_id':ident,'error':str(e)})
   print('CLEANUP UNCONFIRMED',flush=True)
