begin;
-- Approved canonical translations only; immutable content2 and configuration1
-- remain distinct. This grants no dispatch, resend or historical catch-up.
select pg_advisory_xact_lock(193517,141);
select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
lock table collect_hybrid.sms_receipt_policies in access exclusive mode;
lock table collect_security.runtime_control_heads in share row exclusive mode;
do $guard$ declare expected record;oid_value oid;begin
 for expected in select * from(values
 ('collect_security.runtime_control_spec(text)','8262fe001536479c1d47b2c9b29b9b6c4738024f5e8c2ef57360917e687d8761'),
 ('collect_security.runtime_control_check_values(text,jsonb)','9ad11fd161b389f1f4480fd0303dfd3433ff097a9754a4fa7d61fae68035094b'),
 ('collect_receipt_policy.render_v2(bigint,bigint,timestamp with time zone,text,text)','ad9aeab9070a7e47635cd2b7b6ec508e7e2d319d62665d7173fa70d0e3c1475e'),
 ('collect_receipt_policy.render_snapshot(collect_hybrid.momo_balance_snapshots,integer,text)','fbc4e68a5f2ea3031a0552b4febb322adc9ed576abf746f5be7dfa2bba7b4d36'),
 ('collect_receipt_policy.snapshot_is_eligible(collect_hybrid.momo_balance_snapshots)','519c93e37e987d8815133980fc8343b0604223c9234a0c415de9ffe2e333558e'),
 ('collect_receipt_policy.body_for_job(collect_hybrid.sms_notification_outbox)','e16049edbd69a3914ecd15cfd54563f54f7d5e3129a452c637aca81d92845411'),
 ('collect_receipt_policy.content_is_valid(collect_hybrid.sms_notification_outbox)','e7636567846a564750167f6acf0f9f37f5aeec33ddd7c358b85afd2872556fc9'),
 ('collect_hybrid.enqueue_sms_receipt_from_snapshot()','b93c68120a9977b08a0cad6d5448ac2d02d7bf0741431f7efdb4ec00d4bfe394'),
 ('collect_hybrid.sms_receipt_job_is_current(uuid)','ee0317da6de4ca4f6a25c864a402cd9d1d80240d79e2f4be7b84f8b0f54ffa1f'),
 ('public.admin_get_collect_investigation_v1(text,uuid)','30a6151051d6170772e7db15e980f3fa1b4e84d3e44b96d9195720812c974c8a'),
 ('collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)','12f31699d3055e82b490ac88e786a5d675beea3864fdf8e3c1d6ae907496b53a'),
 ('collect_gateway_dispatch.segment_count(text)','d2bf7155304e5855c68b1353647ad7bb7d1beeab01beaf2211920b974197a13d'),
 ('collect_hybrid.claim_verified_current_account()','0a0ba27796959b1a5630dc63048da8e90c67adeb47ab156215870e2d6a9341d2')
 )v(signature,body_sha256)loop
  oid_value:=to_regprocedure(expected.signature);
  if oid_value is null or (select encode(extensions.digest(prosrc,'sha256'),'hex') from pg_proc where oid=oid_value)
   is distinct from expected.body_sha256 then
   raise exception 'receipt_language_predecessor_drift:%',expected.signature using errcode='55000';end if;
 end loop;
end $guard$;
create temporary table receipt_language_adoption on commit drop as
 select p.collection_id,to_jsonb(p) old_row,jsonb_build_object('collection_id',p.collection_id) identity,
  h.revision previous_revision,h.content_sha256 old_sha256
 from collect_hybrid.sms_receipt_policies p left join collect_security.runtime_control_heads h
 on h.family='sms_receipt_policies' and h.identity=jsonb_build_object('collection_id',p.collection_id);
do $capture$ begin
 if exists(select 1 from pg_temp.receipt_language_adoption a where a.previous_revision is null
  or a.previous_revision>=1000000000 or a.old_sha256 is distinct from collect_security.runtime_control_hash(a.old_row))then
  raise exception 'receipt_language_governance_adoption_invalid'using errcode='55000';end if;
end $capture$;
alter table collect_hybrid.sms_receipt_policies add column receipt_language text not null default 'rw'
 constraint sms_receipt_policies_receipt_language_check check(receipt_language in('rw','en','fr'));
-- ALTER supplies the compatible default without triggering a business UPDATE.
-- Adopt the changed full-row fingerprint through a genuine owner schema event.
insert into collect_security.runtime_control_events(family,identity_sha256,previous_revision,revision,
 operation,old_sha256,new_sha256,changed_fields,actor_id,session_id,authority,reason_sha256,redacted,reason_characters,recorded_at)
select 'sms_receipt_policies',collect_security.runtime_control_hash(a.identity),a.previous_revision,a.previous_revision+1,
 'update',a.old_sha256,collect_security.runtime_control_hash(to_jsonb(p)),array['receipt_language'],null,null,'database_owner',
 encode(extensions.digest('Adopt governed receipt language with rw-compatible schema default','sha256'),'hex'),false,
 char_length('Adopt governed receipt language with rw-compatible schema default'),transaction_timestamp()
from pg_temp.receipt_language_adoption a join collect_hybrid.sms_receipt_policies p using(collection_id);
do $adopt$ declare changed integer;begin
 update collect_security.runtime_control_heads h set revision=a.previous_revision+1,
 content_sha256=collect_security.runtime_control_hash(to_jsonb(p)),updated_at=transaction_timestamp()
 from pg_temp.receipt_language_adoption a join collect_hybrid.sms_receipt_policies p using(collection_id)
 where h.family='sms_receipt_policies' and h.identity=a.identity
 and h.revision=a.previous_revision and h.content_sha256=a.old_sha256;
 get diagnostics changed=row_count;
 if changed<>(select count(*)from pg_temp.receipt_language_adoption)or exists(
  select 1 from pg_temp.receipt_language_adoption a join collect_hybrid.sms_receipt_policies p using(collection_id)
  left join collect_security.runtime_control_heads h on h.family='sms_receipt_policies'and h.identity=a.identity
  where to_jsonb(p)-'receipt_language' is distinct from a.old_row or p.receipt_language<>'rw'
  or h.revision is distinct from a.previous_revision+1
  or h.content_sha256 is distinct from collect_security.runtime_control_hash(to_jsonb(p)))then
  raise exception 'receipt_language_governance_adoption_invalid'using errcode='55000';end if;
end $adopt$;
alter table collect_receipt_policy.content_evidence drop constraint content_evidence_language_check;
alter table collect_receipt_policy.content_evidence add constraint content_evidence_language_check
 check(language in('rw','en','fr'));


create or replace function collect_security.runtime_control_spec(p_family text) returns jsonb
language sql immutable security definer set search_path='' as $spec$
 select '{"account_request_reason_options":{"create_allowed":true,"identity":["request_type","locale","key"],"immutable_after_create":[],"nullable":["description","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.account_request_reason_options","types":{"created_at":"timestamp with time zone","description":"text","display_order":"integer","enabled":"boolean","key":"text","label":"text","locale":"text","metadata":"jsonb","request_type":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","description","display_order","enabled","metadata"]},"admin_navigation_items":{"create_allowed":false,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_navigation_items","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","icon_key":"text","key":"text","label":"text","metadata":"jsonb","required_permission":"text","route_path":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","icon_key","display_order","enabled","metadata"]},"admin_queue_filter_options":{"create_allowed":true,"identity":["id"],"immutable_after_create":["rpc_name","filter_kind","value"],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_filter_options","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","filter_kind":"text","id":"uuid","label":"text","rpc_name":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","value":"text"},"writable":["rpc_name","filter_kind","value","label","display_order","enabled"]},"admin_queue_signals":{"create_allowed":true,"identity":["id"],"immutable_after_create":["rpc_name","signal_kind"],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_signals","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","icon_key":"text","id":"uuid","label":"text","rpc_name":"text","signal_kind":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["rpc_name","signal_kind","icon_key","label","display_order","enabled"]},"admin_queue_sla_policies":{"create_allowed":true,"identity":["queue_key"],"immutable_after_create":[],"nullable":["updated_by"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_sla_policies","types":{"escalation":"text","owner":"text","queue_key":"text","target":"text","updated_at":"timestamp with time zone","updated_by":"uuid"},"writable":["target","owner","escalation"]},"admin_queue_specs":{"create_allowed":false,"identity":["rpc_name"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_specs","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","metadata":"jsonb","required_permission":"text","rpc_name":"text","subtitle":"text","title":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["title","subtitle","display_order","enabled","metadata"]},"brand_entities":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["admin_url","app_download_url","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.brand_entities","types":{"admin_url":"text","app_download_url":"text","created_at":"timestamp with time zone","display_name":"text","is_active":"boolean","key":"text","legal_name":"text","metadata":"jsonb","public_url":"text","regulatory_footer_note":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["display_name","legal_name","public_url","admin_url","app_download_url","regulatory_footer_note","metadata","is_active"]},"collection_category_subtypes":{"create_allowed":true,"identity":["collection_type_key","key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_category_subtypes","types":{"collection_type_key":"text","created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","display_order","enabled","metadata"]},"collection_purpose_templates":{"create_allowed":true,"identity":["collection_type_key","key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_purpose_templates","types":{"collection_type_key":"text","created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","display_order","enabled","metadata"]},"collection_type_catalog":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_type_catalog","types":{"created_at":"timestamp with time zone","default_category_subtype":"text","default_purpose_template_key":"text","display_order":"integer","enabled":"boolean","icon_key":"text","key":"text","label":"text","metadata":"jsonb","short_purpose":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","short_purpose","icon_key","default_category_subtype","default_purpose_template_key","display_order","enabled","metadata"]},"collection_type_country_rules":{"create_allowed":true,"identity":["collection_type_key","country_code"],"immutable_after_create":[],"nullable":["min_suggested_amount_rwf","max_suggested_amount_rwf","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_type_country_rules","types":{"collection_type_key":"text","country_code":"text","created_at":"timestamp with time zone","enabled":"boolean","max_suggested_amount_rwf":"bigint","metadata":"jsonb","min_suggested_amount_rwf":"bigint","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["enabled","min_suggested_amount_rwf","max_suggested_amount_rwf","metadata"]},"feature_flags":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"feature_flags.manage","read_permission":"feature_flags.read","relation":"public.feature_flags","types":{"created_at":"timestamp with time zone","description":"text","enabled":"boolean","key":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["enabled","description","metadata"]},"notification_channels":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_channels","types":{"created_at":"timestamp with time zone","description":"text","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","platform":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","description","platform","enabled","display_order","metadata"]},"notification_event_types":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_event_types","types":{"created_at":"timestamp with time zone","default_channel_key":"text","description":"text","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","preference_key":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["preference_key","label","description","default_channel_key","enabled","display_order","metadata"]},"notification_preferences":{"create_allowed":true,"identity":["user_id"],"immutable_after_create":[],"nullable":[],"relation":"public.notification_preferences","types":{"contribution_confirmations":"boolean","created_at":"timestamp with time zone","group_updates":"boolean","payment_reminders":"boolean","security_notices":"boolean","updated_at":"timestamp with time zone","user_id":"uuid"},"user_owned":true,"writable":["contribution_confirmations","payment_reminders","group_updates","security_notices"]},"notification_template_versions":{"create_allowed":true,"identity":["id"],"immutable_after_create":["template_key","version"],"nullable":["published_at","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_template_versions","types":{"body_template":"text","created_at":"timestamp with time zone","effective_at":"timestamp with time zone","id":"uuid","metadata":"jsonb","published_at":"timestamp with time zone","status":"text","template_key":"text","title_template":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","version":"text"},"writable":["template_key","version","title_template","body_template","status","effective_at","metadata"]},"notification_templates":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_templates","types":{"created_at":"timestamp with time zone","enabled":"boolean","event_type_key":"text","key":"text","locale":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["event_type_key","locale","enabled","metadata"]},"otp_policy":{"additional_permission":"notifications.manage","create_allowed":false,"identity":["singleton"],"immutable_after_create":[],"nullable":[],"permission":"settings.manage","read_permission":"settings.read","relation":"collect_security.otp_policy","types":{"enabled":"boolean","global_daily_limit":"integer","global_hourly_limit":"integer","singleton":"boolean"},"writable":["global_hourly_limit","global_daily_limit","enabled"]},"payment_entrypoints":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["display_code","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.payment_entrypoints","types":{"code":"text","country_code":"text","created_at":"timestamp with time zone","currency":"text","display_code":"text","instructions":"text","is_active":"boolean","key":"text","label":"text","metadata":"jsonb","network":"text","sort_order":"integer","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["country_code","currency","network","label","code","display_code","instructions","sort_order","metadata","is_active"]},"policy_document_sections":{"create_allowed":true,"identity":["id"],"immutable_after_create":["policy_document_id","section_key"],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.policy_document_sections","types":{"body":"text","created_at":"timestamp with time zone","display_order":"integer","id":"uuid","metadata":"jsonb","policy_document_id":"uuid","section_key":"text","title":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["policy_document_id","section_key","title","body","display_order","metadata"]},"policy_documents":{"create_allowed":true,"identity":["id"],"immutable_after_create":[],"nullable":["summary","published_at","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.policy_documents","types":{"created_at":"timestamp with time zone","effective_at":"timestamp with time zone","id":"uuid","kind":"text","locale":"text","metadata":"jsonb","published_at":"timestamp with time zone","status":"text","summary":"text","title":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","version":"text"},"writable":["kind","locale","version","title","summary","status","effective_at","metadata"]},"roster_resource_policy":{"additional_permission":"collections.moderate","create_allowed":false,"identity":["id"],"immutable_after_create":[],"nullable":[],"permission":"settings.manage","read_permission":"settings.read","relation":"collect_hybrid.roster_resource_policy","types":{"actor_active":"integer","actor_daily_bytes":"bigint","actor_daily_cost_units":"bigint","actor_daily_requests":"integer","ai_attempt_cost_units":"bigint","global_active":"integer","global_daily_bytes":"bigint","global_daily_cost_units":"bigint","global_daily_requests":"integer","id":"boolean","version":"integer"},"writable":["actor_daily_requests","actor_daily_bytes","actor_active","global_daily_requests","global_daily_bytes","global_active","actor_daily_cost_units","global_daily_cost_units","ai_attempt_cost_units"]},"sms_receipt_member_consents":{"additional_permission":"users.read","create_allowed":true,"identity":["member_record_id"],"immutable_after_create":[],"nullable":[],"permission":"notifications.manage","read_permission":"notifications.read","relation":"collect_hybrid.sms_receipt_member_consents","types":{"capture_method":"text","enabled":"boolean","member_record_id":"uuid","reason":"text","recorded_at":"timestamp with time zone","recorded_by":"uuid","revision":"integer"},"writable":["enabled","capture_method"]},"sms_receipt_policies":{"additional_permission":"collections.moderate","create_allowed":true,"identity":["collection_id"],"immutable_after_create":[],"nullable":[],"permission":"notifications.manage","read_permission":"notifications.read","relation":"collect_hybrid.sms_receipt_policies","types":{"collection_id":"uuid","enabled":"boolean","reason":"text","revision":"integer","template_key":"text","template_version":"integer","updated_at":"timestamp with time zone","updated_by":"uuid","receipt_language":"text"},"writable":["enabled","receipt_language"]},"support_channels":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["display_value","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.support_channels","types":{"channel_type":"text","created_at":"timestamp with time zone","display_value":"text","is_active":"boolean","key":"text","label":"text","metadata":"jsonb","sort_order":"integer","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","value":"text"},"writable":["channel_type","label","value","display_value","sort_order","metadata","is_active"]},"system_settings":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.system_settings","types":{"created_at":"timestamp with time zone","description":"text","is_sensitive":"boolean","key":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","value":"jsonb"},"writable":["value","description"]}}'::jsonb -> p_family;
$spec$;

create or replace function collect_security.runtime_control_check_values(p_family text,p_values jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family); field record; typ text; value_type text; clean text; limit_chars integer; numeric_value numeric;
begin
 if spec is null or p_values is null or jsonb_typeof(p_values)<>'object' or octet_length(p_values::text)>65536 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
 for field in select * from jsonb_each(p_values) loop
  typ:=spec->'types'->>field.key;value_type:=jsonb_typeof(field.value);clean:=field.value#>>'{}';
  if typ is null then raise exception 'runtime_control_invalid' using errcode='22023';end if;
  if value_type='null' then
   if not (spec->'nullable') ? field.key then raise exception 'runtime_control_invalid' using errcode='22023';end if;
   continue;
  end if;
  if typ='boolean' and value_type<>'boolean' or typ in ('integer','bigint') and (value_type<>'number' or clean !~ '^-?[0-9]+$')
    or typ in ('text','uuid','timestamp with time zone') and value_type<>'string' then raise exception 'runtime_control_invalid' using errcode='22023';end if;
  if typ in ('integer','bigint') then
   numeric_value:=clean::numeric;
   if typ='integer' and numeric_value not between -2147483648 and 2147483647 or typ='bigint' and numeric_value not between -100000000000 and 100000000000 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
  end if;
  if typ='jsonb' then perform collect_security.runtime_control_bound_json(field.value);end if;
  if typ='uuid' and clean !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then raise exception 'runtime_control_invalid' using errcode='22023';end if;
  if typ='timestamp with time zone' then
   if char_length(clean) not between 20 and 35 or clean !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then raise exception 'runtime_control_invalid' using errcode='22023';end if;
   begin
    if not isfinite(clean::timestamptz) or clean::timestamptz>clock_timestamp()+interval '2 years' or clean::timestamptz<'2000-01-01'::timestamptz then raise exception 'runtime_control_invalid' using errcode='22023';end if;
   exception when invalid_datetime_format or datetime_field_overflow then raise exception 'runtime_control_invalid' using errcode='22023';end;
  end if;
  if p_family='sms_receipt_policies'and field.key='receipt_language'and clean not in('rw','en','fr')then
   raise exception 'receipt_language_invalid'using errcode='22023';end if;
  if typ='text' then
   limit_chars:=case when field.key in ('body','body_template','instructions','regulatory_footer_note') then 24000 when field.key in ('description','subtitle','summary','short_purpose','target','owner','escalation') then 2000 when field.key like '%url' then 2048 else 500 end;
   if char_length(clean)>limit_chars or regexp_replace(clean,E'[\n\r\t]','','g') ~ '[[:cntrl:]]' then raise exception 'runtime_control_invalid' using errcode='22023';end if;
   if field.key in ('key','queue_key','rpc_name','section_key','icon_key','version','locale','network','currency','country_code','required_permission','template_key','event_type_key','preference_key','collection_type_key','default_category_subtype','default_purpose_template_key')
    and (char_length(clean) not between 1 and 128 or clean !~ '^[A-Za-z0-9_.:-]+$') then raise exception 'runtime_control_invalid' using errcode='22023';end if;
   if field.key in ('label','display_name','legal_name','title','title_template','body_template','body','target','owner','escalation') and char_length(btrim(clean))=0 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
   if field.key like '%url' and not collect_security.runtime_control_https(clean) then raise exception 'runtime_control_invalid_url' using errcode='22023';end if;
   if field.key in ('title_template','body_template') and regexp_replace(clean,'\{\{[a-z][a-z0-9_]{0,63}\}\}','','g') ~ '(\{\{|\}\})' then raise exception 'runtime_control_invalid_template' using errcode='22023';end if;
  end if;
  if field.key in ('display_order','sort_order') and numeric_value not between 0 and 10000 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
 end loop;
end $$;

create function collect_receipt_policy.language_for_job(p_job collect_hybrid.sms_notification_outbox)
returns text language sql stable security definer set search_path=''as $$
 select case when p_job.template_version=1 then 'rw'when p_job.template_version=2 then
  (select e.language from collect_receipt_policy.content_evidence e where e.outbox_id=p_job.id and e.content_version=2)
 else null end
$$;
create function collect_receipt_policy.render_snapshot(p_snapshot collect_hybrid.momo_balance_snapshots,
 p_version integer,p_reference text,p_language text)returns text language sql stable security definer set search_path=''as $$
 select case when p_version=1 then collect_hybrid.render_buri_munsi_receipt(p_snapshot.delta_rwf,
  p_snapshot.member_balance_after_rwf,p_snapshot.group_balance_after_rwf,p_reference)
 when p_version=2 and p_language in('rw','en','fr')then collect_receipt_policy.render_v2(
  p_snapshot.delta_rwf,p_snapshot.member_balance_after_rwf,p_snapshot.captured_at,p_reference,p_language)else null end
$$;
revoke all on function collect_receipt_policy.language_for_job(collect_hybrid.sms_notification_outbox),
 collect_receipt_policy.render_snapshot(collect_hybrid.momo_balance_snapshots,integer,text,text)
 from public,anon,authenticated,service_role;


create or replace function collect_receipt_policy.body_for_job(p_job collect_hybrid.sms_notification_outbox)
returns text language sql stable security definer set search_path=''as $$
 select collect_receipt_policy.render_snapshot(s,p_job.template_version,p_job.reference,collect_receipt_policy.language_for_job(p_job))
 from collect_hybrid.momo_balance_snapshots s where s.id=p_job.snapshot_id
$$;

create or replace function collect_receipt_policy.content_is_valid(p_job collect_hybrid.sms_notification_outbox)
returns boolean language sql stable security definer set search_path=''as $$
 select coalesce(p_job.template_version=2 and exists(select 1 from collect_receipt_policy.content_evidence e
 join collect_hybrid.momo_balance_snapshots s on s.id=p_job.snapshot_id
 where e.outbox_id=p_job.id and e.content_version=2 and e.language in('rw','en','fr')
  and e.snapshot_recorded_at=s.captured_at and e.body_sha256=p_job.body_sha256
  and p_job.message_body=collect_receipt_policy.render_snapshot(s,2,p_job.reference,e.language)
  and p_job.body_sha256=encode(extensions.digest(p_job.message_body,'sha256'),'hex')),false)
$$;

-- Account claiming changes association, never the member key. The
-- non-key lock still excludes competing edits/deletes/claims but permits
-- financial INSERT foreign-key checks while claim waits on a payment.
create or replace function collect_hybrid.claim_verified_current_account()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  verified_phone text;
  phone_hash text;
  identity collect_hybrid.member_momo_identities;
  member collect_hybrid.member_records;
  existing collect_hybrid.member_account_claims;
  updated_payments integer := 0;
  suppressed_jobs integer := 0;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce((
    select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_verified_account_claim'
  ), false) then
    raise exception 'Verified offline-member account claiming is disabled';
  end if;
  verified_phone := collect_admin_access.verified_phone(actor);
  if verified_phone is null
     or verified_phone !~ '^\+2507[2389][0-9]{7}$' then
    return jsonb_build_object('ok', true, 'status', 'no_match');
  end if;
  phone_hash := encode(extensions.digest(verified_phone, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    'hybrid-account-claim:' || phone_hash, 0
  ));
  select item.* into identity
  from collect_hybrid.member_momo_identities item
  where item.momo_number = verified_phone
  for update;
  if identity.member_id is null then
    return jsonb_build_object('ok', true, 'status', 'no_match');
  end if;
  select item.* into member
  from collect_hybrid.member_records item
  where item.id = identity.member_id
  for no key update;
  if member.id is null or member.lifecycle <> 'active' then
    raise exception 'Matching member record requires review';
  end if;
  if member.linked_user_id = actor then
    return jsonb_build_object(
      'ok', true, 'status', 'already_linked', 'collect_id', member.collect_id
    );
  end if;
  if member.linked_user_id is not null then
    raise exception 'Matching member record is linked to another account';
  end if;
  select claim.* into existing
  from collect_hybrid.member_account_claims claim
  where claim.member_record_id = member.id
  for update;
  if existing.user_id = actor
     and existing.identity_revision = identity.revision
     and existing.verified_phone_sha256 = phone_hash then
    return jsonb_build_object(
      'ok', true, 'status', 'already_claimed',
      'member_record_id', member.id, 'collect_id', member.collect_id
    );
  end if;
  if existing.user_id is not null then
    raise exception 'Matching member record is claimed by another account';
  end if;
  if exists (
    select 1 from collect_hybrid.member_account_claims claim
    where claim.user_id = actor and claim.member_record_id <> member.id
  ) then
    raise exception 'Account already claims another member record';
  end if;
  insert into collect_hybrid.member_account_claims(
    member_record_id, user_id, verified_phone_sha256, identity_revision
  ) values (
    member.id, actor, phone_hash, identity.revision
  )
  on conflict (member_record_id) do update
  set user_id = excluded.user_id,
      verified_phone_sha256 = excluded.verified_phone_sha256,
      identity_revision = excluded.identity_revision,
      claim_revision = collect_hybrid.member_account_claims.claim_revision + 1,
      last_claimed_at = clock_timestamp();

  -- Linking identity is not a financial posting. Existing immutable payment,
  -- journal and balance rows stay in place; only their nullable account pointer
  -- is attached so app notifications and own-history privacy work normally.
  update public.payments payment
  set contributor_user_id = actor
  where payment.member_record_id = member.id
    and payment.contributor_user_id is null;
  get diagnostics updated_payments = row_count;

  update collect_hybrid.sms_notification_outbox job
  set state = 'suppressed',
      suppression_reason = 'Member authenticated the app with the exact verified MoMo number',
      claim_token = null,
      claimed_by = null,
      claim_expires_at = null
  where job.member_record_id = member.id
    and job.state in ('queued', 'awaiting_confirmation');
  get diagnostics suppressed_jobs = row_count;

  perform public.create_audit_log(
    'member.offline_account.claimed', 'member_record', member.id,
    jsonb_build_object(
      'collect_id', member.collect_id,
      'identity_revision', identity.revision,
      'verified_phone_sha256', phone_hash,
      'payments_attached', updated_payments,
      'sms_jobs_suppressed', suppressed_jobs
    ),
    actor
  );
  return jsonb_build_object(
    'ok', true, 'status', 'claimed',
    'member_record_id', member.id, 'collect_id', member.collect_id,
    'payments_attached', updated_payments,
    'sms_jobs_suppressed', suppressed_jobs
  );
end;
$$;

create or replace function collect_hybrid.enqueue_sms_receipt_from_snapshot()returns trigger
language plpgsql security definer set search_path=''as $$
declare payment public.payments;identity collect_hybrid.member_momo_identities;
 policy collect_hybrid.sms_receipt_policies;consent collect_hybrid.sms_receipt_member_consents;
 message text;reference_value text;job_id uuid;begin
 -- No caller-supplied contact, amount, balance, text or language is accepted.
 -- Pausing dispatch preserves newly eligible work; historical catch-up is closed.
 if not collect_receipt_policy.snapshot_is_eligible(new)then return new;end if;
 -- Account claiming locks contact/member before payments. Never wait on an
 -- inverse-order recipient lock while financial posting owns the payment.
 -- Busy selection defers to the durable payment event/snapshot backlog; it
 -- does not mark the event handled or abort the financial transaction.
 begin
 perform 1 from public.payments where id=new.payment_id for update nowait;
 perform 1 from public.collections where id=new.collection_id for share nowait;
 perform 1 from collect_hybrid.member_records where id=new.member_record_id for share nowait;
 perform 1 from public.collection_members where collection_id=new.collection_id and member_record_id=new.member_record_id for share nowait;
 if not collect_receipt_policy.snapshot_is_eligible(new)then return new;end if;
 select * into policy from collect_hybrid.sms_receipt_policies where collection_id=new.collection_id
  and enabled and template_key='buri_munsi.payment_received'and template_version=1 for share nowait;
 if policy.collection_id is null then return new;end if;
 select * into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=new.member_record_id and enabled for share nowait;
 if consent.member_record_id is null then return new;end if;
 select * into identity from collect_hybrid.member_momo_identities where member_id=new.member_record_id for share nowait;
 if identity.member_id is null then return new;end if;
 exception when lock_not_available then return new;
 end;
 select * into payment from public.payments where id=new.payment_id;
 reference_value:=btrim(coalesce(payment.transaction_id,''));
 if reference_value~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then
  message:=collect_receipt_policy.render_v2(payment.amount_rwf,new.member_balance_after_rwf,new.captured_at,reference_value,policy.receipt_language);
 end if;
 insert into collect_hybrid.sms_notification_outbox(payment_id,snapshot_id,collection_id,member_record_id,
  destination_e164,destination_sha256,destination_revision,policy_revision,consent_revision,
  template_key,template_version,amount_rwf,member_balance_rwf,group_balance_rwf,reference,
  message_body,body_sha256,state,suppression_reason)
 values(payment.id,new.id,new.collection_id,new.member_record_id,identity.momo_number,
  encode(extensions.digest(identity.momo_number,'sha256'),'hex'),identity.revision,policy.revision,consent.revision,
  policy.template_key,2,payment.amount_rwf,new.member_balance_after_rwf,new.group_balance_after_rwf,
  coalesce(nullif(reference_value,''),'invalid'),message,
  case when message is not null then encode(extensions.digest(message,'sha256'),'hex')end,
  case when message is null then 'suppressed'else 'queued'end,
  case when message is null then 'Provider reference is not safe for the canonical receipt template'end)
 on conflict(payment_id,template_key)do nothing returning id into job_id;
 if job_id is not null and message is not null then
  insert into collect_receipt_policy.content_evidence(outbox_id,content_version,language,snapshot_recorded_at,body_sha256)
  values(job_id,2,policy.receipt_language,new.captured_at,encode(extensions.digest(message,'sha256'),'hex'));
 end if;
 return new;end$$;

create or replace function collect_receipt_operations.ensure_snapshot(p_snapshot uuid,p_catchup boolean,p_commit boolean default true)
returns jsonb language plpgsql set search_path=''as $$
declare s collect_hybrid.momo_balance_snapshots;p public.payments;o collect_hybrid.sms_notification_outbox;
 policy collect_hybrid.sms_receipt_policies;consent collect_hybrid.sms_receipt_member_consents;identity collect_hybrid.member_momo_identities;
 settings collect_receipt_operations.policy;message text;ref text;job_id uuid;code text;begin
 select * into s from collect_hybrid.momo_balance_snapshots where id=p_snapshot and event_type='receipt';
 if s.id is null then return jsonb_build_object('ok',false,'code','SNAPSHOT_MISSING','business_handled',false,'receipt_id',null);end if;
 -- Canonical payment lock fences posting/reversal; current contact, policy and
 -- consent locks fence changes until immutable enqueue and its proof commit.
 select * into p from public.payments where id=s.payment_id for update;
 select * into o from collect_hybrid.sms_notification_outbox where payment_id=p.id and template_key='buri_munsi.payment_received'for update;
 if o.id is not null then
  code:=case when o.template_version=2 and collect_receipt_policy.content_is_valid(o)then 'RECEIPT_EXISTS'else 'LEGACY_CONTENT_REVIEW_REQUIRED'end;
  return jsonb_build_object('ok',code='RECEIPT_EXISTS','code',code,'business_handled',code='RECEIPT_EXISTS','receipt_id',o.id);end if;
 if p.status='reversed'then return jsonb_build_object('ok',true,'code','PAYMENT_REVERSED','business_handled',true,'receipt_id',null);end if;
 if p.status is distinct from 'posted'then return jsonb_build_object('ok',false,'code','PAYMENT_NOT_POSTED','business_handled',false,'receipt_id',null);end if;
 perform 1 from public.collections where id=s.collection_id for share;
 perform 1 from collect_hybrid.member_records where id=s.member_record_id for share;
 perform 1 from public.collection_members where collection_id=s.collection_id and member_record_id=s.member_record_id for share;
 if not collect_receipt_policy.snapshot_is_eligible(s)then return jsonb_build_object('ok',false,'code','RECIPIENT_INELIGIBLE','business_handled',false,'receipt_id',null);end if;
 select * into policy from collect_hybrid.sms_receipt_policies where collection_id=s.collection_id for share;
 select * into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=s.member_record_id for share;
 select * into identity from collect_hybrid.member_momo_identities where member_id=s.member_record_id for share;
 select * into settings from collect_receipt_operations.policy where singleton;
 code:=case when policy.collection_id is null or not policy.enabled then 'POLICY_DISABLED'
  when consent.member_record_id is null or not consent.enabled then 'CONSENT_MISSING'
  when identity.member_id is null then 'CONTACT_MISSING'
  when p_catchup and not settings.catchup_enabled then 'CATCHUP_DISABLED'
  when s.captured_at<clock_timestamp()-make_interval(hours=>settings.catchup_hours)then 'CATCHUP_WINDOW_EXCEEDED'
  when p_catchup and(identity.revision<>1 or identity.created_at>s.captured_at)then 'CONTACT_HISTORY_UNPROVEN'
  when p_catchup and policy.updated_at>s.captured_at then 'POLICY_HISTORY_UNPROVEN'
  when p_catchup and consent.recorded_at>s.captured_at then 'CONSENT_HISTORY_UNPROVEN'else null end;
 if code is not null then return jsonb_build_object('ok',false,'code',code,'business_handled',false,'receipt_id',null);end if;
 ref:=btrim(coalesce(p.transaction_id,''));
 if ref!~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then return jsonb_build_object('ok',false,'code','CONTENT_REFUSED','business_handled',false,'receipt_id',null);end if;
 message:=collect_receipt_policy.render_v2(p.amount_rwf,s.member_balance_after_rwf,s.captured_at,ref,policy.receipt_language);
 if not p_commit then return jsonb_build_object('ok',false,'code','DRY_RUN_ELIGIBLE','business_handled',false,'receipt_id',null);end if;
 insert into collect_hybrid.sms_notification_outbox(payment_id,snapshot_id,collection_id,member_record_id,destination_e164,destination_sha256,destination_revision,policy_revision,consent_revision,
 template_key,template_version,amount_rwf,member_balance_rwf,group_balance_rwf,reference,message_body,body_sha256,state)
 values(p.id,s.id,s.collection_id,s.member_record_id,identity.momo_number,encode(extensions.digest(identity.momo_number,'sha256'),'hex'),identity.revision,policy.revision,consent.revision,
 'buri_munsi.payment_received',2,p.amount_rwf,s.member_balance_after_rwf,s.group_balance_after_rwf,ref,message,encode(extensions.digest(message,'sha256'),'hex'),'queued')
 on conflict(payment_id,template_key)do nothing returning id into job_id;
 if job_id is null then select id into job_id from collect_hybrid.sms_notification_outbox where payment_id=p.id and template_key='buri_munsi.payment_received';end if;
 insert into collect_receipt_policy.content_evidence values(job_id,2,policy.receipt_language,s.captured_at,encode(extensions.digest(message,'sha256'),'hex'))on conflict(outbox_id)do nothing;
 return jsonb_build_object('ok',true,'code','RECEIPT_ENQUEUED','business_handled',true,'receipt_id',job_id);end$$;

create or replace function collect_hybrid.sms_receipt_job_is_current(p_job_id uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select coalesce((select true from collect_hybrid.sms_notification_outbox job
 join collect_hybrid.member_momo_identities identity on identity.member_id=job.member_record_id
 join collect_hybrid.sms_receipt_policies policy on policy.collection_id=job.collection_id
 join collect_hybrid.sms_receipt_member_consents consent on consent.member_record_id=job.member_record_id
 where job.id=p_job_id and collect_receipt_policy.content_is_current(job)
  and coalesce((select enabled from public.feature_flags where key='hybrid_sms_notifications'),false)
  and identity.revision=job.destination_revision and identity.momo_number=job.destination_e164
  and encode(extensions.digest(identity.momo_number,'sha256'),'hex')=job.destination_sha256
  and policy.receipt_language=collect_receipt_policy.language_for_job(job)
  and policy.enabled and policy.revision=job.policy_revision and policy.template_key=job.template_key
  and policy.template_version=1 and consent.enabled and consent.revision=job.consent_revision),false)
$$;

create or replace function public.admin_get_collect_investigation_v1(p_kind text,p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
set timezone='UTC' as $$
declare payment_access boolean; receipt_access boolean; result jsonb; checked timestamptz;
begin
 if p_kind is null or p_kind not in ('transaction','receipt') or p_id is null then
  raise exception 'investigation_target_invalid' using errcode='22023';end if;
 payment_access:=collect_security.transaction_read_authority('payments.read');
 receipt_access:=collect_security.transaction_read_authority('notifications.read');
 if (p_kind='transaction' and not payment_access) or (p_kind='receipt' and not receipt_access) then
  raise exception 'investigation_permission_required' using errcode='42501';end if;

 -- Every section shares one statement snapshot. checked_at is captured after
 -- this read; it is measurement time, never a substituted business timestamp.
 with target as (
  select sms.id sms_id,e.id event_id,p.id payment_id,
   coalesce(p.collection_id,e.collection_id,sms.collection_id) collection_id,
   p.member_record_id,o.id outbox_id,
   collect_security.rwanda_sms_scope(sms.id) supported
  from public.raw_payment_sms sms
  left join public.parsed_payment_events e on e.raw_sms_id=sms.id
  left join public.payments p on p.parsed_event_id=e.id
  left join collect_hybrid.sms_notification_outbox o on o.payment_id=p.id
   and o.template_key='buri_munsi.payment_received'
  where p_kind='transaction' and sms.id=p_id
  union all
  select sms.id,e.id,p.id,o.collection_id,o.member_record_id,o.id,
   coalesce(collect_security.rwanda_sms_scope(sms.id),false)
  from collect_hybrid.sms_notification_outbox o
  join public.payments p on p.id=o.payment_id
  left join public.parsed_payment_events e on e.id=p.parsed_event_id
  left join public.raw_payment_sms sms on sms.id=e.raw_sms_id
  where p_kind='receipt' and o.id=p_id
 ), payment_section as (
  select jsonb_build_object(
   'payment_id',t.payment_id,'raw_sms_id',t.sms_id,'event_id',t.event_id,
   'collection_id',t.collection_id,'member_record_id',t.member_record_id,
   'lifecycle',case when t.sms_id is not null then
    collect_security.transaction_lifecycle(t.sms_id,receipt_access) else null end,
   'times',jsonb_build_object('received_at_device',sms.received_at_device,
    'ingested_at',sms.ingested_at,'parsed_recorded_at',e.created_at,
    'allocation_recorded_at',a.created_at,'provider_confirmed_at',pc.confirmed_at,
    'confirmation_recorded_at',pc.recorded_at,'rejection_occurred_at',pr.occurred_at,
    'rejection_recorded_at',pr.recorded_at,
    'payment_posted_at',case when p.status in ('posted','reversed') then p.posted_at else null end),
   'journals',coalesce((select jsonb_agg(jsonb_build_object(
    'id',j.id,'entry_type',j.entry_type,'amount_rwf',j.amount_rwf::text,'posted_at',j.posted_at,
    'snapshot',case when s.id is null then null else jsonb_build_object(
     'id',s.id,'captured_at',s.captured_at,'delta_rwf',s.delta_rwf::text,
     'member_balance_rwf',s.member_balance_after_rwf::text,
     'group_balance_rwf',s.group_balance_after_rwf::text) end)
    order by j.posted_at,j.id) from collect_hybrid.momo_journal_entries j
    left join collect_hybrid.momo_balance_snapshots s on s.journal_entry_id=j.id
    where j.payment_id=t.payment_id),'[]'::jsonb),
   'current_balances',jsonb_build_object(
    'member_rwf',mb.confirmed_rwf::text,'member_updated_at',mb.updated_at,
    'group_rwf',gb.confirmed_rwf::text,'group_updated_at',gb.updated_at)) value
  from target t left join public.raw_payment_sms sms on sms.id=t.sms_id
  left join public.parsed_payment_events e on e.id=t.event_id
  left join public.payments p on p.id=t.payment_id
  left join public.payment_allocations a on a.payment_id=t.payment_id
   and a.parsed_event_id=t.event_id
  left join public.payment_provider_confirmations pc on pc.payment_id=t.payment_id
  left join collect_hybrid.payment_provider_rejections pr on pr.payment_id=t.payment_id
  left join collect_hybrid.member_balances mb on mb.collection_id=t.collection_id
   and mb.member_record_id=t.member_record_id
  left join collect_hybrid.collection_balances gb on gb.collection_id=t.collection_id
  where payment_access and t.supported
 ), receipt_section as (
  select jsonb_build_object('id',o.id,'payment_id',o.payment_id,'snapshot_id',o.snapshot_id,
   'collection_id',o.collection_id,'member_record_id',o.member_record_id,'state',o.state,
   'template_key',o.template_key,'template_version',o.template_version,
   'created_at',o.created_at,'updated_at',o.updated_at,'observed_sent_at',o.observed_sent_at,
   'masked_destination','+250•••'||right(o.destination_e164,3),
   'amount_rwf',o.amount_rwf::text,'member_balance_rwf',o.member_balance_rwf::text,
   'group_balance_rwf',o.group_balance_rwf::text,
   'snapshot_captured_at',s.captured_at,
   'preview_source',case when s.id is not null then 'immutable_posting_snapshot' else 'snapshot_unavailable' end,
   'masked_snapshot_preview',case when s.id is not null then
    collect_receipt_policy.render_snapshot(s,o.template_version,'snapshot-'||right(s.id::text,8),collect_receipt_policy.language_for_job(o)) else null end,
   'approvals',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,
    'approved_at',c.approved_at,'expires_at',c.expires_at,'consumed_at',c.consumed_at)
    order by c.approved_at desc,c.id desc) from (select *
     from collect_hybrid.sms_notification_confirmations where outbox_id=o.id
     order by approved_at desc,id desc limit 50)c),'[]'::jsonb),
   'approval_total',(select count(*) from collect_hybrid.sms_notification_confirmations where outbox_id=o.id),
   'attempts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,
    'attempt_number',a.attempt_number,'state',a.state,'send_started_at',a.send_started_at,
    'outcome_at',a.outcome_at) order by a.attempt_number desc) from
     (select * from collect_hybrid.sms_notification_attempts where outbox_id=o.id
      order by attempt_number desc limit 50)a),'[]'::jsonb),
   'attempt_total',(select count(*) from collect_hybrid.sms_notification_attempts where outbox_id=o.id)) value
  from target t join collect_hybrid.sms_notification_outbox o on o.id=t.outbox_id
  -- Reconstruction is allowed only from the matching immutable receipt snapshot.
  left join collect_hybrid.momo_balance_snapshots s on s.id=o.snapshot_id
   and s.payment_id=o.payment_id and s.collection_id=o.collection_id
   and s.member_record_id=o.member_record_id and s.event_type='receipt'
   and s.delta_rwf=o.amount_rwf and s.member_balance_after_rwf=o.member_balance_rwf
   and s.group_balance_after_rwf=o.group_balance_rwf
   and exists(select 1 from collect_hybrid.momo_journal_entries j
    where j.id=s.journal_entry_id and j.payment_id=o.payment_id
     and j.collection_id=o.collection_id and j.member_record_id=o.member_record_id
     and j.entry_type='receipt' and j.amount_rwf=o.amount_rwf)
  where receipt_access and t.supported
 ) select jsonb_build_object(
  'contract_version',1,'scope',case when exists(select 1 from target where supported)
   then 'rwanda_momo' else 'unclassified' end,'kind',p_kind,'target_id',p_id,'history_limit',50,
  'payment_state',case when not payment_access then 'denied'
   when not exists(select 1 from target) then 'missing'
   when not exists(select 1 from target where supported) then 'unsupported' else 'available' end,
  'payment',(select value from payment_section limit 1),
  'receipt_state',case when not receipt_access then 'denied'
   when exists(select 1 from target) and not exists(select 1 from target where supported) then 'unsupported'
   when exists(select 1 from receipt_section) then 'available' else 'missing' end,
  'receipt',(select value from receipt_section limit 1)) into result;
 checked:=clock_timestamp();
 return result||jsonb_build_object('checked_at',checked,'sample_valid_until',checked+interval '60 seconds');
end $$;

-- The approved renderer adds only É and é, both one default GSM septet.
-- Keep the narrow alphabet, byte bound and native divideMessage equality.
create or replace function collect_gateway_dispatch.segment_count(p_body text)returns integer language plpgsql immutable set search_path=''as $$declare n integer;begin
 if p_body is null or p_body!~'^[A-Za-z0-9 Éé.,/:_-]+$'or octet_length(p_body)>1000 then raise exception 'gateway_dispatch_encoding_unsupported'using errcode='55000';end if;
 n:=char_length(p_body);return case when n<=160 then 1 else ceil(n::numeric/153)::integer end;end$$;

commit;
