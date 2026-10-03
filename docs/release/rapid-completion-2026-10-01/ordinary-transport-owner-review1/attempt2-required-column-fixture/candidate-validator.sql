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

do $transport_read_prerequisite$
begin
 if not collect_ops.receipt_transport_schema_valid()then
  raise exception 'receipt_transport_platform_read_prerequisite'using errcode='55000';
 end if;
end$transport_read_prerequisite$;