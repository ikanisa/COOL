-- Synthetic fixture only: runner verifies its own pinned network-none target.
do $$begin
 if current_setting('collect.integrity_qa',true)is distinct from 'isolated_clone'
 or exists(select 1 from auth.users where id::text like '99570000-%')then
  raise exception 'Fresh task-owned Integrity target required';end if;
end$$;
insert into auth.users(id,aud,role,email,email_confirmed_at,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)values
 ('99570000-0000-4000-8000-000000000001','authenticated','authenticated','integrity-one@example.test',clock_timestamp(),'250788995701',clock_timestamp(),'{}','{}'),
 ('99570000-0000-4000-8000-000000000002','authenticated','authenticated','integrity-two@example.test',clock_timestamp(),'250788995702',clock_timestamp(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF',momo_number='0788995701',momo_provider='mtn_momo',
 momo_number_hash=repeat('a',64),momo_number_verified_at=clock_timestamp()where id::text like '99570000-%';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values
 ('99570000-0000-4000-8000-000000000011','99570000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
 ('99570000-0000-4000-8000-000000000012','99570000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
 ('99570000-0000-4000-8000-000000000021','99570000-0000-4000-8000-000000000002',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
insert into public.receiver_mode_consents(user_id,enabled,momo_number_hash,build_channel,device_label,created_at)values
 ('99570000-0000-4000-8000-000000000001',true,repeat('a',64),'android','Synthetic task fixture',clock_timestamp()),
 ('99570000-0000-4000-8000-000000000002',true,repeat('a',64),'android','Synthetic task fixture',clock_timestamp());
