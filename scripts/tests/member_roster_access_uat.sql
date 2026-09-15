\set ON_ERROR_STOP on
begin;
set local statement_timeout='30s';
do $$ begin
  if current_database()<>'collect_uat_20260902' then
    raise exception 'Dedicated cloned Collect SQL fixture required';
  end if;
end $$;
create temp table access_results(label text primary key, passed boolean not null);
grant select,insert on access_results to authenticated;
create function pg_temp.check_access(ok boolean,label text) returns void
language sql as $$ insert into pg_temp.access_results values(label,coalesce(ok,false)) $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('99400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'authenticated','authenticated','250788994'||lpad(n::text,3,'0'),now(),'{}','{}'
from generate_series(1,10)n;
insert into public.collections(id,slug,creator_user_id,title,visibility,public_status)
values
('99400000-0000-4000-8000-000000000020','roster-access-public','99400000-0000-4000-8000-000000000001',
 'Synthetic roster public','public_approved','public_approved'),
('99400000-0000-4000-8000-000000000021','roster-access-private','99400000-0000-4000-8000-000000000001',
 'Synthetic roster private','private','private');
insert into public.collection_members(collection_id,user_id,role,status)
select ('99400000-0000-4000-8000-'||lpad(g::text,12,'0'))::uuid,
 ('99400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'member',status::public.member_status
from generate_series(20,21)g cross join
 (values(2,'active'),(3,'invited'),(4,'left'),(5,'removed'))fixture(n,status);
-- Both established links and verified claims must retain active membership.
insert into collect_hybrid.member_records(id,collect_id,lifecycle,origin)
values
('99400000-0000-4000-8000-000000000099',public.generate_public_id(),'active','admin_assisted'),
('99400000-0000-4000-8000-000000000100',public.generate_public_id(),'inactive','admin_assisted');
insert into collect_hybrid.member_account_claims(member_record_id,user_id,verified_phone_sha256,identity_revision)
values
('99400000-0000-4000-8000-000000000099','99400000-0000-4000-8000-000000000008',repeat('a',64),1),
('99400000-0000-4000-8000-000000000100','99400000-0000-4000-8000-000000000009',repeat('b',64),1);
insert into public.collection_members(collection_id,member_record_id,role,status)
select ('99400000-0000-4000-8000-'||lpad(g::text,12,'0'))::uuid,
 ('99400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'member','active'
from generate_series(20,21)g cross join (values(7),(99),(100))record(n);
-- This operator really has platform access, but no group membership.
insert into public.admin_user_roles(user_id,role_id,reason)
select '99400000-0000-4000-8000-000000000010',id,'Synthetic unrelated platform operator'
from public.admin_roles where name='platform_owner';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason)
values ('99400000-0000-4000-8000-000000000010','+250788994010','Synthetic operator fixture');
insert into auth.sessions(id,user_id,created_at)
values ('99410000-0000-4000-8000-000000000010','99400000-0000-4000-8000-000000000010',clock_timestamp());

set local role authenticated;
do $$
declare
  n integer; g integer; group_id uuid; expected boolean;
  primary_allowed boolean; legacy_allowed boolean; primary_denied boolean; legacy_denied boolean;
  roster jsonb; row_count bigint;
begin
  for g in 20..21 loop
    group_id:=('99400000-0000-4000-8000-'||lpad(g::text,12,'0'))::uuid;
    for n in 1..10 loop
      perform set_config('request.jwt.claims',jsonb_build_object(
        'sub','99400000-0000-4000-8000-'||lpad(n::text,12,'0'),'role','authenticated',
        'session_id',case when n=10 then '99410000-0000-4000-8000-000000000010' end)::text,true);
      expected:=n in (1,2,7,8);
      if n=10 then
        perform pg_temp.check_access(public.has_admin_permission('overview.read'),g||':operator fixture is authorized');
      end if;
      primary_allowed:=false; legacy_allowed:=false;
      primary_denied:=false; legacy_denied:=false;
      begin
        roster:=public.list_current_member_group_roster(group_id);
        primary_allowed:=jsonb_typeof(roster)='array' and jsonb_array_length(roster)>0;
      exception when insufficient_privilege then primary_denied:=true; end;
      begin
        select count(*) into row_count from public.list_collection_collect_ids(group_id);
        legacy_allowed:=row_count>0;
      exception when insufficient_privilege then legacy_denied:=true; end;
      perform pg_temp.check_access(case when expected then primary_allowed else primary_denied end,g||':actor '||n||':current roster access');
      perform pg_temp.check_access(case when expected then legacy_allowed else legacy_denied end,g||':actor '||n||':installed-client roster access');
    end loop;
    perform set_config('request.jwt.claims','{}',true);
    primary_allowed:=false; legacy_allowed:=false;
    begin perform public.list_current_member_group_roster(group_id); primary_allowed:=true;
    exception when invalid_authorization_specification then null; end;
    begin perform public.list_collection_collect_ids(group_id); legacy_allowed:=true;
    exception when invalid_authorization_specification then null; end;
    perform pg_temp.check_access(not primary_allowed,g||':missing identity denied by current API');
    perform pg_temp.check_access(not legacy_allowed,g||':missing identity denied by installed-client API');
  end loop;
end $$;
reset role;
select pg_temp.check_access(not has_function_privilege('anon','public.list_current_member_group_roster(uuid)','EXECUTE'),
 'anonymous current API grant denied');
select pg_temp.check_access(not has_function_privilege('anon','public.list_collection_collect_ids(uuid)','EXECUTE'),
 'anonymous installed-client API grant denied');
select label,passed from access_results order by label;
do $$ begin
  if exists(select 1 from access_results where not passed) then
    raise exception 'Member roster access regression: % failed checks',
      (select count(*) from access_results where not passed);
  end if;
end $$;
select 'MEMBER_ROSTER_ACCESS_UAT_PASS: '||count(*)||' checks' from access_results;
rollback;
