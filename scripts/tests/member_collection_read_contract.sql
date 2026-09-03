\set ON_ERROR_STOP on
begin;

-- This UAT intentionally refuses all live or default databases.
do $$ begin
  if current_database() <> 'collect_uat_20260902' then
    raise exception 'Disposable Collect UAT database required';
  end if;
end $$;

create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$ begin
  if ok is not true then raise exception 'FAIL: %', message; end if;
end $$;

insert into auth.users(id, aud, role, phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data)
values
 ('92000000-0000-4000-8000-000000000001','authenticated','authenticated','250788920001',now(),'{}','{}'),
 ('92000000-0000-4000-8000-000000000002','authenticated','authenticated','250788920002',now(),'{}','{}'),
 ('92000000-0000-4000-8000-000000000003','authenticated','authenticated','250788920003',now(),'{}','{}');

insert into public.collections(id, slug, creator_user_id, title, category, visibility, public_status, collection_type)
values ('92000000-0000-4000-8000-000000000010','isolated-read-contract',
 '92000000-0000-4000-8000-000000000001','Synthetic private group','Other','private','private','other');
insert into public.collection_members(collection_id,user_id,role,status) values
 ('92000000-0000-4000-8000-000000000010','92000000-0000-4000-8000-000000000001','owner','active'),
 ('92000000-0000-4000-8000-000000000010','92000000-0000-4000-8000-000000000002','member','active');
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
values ('92000000-0000-4000-8000-000000000010','92000000-0000-4000-8000-000000000001',
 '250788920001',encode(extensions.digest('+250788920001','sha256'),'hex'),'mtn_momo','Synthetic treasury');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true(not has_table_privilege('authenticated','public.collection_receivers','SELECT'),
 'private receiver table remains inaccessible');
select pg_temp.assert_true(jsonb_array_length(public.list_current_user_collections('92000000-0000-4000-8000-000000000010'))=1,
 'active member can read their group through the scoped RPC');
select pg_temp.assert_true(public.list_current_user_collections('92000000-0000-4000-8000-000000000010')->0->>'receiver_momo_number' is null,
 'non-admin member catalogue cannot expose private receiver phone');
select pg_temp.assert_true((public.list_current_user_collections('92000000-0000-4000-8000-000000000010')->0->>'is_member')::boolean,
 'membership state drives contribution label');
select pg_temp.assert_true(not exists (
 select 1 from jsonb_array_elements(public.list_current_user_collections()) item
 where item ?| array['momo_number_hash','receiver_user_id','whatsapp_phone','display_name','raw_body']
), 'catalogue excludes private identity and evidence fields');
select pg_temp.assert_true(exists (
 select 1 from jsonb_array_elements(public.list_current_user_collections()) item
 where item->>'title'='Buri Munsi' and item->>'payment_rail'='rwanda_momo'
 and item->>'settlement_currency'='RWF' and item->>'receiver_momo_number'='41258'
 and (item->>'is_member')::boolean=false
), 'public Buri Munsi has approved Rwanda route for a non-member');

select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.assert_true(public.list_current_user_collections('92000000-0000-4000-8000-000000000010')->0->>'receiver_momo_number'='250788920001',
 'owner can read the configured private route');
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select pg_temp.assert_true(public.list_current_user_collections('92000000-0000-4000-8000-000000000010')='[]'::jsonb,
 'unrelated account cannot read an explicitly requested private group');
select pg_temp.assert_true(public.list_current_user_collections('92000000-0000-4000-8000-000000000099')='[]'::jsonb,
 'missing group returns empty without disclosing other groups');
select set_config('request.jwt.claims','{}',true);
do $$ begin
  perform public.list_current_user_collections();
  raise exception 'Missing identity was accepted';
exception when invalid_authorization_specification then null;
end $$;
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.list_current_user_collections(uuid)','EXECUTE'),
 'anonymous role cannot call member catalogue');
select 'MEMBER_COLLECTION_READ_CONTRACT_PASS';
rollback;
