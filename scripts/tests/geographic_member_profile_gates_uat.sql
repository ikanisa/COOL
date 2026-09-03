-- Executed inside the runner's rollback transaction after the draft migration.
create temp table gate_results(label text primary key);
create function pg_temp.ok(condition boolean, label text) returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'FAIL: %',label; end if;
  insert into gate_results values(label);
end $$;
create function pg_temp.denied(command text, fragment text, label text) returns void language plpgsql as $$
declare message text;
begin
  begin execute command; exception when others then message:=sqlerrm; end;
  perform pg_temp.ok(message is not null and position(fragment in message)>0, label);
end $$;
create temp table fixture(rw uuid, diaspora uuid, owner_id uuid, public_group uuid, private_group uuid, share_code uuid);
insert into fixture select gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid();
grant select on fixture to authenticated;
grant select,insert on gate_results to authenticated;
insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data)
select rw,'authenticated','authenticated','{}'::jsonb,'{}'::jsonb from fixture
union all select diaspora,'authenticated','authenticated','{}'::jsonb,'{}'::jsonb from fixture
union all select owner_id,'authenticated','authenticated','{}'::jsonb,'{}'::jsonb from fixture;
update public.profiles set whatsapp_phone='250789'||lpad(floor(random()*1000000)::text,6,'0'),country_code='RW',currency_code='RWF',momo_number=null,momo_number_hash=null,momo_provider=null
where id in(select rw from fixture union all select owner_id from fixture);
update public.profiles set whatsapp_phone='356'||lpad(floor(random()*100000000)::text,8,'0'),country_code='DE',currency_code='EUR',momo_number=null,momo_number_hash=null,momo_provider=null,revolut_link=null,revolut_account=null
where id=(select diaspora from fixture);
insert into public.collections(id,slug,creator_user_id,title,visibility,public_status,is_platform_sponsored)
select public_group,'profile-gate-public-'||public_group,owner_id,'Profile gate public','public_approved'::public.collection_visibility,'public_approved'::public.collection_visibility,true from fixture
union all select private_group,'profile-gate-private-'||private_group,owner_id,'Profile gate private','private'::public.collection_visibility,'private'::public.collection_visibility,false from fixture;
insert into public.collection_share_secrets(collection_id,share_code,rotated_by) select private_group,share_code,owner_id from fixture;
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
select public_group,owner_id,'0788991123',encode(extensions.digest('+250788991123','sha256'),'hex'),'mtn_momo','Synthetic UAT payee' from fixture;
update public.feature_flags set enabled=true where key='bank_transfer_v1';
update public.bank_transfer_destinations set status='retired' where status='active';
insert into public.bank_transfer_destinations(version,beneficiary_name,iban,bic,bank_name,status,change_reason,created_by,approved_by,approved_at)
select coalesce(max(version),0)+1,'Synthetic UAT beneficiary','DE89370400440532013000','COBADEFFXXX','Synthetic UAT bank','active','Rollback profile gate UAT',
  (select rw from fixture),(select owner_id from fixture),now() from public.bank_transfer_destinations;

set local role authenticated;
do $$
declare f fixture; profile_json jsonb; created_intent jsonb; joined uuid;
begin
 select * into f from fixture;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.rw,'role','authenticated')::text,true);
 perform pg_temp.denied(format('select public.join_group_by_share_code(%L)','profile-gate-public-'||f.public_group),'valid MoMo','RW missing MoMo cannot join public');
 perform pg_temp.denied(format('select public.join_group_by_share_code(%L)',f.share_code),'valid MoMo','RW missing MoMo cannot join private');
 perform pg_temp.denied(format('select public.create_contribution_intent(%L,1000,%L)',f.public_group,repeat('a',64)),'valid MoMo','RW missing MoMo cannot contribute');
 perform pg_temp.denied(format('select public.create_private_group_with_owner_attested(%L,%L,%L,%L,%L,%L,null,null,null)','UAT group','','0788991123',repeat('a',64),'MTN MoMo','ikimina'),'valid MoMo','Incomplete creator cannot create');
 profile_json := public.update_current_member_profile('RW','mtn_momo','0788991123',null,null);
 perform pg_temp.ok(profile_json->>'momo_number'='0788991123','RW save accepts MoMo without account');
 joined := public.join_group_by_share_code(f.share_code::text);
 perform pg_temp.ok(joined=f.private_group,'Complete RW profile joins private');
 perform public.create_contribution_intent(f.public_group,1000,encode(sha256(convert_to('+250788991123','UTF8')),'hex'));
 perform pg_temp.ok(true,'Complete RW profile contributes and auto-joins public');
 perform pg_temp.denied(format('select public.create_bank_transfer_intent(%L,1000)',f.public_group),'Rwanda profiles','RW cannot bypass its rail using bank RPC');
 perform pg_temp.denied(format('select public.create_private_group_with_owner_attested(%L,%L,%L,%L,%L,%L,null,null,null)','UAT group','','0788991123',encode(sha256(convert_to('+250788991123','UTF8')),'hex'),'MTN MoMo','ikimina'),'Android device','Complete creator still requires Android verification');

 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.diaspora,'role','authenticated')::text,true);
 perform pg_temp.denied(format('select public.join_group_by_share_code(%L)','profile-gate-public-'||f.public_group),'account number','Diaspora missing account cannot explicitly join public');
 perform pg_temp.denied(format('select public.join_group_by_slug(%L)','profile-gate-public-'||f.public_group),'account number','Legacy join alias cannot bypass readiness');
 perform pg_temp.denied(format('select public.join_group_by_share_code(%L)',f.share_code),'account number','Diaspora missing account cannot join private');
 perform pg_temp.denied(format('select public.create_bank_transfer_intent(%L,1000)',f.public_group),'account number','Diaspora missing account cannot contribute');
 perform pg_temp.denied($q$select public.update_current_member_profile('DE',null,null,null,'not an account')$q$,'valid account','Account prose rejected');
 perform pg_temp.denied($q$select public.update_current_member_profile('DE',null,null,null,'💶1234')$q$,'valid account','Account emoji rejected');
 profile_json := public.update_current_member_profile('DE',null,null,null,'0001-2345 6789');
 perform pg_temp.ok(profile_json->>'revolut_account'='000123456789','Account-only save normalizes without dropping zeros');
 perform pg_temp.ok(profile_json->>'revolut_link' is null and profile_json->>'momo_number' is null,'Diaspora save requires neither link nor MoMo');
 perform pg_temp.ok(not(profile_json ? 'display_name') and not(profile_json ? 'momo_name'),'Member profile response remains name-free');
 joined := public.join_group_by_share_code(f.share_code::text);
 perform pg_temp.ok(joined=f.private_group,'Account-only diaspora joins private');
 created_intent := public.create_bank_transfer_intent(f.public_group,1000);
 perform pg_temp.ok(created_intent->>'id' is not null,'Account-only diaspora contributes and auto-joins public');
 perform pg_temp.denied(format('select public.create_contribution_intent(%L,1000,%L)',f.public_group,repeat('a',64)),'Rwanda MoMo','Diaspora cannot bypass its rail using MoMo RPC');
 perform pg_temp.denied($q$select public.admin_create_platform_public_group('UAT group','','ikimina',null,'UAT purpose','UAT payee','41258','mtn_momo','Rollback test')$q$,'Admin permission','Member remains denied public Admin creation');
end $$;
reset role;
update public.profiles set currency_code=null where id=(select rw from fixture);
set local role authenticated;
do $$ declare f fixture; begin
 select * into f from fixture;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.rw,'role','authenticated')::text,true);
 perform pg_temp.denied(format('select public.join_group_by_share_code(%L)',f.share_code),'complete your profile','Previously joined member with incomplete profile is rechecked');
 perform pg_temp.denied(format('select public.create_contribution_intent(%L,1000,%L)',f.public_group,encode(sha256(convert_to('+250788991123','UTF8')),'hex')),'complete your profile','Previously cached contribution cannot bypass missing profile currency');
end $$;
reset role;
select pg_temp.ok(not has_schema_privilege('authenticated','collect_profile_access','usage'),'Internal readiness schema not exposed to members');
select pg_temp.ok(not has_function_privilege('authenticated','collect_profile_access.assert_ready(text)','execute'),'Internal readiness helper not callable by members');
select pg_temp.ok(not has_table_privilege('authenticated','public.collections','INSERT'),'Direct group insertion still revoked');
select pg_temp.ok(not has_function_privilege('anon','public.update_current_member_profile(text,text,text,text,text)','EXECUTE'),'Anonymous profile writes remain denied');
select pg_temp.ok(not has_function_privilege('authenticated','public.create_group_with_owner_attested(text,text,text,text,text,text,text,text,boolean,uuid)','EXECUTE'),'Legacy public-flag creation remains denied');
select count(*) as passed from gate_results;
select label from gate_results order by label;
