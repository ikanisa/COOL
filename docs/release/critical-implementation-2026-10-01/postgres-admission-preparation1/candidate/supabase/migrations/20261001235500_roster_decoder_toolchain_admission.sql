begin;
select pg_advisory_xact_lock(193517,194);

-- Update the revoked implementation, preserving migration149's public recovery
-- wrapper, service/session checks, immutable provenance and quota behavior.
-- Previously recorded toolchains are evidence and are never rewritten.
do $$ begin
 if to_regprocedure('collect_hybrid.verify_roster_source_integrity_guarded_149(uuid,uuid,uuid,text,text,text,jsonb,jsonb)') is null
  or not exists(select 1 from collect_hybrid.roster_recovery_guard_inventory
   where entrypoint='verify_roster_source_integrity' and private_alias='verify_roster_source_integrity_guarded_149') then
  raise exception 'roster_decoder_admission_guard_missing'; end if;
end $$;

create or replace function collect_hybrid.verify_roster_source_integrity_guarded_149(p_reservation_id uuid,p_actor_id uuid,p_session_id uuid,
 p_decoder_receipt_sha256 text,p_decoder_build_sha256 text,p_policy_version text,p_toolchain jsonb,p_summary jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r collect_hybrid.roster_resource_reservations; v collect_hybrid.roster_source_verifications;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 select * into r from collect_hybrid.roster_resource_reservations where id=p_reservation_id for update;
 if r.id is null or r.actor_id<>p_actor_id or r.session_id<>p_session_id or r.source_kind not in ('xlsx','image','pdf') then
  raise exception 'roster_resource_unavailable' using errcode='42501'; end if;
 if p_decoder_receipt_sha256 is null or p_decoder_receipt_sha256 !~ '^[a-f0-9]{64}$'
  or p_decoder_build_sha256 is null or p_decoder_build_sha256 !~ '^[a-f0-9]{64}$'
  or p_policy_version is distinct from 'collect-roster-decoder-v1' or p_toolchain is distinct from
   '{"python":"3.12","pillow":"12.3.0","pypdfium2":"5.2.0","pypdf":"6.19.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}'::jsonb
  or p_summary is null or jsonb_typeof(p_summary)<>'object' or not (p_summary ?& array['frames','pages','pixels','expanded_bytes'])
  or (select count(*) from jsonb_object_keys(p_summary))<>4
  or exists(select 1 from jsonb_each(p_summary) where jsonb_typeof(value)<>'number' or value::text !~ '^[0-9]+$'
    or value::text::numeric>160000000)
  or (p_summary->>'frames')::numeric>20 or (p_summary->>'pages')::numeric>20 or (p_summary->>'pixels')::numeric>40000000
  or (r.source_kind='image' and ((p_summary->>'frames')::numeric<1 or (p_summary->>'pages')::numeric<>0 or (p_summary->>'pixels')::numeric<1))
  or (r.source_kind='pdf' and ((p_summary->>'pages')::numeric<1 or (p_summary->>'frames')::numeric<>0 or (p_summary->>'pixels')::numeric<1))
  or (r.source_kind='xlsx' and ((p_summary->>'frames')::numeric<>0 or (p_summary->>'pages')::numeric<>0 or (p_summary->>'pixels')::numeric<>0
    or (p_summary->>'expanded_bytes')::numeric>8388608)) then raise exception 'roster_input_invalid' using errcode='22023'; end if;
 select * into v from collect_hybrid.roster_source_verifications where reservation_id=r.id;
 if v.reservation_id is not null then
  if v.decoder_receipt_sha256<>p_decoder_receipt_sha256 or v.decoder_build_sha256<>p_decoder_build_sha256 or v.toolchain<>p_toolchain or v.summary<>p_summary then
   raise exception 'roster_request_conflict' using errcode='55000'; end if;
 else
  if r.expires_at<=clock_timestamp() or exists(select 1 from collect_hybrid.roster_resource_completions where reservation_id=r.id) then
   raise exception 'roster_resource_expired' using errcode='55000'; end if;
  insert into collect_hybrid.roster_source_verifications values(r.id,r.source_sha256,r.derived_sha256,p_decoder_receipt_sha256,p_decoder_build_sha256,
   p_policy_version,p_toolchain,p_summary,clock_timestamp());
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'reservation_id',r.id,'source_sha256',r.source_sha256,
  'derived_sha256',r.derived_sha256,'decoder_receipt_sha256',p_decoder_receipt_sha256,'verified',true);
end $$;

revoke all on function collect_hybrid.verify_roster_source_integrity_guarded_149(uuid,uuid,uuid,text,text,text,jsonb,jsonb)
 from public,anon,authenticated,service_role;
commit;
