-- Diagnostic for the 2026-09-03 rules review. Local replay only; never production.
-- Observed gaps are reported, not treated as passing production controls.
\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_setting('collect.local_gate_audit', true) is distinct from 'local-replay-only' then
    raise exception 'Explicit local replay audit marker required';
  end if;
end $$;
create temp table gate_audit(label text, observed text);
create temp table gate_fixture(owner_id uuid, joiner_id uuid, payer_id uuid, public_group uuid, private_group uuid, share_code uuid, capability uuid, phone_hash text);
insert into gate_fixture select gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),encode(extensions.digest('+250788991001','sha256'),'hex');
grant select on gate_fixture to authenticated;
grant insert,select on gate_audit to authenticated;
-- Privileged readback only: members intentionally cannot read raw visibility.
create function pg_temp.group_is_private(group_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.collections where id=group_id and visibility='private' and public_status='private');
$$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select owner_id,'authenticated','authenticated',null,now(),'{}'::jsonb,'{}'::jsonb from gate_fixture
union all select joiner_id,'authenticated','authenticated',null,now(),'{}'::jsonb,'{}'::jsonb from gate_fixture
union all select payer_id,'authenticated','authenticated',null,now(),'{}'::jsonb,'{}'::jsonb from gate_fixture;
update public.profiles set display_name=null,whatsapp_phone='250788'||lpad(floor(random()*1000000)::text,6,'0'),country_code='RW',currency_code='RWF',momo_provider='mtn_momo',momo_number='0788991001',momo_number_hash=(select phone_hash from gate_fixture),momo_pay_code=null where id=(select owner_id from gate_fixture);
update public.profiles set country_code=null,currency_code=null,momo_number=null,momo_number_hash=null,momo_provider=null where id=(select joiner_id from gate_fixture);
update public.profiles set country_code='RW',currency_code=null,momo_number='0788991003',momo_number_hash=encode(extensions.digest('+250788991003','sha256'),'hex'),momo_provider=null where id=(select payer_id from gate_fixture);
insert into public.collections(id,slug,creator_user_id,title,visibility,public_status,is_platform_sponsored)
select public_group,'gate-audit-public-'||public_group,owner_id,'Gate audit public','public_approved'::public.collection_visibility,'public_approved'::public.collection_visibility,true from gate_fixture
union all select private_group,'gate-audit-private-'||private_group,owner_id,'Gate audit private','private'::public.collection_visibility,'private'::public.collection_visibility,false from gate_fixture;
insert into public.collection_members(collection_id,user_id,role,status)
select public_group,owner_id,'owner'::public.member_role,'active'::public.member_status from gate_fixture union all select private_group,owner_id,'owner'::public.member_role,'active'::public.member_status from gate_fixture;
insert into public.collection_share_secrets(collection_id,share_code,rotated_by) select private_group,share_code,owner_id from gate_fixture;
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
select public_group,owner_id,'0788991001',phone_hash,'mtn_momo','Synthetic audit payee' from gate_fixture;
insert into public.receiver_mode_consents(user_id,enabled,momo_number_hash,build_channel) select owner_id,true,phone_hash,'android' from gate_fixture;
-- A server-side fixture substitutes for Play Integrity here. This does NOT
-- establish physical-device attestation; it tests the DB capability boundary.
insert into public.native_action_capabilities(id,user_id,action,request_hash,request_payload,receiver_momo_number_hash,package_name,app_verdict,device_verdicts,verified_at,expires_at)
select capability,owner_id,'group.create',repeat('b',64),jsonb_build_object('group_name','Gate audit created','group_description','','receiver_momo_number','0788991001','receiver_momo_number_hash',phone_hash,'receiver_label','MTN MoMo','group_collection_type','ikimina','group_category_subtype',null,'group_purpose_label',null,'group_is_public',false),phone_hash,'app.cool.mobile','PLAY_RECOGNIZED',array['MEETS_DEVICE_INTEGRITY'],now(),now()+interval '3 minutes' from gate_fixture;
set local role authenticated;
do $$
declare f gate_fixture; result uuid;
begin
 select * into f from gate_fixture;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.joiner_id,'role','authenticated')::text,true);
 result := public.join_group_by_share_code('gate-audit-public-'||f.public_group);
 insert into gate_audit values('Join public without country or MoMo','GAP: allowed');
 result := public.join_group_by_share_code(f.share_code::text);
 insert into gate_audit values('Join private without country or MoMo','GAP: allowed');
 begin
  perform public.create_contribution_intent(f.public_group,1000,repeat('c',64));
  raise exception 'No-MoMo contribution unexpectedly accepted';
 exception when others then
  if sqlerrm not like 'Use your verified WhatsApp number%' then raise; end if;
  insert into gate_audit values('Rwanda contribution without MoMo','DENIED as expected');
 end;
 begin
  perform public.admin_create_platform_public_group('Gate audit forbidden','','ikimina',null,'Audit group','Audit payee','41258','mtn_momo','Synthetic audit purpose');
  raise exception 'Non-admin public creation unexpectedly accepted';
 exception when others then
  if sqlerrm not like 'Admin permission % required' then raise; end if;
  insert into gate_audit values('Member calling public-group Admin RPC','DENIED as expected');
 end;
 begin
  insert into public.collections(slug,creator_user_id,title,visibility,public_status) values('forbidden-audit',f.joiner_id,'Forbidden audit','public_approved','public_approved');
  raise exception 'Direct group insert unexpectedly accepted';
 exception when insufficient_privilege then
  insert into gate_audit values('Member direct group insert','DENIED as expected');
 end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.payer_id,'role','authenticated')::text,true);
 perform public.create_contribution_intent(f.public_group,1000,encode(sha256(convert_to('+250788991003','UTF8')),'hex'));
 insert into gate_audit values('Contribution without profile currency or provider','GAP: allowed');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.owner_id,'role','authenticated')::text,true);
 begin
  perform public.create_private_group_with_owner_attested('Gate audit created','','0788991001',f.phone_hash,'MTN MoMo','ikimina',null,null,null);
  raise exception 'No-attestation creation unexpectedly accepted';
 exception when others then
  if sqlerrm <> 'Verify this Android device before creating a group' then raise; end if;
  insert into gate_audit values('Creation without Android capability','DENIED as expected');
 end;
 result := public.create_private_group_with_owner_attested('Gate audit created','','0788991001',f.phone_hash,'MTN MoMo','ikimina',null,null,f.capability);
 insert into gate_audit values('Creation without registered MoMo name','GAP: allowed with synthetic Android capability');
 if not pg_temp.group_is_private(result) then raise exception 'Member group was not private'; end if;
 insert into gate_audit values('Member-created group visibility','PRIVATE as expected');
 perform public.update_bank_transfer_group_profile(result,'Gate audit created','',null,null,true);
 if not pg_temp.group_is_private(result) then raise exception 'Member group promoted public'; end if;
 insert into gate_audit values('Owner attempting public visibility update','REMAINS PRIVATE as expected');
 begin
  perform public.create_private_group_with_owner_attested('Gate audit created','','0788991001',f.phone_hash,'MTN MoMo','ikimina',null,null,f.capability);
  raise exception 'Capability replay unexpectedly accepted';
 exception when others then
  if sqlerrm <> 'Android verification is invalid, expired, or already used' then raise; end if;
  insert into gate_audit values('Reused Android capability','DENIED as expected');
 end;
end $$;
reset role;
select label,observed from gate_audit order by label;
rollback;
