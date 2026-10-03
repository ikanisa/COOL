#!/usr/bin/env python3
"""Exact-current migration replay and real originating-session lock races.

Only a uniquely labelled network-none cached-image container is created. No
database URL, source row, hosted credential, scheduler or provider is accepted.
Auth is a row-free platform shape; signed Auth/provider runtime is separate.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import time
import types
import uuid

ROOT = Path(__file__).resolve().parents[2]
ACTOR = '99440000-0000-4000-8000-000000000001'
SID = '99440000-0000-4000-8000-000000000011'
OTHER_SID = '99440000-0000-4000-8000-000000000012'
SQL_FILE = ROOT / 'scripts/tests/assisted_sms_session_fencing_uat.sql'
HELPER = ROOT / 'scripts/tests/collect_current_release_upgrade_uat.py'
BASELINE = ROOT / '.cache/receipt-foundation-attempt8/schema-only.sql'
PLATFORM_PREREQUISITE = ROOT / 'scripts/sql/receipt_transport_platform_prerequisites.sql'
LOCAL_NET_METADATA = (
    'alter function net.http_get(text,jsonb,jsonb,integer)security definer;'
    'alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;'
    'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;'
    'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;'
)
OWNED = [Path(__file__), SQL_FILE, HELPER, BASELINE, PLATFORM_PREREQUISITE,
         ROOT / 'supabase/functions/_shared/notification_operator.ts',
         ROOT / 'supabase/functions/_shared/notification_operator_test.ts',
         ROOT / 'supabase/functions/collect-notification-operator/index.ts',
         ROOT / 'supabase/functions/_shared/roster_provenance.ts',
         ROOT / 'scripts/hardening/edge_http.test.cjs',
         ROOT / 'scripts/qa/edge_http_runtime_uat.ts']

# System catalogs only: no application, Auth or storage row data is exported.
CATALOG_SQL = r"""with scopes as (
 select oid,nspname,nspowner,nspacl from pg_namespace
 where nspname in('public','auth','storage','extensions','net','supabase_migrations')or nspname like 'collect\_%'escape '\'
), relations as (
 select c.* from pg_class c join scopes n on n.oid=c.relnamespace
 where c.relkind in('r','p','v','m','S','f')
), functions as (
 select p.* from pg_proc p join scopes n on n.oid=p.pronamespace
)
select jsonb_build_object(
 'schemas',(select coalesce(jsonb_agg(jsonb_build_object('schema',nspname,'owner',pg_get_userbyid(nspowner),
  'acl',nspacl,'effective_acl',coalesce(nspacl,acldefault('n',nspowner)))order by nspname),'[]')from scopes),
 'relations',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind,
  'owner',pg_get_userbyid(c.relowner),'row_security',c.relrowsecurity,'force_row_security',c.relforcerowsecurity,
  'acl',c.relacl,'effective_acl',coalesce(c.relacl,acldefault(case when c.relkind='S'then 's'else 'r'end::"char",c.relowner)))
  order by n.nspname,c.relname),'[]')from relations c join scopes n on n.oid=c.relnamespace),
 'functions',(select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'schema',n.nspname,
  'name',p.proname,'kind',p.prokind,'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,
  'configuration',p.proconfig,'acl',p.proacl,'effective_acl',coalesce(p.proacl,acldefault('f',p.proowner)),
  'language',l.lanname,'return_type',pg_get_function_result(p.oid),
  'definition',case when p.prokind in('f','p')and(n.nspname='public'or n.nspname like 'collect\_%'escape '\')then pg_get_functiondef(p.oid)end)
  order by n.nspname,p.proname,p.oid::regprocedure::text),'[]')from functions p join scopes n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang),
 'column_acl',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'column',a.attname,
  'owner',pg_get_userbyid(c.relowner),'acl',a.attacl)order by n.nspname,c.relname,a.attnum),'[]')
  from pg_attribute a join relations c on c.oid=a.attrelid join scopes n on n.oid=c.relnamespace where a.attnum>0 and not a.attisdropped and a.attacl is not null),
 'default_acl',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'owner',pg_get_userbyid(d.defaclrole),
  'object_kind',d.defaclobjtype,'acl',d.defaclacl)order by coalesce(n.nspname,''),d.defaclrole,d.defaclobjtype),'[]')
  from pg_default_acl d left join scopes n on n.oid=d.defaclnamespace where d.defaclnamespace=0 or n.oid is not null),
 'policies',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',p.polname,
  'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles,'using',pg_get_expr(p.polqual,p.polrelid),
  'with_check',pg_get_expr(p.polwithcheck,p.polrelid))order by n.nspname,c.relname,p.polname),'[]')
  from pg_policy p join relations c on c.oid=p.polrelid join scopes n on n.oid=c.relnamespace),
 'platform_normalized',true,'hosted_schema_observed',false,'table_row_data_exported',false);"""


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True, type=Path)
    args = parser.parse_args()
    report = args.report_dir.resolve()
    if not report.is_relative_to(ROOT / 'docs/release') or report.exists():
        parser.error('A fresh evidence directory under repository docs/release is required')
    report.mkdir(parents=True)
    captured = report / 'captured-source'
    captured.mkdir()
    paths = [*OWNED, *sorted((ROOT / 'supabase/migrations').glob('*.sql'))]
    before = {}
    for path in paths:
        body = path.read_bytes()
        relative = str(path.relative_to(ROOT))
        target = captured / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
        before[relative] = sha(body)
    helper = types.ModuleType('captured_release_helper')
    helper.__file__ = str(captured / HELPER.relative_to(ROOT))
    exec(compile((captured / HELPER.relative_to(ROOT)).read_bytes(), helper.__file__, 'exec'), helper.__dict__)
    helper.ROOT = ROOT
    helper.BASELINE = captured / BASELINE.relative_to(ROOT)
    items = []
    for path in sorted((captured / 'supabase/migrations').glob('*.sql')):
        version, name = path.stem.split('_', 1)
        data = path.read_bytes()
        items.append(dict(path='supabase/migrations/' + path.name, version=version,
                          name=name, body=data.decode(), sha256=sha(data)))
    if len({item['version'] for item in items}) != len(items):
        raise RuntimeError('Duplicate migration versions')
    result = dict(status='running', started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  scope='Exact captured application migrations; synthetic SQL authority and real lock order UAT',
                  migrations=len(items), source_hashes=before, cases=[], target={},
                  hosted_written=False, shared_database_written=False, provider_called=False,
                  source_rows_copied=False, signed_auth_runtime_tested=False, final_acceptance=False)
    target = None

    def save():
        (report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')

    def case(name, ok, **details):
        result['cases'].append(dict(name=name, status='pass' if ok else 'fail', **details))
        save()
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        if not ok:
            raise AssertionError(name)

    q = helper.quoted
    claims = "set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"

    def heartbeat(run):
        return "select public.collect_worker_heartbeat_v2(" + ','.join([
            q(ACTOR), q(SID), "'assisted-race'", q(run), "'no_send'", "'{}'"]) + ');'

    def reset_actor():
        target.sql("""begin;
insert into auth.users(id,aud,role,email,email_confirmed_at,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values(%s,'authenticated','authenticated','assisted-owner@example.test',clock_timestamp(),'250788994401',clock_timestamp(),'{}','{}')
on conflict(id)do update set deleted_at=null,banned_until=null,is_anonymous=false,email_confirmed_at=clock_timestamp();
insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
values(%s,'assisted-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic originating-session race')
on conflict(user_id)do update set revoked_at=null,expires_at=null,approved_at=clock_timestamp()-interval '2 minutes';
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select %s,id,'Synthetic originating-session role',clock_timestamp()-interval '1 minute'from public.admin_roles
where name='platform_owner'and not exists(select 1 from public.admin_user_roles where user_id=%s and role_id=public.admin_roles.id);
update public.admin_user_roles set revoked_at=null,created_at=clock_timestamp()-interval '1 minute'where user_id=%s;
insert into public.admin_role_permissions(role_id,permission_name)
select id,p from public.admin_roles cross join unnest(array['notifications.read','notifications.manage'])p where name='platform_owner'on conflict do nothing;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values
(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1')
on conflict(id)do update set created_at=clock_timestamp(),not_after=clock_timestamp()+interval '1 hour',aal='aal1';
commit;""" % tuple(map(q, [ACTOR, ACTOR, ACTOR, ACTOR, ACTOR, SID, ACTOR, OTHER_SID, ACTOR])),
                   label='synthetic fresh approved exact actor/session reset')

    def wait_for(name, predicate, seconds=15):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if target.scalar("select exists(select 1 from pg_stat_activity where application_name=" + q(name) + ' and ' + predicate + ');') == 't':
                return
            time.sleep(.05)
        raise RuntimeError('Live SQL phase not observed for ' + name)

    def start(executor, name, body):
        return executor.submit(target.sql, "set application_name=" + q(name) + ";set statement_timeout='15s';begin;" + body,
                               check=False, label='actual concurrent session ' + name)

    save()
    try:
        platform, provenance = helper.platform_shape()
        (report / 'platform-schema-only.sql').write_text(platform)
        result['platform_shape'] = provenance
        with helper.Target(report, 'private', result['target']) as target:
            target.sql(platform, label='captured row-free Auth/storage bootstrap')
            for item in items:
                if item['version'] == '20261001160000':
                    # Same explicit cached-platform normalization as the
                    # accepted Admin query rehearsal. This affects only this
                    # network-none target; no hosted platform is certified.
                    target.sql(LOCAL_NET_METADATA, user='supabase_admin', label='local pg_net trusted dispatch metadata normalization')
                    target.sql((captured / PLATFORM_PREREQUISITE.relative_to(ROOT)).read_text(),
                               user='supabase_admin', label='captured existing pg_net private-reader platform prerequisite')
                    result['local_net_platform_normalization'] = dict(sql=LOCAL_NET_METADATA,
                        sql_sha256=sha(LOCAL_NET_METADATA.encode()), platform_prerequisite_sha256=before[str(PLATFORM_PREREQUISITE.relative_to(ROOT))],
                        scope='task-owned image metadata and private-reader ACL shape only; hosted installer authority remains unverified')
                helper.apply(target, [item], result['target'])
            case('all exact current migrations replay on clean app shape',
                 int(target.scalar('select count(*)from supabase_migrations.schema_migrations;')) == len(items))
            (report / 'effective-schema-catalog.sql').write_text(CATALOG_SQL + '\n')
            catalog = target.json(CATALOG_SQL)
            catalog_body = (json.dumps(catalog, indent=2) + '\n').encode()
            (report / 'effective-schema-catalog.json').write_bytes(catalog_body)
            result['effective_schema_catalog'] = dict(path='effective-schema-catalog.json', sha256=sha(catalog_body),
                query_sha256=sha(CATALOG_SQL.encode()), schemas=len(catalog['schemas']), relations=len(catalog['relations']),
                functions=len(catalog['functions']), source_hashes=before,
                scope='Read-only effective metadata/function definitions in task-local synthetic platform/prerequisite-normalized target; no table rows or hosted observation')
            save()
            fixture = (captured / SQL_FILE.relative_to(ROOT)).read_text()
            executed = target.sql("set collect.assisted_sms_qa='isolated_clone';\n" + fixture, check=False, label='frozen SQL all-nine authority/ACL fixture')
            (report / 'sql-uat.stdout').write_text(executed.stdout)
            (report / 'sql-uat.stderr').write_text(executed.stderr)
            case('all-nine SQL ACL, allowed actor and sequential revocation matrix passes', executed.returncode == 0,
                 exit_code=executed.returncode, revocation_matrix_notices=executed.stderr.count('ASSISTED_REVOCATION_CASES=9'))
            case('all-nine healthy operator actions use actual current public APIs',
                 executed.stderr.count('ASSISTED_POSITIVE_PIPELINE=PASS') == 1,
                 scope='Canonical synthetic outbox setup; no financial policy certification or provider dispatch')
            case('all six revocation mutations exercised nine entrypoints before any legacy write',
                 executed.stderr.count('ASSISTED_REVOCATION_CASES=9') == 6)
            reset_actor()
            target.sql('begin;' + claims + heartbeat(str(uuid.uuid4())) + 'commit;', label='initial current heartbeat write')
            revocations = {
                'logout': 'delete from auth.sessions where id=' + q(SID) + ';',
                'session_expiry': 'update auth.sessions set not_after=clock_timestamp()-interval \'1 second\'where id=' + q(SID) + ';',
                'user_deletion': 'update auth.users set deleted_at=clock_timestamp()where id=' + q(ACTOR) + ';',
                'role_revocation': 'update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=' + q(ACTOR) + ';',
                'approval_revocation': 'update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=' + q(ACTOR) + ';',
                'permission_revocation': "delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner')and permission_name='notifications.read';",
            }
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                for label, mutation in revocations.items():
                    for ordering in ('revocation_first', 'operation_first'):
                        reset_actor()
                        run = str(uuid.uuid4())
                        previous = target.scalar("select run_id from collect_hybrid.sms_operator_heartbeats where worker_id='assisted-race';")
                        first_name = 'assisted_' + label + '_' + ordering + '_first'
                        second_name = 'assisted_' + label + '_' + ordering + '_second'
                        first_body = mutation if ordering == 'revocation_first' else claims + heartbeat(run)
                        first = start(executor, first_name, first_body + 'select pg_sleep(2);commit;')
                        wait_for(first_name, "wait_event='PgSleep'")
                        second_body = claims + heartbeat(run) if ordering == 'revocation_first' else mutation
                        second = start(executor, second_name, second_body + 'commit;')
                        wait_for(second_name, "wait_event_type='Lock'and cardinality(pg_blocking_pids(pid))>0")
                        first_result = first.result(timeout=20)
                        second_result = second.result(timeout=20)
                        current = target.scalar("select run_id from collect_hybrid.sms_operator_heartbeats where worker_id='assisted-race';")
                        if ordering == 'revocation_first':
                            ok = first_result.returncode == 0 and second_result.returncode != 0 and '42501' in second_result.stderr and current == previous
                        else:
                            later = target.sql('begin;' + claims + heartbeat(str(uuid.uuid4())) + 'commit;', check=False,
                                               label='later exact originating session denied after revocation')
                            ok = first_result.returncode == 0 and second_result.returncode == 0 and current == run and later.returncode != 0 and '42501' in later.stderr
                        case(label + ' ' + ordering + ' actual blocking and commit order', ok,
                             first_exit=first_result.returncode, second_exit=second_result.returncode,
                             blocked_wait_observed=True, before_run_id=previous, requested_run_id=run, after_run_id=current,
                             first_error=first_result.stderr, second_error=second_result.stderr)
                reset_actor()
                previous = target.scalar("select run_id from collect_hybrid.sms_operator_heartbeats where worker_id='assisted-race';")
                target.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 second\'where id=' + q(SID) + ';')
                blocker_name = 'assisted_clock_expiry_blocker'
                waiter_name = 'assisted_clock_expiry_waiter'
                blocker = start(executor, blocker_name, "select 1 from collect_hybrid.sms_operator_heartbeats where worker_id='assisted-race'for update;select pg_sleep(2);commit;")
                wait_for(blocker_name, "wait_event='PgSleep'")
                waiter = start(executor, waiter_name, claims + heartbeat(str(uuid.uuid4())) + 'commit;')
                wait_for(waiter_name, "wait_event_type='Lock'and cardinality(pg_blocking_pids(pid))>0")
                blocker_result, waiter_result = blocker.result(timeout=20), waiter.result(timeout=20)
                case('clock expiry during legacy row wait rolls back its mutation', blocker_result.returncode == 0 and waiter_result.returncode != 0 and '42501' in waiter_result.stderr
                     and target.scalar("select run_id from collect_hybrid.sms_operator_heartbeats where worker_id='assisted-race';") == previous,
                     blocked_wait_observed=True, error=waiter_result.stderr)
            reset_actor()
            repeated = target.sql('begin isolation level repeatable read;' + claims + heartbeat(str(uuid.uuid4())) + 'commit;', check=False,
                                  label='established snapshot admission')
            case('repeatable-read snapshot cannot preserve stale originating authority', repeated.returncode != 0 and '40001' in repeated.stderr)
            case('second active session does not replace original in any race', target.scalar('select exists(select 1 from auth.sessions where id=' + q(OTHER_SID) + ');') == 't')
            case('networkless target never executes schedulers or outbound net work',
                 target.scalar("select current_setting('cron.launch_active_jobs')='off'and current_setting('pg_net.batch_size')='0'and not exists(select 1 from cron.job_run_details);") == 't')
            result['status'] = 'pass'
    except Exception as error:
        result['status'] = 'fail'
        result['error'] = str(error)
        save()
        raise
    finally:
        if target:
            target.close()
        after = {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in paths}
        result['source_inputs_unchanged'] = before == after
        result['source_drift'] = [name for name in before if before[name] != after[name]]
        result['new_migrations_after_capture'] = [str(path.relative_to(ROOT)) for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')) if str(path.relative_to(ROOT)) not in before]
        if not result['source_inputs_unchanged'] or result['new_migrations_after_capture']:
            result['status'] = 'fail'
            result.setdefault('error', 'Current inputs differ from the executed snapshot')
        result['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
