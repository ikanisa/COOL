\set ON_ERROR_STOP on
-- Synthetic rollback only. Root verifies task Docker labels and host55722 first.
-- Invoke with PGOPTIONS='-c collect.roster_provenance_qa=isolated_clone'.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres'
  or current_setting('collect.roster_provenance_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>142
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930100000'
  or exists(select 1 from auth.users where id::text like '99640000-%' or phone like '25078896400%')
  or exists(select 1 from auth.sessions where id::text like '99640000-%')
  or exists(select 1 from public.profiles where id::text like '99640000-%')
  or exists(select 1 from collect_hybrid.member_records where id::text like '99640000-%')
  or exists(select 1 from collect_hybrid.member_momo_identities where momo_number like '+2507899640%')
  or exists(select 1 from collect_hybrid.roster_import_sources where request_id::text like '99640000-%')
  or exists(select 1 from public.notification_device_tokens)
  or exists(select 1 from public.notification_deliveries) then
  raise exception 'Exact isolated142 and unused9964 synthetic namespace required'; end if;
end $$;
create temp table roster_provenance_results(label text primary key);
grant all on roster_provenance_results to authenticated,service_role,anon;
do $$ begin execute format('grant usage on schema %I to authenticated,service_role,anon',pg_my_temp_schema()::regnamespace::text); end $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
 select ('99640000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$$;
create function pg_temp.check_roster(ok boolean,label text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',label; end if;
 insert into pg_temp.roster_provenance_results values(label);
end $$;
create function pg_temp.roster_snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
declare relation text; body jsonb; result jsonb:='{}'; begin
 foreach relation in array array['public.collections','public.collection_members','public.collection_share_secrets',
  'collect_hybrid.member_records','collect_hybrid.member_momo_identities','collect_hybrid.group_creation_requests','collect_hybrid.roster_batches',
  'collect_hybrid.roster_import_sources','collect_hybrid.roster_import_extractions','collect_hybrid.roster_import_results',
  'collect_hybrid.roster_import_revisions','collect_hybrid.roster_import_commits','public.audit_logs','public.payments','public.ledger_entries',
  'collect_hybrid.momo_journal_entries','collect_hybrid.momo_journal_lines','collect_hybrid.collection_balances','collect_hybrid.member_balances'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',relation::regclass) into body;
  result:=result||jsonb_build_object(relation,body);
 end loop; return result;
end $$;
create function pg_temp.expect_roster_error(command text,expected_state text,expected_message text,label text)
returns void language plpgsql as $$
declare caught_state text; caught_message text; before_state jsonb:=pg_temp.roster_snapshot(); begin
 begin execute command; exception when others then get stacked diagnostics caught_state=returned_sqlstate,caught_message=message_text; end;
 perform pg_temp.check_roster(caught_state=expected_state and (expected_message is null or caught_message=expected_message),label);
 perform pg_temp.check_roster(pg_temp.roster_snapshot()=before_state,label||' leaves no data/audit changes');
end $$;
create function pg_temp.actor(n integer default 1,s integer default 11) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.id(n),'session_id',pg_temp.id(s),'role','authenticated','aal','aal1')::text,true);
end $$;
create function pg_temp.source(n integer,kind text default 'text') returns jsonb language sql as $$
 select public.create_roster_import_source(pg_temp.id(1),pg_temp.id(11),pg_temp.id(n),kind,
  encode(extensions.digest(('synthetic original bytes '||n)::text,'sha256'),'hex'),99,
  case when kind='pdf' then 'synthetic.pdf' when kind='xlsx' then 'synthetic.xlsx' else 'pasted-roster.txt' end,
  case when kind='pdf' then 'application/pdf' when kind='xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' else 'text/plain' end,
  case when kind='pdf' then 'application/pdf' when kind='xlsx' then 'zip_container' else 'utf8_text' end,
  case when kind='xlsx' then repeat('c',64) end,case when kind='xlsx' then 55 end,
  kind='pdf',case when kind='pdf' then 'roster-ai-extraction-v1' end,
  case when kind='pdf' then '{"provider":"openai","model":"synthetic-model","prompt_version":"roster-extraction-v1"}'::jsonb end)
$$;
create function pg_temp.candidates() returns jsonb language sql immutable as $$
 select '[{"source_row":1,"member_name":" Alice  A ","momo_name":"ALICE UWASE","momo_number":"250789964001","confidence":1},
          {"source_row":2,"member_name":"Bob B","momo_name":"BOB MUGISHA","momo_number":"(078) 996-4002","confidence":1}]'::jsonb
$$;
create function pg_temp.rows() returns jsonb language sql immutable as $$
 select '[{"member_name":"Alice A","momo_name":"ALICE UWASE","momo_number":"+250789964001"},
          {"member_name":"Bob B","momo_name":"BOB MUGISHA","momo_number":"+250789964002"}]'::jsonb
$$;
create function pg_temp.complete(import_id uuid,ai boolean default false) returns jsonb language sql as $$
 select public.complete_roster_import_preview(import_id,pg_temp.id(1),pg_temp.id(11),pg_temp.candidates(),
  jsonb_build_object('processing_method',case when ai then 'openai_structured_extraction' else 'deterministic' end,
    'provider_response_sha256',case when ai then repeat('b',64) end,'provider_response_id',case when ai then 'synthetic-response-1' end))
$$;
create function pg_temp.commit_roster(req integer,import_id uuid,revision uuid,digest text,mode text default 'create',collection uuid default null)
returns jsonb language sql as $$
 select public.admin_commit_roster_import(pg_temp.id(req),import_id,revision,digest,true,mode,collection,
  case when mode='create' then 'Synthetic provenance group' end,'Reviewed every synthetic member row')
$$;

create temp table roster_financial_baseline as select pg_temp.roster_snapshot() as body;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
 (pg_temp.id(1),'authenticated','authenticated','250788964001',now(),'{}','{}'),
 (pg_temp.id(2),'authenticated','authenticated','250788964002',now(),'{}','{}'),
 (pg_temp.id(3),'authenticated','authenticated','250788964003',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id in (pg_temp.id(1),pg_temp.id(2),pg_temp.id(3));
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values
 (pg_temp.id(1),'+250788964001',now()-interval '2 minutes','Synthetic roster provenance approval'),
 (pg_temp.id(2),'+250788964002',now()-interval '2 minutes','Synthetic other Admin approval');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
 select a.id,r.id,'Synthetic roster role',now()-interval '1 minute'
 from (values(pg_temp.id(1)),(pg_temp.id(2))) a(id) cross join public.admin_roles r where r.name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
 (pg_temp.id(11),pg_temp.id(1),now(),now(),now()+interval '1 hour','aal1'),
 (pg_temp.id(12),pg_temp.id(2),now(),now(),now()+interval '1 hour','aal1'),
 (pg_temp.id(13),pg_temp.id(3),now(),now(),now()+interval '1 hour','aal1'),
 (pg_temp.id(14),pg_temp.id(1),now(),now(),now()+interval '1 hour','aal1');
update public.feature_flags set enabled=false where key='hybrid_member_onboarding';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_roster_error('select pg_temp.source(101)','55000','roster_feature_disabled','disabled feature prevents source receipt');
reset role;
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';

set local role authenticated;
select pg_temp.actor();
select pg_temp.expect_roster_error('select pg_temp.source(101)','42501',null,'browser cannot forge trusted upload receipt');
select pg_temp.expect_roster_error('select public.admin_add_assisted_roster(null,''[]'',pg_temp.id(1),''reviewed old path'')','42501',null,'legacy add raw rows revoked');
select pg_temp.expect_roster_error('select public.admin_create_assisted_group_with_roster(''old'', ''[]'',''reviewed old path'',pg_temp.id(1),pg_temp.id(2))','42501',null,'legacy create raw rows revoked');
reset role;
select pg_temp.expect_roster_error('select public.admin_add_assisted_roster(null,''[]'',pg_temp.id(1),''reviewed old path'')','55000','roster_provenance_required','legacy add fails closed even for owner');
select pg_temp.expect_roster_error('select public.admin_create_assisted_group_with_roster(''old'', ''[]'',''reviewed old path'',pg_temp.id(1),pg_temp.id(2))','55000','roster_provenance_required','legacy create fails closed even for owner');

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.source(101) as source \gset
select set_config('collect.roster.source',:'source',true);
select (:'source'::jsonb->>'import_id') as import_id \gset
select pg_temp.check_roster((:'source'::jsonb->>'contract_version')::int=1 and :'source'::jsonb->>'state'='awaiting_preview'
 and (:'source'::jsonb->>'replayed')::boolean=false and :'source'::jsonb->'extraction_id'='null','server source receipt precedes preview');
select pg_temp.expect_roster_error('select pg_temp.source(101)','55000','roster_import_in_progress','in-progress source retry cannot repeat extraction');
select pg_temp.complete(:'import_id') as preview \gset
select (:'preview'::jsonb->>'revision_id') as initial_revision \gset
select pg_temp.check_roster(:'preview'::jsonb->'normalized_rows'=pg_temp.rows() and (:'preview'::jsonb->>'ready_count')::int=2
 and :'preview'::jsonb->'can_submit'='false' and :'preview'::jsonb->'requires_human_review'='true','server canonical preview is explicitly unreviewed');
select pg_temp.check_roster(:'preview'::jsonb->'source_receipt'->>'detected_type'='utf8_text'
 and :'preview'::jsonb->'source_receipt'->'ai_consent'='false'
 and :'preview'::jsonb->'source_receipt'->>'schema_version'='collect-roster-rows-v1','preview carries authoritative source metadata');
select pg_temp.check_roster(pg_temp.complete(:'import_id')=:'preview'::jsonb,'exact preview completion retry preserves revision');
select pg_temp.check_roster(pg_temp.source(101)->'completed_preview'=:'preview'::jsonb and (pg_temp.source(101)->>'replayed')::boolean,
 'completed source retry returns cached preview');
select pg_temp.expect_roster_error(format('select public.complete_roster_import_preview(%L,pg_temp.id(1),pg_temp.id(11),
 (select jsonb_agg(jsonb_build_object(''source_row'',n,''member_name'',repeat(''A'',480),''momo_name'',repeat(''B'',480),''momo_number'',''0789964001'',''confidence'',1)) from generate_series(1,500) n),%L)',
 :'import_id','{"processing_method":"deterministic","provider_response_sha256":null,"provider_response_id":null}'),
 '22023','roster_input_invalid','server canonical JSONB512000 byte envelope is enforced');
select pg_temp.expect_roster_error(format('select public.complete_roster_import_preview(%L,pg_temp.id(1),pg_temp.id(11),%L,%L)',
 :'import_id',jsonb_set(pg_temp.candidates(),'{0,member_name}','"Different"'),
 '{"processing_method":"deterministic","provider_response_sha256":null,"provider_response_id":null}'),
 '55000','roster_request_conflict','changed completion conflicts');
select pg_temp.expect_roster_error(format('select pg_temp.commit_roster(301,%L,%L,%L)',:'import_id',:'initial_revision',:'preview'::jsonb->>'reviewed_rows_sha256'),
 '42501',null,'service cannot finalize membership');
reset role;

set local role authenticated;
select pg_temp.actor(3,13);
select pg_temp.expect_roster_error(format('select public.admin_get_roster_import(%L)',:'import_id'),'42501','roster_actor_unavailable','member cannot read private import');
select pg_temp.actor(2,12);
select pg_temp.expect_roster_error(format('select public.admin_get_roster_import(%L)',:'import_id'),'42501','roster_import_unavailable','other Admin cannot read private import');
select pg_temp.actor(1,14);
select pg_temp.expect_roster_error(format('select public.admin_get_roster_import(%L)',:'import_id'),'42501','roster_import_unavailable','new session cannot inherit old import');
select pg_temp.actor();
select pg_temp.expect_roster_error(format('select pg_temp.commit_roster(301,%L,%L,%L)',:'import_id',:'initial_revision',:'preview'::jsonb->>'reviewed_rows_sha256'),
 '55000','roster_revision_superseded','unreviewed preview cannot commit');
select pg_temp.expect_roster_error(format('select public.admin_review_roster_import(%L,%L,%L,%L,pg_temp.id(201))',:'import_id',:'initial_revision',
 jsonb_set(pg_temp.rows(),'{0,member_name}','"=SUM(A1)"'),'Reviewed every synthetic row'),'22023','roster_rows_invalid','formula name rejects entire reviewed revision');
select pg_temp.expect_roster_error(format('select public.admin_review_roster_import(%L,%L,%L,%L,pg_temp.id(201))',:'import_id',:'initial_revision',
 jsonb_set(pg_temp.rows(),'{1,momo_number}','"0789964001"'),'Reviewed every synthetic row'),'22023','roster_rows_invalid','duplicate normalized phone rejects entire revision');
select pg_temp.expect_roster_error(format('select public.admin_review_roster_import(%L,%L,%L,%L,pg_temp.id(201))',:'import_id',:'initial_revision',
 jsonb_set(pg_temp.rows(),'{0,momo_number}','"0719964001"'),'Reviewed every synthetic row'),'22023','roster_rows_invalid','unsupported phone prefix matches SQL canonicalizer');
select pg_temp.expect_roster_error(format('select public.admin_review_roster_import(%L,%L,%L,%L,pg_temp.id(201))',:'import_id',:'initial_revision',
 jsonb_set(pg_temp.rows(),'{0,extra}','"unexpected"'),'Reviewed every synthetic row'),'22023','roster_input_invalid','unknown row field denied');
select pg_temp.expect_roster_error(format('select public.admin_review_roster_import(%L,%L,(select jsonb_agg(pg_temp.rows()->0) from generate_series(1,501)),%L,pg_temp.id(201))',
 :'import_id',:'initial_revision','Reviewed every synthetic row'),'22023','roster_input_invalid','all-row bound rejects501 rows before writing');
select public.admin_review_roster_import(:'import_id',:'initial_revision',pg_temp.rows(),'Reviewed every synthetic row',pg_temp.id(201)) as reviewed \gset
select (:'reviewed'::jsonb->>'revision_id') as reviewed_revision \gset
select (:'reviewed'::jsonb->>'reviewed_rows_sha256') as reviewed_hash \gset
select pg_temp.check_roster(:'reviewed'::jsonb->>'parent_revision_id'=:'initial_revision' and (:'reviewed'::jsonb->>'revision_number')::int=2
 and :'reviewed'::jsonb->'can_submit'='true' and :'reviewed'::jsonb->'source_receipt'=:'preview'::jsonb->'source_receipt','human review keeps parent and source metadata');
select pg_temp.check_roster(public.admin_review_roster_import(:'import_id',:'initial_revision',pg_temp.rows(),'Reviewed every synthetic row',pg_temp.id(201))=:'reviewed'::jsonb,
 'exact review retry returns one immutable revision');
select pg_temp.expect_roster_error(format('select public.admin_review_roster_import(%L,%L,pg_temp.rows(),%L,pg_temp.id(201))',:'import_id',:'initial_revision','Changed reviewed reason'),
 '55000','roster_request_conflict','review request binds audit reason');
select pg_temp.expect_roster_error(format('select public.admin_review_roster_import(%L,%L,pg_temp.rows(),%L,pg_temp.id(202))',:'import_id',:'initial_revision','Reviewed every synthetic row'),
 '55000','roster_revision_superseded','stale revision cannot fork review history');
select pg_temp.expect_roster_error(format('select public.admin_commit_roster_import(pg_temp.id(301),%L,%L,%L,false,''create'',null,''Synthetic provenance group'',''Reviewed every synthetic member row'')',
 :'import_id',:'reviewed_revision',:'reviewed_hash'),'22023','roster_input_invalid','explicit human affirmation required');
select pg_temp.expect_roster_error(format('select pg_temp.commit_roster(301,%L,%L,%L)',:'import_id',:'reviewed_revision',repeat('0',64)),
 '55000','roster_request_conflict','wrong reviewed hash cannot commit');
select pg_temp.commit_roster(301,:'import_id',:'reviewed_revision',:'reviewed_hash') as committed \gset
select (:'committed'::jsonb->>'collection_id') as collection_id \gset
select pg_temp.check_roster(:'committed'::jsonb=jsonb_build_object('contract_version',1,'ok',true,'request_id',pg_temp.id(301),'import_id',:'import_id'::uuid,
 'revision_id',:'reviewed_revision'::uuid,'reviewed_rows_sha256',:'reviewed_hash','collection_id',:'collection_id'::uuid,'mode','create',
 'roster_count',2,'share_code_ready',true,'replayed',false),'strict commit ACK binds request import revision hash collection and count');
select pg_temp.check_roster(pg_temp.commit_roster(301,:'import_id',:'reviewed_revision',:'reviewed_hash')=(:'committed'::jsonb||'{"replayed":true}'),
 'same commit request replays exactly once');
select pg_temp.expect_roster_error(format('select pg_temp.commit_roster(302,%L,%L,%L)',:'import_id',:'reviewed_revision',:'reviewed_hash'),
 '55000','roster_import_committed','second request cannot consume committed import');
select pg_temp.expect_roster_error(format('select public.admin_commit_roster_import(pg_temp.id(301),%L,%L,%L,true,''create'',null,''Different title'',''Reviewed every synthetic member row'')',
 :'import_id',:'reviewed_revision',:'reviewed_hash'),'55000','roster_request_conflict','commit replay binds title');
select pg_temp.check_roster(public.admin_get_roster_import(:'import_id')->>'state'='committed'
 and public.admin_get_roster_import(:'import_id')->'preview'->'can_submit'='false','read distinguishes historical commit from new action');
reset role;
select pg_temp.check_roster((select count(*)=2 from public.collection_members where collection_id=:'collection_id' and role='member')
 and (select count(*)=1 from collect_hybrid.roster_import_commits where import_id=:'import_id')
 and (select count(*)=1 from public.audit_logs where entity_id=:'collection_id' and action='roster.import.committed'),
 'one atomic membership graph and audit acknowledgement');

-- Every current-authority loss denies even successful replay.
savepoint revoke_session;
delete from auth.sessions where id=pg_temp.id(11);
set local role authenticated;
select pg_temp.actor();
select pg_temp.expect_roster_error(format('select pg_temp.commit_roster(301,%L,%L,%L)',:'import_id',:'reviewed_revision',:'reviewed_hash'),
 '42501','roster_actor_unavailable','deleted session denies successful commit replay');
reset role;
rollback to savepoint revoke_session;
select pg_temp.check_roster(true,'deleted-session denial rolled back');
savepoint revoke_role;
update public.admin_user_roles set revoked_at=clock_timestamp() where user_id=pg_temp.id(1) and revoked_at is null;
set local role authenticated;
select pg_temp.actor();
select pg_temp.expect_roster_error(format('select public.admin_get_roster_import(%L)',:'import_id'),'42501','roster_actor_unavailable','revoked role cannot read receipts');
reset role;
rollback to savepoint revoke_role;
select pg_temp.check_roster(true,'revoked-role denial rolled back');

-- AI consent/attempt facts precede completion and survive correction; no HTTP.
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.source(102,'pdf') as ai_source \gset
select (:'ai_source'::jsonb->>'import_id') as ai_import \gset
reset role;
select pg_temp.check_roster((select count(*)=1 from collect_hybrid.roster_import_extractions where import_id=:'ai_import')
 and not exists(select 1 from collect_hybrid.roster_import_results where import_id=:'ai_import'),'AI consent and extraction metadata precede any result');
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.complete(:'ai_import',true) as ai_preview \gset
set local role authenticated;
select pg_temp.actor();
select public.admin_review_roster_import(:'ai_import',(:'ai_preview'::jsonb->>'revision_id')::uuid,pg_temp.rows(),
 'Reviewed extracted synthetic rows',pg_temp.id(202)) as ai_reviewed \gset
select pg_temp.check_roster(:'ai_reviewed'::jsonb->'source_receipt'->>'extraction_id'=:'ai_source'::jsonb->>'extraction_id'
 and :'ai_reviewed'::jsonb->'source_receipt'->'ai_consent'='true' and :'ai_reviewed'::jsonb->'source_receipt'->>'consent_version'='roster-ai-extraction-v1'
 and :'ai_reviewed'::jsonb->>'model'='synthetic-model','human correction preserves original AI extraction and consent');
select pg_temp.commit_roster(303,:'ai_import',(:'ai_reviewed'::jsonb->>'revision_id')::uuid,:'ai_reviewed'::jsonb->>'reviewed_rows_sha256','existing',:'collection_id') as existing_result \gset
select pg_temp.check_roster(:'existing_result'::jsonb->>'mode'='existing' and :'existing_result'::jsonb->>'collection_id'=:'collection_id'
 and (:'existing_result'::jsonb->>'roster_count')::int=2,'existing-group commit uses same strict reference path');
reset role;
select pg_temp.check_roster((select count(*)=2 from public.collection_members where collection_id=:'collection_id' and role='member'),
 'existing identities create no duplicate memberships');

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.source(103,'xlsx') as xlsx_source \gset
select pg_temp.complete((:'xlsx_source'::jsonb->>'import_id')::uuid) as xlsx_preview \gset
select pg_temp.check_roster(:'xlsx_preview'::jsonb->'source_receipt'->>'derived_assurance'='client_derived_tsv'
 and :'xlsx_preview'::jsonb->'source_receipt'->>'detected_type'='zip_container'
 and :'xlsx_preview'::jsonb->'source_receipt'->>'derived_sha256'=repeat('c',64),'XLSX source never claims server workbook verification');
set local role authenticated;
select pg_temp.actor();
select public.admin_review_roster_import((:'xlsx_source'::jsonb->>'import_id')::uuid,(:'xlsx_preview'::jsonb->>'revision_id')::uuid,
 jsonb_set(pg_temp.rows(),'{0,member_name}','"Conflicting identity"'),'Reviewed synthetic conflict case',pg_temp.id(203)) as conflict_review \gset
select pg_temp.expect_roster_error(format('select pg_temp.commit_roster(304,%L,%L,%L)',:'xlsx_source'::jsonb->>'import_id',
 :'conflict_review'::jsonb->>'revision_id',:'conflict_review'::jsonb->>'reviewed_rows_sha256'),
 '55000','roster_commit_conflict','existing identity mismatch rolls new group share and membership back');
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.source(104,'pdf') as failed_source \gset
select (:'failed_source'::jsonb->>'import_id') as failed_import \gset
select public.fail_roster_import_preview(:'failed_import',pg_temp.id(1),pg_temp.id(11),'roster_extraction_timeout') as failure_result \gset
select pg_temp.check_roster(public.fail_roster_import_preview(:'failed_import',pg_temp.id(1),pg_temp.id(11),'roster_extraction_timeout')
 =(:'failure_result'::jsonb||'{"replayed":true}'),'exact bounded extraction failure is replayable');
select pg_temp.check_roster(pg_temp.source(104,'pdf')->>'state'='failed' and pg_temp.source(104,'pdf')->>'error_code'='roster_extraction_timeout',
 'failed source retry returns safe failure without provider retry');
select pg_temp.expect_roster_error(format('select pg_temp.complete(%L,true)',:'failed_import'),'55000','roster_request_conflict','failure cannot be replaced with success');
reset role;

-- Prove all immutable evidence families reject owner mutation too.
select pg_temp.expect_roster_error('update collect_hybrid.roster_import_sources set source_size=1 where request_id=pg_temp.id(101)',
 '55000','roster_provenance_immutable','source metadata immutable');
select pg_temp.expect_roster_error(format('delete from collect_hybrid.roster_import_extractions where import_id=%L',:'ai_import'),
 '55000','roster_provenance_immutable','AI consent attempt immutable');
select pg_temp.expect_roster_error(format('update collect_hybrid.roster_import_revisions set normalized_rows=''[]'' where id=%L',:'reviewed_revision'),
 '55000','roster_provenance_immutable','reviewed rows immutable');
select pg_temp.expect_roster_error(format('delete from collect_hybrid.roster_import_results where import_id=%L',:'failed_import'),
 '55000','roster_provenance_immutable','terminal extraction result immutable');
select pg_temp.expect_roster_error('delete from collect_hybrid.roster_import_commits where request_id=pg_temp.id(301)',
 '55000','roster_provenance_immutable','commit acknowledgement immutable');

-- Privileged, clearly synthetic historical fixture for clock-expiry semantics.
-- Inserts only; immutable live records and triggers are never altered.
insert into collect_hybrid.roster_import_sources(id,request_id,actor_id,session_id,source_kind,source_sha256,source_size,
 client_filename,declared_mime,detected_type,ai_consent,input_sha256,created_at,expires_at)
values(pg_temp.id(501),pg_temp.id(105),pg_temp.id(1),pg_temp.id(11),'text',encode(extensions.digest('synthetic original bytes 105','sha256'),'hex'),99,
 'pasted-roster.txt','text/plain','utf8_text',false,
 collect_hybrid.roster_digest(jsonb_build_array(pg_temp.id(1),pg_temp.id(11),'text',encode(extensions.digest('synthetic original bytes 105','sha256'),'hex'),99,
  'pasted-roster.txt','text/plain','utf8_text',null,null,false,null,null)),clock_timestamp()-interval '25 hours',clock_timestamp()-interval '1 hour');
insert into collect_hybrid.roster_import_revisions(id,import_id,revision_number,actor_id,session_id,processing_method,preview,normalized_rows,reviewed_rows_sha256,input_sha256)
select pg_temp.id(502),pg_temp.id(501),1,pg_temp.id(1),pg_temp.id(11),'deterministic',preview,normalized_rows,reviewed_rows_sha256,input_sha256
from collect_hybrid.roster_import_revisions where id=:'initial_revision';
insert into collect_hybrid.roster_import_results(import_id,actor_id,session_id,state,revision_id,processing_metadata,input_sha256)
select pg_temp.id(501),pg_temp.id(1),pg_temp.id(11),'preview_ready',pg_temp.id(502),processing_metadata,input_sha256
from collect_hybrid.roster_import_results where import_id=:'import_id';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.check_roster((pg_temp.source(105)->>'replayed')::boolean and pg_temp.source(105)->>'state'='preview_ready'
 and (pg_temp.source(105)->'completed_preview'->>'expires_at')::timestamptz<clock_timestamp()
 and pg_temp.source(105)->'completed_preview'->'can_submit'='false','expired exact source replay returns bounded noncommittable cached initial preview');
reset role;
insert into collect_hybrid.roster_import_revisions(id,import_id,parent_revision_id,revision_number,request_id,actor_id,session_id,processing_method,
 preview,normalized_rows,reviewed_rows_sha256,input_sha256,reason)
select pg_temp.id(503),pg_temp.id(501),pg_temp.id(502),2,pg_temp.id(205),pg_temp.id(1),pg_temp.id(11),'human_review',
 preview,normalized_rows,reviewed_rows_sha256,input_sha256,'Synthetic historical reviewed rows'
from collect_hybrid.roster_import_revisions where id=:'reviewed_revision';
set local role authenticated;
select pg_temp.actor();
select pg_temp.expect_roster_error(format('select pg_temp.commit_roster(305,pg_temp.id(501),pg_temp.id(503),%L)',:'reviewed_hash'),
 '55000','roster_import_expired','expired reviewed import cannot newly commit');
reset role;
insert into collect_hybrid.roster_import_commits(request_id,import_id,revision_id,collection_id,actor_id,session_id,input_sha256,response,committed_at)
values(pg_temp.id(305),pg_temp.id(501),pg_temp.id(503),:'collection_id',pg_temp.id(1),pg_temp.id(11),
 collect_hybrid.roster_digest(jsonb_build_array(pg_temp.id(501),pg_temp.id(503),:'reviewed_hash',true,'create',null,'Synthetic provenance group',
 'Reviewed every synthetic member row',pg_temp.id(1),pg_temp.id(11))),
 :'committed'::jsonb||jsonb_build_object('request_id',pg_temp.id(305),'import_id',pg_temp.id(501),'revision_id',pg_temp.id(503)),clock_timestamp()-interval '2 hours');
set local role authenticated;
select pg_temp.actor();
select pg_temp.check_roster((pg_temp.commit_roster(305,pg_temp.id(501),pg_temp.id(503),:'reviewed_hash')->>'replayed')::boolean,
 'successful historical commit replays after preview expiry without new writes');
reset role;

select pg_temp.check_roster(not has_function_privilege('authenticated',
 'public.create_roster_import_source(uuid,uuid,uuid,text,text,bigint,text,text,text,text,bigint,boolean,text,jsonb)','EXECUTE')
 and not has_function_privilege('service_role','public.admin_commit_roster_import(uuid,uuid,uuid,text,boolean,text,uuid,text,text)','EXECUTE')
 and not has_function_privilege('authenticated','collect_hybrid.add_roster(uuid,jsonb,uuid,text)','EXECUTE')
 and not has_table_privilege('authenticated','collect_hybrid.roster_import_sources','SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('service_role','collect_hybrid.roster_import_revisions','SELECT,INSERT,UPDATE,DELETE'),'private receipts and narrow RPC grants enforced');
select pg_temp.check_roster((select count(*)=3 from auth.users where id::text like '99640000-%'),'roster never creates fake Auth members');
do $$ declare key text; after_state jsonb:=pg_temp.roster_snapshot(); before_state jsonb:=(select body from roster_financial_baseline); begin
 foreach key in array array['public.payments','public.ledger_entries','collect_hybrid.momo_journal_entries','collect_hybrid.momo_journal_lines',
  'collect_hybrid.collection_balances','collect_hybrid.member_balances'] loop
  perform pg_temp.check_roster(after_state->key=before_state->key,'roster leaves financial table unchanged: '||key);
 end loop;
end $$;
set constraints all immediate;
select 'ROSTER_IMPORT_PROVENANCE_UAT_PASS' as result,count(*) as assertions from roster_provenance_results;
rollback;
