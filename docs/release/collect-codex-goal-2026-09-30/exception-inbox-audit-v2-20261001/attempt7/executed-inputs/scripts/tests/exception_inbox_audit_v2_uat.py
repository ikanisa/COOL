#!/usr/bin/env python3
"""Focused additive exception audit/inbox proof; no hosted installer acceptance.

Captures helper, row-free schema153 and selected SQL before imports/execution.
Only an owned network-none disposable synthetic target is accepted. Local
fixture owner/claims normalization is explicit and is not production ACL parity.
"""
import argparse, datetime, hashlib, json, pathlib, re, sys, time, types, uuid
ROOT=pathlib.Path(__file__).resolve().parents[2]
FEATURE='supabase/migrations/20261001200000_exception_inbox_audit_v2.sql'
STAGES=['20260930213000_operator_email_auth.sql','20260930220527_operator_email_cutover_guard.sql',
 '20260930230100_receipt_backlog_events.sql','20260930230200_admin_receipt_overview.sql',
 '20260930230300_admin_transaction_lifecycle.sql','20260930211605_android_gateway_identity.sql',
 '20261001000100_operational_exception_inbox.sql','20261001000300_admin_exception_reads.sql',
 '20261001000400_receipt_supervisor_identity.sql','20261001000519_safe_unstarted_receipt_cancel.sql',
 '20261001001457_joined_operator_audit.sql','20261001003338_unattended_operating_policy.sql',
 '20261001004651_receipt_cancel_audit_actor.sql','20261001100000_receipt_financial_policy.sql',
 '20261001110000_receipt_operational_authority.sql','20261001120000_operational_exception_lifecycle.sql',
 '20261001140000_receipt_deferral_exceptions.sql','20261001190000_exception_followup_v2.sql']
HELPERS=['shadow_supervisor_uat','receipt_backlog_events_uat','collect_admin_combined_upgrade_uat','collect_current_release_upgrade_uat']
EMAIL='99790000-0000-4000-8000-000000000001';SID='99790000-0000-4000-8000-000000010001'
OTHER='99880000-0000-4000-8000-000000000001';OTHER_SID='99880000-0000-4000-8000-000000010001'
sha=lambda b:hashlib.sha256(b).hexdigest()
q=lambda x:"'"+str(x).replace("'","''")+"'"
ident=lambda:str(uuid.uuid4())
def moment(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report-dir',required=True,type=pathlib.Path);args=p.parse_args()
 report=args.report_dir.resolve();assert not report.exists() and str(report).startswith(str(ROOT/'docs/release')+'/');report.mkdir(parents=True)
 result=dict(kind='schema153_additive_exception_inbox_audit_v2',status='running',cases=[],target={},hosted_called=False,source_rows_copied=False,device_used=False,provider_called=False,full_candidate_tested=False,fixture_limitations=['Local installer postgres superuser normalization','Owner-normalized retained schema153 plus captured19-file subset','Mock cron catalog shape only; no net/Vault/scheduler invocation','SET LOCAL API roles and synthetic JWT claims; no Auth service/signature verification','Current185 installer blocker and whole187 candidate acceptance remain outside scope'])
 save=lambda:(report/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 paths=['supabase/migrations/'+s for s in STAGES]+[FEATURE]+['scripts/tests/'+h+'.py'for h in HELPERS]+[str(pathlib.Path(__file__).relative_to(ROOT))]
 bodies={n:(ROOT/n).read_bytes()for n in paths};base=ROOT/'.cache/receipt-foundation-attempt8';baseline={n:(base/n).read_bytes()for n in ['schema-only.sql','api-acl.sql']}
 captured=report/'executed-inputs';captured.mkdir()
 for n,b in bodies.items():x=captured/n;x.parent.mkdir(parents=True,exist_ok=True);x.write_bytes(b)
 for n,b in baseline.items():(captured/n).write_bytes(b)
 result['source_sha256']={n:sha(b)for n,b in bodies.items()};result['baseline_sha256']={n:sha(b)for n,b in baseline.items()};result['cli_provenance']={'path':'/Volumes/PRO-G40/Development/User-Developer/supabase_2_84_2_codex/supabase','version':'2.84.2','generated':'20261001151541_exception_inbox_audit_v2.sql','published':'20261001200000_exception_inbox_audit_v2.sql'};save()
 mods={}
 for h in HELPERS:
  m=types.ModuleType(h);m.__file__=str(ROOT/'scripts/tests'/f'{h}.py');sys.modules[h]=m;exec(compile(bodies['scripts/tests/'+h+'.py'],m.__file__,'exec'),m.__dict__);mods[h]=m
 u=mods[HELPERS[0]];f=mods[HELPERS[1]];fixture=mods[HELPERS[2]];private=mods[HELPERS[3]]
 assert sha(baseline['schema-only.sql'])==fixture.DUMP_HASH and sha(baseline['api-acl.sql'])==fixture.ACL_HASH
 result['tools']={'python':sys.version,'docker_path':u.DOCKER,'docker_sha256':sha(pathlib.Path(u.DOCKER).read_bytes()),'image':private.IMAGE,'image_id':private.IMAGE_ID,'cli_sha256':sha(pathlib.Path(result['cli_provenance']['path']).read_bytes())}
 def case(name,ok):
  result['cases'].append(dict(name=name,status='pass'if ok else'failed'));save();print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name)
 def retain(name,data):(report/name).write_text(json.dumps(data,indent=2)+'\n')
 db='exception_history_'+uuid.uuid4().hex[:12];target=None;sessions=[]
 sql=lambda s:u.psql(db,s).stdout.strip();owner=lambda s:u.call(db,s,EMAIL,SID);other=lambda s:u.call(db,s,OTHER,OTHER_SID)
 service_auth="set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
 svc=lambda s:json.loads(sql('begin;'+service_auth+s+';commit;').splitlines()[-1]);fail=lambda s,c,reason=None:u.expected_error(db,s,c,reason,uid=EMAIL,sid=SID)
 finance=lambda:{k:v for k,v in f.business_fingerprint(db).items()if k not in('raw_payment_sms','parsed_payment_events')}
 def raw():
  rid=ident();sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values(%s,%s,%s,'M-Money','Synthetic parser failure',%s,repeat('a',64),'failed');"%(q(rid),q(f.GROUP),q(u.UID),q(sha(rid.encode()))))
  return json.loads(sql('select to_jsonb(e)from collect_ops.exceptions e where source_id='+q(rid)+';'))
 def action(e,rev,op,assignee=EMAIL,request=None):
  return owner('select public.admin_act_exception_workflow_v2(%s,%s,%d,%d,%s,%s,%s,%s,clock_timestamp()+interval \'90 seconds\');'%(q(request or ident()),q(e['id']),e['revision'],rev,q(op),q(assignee)if op=='assign'else'null',"clock_timestamp()+interval '2 hours'"if op=='assign'else'null',q('source_rechecked'if op=='resolve'else'owner_review_required')))
 def audit(e,limit=20,cursor=None):
  return owner('select public.admin_get_exception_entity_audit_v2(%s,%d,%s,%s);'%(q(e['id']),limit,q(cursor['recorded_at'])if cursor else'null',q(cursor['event_id'])if cursor else'null'))
 def inbox(who=owner,limit=20,cursor=None):
  return who('select public.admin_list_exception_escalation_inbox_v2(%d,%s,%s);'%(limit,q(cursor['delivered_at'])if cursor else'null',q(cursor['escalation_id'])if cursor else'null'))
 def shape(snapshot,audit_mode):
  assert snapshot['contract_version']==2 and moment(snapshot['sample_valid_until'])-moment(snapshot['checked_at'])==datetime.timedelta(seconds=60)
  rows=snapshot['rows'];assert len(rows)<=snapshot['limit']
  first='recorded_at'if audit_mode else'delivered_at';second='event_id'if audit_mode else'escalation_id'
  keys=[(moment(r[first]),r[second])for r in rows];assert keys==sorted(set(keys),reverse=True)and all(k[0]<=moment(snapshot['checked_at'])for k in keys)
  if snapshot['next_cursor']:assert len(rows)==snapshot['limit']and snapshot['next_cursor']=={first:rows[-1][first],second:rows[-1][second]}
  if audit_mode:
   assert set(snapshot)=={'contract_version','scope','entity_kind','entity_id','status','checked_at','sample_valid_until','limit','history_complete','financial_action','send_action','rows','next_cursor'}
   assert all(set(r)=={'event_id','source','source_record_id','action','recorded_at','actor_kind','actor_id','request_id','revision','workflow_revision','escalation_id','reason_code','origin','assignee_id','due_at'}for r in rows)
  else:
   assert set(snapshot)=={'contract_version','channel','scope','recipient_id','checked_at','sample_valid_until','limit','rows','next_cursor'}
   assert all(set(r)=={'escalation_id','exception_id','source_revision','reason_code','source_active','current_source_revision','delivered_at','read_at'}for r in rows)
  return True
 try:
  target=private.Target(report,'exception_history',result['target']);target.__enter__();u.CONTAINER=target.name;u.SQL_LOG=report/'queries.log';u.CONCURRENCY_LOG=report/'concurrency.log';f.RAW_QUERY_LOG=report/'queries.sql'
  u.psql('postgres','create database '+db+' template template0;')
  sql('create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+baseline['schema-only.sql'].decode()+baseline['api-acl.sql'].decode())
  f.seed(db);sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+f.service(f.payment_sql('99880000-0000-4000-8000-000000050001',amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values(%s,%s,'+250788971001',repeat('a',64),'mtn_momo');"%(q(f.GROUP),q(u.UID)))
  sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('audit.read','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%q(f.ROLE))
  initial=finance()
  for name in STAGES:
   path='supabase/migrations/'+name;r=u.psql(db,bodies[path].decode(),False);(report/(name+'.install.log')).write_text(r.stdout+r.stderr);case(name+' additive install preserves existing nonempty financial evidence',r.returncode==0 and finance()==initial)
  sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('audit.read','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%q(f.ROLE))
  for uid,email in[(EMAIL,'info@ikanisa.com'),(OTHER,'second-owner@example.invalid')]:
   sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values(%s,'authenticated','authenticated',%s,clock_timestamp(),'{}','{}');"%(q(uid),q(email)))
   if uid==EMAIL:svc('select public.bootstrap_collect_email_operator_v1('+q(uid)+');')
   else:sql("insert into collect_admin_access.email_approvals(user_id,email,reason,approved_at)values(%s,%s,'Synthetic approved owner',clock_timestamp()-interval '2 minutes');insert into public.admin_user_roles(user_id,role_id,reason,created_at)values(%s,%s,'Synthetic current owner',clock_timestamp()-interval '1 minute');"%(q(uid),q(email),q(uid),q(f.ROLE)))
  for uid,sid in[(EMAIL,SID),(OTHER,OTHER_SID)]:sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');"%(q(sid),q(uid)))
  historical=raw();action(historical,0,'assign');historical_esc=action(historical,1,'escalate')['escalation_id'];svc('select public.process_exception_escalations_v1(20);');owner('select public.admin_read_exception_escalation_v1('+q(historical_esc)+');')
  definitions=sql("select jsonb_object_agg(p.oid::regprocedure::text,encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'))from pg_proc p where p.proname in('admin_get_operator_entity_audit_v1','admin_list_exception_escalation_inbox_v1','admin_read_exception_escalation_v1','admin_act_exception_workflow_v1','process_exception_escalations_v1');")
  preserved_tables=['exception_escalations','exception_inbox_deliveries','exception_inbox_reads','exception_workflow_requests','exception_actions']
  evidence_before={t:sql('select md5(coalesce(jsonb_agg(to_jsonb(x)order by to_jsonb(x)::text)::text,\'[]\'))from collect_ops.'+t+' x;')for t in preserved_tables}
  prior_fin=finance();r=u.psql(db,bodies[FEATURE].decode(),False);(report/'feature.install.log').write_text(r.stdout+r.stderr);case('new feature installs without changing financial or prior lifecycle evidence',r.returncode==0 and finance()==prior_fin and evidence_before=={t:sql('select md5(coalesce(jsonb_agg(to_jsonb(x)order by to_jsonb(x)::text)::text,\'[]\'))from collect_ops.'+t+' x;')for t in preserved_tables})
  case('all five original v1 function definitions remain exact',definitions==sql("select jsonb_object_agg(p.oid::regprocedure::text,encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'))from pg_proc p where p.proname in('admin_get_operator_entity_audit_v1','admin_list_exception_escalation_inbox_v1','admin_read_exception_escalation_v1','admin_act_exception_workflow_v1','process_exception_escalations_v1');"));result['original_function_definition_hashes']=json.loads(definitions)
  past=audit(historical,25);retain('observed-audit-retained.json',past);case('backfill exposes only three retained actual source phases with unknown executing identity',shape(past,True)and{r['action']for r in past['rows']if r['origin']=='retained_source'}=={'exception.escalation.queued','exception.escalation.delivered','exception.escalation.opened'}and all(r['actor_kind']=='unknown'and r['actor_id']is None and r['request_id']is None for r in past['rows']if r['origin']=='retained_source'))
  item=raw();shared=ident();review=owner('select public.admin_act_operational_exception_v1(%s,%s,%d,\'acknowledge\',\'review_started\');'%(q(shared),q(item['id']),item['revision']));assign=action(item,0,'assign',request=shared);escalate=action(item,1,'escalate');svc('select public.process_exception_escalations_v1(20);')
  opened=owner('select public.admin_read_exception_escalation_v2('+q(escalate['escalation_id'])+');');retain('observed-opened-ack.json',opened)
  case('opening v2 exact four-key immutable ACK does not close source',set(opened)=={'contract_version','escalation_id','read_at','source_resolved'}and opened['contract_version']==2 and not opened['source_resolved']and owner('select public.admin_read_exception_escalation_v2('+q(escalate['escalation_id'])+');')==opened)
  full=audit(item,25);retain('observed-audit-complete.json',full);case('joined audit includes old review assignment deadline escalation and all three lifecycle facts',shape(full,True)and len(full['rows'])==6 and{r['action']for r in full['rows']}=={'exception.acknowledge','exception.workflow.assign','exception.workflow.escalate','exception.escalation.queued','exception.escalation.delivered','exception.escalation.opened'})
  same=[r for r in full['rows']if r['request_id']==shared];case('cross-namespace same request UUID produces two distinct stable event IDs',len(same)==2 and len({r['event_id']for r in same})==2 and all(r['source_record_id']==shared for r in same))
  ar=next(r for r in full['rows']if r['action']=='exception.workflow.assign');case('original assignment auditable opaque assignee and exact approved deadline remain source-derived',ar['assignee_id']==EMAIL and ar['due_at']is not None and ar['workflow_revision']==1 and ar['revision']==item['revision'])
  case('service delivery actor is distinguishable and cannot impersonate an executing human',all(r['actor_kind']=='service'and r['actor_id']is None and r['request_id']is None for r in full['rows']if r['action']=='exception.escalation.delivered'))
  first=audit(item,2);last=audit(item,25,first['next_cursor']);retain('observed-audit-first.json',first);retain('observed-audit-last.json',last);case('audit paired keyset traverses joined phases without repeats or invented completeness',shape(first,True)and shape(last,True)and len(first['rows'])==2 and len(last['rows'])==4 and not set(r['event_id']for r in first['rows'])&set(r['event_id']for r in last['rows'])and not first['history_complete'])
  # More than a page of real original workflow actions and durable service deliveries.
  own_ids={historical_esc,escalate['escalation_id']};foreign_ids=set()
  for n in range(26):
   e=raw();action(e,0,'assign',assignee=EMAIL if n<24 else OTHER);receipt=action(e,1,'escalate');(own_ids if n<24 else foreign_ids).add(receipt['escalation_id'])
  svc('select public.process_exception_escalations_v1(25);');svc('select public.process_exception_escalations_v1(25);')
  page=inbox();tail=inbox(cursor=page['next_cursor']);foreign=inbox(other);retain('observed-inbox-first.json',page);retain('observed-inbox-last.json',tail);retain('observed-inbox-foreign.json',foreign)
  case('current recipient paired20 pagination reaches all26 actual deliveries without overlap',shape(page,False)and shape(tail,False)and len(page['rows'])==20 and len(tail['rows'])==6 and{r['escalation_id']for r in page['rows']+tail['rows']}==own_ids and tail['next_cursor']is None)
  case('different approved current recipient sees only own two deliveries',shape(foreign,False)and foreign['recipient_id']==OTHER and{r['escalation_id']for r in foreign['rows']}==foreign_ids and not own_ids&foreign_ids)
  case('unknown opening creates no false acknowledgement',fail('select public.admin_read_exception_escalation_v2('+q(ident())+');','42501','exception_escalation_delivery_unavailable'))
  case('foreign delivery cannot be opened by another current owner',fail('select public.admin_read_exception_escalation_v2('+q(next(iter(foreign_ids)))+');','42501','exception_escalation_delivery_unavailable'))
  # Actual recipient-unavailable retry then obsolete after source clear.
  unavailable=raw();action(unavailable,0,'assign',assignee=OTHER);unesc=action(unavailable,1,'escalate')['escalation_id'];sql('update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id='+q(OTHER)+';');svc('select public.process_exception_escalations_v1(25);')
  ua=audit(unavailable,25);retain('observed-audit-unavailable.json',ua);case('recipient unavailable durable outcome is separately captured without delivery assertion',any(r['action']=='exception.escalation.recipient_unavailable'and r['actor_kind']=='service'for r in ua['rows'])and not any(r['action']=='exception.escalation.delivered'for r in ua['rows']))
  sql("update public.raw_payment_sms set parse_status='ignored'where id="+q(unavailable['source_id'])+";update collect_ops.exception_escalations set retry_at=clock_timestamp()where id="+q(unesc)+';');svc('select public.process_exception_escalations_v1(25);');cleared=json.loads(sql('select to_jsonb(e)from collect_ops.exceptions e where id='+q(unavailable['id'])+';'));action(cleared,2,'resolve');obsolete=audit(cleared,25);retain('observed-audit-obsolete-resolved.json',obsolete);case('obsolete delivery and explicit workflow resolve retain immutable source-specific history',any(r['action']=='exception.escalation.obsolete'for r in obsolete['rows'])and any(r['action']=='exception.workflow.resolve'and r['reason_code']=='source_rechecked'for r in obsolete['rows']))
  sql('update collect_admin_access.email_approvals set revoked_at=null where user_id='+q(OTHER)+';')
  # Real canonical new financial posting creates both source events and immutable snapshot.
  payment=ident();sql(f.service(f.payment_sql(payment,amount=10)));prior_fin=finance();event=json.loads(sql("select to_jsonb(e)from collect_hybrid.receipt_business_events e where payment_id="+q(payment)+"and source_kind='payment'order by source_version desc limit 1;"));snapshot=sql('select id from collect_hybrid.momo_balance_snapshots where payment_id='+q(payment)+"and event_type='receipt';")
  def observe(kind,source):
   sql("select collect_ops.observe(%s,%s,array['RECEIPT_OPERATION_POLICY_DISABLED'],jsonb_build_object('fixture','scoped actual source'));"%(q(kind),q(source)))
   return json.loads(sql('select to_jsonb(e)from collect_ops.exceptions e where source_kind='+q(kind)+'and source_id='+q(source)+';'))
  for kind,source in[('receipt_event',event['id']),('receipt_backlog',snapshot)]:
   e=observe(kind,source);observed=audit(e);retain('observed-audit-'+kind+'.json',observed);case(kind+' supported source derives actual scoped Rwanda payment with no ensure or financial mutation',observed['status']=='available'and shape(observed,True))
  malformed=ident();sql("insert into collect_hybrid.receipt_business_events(id,source_kind,source_id,source_version,event_kind,collection_id,payment_id,source_state)values(%s,'payment',%s,1,'payment_posted',%s,%s,'posted');"%(q(malformed),q(ident()),q(f.GROUP),q(payment)));bad=observe('receipt_event',malformed);unscoped=audit(bad);retain('observed-audit-unscoped.json',unscoped);case('contradictory typed receipt event does not disclose history',unscoped['status']=='unavailable'and unscoped['rows']==[]and unscoped['next_cursor']is None)
  allocation_raw=raw()['source_id'];allocation_id=ident()
  sql("insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,direction,currency,receiver_phone_hash,allocation_status)values(%s,%s,%s,%s,true,'mtn_momo','incoming','RWF',repeat('a',64),'needs_review');"%(q(allocation_id),q(allocation_raw),q(f.GROUP),q(u.UID)))
  allocation_event=json.loads(sql("select to_jsonb(e)from collect_hybrid.receipt_business_events e where source_kind='allocation'and source_id="+q(allocation_id)+'order by source_version desc limit 1;'));allocation_exception=observe('receipt_event',allocation_event['id']);allocation_audit=audit(allocation_exception);retain('observed-audit-allocation-event.json',allocation_audit)
  case('unposted allocation event has actual typed incoming Rwanda target proof',allocation_audit['status']=='available'and shape(allocation_audit,True))
  legacy_scope=u.psql(db,"begin;alter table public.collections drop constraint collections_rwanda_momo_only;alter table public.collections drop constraint collections_currency_check;update public.collections set currency='EUR',diaspora_enabled=true where id="+q(f.GROUP)+';'+u.auth(EMAIL,SID)+'select public.admin_get_exception_entity_audit_v2('+q(allocation_exception['id'])+');rollback;')
  legacy_projection=json.loads(legacy_scope.stdout.strip().splitlines()[-1]);retain('observed-audit-legacy-target-refusal.json',legacy_projection);case('installer-only legacy non-Rwanda target cannot borrow Rwanda raw SMS scope',legacy_projection['status']=='unavailable'and legacy_projection['rows']==[])
  mismatch=u.psql(db,"begin;set local session_replication_role=replica;update public.parsed_payment_events set receiver_phone_hash=repeat('f',64)where id="+q(allocation_id)+';set local session_replication_role=origin;'+u.auth(EMAIL,SID)+'select public.admin_get_exception_entity_audit_v2('+q(allocation_exception['id'])+');rollback;')
  case('contradictory parsed receiving hash cannot authorize receipt-event audit',json.loads(mismatch.stdout.strip().splitlines()[-1])['status']=='unavailable')
  unknown=audit({'id':ident()});retain('observed-audit-unknown.json',unknown);case('unknown exception audit is explicit unavailable with empty rows',unknown['status']=='unavailable'and unknown['rows']==[])
  # Independently scoped authority checks; inbox opening/list require no audit or mutation grant.
  probes=['select public.admin_get_exception_entity_audit_v2('+q(item['id'])+');','select public.admin_list_exception_escalation_inbox_v2();','select public.admin_read_exception_escalation_v2('+q(escalate['escalation_id'])+');']
  for probe in probes:
   case('new v2 surface refuses legacy transition identity '+probe.split('(')[0],u.expected_error(db,probe,'42501','exception_followup_email_owner_required'))
   for role in ['anon','service_role']:case(role+' denied '+probe.split('(')[0],u.expected_error(db,probe,'42501',role=role))
  for mutation,label in[("update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id="+q(SID)+';','session expiry'),("update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id="+q(EMAIL)+';','approval revocation'),("update public.admin_user_roles set revoked_at=clock_timestamp()where user_id="+q(EMAIL)+';','grant revocation'),("update auth.users set banned_until=clock_timestamp()+interval '1 day'where id="+q(EMAIL)+';','actor ban')]+[("delete from public.admin_role_permissions where role_id="+q(f.ROLE)+'and permission_name='+q(perm)+';',perm)for perm in['payments.read','notifications.read','system_health.read']]:
   for probe in [probes[0],probes[2]]:
    r=u.psql(db,'begin;'+mutation+u.auth(EMAIL,SID)+probe+'rollback;',False);case(label+' denies '+probe.split('(')[0],r.returncode!=0 and'42501:'in r.stderr)
  mutation='delete from public.admin_role_permissions where role_id='+q(f.ROLE)+"and permission_name in('audit.read','notifications.manage');"
  for probe in probes[1:]:case('inbox/opening does not require unrelated audit/mutation authority '+probe.split('(')[0],u.psql(db,'begin;'+mutation+u.auth(EMAIL,SID)+probe+'rollback;',False).returncode==0)
  r=u.psql(db,'begin;'+mutation+u.auth(EMAIL,SID)+probes[0]+'rollback;',False);case('joined audit requires independent audit.read',r.returncode!=0 and'42501:'in r.stderr)
  for args in ['0','26','null',"20,clock_timestamp(),null","20,'infinity',"+q(ident()),"20,'10000-01-01',"+q(ident())]:
   case('inbox rejects bound/cursor '+args,fail('select public.admin_list_exception_escalation_inbox_v2('+args+');','22023'))
   case('audit rejects bound/cursor '+args,fail('select public.admin_get_exception_entity_audit_v2('+q(item['id'])+','+args+');','22023'))
  for isolation in ['repeatable read','serializable']:
   r=u.psql(db,'begin isolation level '+isolation+';'+u.auth(EMAIL,SID)+probes[0]+'rollback;',False);case(isolation+' rejects retained authority snapshot',r.returncode!=0 and'40001:'in r.stderr)
  # A transactional capture failure must roll back delivery, state and source request.
  failing=raw();action(failing,0,'assign');fail_esc=action(failing,1,'escalate')['escalation_id'];count=sql('select count(*)from collect_ops.exception_escalation_events;')
  r=u.psql(db,"begin;create function collect_ops.uat_reject_event()returns trigger language plpgsql as $$begin raise exception 'synthetic capture failure'using errcode='55000';end$$;create trigger uat_event_failure before insert on collect_ops.exception_escalation_events for each row execute function collect_ops.uat_reject_event();"+service_auth+'select public.process_exception_escalations_v1(25);rollback;',False)
  case('induced event capture failure rolls back durable delivery and mutable lifecycle state',r.returncode!=0 and'synthetic capture failure'in r.stderr and sql('select state from collect_ops.exception_escalations where id='+q(fail_esc)+';')=='queued'and sql('select not exists(select 1 from collect_ops.exception_inbox_deliveries where escalation_id='+q(fail_esc)+');')=='t'and sql('select count(*)from collect_ops.exception_escalation_events;')==count)
  held=u.Session(db,'exception_audit_pump_holder');sessions.append(held);held.write('begin;'+service_auth+'select public.process_exception_escalations_v1(25);'+"select 'PUMP_HELD';");held.read('PUMP_HELD')
  started=time.monotonic();case('actual uncommitted pump prevents mixed-state history disclosure',fail(probes[0],'55P03','exception_audit_authority_busy'));case('actual uncommitted pump prevents recipient inbox mixed snapshot',fail(probes[1],'55P03','exception_inbox_authority_busy'));result['pump_read_busy_seconds']=round(time.monotonic()-started,3)
  held.write("rollback;select 'PUMP_ROLLED_BACK';");held.read('PUMP_ROLLED_BACK');case('rollback removes uncommitted delivery event together with delivery state',sql('select state from collect_ops.exception_escalations where id='+q(fail_esc)+';')=='queued')
  svc('select public.process_exception_escalations_v1(25);');retry=audit(failing);retain('observed-audit-after-pump-commit.json',retry);case('later committed pump appears exactly once without fabricating retried recipient action',sum(r['action']=='exception.escalation.delivered'for r in retry['rows'])==1)
  held.write('begin;'+u.auth(EMAIL,SID)+'select public.admin_read_exception_escalation_v2('+q(fail_esc)+");select 'OPEN_HELD';");held.read('OPEN_HELD');case('actual pending current-owner opening blocks concurrent inconsistent history',fail(probes[0],'55P03','exception_audit_authority_busy'));held.write("rollback;select 'OPEN_ROLLED_BACK';");held.read('OPEN_ROLLED_BACK');case('opening rollback retains neither read nor lifecycle event',sql('select not exists(select 1 from collect_ops.exception_inbox_reads where escalation_id='+q(fail_esc)+")and not exists(select 1 from collect_ops.exception_escalation_events where escalation_id="+q(fail_esc)+"and action='opened');")=='t')
  owner('select public.admin_read_exception_escalation_v2('+q(fail_esc)+');')
  # Natural expiry after a real opening write must roll back that write and
  # its immutable event rather than leak an acknowledged outcome.
  expiring=raw();action(expiring,0,'assign');exp_esc=action(expiring,1,'escalate')['escalation_id'];svc('select public.process_exception_escalations_v1(25);')
  expiry=u.psql(db,"begin;update collect_admin_access.email_approvals set expires_at=clock_timestamp()+interval '0.25 seconds'where user_id="+q(EMAIL)+";create function collect_ops.uat_slow_open()returns trigger language plpgsql as $$begin perform pg_sleep(.4);return new;end$$;create trigger uat_slow_open before insert on collect_ops.exception_inbox_reads for each row execute function collect_ops.uat_slow_open();"+u.auth(EMAIL,SID)+'select public.admin_read_exception_escalation_v2('+q(exp_esc)+');rollback;',False)
  case('natural email expiry after actual opening rolls back source ACK and captured event',expiry.returncode!=0 and'42501:'in expiry.stderr and any(reason in expiry.stderr for reason in ['exception_followup_email_owner_required','roster_actor_unavailable']) and sql('select not exists(select 1 from collect_ops.exception_inbox_reads where escalation_id='+q(exp_esc)+");")=='t')
  # A rollback-only representative equal-time request history reaches the
  # exact inner SELECT of the installed public function, not EXPLAIN of its
  # opaque PL/pgSQL call. No planner switches are changed.
  same_at=sql("select collect_ops.utc(clock_timestamp()-interval '1 second');")
  perf=u.Session(db,'exception_v2_performance');sessions.append(perf)
  perf.write('begin;'+u.auth(EMAIL,SID)+"do $$declare n integer;begin for n in 1..1000 loop perform public.admin_act_operational_exception_v1(extensions.uuid_generate_v5('de24414a-723f-5b17-8b7b-935c5d786b56'::uuid,n::text),"+q(item['id'])+","+str(item['revision'])+",'acknowledge','review_started');end loop;end$$;reset role;set local session_replication_role=replica;update collect_ops.exception_actions set recorded_at="+q(same_at)+"where exception_id="+q(item['id'])+";set local session_replication_role=origin;analyze collect_ops.exception_actions;select 'PERF_HELD';");perf.read('PERF_HELD')
  # The same transaction reads its own representative fixture and actual body.
  own_query=bodies[FEATURE].decode().split(' with scope as materialized',1)[1].split('into result;',1)[0]
  own_query='with scope as materialized'+own_query
  own_query=own_query.replace('p_exception_id',q(item['id'])+'::uuid').replace('p_limit','20').replace('p_before_at',q(same_at)+'::timestamptz').replace('p_before_event_id',q('ffffffff-ffff-ffff-ffff-ffffffffffff')+'::uuid')
  own_query=re.sub(r'\bsample\b',q(same_at)+'::timestamptz',own_query)
  perf.write('explain(analyze,buffers,format json)'+own_query+";select 'PLAN_DONE';");plan_lines=perf.read('PLAN_DONE');retain('observed-actual-read-plan.json',{'representative_review_rows':1001,'equal_time_installer_reshape_rollback_only':True,'planner_switches_changed':False,'exact_installed_select_query':own_query,'raw_lines':plan_lines})
  plan_text='\n'.join(plan_lines);case('exact installed read uses namespace-order review index under representative equal-time cursor', 'exception_review_audit_v2_order'in plan_text and 'Index Scan'in plan_text)
  perf.write("rollback;select 'PERF_ROLLED_BACK';");perf.read('PERF_ROLLED_BACK');case('performance fixture rollback preserves immutable original public history',len(audit(item,25)['rows'])==6)
  for table in['exception_escalation_events','exception_workflow_requests','exception_inbox_deliveries','exception_inbox_reads']:
   case(table+' private RLS and no direct API grants',sql("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c where c.oid="+q('collect_ops.'+table)+'::regclass;')=='t')
   r=u.psql(db,'begin;delete from collect_ops.'+table+';rollback;',False);case(table+' immutable even to synthetic owner',r.returncode!=0 and'55000:'in r.stderr)
  case('new private helpers have no API execute access',sql("select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.proname in('capture_escalation_event','exception_event_id','exception_scope_v2','exception_actor_v2')and has_function_privilege(r,p.oid,'EXECUTE')); ")=='t')
  case('all new reads/actions preserve nonempty canonical finance provider primary receipt and send state',finance()==prior_fin);result['financial_before']=prior_fin;result['financial_after']=finance();retain('observed-audit-final.json',audit(item,25));retain('observed-inbox-final.json',inbox());result['status']='pass'
 except BaseException as error:result['status']='failed';result['error']=str(error);raise
 finally:
  for s in sessions:
   try:s.close()
   except Exception as error:result.setdefault('cleanup_errors',[]).append(str(error))
  if target:target.close()
  result['sources_unchanged']=all((ROOT/n).read_bytes()==b for n,b in bodies.items());result['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
if __name__=='__main__':main()
