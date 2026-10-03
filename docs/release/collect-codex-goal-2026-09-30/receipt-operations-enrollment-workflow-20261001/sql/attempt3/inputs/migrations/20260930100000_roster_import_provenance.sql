begin;

-- Same outer gate as141: installer and runtime never reverse Auth/roster order.
select pg_advisory_xact_lock(193517,141);

create table collect_hybrid.roster_import_sources (
 id uuid primary key default gen_random_uuid(), request_id uuid not null unique,
 actor_id uuid not null, session_id uuid not null,
 source_kind text not null check(source_kind in ('text','csv','txt','xlsx','pdf','image')),
 source_sha256 text not null check(source_sha256 ~ '^[a-f0-9]{64}$'),
 source_size bigint not null check(source_size between 1 and 5242880),
 client_filename text not null, declared_mime text not null, detected_type text not null,
 derived_sha256 text, derived_size bigint,
 ai_consent boolean not null, consent_version text,
 parser_version text not null default 'collect-roster-parser-v1',
 schema_version text not null default 'collect-roster-rows-v1',
 input_sha256 text not null check(input_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '24 hours',
 check(isfinite(created_at) and isfinite(expires_at) and expires_at>created_at),
 check((source_kind='xlsx' and derived_sha256 ~ '^[a-f0-9]{64}$' and derived_size between 1 and 512000)
   or (source_kind<>'xlsx' and derived_sha256 is null and derived_size is null))
);
create index roster_import_sources_actor_created_idx on collect_hybrid.roster_import_sources(actor_id,created_at);

-- One explicit provider attempt per upload request, recorded before HTTP.
-- No Auth FK: revoking/deleting an Auth session must preserve provenance.
create table collect_hybrid.roster_import_extractions (
 id uuid primary key default gen_random_uuid(),
 import_id uuid not null unique references collect_hybrid.roster_import_sources(id),
 actor_id uuid not null, session_id uuid not null,
 provider text not null check(provider='openai'), model text not null,
 prompt_version text not null check(prompt_version='roster-extraction-v1'),
 schema_version text not null default 'collect-roster-rows-v1',
 consent_version text not null check(consent_version='roster-ai-extraction-v1'),
 recorded_at timestamptz not null default clock_timestamp()
);
create table collect_hybrid.roster_import_revisions (
 id uuid primary key default gen_random_uuid(),
 import_id uuid not null references collect_hybrid.roster_import_sources(id),
 parent_revision_id uuid unique references collect_hybrid.roster_import_revisions(id),
 extraction_id uuid references collect_hybrid.roster_import_extractions(id),
 revision_number integer not null check(revision_number between 1 and 20),
 request_id uuid unique, actor_id uuid not null, session_id uuid not null,
 processing_method text not null check(processing_method in ('deterministic','openai_structured_extraction','human_review')),
 preview jsonb not null, normalized_rows jsonb not null,
 reviewed_rows_sha256 text not null check(reviewed_rows_sha256 ~ '^[a-f0-9]{64}$'),
 input_sha256 text not null check(input_sha256 ~ '^[a-f0-9]{64}$'),
 reason text, created_at timestamptz not null default clock_timestamp(),
 unique(import_id,revision_number),
 check((revision_number=1 and parent_revision_id is null and request_id is null and reason is null and processing_method<>'human_review')
   or (revision_number>1 and parent_revision_id is not null and request_id is not null and length(reason) between 8 and 500 and processing_method='human_review'))
);
create table collect_hybrid.roster_import_results (
 import_id uuid primary key references collect_hybrid.roster_import_sources(id),
 actor_id uuid not null, session_id uuid not null,
 state text not null check(state in ('preview_ready','failed')),
 revision_id uuid references collect_hybrid.roster_import_revisions(id),
 processing_metadata jsonb, error_code text,
 input_sha256 text not null check(input_sha256 ~ '^[a-f0-9]{64}$'),
 recorded_at timestamptz not null default clock_timestamp(),
 check((state='preview_ready' and revision_id is not null and processing_metadata is not null and error_code is null)
   or (state='failed' and revision_id is null and processing_metadata is null and error_code is not null))
);
create table collect_hybrid.roster_import_commits (
 request_id uuid primary key,
 import_id uuid not null unique references collect_hybrid.roster_import_sources(id),
 revision_id uuid not null references collect_hybrid.roster_import_revisions(id),
 collection_id uuid not null references public.collections(id) on delete restrict,
 actor_id uuid not null, session_id uuid not null,
 input_sha256 text not null check(input_sha256 ~ '^[a-f0-9]{64}$'),
 response jsonb not null, committed_at timestamptz not null default clock_timestamp()
);

create function collect_hybrid.guard_roster_provenance() returns trigger
language plpgsql security definer set search_path='' as $$
begin raise exception 'roster_provenance_immutable' using errcode='55000'; end $$;
do $$ declare t text; begin
 foreach t in array array['roster_import_sources','roster_import_extractions','roster_import_revisions','roster_import_results','roster_import_commits'] loop
  execute format('alter table collect_hybrid.%I enable row level security',t);
  execute format('revoke all on collect_hybrid.%I from public,anon,authenticated,service_role',t);
  execute format('create trigger roster_provenance_immutable before update or delete on collect_hybrid.%I for each row execute function collect_hybrid.guard_roster_provenance()',t);
 end loop;
end $$;

create function collect_hybrid.roster_digest(p_value jsonb) returns text
language sql immutable strict set search_path='' as $$
 select encode(extensions.digest(p_value::text,'sha256'),'hex')
$$;

-- Mirrors ECMAScript whitespace normalization used by the existing parser.
create function collect_hybrid.roster_clean_text(p_value text) returns text
language sql immutable strict set search_path='' as $$
 select btrim(regexp_replace(translate(p_value,
  chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)||chr(65279),
  repeat(' ',19)), '[[:space:]]+',' ','g'))
$$;

create function collect_hybrid.require_roster_actor(p_actor uuid,p_session uuid) returns void
language plpgsql security definer set search_path='' as $$
declare u auth.users; s auth.sessions; enabled_flag boolean;
begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if p_actor is null or p_session is null then raise exception 'roster_session_required' using errcode='42501'; end if;
 select * into u from auth.users where id=p_actor for share;
 select * into s from auth.sessions where id=p_session and user_id=p_actor for share;
 if u.id is null or s.id is null or s.created_at is null or not isfinite(s.created_at) or s.created_at>clock_timestamp()
  or s.aal::text not in ('aal1','aal2') or s.aal is null
  or (s.not_after is not null and (not isfinite(s.not_after) or s.not_after<=clock_timestamp()))
  or u.deleted_at is not null or u.phone_confirmed_at is null or coalesce(u.is_anonymous,false)
  or (u.banned_until is not null and u.banned_until>clock_timestamp())
  or not exists(select 1 from collect_admin_access.whatsapp_approvals a
    join public.admin_user_roles ur on ur.user_id=a.user_id and ur.revoked_at is null
    join public.admin_roles r on r.id=ur.role_id and r.name='platform_owner'
    where a.user_id=p_actor and a.revoked_at is null and a.phone_e164='+'||ltrim(u.phone,'+')
      and (a.expires_at is null or a.expires_at>clock_timestamp())
      and s.created_at>=a.approved_at and s.created_at>=ur.created_at
      and exists(select 1 from public.admin_role_permissions rp where rp.role_id=r.id and rp.permission_name='collections.moderate')
      and exists(select 1 from public.admin_role_permissions rp where rp.role_id=r.id and rp.permission_name='users.read')) then
  raise exception 'roster_actor_unavailable' using errcode='42501'; end if;
 select enabled into enabled_flag from public.feature_flags where key='hybrid_member_onboarding' for share;
 if enabled_flag is distinct from true then raise exception 'roster_feature_disabled' using errcode='55000'; end if;
end $$;

create function collect_hybrid.require_roster_caller() returns uuid
language plpgsql security definer set search_path='' as $$
declare sid text:=auth.jwt()->>'session_id';
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'authenticated' or auth.uid() is null or sid is null
  or sid !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then
  raise exception 'roster_session_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(auth.uid(),sid::uuid);
 return sid::uuid;
end $$;

create function collect_hybrid.roster_preview(p_candidates jsonb,p_human boolean) returns jsonb
language plpgsql immutable set search_path='' as $$
declare raw jsonb; n integer:=0; sr integer; confidence numeric; member_name text; momo_name text;
 phone text; compact text; issues jsonb; seen jsonb:='{}'; rows jsonb:='[]'; normalized jsonb:='[]'; ready integer:=0;
begin
 if p_human is null or p_candidates is null or jsonb_typeof(p_candidates)<>'array'
   or jsonb_array_length(p_candidates) not between 1 and 500 or octet_length(p_candidates::text)>512000 then
  raise exception 'roster_input_invalid' using errcode='22023'; end if;
 for raw in select value from jsonb_array_elements(p_candidates) loop
  n:=n+1;
  if jsonb_typeof(raw)<>'object' or jsonb_typeof(raw->'member_name') is distinct from 'string'
    or jsonb_typeof(raw->'momo_name') is distinct from 'string' or jsonb_typeof(raw->'momo_number') is distinct from 'string'
    or length(raw->>'member_name')>480 or length(raw->>'momo_name')>480 or length(raw->>'momo_number')>32
    or exists(select 1 from jsonb_object_keys(raw) k where k not in ('member_name','momo_name','momo_number','source_row','confidence'))
    or (p_human and (raw ? 'source_row' or raw ? 'confidence')) then
   raise exception 'roster_input_invalid' using errcode='22023'; end if;
  if p_human then sr:=n; confidence:=1;
  else
   if jsonb_typeof(raw->'source_row') is distinct from 'number' or (raw->>'source_row') !~ '^[0-9]+$'
     or (raw->>'source_row')::numeric not between 1 and 2147483647
     or jsonb_typeof(raw->'confidence') is distinct from 'number'
     or (raw->>'confidence')::numeric not between 0 and 1 then
    raise exception 'roster_input_invalid' using errcode='22023'; end if;
   sr:=(raw->>'source_row')::integer; confidence:=(raw->>'confidence')::numeric;
  end if;
  member_name:=collect_hybrid.roster_clean_text(raw->>'member_name');
  momo_name:=collect_hybrid.roster_clean_text(raw->>'momo_name');
  compact:=regexp_replace(collect_hybrid.roster_clean_text(raw->>'momo_number'),'[ ().-]','','g');
  if compact ~ '^250' then compact:='+'||compact; end if;
  phone:=null;
  if compact ~ '^07[2389][0-9]{7}$' or compact ~ '^\+2507[2389][0-9]{7}$' then
   phone:=collect_hybrid.canonical_momo_number(compact); end if;
  issues:='[]';
  if length(member_name) not between 2 and 120 then issues:=issues||jsonb_build_array('Member name must contain 2 to 120 characters'); end if;
  if length(momo_name) not between 2 and 120 then issues:=issues||jsonb_build_array('Registered MoMo name must contain 2 to 120 characters'); end if;
  if (member_name||momo_name) ~ '[[:cntrl:]]' then issues:=issues||jsonb_build_array('Names cannot contain control characters'); end if;
  if member_name ~ '^[=+@-]' or momo_name ~ '^[=+@-]' then issues:=issues||jsonb_build_array('Names cannot begin with spreadsheet formula characters'); end if;
  if phone is null then issues:=issues||jsonb_build_array('Enter a valid full Rwanda MoMo number'); end if;
  if confidence<0.8 then issues:=issues||jsonb_build_array('Extraction confidence is below 80%'); end if;
  if phone is not null then
   if seen ? phone then issues:=issues||jsonb_build_array('MoMo number duplicates source row '||(seen->>phone));
   else seen:=seen||jsonb_build_object(phone,sr); end if;
  end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('source_row',sr,'member_name',member_name,'momo_name',momo_name,
   'momo_number',coalesce(phone,collect_hybrid.roster_clean_text(raw->>'momo_number')),'confidence',confidence,'issues',issues,'ready',jsonb_array_length(issues)=0));
  if jsonb_array_length(issues)=0 then
   ready:=ready+1; normalized:=normalized||jsonb_build_array(jsonb_build_object('member_name',member_name,'momo_name',momo_name,'momo_number',phone)); end if;
 end loop;
 if p_human and ready<>n then raise exception 'roster_rows_invalid' using errcode='22023'; end if;
 return jsonb_build_object('rows',rows,'row_count',n,'ready_count',ready,'error_count',n-ready,'normalized_rows',normalized);
end $$;

create function collect_hybrid.roster_revision_receipt(p_revision uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select r.preview||jsonb_build_object('contract_version',1,'ok',true,'import_id',s.id,'source_sha256',s.source_sha256,
  'source_kind',s.source_kind,'revision_id',r.id,'parent_revision_id',r.parent_revision_id,'revision_number',r.revision_number,
  'reviewed_rows_sha256',r.reviewed_rows_sha256,'can_submit',r.processing_method='human_review' and s.expires_at>statement_timestamp()
    and not exists(select 1 from collect_hybrid.roster_import_commits c where c.import_id=s.id)
    and not exists(select 1 from collect_hybrid.roster_import_revisions newer where newer.import_id=s.id and newer.revision_number>r.revision_number),
  'requires_human_review',r.processing_method<>'human_review','processing_method',r.processing_method,'model',e.model,'expires_at',s.expires_at,
  'source_receipt',jsonb_build_object('request_id',s.request_id,'source_size',s.source_size,'client_filename',s.client_filename,
    'declared_mime',s.declared_mime,'detected_type',s.detected_type,'derived_sha256',s.derived_sha256,
    'derived_assurance',case when s.source_kind='xlsx' then 'client_derived_tsv' end,'extraction_id',e.id,
    'ai_consent',s.ai_consent,'consent_version',s.consent_version,'parser_version',s.parser_version,'schema_version',s.schema_version))
 from collect_hybrid.roster_import_revisions r join collect_hybrid.roster_import_sources s on s.id=r.import_id
 left join collect_hybrid.roster_import_extractions e on e.id=r.extraction_id where r.id=p_revision
$$;

create function public.create_roster_import_source(
 p_actor_id uuid,p_session_id uuid,p_request_id uuid,p_source_kind text,p_original_sha256 text,p_original_size bigint,
 p_client_filename text,p_declared_mime text,p_detected_type text,p_derived_sha256 text,p_derived_size bigint,
 p_ai_consent boolean,p_consent_version text,p_ai_metadata jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s collect_hybrid.roster_import_sources; result collect_hybrid.roster_import_results;
 fingerprint text; extraction uuid; replayed boolean:=false; ai boolean:=p_source_kind in ('pdf','image');
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 if p_request_id is null or p_source_kind is null or p_source_kind not in ('text','csv','txt','xlsx','pdf','image')
   or p_original_sha256 is null or p_original_sha256 !~ '^[a-f0-9]{64}$'
   or p_original_size is null or p_original_size not between 1 and (case when p_source_kind in ('text','csv','txt') then 512000 else 5242880 end)
   or p_client_filename is null or p_client_filename !~ '^[A-Za-z0-9][A-Za-z0-9._ -]{0,159}$'
   or p_declared_mime is null or length(p_declared_mime) not between 1 and 128 or p_declared_mime ~ '[[:cntrl:]]'
   or p_detected_type is null
   or (p_source_kind in ('text','txt') and p_detected_type<>'utf8_text')
   or (p_source_kind='csv' and p_detected_type<>'utf8_csv')
   or (p_source_kind='xlsx' and p_detected_type<>'zip_container')
   or (p_source_kind='pdf' and p_detected_type<>'application/pdf')
   or (p_source_kind='image' and p_detected_type not in ('image/png','image/jpeg','image/webp'))
   or (p_source_kind='xlsx' and (p_derived_sha256 is null or p_derived_sha256 !~ '^[a-f0-9]{64}$' or p_derived_size is null or p_derived_size not between 1 and 512000))
   or (p_source_kind<>'xlsx' and (p_derived_sha256 is not null or p_derived_size is not null))
   or p_ai_consent is distinct from ai
   or (not ai and (p_consent_version is not null or p_ai_metadata is not null)) then
  raise exception 'roster_input_invalid' using errcode='22023'; end if;
 if ai then
  if p_consent_version is distinct from 'roster-ai-extraction-v1' or p_ai_metadata is null
    or jsonb_typeof(p_ai_metadata)<>'object' or p_ai_metadata->>'provider' is distinct from 'openai'
    or p_ai_metadata->>'prompt_version' is distinct from 'roster-extraction-v1'
    or jsonb_typeof(p_ai_metadata->'model') is distinct from 'string'
    or length(btrim(p_ai_metadata->>'model')) not between 1 and 128 or (p_ai_metadata->>'model') ~ '[[:cntrl:]]'
    or exists(select 1 from jsonb_object_keys(p_ai_metadata) k where k not in ('provider','model','prompt_version')) then
   raise exception 'roster_input_invalid' using errcode='22023'; end if;
 end if;
 fingerprint:=collect_hybrid.roster_digest(jsonb_build_array(p_actor_id,p_session_id,p_source_kind,p_original_sha256,p_original_size,
   p_client_filename,p_declared_mime,p_detected_type,p_derived_sha256,p_derived_size,p_ai_consent,p_consent_version,p_ai_metadata));
 select * into s from collect_hybrid.roster_import_sources where request_id=p_request_id;
 if s.id is not null then
  if s.input_sha256<>fingerprint then raise exception 'roster_request_conflict' using errcode='55000'; end if;
  select * into result from collect_hybrid.roster_import_results where import_id=s.id;
  if result.import_id is null then raise exception 'roster_import_in_progress' using errcode='55000'; end if;
  replayed:=true;
 else
  if (select count(*) from collect_hybrid.roster_import_sources where actor_id=p_actor_id and created_at>clock_timestamp()-interval '24 hours')>=100 then
   raise exception 'roster_import_limit' using errcode='55000'; end if;
  insert into collect_hybrid.roster_import_sources(request_id,actor_id,session_id,source_kind,source_sha256,source_size,
   client_filename,declared_mime,detected_type,derived_sha256,derived_size,ai_consent,consent_version,input_sha256)
  values(p_request_id,p_actor_id,p_session_id,p_source_kind,p_original_sha256,p_original_size,p_client_filename,p_declared_mime,
   p_detected_type,p_derived_sha256,p_derived_size,p_ai_consent,p_consent_version,fingerprint) returning * into s;
  if ai then
   insert into collect_hybrid.roster_import_extractions(import_id,actor_id,session_id,provider,model,prompt_version,consent_version)
   values(s.id,p_actor_id,p_session_id,'openai',p_ai_metadata->>'model','roster-extraction-v1',p_consent_version);
  end if;
 end if;
 select id into extraction from collect_hybrid.roster_import_extractions where import_id=s.id;
 return jsonb_build_object('contract_version',1,'ok',true,'request_id',s.request_id,'import_id',s.id,
  'source_sha256',s.source_sha256,'source_size',s.source_size,'source_kind',s.source_kind,'extraction_id',extraction,
  'expires_at',s.expires_at,'derived_sha256',s.derived_sha256,'derived_assurance',case when s.source_kind='xlsx' then 'client_derived_tsv' end,
  'state',coalesce(result.state,'awaiting_preview'),'replayed',replayed,
  'completed_preview',collect_hybrid.roster_revision_receipt(result.revision_id),'error_code',result.error_code);
end $$;

create function public.complete_roster_import_preview(p_import_id uuid,p_actor_id uuid,p_session_id uuid,p_candidates jsonb,p_processing_metadata jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s collect_hybrid.roster_import_sources; prior collect_hybrid.roster_import_results; preview jsonb;
 fingerprint text; revision uuid; extraction uuid; method text;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id for update;
 if s.id is null or s.actor_id<>p_actor_id or s.session_id<>p_session_id then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 method:=case when s.ai_consent then 'openai_structured_extraction' else 'deterministic' end;
 if p_processing_metadata is null or jsonb_typeof(p_processing_metadata)<>'object'
  or p_processing_metadata->>'processing_method' is distinct from method
  or not (p_processing_metadata ?& array['processing_method','provider_response_sha256','provider_response_id'])
  or exists(select 1 from jsonb_object_keys(p_processing_metadata) k where k not in ('processing_method','provider_response_sha256','provider_response_id'))
  or (not s.ai_consent and (p_processing_metadata->>'provider_response_sha256' is not null or p_processing_metadata->>'provider_response_id' is not null))
  or (s.ai_consent and (jsonb_typeof(p_processing_metadata->'provider_response_sha256') is distinct from 'string'
    or (p_processing_metadata->>'provider_response_sha256') !~ '^[a-f0-9]{64}$'
    or jsonb_typeof(p_processing_metadata->'provider_response_id') is distinct from 'string'
    or length(p_processing_metadata->>'provider_response_id') not between 1 and 256
    or (p_processing_metadata->>'provider_response_id') ~ '[[:cntrl:]]')) then
  raise exception 'roster_input_invalid' using errcode='22023'; end if;
 preview:=collect_hybrid.roster_preview(p_candidates,false);
 fingerprint:=collect_hybrid.roster_digest(jsonb_build_array(p_candidates,p_processing_metadata));
 select * into prior from collect_hybrid.roster_import_results where import_id=s.id;
 if prior.import_id is not null then
  if prior.state<>'preview_ready' or prior.input_sha256<>fingerprint then raise exception 'roster_request_conflict' using errcode='55000'; end if;
  return collect_hybrid.roster_revision_receipt(prior.revision_id);
 end if;
 if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 select id into extraction from collect_hybrid.roster_import_extractions where import_id=s.id;
 insert into collect_hybrid.roster_import_revisions(import_id,extraction_id,revision_number,actor_id,session_id,processing_method,
  preview,normalized_rows,reviewed_rows_sha256,input_sha256)
 values(s.id,extraction,1,p_actor_id,p_session_id,method,preview,preview->'normalized_rows',
  collect_hybrid.roster_digest(preview->'normalized_rows'),fingerprint) returning id into revision;
 insert into collect_hybrid.roster_import_results(import_id,actor_id,session_id,state,revision_id,processing_metadata,input_sha256)
 values(s.id,p_actor_id,p_session_id,'preview_ready',revision,p_processing_metadata,fingerprint);
 return collect_hybrid.roster_revision_receipt(revision);
end $$;

create function public.fail_roster_import_preview(p_import_id uuid,p_actor_id uuid,p_session_id uuid,p_error_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s collect_hybrid.roster_import_sources; prior collect_hybrid.roster_import_results; replayed boolean:=false;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 if p_error_code is null or p_error_code not in ('roster_extraction_failed','roster_extraction_timeout','roster_extraction_refused',
  'roster_extraction_incomplete','roster_provider_response_invalid','roster_provider_response_too_large','roster_preview_invalid','roster_extraction_unavailable') then
  raise exception 'roster_input_invalid' using errcode='22023'; end if;
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id for update;
 if s.id is null or s.actor_id<>p_actor_id or s.session_id<>p_session_id then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 select * into prior from collect_hybrid.roster_import_results where import_id=s.id;
 if prior.import_id is not null then
  if prior.state<>'failed' or prior.error_code<>p_error_code then raise exception 'roster_request_conflict' using errcode='55000'; end if;
  replayed:=true;
 else
  insert into collect_hybrid.roster_import_results(import_id,actor_id,session_id,state,error_code,input_sha256)
  values(s.id,p_actor_id,p_session_id,'failed',p_error_code,collect_hybrid.roster_digest(to_jsonb(p_error_code)));
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'import_id',s.id,'state','failed','error_code',p_error_code,'replayed',replayed);
end $$;

create function public.admin_review_roster_import(p_import_id uuid,p_parent_revision_id uuid,p_rows jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; parent collect_hybrid.roster_import_revisions;
 prior collect_hybrid.roster_import_revisions; preview jsonb; fingerprint text; revision uuid; reason text:=btrim(p_reason);
begin
 sid:=collect_hybrid.require_roster_caller();
 if p_request_id is null or p_parent_revision_id is null or reason is null or length(reason) not between 8 and 500 or reason ~ '[[:cntrl:]]' then
  raise exception 'roster_input_invalid' using errcode='22023'; end if;
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id for update;
 if s.id is null or s.actor_id<>auth.uid() or s.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 preview:=collect_hybrid.roster_preview(p_rows,true);
 fingerprint:=collect_hybrid.roster_digest(jsonb_build_array(s.id,p_parent_revision_id,preview->'normalized_rows',reason,auth.uid(),sid));
 select * into prior from collect_hybrid.roster_import_revisions where request_id=p_request_id;
 if prior.id is not null then
  if prior.input_sha256<>fingerprint then raise exception 'roster_request_conflict' using errcode='55000'; end if;
  return collect_hybrid.roster_revision_receipt(prior.id);
 end if;
 if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then raise exception 'roster_import_committed' using errcode='55000'; end if;
 if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 select * into parent from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
 if parent.id is null or parent.id<>p_parent_revision_id then raise exception 'roster_revision_superseded' using errcode='55000'; end if;
 if parent.revision_number>=20 then raise exception 'roster_revision_limit' using errcode='55000'; end if;
 insert into collect_hybrid.roster_import_revisions(import_id,parent_revision_id,extraction_id,revision_number,request_id,
  actor_id,session_id,processing_method,preview,normalized_rows,reviewed_rows_sha256,input_sha256,reason)
 values(s.id,parent.id,parent.extraction_id,parent.revision_number+1,p_request_id,auth.uid(),sid,'human_review',preview,
  preview->'normalized_rows',collect_hybrid.roster_digest(preview->'normalized_rows'),fingerprint,reason) returning id into revision;
 perform public.create_audit_log('roster.import.reviewed','roster_import',s.id,
  jsonb_build_object('revision_id',revision,'parent_revision_id',parent.id,'request_id',p_request_id,'row_count',preview->'row_count','reason',reason));
 return collect_hybrid.roster_revision_receipt(revision);
end $$;

create function public.admin_commit_roster_import(p_request_id uuid,p_import_id uuid,p_revision_id uuid,
 p_reviewed_rows_sha256 text,p_human_affirmed boolean,p_mode text,p_collection_id uuid,p_title text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; r collect_hybrid.roster_import_revisions;
 prior collect_hybrid.roster_import_commits; fingerprint text; result jsonb; group_result jsonb; roster_result jsonb;
 group_id uuid; title text:=btrim(p_title); reason text:=btrim(p_reason); validation jsonb;
begin
 sid:=collect_hybrid.require_roster_caller();
 if p_request_id is null or p_import_id is null or p_revision_id is null or p_reviewed_rows_sha256 is null
  or p_reviewed_rows_sha256 !~ '^[a-f0-9]{64}$' or p_human_affirmed is distinct from true
  or p_mode is null or p_mode not in ('create','existing') or reason is null or length(reason) not between 8 and 500 or reason ~ '[[:cntrl:]]'
  or (p_mode='create' and (p_collection_id is not null or title is null or length(title) not between 3 and 120 or title ~ '[[:cntrl:]]'))
  or (p_mode='existing' and (p_collection_id is null or p_title is not null)) then
  raise exception 'roster_input_invalid' using errcode='22023'; end if;
 fingerprint:=collect_hybrid.roster_digest(jsonb_build_array(p_import_id,p_revision_id,p_reviewed_rows_sha256,p_human_affirmed,
  p_mode,p_collection_id,title,reason,auth.uid(),sid));
 select * into prior from collect_hybrid.roster_import_commits where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.input_sha256<>fingerprint then raise exception 'roster_request_conflict' using errcode='55000'; end if;
  return prior.response||jsonb_build_object('replayed',true);
 end if;
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id for update;
 if s.id is null or s.actor_id<>auth.uid() or s.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then raise exception 'roster_import_committed' using errcode='55000'; end if;
 if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 select * into r from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
 if r.id is null or r.id<>p_revision_id or r.processing_method<>'human_review' then raise exception 'roster_revision_superseded' using errcode='55000'; end if;
 validation:=collect_hybrid.roster_preview(r.normalized_rows,true);
 if r.reviewed_rows_sha256<>p_reviewed_rows_sha256 or collect_hybrid.roster_digest(validation->'normalized_rows')<>p_reviewed_rows_sha256 then
  raise exception 'roster_request_conflict' using errcode='55000'; end if;
 begin
 if p_mode='create' then
  group_result:=collect_hybrid.create_assisted_group_with_share(title,reason,gen_random_uuid());
  group_id:=(group_result->>'collection_id')::uuid;
 else
  group_id:=p_collection_id;
  perform 1 from public.collections where id=group_id and currency='RWF' and creation_origin='admin_assisted'
   and archived_at is null and visibility='private' and public_status='private' and not diaspora_enabled for update;
  if not found then raise exception 'roster_collection_unavailable' using errcode='22023'; end if;
 end if;
 insert into public.collection_share_secrets(collection_id,rotated_by) values(group_id,auth.uid()) on conflict(collection_id) do nothing;
 roster_result:=collect_hybrid.add_roster(group_id,r.normalized_rows,gen_random_uuid(),reason);
 exception when sqlstate 'P0001' then
  raise exception 'roster_commit_conflict' using errcode='55000';
 end;
 if roster_result->>'ok' is distinct from 'true' or roster_result->>'collection_id' is distinct from group_id::text
   or jsonb_typeof(roster_result->'rows') is distinct from 'array'
   or jsonb_array_length(roster_result->'rows')<>jsonb_array_length(r.normalized_rows) then
  raise exception 'roster_commit_failed' using errcode='55000'; end if;
 result:=jsonb_build_object('contract_version',1,'ok',true,'request_id',p_request_id,'import_id',s.id,'revision_id',r.id,
  'reviewed_rows_sha256',r.reviewed_rows_sha256,'collection_id',group_id,'mode',p_mode,'roster_count',jsonb_array_length(r.normalized_rows),
  'share_code_ready',exists(select 1 from public.collection_share_secrets where collection_id=group_id),'replayed',false);
 insert into collect_hybrid.roster_import_commits(request_id,import_id,revision_id,collection_id,actor_id,session_id,input_sha256,response)
 values(p_request_id,s.id,r.id,group_id,auth.uid(),sid,fingerprint,result);
 perform public.create_audit_log('roster.import.committed','collection',group_id,jsonb_build_object('request_id',p_request_id,
  'import_id',s.id,'revision_id',r.id,'source_sha256',s.source_sha256,'reviewed_rows_sha256',r.reviewed_rows_sha256,
  'human_affirmed',true,'mode',p_mode,'row_count',jsonb_array_length(r.normalized_rows),'reason',reason));
 return result;
end $$;

create function public.admin_get_roster_import(p_import_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; result collect_hybrid.roster_import_results;
 revision uuid; committed jsonb;
begin
 sid:=collect_hybrid.require_roster_caller();
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id;
 if s.id is null or s.actor_id<>auth.uid() or s.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 select * into result from collect_hybrid.roster_import_results where import_id=s.id;
 select id into revision from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
 select response into committed from collect_hybrid.roster_import_commits where import_id=s.id;
 return jsonb_build_object('contract_version',1,'ok',true,'import_id',s.id,
  'state',case when committed is not null then 'committed' else coalesce(result.state,'awaiting_preview') end,
  'expires_at',s.expires_at,'preview',collect_hybrid.roster_revision_receipt(revision),'commit',committed,'error_code',result.error_code);
end $$;

-- Preserve the existing detail response/ACL and expose actual eligibility data.
-- Collections has no country_code/is_active column: never invent those facts.
create or replace function public.admin_get_collection(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 perform public.assert_admin_permission('collections.read');
 return coalesce((select jsonb_build_object(
  'id',collection.id,'slug',collection.slug,'title',collection.title,'description',collection.description,
  'creator_user_id',collection.creator_user_id,'creator_label','Collect ID '||profile.public_id,
  'collection_type',collection.collection_type,'category_subtype',collection.category_subtype,'purpose_label',collection.purpose_label,
  'receiver_display_label',receiver.label,'receiver_momo_code',receiver.momo_number,'receiver_network',receiver.network,
  'is_platform_sponsored',collection.is_platform_sponsored,'visibility',collection.visibility,'public_status',collection.public_status,
  'status',case when collection.archived_at is not null then 'archived' else collection.public_status::text end,
  'creation_origin',collection.creation_origin,'archived_at',collection.archived_at,'currency',collection.currency,'diaspora_enabled',collection.diaspora_enabled,
  'active_receivers',(select count(*) from public.collection_receivers route where route.collection_id=collection.id and route.is_active),
  'active_members',(select count(*) from public.collection_members member where member.collection_id=collection.id and member.status='active'),
  'pending_payment_intents',(select count(*) from public.payment_intents intent where intent.collection_id=collection.id and intent.status='pending'),
  'created_at',collection.created_at,'updated_at',collection.updated_at)
 from public.collections collection left join public.profiles profile on profile.id=collection.creator_user_id
 left join lateral (select route.label,route.momo_number,route.network from public.collection_receivers route
  where route.collection_id=collection.id and route.is_active order by route.created_at limit 1) receiver on true
 where collection.id=p_id),'{}'::jsonb);
end $$;

-- Old browser and service paths must never accept unattested raw rows again.
create or replace function public.admin_add_assisted_roster(p_collection_id uuid,p_rows jsonb,p_request_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin raise exception 'roster_provenance_required' using errcode='55000'; end $$;
create or replace function public.admin_create_assisted_group_with_roster(p_title text,p_rows jsonb,p_reason text,p_group_request_id uuid,p_roster_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin raise exception 'roster_provenance_required' using errcode='55000'; end $$;
revoke all on function public.admin_add_assisted_roster(uuid,jsonb,uuid,text),
 public.admin_create_assisted_group_with_roster(text,jsonb,text,uuid,uuid),
 collect_hybrid.add_roster(uuid,jsonb,uuid,text),collect_hybrid.create_assisted_group_with_share(text,text,uuid)
 from public,anon,authenticated,service_role;

revoke all on function collect_hybrid.guard_roster_provenance(),collect_hybrid.roster_digest(jsonb),
 collect_hybrid.roster_clean_text(text),collect_hybrid.require_roster_actor(uuid,uuid),collect_hybrid.require_roster_caller(),
 collect_hybrid.roster_preview(jsonb,boolean),collect_hybrid.roster_revision_receipt(uuid)
 from public,anon,authenticated,service_role;
revoke all on function public.create_roster_import_source(uuid,uuid,uuid,text,text,bigint,text,text,text,text,bigint,boolean,text,jsonb),
 public.complete_roster_import_preview(uuid,uuid,uuid,jsonb,jsonb),public.fail_roster_import_preview(uuid,uuid,uuid,text),
 public.admin_review_roster_import(uuid,uuid,jsonb,text,uuid),public.admin_commit_roster_import(uuid,uuid,uuid,text,boolean,text,uuid,text,text),
 public.admin_get_roster_import(uuid) from public,anon,authenticated,service_role;
grant execute on function public.create_roster_import_source(uuid,uuid,uuid,text,text,bigint,text,text,text,text,bigint,boolean,text,jsonb),
 public.complete_roster_import_preview(uuid,uuid,uuid,jsonb,jsonb),public.fail_roster_import_preview(uuid,uuid,uuid,text) to service_role;
grant execute on function public.admin_review_roster_import(uuid,uuid,jsonb,text,uuid),
 public.admin_commit_roster_import(uuid,uuid,uuid,text,boolean,text,uuid,text,text),public.admin_get_roster_import(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
