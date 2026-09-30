\set ON_ERROR_STOP on
-- Forensic reproduction, synthetic fixture only, before content-binding migration.
begin;
set local statement_timeout='30s';
do $$ begin
 if (select max(version) from supabase_migrations.schema_migrations)<>'20260929120000'
   or (select count(*) from auth.users)<>2
   or (select count(*) from public.payments where transaction_id='RACE2500' and status='review')<>1
   or exists(select 1 from public.provider_finality_requests) then
   raise exception 'Exact synthetic 135 review fixture required';
 end if;
end $$;
savepoint confirmation_case;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.process_provider_finality_event(
 '99600000-0000-4000-8000-000000000701','payment.confirmed',repeat('a',64),
 (select id from public.payments where transaction_id='RACE2500'),
 'mtn_momo','RACE2500','CONTENT-BASELINE',
 (select receiver_momo_number_hash from public.payments where transaction_id='RACE2500'),
 2500,'2026-09-29 00:00:00+00',repeat('b',64));
select 'BUG_CHANGED_AMOUNT_ACCEPTED:' || public.process_provider_finality_event(
 '99600000-0000-4000-8000-000000000702','payment.confirmed',repeat('c',64),
 (select id from public.payments where transaction_id='RACE2500'),
 'mtn_momo','RACE2500','CONTENT-BASELINE',
 (select receiver_momo_number_hash from public.payments where transaction_id='RACE2500'),
 2501,'2026-09-29 00:00:00+00',repeat('b',64))::text;
select 'BUG_SAME_HASH_CHANGED_INPUT_REPLAY:' || public.process_provider_finality_event(
 '99600000-0000-4000-8000-000000000701','payment.confirmed',repeat('a',64),
 (select id from public.payments where transaction_id='RACE2500'),
 'mtn_momo','WRONG-TRANSACTION','WRONG-CONFIRMATION',repeat('0',64),
 9999,'2026-09-28 00:00:00+00',repeat('f',64))::text;
rollback to savepoint confirmation_case;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select 'BUG_WRONG_REJECTION_IDENTITY_ACCEPTED:' || public.process_provider_finality_event(
 '99600000-0000-4000-8000-000000000703','payment.rejected',repeat('d',64),
 (select id from public.payments where transaction_id='RACE2500'),
 'airtel_money','WRONG-TRANSACTION',null,repeat('0',64),9999,
 '2026-09-29 00:00:00+00',repeat('e',64),'Synthetic contradictory rejection','WRONG-REFERENCE')::text;
rollback;
