set search_path=public,extensions,auth;set timezone='UTC';
begin;set local role postgres;
 alter table collect_receipt_operations.requests disable trigger user;
 alter table collect_receipt_operations.owner_requests disable trigger user;
 insert into collect_receipt_operations.requests(request_id,principal_id,action,request_sha256,input,issued_at,recorded_at,result)
 select md5('600-cost-request:'||i)::uuid,e.principal_id,(array['list_events','ensure_receipt','reconcile_backlog','complete_run','begin_run'])[1+(i%5)],e.request_sha256,
 jsonb_build_object('run_id',case when i<=12000 then '7168565d-69e8-4415-aa47-c59123ecaa3e' else md5('unrelated-run:'||i)::uuid::text end,'fence_version',e.input->>'fence_version'),e.issued_at,
 case when i<=512 then clock_timestamp()-interval '1 minute' else clock_timestamp()-interval '1 hour'-i*interval '1 second'end,
 jsonb_build_object('run_id',case when i<=12000 then '7168565d-69e8-4415-aa47-c59123ecaa3e' else md5('unrelated-run:'||i)::uuid::text end,'fence_version',e.result->>'fence_version','status','declared_cost_fixture')
 from generate_series(1,60000)i cross join lateral(select *from collect_receipt_operations.requests where action='complete_run'and input->>'run_id'='7168565d-69e8-4415-aa47-c59123ecaa3e'limit 1)e;
 -- Force exact same-time ties independently of statement clock evaluation.
 update collect_receipt_operations.requests set recorded_at=date_trunc('second',clock_timestamp()-interval '1 minute')where request_id in(select md5('600-cost-request:'||i)::uuid from generate_series(1,512)i);
 insert into collect_receipt_operations.owner_requests(request_id,actor_id,session_id,action,input,result,recorded_at,expires_at)
 select md5('600-cost-owner:'||i)::uuid,e.actor_id,e.session_id,case when i>40000 then 'configure'else 'activate'end,e.input,
 case when i>40000 then jsonb_build_object('revision',100000+i)else jsonb_build_object('principal_id',case when i<=20000 then '07eb4d13-d1c1-49b2-bb44-a3da7b9551fb'else md5('unrelated-principal:'||i)::uuid::text end)end,
 case when i<=512 then date_trunc('second',clock_timestamp()-interval '1 minute')else clock_timestamp()-interval '1 hour'-i*interval '1 second'end,
 case when i>40000 then clock_timestamp()-interval '1 hour'-i*interval '1 second'+interval '100 seconds'end
 from generate_series(1,60000)i cross join lateral(select *from collect_receipt_operations.owner_requests where action='configure'limit 1)e;
 update collect_receipt_operations.owner_requests set recorded_at=date_trunc('second',clock_timestamp()-interval '1 minute')where request_id in(select md5('600-cost-owner:'||i)::uuid from generate_series(1,512)i);
 alter table collect_receipt_operations.requests enable trigger user;
 alter table collect_receipt_operations.owner_requests enable trigger user;
 analyze collect_receipt_operations.requests;analyze collect_receipt_operations.owner_requests;
 create temporary table cost_cursors(label text primary key,at timestamptz,id uuid,at_text text,expected_ids uuid[]);
 insert into cost_cursors(label,at,id)select 'service-deep',recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',request_id)from collect_receipt_operations.requests where input->>'run_id'='7168565d-69e8-4415-aa47-c59123ecaa3e'order by recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_service_request',request_id)desc offset 8000 limit 1;
 insert into cost_cursors(label,at,id)select 'service-tie',recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',request_id)from collect_receipt_operations.requests where request_id in(select md5('600-cost-request:'||i)::uuid from generate_series(1,512)i)order by recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_service_request',request_id)desc offset 255 limit 1;
 insert into cost_cursors(label,at,id)select 'owner-deep',recorded_at,collect_operator_audit.operational_event_id('receipt_operations_owner_request',request_id)from collect_receipt_operations.owner_requests where result->>'principal_id'='07eb4d13-d1c1-49b2-bb44-a3da7b9551fb'order by recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_owner_request',request_id)desc offset 15000 limit 1;
 insert into cost_cursors(label,at,id)select 'owner-tie',recorded_at,collect_operator_audit.operational_event_id('receipt_operations_owner_request',request_id)from collect_receipt_operations.owner_requests where request_id in(select md5('600-cost-owner:'||i)::uuid from generate_series(1,512)i)order by recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_owner_request',request_id)desc offset 255 limit 1;
 update cost_cursors c set at_text=collect_ops.utc(c.at),expected_ids=case when c.label like 'service-%'then
 array(select collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id)from collect_receipt_operations.requests e join collect_receipt_operations.runs r on r.id='7168565d-69e8-4415-aa47-c59123ecaa3e'where e.principal_id=r.principal_id
 and((e.action='begin_run'and e.request_id=r.request_id and e.result->>'run_id'=r.id::text)or(e.action in('list_events','ensure_receipt','reconcile_backlog','complete_run')and e.input->>'run_id'=r.id::text and e.input->>'fence_version'=r.fence_version::text and e.result->>'run_id'=r.id::text and e.result->>'fence_version'=r.fence_version::text))
 and(e.recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id))<(c.at,c.id)order by e.recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id)desc limit 10)
 else array(select collect_operator_audit.operational_event_id('receipt_operations_owner_request',e.request_id)from collect_receipt_operations.owner_requests e where e.action in('enroll','activate','revoke')and e.result->>'principal_id'='07eb4d13-d1c1-49b2-bb44-a3da7b9551fb'and(e.recorded_at,collect_operator_audit.operational_event_id('receipt_operations_owner_request',e.request_id))<(c.at,c.id)order by e.recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_owner_request',e.request_id)desc limit 10)end;
 grant select on cost_cursors to authenticated;
 reset role;
 load 'auto_explain';set auto_explain.log_min_duration=0;set auto_explain.log_nested_statements=on;set auto_explain.log_analyze=on;set auto_explain.log_buffers=on;set auto_explain.log_timing=off;set auto_explain.log_format=json;set client_min_messages=log;set plan_cache_mode=force_generic_plan;
 set local role authenticated;select set_config('request.jwt.claims','{"sub": "99780000-0000-4000-8000-000000000001", "session_id": "99780000-0000-4000-8000-000000010001", "role": "authenticated", "aal": "aal1"}',true);
 select jsonb_build_object('probe','detail-density','response',public.admin_get_receipt_operation_run_v1('7168565d-69e8-4415-aa47-c59123ecaa3e'));
 select jsonb_build_object('probe','service-head','response',public.admin_get_operator_entity_audit_v1('receipt_operation_run','7168565d-69e8-4415-aa47-c59123ecaa3e',10,null,null));
 select jsonb_build_object('probe',c.label,'cursor',jsonb_build_object('recorded_at',c.at_text,'event_id',c.id),'expected_ids',c.expected_ids,'response',public.admin_get_operator_entity_audit_v1('receipt_operation_run','7168565d-69e8-4415-aa47-c59123ecaa3e',10,c.at,c.id))from cost_cursors c where label in('service-deep','service-tie')order by label;
 select jsonb_build_object('probe',c.label,'cursor',jsonb_build_object('recorded_at',c.at_text,'event_id',c.id),'expected_ids',c.expected_ids,'response',public.admin_get_operator_entity_audit_v1('supervisor_identity','07eb4d13-d1c1-49b2-bb44-a3da7b9551fb',10,c.at,c.id))from cost_cursors c where label in('owner-deep','owner-tie')order by label;
 reset role;savepoint ambiguous_fixture;
 set auto_explain.log_min_duration=-1;
 alter table collect_receipt_operations.requests disable trigger user;alter table collect_receipt_operations.owner_requests disable trigger user;
 insert into collect_receipt_operations.requests select md5('600-cost-completion-ambiguity:'||i)::uuid,e.principal_id,e.action,e.request_sha256,e.input,e.issued_at,e.recorded_at,e.result from generate_series(1,10000)i cross join lateral(select *from collect_receipt_operations.requests where action='complete_run'and input->>'run_id'='7168565d-69e8-4415-aa47-c59123ecaa3e'and result->>'status'='completed'limit 1)e;
 insert into collect_receipt_operations.owner_requests select md5('600-cost-config-ambiguity:'||i)::uuid,e.actor_id,e.session_id,e.action,e.input,e.result,e.recorded_at,e.expires_at from generate_series(1,10000)i cross join lateral(select *from collect_receipt_operations.owner_requests where request_id='cd0ce2de-83af-4755-a73b-f40d7ce772be')e;
 alter table collect_receipt_operations.requests enable trigger user;alter table collect_receipt_operations.owner_requests enable trigger user;
 analyze collect_receipt_operations.requests;analyze collect_receipt_operations.owner_requests;
 set auto_explain.log_min_duration=0;
 set local role authenticated;select set_config('request.jwt.claims','{"sub": "99780000-0000-4000-8000-000000000001", "session_id": "99780000-0000-4000-8000-000000010001", "role": "authenticated", "aal": "aal1"}',true);
 select jsonb_build_object('probe','detail-ambiguous','response',public.admin_get_receipt_operation_run_v1('7168565d-69e8-4415-aa47-c59123ecaa3e'));
 reset role;rollback to ambiguous_fixture;rollback;