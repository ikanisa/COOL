\set ON_ERROR_STOP on
-- Root-only isolated task fixture. No providers/network; every write rolls back.
begin;
set local statement_timeout='30s';set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres'
  or current_setting('collect.roster_provenance_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>144
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930120000'
  or exists(select 1 from auth.users where id::text like '99670000-%')
  or exists(select 1 from auth.sessions where id::text like '99670000-%')
  or exists(select 1 from collect_hybrid.roster_import_sources where request_id::text like '99670000-%') then
  raise exception 'Exact isolated144 and unused9967 fixture required'; end if;
end $$;
create temp table reload_checks(n int); insert into reload_checks values(0);
create function pg_temp.reject(stmt text,code text) returns void language plpgsql as $$
begin
 begin execute stmt;exception when others then
  if sqlerrm<>code and sqlstate<>code then raise exception 'Expected %, got %/%',code,sqlstate,sqlerrm; end if;
  update reload_checks set n=n+1;return;
 end;raise exception 'Expected rejection %',code;
end $$;
grant all on reload_checks to authenticated,anon,service_role;
do $$ begin execute format('grant usage on schema %I to authenticated,anon,service_role',pg_my_temp_schema()::regnamespace::text); end $$;
grant execute on function pg_temp.reject(text,text) to authenticated,anon,service_role;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99670000-0000-4000-8000-000000000001','authenticated','authenticated','250788967001',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id='99670000-0000-4000-8000-000000000001';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99670000-0000-4000-8000-000000000001','+250788967001',now()-interval '2 minutes','Synthetic reload fixture identity');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99670000-0000-4000-8000-000000000001',id,'Synthetic reload fixture role',now()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99670000-0000-4000-8000-000000000011','99670000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1'),
('99670000-0000-4000-8000-000000000012','99670000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
create temp table reload_source(id uuid,upload uuid,preview jsonb);
grant all on reload_source to authenticated,service_role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare s jsonb; p jsonb;begin
 s:=public.create_roster_import_source('99670000-0000-4000-8000-000000000001','99670000-0000-4000-8000-000000000011',
 '99670000-0000-4000-8000-000000000101','text',encode(extensions.digest('synthetic reload bytes','sha256'),'hex'),22,
 'pasted-roster.txt','text/plain','utf8_text',null,null,false,null,null);
 p:=public.complete_roster_import_preview((s->>'import_id')::uuid,'99670000-0000-4000-8000-000000000001',
 '99670000-0000-4000-8000-000000000011','[{"source_row":1,"member_name":"Alice Fixture","momo_name":"ALICE FIXTURE","momo_number":"0789967001","confidence":1}]',
 '{"processing_method":"deterministic","provider_response_sha256":null,"provider_response_id":null}');
 insert into reload_source values((s->>'import_id')::uuid,'99670000-0000-4000-8000-000000000101',p);
end $$;
reset role;
-- Full typed payload validation, exact-byte SHA, duplicate keys, malformed
-- objects, missing/extra keys, bounds and invalid nested field types.
do $$ declare good text; x text;begin
 good:='{"parent_revision_id":"99670000-0000-4000-8000-000000000201","rows":[{"member_name":"Alice Fixture","momo_name":"ALICE FIXTURE","momo_number":"0789967001"}],"reason":"","title":""}';
 foreach x in array array['{}','[]',good||' ',replace(good,'"title":""','"title":"","title":"duplicate"'),
  replace(good,'"title":""','"title":2'),replace(good,'"momo_number":"0789967001"','"momo_number":2'),
  replace(good,'"member_name":"Alice Fixture"','"member_name":"Alice Fixture","member_name":"other"'),
  replace(good,'"rows":[','"extra":true,"rows":[')] loop
  perform pg_temp.reject(format('select collect_hybrid.roster_recovery_payload(%L,%L,%L)',x,
   case when x=good||' ' then encode(extensions.digest(convert_to(good,'UTF8'),'sha256'),'hex') else encode(extensions.digest(convert_to(x,'UTF8'),'sha256'),'hex') end,'draft'),'roster_recovery_payload_invalid');
 end loop;
 perform pg_temp.reject(format('select collect_hybrid.roster_recovery_payload(%L,%L,%L)',repeat('x',512001),repeat('a',64),'draft'),'roster_recovery_payload_invalid');
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99670000-0000-4000-8000-000000000001","session_id":"99670000-0000-4000-8000-000000000011"}',true);
do $$ declare r record; txt text; digest text; result jsonb;begin
 select * into r from reload_source;
 txt:=jsonb_build_object('parent_revision_id',r.preview->>'revision_id','rows',r.preview->'normalized_rows','reason','','title','')::text;
 digest:=encode(extensions.digest(convert_to(txt,'UTF8'),'sha256'),'hex');
 perform public.admin_save_roster_import_draft(r.id,'99670000-0000-4000-8000-000000000301',null,txt,digest);
 perform pg_temp.reject(format('select public.admin_save_roster_import_draft(%L,%L,null,%L,%L)',r.id,'99670000-0000-4000-8000-000000000302',txt,digest),'roster_draft_superseded');
 -- Clone tab with stale original reference loses compare-and-swap.
 result:=public.admin_save_roster_import_draft(r.id,'99670000-0000-4000-8000-000000000303','99670000-0000-4000-8000-000000000301',txt,digest);
 perform pg_temp.reject(format('select public.admin_save_roster_import_draft(%L,%L,%L,%L,%L)',r.id,'99670000-0000-4000-8000-000000000304','99670000-0000-4000-8000-000000000301',txt,digest),'roster_draft_superseded');
 if (public.admin_recover_roster_import(r.upload,null))->'draft'->>'checkpoint_id'<>'99670000-0000-4000-8000-000000000303' then raise exception 'CAS recovery mismatch'; end if;
 if (public.admin_recover_roster_import('99670000-0000-4000-8000-000000000999',null))->>'state'<>'missing_source' then raise exception 'Missing source not truthful'; end if;
end $$;
-- Same actor, different live Authsession cannot read or retarget old import.
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99670000-0000-4000-8000-000000000001","session_id":"99670000-0000-4000-8000-000000000012"}',true);
select pg_temp.reject('select public.admin_recover_roster_import(''99670000-0000-4000-8000-000000000101'',null)','roster_import_unavailable');
reset role;
update public.feature_flags set enabled=false where key='hybrid_member_onboarding';
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99670000-0000-4000-8000-000000000001","session_id":"99670000-0000-4000-8000-000000000011"}',true);
select pg_temp.reject('select public.admin_recover_roster_import(''99670000-0000-4000-8000-000000000101'',null)','roster_feature_disabled');
reset role;
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='99670000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.reject('select public.admin_recover_roster_import(''99670000-0000-4000-8000-000000000101'',null)','roster_actor_unavailable');
reset role;
-- Private payload tables and maintenance API are inaccessible to all clients.
set local role anon;
select pg_temp.reject('select * from collect_hybrid.roster_import_editor_drafts','42501');
select pg_temp.reject('select * from collect_hybrid.roster_import_recovery_intents','42501');
select pg_temp.reject('select public.admin_recover_roster_import(''99670000-0000-4000-8000-000000000101'',null)','42501');
reset role;
set local role authenticated;
select pg_temp.reject('select * from collect_hybrid.roster_import_editor_drafts','42501');
select pg_temp.reject('select * from collect_hybrid.roster_import_recovery_intents','42501');
select pg_temp.reject('select collect_hybrid.purge_expired_roster_recovery(1)','42501');
reset role;
set local role service_role;
select pg_temp.reject('select * from collect_hybrid.roster_import_editor_drafts','42501');
select pg_temp.reject('select collect_hybrid.purge_expired_roster_recovery(1)','42501');
reset role;
-- Owner-only bounded physical expiry deletion preserves immutable142 lineage.
-- Expired recovery seeds are synthetic, within this rollback transaction.
update collect_hybrid.roster_import_editor_drafts set updated_at=clock_timestamp()-interval '25 hours',expires_at=clock_timestamp()-interval '1 hour'
where import_id=(select id from reload_source);
insert into collect_hybrid.roster_import_recovery_intents(request_id,import_id,actor_id,session_id,kind,payload,payload_sha256,created_at,expires_at)
select '99670000-0000-4000-8000-000000000401',id,'99670000-0000-4000-8000-000000000001','99670000-0000-4000-8000-000000000011',
 'review','{}',encode(extensions.digest('{}','sha256'),'hex'),clock_timestamp()-interval '25 hours',clock_timestamp()-interval '1 hour' from reload_source;
select pg_temp.reject('select collect_hybrid.purge_expired_roster_recovery(0)','roster_recovery_owner_required');
do $$ declare n int;begin
 n:=collect_hybrid.purge_expired_roster_recovery(1);
 if n<>2 or not exists(select 1 from collect_hybrid.roster_import_sources where id=(select id from reload_source))
  or not exists(select 1 from collect_hybrid.roster_import_revisions where import_id=(select id from reload_source))
  or exists(select 1 from collect_hybrid.roster_import_editor_drafts where import_id=(select id from reload_source))
  or exists(select 1 from collect_hybrid.roster_import_recovery_intents where import_id=(select id from reload_source)) then raise exception 'Bounded purge/provenance mismatch'; end if;
end $$;
-- Restore only the synthetic role to test expiry and bounded per-import quota.
update public.admin_user_roles set revoked_at=null where user_id='99670000-0000-4000-8000-000000000001';
-- Owner-created historical fixture: never UPDATE frozen142 source provenance.
insert into collect_hybrid.roster_import_sources
select (jsonb_populate_record(null::collect_hybrid.roster_import_sources,to_jsonb(s)||jsonb_build_object(
 'id','99670000-0000-4000-8000-000000000501','request_id','99670000-0000-4000-8000-000000000502',
 'created_at',clock_timestamp()-interval '25 hours','expires_at',clock_timestamp()-interval '1 hour'))).*
from collect_hybrid.roster_import_sources s where id=(select id from reload_source);
insert into collect_hybrid.roster_import_recovery_intents(request_id,import_id,actor_id,session_id,kind,payload,payload_sha256,created_at,expires_at)
values('99670000-0000-4000-8000-000000000503','99670000-0000-4000-8000-000000000501',
 '99670000-0000-4000-8000-000000000001','99670000-0000-4000-8000-000000000011','review','{}',
 encode(extensions.digest('{}','sha256'),'hex'),clock_timestamp()-interval '25 hours',clock_timestamp()-interval '1 hour');
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99670000-0000-4000-8000-000000000001","session_id":"99670000-0000-4000-8000-000000000011"}',true);
do $$ declare receipt jsonb;begin
 receipt:=public.admin_recover_roster_import('99670000-0000-4000-8000-000000000502','99670000-0000-4000-8000-000000000503');
 if receipt->>'state'<>'expired' or receipt->'initial_preview' is distinct from 'null'::jsonb
   or receipt->'draft' is distinct from 'null'::jsonb or receipt->'intent' is distinct from 'null'::jsonb
   or receipt->'status' is distinct from 'null'::jsonb then raise exception 'Expired recovery exposed editor payload'; end if;
end $$;
select pg_temp.reject('select public.admin_execute_roster_import_intent(''99670000-0000-4000-8000-000000000503'',encode(extensions.digest(''{}'',''sha256''),''hex''),true)','roster_import_expired');
reset role;
-- 40 immutable intents exhaust the bounded per-source storage quota.
insert into collect_hybrid.roster_import_recovery_intents(request_id,import_id,actor_id,session_id,kind,payload,payload_sha256,expires_at)
select ('99670000-0000-4000-8000-'||lpad((600+i)::text,12,'0'))::uuid,s.id,s.actor_id,s.session_id,'review','{}',
 encode(extensions.digest('{}','sha256'),'hex'),s.expires_at from collect_hybrid.roster_import_sources s
 cross join generate_series(1,40) i where s.id=(select id from reload_source);
set local role authenticated;
do $$ declare r record;txt text;begin
 select * into r from reload_source;
 txt:=jsonb_build_object('p_import_id',r.id,'p_parent_revision_id',r.preview->>'revision_id','p_rows',r.preview->'normalized_rows',
 'p_reason','Synthetic quota review','p_request_id','99670000-0000-4000-8000-000000000699')::text;
 perform pg_temp.reject(format('select public.admin_stage_roster_import_intent(%L,%L,%L,%L,%L)',
 '99670000-0000-4000-8000-000000000699',r.id,'review',txt,encode(extensions.digest(convert_to(txt,'UTF8'),'sha256'),'hex')),'roster_recovery_limit');
end $$;
reset role;
select 'ROSTER_RELOAD_ADVERSARIAL_PASS|'||n from reload_checks;
rollback;
