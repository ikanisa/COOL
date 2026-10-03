begin;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99780000-0000-4000-8000-000000000002','authenticated','authenticated','250788971002',clock_timestamp(),'{}','{}');
update public.profiles set country_code='FR',currency_code='EUR' where id='99780000-0000-4000-8000-000000000002';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99780000-0000-4000-8000-000000000001','+250788971001',clock_timestamp()-interval '2 minutes','Synthetic upgrade identity only');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99780000-0000-4000-8000-000000000001',r.id,'Synthetic upgrade authority',clock_timestamp()-interval '1 minute'from public.admin_roles r where r.name='platform_owner'
and not exists(select 1 from public.admin_user_roles g where g.user_id='99780000-0000-4000-8000-000000000001' and g.role_id=r.id and g.revoked_at is null);
update public.admin_user_roles set created_at=clock_timestamp()-interval '1 minute'
where user_id='99780000-0000-4000-8000-000000000001' and revoked_at is null;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99780000-0000-4000-8000-000000010001','99780000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
insert into public.admin_role_permissions(role_id,permission_name)
select r.id,p.name from public.admin_roles r cross join public.admin_permissions p where r.name='platform_owner' on conflict do nothing;
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,
contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin)
values('99780000-0000-4000-8000-000000030001','current-upgrade-synthetic','99780000-0000-4000-8000-000000000001','Synthetic current upgrade','Family / friends','private','private','ikimina','members',false,false,'admin_assisted');
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)
values('99780000-0000-4000-8000-000000030001','99780000-0000-4000-8000-000000000001','+250788971001','3d6c04fc794d3efe9b717ec98edae1722ae8c9f883d5a007ca50a787c9c446ec','mtn_momo');
insert into collect_hybrid.member_records(id,collect_id,origin,created_by)values('99780000-0000-4000-8000-000000040001','978201','admin_assisted','99780000-0000-4000-8000-000000000001');
insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
values('99780000-0000-4000-8000-000000040001','Synthetic upgrade member','SYNTHETIC MEMBER','+250788978201');
insert into public.collection_members(collection_id,member_record_id,role,status)values('99780000-0000-4000-8000-000000030001','99780000-0000-4000-8000-000000040001','member','active');
insert into collect_hybrid.sms_receipt_policies(collection_id,enabled,reason,updated_by)
values('99780000-0000-4000-8000-000000030001',true,'Synthetic upgrade receipt policy','99780000-0000-4000-8000-000000000001');
insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by)
values('99780000-0000-4000-8000-000000040001',true,'written','Synthetic upgrade consent','99780000-0000-4000-8000-000000000001');
insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,
receiver_momo_number_hash,parse_status,received_at_device)
values('99780000-0000-4000-8000-000000060001','99780000-0000-4000-8000-000000030001','99780000-0000-4000-8000-000000000001','M-Money','Synthetic retained financial observation',encode(extensions.digest('Synthetic retained financial observation','sha256'),'hex'),'3d6c04fc794d3efe9b717ec98edae1722ae8c9f883d5a007ca50a787c9c446ec','parsed',clock_timestamp()-interval '1 day');
insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,
network,currency,direction,receiver_phone_hash,amount_rwf,transaction_id,allocation_status,sender_name)
values('99780000-0000-4000-8000-000000070001','99780000-0000-4000-8000-000000060001','99780000-0000-4000-8000-000000030001','99780000-0000-4000-8000-000000000001',true,'mtn_momo','RWF','incoming','3d6c04fc794d3efe9b717ec98edae1722ae8c9f883d5a007ca50a787c9c446ec',300,'UPGRADE-300','unallocated','Synthetic payer');
commit;