begin;
-- 144: bounded private recovery state. Existing142 provenance is unchanged.
select pg_advisory_xact_lock(193517,141);
create table collect_hybrid.roster_import_recovery_intents (
 request_id uuid primary key, import_id uuid not null references collect_hybrid.roster_import_sources(id),
 actor_id uuid not null, session_id uuid not null,
 kind text not null check(kind in ('review','commit')),
 payload text not null check(octet_length(payload) between 2 and 512000),
 payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 check(isfinite(created_at) and isfinite(expires_at) and expires_at>created_at)
);
create index roster_import_recovery_intents_import_idx on collect_hybrid.roster_import_recovery_intents(import_id);
create table collect_hybrid.roster_import_editor_drafts (
 import_id uuid primary key references collect_hybrid.roster_import_sources(id),
 checkpoint_id uuid not null unique, actor_id uuid not null, session_id uuid not null,
 payload text not null check(octet_length(payload) between 2 and 512000),
 payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
 updated_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 check(isfinite(updated_at) and isfinite(expires_at) and expires_at>updated_at)
);
alter table collect_hybrid.roster_import_recovery_intents enable row level security;
alter table collect_hybrid.roster_import_editor_drafts enable row level security;
revoke all on collect_hybrid.roster_import_recovery_intents,collect_hybrid.roster_import_editor_drafts from public,anon,authenticated,service_role;
-- Intents are immutable until their source expires; the owner-only purge below
-- may remove expired recovery payloads, never original source/review/commit rows.
create function collect_hybrid.guard_roster_recovery_intent() returns trigger
language plpgsql set search_path='' as $$ begin
 if tg_op='DELETE' and old.expires_at<=clock_timestamp() then return old; end if;
 raise exception 'roster_recovery_intent_immutable' using errcode='55000';
end $$;
create trigger roster_recovery_intent_immutable before update or delete on collect_hybrid.roster_import_recovery_intents
 for each row execute function collect_hybrid.guard_roster_recovery_intent();

create function collect_hybrid.roster_recovery_payload(p_payload text,p_sha text,p_kind text) returns jsonb
language plpgsql immutable set search_path='' as $$
declare v jsonb; r jsonb; raw_row json; keys text[]; field text; begin
 if p_payload is null or octet_length(p_payload) not between 2 and 512000
  or p_sha is null or p_sha !~ '^[a-f0-9]{64}$'
  or encode(extensions.digest(convert_to(p_payload,'UTF8'),'sha256'),'hex')<>p_sha then
  raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 begin v:=p_payload::jsonb; exception when others then
  raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end;
 if jsonb_typeof(v)<>'object' then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 if (select count(*) from json_object_keys(p_payload::json))<>(select count(*) from jsonb_object_keys(v)) then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(v) k;
 if p_kind='review' then
  if keys is distinct from array['p_import_id','p_parent_revision_id','p_reason','p_request_id','p_rows'] then
   raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 elsif p_kind='commit' then
  if keys is distinct from array['p_collection_id','p_human_affirmed','p_import_id','p_mode','p_reason','p_request_id','p_reviewed_rows_sha256','p_revision_id','p_title'] then
   raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 elsif p_kind='draft' then
  if keys is distinct from array['parent_revision_id','reason','rows','title'] then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 else raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 if p_kind in ('review','commit') then
  foreach field in array (case when p_kind='review' then array['p_import_id','p_request_id','p_parent_revision_id'] else array['p_import_id','p_request_id','p_revision_id'] end) loop
   if jsonb_typeof(v->field) is distinct from 'string' or coalesce(v->>field,'') !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' then
    raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(v->'p_reason') is distinct from 'string' or length(btrim(v->>'p_reason')) not between 8 and 500 or (v->>'p_reason') ~ '[[:cntrl:]]' then
   raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 end if;
 if p_kind='commit' then
  if v->'p_human_affirmed' is distinct from 'true'::jsonb or jsonb_typeof(v->'p_mode') is distinct from 'string'
   or v->>'p_mode' not in ('create','existing') or jsonb_typeof(v->'p_reviewed_rows_sha256') is distinct from 'string'
   or coalesce(v->>'p_reviewed_rows_sha256','') !~ '^[a-f0-9]{64}$'
   or (v->>'p_mode'='create' and (v->'p_collection_id' is distinct from 'null'::jsonb
    or jsonb_typeof(v->'p_title') is distinct from 'string' or length(btrim(v->>'p_title')) not between 3 and 120 or (v->>'p_title') ~ '[[:cntrl:]]'))
   or (v->>'p_mode'='existing' and (v->'p_title' is distinct from 'null'::jsonb
    or jsonb_typeof(v->'p_collection_id') is distinct from 'string' or coalesce(v->>'p_collection_id','') !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$')) then
   raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 end if;
 if p_kind in ('draft','review') then
  if jsonb_typeof(case when p_kind='draft' then v->'rows' else v->'p_rows' end) is distinct from 'array'
   or jsonb_array_length(case when p_kind='draft' then v->'rows' else v->'p_rows' end) not between 1 and 500 then
   raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
  for raw_row in select value from json_array_elements(case when p_kind='draft' then p_payload::json->'rows' else p_payload::json->'p_rows' end) loop
   r:=raw_row::jsonb;
   if json_typeof(raw_row) is distinct from 'object' then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
   if (select count(*) from json_object_keys(raw_row))<>(select count(*) from jsonb_object_keys(r)) then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
   if jsonb_typeof(r) is distinct from 'object' then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
   select array_agg(k order by k) into keys from jsonb_object_keys(r) k;
   if keys is distinct from array['member_name','momo_name','momo_number']
    or jsonb_typeof(r->'member_name') is distinct from 'string' or length(r->>'member_name')>480
    or jsonb_typeof(r->'momo_name') is distinct from 'string' or length(r->>'momo_name')>480
    or jsonb_typeof(r->'momo_number') is distinct from 'string' or length(r->>'momo_number')>32 then
    raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
  end loop;
 end if;
 if p_kind='draft' and (jsonb_typeof(v->'parent_revision_id') is distinct from 'string' or jsonb_typeof(v->'title') is distinct from 'string' or length(v->>'title')>120
  or jsonb_typeof(v->'reason') is distinct from 'string' or length(v->>'reason')>500
  or coalesce(v->>'parent_revision_id','') !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$') then
  raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 return v;
end $$;

create function public.admin_save_roster_import_draft(p_import_id uuid,p_checkpoint_id uuid,p_previous_checkpoint_id uuid,p_payload text,p_payload_sha256 text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; d collect_hybrid.roster_import_editor_drafts; v jsonb; latest uuid; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id for update;
 if s.id is null or s.actor_id<>auth.uid() or s.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 if p_checkpoint_id is null then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 v:=collect_hybrid.roster_recovery_payload(p_payload,p_payload_sha256,'draft');
 select * into d from collect_hybrid.roster_import_editor_drafts where import_id=s.id for update;
 if d.checkpoint_id=p_checkpoint_id then
  if d.payload<>p_payload or d.payload_sha256<>p_payload_sha256 then raise exception 'roster_request_conflict' using errcode='55000'; end if;
 else
  if d.checkpoint_id is distinct from p_previous_checkpoint_id then raise exception 'roster_draft_superseded' using errcode='55000'; end if;
  if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then raise exception 'roster_import_committed' using errcode='55000'; end if;
  if d.import_id is null and ((select count(*) from collect_hybrid.roster_import_editor_drafts where actor_id=auth.uid() and expires_at>clock_timestamp())>=40
    or (select count(*) from collect_hybrid.roster_import_editor_drafts where session_id=sid and expires_at>clock_timestamp())>=20) then raise exception 'roster_recovery_limit' using errcode='55000'; end if;
  select id into latest from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
  if latest is null or latest::text<>v->>'parent_revision_id' then raise exception 'roster_revision_superseded' using errcode='55000'; end if;
  insert into collect_hybrid.roster_import_editor_drafts(import_id,checkpoint_id,actor_id,session_id,payload,payload_sha256,expires_at)
   values(s.id,p_checkpoint_id,auth.uid(),sid,p_payload,p_payload_sha256,s.expires_at)
   on conflict(import_id) do update set checkpoint_id=excluded.checkpoint_id,payload=excluded.payload,
    payload_sha256=excluded.payload_sha256,updated_at=clock_timestamp();
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'import_id',s.id,'checkpoint_id',p_checkpoint_id,
  'payload_sha256',p_payload_sha256,'expires_at',s.expires_at);
end $$;

create function public.admin_stage_roster_import_intent(p_request_id uuid,p_import_id uuid,p_kind text,p_payload text,p_payload_sha256 text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; prior collect_hybrid.roster_import_recovery_intents; v jsonb; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id for update;
 if s.id is null or s.actor_id<>auth.uid() or s.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 if p_request_id is null or p_kind not in ('review','commit') or p_kind is null then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 v:=collect_hybrid.roster_recovery_payload(p_payload,p_payload_sha256,p_kind);
 if v->>'p_request_id' is distinct from p_request_id::text or v->>'p_import_id' is distinct from s.id::text then
  raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 select * into prior from collect_hybrid.roster_import_recovery_intents where request_id=p_request_id;
 if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid() or prior.session_id<>sid or prior.import_id<>s.id or prior.kind<>p_kind
   or prior.payload<>p_payload or prior.payload_sha256<>p_payload_sha256 then raise exception 'roster_request_conflict' using errcode='55000'; end if;
 else
  if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
  if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then raise exception 'roster_import_committed' using errcode='55000'; end if;
  if (select count(*) from collect_hybrid.roster_import_recovery_intents where import_id=s.id)>=40
   or (select count(*) from collect_hybrid.roster_import_recovery_intents where actor_id=auth.uid() and expires_at>clock_timestamp())>=200
   or (select count(*) from collect_hybrid.roster_import_recovery_intents where session_id=sid and expires_at>clock_timestamp())>=100 then raise exception 'roster_recovery_limit' using errcode='55000'; end if;
  -- Staging is storage only. Frozen142 validates all authority and rows at execution.
  insert into collect_hybrid.roster_import_recovery_intents(request_id,import_id,actor_id,session_id,kind,payload,payload_sha256,expires_at)
   values(p_request_id,s.id,auth.uid(),sid,p_kind,p_payload,p_payload_sha256,s.expires_at);
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'import_id',s.id,'request_id',p_request_id,'kind',p_kind,
  'payload_sha256',p_payload_sha256,'expires_at',s.expires_at);
end $$;

create function public.admin_execute_roster_import_intent(p_request_id uuid,p_payload_sha256 text,p_human_affirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; i collect_hybrid.roster_import_recovery_intents; v jsonb; result jsonb; begin
 sid:=collect_hybrid.require_roster_caller();
 if p_human_affirmed is distinct from true then raise exception 'roster_confirmation_required' using errcode='22023'; end if;
 select * into i from collect_hybrid.roster_import_recovery_intents where request_id=p_request_id;
 if i.request_id is null or i.actor_id<>auth.uid() or i.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 if i.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 if i.payload_sha256 is distinct from p_payload_sha256 then raise exception 'roster_request_conflict' using errcode='55000'; end if;
 v:=collect_hybrid.roster_recovery_payload(i.payload,i.payload_sha256,i.kind);
 if i.kind='review' then
  result:=public.admin_review_roster_import(i.import_id,(v->>'p_parent_revision_id')::uuid,v->'p_rows',v->>'p_reason',i.request_id);
 else
  result:=public.admin_commit_roster_import(i.request_id,i.import_id,(v->>'p_revision_id')::uuid,v->>'p_reviewed_rows_sha256',
   (v->>'p_human_affirmed')::boolean,v->>'p_mode',(v->>'p_collection_id')::uuid,v->>'p_title',v->>'p_reason');
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'request_id',i.request_id,'import_id',i.import_id,
  'kind',i.kind,'payload_sha256',i.payload_sha256,'result',result);
end $$;

create function public.admin_recover_roster_import(p_upload_request_id uuid,p_pending_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; i collect_hybrid.roster_import_recovery_intents;
 d collect_hybrid.roster_import_editor_drafts; state jsonb; initial uuid; answer jsonb; intent jsonb; draft jsonb; phase text; begin
 sid:=collect_hybrid.require_roster_caller();
 if p_upload_request_id is null then raise exception 'roster_recovery_payload_invalid' using errcode='22023'; end if;
 select * into s from collect_hybrid.roster_import_sources where request_id=p_upload_request_id for update;
 if s.id is null then
  -- No file bytes or unsent content can be reconstructed from this reference.
  return jsonb_build_object('contract_version',1,'ok',true,'upload_request_id',p_upload_request_id,
   'import_id',null,'source_sha256',null,'state','missing_source','initial_preview',null,'status',null,
   'requested_intent_id',p_pending_request_id,'intent',null,'draft',null);
 end if;
 if s.actor_id<>auth.uid() or s.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 state:=public.admin_get_roster_import(s.id);
 phase:=state->>'state';
 select id into initial from collect_hybrid.roster_import_revisions where import_id=s.id and revision_number=1;
 if p_pending_request_id is not null then
  select * into i from collect_hybrid.roster_import_recovery_intents where request_id=p_pending_request_id;
  if i.request_id is not null then
   if i.import_id<>s.id or i.actor_id<>auth.uid() or i.session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
   if i.kind='review' then select collect_hybrid.roster_revision_receipt(id) into answer from collect_hybrid.roster_import_revisions where request_id=i.request_id;
   else select response into answer from collect_hybrid.roster_import_commits where request_id=i.request_id; end if;
   intent:=jsonb_build_object('request_id',i.request_id,'kind',i.kind,'payload_sha256',i.payload_sha256,
    'payload',case when i.expires_at>clock_timestamp() then i.payload else null end,'result',answer,
    'expired',i.expires_at<=clock_timestamp());
  end if;
 end if;
 if s.expires_at<=clock_timestamp() and phase<>'committed' then
  -- Original142 provenance remains intact, but expired recovery must not reopen editor rows.
  phase:='expired'; state:=null; initial:=null; intent:=null;
 else
  select * into d from collect_hybrid.roster_import_editor_drafts where import_id=s.id and expires_at>clock_timestamp();
  if d.import_id is not null then
   draft:=jsonb_build_object('checkpoint_id',d.checkpoint_id,'payload_sha256',d.payload_sha256,'payload',d.payload);
  end if;
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'upload_request_id',s.request_id,'import_id',s.id,
  'source_sha256',s.source_sha256,'state',phase,'initial_preview',collect_hybrid.roster_revision_receipt(initial),'status',state,
  'requested_intent_id',p_pending_request_id,'intent',intent,'draft',draft);
end $$;

-- Explicit owner maintenance; no scheduler or provider is introduced. The TTL
-- is enforced on reads immediately, and physical deletion is bounded per call.
create function collect_hybrid.purge_expired_roster_recovery(p_limit integer) returns integer
language plpgsql set search_path='' as $$ declare n integer; m integer; begin
 if current_user not in ('postgres','supabase_admin') or p_limit is null or p_limit not between 1 and 1000 then
  raise exception 'roster_recovery_owner_required' using errcode='42501'; end if;
 with removed as (delete from collect_hybrid.roster_import_editor_drafts where import_id in
  (select import_id from collect_hybrid.roster_import_editor_drafts where expires_at<=clock_timestamp() order by expires_at limit p_limit for update skip locked) returning 1)
 select count(*) into n from removed;
 with removed as (delete from collect_hybrid.roster_import_recovery_intents where request_id in
  (select request_id from collect_hybrid.roster_import_recovery_intents where expires_at<=clock_timestamp() order by expires_at limit p_limit for update skip locked) returning 1)
 select count(*) into m from removed;
 return n+m;
end $$;
revoke all on function collect_hybrid.guard_roster_recovery_intent(),collect_hybrid.roster_recovery_payload(text,text,text),
 collect_hybrid.purge_expired_roster_recovery(integer),
 public.admin_save_roster_import_draft(uuid,uuid,uuid,text,text),
 public.admin_stage_roster_import_intent(uuid,uuid,text,text,text),
 public.admin_execute_roster_import_intent(uuid,text,boolean),public.admin_recover_roster_import(uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_save_roster_import_draft(uuid,uuid,uuid,text,text),
 public.admin_stage_roster_import_intent(uuid,uuid,text,text,text),
 public.admin_execute_roster_import_intent(uuid,text,boolean),public.admin_recover_roster_import(uuid,uuid) to authenticated;
commit;
