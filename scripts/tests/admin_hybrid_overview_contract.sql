\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database() <> 'collect_uat_20260902' then
    raise exception 'Disposable Collect UAT database required';
  end if;
end $$;
do $$
declare
  actor uuid := '10000000-0000-0000-0000-000000000091';
  sms uuid;
  event uuid;
  metrics jsonb;
  before_count bigint;
  after_count bigint;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  select (item->>'value')::bigint into before_count
  from jsonb_array_elements(public.admin_overview()->'metrics') item
  where item->>'label'='Open reconciliations';
  insert into public.raw_payment_sms(receiver_user_id,raw_sender,raw_body,body_hash,parse_status)
  values(actor,'LOCAL SYNTHETIC','Synthetic Admin contract, no customer data',
    encode(extensions.digest('isolated-admin-overview','sha256'),'hex'),'parsed') returning id into sms;
  insert into public.parsed_payment_events(raw_sms_id,receiver_user_id,is_mobile_money_payment,
    network,direction,amount_rwf,currency,transaction_id,confidence,parsed_json,allocation_status)
  values(sms,actor,true,'mtn_momo','incoming',1000,'RWF','LOCAL-OVERVIEW-001',0.5,'{}','needs_review') returning id into event;
  metrics := public.admin_overview()->'metrics';
  select (item->>'value')::bigint into after_count
  from jsonb_array_elements(metrics) item where item->>'label'='Open reconciliations';
  if after_count is distinct from before_count+1 then
    raise exception 'Rwanda review event was omitted from overview';
  end if;
  if after_count is distinct from (public.admin_list_collect_reconciliations(null,null,1,0,'created_at_desc')->>'total')::bigint then
    raise exception 'Overview disagrees with canonical queue total';
  end if;
  if exists(select 1 from jsonb_array_elements(metrics) item where item->>'label'='Evidence health') then
    raise exception 'Misleading bank-only health metric remains';
  end if;
  if not exists(select 1 from jsonb_array_elements(metrics) item
    where item->>'label'='Open reconciliations' and item->>'status'='needs_review') then
    raise exception 'Open work was labelled healthy';
  end if;
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.admin_overview();
    raise exception 'Unauthenticated overview was allowed';
  exception when others then
    if sqlerrm <> 'Authentication required' then raise; end if;
  end;
  if has_function_privilege('anon','public.admin_overview()','EXECUTE') then
    raise exception 'Anonymous overview grant';
  end if;
  raise notice 'ADMIN_HYBRID_OVERVIEW_CONTRACT_PASS';
end $$;
rollback;
