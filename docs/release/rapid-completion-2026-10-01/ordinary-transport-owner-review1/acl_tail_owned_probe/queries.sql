-- Offline synthetic target: isolated installer owner normalization
grant pg_read_all_settings,pg_read_all_stats to postgres;alter role postgres superuser;
-- Offline synthetic target: query
select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'server',current_setting('server_version'));
-- Offline synthetic target: query
do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon nologin;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated nologin;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role nologin bypassrls;end if;end$$;
-- Offline synthetic target: actual cached platform-owned pg_net prerequisite
create schema if not exists extensions;create extension if not exists pg_net with schema extensions;
-- Offline synthetic target: clone-only exact retained platform schema usage shape
grant usage on schema net to public,postgres,anon,authenticated,service_role;
-- Offline synthetic target: query
select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'definer',p.prosecdef,'config',p.proconfig)order by p.oid::regprocedure::text),'[]')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='net'and p.proname in('http_get','http_post','http_delete');
-- Offline synthetic target: clone-only exact retained platform trusted function shape
alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;
-- Offline synthetic target: clone-only exact retained platform trusted function shape
alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;
-- Offline synthetic target: query
select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'definer',p.prosecdef,'config',p.proconfig)order by p.oid::regprocedure::text),'[]')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='net'and p.proname in('http_get','http_post','http_delete');
-- Offline synthetic target: ordinary installer before any candidate application DDL
alter role postgres nosuperuser;
-- Offline synthetic target: ordinary diagnostic schema and exact UTC helper
create schema collect_ops;create function collect_ops.utc(p_time timestamptz) returns text language sql immutable set search_path='' as $$
 select to_char(p_time at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$$;
-- Offline synthetic target: retained missing index condition only
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
-- Offline synthetic target: only platform owner provisions its response index
create index collect_receipt_http_response_id on net._http_response(id);
-- Offline synthetic target: ordinary installer cannot perform owner-only platform ACL setup
-- PROPOSAL ONLY. Execute as the actual pg_net table owner before ordinary
-- application migrations. Do not execute this as the application installer.
-- This preserves existing trusted platform functions and worker identity.
-- postgres may already inherit pg_read_all_data: these revokes normalize its
-- direct grants, not that inherited authority. No membership is changed here.
begin;
do $platform_owner$
begin
 if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
  from pg_class c where c.oid=to_regclass('net._http_response')),false)
  or not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
  from pg_class c where c.oid=to_regclass('net.http_request_queue')),false)then
  raise exception 'receipt_transport_platform_owner_required'using errcode='42501';
 end if;
 -- Receipt dispatch must already have a trusted platform definer. Do not
 -- introduce definer authority or grant queue DML to the application reader.
 if not exists(select 1 from pg_proc p join pg_class q
  on q.oid=to_regclass('net.http_request_queue')
  where p.oid=to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)')
   and p.prosecdef and p.proowner=q.relowner)then
  raise exception 'receipt_transport_platform_dispatch_prerequisite'using errcode='55000';
 end if;
end$platform_owner$;
create index if not exists collect_receipt_http_response_id on net._http_response(id);
do $private_tables$
declare relation regclass;columns text;
begin
 foreach relation in array array['net._http_response'::regclass,'net.http_request_queue'::regclass]loop
  select string_agg(quote_ident(attname),','order by attnum)into columns
   from pg_attribute where attrelid=relation and attnum>0 and not attisdropped;
  execute format('revoke all privileges on table %s from public,anon,authenticated,service_role,postgres',relation);
  -- Table REVOKE alone does not remove column ACLs.
  execute format('revoke all privileges (%s) on table %s from public,anon,authenticated,service_role,postgres',columns,relation);
 end loop;
end$private_tables$;
grant usage on schema net to postgres;
grant select(id,status_code,content,timed_out,error_msg,created)on net._http_response to postgres;
grant select(id)on net.http_request_queue to postgres;
do $private_readers$
begin
 if exists(select 1 from(values('anon'),('authenticated'),('service_role'))r(role_name)
  cross join(values('net._http_response'),('net.http_request_queue'))t(relation)
  where has_table_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   or has_any_column_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,REFERENCES'))then
  raise exception 'receipt_transport_private_tables_prerequisite'using errcode='55000';
 end if;
end$private_readers$;
commit;

-- Offline synthetic target: clone-only original PUBLIC exposure plus explicit stale column grants
grant all on net._http_response,net.http_request_queue to public;grant select(headers)on net._http_response to anon,authenticated,service_role,postgres;grant select(body)on net.http_request_queue to anon,authenticated,service_role,postgres;
-- Offline synthetic target: actual original platform raw direct-read exposure control
set role anon;select headers,content,error_msg from net._http_response limit 0;select url,headers,body from net.http_request_queue limit 0;reset role;
-- Offline synthetic target: ordinary strict type index privilege privacy validator
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
  and not exists(select 1 from(values('anon'),('authenticated'),('service_role'))r(role_name)
   cross join(values('net._http_response'),('net.http_request_queue'))t(relation)
   where has_table_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
    or has_any_column_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,REFERENCES'))
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
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: ordinary app refuses exposed platform prerequisites
do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;

-- Offline synthetic target: exact proposed owner-only full table and column revokes plus seven SELECT grants
-- PROPOSAL ONLY. Execute as the actual pg_net table owner before ordinary
-- application migrations. Do not execute this as the application installer.
-- This preserves existing trusted platform functions and worker identity.
-- postgres may already inherit pg_read_all_data: these revokes normalize its
-- direct grants, not that inherited authority. No membership is changed here.
begin;
do $platform_owner$
begin
 if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
  from pg_class c where c.oid=to_regclass('net._http_response')),false)
  or not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')
  from pg_class c where c.oid=to_regclass('net.http_request_queue')),false)then
  raise exception 'receipt_transport_platform_owner_required'using errcode='42501';
 end if;
 -- Receipt dispatch must already have a trusted platform definer. Do not
 -- introduce definer authority or grant queue DML to the application reader.
 if not exists(select 1 from pg_proc p join pg_class q
  on q.oid=to_regclass('net.http_request_queue')
  where p.oid=to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)')
   and p.prosecdef and p.proowner=q.relowner)then
  raise exception 'receipt_transport_platform_dispatch_prerequisite'using errcode='55000';
 end if;
end$platform_owner$;
create index if not exists collect_receipt_http_response_id on net._http_response(id);
do $private_tables$
declare relation regclass;columns text;
begin
 foreach relation in array array['net._http_response'::regclass,'net.http_request_queue'::regclass]loop
  select string_agg(quote_ident(attname),','order by attnum)into columns
   from pg_attribute where attrelid=relation and attnum>0 and not attisdropped;
  execute format('revoke all privileges on table %s from public,anon,authenticated,service_role,postgres',relation);
  -- Table REVOKE alone does not remove column ACLs.
  execute format('revoke all privileges (%s) on table %s from public,anon,authenticated,service_role,postgres',columns,relation);
 end loop;
end$private_tables$;
grant usage on schema net to postgres;
grant select(id,status_code,content,timed_out,error_msg,created)on net._http_response to postgres;
grant select(id)on net.http_request_queue to postgres;
do $private_readers$
begin
 if exists(select 1 from(values('anon'),('authenticated'),('service_role'))r(role_name)
  cross join(values('net._http_response'),('net.http_request_queue'))t(relation)
  where has_table_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   or has_any_column_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,REFERENCES'))then
  raise exception 'receipt_transport_private_tables_prerequisite'using errcode='55000';
 end if;
end$private_readers$;
commit;

-- Offline synthetic target: ordinary fully satisfied proposal
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

-- Offline synthetic target: query
select jsonb_agg(jsonb_build_object('relation',a.attrelid::regclass::text,'column',a.attname,'privilege',acl.privilege_type)order by a.attrelid::regclass::text,a.attnum)from pg_attribute a cross join lateral aclexplode(a.attacl)acl where a.attrelid in('net._http_response'::regclass,'net.http_request_queue'::regclass)and acl.grantee=(select oid from pg_roles where rolname='postgres');
-- Offline synthetic target: query
select jsonb_build_object('reader_direct_table_acl',exists(select 1 from pg_class c cross join lateral aclexplode(c.relacl)acl where c.oid in('net._http_response'::regclass,'net.http_request_queue'::regclass)and acl.grantee=(select oid from pg_roles where rolname='postgres')),'inherited_read_all_data',pg_has_role('postgres','pg_read_all_data','USAGE'),'inherited_headers_read',has_column_privilege('postgres','net._http_response','headers','SELECT'),'postgres_dml',has_table_privilege('postgres','net.http_request_queue','INSERT,UPDATE,DELETE')or has_table_privilege('postgres','net._http_response','INSERT,UPDATE,DELETE'));
-- Offline synthetic target: actual anon direct response whole read denial
set role anon;select * from net._http_response limit 0;reset role;
-- Offline synthetic target: actual anon direct response raw-column read denial
set role anon;select headers,content,error_msg from net._http_response limit 0;reset role;
-- Offline synthetic target: actual anon direct queue whole read denial
set role anon;select * from net.http_request_queue limit 0;reset role;
-- Offline synthetic target: actual anon direct queue raw-column read denial
set role anon;select url,headers,body from net.http_request_queue limit 0;reset role;
-- Offline synthetic target: actual anon direct response INSERT denial
set role anon;insert into net._http_response default values;reset role;
-- Offline synthetic target: actual anon direct response UPDATE denial
set role anon;update net._http_response set content=null where false;reset role;
-- Offline synthetic target: actual anon direct response DELETE denial
set role anon;delete from net._http_response where false;reset role;
-- Offline synthetic target: actual anon direct queue INSERT denial
set role anon;insert into net.http_request_queue default values;reset role;
-- Offline synthetic target: actual anon direct queue UPDATE denial
set role anon;update net.http_request_queue set body=null where false;reset role;
-- Offline synthetic target: actual anon direct queue DELETE denial
set role anon;delete from net.http_request_queue where false;reset role;
-- Offline synthetic target: actual authenticated direct response whole read denial
set role authenticated;select * from net._http_response limit 0;reset role;
-- Offline synthetic target: actual authenticated direct response raw-column read denial
set role authenticated;select headers,content,error_msg from net._http_response limit 0;reset role;
-- Offline synthetic target: actual authenticated direct queue whole read denial
set role authenticated;select * from net.http_request_queue limit 0;reset role;
-- Offline synthetic target: actual authenticated direct queue raw-column read denial
set role authenticated;select url,headers,body from net.http_request_queue limit 0;reset role;
-- Offline synthetic target: actual authenticated direct response INSERT denial
set role authenticated;insert into net._http_response default values;reset role;
-- Offline synthetic target: actual authenticated direct response UPDATE denial
set role authenticated;update net._http_response set content=null where false;reset role;
-- Offline synthetic target: actual authenticated direct response DELETE denial
set role authenticated;delete from net._http_response where false;reset role;
-- Offline synthetic target: actual authenticated direct queue INSERT denial
set role authenticated;insert into net.http_request_queue default values;reset role;
-- Offline synthetic target: actual authenticated direct queue UPDATE denial
set role authenticated;update net.http_request_queue set body=null where false;reset role;
-- Offline synthetic target: actual authenticated direct queue DELETE denial
set role authenticated;delete from net.http_request_queue where false;reset role;
-- Offline synthetic target: actual service_role direct response whole read denial
set role service_role;select * from net._http_response limit 0;reset role;
-- Offline synthetic target: actual service_role direct response raw-column read denial
set role service_role;select headers,content,error_msg from net._http_response limit 0;reset role;
-- Offline synthetic target: actual service_role direct queue whole read denial
set role service_role;select * from net.http_request_queue limit 0;reset role;
-- Offline synthetic target: actual service_role direct queue raw-column read denial
set role service_role;select url,headers,body from net.http_request_queue limit 0;reset role;
-- Offline synthetic target: actual service_role direct response INSERT denial
set role service_role;insert into net._http_response default values;reset role;
-- Offline synthetic target: actual service_role direct response UPDATE denial
set role service_role;update net._http_response set content=null where false;reset role;
-- Offline synthetic target: actual service_role direct response DELETE denial
set role service_role;delete from net._http_response where false;reset role;
-- Offline synthetic target: actual service_role direct queue INSERT denial
set role service_role;insert into net.http_request_queue default values;reset role;
-- Offline synthetic target: actual service_role direct queue UPDATE denial
set role service_role;update net.http_request_queue set body=null where false;reset role;
-- Offline synthetic target: actual service_role direct queue DELETE denial
set role service_role;delete from net.http_request_queue where false;reset role;
-- Offline synthetic target: query
select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'definer',p.prosecdef,'config',p.proconfig)order by p.oid::regprocedure::text),'[]')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='net'and p.proname in('http_get','http_post','http_delete');
-- Offline synthetic target: query
select coalesce(jsonb_agg(jsonb_build_object('role',usename,'backend',backend_type,'response_owner',pg_get_userbyid(c.relowner),'owns_tables',pg_has_role(usename,c.relowner,'USAGE'))),'[]')from pg_stat_activity a cross join pg_class c where c.oid='net._http_response'::regclass and a.backend_type ilike '%pg_net%';
-- Offline synthetic target: actual existing worker liveness only; no queue insert or HTTP API
select net.check_worker_is_up();
-- Offline synthetic target: clone-only independent column leak negative
grant select(headers)on net._http_response to authenticated;
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: ordinary preflight column leakage refusal
do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;

-- Offline synthetic target: restore leak then clone-only remove inherited read for exact minimum ACL proof
revoke select(headers)on net._http_response from authenticated;revoke pg_read_all_data from postgres;
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: original bounded sampler exact body and private function EXEC
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
select collect_ops.receipt_transport_sample(94160002,'94160000-0000-4000-8000-000000000002');
-- Offline synthetic target: only synthetic response evidence no queue or HTTP operation
insert into net._http_response(id,status_code,content,timed_out,error_msg,created)values(94160002,403,'{"error":"WORKER_AUTH_REQUIRED"}',false,null,clock_timestamp());
-- Offline synthetic target: query
select collect_ops.receipt_transport_sample(94160002,'94160000-0000-4000-8000-000000000002');
-- Offline synthetic target: individual required column missing negative
revoke select(content)on net._http_response from postgres;
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: actual definer cannot bypass required missing column
select collect_ops.receipt_transport_sample(94160003,'94160000-0000-4000-8000-000000000003');
-- Offline synthetic target: restore exact minimal ACL
grant select(content)on net._http_response to postgres;
-- Offline synthetic target: individual required column missing negative
revoke select(id)on net.http_request_queue from postgres;
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
-- Offline synthetic target: actual definer cannot bypass required missing column
select collect_ops.receipt_transport_sample(94160003,'94160000-0000-4000-8000-000000000003');
-- Offline synthetic target: restore exact minimal ACL
grant select(id)on net.http_request_queue to postgres;
-- Offline synthetic target: query
select jsonb_build_object('net',current_setting('pg_net.batch_size'),'cron',current_setting('cron.launch_active_jobs'),'queue_rows',(select count(id)from net.http_request_queue),'superuser',(select rolsuper from pg_roles where rolname=current_user),'valid',collect_ops.receipt_transport_schema_valid());
