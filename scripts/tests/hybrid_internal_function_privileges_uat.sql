\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';

do $$ begin
  if coalesce(current_setting('collect.recovery_drill', true), '')
       <> 'production-archive-v1'
     and current_database() <> 'collect_hybrid_privilege_uat_20260903' then
    raise exception 'Isolated hybrid privilege UAT database required';
  end if;
end $$;

create temp table test_results(label text primary key);
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end;
$$;
create function pg_temp.expect_error(command text, fragment text, label text)
returns void language plpgsql as $$
declare caught text;
begin
  begin execute command; exception when others then caught := sqlerrm; end;
  perform pg_temp.assert_true(
    caught is not null and position(fragment in caught) > 0,
    label
  );
end;
$$;
grant select, insert on pg_temp.test_results to authenticated;
grant execute on function pg_temp.assert_true(boolean, text) to authenticated;
grant execute on function pg_temp.expect_error(text, text, text) to authenticated;

select pg_temp.assert_true(
  not has_function_privilege('public',
    'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute')
  and not has_function_privilege('anon',
    'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute')
  and not has_function_privilege('authenticated',
    'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute')
  and not has_function_privilege('service_role',
    'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute'),
  'SMS outbox trigger helper has no direct caller grant'
);

select pg_temp.assert_true(
  not has_function_privilege('public',
    'collect_hybrid.claim_verified_current_account()', 'execute')
  and not has_function_privilege('anon',
    'collect_hybrid.claim_verified_current_account()', 'execute')
  and not has_function_privilege('authenticated',
    'collect_hybrid.claim_verified_current_account()', 'execute')
  and not has_function_privilege('service_role',
    'collect_hybrid.claim_verified_current_account()', 'execute'),
  'internal account claim implementation has no direct caller grant'
);

select pg_temp.assert_true(
  has_function_privilege('authenticated',
    'public.claim_verified_current_account()', 'execute')
  and not has_function_privilege('anon',
    'public.claim_verified_current_account()', 'execute'),
  'authenticated account claim remains available only through public wrapper'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
set local role authenticated;
select pg_temp.expect_error(
  'select public.claim_verified_current_account()',
  'Verified offline-member account claiming is disabled',
  'public wrapper reaches guarded internal claim without a direct private grant'
);
reset role;

select pg_temp.assert_true(
  not exists (
    select 1
    from information_schema.routine_privileges grant_row
    where grant_row.specific_schema = 'collect_hybrid'
      and grant_row.grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  'collect_hybrid exposes no routines to client or service roles'
);

select label from pg_temp.test_results order by label;
select 'HYBRID_INTERNAL_FUNCTION_PRIVILEGES_UAT_PASS: '
  || count(*) || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
