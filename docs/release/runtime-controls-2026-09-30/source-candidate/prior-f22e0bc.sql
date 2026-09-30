begin;
select pg_advisory_xact_lock(193517,141);
select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));

-- Existing content rows, strings, identifiers, public getters and policy copy
-- are preserved. Governance state is private; no secret/value export or seeded
-- production credentials occur. Owner-only migration/provisioning is separate
-- from authenticated operator updates.
create table collect_security.runtime_control_heads (
 family text not null, identity jsonb not null check(jsonb_typeof(identity)='object' and octet_length(identity::text)<=2048),
 revision bigint not null check(revision between 1 and 1000000000),
 content_sha256 text not null check(content_sha256 ~ '^[a-f0-9]{64}$'),
 updated_at timestamptz not null default clock_timestamp() check(isfinite(updated_at)),
 primary key(family,identity)
);
create table collect_security.runtime_control_events (
 id uuid primary key default gen_random_uuid(), family text not null, identity_sha256 text not null check(identity_sha256 ~ '^[a-f0-9]{64}$'),
 previous_revision bigint not null check(previous_revision>=0), revision bigint not null check(revision=previous_revision+1),
 operation text not null check(operation in ('insert','update','delete')),
 old_sha256 text check(old_sha256 ~ '^[a-f0-9]{64}$'), new_sha256 text check(new_sha256 ~ '^[a-f0-9]{64}$'),
 changed_fields text[] not null, actor_id uuid, session_id uuid,
 authority text not null check(authority in ('live_operator','database_owner')),
 reason_sha256 text not null check(reason_sha256 ~ '^[a-f0-9]{64}$'), redacted boolean not null default false,
 reason_characters integer not null check(reason_characters between 8 and 500),
 recorded_at timestamptz not null default clock_timestamp() check(isfinite(recorded_at)),
 unique(family,identity_sha256,revision)
);
alter table collect_security.runtime_control_heads enable row level security;
alter table collect_security.runtime_control_events enable row level security;
revoke all on collect_security.runtime_control_heads,collect_security.runtime_control_events from public,anon,authenticated,service_role;

create function collect_security.runtime_control_spec(p_family text) returns jsonb
language sql immutable security definer set search_path='' as $spec$
 select '{"account_request_reason_options":{"create_allowed":true,"identity":["request_type","locale","key"],"immutable_after_create":[],"nullable":["description","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.account_request_reason_options","types":{"created_at":"timestamp with time zone","description":"text","display_order":"integer","enabled":"boolean","key":"text","label":"text","locale":"text","metadata":"jsonb","request_type":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","description","display_order","enabled","metadata"]},"admin_navigation_items":{"create_allowed":false,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_navigation_items","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","icon_key":"text","key":"text","label":"text","metadata":"jsonb","required_permission":"text","route_path":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","icon_key","display_order","enabled","metadata"]},"admin_queue_filter_options":{"create_allowed":true,"identity":["id"],"immutable_after_create":["rpc_name","filter_kind","value"],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_filter_options","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","filter_kind":"text","id":"uuid","label":"text","rpc_name":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","value":"text"},"writable":["rpc_name","filter_kind","value","label","display_order","enabled"]},"admin_queue_signals":{"create_allowed":true,"identity":["id"],"immutable_after_create":["rpc_name","signal_kind"],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_signals","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","icon_key":"text","id":"uuid","label":"text","rpc_name":"text","signal_kind":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["rpc_name","signal_kind","icon_key","label","display_order","enabled"]},"admin_queue_sla_policies":{"create_allowed":true,"identity":["queue_key"],"immutable_after_create":[],"nullable":["updated_by"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_sla_policies","types":{"escalation":"text","owner":"text","queue_key":"text","target":"text","updated_at":"timestamp with time zone","updated_by":"uuid"},"writable":["target","owner","escalation"]},"admin_queue_specs":{"create_allowed":false,"identity":["rpc_name"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.admin_queue_specs","types":{"created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","metadata":"jsonb","required_permission":"text","rpc_name":"text","subtitle":"text","title":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["title","subtitle","display_order","enabled","metadata"]},"brand_entities":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["admin_url","app_download_url","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.brand_entities","types":{"admin_url":"text","app_download_url":"text","created_at":"timestamp with time zone","display_name":"text","is_active":"boolean","key":"text","legal_name":"text","metadata":"jsonb","public_url":"text","regulatory_footer_note":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["display_name","legal_name","public_url","admin_url","app_download_url","regulatory_footer_note","metadata","is_active"]},"collection_category_subtypes":{"create_allowed":true,"identity":["collection_type_key","key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_category_subtypes","types":{"collection_type_key":"text","created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","display_order","enabled","metadata"]},"collection_purpose_templates":{"create_allowed":true,"identity":["collection_type_key","key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_purpose_templates","types":{"collection_type_key":"text","created_at":"timestamp with time zone","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","display_order","enabled","metadata"]},"collection_type_catalog":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_type_catalog","types":{"created_at":"timestamp with time zone","default_category_subtype":"text","default_purpose_template_key":"text","display_order":"integer","enabled":"boolean","icon_key":"text","key":"text","label":"text","metadata":"jsonb","short_purpose":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","short_purpose","icon_key","default_category_subtype","default_purpose_template_key","display_order","enabled","metadata"]},"collection_type_country_rules":{"create_allowed":true,"identity":["collection_type_key","country_code"],"immutable_after_create":[],"nullable":["min_suggested_amount_rwf","max_suggested_amount_rwf","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.collection_type_country_rules","types":{"collection_type_key":"text","country_code":"text","created_at":"timestamp with time zone","enabled":"boolean","max_suggested_amount_rwf":"bigint","metadata":"jsonb","min_suggested_amount_rwf":"bigint","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["enabled","min_suggested_amount_rwf","max_suggested_amount_rwf","metadata"]},"feature_flags":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"feature_flags.manage","read_permission":"feature_flags.read","relation":"public.feature_flags","types":{"created_at":"timestamp with time zone","description":"text","enabled":"boolean","key":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["enabled","description","metadata"]},"notification_channels":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_channels","types":{"created_at":"timestamp with time zone","description":"text","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","platform":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["label","description","platform","enabled","display_order","metadata"]},"notification_event_types":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_event_types","types":{"created_at":"timestamp with time zone","default_channel_key":"text","description":"text","display_order":"integer","enabled":"boolean","key":"text","label":"text","metadata":"jsonb","preference_key":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["preference_key","label","description","default_channel_key","enabled","display_order","metadata"]},"notification_preferences":{"create_allowed":true,"identity":["user_id"],"immutable_after_create":[],"nullable":[],"relation":"public.notification_preferences","types":{"contribution_confirmations":"boolean","created_at":"timestamp with time zone","group_updates":"boolean","payment_reminders":"boolean","security_notices":"boolean","updated_at":"timestamp with time zone","user_id":"uuid"},"user_owned":true,"writable":["contribution_confirmations","payment_reminders","group_updates","security_notices"]},"notification_template_versions":{"create_allowed":true,"identity":["id"],"immutable_after_create":["template_key","version"],"nullable":["published_at","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_template_versions","types":{"body_template":"text","created_at":"timestamp with time zone","effective_at":"timestamp with time zone","id":"uuid","metadata":"jsonb","published_at":"timestamp with time zone","status":"text","template_key":"text","title_template":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","version":"text"},"writable":["template_key","version","title_template","body_template","status","effective_at","metadata"]},"notification_templates":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.notification_templates","types":{"created_at":"timestamp with time zone","enabled":"boolean","event_type_key":"text","key":"text","locale":"text","metadata":"jsonb","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["event_type_key","locale","enabled","metadata"]},"otp_policy":{"additional_permission":"notifications.manage","create_allowed":false,"identity":["singleton"],"immutable_after_create":[],"nullable":[],"permission":"settings.manage","read_permission":"settings.read","relation":"collect_security.otp_policy","types":{"enabled":"boolean","global_daily_limit":"integer","global_hourly_limit":"integer","singleton":"boolean"},"writable":["global_hourly_limit","global_daily_limit","enabled"]},"payment_entrypoints":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["display_code","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.payment_entrypoints","types":{"code":"text","country_code":"text","created_at":"timestamp with time zone","currency":"text","display_code":"text","instructions":"text","is_active":"boolean","key":"text","label":"text","metadata":"jsonb","network":"text","sort_order":"integer","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["country_code","currency","network","label","code","display_code","instructions","sort_order","metadata","is_active"]},"policy_document_sections":{"create_allowed":true,"identity":["id"],"immutable_after_create":["policy_document_id","section_key"],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.policy_document_sections","types":{"body":"text","created_at":"timestamp with time zone","display_order":"integer","id":"uuid","metadata":"jsonb","policy_document_id":"uuid","section_key":"text","title":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text"},"writable":["policy_document_id","section_key","title","body","display_order","metadata"]},"policy_documents":{"create_allowed":true,"identity":["id"],"immutable_after_create":[],"nullable":["summary","published_at","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.policy_documents","types":{"created_at":"timestamp with time zone","effective_at":"timestamp with time zone","id":"uuid","kind":"text","locale":"text","metadata":"jsonb","published_at":"timestamp with time zone","status":"text","summary":"text","title":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","version":"text"},"writable":["kind","locale","version","title","summary","status","effective_at","metadata"]},"roster_resource_policy":{"additional_permission":"collections.moderate","create_allowed":false,"identity":["id"],"immutable_after_create":[],"nullable":[],"permission":"settings.manage","read_permission":"settings.read","relation":"collect_hybrid.roster_resource_policy","types":{"actor_active":"integer","actor_daily_bytes":"bigint","actor_daily_cost_units":"bigint","actor_daily_requests":"integer","ai_attempt_cost_units":"bigint","global_active":"integer","global_daily_bytes":"bigint","global_daily_cost_units":"bigint","global_daily_requests":"integer","id":"boolean","version":"integer"},"writable":["actor_daily_requests","actor_daily_bytes","actor_active","global_daily_requests","global_daily_bytes","global_active","actor_daily_cost_units","global_daily_cost_units","ai_attempt_cost_units"]},"sms_receipt_member_consents":{"additional_permission":"users.read","create_allowed":true,"identity":["member_record_id"],"immutable_after_create":[],"nullable":[],"permission":"notifications.manage","read_permission":"notifications.read","relation":"collect_hybrid.sms_receipt_member_consents","types":{"capture_method":"text","enabled":"boolean","member_record_id":"uuid","reason":"text","recorded_at":"timestamp with time zone","recorded_by":"uuid","revision":"integer"},"writable":["enabled","capture_method"]},"sms_receipt_policies":{"additional_permission":"collections.moderate","create_allowed":true,"identity":["collection_id"],"immutable_after_create":[],"nullable":[],"permission":"notifications.manage","read_permission":"notifications.read","relation":"collect_hybrid.sms_receipt_policies","types":{"collection_id":"uuid","enabled":"boolean","reason":"text","revision":"integer","template_key":"text","template_version":"integer","updated_at":"timestamp with time zone","updated_by":"uuid"},"writable":["enabled"]},"support_channels":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["display_value","updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.support_channels","types":{"channel_type":"text","created_at":"timestamp with time zone","display_value":"text","is_active":"boolean","key":"text","label":"text","metadata":"jsonb","sort_order":"integer","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","value":"text"},"writable":["channel_type","label","value","display_value","sort_order","metadata","is_active"]},"system_settings":{"create_allowed":true,"identity":["key"],"immutable_after_create":[],"nullable":["updated_by","updated_reason"],"permission":"settings.manage","read_permission":"settings.read","relation":"public.system_settings","types":{"created_at":"timestamp with time zone","description":"text","is_sensitive":"boolean","key":"text","updated_at":"timestamp with time zone","updated_by":"uuid","updated_reason":"text","value":"jsonb"},"writable":["value","description"]}}'::jsonb -> p_family;
$spec$;

create function collect_security.runtime_control_hash(p_row jsonb) returns text
language sql immutable security definer set search_path='' as $$
 select encode(extensions.digest(convert_to((p_row-array['updated_at','updated_by','updated_reason','recorded_at','recorded_by','reason'])::text,'UTF8'),'sha256'),'hex');
$$;
create function collect_security.runtime_control_identity(p_family text,p_row jsonb) returns jsonb
language sql immutable security definer set search_path='' as $$
 select jsonb_object_agg(k,p_row->k) from jsonb_array_elements_text(collect_security.runtime_control_spec(p_family)->'identity') k;
$$;
create function collect_security.runtime_control_bound_json(p_value jsonb,p_depth integer default 0) returns void
language plpgsql immutable security definer set search_path='' as $$
declare item record; text_value text;
begin
 if p_value is null or p_depth>5 or octet_length(p_value::text)>65536 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
 if jsonb_typeof(p_value)='object' then
  if (select count(*) from jsonb_object_keys(p_value))>50 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
  for item in select * from jsonb_each(p_value) loop
   if char_length(item.key) not between 1 and 80 or item.key !~ '^[A-Za-z_][A-Za-z0-9_.:-]*$'
      or item.key ~* '(secret|password|credential|api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|private[_-]?key)' then
    raise exception 'runtime_control_sensitive_field' using errcode='22023';end if;
   perform collect_security.runtime_control_bound_json(item.value,p_depth+1);
  end loop;
 elsif jsonb_typeof(p_value)='array' then
  if jsonb_array_length(p_value)>50 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
  for item in select value from jsonb_array_elements(p_value) loop perform collect_security.runtime_control_bound_json(item.value,p_depth+1);end loop;
 elsif jsonb_typeof(p_value)='string' then
  text_value:=p_value#>>'{}';
  if char_length(text_value)>32768 or regexp_replace(text_value,E'[\n\r\t]','','g') ~ '[[:cntrl:]]' then raise exception 'runtime_control_invalid' using errcode='22023';end if;
 elsif jsonb_typeof(p_value)='number' then
  if (p_value#>>'{}')::numeric not between -100000000000 and 100000000000 then raise exception 'runtime_control_invalid' using errcode='22023';end if;
 end if;
end $$;
create function collect_security.runtime_control_https(p_value text) returns boolean
language sql immutable security definer set search_path='' as $$
 select p_value is not null and char_length(p_value) between 10 and 2048
  and p_value ~ '^https://[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,63}(:443)?([/?][^[:space:]@]*)?$'
  and p_value !~ '[[:cntrl:]]' and p_value !~ '^https://[0-9.]+';
$$;
-- A common typed validator is called before any cast/parent lock and again by
-- the database trigger. SQL NULL and JSON null have distinct, explicit rules.
create function collect_security.runtime_control_check_values(p_family text,p_values jsonb) returns void
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
create function collect_security.runtime_control_check_identity(p_family text,p_identity jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family); field record; typ text; clean text;
begin
 if spec is null or p_identity is null or jsonb_typeof(p_identity)<>'object' or octet_length(p_identity::text)>2048 then raise exception 'runtime_control_identity_invalid' using errcode='22023';end if;
 if (select array_agg(key order by key) from jsonb_object_keys(p_identity) key) is distinct from (select array_agg(key order by key) from jsonb_array_elements_text(spec->'identity') key) then raise exception 'runtime_control_identity_invalid' using errcode='22023';end if;
 if coalesce((spec->>'user_owned')::boolean,false) and p_identity->>'user_id' is distinct from auth.uid()::text then raise exception 'runtime_control_owner_required' using errcode='42501';end if;
 for field in select * from jsonb_each(p_identity) loop
  typ:=spec->'types'->>field.key;clean:=field.value#>>'{}';
  if field.value='null'::jsonb
   or typ='uuid' and (jsonb_typeof(field.value)<>'string' or clean !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
   or typ='boolean' and field.value is distinct from 'true'::jsonb
   or typ='text' and (jsonb_typeof(field.value)<>'string' or char_length(clean) not between 1 and 128 or clean !~ '^[A-Za-z0-9_.:-]+$') then raise exception 'runtime_control_identity_invalid' using errcode='22023';end if;
 end loop;
end $$;
create function collect_security.runtime_control_lock_parent(p_family text,p_new jsonb,p_old jsonb,p_delete boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare parent_id uuid; template_key_text text; parent public.policy_documents;
begin
 if p_family='policy_documents' then
  perform 1 from public.policy_documents where id=(p_new->>'id')::uuid for update;
 elsif p_family='policy_document_sections' then
  if p_old is not null and p_old->>'policy_document_id' is distinct from p_new->>'policy_document_id' then raise exception 'runtime_control_wiring_immutable' using errcode='55000';end if;
  parent_id:=(p_new->>'policy_document_id')::uuid;
  -- Physical parent fencing also prevents stale repeatable-read publication
  -- after a committed section edit. Governance no-op keeps its version intact.
  update public.policy_documents set status=status where id=parent_id returning * into parent;
  if parent.id is null and p_delete and pg_trigger_depth()>1 then return;end if;
  if parent.id is null or parent.status<>'draft' or parent.published_at is not null then raise exception 'runtime_control_published_immutable' using errcode='55000';end if;
 elsif p_family='notification_template_versions' then
  template_key_text:=p_new->>'template_key';
  update public.notification_templates set enabled=enabled where key=template_key_text;
  if not found and p_delete and pg_trigger_depth()>1 then return;end if;
  if not found then raise exception 'runtime_control_template_required' using errcode='22023';end if;
 end if;
end $$;

create function collect_security.runtime_control_validate(p_family text,p_new jsonb,p_old jsonb default null) returns void
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family); field record; typ text; value_type text; clean text; limit_chars integer;
 parent public.policy_documents; amount_text text;
begin
 if spec is null or p_new is null or jsonb_typeof(p_new)<>'object' then raise exception 'runtime_control_invalid' using errcode='22023';end if;
 perform collect_security.runtime_control_check_values(p_family,case when p_old is null then p_new else
  coalesce((select jsonb_object_agg(key,value) from jsonb_each(p_new) where p_old->key is distinct from value),'{}'::jsonb) end);
 if p_old is not null and exists(select 1 from jsonb_array_elements_text(spec->'immutable_after_create') k where p_new->k is distinct from p_old->k) then
  raise exception 'runtime_control_wiring_immutable' using errcode='55000';end if;
 if p_family='support_channels' then
  if p_new->>'channel_type' in ('phone','whatsapp') and (char_length(p_new->>'value') not between 8 and 16 or p_new->>'value' !~ '^\+?[1-9][0-9]+$')
   or p_new->>'channel_type'='email' and (char_length(p_new->>'value')>254 or p_new->>'value' !~ '^[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$')
   or p_new->>'channel_type'='url' and not collect_security.runtime_control_https(p_new->>'value') then raise exception 'runtime_control_invalid_support' using errcode='22023';end if;
 end if;
 if p_family='payment_entrypoints' and (p_new->>'is_active')::boolean then
  if p_new->>'country_code' is distinct from 'RW' or p_new->>'currency' is distinct from 'RWF' or p_new->>'network' is distinct from 'mtn_momo'
    or p_new->>'code' is null or p_new->>'code' !~ '^\*182\*8\*1\*41258\*[1-9][0-9]{0,8}#$' then raise exception 'runtime_control_rwanda_route_required' using errcode='22023';end if;
  amount_text:=split_part(p_new->>'code','*',6);amount_text:=replace(amount_text,'#','');
  if p_new->'metadata'->>'amount_rwf' is distinct from amount_text then raise exception 'runtime_control_payment_amount_mismatch' using errcode='22023';end if;
 end if;
 if p_family='collection_type_country_rules' and (p_new->>'enabled')::boolean and p_new->>'country_code' is distinct from 'RW' then raise exception 'runtime_control_rwanda_route_required' using errcode='22023';end if;
 if p_family='feature_flags' and (p_new->>'enabled')::boolean and p_new->>'key' ~* '(bank_transfer|stripe|diaspora|international|foreign)' then raise exception 'runtime_control_rwanda_route_required' using errcode='22023';end if;
 if p_family='system_settings' then
  if p_new->>'key' ~* '(secret|password|credential|api[_-]?key|token|private[_-]?key)' then raise exception 'runtime_control_sensitive_field' using errcode='22023';end if;
  if p_new->>'key'='payments.mode' and p_new->'value' is distinct from '{"rwanda":{"provider":"momo_ussd_sms","currency":"RWF"}}'::jsonb then raise exception 'runtime_control_rwanda_route_required' using errcode='22023';end if;
  if p_new->>'key'='sms.parser.schema_version' and p_new->'value' is distinct from '"collect.sms_parser.v1"'::jsonb then raise exception 'runtime_control_unsupported_parser' using errcode='22023';end if;
 end if;
 if p_old is not null and p_family in ('policy_documents','notification_template_versions') and (p_old->>'status'<>'draft' or p_old->>'published_at' is not null) then
  if (p_new-array['status','updated_at','updated_by','updated_reason']) is distinct from (p_old-array['status','updated_at','updated_by','updated_reason'])
    or p_new->>'status' not in ('published','archived') or (p_old->>'status'='archived' and p_new->>'status'<>'archived') then raise exception 'runtime_control_published_immutable' using errcode='55000';end if;
 end if;
 if p_family='policy_document_sections' then
  select * into parent from public.policy_documents where id=(p_new->>'policy_document_id')::uuid;
  if parent.id is null or parent.status<>'draft' or parent.published_at is not null then raise exception 'runtime_control_published_immutable' using errcode='55000';end if;
 end if;
 if p_family='notification_templates' and p_old is not null and exists(select 1 from public.notification_template_versions where template_key=p_old->>'key' and (status<>'draft' or published_at is not null))
  and (p_new-array['enabled','updated_at','updated_by','updated_reason']) is distinct from (p_old-array['enabled','updated_at','updated_by','updated_reason']) then
  raise exception 'runtime_control_published_immutable' using errcode='55000';end if;
 if p_family='policy_documents' and p_new->>'status'='published' and (p_old is null or p_old->>'status'='draft') then
  if not exists(select 1 from public.policy_document_sections where policy_document_id=(p_new->>'id')::uuid) then raise exception 'runtime_control_policy_sections_required' using errcode='22023';end if;
 end if;
 if p_family='sms_receipt_policies' and not exists(select 1 from public.collections c where c.id=(p_new->>'collection_id')::uuid and c.collection_type='ikimina' and c.archived_at is null) then raise exception 'runtime_control_collection_required' using errcode='22023';end if;
 if p_family='sms_receipt_member_consents' and not exists(select 1 from collect_hybrid.member_records m join collect_hybrid.member_momo_identities i on i.member_id=m.id where m.id=(p_new->>'member_record_id')::uuid and m.lifecycle='active' and m.linked_user_id is null) then raise exception 'runtime_control_member_required' using errcode='22023';end if;
 if p_family='roster_resource_policy' and ((p_new->>'actor_active')::integer>(p_new->>'global_active')::integer
   or (p_new->>'actor_daily_requests')::integer>(p_new->>'global_daily_requests')::integer
   or (p_new->>'actor_daily_bytes')::bigint>(p_new->>'global_daily_bytes')::bigint
   or (p_new->>'actor_daily_cost_units')::bigint>(p_new->>'global_daily_cost_units')::bigint
   or (p_new->>'ai_attempt_cost_units')::bigint>(p_new->>'actor_daily_cost_units')::bigint) then raise exception 'runtime_control_quota_order_invalid' using errcode='22023';end if;
 if p_family='otp_policy' and (p_new->>'global_hourly_limit')::integer>(p_new->>'global_daily_limit')::integer then raise exception 'runtime_control_quota_order_invalid' using errcode='22023';end if;
end $$;

create function collect_security.runtime_control_actor(p_family text,p_read boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family); session_id uuid;
begin
 if spec is null then raise exception 'runtime_control_family_invalid' using errcode='22023';end if;
 begin session_id:=public._lock_notification_registration_session();exception when sqlstate '42501' then raise exception 'runtime_control_session_required' using errcode='42501';end;
 if coalesce((spec->>'user_owned')::boolean,false) then return session_id;end if;
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 begin
  perform public.assert_admin_permission(case when p_read then spec->>'read_permission' else spec->>'permission' end);
  if not p_read and spec ? 'additional_permission' then perform public.assert_admin_permission(spec->>'additional_permission');end if;
 exception when sqlstate 'P0001' then raise exception 'runtime_control_permission_required' using errcode='42501';end;
 return session_id;
end $$;

create function collect_security.guard_runtime_control_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin raise exception 'runtime_control_history_immutable' using errcode='55000';end $$;
create trigger runtime_control_event_immutable before update or delete on collect_security.runtime_control_events
for each row execute function collect_security.guard_runtime_control_event();

create function collect_security.govern_runtime_control() returns trigger
language plpgsql security definer set search_path='' as $$
declare control_family text:=tg_table_name; spec jsonb:=collect_security.runtime_control_spec(control_family); prior jsonb; next_row jsonb; identity_row jsonb;
 head collect_security.runtime_control_heads; context jsonb; owner_maintenance boolean;
 actor uuid; sid uuid; audit_redacted boolean; reason_hash text; reason_length integer; changed text[]; content_hash text; target_revision bigint;
begin
 if spec is null or spec->>'relation'<>(tg_table_schema||'.'||tg_table_name) then raise exception 'runtime_control_family_invalid' using errcode='55000';end if;
 prior:=case when tg_op='INSERT' then null else to_jsonb(old) end;
 next_row:=case when tg_op='DELETE' then null else to_jsonb(new) end;
 -- Crucial: preserve the145/146 physical same-value UPDATE serialization
 -- fence. Returning NEW still writes the row; governance state remains untouched.
 if tg_op='UPDATE' and collect_security.runtime_control_hash(prior)=collect_security.runtime_control_hash(next_row) then return new;end if;
 identity_row:=collect_security.runtime_control_identity(control_family,coalesce(next_row,prior));
 if tg_op='UPDATE' and identity_row is distinct from collect_security.runtime_control_identity(control_family,prior) then raise exception 'runtime_control_identity_immutable' using errcode='55000';end if;
 if tg_op='DELETE' and (control_family in ('policy_documents','notification_template_versions') and (prior->>'status'<>'draft' or prior->>'published_at' is not null)
    or control_family='notification_templates' and exists(select 1 from public.notification_template_versions where template_key=prior->>'key' and (status<>'draft' or published_at is not null))
    or control_family='policy_document_sections' and exists(select 1 from public.policy_documents where id=(prior->>'policy_document_id')::uuid and (status<>'draft' or published_at is not null))) then raise exception 'runtime_control_published_immutable' using errcode='55000';end if;
 perform collect_security.runtime_control_lock_parent(control_family,coalesce(next_row,prior),prior,tg_op='DELETE');
 owner_maintenance:=session_user='postgres' and current_setting('role') in ('none','postgres');
 if owner_maintenance then
  actor:=null;sid:=null;reason_hash:=encode(extensions.digest(convert_to('database_owner_maintenance','UTF8'),'sha256'),'hex');reason_length:=26;
 else
  begin context:=current_setting('collect.runtime_control_context',true)::jsonb;exception when others then context:=null;end;
  if context is null or context->>'family'<>control_family or context->'identity' is distinct from identity_row
    or context->>'actor_id' is distinct from auth.uid()::text or context->>'session_id' is distinct from auth.jwt()->>'session_id' then raise exception 'runtime_control_revision_required' using errcode='42501';end if;
  actor:=auth.uid();sid:=collect_security.runtime_control_actor(control_family);
  reason_hash:=context->>'reason_sha256';reason_length:=(context->>'reason_characters')::integer;
 end if;
 select * into head from collect_security.runtime_control_heads where runtime_control_heads.family=control_family and identity=identity_row for update;
 if not owner_maintenance and coalesce(head.revision,0) is distinct from (context->>'expected_revision')::bigint then raise exception 'runtime_control_conflict' using errcode='40001';end if;
 if head.family is not null and prior is not null and head.content_sha256 is distinct from collect_security.runtime_control_hash(prior) then raise exception 'runtime_control_head_invalid' using errcode='55000';end if;
 if tg_op<>'DELETE' then
  if control_family in ('policy_documents','notification_template_versions') and next_row->>'status'='published' and (prior is null or prior->>'status'='draft') then next_row:=next_row||jsonb_build_object('published_at',clock_timestamp());end if;
  if control_family in ('sms_receipt_policies','sms_receipt_member_consents') then
   next_row:=next_row||jsonb_build_object('reason','runtime_control:'||reason_hash,'revision',coalesce((prior->>'revision')::integer,0)+1);
   if control_family='sms_receipt_policies' then next_row:=next_row||jsonb_build_object('updated_by',actor);else next_row:=next_row||jsonb_build_object('recorded_by',actor,'recorded_at',clock_timestamp());end if;
   -- Database-owner fixtures must explicitly carry the accountable profile.
   if actor is null then next_row:=next_row||jsonb_build_object(case when control_family='sms_receipt_policies' then 'updated_by' else 'recorded_by' end,coalesce(to_jsonb(new)->case when control_family='sms_receipt_policies' then 'updated_by' else 'recorded_by' end,prior->case when control_family='sms_receipt_policies' then 'updated_by' else 'recorded_by' end));end if;
  end if;
  perform collect_security.runtime_control_validate(control_family,next_row,prior);
  if next_row ? 'updated_at' then next_row:=next_row||jsonb_build_object('updated_at',clock_timestamp());end if;
  if next_row ? 'updated_by' and not (control_family='sms_receipt_policies' and actor is null) then next_row:=next_row||jsonb_build_object('updated_by',actor);end if;
  if next_row ? 'updated_reason' then next_row:=next_row||jsonb_build_object('updated_reason','runtime_control:'||reason_hash);end if;
  if control_family='roster_resource_policy' and prior is not null then next_row:=next_row||jsonb_build_object('version',(prior->>'version')::integer+1);end if;
  new:=jsonb_populate_record(new,next_row);
 end if;
 select coalesce(array_agg(key order by key),'{}') into changed from jsonb_each(coalesce(next_row,prior)) field
 where field.key not in ('created_at','updated_at','updated_by','updated_reason','recorded_by','recorded_at','reason') and (tg_op<>'UPDATE' or prior->field.key is distinct from field.value);
 target_revision:=coalesce(head.revision,0)+1;
 content_hash:=case when tg_op='DELETE' then collect_security.runtime_control_hash(jsonb_build_object('deleted',true)) else collect_security.runtime_control_hash(next_row) end;
 insert into collect_security.runtime_control_heads(family,identity,revision,content_sha256,updated_at) values(control_family,identity_row,target_revision,content_hash,clock_timestamp())
 on conflict on constraint runtime_control_heads_pkey do update set revision=excluded.revision,content_sha256=excluded.content_sha256,updated_at=excluded.updated_at;
 audit_redacted:=control_family='notification_preferences' or control_family='system_settings' and coalesce((coalesce(next_row,prior)->>'is_sensitive')::boolean,false);
 insert into collect_security.runtime_control_events(family,identity_sha256,previous_revision,revision,operation,old_sha256,new_sha256,changed_fields,actor_id,session_id,authority,reason_sha256,redacted,reason_characters)
 values(control_family,collect_security.runtime_control_hash(identity_row),target_revision-1,target_revision,lower(tg_op),case when prior is null or audit_redacted then null else collect_security.runtime_control_hash(prior) end,
 case when next_row is null or audit_redacted then null else content_hash end,changed,actor,sid,case when owner_maintenance then 'database_owner' else 'live_operator' end,reason_hash,audit_redacted,reason_length);
 if tg_op='DELETE' then return old;end if;return new;
end $$;

-- Capture immutable baseline fingerprints without changing or revalidating
-- any historical copy. Adding guards does not emit an operator-change event.
do $install$ declare entry record; trigger_row record; begin
 for entry in select key family,value spec from jsonb_each((select jsonb_object_agg(x,collect_security.runtime_control_spec(x)) from unnest(array[
 'brand_entities','support_channels','payment_entrypoints','feature_flags','system_settings','admin_navigation_items','admin_queue_specs','admin_queue_filter_options','admin_queue_signals','admin_queue_sla_policies','notification_preferences','notification_channels','notification_event_types','notification_templates','notification_template_versions','policy_documents','policy_document_sections','account_request_reason_options','collection_type_catalog','collection_category_subtypes','collection_purpose_templates','collection_type_country_rules','sms_receipt_policies','sms_receipt_member_consents','otp_policy','roster_resource_policy']) x)) loop
  execute format('insert into collect_security.runtime_control_heads(family,identity,revision,content_sha256) select %L,collect_security.runtime_control_identity(%L,to_jsonb(t)),1,collect_security.runtime_control_hash(to_jsonb(t)) from %s t',entry.family,entry.family,entry.spec->>'relation');
  -- Replace former unversioned audits; keep real-time invalidation triggers.
  for trigger_row in select tgname from pg_trigger where tgrelid=(entry.spec->>'relation')::regclass and not tgisinternal and tgname in ('audit_admin_runtime_metadata_change_trigger','audit_collection_catalog_change_trigger','audit_notification_runtime_change_trigger','audit_policy_runtime_change_trigger','audit_public_runtime_config_change_trigger') loop
   execute format('drop trigger %I on %s',trigger_row.tgname,entry.spec->>'relation');
  end loop;
  execute format('create trigger runtime_control_governance before insert or update or delete on %s for each row execute function collect_security.govern_runtime_control()',entry.spec->>'relation');
  execute format('revoke insert,update,delete,truncate on %s from public,anon,authenticated,service_role',entry.spec->>'relation');
 end loop;
end $install$;

create function public.admin_get_runtime_control_v1(p_family text,p_identity jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family); value_row jsonb; head collect_security.runtime_control_heads; sid uuid; redacted boolean:=false;
begin
 sid:=collect_security.runtime_control_actor(p_family,true);
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 execute format('select to_jsonb(t) from %s t where to_jsonb(t) @> $1',spec->>'relation') into value_row using p_identity;
 select * into head from collect_security.runtime_control_heads h where h.family=p_family and h.identity=p_identity;
 if value_row is not null and (head.family is null or head.content_sha256 is distinct from collect_security.runtime_control_hash(value_row)) then raise exception 'runtime_control_head_invalid' using errcode='55000';end if;
 if value_row is not null then
  redacted:=p_family='system_settings' and coalesce((value_row->>'is_sensitive')::boolean,false);
  value_row:=value_row-array['updated_by','updated_reason','reason','recorded_by'];
  if redacted then value_row:=value_row-'value';end if;
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'family',p_family,'identity',p_identity,'revision',coalesce(head.revision,0),'exists',value_row is not null,
  'value',value_row,'redacted',redacted,'content_sha256',case when redacted then null else head.content_sha256 end);
end $$;

create function public.admin_update_runtime_control_v1(p_family text,p_identity jsonb,p_patch jsonb,p_expected_revision bigint,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family); sid uuid; old_row jsonb; desired jsonb; head collect_security.runtime_control_heads;
 reason_text text:=btrim(coalesce(p_reason,'')); columns_sql text; values_sql text; assignments_sql text; result_row jsonb; context jsonb; prior_context text; changed boolean;
 parent_id uuid; identifier record;
begin
 sid:=collect_security.runtime_control_actor(p_family);
 if p_expected_revision is null or p_expected_revision not between 0 and 1000000000 or char_length(reason_text) not between 8 and 500
  or regexp_replace(reason_text,E'[\n\r\t]','','g') ~ '[[:cntrl:]]' then raise exception 'runtime_control_revision_reason_required' using errcode='22023';end if;
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 if p_patch is null or jsonb_typeof(p_patch)<>'object' or octet_length(p_patch::text)>65536 or p_patch='{}'::jsonb
  or exists(select 1 from jsonb_object_keys(p_patch) field where not (spec->'writable') ? field) then raise exception 'runtime_control_patch_invalid' using errcode='22023';end if;
 perform collect_security.runtime_control_check_values(p_family,p_patch);
 -- Parent publication locks precede child/head locks, preventing a late section
 -- edit from racing publication. Wiring identifiers stay immutable after create.
 execute format('select to_jsonb(t) from %s t where to_jsonb(t) @> $1',spec->>'relation') into old_row using p_identity;
 if old_row is not null and exists(select 1 from jsonb_array_elements_text(spec->'immutable_after_create') k where p_patch ? k and old_row->k is distinct from p_patch->k) then
  raise exception 'runtime_control_wiring_immutable' using errcode='55000';end if;
 if old_row is null and not (spec->>'create_allowed')::boolean then raise exception 'runtime_control_create_owner_only' using errcode='42501';end if;
 perform collect_security.runtime_control_lock_parent(p_family,coalesce(old_row,p_identity)||p_patch,old_row);
 select * into head from collect_security.runtime_control_heads h where h.family=p_family and h.identity=p_identity for update;
 if coalesce(head.revision,0) is distinct from p_expected_revision then raise exception 'runtime_control_conflict' using errcode='40001';end if;
 execute format('select to_jsonb(t) from %s t where to_jsonb(t) @> $1 for update',spec->>'relation') into old_row using p_identity;
 if old_row is not null and head.content_sha256 is distinct from collect_security.runtime_control_hash(old_row) then raise exception 'runtime_control_head_invalid' using errcode='55000';end if;
 -- Recheck effective authority after every possible row wait, under the shared
 -- Auth/roster gates also used by revocation; stale JWT fields confer no rights.
 perform collect_security.runtime_control_actor(p_family);
 if p_family='system_settings' and coalesce((old_row->>'is_sensitive')::boolean,false) then raise exception 'runtime_control_sensitive_setting_owner_only' using errcode='42501';end if;
 desired:=coalesce(old_row,p_identity)||p_patch;
 perform collect_security.runtime_control_validate(p_family,desired,old_row);
 changed:=old_row is null or collect_security.runtime_control_hash(desired) is distinct from collect_security.runtime_control_hash(old_row);
 if not changed then return jsonb_build_object('contract_version',1,'ok',true,'family',p_family,'identity',p_identity,'previous_revision',head.revision,'revision',head.revision,'changed',false,'updated_at',head.updated_at,'content_sha256',head.content_sha256);end if;
 context:=jsonb_build_object('family',p_family,'identity',p_identity,'expected_revision',p_expected_revision,'actor_id',auth.uid(),'session_id',sid,
  'reason_sha256',encode(extensions.digest(convert_to(reason_text,'UTF8'),'sha256'),'hex'),'reason_characters',char_length(reason_text));
 prior_context:=current_setting('collect.runtime_control_context',true);
 perform set_config('collect.runtime_control_context',context::text,true);
 begin
  if old_row is null then
   select string_agg(format('%I',key),',' order by key),string_agg(format('(jsonb_populate_record(null::%s,$1)).%I',spec->>'relation',key),',' order by key)
   into columns_sql,values_sql from jsonb_object_keys(p_identity||p_patch) key;
   execute format('insert into %s (%s) select %s returning to_jsonb(%s.*)',spec->>'relation',columns_sql,values_sql,split_part(spec->>'relation','.',2)) into result_row using p_identity||p_patch;
  else
   select string_agg(format('%I=(jsonb_populate_record(null::%s,$1)).%I',key,spec->>'relation',key),',' order by key) into assignments_sql from jsonb_object_keys(p_patch) key;
   execute format('update %s t set %s where to_jsonb(t) @> $2 returning to_jsonb(t)',spec->>'relation',assignments_sql) into result_row using p_patch,p_identity;
  end if;
 exception
 when unique_violation then perform set_config('collect.runtime_control_context',coalesce(prior_context,''),true);raise exception 'runtime_control_conflict' using errcode='40001';
 when not_null_violation or check_violation or foreign_key_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
  perform set_config('collect.runtime_control_context',coalesce(prior_context,''),true);raise exception 'runtime_control_invalid' using errcode='22023';
 when others then perform set_config('collect.runtime_control_context',coalesce(prior_context,''),true);raise;end;
 perform set_config('collect.runtime_control_context',coalesce(prior_context,''),true);
 select * into strict head from collect_security.runtime_control_heads h where h.family=p_family and h.identity=p_identity;
 return jsonb_build_object('contract_version',1,'ok',true,'family',p_family,'identity',p_identity,'previous_revision',p_expected_revision,'revision',head.revision,'changed',true,'updated_at',head.updated_at,'content_sha256',head.content_sha256);
end $$;

create function public.admin_set_feature_flag_v2(p_key text,p_enabled boolean,p_expected_revision bigint,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare receipt jsonb; key_text text:=btrim(coalesce(p_key,''));begin
 if p_enabled is null then raise exception 'runtime_control_patch_invalid' using errcode='22023';end if;
 receipt:=public.admin_update_runtime_control_v1('feature_flags',jsonb_build_object('key',key_text),jsonb_build_object('enabled',p_enabled),p_expected_revision,p_reason);
 return (receipt-array['family','identity','content_sha256'])||jsonb_build_object('contract_version',2,'key',key_text,'enabled',p_enabled);
end $$;
create function public.get_notification_preferences_v2() returns jsonb
language plpgsql security definer set search_path='' as $$
declare receipt jsonb; preferences jsonb;begin
 receipt:=public.admin_get_runtime_control_v1('notification_preferences',jsonb_build_object('user_id',auth.uid()));
 preferences:=case when (receipt->>'exists')::boolean then receipt->'value'-array['user_id','created_at','updated_at']
  else '{"contribution_confirmations":true,"payment_reminders":true,"group_updates":true,"security_notices":true}'::jsonb end;
 return jsonb_build_object('contract_version',2,'ok',true,'user_id',auth.uid(),'revision',receipt->'revision','exists',receipt->'exists','preferences',preferences);
end $$;
create function public.set_notification_preferences_v2(p_preferences jsonb,p_expected_revision bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare receipt jsonb;begin
 perform collect_security.runtime_control_actor('notification_preferences');
 if p_preferences is null or jsonb_typeof(p_preferences)<>'object' then raise exception 'runtime_control_patch_invalid' using errcode='22023';end if;
 if (select array_agg(key order by key) from jsonb_object_keys(p_preferences) key) is distinct from
  array['contribution_confirmations','group_updates','payment_reminders','security_notices']::text[] then raise exception 'runtime_control_patch_invalid' using errcode='22023';end if;
 receipt:=public.admin_update_runtime_control_v1('notification_preferences',jsonb_build_object('user_id',auth.uid()),p_preferences,p_expected_revision,'User notification preferences update');
 return (receipt-array['family','identity','content_sha256'])||jsonb_build_object('contract_version',2,'user_id',auth.uid());
end $$;

-- The prior contract has no optimistic version, so it cannot safely infer one
-- after waiting. Its signature stays recognizable and fails closed until callers
-- send the explicitly reviewed v2 expected-revision contract.
create or replace function public.admin_set_feature_flag(p_key text,p_enabled boolean,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin perform collect_security.runtime_control_actor('feature_flags');raise exception 'runtime_control_revision_required' using errcode='22023';end $$;
create or replace function public.admin_set_sms_receipt_policy(p_collection_id uuid,p_enabled boolean,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin perform collect_security.runtime_control_actor('sms_receipt_policies');raise exception 'runtime_control_revision_required' using errcode='22023';end $$;
create or replace function public.admin_set_member_sms_receipt_consent(p_member_record_id uuid,p_enabled boolean,p_capture_method text,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin perform collect_security.runtime_control_actor('sms_receipt_member_consents');raise exception 'runtime_control_revision_required' using errcode='22023';end $$;

create or replace function public.admin_list_feature_flags(p_search text default null,p_status text default null) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
begin
 perform collect_security.runtime_control_actor('feature_flags',true);
 if char_length(coalesce(p_search,''))>200 or p_status is not null and p_status not in ('enabled','disabled') then raise exception 'runtime_control_query_invalid' using errcode='22023';end if;
 return jsonb_build_object('rows',coalesce((select jsonb_agg(public._admin_row(gen_random_uuid(),flag.key,flag.description,case when flag.enabled then 'enabled' else 'disabled' end,'',flag.updated_at)||jsonb_build_object('extra',jsonb_build_object('runtime_revision',head.revision)) order by flag.key)
 from public.feature_flags flag join collect_security.runtime_control_heads head on head.family='feature_flags' and head.identity=jsonb_build_object('key',flag.key)
 where (p_search is null or flag.key ilike '%'||p_search||'%' or flag.description ilike '%'||p_search||'%') and (p_status is null or p_status='enabled' and flag.enabled or p_status='disabled' and not flag.enabled)),'[]'::jsonb));
end $$;

create function public.admin_list_runtime_control_events_v1(p_family text default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform public._lock_notification_registration_session();perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));perform public.assert_admin_permission('audit.read');
 if p_limit is null or p_limit not between 1 and 100 or p_family is not null and collect_security.runtime_control_spec(p_family) is null then raise exception 'runtime_control_query_invalid' using errcode='22023';end if;
 return jsonb_build_object('contract_version',1,'events',coalesce((select jsonb_agg(to_jsonb(event)-'session_id' order by event.recorded_at desc,event.id) from(select * from collect_security.runtime_control_events where p_family is null or family=p_family order by recorded_at desc,id limit p_limit) event),'[]'::jsonb));
end $$;

-- All implementation helpers default-deny every API role; existing select
-- policies/read getters retain their historical product/permission boundaries.
do $$ declare routine record;begin
 for routine in select oid::regprocedure signature from pg_proc where pronamespace='collect_security'::regnamespace and proname in ('runtime_control_spec','runtime_control_hash','runtime_control_identity','runtime_control_bound_json','runtime_control_https','runtime_control_validate','runtime_control_check_values','runtime_control_check_identity','runtime_control_lock_parent','runtime_control_actor','guard_runtime_control_event','govern_runtime_control') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',routine.signature);
 end loop;
end $$;
revoke all on function public.get_notification_preferences_v2(),public.set_notification_preferences_v2(jsonb,bigint) from public,anon,authenticated,service_role;
grant execute on function public.get_notification_preferences_v2(),public.set_notification_preferences_v2(jsonb,bigint) to authenticated;
revoke all on function public.admin_get_runtime_control_v1(text,jsonb),public.admin_update_runtime_control_v1(text,jsonb,jsonb,bigint,text),public.admin_set_feature_flag_v2(text,boolean,bigint,text),public.admin_list_runtime_control_events_v1(text,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_get_runtime_control_v1(text,jsonb),public.admin_update_runtime_control_v1(text,jsonb,jsonb,bigint,text),public.admin_set_feature_flag_v2(text,boolean,bigint,text),public.admin_list_runtime_control_events_v1(text,integer) to authenticated;
commit;
