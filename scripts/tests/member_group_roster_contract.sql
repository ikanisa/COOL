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
select ('96000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'authenticated','authenticated','25078896000'||i,now(),'{}','{}' from generate_series(1,5) i;
update public.profiles set public_id='96000'||right(id::text,1), display_name='PRIVATE SYNTHETIC NAME'
where id::text like '96000000-0000-4000-8000-%';
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
values ('96000000-0000-4000-8000-000000000010','synthetic-roster','96000000-0000-4000-8000-000000000001',
 'Synthetic roster','Other','public_approved','public_approved','other');
insert into public.collection_members(collection_id,user_id,role,status)
select '96000000-0000-4000-8000-000000000010',('96000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 role::public.member_role,status::public.member_status from (values
 (1,'owner','active'),(2,'owner','removed'),(2,'admin','active'),(2,'member','active'),
 (3,'receiver','active'),(3,'member','active'),(4,'viewer','invited')) v(n,role,status);
insert into public.payments(collection_id,contributor_user_id,contributor_public_id,receiver_user_id,
 receiver_momo_number_hash,amount_rwf,transaction_id,source,anonymity_choice)
select '96000000-0000-4000-8000-000000000010',('96000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '96000'||n,'96000000-0000-4000-8000-000000000001',repeat('a',64),amount,'ROSTER-MOMO-'||seq,'manual_admin',choice
from (values (1,2,1000,'anonymous'),(2,2,2000,'public_id'),(3,1,500,'public_id'),(4,1,700,'anonymous'),(5,3,900,'anonymous'))
 v(seq,n,amount,choice);
insert into public.bank_transfer_destinations(id,version,beneficiary_name,iban,bic,bank_name,change_reason)
values ('96000000-0000-4000-8000-000000000040',960001,'Synthetic treasury','DE89370400440532013000',
 'COBADEFFXXX','Synthetic bank','Rollback roster test');
insert into public.bank_transfer_intents(id,collection_id,contributor_user_id,destination_id,destination_snapshot,transfer_reference,amount_minor,status)
select ('96000000-0000-4000-8000-'||lpad((40+n)::text,12,'0'))::uuid,'96000000-0000-4000-8000-000000000010',
 ('96000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'96000000-0000-4000-8000-000000000040','{}',
 'COL-ROSTER000'||n,case when n=2 then 12345 else 500 end,'reconciled' from generate_series(1,2)n;
insert into public.bank_transactions(id,transaction_key,bank_transaction_id,amount_minor,occurred_at,status,reconciled_at,payer_name)
select ('96000000-0000-4000-8000-'||lpad((20+n)::text,12,'0'))::uuid,
 encode(extensions.digest('roster-test-'||n,'sha256'),'hex'),'ROSTER-BANK-'||n,
 case when n=2 then 12345 else 500 end,now(),'reconciled',now(),'PRIVATE SYNTHETIC PAYER' from generate_series(1,2)n;
insert into public.bank_transaction_allocations(bank_transaction_id,bank_transfer_intent_id,collection_id,contributor_user_id,allocation_method,confidence,reason)
select ('96000000-0000-4000-8000-'||lpad((20+n)::text,12,'0'))::uuid,('96000000-0000-4000-8000-'||lpad((40+n)::text,12,'0'))::uuid,
 '96000000-0000-4000-8000-000000000010',('96000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'auto_exact_reference',1,'Synthetic roster' from generate_series(1,2)n;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
-- This assertion exposes the duplicate rows in the pre-repair contract.
select pg_temp.assert_true((select count(*)=4 from public.list_collection_collect_ids('96000000-0000-4000-8000-000000000010')),
 'legacy roster returns one row per Collect ID');
select set_config('collect.roster',public.list_current_member_group_roster('96000000-0000-4000-8000-000000000010')::text,true);
select pg_temp.assert_true((select count(*)=4 and count(distinct row->>'public_id')=4
 from jsonb_array_elements(current_setting('collect.roster')::jsonb)row),'new roster has one row per ID');
select pg_temp.assert_true((select row->>'role'='admin' and row->>'status'='active' and row->>'amount_scope'='own'
 and row->'contributions'='[{"currency":"EUR","amount_minor":12345},{"currency":"RWF","amount_minor":3000}]'::jsonb
 from jsonb_array_elements(current_setting('collect.roster')::jsonb)row where row->>'public_id'='960002'),
 'own role and both rail amounts are exact, without summing currencies');
select pg_temp.assert_true((select row->>'role'='owner' and row->>'amount_scope'='shared'
 and row->'contributions'='[{"currency":"RWF","amount_minor":500}]'::jsonb
 from jsonb_array_elements(current_setting('collect.roster')::jsonb)row where row->>'public_id'='960001'),
 'peer totals include only explicitly ID-visible contributions, not hidden MoMo or bank amounts');
select pg_temp.assert_true((select row->>'role'='receiver' and row->>'amount_scope'='hidden' and row->'contributions'='[]'::jsonb
 from jsonb_array_elements(current_setting('collect.roster')::jsonb)row where row->>'public_id'='960003'),
 'hidden amounts remain unavailable, not zero');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(current_setting('collect.roster')::jsonb)row
 where row ?| array['user_id','display_name','payer_name','phone','transaction_id','raw_body','anonymity_choice'])
 and current_setting('collect.roster') not like '%PRIVATE%', 'identity and evidence allowlist');
reset role;
update public.profiles set country_code='MT',currency_code='EUR' where public_id='960002';
set local role authenticated;
select pg_temp.assert_true(public.list_current_member_group_roster('96000000-0000-4000-8000-000000000010')=current_setting('collect.roster')::jsonb,
 'country change cannot alter historical roster amounts');
-- Invited accounts and public non-members do not acquire roster access.
do $$ declare n int; begin
 for n in 4..5 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub','96000000-0000-4000-8000-00000000000'||n,'role','authenticated')::text,true);
  begin
   perform public.list_current_member_group_roster('96000000-0000-4000-8000-000000000010');
   raise exception 'Unauthorized roster access allowed';
  exception when insufficient_privilege then null; end;
  begin
   perform public.list_collection_collect_ids('96000000-0000-4000-8000-000000000010');
   raise exception 'Unauthorized legacy roster access allowed';
  exception when insufficient_privilege then null; end;
 end loop;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 perform public.list_current_member_group_roster('96000000-0000-4000-8000-000000000010');
 raise exception 'Missing identity accepted';
exception when invalid_authorization_specification then null; end $$;
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.list_current_member_group_roster(uuid)','execute')
 and not has_function_privilege('anon','collect_member_actions.group_roster(uuid)','execute'),'anonymous API and helper denied');
select 'MEMBER_GROUP_ROSTER_CONTRACT_PASS';
rollback;
