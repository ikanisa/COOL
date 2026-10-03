-- Offline synthetic target: isolated installer owner normalization
grant pg_read_all_settings,pg_read_all_stats to postgres;alter role postgres superuser;
-- Offline synthetic target: query
select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'server',current_setting('server_version'));
-- Offline synthetic target: query
do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon nologin;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated nologin;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role nologin bypassrls;end if;end$$;
-- Offline synthetic target: platform-owner pg_net prerequisite
create schema if not exists extensions;create extension if not exists pg_net with schema extensions;
-- Offline synthetic target: query
select jsonb_build_object('extension_owner',pg_get_userbyid(e.extowner),'schema',n.nspname,'version',e.extversion,'response_owner',(select pg_get_userbyid(relowner)from pg_class where oid='net._http_response'::regclass))from pg_extension e join pg_namespace n on n.oid=e.extnamespace where extname='pg_net';
-- Offline synthetic target: ordinary application authority before any candidate DDL
alter role postgres nosuperuser;
-- Offline synthetic target: query
select jsonb_build_object('current_user',current_user,'superuser',rolsuper,'owns_response',pg_has_role(current_user,(select relowner from pg_class where oid='net._http_response'::regclass),'USAGE'))from pg_roles where rolname=current_user;
-- Offline synthetic target: ordinary-owned diagnostic schema and exact canonical UTC function
create schema collect_ops;create function collect_ops.utc(p_time timestamptz) returns text language sql immutable set search_path='' as $$
 select to_char(p_time at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$$;
-- Offline synthetic target: missing platform index ordinary candidate denial
do $transport_index_prerequisite$
begin
 if to_regclass('net.collect_receipt_http_response_id')is null then
  if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
   from pg_class c where c.oid=to_regclass('net._http_response')),false)then
   raise exception 'receipt_transport_platform_index_prerequisite'using errcode='55000';
  end if;
  create index collect_receipt_http_response_id on net._http_response(id);
 end if;
end$transport_index_prerequisite$;
-- Offline synthetic target: declared platform-owner index provision only
create index collect_receipt_http_response_id on net._http_response(id);
-- Offline synthetic target: ordinary existing index branch
do $transport_index_prerequisite$
begin
 if to_regclass('net.collect_receipt_http_response_id')is null then
  if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
   from pg_class c where c.oid=to_regclass('net._http_response')),false)then
   raise exception 'receipt_transport_platform_index_prerequisite'using errcode='55000';
  end if;
  create index collect_receipt_http_response_id on net._http_response(id);
 end if;
end$transport_index_prerequisite$;
-- Offline synthetic target: ordinary-owned proposed strict definer validator
create function collect_ops.receipt_transport_schema_valid()returns boolean
language sql stable security definer set search_path=''as $$
 select case when to_regnamespace('net')is null
  or not has_schema_privilege(current_user,'net','USAGE')then false else coalesce(
  to_regclass('net._http_response')is not null and to_regclass('net.http_request_queue')is not null
  and not exists(
   select 1 from(values('net._http_response','id','bigint'),('net._http_response','status_code','integer'),
    ('net._http_response','content','text'),('net._http_response','timed_out','boolean'),('net._http_response','error_msg','text'),
    ('net._http_response','created','timestamp with time zone'),('net.http_request_queue','id','bigint'))required(relation,name,type)
   where not exists(select 1 from pg_attribute a where a.attrelid=to_regclass(required.relation)and a.attname=required.name
    and a.attnum>0 and not a.attisdropped and format_type(a.atttypid,a.atttypmod)=required.type
    and has_column_privilege(current_user,a.attrelid,a.attnum,'SELECT')))
  and exists(select 1 from pg_index i join pg_class ix on ix.oid=i.indexrelid
   join pg_class source on source.oid=i.indrelid join pg_am am on am.oid=ix.relam
   join pg_opclass op on op.oid=i.indclass[0] join pg_namespace opns on opns.oid=op.opcnamespace
   where i.indexrelid=to_regclass('net.collect_receipt_http_response_id')
    and i.indrelid=to_regclass('net._http_response')and ix.relkind='i'and ix.relowner=source.relowner
    and i.indisvalid and i.indisready and i.indislive and not i.indisunique and not i.indisexclusion
    and i.indnkeyatts=1 and i.indnatts=1 and i.indexprs is null and i.indpred is null
    and i.indkey[0]=(select a.attnum from pg_attribute a where a.attrelid=i.indrelid and a.attname='id'and not a.attisdropped)
    and am.amname='btree'and opns.nspname='pg_catalog'and op.opcname='int8_ops'and op.opcmethod=am.oid
    and i.indcollation[0]=0 and i.indoption[0]=0),false)end;
$$;


-- Offline synthetic target: query
select jsonb_build_object('schema_usage',has_schema_privilege('postgres','net','USAGE'),'response_table_select',has_table_privilege('postgres','net._http_response','SELECT'),'queue_table_select',has_table_privilege('postgres','net.http_request_queue','SELECT'),'headers_select',has_column_privilege('postgres','net._http_response','headers','SELECT'),'queue_body_select',has_column_privilege('postgres','net.http_request_queue','body','SELECT'));
-- Offline synthetic target: clone-only restrictive table ACL and inherited read-role fixture
revoke all on net._http_response,net.http_request_queue from public,anon,authenticated,service_role,postgres;revoke pg_read_all_data from postgres;
-- Offline synthetic target: query
select not pg_has_role(current_user,'pg_read_all_data','USAGE');
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: ordinary read prerequisite rejection
do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;
-- Offline synthetic target: exact owner-declared index usage and seven column SELECT prerequisites
-- Execute only as the net._http_response owner or its authorized platform
-- installer, before ordinary Collect migrations. This adds no client access,
-- HTTP enqueue authority, net DML or broad table-level SELECT grant.
create index if not exists collect_receipt_http_response_id on net._http_response(id);
grant usage on schema net to postgres;
grant select(id,status_code,content,timed_out,error_msg,created)on net._http_response to postgres;
grant select(id)on net.http_request_queue to postgres;

-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: ordinary satisfied read prerequisite
do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;
-- Offline synthetic target: query
select jsonb_build_object('response_table_select',has_table_privilege('postgres','net._http_response','SELECT'),'queue_table_select',has_table_privilege('postgres','net.http_request_queue','SELECT'),'headers_select',has_column_privilege('postgres','net._http_response','headers','SELECT'),'queue_body_select',has_column_privilege('postgres','net.http_request_queue','body','SELECT'),'response_dml',has_table_privilege('postgres','net._http_response','INSERT,UPDATE,DELETE'),'queue_dml',has_table_privilege('postgres','net.http_request_queue','INSERT,UPDATE,DELETE'),'client_column_select',exists(select 1 from(values('anon'),('authenticated'),('service_role'))r(role_name)where has_any_column_privilege(r.role_name,'net._http_response','SELECT')or has_any_column_privilege(r.role_name,'net.http_request_queue','SELECT')));
-- Offline synthetic target: exact source bounded sampler and original private execution restriction
create function collect_ops.receipt_transport_sample(p_http_request_id bigint,p_worker_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare response_rows integer;r record;body jsonb;code text;outcome text;status integer;response_at timestamptz;begin
 -- Never select/store headers, URLs or raw errors. Read at most two matching
 -- response rows; pg_net0.20.0 does not make its response ID unique.
 -- Count and selected metadata use one statement snapshot. An ephemeral
 -- response disappearing between count and fetch must not become a false
 -- terminal invalid-response observation.
 select count(*)as rows_observed,(array_agg(status_code))[1]as status_code,(array_agg(timed_out))[1]as timed_out,
  (array_agg(error_present))[1]as error_present,(array_agg(bounded_content))[1]as bounded_content,(array_agg(created))[1]as created into r
 from(select status_code,timed_out,nullif(error_msg,'')is not null as error_present,
  case when octet_length(content)<=1024 then content else null end as bounded_content,created
  from net._http_response where id=p_http_request_id limit 2)x;
 response_rows:=r.rows_observed;
 if response_rows=0 then
  outcome:=case when exists(select 1 from net.http_request_queue where id=p_http_request_id)then 'QUEUED_UNOBSERVED'else 'RESPONSE_UNOBSERVED'end;
 elsif response_rows=2 then outcome:='RESPONSE_CONFLICT';
 else
  if isfinite(r.created)then response_at:=r.created;end if;
  if r.status_code between 100 and 599 then status:=r.status_code;end if;
  if r.bounded_content is not null then
   begin
    body:=r.bounded_content::jsonb;
    if jsonb_typeof(body)='object'and(body-'error'-'request_id')='{}'::jsonb
     and jsonb_typeof(body->'error')='string'and(body->>'error')in('WORKER_UNCONFIGURED','WORKER_AUTH_REQUIRED','WORKER_REQUEST_INVALID',
      'WORKER_AUTHORITY_REFUSED','WORKER_ORIGINAL_CONFLICT','WORKER_LOOKUP_UNAVAILABLE','WORKER_OUTCOME_UNKNOWN','METHOD_NOT_ALLOWED')
     and((body->>'error')in('WORKER_UNCONFIGURED','WORKER_AUTH_REQUIRED','WORKER_REQUEST_INVALID','METHOD_NOT_ALLOWED')and not body?'request_id'
      or body->>'request_id'=p_worker_request_id::text)then code:=body->>'error';end if;
   exception when data_exception then code:=null;end;
  end if;
  if response_at is null or(r.timed_out is true and status is not null)or(r.error_present and status is not null)then outcome:='RESPONSE_INVALID';code:=null;
  elsif r.timed_out is true then outcome:='NETWORK_TIMEOUT';code:=null;
  elsif r.error_present then outcome:='NETWORK_FAILURE';code:=null;
  elsif status is null then outcome:='RESPONSE_INVALID';code:=null;
  elsif status=503 and code='WORKER_UNCONFIGURED'then outcome:='WORKER_CONFIG_REFUSED';
  elsif status=409 and code='WORKER_ORIGINAL_CONFLICT'then outcome:='ORIGINAL_CONFLICT';
  elsif status in(401,403)then outcome:='AUTH_REFUSED';
  elsif status in(404,405)then outcome:='ENDPOINT_UNAVAILABLE';
  elsif status in(400,409,413,415,422)then outcome:='REQUEST_REFUSED';
  elsif status=429 then outcome:='RATE_LIMITED';
  elsif status between 500 and 599 then outcome:='HTTP_SERVER_FAILURE';
  elsif status between 400 and 499 then outcome:='HTTP_REFUSED';
  elsif status=202 then outcome:='HTTP_PENDING';
  elsif status between 200 and 299 then outcome:='HTTP_ACCEPTED';
  else outcome:='HTTP_UNEXPECTED';end if;
 end if;
 return jsonb_build_object('outcome',outcome,'transport_terminal',outcome not in('QUEUED_UNOBSERVED','RESPONSE_UNOBSERVED'),
  'http_status',status,'worker_error_code',code,'response_rows_observed',response_rows,'response_at',collect_ops.utc(response_at));
end$$;revoke all on function collect_ops.receipt_transport_sample(bigint,uuid),collect_ops.receipt_transport_schema_valid()from public,anon,authenticated,service_role;
-- Offline synthetic target: query
select jsonb_build_object('owner',pg_get_userbyid(proowner),'definer',prosecdef,'search_path',proconfig)from pg_proc where oid='collect_ops.receipt_transport_sample(bigint,uuid)'::regprocedure;
-- Offline synthetic target: query
select collect_ops.receipt_transport_sample(94160001,'94160000-0000-4000-8000-000000000001');
-- Offline synthetic target: clone-only synthetic ephemeral response; no HTTP call or queue insert
insert into net._http_response(id,status_code,content,timed_out,error_msg,created)values(94160001,403,'{"error":"WORKER_AUTH_REQUIRED"}',false,null,clock_timestamp());
-- Offline synthetic target: query
select collect_ops.receipt_transport_sample(94160001,'94160000-0000-4000-8000-000000000001');
-- Offline synthetic target: clone-only duplicate response evidence; no enqueue
insert into net._http_response(id,status_code,content,timed_out,error_msg,created)values(94160001,200,'{}',false,null,clock_timestamp());
-- Offline synthetic target: query
select collect_ops.receipt_transport_sample(94160001,'94160000-0000-4000-8000-000000000001');
-- Offline synthetic target: clone-only wrong-column index negative control
drop index net.collect_receipt_http_response_id;create index collect_receipt_http_response_id on net._http_response(status_code);
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: ordinary wrong-column prerequisite refusal
do $transport_index_prerequisite$
begin
 if to_regclass('net.collect_receipt_http_response_id')is null then
  if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
   from pg_class c where c.oid=to_regclass('net._http_response')),false)then
   raise exception 'receipt_transport_platform_index_prerequisite'using errcode='55000';
  end if;
  create index collect_receipt_http_response_id on net._http_response(id);
 end if;
end$transport_index_prerequisite$;do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;
-- Offline synthetic target: restore own compatible platform index
drop index net.collect_receipt_http_response_id;create index collect_receipt_http_response_id on net._http_response(id);
-- Offline synthetic target: clone-only partial index negative control
drop index net.collect_receipt_http_response_id;create index collect_receipt_http_response_id on net._http_response(id)where id>0;
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: ordinary partial prerequisite refusal
do $transport_index_prerequisite$
begin
 if to_regclass('net.collect_receipt_http_response_id')is null then
  if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
   from pg_class c where c.oid=to_regclass('net._http_response')),false)then
   raise exception 'receipt_transport_platform_index_prerequisite'using errcode='55000';
  end if;
  create index collect_receipt_http_response_id on net._http_response(id);
 end if;
end$transport_index_prerequisite$;do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;
-- Offline synthetic target: restore own compatible platform index
drop index net.collect_receipt_http_response_id;create index collect_receipt_http_response_id on net._http_response(id);
-- Offline synthetic target: clone-only expression index negative control
drop index net.collect_receipt_http_response_id;create index collect_receipt_http_response_id on net._http_response((id+1));
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: ordinary expression prerequisite refusal
do $transport_index_prerequisite$
begin
 if to_regclass('net.collect_receipt_http_response_id')is null then
  if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
   from pg_class c where c.oid=to_regclass('net._http_response')),false)then
   raise exception 'receipt_transport_platform_index_prerequisite'using errcode='55000';
  end if;
  create index collect_receipt_http_response_id on net._http_response(id);
 end if;
end$transport_index_prerequisite$;do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;
-- Offline synthetic target: restore own compatible platform index
drop index net.collect_receipt_http_response_id;create index collect_receipt_http_response_id on net._http_response(id);
-- Offline synthetic target: clone-only individual required column ACL refusal
revoke select(content)on net._http_responsefrom postgres;
