#!/usr/bin/env python3
"""Trusted receipt worker proof. Cached network-none PG17.6, synthetic rows only.

SQL role claims are installer fixtures; HTTP auth is tested separately against
the real handler. Cron launch and pg_net worker are disabled in the owned target.
"""
import argparse,concurrent.futures,datetime,hashlib,json,pathlib,types,uuid
import receipt_operational_authority_uat as authority
ROOT=authority.ROOT;SOURCE=authority.SOURCE
MIGRATIONS=[ROOT/'supabase/migrations/20261001110000_receipt_operational_authority.sql',ROOT/'supabase/migrations/20261001120000_operational_exception_lifecycle.sql',ROOT/'supabase/migrations/20261001140000_receipt_deferral_exceptions.sql',ROOT/'supabase/migrations/20261001150000_receipt_exception_worker.sql']
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
 result=dict(status='running',scope='trusted worker feature; exact177 prerequisites+sealed110000+120000+140000+150000; no130000 sender integration',started_at=now(),source08_manifest_sha256=sha(marker),migration_sha256={p.name:sha(b)for p,b in bodies.items()},runner_sha256=sha(runner),support_sha256=sha(support),helper_sha256=sha(helper),baseline_sha256=sha(baseline),checks=[],target={},hosted_written=False,device_used=False,sms_sent=False,jwt_verified=False)
 save(report/'execution-binding.json',{k:v for k,v in result.items()if k not in('checks','target')})
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 def case(name,ok=True):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'exception_worker',result['target'])as t:
   platform,_=m.platform_shape();t.sql(platform,label='captured row-free platform');m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);";service="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expression,as_service=False):return json.loads(t.sql('begin;'+(service if as_service else auth)+'select '+expression+';commit;').stdout.strip().splitlines()[-1])
   def error(expression,code,label,as_service=False):
    observed=t.sql('begin;'+(service if as_service else auth)+'select '+expression+';rollback;',check=False);case(label,observed.returncode!=0 and code in observed.stderr)
   t.sql("begin;update auth.users set email='deferral-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'deferral-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic current email deferral owner');commit;")
   finance_tables=[('public','payments'),('public','payment_provider_confirmations'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_hybrid','sms_notification_attempts'),('collect_receipt_policy','content_evidence')]
   columns=m.columns(t,finance_tables);financial=lambda:m.fingerprints(t,columns)
   prior_finance=financial()
   for p in MIGRATIONS[:2]:t.sql(bodies[p].decode(),label='exact additive prerequisite '+p.name)
   case('operations and lifecycle prerequisites preserve existing canonical financial evidence',financial()==prior_finance)
   pub,kh=authority.key(0);principal=call('public.admin_enroll_receipt_operations_identity_v2('+','.join([q(ident()),q(pub),q(kh),"clock_timestamp()+interval '1 day'"])+')')['principal_id']
   def expression(action,payload=None,request=None):
    request=request or ident();payload=payload or{};return 'public.receipt_operations_execute_v2('+','.join([q(principal),q(request),q(kh),q(sha(json.dumps([action,request,payload]).encode())),'clock_timestamp()',q(action),q(json.dumps(payload))+'::jsonb'])+')'
   def execute(action,payload=None):return call(expression(action,payload),True)
   execute('prove_key');call('public.admin_activate_receipt_operations_identity_v2('+','.join(map(q,[principal,ident(),kh]))+')')
   gpub,gkh=authority.key(1);device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[ident(),ident(),gpub,gkh,'c'*64]))+')')['device_id']
   hp={'sms_permission':True,'network':'validated','telephony':'ready','sim_selected':True,'sim_revision_sha256':'d'*64,'local_pause':True,'reported_at':now().replace('+00:00','Z')};call('public.gateway_heartbeat_v1('+','.join(map(q,[device,ident(),'e'*64]))+','+q(json.dumps(hp))+'::jsonb)',True);call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,ident(),gkh,'c'*64]))+')')
   caps={key:(20 if key=='run_sms_segments'else 100)for key in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   def configure(run_actions=100):
    return call('public.admin_configure_receipt_operations_v2('+','.join([q(ident()),t.scalar('select revision from collect_receipt_operations.policy;'),"'Live-limited'"if run_actions<=10 else"'Live'",'false','array['+q(principal)+']::uuid[]','array['+q(m.GROUP)+']::uuid[]','array['+q(device)+']::uuid[]',q(json.dumps({**caps,'run_actions':run_actions}))+'::jsonb','true','24',"'Synthetic bounded deferral authority'","clock_timestamp()+interval '120 seconds'"])+')')
   def post(n,allocation=True,confirm=True):
    pid='99940000-0000-4000-8000-%012d'%(100000+n);raw='99940000-0000-4000-8000-%012d'%(600000+n);parsed='99940000-0000-4000-8000-%012d'%(700000+n);ref='DEFERRAL-'+str(n);wh=sha(b'+250788971001')
    if allocation:t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic deferral observation'","encode(extensions.digest('Synthetic deferral observation','sha256'),'hex')",q(wh),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(parsed),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wh),'100',q(ref),"'unallocated'","'Synthetic deferral payer'"])+');commit;')
    if confirm:t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values("+','.join([q(pid),q(parsed)if allocation else'null',q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+');select public.confirm_provider_payment('+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-DEFERRAL-'+str(n)),q(wh),'100','clock_timestamp()',"repeat('c',64)"])+');commit;',label='synthetic canonical payment '+str(n))
    return pid,parsed,raw
   event=lambda kind,source:t.json('select to_jsonb(e)from collect_hybrid.receipt_business_events e where source_kind='+q(kind)+'and source_id='+q(source)+'order by source_version desc limit 1;')
   run_args=lambda r:{'run_id':r['run_id'],'fence_version':r['fence_version']}
   ensure=lambda r,e:execute('ensure_receipt',{**run_args(r),'event_id':e['id'],'expected_source_version':e['source_version']})
   p1,_,_=post(1);p2,parsed2,raw2=post(2);configure(1);run=execute('begin_run');ensure(run,event('payment',p1));deferred=ensure(run,event('payment',p2));case('real live action cap creates retained pre-install event deferral',deferred['code']=='QUOTA_EXHAUSTED'and not deferred['business_handled'])
   t.sql(bodies[MIGRATIONS[2]].decode(),label='sealed140000 prerequisite')
   first_scan=call('public.process_receipt_deferral_exceptions_v1('+q(ident())+",25,clock_timestamp()+interval '90 seconds')",True)
   item=t.json("select to_jsonb(e)from collect_ops.exceptions e where source_kind='receipt_event'and source_id="+q(event('payment',p2)['id'])+"and active;")
   assigned=call('public.admin_act_exception_workflow_v1('+','.join([q(ident()),q(item['id']),str(item['revision']),'0',"'assign'",q(m.UID),"clock_timestamp()+interval '10 minutes'","'review_started'","clock_timestamp()+interval '100 seconds'"])+')')
   call('public.admin_act_exception_workflow_v1('+','.join([q(ident()),q(item['id']),str(item['revision']),str(assigned['workflow_revision']),"'escalate'",'null','null',"'owner_review_required'","clock_timestamp()+interval '100 seconds'"])+')')
   # A genuine subsequent operational deferral appends work behind the cursor.
   assert ensure(run,event('payment',p2))['code']=='QUOTA_EXHAUSTED'
   original_cron=t.json("select coalesce(jsonb_agg(to_jsonb(j)order by jobid),'[]')from cron.job j;");before=financial()
   t.sql(bodies[MIGRATIONS[3]].decode(),label='new additive150000 trusted worker')
   case('150000 preserves all canonical financial and receipt rows',financial()==before)
   case('new cron is inactive and all preexisting cron definitions unchanged',t.scalar("select count(*)=1 and bool_and(not active)from cron.job where jobname='collect-receipt-exceptions';")=='t'and t.json("select coalesce(jsonb_agg(to_jsonb(j)order by jobid),'[]')from cron.job j where jobname<>'collect-receipt-exceptions';")==original_cron)
   for role in ['anon','authenticated','service_role']:
    case(role+' cannot access private worker evidence or installer controls',t.scalar("select not has_schema_privilege("+q(role)+",'collect_ops','USAGE')and not has_function_privilege("+q(role)+",'public.configure_receipt_exception_schedule_v1(bigint,boolean,integer,integer,integer,integer,integer)','EXECUTE')and not exists(select 1 from pg_class c where c.relnamespace='collect_ops'::regnamespace and c.relname like 'receipt_worker_%'and c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE')));")=='t')
   tick=lambda:t.json('select collect_ops.run_receipt_exception_schedule();')
   case('inactive schedule produces no job or network wake',tick()=={'status':'inactive'}and t.scalar('select not exists(select 1 from collect_ops.receipt_worker_jobs);')=='t')
   def configure_worker(enabled=True,day_jobs=1440,day_scan=36000,day_escalations=28800):
    return t.json('select public.configure_receipt_exception_schedule_v1('+','.join([t.scalar('select revision from collect_ops.receipt_worker_configuration;'),str(enabled).lower(),'25','20',str(day_jobs),str(day_scan),str(day_escalations)])+');')
   missing=t.sql("select public.configure_receipt_exception_schedule_v1(1,true,25,20,1440,36000,28800);",check=False)
   case('activation without Vault refuses atomically with generic error',missing.returncode!=0 and'receipt_worker_transport_unconfigured'in missing.stderr and t.scalar('select revision=1 and not enabled from collect_ops.receipt_worker_configuration;')=='t')
   # This cached runtime has no pgsodium root key. Explicitly replace only its
   # isolated decrypted view, not production encryption or any real secret.
   result['vault_crypto_verified']=False;result['synthetic_vault_view']=True
   t.sql("alter view vault.decrypted_secrets rename to isolated_original_decrypted_secrets;create table vault.receipt_worker_fixture_credentials(name text primary key,decrypted_secret text);create view vault.decrypted_secrets as select name,decrypted_secret from vault.receipt_worker_fixture_credentials;insert into vault.receipt_worker_fixture_credentials values('collect_receipt_exception_project_url','https://wrongproject00000000.supabase.co'),('collect_receipt_exception_api_key','SYNTHETIC-PUBLISHABLE-KEY-ONLY'),('collect_receipt_exception_worker_secret','SYNTHETIC-WORKER-CREDENTIAL-NEVER-A-REAL-SECRET');")
   wrong=t.sql("select public.configure_receipt_exception_schedule_v1(1,true,25,20,1440,36000,28800);",check=False)
   case('wrong project URL cannot redirect worker credential',wrong.returncode!=0 and'receipt_worker_transport_unconfigured'in wrong.stderr)
   t.sql("update vault.receipt_worker_fixture_credentials set decrypted_secret='https://lhbowpbcpwoiparwnwgt.supabase.co'where name='collect_receipt_exception_project_url';")
   configured=configure_worker();case('verified synthetic transport prepares active definition while isolated cron launch stays off',configured['revision']==2 and configured['enabled']and t.scalar("select active from cron.job where jobname='collect-receipt-exceptions';")=='t'and t.scalar("select current_setting('cron.launch_active_jobs');")=='off')
   unobserved=call('public.admin_get_receipt_exception_worker_health_v1()');save(report/'observed-worker-unobserved-health.json',unobserved);case('enabled unobserved worker raises stale alert without inventing availability',unobserved['state']=='unobserved'and'WORKER_STALE'in unobserved['alerts'])
   queued=tick();job=t.json('select to_jsonb(j)from collect_ops.receipt_worker_jobs j where request_id='+q(queued['request_id'])+';')
   save(report/'observed-scheduled-job.json',queued)
   case('first wake reserves bounded quotas and queues one immutable90second job',queued['status']=='queued'and queued['attempt']==1 and job['scan_limit']==25 and job['escalation_limit']==20 and t.scalar('select count(*)=1 from collect_ops.receipt_worker_jobs;')=='t')
   queue=t.json('select jsonb_build_object(\'url\',url,\'body\',convert_from(body,\'UTF8\')::jsonb,\'timeout\',timeout_milliseconds)from net.http_request_queue where id='+str(queued['http_request_id'])+';');save(report/'observed-http-body.json',queue['body'])
   case('actual pg_net request is fixed-host exact original envelope with15second timeout',queue['url']=='https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-exception-worker'and set(queue['body'])=={'contract_version','action','request_id','configuration_revision','expires_at'}and queue['body']['request_id']==job['request_id']and queue['timeout']==15000)
   case('second immediate wake preserves original and avoids duplicate HTTP dispatch',tick()['status']=='pending'and t.scalar('select count(*)=1 from collect_ops.receipt_worker_dispatches;')=='t')
   def worker_expr(j,revision=None,deadline=None):return 'public.execute_receipt_exception_worker_v1('+','.join([q(j['request_id']),str(revision or j['configuration_revision']),q(deadline or j['expires_at'])])+')'
   error(worker_expr(job),'42501','ordinary owner cannot execute trusted worker')
   error(worker_expr(job,revision=3),'22023','same original UUID cannot change configuration revision',True)
   error(worker_expr({**job,'request_id':ident()}),'42501','service caller cannot invent an unscheduled job',True)
   before=financial();processed=call(worker_expr(job),True);save(report/'observed-worker-executed.json',processed)
   case('worker atomically scans actual deferral and delivers actual assigned escalation only',processed['status']=='recorded'and processed['receipt']['status']=='completed'and processed['receipt']['scan']['processed']>0 and processed['receipt']['escalation']['delivered']==1 and not processed['receipt']['external_send']and financial()==before)
   case('worker receipt has FK to exact original scan ACK',t.scalar('select count(*)=1 from collect_ops.receipt_worker_receipts r join collect_ops.receipt_exception_scans s on s.request_id=r.scan_request_id where r.request_id='+q(job['request_id'])+';')=='t')
   case('duplicate exact worker request returns original without duplicate inbox',call(worker_expr(job),True)==processed and t.scalar('select count(*)=1 from collect_ops.exception_inbox_deliveries;')=='t')
   lookup=call('public.get_receipt_exception_worker_request_v1('+q(job['request_id'])+')',True);save(report/'observed-worker-lookup.json',lookup)
   case('lost HTTP response recovers immutable exact original receipt',lookup['status']=='recorded'and lookup['receipt']==processed['receipt'])
   case('completed wake respects60second schedule cadence',tick()=={'status':'cadence'})
   health=call('public.admin_get_receipt_exception_worker_health_v1()');save(report/'observed-worker-health.json',health)
   case('fresh owner health is redacted truthful and no business/send claim',health['state']=='observed'and not health['source_scan_complete']and not health['financial_action']and not health['send_action']and not health['external_send']and not any(k in json.dumps(health)for k in ['recipient_id','raw_body','phone','amount_rwf']))
   with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
    holder=pool.submit(t.sql,"begin;set local application_name='trusted-worker-overlap';select pg_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'));select pg_sleep(1);commit;")
    for _ in range(100):
     if t.scalar("select exists(select 1 from pg_stat_activity where application_name='trusted-worker-overlap'and wait_event='PgSleep');")=='t':break
     m.time.sleep(.01)
    else:raise AssertionError('overlap fixture unavailable')
    case('global overlap refuses a schedule wake and returns explicit execution uncertainty',tick()=={'status':'overlap'}and call(worker_expr(job),True)['status']=='in_progress');holder.result()
   expired_auth=t.sql('begin;update auth.sessions set not_after=clock_timestamp()-interval \'1 second\'where id='+q(m.SID)+';'+auth+'select public.admin_get_receipt_exception_worker_health_v1();rollback;',check=False);case('expired operator session cannot inspect worker health',expired_auth.returncode!=0 and'42501'in expired_auth.stderr)
   def fixture_job(age=61,revision=None):
    # Installer-only time-control fixture; every immutable job still has exact90s life.
    request=ident();rev=revision or t.scalar('select revision from collect_ops.receipt_worker_configuration;')
    t.sql('with stamp as materialized(select clock_timestamp()at)insert into collect_ops.receipt_worker_jobs select '+q(request)+','+str(rev)+",25,20,(at at time zone 'UTC')::date,at-interval '"+str(age)+" seconds',at-interval '"+str(age)+" seconds'+interval '90 seconds'from stamp;")
    return t.json('select to_jsonb(j)from collect_ops.receipt_worker_jobs j where request_id='+q(request)+';')
   # Old synthetic jobs are earlier than the actual first wake, so latest selection
   # remains real; direct execution still proves expiry and authority fencing.
   expired=fixture_job(91);error(worker_expr(expired),'55000','expired original job refuses before any partial progress',True)
   missing_lookup=call('public.get_receipt_exception_worker_request_v1('+q(expired['request_id'])+')',True);save(report/'observed-worker-expired-lookup.json',missing_lookup)
   case('fresh expired not-recorded proof retains known original deadline',missing_lookup['status']=='not_recorded'and missing_lookup['expires_at']is not None and missing_lookup['receipt']is None)
   pending_job=fixture_job(20);disabled=configure_worker(False);error(worker_expr(pending_job),'42501','disable immediately revision-fences scheduled original',True)
   case('disabled configuration keeps original recorded proof readable',call('public.get_receipt_exception_worker_request_v1('+q(job['request_id'])+')',True)['receipt']==processed['receipt'])
   # Quotas reserve at creation; uncertainty never frees a consumed reservation.
   configure_worker(True,1,25,20)
   case('daily job and source budgets account for existing original reservations',t.scalar("select count(*)>=1 and sum(scan_limit)>=25 and sum(escalation_limit)>=20 from collect_ops.receipt_worker_jobs where reserved_day=(clock_timestamp()at time zone 'UTC')::date;")=='t')
   # A retained original from an interrupted scheduler transaction is a time-
   # controlled installer fixture. Actual wake/re-dispatch/expiry SQL runs with
   # real wall time and its exact immutable lease; no clock or function mock.
   uncertain=fixture_job(0);wake=tick();case('retained original wakes with same UUID and deadline instead of new job',wake['status']=='redispatched'and wake['request_id']==uncertain['request_id']and wake['attempt']==1)
   for attempt in [2,3]:
    last=t.scalar('select collect_ops.utc(max(dispatched_at)+interval \'30.1 seconds\')from collect_ops.receipt_worker_dispatches where request_id='+q(uncertain['request_id'])+';')
    remaining=max(0,(datetime.datetime.fromisoformat(last.replace('Z','+00:00'))-datetime.datetime.now(datetime.timezone.utc)).total_seconds())
    print('WAIT actual bounded original backoff',round(remaining,1),flush=True);m.time.sleep(remaining)
    wake=tick();case('bounded original redispatch attempt'+str(attempt)+' retains job quotas and immutable parameters',wake['status']=='redispatched'and wake['request_id']==uncertain['request_id']and wake['attempt']==attempt)
   case('three dispatches exhaust retry allowance without another network wake',tick()['status']=='pending'and t.scalar('select count(*)=3 from collect_ops.receipt_worker_dispatches where request_id='+q(uncertain['request_id'])+';')=='t')
   remaining=max(0,(datetime.datetime.fromisoformat(uncertain['expires_at'])-datetime.datetime.now(datetime.timezone.utc)).total_seconds()+.1);print('WAIT actual original expiry',round(remaining,1),flush=True);m.time.sleep(remaining)
   unknown_health=call('public.admin_get_receipt_exception_worker_health_v1()');save(report/'observed-worker-unknown-health.json',unknown_health);case('expired original without fresh reconciliation remains explicitly unknown',unknown_health['state']=='unknown'and'ORIGINAL_OUTCOME_UNKNOWN'in unknown_health['alerts'])
   wake=tick();case('expired missing original is durably fenced and cannot bypass reserved daily quotas',wake=={'status':'quota_exhausted'}and t.scalar('select count(*)=1 from collect_ops.receipt_worker_expirations where request_id='+q(uncertain['request_id'])+';')=='t')
   error(worker_expr(uncertain),'55000','delayed expired worker cannot arrive after conclusive absence proof',True)
   no_original=call('public.get_receipt_exception_worker_request_v1('+q(uncertain['request_id'])+')',True);save(report/'observed-worker-expired-lookup.json',no_original)
   case('fresh expired lookup remains missing with exact retained original deadline',no_original['status']=='not_recorded'and no_original['expires_at']is not None and no_original['receipt']is None)
   quota_health=call('public.admin_get_receipt_exception_worker_health_v1()');save(report/'observed-worker-quota-health.json',quota_health)
   case('conclusively fenced expiry is known unhandled with budget alert and no false unknown',set(['ORIGINAL_EXPIRED_UNHANDLED','WORKER_QUOTA_EXHAUSTED']).issubset(quota_health['alerts'])and'ORIGINAL_OUTCOME_UNKNOWN'not in quota_health['alerts']and quota_health['state']=='expired_without_receipt')
   for table in ['receipt_worker_configuration_history','receipt_worker_jobs','receipt_worker_dispatches','receipt_worker_receipts','receipt_worker_expirations']:
    mutation=t.sql('delete from collect_ops.'+table+';',check=False);case(table+' originals cannot be deleted',mutation.returncode!=0 and'55000'in mutation.stderr)
   error('public.get_receipt_exception_worker_request_v1('+q(job['request_id'])+')','42501','owner cannot read trusted original service lookup')
   case('canonical finance unchanged and no transport send or attempt',financial()==before and t.scalar('select not exists(select 1 from collect_hybrid.sms_notification_attempts);')=='t')
   configure_worker(False);case('proof ends with worker configuration and scheduled job disabled',tick()=={'status':'inactive'}and t.scalar("select not active from cron.job where jobname='collect-receipt-exceptions';")=='t')
   save(report/'final-worker-projection.json',t.json("select jsonb_build_object('configuration',(select to_jsonb(c)-'singleton'from collect_ops.receipt_worker_configuration c),'jobs',(select count(*)from collect_ops.receipt_worker_jobs),'receipts',(select count(*)from collect_ops.receipt_worker_receipts),'dispatches',(select count(*)from collect_ops.receipt_worker_dispatches));"))
  result['status']='pass'
 except BaseException as error:result['status']='failed';result['error']=str(error);raise
 finally:
  result['sources_unchanged']=all(p.read_bytes()==b for p,b in bodies.items());result['runner_unchanged']=pathlib.Path(__file__).read_bytes()==runner;result['support_unchanged']=pathlib.Path(authority.__file__).read_bytes()==support;result['finished_at']=now();save(report/'result.json',result)
if __name__=='__main__':main()
