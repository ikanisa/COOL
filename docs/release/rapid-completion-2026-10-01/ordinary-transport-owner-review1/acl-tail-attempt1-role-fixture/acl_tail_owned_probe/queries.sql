-- Offline synthetic target: isolated installer owner normalization
grant pg_read_all_settings,pg_read_all_stats to postgres;alter role postgres superuser;
-- Offline synthetic target: query
select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'server',current_setting('server_version'));
-- Offline synthetic target: query
do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon nologin;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated nologin;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role nologin bypassrls;end if;end$$;
-- Offline synthetic target: actual cached platform-owned pg_net prerequisite
create schema if not exists extensions;create extension if not exists pg_net with schema extensions;
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
select headers,content,error_msg from net._http_response limit 0;select url,headers,body from net.http_request_queue limit 0;
