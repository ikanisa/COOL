\set ON_ERROR_STOP on
-- Run ONLY on a root-verified isolated local clone with:
-- PGOPTIONS='-c collect.notification_qa=isolated_clone' psql ... -f this_file
-- Every write, including synthetic Auth users, rolls back. No provider calls.
begin;
set local statement_timeout = '30s';
set local lock_timeout = '5s';
do $$ begin
  if current_setting('collect.notification_qa', true) is distinct from 'isolated_clone'
    or current_database() <> 'postgres'
    or (select count(*) from supabase_migrations.schema_migrations) <> 141
    or (select max(version) from supabase_migrations.schema_migrations) <> '20260929180000'
    or exists (select 1 from public.notification_deliveries)
    or exists (select 1 from public.notification_device_tokens)
    or exists (select 1 from auth.users where id::text like '99870000-%')
    or to_regprocedure('public.notification_delivery_is_current(uuid,uuid,integer)') is null
    or to_regprocedure('public.claim_notification_deliveries(integer)') is not null
    or to_regprocedure('public.complete_notification_delivery(uuid,boolean,boolean,text,text,integer)') is not null then
    raise exception 'Verified isolated clone with empty push queue and fencing migration required';
  end if;
end $$;
create temp table notification_test_results(label text primary key);
create function pg_temp.notification_assert(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.notification_test_results values(label);
end $$;

insert into auth.users(id, aud, role, phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data)
values ('99870000-0000-4000-8000-000000000001','authenticated','authenticated','250788907001',now(),'{}','{}'),
       ('99870000-0000-4000-8000-000000000002','authenticated','authenticated','250788907002',now(),'{}','{}'),
       ('99870000-0000-4000-8000-000000000003','authenticated','authenticated','250788907003',now(),'{}','{}');
update public.profiles set country_code='RW', currency_code='RWF'
where id in ('99870000-0000-4000-8000-000000000001','99870000-0000-4000-8000-000000000002','99870000-0000-4000-8000-000000000003');

insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values ('99870000-0000-4000-8000-000000000101','99870000-0000-4000-8000-000000000001',now()-interval '10 minutes',now(),now()+interval '1 hour','aal1'),
       ('99870000-0000-4000-8000-000000000102','99870000-0000-4000-8000-000000000002',now()-interval '8 minutes',now(),now()+interval '1 hour','aal1');

create function pg_temp.notification_seed() returns void language plpgsql as $$
begin
  delete from public.notification_events where user_id in
    ('99870000-0000-4000-8000-000000000001','99870000-0000-4000-8000-000000000002');
  delete from public.notification_device_tokens where id='99870000-0000-4000-8000-000000000010';
  insert into public.notification_device_tokens(id,user_id,platform,provider,token,token_hash,environment,registration_session_id,registration_session_created_at)
  values ('99870000-0000-4000-8000-000000000010','99870000-0000-4000-8000-000000000001',
    'android','fcm','synthetic-notification-token-907001',
    encode(extensions.digest('synthetic-notification-token-907001','sha256'),'hex'),'production','99870000-0000-4000-8000-000000000101',
    (select created_at from auth.sessions where id='99870000-0000-4000-8000-000000000101'));
  insert into public.notification_events(id,user_id,type,title,body)
  values ('99870000-0000-4000-8000-000000000020','99870000-0000-4000-8000-000000000001',
    'group_update','Synthetic QA','Rollback-only notification fixture.');
end $$;

select pg_temp.notification_assert(
  not has_table_privilege('authenticated','public.notification_device_tokens','INSERT,UPDATE,DELETE,TRUNCATE')
  and not has_table_privilege('anon','public.notification_device_tokens','INSERT,UPDATE,DELETE,TRUNCATE'),
  'API users cannot bypass registration with direct token mutations or delete/reinsert');

select pg_temp.notification_assert(
  not has_function_privilege('authenticated','public.claim_notification_deliveries(integer,integer)','EXECUTE')
  and not has_function_privilege('anon','public.notification_delivery_is_current(uuid,uuid,integer)','EXECUTE')
  and not has_function_privilege('authenticated','public.complete_notification_delivery(uuid,uuid,integer,boolean,boolean,text,text,integer,integer)','EXECUTE')
  and has_function_privilege('service_role','public.complete_notification_delivery(uuid,uuid,integer,boolean,boolean,text,text,integer,integer)','EXECUTE'),
  'claim validation and fenced completion are service-only');

select pg_temp.notification_seed();
do $$ declare refused boolean := false; begin
  begin execute 'select * from public.claim_notification_deliveries(p_limit => 1)';
  exception when undefined_function then refused := true; end;
  perform pg_temp.notification_assert(refused and not exists (select 1 from public.notification_deliveries where status='processing'),
    'legacy dispatcher cannot claim before sending without a contract version');
  refused := false;
  begin execute 'select * from public.claim_notification_deliveries(1)';
  exception when undefined_function then refused := true; end;
  perform pg_temp.notification_assert(refused and not exists (select 1 from public.notification_deliveries where status='processing'),
    'legacy positional one-argument claim is rejected');
  refused := false;
  begin perform * from public.claim_notification_deliveries(99,1);
  exception when others then
    if sqlerrm <> 'notification_claim_contract_unsupported' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'unsupported claim contract is rejected');
  refused := false;
  begin perform * from public.claim_notification_deliveries(1,1);
  exception when others then
    if sqlerrm <> 'notification_claim_contract_unsupported' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'protocol1 claim is rejected before provider work');
end $$;
do $$ declare lease record; refused boolean; begin
  select * into strict lease from public.claim_notification_deliveries(2,1);
  perform pg_temp.notification_assert(lease.user_id='99870000-0000-4000-8000-000000000001'::uuid
    and lease.title='Collect' and lease.body='Open Collect to view your updates', 'protocol2 claim contains bound recipient and generic preview');
  perform pg_temp.notification_assert(lease.claim_token is not null and lease.attempt_number=1
    and public.notification_delivery_is_current(lease.delivery_id,lease.claim_token,1),
    'new claim has an active owner-bound fence');
  refused := false;
  begin perform public.complete_notification_delivery(lease.delivery_id,gen_random_uuid(),1,true);
  exception when others then
    if sqlerrm <> 'notification_delivery_fence_lost' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'wrong claim token is rejected');
  refused := false;
  begin perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,2,true);
  exception when others then
    if sqlerrm <> 'notification_delivery_fence_lost' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'wrong attempt number is rejected');
  update public.notification_deliveries set claim_expires_at=clock_timestamp()+interval '15 seconds'
    where id=lease.delivery_id;
  perform pg_temp.notification_assert(not public.notification_delivery_is_current(lease.delivery_id,lease.claim_token,1),
    'preflight refuses a lease without a full provider time budget');
  update public.notification_deliveries set claim_expires_at=clock_timestamp()+interval '5 minutes'
    where id=lease.delivery_id;
  perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,1,true,false,'synthetic-provider-id');
  perform pg_temp.notification_assert((select status='sent' and claim_token is null from public.notification_deliveries where id=lease.delivery_id)
    and (select count(*)=1 from public.notification_delivery_attempts where delivery_id=lease.delivery_id)
    and (select status='sent' from public.notification_events where id=lease.event_id),
    'correct fence records one accepted send and updates event state');
  refused := false;
  begin perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,1,false,true);
  exception when others then
    if sqlerrm <> 'notification_delivery_fence_lost' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused and (select status='sent' from public.notification_deliveries where id=lease.delivery_id),
    'duplicate completion cannot downgrade accepted send');
end $$;

select pg_temp.notification_seed();
do $$ declare lease record; n integer; begin
  for n in 1..5 loop
    select * into strict lease from public.claim_notification_deliveries(2,1);
    perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,n,false,true,null,'http_503');
    if n < 5 then
      perform pg_temp.notification_assert((select status='queued' and next_attempt_at > clock_timestamp()+interval '50 seconds'
        from public.notification_deliveries where id=lease.delivery_id), 'retry has bounded backoff attempt '||n);
      update public.notification_deliveries set next_attempt_at=clock_timestamp()-interval '1 second' where id=lease.delivery_id;
    end if;
  end loop;
  perform pg_temp.notification_assert((select status='failed' from public.notification_deliveries where id=lease.delivery_id)
    and (select count(*)=5 from public.notification_delivery_attempts where delivery_id=lease.delivery_id)
    and (select status='failed' from public.notification_events where id=lease.event_id),
    'fifth provider failure is terminal with preserved attempt history');
end $$;

select pg_temp.notification_seed();
do $$ declare original record; replacement record; refused boolean; begin
  select * into strict original from public.claim_notification_deliveries(2,1);
  update public.notification_deliveries set claim_expires_at=clock_timestamp()-interval '1 second' where id=original.delivery_id;
  perform pg_temp.notification_assert((select count(*)=0 from public.claim_notification_deliveries(2,1)),
    'expired claim recovery honors backoff instead of sending immediately');
  perform pg_temp.notification_assert((select status='queued' and last_error_code='claim_timeout' and claim_token is null
    from public.notification_deliveries where id=original.delivery_id), 'expired first claim becomes a recorded retry');
  update public.notification_deliveries set next_attempt_at=clock_timestamp()-interval '1 second' where id=original.delivery_id;
  select * into strict replacement from public.claim_notification_deliveries(2,1);
  perform pg_temp.notification_assert(replacement.claim_token<>original.claim_token and replacement.attempt_number=2,
    'replacement claim has a new token and incremented attempt');
  refused := false;
  begin perform public.complete_notification_delivery(original.delivery_id,original.claim_token,original.attempt_number,true);
  exception when others then
    if sqlerrm <> 'notification_delivery_fence_lost' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused and public.notification_delivery_is_current(replacement.delivery_id,replacement.claim_token,2),
    'stale worker cannot complete a replacement worker claim');
  perform public.complete_notification_delivery(replacement.delivery_id,replacement.claim_token,2,true);
end $$;

select pg_temp.notification_seed();
do $$ declare lease record; begin
  select * into strict lease from public.claim_notification_deliveries(2,1);
  update public.notification_deliveries set attempt_count=5,claim_expires_at=clock_timestamp()-interval '1 second'
    where id=lease.delivery_id;
  perform pg_temp.notification_assert((select count(*)=0 from public.claim_notification_deliveries(2,1)),
    'expired fifth claim cannot be sent again');
  perform pg_temp.notification_assert((select status='failed' and last_error_code='attempts_exhausted'
    from public.notification_deliveries where id=lease.delivery_id)
    and (select status='failed' from public.notification_events where id=lease.event_id),
    'expired fifth claim reaches terminal failed state');
end $$;

select pg_temp.notification_seed();
update public.notification_deliveries set attempt_count=5;
do $$ begin
  perform * from public.claim_notification_deliveries(2,1);
  perform pg_temp.notification_assert((select count(*)=1 from public.notification_deliveries
    where status='failed' and last_error_code='attempts_exhausted'),
    'legacy queued exhausted delivery is terminalized');
end $$;

select pg_temp.notification_seed();
do $$ declare old_lease record; new_lease record; refused boolean; begin
  select * into strict old_lease from public.claim_notification_deliveries(2,1);
  perform set_config('request.jwt.claim.sub','99870000-0000-4000-8000-000000000002',true);
  perform set_config('request.jwt.claims','{"sub":"99870000-0000-4000-8000-000000000002","role":"authenticated","session_id":"99870000-0000-4000-8000-000000000102","aal":"aal1"}',true);
  refused := false;
  begin perform public.register_notification_device('android','fcm','synthetic-notification-token-907001');
  exception when others then
    if sqlerrm <> 'notification_device_in_flight' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused and (select user_id='99870000-0000-4000-8000-000000000001'
    from public.notification_device_tokens where id=old_lease.device_id),
    'token reassignment is blocked during a live claim');
  update public.notification_deliveries set claim_expires_at=clock_timestamp()-interval '1 second' where id=old_lease.delivery_id;
  perform public.register_notification_device('android','fcm','synthetic-notification-token-907001');
  perform pg_temp.notification_assert((select status='failed' from public.notification_deliveries where id=old_lease.delivery_id)
    and not public.notification_delivery_is_current(old_lease.delivery_id,old_lease.claim_token,1),
    'safe reassignment cancels old-owner delivery after lease expiry');
  insert into public.notification_events(id,user_id,type,title,body)
  values ('99870000-0000-4000-8000-000000000021','99870000-0000-4000-8000-000000000002',
    'group_update','Synthetic new owner','Only the new owner event can be claimed.');
  select * into strict new_lease from public.claim_notification_deliveries(2,1);
  perform pg_temp.notification_assert(new_lease.event_id='99870000-0000-4000-8000-000000000021',
    'reassigned token receives only its current owner event');
  perform public.complete_notification_delivery(new_lease.delivery_id,new_lease.claim_token,1,true);
end $$;

select pg_temp.notification_seed();
do $$ declare lease record; refused boolean; begin
  select * into strict lease from public.claim_notification_deliveries(2,1);
  perform set_config('request.jwt.claim.sub','99870000-0000-4000-8000-000000000001',true);
  perform set_config('request.jwt.claims','{"sub":"99870000-0000-4000-8000-000000000001","role":"authenticated","session_id":"99870000-0000-4000-8000-000000000101","aal":"aal1"}',true);
  perform public.unregister_notification_device('fcm','synthetic-notification-token-907001');
  perform pg_temp.notification_assert(not public.notification_delivery_is_current(lease.delivery_id,lease.claim_token,1)
    and (select status='failed' and claim_expires_at>clock_timestamp()
      from public.notification_deliveries where id=lease.delivery_id),
    'sign-out cancels pending send while retaining reassignment fence');
  perform set_config('request.jwt.claim.sub','99870000-0000-4000-8000-000000000002',true);
  perform set_config('request.jwt.claims','{"sub":"99870000-0000-4000-8000-000000000002","role":"authenticated","session_id":"99870000-0000-4000-8000-000000000102","aal":"aal1"}',true);
  refused := false;
  begin perform public.register_notification_device('android','fcm','synthetic-notification-token-907001');
  exception when others then
    if sqlerrm <> 'notification_device_in_flight' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'sign-out cannot bypass active token reassignment fence');
end $$;

select pg_temp.notification_seed();
-- Simulate a pre-migration queued delivery attached to somebody else's token.
update public.notification_events set user_id='99870000-0000-4000-8000-000000000002'
where id='99870000-0000-4000-8000-000000000020';
do $$ begin
  perform * from public.claim_notification_deliveries(2,1);
  perform pg_temp.notification_assert((select count(*)=1 from public.notification_deliveries
    where status='failed' and last_error_code='device_owner_changed'),
    'legacy wrong-owner delivery cannot be claimed');
end $$;

select pg_temp.notification_seed();
do $$ declare lease record; begin
  select * into strict lease from public.claim_notification_deliveries(2,1);
  perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,1,false,false,null,'UNREGISTERED');
  perform pg_temp.notification_assert((select not enabled from public.notification_device_tokens where id=lease.device_id)
    and (select status='failed' from public.notification_deliveries where id=lease.delivery_id),
    'invalid provider token disables its device and fails the delivery');
end $$;

-- Seed an approved synthetic operator, including a post-approval Auth session.
-- No existing operator roles, identities, sessions or approvals are changed.
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99870000-0000-4000-8000-000000000003',role.id,'Synthetic notification retry QA',now()-interval '5 seconds'
from public.admin_roles role where role.name='platform_owner';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,approved_by,reason)
values ('99870000-0000-4000-8000-000000000003','+250788907003',now()-interval '4 seconds',
  '99870000-0000-4000-8000-000000000003','Synthetic notification retry QA');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
values ('99870000-0000-4000-8000-000000000901','99870000-0000-4000-8000-000000000003',
  now()-interval '3 seconds',now(),now()+interval '1 hour');
grant all on pg_temp.notification_test_results to authenticated;

select pg_temp.notification_seed();
do $$ declare lease record; begin
  select * into strict lease from public.claim_notification_deliveries(2,1);
  perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,1,false,false,null,'http_400');
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','99870000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"99870000-0000-4000-8000-000000000003","role":"authenticated","session_id":"99870000-0000-4000-8000-000000000901"}',true);
do $$ declare result jsonb; refused boolean := false; begin
  result := public.admin_get_notification('99870000-0000-4000-8000-000000000020');
  perform pg_temp.notification_assert((result->>'retryable_count')::integer=1
    and (result->>'cumulative_attempt_count')::integer=1,
    'approved Admin sees one eligible failed attempt');
  begin perform public.admin_retry_notification('99870000-0000-4000-8000-000000000020','  ');
  exception when others then
    if sqlerrm <> 'Reason is required' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'Admin retry still requires a nonempty reason');
  result := public.admin_retry_notification('99870000-0000-4000-8000-000000000020','Synthetic approved retry');
  perform pg_temp.notification_assert(result->>'ok'='true' and (result->>'delivery_count')::integer=1,
    'approved authenticated Admin retries exactly one eligible delivery');
  result := public.admin_get_notification('99870000-0000-4000-8000-000000000020');
  perform pg_temp.notification_assert((result->>'retryable_count')::integer=0
    and (result->>'cumulative_attempt_count')::integer=1 and result->>'status'='queued',
    'retried delivery leaves failed count while preserving cumulative history');
end $$;
reset role;
select pg_temp.notification_assert((select count(*)=1 from public.audit_logs
  where actor_user_id='99870000-0000-4000-8000-000000000003'
    and action='notification.delivery.retried' and entity_id='99870000-0000-4000-8000-000000000020'
    and metadata->>'reason'='Synthetic approved retry' and (metadata->>'delivery_count')::integer=1),
  'permissioned retry records actor reason and delivery count in audit log');
do $$ declare lease record; begin
  select * into strict lease from public.claim_notification_deliveries(2,1);
  perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,1,true);
  perform pg_temp.notification_assert((select array_agg(attempt_number order by attempt_number)=array[1,2]
    from public.notification_delivery_attempts where delivery_id=lease.delivery_id),
    'actual operator retry appends cumulative attempts without collision');
end $$;

create function pg_temp.notification_assert_ineligible(label text) returns void language plpgsql as $$
declare refused boolean := false; result jsonb;
begin
  result := public.admin_get_notification('99870000-0000-4000-8000-000000000020');
  perform pg_temp.notification_assert((result->>'retryable_count')::integer=0,
    label || ' is excluded from Admin retryable count');
  begin perform public.admin_retry_notification('99870000-0000-4000-8000-000000000020','Synthetic forbidden retry');
  exception when others then
    if sqlerrm <> 'No retryable failed deliveries' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, label || ' is rejected by actual Admin retry');
end $$;

select pg_temp.notification_seed();
update public.notification_deliveries set status='failed';
update public.notification_device_tokens set user_id='99870000-0000-4000-8000-000000000002'
where id='99870000-0000-4000-8000-000000000010';
set local role authenticated;
select pg_temp.notification_assert_ineligible('Wrong-owner token');
reset role;

select pg_temp.notification_seed();
update public.notification_deliveries set status='failed';
update public.notification_device_tokens set enabled=false
where id='99870000-0000-4000-8000-000000000010';
set local role authenticated;
select pg_temp.notification_assert_ineligible('Disabled token');
reset role;

select pg_temp.notification_seed();
update public.notification_deliveries set status='failed';
update public.notification_device_tokens set provider='legacy_local'
where id='99870000-0000-4000-8000-000000000010';
set local role authenticated;
select pg_temp.notification_assert_ineligible('Unsupported transport');
reset role;

select pg_temp.notification_seed();
update public.notification_deliveries set status='failed';
update public.notification_device_tokens set token=null
where id='99870000-0000-4000-8000-000000000010';
set local role authenticated;
select pg_temp.notification_assert_ineligible('Missing provider token');
reset role;

select pg_temp.notification_seed();
select * from public.claim_notification_deliveries(2,1);
-- Device disable cancels the claim but retains its live lease. Re-enabling the
-- same identity must not let an operator bypass the still-running worker fence.
update public.notification_device_tokens set enabled=false
where id='99870000-0000-4000-8000-000000000010';
update public.notification_device_tokens set enabled=true
where id='99870000-0000-4000-8000-000000000010';
set local role authenticated;
select pg_temp.notification_assert_ineligible('Canceled but unexpired claim');
reset role;
update public.notification_deliveries set claim_expires_at=clock_timestamp()-interval '1 second';
set local role authenticated;
do $$ declare result jsonb; begin
  result := public.admin_get_notification('99870000-0000-4000-8000-000000000020');
  perform pg_temp.notification_assert((result->>'retryable_count')::integer=1,
    'expired canceled claim becomes eligible in the Admin view');
  result := public.admin_retry_notification('99870000-0000-4000-8000-000000000020','Synthetic canceled claim recovery');
  perform pg_temp.notification_assert(result->>'ok'='true' and (result->>'delivery_count')::integer=1,
    'actual Admin action recovers an expired canceled claim');
end $$;
reset role;
select pg_temp.notification_assert((select count(*)=1 from public.notification_deliveries
  where status='queued' and attempt_count=0 and prior_attempt_count=1
    and claim_token is null and claim_expires_at is null and claim_user_id is null),
  'Admin recovery clears canceled fence and retains prior attempt count');
select pg_temp.notification_assert(not exists (select 1 from public.audit_logs
  where actor_user_id='99870000-0000-4000-8000-000000000003'
    and metadata->>'reason'='Synthetic forbidden retry'),
  'ineligible retries do not create success audit records');

-- A confirmed member without an approved platform role cannot use either RPC.
set local role authenticated;
select set_config('request.jwt.claim.sub','99870000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99870000-0000-4000-8000-000000000001","role":"authenticated","session_id":"99870000-0000-4000-8000-000000000101","aal":"aal1"}',true);
do $$ declare refused boolean := false; begin
  begin perform public.admin_get_notification('99870000-0000-4000-8000-000000000020');
  exception when others then
    if sqlerrm <> 'Admin permission notifications.read required' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'ordinary member cannot read Admin notification details');
  refused := false;
  begin perform public.admin_retry_notification('99870000-0000-4000-8000-000000000020','Synthetic unauthorized retry');
  exception when others then
    if sqlerrm <> 'Admin permission notifications.manage required' then raise; end if; refused := true; end;
  perform pg_temp.notification_assert(refused, 'ordinary member cannot invoke Admin retry');
end $$;
reset role;

-- Retry floors are persisted; jitter cannot advance a provider's instruction.
select pg_temp.notification_seed();
do $$ declare lease record; delay integer; samples integer[] := '{}'; begin
  for n in 1..64 loop
    delay := public._notification_retry_delay(1, 900);
    if delay < 900 or delay > 1125 then raise exception 'retry jitter out of bounds'; end if;
    samples := array_append(samples,delay);
  end loop;
  perform pg_temp.notification_assert((select count(distinct value)>1 from unnest(samples) value), 'bounded jitter produces independently varied delays');
  perform pg_temp.notification_assert(public._notification_retry_delay(1,3600)=3600, 'maximum provider floor cannot be exceeded or shortened');
  select * into strict lease from public.claim_notification_deliveries(2,1);
  perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,1,false,true,null,'http_503',10,900);
  perform pg_temp.notification_assert((select next_attempt_at >= clock_timestamp()+interval '899 seconds'
    and next_attempt_at <= clock_timestamp()+interval '1126 seconds' and status='queued'
    from public.notification_deliveries where id=lease.delivery_id), 'completion persists APNs900 second floor with bounded jitter');
  update public.notification_deliveries set next_attempt_at=clock_timestamp()-interval '1 second' where id=lease.delivery_id;
  select * into strict lease from public.claim_notification_deliveries(2,1);
  perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,2,false,true,null,'http_429',10,3601);
  perform pg_temp.notification_assert((select status='failed' and last_error_code='retry_after_exceeds_budget'
    from public.notification_deliveries where id=lease.delivery_id), 'excessive provider wait is terminal instead of retrying too soon');
end $$;
select pg_temp.notification_assert((select count(*)=1 and bool_and(not active)
  and bool_and(schedule='* * * * *') and bool_and(command='select public.run_notification_dispatch_schedule();')
  from cron.job where jobname='collect-dispatch-notifications'), 'recurring scheduler source exists but starts inactive without configuration');
select pg_temp.notification_assert(not has_function_privilege('service_role','public._notification_dispatch_configuration()','EXECUTE')
  and not has_function_privilege('authenticated','public.run_notification_dispatch_schedule()','EXECUTE')
  and not has_function_privilege('service_role','public.configure_notification_dispatch_schedule(boolean)','EXECUTE'),
  'scheduler secrets and activation are trusted database-owner only');

select pg_temp.notification_seed();
update public.notification_deliveries set status='failed';
update auth.sessions set not_after=clock_timestamp()+interval '100 milliseconds'
where id='99870000-0000-4000-8000-000000000101';
select pg_sleep(0.15);
set local role authenticated;
select set_config('request.jwt.claim.sub','99870000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"99870000-0000-4000-8000-000000000003","role":"authenticated","session_id":"99870000-0000-4000-8000-000000000901"}',true);
select pg_temp.notification_assert_ineligible('Elapsed registration session');
reset role;

select 'NOTIFICATION_DELIVERY_SESSIONS_UAT_PASS' as result, count(*) as assertions
from pg_temp.notification_test_results;
rollback;
