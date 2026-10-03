#!/usr/bin/env python3
"""Actual offline PostgreSQL closure API/transport-guard evidence, not live SMS."""
import argparse, base64, datetime, hashlib, json, pathlib, sys, threading, types, uuid

ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
STAGE=pathlib.Path(__file__).resolve().parent
FEATURES=['20261001110000_receipt_operational_authority.sql','20261001120000_operational_exception_lifecycle.sql',
 '20261001130000_android_dispatch_authority.sql','20261001140000_receipt_deferral_exceptions.sql',
 '20261001150000_receipt_exception_worker.sql','20261001170000_android_attempt_archive.sql',
 '20261001210000_receipt_worker_bounded_sweep.sql','20261001220000_governed_settings_requests.sql',
 '20261001233000_assisted_sms_originating_session_fence.sql','20261002000000_runtime_control_edit_eligibility.sql',
 '20261002010000_sms_receipt_language_selection.sql','20261002020000_receipt_source_busy_deferral.sql']
def sha(data):return hashlib.sha256(data).hexdigest()
def uid():return str(uuid.uuid4())
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def save(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',type=pathlib.Path,required=True);args=ap.parse_args()
 report=args.report_dir.resolve();assert not report.exists();report.mkdir();inputs=report/'inputs';inputs.mkdir();(inputs/'migrations').mkdir();commands=report/'commands';commands.mkdir()
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();(inputs/'executed-helper.py').write_bytes(helper)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner)
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();(inputs/'row-free-platform.sql').write_bytes(baseline)
 marker=(SOURCE/'.collect-release-candidate.json').read_bytes();(inputs/'source08-marker.json').write_bytes(marker);manifest=json.loads(marker)
 bindings={};items=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  body=p.read_bytes();rel=str(p.relative_to(SOURCE));assert body==(ROOT/rel).read_bytes()and sha(body)==manifest['source_files'][rel]['sha256'];(inputs/'migrations'/p.name).write_bytes(body)
  version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=rel,sha256=sha(body),body=body.decode()));bindings[rel]=sha(body)
 assert len(items)==177
 features=[]
 for name in FEATURES:
  p=ROOT/'supabase/migrations'/name;body=p.read_bytes();(inputs/name).write_bytes(body);features.append((p,body));bindings[str(p.relative_to(ROOT))]=sha(body)
 migration=STAGE/'supabase/migrations/20261002040000_receipt_unarmed_closure.sql';body=migration.read_bytes();(inputs/migration.name).write_bytes(body)
 result=dict(scope='177 exact retained source08 prerequisites plus twelve exact current scoped migrations and staged closure; actual synthetic offline local PostgreSQL; not whole candidate, hosted Auth, native or carrier acceptance',started_at=now(),checks=[],target={},source_bindings=bindings,runner_sha256=sha(runner),helper_sha256=sha(helper),baseline_sha256=sha(baseline),migration_sha256=sha(body),hosted_written=False,sms_sent=False,device_used=False)
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 runtime=pathlib.Path(sys.executable).resolve();runtime_bytes=runtime.read_bytes();(inputs/'python-runtime').write_bytes(runtime_bytes)
 docker_bytes=pathlib.Path(m.DOCKER).read_bytes();(inputs/'docker-runtime').write_bytes(docker_bytes)
 result['tools']=dict(python_path=str(runtime),python_sha256=sha(runtime_bytes),python_version=sys.version,docker_path=m.DOCKER,docker_sha256=sha(docker_bytes),image=m.IMAGE,image_id=m.IMAGE_ID)
 save(report/'execution-binding.json',result)
 original=m.command;counter=0;lock=threading.Lock()
 def command(args,text=None,check=True,timeout=120):
  nonlocal counter
  with lock:counter+=1;index=counter
  prefix=commands/f'{index:05d}';started=now();r=original(args,text,False,timeout)
  prefix.with_suffix('.stdout').write_text(r.stdout);prefix.with_suffix('.stderr').write_text(r.stderr)
  safe=[a if not a.startswith('POSTGRES_PASSWORD=')else 'POSTGRES_PASSWORD=<generated-local-fixture>'for a in args]
  save(prefix.with_suffix('.json'),dict(argv=safe,input_sha256=sha(text.encode())if text is not None else None,started_at=started,finished_at=now(),exit_code=r.returncode,stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode())))
  if check and r.returncode:raise RuntimeError('command failed '+str(safe)+': '+r.stderr[-3500:])
  return r
 m.command=command
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'successorclosure',result['target'])as t:
   platform,provenance=m.platform_shape();save(report/'platform-provenance.json',provenance);t.sql(platform,label='captured row-free platform');m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   t.sql("begin;update auth.users set email='closure-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'closure-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic current email successor operator');commit;")
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
   svc="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expr,service=False):return t.json('begin;'+(svc if service else auth)+'select '+expr+';commit;')
   def denied(expr,error,label,service=False):
    r=t.sql('begin;'+(svc if service else auth)+'select '+expr+';rollback;',check=False,label=label);case(label,r.returncode!=0 and error in r.stderr)
   for p,b in features:t.sql(b.decode(),label='exact prerequisite '+p.name)
   def post(n):
    pid,raw,event=uid(),uid(),uid();ref='CLOSURE-'+str(n);wh=sha(b'+250788971001')
    t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic closure payment observation'","encode(extensions.digest('Synthetic closure payment observation','sha256'),'hex')",q(wh),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wh),'100',q(ref),"'unallocated'","'Synthetic closure payer'"])+');insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values('+','.join([q(pid),q(event),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+');commit;')
    t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-CLOSURE-'+str(n)),q(wh),'100','clock_timestamp()',"repeat('c',64)"])+');commit;')
    return t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='+q(pid)+';')
   a=post(1);b=post(2)
   finance_tables=[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_receipt_policy','content_evidence'),('collect_receipt_policy','decisions')]
   cols=m.columns(t,finance_tables);before=m.fingerprints(t,cols)
   functions=t.json("select jsonb_agg(jsonb_build_object('oid',oid,'def',pg_get_functiondef(oid),'owner',proowner,'acl',proacl,'config',proconfig)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_receipt_policy'::regnamespace,'collect_hybrid'::regnamespace,'collect_security'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_receipt_operations'::regnamespace);")
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='demote fixture installer before additive closure DDL')
   case('closure installer is actual NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t')
   t.sql(body.decode(),label='exact additive closure migration ordinary owner')
   after=t.json("select jsonb_agg(jsonb_build_object('oid',oid,'def',pg_get_functiondef(oid),'owner',proowner,'acl',proacl,'config',proconfig)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_receipt_policy'::regnamespace,'collect_hybrid'::regnamespace,'collect_security'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_receipt_operations'::regnamespace);")
   by_oid={x['oid']:x for x in after};case('all predecessor function bytes OIDs owners ACL and configuration preserved',all(by_oid.get(x['oid'])==x for x in functions))
   case('install preserves all nonempty financial evidence and original queued rows',before==m.fingerprints(t,cols)and t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(a['id'])+';')==a)
   case('successor sending remains disabled by default and retained v2 decision unchanged',t.scalar("select not enabled and revision=1 from collect_receipt_successors.configuration;")=='t'and before==m.fingerprints(t,cols))
   for role in ['anon','authenticated','service_role']:
    case(role+' cannot directly read or write successor schema evidence',t.scalar("select not has_schema_privilege("+q(role)+",'collect_receipt_successors','USAGE')and not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='collect_receipt_successors'and c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')));")=='t')
   def inspect(o):return call('public.admin_inspect_unarmed_receipt_closure_v1('+q(o['id'])+')')
   def close_sql(o,h,request=None,reason='Synthetic irreversible original closure'):
    request=request or uid();return request,'public.admin_close_unarmed_receipt_v1('+','.join([q(request),q(o['id']),str(h['root_revision']),str(h['lineage_revision']),"'definitely_not_invoked'",q(reason)])+')'
   h=inspect(a);save(report/'observed-unarmed-inspection.json',h)
   case('actual closed inspection reports untouched current receipt eligible',h['can_close']and h['reason_code']=='unarmed_eligible'and h['root_revision']==1 and h['lineage_revision']==1 and not h['automatic_grant_present'])
   request,expression=close_sql(a,h);receipt=call(expression);save(report/'observed-original-closure.json',receipt)
   case('actual closure suppresses only original transport and retains finance',receipt['proof_class']=='never_armed_closed'and not receipt['financial_action']and not receipt['send_action']and receipt['primary_receipt_retained']and before==m.fingerprints(t,cols))
   closed=t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(a['id'])+';')
   case('closure retains exact original payload snapshot contact and lifetime identity',closed['state']=='suppressed'and closed['suppression_reason']=='successor_unarmed_closed'and {k:v for k,v in closed.items()if k not in['state','suppression_reason']}=={k:v for k,v in a.items()if k not in['state','suppression_reason']})
   case('same original UUID exactly replays closure receipt',call(expression)==receipt)
   _,conflict=close_sql(a,h,request,'Different accountable closure reason');denied(conflict,'receipt_successor_request_conflict','changed reason cannot reuse original request')
   looked=call('public.admin_get_receipt_successor_request_v1('+q(request)+')');save(report/'observed-original-lookup.json',looked);case('original request lookup recovers exact committed receipt',looked['status']=='recorded'and looked['receipt']==receipt)
   missing=call('public.admin_get_receipt_successor_request_v1('+q(uid())+')');case('unknown request lookup is not recorded and grants no authority',missing['status']=='not_recorded'and missing['receipt']is None)
   case('closed root inspect refuses a second closure',inspect(a)['reason_code']=='already_closed'and not inspect(a)['can_close'])
   ensured=t.json('select collect_receipt_operations.ensure_snapshot('+q(a['snapshot_id'])+',false,true);');case('primary ensure still returns one retained closed primary receipt',ensured['code']=='RECEIPT_EXISTS'and ensured['receipt_id']==a['id']and t.scalar('select count(*)=1 from collect_hybrid.sms_notification_outbox where payment_id='+q(a['payment_id'])+';')=='t')
   r=t.sql("update collect_hybrid.sms_notification_outbox set state='queued',suppression_reason=null where id="+q(a['id'])+';',check=False);case('even owner cannot reopen an irreversibly closed original',r.returncode!=0 and 'receipt_original_irreversibly_closed'in r.stderr)
   denied('public.collect_claim_receipt_v2('+','.join(map(q,[m.UID,m.SID,a['id'],'synthetic-closure-worker',uid()]))+')','receipt_original_irreversibly_closed','actual assisted claim RPC cannot issue a post-closure capability',True)
   r=t.sql('insert into collect_hybrid.sms_notification_claim_requests(request_id,outbox_id,operator_user_id,worker_id,result)values('+','.join(map(q,[uid(),a['id'],m.UID,'synthetic-direct-closure']))+",'{}'::jsonb);",check=False);case('direct assisted claim insert is permanently fenced',r.returncode!=0 and 'receipt_original_irreversibly_closed'in r.stderr)
   for table in ['original_closures','owner_requests','content_policies']:
    r=t.sql('delete from collect_receipt_successors.'+table+';',check=False);case('even owner cannot delete retained '+table,r.returncode!=0 and 'receipt_successor_evidence_immutable'in r.stderr)
    r=t.sql('truncate collect_receipt_successors.'+table+' cascade;',check=False);case('even owner cannot truncate retained '+table,r.returncode!=0 and 'receipt_successor_evidence_immutable'in r.stderr)
   # Actual current principal/device/run, with real shared-budget grant.
   pref='3059301306072a8648ce3d020106082a8648ce3d03010703420004';points=['6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5','7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1']
   def key(n):data=bytes.fromhex(pref+points[n]);return base64.b64encode(data).decode(),sha(data)
   pub,kh=key(0);principal=call('public.admin_enroll_receipt_operations_identity_v2('+','.join([q(uid()),q(pub),q(kh),"clock_timestamp()+interval '1 day'"])+')')['principal_id']
   def operation(action,payload=None):
    payload=payload or {};req=uid();return call('public.receipt_operations_execute_v2('+','.join([q(principal),q(req),q(kh),q(sha(json.dumps([req,action,payload]).encode())),'clock_timestamp()',q(action),q(json.dumps(payload))+'::jsonb'])+')',True)
   operation('prove_key');call('public.admin_activate_receipt_operations_identity_v2('+','.join(map(q,[principal,uid(),kh]))+')')
   pub,gkh=key(1);device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[uid(),uid(),pub,gkh,'c'*64]))+')')['device_id']
   def heartbeat():
    payload=dict(sms_permission=True,network='validated',telephony='ready',sim_selected=True,sim_revision_sha256='d'*64,local_pause=False,reported_at=now());return call('public.gateway_heartbeat_v1('+','.join(map(q,[device,uid(),sha(json.dumps(payload).encode())]))+','+q(json.dumps(payload))+'::jsonb)',True)
   heartbeat();call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
   caps={k:20 if k=='run_actions'else 40 if k=='run_sms_segments'else 100 for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   call('public.admin_configure_receipt_operations_v2('+','.join([q(uid()),'1',"'Live-limited'",'false',"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(caps))+'::jsonb','false','24',"'Synthetic offline closure authority only'","clock_timestamp()+interval '100 seconds'"])+')');operation('begin_run');t.sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';");heartbeat()
   # Retain original seed/queued rows; cancel every unrelated original with the
   # actual existing API so dispatch's deterministic queue reaches b.
   queued=t.json("select coalesce(jsonb_agg(id),'[]')from collect_hybrid.sms_notification_outbox where state='queued'and id<>"+q(b['id'])+';')
   for outbox in queued:
    inspected=call('public.admin_inspect_unstarted_receipt_v1('+q(outbox)+')')
    if inspected['receipt']['can_cancel']:call('public.admin_cancel_unstarted_receipt_v1('+q(uid())+','+q(outbox)+','+str(inspected['receipt']['revision'])+",'content_review_required')")
   grant=call('public.gateway_dispatch_grant_v2('+','.join([q(device),q(uid()),q('a'*64),"'{}'::jsonb"])+')',True);save(report/'observed-prior-ordinary-grant.json',grant)
   case('actual ordinary automatic grant is issued for second original with shared budget',grant['code']=='DISPATCH_GRANTED'and grant['receipt_id']==b['id']and t.scalar('select count(*)=1 from collect_receipt_operations.reservations where id=(select reservation_id from collect_gateway_dispatch.attempts where id='+q(grant['attempt_id'])+');')=='t')
   hb=inspect(b);case('issued ordinary automatic grant without arm is closable',hb['can_close']and hb['automatic_grant_present'])
   rb,eb=close_sql(b,hb);closed_grant=call(eb);save(report/'observed-issued-grant-closure.json',closed_grant)
   case('closing ordinary grant retains immutable original grant and budget reservation',t.scalar('select state=\'granted\'from collect_gateway_dispatch.attempts where id='+q(grant['attempt_id'])+';')=='t'and t.scalar('select count(*)=1 from collect_receipt_operations.reservations where id=(select reservation_id from collect_gateway_dispatch.attempts where id='+q(grant['attempt_id'])+');')=='t')
   arm=dict(attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],reservation_sha256='b'*64,callbacks=[dict(segment_index=i,sent_callback_id=uid(),delivery_callback_id=uid())for i in range(grant['segment_count'])])
   denied('public.gateway_arm_dispatch_v2('+','.join([q(device),q(uid()),q('b'*64),q(json.dumps(arm))+'::jsonb'])+')','gateway_dispatch_arm_fenced','actual previously issued ordinary grant cannot arm after closure',True)
   r=t.sql('insert into collect_gateway_dispatch.arms(attempt_id,request_id,reservation_sha256,callback_plan,health_observation_id,armed_at,expires_at)select id,'+q(uid())+",repeat('b',64),'[]'::jsonb,health_observation_id,clock_timestamp(),expires_at from collect_gateway_dispatch.attempts where id="+q(grant['attempt_id'])+';',check=False);case('direct automatic arm insert cannot bypass closure',r.returncode!=0 and 'receipt_original_irreversibly_closed'in r.stderr)
   grant2=call('public.gateway_dispatch_grant_v2('+','.join([q(device),q(uid()),q('c'*64),"'{}'::jsonb"])+')',True);case('ordinary automatic poll cannot grant either closed original',grant2['code']=='NO_ELIGIBLE_RECEIPT')
   c=post(3);gc=call('public.gateway_dispatch_grant_v2('+','.join([q(device),q(uid()),q('d'*64),"'{}'::jsonb"])+')',True)
   pc=dict(attempt_id=gc['attempt_id'],fence_version=gc['fence_version'],body_sha256=gc['body_sha256'],destination_sha256=gc['destination_sha256'],reservation_sha256='e'*64,callbacks=[dict(segment_index=i,sent_callback_id=uid(),delivery_callback_id=uid())for i in range(gc['segment_count'])])
   ac=call('public.gateway_arm_dispatch_v2('+','.join([q(device),q(uid()),q('e'*64),q(json.dumps(pc))+'::jsonb'])+')',True)
   hc=inspect(c);case('actual final armed attempt is never classified uninvoked',not hc['can_close']and hc['reason_code']in['state_not_queued','original_already_armed','assisted_transport_present'])
   _,ec=close_sql(c,hc);denied(ec,'receipt_successor_original_not_closable','armed unknown original cannot be closed for retry')
   before_head=int(t.scalar('select revision from collect_receipt_successors.lineage_heads where root_outbox_id='+q(c['id'])+';'))
   callback=dict(attempt_id=gc['attempt_id'],fence_version=gc['fence_version'],body_sha256=gc['body_sha256'],destination_sha256=gc['destination_sha256'],segment_count=gc['segment_count'],callback_id=pc['callbacks'][0]['sent_callback_id'],segment_index=0,callback_kind='sent',result_code=-1,tp_status=None,occurred_at=now())
   cr=call('public.gateway_callback_v2('+','.join([q(device),q(uid()),q('f'*64),q(json.dumps(callback))+'::jsonb'])+')',True)
   case('actual callback advances lineage even before complete terminal outcome',int(t.scalar('select revision from collect_receipt_successors.lineage_heads where root_outbox_id='+q(c['id'])+';'))>before_head)
   save(report/'observed-armed-inspection.json',hc);save(report/'observed-callback.json',cr)
   result['status']='passed';result['finished_at']=now();save(report/'result.json',result)
 except BaseException as e:
  result['status']='failed';result['error']=type(e).__name__+': '+str(e);result['finished_at']=now();save(report/'result.json',result);raise
 finally:
  result['source_unchanged']=all((ROOT/p).read_bytes()==(inputs/'migrations'/pathlib.Path(p).name).read_bytes()for p in bindings if(inputs/'migrations'/pathlib.Path(p).name).exists())and all(p.read_bytes()==b for p,b in features)and migration.read_bytes()==body and pathlib.Path(__file__).read_bytes()==runner
  result['command_count']=counter;save(report/'result.json',result)
if __name__=='__main__':main()
