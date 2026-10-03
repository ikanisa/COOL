#!/usr/bin/env python3
"""Focused Admin automatic evidence proof using actual retained producer fixtures.

Local SQL role claims are trust fixtures, never hosted JWT/device/carrier proof.
The 177 captured migration prerequisites and three feature prerequisites are
reused; this does not rehearse the complete current candidate.
"""
import argparse,base64,concurrent.futures,datetime,hashlib,json,pathlib,types,uuid
ROOT=next(p for p in pathlib.Path(__file__).resolve().parents if (p/'.git').exists())
READER_NAME='20261001230000_automatic_gateway_investigation.sql'
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
SQL=ROOT/'supabase/migrations/20261001170000_android_attempt_archive.sql'
DISPATCH=ROOT/'supabase/migrations/20261001130000_android_dispatch_authority.sql'
FOUNDATION=ROOT/'supabase/migrations/20261001110000_receipt_operational_authority.sql'
def sha(b):return hashlib.sha256(b).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def save(p,x):p.write_text(json.dumps(x,indent=2)+'\n')
def uid():return str(uuid.uuid4())
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',required=True);ap.add_argument('--migration',type=pathlib.Path,default=ROOT/'supabase/migrations'/READER_NAME);args=ap.parse_args();report=pathlib.Path(args.report_dir).resolve();assert not report.exists();report.mkdir(parents=True);inputs=report/'inputs';inputs.mkdir();(inputs/'migrations').mkdir()
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();(inputs/'executed-helper.py').write_bytes(helper)
 marker=(SOURCE/'.collect-release-candidate.json').read_bytes();(inputs/'source08-marker.json').write_bytes(marker);manifest=json.loads(marker)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner)
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();(inputs/'row-free-platform.sql').write_bytes(baseline)
 staged=[(FOUNDATION,FOUNDATION.read_bytes()),(DISPATCH,DISPATCH.read_bytes()),(SQL,SQL.read_bytes()),(args.migration.resolve(),args.migration.read_bytes())]
 assert sha(staged[0][1])=='743e4362ea5eab756d2665a2fe9a1840d593baac1348e1d61042b024288cfe40'
 for p,b in staged:(inputs/p.name).write_bytes(b)
 items=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=p.read_bytes();rel=str(p.relative_to(SOURCE));assert b==(ROOT/rel).read_bytes();assert sha(b)==manifest['source_files'][rel]['sha256'];(inputs/'migrations'/p.name).write_bytes(b);version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=rel,sha256=sha(b),body=b.decode()))
 assert len(items)==177
 result=dict(scope='177 unchanged source08 app prerequisites + stable110000 + dispatch130000 + archive170000 + new230000; scoped local Admin evidence; complete current candidate excluded',started_at=now(),runner_sha256=sha(runner),helper_sha256=sha(helper),source08_marker_sha256=sha(marker),foundation_sha256=sha(staged[0][1]),dispatch_sha256=sha(staged[1][1]),archive_sha256=sha(staged[2][1]),migration_sha256=sha(staged[3][1]),producer_fixture_sha256=sha((ROOT/'scripts/tests/android_attempt_archive_uat.py').read_bytes()),baseline_sha256=sha(baseline),checks=[],target={},hosted_written=False,device_used=False,sms_sent=False)
 save(report/'execution-binding.json',{k:v for k,v in result.items()if k not in('checks','target')})
 m=types.ModuleType('retained_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok),category='admin_reader'if name.startswith('Admin:')else'producer_fixture'));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
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
   finance=m.columns(t,[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances')]);before=m.fingerprints(t,finance)
   for p,b in staged[:3]:t.sql(b.decode(),label='exact feature producer prerequisite '+p.name)
   predecessor=t.json("select jsonb_agg(jsonb_build_object('oid',p.oid,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',p.proacl)order by p.oid)from pg_proc p where p.pronamespace in('public'::regnamespace,'collect_gateway'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_gateway_archive'::regnamespace);")
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='demote fixture owner before new reader install')
   case('Admin: new reader installer is genuinely NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t')
   t.sql(staged[3][1].decode(),label='ordinary-role additive Admin reader')
   after=t.json("select jsonb_agg(jsonb_build_object('oid',p.oid,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',p.proacl)order by p.oid)from pg_proc p where p.pronamespace in('public'::regnamespace,'collect_gateway'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_gateway_archive'::regnamespace);")
   after_by_oid={v['oid']:v for v in after}
   case('Admin: install preserves every predecessor function OID definition owner and ACL',all(after_by_oid.get(v['oid'])==v for v in predecessor))
   def read_receipt(rid=None,limit=20,cursor=None):
    return call('public.admin_get_gateway_receipt_investigation_v3('+','.join([q(rid or receipt),str(limit),q(cursor['recorded_at'])if cursor else'null',q(cursor['request_id'])if cursor else'null'])+')')
   def read_device(did=None,limit=20,cursor=None):
    return call('public.admin_list_gateway_device_attempts_v3('+','.join([q(did or device),str(limit),q(cursor['issued_at'])if cursor else'null',q(cursor['attempt_id'])if cursor else'null'])+')')
   receipt_keys=set('contract_version scope receipt_id status checked_at sample_valid_until limit attempt arm expected_callbacks archive_ack history_complete rows next_cursor carrier_proof delivery_proven send_authority'.split())
   attempt_keys=set('attempt_id receipt_id device_id run_id principal_id fence_version policy_revision segment_count grant_request_id health_observation_id state issued_at expires_at updated_at'.split())
   row_keys=set('request_id source action recorded_at code callback_id segment_index callback_kind result_code tp_status occurred_at'.split())
   def checked_read(label,v):
    encoded=json.dumps(v)
    case('Admin: '+label,set(v)==receipt_keys and v['contract_version']==3 and v['scope']=='rw_automatic_gateway_evidence'and all(v[k]is False for k in ['carrier_proof','delivery_proven','send_authority','history_complete'])and all(set(r)==row_keys for r in v['rows'])and len(v['rows'])<=v['limit']and (v['attempt']is None or set(v['attempt'])==attempt_keys)and datetime.datetime.fromisoformat(v['sample_valid_until'].replace('Z','+00:00'))-datetime.datetime.fromisoformat(v['checked_at'].replace('Z','+00:00'))==datetime.timedelta(seconds=60)and not any(k in encoded for k in ['destination_e164','destination_sha256','body_text','body_sha256','reservation_sha256','sim_revision_sha256','callback_plan','request_sha256']))
    save(report/('admin-'+label.replace(' ','-')+'.json'),v)
    return v

   case('installation preserves nonempty canonical financial data',before==m.fingerprints(t,finance))
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
   # Real canonical nonempty receipt, explicit Rwanda route and owner consent.
   pid='99930000-0000-4000-8000-000000000001';raw='99930000-0000-4000-8000-000000000002';event='99930000-0000-4000-8000-000000000003';wh=sha(b'+250788971001');ref='DISPATCH-'+('X'*50)
   t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic dispatch observation'","encode(extensions.digest('Synthetic dispatch observation','sha256'),'hex')",q(wh),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wh),'100',q(ref),"'unallocated'","'Synthetic payer'"])+');commit;')
   t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values("+','.join([q(pid),q(event),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),"'SYNTHETIC-DISPATCH-PROOF'",q(wh),'100','clock_timestamp()',"repeat('c',64)"])+');commit;')
   receipt=t.scalar('select id from collect_hybrid.sms_notification_outbox where payment_id='+q(pid)+';');case('fixture produces current redacted-v2 eligible queued receipt',bool(receipt)and t.scalar('select template_version=2 and state=\'queued\'and collect_receipt_policy.content_is_current(o)and collect_receipt_actions.rwanda_source(o)from collect_hybrid.sms_notification_outbox o where id='+q(receipt)+';')=='t')
   def extra_source(index):
    pid=uid();raw=uid();event=uid();wh=sha(b'+250788971001');ref='ADMIN-PAGE-'+str(index)
    t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic dispatch observation'","encode(extensions.digest('Synthetic dispatch observation','sha256'),'hex')",q(wh),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wh),'100',q(ref),"'unallocated'","'Synthetic payer'"])+');commit;')
    t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values("+','.join([q(pid),q(event),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),"'SYNTHETIC-DISPATCH-PROOF'",q(wh),'100','clock_timestamp()',"repeat('c',64)"])+');commit;')
    receipt=t.scalar('select id from collect_hybrid.sms_notification_outbox where payment_id='+q(pid)+';');case('fixture produces current redacted-v2 eligible queued receipt',bool(receipt)and t.scalar('select template_version=2 and state=\'queued\'and collect_receipt_policy.content_is_current(o)and collect_receipt_actions.rwanda_source(o)from collect_hybrid.sms_notification_outbox o where id='+q(receipt)+';')=='t')
    return receipt
   extra_receipts=[extra_source(i)for i in range(2)]
   finance_before=m.fingerprints(t,finance);immutable_cols=m.columns(t,[('collect_hybrid','sms_notification_outbox')]);immutable_cols['collect_hybrid.sms_notification_outbox']=[c for c in immutable_cols['collect_hybrid.sms_notification_outbox']if c not in ['state','fence_version','attempt_count','updated_at','observed_sent_at']];primary_before=m.fingerprints(t,immutable_cols)
   caps={k:10 if k=='run_actions'else 20 if k=='run_sms_segments'else 100 for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   config=call('public.admin_configure_receipt_operations_v2('+','.join([q(uid()),'1',"'Live-limited'",'false',"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(caps))+'::jsonb','false','24',"'Synthetic offline governed pilot'","clock_timestamp()+interval '120 seconds'"])+')')
   run=operation('begin_run');case('actual current-policy operation run has live fence',run['code']=='RUN_STARTED')
   t.sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';");heartbeat()
   initial=checked_read('current receipt before automatic grant',read_receipt())
   case('Admin: queued current source reports no automatic attempt',initial['status']=='no_automatic_attempt'and initial['attempt']is None and initial['rows']==[]and initial['expected_callbacks']==[]and initial['archive_ack']is None)
   absent=checked_read('missing receipt is unavailable',read_receipt(uid()))
   case('Admin: unavailable source discloses no automatic evidence',absent['status']=='unavailable'and absent['attempt']is None and absent['rows']==[])
   grant=call(gateway('dispatch_grant'),True);save(report/'observed-grant.json',grant)
   case('actual backend produces automatic prior-arm fixture',grant['ok']and grant['segment_count']==2)
   granted=checked_read('prior grant before arm',read_receipt())
   case('Admin: automatic grant is historical evidence without an arm',granted['attempt']['attempt_id']==grant['attempt_id']and granted['attempt']['state']=='granted'and granted['arm']is None and granted['expected_callbacks']==[]and len(granted['rows'])==1 and granted['rows'][0]['source']=='grant')
   arm=dict(attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],reservation_sha256='a'*64,callbacks=[dict(segment_index=i,sent_callback_id=uid(),delivery_callback_id=uid())for i in range(grant['segment_count'])])
   call(gateway('arm_dispatch',arm),True)
   armed=checked_read('arm expected callback plan',read_receipt())
   case('Admin: arm exposes bounded expected IDs without reservation or text',armed['arm']['request_id']is not None and len(armed['expected_callbacks'])==4 and all(not x['has_observation']and not x['consistent']and x['result_code']is None for x in armed['expected_callbacks']))
   for role in ['anon','authenticated','service_role']:

    case(role+' has no private archive schema/table/helper grants',t.scalar("select not has_schema_privilege("+q(role)+",'collect_gateway_archive','USAGE')and not exists(select 1 from pg_class c where c.relnamespace='collect_gateway_archive'::regnamespace and c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE')))and not exists(select 1 from pg_proc f where f.pronamespace='collect_gateway_archive'::regnamespace and has_function_privilege("+q(role)+",f.oid,'EXECUTE'));")=='t')
   refs=[dict(callback_id=x[k+'_callback_id'],request_id=uid(),request_sha256='a'*64)for x in arm['callbacks']for k in ['sent','delivery']]
   payload=dict(attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],callback_requests=refs)
   def archive(action,payload={},request=None,digest=None,dev=None):
    req=request or uid();h=digest or sha(json.dumps([req,action,payload]).encode())
    return 'public.gateway_archive_'+action+'_v3('+','.join([q(dev or device),q(req),q(h),q(json.dumps(payload))+'::jsonb'])+')'
   req=uid();incomplete=call(archive('attempt',payload,req),True);save(report/'observed-incomplete.json',incomplete)
   case('arm without all durable multipart callbacks refuses archival',not incomplete['ok']and incomplete['code']=='CALLBACK_EVIDENCE_INCOMPLETE')
   case('refused original UUID remains recorded without ACK',call(archive('lookup',{'target_request_id':req}),True)['recorded_result']==incomplete and t.scalar('select count(*)from collect_gateway_archive.acknowledgements;')=='0')
   bad(archive('attempt',payload),'permission denied','human JWT cannot manufacture device archive authority',False)
   anonymous=t.sql('begin;set local role anon;select '+archive('attempt',payload)+';rollback;',check=False)
   case('anonymous role has no archive entrypoint',anonymous.returncode!=0 and 'permission denied'in anonymous.stderr)
   case('service only narrow RPC grants',t.scalar("select has_function_privilege('service_role','public.gateway_archive_attempt_v3(uuid,uuid,text,jsonb)','EXECUTE')and not has_function_privilege('authenticated','public.gateway_archive_attempt_v3(uuid,uuid,text,jsonb)','EXECUTE')and not has_function_privilege('anon','public.gateway_archive_lookup_v3(uuid,uuid,text,jsonb)','EXECUTE');")=='t')
   def cb(i,kind='sent',code=-1):return dict(callback_id=arm['callbacks'][i][kind+'_callback_id'],attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],segment_index=i,segment_count=grant['segment_count'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],callback_kind=kind,result_code=code,tp_status=None,occurred_at=now())
   for i in range(grant['segment_count']):
    for kind in ['sent','delivery']:
     ix=i*2+(kind=='delivery');body=cb(i,kind);digest=sha(json.dumps(body).encode());refs[ix]['request_sha256']=digest
     call(gateway('callback',body,request=refs[ix]['request_id'],digest=digest),True)
     if ix==0:
      partial=checked_read('partial multipart observations',read_receipt())
      case('Admin: one recorded callback cannot prove complete multipart delivery',sum(x['has_observation']for x in partial['expected_callbacks'])==1 and partial['archive_ack']is None)
   complete=checked_read('all framework callbacks before archive',read_receipt())
   case('Admin: complete framework observations have no invented archive ACK',complete['attempt']['state']=='observed_sent'and all(x['has_observation']and x['consistent']for x in complete['expected_callbacks'])and complete['archive_ack']is None)
   extra_grants=[call(gateway('dispatch_grant'),True)for _ in extra_receipts]
   case('Admin: device directory fixtures use two real additional bounded grants',all(x['ok']for x in extra_grants)and {x['receipt_id']for x in extra_grants}==set(extra_receipts))

   before_sources=m.fingerprints(t,m.columns(t,[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_gateway_dispatch','attempts'),('collect_gateway_dispatch','arms'),('collect_gateway_dispatch','callback_bindings'),('collect_gateway_dispatch','callbacks'),('collect_gateway_dispatch','requests')]))
   bad(archive('attempt',{**payload,'destination_e164':'+250788971001'}),'gateway_payload_invalid','caller cannot supply contact or financial fields')
   bad(archive('attempt',{**payload,'fence_version':payload['fence_version']+1}),'gateway_dispatch_attempt_unavailable','wrong fence refuses before source disclosure')
   bad(archive('attempt',{**payload,'body_sha256':'f'*64}),'gateway_archive_binding_invalid','wrong immutable body hash refuses')
   badrefs=[dict(x)for x in refs];badrefs[0]['request_sha256']='f'*64
   bad(archive('attempt',{**payload,'callback_requests':badrefs}),'gateway_archive_binding_invalid','wrong original callback request digest refuses')
   bad(archive('attempt',{**payload,'callback_requests':refs[::-1]}),'gateway_archive_binding_invalid','wrong callback plan order refuses')
   bad(archive('attempt',payload,refs[0]['request_id']),'gateway_archive_request_conflict','v2 original UUID cannot become an archive request')
   unknown=call(archive('lookup',{'target_request_id':uid()}),True);save(report/'observed-unknown.json',unknown)
   case('unknown original request has no fabricated ACK',unknown['outcome']=='unknown'and unknown['recorded_result']is None)
   t.sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
   call('public.admin_revoke_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
   req1,req2=uid(),uid();expr1=archive('attempt',payload,req1);expr2=archive('attempt',payload,req2)
   with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
    f1=pool.submit(call,expr1,True);f2=pool.submit(call,expr2,True);pair=[f1.result(),f2.result()]
   save(report/'observed-concurrent.json',pair);ack=next(x for x in pair if x['ok']);save(report/'observed-ack.json',ack)
   case('actual concurrent archive requests preserve one lifetime ACK',sum(x['ok']for x in pair)==1 and any(x['code']=='ATTEMPT_ALREADY_ACKNOWLEDGED'for x in pair))
   case('paused and revoked prior device can archive known evidence',ack['ok']and ack['receipt_id']==receipt and ack['callback_requests']==refs)
   case('ACK explicitly grants no send delivery or carrier conclusion',ack['carrier_proof']is False and ack['delivery_proven']is False and ack['send_authority']is False and ack['evidence_kind']=='complete_framework_callback_observations')
   archived=checked_read('actual terminal archive acknowledgement',read_receipt())
   case('Admin: historical archive receipt reports exact durable ACK only',archived['archive_ack']['acknowledgement_id']==ack['archive_ack_id']and archived['archive_ack']['request_id']==ack['request_id']and archived['archive_ack']['evidence_kind']=='complete_framework_callback_observations')
   expr=expr1 if ack['request_id']==req1 else expr2
   replay=call(expr,True);case('SQL idempotency changes only replay marker',replay=={**ack,'replay':True})
   original=call(archive('lookup',{'target_request_id':ack['request_id']}),True);save(report/'observed-lookup.json',original)
   case('manual original UUID lookup returns immutable acknowledgement',original['recorded_result']==ack)
   point=points[0];prime=0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
   third=bytes.fromhex(pref+point[:64]+format(prime-int(point[64:],16),'064x'));thirdpub=base64.b64encode(third).decode();thirdhash=sha(third)
   other=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[uid(),uid(),thirdpub,thirdhash,'b'*64]))+')')['device_id']
   case('another device lookup cannot disclose original ACK',call(archive('lookup',{'target_request_id':ack['request_id']},dev=other),True)['outcome']=='unknown')
   bad(archive('attempt',payload,dev=other),'gateway_dispatch_attempt_unavailable','other enrolled device cannot archive a foreign attempt')
   isolation=t.sql("begin isolation level repeatable read;"+svc+'select '+archive('lookup',{'target_request_id':ack['request_id']})+';rollback;',check=False)
   case('stale transaction isolation refuses archive read authority',isolation.returncode!=0 and 'gateway_archive_snapshot_retry'in isolation.stderr)
   bad(archive('attempt',payload,ack['request_id'],'f'*64),'gateway_archive_request_conflict','changed original request bytes cannot reuse UUID')
   sourcecols=m.columns(t,[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_gateway_dispatch','attempts'),('collect_gateway_dispatch','arms'),('collect_gateway_dispatch','callback_bindings'),('collect_gateway_dispatch','callbacks'),('collect_gateway_dispatch','requests')])
   case('ACK lookup/refusals preserve exact financial receipt attempt and callback data',before_sources==m.fingerprints(t,sourcecols))
   bad(gateway('callback',cb(0,'sent'),request=ack['request_id']),'gateway_archive_request_conflict','archived original UUID cannot become a new callback')
   for table in ['requests','acknowledgements']:
    p=t.sql('update collect_gateway_archive.'+table+' set recorded_at=clock_timestamp();',check=False)
    save(report/('observed-immutable-'+table+'.json'),dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr))
    case('archive '+table+' immutable under owner SQL',p.returncode!=0 and 'gateway_dispatch_evidence_immutable'in p.stderr)
   changed=call(gateway('callback',cb(0,'sent',1)),True);save(report/'observed-late-conflict.json',changed)
   case('late signed contradiction after archival is retained and folds uncertain',changed['state']=='uncertain'and changed['conflicting_observations'])
   case('historical archive ACK remains point-in-time evidence after contradiction',call(archive('lookup',{'target_request_id':ack['request_id']}),True)['recorded_result']==ack)
   case('archive ACK creates no new lifetime or assisted transport identity',t.scalar('select count(*)=3 from collect_gateway_dispatch.attempts;')=='t'and t.scalar('select not exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id='+q(receipt)+');')=='t')
   bad('collect_gateway_archive.require_request('+','.join(map(q,[device,uid(),'a'*64]))+')','permission denied','service cannot bypass public archive boundary')
   contradicted=checked_read('late contradictory observation',read_receipt())
   case('Admin: late contradiction preserves historical ACK and current uncertainty',contradicted['attempt']['state']=='uncertain'and contradicted['archive_ack']==archived['archive_ack']and sum(not x['consistent']for x in contradicted['expected_callbacks'])==1)
   pages=[];cursor=None
   for _ in range(15):
    v=read_receipt(limit=2,cursor=cursor);pages+=v['rows'];cursor=v['next_cursor']
    if cursor is None:break
   case('Admin: exact timestamp UUID paging covers all three producer branches once',cursor is None and len(pages)==len({x['request_id']for x in pages})and {x['source']for x in pages}=={'grant','arm','callback','archive'}and len(pages)==10 and pages==sorted(pages,key=lambda x:(x['recorded_at'],x['request_id']),reverse=True))
   directory=read_device(limit=1);save(report/'admin-directory-first.json',directory)
   case('Admin: device directory bounded scanned window has typed cursor',set(directory)==set('contract_version scope device_id status checked_at sample_valid_until limit scanned_count rows next_cursor carrier_proof delivery_proven send_authority'.split())and directory['scanned_count']==1 and len(directory['rows'])==1 and directory['next_cursor']is not None and set(directory['rows'][0])==attempt_keys and all(directory[k]is False for k in ['carrier_proof','delivery_proven','send_authority']))
   drows=directory['rows'];dcur=directory['next_cursor']
   while dcur:
    v=read_device(limit=1,cursor=dcur);drows+=v['rows'];dcur=v['next_cursor']
   case('Admin: device timestamp UUID pages contain every actual attempt once',len(drows)==3 and len({x['attempt_id']for x in drows})==3)
   top=directory['rows'][0];hidden=t.json('begin;update public.parsed_payment_events set network='+q('airtel_momo')+' where id=(select parsed_event_id from public.payments where id=(select payment_id from collect_hybrid.sms_notification_outbox where id='+q(top['receipt_id'])+'));'+auth+'select public.admin_list_gateway_device_attempts_v3('+q(device)+',1);rollback;')
   case('Admin: filtered empty device page preserves continuation after scanned anchor',hidden['rows']==[]and hidden['scanned_count']==1 and hidden['next_cursor']is not None and hidden['next_cursor']['attempt_id']==top['attempt_id'])
   filtered=t.json('begin;update public.parsed_payment_events set network='+q('airtel_momo')+' where id='+q(event)+';'+auth+'select public.admin_get_gateway_receipt_investigation_v3('+q(receipt)+');rollback;')
   case('Admin: contradictory current Rwanda parser hides all receipt evidence',filtered['status']=='unavailable'and filtered['attempt']is None and filtered['archive_ack']is None and filtered['expected_callbacks']==[]and filtered['rows']==[])
   bad('public.admin_get_gateway_receipt_investigation_v3(null)','gateway_investigation_input_invalid','Admin: null receipt refuses',False)
   bad('public.admin_get_gateway_receipt_investigation_v3('+q(receipt)+',26)','gateway_investigation_input_invalid','Admin: oversize limit refuses',False)
   bad('public.admin_get_gateway_receipt_investigation_v3('+q(receipt)+',1,clock_timestamp(),null)','gateway_investigation_input_invalid','Admin: incomplete cursor refuses',False)
   bad('public.admin_list_gateway_device_attempts_v3('+q(device)+',0)','gateway_investigation_input_invalid','Admin: zero directory limit refuses',False)
   bad('public.admin_list_gateway_device_attempts_v3('+q(device)+",1,'infinity',gen_random_uuid())",'gateway_investigation_input_invalid','Admin: nonfinite directory cursor refuses',False)
   for role in ['anon','service_role']:
    r=t.sql('begin;set local role '+role+';select public.admin_get_gateway_receipt_investigation_v3('+q(receipt)+');rollback;',check=False)
    case('Admin: '+role+' cannot call owner evidence reader',r.returncode!=0 and 'permission denied'in r.stderr)
   r=t.sql('begin isolation level repeatable read;'+auth+'select public.admin_get_gateway_receipt_investigation_v3('+q(receipt)+');rollback;',check=False)
   case('Admin: stale transaction snapshot refuses',r.returncode!=0 and 'gateway_read_snapshot_retry'in r.stderr)
   for permission in ['notifications.read','system_health.read']:
    r=t.sql('begin;delete from public.admin_role_permissions where permission_name='+q(permission)+';'+auth+'select public.admin_get_gateway_receipt_investigation_v3('+q(receipt)+');rollback;',check=False)
    case('Admin: current '+permission+' removal refuses',r.returncode!=0 and 'roster_actor_unavailable'in r.stderr)
   for assignment,label in [("update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id="+q(m.SID),'expired session'),("update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id="+q(m.UID),'revoked approval'),("update auth.users set deleted_at=clock_timestamp()where id="+q(m.UID),'deleted account')]:
    r=t.sql('begin;'+assignment+';'+auth+'select public.admin_list_gateway_device_attempts_v3('+q(device)+');rollback;',check=False)
    case('Admin: current '+label+' denies device history',r.returncode!=0 and ('roster_actor_unavailable'in r.stderr or 'session'in r.stderr))
   case('Admin: new helper remains private and no API role acquires underlying table access',t.scalar("select not has_function_privilege('authenticated','collect_gateway_dispatch.admin_attempt_projection(collect_gateway_dispatch.attempts)','EXECUTE')and not has_function_privilege('service_role','collect_gateway_dispatch.admin_attempt_projection(collect_gateway_dispatch.attempts)','EXECUTE')and not has_table_privilege('authenticated','collect_gateway_dispatch.callbacks','SELECT');")=='t')
   read_spec=m.columns(t,[('collect_gateway_dispatch','attempts'),('collect_gateway_dispatch','callbacks'),('collect_gateway_dispatch','requests'),('collect_gateway_archive','acknowledgements'),('collect_gateway_archive','requests'),('collect_hybrid','sms_notification_outbox')]);read_before=m.fingerprints(t,read_spec)
   read_receipt();read_device();case('Admin: all successful investigation reads preserve exact transport and receipt records',read_before==m.fingerprints(t,read_spec))
   save(report/'synthetic-fixture.json',dict(device_id=device,request=payload,acknowledgement=ack,original_lookup=original,unknown_lookup=unknown,late_conflict=changed))
   case('financial snapshots journals payments and lifetime primary content remain identical',finance_before==m.fingerprints(t,finance)and primary_before==m.fingerprints(t,immutable_cols))
   result['finished_at']=now();result['passed']=all(c['passed']for c in result['checks']);save(report/'result.json',result)
 except Exception as e:result['error']=str(e);result['finished_at']=now();save(report/'result.json',result);raise
 finally:
  result['source_unchanged']=all(p.read_bytes()==b for p,b in staged)and all((ROOT/x['path']).read_bytes()==(inputs/'migrations'/pathlib.Path(x['path']).name).read_bytes()for x in items)and pathlib.Path(__file__).read_bytes()==runner;save(report/'result.json',result)
if __name__=='__main__':main()
