begin isolation level serializable;
do $$ begin if current_user<>'postgres' or current_database()<>'postgres' or (select rolsuper from pg_roles where rolname=current_user) or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0' or (select count(*) from supabase_migrations.schema_migrations)<>148 or (select max(version) from supabase_migrations.schema_migrations)<>'20260930160000' then raise exception 'Exact offline sequential upgrade required'; end if; end $$;

-- 149: fresh-Auth recovery. No browser credential/capability is required.
-- Installed142/144/145 provenance is retained byte-for-byte in source/history.
select pg_advisory_xact_lock(193517,141);

-- Lock every authoritative approval/role/permission row, not only Auth.
-- After a revocation wins, an established Repeatable Read snapshot must abort
-- or reject; it cannot authorize a fresh recovery from an older unlocked EXISTS.
create function collect_hybrid.require_roster_actor_authority(p_actor uuid,p_session uuid,p_role_name text,p_permission_names text[])
returns void language plpgsql security definer set search_path='' as $$
declare u auth.users; s auth.sessions; role_uuid uuid; permission text; begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if p_actor is null or p_session is null then raise exception 'roster_session_required' using errcode='42501'; end if;
 if p_role_name is null or p_role_name !~ '^[a-z_]+$' or p_permission_names is null
  or cardinality(p_permission_names) not between 1 and 30
  or exists(select 1 from unnest(p_permission_names) n where n is null or n !~ '^[a-z_]+(\.[a-z_]+)+$') then
  raise exception 'roster_actor_unavailable' using errcode='42501'; end if;
 select * into u from auth.users where id=p_actor for share;
 select * into s from auth.sessions where id=p_session and user_id=p_actor for share;
 if u.id is null or s.id is null or s.created_at is null or not isfinite(s.created_at) or s.created_at>clock_timestamp()
  or s.aal::text not in ('aal1','aal2') or s.aal is null
  or (s.not_after is not null and (not isfinite(s.not_after) or s.not_after<=clock_timestamp()))
  or u.deleted_at is not null or u.phone_confirmed_at is null or coalesce(u.is_anonymous,false)
  or (u.banned_until is not null and u.banned_until>clock_timestamp()) then
  raise exception 'roster_actor_unavailable' using errcode='42501'; end if;
 select r.id into role_uuid from collect_admin_access.whatsapp_approvals a
  join public.admin_user_roles ur on ur.user_id=a.user_id and ur.revoked_at is null
  join public.admin_roles r on r.id=ur.role_id and r.name=p_role_name
  where a.user_id=p_actor and a.revoked_at is null and a.phone_e164='+'||ltrim(u.phone,'+')
   and (a.expires_at is null or a.expires_at>clock_timestamp())
   and s.created_at>=a.approved_at and s.created_at>=ur.created_at
  order by ur.created_at for share of a,ur,r;
 if role_uuid is null then raise exception 'roster_actor_unavailable' using errcode='42501'; end if;
 -- Sorted locks avoid opposite permission-row orders between authority users.
 for permission in select distinct n from unnest(p_permission_names) n order by n loop
  perform 1 from public.admin_role_permissions where role_id=role_uuid and permission_name=permission for share;
  if not found then raise exception 'roster_actor_unavailable' using errcode='42501'; end if;
 end loop;
end $$;
create or replace function collect_hybrid.require_roster_actor(p_actor uuid,p_session uuid) returns void
language plpgsql security definer set search_path='' as $$
declare enabled_flag boolean; begin
 perform collect_hybrid.require_roster_actor_authority(p_actor,p_session,'platform_owner',array['collections.moderate','users.read']);
 select enabled into enabled_flag from public.feature_flags where key='hybrid_member_onboarding' for share;
 if enabled_flag is distinct from true then raise exception 'roster_feature_disabled' using errcode='55000'; end if;
end $$;
revoke all on function collect_hybrid.require_roster_actor_authority(uuid,uuid,text,text[]),
 collect_hybrid.require_roster_actor(uuid,uuid) from public,anon,authenticated,service_role;

-- Advisory serialization alone does not refresh a Repeatable Read snapshot.
-- Every recovery quota decision also writes this private singleton. An older
-- waiter receives40001 instead of counting descendants from a stale snapshot.
create table collect_hybrid.roster_recovery_budget (
 id boolean primary key default true check(id),
 version integer not null check(version>0)
);
insert into collect_hybrid.roster_recovery_budget values(true,1);
alter table collect_hybrid.roster_recovery_budget enable row level security;
revoke all on collect_hybrid.roster_recovery_budget from public,anon,authenticated,service_role;
create function collect_hybrid.lock_roster_recovery_budget() returns void
language plpgsql security definer set search_path='' as $$ begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 update collect_hybrid.roster_recovery_budget set version=version where id;
 if not found then raise exception 'roster_recovery_budget_unavailable' using errcode='55000'; end if;
end $$;

create table collect_hybrid.roster_recovery_transfers (
 request_id uuid primary key,
 root_import_id uuid not null references collect_hybrid.roster_import_sources(id),
 from_import_id uuid not null unique references collect_hybrid.roster_import_sources(id),
 to_import_id uuid not null unique references collect_hybrid.roster_import_sources(id) deferrable initially deferred,
 actor_id uuid not null, from_session_id uuid not null, to_session_id uuid not null,
 destination_reference_id uuid not null unique, initial_revision_id uuid not null unique,
 from_revision_id uuid not null references collect_hybrid.roster_import_revisions(id),
 from_checkpoint_id uuid, from_draft_sha256 text check(from_draft_sha256 is null or from_draft_sha256 ~ '^[a-f0-9]{64}$'),
 from_intents_sha256 text not null check(from_intents_sha256 ~ '^[a-f0-9]{64}$'),
 checkpoint_id uuid, draft_sha256 text,
 source_etag text not null check(source_etag ~ '^[a-f0-9]{64}$'),
 request_sha256 text not null check(request_sha256 ~ '^[a-f0-9]{64}$'),
 original_proof_sha256 text not null check(original_proof_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 check(from_session_id<>to_session_id and from_import_id<>to_import_id),
 check(isfinite(created_at) and isfinite(expires_at) and expires_at>created_at),
 check((checkpoint_id is null and draft_sha256 is null) or
   (checkpoint_id is not null and draft_sha256 ~ '^[a-f0-9]{64}$'))
);
create index roster_recovery_transfer_root_idx on collect_hybrid.roster_recovery_transfers(root_import_id);
alter table collect_hybrid.roster_recovery_transfers enable row level security;
revoke all on collect_hybrid.roster_recovery_transfers from public,anon,authenticated,service_role;
create trigger roster_transfer_immutable before update or delete on collect_hybrid.roster_recovery_transfers
 for each row execute function collect_hybrid.guard_roster_provenance();

create function collect_hybrid.roster_recovery_root(p_import uuid) returns uuid
language sql stable set search_path='' as $$
 select coalesce((select root_import_id from collect_hybrid.roster_recovery_transfers where to_import_id=p_import),p_import)
$$;
create function collect_hybrid.roster_recovery_sha(p_text text) returns text
language sql immutable strict set search_path='' as $$
 select encode(extensions.digest(convert_to(p_text,'UTF8'),'sha256'),'hex')
$$;
-- No token claim supplied by the client is accepted. auth.jwt() has already
-- passed PostgREST signature verification; require_roster_caller rechecks Auth.
create function collect_hybrid.require_fresh_roster_auth() returns uuid
language plpgsql security definer set search_path='' as $$
declare sid uuid; s auth.sessions; exp_epoch numeric; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into s from auth.sessions where id=sid and user_id=auth.uid() for share;
 if s.id is null or s.created_at<clock_timestamp()-interval '10 minutes' or s.created_at>clock_timestamp()
  or jsonb_typeof(auth.jwt()->'exp') is distinct from 'number' then
  raise exception 'roster_fresh_auth_required' using errcode='42501'; end if;
 begin exp_epoch:=(auth.jwt()->>'exp')::numeric; exception when others then
  raise exception 'roster_fresh_auth_required' using errcode='42501'; end;
 if exp_epoch<=extract(epoch from clock_timestamp()) or exp_epoch>253402300799 then
  raise exception 'roster_fresh_auth_required' using errcode='42501'; end if;
 return sid;
end $$;

create function collect_hybrid.roster_recovery_leaf(p_import uuid,p_mutation boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare s collect_hybrid.roster_import_sources; root_source collect_hybrid.roster_import_sources; begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 select * into s from collect_hybrid.roster_import_sources where id=p_import;
 if s.id is null then return; end if; -- Frozen entrypoint preserves its missing-source contract.
 if auth.role()='authenticated' and s.actor_id is distinct from auth.uid() then
  raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 if exists(select 1 from collect_hybrid.roster_recovery_transfers where from_import_id=s.id) then
  raise exception 'roster_recovery_transferred' using errcode='55000'; end if;
 select * into root_source from collect_hybrid.roster_import_sources where id=collect_hybrid.roster_recovery_root(s.id);
 if s.id<>root_source.id then
  -- Logout may legitimately delete the issued source session. Immutable
  -- provenance records that issuance; current verified authority authorizes
  -- this branch. The original SID never becomes a credential/dependency.
  if auth.role()='authenticated' then
   perform collect_hybrid.require_roster_actor(root_source.actor_id,(auth.jwt()->>'session_id')::uuid);
  end if;
  if s.actor_id<>root_source.actor_id or s.expires_at<>root_source.expires_at then
   raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
 end if;
 if p_mutation and s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
end $$;

-- The source proof is reconstructed only from genuine immutable original rows.
-- It is returned as literal UTF8 text with a SHA; no JSON.stringify assumption.
alter function collect_hybrid.roster_revision_receipt(uuid) rename to roster_revision_receipt_v149_frozen;
revoke all on function collect_hybrid.roster_revision_receipt_v149_frozen(uuid) from public,anon,authenticated,service_role;
create function collect_hybrid.roster_original_proof(p_root uuid) returns text
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('contract_version',1,'root_import_id',s.id,'upload_request_id',s.request_id,
  'actor_id',s.actor_id,'session_id',s.session_id,'source_kind',s.source_kind,'source_sha256',s.source_sha256,
  'input_sha256',s.input_sha256,'expires_at',to_char(s.expires_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'source_receipt',collect_hybrid.roster_revision_receipt_v149_frozen(r.id)->'source_receipt',
  'resource_reservation_id',res.id,'decoder_receipt_sha256',v.decoder_receipt_sha256,
  'decoder_build_sha256',v.decoder_build_sha256)::text
 from collect_hybrid.roster_import_sources s
 join collect_hybrid.roster_import_revisions r on r.import_id=s.id and r.revision_number=1
 left join collect_hybrid.roster_resource_reservations res on res.request_id=s.request_id
 left join collect_hybrid.roster_source_verifications v on v.reservation_id=res.id where s.id=p_root
$$;
create function collect_hybrid.roster_revision_receipt(p_revision uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare answer jsonb; t collect_hybrid.roster_recovery_transfers; r collect_hybrid.roster_import_revisions;
 proof text; begin
 select * into r from collect_hybrid.roster_import_revisions where id=p_revision;
 if r.id is null then return null; end if;
 answer:=collect_hybrid.roster_revision_receipt_v149_frozen(r.id);
 if exists(select 1 from collect_hybrid.roster_recovery_transfers where from_import_id=r.import_id) then
  answer:=answer||jsonb_build_object('can_submit',false);
 end if;
 select * into t from collect_hybrid.roster_recovery_transfers where to_import_id=r.import_id;
 if t.request_id is null then return answer; end if;
 proof:=collect_hybrid.roster_original_proof(t.root_import_id);
 if proof is null or collect_hybrid.roster_recovery_sha(proof)<>t.original_proof_sha256 then
  raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
 return answer||jsonb_build_object('source_receipt',proof::jsonb->'source_receipt',
  'recovery_lineage',jsonb_build_object('contract_version',1,'transfer_request_id',t.request_id,
   'root_import_id',t.root_import_id,'from_import_id',t.from_import_id,'to_import_id',t.to_import_id,
   'actor_id',t.actor_id,'destination_session_id',t.to_session_id,'destination_reference_id',t.destination_reference_id,
   'initial_revision_id',t.initial_revision_id,'original_proof',proof,'original_proof_sha256',t.original_proof_sha256));
end $$;

create function collect_hybrid.roster_interrupted_etag(p_import uuid,p_destination_session uuid) returns text
language sql stable security definer set search_path='' as $$
 select collect_hybrid.roster_digest(jsonb_build_object('actor',s.actor_id,'destination_session',p_destination_session,
  'root',collect_hybrid.roster_recovery_root(s.id),'leaf',s.id,'input_sha256',s.input_sha256,'expiry',extract(epoch from s.expires_at),
  'revision',(select id from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1),
  'draft',(select jsonb_build_array(checkpoint_id,payload_sha256) from collect_hybrid.roster_import_editor_drafts where import_id=s.id),
  'intents',(select coalesce(jsonb_agg(jsonb_build_array(request_id,kind,payload_sha256,expires_at) order by request_id),'[]')
    from collect_hybrid.roster_import_recovery_intents where import_id=s.id),
  'commit',(select request_id from collect_hybrid.roster_import_commits where import_id=s.id),
  'transfer',(select request_id from collect_hybrid.roster_recovery_transfers where from_import_id=s.id)))
 from collect_hybrid.roster_import_sources s where s.id=p_import
$$;
create function collect_hybrid.require_interrupted_roster(p_import uuid,p_destination uuid,p_etag text default null)
returns collect_hybrid.roster_import_sources language plpgsql security definer set search_path='' as $$
declare s collect_hybrid.roster_import_sources; new_auth auth.sessions;
 root_source collect_hybrid.roster_import_sources; begin
 select * into s from collect_hybrid.roster_import_sources where id=p_import for update;
 if s.id is null or s.actor_id<>auth.uid() or s.session_id=p_destination then
  raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 perform collect_hybrid.roster_recovery_leaf(s.id,true);
 perform collect_hybrid.require_roster_actor(s.actor_id,p_destination);
 select * into root_source from collect_hybrid.roster_import_sources where id=collect_hybrid.roster_recovery_root(s.id);
 select * into new_auth from auth.sessions where id=p_destination and user_id=s.actor_id;
 if new_auth.id is null or new_auth.created_at<=s.created_at or new_auth.created_at<=root_source.created_at then
  raise exception 'roster_fresh_auth_required' using errcode='42501'; end if;
 if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then
  raise exception 'roster_import_committed' using errcode='55000'; end if;
 if not exists(select 1 from collect_hybrid.roster_import_revisions where import_id=s.id and revision_number=1) then
  raise exception 'roster_preview_unacknowledged' using errcode='55000'; end if;
 if p_etag is not null and (p_etag !~ '^[a-f0-9]{64}$' or p_etag<>collect_hybrid.roster_interrupted_etag(s.id,p_destination)) then
  raise exception 'roster_draft_superseded' using errcode='55000'; end if;
 return s;
end $$;

create function public.admin_list_interrupted_roster_imports() returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; answer jsonb:='[]'; begin
 sid:=collect_hybrid.require_fresh_roster_auth();
 -- A bounded authenticated server lookup; browser references confer no access.
 for s in select * from collect_hybrid.roster_import_sources where actor_id=auth.uid() and session_id<>sid
  and expires_at>clock_timestamp() and not exists(select 1 from collect_hybrid.roster_recovery_transfers where from_import_id=id)
  order by created_at desc,id limit 100 loop
  begin
   if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then
    answer:=answer||jsonb_build_array(jsonb_build_object('import_id',s.id,'source_sha256',s.source_sha256,
     'source_kind',s.source_kind,'created_at',s.created_at,'expires_at',s.expires_at,'state','committed','etag',null));
   else
    perform collect_hybrid.require_interrupted_roster(s.id,sid);
    answer:=answer||jsonb_build_array(jsonb_build_object('import_id',s.id,'source_sha256',s.source_sha256,
     'source_kind',s.source_kind,'created_at',s.created_at,'expires_at',s.expires_at,'state','interrupted',
     'etag',collect_hybrid.roster_interrupted_etag(s.id,sid)));
   end if;
  exception when sqlstate '42501' or sqlstate '55000' then null;
  end;
 end loop;
 return jsonb_build_object('contract_version',1,'ok',true,'actor_id',auth.uid(),'destination_session_id',sid,'items',answer);
end $$;

-- Serialize only the already-validated editor shape without jsonb's added
-- whitespace. Replacing one UUID must not expand a valid512KB checkpoint.
create function collect_hybrid.roster_compact_recovery_draft(p_value jsonb,p_parent uuid) returns text
language sql immutable strict set search_path='' as $$
 select '{"parent_revision_id":'||to_json(p_parent::text)::text||',"rows":['||
  (select string_agg('{"member_name":'||to_json(x->>'member_name')::text||
    ',"momo_name":'||to_json(x->>'momo_name')::text||
    ',"momo_number":'||to_json(x->>'momo_number')::text||'}',',' order by ord)
   from jsonb_array_elements(p_value->'rows') with ordinality a(x,ord))||
  '],"title":'||to_json(p_value->>'title')::text||',"reason":'||to_json(p_value->>'reason')::text||'}'
$$;
create function collect_hybrid.roster_interrupted_draft(p_import uuid,p_parent uuid) returns text
language plpgsql stable security definer set search_path='' as $$
declare d collect_hybrid.roster_import_editor_drafts; r collect_hybrid.roster_import_revisions; v jsonb; begin
 select * into r from collect_hybrid.roster_import_revisions where import_id=p_import order by revision_number desc limit 1;
 select * into d from collect_hybrid.roster_import_editor_drafts where import_id=p_import and expires_at>statement_timestamp();
 if d.import_id is not null then
  v:=collect_hybrid.roster_recovery_payload(d.payload,d.payload_sha256,'draft');
  if not exists(select 1 from collect_hybrid.roster_import_revisions where import_id=p_import
   and id=(v->>'parent_revision_id')::uuid) then
   raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
  if v->>'parent_revision_id'=r.id::text then
   if p_parent=r.id then return d.payload; end if; -- Inspection preserves exact acknowledged bytes/SHA.
   return collect_hybrid.roster_compact_recovery_draft(v,p_parent);
  end if;
 else v:=jsonb_build_object('title','','reason',''); end if;
 -- An acknowledged review supersedes stale editor rows. Preserve its saved
 -- title/reason, but never reapply those older rows or their approval state.
 v:=v||jsonb_build_object('rows',(select jsonb_agg(jsonb_build_object('member_name',x->>'member_name',
  'momo_name',x->>'momo_name','momo_number',x->>'momo_number') order by ord)
  from jsonb_array_elements(r.preview->'rows') with ordinality a(x,ord)));
 return collect_hybrid.roster_compact_recovery_draft(v,p_parent);
end $$;
create function public.admin_inspect_interrupted_roster_import(p_import_id uuid,p_etag text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; initial uuid; latest uuid; payload text; begin
 sid:=collect_hybrid.require_fresh_roster_auth();
 if p_etag is null or p_etag !~ '^[a-f0-9]{64}$' then
  raise exception 'roster_draft_superseded' using errcode='55000'; end if;
 s:=collect_hybrid.require_interrupted_roster(p_import_id,sid,p_etag);
 select id into initial from collect_hybrid.roster_import_revisions where import_id=s.id and revision_number=1;
 select id into latest from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
 payload:=collect_hybrid.roster_interrupted_draft(s.id,latest);
 perform collect_hybrid.roster_recovery_payload(payload,collect_hybrid.roster_recovery_sha(payload),'draft');
 if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 return jsonb_build_object('contract_version',1,'ok',true,'import_id',s.id,'actor_id',auth.uid(),
  'destination_session_id',sid,'etag',p_etag,'initial_preview',collect_hybrid.roster_revision_receipt(initial),
  'latest_preview',collect_hybrid.roster_revision_receipt(latest),'draft_payload',payload,
  'draft_sha256',collect_hybrid.roster_recovery_sha(payload),'expires_at',s.expires_at);
end $$;

create function collect_hybrid.roster_transfer_ack(p_request uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('contract_version',1,'ok',true,'state','transferred','request_id',t.request_id,
  'from_import_id',t.from_import_id,'root_import_id',t.root_import_id,'to_import_id',t.to_import_id,
  'actor_id',t.actor_id,'destination_session_id',t.to_session_id,'destination_reference_id',t.destination_reference_id,
  'initial_revision_id',t.initial_revision_id,'checkpoint_id',t.checkpoint_id,'draft_sha256',t.draft_sha256,
  'source_etag',t.source_etag,'original_proof_sha256',t.original_proof_sha256,'expires_at',t.expires_at)
 from collect_hybrid.roster_recovery_transfers t where t.request_id=p_request
$$;

create function public.admin_transfer_interrupted_roster_import(p_request_id uuid,p_import_id uuid,p_etag text,p_human_affirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; root_source collect_hybrid.roster_import_sources;
 prior collect_hybrid.roster_recovery_transfers; base collect_hybrid.roster_import_revisions;
 old_draft collect_hybrid.roster_import_editor_drafts; old_revision uuid; intents_sha text;
 proof text; fingerprint text; destination uuid:=gen_random_uuid(); lookup_ref uuid:=gen_random_uuid();
 revision uuid:=gen_random_uuid(); checkpoint uuid:=gen_random_uuid(); payload text; preview jsonb; candidates jsonb; begin
 sid:=collect_hybrid.require_fresh_roster_auth();
 perform collect_hybrid.lock_roster_recovery_budget();
 if p_request_id is null or p_import_id is null or p_etag is null or p_etag !~ '^[a-f0-9]{64}$' or p_human_affirmed is distinct from true then
  raise exception 'roster_confirmation_required' using errcode='22023'; end if;
 fingerprint:=collect_hybrid.roster_digest(jsonb_build_array(p_request_id,p_import_id,p_etag,true,auth.uid(),sid));
 select * into prior from collect_hybrid.roster_recovery_transfers where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid() or prior.to_session_id<>sid or prior.request_sha256<>fingerprint then
   raise exception 'roster_request_conflict' using errcode='55000'; end if;
  perform collect_hybrid.roster_recovery_leaf(prior.to_import_id,true);
  return collect_hybrid.roster_transfer_ack(prior.request_id);
 end if;
 s:=collect_hybrid.require_interrupted_roster(p_import_id,sid,p_etag);
 select * into root_source from collect_hybrid.roster_import_sources where id=collect_hybrid.roster_recovery_root(s.id);
 if (select count(*) from collect_hybrid.roster_recovery_transfers where root_import_id=root_source.id)>=8
  or (select count(*) from collect_hybrid.roster_import_sources where actor_id=auth.uid() and created_at>clock_timestamp()-interval '24 hours')>=100
  or (select count(*) from collect_hybrid.roster_import_editor_drafts where actor_id=auth.uid() and expires_at>clock_timestamp())>=40
  or (select count(*) from collect_hybrid.roster_import_editor_drafts where session_id=sid and expires_at>clock_timestamp())>=20 then
  raise exception 'roster_recovery_limit' using errcode='55000'; end if;
 select * into base from collect_hybrid.roster_import_revisions where import_id=root_source.id and revision_number=1;
 select jsonb_agg(jsonb_build_object('source_row',x->'source_row','member_name',x->'member_name',
  'momo_name',x->'momo_name','momo_number',x->'momo_number','confidence',x->'confidence') order by ord)
 into candidates from jsonb_array_elements(base.preview->'rows') with ordinality a(x,ord);
 preview:=collect_hybrid.roster_preview(candidates,false);
 select id into old_revision from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
 select * into old_draft from collect_hybrid.roster_import_editor_drafts where import_id=s.id;
 select collect_hybrid.roster_digest(coalesce(jsonb_agg(jsonb_build_array(request_id,kind,payload_sha256,expires_at) order by request_id),'[]')) into intents_sha
  from collect_hybrid.roster_import_recovery_intents where import_id=s.id;
 proof:=collect_hybrid.roster_original_proof(root_source.id);
 if proof is null then raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
 payload:=collect_hybrid.roster_interrupted_draft(s.id,revision);
 perform collect_hybrid.roster_recovery_payload(payload,collect_hybrid.roster_recovery_sha(payload),'draft');
 -- Audit comes first with a deferred destination FK. Triggers validate the
 -- exact copy against this immutable lineage, never a caller-supplied flag/GUC.
 insert into collect_hybrid.roster_recovery_transfers(request_id,root_import_id,from_import_id,to_import_id,
  actor_id,from_session_id,to_session_id,destination_reference_id,initial_revision_id,checkpoint_id,draft_sha256,
  from_revision_id,from_checkpoint_id,from_draft_sha256,from_intents_sha256,source_etag,request_sha256,original_proof_sha256,expires_at)
 values(p_request_id,root_source.id,s.id,destination,auth.uid(),s.session_id,sid,lookup_ref,revision,checkpoint,
  collect_hybrid.roster_recovery_sha(payload),old_revision,old_draft.checkpoint_id,old_draft.payload_sha256,intents_sha,p_etag,fingerprint,collect_hybrid.roster_recovery_sha(proof),root_source.expires_at);
 insert into collect_hybrid.roster_import_sources(id,request_id,actor_id,session_id,source_kind,source_sha256,source_size,
  client_filename,declared_mime,detected_type,derived_sha256,derived_size,ai_consent,consent_version,
  parser_version,schema_version,input_sha256,expires_at)
 values(destination,lookup_ref,s.actor_id,sid,root_source.source_kind,root_source.source_sha256,root_source.source_size,
  root_source.client_filename,root_source.declared_mime,root_source.detected_type,root_source.derived_sha256,
  root_source.derived_size,root_source.ai_consent,root_source.consent_version,root_source.parser_version,
  root_source.schema_version,root_source.input_sha256,root_source.expires_at);
 insert into collect_hybrid.roster_import_revisions(id,import_id,extraction_id,revision_number,actor_id,session_id,
  processing_method,preview,normalized_rows,reviewed_rows_sha256,input_sha256)
 values(revision,destination,base.extraction_id,1,auth.uid(),sid,base.processing_method,preview,
  preview->'normalized_rows',collect_hybrid.roster_digest(preview->'normalized_rows'),base.input_sha256);
 insert into collect_hybrid.roster_import_results(import_id,actor_id,session_id,state,revision_id,processing_metadata,input_sha256)
 select destination,auth.uid(),sid,'preview_ready',revision,processing_metadata,input_sha256
 from collect_hybrid.roster_import_results where import_id=root_source.id and state='preview_ready';
 insert into collect_hybrid.roster_import_editor_drafts(import_id,checkpoint_id,actor_id,session_id,payload,payload_sha256,expires_at)
 values(destination,checkpoint,auth.uid(),sid,payload,collect_hybrid.roster_recovery_sha(payload),root_source.expires_at);
 perform public.create_audit_log('roster.import.recovery_transferred','roster_import',destination,
  jsonb_build_object('request_id',p_request_id,'from_import_id',s.id,'root_import_id',root_source.id,
   'original_proof_sha256',collect_hybrid.roster_recovery_sha(proof),'human_review_reset',true));
 if root_source.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 return collect_hybrid.roster_transfer_ack(p_request_id);
end $$;

create function public.admin_get_roster_transfer_status(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; t collect_hybrid.roster_recovery_transfers; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into t from collect_hybrid.roster_recovery_transfers where request_id=p_request_id;
 if t.request_id is null then return jsonb_build_object('contract_version',1,'ok',true,'state','missing','request_id',p_request_id); end if;
 if t.actor_id<>auth.uid() or t.to_session_id<>sid then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(t.actor_id,sid);
 return collect_hybrid.roster_transfer_ack(t.request_id);
end $$;
create function public.admin_get_interrupted_roster_commit_status(p_import_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; c collect_hybrid.roster_import_commits; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id;
 if s.id is null or s.actor_id<>auth.uid() then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
 select * into c from collect_hybrid.roster_import_commits where import_id=s.id;
 -- Current authority permits only reading an immutable outcome, no old editor.
 return jsonb_build_object('contract_version',1,'ok',true,'import_id',s.id,'state',case when c.request_id is null then 'missing' else 'committed' end,
  'commit',c.response);
end $$;

-- Trigger-level fencing prevents cached/private old-leaf plans from bypassing
-- the new RPC wrappers. All insert paths share original-root TTL/budgets.
create function collect_hybrid.guard_roster_recovery_descendant() returns trigger
language plpgsql security definer set search_path='' as $$
declare import_uuid uuid; root_uuid uuid; s collect_hybrid.roster_import_sources;
 t collect_hybrid.roster_recovery_transfers; original collect_hybrid.roster_import_sources; begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 perform collect_hybrid.lock_roster_recovery_budget();
 if tg_table_name='roster_import_sources' then
  select * into t from collect_hybrid.roster_recovery_transfers where to_import_id=new.id;
  if t.request_id is not null then
   select * into original from collect_hybrid.roster_import_sources where id=t.root_import_id;
   if new.request_id<>t.destination_reference_id or new.actor_id<>t.actor_id or new.session_id<>t.to_session_id
    or new.expires_at<>original.expires_at or new.source_sha256<>original.source_sha256
    or new.input_sha256<>original.input_sha256
    or (to_jsonb(new)-array['id','request_id','session_id','created_at']) is distinct from
       (to_jsonb(original)-array['id','request_id','session_id','created_at']) then
    raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
  end if;
  if new.expires_at<=clock_timestamp() or new.created_at>clock_timestamp()
   or (select count(*) from collect_hybrid.roster_import_sources where actor_id=new.actor_id
    and created_at>clock_timestamp()-interval '24 hours')>=100 then
   raise exception 'roster_recovery_limit' using errcode='55000'; end if;
  return new;
 end if;
 import_uuid:=new.import_id;
 perform collect_hybrid.roster_recovery_leaf(import_uuid,true);
 select * into s from collect_hybrid.roster_import_sources where id=import_uuid;
 if s.id is null or new.actor_id<>s.actor_id or new.session_id<>s.session_id then
  raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
 root_uuid:=collect_hybrid.roster_recovery_root(import_uuid);
 select * into t from collect_hybrid.roster_recovery_transfers where to_import_id=import_uuid;
 if tg_table_name='roster_import_revisions' then
  if new.processing_method='human_review' and
   (select count(*) from collect_hybrid.roster_import_revisions where processing_method='human_review'
    and collect_hybrid.roster_recovery_root(import_id)=root_uuid)>=19 then
   raise exception 'roster_revision_limit' using errcode='55000'; end if;
  if t.request_id is not null and new.revision_number=1 and
   (new.id<>t.initial_revision_id or new.processing_method='human_review' or new.request_id is not null
    or new.parent_revision_id is not null or new.extraction_id is distinct from
      (select extraction_id from collect_hybrid.roster_import_revisions where import_id=root_uuid and revision_number=1)) then
   raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
 elsif tg_table_name='roster_import_recovery_intents' then
  if new.expires_at<>s.expires_at or
    (select count(*) from collect_hybrid.roster_import_recovery_intents where collect_hybrid.roster_recovery_root(import_id)=root_uuid)>=40
    or (select count(*) from collect_hybrid.roster_import_recovery_intents where actor_id=new.actor_id and expires_at>clock_timestamp())>=200
    or (select count(*) from collect_hybrid.roster_import_recovery_intents where session_id=new.session_id and expires_at>clock_timestamp())>=100 then
   raise exception 'roster_recovery_limit' using errcode='55000'; end if;
  perform collect_hybrid.roster_recovery_payload(new.payload,new.payload_sha256,new.kind);
 elsif tg_table_name='roster_import_editor_drafts' then
  if new.expires_at<>s.expires_at or (tg_op='INSERT' and
   ((select count(*) from collect_hybrid.roster_import_editor_drafts where actor_id=new.actor_id and expires_at>clock_timestamp())>=40
    or (select count(*) from collect_hybrid.roster_import_editor_drafts where session_id=new.session_id and expires_at>clock_timestamp())>=20)) then
   raise exception 'roster_recovery_limit' using errcode='55000'; end if;
  perform collect_hybrid.roster_recovery_payload(new.payload,new.payload_sha256,'draft');
 elsif tg_table_name='roster_import_extractions' then
  if t.request_id is not null then raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
 elsif tg_table_name='roster_import_results' and t.request_id is not null then
  if new.state<>'preview_ready' or new.revision_id<>t.initial_revision_id or
    not exists(select 1 from collect_hybrid.roster_import_results where import_id=root_uuid and state='preview_ready'
     and processing_metadata=new.processing_metadata and input_sha256=new.input_sha256) then
   raise exception 'roster_recovery_lineage_invalid' using errcode='55000'; end if;
 elsif tg_table_name='roster_import_commits' then
  if exists(select 1 from collect_hybrid.roster_import_commits c where collect_hybrid.roster_recovery_root(c.import_id)=root_uuid) then
   raise exception 'roster_import_committed' using errcode='55000'; end if;
 end if;
 -- Final insertion expiry includes the financial commit: an exception rolls
 -- back preceding group/member writes atomically, not merely its receipt.
 if s.expires_at<=clock_timestamp() then raise exception 'roster_import_expired' using errcode='55000'; end if;
 return new;
end $$;
do $$ declare tab text; begin
 foreach tab in array array['roster_import_sources','roster_import_extractions','roster_import_revisions','roster_import_results',
  'roster_import_commits','roster_import_recovery_intents','roster_import_editor_drafts'] loop
  execute format('create trigger roster_recovery_descendant before insert on collect_hybrid.%I for each row execute function collect_hybrid.guard_roster_recovery_descendant()',tab);
 end loop;
 create trigger roster_recovery_draft_update before update on collect_hybrid.roster_import_editor_drafts
  for each row execute function collect_hybrid.guard_roster_recovery_descendant();
end $$;

create function collect_hybrid.guard_roster_service_recovery(p_import uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
 perform collect_hybrid.roster_recovery_leaf(p_import,true);
 if exists(select 1 from collect_hybrid.roster_recovery_transfers where to_import_id=p_import) then
  raise exception 'roster_recovery_provider_replay_forbidden' using errcode='55000'; end if;
end $$;

-- Inventory EVERY installed overload, then move originals into private revoked
-- aliases. Public signatures/defaults remain stable and dispatch through guards.
create table collect_hybrid.roster_recovery_guard_inventory (
 entrypoint text not null, identity_arguments text not null, private_alias text not null,
 primary key(entrypoint,identity_arguments)
);
alter table collect_hybrid.roster_recovery_guard_inventory enable row level security;
revoke all on collect_hybrid.roster_recovery_guard_inventory from public,anon,authenticated,service_role;
do $install$
declare f record; alias_name text; arguments text; guard_sql text; role_name text; required_name text;
 entries text[]:=array['create_roster_import_source','_create_roster_import_source_v142','complete_roster_import_preview','fail_roster_import_preview',
  'admin_review_roster_import','admin_commit_roster_import','admin_get_roster_import','admin_save_roster_import_draft',
  'admin_stage_roster_import_intent','admin_execute_roster_import_intent','admin_recover_roster_import',
  'reserve_roster_resources','verify_roster_source_integrity','finish_roster_resources'];
begin
 foreach required_name in array entries loop
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=required_name) then
   raise exception 'roster_guard_inventory_missing:%',required_name; end if;
 end loop;
 for f in select p.oid,p.proname,p.proargnames,p.prorettype,pg_get_function_arguments(p.oid) as declaration,
  pg_get_function_identity_arguments(p.oid) as identity_args
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=any(entries)
  order by p.proname,p.oid loop
  if f.prorettype<>'jsonb'::regtype then raise exception 'roster_guard_signature_unknown:%',f.proname; end if;
  alias_name:=f.proname||'_guarded_149';
  select string_agg(quote_ident(x),',' order by ord) into arguments from unnest(f.proargnames) with ordinality a(x,ord);
  if arguments is null then raise exception 'roster_guard_signature_unknown:%',f.proname; end if;
  if 'p_import_id'=any(f.proargnames) then
   guard_sql:=format('perform collect_hybrid.%I(p_import_id%s);',
     case when f.proname in ('complete_roster_import_preview','fail_roster_import_preview') then 'guard_roster_service_recovery' else 'roster_recovery_leaf' end,
     case when f.proname in ('complete_roster_import_preview','fail_roster_import_preview') then ''
      when f.proname='admin_get_roster_import' then ',false' else ',true' end);
  elsif f.proname='admin_execute_roster_import_intent' then
   guard_sql:='perform collect_hybrid.roster_recovery_leaf((select import_id from collect_hybrid.roster_import_recovery_intents where request_id=p_request_id),true);';
  elsif f.proname='admin_recover_roster_import' then
   guard_sql:='perform collect_hybrid.roster_recovery_leaf((select id from collect_hybrid.roster_import_sources where request_id=p_upload_request_id),false);';
  elsif 'p_request_id'=any(f.proargnames) then
   guard_sql:='perform collect_hybrid.guard_roster_service_recovery((select id from collect_hybrid.roster_import_sources where request_id=p_request_id));';
  elsif 'p_reservation_id'=any(f.proargnames) then
   guard_sql:='perform collect_hybrid.guard_roster_service_recovery((select s.id from collect_hybrid.roster_import_sources s join collect_hybrid.roster_resource_reservations r on r.request_id=s.request_id where r.id=p_reservation_id));';
  else raise exception 'roster_guard_signature_unknown:%',f.proname; end if;
  if f.proname like 'admin_%%' then
   guard_sql:='perform collect_hybrid.require_roster_caller(); '||guard_sql;
  end if;
  if f.proname='admin_get_roster_import' then
   guard_sql:=guard_sql||$expiry$
    if exists(select 1 from collect_hybrid.roster_import_sources s where s.id=p_import_id and s.expires_at<=clock_timestamp()
      and not exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id)) then
     perform collect_hybrid.require_roster_caller();
     if not exists(select 1 from collect_hybrid.roster_import_sources where id=p_import_id and actor_id=auth.uid()
      and session_id=(auth.jwt()->>'session_id')::uuid) then raise exception 'roster_import_unavailable' using errcode='42501'; end if;
     return jsonb_build_object('contract_version',1,'ok',true,'import_id',p_import_id,'state','expired',
      'expires_at',(select expires_at from collect_hybrid.roster_import_sources where id=p_import_id),'preview',null,'commit',null,'error_code',null);
    end if;
   $expiry$;
  end if;
  execute format('alter function public.%I(%s) set schema collect_hybrid',f.proname,f.identity_args);
  execute format('alter function collect_hybrid.%I(%s) rename to %I',f.proname,f.identity_args,alias_name);
  execute format('revoke all on function collect_hybrid.%I(%s) from public,anon,authenticated,service_role',alias_name,f.identity_args);
  execute format($ddl$create function public.%I(%s) returns jsonb language plpgsql security definer set search_path='' as $fn$
   begin %s return collect_hybrid.%I(%s); end $fn$ $ddl$,f.proname,f.declaration,guard_sql,alias_name,arguments);
  execute format('revoke all on function public.%I(%s) from public,anon,authenticated,service_role',f.proname,f.identity_args);
  role_name:=case when f.proname like 'admin_%%' then 'authenticated' when f.proname='_create_roster_import_source_v142' then null else 'service_role' end;
  if role_name is not null then execute format('grant execute on function public.%I(%s) to %I',f.proname,f.identity_args,role_name); end if;
  insert into collect_hybrid.roster_recovery_guard_inventory values(f.proname,f.identity_args,alias_name);
 end loop;
end $install$;
-- Explicitly inventory the two retired raw-row APIs. They still only reject.
insert into collect_hybrid.roster_recovery_guard_inventory
 select p.proname,pg_get_function_identity_arguments(p.oid),'retired_provenance_required'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
 and p.proname in ('admin_add_assisted_roster','admin_create_assisted_group_with_roster');
revoke all on function public.admin_add_assisted_roster(uuid,jsonb,uuid,text),
 public.admin_create_assisted_group_with_roster(text,jsonb,text,uuid,uuid),collect_hybrid.add_roster(uuid,jsonb,uuid,text),
 collect_hybrid.create_assisted_group_with_share(text,text,uuid) from public,anon,authenticated,service_role;

revoke all on function collect_hybrid.lock_roster_recovery_budget(),collect_hybrid.roster_recovery_root(uuid),collect_hybrid.roster_recovery_sha(text),
 collect_hybrid.require_fresh_roster_auth(),collect_hybrid.roster_recovery_leaf(uuid,boolean),collect_hybrid.roster_original_proof(uuid),
 collect_hybrid.roster_revision_receipt(uuid),collect_hybrid.roster_interrupted_etag(uuid,uuid),
 collect_hybrid.require_interrupted_roster(uuid,uuid,text),collect_hybrid.roster_compact_recovery_draft(jsonb,uuid),
 collect_hybrid.roster_interrupted_draft(uuid,uuid),
 collect_hybrid.roster_transfer_ack(uuid),collect_hybrid.guard_roster_recovery_descendant(),collect_hybrid.guard_roster_service_recovery(uuid),
 public.admin_list_interrupted_roster_imports(),public.admin_inspect_interrupted_roster_import(uuid,text),
 public.admin_transfer_interrupted_roster_import(uuid,uuid,text,boolean),public.admin_get_roster_transfer_status(uuid),
 public.admin_get_interrupted_roster_commit_status(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_list_interrupted_roster_imports(),public.admin_inspect_interrupted_roster_import(uuid,text),
 public.admin_transfer_interrupted_roster_import(uuid,uuid,text,boolean),public.admin_get_roster_transfer_status(uuid),
 public.admin_get_interrupted_roster_commit_status(uuid) to authenticated;
notify pgrst,'reload schema';

insert into supabase_migrations.schema_migrations(version,name,statements) values ('20260930170000','roster_fresh_auth_recovery',array['begin;
-- 149: fresh-Auth recovery. No browser credential/capability is required.
-- Installed142/144/145 provenance is retained byte-for-byte in source/history.
select pg_advisory_xact_lock(193517,141);

-- Lock every authoritative approval/role/permission row, not only Auth.
-- After a revocation wins, an established Repeatable Read snapshot must abort
-- or reject; it cannot authorize a fresh recovery from an older unlocked EXISTS.
create function collect_hybrid.require_roster_actor_authority(p_actor uuid,p_session uuid,p_role_name text,p_permission_names text[])
returns void language plpgsql security definer set search_path='''' as $$
declare u auth.users; s auth.sessions; role_uuid uuid; permission text; begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext(''collect_admin_combined_roster''));
 if p_actor is null or p_session is null then raise exception ''roster_session_required'' using errcode=''42501''; end if;
 if p_role_name is null or p_role_name !~ ''^[a-z_]+$'' or p_permission_names is null
  or cardinality(p_permission_names) not between 1 and 30
  or exists(select 1 from unnest(p_permission_names) n where n is null or n !~ ''^[a-z_]+(\.[a-z_]+)+$'') then
  raise exception ''roster_actor_unavailable'' using errcode=''42501''; end if;
 select * into u from auth.users where id=p_actor for share;
 select * into s from auth.sessions where id=p_session and user_id=p_actor for share;
 if u.id is null or s.id is null or s.created_at is null or not isfinite(s.created_at) or s.created_at>clock_timestamp()
  or s.aal::text not in (''aal1'',''aal2'') or s.aal is null
  or (s.not_after is not null and (not isfinite(s.not_after) or s.not_after<=clock_timestamp()))
  or u.deleted_at is not null or u.phone_confirmed_at is null or coalesce(u.is_anonymous,false)
  or (u.banned_until is not null and u.banned_until>clock_timestamp()) then
  raise exception ''roster_actor_unavailable'' using errcode=''42501''; end if;
 select r.id into role_uuid from collect_admin_access.whatsapp_approvals a
  join public.admin_user_roles ur on ur.user_id=a.user_id and ur.revoked_at is null
  join public.admin_roles r on r.id=ur.role_id and r.name=p_role_name
  where a.user_id=p_actor and a.revoked_at is null and a.phone_e164=''+''||ltrim(u.phone,''+'')
   and (a.expires_at is null or a.expires_at>clock_timestamp())
   and s.created_at>=a.approved_at and s.created_at>=ur.created_at
  order by ur.created_at for share of a,ur,r;
 if role_uuid is null then raise exception ''roster_actor_unavailable'' using errcode=''42501''; end if;
 -- Sorted locks avoid opposite permission-row orders between authority users.
 for permission in select distinct n from unnest(p_permission_names) n order by n loop
  perform 1 from public.admin_role_permissions where role_id=role_uuid and permission_name=permission for share;
  if not found then raise exception ''roster_actor_unavailable'' using errcode=''42501''; end if;
 end loop;
end $$;
create or replace function collect_hybrid.require_roster_actor(p_actor uuid,p_session uuid) returns void
language plpgsql security definer set search_path='''' as $$
declare enabled_flag boolean; begin
 perform collect_hybrid.require_roster_actor_authority(p_actor,p_session,''platform_owner'',array[''collections.moderate'',''users.read'']);
 select enabled into enabled_flag from public.feature_flags where key=''hybrid_member_onboarding'' for share;
 if enabled_flag is distinct from true then raise exception ''roster_feature_disabled'' using errcode=''55000''; end if;
end $$;
revoke all on function collect_hybrid.require_roster_actor_authority(uuid,uuid,text,text[]),
 collect_hybrid.require_roster_actor(uuid,uuid) from public,anon,authenticated,service_role;

-- Advisory serialization alone does not refresh a Repeatable Read snapshot.
-- Every recovery quota decision also writes this private singleton. An older
-- waiter receives40001 instead of counting descendants from a stale snapshot.
create table collect_hybrid.roster_recovery_budget (
 id boolean primary key default true check(id),
 version integer not null check(version>0)
);
insert into collect_hybrid.roster_recovery_budget values(true,1);
alter table collect_hybrid.roster_recovery_budget enable row level security;
revoke all on collect_hybrid.roster_recovery_budget from public,anon,authenticated,service_role;
create function collect_hybrid.lock_roster_recovery_budget() returns void
language plpgsql security definer set search_path='''' as $$ begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext(''collect_admin_combined_roster''));
 update collect_hybrid.roster_recovery_budget set version=version where id;
 if not found then raise exception ''roster_recovery_budget_unavailable'' using errcode=''55000''; end if;
end $$;

create table collect_hybrid.roster_recovery_transfers (
 request_id uuid primary key,
 root_import_id uuid not null references collect_hybrid.roster_import_sources(id),
 from_import_id uuid not null unique references collect_hybrid.roster_import_sources(id),
 to_import_id uuid not null unique references collect_hybrid.roster_import_sources(id) deferrable initially deferred,
 actor_id uuid not null, from_session_id uuid not null, to_session_id uuid not null,
 destination_reference_id uuid not null unique, initial_revision_id uuid not null unique,
 from_revision_id uuid not null references collect_hybrid.roster_import_revisions(id),
 from_checkpoint_id uuid, from_draft_sha256 text check(from_draft_sha256 is null or from_draft_sha256 ~ ''^[a-f0-9]{64}$''),
 from_intents_sha256 text not null check(from_intents_sha256 ~ ''^[a-f0-9]{64}$''),
 checkpoint_id uuid, draft_sha256 text,
 source_etag text not null check(source_etag ~ ''^[a-f0-9]{64}$''),
 request_sha256 text not null check(request_sha256 ~ ''^[a-f0-9]{64}$''),
 original_proof_sha256 text not null check(original_proof_sha256 ~ ''^[a-f0-9]{64}$''),
 created_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 check(from_session_id<>to_session_id and from_import_id<>to_import_id),
 check(isfinite(created_at) and isfinite(expires_at) and expires_at>created_at),
 check((checkpoint_id is null and draft_sha256 is null) or
   (checkpoint_id is not null and draft_sha256 ~ ''^[a-f0-9]{64}$''))
);
create index roster_recovery_transfer_root_idx on collect_hybrid.roster_recovery_transfers(root_import_id);
alter table collect_hybrid.roster_recovery_transfers enable row level security;
revoke all on collect_hybrid.roster_recovery_transfers from public,anon,authenticated,service_role;
create trigger roster_transfer_immutable before update or delete on collect_hybrid.roster_recovery_transfers
 for each row execute function collect_hybrid.guard_roster_provenance();

create function collect_hybrid.roster_recovery_root(p_import uuid) returns uuid
language sql stable set search_path='''' as $$
 select coalesce((select root_import_id from collect_hybrid.roster_recovery_transfers where to_import_id=p_import),p_import)
$$;
create function collect_hybrid.roster_recovery_sha(p_text text) returns text
language sql immutable strict set search_path='''' as $$
 select encode(extensions.digest(convert_to(p_text,''UTF8''),''sha256''),''hex'')
$$;
-- No token claim supplied by the client is accepted. auth.jwt() has already
-- passed PostgREST signature verification; require_roster_caller rechecks Auth.
create function collect_hybrid.require_fresh_roster_auth() returns uuid
language plpgsql security definer set search_path='''' as $$
declare sid uuid; s auth.sessions; exp_epoch numeric; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into s from auth.sessions where id=sid and user_id=auth.uid() for share;
 if s.id is null or s.created_at<clock_timestamp()-interval ''10 minutes'' or s.created_at>clock_timestamp()
  or jsonb_typeof(auth.jwt()->''exp'') is distinct from ''number'' then
  raise exception ''roster_fresh_auth_required'' using errcode=''42501''; end if;
 begin exp_epoch:=(auth.jwt()->>''exp'')::numeric; exception when others then
  raise exception ''roster_fresh_auth_required'' using errcode=''42501''; end;
 if exp_epoch<=extract(epoch from clock_timestamp()) or exp_epoch>253402300799 then
  raise exception ''roster_fresh_auth_required'' using errcode=''42501''; end if;
 return sid;
end $$;

create function collect_hybrid.roster_recovery_leaf(p_import uuid,p_mutation boolean default false) returns void
language plpgsql security definer set search_path='''' as $$
declare s collect_hybrid.roster_import_sources; root_source collect_hybrid.roster_import_sources; begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext(''collect_admin_combined_roster''));
 select * into s from collect_hybrid.roster_import_sources where id=p_import;
 if s.id is null then return; end if; -- Frozen entrypoint preserves its missing-source contract.
 if auth.role()=''authenticated'' and s.actor_id is distinct from auth.uid() then
  raise exception ''roster_import_unavailable'' using errcode=''42501''; end if;
 if exists(select 1 from collect_hybrid.roster_recovery_transfers where from_import_id=s.id) then
  raise exception ''roster_recovery_transferred'' using errcode=''55000''; end if;
 select * into root_source from collect_hybrid.roster_import_sources where id=collect_hybrid.roster_recovery_root(s.id);
 if s.id<>root_source.id then
  -- Logout may legitimately delete the issued source session. Immutable
  -- provenance records that issuance; current verified authority authorizes
  -- this branch. The original SID never becomes a credential/dependency.
  if auth.role()=''authenticated'' then
   perform collect_hybrid.require_roster_actor(root_source.actor_id,(auth.jwt()->>''session_id'')::uuid);
  end if;
  if s.actor_id<>root_source.actor_id or s.expires_at<>root_source.expires_at then
   raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
 end if;
 if p_mutation and s.expires_at<=clock_timestamp() then raise exception ''roster_import_expired'' using errcode=''55000''; end if;
end $$;

-- The source proof is reconstructed only from genuine immutable original rows.
-- It is returned as literal UTF8 text with a SHA; no JSON.stringify assumption.
alter function collect_hybrid.roster_revision_receipt(uuid) rename to roster_revision_receipt_v149_frozen;
revoke all on function collect_hybrid.roster_revision_receipt_v149_frozen(uuid) from public,anon,authenticated,service_role;
create function collect_hybrid.roster_original_proof(p_root uuid) returns text
language sql stable security definer set search_path='''' as $$
 select jsonb_build_object(''contract_version'',1,''root_import_id'',s.id,''upload_request_id'',s.request_id,
  ''actor_id'',s.actor_id,''session_id'',s.session_id,''source_kind'',s.source_kind,''source_sha256'',s.source_sha256,
  ''input_sha256'',s.input_sha256,''expires_at'',to_char(s.expires_at at time zone ''UTC'',''YYYY-MM-DD"T"HH24:MI:SS.US"Z"''),
  ''source_receipt'',collect_hybrid.roster_revision_receipt_v149_frozen(r.id)->''source_receipt'',
  ''resource_reservation_id'',res.id,''decoder_receipt_sha256'',v.decoder_receipt_sha256,
  ''decoder_build_sha256'',v.decoder_build_sha256)::text
 from collect_hybrid.roster_import_sources s
 join collect_hybrid.roster_import_revisions r on r.import_id=s.id and r.revision_number=1
 left join collect_hybrid.roster_resource_reservations res on res.request_id=s.request_id
 left join collect_hybrid.roster_source_verifications v on v.reservation_id=res.id where s.id=p_root
$$;
create function collect_hybrid.roster_revision_receipt(p_revision uuid) returns jsonb
language plpgsql stable security definer set search_path='''' as $$
declare answer jsonb; t collect_hybrid.roster_recovery_transfers; r collect_hybrid.roster_import_revisions;
 proof text; begin
 select * into r from collect_hybrid.roster_import_revisions where id=p_revision;
 if r.id is null then return null; end if;
 answer:=collect_hybrid.roster_revision_receipt_v149_frozen(r.id);
 if exists(select 1 from collect_hybrid.roster_recovery_transfers where from_import_id=r.import_id) then
  answer:=answer||jsonb_build_object(''can_submit'',false);
 end if;
 select * into t from collect_hybrid.roster_recovery_transfers where to_import_id=r.import_id;
 if t.request_id is null then return answer; end if;
 proof:=collect_hybrid.roster_original_proof(t.root_import_id);
 if proof is null or collect_hybrid.roster_recovery_sha(proof)<>t.original_proof_sha256 then
  raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
 return answer||jsonb_build_object(''source_receipt'',proof::jsonb->''source_receipt'',
  ''recovery_lineage'',jsonb_build_object(''contract_version'',1,''transfer_request_id'',t.request_id,
   ''root_import_id'',t.root_import_id,''from_import_id'',t.from_import_id,''to_import_id'',t.to_import_id,
   ''actor_id'',t.actor_id,''destination_session_id'',t.to_session_id,''destination_reference_id'',t.destination_reference_id,
   ''initial_revision_id'',t.initial_revision_id,''original_proof'',proof,''original_proof_sha256'',t.original_proof_sha256));
end $$;

create function collect_hybrid.roster_interrupted_etag(p_import uuid,p_destination_session uuid) returns text
language sql stable security definer set search_path='''' as $$
 select collect_hybrid.roster_digest(jsonb_build_object(''actor'',s.actor_id,''destination_session'',p_destination_session,
  ''root'',collect_hybrid.roster_recovery_root(s.id),''leaf'',s.id,''input_sha256'',s.input_sha256,''expiry'',extract(epoch from s.expires_at),
  ''revision'',(select id from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1),
  ''draft'',(select jsonb_build_array(checkpoint_id,payload_sha256) from collect_hybrid.roster_import_editor_drafts where import_id=s.id),
  ''intents'',(select coalesce(jsonb_agg(jsonb_build_array(request_id,kind,payload_sha256,expires_at) order by request_id),''[]'')
    from collect_hybrid.roster_import_recovery_intents where import_id=s.id),
  ''commit'',(select request_id from collect_hybrid.roster_import_commits where import_id=s.id),
  ''transfer'',(select request_id from collect_hybrid.roster_recovery_transfers where from_import_id=s.id)))
 from collect_hybrid.roster_import_sources s where s.id=p_import
$$;
create function collect_hybrid.require_interrupted_roster(p_import uuid,p_destination uuid,p_etag text default null)
returns collect_hybrid.roster_import_sources language plpgsql security definer set search_path='''' as $$
declare s collect_hybrid.roster_import_sources; new_auth auth.sessions;
 root_source collect_hybrid.roster_import_sources; begin
 select * into s from collect_hybrid.roster_import_sources where id=p_import for update;
 if s.id is null or s.actor_id<>auth.uid() or s.session_id=p_destination then
  raise exception ''roster_import_unavailable'' using errcode=''42501''; end if;
 perform collect_hybrid.roster_recovery_leaf(s.id,true);
 perform collect_hybrid.require_roster_actor(s.actor_id,p_destination);
 select * into root_source from collect_hybrid.roster_import_sources where id=collect_hybrid.roster_recovery_root(s.id);
 select * into new_auth from auth.sessions where id=p_destination and user_id=s.actor_id;
 if new_auth.id is null or new_auth.created_at<=s.created_at or new_auth.created_at<=root_source.created_at then
  raise exception ''roster_fresh_auth_required'' using errcode=''42501''; end if;
 if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then
  raise exception ''roster_import_committed'' using errcode=''55000''; end if;
 if not exists(select 1 from collect_hybrid.roster_import_revisions where import_id=s.id and revision_number=1) then
  raise exception ''roster_preview_unacknowledged'' using errcode=''55000''; end if;
 if p_etag is not null and (p_etag !~ ''^[a-f0-9]{64}$'' or p_etag<>collect_hybrid.roster_interrupted_etag(s.id,p_destination)) then
  raise exception ''roster_draft_superseded'' using errcode=''55000''; end if;
 return s;
end $$;

create function public.admin_list_interrupted_roster_imports() returns jsonb
language plpgsql security definer set search_path='''' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; answer jsonb:=''[]''; begin
 sid:=collect_hybrid.require_fresh_roster_auth();
 -- A bounded authenticated server lookup; browser references confer no access.
 for s in select * from collect_hybrid.roster_import_sources where actor_id=auth.uid() and session_id<>sid
  and expires_at>clock_timestamp() and not exists(select 1 from collect_hybrid.roster_recovery_transfers where from_import_id=id)
  order by created_at desc,id limit 100 loop
  begin
   if exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id) then
    answer:=answer||jsonb_build_array(jsonb_build_object(''import_id'',s.id,''source_sha256'',s.source_sha256,
     ''source_kind'',s.source_kind,''created_at'',s.created_at,''expires_at'',s.expires_at,''state'',''committed'',''etag'',null));
   else
    perform collect_hybrid.require_interrupted_roster(s.id,sid);
    answer:=answer||jsonb_build_array(jsonb_build_object(''import_id'',s.id,''source_sha256'',s.source_sha256,
     ''source_kind'',s.source_kind,''created_at'',s.created_at,''expires_at'',s.expires_at,''state'',''interrupted'',
     ''etag'',collect_hybrid.roster_interrupted_etag(s.id,sid)));
   end if;
  exception when sqlstate ''42501'' or sqlstate ''55000'' then null;
  end;
 end loop;
 return jsonb_build_object(''contract_version'',1,''ok'',true,''actor_id'',auth.uid(),''destination_session_id'',sid,''items'',answer);
end $$;

-- Serialize only the already-validated editor shape without jsonb''s added
-- whitespace. Replacing one UUID must not expand a valid512KB checkpoint.
create function collect_hybrid.roster_compact_recovery_draft(p_value jsonb,p_parent uuid) returns text
language sql immutable strict set search_path='''' as $$
 select ''{"parent_revision_id":''||to_json(p_parent::text)::text||'',"rows":[''||
  (select string_agg(''{"member_name":''||to_json(x->>''member_name'')::text||
    '',"momo_name":''||to_json(x->>''momo_name'')::text||
    '',"momo_number":''||to_json(x->>''momo_number'')::text||''}'','','' order by ord)
   from jsonb_array_elements(p_value->''rows'') with ordinality a(x,ord))||
  ''],"title":''||to_json(p_value->>''title'')::text||'',"reason":''||to_json(p_value->>''reason'')::text||''}''
$$;
create function collect_hybrid.roster_interrupted_draft(p_import uuid,p_parent uuid) returns text
language plpgsql stable security definer set search_path='''' as $$
declare d collect_hybrid.roster_import_editor_drafts; r collect_hybrid.roster_import_revisions; v jsonb; begin
 select * into r from collect_hybrid.roster_import_revisions where import_id=p_import order by revision_number desc limit 1;
 select * into d from collect_hybrid.roster_import_editor_drafts where import_id=p_import and expires_at>statement_timestamp();
 if d.import_id is not null then
  v:=collect_hybrid.roster_recovery_payload(d.payload,d.payload_sha256,''draft'');
  if not exists(select 1 from collect_hybrid.roster_import_revisions where import_id=p_import
   and id=(v->>''parent_revision_id'')::uuid) then
   raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
  if v->>''parent_revision_id''=r.id::text then
   if p_parent=r.id then return d.payload; end if; -- Inspection preserves exact acknowledged bytes/SHA.
   return collect_hybrid.roster_compact_recovery_draft(v,p_parent);
  end if;
 else v:=jsonb_build_object(''title'','''',''reason'',''''); end if;
 -- An acknowledged review supersedes stale editor rows. Preserve its saved
 -- title/reason, but never reapply those older rows or their approval state.
 v:=v||jsonb_build_object(''rows'',(select jsonb_agg(jsonb_build_object(''member_name'',x->>''member_name'',
  ''momo_name'',x->>''momo_name'',''momo_number'',x->>''momo_number'') order by ord)
  from jsonb_array_elements(r.preview->''rows'') with ordinality a(x,ord)));
 return collect_hybrid.roster_compact_recovery_draft(v,p_parent);
end $$;
create function public.admin_inspect_interrupted_roster_import(p_import_id uuid,p_etag text) returns jsonb
language plpgsql security definer set search_path='''' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; initial uuid; latest uuid; payload text; begin
 sid:=collect_hybrid.require_fresh_roster_auth();
 if p_etag is null or p_etag !~ ''^[a-f0-9]{64}$'' then
  raise exception ''roster_draft_superseded'' using errcode=''55000''; end if;
 s:=collect_hybrid.require_interrupted_roster(p_import_id,sid,p_etag);
 select id into initial from collect_hybrid.roster_import_revisions where import_id=s.id and revision_number=1;
 select id into latest from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
 payload:=collect_hybrid.roster_interrupted_draft(s.id,latest);
 perform collect_hybrid.roster_recovery_payload(payload,collect_hybrid.roster_recovery_sha(payload),''draft'');
 if s.expires_at<=clock_timestamp() then raise exception ''roster_import_expired'' using errcode=''55000''; end if;
 return jsonb_build_object(''contract_version'',1,''ok'',true,''import_id'',s.id,''actor_id'',auth.uid(),
  ''destination_session_id'',sid,''etag'',p_etag,''initial_preview'',collect_hybrid.roster_revision_receipt(initial),
  ''latest_preview'',collect_hybrid.roster_revision_receipt(latest),''draft_payload'',payload,
  ''draft_sha256'',collect_hybrid.roster_recovery_sha(payload),''expires_at'',s.expires_at);
end $$;

create function collect_hybrid.roster_transfer_ack(p_request uuid) returns jsonb
language sql stable security definer set search_path='''' as $$
 select jsonb_build_object(''contract_version'',1,''ok'',true,''state'',''transferred'',''request_id'',t.request_id,
  ''from_import_id'',t.from_import_id,''root_import_id'',t.root_import_id,''to_import_id'',t.to_import_id,
  ''actor_id'',t.actor_id,''destination_session_id'',t.to_session_id,''destination_reference_id'',t.destination_reference_id,
  ''initial_revision_id'',t.initial_revision_id,''checkpoint_id'',t.checkpoint_id,''draft_sha256'',t.draft_sha256,
  ''source_etag'',t.source_etag,''original_proof_sha256'',t.original_proof_sha256,''expires_at'',t.expires_at)
 from collect_hybrid.roster_recovery_transfers t where t.request_id=p_request
$$;

create function public.admin_transfer_interrupted_roster_import(p_request_id uuid,p_import_id uuid,p_etag text,p_human_affirmed boolean)
returns jsonb language plpgsql security definer set search_path='''' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; root_source collect_hybrid.roster_import_sources;
 prior collect_hybrid.roster_recovery_transfers; base collect_hybrid.roster_import_revisions;
 old_draft collect_hybrid.roster_import_editor_drafts; old_revision uuid; intents_sha text;
 proof text; fingerprint text; destination uuid:=gen_random_uuid(); lookup_ref uuid:=gen_random_uuid();
 revision uuid:=gen_random_uuid(); checkpoint uuid:=gen_random_uuid(); payload text; preview jsonb; candidates jsonb; begin
 sid:=collect_hybrid.require_fresh_roster_auth();
 perform collect_hybrid.lock_roster_recovery_budget();
 if p_request_id is null or p_import_id is null or p_etag is null or p_etag !~ ''^[a-f0-9]{64}$'' or p_human_affirmed is distinct from true then
  raise exception ''roster_confirmation_required'' using errcode=''22023''; end if;
 fingerprint:=collect_hybrid.roster_digest(jsonb_build_array(p_request_id,p_import_id,p_etag,true,auth.uid(),sid));
 select * into prior from collect_hybrid.roster_recovery_transfers where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid() or prior.to_session_id<>sid or prior.request_sha256<>fingerprint then
   raise exception ''roster_request_conflict'' using errcode=''55000''; end if;
  perform collect_hybrid.roster_recovery_leaf(prior.to_import_id,true);
  return collect_hybrid.roster_transfer_ack(prior.request_id);
 end if;
 s:=collect_hybrid.require_interrupted_roster(p_import_id,sid,p_etag);
 select * into root_source from collect_hybrid.roster_import_sources where id=collect_hybrid.roster_recovery_root(s.id);
 if (select count(*) from collect_hybrid.roster_recovery_transfers where root_import_id=root_source.id)>=8
  or (select count(*) from collect_hybrid.roster_import_sources where actor_id=auth.uid() and created_at>clock_timestamp()-interval ''24 hours'')>=100
  or (select count(*) from collect_hybrid.roster_import_editor_drafts where actor_id=auth.uid() and expires_at>clock_timestamp())>=40
  or (select count(*) from collect_hybrid.roster_import_editor_drafts where session_id=sid and expires_at>clock_timestamp())>=20 then
  raise exception ''roster_recovery_limit'' using errcode=''55000''; end if;
 select * into base from collect_hybrid.roster_import_revisions where import_id=root_source.id and revision_number=1;
 select jsonb_agg(jsonb_build_object(''source_row'',x->''source_row'',''member_name'',x->''member_name'',
  ''momo_name'',x->''momo_name'',''momo_number'',x->''momo_number'',''confidence'',x->''confidence'') order by ord)
 into candidates from jsonb_array_elements(base.preview->''rows'') with ordinality a(x,ord);
 preview:=collect_hybrid.roster_preview(candidates,false);
 select id into old_revision from collect_hybrid.roster_import_revisions where import_id=s.id order by revision_number desc limit 1;
 select * into old_draft from collect_hybrid.roster_import_editor_drafts where import_id=s.id;
 select collect_hybrid.roster_digest(coalesce(jsonb_agg(jsonb_build_array(request_id,kind,payload_sha256,expires_at) order by request_id),''[]'')) into intents_sha
  from collect_hybrid.roster_import_recovery_intents where import_id=s.id;
 proof:=collect_hybrid.roster_original_proof(root_source.id);
 if proof is null then raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
 payload:=collect_hybrid.roster_interrupted_draft(s.id,revision);
 perform collect_hybrid.roster_recovery_payload(payload,collect_hybrid.roster_recovery_sha(payload),''draft'');
 -- Audit comes first with a deferred destination FK. Triggers validate the
 -- exact copy against this immutable lineage, never a caller-supplied flag/GUC.
 insert into collect_hybrid.roster_recovery_transfers(request_id,root_import_id,from_import_id,to_import_id,
  actor_id,from_session_id,to_session_id,destination_reference_id,initial_revision_id,checkpoint_id,draft_sha256,
  from_revision_id,from_checkpoint_id,from_draft_sha256,from_intents_sha256,source_etag,request_sha256,original_proof_sha256,expires_at)
 values(p_request_id,root_source.id,s.id,destination,auth.uid(),s.session_id,sid,lookup_ref,revision,checkpoint,
  collect_hybrid.roster_recovery_sha(payload),old_revision,old_draft.checkpoint_id,old_draft.payload_sha256,intents_sha,p_etag,fingerprint,collect_hybrid.roster_recovery_sha(proof),root_source.expires_at);
 insert into collect_hybrid.roster_import_sources(id,request_id,actor_id,session_id,source_kind,source_sha256,source_size,
  client_filename,declared_mime,detected_type,derived_sha256,derived_size,ai_consent,consent_version,
  parser_version,schema_version,input_sha256,expires_at)
 values(destination,lookup_ref,s.actor_id,sid,root_source.source_kind,root_source.source_sha256,root_source.source_size,
  root_source.client_filename,root_source.declared_mime,root_source.detected_type,root_source.derived_sha256,
  root_source.derived_size,root_source.ai_consent,root_source.consent_version,root_source.parser_version,
  root_source.schema_version,root_source.input_sha256,root_source.expires_at);
 insert into collect_hybrid.roster_import_revisions(id,import_id,extraction_id,revision_number,actor_id,session_id,
  processing_method,preview,normalized_rows,reviewed_rows_sha256,input_sha256)
 values(revision,destination,base.extraction_id,1,auth.uid(),sid,base.processing_method,preview,
  preview->''normalized_rows'',collect_hybrid.roster_digest(preview->''normalized_rows''),base.input_sha256);
 insert into collect_hybrid.roster_import_results(import_id,actor_id,session_id,state,revision_id,processing_metadata,input_sha256)
 select destination,auth.uid(),sid,''preview_ready'',revision,processing_metadata,input_sha256
 from collect_hybrid.roster_import_results where import_id=root_source.id and state=''preview_ready'';
 insert into collect_hybrid.roster_import_editor_drafts(import_id,checkpoint_id,actor_id,session_id,payload,payload_sha256,expires_at)
 values(destination,checkpoint,auth.uid(),sid,payload,collect_hybrid.roster_recovery_sha(payload),root_source.expires_at);
 perform public.create_audit_log(''roster.import.recovery_transferred'',''roster_import'',destination,
  jsonb_build_object(''request_id'',p_request_id,''from_import_id'',s.id,''root_import_id'',root_source.id,
   ''original_proof_sha256'',collect_hybrid.roster_recovery_sha(proof),''human_review_reset'',true));
 if root_source.expires_at<=clock_timestamp() then raise exception ''roster_import_expired'' using errcode=''55000''; end if;
 return collect_hybrid.roster_transfer_ack(p_request_id);
end $$;

create function public.admin_get_roster_transfer_status(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='''' as $$
declare sid uuid; t collect_hybrid.roster_recovery_transfers; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into t from collect_hybrid.roster_recovery_transfers where request_id=p_request_id;
 if t.request_id is null then return jsonb_build_object(''contract_version'',1,''ok'',true,''state'',''missing'',''request_id'',p_request_id); end if;
 if t.actor_id<>auth.uid() or t.to_session_id<>sid then raise exception ''roster_import_unavailable'' using errcode=''42501''; end if;
 perform collect_hybrid.require_roster_actor(t.actor_id,sid);
 return collect_hybrid.roster_transfer_ack(t.request_id);
end $$;
create function public.admin_get_interrupted_roster_commit_status(p_import_id uuid) returns jsonb
language plpgsql security definer set search_path='''' as $$
declare sid uuid; s collect_hybrid.roster_import_sources; c collect_hybrid.roster_import_commits; begin
 sid:=collect_hybrid.require_roster_caller();
 select * into s from collect_hybrid.roster_import_sources where id=p_import_id;
 if s.id is null or s.actor_id<>auth.uid() then raise exception ''roster_import_unavailable'' using errcode=''42501''; end if;
 select * into c from collect_hybrid.roster_import_commits where import_id=s.id;
 -- Current authority permits only reading an immutable outcome, no old editor.
 return jsonb_build_object(''contract_version'',1,''ok'',true,''import_id'',s.id,''state'',case when c.request_id is null then ''missing'' else ''committed'' end,
  ''commit'',c.response);
end $$;

-- Trigger-level fencing prevents cached/private old-leaf plans from bypassing
-- the new RPC wrappers. All insert paths share original-root TTL/budgets.
create function collect_hybrid.guard_roster_recovery_descendant() returns trigger
language plpgsql security definer set search_path='''' as $$
declare import_uuid uuid; root_uuid uuid; s collect_hybrid.roster_import_sources;
 t collect_hybrid.roster_recovery_transfers; original collect_hybrid.roster_import_sources; begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext(''collect_admin_combined_roster''));
 perform collect_hybrid.lock_roster_recovery_budget();
 if tg_table_name=''roster_import_sources'' then
  select * into t from collect_hybrid.roster_recovery_transfers where to_import_id=new.id;
  if t.request_id is not null then
   select * into original from collect_hybrid.roster_import_sources where id=t.root_import_id;
   if new.request_id<>t.destination_reference_id or new.actor_id<>t.actor_id or new.session_id<>t.to_session_id
    or new.expires_at<>original.expires_at or new.source_sha256<>original.source_sha256
    or new.input_sha256<>original.input_sha256
    or (to_jsonb(new)-array[''id'',''request_id'',''session_id'',''created_at'']) is distinct from
       (to_jsonb(original)-array[''id'',''request_id'',''session_id'',''created_at'']) then
    raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
  end if;
  if new.expires_at<=clock_timestamp() or new.created_at>clock_timestamp()
   or (select count(*) from collect_hybrid.roster_import_sources where actor_id=new.actor_id
    and created_at>clock_timestamp()-interval ''24 hours'')>=100 then
   raise exception ''roster_recovery_limit'' using errcode=''55000''; end if;
  return new;
 end if;
 import_uuid:=new.import_id;
 perform collect_hybrid.roster_recovery_leaf(import_uuid,true);
 select * into s from collect_hybrid.roster_import_sources where id=import_uuid;
 if s.id is null or new.actor_id<>s.actor_id or new.session_id<>s.session_id then
  raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
 root_uuid:=collect_hybrid.roster_recovery_root(import_uuid);
 select * into t from collect_hybrid.roster_recovery_transfers where to_import_id=import_uuid;
 if tg_table_name=''roster_import_revisions'' then
  if new.processing_method=''human_review'' and
   (select count(*) from collect_hybrid.roster_import_revisions where processing_method=''human_review''
    and collect_hybrid.roster_recovery_root(import_id)=root_uuid)>=19 then
   raise exception ''roster_revision_limit'' using errcode=''55000''; end if;
  if t.request_id is not null and new.revision_number=1 and
   (new.id<>t.initial_revision_id or new.processing_method=''human_review'' or new.request_id is not null
    or new.parent_revision_id is not null or new.extraction_id is distinct from
      (select extraction_id from collect_hybrid.roster_import_revisions where import_id=root_uuid and revision_number=1)) then
   raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
 elsif tg_table_name=''roster_import_recovery_intents'' then
  if new.expires_at<>s.expires_at or
    (select count(*) from collect_hybrid.roster_import_recovery_intents where collect_hybrid.roster_recovery_root(import_id)=root_uuid)>=40
    or (select count(*) from collect_hybrid.roster_import_recovery_intents where actor_id=new.actor_id and expires_at>clock_timestamp())>=200
    or (select count(*) from collect_hybrid.roster_import_recovery_intents where session_id=new.session_id and expires_at>clock_timestamp())>=100 then
   raise exception ''roster_recovery_limit'' using errcode=''55000''; end if;
  perform collect_hybrid.roster_recovery_payload(new.payload,new.payload_sha256,new.kind);
 elsif tg_table_name=''roster_import_editor_drafts'' then
  if new.expires_at<>s.expires_at or (tg_op=''INSERT'' and
   ((select count(*) from collect_hybrid.roster_import_editor_drafts where actor_id=new.actor_id and expires_at>clock_timestamp())>=40
    or (select count(*) from collect_hybrid.roster_import_editor_drafts where session_id=new.session_id and expires_at>clock_timestamp())>=20)) then
   raise exception ''roster_recovery_limit'' using errcode=''55000''; end if;
  perform collect_hybrid.roster_recovery_payload(new.payload,new.payload_sha256,''draft'');
 elsif tg_table_name=''roster_import_extractions'' then
  if t.request_id is not null then raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
 elsif tg_table_name=''roster_import_results'' and t.request_id is not null then
  if new.state<>''preview_ready'' or new.revision_id<>t.initial_revision_id or
    not exists(select 1 from collect_hybrid.roster_import_results where import_id=root_uuid and state=''preview_ready''
     and processing_metadata=new.processing_metadata and input_sha256=new.input_sha256) then
   raise exception ''roster_recovery_lineage_invalid'' using errcode=''55000''; end if;
 elsif tg_table_name=''roster_import_commits'' then
  if exists(select 1 from collect_hybrid.roster_import_commits c where collect_hybrid.roster_recovery_root(c.import_id)=root_uuid) then
   raise exception ''roster_import_committed'' using errcode=''55000''; end if;
 end if;
 -- Final insertion expiry includes the financial commit: an exception rolls
 -- back preceding group/member writes atomically, not merely its receipt.
 if s.expires_at<=clock_timestamp() then raise exception ''roster_import_expired'' using errcode=''55000''; end if;
 return new;
end $$;
do $$ declare tab text; begin
 foreach tab in array array[''roster_import_sources'',''roster_import_extractions'',''roster_import_revisions'',''roster_import_results'',
  ''roster_import_commits'',''roster_import_recovery_intents'',''roster_import_editor_drafts''] loop
  execute format(''create trigger roster_recovery_descendant before insert on collect_hybrid.%I for each row execute function collect_hybrid.guard_roster_recovery_descendant()'',tab);
 end loop;
 create trigger roster_recovery_draft_update before update on collect_hybrid.roster_import_editor_drafts
  for each row execute function collect_hybrid.guard_roster_recovery_descendant();
end $$;

create function collect_hybrid.guard_roster_service_recovery(p_import uuid) returns void
language plpgsql security definer set search_path='''' as $$ begin
 perform collect_hybrid.roster_recovery_leaf(p_import,true);
 if exists(select 1 from collect_hybrid.roster_recovery_transfers where to_import_id=p_import) then
  raise exception ''roster_recovery_provider_replay_forbidden'' using errcode=''55000''; end if;
end $$;

-- Inventory EVERY installed overload, then move originals into private revoked
-- aliases. Public signatures/defaults remain stable and dispatch through guards.
create table collect_hybrid.roster_recovery_guard_inventory (
 entrypoint text not null, identity_arguments text not null, private_alias text not null,
 primary key(entrypoint,identity_arguments)
);
alter table collect_hybrid.roster_recovery_guard_inventory enable row level security;
revoke all on collect_hybrid.roster_recovery_guard_inventory from public,anon,authenticated,service_role;
do $install$
declare f record; alias_name text; arguments text; guard_sql text; role_name text; required_name text;
 entries text[]:=array[''create_roster_import_source'',''_create_roster_import_source_v142'',''complete_roster_import_preview'',''fail_roster_import_preview'',
  ''admin_review_roster_import'',''admin_commit_roster_import'',''admin_get_roster_import'',''admin_save_roster_import_draft'',
  ''admin_stage_roster_import_intent'',''admin_execute_roster_import_intent'',''admin_recover_roster_import'',
  ''reserve_roster_resources'',''verify_roster_source_integrity'',''finish_roster_resources''];
begin
 foreach required_name in array entries loop
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public'' and p.proname=required_name) then
   raise exception ''roster_guard_inventory_missing:%'',required_name; end if;
 end loop;
 for f in select p.oid,p.proname,p.proargnames,p.prorettype,pg_get_function_arguments(p.oid) as declaration,
  pg_get_function_identity_arguments(p.oid) as identity_args
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public'' and p.proname=any(entries)
  order by p.proname,p.oid loop
  if f.prorettype<>''jsonb''::regtype then raise exception ''roster_guard_signature_unknown:%'',f.proname; end if;
  alias_name:=f.proname||''_guarded_149'';
  select string_agg(quote_ident(x),'','' order by ord) into arguments from unnest(f.proargnames) with ordinality a(x,ord);
  if arguments is null then raise exception ''roster_guard_signature_unknown:%'',f.proname; end if;
  if ''p_import_id''=any(f.proargnames) then
   guard_sql:=format(''perform collect_hybrid.%I(p_import_id%s);'',
     case when f.proname in (''complete_roster_import_preview'',''fail_roster_import_preview'') then ''guard_roster_service_recovery'' else ''roster_recovery_leaf'' end,
     case when f.proname in (''complete_roster_import_preview'',''fail_roster_import_preview'') then ''''
      when f.proname=''admin_get_roster_import'' then '',false'' else '',true'' end);
  elsif f.proname=''admin_execute_roster_import_intent'' then
   guard_sql:=''perform collect_hybrid.roster_recovery_leaf((select import_id from collect_hybrid.roster_import_recovery_intents where request_id=p_request_id),true);'';
  elsif f.proname=''admin_recover_roster_import'' then
   guard_sql:=''perform collect_hybrid.roster_recovery_leaf((select id from collect_hybrid.roster_import_sources where request_id=p_upload_request_id),false);'';
  elsif ''p_request_id''=any(f.proargnames) then
   guard_sql:=''perform collect_hybrid.guard_roster_service_recovery((select id from collect_hybrid.roster_import_sources where request_id=p_request_id));'';
  elsif ''p_reservation_id''=any(f.proargnames) then
   guard_sql:=''perform collect_hybrid.guard_roster_service_recovery((select s.id from collect_hybrid.roster_import_sources s join collect_hybrid.roster_resource_reservations r on r.request_id=s.request_id where r.id=p_reservation_id));'';
  else raise exception ''roster_guard_signature_unknown:%'',f.proname; end if;
  if f.proname like ''admin_%%'' then
   guard_sql:=''perform collect_hybrid.require_roster_caller(); ''||guard_sql;
  end if;
  if f.proname=''admin_get_roster_import'' then
   guard_sql:=guard_sql||$expiry$
    if exists(select 1 from collect_hybrid.roster_import_sources s where s.id=p_import_id and s.expires_at<=clock_timestamp()
      and not exists(select 1 from collect_hybrid.roster_import_commits where import_id=s.id)) then
     perform collect_hybrid.require_roster_caller();
     if not exists(select 1 from collect_hybrid.roster_import_sources where id=p_import_id and actor_id=auth.uid()
      and session_id=(auth.jwt()->>''session_id'')::uuid) then raise exception ''roster_import_unavailable'' using errcode=''42501''; end if;
     return jsonb_build_object(''contract_version'',1,''ok'',true,''import_id'',p_import_id,''state'',''expired'',
      ''expires_at'',(select expires_at from collect_hybrid.roster_import_sources where id=p_import_id),''preview'',null,''commit'',null,''error_code'',null);
    end if;
   $expiry$;
  end if;
  execute format(''alter function public.%I(%s) set schema collect_hybrid'',f.proname,f.identity_args);
  execute format(''alter function collect_hybrid.%I(%s) rename to %I'',f.proname,f.identity_args,alias_name);
  execute format(''revoke all on function collect_hybrid.%I(%s) from public,anon,authenticated,service_role'',alias_name,f.identity_args);
  execute format($ddl$create function public.%I(%s) returns jsonb language plpgsql security definer set search_path='''' as $fn$
   begin %s return collect_hybrid.%I(%s); end $fn$ $ddl$,f.proname,f.declaration,guard_sql,alias_name,arguments);
  execute format(''revoke all on function public.%I(%s) from public,anon,authenticated,service_role'',f.proname,f.identity_args);
  role_name:=case when f.proname like ''admin_%%'' then ''authenticated'' when f.proname=''_create_roster_import_source_v142'' then null else ''service_role'' end;
  if role_name is not null then execute format(''grant execute on function public.%I(%s) to %I'',f.proname,f.identity_args,role_name); end if;
  insert into collect_hybrid.roster_recovery_guard_inventory values(f.proname,f.identity_args,alias_name);
 end loop;
end $install$;
-- Explicitly inventory the two retired raw-row APIs. They still only reject.
insert into collect_hybrid.roster_recovery_guard_inventory
 select p.proname,pg_get_function_identity_arguments(p.oid),''retired_provenance_required''
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public''
 and p.proname in (''admin_add_assisted_roster'',''admin_create_assisted_group_with_roster'');
revoke all on function public.admin_add_assisted_roster(uuid,jsonb,uuid,text),
 public.admin_create_assisted_group_with_roster(text,jsonb,text,uuid,uuid),collect_hybrid.add_roster(uuid,jsonb,uuid,text),
 collect_hybrid.create_assisted_group_with_share(text,text,uuid) from public,anon,authenticated,service_role;

revoke all on function collect_hybrid.lock_roster_recovery_budget(),collect_hybrid.roster_recovery_root(uuid),collect_hybrid.roster_recovery_sha(text),
 collect_hybrid.require_fresh_roster_auth(),collect_hybrid.roster_recovery_leaf(uuid,boolean),collect_hybrid.roster_original_proof(uuid),
 collect_hybrid.roster_revision_receipt(uuid),collect_hybrid.roster_interrupted_etag(uuid,uuid),
 collect_hybrid.require_interrupted_roster(uuid,uuid,text),collect_hybrid.roster_compact_recovery_draft(jsonb,uuid),
 collect_hybrid.roster_interrupted_draft(uuid,uuid),
 collect_hybrid.roster_transfer_ack(uuid),collect_hybrid.guard_roster_recovery_descendant(),collect_hybrid.guard_roster_service_recovery(uuid),
 public.admin_list_interrupted_roster_imports(),public.admin_inspect_interrupted_roster_import(uuid,text),
 public.admin_transfer_interrupted_roster_import(uuid,uuid,text,boolean),public.admin_get_roster_transfer_status(uuid),
 public.admin_get_interrupted_roster_commit_status(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_list_interrupted_roster_imports(),public.admin_inspect_interrupted_roster_import(uuid,text),
 public.admin_transfer_interrupted_roster_import(uuid,uuid,text,boolean),public.admin_get_roster_transfer_status(uuid),
 public.admin_get_interrupted_roster_commit_status(uuid) to authenticated;
notify pgrst,''reload schema'';
commit;
']);
commit;
