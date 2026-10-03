#!/usr/bin/env python3
"""Operations authority proof in an owned network-none disposable PostgreSQL.

No hosted credentials, source rows, device or transport sends are accepted.
SQL service claims are installer trust-boundary fixtures, not real JWT/P256
verification. Real exact-byte signature verification is covered by Edge tests.
"""
import argparse,base64,concurrent.futures,datetime,hashlib,json,pathlib,types,uuid
ROOT=pathlib.Path(__file__).resolve().parents[2]
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
MIGRATION=ROOT/'supabase/migrations/20261001110000_receipt_operational_authority.sql'
def sha(value):return hashlib.sha256(value).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n')
def ident():return str(uuid.uuid4())
PREFIX='3059301306072a8648ce3d020106082a8648ce3d03010703420004'
POINTS=['6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
 '7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1']
def key(n):
 b=bytes.fromhex(PREFIX+POINTS[n]);return base64.b64encode(b).decode(),sha(b)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--report-dir',required=True);args=parser.parse_args();report=pathlib.Path(args.report_dir).resolve()
 assert not report.exists();report.mkdir(parents=True);inputs=report/'inputs';inputs.mkdir();(inputs/'migrations').mkdir()
 marker=(SOURCE/'.collect-release-candidate.json').read_bytes();manifest=json.loads(marker);save(inputs/'source08-marker.json',manifest)
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();(inputs/'executed-helper.py').write_bytes(helper)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner)
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();(inputs/'row-free-platform.sql').write_bytes(baseline)
 sql=MIGRATION.read_bytes();(inputs/MIGRATION.name).write_bytes(sql);items=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=p.read_bytes();rel=str(p.relative_to(SOURCE));assert sha(b)==manifest['source_files'][rel]['sha256'];(inputs/'migrations'/p.name).write_bytes(b)
  version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=rel,sha256=sha(b),body=b.decode()))
 assert len(items)==177
 result=dict(scope='focused operations feature on exact source08 177 prerequisites; local cached PG17.6 only',started_at=now(),source08_manifest_sha256=sha(marker),migration_sha256=sha(sql),helper_sha256=sha(helper),runner_sha256=sha(runner),baseline_sha256=sha(baseline),checks=[],target={},hosted_written=False,device_used=False,sms_sent=False,signature_verified_in_sql=False)
 save(report/'execution-binding.json',{k:v for k,v in result.items()if k not in('checks','target')})
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 def case(name,ok=True):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'operations',result['target'])as t:
   platform,_=m.platform_shape();t.sql(platform,label='captured row-free platform shape');m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
   service="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expression,as_service=False):
    r=t.sql('begin;'+(service if as_service else auth)+'select '+expression+';commit;');return json.loads(r.stdout.strip().splitlines()[-1])
   def error(expression,code,label,as_service=False):
    r=t.sql('begin;'+(service if as_service else auth)+'select '+expression+';rollback;',check=False);case(label,r.returncode!=0 and code in r.stderr)
   t.sql("begin;update auth.users set email='operations-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'operations-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic current email operations owner');commit;")
   preserved=[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','sms_notification_outbox')]
   cols=m.columns(t,preserved);before=m.fingerprints(t,cols);t.sql(sql.decode(),label='new additive operations authority migration');case('install preserves canonical finance and immutable prior receipts',m.fingerprints(t,cols)==before)
   default=call('public.admin_get_receipt_operations_policy_v2()');save(report/'observed-policy-default.json',default);case('default is Paused emergency stopped with no identities devices or scopes',default['mode']=='Paused'and default['emergency_stop']and not default['principal_ids']and not default['device_ids'])
   for role in ['anon','authenticated','service_role']:
    case(role+' cannot read mutate or execute private operations tables/helpers',t.scalar("select not has_schema_privilege("+q(role)+",'collect_receipt_operations','USAGE')and not exists(select 1 from pg_class c where c.relnamespace='collect_receipt_operations'::regnamespace and(c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE'))))and not exists(select 1 from pg_proc f where f.pronamespace='collect_receipt_operations'::regnamespace and has_function_privilege("+q(role)+",f.oid,'EXECUTE')); ")=='t')
   case('execute API grants only service role',t.scalar("select has_function_privilege('service_role','public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)','EXECUTE')and not has_function_privilege('authenticated','public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)','EXECUTE')and not has_function_privilege('anon','public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)','EXECUTE');")=='t')
   pub,kh=key(0);enroll_request=ident();enroll_expr='public.admin_enroll_receipt_operations_identity_v2('+','.join([q(enroll_request),q(pub),q(kh),"clock_timestamp()+interval '1 day'"])+')'
   enrolled=call(enroll_expr);principal=enrolled['principal_id'];case('new separate machine scope enrolls pending without financial or send authority',enrolled['scope']=='rw_receipt_operations'and enrolled['state_at_action']=='pending')
   def expr(action,payload=None,request=None,digest=None,issued='clock_timestamp()',pid=principal,key_hash=kh):
    req=request or ident();body=payload or{};digest=digest or sha(json.dumps([action,req,body]).encode());return 'public.receipt_operations_execute_v2('+','.join([q(pid),q(req),q(key_hash),q(digest),issued,q(action),q(json.dumps(body))+'::jsonb'])+')'
   def execute(action,payload=None,request=None,**kwargs):return call(expr(action,payload,request,**kwargs),True)
   error(expr('begin_run'),'42501','pending operations identity cannot start a run',True)
   proof=execute('prove_key');case('pending key proof records only no-send no-financial observation',proof['business_handled']is False and proof['send_action']is False)
   activated=call('public.admin_activate_receipt_operations_identity_v2('+','.join(map(q,[principal,ident(),kh]))+')');case('fresh proof owner activation works for operations identity',activated['state_at_action']=='active')
   refused=execute('begin_run');case('default pause produces retained explicit refusal with no run',refused['code']=='OPERATIONS_PAUSED'and refused['run_id']is None)
   error('public.receipt_supervisor_observe_v1('+','.join([q(principal),q(ident()),q(kh),q('b'*64),'clock_timestamp()',"'shadow_health'"])+')','42501','operations identity cannot use v1 Shadow authority',True)
   error(expr('prove_key',issued="clock_timestamp()-interval '31 seconds'"),'42501','expired signed request fails after database recheck',True)
   error(expr('prove_key',key_hash='f'*64),'42501','wrong current key fails',True)
   # Real enrollment/health/activation APIs with synthetic public curve key;
   # no private signer, hardware, carrier or callback is involved in this DB.
   gpub,gkh=key(1);device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[ident(),ident(),gpub,gkh,'c'*64]))+')')['device_id']
   hp={'sms_permission':True,'network':'validated','telephony':'ready','sim_selected':True,'sim_revision_sha256':'d'*64,'local_pause':True,'reported_at':now().replace('+00:00','Z')}
   call('public.gateway_heartbeat_v1('+','.join(map(q,[device,ident(),'e'*64]))+','+q(json.dumps(hp))+'::jsonb)',True)
   call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,ident(),gkh,'c'*64]))+')');case('configuration tests use actual active enrollment fixture not fabricated dispatch authority',t.scalar('select state=\'active\'from collect_gateway.devices where id='+q(device)+';')=='t')
   caps={k:(10 if k=='run_actions'else 20 if k=='run_sms_segments'else 100)for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   def configure(mode='Live-limited',stop=False,catchup=True,custom=None,request=None,revision=None):
    rev=revision or t.scalar('select revision from collect_receipt_operations.policy;');c=custom or caps
    return call('public.admin_configure_receipt_operations_v2('+','.join([q(request or ident()),str(rev),q(mode),str(stop).lower(),"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(c))+'::jsonb',str(catchup).lower(),'24',"'Synthetic offline governed operations policy'"])+')')
   configure('Shadow');run=execute('begin_run');case('Shadow starts fixed120second fenced lease',run['ok']and run['mode']=='Shadow'and (datetime.datetime.fromisoformat(run['expires_at'].replace('Z','+00:00'))-datetime.datetime.fromisoformat(run['observed_at'].replace('Z','+00:00'))).total_seconds()==120)
   req=ident();listing=execute('list_events',{'run_id':run['run_id'],'fence_version':run['fence_version'],'limit':2},req);save(report/'observed-shadow-list.json',listing)
   case('event page is bounded canonical source evidence without content or contact',len(listing['events'])<=2 and all(set(e)=={'event_id','source_version','event_kind','payment_id','collection_id','source_state'}for e in listing['events']))
   case('overlap refuses rather than starting another runner',execute('begin_run')['code']=='RUN_BUSY')
   def args(r):return {'run_id':r['run_id'],'fence_version':r['fence_version']}
   events=listing['events'];event=events[0];item={**args(run),'event_id':event['event_id'],'expected_source_version':event['source_version']}
   shadow=execute('ensure_receipt',item);case('Shadow observation creates no handled ACK receipt or quota reservation',shadow['code']=='SHADOW_OBSERVED'and not shadow['business_handled']and t.scalar('select count(*)=0 from collect_receipt_operations.handled_events;')=='t')
   complete=execute('complete_run',args(run));case('Shadow completion never claims business handled',complete['business_handled']is False)
   error(expr('list_events',{**args(run),'limit':1}),'55000','completed lease is fenced for new work',True)
   configure('Dry-run');dry=execute('begin_run');dry_result=execute('ensure_receipt',{**args(dry),'event_id':event['event_id'],'expected_source_version':event['source_version']});case('Dry-run inspects actual policy and creates no primary or business ACK',not dry_result['business_handled']and t.scalar('select count(*)=0 from collect_receipt_operations.handled_events;')=='t');execute('complete_run',args(dry))
   configure();live=execute('begin_run');case('Live-limited has explicit active device and policy bound run',live['mode']=='Live-limited'and live['ok'])
   # New canonical posted payment automatically creates an immutable v2 job
   # while SMS flag remains off. Real ensure ACK proves durable existing work.
   def post(n):
    pid='99910000-0000-4000-8000-%012d'%(100000+n);ref='OPERATIONS-'+str(n);wh=sha(b'+250788971001')
    t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);insert into public.payments(id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values("+','.join([q(pid),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-OPERATIONS-'+str(n)),q(wh),'100','clock_timestamp()',"repeat('c',64)"])+');commit;',label='synthetic canonical operations payment '+str(n));return pid
   pid=post(1);job=t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='+q(pid)+';');new_event=t.json("select to_jsonb(e)from collect_hybrid.receipt_business_events e where source_kind='payment'and source_id="+q(pid)+'order by source_version desc limit 1;')
   live_item={**args(live),'event_id':new_event['id'],'expected_source_version':new_event['source_version']};request=ident();digest=sha(json.dumps(['ensure_receipt',request,live_item]).encode());handled=execute('ensure_receipt',live_item,request,digest=digest);save(report/'observed-live-ensure.json',handled)
   case('live ensure atomically commits real per-event handled proof to existing v2 receipt',handled['code']=='RECEIPT_EXISTS'and handled['receipt_id']==job['id']and handled['business_handled']and t.scalar('select count(*)=1 from collect_receipt_operations.handled_events where event_id='+q(new_event['id'])+';')=='t')
   repeated=execute('ensure_receipt',live_item,request,digest=digest);case('identical current request replay returns original immutable result without new quota',repeated==handled and t.scalar('select count(*)=1 from collect_receipt_operations.reservations where id='+q(request)+';')=='t')
   case('new request for same event in same run retains handling and avoids action repeat',execute('ensure_receipt',live_item)['receipt_id']==job['id']and t.scalar('select count(*)=1 from collect_receipt_operations.reservations where run_id='+q(live['run_id'])+';')=='t')
   lookup=execute('reconcile_request',{'target_request_id':request});case('original request read reconciliation retains actual committed result',lookup['status']=='recorded'and lookup['receipt']==handled)
   error(expr('ensure_receipt',{**live_item,'expected_source_version':new_event['source_version']+1},request,digest='f'*64),'22023','same request UUID with altered exact bytes fails',True)
   error(expr('ensure_receipt',{**live_item,'event_id':ident()}),'42501','unknown or out-of-scope event fails',True)
   error(expr('ensure_receipt',{**live_item,'destination':'+250788000000'}),'22023','caller supplied recipient is rejected',True)
   error(expr('list_events',{**args(live),'fence_version':live['fence_version']+1,'limit':1}),'55000','stale run fence cannot read or mutate event work',True)
   # Bound missed receipt from predecessor paused posting: immutable recorded
   # consent/contact predate the retained original balance snapshot.
   missing='99780000-0000-4000-8000-000000050003';count_before=t.scalar('select count(*)from collect_hybrid.sms_notification_outbox;');backlog=execute('reconcile_backlog',{**args(live),'limit':1});save(report/'observed-backlog.json',backlog)
   case('bounded missed receipt creates safe dated v2 using original financial snapshot',backlog['examined']==1 and backlog['handled']==1 and t.scalar('select template_version=2 and state=\'queued\'from collect_hybrid.sms_notification_outbox where payment_id='+q(missing)+';')=='t')
   case('reconciliation never creates more than one lifetime primary',execute('reconcile_backlog',{**args(live),'limit':25})['examined']==0 and int(t.scalar('select count(*)from collect_hybrid.sms_notification_outbox;'))==int(count_before)+1)
   case('queue persists while SMS off and no attempt starts',t.scalar("select not enabled and not exists(select 1 from collect_hybrid.sms_notification_attempts)from public.feature_flags where key='hybrid_sms_notifications';")=='t')
   # Real page assignment is durably recorded: unhandled assigned work prevents
   # completed telemetry being presented as a processed business batch.
   execute('list_events',{**args(live),'limit':25});comp=execute('complete_run',args(live));save(report/'observed-completion-partial.json',comp)
   case('partial completion derives action counters and refuses business-complete claim',comp['action_count']==2 and comp['sms_segments']==0 and comp['deferred_count']>0 and comp['business_handled']is False)
   configure(custom={**caps,'run_actions':1});limit_run=execute('begin_run');p2=post(2);p3=post(3)
   es=[t.json("select to_jsonb(e)from collect_hybrid.receipt_business_events e where source_kind='payment'and source_id="+q(pn)+'order by source_version desc limit 1;')for pn in[p2,p3]]
   def concurrent_ensure(e):return execute('ensure_receipt',{**args(limit_run),'event_id':e['id'],'expected_source_version':e['source_version']})
   with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:outcomes=list(pool.map(concurrent_ensure,es))
   case('overlapping ensure requests atomically respect run action cap',sorted(x['code']for x in outcomes)==['QUOTA_EXHAUSTED','RECEIPT_EXISTS']and t.scalar('select sum(actions)=1 from collect_receipt_operations.reservations where run_id='+q(limit_run['run_id'])+';')=='t')
   stop=configure('Paused',True);error(expr('list_events',{**args(limit_run),'limit':1}),'55000','emergency stop and policy revision fence old run immediately',True)
   case('paused ingestion remains independent from operations stop',t.scalar("select status='posted'and exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id=p.id)from public.payments p where id="+q(post(4))+';')=='t')
   configure('Live');open_run=execute('begin_run');case('full Live mode implemented under explicit caps and allowlist',open_run['ok']and open_run['mode']=='Live')
   t.sql('update collect_receipt_operations.runs set started_at=started_at-interval \'3 minutes\',expires_at=expires_at-interval \'3 minutes\'where id='+q(open_run['run_id'])+';')
   error(expr('list_events',{**args(open_run),'limit':1}),'55000','expired run cannot receive action authority',True)
   case('new run after expiry obtains greater fence without restarting old UUID',execute('begin_run')['fence_version']>open_run['fence_version'])
   for table in ['requests','handled_events','reservations','run_events']:
    r=t.sql('delete from collect_receipt_operations.'+table+';',check=False);case('immutable '+table+' cannot be deleted',r.returncode!=0 and'55000'in r.stderr)
   case('canonical journals stay balanced independent of operations',t.scalar("select bool_and(n=2 and debit=credit)from(select journal_entry_id,count(*)n,sum(amount_rwf)filter(where direction='debit')debit,sum(amount_rwf)filter(where direction='credit')credit from collect_hybrid.momo_journal_lines group by journal_entry_id)x;")=='t')
   save(report/'final-operations-projection.json',t.json("select jsonb_build_object('runs',(select jsonb_agg(to_jsonb(r))from collect_receipt_operations.runs r),'handled',(select jsonb_agg(to_jsonb(h))from collect_receipt_operations.handled_events h),'reservations',(select jsonb_agg(to_jsonb(q))from collect_receipt_operations.reservations q));"))
  result['status']='pass'
 except BaseException as e:result['status']='failed';result['error']=str(e);raise
 finally:result['source_migration_unchanged']=sha(MIGRATION.read_bytes())==result['migration_sha256'];result['runner_unchanged']=sha(pathlib.Path(__file__).read_bytes())==result['runner_sha256'];result['finished_at']=now();save(report/'result.json',result)
if __name__=='__main__':main()
