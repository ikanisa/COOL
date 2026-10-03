begin;

-- Contextual read only. It does not replace the v1 mutation/registry or grant
-- an authority token: v2 still executes all final parent/revision/actor guards.
do $$begin
 if to_regprocedure('collect_security.runtime_control_v2_observe(text,boolean)') is null then
  raise exception 'runtime_control_eligibility_prerequisite_required' using errcode='55000';end if;
end$$;

create function public.admin_get_runtime_control_eligibility_v1(
 p_family text,p_identity jsonb,p_expected_revision bigint,p_patch_json text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_v2_spec(p_family);observed jsonb;original_sid uuid;
 patch jsonb;row_value jsonb;desired jsonb;head collect_security.runtime_control_heads;
 permitted jsonb;statuses jsonb:='[]';blocker text;can_manage boolean;create_allowed boolean;
 parent public.policy_documents;template public.notification_templates;has_sections boolean;has_published boolean;
 at_time timestamptz;field text;
begin
 observed:=collect_security.runtime_control_v2_observe(p_family);original_sid:=(observed->>'session_id')::uuid;
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 if p_expected_revision is null or p_expected_revision not between 0 and 1000000000
  or p_patch_json is null or octet_length(p_patch_json) not between 2 and 65536 then
  raise exception 'runtime_control_eligibility_input_invalid' using errcode='22023';end if;
 begin patch:=p_patch_json::jsonb;exception when invalid_text_representation then
  raise exception 'runtime_control_patch_invalid' using errcode='22023';end;
 if jsonb_typeof(patch)<>'object' or exists(select 1 from jsonb_object_keys(patch)k where not(spec->'writable')?k) then
  raise exception 'runtime_control_patch_invalid' using errcode='22023';end if;
 perform collect_security.runtime_control_check_values(p_family,patch);
 -- Complete predicate fences protect missing sections/versions as well as
 -- existing rows. NOWAIT refuses an incompatible writer instead of observing
 -- stale parent eligibility. SHARE rows below bind actual contextual records.
 if p_family in('policy_documents','policy_document_sections','notification_templates','notification_template_versions') then
  begin lock table public.policy_documents,public.policy_document_sections,
   public.notification_templates,public.notification_template_versions in share mode nowait;
  exception when lock_not_available then raise exception 'runtime_control_eligibility_unavailable' using errcode='42501';end;
 end if;
 select * into head from collect_security.runtime_control_heads h
  where h.family=p_family and h.identity=p_identity for share;
 if coalesce(head.revision,0) is distinct from p_expected_revision then
  raise exception 'runtime_control_conflict' using errcode='40001';end if;
 execute format('select to_jsonb(t) from %s t where to_jsonb(t) @> $1 for share',spec->>'relation') into row_value using p_identity;
 if row_value is not null and (head.family is null or head.content_sha256 is distinct from collect_security.runtime_control_hash(row_value)) then
  raise exception 'runtime_control_head_invalid' using errcode='55000';end if;
 desired:=coalesce(row_value,p_identity)||patch;
 select coalesce(jsonb_agg(k),'[]') into permitted from jsonb_array_elements_text(spec->'writable')k
  where row_value is null or not coalesce(spec->'immutable_after_create','[]')?k;
 create_allowed:=(spec->>'create_allowed')::boolean;
 if row_value is null and not create_allowed then blocker:='create_not_allowed';permitted:='[]';end if;
 if p_family='system_settings' and coalesce((row_value->>'is_sensitive')::boolean,false) then
  blocker:='sensitive_value';permitted:='[]';create_allowed:=false;
 end if;
 if p_family in('policy_documents','notification_template_versions') then
  if row_value is not null and (row_value->>'status'<>'draft' or row_value->>'published_at' is not null) then
   permitted:='["status"]';statuses:=case when row_value->>'status'='archived' then '["archived"]'::jsonb else '["published","archived"]'::jsonb end;
  else
   statuses:='["draft","published","archived"]';
   if p_family='policy_documents' then
    perform 1 from public.policy_document_sections where policy_document_id=(p_identity->>'id')::uuid for share;
    has_sections:=found;
    if not has_sections then statuses:='["draft","archived"]';end if;
   end if;
  end if;
 end if;
 if p_family='policy_document_sections' then
  if desired->>'policy_document_id' is null then blocker:='parent_required';permitted:='[]';
  else
   select * into parent from public.policy_documents where id=(desired->>'policy_document_id')::uuid for share;
   if parent.id is null then blocker:='parent_missing';permitted:='[]';
   elsif parent.status<>'draft' or parent.published_at is not null then blocker:='parent_published';permitted:='[]';end if;
  end if;
 elsif p_family='notification_template_versions' then
  if desired->>'template_key' is null then blocker:='parent_required';permitted:='[]';statuses:='[]';
  else
   select * into template from public.notification_templates where key=desired->>'template_key' for share;
   if template.key is null then blocker:='parent_missing';permitted:='[]';statuses:='[]';end if;
  end if;
 elsif p_family='notification_templates' and row_value is not null then
  perform 1 from public.notification_template_versions where template_key=row_value->>'key' for share;
  select exists(select 1 from public.notification_template_versions where template_key=row_value->>'key'
   and (status<>'draft' or published_at is not null)) into has_published;
  if has_published then permitted:='["enabled"]';end if;
 end if;
 -- No unchanged immutable wiring or content is accepted merely because it
 -- hashes to a no-op; the client receives an exact admitted patch boundary.
 if exists(select 1 from jsonb_object_keys(patch)k where not permitted?k) then blocker:='patch_not_permitted';end if;
 if patch?'status' and not statuses?(patch->>'status') then
  blocker:=case when p_family='policy_documents' and patch->>'status'='published' and not coalesce(has_sections,true)
   then 'sections_required' else 'status_not_permitted' end;
 end if;
 observed:=collect_security.runtime_control_v2_observe(p_family);
 if original_sid is distinct from (observed->>'session_id')::uuid then
  raise exception 'runtime_control_session_required' using errcode='42501';end if;
 can_manage:=(observed->>'can_manage')::boolean;
 if not can_manage then blocker:='manage_required';permitted:='[]';statuses:='[]';create_allowed:=false;end if;
 at_time:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'scope','runtime_control_eligibility','family',p_family,'identity',p_identity,
  'revision',coalesce(head.revision,0),'patch_sha256',encode(extensions.digest(convert_to(p_patch_json,'UTF8'),'sha256'),'hex'),
  'checked_at',collect_security.runtime_control_v2_utc(at_time),'sample_valid_until',collect_security.runtime_control_v2_utc(at_time+interval '60 seconds'),
  'can_manage',can_manage,'permitted_fields',permitted,'permitted_statuses',statuses,'create_allowed',create_allowed,'blocker',blocker);
end$$;
revoke all on function public.admin_get_runtime_control_eligibility_v1(text,jsonb,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_get_runtime_control_eligibility_v1(text,jsonb,bigint,text) to authenticated;
notify pgrst,'reload schema';
commit;
