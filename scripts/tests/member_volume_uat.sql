\set ON_ERROR_STOP on
begin;
set local statement_timeout='45s';
do $$ begin
  if current_database() <> 'collect_uat_20260902' then raise exception 'Disposable Collect UAT database required'; end if;
  if exists(select 1 from auth.users where id between '98000000-0000-4000-8000-000000000001' and '98000000-0000-4000-8000-000000001000') then
    raise exception 'Synthetic account namespace must be empty';
  end if;
end $$;
create function pg_temp.assert_true(ok boolean,message text) returns void
language plpgsql as $$ begin if ok is not true then raise exception 'FAIL: %',message; end if; end $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('98000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'authenticated','authenticated','250789'||lpad(n::text,6,'0'),now(),'{}','{}' from generate_series(1,1000)n;
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
values
 ('98000000-0000-4000-8000-000000010000','volume-visible','98000000-0000-4000-8000-000000000001','Synthetic volume visible','Other','private','private','other'),
 ('98000000-0000-4000-8000-000000020000','volume-private','98000000-0000-4000-8000-000000001000','Synthetic volume private','Other','private','private','other');
insert into public.collection_members(collection_id,user_id,role,status)
select '98000000-0000-4000-8000-000000010000',('98000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n=1 then 'owner' else 'member' end::public.member_role,'active' from generate_series(1,1000)n;
insert into public.collection_members(collection_id,user_id,role,status)
values ('98000000-0000-4000-8000-000000020000','98000000-0000-4000-8000-000000001000','owner','active');
insert into public.payments(id,collection_id,contributor_user_id,contributor_public_id,receiver_user_id,
 receiver_momo_number_hash,amount_rwf,transaction_id,source,anonymity_choice,posted_at)
select ('98000001-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n<=10000 then '98000000-0000-4000-8000-000000010000' else '98000000-0000-4000-8000-000000020000' end::uuid,
 ('98000000-0000-4000-8000-'||lpad((case when n<=10000 then 1+(n-1)%1000 else 1000 end)::text,12,'0'))::uuid,
 p.public_id,
 '98000000-0000-4000-8000-000000000001',repeat('a',64),1000,'VOLUME-MOMO-'||n,'manual_admin',
 case when n%2=0 then 'public_id' else 'anonymous' end,now()-n*interval '1 minute'
from generate_series(1,20000)n join public.profiles p
 on p.id=('98000000-0000-4000-8000-'||lpad((case when n<=10000 then 1+(n-1)%1000 else 1000 end)::text,12,'0'))::uuid;
insert into public.ledger_entries(payment_id,collection_id,user_id,entry_type,amount_rwf)
select p.id,p.collection_id,case when kind='member_credit' then p.contributor_user_id end,kind,p.amount_rwf
from public.payments p cross join unnest(array['collection_credit','member_credit'])kind
where p.id between '98000001-0000-4000-8000-000000000001' and '98000001-0000-4000-8000-000000020000';

insert into public.bank_transfer_destinations(id,version,beneficiary_name,iban,bic,bank_name,change_reason)
values ('98000000-0000-4000-8000-000000030000',980001,'Synthetic volume treasury','DE89370400440532013000',
 'COBADEFFXXX','Synthetic volume bank','Rollback volume fixture');
insert into public.bank_transfer_intents(id,collection_id,contributor_user_id,destination_id,destination_snapshot,
 transfer_reference,amount_minor,status,created_at)
select ('98000002-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'98000000-0000-4000-8000-000000010000',
 ('98000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'98000000-0000-4000-8000-000000030000','{}',
 'COL-VOLM'||lpad(n::text,6,'0'),12345,'reconciled',now()-n*interval '1 minute' from generate_series(1,1000)n;
insert into public.bank_transactions(id,transaction_key,bank_transaction_id,amount_minor,occurred_at,status,reconciled_at,payer_name)
select ('98000003-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,encode(extensions.digest('VOLUME-BANK-'||n,'sha256'),'hex'),
 'VOLUME-BANK-'||n,12345,now()-n*interval '1 minute','reconciled',now()-n*interval '1 minute','PRIVATE SYNTHETIC PAYER'
from generate_series(1,1000)n;
insert into public.bank_transaction_allocations(bank_transaction_id,bank_transfer_intent_id,collection_id,
 contributor_user_id,allocation_method,confidence,reason)
select ('98000003-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('98000002-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '98000000-0000-4000-8000-000000010000',('98000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'auto_exact_reference',1,'Rollback volume fixture' from generate_series(1,1000)n;
insert into public.payment_intents(id,collection_id,contributor_user_id,contribution_code,expected_amount_rwf,
 receiver_momo_number_hash,expires_at,created_at,status)
select ('98000004-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'98000000-0000-4000-8000-000000010000',
 '98000000-0000-4000-8000-000000000002','VOLUME-INTENT-'||n,1000,repeat('a',64),now()-interval '1 hour',now()-n*interval '1 minute','expired'
from generate_series(1,1000)n;
analyze public.payments;
analyze public.ledger_entries;
analyze public.collection_members;
analyze public.bank_transactions;
analyze public.bank_transaction_allocations;
analyze public.bank_transfer_intents;
analyze public.payment_intents;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare
 rpc text; started timestamptz; result jsonb; iteration int;
begin
 foreach rpc in array array['list_current_member_payment_history','list_current_member_collection_balances',
   'list_current_member_payment_intents','list_current_member_group_roster'] loop
  for iteration in 1..3 loop
   started=clock_timestamp();
   if rpc='list_current_member_group_roster' then
    result=public.list_current_member_group_roster('98000000-0000-4000-8000-000000010000');
   else execute format('select public.%I()',rpc) into result; end if;
   raise notice 'VOLUME_METRIC %',jsonb_build_object('rpc',rpc,'iteration',iteration,
     'server_ms',round(extract(epoch from clock_timestamp()-started)*1000,3),
     'rows',jsonb_array_length(result),'json_bytes',octet_length(result::text));
  end loop;
  if rpc='list_current_member_payment_history' then
   perform pg_temp.assert_true(jsonb_array_length(result)=11000,'all 11000 visible mixed-rail payments returned');
   perform pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(result)r where
    r->>'collection_id'='98000000-0000-4000-8000-000000020000' or r ?| array['payer_name','display_name','contributor_user_id']
    or (r->>'is_current_user_contribution'='false' and r->>'transaction_id' is not null)), 'private groups and peer evidence excluded at volume');
  elsif rpc='list_current_member_group_roster' then
   perform pg_temp.assert_true(jsonb_array_length(result)=1000,'1000 distinct roster entries returned');
   perform pg_temp.assert_true((select r->'contributions'='[{"currency":"EUR","amount_minor":12345},{"currency":"RWF","amount_minor":10000}]'::jsonb
     from jsonb_array_elements(result)r where r->>'amount_scope'='own'),'own roster amounts exact at volume');
  elsif rpc='list_current_member_payment_intents' then
   perform pg_temp.assert_true(jsonb_array_length(result)=1001,'all own intents returned across both rails');
  else
   perform pg_temp.assert_true((select r->>'supporter_count'='1000' and r->'balances'='[
    {"currency":"EUR","amount_raised_minor":12345000,"current_user_balance_minor":12345},
    {"currency":"RWF","amount_raised_minor":10000000,"current_user_balance_minor":10000}]'::jsonb
    from jsonb_array_elements(result)r where r->>'collection_id'='98000000-0000-4000-8000-000000010000'),
    '1000 supporters and separate authoritative balances at volume');
  end if;
 end loop;
end $$;
select 'MEMBER_VOLUME_UAT_PASS';
rollback;
