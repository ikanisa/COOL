\set ON_ERROR_STOP on
-- ROOT ONLY: exact offline147 fixture, every mutation rolls back.
begin;
set local statement_timeout='30s';set local lock_timeout='5s';set local timezone='UTC';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres'
  or current_setting('collect.runtime_controls_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>147
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930150000'
  or exists(select 1 from auth.users where id::text like '99720000-%')
  or exists(select 1 from public.feature_flags where key like 'qa_runtime_147%')
  or exists(select 1 from public.policy_documents where id::text like '99720000-%') then
  raise exception 'Exact isolated147 and unused9972 fixture required';end if;
end $$;
create temp table runtime_checks(n integer);insert into runtime_checks values(0);
create function pg_temp.expect(stmt text,code text,message text default null) returns void language plpgsql as $$
begin
 begin execute stmt;exception when others then
  if sqlstate<>code or message is not null and sqlerrm<>message then raise exception 'Expected %/%, got %/%',code,message,sqlstate,sqlerrm;end if;
  update runtime_checks set n=n+1;return;
 end;raise exception 'Expected rejection %/%',code,message;
end $$;
grant all on runtime_checks to authenticated,anon,service_role;
do $$ begin execute format('grant usage on schema %I to authenticated,anon,service_role',pg_my_temp_schema()::regnamespace::text);end $$;
grant execute on function pg_temp.expect(text,text,text) to authenticated,anon,service_role;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
 ('99720000-0000-4000-8000-000000000001','authenticated','authenticated','250788972001',now(),'{}','{}'),
 ('99720000-0000-4000-8000-000000000002','authenticated','authenticated','250788972002',now(),'{}','{}'),
 ('99720000-0000-4000-8000-000000000003','authenticated','authenticated','250788972003',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id::text like '99720000-%';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99720000-0000-4000-8000-000000000001','+250788972001',now()-interval '2 minutes','Synthetic runtime governance fixture'),
 ('99720000-0000-4000-8000-000000000003','+250788972003',now()-interval '2 minutes','Synthetic operator fixture');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select x.user_id,r.id,'Synthetic runtime governance role',now()-interval '1 minute' from (values('99720000-0000-4000-8000-000000000001'::uuid),('99720000-0000-4000-8000-000000000003'::uuid)) x(user_id) cross join public.admin_roles r where r.name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
 ('99720000-0000-4000-8000-000000000011','99720000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1'),
 ('99720000-0000-4000-8000-000000000012','99720000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour','aal1'),
 ('99720000-0000-4000-8000-000000000013','99720000-0000-4000-8000-000000000003',now(),now(),now()+interval '1 hour','aal1');
insert into public.notification_preferences(user_id,payment_reminders) values('99720000-0000-4000-8000-000000000001',false);
insert into public.feature_flags(key,enabled,description) values('qa_runtime_147',false,'Synthetic runtime flag');
insert into public.system_settings(key,value,is_sensitive) values('qa_runtime_147_private','"synthetic_not_a_secret"',true);
insert into public.policy_documents(id,kind,locale,version,title,summary) values
 ('99720000-0000-4000-8000-000000000101','terms','en','qa-runtime-147-a','Synthetic policy','Synthetic summary'),
 ('99720000-0000-4000-8000-000000000102','terms','en','qa-runtime-147-b','Synthetic draft','Synthetic summary');
insert into public.policy_document_sections(id,policy_document_id,section_key,title,body) values
 ('99720000-0000-4000-8000-000000000111','99720000-0000-4000-8000-000000000101','qa','Synthetic section','Synthetic policy body');
insert into public.notification_templates(key,event_type_key,locale) values('qa_runtime_147','security_notice','en');
insert into public.notification_template_versions(id,template_key,version,title_template,body_template) values
 ('99720000-0000-4000-8000-000000000121','qa_runtime_147','qa-147-a','Synthetic notice','Synthetic body {{group_name}}');
insert into public.payment_entrypoints(key,country_code,currency,network,label,code,metadata) values
 ('qa_runtime_147','RW','RWF','mtn_momo','Synthetic route','*182*8*1*41258*2000#','{"amount_rwf":2000}');
-- Full family registry/grant/guard/head coverage, including all live historical
-- rows. It verifies hashes without exporting any setting values.
do $$ declare family text;spec jsonb;r record;role_name text;begin
 foreach family in array array['brand_entities','support_channels','payment_entrypoints','feature_flags','system_settings','admin_navigation_items','admin_queue_specs','admin_queue_filter_options','admin_queue_signals','admin_queue_sla_policies','notification_preferences','notification_channels','notification_event_types','notification_templates','notification_template_versions','policy_documents','policy_document_sections','account_request_reason_options','collection_type_catalog','collection_category_subtypes','collection_purpose_templates','collection_type_country_rules','sms_receipt_policies','sms_receipt_member_consents','otp_policy','roster_resource_policy'] loop
  spec:=collect_security.runtime_control_spec(family);
  if spec is null or (select count(*) from pg_trigger where tgrelid=(spec->>'relation')::regclass and tgname='runtime_control_governance' and tgenabled='O')<>1 then raise exception 'Missing family guard %',family;end if;
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_table_privilege(role_name,spec->>'relation','INSERT,UPDATE,DELETE,TRUNCATE') then raise exception 'Direct writer grant leaked';end if;
  end loop;
  execute format('select count(*) bad from %s t left join collect_security.runtime_control_heads h on h.family=$1 and h.identity=collect_security.runtime_control_identity($1,to_jsonb(t)) where h.family is null or h.content_sha256 is distinct from collect_security.runtime_control_hash(to_jsonb(t))',spec->>'relation') into r using family;
  if r.bad<>0 then raise exception 'Unbound baseline head %',family;end if;
  update runtime_checks set n=n+1;
 end loop;
 foreach role_name in array array['anon','authenticated','service_role'] loop
  if has_table_privilege(role_name,'collect_security.runtime_control_events','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') or has_table_privilege(role_name,'collect_security.runtime_control_heads','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then raise exception 'Private governance grants leaked';end if;
 end loop;
 update runtime_checks set n=n+3;
end $$;
insert into collect_security.otp_policy(singleton,global_hourly_limit,global_daily_limit,enabled) values(true,100,1000,false) on conflict(singleton) do nothing;
create temp table runtime_fence_before as select to_jsonb(h) body from collect_security.runtime_control_heads h where family in ('otp_policy','roster_resource_policy');
create temp table runtime_fence_events_before as select count(*) n from collect_security.runtime_control_events where family in ('otp_policy','roster_resource_policy');
update collect_security.otp_policy set enabled=enabled;
update collect_hybrid.roster_resource_policy set version=version;
do $$ begin
 if (select jsonb_agg(body order by body::text) from runtime_fence_before) is distinct from (select jsonb_agg(to_jsonb(h) order by to_jsonb(h)::text) from collect_security.runtime_control_heads h where family in ('otp_policy','roster_resource_policy'))
 or (select n from runtime_fence_events_before)<>(select count(*) from collect_security.runtime_control_events where family in ('otp_policy','roster_resource_policy')) then raise exception 'Physical budget fences emitted fake governance';end if;
 update runtime_checks set n=n+2;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99720000-0000-4000-8000-000000000001","session_id":"99720000-0000-4000-8000-000000000011"}',true);
do $$ declare r jsonb;l jsonb;l2 jsonb;begin
 r:=public.admin_set_feature_flag_v2('qa_runtime_147',true,1,'Synthetic reason private literal');
 if (select array_agg(key order by key) from jsonb_object_keys(r) key) is distinct from array['changed','contract_version','enabled','key','ok','previous_revision','revision','updated_at']::text[]
 or r->>'contract_version'<>'2' or r->>'ok'<>'true' or r->>'key'<>'qa_runtime_147' or r->>'enabled'<>'true' or r->>'changed'<>'true' or r->>'previous_revision'<>'1' or r->>'revision'<>'2' then raise exception 'Feature ACK invalid';end if;
 r:=public.admin_set_feature_flag_v2('qa_runtime_147',true,2,'Synthetic no-op reason');
 if r->>'changed'<>'false' or r->>'revision'<>'2' then raise exception 'No-op revision invalid';end if;
 l:=public.admin_list_feature_flags('qa_runtime_147','enabled');
 if l->'rows'->0->'extra'->>'runtime_revision'<>'2' then raise exception 'Feature row revision absent';end if;
 l2:=public.admin_list_feature_flags('qa_runtime_147','enabled');
 if l->'rows'->0->>'id' is distinct from l2->'rows'->0->>'id' or l->'rows'->0->>'id' is distinct from md5('collect.runtime-control.row.v1:feature_flags:qa_runtime_147')::uuid::text then raise exception 'Feature immutable row identity invalid';end if;
 update runtime_checks set n=n+4;
end $$;
reset role;
grant update on public.feature_flags to authenticated;
create policy qa_runtime_context_guard on public.feature_flags for update to authenticated using(key='qa_runtime_147' and auth.uid()='99720000-0000-4000-8000-000000000001'::uuid) with check(key='qa_runtime_147' and auth.uid()='99720000-0000-4000-8000-000000000001'::uuid);
set local role authenticated;
do $$ declare valid_context jsonb;candidate jsonb;key_text text;begin
 valid_context:=jsonb_build_object('family','feature_flags','identity',jsonb_build_object('key','qa_runtime_147'),'expected_revision',2,'actor_id',auth.uid(),'session_id',auth.jwt()->>'session_id','reason_sha256',repeat('a',64),'reason_characters',8);
 -- Missing, unknown, wrong-type and out-of-range fields fail closed before
 -- casts/head lookup. Never count this temporary UAT grant as a deployed grant.
 foreach key_text in array array['family','identity','expected_revision','actor_id','session_id','reason_sha256','reason_characters'] loop
  candidate:=valid_context-key_text;perform set_config('collect.runtime_control_context',candidate::text,true);
  perform pg_temp.expect($s$update public.feature_flags set enabled=false where key='qa_runtime_147'$s$,'42501','runtime_control_revision_required');
 end loop;
 for candidate in select value from jsonb_array_elements(jsonb_build_array(
  valid_context||'{"extra":true}',valid_context||'{"family":null}',valid_context||'{"expected_revision":"2"}',valid_context||'{"expected_revision":2000000000}',valid_context||'{"reason_characters":7}',valid_context||'{"reason_characters":900}',valid_context||'{"reason_sha256":"invalid"}',valid_context||'{"session_id":"other"}')) loop
  perform set_config('collect.runtime_control_context',candidate::text,true);
  perform pg_temp.expect($s$update public.feature_flags set enabled=false where key='qa_runtime_147'$s$,'42501','runtime_control_revision_required');
 end loop;
 perform set_config('collect.runtime_control_context','',true);
end $$;
reset role;drop policy qa_runtime_context_guard on public.feature_flags;revoke update on public.feature_flags from authenticated;set local role authenticated;
select pg_temp.expect($s$select public.admin_set_feature_flag_v2('qa_runtime_147',false,1,'Synthetic stale edit')$s$,'40001','runtime_control_conflict');
select pg_temp.expect($s$select public.admin_set_feature_flag('qa_runtime_147',false,'Synthetic legacy edit')$s$,'22023','runtime_control_revision_required');
select pg_temp.expect($s$update public.feature_flags set enabled=false where key='qa_runtime_147'$s$,'42501');
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('feature_flags',null)$s$,'22023','runtime_control_identity_invalid');
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('policy_documents','{"id":null}')$s$,'22023','runtime_control_identity_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}',null,2,'Synthetic null patch')$s$,'22023','runtime_control_patch_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}','{"enabled":null}',2,'Synthetic null boolean')$s$,'22023','runtime_control_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}','{"enabled":"false"}',2,'Synthetic string boolean')$s$,'22023','runtime_control_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}','{"updated_by":"99720000-0000-4000-8000-000000000002"}',2,'Synthetic actor forgery')$s$,'22023','runtime_control_patch_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}',jsonb_build_object('description',repeat('x',2001)),2,'Synthetic long string')$s$,'22023','runtime_control_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}','{"metadata":{"api_key":"synthetic"}}',2,'Synthetic secret field')$s$,'22023','runtime_control_sensitive_field');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}','{"metadata":{"a":{"b":{"c":{"d":{"e":{"f":1}}}}}}}',2,'Synthetic deep metadata')$s$,'22023','runtime_control_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('payment_entrypoints','{"key":"qa_runtime_147"}','{"country_code":"UG"}',1,'Synthetic wrong country')$s$,'22023','runtime_control_rwanda_route_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('payment_entrypoints','{"key":"qa_runtime_147"}','{"metadata":{"amount_rwf":2001}}',1,'Synthetic wrong amount')$s$,'22023','runtime_control_payment_amount_mismatch');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('policy_documents','{"id":"99720000-0000-4000-8000-000000000101"}','{"effective_at":"infinity"}',1,'Synthetic invalid timestamp')$s$,'22023','runtime_control_invalid');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('otp_policy','{"singleton":true}','{"global_hourly_limit":2147483648}',1,'Synthetic oversized integer')$s$,'22023','runtime_control_invalid');
do $$ declare r jsonb;begin
 r:=public.admin_get_runtime_control_v1('system_settings','{"key":"qa_runtime_147_private"}');
 if r->>'redacted'<>'true' or r->'value' ? 'value' or r->>'content_sha256' is not null or r::text like '%synthetic_not_a_secret%' then raise exception 'Sensitive getter leaked';end if;
 update runtime_checks set n=n+1;
end $$;
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('system_settings','{"key":"qa_runtime_147_private"}','{"description":"Changed"}',1,'Synthetic secret edit')$s$,'42501','runtime_control_sensitive_setting_owner_only');
-- Publication freezes both parent copy and section wiring; new draft versions
-- retain prior published bytes and archived versions cannot be resurrected.
select public.admin_update_runtime_control_v1('policy_documents','{"id":"99720000-0000-4000-8000-000000000101"}','{"status":"published"}',1,'Synthetic publication reason');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('policy_documents','{"id":"99720000-0000-4000-8000-000000000101"}','{"title":"Replaced"}',2,'Synthetic published edit')$s$,'55000','runtime_control_published_immutable');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('policy_document_sections','{"id":"99720000-0000-4000-8000-000000000111"}','{"body":"Replaced"}',1,'Synthetic section edit')$s$,'55000','runtime_control_published_immutable');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('policy_document_sections','{"id":"99720000-0000-4000-8000-000000000111"}','{"policy_document_id":"99720000-0000-4000-8000-000000000102"}',1,'Synthetic parent escape')$s$,'55000','runtime_control_wiring_immutable');
select public.admin_update_runtime_control_v1('notification_template_versions','{"id":"99720000-0000-4000-8000-000000000121"}','{"status":"published"}',1,'Synthetic notice publication');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_template_versions','{"id":"99720000-0000-4000-8000-000000000121"}','{"body_template":"Replaced"}',2,'Synthetic template edit')$s$,'55000','runtime_control_published_immutable');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_templates','{"key":"qa_runtime_147"}','{"locale":"rw"}',1,'Synthetic template reinterpretation')$s$,'55000','runtime_control_published_immutable');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_template_versions','{"id":"99720000-0000-4000-8000-000000000122"}','{"template_key":"qa_runtime_147","version":"bad","title_template":"Notice","body_template":"Malformed {{ variable }"}',0,'Synthetic invalid template')$s$,'22023','runtime_control_invalid_template');
select public.admin_update_runtime_control_v1('notification_template_versions','{"id":"99720000-0000-4000-8000-000000000121"}','{"status":"archived"}',2,'Synthetic template archival');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_template_versions','{"id":"99720000-0000-4000-8000-000000000121"}','{"status":"draft"}',3,'Synthetic archived resurrection')$s$,'55000','runtime_control_published_immutable');
select public.admin_update_runtime_control_v1('notification_template_versions','{"id":"99720000-0000-4000-8000-000000000122"}','{"template_key":"qa_runtime_147","version":"qa-147-b","title_template":"New notice","body_template":"New draft body"}',0,'Synthetic additive version');
reset role;
select pg_temp.expect($s$delete from public.policy_documents where id='99720000-0000-4000-8000-000000000101'$s$,'55000','runtime_control_published_immutable');
select pg_temp.expect($s$delete from public.notification_templates where key='qa_runtime_147'$s$,'55000','runtime_control_published_immutable');
do $$ begin
 if not exists(select 1 from public.policy_document_sections where id='99720000-0000-4000-8000-000000000111' and body='Synthetic policy body')
 or not exists(select 1 from public.notification_template_versions where id='99720000-0000-4000-8000-000000000121' and body_template='Synthetic body {{group_name}}' and published_at is not null)
 or exists(select 1 from collect_security.runtime_control_events where reason_sha256 is null or changed_fields is null)
 or exists(select 1 from collect_security.runtime_control_events where family='system_settings' and not redacted)
 or exists(select 1 from collect_security.runtime_control_events where family='system_settings' and (old_sha256 is not null or new_sha256 is not null))
 or (select count(*) from collect_security.runtime_control_events where family='feature_flags' and identity_sha256=collect_security.runtime_control_hash('{"key":"qa_runtime_147"}'))<>2 then raise exception 'Immutable copy/redacted audit/no-op evidence invalid';end if;
 update runtime_checks set n=n+4;
end $$;
select pg_temp.expect($s$update collect_security.runtime_control_events set operation='delete'$s$,'55000','runtime_control_history_immutable');
-- An ordinary user gets exactly their own preferences without any Admin grant.
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99720000-0000-4000-8000-000000000002","session_id":"99720000-0000-4000-8000-000000000012"}',true);
do $$ declare r jsonb;begin
 r:=public.get_notification_preferences_v2();
 if r->>'revision'<>'0' or r->>'exists'<>'false' then raise exception 'Absent preferences defaults invalid';end if;
 r:=public.set_notification_preferences_v2('{"contribution_confirmations":true,"payment_reminders":false,"group_updates":true,"security_notices":true}',0);
 if (select array_agg(key order by key) from jsonb_object_keys(r) key) is distinct from array['changed','contract_version','ok','previous_revision','revision','updated_at','user_id']::text[] or r->>'contract_version'<>'2' or r->>'revision'<>'1' or r->>'user_id'<>'99720000-0000-4000-8000-000000000002' then raise exception 'Preference save ACK invalid';end if;
 r:=public.get_notification_preferences_v2();
 if (select array_agg(key order by key) from jsonb_object_keys(r) key) is distinct from array['contract_version','exists','ok','preferences','revision','user_id']::text[] or r->'preferences'->>'payment_reminders'<>'false' then raise exception 'Preference reader invalid';end if;
 update runtime_checks set n=n+3;
end $$;
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('feature_flags','{"key":"qa_runtime_147"}')$s$,'42501','runtime_control_permission_required');
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000001"}')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.set_notification_preferences_v2('{"contribution_confirmations":false,"payment_reminders":false,"group_updates":true,"security_notices":true}',0)$s$,'40001','runtime_control_conflict');
select pg_temp.expect($s$select public.set_notification_preferences_v2('{"security_notices":null}',1)$s$,'22023','runtime_control_patch_invalid');
select pg_temp.expect($s$update public.notification_preferences set payment_reminders=true where user_id='99720000-0000-4000-8000-000000000002'$s$,'42501');
-- Generic SECURITY DEFINER RPC ownership: a member, an approved operator,
-- and a platform owner all get the SAME error before any target lookup. Collect
-- uses one combined Admin role, so operator/owner contexts share the real role.
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99720000-0000-4000-8000-000000000002","session_id":"99720000-0000-4000-8000-000000000012"}',true);
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000001"}')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000001"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',0,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000001"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',1,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',0,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',1,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99720000-0000-4000-8000-000000000003","session_id":"99720000-0000-4000-8000-000000000013"}',true);
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000002"}')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000002"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',0,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000002"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',1,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',0,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',1,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99720000-0000-4000-8000-000000000001","session_id":"99720000-0000-4000-8000-000000000011"}',true);
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000002"}')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000002"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',0,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000002"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',1,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_get_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',0,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
select pg_temp.expect($s$select public.admin_update_runtime_control_v1('notification_preferences','{"user_id":"99720000-0000-4000-8000-000000000099"}','{"contribution_confirmations":false,"payment_reminders":true,"group_updates":true,"security_notices":true}',1,'Synthetic foreign preference edit')$s$,'42501','runtime_control_owner_required');
reset role;
update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='99720000-0000-4000-8000-000000000012';
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99720000-0000-4000-8000-000000000002","session_id":"99720000-0000-4000-8000-000000000012"}',true);
select pg_temp.expect($s$select public.get_notification_preferences_v2()$s$,'42501','runtime_control_session_required');
reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect($s$select public.admin_set_feature_flag_v2('qa_runtime_147',false,2,'Synthetic service bypass')$s$,'42501');
reset role;
select 'RUNTIME_CONTROL_UAT_CHECKS:'||n from runtime_checks;
rollback;
