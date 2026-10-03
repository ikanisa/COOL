-- Execute only as the net._http_response owner or its authorized platform
-- installer, before ordinary Collect migrations. This adds no client access,
-- HTTP enqueue authority, net DML or broad table-level SELECT grant.
create index if not exists collect_receipt_http_response_id on net._http_response(id);
grant usage on schema net to postgres;
grant select(id,status_code,content,timed_out,error_msg,created)on net._http_response to postgres;
grant select(id)on net.http_request_queue to postgres;
