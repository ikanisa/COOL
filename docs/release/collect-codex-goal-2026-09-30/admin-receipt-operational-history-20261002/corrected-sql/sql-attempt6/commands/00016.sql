set search_path=public,extensions,auth;set timezone='UTC';
-- Execute as the actual pg_net table owner before ordinary
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
