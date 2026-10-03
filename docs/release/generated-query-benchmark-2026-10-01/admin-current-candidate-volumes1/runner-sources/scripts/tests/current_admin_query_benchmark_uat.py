#!/usr/bin/env python3
"""Actual current Admin list queries over disposable1000/10000-row fixtures.

Read fixtures are trusted synthetic inserts into the private clone, with every
production trigger and constraint intact. They are not enrollment/signature,
source-observation, financial-posting, sender or carrier evidence. The reviewed
ordinary-installer receipt is required before any SQL. The exact schema154
capture is restored in a fresh network-none target; shared tables/cron remain
read only and every captured stage absent from154 is appended.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import datetime as dt
import hashlib
import json
from pathlib import Path
import statistics
import time
import traceback

import current_generated_query_benchmark_uat as Q
import collect_current_release_upgrade_uat as replay

ROOT, B, D, P, U = Q.ROOT, Q.B, Q.D, Q.P, Q.U
LIMIT = 50
SID = '99760000-0000-4000-8000-000000090001'
API_RELATIONS = {'gateway': 'devices', 'exceptions': 'exceptions'}
API_NAMES = {'gateway': 'public.admin_list_gateway_devices_v1',
             'exceptions': 'public.admin_list_operational_exceptions_v2'}
BASELINE = ROOT / 'docs/release/runtime-controls-2026-10-01/current21-full26-races-attempt1'
BASELINE_PROOF_SHA = '1e00881a21cf9945064f56eacf5918f0d0d8348b76410a4eece4978e53ad8183'
PLATFORM_PATH = ROOT / 'scripts/sql/receipt_transport_platform_prerequisites.sql'
PLATFORM_STATEMENTS = [
    'create index if not exists collect_receipt_http_response_id on net._http_response(id)',
    'grant usage on schema net to postgres',
    'grant select(id,status_code,content,timed_out,error_msg,created)on net._http_response to postgres',
    'grant select(id)on net.http_request_queue to postgres',
]
# Local fixture metadata used by the accepted ordinary installer rehearsal.
# The shipping prerequisite deliberately verifies rather than creates this
# trusted platform dispatch boundary.
LOCAL_NET_METADATA = (
    'alter function net.http_get(text,jsonb,jsonb,integer)security definer;'
    'alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;'
    'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;'
    'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;'
)


def admit_receipt(proof, current, platform_path, platform_sha256):
    """Bind the completed ordinary installer, never a failed partial185 run."""
    P.require(proof.get('kind') == 'ordinary_local_installer_all_current_clean_populated'
        and proof.get('status') == 'pass' and proof.get('all_task_containers_removed') is True
        and proof.get('shared_database_written') is False and proof.get('source_rows_copied') is False,
        dict(incomplete_or_wrong_ordinary_receipt=True))
    rows = proof.get('source_inventory', [])
    captured = {r['path']: r['sha256'] for r in rows}
    P.require(rows and len(captured) == len(rows) and captured == current
        and len({r['version'] for r in rows}) == len(rows)
        and [r['path'] for r in rows] == sorted(current), dict(nonexact_capture_map=True))
    P.require(proof.get('platform_prerequisite_sha256', {}).get(platform_path) == platform_sha256,
              dict(unbound_platform_prerequisite=platform_path))
    predecessor = proof.get('predecessor', {}).get('count')
    P.require(isinstance(predecessor, int) and 0 < predecessor < len(rows),
              dict(invalid_populated_predecessor=True))
    for phase in ('clean', 'populated'):
        state = proof.get('phases', {}).get(phase, {})
        migrations = state.get('migrations', [])
        actual = {r['path']: r['sha256'] for r in migrations}
        P.require(state.get('status') == 'pass' and len(migrations) == len(rows)
            and actual == captured and [r['path'] for r in migrations] == [r['path'] for r in rows]
            and state.get('task_container_removed') is True,
            dict(incomplete_phase=phase))
        P.require(state.get('scheduler_readback') == dict(cron='off', net='0', history=0),
                  dict(unsafe_scheduler_phase=phase))
        guard = state.get('guard', {})
        P.require(guard.get('network') == 'none' and guard.get('published_ports') is False
            and guard.get('labels_verified') is True and guard.get('cron') == 'off'
            and guard.get('net') == '0', dict(unsafe_target_guard_phase=phase))
        net = state.get('net_platform_ownership', {})
        P.require(all(net.get(k) == v for k, v in dict(extension_owner='supabase_admin',
            schema='extensions', version='0.20.0').items()), dict(unreviewed_net_platform=phase))
        for index, row in enumerate(migrations):
            actor = row.get('actual_installer_authority', {})
            P.require(row.get('status') == 'pass' and actor.get('superuser') is False
                and actor.get('current_user') == 'postgres' and actor.get('current_role') == 'postgres',
                dict(nonordinary_migration=row.get('path'), phase=phase))
            if phase == 'populated' and index >= predecessor:
                P.require(row.get('canonical_predecessor_preserved') is True,
                          dict(unpreserved_predecessor=row['path']))
    return rows


def admit_platform_sql(body):
    # This is the root-selected file, bound to a successful ordinary receipt.
    # Owner/definer assertions and table/all-column privacy revokes are allowed.
    # The only affirmative grants remain the reviewed usage/seven columns.
    # This check supplements the actual owner matrix; it is not a SQL parser or
    # a replacement security acceptance for an arbitrary prerequisite script.
    import re
    text = re.sub(r'--[^\n]*', '', body).lower()
    executable = re.sub(r"'(?:[^']|'')*'", "''", text)
    compact = lambda s: re.sub(r'\s*([(),])\s*', r'\1', ' '.join(s.lower().strip().split()))
    grants = re.findall(r'\bgrant\s+[^;]+', text)
    expected = [s for s in PLATFORM_STATEMENTS if s.startswith('grant ')]
    P.require(sorted(compact(s) for s in grants) == sorted(compact(s) for s in expected)
        and compact(PLATFORM_STATEMENTS[0]) in compact(text)
        and not re.search(r'\b(?:alter\s+(?:role|user)|owner\s+to|net\.http_(?:get|post|delete)\s*\()', executable),
        dict(unreviewed_affirmative_platform_authority=True))
    return body


def baseline_capture(current):
    proof_path = BASELINE / 'result.json'
    P.require(Q.sha(proof_path) == BASELINE_PROOF_SHA, dict(baseline_receipt_changed=True))
    proof = json.loads(proof_path.read_bytes())
    inventory_path = BASELINE / 'migration-source-inventory.json'
    P.require(Q.sha(inventory_path) == proof['migration_inventory_sha256'], dict(baseline_inventory_changed=True))
    inventory = json.loads(inventory_path.read_bytes())
    added = {'supabase/migrations/' + name for name in proof['migration_sources']}
    baseline = {path: sha for path, sha in inventory.items() if path not in added}
    P.require(len(baseline) == proof['source_guard']['count'] == 154
        and all(current.get(path) == sha for path, sha in baseline.items()),
        dict(schema154_prefix_source_changed=True))
    files = [proof_path, inventory_path]
    for name, key in [('schema-only.sql', 'schema_only_sha256'), ('api-acl.sql', 'api_acl_sha256'),
                      ('api-column-acl.sql', 'api_column_acl_sha256')]:
        path = BASELINE / name
        P.require(Q.sha(path) == proof[key], dict(baseline_shape_or_acl_changed=name))
        files.append(path)
    return baseline, files


@contextmanager
def private_clone(report, evidence, baseline, platform_body):
    """Real cron/net in private postgres; never install into the shared clone."""
    before = Q.R.snapshot()
    evidence['source_guard'] = Q.R.guard(154, '20260930230000')
    Q.save(report / 'source-before.json', before)
    old_container = U.CONTAINER
    target = replay.Target(report, 'schema154_private', evidence.setdefault('target', {}))
    try:
        with target:
            shape = (BASELINE / 'schema-only.sql').read_text()
            target.sql(shape, label='exact accepted no-row schema154 owner-normalized restore')
            target.sql((BASELINE / 'api-acl.sql').read_text()
                + (BASELINE / 'api-column-acl.sql').read_text(), label='exact accepted API relation and column ACL restore')
            target.sql('create extension if not exists pg_cron with schema pg_catalog;'
                'create extension if not exists pg_net with schema extensions;', user='supabase_admin',
                label='declared owner-only cron/net platform prerequisites in fresh private postgres')
            target.sql(LOCAL_NET_METADATA, user='supabase_admin',
                label='local exact retained trusted pg_net metadata before application installer')
            evidence['local_platform_metadata_normalization'] = dict(
                shipping_prerequisite_changed=False, local_fixture_only=True,
                sql=LOCAL_NET_METADATA,
                sql_sha256=hashlib.sha256(LOCAL_NET_METADATA.encode()).hexdigest(),
                functions=target.json("select jsonb_agg(jsonb_build_object('name',p.proname,'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'settings',p.proconfig)order by p.proname)from pg_proc p where p.oid in(to_regprocedure('net.http_get(text,jsonb,jsonb,integer)'),to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)'));"))
            P.require(evidence['local_platform_metadata_normalization']['functions'] == [
                dict(name=name, owner='supabase_admin', security_definer=True, settings=['search_path=net'])
                for name in ('http_get', 'http_post')], dict(untrusted_local_net_metadata=True))
            target.sql('alter role postgres nosuperuser;', user='supabase_admin',
                label='end restore authority before platform trusted-definer assertions')
            target.sql(platform_body, user='supabase_admin', label='receipt-bound nonsecret owner index and read prerequisites')
            target.sql('grant execute on function cron.alter_job(bigint,text,text,text,text,boolean)to postgres;',
                user='supabase_admin', label='retained ordinary installer cron owner API prerequisite')
            evidence['net_platform'] = target.json("select jsonb_build_object('owner',pg_get_userbyid(e.extowner),'schema',n.nspname,'version',e.extversion)from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pg_net';")
            P.require(evidence['net_platform'] == dict(owner='supabase_admin', schema='extensions', version='0.20.0'),
                      dict(private_net_platform_mismatch=True))
            target.sql('alter role postgres nosuperuser;', user='supabase_admin', label='end schema restore and platform setup authority')
            evidence['ordinary_installer'] = target.json("select jsonb_build_object('superuser',rolsuper,'current_user',current_user,'current_role',current_role)from pg_roles where rolname=current_user;")
            P.require(evidence['ordinary_installer'] == dict(superuser=False, current_user='postgres', current_role='postgres'),
                      dict(private_installer_not_ordinary=True))
            registry = []
            for path in sorted(baseline):
                source = ROOT / path
                version, name = source.stem.split('_', 1)
                registry.append('insert into supabase_migrations.schema_migrations(version,name,statements)values('
                    + ','.join([D.literal(version), D.literal(name), 'array[' + D.literal(source.read_text()) + ']']) + ');')
            target.sql(''.join(registry), label='synthetic exact accepted154 registry; schema shape restored rather than migrations rerun')
            U.CONTAINER = target.name
            # Later worker migrations need real cron owner APIs in database
            # postgres. The existing shared-container temporary database helper
            # cannot provide this without violating cron.database_name.
            B.seed_baseline_shadow_lease('postgres', report, evidence)
            yield 'postgres'
            final_guard = target.json("select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'history',(select count(*)from cron.job_run_details),'queued',(select count(id)from net.http_request_queue));")
            P.require(final_guard == dict(cron='off', net='0', history=0, queued=0), dict(private_scheduler_or_net_activity=final_guard))
            evidence['scheduler_readback'] = final_guard
    finally:
        U.CONTAINER = old_container
        target.close()
        after = Q.R.snapshot()
        Q.save(report / 'source-after.json', after)
        evidence['all_source_tables_catalog_cron_preserved'] = before == after
        evidence['isolated_database_removed'] = target.evidence.get('task_container_removed') is True
        evidence['source_guard_after'] = Q.R.guard(154, '20260930230000')
        P.require(before == after and evidence['isolated_database_removed'], dict(shared_preservation_or_target_cleanup_failed=True))


def identity(kind, n):
    return f'9976{kind:04d}-0000-4000-8000-{n:012d}'


def stamp(n):
    return (dt.datetime(2026, 9, 27, 12, tzinfo=dt.timezone.utc)
            + dt.timedelta(seconds=n // 3)).isoformat()


def page_sql(scope, cursor=None, active=True, kind=None):
    if scope == 'gateway':
        before = ('null,null' if cursor is None else
                  D.literal(cursor['enrolled_at']) + ',' + D.literal(cursor['device_id']))
        return f'select {API_NAMES[scope]}({LIMIT},{before})'
    before = ('null,null' if cursor is None else
              D.literal(cursor['changed_at']) + ',' + D.literal(cursor['id']))
    category = 'null' if kind is None else D.literal(kind)
    return (f'select {API_NAMES[scope]}({str(active).lower()},{LIMIT},'
            f'{before},{category})')


def read_plan(stderr, scope):
    """Admit the nested relational CTE, never the public wrapper/actor plan."""
    plans = Q.nested_plans(stderr)
    actual = [plan for plan in plans
              if 'candidates as materialized' in plan['Query Text'].lower()
              and any(n.get('Relation Name') == API_RELATIONS[scope]
                      for n in Q.nodes(plan['Plan']))]
    P.require(len(actual) == 1, dict(scope=scope, actual_list_plan_count=len(actual)))
    nodes = list(Q.nodes(actual[0]['Plan']))
    P.require(any('Shared Hit Blocks' in n for n in nodes), dict(missing_actual_buffers=scope))
    limits = [n['Actual Rows'] for n in nodes
              if n.get('Node Type') == 'Limit' and 'Actual Rows' in n]
    P.require(limits and all(0 <= n <= LIMIT + 1 for n in limits),
              dict(scope=scope, unbounded_window_limits=limits))
    return actual[0]


def measured(db, sql, packet, name, scope):
    samples = []
    answer = None
    for _ in range(3):
        start = time.monotonic()
        answer = D.scalar(db, 'begin;' + P.actor(P.MAKER, SID) + sql + ';rollback;')
        samples.append(time.monotonic() - start)
    body = ("load 'auto_explain';set client_min_messages=log;"
            "set auto_explain.log_min_duration=0;set auto_explain.log_analyze=on;"
            "set auto_explain.log_buffers=on;set auto_explain.log_nested_statements=on;"
            "set auto_explain.log_format=json;set auto_explain.log_timing=off;"
            "set session authorization postgres;begin;" + P.actor(P.MAKER, SID)
            + sql + ';rollback;')
    result = Q.diagnostic_query(db, body)
    (packet / f'{name}.stdout').write_text(result.stdout)
    (packet / f'{name}.stderr').write_text(result.stderr)
    P.require(result.returncode == 0, dict(name=name, diagnostic_exit=result.returncode,
                                         failure=result.stderr[-2000:]))
    plan = read_plan(result.stderr, scope)
    return answer, dict(name=name, scope=scope, sql_sha256=hashlib.sha256(sql.encode()).hexdigest(),
        end_to_end_seconds=samples, median_seconds=statistics.median(samples),
        nested_read_plan=plan, stdout_sha256=Q.sha(packet / f'{name}.stdout'),
        stderr_sha256=Q.sha(packet / f'{name}.stderr'),
        api_role='authenticated', execution_session_authorization='postgres',
        wrapper_or_actor_only_plan_accepted=False, includes_docker_psql=True,
        hosted_latency_or_slo_accepted=False)


def preflight(db, report):
    body = ("load 'auto_explain';set session authorization postgres;begin;"
            + P.actor(P.MAKER, SID)
            + "select jsonb_build_object('preflight',true,'session_user',session_user,"
              "'api_role',current_user,'actor',auth.uid(),'session',auth.jwt()->>'session_id');rollback;")
    result = Q.diagnostic_query(db, body)
    (report / 'diagnostic-preflight.stdout').write_text(result.stdout)
    (report / 'diagnostic-preflight.stderr').write_text(result.stderr)
    P.require(result.returncode == 0, dict(preflight_exit=result.returncode,
                                          failure=result.stderr[-2000:]))
    records = [json.loads(line) for line in result.stdout.splitlines()
               if line.startswith('{') and '"preflight"' in line]
    expected = dict(preflight=True, session_user='postgres', api_role='authenticated',
                    actor=P.MAKER, session=SID)
    P.require(records == [expected], dict(preflight_expected=expected, actual=records))
    return dict(actual=expected, before_volume_fixtures=True,
                stdout_sha256=Q.sha(report / 'diagnostic-preflight.stdout'),
                stderr_sha256=Q.sha(report / 'diagnostic-preflight.stderr'))


def authority(db, report, evidence, stages):
    B.seed_schema_clone_permission_catalog(db, report, evidence)
    for path, body in stages:
        actor = D.scalar(db, "select jsonb_build_object('superuser',rolsuper,'current_user',current_user,'current_role',current_role)from pg_roles where rolname=current_user;")
        P.require(actor == dict(superuser=False, current_user='postgres', current_role='postgres'),
                  dict(stage_installer_not_ordinary=str(path)))
        U.psql(db, body.decode())
        version, name = path.stem.split('_', 1)
        U.psql(db, 'insert into supabase_migrations.schema_migrations(version,name,statements)values('
            + ','.join([D.literal(version), D.literal(name), 'array[' + D.literal(body.decode()) + ']']) + ');')
    evidence['actual_appended_stage_sha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(body).hexdigest()
                                              for path, body in stages}
    D.seed(db)
    P.seed_authority(db)
    # Add permissions before issuing a new session. Do not age/reset an old one.
    U.psql(db, f"""begin;
      insert into public.admin_permissions(name) values('system_health.read')on conflict do nothing;
      insert into public.admin_role_permissions(role_id,permission_name)
        select '{P.ROLE}',unnest(array['payments.read','notifications.read','system_health.read']);
      update public.profiles set is_platform_admin=true where id='{P.MAKER}';
      insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
        values('{SID}','{P.MAKER}',clock_timestamp(),clock_timestamp(),
          clock_timestamp()+interval '1 hour','aal2');commit;""")
    ack = D.scalar(db, 'begin;' + P.actor(P.MAKER, SID)
        + "select public.admin_set_operator_email_mode_v1('Synthetic Admin query benchmark cutover');commit;")
    P.require(ack == dict(ok=True, mode='email', replay=False), dict(cutover_ack=ack))
    evidence['diagnostic_preflight'] = preflight(db, report)


def fixtures(db, count, report):
    """Read-side synthetic rows only; no sender attempt/arm is manufactured."""
    sql = ['begin;']
    devices = []
    categories = ['raw_sms', 'allocation', 'payment', 'receipt', 'gateway']
    reasons = ['PARSING_FAILED', 'ALLOCATION_REVIEW', 'VERIFICATION_PENDING',
               'CONTACT_MISSING', 'GATEWAY_UNOBSERVED']
    for n in range(1, count + 1):
        device = identity(1, n)
        created = stamp(n)
        devices.append(dict(id=device, at=created, installation=identity(2, n),
                            health=identity(4, 2 * n + 1), owner_request=identity(5, 2 * n + 1)))
        sql.append(f"""insert into collect_gateway.devices(id,enrollment_request_id,owner_actor_id,
          owner_session_id,installation_id,public_key_spki_base64,key_sha256,
          signing_certificate_sha256,created_at)values('{device}','{identity(3,n)}','{P.MAKER}',
          '{SID}','{identity(2,n)}','SYNTHETIC-READ-FIXTURE-NOT-A-SIGNATURE',
          '{n:064x}',repeat('a',64),'{created}');""")
        for k in (0, 1):
            ref = 2 * n + k
            request, observation, owner_request = identity(6, ref), identity(4, ref), identity(5, ref)
            sql.append(f"""insert into collect_gateway.requests(request_id,device_id,action,
              request_sha256,payload,result,recorded_at)values('{request}','{device}','heartbeat',
              repeat('b',64),'{{}}','{{}}','{created}');
              insert into collect_gateway.health_observations(id,device_id,request_id,reported_at,
              ingested_at,sms_permission,network,telephony,sim_selected,local_pause)
              values('{observation}','{device}','{request}','{created}','{created}',
                {'true' if k==0 else 'false'},'unknown','unknown',false,true);
              insert into collect_gateway.admin_requests(request_id,actor_id,action,input,result,recorded_at)
              values('{owner_request}','{P.MAKER}','enroll','{{}}',jsonb_build_object(
                'device_id','{device}','request_id','{owner_request}','state_at_action','pending',
                'recorded_at',collect_gateway.utc('{created}'::timestamptz),'replay',false),'{created}');""")
        # The explicit exception fixture has deterministic tied timestamps,
        # mixed active/category filters and current vs prior-revision actions.
        ex, kind, reason = identity(7, n), categories[n % 5], reasons[n % 5]
        revision = 2 if n % 2 else 1
        sql.append(f"""insert into collect_ops.exceptions(id,source_kind,source_id,reason_code,
          active,source_sha256,revision,first_observed_at,last_changed_at)
          values('{ex}','{kind}','{identity(8,n)}','{reason}',{str(n%3!=0).lower()},
            repeat('c',64),{revision},'{created}','{created}');""")
        for action, offset in [('acknowledge', 0), ('escalate', 1)]:
            expected = revision if (n + offset) % 2 else revision - 1
            sql.append(f"""insert into collect_ops.exception_actions(request_id,exception_id,
              expected_revision,action,reason_code,actor_id,session_id,recorded_at,result)
              values('{identity(9,2*n+offset)}','{ex}',{expected},'{action}','review_started',
                '{P.MAKER}','{SID}','{created}','{{}}');""")
    sql.append('commit;analyze collect_gateway.devices;analyze collect_gateway.admin_requests;'
               'analyze collect_gateway.health_observations;analyze collect_gateway.segment_callbacks;'
               'analyze collect_ops.exceptions;analyze collect_ops.exception_actions;')
    body = '\n'.join(sql)
    (report / 'synthetic-read-fixtures.sql').write_text(body)
    U.psql(db, body)
    # Source metadata oracle includes genuine derived Gateway trigger rows.
    # Sorting/cursor/category decisions occur independently in Python; the
    # public list API is never used to construct the expected row set.
    exceptions = D.scalar(db, """select coalesce(jsonb_agg(jsonb_build_object('id',e.id,
      'source_kind',e.source_kind,'active',e.active,'at',e.last_changed_at,
      'acknowledged',exists(select 1 from collect_ops.exception_actions a where a.exception_id=e.id
        and a.expected_revision=e.revision and a.action='acknowledge'),
      'escalation_requested',exists(select 1 from collect_ops.exception_actions a where a.exception_id=e.id
        and a.expected_revision=e.revision and a.action='escalate'))),'[]')from collect_ops.exceptions e;""")
    value = dict(devices=devices, exceptions=exceptions,
                 callback_rows=0, synthetic_callbacks_not_manufactured=True)
    Q.save(report / 'source-read-oracle.json', value)
    return value


def ordered(rows):
    return sorted(rows, key=lambda x: (dt.datetime.fromisoformat(x['at']), x['id']), reverse=True)


def cursor_for(row, scope):
    return ({'enrolled_at': row['at'], 'device_id': row['id']} if scope == 'gateway'
            else {'changed_at': row['at'], 'id': row['id']})


def assert_page(page, expected, offset, scope):
    rows = expected[offset:offset + LIMIT]
    id_key, time_key = ('device_id', 'enrolled_at') if scope == 'gateway' else ('id', 'last_changed_at')
    P.require([x[id_key] for x in page['rows']] == [x['id'] for x in rows],
              dict(scope=scope, offset=offset, expected_ids=[x['id'] for x in rows], actual=page))
    P.require(page['limit'] == LIMIT, dict(limit=page['limit']))
    checked = dt.datetime.fromisoformat(page['checked_at'].replace('Z', '+00:00'))
    expiry = dt.datetime.fromisoformat(page['sample_valid_until'].replace('Z', '+00:00'))
    P.require(expiry == checked + dt.timedelta(seconds=60), dict(scope=scope, invalid_read_ttl=True))
    more = offset + len(rows) < len(expected)
    cursor = page['next_cursor']
    P.require((cursor is not None) == more, dict(scope=scope, wrong_cursor=cursor, expected_more=more))
    if cursor:
        P.require(cursor == ({'enrolled_at': page['rows'][-1][time_key], 'device_id': rows[-1]['id']}
                  if scope == 'gateway' else
                  {'changed_at': page['rows'][-1][time_key], 'id': rows[-1]['id']}),
                  dict(scope=scope, wrong_paired_cursor=cursor))
    if scope == 'gateway':
        P.require(page['total'] == len(expected), dict(expected_total=len(expected), actual=page['total']))
    for wire, source in zip(page['rows'], rows):
        P.require(dt.datetime.fromisoformat(wire[time_key].replace('Z', '+00:00'))
                  == dt.datetime.fromisoformat(source['at']), dict(scope=scope, business_time_changed=wire))
        if scope == 'gateway':
            P.require(wire['installation_id'] == source['installation']
                and wire['state'] == 'pending' and not wire['dispatch_available']
                and wire['callback_observations'] == dict(total=0, sent=0, delivery=0)
                and wire['health']['observation_id'] == source['health']
                and wire['health']['sms_permission'] is False
                and wire['health']['freshness'] == 'stale'
                and wire['last_owner_action']['receipt']['request_id'] == source['owner_request'],
                dict(scope=scope, invalid_latest_or_count_projection=wire))
        else:
            P.require(wire['active'] == source['active'] and wire['source_kind'] == source['source_kind']
                and wire['acknowledged'] == source['acknowledged']
                and wire['escalation_requested'] == source['escalation_requested'],
                dict(scope=scope, invalid_review_projection=wire))


def run_volume(db, count, report, evidence, stages):
    authority(db, report, evidence, stages)
    oracle = fixtures(db, count, report)
    metrics = []
    samples = [('gateway', True, None)]
    samples += [('exceptions', active, kind) for active in (True, False)
                for kind in (None, 'raw_sms', 'allocation', 'payment', 'receipt', 'gateway')]
    for scope, active, kind in samples:
        wanted = ordered(oracle['devices'] if scope == 'gateway' else
                         [x for x in oracle['exceptions'] if x['active'] == active
                          and (kind is None or x['source_kind'] == kind)])
        for depth, offset in [('first', 0), ('middle', len(wanted) // 2),
                              ('deep', max(0, len(wanted) - LIMIT)), ('terminal', len(wanted))]:
            cursor = None if offset == 0 else cursor_for(wanted[offset - 1], scope)
            name = f'{scope}-{active}-{kind or "all"}-{depth}'
            page, metric = measured(db, page_sql(scope, cursor, active, kind), report, name, scope)
            assert_page(page, wanted, offset, scope)
            metrics.append(dict(metric, depth=depth, expected_matching=len(wanted), offset=offset,
                                returned=len(page['rows']), category=kind, active=active))
            evidence['cases'].append(dict(name=name, status='pass'))
            Q.save(report / 'measurements.json', metrics)
            Q.save(report / 'result.json', evidence)
            print('PASS ' + name, flush=True)
    evidence['source_oracle_sha256'] = Q.sha(report / 'source-read-oracle.json')
    evidence['synthetic_fixture_sql_sha256'] = Q.sha(report / 'synthetic-read-fixtures.sql')
    evidence['sampled_anchor_navigation_only'] = True
    evidence['callback_aggregation_limit'] = ('Zero callback rows in this large-volume fixture. '
        'Existing small actual Gateway UAT nonzero sent/delivery projections remain separate; '
        'this run does not claim1000/10000 callback observations or sender authority.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--reviewed-upgrade', '--reviewed-stages', dest='reviewed_upgrade', required=True, type=Path)
    parser.add_argument('--platform-prerequisites', default=PLATFORM_PATH, type=Path)
    args = parser.parse_args()
    packet = args.output.resolve()
    if not packet.is_relative_to(ROOT / 'docs/release'):
        parser.error('Repository release packet required')
    packet.mkdir(parents=True, exist_ok=False)
    review = args.reviewed_upgrade.resolve(strict=True)
    platform_path = args.platform_prerequisites.resolve(strict=True)
    if not review.is_relative_to(ROOT) or not platform_path.is_relative_to(ROOT):
        parser.error('Repository-local bound upgrade receipt and nonsecret platform prerequisites required')
    if platform_path != PLATFORM_PATH.resolve():
        parser.error('Root-selected receipt_transport_platform_prerequisites.sql required')
    proof = json.loads(review.read_bytes())
    current = {str(path.relative_to(ROOT)): Q.sha(path)
               for path in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
    result = dict(kind='current_admin_actual_list_query_volumes', status='running',
                  reviewed_upgrade_receipt_sha256=Q.sha(review), volumes=[1000, 10000], volume_results=[],
                  hosted_called=False, provider_called=False, shared_source_written=False,
                  signed_auth_or_enrollment_or_sender_or_production_acceptance=False)
    try:
        platform_body = admit_platform_sql(platform_path.read_text())
        inventory = admit_receipt(proof, current, str(platform_path.relative_to(ROOT)), Q.sha(platform_path))
        baseline, baseline_files = baseline_capture(current)
    except (AssertionError, KeyError, TypeError, ValueError) as error:
        result.update(status='failed', failure_phase='before_sql_or_clone',
                      failure=str(error), expected_current_capture=current,
                      observed_capture=proof.get('source_inventory'),
                      sql_executed=False)
        Q.save(packet / 'result.json', result)
        return 1
    stages = [(ROOT / item['path'], (ROOT / item['path']).read_bytes()) for item in inventory
              if item['path'] not in baseline]
    result.update(reviewed_migration_count=len(inventory), baseline_schema_migration_count=len(baseline),
                  appended_stage_count=len(stages), platform_prerequisite_sha256=Q.sha(platform_path))
    helpers = [Path(__file__), Path(Q.__file__), Path(P.__file__), Path(D.__file__), Path(B.__file__), Path(replay.__file__),
               ROOT / 'scripts/tests/local_schema_uat.py', ROOT / 'scripts/tests/local_offline_verification.py',
               ROOT / 'scripts/tests/shadow_supervisor_uat.py', Path(Q.R.FIXTURE.__file__),
               B.PERMISSION_CATALOG_SOURCE, B.PAYMENT_PERMISSION_SOURCE, B.SHADOW_LEASE_SOURCE,
               review, platform_path] + baseline_files
    inputs = {str(x.relative_to(ROOT)): Q.sha(x) for x in helpers}
    inputs.update(current)
    result['source_inputs'] = inputs
    source = packet / 'runner-sources'
    for rel, expected_sha in inputs.items():
        body = (ROOT / rel).read_bytes()
        P.require(hashlib.sha256(body).hexdigest() == expected_sha, dict(source_changed=rel))
        dest = source / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(body)
    try:
        for count in result['volumes']:
            report = packet / f'volume-{count}'
            report.mkdir(mode=0o700)
            evidence = dict(status='running', volume=count, cases=[], triggers_disabled=False,
                            trusted_synthetic_private_read_fixture=True, source_rows_copied=False)
            U.SQL_LOG, U.CONCURRENCY_LOG = report / 'queries.log', report / 'concurrency.log'
            try:
                with private_clone(report, evidence, baseline, platform_body) as db:
                    run_volume(db, count, report, evidence, stages)
                evidence['status'] = 'pass_scoped'
            except Exception as error:
                evidence.update(status='failed', failure=str(error), traceback=traceback.format_exc())
            finally:
                U.SQL_LOG = U.CONCURRENCY_LOG = None
                Q.save(report / 'result.json', evidence)
                result['volume_results'].append(dict(volume=count, status=evidence['status'],
                    cases=len(evidence['cases']), result_sha256=Q.sha(report / 'result.json'),
                    all_source_tables_catalog_cron_preserved=evidence.get('all_source_tables_catalog_cron_preserved'),
                    isolated_database_removed=evidence.get('isolated_database_removed')))
                Q.save(packet / 'result.json', result)
            if evidence['status'] == 'failed':
                break
        result['status'] = ('pass_scoped' if len(result['volume_results']) == 2
                            and all(x['status'] == 'pass_scoped' for x in result['volume_results']) else 'failed')
    finally:
        result['source_inputs_unchanged'] = all(Q.sha(ROOT / rel) == h for rel, h in inputs.items())
        result['entire_migration_capture_stable'] = current == {
            str(path.relative_to(ROOT)): Q.sha(path)
            for path in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
        if not result['source_inputs_unchanged'] or not result['entire_migration_capture_stable']:
            result['status'] = 'failed'
        result['completed_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
        result['limits'] = ['Actual list query read fixtures, no enrollment/source/financial producer authority.',
                           'Sampled anchors rather than complete cursor chain; paired ties/order/terminal tested.',
                           'Zero callback fixture rows: no large nonzero callback aggregation claim.',
                           'Exact Gateway total; Exceptions has no total-count API; only supported descending sort.',
                           'Local three samples and nested buffers do not approve hosted p95/p99/SLO/device capacity.']
        Q.save(packet / 'result.json', result)
    return int(result['status'] == 'failed')


if __name__ == '__main__':
    raise SystemExit(main())
