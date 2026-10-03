-- Root-owned full threshold/absence matrix, no application writes/providers.
begin;
set local statement_timeout='30s';
do $$begin
 if current_user<>'postgres' or current_database()<>'postgres'
  or current_setting('collect.operational_health_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0' then
  raise exception 'Exact isolated owner health fixture required';end if;
end $$;
create temp table health_matrix_assertions(name text primary key);
create function pg_temp.health_matrix_assert(p_name text,p_ok boolean) returns void language plpgsql as $$begin
 if p_ok is distinct from true then raise exception 'Health matrix assertion failed:%',p_name;end if;
 insert into health_matrix_assertions values(p_name);
end $$;
create function pg_temp.health_matrix_state(p_metrics jsonb,p_code text) returns text language sql as $$
 select a->>'state' from jsonb_array_elements(collect_security.operational_health_alerts(p_metrics)) a where a->>'code'=p_code
$$;
do $$declare r record; metrics jsonb; value jsonb; rejected boolean; alert jsonb; begin
 -- Threshold contract1 is independently specified in the local response
 -- procedures. Exercise every alert at both sides of the boundary, then feed
 -- malformed measurements; a copied list alone is not acceptance evidence.
 for r in select * from (values
  ('receipt_parse_backlog','sms_pending',100,null::text),
  ('receipt_parse_age','sms_pending_age_seconds',300,'sms_pending'),
  ('receipt_parse_failure','sms_failed_24h',1,null::text),
  ('receipt_parser_lease_expired','sms_expired_parse_leases',1,null::text),
  ('payment_unmatched','unallocated_events',1,null::text),
  ('payment_review_age','payment_review_age_seconds',3600,'payments_review'),
  ('reconciliation_exception','reconciliation_open',1,null::text),
  ('push_queue_age','push_due_age_seconds',120,'push_due'),
  ('push_expired_lease','push_expired_leases',1,null::text),
  ('push_missing_lease','push_missing_leases',1,null::text),
  ('push_attempt_failure','push_failed_24h',5,null::text),
  ('receipt_telemetry_stale','receipt_telemetry_age_seconds',300,'durable_receipts_24h'),
  ('push_scheduler_stale','push_scheduler_age_seconds',180,'push_due')
 ) rules(code,metric,threshold,queue) loop
  metrics:=case when r.queue is null then '{}'::jsonb else jsonb_build_object(r.queue,1) end;
  select a into alert from jsonb_array_elements(collect_security.operational_health_alerts(metrics)) a where a->>'code'=r.code;
  perform pg_temp.health_matrix_assert(r.code||':typed-contract',alert=jsonb_build_object('code',r.code,'metric',r.metric,'threshold',r.threshold,'state','unknown'));
  perform pg_temp.health_matrix_assert(r.code||':absent',pg_temp.health_matrix_state(metrics,r.code)='unknown');
  perform pg_temp.health_matrix_assert(r.code||':null',pg_temp.health_matrix_state(metrics||jsonb_build_object(r.metric,null),r.code)='unknown');
  perform pg_temp.health_matrix_assert(r.code||':zero',pg_temp.health_matrix_state(metrics||jsonb_build_object(r.metric,0),r.code)='ok');
  perform pg_temp.health_matrix_assert(r.code||':below',pg_temp.health_matrix_state(metrics||jsonb_build_object(r.metric,r.threshold-1),r.code)='ok');
  perform pg_temp.health_matrix_assert(r.code||':exact',pg_temp.health_matrix_state(metrics||jsonb_build_object(r.metric,r.threshold),r.code)='attention');
  perform pg_temp.health_matrix_assert(r.code||':above',pg_temp.health_matrix_state(metrics||jsonb_build_object(r.metric,r.threshold+1),r.code)='attention');
  if r.queue is not null then
   perform pg_temp.health_matrix_assert(r.code||':empty-queue',pg_temp.health_matrix_state(jsonb_build_object(r.queue,0),r.code)='not_applicable');
   perform pg_temp.health_matrix_assert(r.code||':nonempty-missing-age',pg_temp.health_matrix_state(jsonb_build_object(r.queue,1),r.code)='unknown');
  end if;
  for value in select v from (values('-1'::jsonb),('1.5'::jsonb),('"100"'::jsonb),('true'::jsonb),('[]'::jsonb),('9007199254740992'::jsonb)) malformed(v) loop
   rejected:=false;
   begin perform collect_security.operational_health_alerts(metrics||jsonb_build_object(r.metric,value));
   exception when invalid_parameter_value then rejected:=true;end;
   perform pg_temp.health_matrix_assert(r.code||':reject:'||value::text,rejected);
  end loop;
 end loop;
 perform pg_temp.health_matrix_assert('exact13-unique-alerts',
  jsonb_array_length(collect_security.operational_health_alerts('{}'))=13
  and (select count(distinct a->>'code') from jsonb_array_elements(collect_security.operational_health_alerts('{}')) a)=13);
end $$;
select 'HEALTH_ALERT_MATRIX_ASSERTIONS|'||count(*) from health_matrix_assertions;
rollback;
