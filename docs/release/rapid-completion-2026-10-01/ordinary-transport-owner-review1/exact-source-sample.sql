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
end$$;