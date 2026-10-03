#!/usr/bin/env python3
"""Focused receipt content2 proof on a private, network-none synthetic target."""
import pathlib,json,hashlib,types,datetime,sys
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06')
REPORT=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'.cache/receipt-financial-policy-attempt1'
MIGRATION=ROOT/'supabase/migrations/20261001100000_receipt_financial_policy.sql'
def sha(b):return hashlib.sha256(b).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
def main():
 REPORT.mkdir();inputs=REPORT/'inputs';inputs.mkdir();(inputs/'migrations').mkdir()
 helper=(SOURCE/'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes();(inputs/'executed-helper.py').write_bytes(helper)
 runner=pathlib.Path(__file__).read_bytes();(inputs/'executed-runner.py').write_bytes(runner)
 baseline=(ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes();(inputs/'row-free-platform.sql').write_bytes(baseline)
 marker=(SOURCE/'.collect-release-candidate.json').read_bytes();manifest=json.loads(marker)
 assert sha(marker)=='3dde2f704488a7a18d7d9f916f2451d76a8662bb79619b788d792706d11ba42f'
 items=[]
 for p in sorted((SOURCE/'supabase/migrations').glob('*.sql')):
  b=p.read_bytes();assert sha(b)==manifest['source_files'][str(p.relative_to(SOURCE))]['sha256'];(inputs/'migrations'/p.name).write_bytes(b)
  version,name=p.stem.split('_',1);items.append(dict(version=version,name=name,path=str(p.relative_to(SOURCE)),sha256=sha(b),body=b.decode()))
 assert len(items)==175
 sql=MIGRATION.read_bytes();(inputs/MIGRATION.name).write_bytes(sql)
 result=dict(financial_finality_fixture_execution='Local installer with service-role JWT claims executes current trusted confirmation function; service_role direct execute is not granted or broadened',scope='focused synthetic content2 feature UAT with exact frozen175 prerequisite bootstrap; not whole release acceptance',started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),source06_manifest_sha256=sha(marker),migration_sha256=sha(sql),migration_path=str(MIGRATION),helper_sha256=sha(helper),runner_sha256=sha(runner),helper_captured_before_import=True,baseline_sha256=sha(baseline),checks=[],target={})
 save(REPORT/'execution-binding.json',{k:v for k,v in result.items()if k not in('checks','target')})
 m=types.ModuleType('retained_helper');m.__file__=str(inputs/'executed-helper.py');exec(compile(helper,m.__file__,'exec'),m.__dict__);m.ROOT=SOURCE;m.BASELINE=inputs/'row-free-platform.sql'
 q=m.quoted
 def case(name,ok):
  result['checks'].append(dict(name=name,pass_=bool(ok)));print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 try:
  with m.Target(REPORT,'private',result['target'])as t:
   platform,_=m.platform_shape();t.sql(platform,label='captured row-free Auth/Storage platform shape')
   m.apply(t,items[:124],result['target']);m.seed_populated(t,result['target'],case);m.apply(t,items[124:],result['target'])
   claims=json.dumps(dict(sub=m.UID,session_id=m.SID,role='authenticated',aal='aal1'))
   auth="set local role authenticated;select set_config('request.jwt.claims',"+q(claims)+",true);"
   def call(expression,service=False):
    prefix="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"if service else auth
    r=t.sql('begin;'+prefix+'select '+expression+';commit;');lines=r.stdout.strip().splitlines();return json.loads(lines[-1])
   def fail(expression,code,message,service=False):
    prefix="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"if service else auth
    r=t.sql('begin;'+prefix+'select '+expression+';rollback;',check=False);case(message,r.returncode!=0 and code in r.stderr and message in r.stderr)
   t.sql("begin;update auth.users set email='policy-owner@example.test',email_confirmed_at=clock_timestamp()where id="+q(m.UID)+";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values("+q(m.UID)+",'policy-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic delegated policy UAT owner');commit;")
   def flag(on):
    rev=t.scalar("select revision from collect_security.runtime_control_heads where family='feature_flags'and identity='{\"key\":\"hybrid_sms_notifications\"}'::jsonb;")
    return call("public.admin_update_runtime_control_v1('feature_flags','{\"key\":\"hybrid_sms_notifications\"}'::jsonb,'{\"enabled\":"+str(on).lower()+"}'::jsonb,"+(rev or'0')+",'Synthetic offline dispatch boundary check')")
   legacy=t.json('select jsonb_agg(to_jsonb(o)order by payment_id)from collect_hybrid.sms_notification_outbox o;')
   legacy_queue=legacy[0]['id'];legacy_arm=legacy[1]['id'];flag(True)
   claim=call('public.collect_claim_receipt('+q(m.UID)+','+q(legacy_arm)+",'policy-uat','99890000-0000-4000-8000-000000000001')",True)
   armrow=t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(legacy_arm)+';')
   confirmation='99890000-0000-4000-8000-000000000002'
   call('public.collect_confirm_receipt('+','.join([q(m.UID),q(legacy_arm),q(claim['claim_token']),str(claim['fence_version']),str(armrow['destination_revision']),q(armrow['body_sha256']),q(confirmation)])+')',True)
   armed=call('public.collect_record_send_start('+','.join([q(m.UID),q(legacy_arm),q(claim['claim_token']),str(claim['fence_version']),q(confirmation)])+')',True);flag(False)
   tables=[('public','payments'),('collect_hybrid','momo_journal_entries'),('collect_hybrid','momo_journal_lines'),('collect_hybrid','momo_balance_snapshots'),('collect_hybrid','member_balances'),('collect_hybrid','collection_balances'),('collect_hybrid','sms_notification_outbox'),('collect_hybrid','sms_notification_attempts'),('collect_hybrid','sms_notification_confirmations')]
   cols=m.columns(t,tables);before=m.fingerprints(t,cols);t.sql(sql.decode(),label='install exact new content policy migration')
   case('install preserves nonempty finance legacy payload queue and prior armed evidence',m.fingerprints(t,cols)==before)
   read=call('public.admin_receipt_content_policy_v1()');save(REPORT/'observed-policy.json',read)
   case('delegated content2 separate from collection config1 without send approval',read['content_policy_version']==2 and read['collection_configuration_version']==1 and not read['dispatch_authority_created']and not read['provider_settlement_verified'])
   outputs=t.json("select jsonb_object_agg(lang,collect_receipt_policy.render_v2(1000,12000,'2026-10-01T08:59:00Z','SYNTHETIC-REF',lang))from unnest(array['rw','en','fr'])lang;");save(REPORT/'observed-language-copy.json',outputs)
   case('three explicit languages member-only date and no received or group-total claim',all('2026-10-01 10:59 CAT'in v and '12,000'in v and '95,000'not in v for v in outputs.values())and 'Twakiriye'not in outputs['rw'])
   case('whole bigint upper bound rendered without hash marks',t.scalar("select collect_receipt_policy.render_v2(9223372036854775807,9223372036854775807,now(),'MAX','en')not like '%#%';")=='t')
   for expr in ["(0,0,now(),'REF','rw')","(1,-1,now(),'REF','rw')","(1,0,'infinity','REF','rw')","(1,0,now(),E'bad\\nref','rw')","(1,0,now(),'REF','xx')"]:
    r=t.sql('select collect_receipt_policy.render_v2'+expr+';',check=False);case('renderer refuses '+expr,r.returncode!=0 and'22023'in r.stderr)
   def post(n,amount=100,parsed='null'):
    pid='99890000-0000-4000-8000-%012d'%(100000+n);ref='POLICY-'+str(n);wh=sha(b'+250788971001')
    if n==1:
     raw='99890000-0000-4000-8000-000000060001';event='99890000-0000-4000-8000-000000070001';parsed=q(event)
     t.sql('begin;insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status,received_at_device)values('+','.join([q(raw),q(m.GROUP),q(m.UID),"'M-Money'","'Synthetic new content financial observation'","encode(extensions.digest('Synthetic new content financial observation','sha256'),'hex')",q(wh),"'parsed'",'clock_timestamp()'])+');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)values('+','.join([q(event),q(raw),q(m.GROUP),q(m.UID),'true',"'mtn_momo'","'RWF'","'incoming'",q(wh),str(amount),q(ref),"'unallocated'","'Synthetic content payer'"])+');commit;',label='independent new actual Rwanda raw parsed receipt reader fixture')
    r=t.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)values("+','.join([q(pid),parsed,q(m.GROUP),q(m.MEMBER),q(m.UID),q(wh),str(amount),q(ref),"'mtn_momo'","'manual_admin'","'review'",'null'])+");select public.confirm_provider_payment("+','.join([q(pid),"'mtn_momo'",q(ref),q('SYNTHETIC-CONF-'+str(n)),q(wh),str(amount),'clock_timestamp()',"repeat('c',64)"])+");commit;",label='canonical synthetic new payment '+str(n));return pid
   pid=post(1)
   job=t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='+q(pid)+';');save(REPORT/'synthetic-v2-receipt.json',job)
   case('paused actual posting enqueues safe v2 rw and snapshot proof',job['template_version']==2 and job['state']=='queued'and'CAT:'in job['message_body']and 'Balance y'not in job['message_body']and t.scalar('select collect_receipt_policy.content_is_valid(o)from collect_hybrid.sms_notification_outbox o where id='+q(job['id'])+';')=='t')
   case('queue body hash is exact backend UTF8 digest',sha(job['message_body'].encode())==job['body_sha256'])
   for account,direction in [('momo_receiving_asset:RWF','debit'),('member_savings_liability:RWF','credit')]:
    probe=t.sql('begin;alter table collect_hybrid.momo_journal_lines drop constraint momo_journal_lines_journal_entry_id_account_code_direction_key;set local session_replication_role=replica;update collect_hybrid.momo_journal_lines set account_code='+q(account)+',direction='+q(direction)+'where journal_entry_id=(select journal_entry_id from collect_hybrid.momo_balance_snapshots where payment_id='+q(pid)+');set local session_replication_role=origin;select not collect_receipt_policy.snapshot_is_eligible(s)and collect_receipt_actions.ineligible_reason(o)=\'source_evidence_invalid\'from collect_hybrid.momo_balance_snapshots s join collect_hybrid.sms_notification_outbox o on o.snapshot_id=s.id where s.payment_id='+q(pid)+';rollback;',label='installer-only constraint-free two same-side corrupt-line rollback fixture; no API can perform this')
    case('actual eligibility and cancellation reject two '+direction+' lines',probe.stdout.strip().splitlines()[-1]=='t')
   case('balanced original pair restored after corrupt-fixture rollback',t.scalar('select collect_receipt_policy.snapshot_is_eligible(s)from collect_hybrid.momo_balance_snapshots s where payment_id='+q(pid)+';')=='t')

   case('snapshot member balance is950 not provider settlement attestation',job['member_balance_rwf']==950)
   inspect=call('public.admin_inspect_unstarted_receipt_v1('+q(job['id'])+')');case('v2 conservative cancellation remains eligible',inspect['receipt']['can_cancel'])
   inspection=call('public.admin_get_collect_investigation_v1(\'receipt\','+q(job['id'])+')');save(REPORT/'observed-investigation-v2.json',inspection)
   case('real Admin preview version2 dated member-only opaque reference',inspection['receipt']['template_version']==2 and'CAT:'in inspection['receipt']['masked_snapshot_preview']and'POLICY-1'not in inspection['receipt']['masked_snapshot_preview'])
   detail=call('public.admin_get_hybrid_sms_receipt('+q(job['id'])+')');save(REPORT/'observed-detail-v2.json',detail)
   # Public signatures are captured source contracts; do not guess list paging.
   listargs=t.scalar("select pg_get_function_arguments('public.admin_list_hybrid_sms_receipts'::regproc);");result['list_rpc_arguments']=listargs
   listing=call("public.admin_list_hybrid_sms_receipts(null,null,25,0,'created_at_desc')");save(REPORT/'observed-list-v2.json',listing)
   repeated=t.sql("begin;select collect_hybrid.post_momo_receipt("+q(pid)+");commit;");case('duplicate financial replay retains one lifetime primary',t.scalar('select count(*)=1 from collect_hybrid.sms_notification_outbox where payment_id='+q(pid)+';')=='t')
   fail('public.collect_claim_receipt('+q(m.UID)+','+q(job['id'])+",'policy-uat','99890000-0000-4000-8000-000000000003')",'55000','receipt_dispatch_paused',True)
   flag(True);legacy_before=t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(legacy_queue)+';')
   fail('public.collect_claim_receipt('+q(m.UID)+','+q(legacy_queue)+",'policy-uat','99890000-0000-4000-8000-000000000004')",'55000','CONTENT_POLICY_REVIEW_REQUIRED',True)
   case('legacy refusal leaves original queued row and no claim request',t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(legacy_queue)+';')==legacy_before and t.scalar("select not exists(select 1 from collect_hybrid.sms_notification_claim_requests where request_id='99890000-0000-4000-8000-000000000004');")=='t')
   claim2=call('public.collect_claim_receipt('+q(m.UID)+','+q(job['id'])+",'policy-uat','99890000-0000-4000-8000-000000000005')",True)
   claimed=call('public.collect_get_claimed_receipt('+','.join([q(m.UID),q(job['id']),q(claim2['claim_token']),str(claim2['fence_version'])])+')',True)
   case('v2 existing assisted claim returns exact original body and hash',claimed['message_body']==job['message_body']and claimed['template_version']==2)
   cf2='99890000-0000-4000-8000-000000000006';call('public.collect_confirm_receipt('+','.join([q(m.UID),q(job['id']),q(claim2['claim_token']),str(claim2['fence_version']),str(job['destination_revision']),q(job['body_sha256']),q(cf2)])+')',True)
   flag(False)
   fail('public.collect_record_send_start('+','.join([q(m.UID),q(job['id']),q(claim2['claim_token']),str(claim2['fence_version']),q(cf2)])+')','55000','receipt_dispatch_paused',True)
   outcome=call('public.collect_record_observed_outcome('+','.join([q(m.UID),q(armed['attempt_id']),"'uncertain'","'Synthetic earlier carrier handoff evidence'","'No real SMS was sent in this offline fixture'"])+')',True)
   case('prior armed v1 unknown evidence still reconciles while paused',outcome['state']=='uncertain')
   save(REPORT/'observed-prior-v1-unknown.json',outcome)
   replay=call('public.collect_record_observed_outcome('+','.join([q(m.UID),q(armed['attempt_id']),"'uncertain'","'Synthetic earlier carrier handoff evidence'","'No real SMS was sent in this offline fixture'"])+')',True)
   case('prior legacy unknown reconciliation replay unchanged',replay['replay']is True and replay['state']=='uncertain')
   flag(True)
   started=call('public.collect_record_send_start('+','.join([q(m.UID),q(job['id']),q(claim2['claim_token']),str(claim2['fence_version']),q(cf2)])+')',True)
   case('content2 exact confirmed authority can record local pre-send boundary',started['state']=='send_started')
   flag(False)
   unknown2=call('public.collect_record_observed_outcome('+','.join([q(m.UID),q(started['attempt_id']),"'uncertain'","'Synthetic v2 unknown outcome only'","'No SmsManager invocation or provider call occurred'"])+')',True)
   case('v2 unknown records evidence without queued retry',unknown2['state']=='uncertain'and t.scalar('select state=\'uncertain\'from collect_hybrid.sms_notification_outbox where id='+q(job['id'])+';')=='t')

   p2=post(2)
   case('second v2 remains queued while paused',t.scalar('select state=\'queued\'and template_version=2 from collect_hybrid.sms_notification_outbox where payment_id='+q(p2)+';')=='t')
   # Test current eligibility changes through real governed setters inside rollback,
   # with real canonical financial posts; fixture writes never touch production.
   for family,identity,patch in [('sms_receipt_member_consents',{'member_record_id':m.MEMBER},{'enabled':False}),('sms_receipt_policies',{'collection_id':m.GROUP},{'enabled':False})]:
    ident=json.dumps(identity);pat=json.dumps(patch);rev=t.scalar('select revision from collect_security.runtime_control_heads where family='+q(family)+'and identity='+q(ident)+'::jsonb;')
    t.sql('begin;'+auth+"select public.admin_update_runtime_control_v1("+q(family)+','+q(ident)+'::jsonb,'+q(pat)+'::jsonb,'+rev+",'Synthetic current eligibility refusal');commit;")
    pn=post(3 if family.endswith('consents') else 4);case('financial posting survives with no SMS when '+family+' disabled',t.scalar('select status=\'posted\'and not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id=p.id)from public.payments p where id='+q(pn)+';')=='t')
    rev=t.scalar('select revision from collect_security.runtime_control_heads where family='+q(family)+'and identity='+q(ident)+'::jsonb;')
    t.sql('begin;'+auth+"select public.admin_update_runtime_control_v1("+q(family)+','+q(ident)+"::jsonb,'{\"enabled\":true}'::jsonb,"+rev+",'Synthetic eligibility fixture restore');commit;")
   t.sql('begin;update collect_hybrid.member_records set linked_user_id=null where linked_user_id='+q(m.OTHER)+';update collect_hybrid.member_records set linked_user_id='+q(m.OTHER)+'where id='+q(m.MEMBER)+';commit;');pn=post(5);case('app-linked financial commit remains receipt-suppressed',t.scalar('select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='+q(pn)+');')=='t')
   # Linking is deliberate permanent evidence; no automatic unlink/backfill.
   case('historical missing primaries were not automatically backfilled',t.scalar("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='99780000-0000-4000-8000-000000050003');")=='t')
   for role in ['anon','authenticated','service_role']:
    case(role+' has no direct new private content access',t.scalar("select not has_schema_privilege("+q(role)+",'collect_receipt_policy','USAGE')and not has_table_privilege("+q(role)+",'collect_receipt_policy.content_evidence','SELECT');")=='t')
   case('only authenticated has policy read RPC execute',t.scalar("select has_function_privilege('authenticated','public.admin_receipt_content_policy_v1()','EXECUTE')and not has_function_privilege('anon','public.admin_receipt_content_policy_v1()','EXECUTE')and not has_function_privilege('service_role','public.admin_receipt_content_policy_v1()','EXECUTE');")=='t')
   for table in ['decisions','content_evidence']:
    r=t.sql('delete from collect_receipt_policy.'+table+';',check=False);case('immutable '+table+' retained',r.returncode!=0 and'55000'in r.stderr and'receipt_content_evidence_immutable'in r.stderr)
   case('source contact body and member snapshot of original v2 remain immutable despite later balance changes',t.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(job['id'])+';')['message_body']==job['message_body'])
   case('canonical payment events remain durable independently of SMS suppression',t.scalar("select count(*)=5 from collect_hybrid.receipt_business_events where source_kind='payment'and source_id in(select id from public.payments where transaction_id like 'POLICY-%');")=='t')
   save(REPORT/'final-financial-projection.json',t.json("select jsonb_build_object('payments',(select jsonb_agg(to_jsonb(p)order by id)from public.payments p),'snapshots',(select jsonb_agg(to_jsonb(s)order by id)from collect_hybrid.momo_balance_snapshots s),'journals',(select jsonb_agg(to_jsonb(j)order by id)from collect_hybrid.momo_journal_entries j),'lines',(select jsonb_agg(to_jsonb(l)order by id)from collect_hybrid.momo_journal_lines l));"))
   case('every canonical financial journal remains exactly balanced two lines',t.scalar("select bool_and(n=2 and debit=credit)from(select journal_entry_id,count(*)n,sum(amount_rwf)filter(where direction='debit')debit,sum(amount_rwf)filter(where direction='credit')credit from collect_hybrid.momo_journal_lines group by journal_entry_id)x;")=='t')
  result['status']='pass'
 except BaseException as e:
  result['status']='failed';result['error']=str(e);raise
 finally:
  result['source_migration_unchanged']=sha(MIGRATION.read_bytes())==result['migration_sha256'];result['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save(REPORT/'result.json',result)
if __name__=='__main__':main()
