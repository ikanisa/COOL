"""Actual nested plans under current synthetic API authority; fixtures rollback."""
import json,re,pathlib,hashlib

def run_cost_proof(t,auth,principal,rid,m,case,report,saved,audits):
 q=m.quoted
 request_ids="md5('600-cost-request:'||i)::uuid"
 owner_ids="md5('600-cost-owner:'||i)::uuid"
 service_source='receipt_operations_service_request';owner_source='receipt_operations_owner_request'
 # These are explicit installer-only retained-history density fixtures, copied
 # from actual request rows. They are never advertised as ordinary producer
 # outcomes. Row values and all trigger alterations rollback as one transaction.
 setup=f"""begin;set local role postgres;
 alter table collect_receipt_operations.requests disable trigger user;
 alter table collect_receipt_operations.owner_requests disable trigger user;
 insert into collect_receipt_operations.requests(request_id,principal_id,action,request_sha256,input,issued_at,recorded_at,result)
 select {request_ids},e.principal_id,(array['list_events','ensure_receipt','reconcile_backlog','complete_run','begin_run'])[1+(i%5)],e.request_sha256,
 jsonb_build_object('run_id',case when i<=12000 then {q(rid)} else md5('unrelated-run:'||i)::uuid::text end,'fence_version',e.input->>'fence_version'),e.issued_at,
 case when i<=512 then clock_timestamp()-interval '1 minute' else clock_timestamp()-interval '1 hour'-i*interval '1 second'end,
 jsonb_build_object('run_id',case when i<=12000 then {q(rid)} else md5('unrelated-run:'||i)::uuid::text end,'fence_version',e.result->>'fence_version','status','declared_cost_fixture')
 from generate_series(1,60000)i cross join lateral(select *from collect_receipt_operations.requests where action='complete_run'and input->>'run_id'={q(rid)}limit 1)e;
 -- Force exact same-time ties independently of statement clock evaluation.
 update collect_receipt_operations.requests set recorded_at=date_trunc('second',clock_timestamp()-interval '1 minute')where request_id in(select {request_ids} from generate_series(1,512)i);
 insert into collect_receipt_operations.owner_requests(request_id,actor_id,session_id,action,input,result,recorded_at,expires_at)
 select {owner_ids},e.actor_id,e.session_id,case when i>40000 then 'configure'else 'activate'end,e.input,
 case when i>40000 then jsonb_build_object('revision',100000+i)else jsonb_build_object('principal_id',case when i<=20000 then {q(principal)}else md5('unrelated-principal:'||i)::uuid::text end)end,
 case when i<=512 then date_trunc('second',clock_timestamp()-interval '1 minute')else clock_timestamp()-interval '1 hour'-i*interval '1 second'end,
 case when i>40000 then clock_timestamp()-interval '1 hour'-i*interval '1 second'+interval '100 seconds'end
 from generate_series(1,60000)i cross join lateral(select *from collect_receipt_operations.owner_requests where action='configure'limit 1)e;
 update collect_receipt_operations.owner_requests set recorded_at=date_trunc('second',clock_timestamp()-interval '1 minute')where request_id in(select {owner_ids} from generate_series(1,512)i);
 alter table collect_receipt_operations.requests enable trigger user;
 alter table collect_receipt_operations.owner_requests enable trigger user;
 analyze collect_receipt_operations.requests;analyze collect_receipt_operations.owner_requests;
 create temporary table cost_cursors(label text primary key,at timestamptz,id uuid,at_text text,expected_ids uuid[]);
 insert into cost_cursors(label,at,id)select 'service-deep',recorded_at,collect_operator_audit.operational_event_id('{service_source}',request_id)from collect_receipt_operations.requests where input->>'run_id'={q(rid)}order by recorded_at desc,collect_operator_audit.operational_event_id('{service_source}',request_id)desc offset 8000 limit 1;
 insert into cost_cursors(label,at,id)select 'service-tie',recorded_at,collect_operator_audit.operational_event_id('{service_source}',request_id)from collect_receipt_operations.requests where request_id in(select {request_ids} from generate_series(1,512)i)order by recorded_at desc,collect_operator_audit.operational_event_id('{service_source}',request_id)desc offset 255 limit 1;
 insert into cost_cursors(label,at,id)select 'owner-deep',recorded_at,collect_operator_audit.operational_event_id('{owner_source}',request_id)from collect_receipt_operations.owner_requests where result->>'principal_id'={q(principal)}order by recorded_at desc,collect_operator_audit.operational_event_id('{owner_source}',request_id)desc offset 15000 limit 1;
 insert into cost_cursors(label,at,id)select 'owner-tie',recorded_at,collect_operator_audit.operational_event_id('{owner_source}',request_id)from collect_receipt_operations.owner_requests where request_id in(select {owner_ids} from generate_series(1,512)i)order by recorded_at desc,collect_operator_audit.operational_event_id('{owner_source}',request_id)desc offset 255 limit 1;
 update cost_cursors c set at_text=collect_ops.utc(c.at),expected_ids=case when c.label like 'service-%'then
 array(select collect_operator_audit.operational_event_id('{service_source}',e.request_id)from collect_receipt_operations.requests e join collect_receipt_operations.runs r on r.id={q(rid)}where e.principal_id=r.principal_id
 and((e.action='begin_run'and e.request_id=r.request_id and e.result->>'run_id'=r.id::text)or(e.action in('list_events','ensure_receipt','reconcile_backlog','complete_run')and e.input->>'run_id'=r.id::text and e.input->>'fence_version'=r.fence_version::text and e.result->>'run_id'=r.id::text and e.result->>'fence_version'=r.fence_version::text))
 and(e.recorded_at,collect_operator_audit.operational_event_id('{service_source}',e.request_id))<(c.at,c.id)order by e.recorded_at desc,collect_operator_audit.operational_event_id('{service_source}',e.request_id)desc limit 10)
 else array(select collect_operator_audit.operational_event_id('{owner_source}',e.request_id)from collect_receipt_operations.owner_requests e where e.action in('enroll','activate','revoke')and e.result->>'principal_id'={q(principal)}and(e.recorded_at,collect_operator_audit.operational_event_id('{owner_source}',e.request_id))<(c.at,c.id)order by e.recorded_at desc,collect_operator_audit.operational_event_id('{owner_source}',e.request_id)desc limit 10)end;
 grant select on cost_cursors to authenticated;
 reset role;
 load 'auto_explain';set auto_explain.log_min_duration=0;set auto_explain.log_nested_statements=on;set auto_explain.log_analyze=on;set auto_explain.log_buffers=on;set auto_explain.log_timing=off;set auto_explain.log_format=json;set client_min_messages=log;set plan_cache_mode=force_generic_plan;
 {auth}
 select jsonb_build_object('probe','detail-density','response',public.admin_get_receipt_operation_run_v1({q(rid)}));
 select jsonb_build_object('probe','service-head','response',public.admin_get_operator_entity_audit_v1('receipt_operation_run',{q(rid)},10,null,null));
 select jsonb_build_object('probe',c.label,'cursor',jsonb_build_object('recorded_at',c.at_text,'event_id',c.id),'expected_ids',c.expected_ids,'response',public.admin_get_operator_entity_audit_v1('receipt_operation_run',{q(rid)},10,c.at,c.id))from cost_cursors c where label in('service-deep','service-tie')order by label;
 select jsonb_build_object('probe',c.label,'cursor',jsonb_build_object('recorded_at',c.at_text,'event_id',c.id),'expected_ids',c.expected_ids,'response',public.admin_get_operator_entity_audit_v1('supervisor_identity',{q(principal)},10,c.at,c.id))from cost_cursors c where label in('owner-deep','owner-tie')order by label;
 reset role;savepoint ambiguous_fixture;
 set auto_explain.log_min_duration=-1;
 alter table collect_receipt_operations.requests disable trigger user;alter table collect_receipt_operations.owner_requests disable trigger user;
 insert into collect_receipt_operations.requests select md5('600-cost-completion-ambiguity:'||i)::uuid,e.principal_id,e.action,e.request_sha256,e.input,e.issued_at,e.recorded_at,e.result from generate_series(1,10000)i cross join lateral(select *from collect_receipt_operations.requests where action='complete_run'and input->>'run_id'={q(rid)}and result->>'status'='completed'limit 1)e;
 insert into collect_receipt_operations.owner_requests select md5('600-cost-config-ambiguity:'||i)::uuid,e.actor_id,e.session_id,e.action,e.input,e.result,e.recorded_at,e.expires_at from generate_series(1,10000)i cross join lateral(select *from collect_receipt_operations.owner_requests where request_id={q(saved['historical_config']['request_id'])})e;
 alter table collect_receipt_operations.requests enable trigger user;alter table collect_receipt_operations.owner_requests enable trigger user;
 analyze collect_receipt_operations.requests;analyze collect_receipt_operations.owner_requests;
 set auto_explain.log_min_duration=0;
 {auth}
 select jsonb_build_object('probe','detail-ambiguous','response',public.admin_get_receipt_operation_run_v1({q(rid)}));
 reset role;rollback to ambiguous_fixture;rollback;"""
 r=t.sql(setup,user='supabase_admin',label='declared rollback-only120k retained request density and20k ambiguity fixtures; actual authenticated readers with nested EXPLAIN instrumentation')
 observations=[v for x in r.stdout.splitlines()if x.startswith('{')for v in [json.loads(x)]if 'probe'in v]
 (report/'cost-observations.json').write_text(json.dumps(observations,indent=2)+'\n')
 # PostgreSQL auto_explain JSON is emitted to client LOG with the full actual
 # nested query text. Retain raw command logs plus parsed plans without rewriting.
 plans=[];decoder=json.JSONDecoder()
 for match in re.finditer(r'(?m)^\{\s*$',r.stderr):
  try:obj,_=decoder.raw_decode(r.stderr[match.start():])
  except json.JSONDecodeError:continue
  if 'Plan'in obj:plans.append(obj)
 (report/'actual-nested-explain.json').write_text(json.dumps(plans,indent=2)+'\n')
 def walk(n):
  yield n
  for p in n.get('Plans',[]):yield from walk(p)
 relevant=[p for p in plans if 'matching_completion'in p['Query Text']or'matching_config'in p['Query Text']or'with events as not materialized'in p['Query Text']]
 case('actual nested EXPLAIN captured real detail and joined audit SQL',len(relevant)>=9)
 details=[p for p in relevant if 'matching_completion'in p['Query Text']or'matching_config'in p['Query Text']]
 case('detail ambiguity is bounded before count with exact indexed identities',all(any(n['Node Type']=='Limit'and n.get('Actual Rows',99)<=2 for n in walk(p['Plan']))for p in details)and all(any('Index'in n['Node Type']and n.get('Index Cond')for n in walk(p['Plan']))for p in details))
 audits_plans=[p for p in relevant if 'with events as not materialized'in p['Query Text']]
 service=[p for p in audits_plans if any(n.get('Index Name')in('receipt_history_service_run_audit','receipt_history_completions')and n.get('Actual Loops',0)>0 for n in walk(p['Plan']))]
 owner=[p for p in audits_plans if any(n.get('Index Name')=='receipt_history_owner_identity_audit'and n.get('Actual Loops',0)>0 for n in walk(p['Plan']))]
 case('all actual service head/deep/tie plans use four bounded ordered run-action index seeks',len(service)==3 and all(len([n for n in walk(p['Plan'])if n.get('Index Name')in('receipt_history_service_run_audit','receipt_history_completions')])==4 for p in service))
 case('actual begin branch reads at most one original request by primary key despite12k retained begins',all(any(n.get('Index Name')=='requests_pkey'and n.get('Actual Rows',99)<=1 and n.get('Rows Removed by Filter',0)==0 for n in walk(p['Plan']))for p in service))
 case('forced generic plan service run-action index nodes return at most limit+1 and omit unrelated histories',all(n.get('Actual Rows',99)<=11 and n.get('Rows Removed by Filter',0)<=1 and 'principal_id'in n.get('Index Cond','')and('action'in n.get('Index Cond','')or n.get('Index Name')=='receipt_history_completions')for p in service for n in walk(p['Plan'])if n.get('Index Name')in('receipt_history_service_run_audit','receipt_history_completions')))
 case('forced generic owner identity deep/tie plans seek matching derived event order',len(owner)==2 and all(any('ROW('in n.get('Index Cond','')and ('md5'in n.get('Index Cond','')or 'operational_event_id'in n.get('Index Cond',''))for n in walk(p['Plan'])if n.get('Index Name')=='receipt_history_owner_identity_audit')for p in owner))
 case('forced generic owner identity index nodes return at most limit+1 without lifetime filtered scan',all(n.get('Actual Rows',99)<=11 and n.get('Rows Removed by Filter',0)<=2 for p in owner for n in walk(p['Plan'])if n.get('Index Name')=='receipt_history_owner_identity_audit'))
 obs={v['probe']:v for v in observations}
 case('forced generic deep service cursor seeks are part of ordered index condition',all('ROW('in n.get('Index Cond','')and('md5'in n.get('Index Cond','')or 'operational_event_id'in n.get('Index Cond',''))for p in service for n in walk(p['Plan'])if n.get('Index Name')in('receipt_history_service_run_audit','receipt_history_completions')))
 case('density preserves actual original run configuration and completion shapes',obs['detail-density']['response']['historical_config']==saved['historical_config']and obs['detail-density']['response']['completion']==saved['completion']and obs['detail-density']['response']['run']==saved['run'])
 case('10k ambiguous original config and completion stay unavailable',obs['detail-ambiguous']['response']['historical_config']is None and obs['detail-ambiguous']['response']['completion']is None)
 for label in ['service-deep','service-tie','owner-deep','owner-tie']:
  v=obs[label];rows=v['response']['rows'];cursor=v['cursor']
  case('actual '+label+' complete timestamp+derived UUID cursor respects exact descending page',len(rows)==10 and all((x['recorded_at'],x['event_id'])<(cursor['recorded_at'],cursor['event_id'])for x in rows)and [(x['recorded_at'],x['event_id'])for x in rows]==sorted([(x['recorded_at'],x['event_id'])for x in rows],reverse=True)and len({x['event_id']for x in rows})==10 and [x['event_id']for x in rows]==v['expected_ids'])
  if label.endswith('tie'):case('actual '+label+' remains inside same timestamp tie',all(x['recorded_at']==cursor['recorded_at']for x in rows))
 # These response shapes come from the real RPC, with explicit synthetic cost
 # density fixtures; ordinary business fixtures remain the earlier saved calls.
 fields=set(audits['receipt_operation_run']['rows'][0])
 case('all service and identity audit row DTO shapes remain exact',all(set(row)==fields for v in observations if v['probe'].startswith(('service','owner'))for row in v['response']['rows']))
 case('rollback density fixtures removes every retained synthetic cost request',t.scalar("select not exists(select 1 from collect_receipt_operations.requests where request_id in(select md5('600-cost-request:'||i)::uuid from generate_series(1,60000)i));")=='t')
 return dict(rows=dict(service=60000,owner=60000,additional_ambiguity=20000),actual_nested_plans=len(plans),relevant_plans=len(relevant),fixture_scope='explicit rollback-only installer density cloned from ordinary producer request rows; actual authenticated readers; no unrelated row/source mutation survives')
