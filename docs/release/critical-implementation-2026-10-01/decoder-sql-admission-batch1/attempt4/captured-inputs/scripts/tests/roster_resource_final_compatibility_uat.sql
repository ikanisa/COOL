\set ON_ERROR_STOP on
-- Source-only final146 compatibility: real new budget + verification prerequisite,
-- then unchanged142 review/commit and144 reload. Root alone runs; all writes roll back.
begin;
set local statement_timeout='30s';set local lock_timeout='5s';
do $$ begin
 if current_user<>'postgres' or current_database()<>'postgres'
  or current_setting('collect.roster_provenance_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>196
  or (select max(version) from supabase_migrations.schema_migrations)<>'20261002010000'
  or exists(select 1 from auth.users where id::text like '99710000-%')
  or exists(select 1 from collect_hybrid.roster_resource_reservations where request_id::text like '99710000-%') then
  raise exception 'Exact isolated196 and unused9971 namespace required';end if;
end $$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99710000-0000-4000-8000-000000000001','authenticated','authenticated','250788971101',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id='99710000-0000-4000-8000-000000000001';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99710000-0000-4000-8000-000000000001','+250788971101',now()-interval '2 minutes','Synthetic final146 compatibility');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99710000-0000-4000-8000-000000000001',id,'Synthetic final146 role',now()-interval '1 minute' from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99710000-0000-4000-8000-000000000011','99710000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
create temp table compatibility_source(upload uuid,import uuid,preview jsonb,reservation uuid);grant all on compatibility_source to service_role,authenticated;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare b jsonb;s jsonb;p jsonb;begin
 b:=public.reserve_roster_resources('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000011',
  '99710000-0000-4000-8000-000000000101',repeat('a',64),'xlsx',100,repeat('b',64));
 perform public.verify_roster_source_integrity((b->>'reservation_id')::uuid,'99710000-0000-4000-8000-000000000001',
  '99710000-0000-4000-8000-000000000011',repeat('c',64),repeat('d',64),'collect-roster-decoder-v1',
  '{"python":"3.12","pillow":"12.3.0","pypdfium2":"5.2.0","pypdf":"6.19.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
  '{"frames":0,"pages":0,"pixels":0,"expanded_bytes":1000}');
 s:=public.create_roster_import_source('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000011',
  '99710000-0000-4000-8000-000000000101','xlsx',repeat('a',64),100,'synthetic.xlsx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','zip_container',repeat('b',64),100,false,null,null);
 p:=public.complete_roster_import_preview((s->>'import_id')::uuid,'99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000011',
  '[{"source_row":2,"member_name":"Aline Fixture","momo_name":"ALINE FIXTURE","momo_number":"0789971001","confidence":1}]',
  '{"processing_method":"deterministic","provider_response_sha256":null,"provider_response_id":null}');
 -- Explicitly simulate a lost finish ACK, repaired from the durable preview.
 b:=public.reserve_roster_resources('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000011',
  '99710000-0000-4000-8000-000000000101',repeat('a',64),'xlsx',100,repeat('b',64));
 if b->>'state'<>'finished' or b->>'replayed'<>'true' then raise exception 'Lost cleanup ACK not repaired';end if;
 insert into compatibility_source values('99710000-0000-4000-8000-000000000101',(s->>'import_id')::uuid,p,(b->>'reservation_id')::uuid);
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99710000-0000-4000-8000-000000000001","session_id":"99710000-0000-4000-8000-000000000011"}',true);
do $$ declare s record;r jsonb;ack jsonb;recovered jsonb;begin
 select * into s from compatibility_source;
 r:=public.admin_review_roster_import(s.import,(s.preview->>'revision_id')::uuid,
  '[{"member_name":"Aline Fixture","momo_name":"ALINE FIXTURE","momo_number":"0789971001"}]','Reviewed every synthetic row',
  '99710000-0000-4000-8000-000000000201');
 if r->>'can_submit'<>'true' or r->>'requires_human_review'<>'false' then raise exception 'Reviewed142 receipt incompatible';end if;
 ack:=public.admin_commit_roster_import('99710000-0000-4000-8000-000000000301',s.import,(r->>'revision_id')::uuid,
  r->>'reviewed_rows_sha256',true,'create',null,'Synthetic verified-workbook group','Reviewed every synthetic member');
 if ack->>'ok'<>'true' or ack->>'roster_count'<>'1' then raise exception 'Commit142 receipt incompatible';end if;
 recovered:=public.admin_recover_roster_import(s.upload,null);
 if recovered->>'state'<>'committed' or recovered->'status'->'commit'->>'collection_id' is distinct from ack->>'collection_id' then
  raise exception 'Reload144 lost exact committed receipt';end if;
 raise notice 'FINAL146_COMPATIBILITY_PREVIEW:%',s.preview;
 raise notice 'FINAL146_COMPATIBILITY_REVIEW:%',r;
 raise notice 'FINAL146_COMPATIBILITY_COMMIT:%',ack;
 raise notice 'FINAL146_COMPATIBILITY_RELOAD:%',recovered;
end $$;
reset role;
do $$ begin
 if (select count(*) from collect_hybrid.roster_source_verifications v join compatibility_source s on s.reservation=v.reservation_id)<>1
  or (select count(*) from collect_hybrid.roster_resource_completions c join compatibility_source s on s.reservation=c.reservation_id where c.outcome='preview_ready')<>1 then
  raise exception 'Verified source/resource lineage missing';end if;
end $$;
select 'FINAL146_COMPATIBILITY_PASS';
rollback;
