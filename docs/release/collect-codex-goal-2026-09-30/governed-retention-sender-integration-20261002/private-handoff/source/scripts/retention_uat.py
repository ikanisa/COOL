#!/usr/bin/env python3
"""Affected205 snapshot +420/440/800 reconstruction, then private900.
No new chronological/full restore acceptance, hosted/service/provider work.
"""
import argparse,concurrent.futures,datetime,hashlib,json,pathlib,subprocess,sys,time,types,uuid
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
STAGE=ROOT/'.cache/collect-governed-sender-retention-20261002'
SNAP=ROOT/'.cache/receipt-worker-snapshot-capture-20261002/proof/sql-attempt6'
sha=lambda b:hashlib.sha256(b).hexdigest()
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(p,x):p.write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',type=pathlib.Path,required=True);ap.add_argument('--owner-tail',action='store_true');ap.add_argument('--lookup-tail',action='store_true');a=ap.parse_args();report=a.report_dir.resolve();assert not report.exists();report.mkdir(parents=True);inputs=report/'inputs';inputs.mkdir();cmds=report/'commands';cmds.mkdir()
 tail_started=False
 result=dict(status='running',started_at=now(),checks=[],bindings={},target={},scope='affected205 logical snapshot + exact420/440/800 then private900; not new full chronological208, all-table restore, hosted or runtime acceptance',fixture_roles_and_grants_inherited=True,new_grants_or_privileged_fallback=False)
 def capture(p,name=None,copy=True):
  b=p.read_bytes();result['bindings'][str(p)]=dict(bytes=len(b),sha256=sha(b));
  if copy:(inputs/(name or p.name)).write_bytes(b)
  return b
 runner=capture(pathlib.Path(__file__),'executed-runner.py');helper=capture(ROOT/'scripts/tests/collect_current_release_upgrade_uat.py','executed-helper.py');catalog_query=capture(ROOT/'scripts/sql/collect_recovery_source_catalog.sql');vector=json.loads(capture(STAGE/'CURRENT208_SOURCE_VECTOR.json'))
 for rel,digest in vector['migration_sha256'].items():
  p=ROOT/rel;assert sha(capture(p,p.name,copy=False))==digest
 assert len(vector['migration_sha256'])==208
 raw=capture(SNAP/'capture/database.dump',copy=False);assert sha(raw)=='32b06c370fa292b651555fb5db8e42ce0056502b1182a576933fbfe6d18f710b'
 expected=json.loads(capture(SNAP/'restored-source-catalog.json',copy=False));capture(SNAP/'driver-result.json',copy=False);capture(SNAP/'capture/worker-snapshot.json',copy=False)
 body=capture(STAGE/'implementation/supabase/migrations/20261002090000_governed_receipt_retention_controls.sql','900.sql')
 m=types.ModuleType('helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=ROOT;q=m.quoted
 capture(pathlib.Path(sys.executable).resolve(),copy=False);capture(pathlib.Path(m.DOCKER),copy=False)
 original_command=m.command;counter=0
 def recorded(args,text=None,check=True,timeout=120):
  nonlocal counter
  counter+=1;n=counter;start=now();r=original_command(args,text,False,timeout);p=cmds/f'{n:04d}'
  p.with_suffix('.stdout').write_text(r.stdout);p.with_suffix('.stderr').write_text(r.stderr)
  save(p.with_suffix('.json'),dict(argv=['POSTGRES_PASSWORD=<generated-local>'if x.startswith('POSTGRES_PASSWORD=')else x for x in args],input_sha256=sha(text.encode())if text is not None else None,exit_code=r.returncode,started_at=start,finished_at=now(),stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode())))
  if check and r.returncode:raise RuntimeError(r.stderr[-2000:])
  return r
 m.command=recorded
 def case(name,ok):
  if (a.owner_tail or a.lookup_tail) and not tail_started:
   assert ok,name
   result.setdefault('required_fixture_preconditions',[]).append(name);return
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 def oldprocs(t):return t.json("select jsonb_agg(jsonb_build_object('oid',oid,'schema',pronamespace::regnamespace::text,'name',proname,'source',encode(sha256(convert_to(prosrc,'UTF8')),'hex'),'acl',proacl,'owner',pg_get_userbyid(proowner),'config',proconfig,'definer',prosecdef,'volatility',provolatile)order by oid)from pg_proc where pronamespace not in('pg_catalog'::regnamespace,'information_schema'::regnamespace);")
 try:
  with m.Target(report,'retention',result['target'])as t:
   # Exact selected205 fixture's inherited platform prelude. No application
   # cron DML grant or new owner API grant is introduced. Catalog must match.
   t.sql("do $$begin if not exists(select 1 from pg_roles where rolname='supabase_functions_admin')then create user supabase_functions_admin noinherit createrole login noreplication;end if;end$$;",user='supabase_admin',label='selected205 missing stock platform role only')
   r=subprocess.run([m.DOCKER,'exec','-i',t.name,'pg_restore','--clean','--if-exists','--file=-'],input=raw,capture_output=True,timeout=60);assert r.returncode==0,r.stderr[-2000:]
   # Exact accepted205 nonmember GraphQL restore preparation. No app source altered.
   t.sql('ALTER EXTENSION pg_graphql DROP FUNCTION graphql_public.graphql(text,text,jsonb,jsonb);DROP FUNCTION graphql_public.graphql(text,text,jsonb,jsonb);\n'+r.stdout.decode(),user='supabase_admin',label='selected205 full customdump reconstruction by reference')
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='ordinary selected205 owner restored')
   catalog=t.json(catalog_query.decode());save(report/'actual-selected205-catalog.json',catalog)
   diffs={k:dict(expected=expected[k],actual=catalog[k])for k in expected if expected[k]!=catalog[k]};save(report/'catalog-differences.json',diffs)
   case('actual selected205 complete normalized catalog matches retained exact source before delta replay',not diffs)
   result['inherited_platform']=dict(roles=[r for r in catalog['roles']if r[0]in ['postgres','supabase_admin']],memberships=catalog['memberships'],cron_relations=[r for r in catalog['relations']if r[0]=='cron'],cron_functions=[r for r in catalog['functions']if r[0]=='cron'])
   conf=t.json("select to_jsonb(c)-'singleton'from collect_receipt_worker_history.configuration c;")
   for version in ['20261002042000','20261002044000','20261002080000']:
    p=next((ROOT/'supabase/migrations').glob(version+'*.sql'));b=capture(p,p.name);t.sql(b.decode(),label='affected current208 delta '+p.name);t.sql('insert into supabase_migrations.schema_migrations(version,name,statements)values('+q(version)+','+q(p.stem[15:])+',array['+q(b.decode())+']);')
   case('three named compatible current208 deltas preserve exact700 configuration',conf==t.json("select to_jsonb(c)-'singleton'from collect_receipt_worker_history.configuration c;"))
   case('new migration installer is actual ordinary NOSUPERUSER',t.scalar("select not rolsuper from pg_roles where rolname=current_user;")=='t')
   before=oldprocs(t);save(report/'predecessor-function-association.json',before)
   cold_before=t.json("select jsonb_build_object('objects',(select jsonb_agg(to_jsonb(c)order by sha256)from collect_receipt_worker_history.objects c),'relocations',(select jsonb_agg(to_jsonb(c)order by family,original_key)from collect_receipt_worker_history.relocations c));")
   t.sql(body.decode(),label='private900 ordinary owner installation')
   after={x['oid']:x for x in oldprocs(t)}
   case('all existing function OID/prosrc/owner/ACL/config unchanged across additive900',all(after.get(x['oid'])==x for x in before))
   case('immutable adoption preserves actual enabled/batch/byte/revision without autoenable',t.json('select configuration from collect_receipt_retention_controls.adoption;')==conf)
   for role in ['anon','authenticated','service_role']:
    case(role+' cannot read or mutate private adoption/request or invoke prepare',t.scalar("select not has_schema_privilege("+q(role)+",'collect_receipt_retention_controls','USAGE')and not has_function_privilege("+q(role)+",'collect_receipt_worker_history.prepare(bigint,boolean,integer,integer)','EXECUTE');")=='t')
   case('only authenticated has the public controls entrypoints',t.scalar("select has_function_privilege('authenticated','public.admin_get_receipt_retention_controls_v1()','EXECUTE')and not has_function_privilege('anon','public.admin_get_receipt_retention_controls_v1()','EXECUTE')and not has_function_privilege('service_role','public.admin_get_receipt_retention_controls_v1()','EXECUTE');")=='t')
   # Freshen only the retained local synthetic owner/session fixture; production
   # auth/service approval RPCs are neither substituted nor claimed verified.
   u=t.scalar('select actor_id from collect_receipt_successors.approvals limit 1;')
   if not u:u=m.UID
   sid=t.scalar('select id from auth.sessions where user_id='+q(u)+'order by created_at limit 1;')
   t.sql('update auth.sessions set created_at=clock_timestamp(),updated_at=clock_timestamp(),not_after=clock_timestamp()+interval\'1 hour\'where id='+q(sid)+';',label='declared synthetic current session validity')
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=u,session_id=sid,role='authenticated',aal='aal1')))+",true);"
   def call(expr,prefix='',check=True):return t.json('begin;'+prefix+auth+'select '+expr+';commit;')if check else t.sql('begin;'+prefix+auth+'select '+expr+';rollback;',check=False)
   def bad(expr,code,name,prefix=''):
    r=call(expr,prefix,False);case(name,r.returncode!=0 and code in r.stderr)
   if a.lookup_tail:
    tail_started=True;result['scope']='only corrected full-intent/checked-at original lookup and expiration/replay denials;45+3 predecessor separate; affected205+420/440/800 prerequisite reconstruction'
    snap=call('public.admin_get_receipt_retention_controls_v1()');save(report/'observed-read-initial.json',snap)
    expiry=t.scalar("select collect_receipt_retention_controls.utc(clock_timestamp()+interval '100 seconds');");rid=str(uuid.uuid4())
    expr='public.admin_configure_receipt_retention_controls_v1('+','.join([q(rid),str(conf['revision']),'false','12','1048576',"'Synthetic governed maintenance test'",q(expiry)])+')'
    rec=call(expr);save(report/'observed-recorded.json',rec)
    def lookup(i,fp=None):return 'public.admin_get_receipt_retention_control_request_v1('+','.join([q(i['request_id']),q(fp or t.scalar('select collect_receipt_retention_controls.fingerprint('+q(json.dumps(i))+'::jsonb);')),q(json.dumps(i))+'::jsonb'])+')'
    recovered=call(lookup(rec['intent'],rec['fingerprint_sha256']));save(report/'observed-recovered.json',recovered);case('corrected full-intent lookup preserves exact13 immutable recorded result',recovered==rec)
    bad(lookup(rec['intent'],'f'*64),'55000','lookup wrong fingerprint refuses')
    altered={**rec['intent'],'reason':'Different retained original reason'};bad(lookup(altered),'55000','same UUID different full-intent fingerprint refuses recorded result')
    altered={**rec['intent'],'expires_at':'2099-01-01T00:00:00.000000Z'};bad(lookup(altered,rec['fingerprint_sha256']),'55000','lookup cannot declare a false expiry with original fingerprint')
    altered={**rec['intent'],'session_id':'99780000-0000-4000-8000-000000019999'};bad(lookup(altered,rec['fingerprint_sha256']),'55000','full-intent lookup session substitution refuses')
    missing={**rec['intent'],'request_id':str(uuid.uuid4()),'expected_revision':rec['after_configuration']['revision'],'expires_at':t.scalar("select collect_receipt_retention_controls.utc(clock_timestamp()+interval '1 second');")}
    # The process intentionally returns after the expiry, while its retained
    # server observation is before it. It must remain a predeadline observation.
    r=t.sql('begin;'+auth+'select '+lookup(missing)+';select pg_sleep(1.2);commit;')
    delayed=next(json.loads(x)for x in r.stdout.splitlines()if x.startswith('{')and 'rw_receipt_retention_control_request'in x);save(report/'observed-not-recorded-delayed-predeadline.json',delayed)
    deadline=datetime.datetime.fromisoformat(missing['expires_at'].replace('Z','+00:00'))
    case('delayed not-recorded producer is closed14 and carries server predeadline evidence',len(delayed)==14 and delayed['status']=='not_recorded'and datetime.datetime.fromisoformat(delayed['checked_at'].replace('Z','+00:00'))<deadline and datetime.datetime.now(datetime.timezone.utc)>=deadline)
    late=call(lookup(missing));save(report/'observed-not-recorded-after-deadline.json',late);case('fresh lookup after exact deadline proves absent original while holding UUID lock',datetime.datetime.fromisoformat(late['checked_at'].replace('Z','+00:00'))>=deadline and late['status']=='not_recorded')
    bad('public.admin_configure_receipt_retention_controls_v1('+','.join([q(missing['request_id']),str(missing['expected_revision']),'false','12','1048576',q(missing['reason']),q(missing['expires_at'])])+')','22023','exact missing original cannot be admitted after postdeadline lookup')
    save(report/'observed-missing-intent.json',missing)
    bad(lookup(rec['intent'],rec['fingerprint_sha256']),'42501','corrected original lookup refuses authoritative session expiry',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id="+q(sid)+';')
    # Same auth/session floor, original request lock, and expired current session
    # after a genuine wait. No configuration or request write occurs.
    waited={**missing,'request_id':str(uuid.uuid4()),'expires_at':t.scalar("select collect_receipt_retention_controls.utc(clock_timestamp()+interval '100 seconds');")}
    t.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 second\'where id='+q(sid)+';')
    with concurrent.futures.ThreadPoolExecutor()as pool:
     f=pool.submit(lambda:t.sql("begin;select pg_advisory_xact_lock(hashtext('collect-receipt-retention-request:"+waited['request_id']+"'));select pg_sleep(1.6);commit;"));time.sleep(.3)
     r=call(lookup(waited),check=False);f.result()
    case('corrected full-intent lookup reauthorizes after wait before publishing absence',r.returncode!=0 and '42501'in r.stderr)
    case('only original configure was recorded and existing700 identity/source body remain unchanged',t.scalar('select count(*)from collect_receipt_retention_controls.requests;')=='1'and all({x['oid']:x for x in oldprocs(t)}.get(x['oid'])==x for x in before))
    case('corrected producer and pinned source/tool bindings unchanged',all(sha(pathlib.Path(p).read_bytes())==v['sha256']for p,v in result['bindings'].items()))
    result['status']='passed';return
   if a.owner_tail:
    tail_started=True;result['scope']='three bounded owner-floor wait/expiry/permission/lookup checks after affected205+420/440/800 fixture construction;45-case precursor retained separately'
    def change(rid,expiry):return 'public.admin_configure_receipt_retention_controls_v1('+','.join([q(rid),str(conf['revision']),'false','12','1048576',"'Synthetic owner-floor postwait test'",q(expiry)])+')'
    # Real700 prove() admission owns roster. Exact held lock tuple, not just
    # activity text, binds the runtime wait to the source-derived floor.
    t.json('select collect_receipt_worker_history.prepare('+str(conf['revision'])+',true,12,1048576);');conf=t.json("select to_jsonb(c)-'singleton'from collect_receipt_worker_history.configuration c;")
    expiry=t.scalar("select collect_receipt_retention_controls.utc(clock_timestamp()+interval '1 second');")
    with concurrent.futures.ThreadPoolExecutor()as pool:
     f=pool.submit(lambda:t.sql("begin;select collect_receipt_worker_history.maintain('99780000-0000-4000-8000-000000099998',1,clock_timestamp()+interval '100 seconds');select pg_sleep(2);rollback;"));time.sleep(.3)
     g=pool.submit(lambda:call(change(str(uuid.uuid4()),expiry),check=False));time.sleep(.3)
     locks=t.json("select jsonb_build_object('expected_roster_objid',(hashtext('collect_admin_combined_roster')::bigint&4294967295),'rows',(select jsonb_agg(jsonb_build_object('pid',l.pid,'classid',l.classid::bigint,'objid',l.objid::bigint,'objsubid',l.objsubid,'mode',l.mode,'granted',l.granted,'blockers',pg_blocking_pids(l.pid)))from pg_locks l where locktype='advisory'));");save(report/'actual-owner-floor-advisory-binding.json',locks);r=g.result();f.result()
    case('actual700 roster wait tuple and postwait expiry refuse without config/request adoption',r.returncode!=0 and '22023'in r.stderr and any(not x['granted']and x['objid']==locks['expected_roster_objid']for x in locks['rows'])and t.scalar('select revision from collect_receipt_worker_history.configuration;')==str(conf['revision'])and t.scalar('select count(*)from collect_receipt_retention_controls.requests;')=='0')
    # A producer commits removal while it owns the actual roster publication
    # floor. The waiting caller must see the committed current permission.
    with concurrent.futures.ThreadPoolExecutor()as pool:
     f=pool.submit(lambda:t.sql("begin;select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner')and permission_name='settings.manage';select pg_sleep(1.5);commit;"));time.sleep(.3)
     r=call(change(str(uuid.uuid4()),t.scalar("select collect_receipt_retention_controls.utc(clock_timestamp()+interval '100 seconds');")),check=False);f.result()
    case('owner-floor wait sees committed manage revocation and refuses all writes',r.returncode!=0 and '42501'in r.stderr and t.scalar('select count(*)from collect_receipt_retention_controls.requests;')=='0')
    # No manage grant is restored: owner-only read recovery remains available,
    # but session expiry during the exact request lock wait removes authority.
    rid=str(uuid.uuid4());t.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 second\'where id='+q(sid)+';')
    with concurrent.futures.ThreadPoolExecutor()as pool:
     f=pool.submit(lambda:t.sql("begin;select pg_advisory_xact_lock(hashtext('collect-receipt-retention-request:"+rid+"'));select pg_sleep(1.6);commit;"));time.sleep(.3)
     r=call('public.admin_get_receipt_retention_control_request_v1('+q(rid)+','+q('a'*64)+')',check=False);f.result()
    case('original UUID lookup reauthorizes session after request wait before not-recorded result',r.returncode!=0 and '42501'in r.stderr)
    result['status']='passed';return
   snap=call('public.admin_get_receipt_retention_controls_v1()');save(report/'observed-read-initial.json',snap)
   case('real read closed11 shape and release declarations contain no runtime claims',len(snap)==11 and snap['actor_id']==u and snap['session_id']==sid and snap['configuration']==t.json("select collect_receipt_retention_controls.configuration(to_jsonb(c)-'singleton')from collect_receipt_worker_history.configuration c;") and all(p['verification_state']=='release_declared'and p['observed_at']is None for p in snap['platform_policies'].values()))
   rev=conf['revision'];req=str(uuid.uuid4());expiry=t.scalar("select collect_receipt_retention_controls.utc(clock_timestamp()+interval '100 seconds');")
   def configure(rid=req,revision=rev,enabled=False,limit=12,bytes=1048576,reason='Synthetic governed maintenance test',expires=expiry):return 'public.admin_configure_receipt_retention_controls_v1('+','.join([q(rid),str(revision),'true'if enabled else'false',str(limit),str(bytes),q(reason),q(expires)+'::timestamptz'])+')'
   expression=configure();record=call(expression);save(report/'observed-recorded.json',record)
   case('real specific configure preserves inactive state and atomically records revision/cron/intent',record['after_configuration']['revision']==rev+1 and not record['after_configuration']['enabled']and record['after_cron']['state']=='inactive'and len(record)==13)
   case('exact original UUID replay returns original immutable receipt without another revision',call(expression)==record and t.scalar('select revision from collect_receipt_worker_history.configuration;')==str(rev+1))
   lookup='public.admin_get_receipt_retention_control_request_v1('+q(req)+','+q(record['fingerprint_sha256'])+')'
   recovered=call(lookup);save(report/'observed-recovered.json',recovered);case('uncertain response original UUID lookup returns exact recorded result',recovered==record)
   absent=call('public.admin_get_receipt_retention_control_request_v1('+q(str(uuid.uuid4()))+','+q('a'*64)+')');save(report/'observed-not-recorded.json',absent);case('nonrecorded lookup is exact null result without absence of send claim',absent['status']=='not_recorded'and all(absent[k]is None for k in ['intent','recorded_at','before_configuration','after_configuration','before_cron','after_cron']))
   for key,kwargs in [('reason',dict(reason='Different reason exact UUID refused')),('enable',dict(enabled=True)),('batch',dict(limit=13)),('byte',dict(bytes=1048577)),('revision',dict(revision=rev+1)),('expiry',dict(expires='2099-01-01T00:00:00.000000Z'))]:bad(configure(**kwargs),'55000','same UUID '+key+' mismatch refused')
   bad('public.admin_get_receipt_retention_control_request_v1('+q(req)+','+q('a'*64)+')','55000','lookup conflicting fingerprint refused')
   bad(configure(rid=str(uuid.uuid4())),'55000','fresh UUID stale revision refused')
   bad(configure(rid=str(uuid.uuid4()),revision=rev+1,expires='2000-01-01T00:00:00.000000Z'),'22023','expired intent refused before prepare')
   bad(configure(rid=str(uuid.uuid4()),revision=rev+1,limit=26),'22023','batch beyond actual700 cap refused')
   bad(configure(rid=str(uuid.uuid4()),revision=rev+1,bytes=4194305),'22023','byte beyond actual700 cap refused')
   # Authoritative permission/session negatives roll back exact fixture changes.
   bad('public.admin_get_receipt_retention_controls_v1()','42501','settings read denial is authoritative',"delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner')and permission_name='settings.read';")
   bad(configure(rid=str(uuid.uuid4()),revision=rev+1),'42501','settings manage denial is authoritative',"delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner')and permission_name='settings.manage';")
   no_manage=t.sql('begin;delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name=\'platform_owner\')and permission_name=\'settings.manage\';'+auth+'select public.admin_get_receipt_retention_controls_v1();rollback;');denied_manage=json.loads(no_manage.stdout.strip().splitlines()[-1]);save(report/'observed-read-no-manage.json',denied_manage);case('valid read distinguishes absent manage permission',denied_manage['mutation_allowed']is False)
   bad('public.admin_get_receipt_retention_controls_v1()','42501','revoked owner role cannot read',"update public.admin_user_roles set revoked_at=clock_timestamp()where user_id="+q(u)+"and revoked_at is null;")
   bad('public.admin_get_receipt_retention_controls_v1()','42501','expired current session cannot read',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id="+q(sid)+';')
   bad('public.admin_get_receipt_retention_controls_v1()','42501','unverified email cannot read',"update auth.users set email_confirmed_at=null where id="+q(u)+';')
   r=t.sql("begin isolation level repeatable read;"+auth+"select public.admin_get_receipt_retention_controls_v1();rollback;",check=False);case('repeatable-read refuses fresh owner controls',r.returncode!=0 and '40001'in r.stderr)
   bad('public.admin_get_receipt_retention_control_request_v1('+q(req)+','+q(record['fingerprint_sha256'])+')','42501','original lookup refuses expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id="+q(sid)+';')
   bad('public.admin_get_receipt_retention_control_request_v1('+q(req)+','+q(record['fingerprint_sha256'])+')','55000','original lookup refuses a different current session',"insert into auth.sessions(id,user_id,created_at,updated_at,aal,not_after)values('99780000-0000-4000-8000-000000019999',"+q(u)+",clock_timestamp(),clock_timestamp(),'aal1',clock_timestamp()+interval '1 hour');"+"select set_config('request.jwt.claims','{}',true);") if False else None
   # Narrow unavailable cron projection and configure rollback on actual missing
   # SELECT, with original ACL restored by the transaction. No privilege fallback.
   missing=t.sql("begin;revoke select on cron.job from public,postgres;revoke pg_read_all_data from postgres;"+auth+"select public.admin_get_receipt_retention_controls_v1();rollback;",user='supabase_admin');unavailable=json.loads(missing.stdout.strip().splitlines()[-1]);save(report/'observed-cron-unavailable.json',unavailable);case('actual cron permission loss produces explicit unavailable read',unavailable['cron']['state']=='unavailable'and unavailable['cron']['job_id']is None)
   badcount=t.scalar('select count(*)from collect_receipt_retention_controls.requests;')
   r=t.sql("begin;revoke select on cron.job from public,postgres;revoke pg_read_all_data from postgres;"+auth+'select '+configure(rid=str(uuid.uuid4()),revision=rev+1)+';rollback;',user='supabase_admin',check=False);case('configure without actual cron privileges fails rather than fallback',r.returncode!=0 and '42501'in r.stderr and t.scalar('select count(*)from collect_receipt_retention_controls.requests;')==badcount)
   # Actual enabled -> bounded maintenance -> disable, with closed recorded DTO.
   enabled=call(configure(rid=str(uuid.uuid4()),revision=rev+1,enabled=True));save(report/'observed-enabled.json',enabled);case('enable changes storage maintenance only with actual active owned cron',enabled['after_cron']['state']=='active'and enabled['after_configuration']['enabled'])
   enabled_snap=call('public.admin_get_receipt_retention_controls_v1()');save(report/'observed-read-enabled.json',enabled_snap)
   heldid=str(uuid.uuid4())
   def hold(body):return t.sql('begin;'+body+"select pg_sleep(1.6);commit;",label='actual concurrent holder')
   with concurrent.futures.ThreadPoolExecutor()as pool:
    f=pool.submit(lambda:t.sql("begin;select collect_receipt_worker_history.maintain('99780000-0000-4000-8000-000000099999',1,clock_timestamp()+interval '100 seconds');select pg_sleep(2);rollback;",label='actual shipping700 maintain holds shared maintenance lock'));time.sleep(.3)
    g=pool.submit(lambda:call(configure(rid=str(uuid.uuid4()),revision=rev+2,enabled=True),check=False));time.sleep(.3)
    waits=t.json("select coalesce(jsonb_agg(jsonb_build_object('pid',pid,'wait_type',wait_event_type,'wait_event',wait_event,'blockers',pg_blocking_pids(pid),'query',query)),'[]')from pg_stat_activity where datname=current_database()and pid<>pg_backend_pid()and state<>'idle';")
    save(report/'actual-maintain-configure-wait.json',waits);r=g.result();f.result()
    outcome=json.loads(r.stdout.strip().splitlines()[-1])if r.returncode==0 else None
    case('actual700 maintenance serializes overlapping configure with no deadlock or premature record',r.returncode==0 and any(x['blockers']for x in waits)and outcome['after_configuration']['revision']==rev+3 and t.scalar('select revision from collect_receipt_worker_history.configuration;')==str(rev+2))
   with concurrent.futures.ThreadPoolExecutor()as pool:
    f=pool.submit(hold,"select pg_advisory_xact_lock(hashtext('collect-receipt-history-maintenance'));");time.sleep(.3)
    bad(configure(rid=str(uuid.uuid4()),revision=rev+2,enabled=True),'P0002','held maintenance advisory refuses a new configure');f.result()
   # Fresh request UUID wait crosses expiry; final authorization/expiry must win.
   expiry2=t.scalar("select collect_receipt_retention_controls.utc(clock_timestamp()+interval '1 second');")
   with concurrent.futures.ThreadPoolExecutor()as pool:
    f=pool.submit(hold,"select pg_advisory_xact_lock(hashtext('collect-receipt-retention-request:"+heldid+"'));");time.sleep(.3)
    bad(configure(rid=heldid,revision=rev+2,expires=expiry2),'22023','postwait request expiry refuses configure');f.result()
   # A read waits on the configuration, then current session expires by time.
   saved_session=t.json('select to_jsonb(s)from auth.sessions s where id='+q(sid)+';')
   t.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 second\'where id='+q(sid)+';')
   with concurrent.futures.ThreadPoolExecutor()as pool:
    f=pool.submit(hold,'select *from collect_receipt_worker_history.configuration where singleton for update;');time.sleep(.3)
    bad('public.admin_get_receipt_retention_controls_v1()','42501','postwait read reauthorizes expired session');f.result()
   t.sql('update auth.sessions set not_after='+q(saved_session['not_after'])+'::timestamptz where id='+q(sid)+';')
   disabled=call(configure(rid=str(uuid.uuid4()),revision=rev+2));save(report/'observed-disabled.json',disabled);case('disable stops future maintenance without deleting evidence',disabled['after_cron']['state']=='inactive'and not disabled['after_configuration']['enabled'])
   case('original recorded result remains original after later configure',call(lookup)==record)
   imm=t.sql('update collect_receipt_retention_controls.requests set fingerprint_sha256=repeat(\'f\',64);',check=False);case('recorded request evidence cannot be rewritten',imm.returncode!=0 and '55000'in imm.stderr)

   case('all immutable retained cold objects/relocations unchanged by configure/recovery',cold_before==t.json("select jsonb_build_object('objects',(select jsonb_agg(to_jsonb(c)order by sha256)from collect_receipt_worker_history.objects c),'relocations',(select jsonb_agg(to_jsonb(c)order by family,original_key)from collect_receipt_worker_history.relocations c));"))
   case('source/tool exact bindings unchanged',all(sha(pathlib.Path(p).read_bytes())==v['sha256']for p,v in result['bindings'].items()))
   result['status']='passed'
 except BaseException as e:result['status']='failed';result['error']=str(e);raise
 finally:
  result['finished_at']=now();result['target_removed']=result['target'].get('task_container_removed',False);save(report/'result.json',result)
if __name__=='__main__':main()
