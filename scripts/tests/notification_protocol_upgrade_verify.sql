\set ON_ERROR_STOP on
begin;
do $$ declare old_lease record; refused boolean := false; begin
  if current_setting('collect.notification_qa', true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs') <> 'off'
    or current_setting('pg_net.batch_size') <> '0'
    or (select count(*) from supabase_migrations.schema_migrations) <> 139
    or (select max(version) from supabase_migrations.schema_migrations) <> '20260929160000' then
    raise exception 'Guarded synthetic139 fixture required';
  end if;
  select * into strict old_lease from public.notification_protocol_upgrade_qa;
  if public.notification_delivery_is_current(old_lease.delivery_id,old_lease.claim_token,old_lease.attempt_number) then
    raise exception 'Old live claim still passes preflight'; end if;
  begin perform public.complete_notification_delivery(old_lease.delivery_id,old_lease.claim_token,old_lease.attempt_number,true);
  exception when others then
    if sqlerrm <> 'notification_delivery_fence_lost' then raise; end if; refused:=true; end;
  if not refused then raise exception 'Old live claim can complete'; end if;
  if not exists(select 1 from public.notification_deliveries where id=old_lease.delivery_id
    and status='queued' and claim_token<>old_lease.claim_token and claim_expires_at=old_lease.expires_at
    and next_attempt_at>=old_lease.expires_at and attempt_count=old_lease.attempt_number) then
    raise exception 'Old lease wait or attempt budget was lost'; end if;
  if not exists(select 1 from public.notification_delivery_attempts where delivery_id=old_lease.delivery_id
    and attempt_number=old_lease.attempt_number and outcome='retry' and error_code='claim_protocol_upgraded') then
    raise exception 'Upgrade attempt evidence missing'; end if;
  if exists(select 1 from public.claim_notification_deliveries(2,1)) then
    raise exception 'New worker claimed before old lease expiry'; end if;
  if not exists(select 1 from public.notification_events where id='99890000-0000-4000-8000-000000000020'
    and title='Private synthetic title' and body='Private synthetic body') then
    raise exception 'Authorized in-app content was changed'; end if;
end $$;
select 'NOTIFICATION_PROTOCOL_UPGRADE_PASS' as result;
-- Remove only this exact synthetic graph after all checks pass.
delete from public.notification_events where id='99890000-0000-4000-8000-000000000020';
delete from public.notification_device_tokens where id='99890000-0000-4000-8000-000000000010';
delete from auth.users where id='99890000-0000-4000-8000-000000000001';
do $$ declare fk record; referenced boolean; member_ids uuid[]:=ARRAY['99890000-0000-4000-8000-000000000001']::uuid[]; begin
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
drop table public.notification_protocol_upgrade_qa;
commit;
