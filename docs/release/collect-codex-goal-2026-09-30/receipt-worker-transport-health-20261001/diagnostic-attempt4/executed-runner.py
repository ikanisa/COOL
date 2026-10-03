#!/usr/bin/env python3
"""Transport observation delta: real pg_net0.20.0 tables, declared response faults.

Network-none cached PG17.6; synthetic role/Vault fixtures. No network, hosted
secret or SMS. Reuses sealed worker proof without repeating timed retry tests.
"""
import argparse,concurrent.futures,datetime,hashlib,json,pathlib,types,uuid
import receipt_operational_authority_uat as authority
ROOT=authority.ROOT;SOURCE=authority.SOURCE
MIGRATIONS=[ROOT/'supabase/migrations/20261001110000_receipt_operational_authority.sql',ROOT/'supabase/migrations/20261001120000_operational_exception_lifecycle.sql',ROOT/'supabase/migrations/20261001140000_receipt_deferral_exceptions.sql',ROOT/'supabase/migrations/20261001150000_receipt_exception_worker.sql',ROOT/'supabase/migrations/20261001160000_receipt_worker_transport_health.sql']
sha=authority.sha;now=authority.now;save=authority.save;ident=authority.ident

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--report-dir',required=True);args=parser.parse_args();report=pathlib.Path(args.report_dir).resolve();assert not report.exists();report.mkdir(parents=True);inputs=report/'inputs';inputs.mkdir();(inputs/'migrations').mkdir()
 marker=(SOURCE/'.collect-release-candidate.json').read_bytes();manifest=json.loads(marker);(inputs/'source08-marker.json').write_bytes(marker)
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();(inputs/'executed-helper.py').write_bytes(helper)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner);support=pathlib.Path(authority.__file__).read_bytes();(inputs/'authority-support.py').write_bytes(support)
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();(inputs/'row-free-platform.sql').write_bytes(baseline)
 bodies={p:p.read_bytes()for p in MIGRATIONS};sealed=ROOT/'docs/release/collect-codex-goal-2026-09-30/receipt-operational-authority-20261001/accepted-sql-attempt7/inputs/20261001110000_receipt_operational_authority.sql';assert bodies[MIGRATIONS[0]]==sealed.read_bytes()
 for p,b in bodies.items():(inputs/p.name).write_bytes(b)
 items=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=p.read_bytes();rel=str(p.relative_to(SOURCE));assert sha(b)==manifest['source_files'][rel]['sha256'];(inputs/'migrations'/p.name).write_bytes(b);version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=rel,sha256=sha(b),body=b.decode()))
 assert len(items)==177
 result=dict(status='running',scope='transport diagnostics delta; exact177 prerequisites+sealed110000+120000+140000+150000+160000; no130000 sender integration',started_at=now(),source08_manifest_sha256=sha(marker),migration_sha256={p.name:sha(b)for p,b in bodies.items()},runner_sha256=sha(runner),support_sha256=sha(support),helper_sha256=sha(helper),baseline_sha256=sha(baseline),checks=[],target={},hosted_written=False,device_used=False,sms_sent=False,jwt_verified=False)
 save(report/'execution-binding.json',{k:v for k,v in result.items()if k not in('checks','target')})
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 def case(name,ok=True):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'transport',result['target'])as t:
   platform,_=m.platform_shape();t.sql(platform,label='captured row-free platform');m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);";service="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expression,as_service=False):return json.loads(t.sql('begin;'+(service if as_service else auth)+'select '+expression+';commit;').stdout.strip().splitlines()[-1])
   def error(expression,code,label,as_service=False):
    observed=t.sql('begin;'+(service if as_service else auth)+'select '+expression+';rollback;',check=False);case(label,observed.returncode!=0 and code in observed.stderr)
   t.sql("begin;update auth.users set email='deferral-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'deferral-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic current email deferral owner');commit;")
   finance_tables=[('public','payments'),('public','payment_provider_confirmations'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_hybrid','sms_notification_attempts'),('collect_receipt_policy','content_evidence')]
   columns=m.columns(t,finance_tables);financial=lambda:m.fingerprints(t,columns)
   prior_finance=financial()
   for p in MIGRATIONS[:4]:t.sql(bodies[p].decode(),label='exact additive prerequisite '+p.name)
   case('sealed worker prerequisites preserve canonical financial evidence',financial()==prior_finance)
   sealed_dir=ROOT/'docs/release/collect-codex-goal-2026-09-30/receipt-exception-worker-20261001/accepted-sql-attempt8/inputs'
   assert all(bodies[p]==(sealed_dir/p.name).read_bytes()for p in MIGRATIONS[:4])
   scheduler_oid=t.scalar("select 'collect_ops.run_receipt_exception_schedule()'::regprocedure::oid;")
   health_definition=t.scalar("select encode(extensions.digest(pg_get_functiondef('public.admin_get_receipt_exception_worker_health_v1()'::regprocedure),'sha256'),'hex');")
   original_cron=t.json("select jsonb_agg(to_jsonb(j)order by jobid)from cron.job j;")
   before=financial();t.sql(bodies[MIGRATIONS[4]].decode(),label='new additive160000 transport observation')
   case('160000 preserves canonical financial and receipt evidence',financial()==before)
   case('scheduler OID and existing cron rows remain exact',scheduler_oid==t.scalar("select 'collect_ops.run_receipt_exception_schedule()'::regprocedure::oid;")and original_cron==t.json("select jsonb_agg(to_jsonb(j)order by jobid)from cron.job j;"))
   case('existing24field health function definition stays byte identical',health_definition==t.scalar("select encode(extensions.digest(pg_get_functiondef('public.admin_get_receipt_exception_worker_health_v1()'::regprocedure),'sha256'),'hex');"))
   schema=t.json("select jsonb_build_object('version',(select extversion from pg_extension where extname='pg_net'),'response_indexes',(select coalesce(jsonb_agg(indexdef),'[]')from pg_indexes where schemaname='net'and tablename='_http_response'),'schema_valid',collect_ops.receipt_transport_schema_valid());");save(report/'observed-pg-net-runtime.json',schema)
   case('actual pg_net0.20.0 shape and response-ID index match collector contract',schema['version']=='0.20.0'and schema['schema_valid']and any('(id)'in x for x in schema['response_indexes']))
   for role in ['anon','authenticated','service_role']:
    case(role+' cannot access private observations inspections or sampling helpers',t.scalar("select not has_schema_privilege("+q(role)+",'collect_ops','USAGE')and not has_function_privilege("+q(role)+",'collect_ops.receipt_transport_sample(bigint,uuid)','EXECUTE')and not exists(select 1 from pg_class c where c.relnamespace='collect_ops'::regnamespace and c.relname like 'receipt_transport_%'and c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE')));")=='t')
   tick=lambda:t.json('select collect_ops.run_receipt_exception_schedule();')
   case('default inactive wrapper neither observes nor dispatches',tick()=={'status':'inactive'}and t.scalar('select not exists(select 1 from collect_ops.receipt_transport_requests)and not exists(select 1 from collect_ops.receipt_worker_jobs);')=='t')
   def reconcile(limit=25,request=None,deadline=None):
    request=request or ident();deadline=deadline or t.scalar("select collect_ops.utc(clock_timestamp()+interval '90 seconds');")
    prior=financial();network=t.scalar('select count(*)from net.http_request_queue;');result=call('public.reconcile_receipt_worker_transport_v1('+','.join([q(request),str(limit),q(deadline)])+')',True);assert financial()==prior and t.scalar('select count(*)from net.http_request_queue;')==network;return result
   def rounds(n=3):return[reconcile()for _ in range(n)]
   error('public.reconcile_receipt_worker_transport_v1('+q(ident())+",1,clock_timestamp()+interval '90 seconds')",'42501','ordinary email owner cannot invoke trusted reconciler')
   error('public.reconcile_receipt_worker_transport_v1('+q(ident())+",26,clock_timestamp()+interval '90 seconds')",'22023','inspection batch cannot exceed25',True)
   error('public.reconcile_receipt_worker_transport_v1('+q(ident())+",1,clock_timestamp()-interval '1 second')",'55000','expired request cannot observe or consume quota',True)
   error('public.reconcile_receipt_worker_transport_v1('+q(ident())+",1,clock_timestamp()+interval '121 seconds')",'22023','inspection authority cannot exceed120seconds',True)
   # Explicit isolated Vault-view fixture; no managed encryption claim.
   result['vault_crypto_verified']=False;result['synthetic_vault_view']=True;result['network_response_source']='declared inserts into actual pg_net0.20.0 response table; no network worker'
   t.sql("alter view vault.decrypted_secrets rename to isolated_original_decrypted_secrets;create table vault.transport_fixture_credentials(name text primary key,decrypted_secret text);create view vault.decrypted_secrets as select name,decrypted_secret from vault.transport_fixture_credentials;insert into vault.transport_fixture_credentials values('collect_receipt_exception_project_url','https://lhbowpbcpwoiparwnwgt.supabase.co'),('collect_receipt_exception_api_key','SYNTHETIC-PUBLISHABLE-KEY-ONLY'),('collect_receipt_exception_worker_secret','SYNTHETIC-WORKER-CREDENTIAL-NEVER-A-REAL-SECRET');select public.configure_receipt_exception_schedule_v1(1,true,25,20,1440,36000,28800);")
   queued=tick();request=queued['request_id'];http=queued['http_request_id'];job=t.json('select to_jsonb(j)from collect_ops.receipt_worker_jobs j where request_id='+q(request)+';')
   first=call('public.admin_get_receipt_worker_transport_v1('+q(request)+')');save(report/'observed-detail-not-collected.json',first)
   case('new detail reports actual uncollected dispatch without guessed status or ACK',first['original_status']=='pending'and first['rows'][0]['outcome']=='NOT_COLLECTED'and first['rows'][0]['http_request_id']==str(http)and first['original_receipt_status']is None)
   scan=reconcile();save(report/'observed-reconciled-queued.json',scan)
   collected=call('public.admin_get_receipt_worker_transport_v1('+q(request)+')');save(report/'observed-detail-queued.json',collected)
   case('queue observation binds actual dispatchedHTTPID with immutable request ACK',scan['inspected']==1 and scan['observations_added']==1 and collected['rows'][0]['outcome']=='QUEUED_UNOBSERVED'and not collected['rows'][0]['transport_terminal']and t.scalar('select count(*)=1 from collect_ops.receipt_transport_request_observations where request_id='+q(scan['request_id'])+';')=='t')
   case('evidence digest binds original request dispatch and observed finite metadata',t.scalar("select o.evidence_sha256=encode(extensions.digest(convert_to(jsonb_build_object('http_request_id',d.http_request_id::text,'request_id',d.request_id,'attempt',d.attempt,'dispatched_at',collect_ops.utc(d.dispatched_at),'metadata',jsonb_build_object('outcome',o.outcome,'transport_terminal',o.transport_terminal,'http_status',o.http_status,'worker_error_code',o.worker_error_code,'response_rows_observed',o.response_rows_observed,'response_at',collect_ops.utc(o.response_at)))::text,'UTF8'),'sha256'),'hex')from collect_ops.receipt_transport_observations o join collect_ops.receipt_worker_dispatches d using(http_request_id)where d.request_id="+q(request)+';')=='t')
   case('retained evidence is logged despite ephemeral unlogged pg_net responses',t.scalar("select(select relpersistence='p'from pg_class where oid='collect_ops.receipt_transport_observations'::regclass)and(select relpersistence='u'from pg_class where oid='net._http_response'::regclass);")=='t')
   old_obs=t.scalar('select count(*)from collect_ops.receipt_transport_observations;');old_units=t.scalar('select count(*)from collect_ops.receipt_transport_inspections;')
   case('same exact original returns unchanged receipt without duplicate observation or quota',reconcile(25,scan['request_id'],scan['expires_at'])==scan and t.scalar('select count(*)from collect_ops.receipt_transport_observations;')==old_obs and t.scalar('select count(*)from collect_ops.receipt_transport_inspections;')==old_units)
   error('public.reconcile_receipt_worker_transport_v1('+','.join([q(scan['request_id']),'1',q(scan['expires_at'])])+')','22023','same reconciliation UUID cannot change limit',True)
   found=call('public.get_receipt_worker_transport_request_v1('+q(scan['request_id'])+')',True);save(report/'observed-original-lookup.json',found)
   case('lost reconciliation response recovers exact immutable receipt',found['status']=='recorded'and found['receipt']==scan)
   rounds();case('restart cyclic cursor preserves stable queued evidence signatures',t.scalar('select count(*)from collect_ops.receipt_transport_observations;')==old_obs)
   def response(http_id,status=None,timed=False,error=None,body=None,created='clock_timestamp()'):
    t.sql('insert into net._http_response(id,status_code,timed_out,error_msg,content,headers,created)values('+','.join([str(http_id),str(status)if status is not None else'null',str(timed).lower(),q(error)if error is not None else'null',q(body)if body is not None else'null',q(json.dumps({'x-private':'SECRET-HEADER-DO-NOT-PERSIST'}))+'::jsonb',created])+');')
   response(http,503,body=json.dumps({'error':'WORKER_UNCONFIGURED'}));rounds()
   configured=call('public.admin_get_receipt_worker_transport_v1('+q(request)+')');save(report/'observed-detail-config-refused.json',configured)
   case('strict allowlisted503 error becomes actionable configuration refusal',configured['rows'][0]['outcome']=='WORKER_CONFIG_REFUSED'and configured['rows'][0]['worker_error_code']=='WORKER_UNCONFIGURED'and'WORKER_CONFIG_REFUSED'in configured['alerts']and configured['original_status']=='pending')
   t.sql('delete from net._http_response where id='+str(http)+';delete from net.http_request_queue where id='+str(http)+';');rounds()
   retained=call('public.admin_get_receipt_worker_transport_v1('+q(request)+')')
   case('pg_net ephemeral response pruning cannot erase retained terminal evidence',retained['rows']==configured['rows'])
   ids={}
   def dispatch_fixture():
    # Installer-only preexisting original/dispatch fixture. HTTP ID/body is
    # produced by the real net.http_post queue function with network worker off.
    rid=ident();t.sql('with stamp as materialized(select clock_timestamp()at)insert into collect_ops.receipt_worker_jobs select '+q(rid)+",2,25,20,(at at time zone 'UTC')::date,at,at+interval '90 seconds'from stamp;")
    hid=int(t.scalar("select net.http_post(url:='https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-exception-worker',body:='{}'::jsonb,headers:='{}'::jsonb,timeout_milliseconds:=15000);"));t.sql('insert into collect_ops.receipt_worker_dispatches values('+q(rid)+',1,'+str(hid)+',clock_timestamp());');return rid,hid
   cases=[('accepted',200,False,None,'SENSITIVE-BODY-DO-NOT-PERSIST','HTTP_ACCEPTED'),('pending',202,False,None,'{"error":"WORKER_OUTCOME_UNKNOWN"}','HTTP_PENDING'),
    ('auth',401,False,None,'{"error":"WORKER_AUTH_REQUIRED"}','AUTH_REFUSED'),('authority',403,False,None,None,'AUTH_REFUSED'),('endpoint',404,False,None,None,'ENDPOINT_UNAVAILABLE'),
    ('request',400,False,None,None,'REQUEST_REFUSED'),('conflict',409,False,None,'{"error":"WORKER_ORIGINAL_CONFLICT"}','REQUEST_REFUSED'),
    ('rate',429,False,None,None,'RATE_LIMITED'),('server',503,False,None,'{"error":"WORKER_UNCONFIGURED","private":"SECRET"}','HTTP_SERVER_FAILURE'),
    ('refused',418,False,None,None,'HTTP_REFUSED'),('redirect',302,False,None,None,'HTTP_UNEXPECTED'),('timeout',None,True,'SENSITIVE-NETWORK-ERROR',None,'NETWORK_TIMEOUT'),
    ('network',None,False,'SENSITIVE-DNS-NETWORK-ERROR',None,'NETWORK_FAILURE'),('invalid',700,False,None,None,'RESPONSE_INVALID'),('contradictory',200,True,None,None,'RESPONSE_INVALID'),
    ('bad_json',503,False,None,'{"error":"\\u0000"}','HTTP_SERVER_FAILURE'),('oversized',503,False,None,json.dumps({'error':'WORKER_UNCONFIGURED','padding':'x'*2000}),'HTTP_SERVER_FAILURE')]
   for name,status,timed,error_text,body,expected in cases:
    rid,hid=dispatch_fixture();response(hid,status,timed,error_text,body);ids[name]=(rid,hid,expected)
   rid,hid=dispatch_fixture();response(hid,409,body=json.dumps({'error':'WORKER_ORIGINAL_CONFLICT','request_id':rid}));ids['exact_conflict']=(rid,hid,'ORIGINAL_CONFLICT')
   rid,hid=dispatch_fixture();response(hid,200);response(hid,401);ids['duplicate_response']=(rid,hid,'RESPONSE_CONFLICT')
   rid,hid=dispatch_fixture();t.sql('delete from net.http_request_queue where id='+str(hid)+';');ids['absent']=(rid,hid,'RESPONSE_UNOBSERVED')
   stray=int(t.scalar("select net.http_post(url:='https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-exception-worker',body:='{}'::jsonb,headers:='{}'::jsonb,timeout_milliseconds:=15000);"));response(stray,401)
   rounds(4)
   for name,(rid,hid,expected)in ids.items():
    detail=call('public.admin_get_receipt_worker_transport_v1('+q(rid)+')');save(report/('observed-detail-'+name+'.json'),detail)
    case('actual response-table fault '+name+' derives '+expected+' without worker ACK',detail['rows'][0]['outcome']==expected and detail['original_receipt_status']is None and detail['original_status']=='pending'and not detail['financial_action']and not detail['send_action']and not detail['resend_action'])
   case('unregistered unrelated pg_net response cannot enter worker evidence',t.scalar('select not exists(select 1 from collect_ops.receipt_transport_observations where http_request_id='+str(stray)+');')=='t')
   # Installer fixture supplies an already expired original. Reuse150000's
   # accepted real90second expiry proof; no need to repeat that timed success.
   expired_request=ident();t.sql('with stamp as materialized(select clock_timestamp()at)insert into collect_ops.receipt_worker_jobs select '+q(expired_request)+",2,25,20,(at at time zone 'UTC')::date,at-interval '100 seconds',at-interval '10 seconds'from stamp;")
   expired_http=int(t.scalar("select net.http_post(url:='https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-exception-worker',body:='{}'::jsonb,headers:='{}'::jsonb,timeout_milliseconds:=15000);"));t.sql('insert into collect_ops.receipt_worker_dispatches values('+q(expired_request)+",1,"+str(expired_http)+",clock_timestamp()-interval '95 seconds');");response(expired_http,200);rounds(4)
   expired_unknown=call('public.admin_get_receipt_worker_transport_v1('+q(expired_request)+')');save(report/'observed-detail-expired-unknown.json',expired_unknown)
   case('accepted HTTP on expired original remains unknown without durable receipt or absence fence',expired_unknown['original_status']=='unknown'and expired_unknown['rows'][0]['outcome']=='HTTP_ACCEPTED'and expired_unknown['original_receipt_status']is None)
   t.sql("begin;select pg_advisory_xact_lock(hashtext('collect-receipt-exception-job:'||"+q(expired_request)+"));insert into collect_ops.receipt_worker_expirations values("+q(expired_request)+",clock_timestamp(),'expired_without_receipt');commit;")
   expired_fenced=call('public.admin_get_receipt_worker_transport_v1('+q(expired_request)+')');save(report/'observed-detail-expired-fenced.json',expired_fenced)
   case('retained original expiry proof alone changes absence status without transport rewriting',expired_fenced['original_status']=='expired_without_receipt'and expired_fenced['rows']==expired_unknown['rows'])
   t.sql('alter table net._http_response rename to isolated_missing_http_response;');unavailable=reconcile();save(report/'observed-reconciled-runtime-unavailable.json',unavailable)
   schema_fault=call('public.admin_get_receipt_worker_transport_v1('+q(request)+')');save(report/'observed-detail-schema-unavailable.json',schema_fault)
   case('actual missing response relation records finite runtime refusal and actionable read alert',unavailable['status']=='runtime_unavailable'and unavailable['inspected']==0 and'SOURCE_SCHEMA_UNAVAILABLE'in schema_fault['alerts']and not schema_fault['collector']['source_schema_valid'])
   t.sql('alter table net.isolated_missing_http_response rename to _http_response;');case('source restoration retains exact immutable observations',call('public.admin_get_receipt_worker_transport_v1('+q(request)+')')['rows']==configured['rows'])
   all_evidence=t.json("select jsonb_build_object('observations',(select jsonb_agg(to_jsonb(o))from collect_ops.receipt_transport_observations o),'requests',(select jsonb_agg(to_jsonb(r))from collect_ops.receipt_transport_requests r));");save(report/'final-redacted-evidence.json',all_evidence)
   case('durable evidence contains no response content headers URL or raw network error',not any(x in json.dumps(all_evidence)for x in ['SENSITIVE','SECRET','supabase.co','error_msg','content_type','headers','raw_body']))
   # An HTTP200 observation is independent of the real original worker ACK.
   accepted_request=ids['accepted'][0];accepted_job=t.json('select to_jsonb(j)from collect_ops.receipt_worker_jobs j where request_id='+q(accepted_request)+';')
   processed=call('public.execute_receipt_exception_worker_v1('+','.join([q(accepted_request),str(accepted_job['configuration_revision']),q(accepted_job['expires_at'])])+')',True)
   acknowledged=call('public.admin_get_receipt_worker_transport_v1('+q(accepted_request)+')');save(report/'observed-detail-original-recorded.json',acknowledged)
   case('only actual immutable worker receipt changes original state to recorded',processed['status']=='recorded'and acknowledged['original_status']=='recorded'and acknowledged['original_receipt_status']=='completed'and acknowledged['scan_request_id']==accepted_request and acknowledged['rows'][0]['outcome']=='HTTP_ACCEPTED')
   with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
    holder=pool.submit(t.sql,"begin;set local application_name='transport-overlap';select pg_advisory_xact_lock(hashtext('collect-receipt-transport-reconcile'));select pg_sleep(1);commit;")
    for _ in range(100):
     if t.scalar("select exists(select 1 from pg_stat_activity where application_name='transport-overlap'and wait_event='PgSleep');")=='t':break
     m.time.sleep(.01)
    else:raise AssertionError('collector overlap fixture unavailable')
    busy=reconcile();save(report/'observed-reconciled-busy.json',busy);case('collector overlap records immutable busy receipt without inspection quota',busy['status']=='busy'and busy['inspected']==0);holder.result()
   unknown=ident();missing=call('public.get_receipt_worker_transport_request_v1('+q(unknown)+')',True)
   case('missing original lookup remains fresh absence without fabricated expiry or receipt',missing['status']=='not_recorded'and missing['expires_at']is None and missing['receipt']is None)
   expired_auth=t.sql('begin;update auth.sessions set not_after=clock_timestamp()-interval \'1 second\'where id='+q(m.SID)+';'+auth+'select public.admin_get_receipt_worker_transport_v1('+q(request)+');rollback;',check=False);case('expired operator session cannot read transport detail',expired_auth.returncode!=0 and'42501'in expired_auth.stderr)
   revoked=t.sql('begin;update public.admin_user_roles set revoked_at=clock_timestamp()where user_id='+q(m.UID)+';'+auth+'select public.admin_get_receipt_worker_transport_v1('+q(request)+');rollback;',check=False);case('revoked current role cannot read retained transport evidence',revoked.returncode!=0 and'42501'in revoked.stderr)
   units=int(t.scalar('select count(*)from collect_ops.receipt_transport_inspections;'));t.sql('update collect_ops.receipt_transport_configuration set day_inspections='+str(units)+' where singleton;');quota=reconcile();save(report/'observed-reconciled-quota.json',quota)
   case('atomic daily inspection cap refuses further work without touching originals',quota['status']=='quota_exhausted'and quota['inspected']==0 and int(t.scalar('select count(*)from collect_ops.receipt_transport_inspections;'))==units)
   quota_detail=call('public.admin_get_receipt_worker_transport_v1('+q(request)+')');save(report/'observed-detail-quota.json',quota_detail);case('fresh redacted collector quota alert is actionable','COLLECTOR_QUOTA_EXHAUSTED'in quota_detail['alerts']and quota_detail['collector']['quota_exhausted'])
   case('actual detail has exact15top12row7collector contract keys',set(quota_detail)=={'contract_version','request_id','checked_at','sample_valid_until','original_status','original_expires_at','original_receipt_status','scan_request_id','rows','alerts','collector','source_scan_complete','financial_action','send_action','resend_action'}and all(set(row)=={'attempt','http_request_id','dispatched_at','evidence_revision','outcome','transport_terminal','http_status','worker_error_code','response_rows_observed','response_at','observed_at','evidence_sha256'}for row in quota_detail['rows'])and set(quota_detail['collector'])=={'configuration_revision','last_request_id','last_recorded_at','day_inspections','day_cap','quota_exhausted','source_schema_valid'})
   for table in ['receipt_transport_requests','receipt_transport_inspections','receipt_transport_observations','receipt_transport_request_observations']:
    mutation=t.sql('delete from collect_ops.'+table+';',check=False);case(table+' original evidence cannot be deleted',mutation.returncode!=0 and'55000'in mutation.stderr)
   t.sql("select public.configure_receipt_exception_schedule_v1(2,false,25,20,1440,36000,28800);")
   case('proof finishes inactive and finances unchanged without network/SMS execution',tick()=={'status':'inactive'}and financial()==before and t.scalar("select not active from cron.job where jobname='collect-receipt-exceptions';")=='t')
  result['status']='pass'
 except BaseException as error:result['status']='failed';result['error']=str(error);raise
 finally:
  result['sources_unchanged']=all(p.read_bytes()==b for p,b in bodies.items());result['runner_unchanged']=pathlib.Path(__file__).read_bytes()==runner;result['support_unchanged']=pathlib.Path(authority.__file__).read_bytes()==support;result['finished_at']=now();save(report/'result.json',result)
if __name__=='__main__':main()
