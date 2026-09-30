\set ON_ERROR_STOP on
-- SOURCE ONLY. Root exclusively executes on exact quiet149 clone. Every row rolls back.
begin;
set local statement_timeout='45s'; set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres' or current_setting('collect.roster_provenance_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>149
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930170000'
  or exists(select 1 from auth.users where id::text like '99890000-%')
  or exists(select 1 from auth.sessions where id::text like '99890000-%')
  or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries) then
  raise exception 'Exact quiet149 and unused9989 fixture required'; end if;
end $$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99890000-0000-4000-8000-000000000001','authenticated','authenticated','250788989001',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id='99890000-0000-4000-8000-000000000001';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99890000-0000-4000-8000-000000000001','+250788989001',now()-interval '20 minutes','Synthetic fresh recovery fixture');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99890000-0000-4000-8000-000000000001',id,'Synthetic fresh recovery role',now()-interval '19 minutes' from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99890000-0000-4000-8000-000000000011','99890000-0000-4000-8000-000000000001',now()-interval '18 minutes',now(),now()+interval '2 hours','aal1');
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
create temp table fresh149_fixture(source jsonb, initial jsonb, draft_text text, listing jsonb, inspected jsonb, transfer_request jsonb,
 ack jsonb, recovered jsonb, reviewed jsonb, commit jsonb, committed_status jsonb);
insert into fresh149_fixture default values;
grant all on fresh149_fixture to service_role,authenticated;
do $$ begin execute format('grant usage on schema %I to service_role,authenticated',pg_my_temp_schema()::regnamespace::text); end $$;
create function pg_temp.expect149(stmt text,expected text) returns void language plpgsql as $$ begin
 begin execute stmt; exception when others then if sqlerrm<>expected then raise exception 'Expected %, got %',expected,sqlerrm; end if; return; end;
 raise exception 'Expected rejection %',expected;
end $$;
grant execute on function pg_temp.expect149(text,text) to authenticated,service_role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
#variable_conflict use_variable
declare reservation jsonb; source jsonb; initial jsonb; begin
 reservation:=public.reserve_roster_resources('99890000-0000-4000-8000-000000000001','99890000-0000-4000-8000-000000000011',
 '99890000-0000-4000-8000-000000000101',repeat('a',64),'image',99,null);
 perform public.verify_roster_source_integrity((reservation->>'reservation_id')::uuid,'99890000-0000-4000-8000-000000000001',
 '99890000-0000-4000-8000-000000000011',repeat('b',64),repeat('c',64),'collect-roster-decoder-v1',
 '{"python":"3.12","pillow":"12.0.0","pypdfium2":"5.2.0","pypdf":"6.7.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
 '{"frames":1,"pages":0,"pixels":100,"expanded_bytes":400}');
 source:=public.create_roster_import_source('99890000-0000-4000-8000-000000000001','99890000-0000-4000-8000-000000000011',
 '99890000-0000-4000-8000-000000000101','image',repeat('a',64),99,'synthetic149.png','image/png','image/png',null,null,true,
 'roster-ai-extraction-v1','{"provider":"openai","model":"synthetic149-model","prompt_version":"roster-extraction-v1"}');
 initial:=public.complete_roster_import_preview((source->>'import_id')::uuid,'99890000-0000-4000-8000-000000000001',
 '99890000-0000-4000-8000-000000000011','[{"source_row":1,"member_name":"Synthetic Ada","momo_name":"SYNTHETIC ADA","momo_number":"0789989001","confidence":0.93}]',
 '{"processing_method":"openai_structured_extraction","provider_response_id":"synthetic149-provider-response","provider_response_sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}');
 perform public.finish_roster_resources((reservation->>'reservation_id')::uuid,'99890000-0000-4000-8000-000000000001',
 '99890000-0000-4000-8000-000000000011','preview_ready');
 update fresh149_fixture set source=source,initial=initial;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1','sub','99890000-0000-4000-8000-000000000001',
 'session_id','99890000-0000-4000-8000-000000000011','exp',extract(epoch from clock_timestamp())::bigint+3600)::text,true);
do $$
#variable_conflict use_variable
declare f fresh149_fixture; payload text; begin
 select * into f from fresh149_fixture;
 payload:=jsonb_pretty(jsonb_build_object('parent_revision_id',f.initial->>'revision_id','rows',
  '[{"member_name":"Edited Synthetic Ada","momo_name":"SYNTHETIC ADA","momo_number":"0789989001"}]'::jsonb,
  'title','Private synthetic149 group','reason','Saved synthetic149 reason'));
 perform public.admin_save_roster_import_draft((f.source->>'import_id')::uuid,'99890000-0000-4000-8000-000000000401',null,payload,
  encode(extensions.digest(convert_to(payload,'UTF8'),'sha256'),'hex'));
 update fresh149_fixture set draft_text=payload;
 perform pg_temp.expect149('select public.admin_list_interrupted_roster_imports()','roster_fresh_auth_required');
end $$;
reset role;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99890000-0000-4000-8000-000000000012','99890000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),now()+interval '2 hours','aal1');
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1','sub','99890000-0000-4000-8000-000000000001',
 'session_id','99890000-0000-4000-8000-000000000012','exp',extract(epoch from clock_timestamp())::bigint+3600)::text,true);
do $$
#variable_conflict use_variable
declare f fresh149_fixture; listing jsonb; inspected jsonb; selected jsonb; request jsonb; ack jsonb; recovered jsonb;
 reviewed jsonb; committed jsonb; invalid_etag text; begin
 select * into f from fresh149_fixture;
 listing:=public.admin_list_interrupted_roster_imports(); selected:=listing->'items'->0;
 if jsonb_array_length(listing->'items')<>1 or selected->>'import_id'<>f.source->>'import_id' or selected ? 'rows' or selected ? 'title' then
  raise exception 'Bounded listing disclosure/membership mismatch'; end if;
 inspected:=public.admin_inspect_interrupted_roster_import((selected->>'import_id')::uuid,selected->>'etag');
 if inspected->>'draft_sha256'<>encode(extensions.digest(convert_to(inspected->>'draft_payload','UTF8'),'sha256'),'hex')
  or inspected->'initial_preview'->'source_receipt'<>f.initial->'source_receipt' then raise exception 'Inspection proof mismatch'; end if;
 request:=jsonb_build_object('p_request_id','99890000-0000-4000-8000-000000000201','p_import_id',selected->>'import_id','p_etag',selected->>'etag','p_human_affirmed',true);
 perform pg_temp.expect149(format('select public.admin_transfer_interrupted_roster_import(%L,%L,%L,false)',request->>'p_request_id',request->>'p_import_id',request->>'p_etag'),'roster_confirmation_required');
 invalid_etag:=case when left(selected->>'etag',1)='0' then '1' else '0' end||substr(selected->>'etag',2);
 perform pg_temp.expect149(format('select public.admin_transfer_interrupted_roster_import(%L,%L,%L,true)',request->>'p_request_id',request->>'p_import_id',invalid_etag),'roster_draft_superseded');
 ack:=public.admin_transfer_interrupted_roster_import((request->>'p_request_id')::uuid,(request->>'p_import_id')::uuid,request->>'p_etag',true);
 if public.admin_get_roster_transfer_status((request->>'p_request_id')::uuid)<>ack then raise exception 'Status ACK mismatch'; end if;
 if public.admin_transfer_interrupted_roster_import((request->>'p_request_id')::uuid,(request->>'p_import_id')::uuid,request->>'p_etag',true)<>ack then raise exception 'Transfer exact replay mismatch'; end if;
 recovered:=public.admin_recover_roster_import((ack->>'destination_reference_id')::uuid,null);
 if recovered->'initial_preview'->>'can_submit'<>'false' or recovered->'initial_preview'->>'requires_human_review'<>'true'
  or recovered->'initial_preview'->'source_receipt'<>f.initial->'source_receipt'
  or recovered->'initial_preview'->'source_receipt'->>'request_id'<>f.initial->'source_receipt'->>'request_id'
  or recovered->'initial_preview'->'recovery_lineage'->>'destination_reference_id'<>ack->>'destination_reference_id'
  or recovered->'initial_preview'->>'model'<>f.initial->>'model'
  or recovered->'initial_preview'->>'expires_at'<>f.initial->>'expires_at'
  or recovered->'intent' is distinct from 'null'::jsonb then raise exception 'Fresh branch reset/lineage/TTL mismatch'; end if;
 if (recovered->'draft'->>'payload')::jsonb->'rows'<>(f.draft_text::jsonb)->'rows'
  or (recovered->'draft'->>'payload')::jsonb->>'parent_revision_id'<>ack->>'initial_revision_id' then raise exception 'Editor rebase mismatch'; end if;
 perform pg_temp.expect149(format('select public.admin_get_roster_import(%L)',f.source->>'import_id'),'roster_recovery_transferred');
 perform pg_temp.expect149(format('select public.admin_save_roster_import_draft(%L,%L,null,%L,%L)',f.source->>'import_id,gen_random_uuid(),f.draft_text,
  encode(extensions.digest(convert_to(f.draft_text,'UTF8'),'sha256'),'hex')),'roster_recovery_transferred');
 perform pg_temp.expect149(format('select public.admin_commit_roster_import(%L,%L,%L,%L,true,''create'',null,''Synthetic149 group'',''Reviewed all synthetic149 rows'')',gen_random_uuid(),
 ack->>'to_import_id',ack->>'initial_revision_id',recovered->'initial_preview'->>'reviewed_rows_sha256'),'roster_revision_superseded');
 reviewed:=public.admin_review_roster_import((ack->>'to_import_id')::uuid,(ack->>'initial_revision_id')::uuid,
  (recovered->'draft'->>'payload')::jsonb->'rows','Reviewed every synthetic149 recovered row','99890000-0000-4000-8000-000000000301');
 committed:=public.admin_commit_roster_import('99890000-0000-4000-8000-000000000501',(ack->>'to_import_id')::uuid,
  (reviewed->>'revision_id')::uuid,reviewed->>'reviewed_rows_sha256',true,'create',null,'Synthetic149 recovered group','Reviewed all synthetic149 pages');
 update fresh149_fixture set listing=listing,inspected=inspected,transfer_request=request,ack=ack,recovered=recovered,
 reviewed=reviewed,commit=committed,committed_status=public.admin_get_interrupted_roster_commit_status((ack->>'to_import_id')::uuid);
end $$;
reset role;
do $$
#variable_conflict use_variable
declare i record; role_name text; count_alias integer:=0; begin
 for i in select * from collect_hybrid.roster_recovery_guard_inventory where private_alias<>'retired_provenance_required' loop
  count_alias:=count_alias+1;
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='collect_hybrid' and p.proname=i.private_alias and has_function_privilege(role_name,p.oid,'EXECUTE')) then raise exception 'Private alias EXECUTE leak'; end if;
  end loop;
 end loop;
 if count_alias<>14 then raise exception '149 inventory expected14 current overloads, got%',count_alias; end if;
 if (select count(*) from collect_hybrid.roster_import_extractions where actor_id='99890000-0000-4000-8000-000000000001')<>1
  or (select count(*) from collect_hybrid.roster_source_verifications v join collect_hybrid.roster_resource_reservations r on r.id=v.reservation_id
    where r.actor_id='99890000-0000-4000-8000-000000000001')<>1 then raise exception 'Recovery forged extraction/resource proof'; end if;
end $$;
set constraints all immediate;
select 'ROSTER_FRESH_AUTH_RECEIPT_JSON|'||to_jsonb(f)::text from fresh149_fixture f;
select 'ROSTER_FRESH_AUTH_UAT_PASS|happy_path_and_guard_inventory';
rollback;
