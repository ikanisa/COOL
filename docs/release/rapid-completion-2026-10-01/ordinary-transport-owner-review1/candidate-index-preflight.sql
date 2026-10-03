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