#!/usr/bin/env python3
"""Actual offline PostgreSQL immutable successor approval evidence, not live SMS."""
import argparse, base64, concurrent.futures, datetime, hashlib, json, pathlib, sys, threading, time, types, uuid

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
 prior_dir=STAGE.parent/'accepted-unarmed-closure-current1/proof/attempt7';prior=json.loads((prior_dir/'result.json').read_text())
 assert prior['status']=='passed'and prior['source_unchanged']and len(prior['checks'])==51
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();assert sha(helper)==prior['helper_sha256'];(inputs/'executed-helper.py').write_bytes(helper)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner)
 bindings={}
 for rel,h in prior['source_bindings'].items():
  b=(ROOT/rel).read_bytes();assert sha(b)==h
  dest=inputs/'migrations'/pathlib.Path(rel).name;dest.write_bytes(b);bindings[rel]=h
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();assert sha(baseline)==prior['baseline_sha256'];(inputs/'row-free-platform.sql').write_bytes(baseline)
 closure=(prior_dir/'inputs/20261002040000_receipt_unarmed_closure.sql').read_bytes();assert sha(closure)==prior['migration_sha256'];(inputs/'20261002040000_receipt_unarmed_closure.sql').write_bytes(closure)
 setup=(prior_dir/'inputs/reused-predecessor-setup.sql').read_bytes();assert sha(setup)==prior['reused_predecessor']['setup_sha256'];(inputs/'reused-predecessor-setup.sql').write_bytes(setup)
 migration=STAGE/'supabase/migrations/20261002041000_receipt_successor_approvals.sql';body=migration.read_bytes();(inputs/migration.name).write_bytes(body)
 result=dict(scope='189 exact source-bound retained/current prerequisites, sealed closure400 and staged approval410; focused synthetic offline PostgreSQL only, no sender or Admin consumer acceptance',started_at=now(),checks=[],target={},source_bindings=bindings,runner_sha256=sha(runner),helper_sha256=sha(helper),baseline_sha256=sha(baseline),closure_sha256=sha(closure),migration_sha256=sha(body),reused_setup_sha256=sha(setup),sealed_closure_result_sha256=sha((prior_dir/'result.json').read_bytes()),hosted_written=False,sms_sent=False,device_used=False)
 m=types.ModuleType('captured_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql';q=m.quoted
 runtime=pathlib.Path(sys.executable).resolve();rb=runtime.read_bytes();db=pathlib.Path(m.DOCKER).read_bytes();(inputs/'python-runtime').write_bytes(rb);(inputs/'docker-runtime').write_bytes(db)
 result['tools']=dict(python_path=str(runtime),python_sha256=sha(rb),python_version=sys.version,docker_path=m.DOCKER,docker_sha256=sha(db),image=m.IMAGE,image_id=m.IMAGE_ID)
 save(report/'execution-binding.json',result)
 original=m.command;counter=0;lock=threading.Lock()
 def command(args,text=None,check=True,timeout=120):
  nonlocal counter
  with lock:counter+=1;index=counter
  prefix=commands/f'{index:05d}';started=now();r=original(args,text,False,timeout)
  prefix.with_suffix('.stdout').write_text(r.stdout);prefix.with_suffix('.stderr').write_text(r.stderr)
  safe=[a if not a.startswith('POSTGRES_PASSWORD=')else 'POSTGRES_PASSWORD=<generated-local-fixture>'for a in args]
  save(prefix.with_suffix('.json'),dict(argv=safe,input_sha256=sha(text.encode())if text is not None else None,started_at=started,finished_at=now(),exit_code=r.returncode,stdout_sha256=sha(r.stdout.encode()),stderr_sha256=sha(r.stderr.encode())))
  if check and r.returncode:raise RuntimeError('command failed '+str(safe)+': '+r.stderr[-3000:])
  return r
 m.command=command
 def case(name,ok):
  result['checks'].append(dict(name=name,passed=bool(ok)));save(report/'result.json',result);print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(report,'successorapproval',result['target'])as t:
   _,provenance=m.platform_shape();save(report/'platform-provenance.json',provenance)
   t.sql(setup.decode(),label='fresh exact source-bound successful predecessor setup program')
   t.sql('alter role postgres nosuperuser;',user='supabase_admin',label='actual ordinary owner for additive closure and approval DDL')
   t.sql(closure.decode(),label='exact sealed closure prerequisite')
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1')))+",true);"
   def call(expr):return t.json('begin;'+auth+'select '+expr+';commit;')
   def denied(expr,error,name,pre=''):
    r=t.sql('begin;'+pre+auth+'select '+expr+';rollback;',check=False,label=name);case(name,r.returncode!=0 and error in r.stderr)
   a=t.json("select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where reference='CLOSURE-1';")
   b=t.json("select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where reference='CLOSURE-2';")
   h=call('public.admin_inspect_unarmed_receipt_closure_v1('+q(a['id'])+')')
   closed=call('public.admin_close_unarmed_receipt_v1('+','.join([q(uid()),q(a['id']),str(h['root_revision']),str(h['lineage_revision']),"'definitely_not_invoked'","'Synthetic owned closure preceding exact approval proof'"])+')')
   save(report/'observed-closure-prerequisite.json',closed)
   closed_a=t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(a['id'])+';')
   financial=[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_receipt_policy','content_evidence'),('collect_receipt_policy','decisions'),('collect_hybrid','sms_notification_outbox'),('collect_receipt_successors','original_closures')]
   cols=m.columns(t,financial);before=m.fingerprints(t,cols)
   query="select jsonb_agg(jsonb_build_object('oid',oid,'def',pg_get_functiondef(oid),'owner',proowner,'acl',proacl,'config',proconfig)order by oid)from pg_proc where pronamespace in('public'::regnamespace,'collect_receipt_policy'::regnamespace,'collect_hybrid'::regnamespace,'collect_security'::regnamespace,'collect_gateway_dispatch'::regnamespace,'collect_receipt_operations'::regnamespace,'collect_receipt_successors'::regnamespace);"
   functions=t.json(query)
   case('approval installer is actual NOSUPERUSER',t.scalar('select not rolsuper from pg_roles where rolname=current_user;')=='t')
   t.sql(body.decode(),label='exact additive immutable approval migration')
   after=t.json(query);by_oid={x['oid']:x for x in after}
   case('every predecessor function bytes OIDs owners ACL and configuration retained',all(by_oid.get(x['oid'])==x for x in functions))
   case('install preserves exact nonempty originals closures finance and retained v2 decision',before==m.fingerprints(t,cols))
   case('successor configuration remains inactive with no jobs attempts arms or extra budget table',t.scalar("select not enabled from collect_receipt_successors.configuration where singleton;")=='t'and t.scalar("select count(*)=0 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='collect_receipt_successors'and c.relname in('jobs','attempts','arms','reservations');")=='t')
   for role in ['anon','authenticated','service_role']:
    case(role+' has no direct successor evidence/helper access',t.scalar("select not has_schema_privilege("+q(role)+",'collect_receipt_successors','USAGE')and not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='collect_receipt_successors'and c.relkind='r'and(not c.relrowsecurity or has_table_privilege("+q(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE')));")=='t')
   inspect_expr=lambda o,action='retry_uninvoked',source=None:'public.admin_inspect_receipt_successor_v1('+','.join(map(q,[o['id'],action,source or o['snapshot_id']]))+')'
   inspect=lambda o,action='retry_uninvoked',source=None:call(inspect_expr(o,action,source))
   h=inspect(a);save(report/'observed-exact-preview-rw.json',h)
   shape={'contract_version','scope','action','outbox_id','source_snapshot_id','checked_at','sample_valid_until','status','can_approve','reason_code','preview','preview_sha256','configuration_enabled','financial_action','send_action','primary_receipt_retained','carrier_proof','delivery_proven'}
   case('actual exact closed inspection admits only irreversible unarmed retry',set(h)==shape and h['can_approve']and h['reason_code']=='retry_eligible'and h['preview']['proof_class']=='never_armed_closed'and not h['send_action']and not h['configuration_enabled'])
   case('preview contains backend text and recorded balance with masked recipient only',h['preview']['body']==a['message_body']and h['preview']['member_balance_recorded_rwf']==a['member_balance_rwf']and 'destination_e164'not in h['preview']and a['destination_e164']not in json.dumps(h)and h['preview']['recipient_masked'].endswith(a['destination_e164'][-3:]))
   case('untouched original cannot enter retry before irreversible closure',inspect(b)['reason_code']=='irreversible_closure_required'and not inspect(b)['can_approve'])
   case('wrong financial source is refused without arbitrary replacement',inspect(a,source=b['snapshot_id'])['reason_code']=='source_not_original')
   for action in ['approved_resend','correction']:
    x=inspect(a,action);case(action+' remains a nonauthorizing missing-proof refusal',x['reason_code']=='proof_class_unavailable'and not x['can_approve']and x['preview']is None)
   def approve_expr(o,h,request=None,reason='Synthetic exact current immutable retry approval',**overrides):
    v=dict(request=request or uid(),outbox=o['id'],action='retry_uninvoked',source=o['snapshot_id'],rr=h['preview']['root_revision'],lr=h['preview']['lineage_revision'],hash=h['preview_sha256'],deadline=h['sample_valid_until'],reason_code='definitely_not_invoked',reason=reason);v.update(overrides)
    return v['request'],'public.admin_approve_receipt_successor_v1('+','.join([q(v['request']),q(v['outbox']),q(v['action']),q(v['source']),str(v['rr']),str(v['lr']),q(v['hash']),q(v['deadline'])+'::timestamptz',q(v['reason_code']),q(v['reason'])])+')'
   _,expr=approve_expr(a,h,hash='a'*64);denied(expr,'receipt_successor_source_changed','modified text hash cannot be approved')
   _,expr=approve_expr(a,h,deadline='2020-01-01T00:00:00Z');denied(expr,'receipt_successor_preview_expired','expired sample never creates durable approval')
   _,expr=approve_expr(a,h,deadline='2099-01-01T00:00:00Z');denied(expr,'receipt_successor_preview_expired','caller cannot extend preview deadline')
   _,expr=approve_expr(a,h,reason_code='send_failed');denied(expr,'receipt_successor_input_invalid','send failure is never uninvoked proof')
   _,expr=approve_expr(a,h,reason='short');denied(expr,'receipt_successor_input_invalid','approval requires reason of at least eight characters')
   # Actual governed language change invalidates an old exact preview while the
   # original body remains immutable. New previews rederive approved rw/en/fr.
   def policy_update(patch):
    identity=q(json.dumps(dict(collection_id=m.GROUP)))+'::jsonb';revision=t.scalar("select revision from collect_security.runtime_control_heads where family='sms_receipt_policies'and identity="+identity+';')
    return call("public.admin_update_runtime_control_v1('sms_receipt_policies',"+identity+','+q(json.dumps(patch))+'::jsonb,'+revision+",'Synthetic successor source policy update')")
   policy_update(dict(receipt_language='en'))
   _,expr=approve_expr(a,h);denied(expr,'receipt_successor_source_changed','current language policy change fences old exact preview')
   previews={}
   for language in ['en','fr','rw']:
    if language!='en':policy_update(dict(receipt_language=language))
    x=inspect(a);previews[language]=x;save(report/'observed-exact-preview-'+language+'.json',x)
    expected=t.scalar('select collect_receipt_policy.render_v2('+str(a['amount_rwf'])+','+str(a['member_balance_rwf'])+',(select captured_at from collect_hybrid.momo_balance_snapshots where id='+q(a['snapshot_id'])+'),'+q(a['reference'])+','+q(language)+');')
    case(language+' preview rederives exact current governed language without original mutation',x['can_approve']and x['preview']['language']==language and x['preview']['body']==expected and t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(a['id'])+';')==closed_a)
   h=inspect(a)
   _,expr=approve_expr(a,h)
   denied(expr,'receipt_successor_source_changed','contact revision and destination change fence old preview',pre='update collect_hybrid.member_momo_identities set momo_number=\'+250788971009\',revision=revision+1 where member_id='+q(m.MEMBER)+';')
   disabled=t.json('begin;update collect_hybrid.sms_receipt_member_consents set enabled=false,revision=revision+1 where member_record_id='+q(m.MEMBER)+';'+auth+'select '+inspect_expr(a)+';rollback;')
   case('disabled consent yields no preview or authority',not disabled['can_approve']and disabled['reason_code']=='consent_missing'and disabled['preview']is None)
   request,expr=approve_expr(a,h);reservations_before=t.scalar('select count(*)from collect_receipt_operations.reservations;');receipt=call(expr);save(report/'observed-original-approval.json',receipt)
   case('exact paused review records one immutable approval and advances only lineage',receipt['lineage_revision']==h['preview']['lineage_revision']+1 and not receipt['send_action']and t.scalar('select count(*)=1 from collect_receipt_successors.approvals;')=='t'and t.scalar('select count(*)from collect_receipt_operations.reservations;')==reservations_before and before==m.fingerprints(t,cols))
   case('same original request returns exact retained approval',call(expr)==receipt)
   _,changed=approve_expr(a,h,request=request,reason='Different immutable approval input refused');denied(changed,'receipt_successor_request_conflict','changed reason cannot reuse approval UUID')
   lookup=call('public.admin_get_receipt_successor_request_v1('+q(request)+')');case('existing original-request lookup recovers exact approval',lookup['status']=='recorded'and lookup['receipt']==receipt)
   read=call('public.admin_get_receipt_successor_v1('+q(receipt['approval_id'])+')');save(report/'observed-approval-read.json',read)
   case('joined investigation retains exact preview and reason with no destination disclosure',read['approval']['status']=='pending'and read['approval']['preview']['body']==h['preview']['body']and read['approval']['reason']=='Synthetic exact current immutable retry approval'and a['destination_e164']not in json.dumps(read)and len(read['approval']['events'])==1)
   fresh=inspect(a);case('one pending approval prevents silent replacement',not fresh['can_approve']and fresh['reason_code']=='approval_pending'and fresh['preview_sha256']is None)
   _,again=approve_expr(a,h);denied(again,'receipt_successor_source_changed','old preview cannot admit concurrent successor intent')
   for table in ['approvals','approval_events']:
    for verb in ['update '+table+' set reason=\'Changed immutable intent\'','delete from '+table,'truncate '+table+' cascade']:
     sql=verb.replace(table,'collect_receipt_successors.'+table);r=t.sql(sql+';',check=False)
     case('owner '+verb.split()[0]+' cannot erase or alter '+table,r.returncode!=0 and 'receipt_successor_evidence_immutable'in r.stderr)
   revoked_request=uid();revexpr='public.admin_revoke_receipt_successor_v1('+','.join([q(revoked_request),q(receipt['approval_id']),str(receipt['lineage_revision']),"'Synthetic owner stops pending retry intent'"])+')';revoked=call(revexpr);save(report/'observed-original-revocation.json',revoked)
   case('owner revocation appends immutable event and advances lineage without original change',revoked['lineage_revision']==receipt['lineage_revision']+1 and call('public.admin_get_receipt_successor_v1('+q(receipt['approval_id'])+')')['approval']['status']=='revoked'and before==m.fingerprints(t,cols))
   case('revocation UUID exactly replays and is recoverable',call(revexpr)==revoked and call('public.admin_get_receipt_successor_request_v1('+q(revoked_request)+')')['receipt']==revoked)
   h=inspect(a);case('revoked approval admits fresh explicit review without changing prior preview',h['can_approve']and t.scalar('select count(*)=1 from collect_receipt_successors.approvals;')=='t')
   req2,e2=approve_expr(a,h);r2=call(e2)
   listed=call('public.admin_list_receipt_successors_v1('+q(a['id'])+',null,1)');nextpage=call('public.admin_list_receipt_successors_v1('+q(a['id'])+','+str(listed['next_after'])+',1)');save(report/'observed-lineage-pagination.json',dict(first=listed,next=nextpage))
   case('actual bounded keyset lineage retains revoked and pending approvals without duplicates',listed['has_more']and listed['items'][0]['approval_id']==receipt['approval_id']and nextpage['items'][0]['approval_id']==r2['approval_id']and not nextpage['has_more']and nextpage['next_after']is None)
   denied('public.admin_list_receipt_successors_v1('+q(a['id'])+',null,51)','receipt_successor_input_invalid','unbounded lineage limit refused')
   for permission in ['payments.read','notifications.read','system_health.read']:
    denied(inspect_expr(a),'42501:','read requires current '+permission,pre="delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner')and permission_name="+q(permission)+';')
   denied(e2,'42501:','approval replay still requires current manage permission',pre="delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner')and permission_name='notifications.manage';")
   denied('public.admin_get_receipt_successor_v1('+q(r2['approval_id'])+')','42501:','joined read requires current verified email owner',pre='update auth.users set email_confirmed_at=null where id='+q(m.UID)+';')
   denied('public.admin_get_receipt_successor_request_v1('+q(req2)+')','42501:','approval recovery refuses expired current session',pre='update auth.sessions set not_after=clock_timestamp()-interval \'1 second\'where id='+q(m.SID)+';')
   r=t.sql('begin isolation level repeatable read;'+auth+'select '+inspect_expr(a)+';rollback;',check=False);case('approval inspection refuses stale transaction snapshot',r.returncode!=0 and '40001:'in r.stderr)
   # Payment lock contention is actually observed and refused; it cannot make
   # preview admission silently skip the financial source.
   def observed(name,predicate,timeout=5):
    until=time.monotonic()+timeout
    while time.monotonic()<until:
     if t.scalar('select exists(select 1 from pg_stat_activity where application_name='+q(name)+'and '+predicate+');')=='t':return True
     time.sleep(.03)
    return False
   with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
    blocking=pool.submit(t.sql,"begin;select set_config('application_name','successor-preview-source-lock',true);select 1 from public.payments where id="+q(a['payment_id'])+'for update;select pg_sleep(2);commit;',label='actual competing financial source lock')
    waiting=observed('successor-preview-source-lock',"wait_event='PgSleep'")
    r=t.sql('begin;'+auth+'select '+inspect_expr(a)+';commit;',check=False,label='actual preview refuses source lock contention');block=blocking.result(timeout=8)
   save(report/'observed-source-contention.json',dict(blocker_seen=waiting,blocker_exit=block.returncode,inspection_exit=r.returncode,stderr=r.stderr))
   case('actual financial source contention is finite refusal with no authority',waiting and block.returncode==0 and r.returncode!=0 and 'receipt_successor_source_busy'in r.stderr)
   # Fresh root b gives independent approval admission. Real session expiry
   # while approval waits on policy must abort without owner request or intent.
   hb=call('public.admin_inspect_unarmed_receipt_closure_v1('+q(b['id'])+')');call('public.admin_close_unarmed_receipt_v1('+','.join([q(uid()),q(b['id']),str(hb['root_revision']),str(hb['lineage_revision']),"'definitely_not_invoked'","'Synthetic independent expiry approval root closure'"])+')')
   h=inspect(b);expired_request,expired_expr=approve_expr(b,h)
   t.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 second\'where id='+q(m.SID)+';')
   with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
    blocker=pool.submit(t.sql,"begin;select set_config('application_name','successor-approval-policy-lock',true);select 1 from collect_receipt_operations.policy where singleton for update;select pg_sleep(3);commit;",label='actual policy blocker for expiry fence')
    assert observed('successor-approval-policy-lock',"wait_event='PgSleep'")
    approving=pool.submit(t.sql,"begin;select set_config('application_name','successor-approval-expiring-owner',true);"+auth+'select '+expired_expr+';commit;',check=False,label='actual approval waits with naturally expiring owner')
    waiting=observed('successor-approval-expiring-owner',"wait_event_type='Lock'");br=blocker.result(timeout=8);ar=approving.result(timeout=8)
   save(report/'observed-post-wait-owner-expiry.json',dict(actual_wait=waiting,blocker_exit=br.returncode,approval_exit=ar.returncode,stderr=ar.stderr))
   case('post-wait natural owner expiry rolls back approval and original UUID receipt',waiting and br.returncode==0 and ar.returncode!=0 and '42501:'in ar.stderr and t.scalar('select not exists(select 1 from collect_receipt_successors.owner_requests where request_id='+q(expired_request)+')and not exists(select 1 from collect_receipt_successors.approvals where root_outbox_id='+q(b['id'])+');')=='t')
   t.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 hour\'where id='+q(m.SID)+';')
   # Audit evidence joins exact request/root/approval IDs without exposing text
   # or raw recipient. No financial action or sender budget is manufactured.
   audits=t.json("select jsonb_agg(jsonb_build_object('action',action,'entity_id',entity_id,'details',details)order by created_at,id)from public.audit_logs where action in('notification.successor.approved','notification.successor.revoked');")
   save(report/'observed-joined-audit.json',audits)
   case('joined immutable approvals and revocation have independent exact audit links',len(audits)==3 and all(x['entity_id']==a['id']and x['details']['request_id']in[request,revoked_request,req2]for x in audits)and a['destination_e164']not in json.dumps(audits))
   case('final state has exactly one retained primary per payment and unchanged shared budget',t.scalar('select count(*)=1 from collect_hybrid.sms_notification_outbox where payment_id='+q(a['payment_id'])+';')=='t'and t.scalar('select count(*)from collect_receipt_operations.reservations;')==reservations_before and t.scalar('select not enabled from collect_receipt_successors.configuration;')=='t')
   result['status']='passed';result['finished_at']=now();save(report/'result.json',result)
 except BaseException as e:
  result['status']='failed';result['error']=type(e).__name__+': '+str(e);result['finished_at']=now();save(report/'result.json',result);raise
 finally:
  result['source_unchanged']=all(sha((ROOT/p).read_bytes())==h for p,h in bindings.items())and migration.read_bytes()==body and pathlib.Path(__file__).read_bytes()==runner
  result['command_count']=counter;save(report/'result.json',result)
if __name__=='__main__':main()
