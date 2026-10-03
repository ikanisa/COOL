#!/usr/bin/env python3
"""Actual offline language/adoption/producers/dispatch and claim-lock evidence."""
import argparse,base64,concurrent.futures,datetime,hashlib,json,pathlib,threading,time,types,uuid
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
STAGE=pathlib.Path(__file__).resolve().parent
def sha(b):return hashlib.sha256(b).hexdigest()
def uid():return str(uuid.uuid4())
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--report-dir',type=pathlib.Path,required=True);args=ap.parse_args()
 report=args.report_dir.resolve();assert not report.exists();report.mkdir();inputs=report/'inputs';inputs.mkdir();(inputs/'migrations').mkdir();commands=report/'commands';commands.mkdir()
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();(inputs/'executed-helper.py').write_bytes(helper)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner)
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();(inputs/'row-free-platform.sql').write_bytes(baseline)
 marker=(SOURCE/'.collect-release-candidate.json').read_bytes();(inputs/'source08-marker.json').write_bytes(marker);manifest=json.loads(marker)
 items=[];bindings={}
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=p.read_bytes();rel=str(p.relative_to(SOURCE));assert b==(ROOT/rel).read_bytes()and sha(b)==manifest['source_files'][rel]['sha256'];(inputs/'migrations'/p.name).write_bytes(b)
  version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=rel,sha256=sha(b),body=b.decode()));bindings[rel]=sha(b)
 assert len(items)==177
 features=[]
 for name in ['20261001110000_receipt_operational_authority.sql','20261001130000_android_dispatch_authority.sql','20261001220000_governed_settings_requests.sql']:
  p=ROOT/'supabase/migrations'/name;b=p.read_bytes();features.append((p,b));(inputs/name).write_bytes(b);bindings[str(p.relative_to(ROOT))]=sha(b)
 migration=STAGE/'20261001250000_sms_receipt_language_selection.sql';sql=migration.read_bytes();(inputs/migration.name).write_bytes(sql)
 result=dict(scope='177 exact source08 prerequisites plus110000,130000,220000 and staged250000; actual synthetic local language/adoption/producers/dispatch/claim contention; not complete candidate, hosted Auth, native or carrier acceptance',started_at=now(),checks=[],target={},source_bindings=bindings,runner_sha256=sha(runner),helper_sha256=sha(helper),baseline_sha256=sha(baseline),migration_sha256=sha(sql),hosted_written=False,sms_sent=False,device_used=False)
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 original_command=m.command;command_lock=threading.Lock();counter=0
 def recorded_command(args,text=None,check=True,timeout=120):
  nonlocal counter
  with command_lock:counter+=1;index=counter
  prefix=commands/f'{index:05d}';began=now();r=original_command(args,text,False,timeout)
  prefix.with_suffix('.stdout').write_text(r.stdout);prefix.with_suffix('.stderr').write_text(r.stderr)
  safe_args=[x if not x.startswith('POSTGRES_PASSWORD=')else 'POSTGRES_PASSWORD=<generated-local-fixture>'for x in args]
  save(prefix.with_suffix('.json'),dict(argv=safe_args,input_sha256=sha(text.encode())if text is not None else None,started_at=began,finished_at=now(),exit_code=r.returncode,stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode())))
  if check and r.returncode:raise RuntimeError('command failed '+str(safe_args)+': '+r.stderr[-3500:])
  return r
 m.command=recorded_command
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'language',result['target'])as t:
   platform,_=m.platform_shape();t.sql(platform,label='captured row-free platform');m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   t.sql("begin;update auth.users set email='language-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'language-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic current email language operator');commit;")
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
   svc="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   def call(expr,service=False):return t.json('begin;'+(svc if service else auth)+'select '+expr+';commit;')
   def bad(expr,error,label,service=False):
    r=t.sql('begin;'+(svc if service else auth)+'select '+expr+';rollback;',check=False,label=label);case(label,r.returncode!=0 and error in r.stderr)
   for p,b in features:t.sql(b.decode(),label='exact prerequisite '+p.name)
   identity=q(json.dumps(dict(collection_id=m.GROUP)))+'::jsonb'
   def head():return int(t.scalar("select revision from collect_security.runtime_control_heads where family='sms_receipt_policies'and identity="+identity+';'))
   def update(patch,expected=None,request=None,expiry=None):
    return call('public.admin_update_runtime_control_v2('+','.join([q(request or uid()),"'sms_receipt_policies'",identity,q(json.dumps(patch,separators=(',',':'))),str(head()if expected is None else expected),"'Synthetic approved language selection'",q(expiry)if expiry else "clock_timestamp()+interval '100 seconds'"])+')')
   def prepare_payment(n):
    pid,raw,event=uid(),uid(),uid();ref='LANGUAGE-'+str(n);wh=sha(b'+250788971001')
    t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic language payment observation'","encode(extensions.digest('Synthetic language payment observation','sha256'),'hex')",q(wh),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wh),'100',q(ref),"'unallocated'","'Synthetic language payer'"])+');insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values('+','.join([q(pid),q(event),q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),'100',q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+');commit;',label='actual independent raw parsed review payment '+str(n))
    return pid,ref,wh
   def confirm(p,n,delay=0):
    pid,ref,wh=p
    return t.sql("begin;select set_config('application_name','language-normal-post',true);select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"+('select 1 from public.payments where id='+q(pid)+' for update;select pg_sleep('+str(delay)+');'if delay else'')+'select public.confirm_provider_payment('+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-LANGUAGE-'+str(n)),q(wh),'100','clock_timestamp()',"repeat('c',64)"])+');commit;',label='canonical trusted synthetic posting '+str(n))
   def post(n):p=prepare_payment(n);confirm(p,n);return p[0]
   def job(pid):return t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='+q(pid)+';')
   old_pid=post(0);old_job=job(old_pid);case('prerequisite actual normal posting has immutable content2 rw',old_job['template_version']==2 and t.scalar('select language=\'rw\'from collect_receipt_policy.content_evidence where outbox_id='+q(old_job['id'])+';')=='t')
   tables=[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_receipt_policy','content_evidence'),('collect_receipt_policy','decisions')]
   cols=m.columns(t,tables);before=m.fingerprints(t,cols);policies=t.json('select jsonb_agg(to_jsonb(p)order by collection_id)from collect_hybrid.sms_receipt_policies p;');old_head=head()
   old_events=t.json('select coalesce(jsonb_agg(to_jsonb(e)order by id),\'[]\')from collect_security.runtime_control_events e;')
   old_functions=t.json("select jsonb_agg(jsonb_build_object('oid',oid,'owner',proowner,'acl',proacl)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_receipt_policy'::regnamespace,'collect_hybrid'::regnamespace,'collect_security'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_receipt_operations'::regnamespace);")
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='demote fixture installer before language DDL')
   case('language migration installer is actual NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t')
   mismatch=t.sql("begin;update collect_security.runtime_control_heads set content_sha256=repeat('a',64)where family='sms_receipt_policies';"+sql.decode(),check=False,label='real bad-head transactional adoption refusal')
   case('bad prior governance hash refuses atomically before column or event adoption',mismatch.returncode!=0 and 'receipt_language_governance_adoption_invalid'in mismatch.stderr and head()==old_head and t.scalar("select not exists(select 1 from information_schema.columns where table_schema='collect_hybrid'and table_name='sms_receipt_policies'and column_name='receipt_language');")=='t')
   drift=t.sql("begin;create or replace function collect_gateway_dispatch.segment_count(p_body text)returns integer language plpgsql immutable set search_path=''as $$begin return 1;end$$;"+sql.decode(),check=False,label='real predecessor-body transactional drift refusal')
   case('changed real predecessor body refuses atomically',drift.returncode!=0 and 'receipt_language_predecessor_drift'in drift.stderr and head()==old_head)
   t.sql(sql.decode(),label='exact additive language migration under ordinary owner')
   case('install preserves all nonempty finance queued payloads content proofs and decisions',before==m.fingerprints(t,cols))
   current_policies=t.json("select jsonb_agg(to_jsonb(p)-'receipt_language'order by collection_id)from collect_hybrid.sms_receipt_policies p;")
   case('install preserves exact business policies while adding only compatible rw defaults',current_policies==policies and t.scalar("select bool_and(receipt_language='rw')from collect_hybrid.sms_receipt_policies;")=='t')
   after_functions=t.json("select jsonb_agg(jsonb_build_object('oid',oid,'owner',proowner,'acl',proacl)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_receipt_policy'::regnamespace,'collect_hybrid'::regnamespace,'collect_security'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_receipt_operations'::regnamespace);");by_oid={x['oid']:x for x in after_functions}
   case('every predecessor function preserves OID owner and execute ACL',all(by_oid.get(x['oid'])==x for x in old_functions))
   old_ids=[x['id']for x in old_events];case('schema adoption preserves every prior immutable event',t.json('select coalesce(jsonb_agg(to_jsonb(e)order by id),\'[]\')from collect_security.runtime_control_events e where id=any('+q('{'+','.join(old_ids)+'}')+'::uuid[]);')==old_events)
   adoption=t.json("select to_jsonb(e)from collect_security.runtime_control_events e where family='sms_receipt_policies'and previous_revision="+str(old_head)+"and revision="+str(old_head+1)+"and identity_sha256=collect_security.runtime_control_hash("+identity+');');save(report/'observed-schema-adoption.json',adoption)
   case('schema adoption records a genuine owner-only non-request event and advances governance exactly once',head()==old_head+1 and adoption['authority']=='database_owner'and adoption['actor_id']is None and adoption['session_id']is None and adoption.get('request_id')is None and adoption['changed_fields']==['receipt_language'])
   cat=call("public.admin_list_runtime_controls_v2('sms_receipt_policies',20,null)");save(report/'observed-language-catalog-v2.json',cat)
   case('actual closed v2 catalog exposes governed writable language and current revision',cat['descriptor']['writable_fields']==['enabled','receipt_language']and cat['descriptor']['field_types']['receipt_language']=='text'and any(x['value']['receipt_language']=='rw'for x in cat['rows']))
   bad('public.admin_update_runtime_control_v1(\'sms_receipt_policies\','+identity+',\'{"receipt_language":"en"}\'::jsonb,'+str(old_head)+",'Synthetic stale pre-adoption policy')",'runtime_control_revision_conflict','pre-adoption editor revision cannot mutate')
   for lang in ['xx','EN',' fr','fr\n','é']:
    bad('public.admin_update_runtime_control_v1(\'sms_receipt_policies\','+identity+','+q(json.dumps(dict(receipt_language=lang)))+'::jsonb,'+str(head())+",'Synthetic unsupported language refusal')",'receipt_language_invalid','unsupported language refused '+repr(lang))
   for role in ['anon','authenticated','service_role']:
    case(role+' cannot read or mutate private immutable content evidence or new helpers',t.scalar("select not has_schema_privilege("+q(role)+",'collect_receipt_policy','USAGE')and not has_table_privilege("+q(role)+",'collect_receipt_policy.content_evidence','SELECT,INSERT,UPDATE,DELETE')and not has_function_privilege("+q(role)+",'collect_receipt_policy.language_for_job(collect_hybrid.sms_notification_outbox)','EXECUTE')and not has_function_privilege("+q(role)+",'collect_receipt_policy.render_snapshot(collect_hybrid.momo_balance_snapshots,integer,text,text)','EXECUTE');")=='t')
   observed={};last_job=None
   for n,lang in enumerate(['rw','en','fr'],1):
    policy_before=t.json('select to_jsonb(p)from collect_hybrid.sms_receipt_policies p where collection_id='+q(m.GROUP)+';');receipt=update(dict(receipt_language=lang));save(report/('observed-language-request-'+lang+'.json'),receipt)
    policy_after=t.json('select to_jsonb(p)from collect_hybrid.sms_receipt_policies p where collection_id='+q(m.GROUP)+';')
    case(lang+' policy uses governed original request and correct business revision',receipt['contract_version']==2 and receipt['changed']==(policy_before['receipt_language']!=lang)and policy_after['revision']==policy_before['revision']+int(receipt['changed']))
    pid=post(n);o=job(pid);last_job=o;proof=t.json('select to_jsonb(e)from collect_receipt_policy.content_evidence e where outbox_id='+q(o['id'])+';');observed[lang]=o;save(report/('observed-normal-receipt-'+lang+'.json'),dict(job=o,evidence=proof))
    expected=t.scalar('select collect_receipt_policy.render_v2(amount_rwf,member_balance_rwf,(select captured_at from collect_hybrid.momo_balance_snapshots where id=o.snapshot_id),reference,'+q(lang)+')from collect_hybrid.sms_notification_outbox o where id='+q(o['id'])+';')
    case(lang+' actual normal producer captures selected immutable language and exact body/hash',proof['language']==lang and o['message_body']==expected and sha(o['message_body'].encode())==o['body_sha256']and o['template_version']==2 and o['state']=='queued')
    case(lang+' all currentness and body reconstruction consumers use captured language',t.scalar('select collect_receipt_policy.content_is_valid(o)and collect_receipt_policy.content_is_current(o)and collect_receipt_policy.body_for_job(o)=message_body from collect_hybrid.sms_notification_outbox o where id='+q(o['id'])+';')=='t')
    detail=call('public.admin_get_collect_investigation_v1(\'receipt\','+q(o['id'])+')');save(report/('observed-admin-immutable-preview-'+lang+'.json'),detail)
    preview=detail['receipt']['masked_snapshot_preview'];case(lang+' actual Admin preview uses selected immutable copy with reference masked',bool(preview)and o['reference']not in preview and ('Épargne'in preview if lang=='fr'else 'Savings recorded'in preview if lang=='en'else 'Ubwizigame'in preview))
    # Installer-only missed-receipt fixture: skip only the enqueue trigger while
    # the real trusted posting still creates its immutable financial snapshot.
    trigger=t.scalar("select tgname from pg_trigger where tgrelid='collect_hybrid.momo_balance_snapshots'::regclass and tgfoid='collect_hybrid.enqueue_sms_receipt_from_snapshot()'::regprocedure and not tgisinternal;")
    t.sql('alter table collect_hybrid.momo_balance_snapshots disable trigger '+m.identifier(trigger)+';',label='installer-only missed enqueue fixture')
    try:missed=post(10+n)
    finally:t.sql('alter table collect_hybrid.momo_balance_snapshots enable trigger '+m.identifier(trigger)+';')
    snapshot=t.scalar('select id from collect_hybrid.momo_balance_snapshots where payment_id='+q(missed)+"and event_type='receipt';")
    dry=t.json('select collect_receipt_operations.ensure_snapshot('+q(snapshot)+',false,false);');case(lang+' dry ensure derives eligible content without durable job',dry['code']=='DRY_RUN_ELIGIBLE'and not dry['business_handled']and t.scalar('select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='+q(missed)+');')=='t')
    ensured=t.json('select collect_receipt_operations.ensure_snapshot('+q(snapshot)+',false,true);');eo=job(missed);save(report/('observed-ensure-receipt-'+lang+'.json'),dict(result=ensured,job=eo))
    case(lang+' actual ensure creates the same selected immutable language and repeats without duplicate',ensured['code']=='RECEIPT_ENQUEUED'and t.scalar('select language='+q(lang)+'from collect_receipt_policy.content_evidence where outbox_id='+q(eo['id'])+';')=='t'and t.json('select collect_receipt_operations.ensure_snapshot('+q(snapshot)+',false,true);')['code']=='RECEIPT_EXISTS'and t.scalar('select count(*)=1 from collect_hybrid.sms_notification_outbox where payment_id='+q(missed)+';')=='t')
   old_copy=call('public.admin_get_collect_investigation_v1(\'receipt\','+q(old_job['id'])+')')['receipt']['masked_snapshot_preview'];case('current French policy never rewrites old rw body evidence or immutable Admin preview',job(old_pid)==old_job and 'Ubwizigame'in old_copy and t.scalar('select language=\'rw\'from collect_receipt_policy.content_evidence where outbox_id='+q(old_job['id'])+';')=='t')
   for length,segments in [(160,1),(161,2),(306,2),(307,3)]:
    case('approved accented GSM accounting boundary '+str(length),t.scalar('select collect_gateway_dispatch.segment_count(repeat(\'é\','+str(length)+'))='+str(segments)+';')=='t')
   for body in ['é'*501,'e\u0301','^','€','😀','\n','`']:
    r=t.sql('select collect_gateway_dispatch.segment_count('+q(body)+');',check=False);case('narrow encoding refuses '+repr(body[:12]),r.returncode!=0 and 'gateway_dispatch_encoding_unsupported'in r.stderr)
   for operation in ['update','delete']:
    r=t.sql(('update collect_receipt_policy.content_evidence set language=\'en\''if operation=='update'else'delete from collect_receipt_policy.content_evidence')+'where outbox_id='+q(last_job['id'])+';',check=False);case('even owner cannot '+operation+' captured language evidence',r.returncode!=0 and 'receipt_content_evidence_immutable'in r.stderr)
   # Exact existing enrollment/authority protocol, actual local SQL producers.
   pref='3059301306072a8648ce3d020106082a8648ce3d03010703420004';points=['6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5','7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1']
   def key(n):b=bytes.fromhex(pref+points[n]);return base64.b64encode(b).decode(),sha(b)
   pub,kh=key(0);principal=call('public.admin_enroll_receipt_operations_identity_v2('+','.join([q(uid()),q(pub),q(kh),"clock_timestamp()+interval '1 day'"])+')')['principal_id']
   def operation(action,payload={}):
    req=uid();return call('public.receipt_operations_execute_v2('+','.join([q(principal),q(req),q(kh),q(sha(json.dumps([req,action,payload]).encode())),'clock_timestamp()',q(action),q(json.dumps(payload))+'::jsonb'])+')',True)
   operation('prove_key');call('public.admin_activate_receipt_operations_identity_v2('+','.join(map(q,[principal,uid(),kh]))+')')
   pub,gkh=key(1);device=call('public.admin_enroll_gateway_device_v1('+','.join(map(q,[uid(),uid(),pub,gkh,'c'*64]))+')')['device_id']
   def heartbeat():
    payload=dict(sms_permission=True,network='validated',telephony='ready',sim_selected=True,sim_revision_sha256='d'*64,local_pause=False,reported_at=now());return call('public.gateway_heartbeat_v1('+','.join(map(q,[device,uid(),sha(json.dumps(payload).encode())]))+','+q(json.dumps(payload))+'::jsonb)',True)
   heartbeat();call('public.admin_activate_gateway_device_v1('+','.join(map(q,[device,uid(),gkh,'c'*64]))+')')
   caps={k:10 if k=='run_actions'else 20 if k=='run_sms_segments'else 100 for k in ['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']}
   call('public.admin_configure_receipt_operations_v2('+','.join([q(uid()),'1',"'Live-limited'",'false',"array["+q(principal)+"]::uuid[]","array["+q(m.GROUP)+"]::uuid[]","array["+q(device)+"]::uuid[]",q(json.dumps(caps))+'::jsonb','false','24',"'Synthetic offline language authority only'","clock_timestamp()+interval '100 seconds'"])+')');operation('begin_run')
   t.sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';");heartbeat()
   # Preserve old jobs; mark only stale unstarted jobs with their existing
   # conservative cancellation API so queue order reaches current French work.
   for lang,o in observed.items():
    if lang!='fr':call('public.admin_cancel_unstarted_receipt_v1('+q(o['id'])+','+str(o['fence_version'])+",'Synthetic stale language receipt closure')")
   grant=call('public.gateway_dispatch_grant_v2('+','.join([q(device),q(uid()),q('a'*64),"'{}'::jsonb"])+')',True);save(report/'observed-french-dispatch-grant.json',grant)
   case('actual automatic grant accepts exact French immutable body and charges multipart segments',grant['code']=='DISPATCH_GRANTED'and 'Épargne'in grant['body']and grant['segment_count']==int(t.scalar('select collect_gateway_dispatch.segment_count('+q(grant['body'])+');'))and t.scalar('select sms_segments='+str(grant['segment_count'])+'from collect_receipt_operations.reservations where receipt_id='+q(grant['receipt_id'])+';')=='t')
   current_fr=job(post(40));update(dict(receipt_language='en'));case('language change invalidates queued authority while immutable French evidence remains valid',t.scalar('select not collect_hybrid.sms_receipt_job_is_current(o.id)and collect_receipt_policy.content_is_valid(o)from collect_hybrid.sms_notification_outbox o where id='+q(current_fr['id'])+';')=='t')
   arm=dict(attempt_id=grant['attempt_id'],fence_version=grant['fence_version'],body_sha256=grant['body_sha256'],destination_sha256=grant['destination_sha256'],reservation_sha256='b'*64,callbacks=[dict(segment_index=i,sent_callback_id=uid(),delivery_callback_id=uid())for i in range(grant['segment_count'])])
   bad('public.gateway_arm_dispatch_v2('+','.join([q(device),q(uid()),q('b'*64),q(json.dumps(arm))+'::jsonb'])+')','gateway_dispatch_source_invalid','policy language change fences the previously granted final arm',True)
   # Real account-claim call waits on the already locked payment; posting must
   # defer inverse-order member/contact locks and commit without deadlock.
   actor=uid();sid=uid();t.sql("insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)values("+q(actor)+",'authenticated','authenticated','250788978201',clock_timestamp(),'{}','{}');update public.feature_flags set enabled=true where key='hybrid_verified_account_claim';")
   p=prepare_payment(50)
   claim_auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=actor,session_id=sid,role='authenticated',aal='aal1')))+",true);"
   with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
    posting=pool.submit(confirm,p,50,3)
    for _ in range(100):
     if t.scalar("select exists(select 1 from pg_stat_activity where application_name='language-normal-post'and query like '%pg_sleep(3)%'and state='active');")=='t':break
     time.sleep(.01)
    else:raise AssertionError('owned actual posting sleep not observed')
    claiming=pool.submit(t.sql,"begin;select set_config('application_name','language-account-claim',true);"+claim_auth+'select public.claim_verified_current_account();commit;',label='actual authenticated account claim contends with financial posting')
    waiting=False
    for _ in range(100):
     if t.scalar("select exists(select 1 from pg_stat_activity where application_name='language-account-claim'and wait_event_type='Lock');")=='t':waiting=True;break
     time.sleep(.01)
    case('actual account claim observed waiting on owned financial posting transaction',waiting)
    posting_result=posting.result(timeout=20);claim_result=claiming.result(timeout=20)
   save(report/'observed-claim-posting.json',dict(posting=dict(exit_code=posting_result.returncode,stdout=posting_result.stdout,stderr=posting_result.stderr),claim=dict(exit_code=claim_result.returncode,stdout=claim_result.stdout,stderr=claim_result.stderr),actual_wait_observed=waiting))
   case('normal financial posting and actual account claim both commit without deadlock',posting_result.returncode==0 and claim_result.returncode==0 and 'claimed'in claim_result.stdout and t.scalar('select status=\'posted\'and contributor_user_id='+q(actor)+'from public.payments where id='+q(p[0])+';')=='t')
   case('busy receipt selection preserves immutable snapshot and durable unhandled payment event',t.scalar('select exists(select 1 from collect_hybrid.momo_balance_snapshots where payment_id='+q(p[0])+"and event_type='receipt')and exists(select 1 from collect_hybrid.receipt_business_events where payment_id="+q(p[0])+"and event_kind='payment_posted')and not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id="+q(p[0])+');')=='t')
   result['status']='passed';result['finished_at']=now();save(report/'result.json',result)
 except BaseException as e:
  result['status']='failed';result['error']=type(e).__name__+': '+str(e);result['finished_at']=now();save(report/'result.json',result);raise
 finally:
  result['source_unchanged']=all((ROOT/p).read_bytes()==(inputs/'migrations'/pathlib.Path(p).name).read_bytes()for p in bindings if (inputs/'migrations'/pathlib.Path(p).name).exists())and all(p.read_bytes()==b for p,b in features)and migration.read_bytes()==sql and pathlib.Path(__file__).read_bytes()==runner
  result['command_count']=counter;save(report/'result.json',result)
if __name__=='__main__':main()
