begin;

-- Advisory serialization does not refresh an established Repeatable Read
-- snapshot. Lock the actual approval, grant, role and permission proof rows,
-- using149's authority helper, before returning copy or permitting a change.
-- Keep ordinary member-owned preference authority separate from Admin rights.
create or replace function collect_security.runtime_control_actor(p_family text,p_read boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_spec(p_family);
 session_id uuid; permissions text[];
begin
 if spec is null then raise exception 'runtime_control_family_invalid' using errcode='22023';end if;
 begin session_id:=public._lock_notification_registration_session();
 exception when sqlstate '42501' then
  raise exception 'runtime_control_session_required' using errcode='42501';end;
 if coalesce((spec->>'user_owned')::boolean,false) then return session_id;end if;
 permissions:=array[case when p_read then spec->>'read_permission' else spec->>'permission' end];
 if not p_read and spec ? 'additional_permission' then
  permissions:=array_append(permissions,spec->>'additional_permission');end if;
 begin
  perform collect_hybrid.require_roster_actor_authority(auth.uid(),session_id,'platform_owner',permissions);
 exception when sqlstate '42501' then
  raise exception 'runtime_control_permission_required' using errcode='42501';end;
 return session_id;
end $$;

create or replace function public.admin_list_runtime_control_events_v1(p_family text default null,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$
declare session_id uuid;
begin
 session_id:=public._lock_notification_registration_session();
 begin
  perform collect_hybrid.require_roster_actor_authority(auth.uid(),session_id,'platform_owner',array['audit.read']);
 exception when sqlstate '42501' then
  raise exception 'runtime_control_permission_required' using errcode='42501';end;
 if p_limit is null or p_limit not between 1 and 100
  or p_family is not null and collect_security.runtime_control_spec(p_family) is null then
  raise exception 'runtime_control_query_invalid' using errcode='22023';end if;
 return jsonb_build_object('contract_version',1,'events',coalesce((
  select jsonb_agg(to_jsonb(event)-'session_id' order by event.recorded_at desc,event.id)
  from(select * from collect_security.runtime_control_events
   where p_family is null or family=p_family order by recorded_at desc,id limit p_limit) event),'[]'::jsonb));
end $$;

revoke all on function collect_security.runtime_control_actor(text,boolean)
 from public,anon,authenticated,service_role;
revoke all on function public.admin_list_runtime_control_events_v1(text,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_list_runtime_control_events_v1(text,integer) to authenticated;
notify pgrst,'reload schema';
commit;
