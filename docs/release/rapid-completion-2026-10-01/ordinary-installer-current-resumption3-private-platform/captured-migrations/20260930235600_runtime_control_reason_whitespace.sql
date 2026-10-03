begin;

-- Current SQL probes accepted invisible Unicode reasons before real
-- settings changes. Reuse235500's private normalization before the
-- existing8..500 bound and audit hash. Preserve all family, permission,
-- identity, parent, revision, publication, ACK and no-op contracts.
do $$begin
 if to_regprocedure('collect_admin_access.normalized_operator_reason(text)') is null then
  raise exception 'runtime_control_reason_normalizer_required' using errcode='55000';
 end if;
end$$;

create or replace function public.admin_update_runtime_control_v1(p_family text,p_identity jsonb,p_patch jsonb,p_expected_revision bigint,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family); sid uuid; old_row jsonb; desired jsonb; head collect_security.runtime_control_heads;
 reason_text text:=collect_admin_access.normalized_operator_reason(p_reason); columns_sql text; values_sql text; assignments_sql text; result_row jsonb; context jsonb; prior_context text; changed boolean;
 parent_id uuid; identifier record;
begin
 sid:=collect_security.runtime_control_actor(p_family);
 if p_expected_revision is null or p_expected_revision not between 0 and 1000000000 or char_length(reason_text) not between 8 and 500
  or regexp_replace(reason_text,E'[\n\r\t]','','g') ~ '[[:cntrl:]]' then raise exception 'runtime_control_revision_reason_required' using errcode='22023';end if;
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 if coalesce((spec->>'user_owned')::boolean,false) and p_identity->>'user_id' is distinct from auth.uid()::text then raise exception 'runtime_control_owner_required' using errcode='42501';end if;
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

notify pgrst,'reload schema';
commit;
