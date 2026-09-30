\set ON_ERROR_STOP on
begin;
create temp table sms_result(payload jsonb not null);
grant all on pg_temp.sms_result to service_role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
insert into pg_temp.sms_result
select public.finalize_attested_payment_sms(
  '90000000-0000-4000-8000-000000000001'
);
reset role;

do $$
declare result jsonb;
begin
  select payload into result from pg_temp.sms_result;
  if result ->> 'status' <> 'awaiting_reconciliation'
     or result ->> 'evidence_level' <> 'sms_observed'
     or result ->> 'payment_id' is not null then
    raise exception 'SMS result did not fail closed';
  end if;
  if (select status from public.payments
      where id = '90000000-0000-4000-8000-000000000002') <> 'review'
     or exists(select 1 from public.ledger_entries) then
    raise exception 'SMS function changed financial state';
  end if;
  if has_function_privilege('authenticated',
       'public.finalize_attested_payment_sms(uuid)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.finalize_attested_payment_sms(uuid)', 'EXECUTE') then
    raise exception 'SMS function privileges are wrong';
  end if;
  begin
    perform public.finalize_attested_payment_sms(
      '90000000-0000-4000-8000-000000000003');
    raise exception 'Unknown receipt was accepted';
  exception when sqlstate '22023' then null;
  end;
end;
$$;

select 'SMS_OBSERVATION_SQL_SCRATCH_PASS';
rollback;
