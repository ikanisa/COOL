begin;

-- Authoritative own-canonical restart recovery. A null observation confirms
-- only the absence of canonical intake evidence at this statement; it neither
-- cancels an in-flight submission nor authorizes erasure or a processor action.
create function public.get_current_account_deletion_request_status_v1()
returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare own_request uuid;
begin
 perform collect_privacy.require_actor(false);
 select i.request_id into own_request from collect_privacy.intake_requests i
  where i.subject_id=auth.uid();
 if own_request is null then
  perform collect_privacy.require_actor(false);
  return null;
 end if;
 -- Preserve the exact minimized receipt and all effective live-session fences.
 return public.get_account_deletion_request_status_v1(own_request);
end$$;

revoke all on function public.get_current_account_deletion_request_status_v1()
 from public,anon,authenticated,service_role;
grant execute on function public.get_current_account_deletion_request_status_v1()
 to authenticated;

commit;
