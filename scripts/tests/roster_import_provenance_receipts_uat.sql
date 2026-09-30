\set ON_ERROR_STOP on
-- Root verifies the exact task-owned Docker labels/55722 before execution.
-- PGOPTIONS='-c collect.roster_provenance_qa=isolated_clone'
-- Actual RPC receipt shapes over synthetic inputs; provider/Auth HTTP calls=0.
-- Output JSON lines start ROSTER_RECEIPT_JSON| and all database writes roll back.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres'
  or current_setting('collect.roster_provenance_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>142
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930100000'
  or exists(select 1 from auth.users where id::text like '99650000-%' or phone='250788965001')
  or exists(select 1 from auth.sessions where id::text like '99650000-%')
  or exists(select 1 from public.profiles where id::text like '99650000-%')
  or exists(select 1 from collect_hybrid.member_records where id::text like '99650000-%')
  or exists(select 1 from collect_hybrid.member_momo_identities where momo_number in ('+250789965001','+250789965002'))
  or exists(select 1 from collect_hybrid.roster_import_sources where request_id::text like '99650000-%')
  or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries) then
  raise exception 'Exact isolated142 and unused9965 decoder fixture required'; end if;
end $$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99650000-0000-4000-8000-000000000001','authenticated','authenticated','250788965001',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id='99650000-0000-4000-8000-000000000001';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99650000-0000-4000-8000-000000000001','+250788965001',now()-interval '2 minutes','Synthetic decoder fixture identity');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99650000-0000-4000-8000-000000000001',id,'Synthetic decoder fixture role',now()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99650000-0000-4000-8000-000000000011','99650000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';

create temp table roster_receipt_cases(
 case_name text primary key,number integer,browser_request jsonb,candidates jsonb,
 source jsonb,initial_preview jsonb,review_request jsonb,reviewed_preview jsonb,commit_request jsonb,
 committed jsonb,commit_replay jsonb,read_receipt jsonb
);
grant all on roster_receipt_cases to service_role,authenticated;
do $$ begin execute format('grant usage on schema %I to service_role,authenticated',pg_my_temp_schema()::regnamespace::text); end $$;
insert into roster_receipt_cases(case_name,number,browser_request,candidates) values
 ('deterministic',1,jsonb_build_object('contract_version',1,'request_id','99650000-0000-4000-8000-000000000101',
  'source_type','text','content',E'member_name\tmomo_name\tmomo_number\nAlice Fixture\tALICE FIXTURE\t0789965001'),
  '[{"source_row":2,"member_name":"Alice Fixture","momo_name":"ALICE FIXTURE","momo_number":"0789965001","confidence":1}]'),
 -- This is the existing synthetic solid2x3 PNG from roster_file_policy_test.ts.
 -- Its pixels contain no roster: the AI candidate is a synthetic decoder case.
 ('ai',2,jsonb_build_object('contract_version',1,'request_id','99650000-0000-4000-8000-000000000102',
  'source_type','image','filename','synthetic.png','mime_type','image/png',
  'content_base64','iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=',
  'ai_consent',true,'consent_version','roster-ai-extraction-v1'),
  '[{"source_row":1,"member_name":"Ada Fixture","momo_name":"ADA FIXTURE","momo_number":"0789965002","confidence":0.93}]');

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare r record; raw_bytes bytea; source_result jsonb; preview_result jsonb; ai boolean; begin
 for r in select * from roster_receipt_cases order by number loop
  ai:=r.case_name='ai';
  raw_bytes:=case when ai then decode(r.browser_request->>'content_base64','base64')
    else convert_to(r.browser_request->>'content','UTF8') end;
  source_result:=public.create_roster_import_source('99650000-0000-4000-8000-000000000001','99650000-0000-4000-8000-000000000011',
   (r.browser_request->>'request_id')::uuid,r.browser_request->>'source_type',encode(extensions.digest(raw_bytes,'sha256'),'hex'),octet_length(raw_bytes),
   case when ai then 'synthetic.png' else 'pasted-roster.txt' end,case when ai then 'image/png' else 'text/plain' end,
   case when ai then 'image/png' else 'utf8_text' end,null,null,ai,case when ai then 'roster-ai-extraction-v1' end,
   case when ai then '{"provider":"openai","model":"synthetic-model","prompt_version":"roster-extraction-v1"}'::jsonb end);
  preview_result:=public.complete_roster_import_preview((source_result->>'import_id')::uuid,
   '99650000-0000-4000-8000-000000000001','99650000-0000-4000-8000-000000000011',r.candidates,
   jsonb_build_object('processing_method',case when ai then 'openai_structured_extraction' else 'deterministic' end,
    'provider_response_sha256',case when ai then encode(extensions.digest('synthetic provider decoder response','sha256'),'hex') end,
    'provider_response_id',case when ai then 'synthetic-decoder-response' end));
  update roster_receipt_cases set source=source_result,initial_preview=preview_result where case_name=r.case_name;
 end loop;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99650000-0000-4000-8000-000000000001","session_id":"99650000-0000-4000-8000-000000000011"}',true);
do $$ declare r record; review_args jsonb; commit_args jsonb; reviewed jsonb; result jsonb; replayed jsonb; begin
 for r in select * from roster_receipt_cases order by number loop
  review_args:=jsonb_build_object('p_import_id',r.initial_preview->>'import_id','p_parent_revision_id',r.initial_preview->>'revision_id',
   'p_rows',r.initial_preview->'normalized_rows','p_reason','Reviewed all synthetic decoder rows',
   'p_request_id',('99650000-0000-4000-8000-'||lpad((200+r.number)::text,12,'0'))::uuid);
  reviewed:=public.admin_review_roster_import((review_args->>'p_import_id')::uuid,(review_args->>'p_parent_revision_id')::uuid,
   review_args->'p_rows',review_args->>'p_reason',(review_args->>'p_request_id')::uuid);
  commit_args:=jsonb_build_object('p_request_id',('99650000-0000-4000-8000-'||lpad((300+r.number)::text,12,'0'))::uuid,
   'p_import_id',reviewed->>'import_id','p_revision_id',reviewed->>'revision_id','p_reviewed_rows_sha256',reviewed->>'reviewed_rows_sha256',
   'p_human_affirmed',true,'p_mode','create','p_collection_id',null,'p_title','Synthetic decoder '||r.case_name,
   'p_reason','Reviewed every synthetic decoder member');
  result:=public.admin_commit_roster_import((commit_args->>'p_request_id')::uuid,(commit_args->>'p_import_id')::uuid,
   (commit_args->>'p_revision_id')::uuid,commit_args->>'p_reviewed_rows_sha256',true,'create',null,commit_args->>'p_title',commit_args->>'p_reason');
  replayed:=public.admin_commit_roster_import((commit_args->>'p_request_id')::uuid,(commit_args->>'p_import_id')::uuid,
   (commit_args->>'p_revision_id')::uuid,commit_args->>'p_reviewed_rows_sha256',true,'create',null,commit_args->>'p_title',commit_args->>'p_reason');
  if (reviewed->'can_submit') is distinct from 'true'::jsonb or result->'replayed' is distinct from 'false'::jsonb
   or replayed is distinct from (result||'{"replayed":true}'::jsonb) then raise exception 'Actual decoder receipt workflow mismatch'; end if;
  update roster_receipt_cases set review_request=review_args,reviewed_preview=reviewed,commit_request=commit_args,
   committed=result,commit_replay=replayed,read_receipt=public.admin_get_roster_import((reviewed->>'import_id')::uuid)
   where case_name=r.case_name;
 end loop;
end $$;
reset role;
set constraints all immediate;
select 'ROSTER_RECEIPT_JSON|'||jsonb_build_object('case',case_name,'browser_request',browser_request,'source',source,
 'initial_preview',initial_preview,'review_request',review_request,'reviewed_preview',reviewed_preview,
 'commit_request',commit_request,'commit',committed,'commit_replay',commit_replay,'read',read_receipt)::text
from roster_receipt_cases order by number;
select 'ROSTER_RECEIPT_FIXTURE_PASS|2';
rollback;
