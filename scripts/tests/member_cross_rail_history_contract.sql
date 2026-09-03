\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database() <> 'collect_uat_20260902' then
    raise exception 'Disposable Collect UAT database required';
  end if;
end $$;
create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$ begin
  if ok is not true then raise exception 'FAIL: %', message; end if;
end $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('94000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  'authenticated','authenticated','25078894000' || n,now(),'{}','{}'
from generate_series(1,3) n;
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
values ('94000000-0000-4000-8000-000000000010','isolated-cross-rail',
 '94000000-0000-4000-8000-000000000001','Synthetic mixed settlement','Other','private','private','other');
insert into public.collection_members(collection_id,user_id,role,status) values
 ('94000000-0000-4000-8000-000000000010','94000000-0000-4000-8000-000000000001','owner','active'),
 ('94000000-0000-4000-8000-000000000010','94000000-0000-4000-8000-000000000002','member','active');
insert into public.payments(id,collection_id,contributor_user_id,receiver_user_id,
 receiver_momo_number_hash,amount_rwf,transaction_id,source)
select ('94000000-0000-4000-8000-' || lpad((20+n)::text,12,'0'))::uuid,
 '94000000-0000-4000-8000-000000000010','94000000-0000-4000-8000-000000000002',
 '94000000-0000-4000-8000-000000000001',repeat('a',64),n*1000,'LOCAL-MOMO-' || n,'manual_admin'
from generate_series(1,2) n;
insert into public.ledger_entries(payment_id,collection_id,user_id,entry_type,amount_rwf)
select p.id,p.collection_id,case when kind='member_credit' then p.contributor_user_id end,kind,p.amount_rwf
from public.payments p cross join unnest(array['collection_credit','member_credit']) kind
where p.collection_id='94000000-0000-4000-8000-000000000010';
insert into public.payment_intents(id,collection_id,contributor_user_id,contribution_code,
 expected_amount_rwf,receiver_momo_number_hash,expires_at)
values ('94000000-0000-4000-8000-000000000030','94000000-0000-4000-8000-000000000010',
 '94000000-0000-4000-8000-000000000002','LOCAL-CROSS-RAIL',1000,repeat('a',64),now()-interval '1 hour');

insert into public.bank_transfer_destinations(id,version,beneficiary_name,iban,bic,bank_name,change_reason)
values ('94000000-0000-4000-8000-000000000040',940001,'Synthetic treasury',
 'DE89370400440532013000','COBADEFFXXX','Synthetic bank','Rollback-only cross-rail test');
insert into public.bank_transfer_intents(id,collection_id,contributor_user_id,destination_id,
 destination_snapshot,transfer_reference,amount_minor,status)
select ('94000000-0000-4000-8000-' || lpad((40+n)::text,12,'0'))::uuid,
 '94000000-0000-4000-8000-000000000010',
 ('94000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 '94000000-0000-4000-8000-000000000040','{}','COL-LOCAL0000' || n,
 case when n=2 then 12345 else 500 end,'reconciled'
from generate_series(1,2) n;
insert into public.bank_transactions(id,transaction_key,bank_transaction_id,amount_minor,
 occurred_at,status,reconciled_at,payer_name)
select ('94000000-0000-4000-8000-' || lpad((20+n)::text,12,'0'))::uuid,
 encode(extensions.digest('local-cross-rail-' || n,'sha256'),'hex'),'LOCAL-BANK-' || n,
 case when n=2 then 12345 else 500 end,now(),'reconciled',now(),'PRIVATE SYNTHETIC PAYER'
from generate_series(1,2) n;
insert into public.bank_transaction_allocations(bank_transaction_id,bank_transfer_intent_id,
 collection_id,contributor_user_id,allocation_method,confidence,reason)
select ('94000000-0000-4000-8000-' || lpad((20+n)::text,12,'0'))::uuid,
 ('94000000-0000-4000-8000-' || lpad((40+n)::text,12,'0'))::uuid,
 '94000000-0000-4000-8000-000000000010',
 ('94000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'auto_exact_reference',1,'Synthetic read-contract fixture'
from generate_series(1,2) n;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true(jsonb_array_length(public.list_current_member_payment_history())=4,
 'both rails returned, no shared UUID collision or truncation');
select pg_temp.assert_true((select count(distinct row->>'payment_id')=4
 from jsonb_array_elements(public.list_current_member_payment_history()) row), 'rail-qualified history identifiers');
select pg_temp.assert_true((select count(*)=3
 from jsonb_array_elements(public.list_current_member_payment_history()) row
 where (row->>'is_current_user_contribution')::boolean), 'own history distinct from group history');
select pg_temp.assert_true(not exists(select 1
 from jsonb_array_elements(public.list_current_member_payment_history()) row
 where row ?| array['payer_name','display_name','contributor_user_id','raw_body','sender_phone_hash']
 or (not (row->>'is_current_user_contribution')::boolean and row->>'transaction_id' is not null)),
 'private identity and peer references excluded');
select pg_temp.assert_true(not exists(select 1 from public.list_current_user_bank_contributions()
 where not is_current_user_contribution and transaction_id is not null), 'legacy bank contract also masks peer references');
select pg_temp.assert_true((select (row->>'supporter_count')::int=2
 from jsonb_array_elements(public.list_current_member_collection_balances()) row
 where row->>'collection_id'='94000000-0000-4000-8000-000000000010'),
 'same user across two rails and multiple receipts counted once');
select pg_temp.assert_true((select row->'balances'='[
 {"currency":"EUR","amount_raised_minor":12845,"current_user_balance_minor":12345},
 {"currency":"RWF","amount_raised_minor":3000,"current_user_balance_minor":3000}]'::jsonb
 from jsonb_array_elements(public.list_current_member_collection_balances()) row
 where row->>'collection_id'='94000000-0000-4000-8000-000000000010'),
 'independent authoritative RWF and EUR total/own balances');
select pg_temp.assert_true(jsonb_array_length(public.list_current_member_payment_intents())=2,
 'both original intent rails retained despite missing historical receiver');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.list_current_member_payment_intents()) row
 where row->>'rail'='rwanda_momo' and row->>'currency'='RWF' and row->>'status'='expired'),
 'read-only computed expiry and original currency');
select set_config('collect.uat_history',public.list_current_member_payment_history()::text,true);
select set_config('collect.uat_balances',public.list_current_member_collection_balances()::text,true);
select set_config('collect.uat_intents',public.list_current_member_payment_intents()::text,true);
reset role;
update public.profiles set country_code='MT',currency_code='EUR'
where id='94000000-0000-4000-8000-000000000002';
select pg_temp.assert_true((select status='pending' from public.payment_intents
 where id='94000000-0000-4000-8000-000000000030'), 'history read did not mutate intent status');
set local role authenticated;
select pg_temp.assert_true(public.list_current_member_payment_history()=current_setting('collect.uat_history')::jsonb,
 'country change preserves all history');
select pg_temp.assert_true(public.list_current_member_collection_balances()=current_setting('collect.uat_balances')::jsonb,
 'country change preserves all balances');
select pg_temp.assert_true(public.list_current_member_payment_intents()=current_setting('collect.uat_intents')::jsonb,
 'country change preserves all intents');

select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select pg_temp.assert_true(public.list_current_member_payment_history()='[]', 'outsider cannot read private history');
select pg_temp.assert_true(public.list_current_member_payment_intents()='[]', 'outsider cannot read intents');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.list_current_member_collection_balances()) row
 where row->>'collection_id'='94000000-0000-4000-8000-000000000010'), 'outsider cannot read private balances');
select set_config('request.jwt.claims','{}',true);
do $$ begin
  begin perform public.list_current_member_payment_history(); raise exception 'missing identity accepted';
    exception when invalid_authorization_specification then null; end;
  begin perform public.list_current_member_payment_intents(); raise exception 'missing identity accepted';
    exception when invalid_authorization_specification then null; end;
  begin perform public.list_current_member_collection_balances(); raise exception 'missing identity accepted';
    exception when invalid_authorization_specification then null; end;
end $$;
reset role;
-- Leaving a private group removes aggregate/peer access, not one's own history.
update public.collection_members set status='left'
where collection_id='94000000-0000-4000-8000-000000000010'
 and user_id='94000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true(jsonb_array_length(public.list_current_member_payment_history())=3
 and not exists(select 1 from jsonb_array_elements(public.list_current_member_payment_history()) row
   where not (row->>'is_current_user_contribution')::boolean), 'former member keeps only own history');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.list_current_member_collection_balances()) row
 where row->>'collection_id'='94000000-0000-4000-8000-000000000010'), 'former member loses private aggregate access');
reset role;
insert into public.payments(collection_id,receiver_user_id,receiver_momo_number_hash,
 amount_rwf,transaction_id,source) values
 ('94000000-0000-4000-8000-000000000010','94000000-0000-4000-8000-000000000001',
 repeat('a',64),1000,'LOCAL-ANONYMOUS','manual_admin');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.assert_true((select row->'supporter_count'='null'::jsonb
 from jsonb_array_elements(public.list_current_member_collection_balances()) row
 where row->>'collection_id'='94000000-0000-4000-8000-000000000010'), 'unlinked anonymous receipts cannot prove distinct people');
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.list_current_member_payment_history()','EXECUTE')
 and not has_function_privilege('anon','public.list_current_member_payment_intents()','EXECUTE')
 and not has_function_privilege('anon','public.list_current_member_collection_balances()','EXECUTE'), 'anonymous grants closed');
select 'MEMBER_CROSS_RAIL_HISTORY_CONTRACT_PASS';
rollback;
