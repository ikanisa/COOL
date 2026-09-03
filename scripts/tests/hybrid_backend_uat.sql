\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'collect_hybrid_uat_20260902' then raise exception 'Isolated local hybrid UAT database required'; end if;
  if exists(select 1 from auth.users) then raise exception 'Synthetic UAT requires empty account namespace'; end if;
end $$;
create temp table test_results(label text primary key);
create temp table test_values(key text primary key, value jsonb);
grant all on pg_temp.test_results, pg_temp.test_values to authenticated, service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end; $$;
create function pg_temp.expect_error(command text, fragment text, label text) returns void language plpgsql as $$
declare caught text;
begin
  begin execute command; exception when others then caught := sqlerrm; end;
  perform pg_temp.assert_true(caught is not null and position(fragment in caught)>0, label);
end; $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values
 ('96000000-0000-4000-8000-000000000001','authenticated','authenticated','250788000001',now(),'{}','{}'),
 ('96000000-0000-4000-8000-000000000002','authenticated','authenticated','250788000002',now(),'{}','{}'),
 ('96000000-0000-4000-8000-000000000003','authenticated','authenticated','250788000003',now(),'{}','{}');
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000001","role":"service_role"}',true);
update public.profiles set is_platform_admin=true where id='96000000-0000-4000-8000-000000000001';
select pg_temp.assert_true((select count(*)=3 from collect_hybrid.member_records), 'app profile insertion reserves registry IDs');
select pg_temp.assert_true((select bool_and(m.collect_id=p.public_id) from collect_hybrid.member_records m join public.profiles p on p.id=m.linked_user_id), 'app IDs remain unchanged');
select pg_temp.assert_true(not has_table_privilege('authenticated','collect_hybrid.member_momo_identities','SELECT'), 'PII table is inaccessible to authenticated clients');
select pg_temp.assert_true(not has_table_privilege('anon','collect_hybrid.member_records','SELECT'), 'registry is inaccessible to anonymous clients');
select pg_temp.assert_true(not has_function_privilege('anon','public.admin_create_assisted_group(text,text,uuid)','EXECUTE'), 'anonymous group RPC is denied');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.ingest_raw_payment_sms(uuid,uuid,text,text,text,uuid,text,timestamptz)','EXECUTE'), 'raw ingest RPC is service-only');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.expect_error($q$select public.admin_create_assisted_group('Synthetic savings','Synthetic UAT creation','96000000-0000-4000-8000-000000000099')$q$, 'disabled', 'onboarding feature defaults off');
reset role;
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.expect_error($q$select public.admin_create_assisted_group('Synthetic savings','Synthetic UAT creation','96000000-0000-4000-8000-000000000099')$q$, 'Admin permission', 'ordinary member cannot create assisted group');
select pg_temp.expect_error($q$select collect_hybrid.create_assisted_group('Synthetic savings','Synthetic UAT creation','96000000-0000-4000-8000-000000000099')$q$, 'Admin permission', 'direct private command retains authorization');
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into pg_temp.test_values values('group', public.admin_create_assisted_group('Synthetic savings','Synthetic UAT creation','96000000-0000-4000-8000-000000000099'));
insert into pg_temp.test_values values('public_group', public.admin_create_platform_public_group(
 'Synthetic public savings','Synthetic public group','ikimina',null,'Synthetic savings',
 'Synthetic receiver','41259','mtn_momo','Synthetic compatibility UAT'));
select pg_temp.assert_true((select value->>'visibility'='private' and value->>'route_ready'='false' from pg_temp.test_values where key='group'), 'assisted group is private and has no invented route');
select pg_temp.assert_true(public.admin_create_assisted_group('Synthetic savings','Synthetic UAT creation','96000000-0000-4000-8000-000000000099')->>'replay'='true', 'group creation retry is idempotent');
select pg_temp.expect_error($q$select public.admin_create_assisted_group('Changed savings','Synthetic UAT creation','96000000-0000-4000-8000-000000000099')$q$, 'idempotency key conflict', 'group request cannot silently change inputs');
insert into pg_temp.test_values values('roster', public.admin_add_assisted_roster(
 (select (value->>'collection_id')::uuid from pg_temp.test_values where key='group'),
 '[{"member_name":"TEST MEMBER A","momo_name":"TEST MEMBER A","momo_number":"0788123456"},{"member_name":"TEST MEMBER B","momo_name":"TEST MEMBER B","momo_number":"+250732123789"}]',
 '96000000-0000-4000-8000-000000000010','Reviewed synthetic roster'));
insert into pg_temp.test_values values('replay', public.admin_add_assisted_roster(
 (select (value->>'collection_id')::uuid from pg_temp.test_values where key='group'),
 '[{"member_name":"TEST MEMBER A","momo_name":"TEST MEMBER A","momo_number":"0788123456"},{"member_name":"TEST MEMBER B","momo_name":"TEST MEMBER B","momo_number":"+250732123789"}]',
 '96000000-0000-4000-8000-000000000010','Reviewed synthetic roster'));
select pg_temp.assert_true((select value->>'replay'='true' from pg_temp.test_values where key='replay'), 'identical roster replay is idempotent');
select pg_temp.expect_error($q$select public.admin_add_assisted_roster(
 (select (value->>'collection_id')::uuid from pg_temp.test_values where key='group'),
 '[{"momo_name":"CHANGED NAME","momo_number":"0788123456"}]',
 '96000000-0000-4000-8000-000000000010','Reviewed synthetic roster')$q$, 'idempotency key conflict', 'changed roster cannot reuse request key');
select pg_temp.expect_error($q$select public.admin_add_assisted_roster(
 (select (value->>'collection_id')::uuid from pg_temp.test_values where key='group'),
 '[{"momo_name":"TEST MEMBER C","momo_number":"0788123000"},{"momo_name":"INVALID","momo_number":"123"}]',
 '96000000-0000-4000-8000-000000000011','Reviewed synthetic roster')$q$, 'Invalid Rwanda MoMo number', 'bad batch fails atomically');
select pg_temp.expect_error($q$select public.admin_add_assisted_roster(
 (select (value->>'collection_id')::uuid from pg_temp.test_values where key='group'),
 '[{"momo_name":"WRONG NAME","momo_number":"0788123456"}]',
 '96000000-0000-4000-8000-000000000012','Reviewed synthetic roster')$q$, 'identity differs', 'existing phone cannot silently change identity');
reset role;
select pg_temp.assert_true((select creation_origin='platform_sponsored' and is_platform_sponsored and public_status='public_approved'
 from public.collections where id=(select (value->>'collection_id')::uuid from pg_temp.test_values where key='public_group')), 'existing public creation remains sponsored and public');
select pg_temp.assert_true((select count(*)=3 from auth.users), 'offline roster creates no fake Auth users');
select pg_temp.assert_true((select count(*)=2 from collect_hybrid.member_momo_identities), 'failed batch and retries create no extra identities');
select pg_temp.assert_true((select count(*)=2 from public.collection_members where user_id is null and member_record_id is not null), 'offline memberships do not require app account');
select pg_temp.assert_true((select momo_number='+250788123456' and last3='456'
 and match_key=encode(extensions.digest('TEST MEMBER A|456','sha256'),'hex')
 from collect_hybrid.member_momo_identities where momo_number='+250788123456'), 'canonical phone and easyMO match key agree');
select pg_temp.assert_true((select count(*)=count(distinct collect_id) from collect_hybrid.member_records), 'one numeric ID namespace');
select pg_temp.expect_error($q$update public.profiles set public_id=(select collect_id from collect_hybrid.member_records where linked_user_id is null limit 1)
 where id='96000000-0000-4000-8000-000000000002'$q$, 'reviewed account-link', 'public ID cannot overwrite offline member identity');
delete from auth.users where id='96000000-0000-4000-8000-000000000003';
select pg_temp.assert_true(exists(select 1 from collect_hybrid.member_records where id='96000000-0000-4000-8000-000000000003' and linked_user_id is null), 'account deletion retains member ID reservation');

insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
select (value->>'collection_id')::uuid,'96000000-0000-4000-8000-000000000001','41258',repeat('a',64),'mtn_momo','Synthetic receiver'
from pg_temp.test_values where key='group';
insert into public.receiver_mode_consents(user_id,enabled,momo_number_hash,build_channel)
values ('96000000-0000-4000-8000-000000000001',true,repeat('a',64),'internal_receiver');
insert into pg_temp.test_values values('body',to_jsonb(E'  You have received 1,500 RWF from TEST MEMBER A (***456). Your balance: 9,500 RWF.\r\n'::text));
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into pg_temp.test_values values('sms',public.ingest_raw_payment_sms(
 '96000000-0000-4000-8000-000000000001',null,'M-Money',(select value#>>'{}' from pg_temp.test_values where key='body'),
 encode(extensions.digest((select value#>>'{}' from pg_temp.test_values where key='body'),'sha256'),'hex'),
 '96000000-0000-4000-8000-000000000020',repeat('a',64),'2026-09-02T10:00:00+02:00'));
insert into pg_temp.test_values values('sms_replay',public.ingest_raw_payment_sms(
 '96000000-0000-4000-8000-000000000001',null,'M-Money',(select value#>>'{}' from pg_temp.test_values where key='body'),
 encode(extensions.digest((select value#>>'{}' from pg_temp.test_values where key='body'),'sha256'),'hex'),
 '96000000-0000-4000-8000-000000000021',repeat('a',64),'2026-09-02T10:00:00+02:00'));
select pg_temp.assert_true((select value->>'id' from pg_temp.test_values where key='sms')=(select value->>'id' from pg_temp.test_values where key='sms_replay'), 'alternate envelope of same observed receipt deduplicates');
insert into pg_temp.test_values values('sms_later',public.ingest_raw_payment_sms(
 '96000000-0000-4000-8000-000000000001',null,'M-Money',(select value#>>'{}' from pg_temp.test_values where key='body'),
 encode(extensions.digest((select value#>>'{}' from pg_temp.test_values where key='body'),'sha256'),'hex'),
 '96000000-0000-4000-8000-000000000022',repeat('a',64),'2026-09-02T10:01:00+02:00'));
select pg_temp.assert_true((select value->>'id' from pg_temp.test_values where key='sms')<>(select value->>'id' from pg_temp.test_values where key='sms_later'), 'same text at different original time remains distinct evidence');
select pg_temp.expect_error($q$select public.ingest_raw_payment_sms(
 '96000000-0000-4000-8000-000000000001',null,'M-Money','changed body',encode(extensions.digest('changed body','sha256'),'hex'),
 '96000000-0000-4000-8000-000000000020',repeat('a',64),'2026-09-02T10:00:00+02:00')$q$, 'envelope evidence changed', 'conflicting envelope replay is rejected');
select pg_temp.expect_error($q$select public.ingest_raw_payment_sms(
 '96000000-0000-4000-8000-000000000001',null,'M-Money','changed body',repeat('f',64),
 '96000000-0000-4000-8000-000000000023',repeat('a',64),'2026-09-02T10:00:00+02:00')$q$, 'Invalid raw SMS', 'server verifies exact raw body hash');
select pg_temp.expect_error($q$select public.ingest_raw_payment_sms(
 '96000000-0000-4000-8000-000000000002',null,'M-Money','synthetic body',encode(extensions.digest('synthetic body','sha256'),'hex'),
 '96000000-0000-4000-8000-000000000024',repeat('a',64),'2026-09-02T10:00:00+02:00')$q$, 'not authorized', 'receiver ownership and capture consent remain enforced');
reset role;
select pg_temp.assert_true((select bool_and(raw_body=(select value#>>'{}' from pg_temp.test_values where key='body')) from public.raw_payment_sms), 'exact raw body whitespace survives database ingestion');
select pg_temp.expect_error($q$update public.raw_payment_sms set raw_body='modified'$q$, 'immutable', 'source evidence remains immutable');
select pg_temp.assert_true((select count(*)=0 from public.payments), 'foundation does not silently post money');
select pg_temp.assert_true((select count(*)=0 from public.notification_events), 'foundation does not send or enqueue legacy pushes');
select 'PASS ' || label from pg_temp.test_results order by label;
select 'HYBRID_BACKEND_UAT_PASS: ' || count(*) || ' assertions; synthetic rollback only' from pg_temp.test_results;
rollback;
