#!/usr/bin/env python3
"""Source-bound durable deferral UAT on an owned network-none PG17.6 target.

Uses exact177 frozen prerequisites plus sealed operations110000 and current
exception lifecycle120000; excludes automatic sender130000 deliberately.
SQL Auth/service claims are synthetic trust-boundary fixtures, not real JWTs.
"""
import argparse,concurrent.futures,datetime,hashlib,json,pathlib,types,uuid
import receipt_operational_authority_uat as authority
ROOT=authority.ROOT;SOURCE=authority.SOURCE
MIGRATIONS=[ROOT/'supabase/migrations/20261001110000_receipt_operational_authority.sql',ROOT/'supabase/migrations/20261001120000_operational_exception_lifecycle.sql',ROOT/'supabase/migrations/20261001140000_receipt_deferral_exceptions.sql']
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
 result=dict(status='running',scope='focused durable deferral feature; exact177 prerequisites+sealed110000+120000+140000; no130000 sender integration',started_at=now(),source08_manifest_sha256=sha(marker),migration_sha256={p.name:sha(b)for p,b in bodies.items()},runner_sha256=sha(runner),support_sha256=sha(support),helper_sha256=sha(helper),baseline_sha256=sha(baseline),checks=[],target={},hosted_written=False,device_used=False,sms_sent=False,jwt_verified=False)
 save(report/'execution-binding.json',{k:v for k,v in result.items()if k not in('checks','target')})
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 def case(name,ok=True):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'deferral',result['target'])as t:
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
   before=financial();old_refresh=t.scalar("select 'collect_ops.refresh_source(text,uuid)'::regprocedure::oid;");old_sms=t.scalar("select 'collect_ops.transaction_sms_id(text,uuid)'::regprocedure::oid;");t.sql(bodies[MIGRATIONS[2]].decode(),label='new additive140000 deferral exception migration')
   case('140000 preserves finance and old source function identities',financial()==before and t.scalar("select 'collect_ops.refresh_source(text,uuid)'::regprocedure::oid;")==old_refresh and t.scalar("select 'collect_ops.transaction_sms_id(text,uuid)'::regprocedure::oid;")==old_sms)
   case('installation invents no exception historical observation assignment or delivery',t.scalar("select not exists(select 1 from collect_ops.exceptions where source_kind in('receipt_event','receipt_backlog'))and not exists(select 1 from collect_ops.receipt_exception_work)and not exists(select 1 from collect_ops.exception_workflows);")=='t')
   for role in ['anon','authenticated','service_role']:
    case(role+' has no private derived receipt tables or helpers',t.scalar("select not has_schema_privilege("+q(role)+",'collect_ops','USAGE')and not exists(select 1 from pg_class c where c.relnamespace='collect_ops'::regnamespace and c.relname like 'receipt_exception_%'and c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE'))); ")=='t')
   def scan(limit=25,request=None,deadline=None):
    request=request or ident();deadline=deadline or t.scalar("select collect_ops.utc(clock_timestamp()+interval '100 seconds');");before=financial();observed=call('public.process_receipt_deferral_exceptions_v1('+','.join([q(request),str(limit),q(deadline)])+')',True);assert financial()==before;return observed
   def sweep(rounds=4):return[scan()for _ in range(rounds)]
   first=scan(1);save(report/'observed-scan-first.json',first);case('bounded fresh sweep discovers real pre-install deferral and records one exception',first['seeded']==1 and first['processed']==1 and first['activated']==1 and not first['source_scan_complete'])
   lookup=call('public.get_receipt_deferral_exception_scan_v1('+q(first['request_id'])+')',True);save(report/'observed-scan-lookup.json',lookup);case('lost scan response reconciles exact immutable original receipt',lookup['status']=='recorded'and lookup['receipt']==first and lookup['expires_at']==first['expires_at'])
   case('same unexpired original scan returns unchanged result without reprocessing',scan(1,first['request_id'],first['expires_at'])==first)
   error('public.process_receipt_deferral_exceptions_v1('+','.join([q(first['request_id']),'2',q(first['expires_at'])])+')','22023','same scan UUID cannot change limit or original bytes',True)
   error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'26',"clock_timestamp()+interval '100 seconds'"])+')','22023','fresh service scan is capped at25sources',True)
   error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'1',"clock_timestamp()-interval '1 second'"])+')','55000','expired service scan cannot produce durable progress',True)
   error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'1',"clock_timestamp()+interval '121 seconds'"])+')','22023','service scan cannot extend beyond120seconds',True)
   error('public.process_receipt_deferral_exceptions_v1('+','.join([q(ident()),'1',"clock_timestamp()+interval '100 seconds'"])+')','42501','email owner cannot invoke trusted service scanner')
   ex=lambda source,code:t.json("select to_jsonb(e)from collect_ops.exceptions e where source_kind='receipt_event'and source_id="+q(source)+"and reason_code='RECEIPT_OPERATION_"+code+"';")
   e2=event('payment',p2);item=ex(e2['id'],'QUOTA_EXHAUSTED');before_obs=t.scalar('select count(*)from collect_ops.exception_observations;');sweep();case('restart and duplicate cyclic scans preserve stable exception and observations',ex(e2['id'],'QUOTA_EXHAUSTED')['id']==item['id']and t.scalar('select count(*)from collect_ops.exception_observations;')==before_obs and int(t.scalar('select epoch from collect_ops.receipt_exception_progress;'))>=2)
   listing=call("public.admin_list_operational_exceptions_v2(true,20,null,null,'receipt_event')");save(report/'observed-event-inbox.json',listing);case('new source filter exposes actual transaction link with existing strict row keys',len(listing['rows'])==1 and listing['rows'][0]['transaction_sms_id']==raw2)
   detail=call('public.admin_get_receipt_deferral_exception_v1('+q(item['id'])+')');save(report/'observed-detail-deferred.json',detail)
   detail_keys={'contract_version','exception_id','source_kind','source_id','source_version','event_kind','reason_code','revision','active','disposition','original_code','current_code','business_handled','receipt_id','checked_at','sample_valid_until','financial_action','send_action'}
   case('deferred detail is exact redacted and never a business or send acknowledgement',set(detail)==detail_keys and detail['active']and detail['disposition']=='deferred'and detail['business_handled']is False and not detail['financial_action']and not detail['send_action'])
   workflow=call('public.admin_act_exception_workflow_v1('+','.join([q(ident()),q(item['id']),str(item['revision']),'0',"'assign'",q(m.UID),"clock_timestamp()+interval '10 minutes'","'review_started'","clock_timestamp()+interval '100 seconds'"])+')');case('real source-bound assignment works without automatic recipient invention',workflow['action']=='assign'and not workflow['send_action'])
   escalated=call('public.admin_act_exception_workflow_v1('+','.join([q(ident()),q(item['id']),str(item['revision']),str(workflow['workflow_revision']),"'escalate'",'null','null',"'owner_review_required'","clock_timestamp()+interval '100 seconds'"])+')');delivered=call('public.process_exception_escalations_v1(20)',True);case('existing escalation delivers new source into private Admin inbox only',delivered['delivered']==1 and not delivered['external_send'])
   case('escalation retry does not duplicate inbox delivery',call('public.process_exception_escalations_v1(20)',True)['delivered']==0 and t.scalar('select count(*)=1 from collect_ops.exception_inbox_deliveries;')=='t')
   configure(10);sweep();cleared=call('public.admin_get_receipt_deferral_exception_v1('+q(item['id'])+')');save(report/'observed-detail-source-cleared.json',cleared);case('current quota blocker clearing is truthful without fabricating handled event',not cleared['active']and cleared['disposition']=='current_blocker_cleared'and not cleared['business_handled']and t.scalar('select not exists(select 1 from collect_receipt_operations.handled_events where event_id='+q(e2['id'])+');')=='t')
   error('public.admin_act_exception_workflow_v1('+','.join([q(ident()),q(item['id']),str(item['revision']),str(escalated['workflow_revision']),"'escalate'",'null','null',"'owner_review_required'","clock_timestamp()+interval '100 seconds'"])+')','55000','stale escalation cannot act on cleared source revision')
   next_run=execute('begin_run');actual=ensure(next_run,e2);sweep();handled=call('public.admin_get_receipt_deferral_exception_v1('+q(item['id'])+')');save(report/'observed-detail-handled.json',handled);case('actual durable handling proof is distinguished from eligibility clearing',actual['business_handled']and handled['business_handled']and handled['disposition']=='durably_handled'and handled['receipt_id']==actual['receipt_id'])
   _,unallocated,_=post(3,confirm=False);old=event('allocation',unallocated);ensure(next_run,old);sweep();old_item=ex(old['id'],'SNAPSHOT_MISSING');case('real unallocated source has concrete snapshot deferral exception',old_item['active'])
   t.sql("update public.parsed_payment_events set allocation_status='needs_review'where id="+q(unallocated)+';');newer=event('allocation',unallocated);sweep();superseded=call('public.admin_get_receipt_deferral_exception_v1('+q(old_item['id'])+')');save(report/'observed-detail-superseded.json',superseded);case('committed newer source clears old blocker without false original handled proof',not superseded['active']and superseded['disposition']=='source_superseded'and not superseded['business_handled'])
   ensure(next_run,newer);sweep();new_item=ex(newer['id'],'SNAPSHOT_MISSING');case('new committed source revision gets independently deduplicated exception identity',new_item['active']and new_item['id']!=old_item['id']and newer['source_version']==old['source_version']+1)
   # Backlog action refuses quota, then a new capped run durably handles the
   # same original snapshot. No historical balance/contact is recomputed.
   configure(1);backrun=execute('begin_run');ensure(backrun,event('receipt',t.scalar('select id from collect_hybrid.sms_notification_outbox where payment_id='+q(p1)+';')));backlog=execute('reconcile_backlog',{**run_args(backrun),'limit':1});case('real missed snapshot refusal is retained by bounded backlog contract',backlog['deferred']==1)
   sweep();back_item=t.json("select to_jsonb(e)from collect_ops.exceptions e where source_kind='receipt_backlog'and active order by first_observed_at limit 1;");back_detail=call('public.admin_get_receipt_deferral_exception_v1('+q(back_item['id'])+')');save(report/'observed-detail-backlog-deferred.json',back_detail);case('backlog projection identifies actual immutable snapshot without invented version',back_detail['source_version']is None and back_detail['event_kind']is None and back_detail['current_code']=='QUOTA_EXHAUSTED'and not back_detail['business_handled'])
   configure(10);br=execute('begin_run');resolved=execute('reconcile_backlog',{**run_args(br),'limit':1});sweep();back_handled=call('public.admin_get_receipt_deferral_exception_v1('+q(back_item['id'])+')');save(report/'observed-detail-backlog-handled.json',back_handled);case('backlog resolution uses actual immutable successful original snapshot proof',resolved['handled']==1 and back_handled['business_handled']and not back_handled['active']and back_handled['disposition']=='durably_handled')
   # Unavailable trusted source work is retained as refusal, not an invented
   # exception or ACK. Installer-only corrupt-input fixture cannot be submitted
   # by service callers because direct/private grants are absent.
   unknown=ident();t.sql("insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_event',"+q(unknown)+",'sweep');");rejected=scan();case('unavailable source refusal advances other work without creating false exception',rejected['refused']==1 and t.scalar('select outcome=\'source_unavailable\'from collect_ops.receipt_exception_work where source_id='+q(unknown)+';')=='t'and t.scalar('select not exists(select 1 from collect_ops.exceptions where source_id='+q(unknown)+');')=='t')
   # Real overlap is reported as a recorded bounded no-op, with safe original
   # request lookup; no waiting worker renews a lease or advances the cursor.
   with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
    holder=pool.submit(t.sql,"begin;set local application_name='deferral-worker-overlap';select pg_advisory_xact_lock(hashtext('collect-receipt-exception-worker'));select pg_sleep(2);commit;")
    for _ in range(100):
     if t.scalar("select exists(select 1 from pg_stat_activity where application_name='deferral-worker-overlap'and wait_event='PgSleep');")== 't':break
     m.time.sleep(.01)
    else:raise AssertionError('worker overlap fixture unavailable')
    busy=scan();save(report/'observed-scan-busy.json',busy);case('overlapping worker produces immutable busy receipt without progress',busy['status']=='busy'and busy['processed']==0 and busy['seeded']==0);holder.result()
   blocked=ident();deadline=now().replace('+00:00','Z');revision=t.scalar('select last_request_id from collect_ops.receipt_exception_progress;')
   with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
    holder=pool.submit(t.sql,"begin;set local application_name='deferral-workflow-expiry';select pg_advisory_xact_lock(hashtext('collect-ops-workflow'));select pg_sleep(1);commit;")
    for _ in range(100):
     if t.scalar("select exists(select 1 from pg_stat_activity where application_name='deferral-workflow-expiry'and wait_event='PgSleep');")=='t':break
     m.time.sleep(.01)
    else:raise AssertionError('workflow expiry fixture unavailable')
    error('public.process_receipt_deferral_exceptions_v1('+','.join([q(blocked),'1',"clock_timestamp()+interval '0.05 seconds'"])+')','55P03','locked workflow deadline attempt refuses safely before partial progress',True);holder.result()
   missing=call('public.get_receipt_deferral_exception_scan_v1('+q(blocked)+')',True);case('failed scan after original deadline has missing proof and unchanged cursor',missing['status']=='not_recorded'and t.scalar('select last_request_id from collect_ops.receipt_exception_progress;')==revision)
   call('public.admin_revoke_receipt_supervisor_v1('+','.join(map(q,[principal,ident(),kh]))+')');case('revoked machine cannot process events but trusted exception scan remains independent',scan()['status']=='processed');error(expression('begin_run'),'42501','revoked unattended identity cannot create authority',True)
   revoked=t.sql('begin;update public.admin_user_roles set revoked_at=clock_timestamp()where user_id='+q(m.UID)+';'+auth+'select public.admin_get_receipt_deferral_exception_v1('+q(new_item['id'])+');rollback;',check=False);case('current owner role revocation denies private exception detail',revoked.returncode!=0 and'42501'in revoked.stderr)
   for table in ['receipt_exception_scans','receipt_exception_work']:
    observed=t.sql('delete from collect_ops.'+table+';',check=False);case('durable '+table+' evidence cannot be deleted',observed.returncode!=0 and'55000'in observed.stderr)
   case('all canonical journals remain balanced and no native/SMS attempt was created',t.scalar("select not exists(select 1 from collect_hybrid.sms_notification_attempts)and(select bool_and(n=2 and debit=credit)from(select journal_entry_id,count(*)n,sum(amount_rwf)filter(where direction='debit')debit,sum(amount_rwf)filter(where direction='credit')credit from collect_hybrid.momo_journal_lines group by journal_entry_id)x);")=='t')
   save(report/'observed-backlog-inbox.json',call("public.admin_list_operational_exceptions_v2(false,50,null,null,'receipt_backlog')"));save(report/'final-projection.json',t.json("select jsonb_build_object('progress',(select to_jsonb(p)from collect_ops.receipt_exception_progress p),'exceptions',(select jsonb_agg(to_jsonb(e))from collect_ops.exceptions e where e.source_kind in('receipt_event','receipt_backlog')),'work',(select jsonb_agg(to_jsonb(w))from collect_ops.receipt_exception_work w));"))
  result['status']='pass'
 except BaseException as error:result['status']='failed';result['error']=str(error);raise
 finally:
  result['sources_unchanged']=all(p.read_bytes()==b for p,b in bodies.items());result['runner_unchanged']=pathlib.Path(__file__).read_bytes()==runner;result['support_unchanged']=pathlib.Path(authority.__file__).read_bytes()==support;result['finished_at']=now();save(report/'result.json',result)
if __name__=='__main__':main()
