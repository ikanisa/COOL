\set ON_ERROR_STOP on
-- SOURCE ONLY. Root exclusively executes on exact quiet196 clone. Every row rolls back.
begin;
set local statement_timeout='45s'; set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres' or current_setting('collect.roster_provenance_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>196
  or (select max(version) from supabase_migrations.schema_migrations)<>'20261001250000'
  or exists(select 1 from auth.users where id::text like '99890000-%')
  or exists(select 1 from auth.sessions where id::text like '99890000-%')
  or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries) then
  raise exception 'Exact quiet196 and unused9989 fixture required'; end if;
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
create temp table fresh149_checks(name text primary key,passed boolean not null check(passed));
insert into fresh149_fixture default values;
grant all on fresh149_fixture,fresh149_checks to anon,service_role,authenticated;
do $$ begin execute format('grant usage on schema %I to anon,service_role,authenticated',pg_my_temp_schema()::regnamespace::text); end $$;
create function pg_temp.assert149(name text,passed boolean) returns void language plpgsql as $$ begin
 if passed is distinct from true then raise exception '149 assertion failed:%',name; end if;
 insert into fresh149_checks values(name,true);
end $$;
create function pg_temp.expect149(stmt text,expected text) returns void language plpgsql as $$ begin
 begin execute stmt; exception when others then if sqlerrm<>expected then raise exception 'Expected %, got %',expected,sqlerrm; end if;
  perform pg_temp.assert149(expected||':'||md5(stmt),true); return; end;
 raise exception 'Expected rejection %',expected;
end $$;
grant execute on function pg_temp.expect149(text,text),pg_temp.assert149(text,boolean) to anon,authenticated,service_role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
#variable_conflict use_variable
declare reservation jsonb; source jsonb; initial jsonb; begin
 reservation:=public.reserve_roster_resources('99890000-0000-4000-8000-000000000001','99890000-0000-4000-8000-000000000011',
 '99890000-0000-4000-8000-000000000101',repeat('a',64),'image',99,null);
 perform public.verify_roster_source_integrity((reservation->>'reservation_id')::uuid,'99890000-0000-4000-8000-000000000001',
 '99890000-0000-4000-8000-000000000011',repeat('b',64),repeat('c',64),'collect-roster-decoder-v1',
 '{"python":"3.12","pillow":"12.3.0","pypdfium2":"5.2.0","pypdf":"6.19.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
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
 perform pg_temp.expect149(format('select public.admin_save_roster_import_draft(%L,%L,null,%L,%L)',f.source->>'import_id',gen_random_uuid(),f.draft_text,
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

-- Additional synthetic public-API fixtures. Decoder/provider metadata below is
-- controlled SQL input, not a claim that an actual provider/decoder ran here.
create function pg_temp.claim149(p_session uuid) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1',
  'sub','99890000-0000-4000-8000-000000000001','session_id',p_session,
  'exp',extract(epoch from clock_timestamp())::bigint+3600)::text,true);
end $$;
create function pg_temp.prepare149(n integer,kind text default 'text',phase text default 'preview_ready') returns jsonb
language plpgsql as $$
declare old_claims text:=current_setting('request.jwt.claims',true); reservation jsonb; source jsonb; initial jsonb;
 request uuid:=('99890000-0000-4000-8000-'||lpad((1000+n)::text,12,'0'))::uuid;
 sha text:=encode(extensions.digest('synthetic149 source '||n,'sha256'),'hex');
 derived text:=case when kind='xlsx' then repeat('c',64) end; ai boolean:=kind in ('image','pdf');
 begin
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 reservation:=public.reserve_roster_resources('99890000-0000-4000-8000-000000000001','99890000-0000-4000-8000-000000000011',request,sha,kind,99,derived);
 if kind in ('xlsx','image','pdf') then
  perform public.verify_roster_source_integrity((reservation->>'reservation_id')::uuid,'99890000-0000-4000-8000-000000000001',
   '99890000-0000-4000-8000-000000000011',repeat('b',64),repeat('c',64),'collect-roster-decoder-v1',
   '{"python":"3.12","pillow":"12.3.0","pypdfium2":"5.2.0","pypdf":"6.19.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
   case when kind='image' then '{"frames":1,"pages":0,"pixels":100,"expanded_bytes":400}'::jsonb
    when kind='pdf' then '{"frames":0,"pages":1,"pixels":100,"expanded_bytes":400}'::jsonb
    else '{"frames":0,"pages":0,"pixels":0,"expanded_bytes":400}'::jsonb end);
 end if;
 source:=public.create_roster_import_source('99890000-0000-4000-8000-000000000001','99890000-0000-4000-8000-000000000011',request,kind,sha,99,
  'synthetic149-'||n||case when kind='xlsx' then '.xlsx' when kind='image' then '.png' when kind='pdf' then '.pdf' else '.txt' end,
  case when kind='xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' when kind='image' then 'image/png' when kind='pdf' then 'application/pdf' else 'text/plain' end,
  case when kind='xlsx' then 'zip_container' when kind='image' then 'image/png' when kind='pdf' then 'application/pdf' else 'utf8_text' end,
  derived,case when kind='xlsx' then 30 end,ai,case when ai then 'roster-ai-extraction-v1' end,
  case when ai then '{"provider":"openai","model":"synthetic149-model","prompt_version":"roster-extraction-v1"}'::jsonb end);
 if phase='preview_ready' then
  initial:=public.complete_roster_import_preview((source->>'import_id')::uuid,'99890000-0000-4000-8000-000000000001',
   '99890000-0000-4000-8000-000000000011',jsonb_build_array(jsonb_build_object('source_row',1,'member_name','Synthetic member '||n,
    'momo_name','SYNTHETIC MEMBER '||n,'momo_number','0789'||lpad(n::text,6,'0'),'confidence',1)),
   jsonb_build_object('processing_method',case when ai then 'openai_structured_extraction' else 'deterministic' end,
    'provider_response_sha256',case when ai then repeat('d',64) end,'provider_response_id',case when ai then 'synthetic149-response-'||n end));
 elsif phase='failed' then
  perform public.fail_roster_import_preview((source->>'import_id')::uuid,'99890000-0000-4000-8000-000000000001',
   '99890000-0000-4000-8000-000000000011','roster_extraction_failed');
 elsif phase<>'awaiting_preview' then raise exception 'Unknown synthetic fixture phase'; end if;
 perform public.finish_roster_resources((reservation->>'reservation_id')::uuid,'99890000-0000-4000-8000-000000000001',
  '99890000-0000-4000-8000-000000000011',case when phase='preview_ready' then phase else 'failed' end);
 perform set_config('request.jwt.claims',old_claims,true);
 return jsonb_build_object('source',source,'initial',initial,'reservation',reservation);
end $$;

-- The original immutable proof and a completed branch remain readable; neither
-- fresh lookup nor replay creates a second financial/member graph.
do $$ declare f fresh149_fixture; begin
 select * into f from fresh149_fixture;
 perform pg_temp.assert149('main:inspection-preserves-exact-acknowledged-UTF8',f.inspected->>'draft_payload'=f.draft_text);
 perform pg_temp.assert149('main:transfer-has-exact-reference-envelope',
  (select array_agg(k order by k) from jsonb_object_keys(f.ack) k)=
  array(select k from unnest(array['contract_version','ok','state','request_id','from_import_id','root_import_id','to_import_id',
   'actor_id','destination_session_id','destination_reference_id','initial_revision_id','checkpoint_id','draft_sha256',
   'source_etag','original_proof_sha256','expires_at']) k order by k));
 perform pg_temp.assert149('main:one-extraction-only',(select count(*) from collect_hybrid.roster_import_extractions
  where actor_id='99890000-0000-4000-8000-000000000001')=1);
 perform pg_temp.assert149('main:one-member-graph',(select count(*) from public.collection_members where collection_id=(f.commit->>'collection_id')::uuid and role='member')=1);
 perform pg_temp.assert149('main:immutable-original-proof',collect_hybrid.roster_recovery_sha(collect_hybrid.roster_original_proof((f.source->>'import_id')::uuid))=f.ack->>'original_proof_sha256');
 perform pg_temp.assert149('main:committed-read-only-receipt',f.committed_status->>'state'='committed' and f.committed_status->'commit'=f.commit);
 perform pg_temp.assert149('main:no-intent-copied',(select count(*) from collect_hybrid.roster_import_recovery_intents where import_id=(f.ack->>'to_import_id')::uuid)=0);
 perform pg_temp.expect149(format('select public.admin_inspect_interrupted_roster_import(%L,null)',f.source->>'import_id'),'roster_draft_superseded');
 perform pg_temp.expect149(format('select public.admin_transfer_interrupted_roster_import(%L,%L,%L,true)',f.transfer_request->>'p_request_id',f.source->>'import_id',repeat('0',64)),'roster_request_conflict');
 perform pg_temp.claim149('99890000-0000-4000-8000-000000000011');
 perform pg_temp.expect149(format('select public.admin_get_roster_transfer_status(%L)',f.transfer_request->>'p_request_id'),'roster_import_unavailable');
 perform pg_temp.claim149('99890000-0000-4000-8000-000000000012');
end $$;

-- Proof/etag cryptographic binding uses canonical time, independent of SQL
-- connection timezone; display receipt timestamps may retain their timezone.
do $$ declare f jsonb; old_timezone text:=current_setting('TimeZone'); p1 text; e1 text; begin
 f:=pg_temp.prepare149(9);
 p1:=collect_hybrid.roster_original_proof((f->'source'->>'import_id')::uuid);
 e1:=collect_hybrid.roster_interrupted_etag((f->'source'->>'import_id')::uuid,'99890000-0000-4000-8000-000000000012');
 perform set_config('TimeZone','Pacific/Auckland',true);
 perform pg_temp.assert149('time:proof-independent-of-connection-zone',p1=collect_hybrid.roster_original_proof((f->'source'->>'import_id')::uuid));
 perform pg_temp.assert149('time:etag-independent-of-connection-zone',e1=collect_hybrid.roster_interrupted_etag((f->'source'->>'import_id')::uuid,'99890000-0000-4000-8000-000000000012'));
 perform set_config('TimeZone',old_timezone,true);
end $$;

-- Missing/unacknowledged/failed sources never become a synthetic preview or
-- trigger a provider retry; an XLSX branch inherits genuine verification refs.
do $$ declare awaiting jsonb; failed jsonb; workbook jsonb; ack jsonb; sid uuid:='99890000-0000-4000-8000-000000000013';
 etag text; b jsonb; begin
 awaiting:=pg_temp.prepare149(10,'text','awaiting_preview'); failed:=pg_temp.prepare149(11,'image','failed');
 workbook:=pg_temp.prepare149(12,'xlsx');
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values(sid,'99890000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '2 hours','aal1');
 perform pg_temp.claim149(sid);
 perform pg_temp.expect149(format('select public.admin_inspect_interrupted_roster_import(%L,%L)',gen_random_uuid(),repeat('e',64)),'roster_import_unavailable');
 foreach b in array array[awaiting,failed] loop
  etag:=collect_hybrid.roster_interrupted_etag((b->'source'->>'import_id')::uuid,sid);
  perform pg_temp.expect149(format('select public.admin_inspect_interrupted_roster_import(%L,%L)',b->'source'->>'import_id',etag),'roster_preview_unacknowledged');
 end loop;
 etag:=collect_hybrid.roster_interrupted_etag((workbook->'source'->>'import_id')::uuid,sid);
 ack:=public.admin_transfer_interrupted_roster_import('99890000-0000-4000-8000-000000002012',(workbook->'source'->>'import_id')::uuid,etag,true);
 b:=public.admin_recover_roster_import((ack->>'destination_reference_id')::uuid,null);
 perform pg_temp.assert149('xlsx:original-receipt-retained',b->'initial_preview'->'source_receipt'=workbook->'initial'->'source_receipt');
 perform pg_temp.assert149('xlsx:no-synthetic-extraction',b->'initial_preview'->'source_receipt'->'extraction_id'='null'::jsonb);
 perform pg_temp.assert149('xlsx:decoder-proof-in-lineage',(b->'initial_preview'->'recovery_lineage'->>'original_proof')::jsonb->>'decoder_receipt_sha256'=repeat('b',64));
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 perform pg_temp.expect149(format('select public.complete_roster_import_preview(%L,%L,%L,''[]'',''{}'')',ack->>'to_import_id','99890000-0000-4000-8000-000000000001',sid),'roster_recovery_provider_replay_forbidden');
 perform pg_temp.expect149(format('select public.reserve_roster_resources(%L,%L,%L,%L,''xlsx'',99,%L)','99890000-0000-4000-8000-000000000001',sid,ack->>'destination_reference_id',workbook->'source'->>'source_sha256',repeat('c',64)),'roster_recovery_provider_replay_forbidden');
 perform pg_temp.claim149(sid);
end $$;

-- Accepted compact500-row drafts near the byte ceiling survive inspection
-- unchanged and transfer/rebase without added whitespace or lost Unicode.
do $$ declare f jsonb; sid uuid:='99890000-0000-4000-8000-000000000014'; rows jsonb; v jsonb; payload text; inspected jsonb; ack jsonb; recovered jsonb; etag text; begin
 f:=pg_temp.prepare149(20);
 select jsonb_agg(jsonb_build_object('member_name',repeat('é',238)||E'"\\', 'momo_name',repeat('ő',238)||E'"\\', 'momo_number','0789000020') order by n)
 into rows from generate_series(1,500) n;
 v:=jsonb_build_object('rows',rows,'title','Saved Unicode title é','reason','Saved escaped reason " é');
 payload:=collect_hybrid.roster_compact_recovery_draft(v,(f->'initial'->>'revision_id')::uuid);
 perform pg_temp.assert149('bytes:near-ceiling-fixture',octet_length(payload) between 510000 and 512000);
 perform pg_temp.claim149('99890000-0000-4000-8000-000000000011');
 perform public.admin_save_roster_import_draft((f->'source'->>'import_id')::uuid,'99890000-0000-4000-8000-000000004020',null,payload,collect_hybrid.roster_recovery_sha(payload));
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values(sid,'99890000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '2 hours','aal1');
 perform pg_temp.claim149(sid); etag:=collect_hybrid.roster_interrupted_etag((f->'source'->>'import_id')::uuid,sid);
 inspected:=public.admin_inspect_interrupted_roster_import((f->'source'->>'import_id')::uuid,etag);
 perform pg_temp.assert149('bytes:exact-original-checkpoint',inspected->>'draft_payload'=payload and inspected->>'draft_sha256'=collect_hybrid.roster_recovery_sha(payload));
 ack:=public.admin_transfer_interrupted_roster_import('99890000-0000-4000-8000-000000002020',(f->'source'->>'import_id')::uuid,etag,true);
 recovered:=public.admin_recover_roster_import((ack->>'destination_reference_id')::uuid,null);
 perform pg_temp.assert149('bytes:bounded-rebased-checkpoint',octet_length(recovered->'draft'->>'payload')=octet_length(payload));
 perform pg_temp.assert149('bytes:all-500-escaped-Unicode-rows',(recovered->'draft'->>'payload')::jsonb->'rows'=rows);
 perform pg_temp.assert149('bytes:title-reason-retained',(((recovered->'draft'->>'payload')::jsonb-array['parent_revision_id','rows']))=(v-array['rows']));
 perform pg_temp.assert149('bytes:parent-only-rebased',(recovered->'draft'->>'payload')::jsonb->>'parent_revision_id'=ack->>'initial_revision_id');
end $$;

-- A review supersedes stale raw rows, while its acknowledged title/reason
-- survive. A fresh branch always needs a new reviewed ACK before commit.
do $$ declare f jsonb; sid uuid:='99890000-0000-4000-8000-000000000015'; payload text; review jsonb; inspected jsonb; etag text; begin
 f:=pg_temp.prepare149(21); perform pg_temp.claim149('99890000-0000-4000-8000-000000000011');
 payload:=collect_hybrid.roster_compact_recovery_draft(jsonb_build_object('rows',f->'initial'->'normalized_rows',
  'title','Acknowledged stale title','reason','Acknowledged stale reason'),(f->'initial'->>'revision_id')::uuid);
 perform public.admin_save_roster_import_draft((f->'source'->>'import_id')::uuid,'99890000-0000-4000-8000-000000004021',null,payload,collect_hybrid.roster_recovery_sha(payload));
 review:=public.admin_review_roster_import((f->'source'->>'import_id')::uuid,(f->'initial'->>'revision_id')::uuid,
  '[{"member_name":"Reviewed replacement","momo_name":"REVIEWED REPLACEMENT","momo_number":"0789000021"}]','Reviewed latest acknowledged rows','99890000-0000-4000-8000-000000003021');
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values(sid,'99890000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '2 hours','aal1');
 perform pg_temp.claim149(sid); etag:=collect_hybrid.roster_interrupted_etag((f->'source'->>'import_id')::uuid,sid);
 inspected:=public.admin_inspect_interrupted_roster_import((f->'source'->>'import_id')::uuid,etag);
 perform pg_temp.assert149('stale:latest-reviewed-rows', (inspected->>'draft_payload')::jsonb->'rows'=review->'normalized_rows');
 perform pg_temp.assert149('stale:acknowledged-title-reason',(inspected->>'draft_payload')::jsonb->>'title'='Acknowledged stale title' and (inspected->>'draft_payload')::jsonb->>'reason'='Acknowledged stale reason');
 perform pg_temp.assert149('stale:latest-parent',(inspected->>'draft_payload')::jsonb->>'parent_revision_id'=review->>'revision_id');
end $$;

-- Transferred, live and expired foreign IDs must have the same unavailable
-- result. Owner fixture modifications use subtransactions and are rolled back.
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99890000-0000-4000-8000-000000000002','authenticated','authenticated','250788989002',now(),'{}','{}');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99890000-0000-4000-8000-000000000002','+250788989002',now()-interval '20 minutes','Synthetic foreign authority');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99890000-0000-4000-8000-000000000002',id,'Synthetic foreign role',now()-interval '19 minutes' from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99890000-0000-4000-8000-000000000022','99890000-0000-4000-8000-000000000002',clock_timestamp(),clock_timestamp(),now()+interval '2 hours','aal1');
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1','sub','99890000-0000-4000-8000-000000000002',
 'session_id','99890000-0000-4000-8000-000000000022','exp',extract(epoch from clock_timestamp())::bigint+3600)::text,true);
do $$ declare f fresh149_fixture; begin
 select * into f from fresh149_fixture;
 perform pg_temp.expect149(format('select public.admin_get_roster_import(%L)',f.source->>'import_id'),'roster_import_unavailable');
 perform pg_temp.expect149(format('select public.admin_get_roster_import(%L)',f.ack->>'to_import_id'),'roster_import_unavailable');
 perform pg_temp.expect149(format('select public.admin_get_interrupted_roster_commit_status(%L)',f.ack->>'to_import_id'),'roster_import_unavailable');
 perform pg_temp.expect149('select collect_hybrid.require_roster_actor_authority(null,null,''platform_owner'',array[''users.read''])','permission denied for function require_roster_actor_authority');
 perform pg_temp.expect149('select collect_hybrid.lock_roster_recovery_budget()','permission denied for function lock_roster_recovery_budget');
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.expect149('select public.admin_list_interrupted_roster_imports()','permission denied for function admin_list_interrupted_roster_imports');
reset role;

-- Sequential authority adversaries complement the separately coordinated RR
-- races. Each mutation is rolled back before another assertion/fixture uses it.
do $$ declare f jsonb; sid uuid:='99890000-0000-4000-8000-000000000016'; etag text; statement text; baseline integer; begin
 f:=pg_temp.prepare149(30);
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values(sid,'99890000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '2 hours','aal1');
 perform pg_temp.claim149(sid); etag:=collect_hybrid.roster_interrupted_etag((f->'source'->>'import_id')::uuid,sid);
 statement:=format('select public.admin_transfer_interrupted_roster_import(%L,%L,%L,true)','99890000-0000-4000-8000-000000002030',f->'source'->>'import_id',etag);
 select count(*) into baseline from collect_hybrid.roster_recovery_transfers;
 begin
  update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='99890000-0000-4000-8000-000000000011';
  perform public.admin_transfer_interrupted_roster_import('99890000-0000-4000-8000-000000002030',(f->'source'->>'import_id')::uuid,etag,true);
  raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('authority:expired-issued-session-is-not-a-current-credential',true);
 begin
  update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='99890000-0000-4000-8000-000000000001';
  perform pg_temp.expect149(statement,'roster_actor_unavailable'); raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('authority:approval-revoked',true);
 begin
  update collect_admin_access.whatsapp_approvals set approved_at=clock_timestamp() where user_id='99890000-0000-4000-8000-000000000001';
  perform pg_temp.expect149(statement,'roster_actor_unavailable'); raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('authority:reapproval-does-not-revive-old-session',true);
 begin
  update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='99890000-0000-4000-8000-000000000001';
  perform pg_temp.expect149(statement,'roster_actor_unavailable'); raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('authority:role-revoked',true);
 begin
  delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner') and permission_name='users.read';
  perform pg_temp.expect149(statement,'roster_actor_unavailable'); raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('authority:permission-removed',true);
 begin
  update public.feature_flags set enabled=false where key='hybrid_member_onboarding';
  perform pg_temp.expect149(statement,'roster_feature_disabled'); raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('authority:feature-disabled',true);
 begin
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1','sub','99890000-0000-4000-8000-000000000001','session_id',sid,'exp',1)::text,true);
  perform pg_temp.expect149(statement,'roster_fresh_auth_required'); raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('authority:expired-JWT',true);
 perform pg_temp.assert149('authority:no-destination-created',baseline=(select count(*) from collect_hybrid.roster_recovery_transfers));
end $$;


-- Real Auth session deletion (normal logout) does not turn original issuance
-- into a recovery dependency. Current fresh authority, a new review and an
-- explicit commit still produce exactly one graph. This subtransaction rolls
-- back the deletion and graph before subsequent fixture readback/receipt export.
do $$ declare f jsonb; sid uuid:='99890000-0000-4000-8000-000000000017'; etag text;
 ack jsonb; recovered jsonb; reviewed jsonb; committed jsonb; proof_sha text; begin
 f:=pg_temp.prepare149(31);
 proof_sha:=collect_hybrid.roster_recovery_sha(collect_hybrid.roster_original_proof((f->'source'->>'import_id')::uuid));
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values(sid,'99890000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '2 hours','aal1');
 perform pg_temp.claim149(sid); etag:=collect_hybrid.roster_interrupted_etag((f->'source'->>'import_id')::uuid,sid);
 begin
  delete from auth.sessions where id='99890000-0000-4000-8000-000000000011';
  ack:=public.admin_transfer_interrupted_roster_import('99890000-0000-4000-8000-000000002031',(f->'source'->>'import_id')::uuid,etag,true);
  recovered:=public.admin_recover_roster_import((ack->>'destination_reference_id')::uuid,null);
  if recovered->'initial_preview'->>'can_submit'<>'false' then raise exception 'Deleted-session recovery carried approval'; end if;
  reviewed:=public.admin_review_roster_import((ack->>'to_import_id')::uuid,(ack->>'initial_revision_id')::uuid,
   (recovered->'draft'->>'payload')::jsonb->'rows','Reviewed after actual original logout','99890000-0000-4000-8000-000000003031');
  perform public.admin_save_roster_import_draft((ack->>'to_import_id')::uuid,'99890000-0000-4000-8000-000000004031',
   (ack->>'checkpoint_id')::uuid,collect_hybrid.roster_compact_recovery_draft(jsonb_build_object('rows',reviewed->'normalized_rows',
    'title','Saved after original logout','reason','Current fresh session review'),(reviewed->>'revision_id')::uuid),
   collect_hybrid.roster_recovery_sha(collect_hybrid.roster_compact_recovery_draft(jsonb_build_object('rows',reviewed->'normalized_rows',
    'title','Saved after original logout','reason','Current fresh session review'),(reviewed->>'revision_id')::uuid)));
  committed:=public.admin_commit_roster_import('99890000-0000-4000-8000-000000005031',(ack->>'to_import_id')::uuid,
   (reviewed->>'revision_id')::uuid,reviewed->>'reviewed_rows_sha256',true,'create',null,'Fresh after logout','Explicitly approved all recovered rows');
  if committed->>'roster_count'<>'1' or proof_sha<>collect_hybrid.roster_recovery_sha(collect_hybrid.roster_original_proof((f->'source'->>'import_id')::uuid))
   or public.admin_get_roster_transfer_status('99890000-0000-4000-8000-000000002031')<>ack then
   raise exception 'Deleted-session recovery changed immutable proof or outcome'; end if;
  raise exception using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 perform pg_temp.assert149('logout:deleted-original-SID-transfer-review-save-submit',true);
 perform pg_temp.assert149('logout:issued-session-restored-by-subtransaction',exists(select 1 from auth.sessions where id='99890000-0000-4000-8000-000000000011'));
end $$;

select 'ROSTER_FRESH_AUTH_ASSERTIONS_JSON|'||jsonb_build_object('passed',(select count(*) from fresh149_checks),'checks',(select jsonb_agg(name order by name) from fresh149_checks))::text;

set constraints all immediate;
select 'ROSTER_FRESH_AUTH_RECEIPT_JSON|'||to_jsonb(f)::text from fresh149_fixture f;
select 'ROSTER_FRESH_AUTH_UAT_PASS|happy_path_and_guard_inventory';
rollback;
