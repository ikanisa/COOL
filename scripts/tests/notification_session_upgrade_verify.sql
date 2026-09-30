\set ON_ERROR_STOP on
-- Execute only after root applies141 to the synthetic140 seed above.
begin;
do $$ declare old_claim record; denied boolean:=false; begin
  if current_setting('collect.notification_qa',true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
    or (select count(*) from supabase_migrations.schema_migrations)<>141
    or (select max(version) from supabase_migrations.schema_migrations)<>'20260929180000' then
    raise exception 'Guarded synthetic141 fixture required'; end if;
  if to_regclass('public.notification_session_upgrade_qa') is null then
    raise exception 'Upgrade QA source graph absent; do not rerun verify or seed blindly'; end if;
  select * into strict old_claim from public.notification_session_upgrade_qa;
  if not exists(select 1 from public.notification_device_tokens
    where id='99720000-0000-4000-8000-000000000010' and not enabled and registration_session_id is null and registration_session_created_at is null
      and disabled_reason='registration_session_required') then raise exception 'Legacy token was rebound or left enabled'; end if;
  if not exists(select 1 from public.notification_deliveries where id=old_claim.delivery_id and status='failed'
    and claim_token=old_claim.claim_token and claim_expires_at=old_claim.claim_expires_at and attempt_count=old_claim.attempt_number)
    then raise exception 'Legacy live-claim evidence/expiry fence not retained'; end if;
  if not exists(select 1 from public.notification_delivery_attempts where delivery_id=old_claim.delivery_id
    and attempt_number=old_claim.attempt_number and outcome='failed') then raise exception 'Legacy attempt evidence missing'; end if;
  if public.notification_delivery_is_current(old_claim.delivery_id,old_claim.claim_token,old_claim.attempt_number)
    then raise exception 'Legacy unbound claim passes preflight'; end if;
  begin perform public.complete_notification_delivery(old_claim.delivery_id,old_claim.claim_token,old_claim.attempt_number,true);
  exception when others then
    if sqlerrm<>'notification_delivery_fence_lost' then raise; end if; denied:=true; end;
  if not denied then raise exception 'Legacy unbound completion permitted'; end if;
  if not exists(select 1 from public.notification_events where id='99720000-0000-4000-8000-000000000020'
    and title='Private synthetic title' and body='Private synthetic body') then raise exception 'In-app content changed'; end if;
end $$;
-- The synthetic token still provides direct tuple provenance for141 here.
-- Record it before deleting the token; no retrospective guessed migration XID.
create temp table notification_upgrade_telemetry_trace on commit drop as
select q.seed_xid,q.telemetry_baseline,q.seed_telemetry_ids,
  (select d.xmin::text from public.notification_device_tokens d
    where d.id='99720000-0000-4000-8000-000000000010') as migration_xid,
  (select d.xmin::text from public.notification_deliveries d where d.id=q.delivery_id) as delivery_xid,
  pg_current_xact_id()::text as verify_xid
from public.notification_session_upgrade_qa q;
delete from public.notification_events where id='99720000-0000-4000-8000-000000000020';
delete from public.notification_device_tokens where id='99720000-0000-4000-8000-000000000010';
delete from auth.users where id='99720000-0000-4000-8000-000000000001';
do $$ declare fk record; referenced boolean; member_ids uuid[]:=ARRAY['99720000-0000-4000-8000-000000000001']::uuid[]; begin
  if exists(select 1 from auth.users where id=any(member_ids))
    or exists(select 1 from collect_hybrid.member_records where id=any(member_ids) and linked_user_id is not null) then
    raise exception 'Synthetic members remain linked; cleanup refused'; end if;
  -- Refuse any referenced row before DELETE; never depend on cascade behavior.
  for fk in select c.conrelid::regclass as relation,a.attname,c.confdeltype,
      cardinality(c.conkey) as key_count from pg_constraint c
      join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
      where c.contype='f' and c.confrelid='collect_hybrid.member_records'::regclass loop
    if fk.key_count<>1 then raise exception 'Unexpected composite member FK; cleanup refused'; end if;
    execute format('select exists(select 1 from %s where %I=any($1))',fk.relation,fk.attname)
      into referenced using member_ids;
    if referenced then raise exception 'Synthetic member referenced by %; cleanup refused',fk.relation; end if;
  end loop;
  delete from collect_hybrid.member_records where id=any(member_ids) and linked_user_id is null;
end $$;
do $$ declare trace record; begin
  select * into strict trace from pg_temp.notification_upgrade_telemetry_trace;
  if trace.migration_xid is null or trace.migration_xid is distinct from trace.delivery_xid
    or trace.seed_xid=trace.migration_xid or trace.verify_xid in (trace.seed_xid,trace.migration_xid) then
    raise exception 'Upgrade phase tuple provenance inconsistent; telemetry cleanup refused'; end if;
  if exists(select 1 from jsonb_array_elements(trace.telemetry_baseline) b
    where not exists(select 1 from public.app_realtime_events e where e.id=(b->>'id')::uuid and to_jsonb(e)=b)) then
    raise exception 'Original telemetry changed; cleanup refused'; end if;
  if exists(select 1 from public.app_realtime_events e
    where not exists(select 1 from jsonb_array_elements(trace.telemetry_baseline) b where b->>'id'=e.id::text)
      and (e.xmin::text not in (trace.seed_xid,trace.migration_xid,trace.verify_xid)
        or e.area not in ('profiles','notifications'))) then
    raise exception 'Unattributed telemetry event; cleanup refused'; end if;
  if (select count(*) from public.app_realtime_events e where e.id=any(trace.seed_telemetry_ids) and e.xmin::text=trace.seed_xid)<>5
    or (select count(*) from public.app_realtime_events e where e.xmin::text=trace.seed_xid and e.area='profiles')<>1
    or (select count(*) from public.app_realtime_events e where e.xmin::text=trace.seed_xid and e.area='notifications')<>4
    or (select count(*) from public.app_realtime_events e where e.xmin::text=trace.migration_xid and e.area='notifications')<>2
    or (select count(*) from public.app_realtime_events e where e.xmin::text=trace.verify_xid and e.area='profiles')<>1
    or (select count(*) from public.app_realtime_events e where e.xmin::text=trace.verify_xid and e.area='notifications')<>2
    or (select count(*) from public.app_realtime_events e where not exists(
      select 1 from jsonb_array_elements(trace.telemetry_baseline) b where b->>'id'=e.id::text))<>10 then
    raise exception 'Unexpected synthetic phase telemetry counts; cleanup refused'; end if;
end $$;
select 'NOTIFICATION_SESSION_UPGRADE_TRACE:'||jsonb_build_object('phase','verify',
  'seed_xid',trace.seed_xid,'migration_xid',trace.migration_xid,'verify_xid',trace.verify_xid,
  'events',(select jsonb_agg(jsonb_build_object('row',to_jsonb(e),'xmin',e.xmin::text) order by e.id)
    from public.app_realtime_events e where not exists(select 1 from jsonb_array_elements(trace.telemetry_baseline) b where b->>'id'=e.id::text)),
  'disposition','exact synthetic events removed in this transaction')::text
from pg_temp.notification_upgrade_telemetry_trace trace;
delete from public.app_realtime_events e using pg_temp.notification_upgrade_telemetry_trace trace
where e.xmin::text in (trace.seed_xid,trace.migration_xid,trace.verify_xid)
  and not exists(select 1 from jsonb_array_elements(trace.telemetry_baseline) b where b->>'id'=e.id::text);
do $$ begin
  if (select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]'::jsonb) from public.app_realtime_events e)
    is distinct from (select telemetry_baseline from pg_temp.notification_upgrade_telemetry_trace) then
    raise exception 'Exact telemetry baseline not restored; verify transaction rolled back'; end if;
end $$;
drop table public.notification_session_upgrade_qa;
select 'NOTIFICATION_SESSION_UPGRADE_PASS' as result;
commit;
