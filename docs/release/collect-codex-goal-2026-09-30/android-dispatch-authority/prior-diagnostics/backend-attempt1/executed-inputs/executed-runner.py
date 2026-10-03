#!/usr/bin/env python3
"""Task-private, network-none SQL dispatch authority proof. No hosted/device/SMS."""
import argparse,base64,concurrent.futures,datetime,hashlib,json,pathlib,types,uuid
ROOT=pathlib.Path(__file__).resolve().parents[2]
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
SQL=ROOT/'supabase/migrations/20261001130000_android_dispatch_authority.sql'
FOUNDATION=ROOT/'supabase/migrations/20261001110000_receipt_operational_authority.sql'
def sha(b):return hashlib.sha256(b).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def save(p,x):p.write_text(json.dumps(x,indent=2)+'\n')
def uid():return str(uuid.uuid4())
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',required=True);args=ap.parse_args();report=pathlib.Path(args.report_dir).resolve();assert not report.exists();report.mkdir(parents=True);inputs=report/'inputs';inputs.mkdir();(inputs/'migrations').mkdir()
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();(inputs/'executed-helper.py').write_bytes(helper)
 marker=(SOURCE/'.collect-release-candidate.json').read_bytes();(inputs/'source08-marker.json').write_bytes(marker);manifest=json.loads(marker)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner)
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();(inputs/'row-free-platform.sql').write_bytes(baseline)
 staged=[(FOUNDATION,FOUNDATION.read_bytes()),(SQL,SQL.read_bytes())]
 assert sha(staged[0][1])=='743e4362ea5eab756d2665a2fe9a1840d593baac1348e1d61042b024288cfe40'
 for p,b in staged:(inputs/p.name).write_bytes(b)
 items=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=p.read_bytes();rel=str(p.relative_to(SOURCE));assert sha(b)==manifest['source_files'][rel]['sha256'];(inputs/'migrations'/p.name).write_bytes(b);version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=rel,sha256=sha(b),body=b.decode()))
 assert len(items)==177
 result=dict(scope='source08 177 app prerequisites + stable110000 + dispatch130000; synthetic service trust boundary; local PG17.6 only',started_at=now(),runner_sha256=sha(runner),helper_sha256=sha(helper),source08_marker_sha256=sha(marker),foundation_sha256=sha(staged[0][1]),migration_sha256=sha(staged[1][1]),baseline_sha256=sha(baseline),checks=[],target={},hosted_written=False,device_used=False,sms_sent=False)
 save(report/'execution-binding.json',{k:v for k,v in result.items()if k not in('checks','target')})
 m=types.ModuleType('retained_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'dispatch',result['target'])as t:
   platform,_=m.platform_shape();t.sql(platform,label='captured row-free Auth platform');m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
   svc="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expr,service=False):return t.json('begin;'+(svc if service else auth)+'select '+expr+';commit;')
   def bad(expr,reason,label,service=True):
    r=t.sql('begin;'+(svc if service else auth)+'select '+expr+';rollback;',check=False);case(label,r.returncode!=0 and reason in r.stderr)
   t.sql("begin;update auth.users set email='dispatch-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'dispatch-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic current email dispatch owner');commit;")
   finance=m.columns(t,[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots')]);before=m.fingerprints(t,finance)
   for p,b in staged:t.sql(b.decode(),label='additive '+p.name)
   case('installation preserves nonempty canonical financial data',before==m.fingerprints(t,finance))
   for role in ['anon','authenticated','service_role']:
    case(role+' has no private schema/table/helper grant',t.scalar("select not has_schema_privilege("+q(role)+",'collect_gateway_dispatch','USAGE')and not exists(select 1 from pg_class c where c.relnamespace='collect_gateway_dispatch'::regnamespace and(c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE'))))and not exists(select 1 from pg_proc f where f.pronamespace='collect_gateway_dispatch'::regnamespace and has_function_privilege("+q(role)+",f.oid,'EXECUTE'));")=='t')
   case('v2 sender RPC only service grant',t.scalar("select has_function_privilege('service_role','public.gateway_dispatch_grant_v2(uuid,uuid,text,jsonb)','EXECUTE')and not has_function_privilege('authenticated','public.gateway_dispatch_grant_v2(uuid,uuid,text,jsonb)','EXECUTE')and not has_function_privilege('anon','public.gateway_dispatch_grant_v2(uuid,uuid,text,jsonb)','EXECUTE');")=='t')
   pref='3059301306072a8648ce3d020106082a8648ce3d03010703420004'
   points=['6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5','7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1']
   def key(n):b=bytes.fromhex(pref+points[n]);return base64.b64encode(b).decode(),sha(b)
   pub,kh=key(0);principal=call('public.admin_enroll_receipt_operations_identity_v2('+','.join([q(uid()),q(pub),q(kh),"clock_timestamp()+interval '1 day'"])+')')['principal_id']
   def operation(action,payload={}):
    req=uid();digest=sha(json.dumps([req,action,payload]).encode());return call('public.receipt_operations_execute_v2('+','.join([q(principal),q(req),q(kh),q(digest),'clock_timestamp()',q(action),q(json.dumps(payload))+'::jsonb'])+')',True)
   operation('prove_key');call('public.admin_activate_receipt_operations_identity_v2('+','.join(map(q,[principal,uid(),kh]))+')')
   pub,gkh=key(1);device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[uid(),uid(),pub,gkh,'c'*64]))+')')['device_id']
   def gateway(action,payload={},request=None,digest=None,dev=None):
    req=request or uid();h=digest or sha(json.dumps([req,action,payload]).encode());return 'public.gateway_'+action+'_v2('+','.join([q(dev or device),q(req),q(h),q(json.dumps(payload))+'::jsonb'])+')'
   def heartbeat(**changes):
    payload=dict(sms_permission=True,network='validated',telephony='ready',sim_selected=True,sim_revision_sha256='d'*64,local_pause=False,reported_at=now());payload.update(changes)
    return call('public.gateway_heartbeat_v1('+','.join(map(q,[device,uid(),sha(json.dumps(payload).encode())]))+','+q(json.dumps(payload))+'::jsonb)',True)
   heartbeat();call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
   paused=call(gateway('dispatch_grant'),True);save(report/'observed-grant-paused.json',paused);case('unchanged default Paused policy cannot grant',paused['code']=='OPERATIONS_PAUSED')
   case('paused request reserves no attempt or quota',t.scalar('select not exists(select 1 from collect_gateway_dispatch.attempts)and not exists(select 1 from collect_receipt_operations.reservations);')=='t')
   # Real canonical nonempty receipt, explicit Rwanda route and owner consent.
   pid='99930000-0000-4000-8000-000000000001';raw='99930000-0000-4000-8000-000000000002';event='99930000-0000-4000-8000-000000000003';wh=sha(b'+250788971001');ref='DISPATCH-SYNTHETIC-1'
   t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic dispatch observation'","encode(extensions.digest('Synthetic dispatch observation','sha256'),'hex')",q(wh),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wh),'100',q(ref),"'unallocated'","'Synthetic payer'"])+');commit;')
   t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values("+','.join([q(pid),q(event),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),"'SYNTHETIC-DISPATCH-PROOF'",q(wh),'100','clock_timestamp()',"repeat('c',64)"])+');commit;')
   receipt=t.scalar('select id from collect_hybrid.sms_notification_outbox where payment_id='+q(pid)+';');case('fixture produces current redacted-v2 eligible queued receipt',bool(receipt)and t.scalar('select template_version=2 and state=\'queued\'and collect_hybrid.sms_receipt_job_is_current(id)and collect_receipt_actions.rwanda_source(o)from collect_hybrid.sms_notification_outbox o where id='+q(receipt)+';')=='t')
   finance_before=m.fingerprints(t,finance);immutable_cols=m.columns(t,[('collect_hybrid','sms_notification_outbox')]);immutable_cols[('collect_hybrid','sms_notification_outbox')]=[c for c in immutable_cols[('collect_hybrid','sms_notification_outbox')]if c not in ['state','fence_version','attempt_count','updated_at','observed_sent_at']];primary_before=m.fingerprints(t,immutable_cols)
   caps={k:10 if k=='run_actions'else 20 if k=='run_sms_segments'else 100 for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   config=call('public.admin_configure_receipt_operations_v2('+','.join([q(uid()),'1',"'Live-limited'",'false',"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(caps))+'::jsonb','false','24',"'Synthetic offline governed pilot'","clock_timestamp()+interval '120 seconds'"])+')')
   run=operation('begin_run');case('actual current-policy operation run has live fence',run['code']=='RUN_STARTED')
   bad(gateway('dispatch_grant'),'receipt_dispatch_paused','SMS flag false blocks even configured Live run')
   t.sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
   heartbeat(network='offline');case('latest offline device health returns no grant',call(gateway('dispatch_grant'),True)['code']=='DEVICE_NOT_READY');heartbeat()
   req=uid();expr=gateway('dispatch_grant',request=req);grant=call(expr,True);save(report/'observed-grant.json',grant);case('grant derives immutable body contact segments and current run',grant['ok']and grant['receipt_id']==receipt and grant['run_id']==run['run_id']and grant['segment_count']==2 and grant['body_sha256']==sha(grant['body'].encode())and grant['destination_sha256']==sha(grant['destination_e164'].encode()))
   case('grant leaves receipt queued without assisted attempt/confirmation',t.scalar('select state=\'queued\'and not exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id='+q(receipt)+')and not exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id='+q(receipt)+')from collect_hybrid.sms_notification_outbox where id='+q(receipt)+';')=='t')
   replay=call(expr,True);case('replayed grant cannot release body or renewed authority',replay['code']=='ORIGINAL_REQUEST_RECORDED'and set(replay)=={'ok','code','device_id','request_id','replay'})
   lookup=call(gateway('reconcile',{'target_request_id':req}),True);save(report/'observed-grant-reconciliation.json',lookup);case('original UUID lookup is durable redacted evidence only',lookup['recorded_result']==replay)
   case('another grant cannot allocate second lifetime attempt',call(gateway('dispatch_grant'),True)['code']=='NO_ELIGIBLE_RECEIPT')
   case('cancellation excludes new automatic prior evidence',t.scalar('select collect_receipt_actions.ineligible_reason(o)from collect_hybrid.sms_notification_outbox o where id='+q(receipt)+';')=='prior_transport_evidence')
   bad('public.collect_claim_receipt('+','.join([q(m.UID),q(receipt),"'synthetic-worker'",q(uid())])+')','gateway_dispatch_arm_required','real assisted claim cannot overlap automatic reservation')
   arm=dict(attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],reservation_sha256='a'*64,callbacks=[dict(segment_index=i,sent_callback_id=uid(),delivery_callback_id=uid())for i in range(grant['segment_count'])])
   bad(gateway('arm_dispatch',{**arm,'fence_version':grant['fence_version']+1}),'gateway_dispatch_attempt_unavailable','wrong fence cannot arm')
   heartbeat(sim_revision_sha256='f'*64);bad(gateway('arm_dispatch',arm),'gateway_dispatch_arm_fenced','SIM selection change prevents final arm');heartbeat()
   armreq=uid();armexpr=gateway('arm_dispatch',arm,armreq);armed=call(armexpr,True);save(report/'observed-arm.json',armed);case('arm atomically records permit and send_started once',armed['ok']and armed['reservation_sha256']==arm['reservation_sha256']and t.scalar('select state=\'send_started\'from collect_hybrid.sms_notification_outbox where id='+q(receipt)+';')=='t')
   case('arm replay is redacted and never another invocation permission',call(armexpr,True)['code']=='ORIGINAL_REQUEST_RECORDED')
   def cb(i,kind='sent',code=-1,request=None):return dict(callback_id=arm['callbacks'][i][kind+'_callback_id'],attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],segment_index=i,segment_count=grant['segment_count'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],callback_kind=kind,result_code=code,tp_status=None,occurred_at=now())
   first=call(gateway('callback',cb(0)),True);save(report/'observed-partial-callback.json',first);case('one multipart sent callback cannot claim whole message sent',first['state']=='send_started'and first['sent_observations']==1)
   bad(gateway('callback',{**cb(1),'body_sha256':'f'*64}),'gateway_dispatch_callback_binding_invalid','wrong immutable body cannot record callback')
   complete=call(gateway('callback',cb(1)),True);save(report/'observed-complete-callback.json',complete);case('all consistent SENT OK becomes observed_sent only no carrier proof',complete['state']=='observed_sent'and complete['sent_observations']==2 and complete['carrier_proof']is False)
   t.sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
   call('public.admin_stop_receipt_operations_v2('+','.join([q(uid()),str(config['revision']),"'Synthetic emergency stop after arm'","clock_timestamp()+interval '120 seconds'"])+')')
   call('public.admin_revoke_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
   late=call(gateway('callback',cb(0,'delivery',0)),True);case('prior-arm raw delivery callback reconciles after SMS pause stop and revocation',late['delivery_observations']==1 and late['carrier_proof']is False)
   changed=call(gateway('callback',cb(0,'sent',1)),True);save(report/'observed-contradictory-callback.json',changed);case('late contradictory signed SENT observation retained and folds uncertain',changed['state']=='uncertain'and changed['conflicting_observations'])
   status=call(gateway('attempt_status',{'attempt_id':grant['attempt_id'],'fence_version':grant['fence_version']}),True);save(report/'observed-status.json',status);case('revoked original device status never authorizes resend or archival',status['state']=='uncertain'and status['terminal_archive_ack']is False)
   bad(gateway('dispatch_grant'),'gateway_device_not_active','revoked device cannot fetch new grant')
   read=call('public.admin_get_gateway_receipt_attempt_v2('+q(receipt)+')');save(report/'observed-owner-automatic-history.json',read);case('owner auto-history separate from human approval and redacted',read['automatic_attempt']['attempt_id']==grant['attempt_id']and not any(k in json.dumps(read)for k in ['destination_e164','body_sha256','reservation_sha256','callback_plan']))
   bad('public.admin_get_gateway_receipt_attempt_v2('+q(receipt)+')','permission denied','machine service cannot impersonate owner read')
   case('one immutable primary payload snapshot identity survives all transport steps',primary_before==m.fingerprints(t,immutable_cols))
   case('canonical financial journals snapshots and payments remain identical',finance_before==m.fingerprints(t,finance))
   case('automatic attempt never manufactures assisted confirmation/operator',t.scalar('select not exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id='+q(receipt)+')and not exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id='+q(receipt)+');')=='t')
   bad('collect_gateway_dispatch.status('+q(grant['attempt_id'])+')','permission denied','service cannot execute private helper directly')
   r=t.sql('delete from collect_gateway_dispatch.arms where attempt_id='+q(grant['attempt_id'])+';',check=False);case('armed immutable evidence cannot be deleted',r.returncode!=0 and 'gateway_dispatch_evidence_immutable'in r.stderr)
   result['finished_at']=now();result['passed']=all(c['passed']for c in result['checks']);save(report/'result.json',result)
 except Exception as e:result['error']=str(e);result['finished_at']=now();save(report/'result.json',result);raise
 finally:
  result['source_unchanged']=all(p.read_bytes()==b for p,b in staged)and pathlib.Path(__file__).read_bytes()==runner;save(report/'result.json',result)
if __name__=='__main__':main()
