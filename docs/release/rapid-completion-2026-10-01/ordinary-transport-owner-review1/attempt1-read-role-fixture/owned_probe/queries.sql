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
-- Offline synthetic target: clone-only restrictive table ACL fixture
revoke all on net._http_response,net.http_request_queue from public,anon,authenticated,service_role,postgres;
-- Offline synthetic target: query
select collect_ops.receipt_transport_schema_valid();
