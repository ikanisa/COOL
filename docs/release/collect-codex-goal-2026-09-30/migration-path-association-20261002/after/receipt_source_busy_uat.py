#!/usr/bin/env python3
"""Actual bounded source-lock, durable deferral and recovery proof; no shared DB."""
import argparse,base64,concurrent.futures,datetime,hashlib,json,pathlib,sys,threading,time,types,uuid
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
STAGE=pathlib.Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
uid=lambda:str(uuid.uuid4())
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
FEATURES=['20261001110000_receipt_operational_authority.sql','20261001120000_operational_exception_lifecycle.sql','20261001130000_android_dispatch_authority.sql','20261001140000_receipt_deferral_exceptions.sql','20261001150000_receipt_exception_worker.sql','20261001210000_receipt_worker_bounded_sweep.sql','20261001220000_governed_settings_requests.sql','20261002010000_sms_receipt_language_selection.sql']
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',type=pathlib.Path,required=True);a=ap.parse_args()
 report=a.report_dir.resolve();assert not report.exists();report.mkdir();inputs=report/'inputs';inputs.mkdir();(inputs/'migrations').mkdir();commands=report/'commands';commands.mkdir()
 bindings={};source_bytes={}
 def capture(p,dest):
  b=p.read_bytes();source_bytes[str(p)]=b;bindings[str(p)]=sha(b);dest.write_bytes(b);return b
 helper=capture(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py',inputs/'executed-helper.py')
 runner=capture(pathlib.Path(__file__),inputs/'executed-runner.py')
 baseline=capture(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql',inputs/'row-free-platform.sql')
 marker=capture(SOURCE/'.collect-release-candidate.json',inputs/'source08-marker.json');manifest=json.loads(marker)
 items=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=capture(p,inputs/'migrations'/p.name);rel=str(p.relative_to(SOURCE));assert b==(ROOT/rel).read_bytes()and sha(b)==manifest['source_files'][rel]['sha256'];source_bytes[str(ROOT/rel)]=b;bindings[str(ROOT/rel)]=sha(b)
  version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=rel,sha256=sha(b),body=b.decode()))
 assert len(items)==177
 features=[(name,capture(ROOT/'supabase/migrations'/name,inputs/name))for name in FEATURES]
 migration=ROOT/'supabase/migrations/20261002020000_receipt_source_busy_deferral.sql'
 if not migration.exists():migration=ROOT/'.cache/receipt-source-busy-20261001/supabase/migrations'/migration.name
 sql=capture(migration,inputs/migration.name)
 runtime=pathlib.Path(sys.executable).resolve();capture(runtime,inputs/'python-runtime')
 result=dict(status='running',scope='177 unchanged source08 prerequisite migrations plus exact110/120/130/140/150/210/220/250 and staged260; focused synthetic SQL contention and durable recovery, not full candidate or hosted Auth/device/carrier',started_at=now(),checks=[],target={},source_bindings=bindings,migration_sha256=sha(sql),hosted_written=False,sms_sent=False,device_used=False)
 save(report/'execution-binding.json',result)
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 original_command=m.command;counter=0;command_lock=threading.Lock()
 def recorded(args,text=None,check=True,timeout=120):
  nonlocal counter
  with command_lock:counter+=1;index=counter
  prefix=commands/f'{index:05d}';start=now();r=original_command(args,text,False,timeout)
  prefix.with_suffix('.stdout').write_text(r.stdout);prefix.with_suffix('.stderr').write_text(r.stderr)
  save(prefix.with_suffix('.json'),dict(argv=[x if not x.startswith('POSTGRES_PASSWORD=')else'POSTGRES_PASSWORD=<generated-local-fixture>'for x in args],input_sha256=sha(text.encode())if text is not None else None,started_at=start,finished_at=now(),exit_code=r.returncode,stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode())))
  if check and r.returncode:raise RuntimeError('recorded command failed: '+r.stderr[-3500:])
  return r
 m.command=recorded
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'source_busy',result['target'])as t:
   save(report/'target-handle.json',result['target']);platform,provenance=m.platform_shape();save(report/'platform-provenance.json',provenance);t.sql(platform,label='captured row-free platform');m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   t.sql("begin;update auth.users set email='busy-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'busy-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic source contention operator');commit;")
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
   svc="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expr,service=False):return t.json('begin;'+(svc if service else auth)+'select '+expr+';commit;')
   for name,b in features:t.sql(b.decode(),label='exact affected prerequisite '+name)
   finance_tables=[('public','payments'),('public','payment_provider_confirmations'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_receipt_policy','content_evidence')]
   cols=m.columns(t,finance_tables);before=m.fingerprints(t,cols)
   attrs=lambda:t.json("select jsonb_agg(jsonb_build_object('oid',oid,'owner',proowner,'acl',proacl,'config',proconfig,'args',proargtypes::text,'result',prorettype,'volatile',provolatile,'definer',prosecdef)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_receipt_operations'::regnamespace,'collect_ops'::regnamespace);")
   oldattrs=attrs();flags=t.json('select jsonb_agg(to_jsonb(x)order by key)from public.feature_flags x;');policy=t.json('select to_jsonb(p)from collect_receipt_operations.policy p;');cron=t.json('select coalesce(jsonb_agg(to_jsonb(x)order by jobid),\'[]\')from cron.job x;')
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='demote installer before260 DDL')
   case('260 installer is actual ordinary NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t')
   for signature in ['collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)','collect_ops.receipt_exception_source(text,uuid)']:
    definition=t.scalar('select pg_get_functiondef('+q(signature)+'::regprocedure);') if False else t.json('select to_jsonb(pg_get_functiondef('+q(signature)+'::regprocedure));')
    drift=definition.replace('$function$','$function$-- unexpected predecessor\n',1);assert drift!=definition
    refused=t.sql('begin;'+drift+';'+sql.decode(),check=False,label='atomic exact predecessor drift '+signature)
    case('atomic predecessor drift refuses '+signature,refused.returncode!=0 and 'receipt_source_busy_predecessor_drift'in refused.stderr and attrs()==oldattrs)
   refused=t.sql("begin;alter table collect_ops.exceptions drop constraint exceptions_reason_code_check;alter table collect_ops.exceptions add constraint exceptions_reason_code_check check(reason_code<>'unsupported');"+sql.decode(),check=False,label='atomic reason CHECK drift')
   case('atomic reason CHECK drift refuses before publishing260',refused.returncode!=0 and 'receipt_source_busy_constraint_drift'in refused.stderr and attrs()==oldattrs)
   t.sql(sql.decode(),label='exact260 ordinary-owner migration')
   case('260 preserves all existing function OID owner ACL signature and security configuration',attrs()==oldattrs)
   case('260 install preserves finance receipts flags authority policy and cron',m.fingerprints(t,cols)==before and t.json('select jsonb_agg(to_jsonb(x)order by key)from public.feature_flags x;')==flags and t.json('select to_jsonb(p)from collect_receipt_operations.policy p;')==policy and t.json('select coalesce(jsonb_agg(to_jsonb(x)order by jobid),\'[]\')from cron.job x;')==cron)
   for role in ['anon','authenticated','service_role']:
    case(role+' still denied direct private ensure and exception-source execution',t.scalar("select not has_function_privilege("+q(role)+",'collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)','EXECUTE')and not has_function_privilege("+q(role)+",'collect_ops.receipt_exception_source(text,uuid)','EXECUTE');")=='t')
   # Enroll real SQL-controlled synthetic principals. No real key is signed.
   pref='3059301306072a8648ce3d020106082a8648ce3d03010703420004';points=['6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5','7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1']
   def key(n):b=bytes.fromhex(pref+points[n]);return base64.b64encode(b).decode(),sha(b)
   pub,kh=key(0);principal=call('public.admin_enroll_receipt_operations_identity_v2('+','.join([q(uid()),q(pub),q(kh),"clock_timestamp()+interval '1 day'"])+')')['principal_id']
   def expression(action,payload,request=None):
    req=request or uid();return 'public.receipt_operations_execute_v2('+','.join([q(principal),q(req),q(kh),q(sha(json.dumps([req,action,payload]).encode())),'clock_timestamp()',q(action),q(json.dumps(payload))+'::jsonb'])+')'
   def operation(action,payload={},request=None):return call(expression(action,payload,request),True)
   operation('prove_key');call('public.admin_activate_receipt_operations_identity_v2('+','.join(map(q,[principal,uid(),kh]))+')')
   pub,gkh=key(1);device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[uid(),uid(),pub,gkh,'c'*64]))+')')['device_id'];hp=dict(sms_permission=True,network='validated',telephony='ready',sim_selected=True,sim_revision_sha256='d'*64,local_pause=False,reported_at=now())
   call('public.gateway_heartbeat_v1('+','.join(map(q,[device,uid(),sha(json.dumps(hp).encode())]))+','+q(json.dumps(hp))+'::jsonb)',True);call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
   caps={k:10 if k=='run_actions'else 20 if k=='run_sms_segments'else 100 for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   call('public.admin_configure_receipt_operations_v2('+','.join([q(uid()),'1',"'Live-limited'",'false',"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(caps))+'::jsonb','true','24',"'Synthetic source-contention recovery only'","clock_timestamp()+interval '100 seconds'"])+')')
   trigger=t.scalar("select tgname from pg_trigger where tgrelid='collect_hybrid.momo_balance_snapshots'::regclass and tgfoid='collect_hybrid.enqueue_sms_receipt_from_snapshot()'::regprocedure and not tgisinternal;");trigger_identifier='"'+trigger.replace('"','""')+'"'
   def post(n,missed=True,member=m.MEMBER):
    pid,raw,event=uid(),uid(),uid();ref='SOURCE-BUSY-'+str(n);wallet=sha(b'+250788971001')
    if missed:t.sql('alter table collect_hybrid.momo_balance_snapshots disable trigger '+trigger_identifier+';',label='installer-only missed normal enqueue fixture')
    try:
     t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic source contention observation'","encode(extensions.digest('Synthetic source contention observation','sha256'),'hex')",q(wallet),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wallet),'100',q(ref),"'unallocated'","'Synthetic busy payer'"])+');insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values('+','.join([q(pid),q(event),q(m.GROUP),q(member),q(m.UID),q(wallet),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-'+ref),q(wallet),'100','clock_timestamp()',"repeat('c',64)"])+');commit;',label='actual trusted synthetic financial posting '+str(n))
    finally:
     if missed:t.sql('alter table collect_hybrid.momo_balance_snapshots enable trigger '+trigger_identifier+';')
    s=t.scalar('select id from collect_hybrid.momo_balance_snapshots where payment_id='+q(pid)+"and event_type='receipt';");e=t.json('select to_jsonb(e)from collect_hybrid.receipt_business_events e where payment_id='+q(pid)+"and event_kind='payment_posted';")
    return pid,s,e
   pid,snapshot,event=post(1);existing_pid,existing_snapshot,existing_event=post(2,False)
   run=operation('begin_run');fence=dict(run_id=run['run_id'],fence_version=run['fence_version']);payload=dict(**fence,event_id=event['id'],expected_source_version=event['source_version']);req=uid()
   actor,sid=uid(),uid();t.sql("insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)values("+q(actor)+",'authenticated','authenticated','250788978201',clock_timestamp(),'{}','{}');update public.feature_flags set enabled=true where key='hybrid_verified_account_claim';")
   claim_auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=actor,session_id=sid,role='authenticated',aal='aal1')))+",true);"
   def await_state(app,condition):
    for _ in range(120):
     if t.scalar("select exists(select 1 from pg_stat_activity where application_name="+q(app)+'and '+condition+');')=='t':return True
     time.sleep(.01)
    return False
   with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
    ensuring=pool.submit(t.sql,"begin;set local application_name='source-busy-real-ensure';select 1 from public.payments where id="+q(pid)+"for update;select pg_sleep(3);"+svc+'select '+expression('ensure_receipt',payload,req)+';commit;',label='actual ensure caller owns payment before account claim')
    case('actual ensure transaction observed holding payment',await_state('source-busy-real-ensure',"wait_event='PgSleep'"))
    claiming=pool.submit(t.sql,"begin;set local application_name='source-busy-real-claim';"+claim_auth+'select public.claim_verified_current_account();commit;',label='actual authenticated account claim holds member then waits payment')
    case('actual account claim observed waiting on owned payment',await_state('source-busy-real-claim',"wait_event_type='Lock'"))
    er=ensuring.result(timeout=20);cr=claiming.result(timeout=20)
   busy=json.loads(er.stdout.strip().splitlines()[-1]);save(report/'observed-busy-ensure.json',busy);save(report/'observed-claim-ensure.json',dict(ensure=dict(exit_code=er.returncode,stdout=er.stdout,stderr=er.stderr),claim=dict(exit_code=cr.returncode,stdout=cr.stdout,stderr=cr.stderr)))
   case('actual claim and ensure both commit without inverse-order deadlock',er.returncode==0 and cr.returncode==0 and 'claimed'in cr.stdout)
   case('actual ensure returns closed false SOURCE_BUSY without receipt or business ACK',busy['code']=='SOURCE_BUSY'and not busy['ok']and not busy['business_handled']and busy['receipt_id']is None)
   case('busy event is durably deferred but not handled and no receipt/proof exists',t.scalar('select exists(select 1 from collect_receipt_operations.run_events where run_id='+q(run['run_id'])+'and event_id='+q(event['id'])+"and code='SOURCE_BUSY'and not business_handled)and exists(select 1 from collect_receipt_operations.event_deferrals where event_id="+q(event['id'])+"and code='SOURCE_BUSY')and not exists(select 1 from collect_receipt_operations.handled_events where event_id="+q(event['id'])+')and not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='+q(pid)+');')=='t')
   # Existing receipt work in the same partial batch remains independently ACKed.
   partial=operation('ensure_receipt',dict(**fence,event_id=existing_event['id'],expected_source_version=existing_event['source_version']))
   case('partial batch independently handles existing receipt after busy item',partial['code']=='RECEIPT_EXISTS'and partial['business_handled'])
   close=operation('complete_run',fence);save(report/'observed-partial-run-completion.json',close)
   case('partial completion reports deferred work rather than falsely completed business',close['handled_count']==1 and close['deferred_count']==1 and not close['business_handled'])
   replay=operation('reconcile_request',dict(target_request_id=req));save(report/'observed-reconciled-busy-request.json',replay)
   case('new caller recovers original durable SOURCE_BUSY request exactly without blind retry',replay['status']=='recorded'and replay['receipt']==busy)
   claimed_pid,claimed_event=pid,event
   claimed=t.json('select collect_receipt_operations.ensure_snapshot('+q(snapshot)+',true,true);')
   case('completed account claim preserves assisted-SMS recipient refusal',claimed['code']=='RECIPIENT_INELIGIBLE'and not claimed['business_handled']and t.scalar('select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='+q(claimed_pid)+');')=='t')
   source_member=uid()
   t.sql('begin;insert into collect_hybrid.member_records(id,collect_id,origin,created_by)values('+q(source_member)+",'978202','admin_assisted',"+q(m.UID)+');insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)values('+q(source_member)+",'Synthetic unclaimed recovery member','SYNTHETIC RECOVERY MEMBER','+250788978202');insert into public.collection_members(collection_id,member_record_id,role,status)values("+q(m.GROUP)+','+q(source_member)+",'member','active');insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by)values("+q(source_member)+",true,'written','Synthetic recovery consent',"+q(m.UID)+');commit;',label='independent unclaimed recovery member with explicit consent')
   pid,snapshot,event=post(3,member=source_member);run=operation('begin_run');fence=dict(run_id=run['run_id'],fence_version=run['fence_version'])
   with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
    holder=pool.submit(t.sql,"begin;set local application_name='source-busy-recoverable-member';select 1 from collect_hybrid.member_records where id="+q(source_member)+"for update;select pg_sleep(2);commit;",label='temporary unclaimed member contention')
    assert await_state('source-busy-recoverable-member',"wait_event='PgSleep'")
    deferred=operation('ensure_receipt',dict(**fence,event_id=event['id'],expected_source_version=event['source_version']));save(report/'observed-recoverable-busy-ensure.json',deferred)
    case('independent unclaimed event durably defers temporary contention',deferred['code']=='SOURCE_BUSY'and not deferred['business_handled'])
    holder.result(timeout=10)
   operation('complete_run',fence)
   # Every changed row-lock branch is bounded, including the existing outbox path.
   no_job=lambda:t.scalar('select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='+q(pid)+');')=='t'
   lock_targets=[('payment','public.payments','id='+q(pid)),('collection','public.collections','id='+q(m.GROUP)),('member','collect_hybrid.member_records','id='+q(source_member)),('membership','public.collection_members','collection_id='+q(m.GROUP)+'and member_record_id='+q(source_member)),('policy','collect_hybrid.sms_receipt_policies','collection_id='+q(m.GROUP)),('consent','collect_hybrid.sms_receipt_member_consents','member_record_id='+q(source_member)),('identity','collect_hybrid.member_momo_identities','member_id='+q(source_member)),('existing outbox','collect_hybrid.sms_notification_outbox','payment_id='+q(existing_pid))]
   for name,table,where in lock_targets:
    app='source-busy-lock-'+name.replace(' ','-')
    with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
     holder=pool.submit(t.sql,'begin;set local application_name='+q(app)+';select 1 from '+table+' where '+where+' for update;select pg_sleep('+('4'if name=='member'else'1.5')+');commit;',label='actual source row holder '+name)
     assert await_state(app,"wait_event='PgSleep'"),'source lock not observed '+name
     start=time.monotonic();r=t.json('select collect_receipt_operations.ensure_snapshot('+q(existing_snapshot if name=='existing outbox'else snapshot)+',true,true);');elapsed=time.monotonic()-start
     case(name+' contention returns bounded false SOURCE_BUSY before immutable writes',r==dict(ok=False,code='SOURCE_BUSY',business_handled=False,receipt_id=None)and elapsed<1 and no_job())
     if name=='member':
      scan_id=uid();expiry=t.scalar("select collect_ops.utc(clock_timestamp()+interval '100 seconds');");scan=call('public.process_receipt_deferral_exceptions_v1('+','.join([q(scan_id),'25',q(expiry)])+')',True);save(report/'observed-busy-exception-scan.json',scan)
      ex=t.scalar('select id from collect_ops.exceptions where source_kind=\'receipt_event\'and source_id='+q(event['id'])+"and reason_code='RECEIPT_OPERATION_SOURCE_BUSY';")
      detail=call('public.admin_get_receipt_deferral_exception_v1('+q(ex)+')');save(report/'observed-busy-admin-detail.json',detail)
      inbox=call("public.admin_list_operational_exceptions_v2(true,20,null,null,'receipt_event')");save(report/'observed-busy-admin-inbox.json',inbox)
      case('trusted scan records SOURCE_BUSY exception without unknown-deferral failure',scan['status']=='processed'and scan['refused']==0 and detail['current_code']=='SOURCE_BUSY'and detail['active']and not detail['business_handled'])
      case('original scanner request replays exactly without duplicate observations',call('public.process_receipt_deferral_exceptions_v1('+','.join([q(scan_id),'25',q(expiry)])+')',True)==scan)
     holder.result(timeout=10)
   t.sql('update collect_receipt_operations.event_deferrals set next_check_at=clock_timestamp()-interval \'1 second\'where event_id='+q(event['id'])+';',label='installer-only advance due deferral fixture; no production retry override')
   restarted=operation('begin_run');newfence=dict(run_id=restarted['run_id'],fence_version=restarted['fence_version']);listed=operation('list_events',dict(**newfence,limit=25));case('later run rediscovers durably unhandled busy event after due time',any(e['event_id']==event['id']for e in listed['events']))
   recovered=operation('ensure_receipt',dict(**newfence,event_id=event['id'],expected_source_version=event['source_version']));save(report/'observed-recovered-ensure.json',recovered)
   case('later ensure derives and durably saves exactly one immutable receipt before ACK',recovered['code']=='RECEIPT_ENQUEUED'and recovered['business_handled']and t.scalar('select count(*)=1 from collect_hybrid.sms_notification_outbox o join collect_receipt_policy.content_evidence e on e.outbox_id=o.id where o.payment_id='+q(pid)+"and collect_receipt_policy.content_is_valid(o)and e.language='rw';")=='t'and t.scalar('select receipt_id='+q(recovered['receipt_id'])+'from collect_receipt_operations.handled_events where event_id='+q(event['id'])+';')=='t')
   repeated=operation('ensure_receipt',dict(**newfence,event_id=event['id'],expected_source_version=event['source_version']));case('repeated required work returns retained same receipt without duplication',repeated['receipt_id']==recovered['receipt_id']and repeated['business_handled']and t.scalar('select count(*)=1 from collect_hybrid.sms_notification_outbox where payment_id='+q(pid)+';')=='t')
   for _ in range(3):call('public.process_receipt_deferral_exceptions_v1('+q(uid())+",25,clock_timestamp()+interval '100 seconds')",True)
   case('recovery clears busy exception while retaining original immutable busy evidence',t.scalar('select not exists(select 1 from collect_ops.exceptions where source_id='+q(event['id'])+"and reason_code='RECEIPT_OPERATION_SOURCE_BUSY'and active)and exists(select 1 from collect_receipt_operations.run_events where run_id="+q(run['run_id'])+'and event_id='+q(event['id'])+"and code='SOURCE_BUSY'and not business_handled);")=='t')
   case('financial finality and balances survive contention and recovery',t.scalar('select status=\'posted\'and contributor_user_id='+q(actor)+'from public.payments where id='+q(claimed_pid)+';')=='t'and t.scalar('select count(*)=1 from collect_hybrid.momo_balance_snapshots where payment_id='+q(pid)+"and event_type='receipt';")=='t')
   result['status']='passed';result['finished_at']=now();save(report/'result.json',result)
 except BaseException as e:
  result['status']='failed';result['error']=type(e).__name__+': '+str(e);result['finished_at']=now();save(report/'result.json',result);raise
 finally:
  result['source_unchanged']=all(pathlib.Path(p).read_bytes()==b for p,b in source_bytes.items());result['command_receipts']=counter;save(report/'result.json',result)
  if not result['source_unchanged']:raise AssertionError('frozen SQL proof inputs changed')
if __name__=='__main__':main()
