#!/usr/bin/env python3
"""Root-run local QA telemetry trace/repair. No hosted endpoints or fixture replay.

trace: pg_restore exports one backup table to stdout; PostgreSQL is read-only.
apply: requires an exact reviewed trace digest and three explicitly attributed XIDs.
"""
from __future__ import annotations
import argparse
import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = 'supabase_db_' + PROJECT
BACKUP = ROOT / '.cache/notification-sessions-20260930/pre141.dump'
PACKET = ROOT / 'docs/release/notification-session-fencing-2026-09-30'
BASELINE = PACKET / 'pre141-domain-fingerprints.json'
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
SCHEMAS = {'public', 'auth', 'collect_hybrid', 'collect_security', 'collect_admin_access'}
UUID = re.compile(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
SCOPED = 'public.app_realtime_events'

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def command(args: list[str], data: bytes | None = None) -> bytes:
    result = subprocess.run(args, input=data, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace')[-6000:])
    return result.stdout

def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

def literal(value) -> str:
    return quote(json.dumps(value, separators=(',', ':'))) + '::jsonb'

def sql(body: str) -> str:
    return command(PSQL, ("set timezone='UTC'; set standard_conforming_strings=on; set statement_timeout='30s';\n" + body).encode()).decode().strip()

def fixture_identity() -> dict:
    labels = json.loads(command(['docker', 'inspect', CONTAINER, '--format', '{{json .Config.Labels}}']))
    ports = json.loads(command(['docker', 'inspect', CONTAINER, '--format', '{{json .HostConfig.PortBindings}}']))
    config = (ROOT / '.cache/financial-concurrency-20260929/supabase/config.toml').read_text()
    if labels.get('com.supabase.cli.project') != PROJECT or labels.get('com.docker.compose.project') != PROJECT:
        raise RuntimeError('Exact task-owned Docker labels required')
    if ports.get('5432/tcp', [{}])[0].get('HostPort') != '55722' or not re.search(r'^port = 55722$', config, re.M) or not re.search(r'^project_id = "'+PROJECT+r'"$', config, re.M):
        raise RuntimeError('Exact task-owned project/port required')
    return {'project': PROJECT, 'host_port': 55722, 'labels_verified': True}

def guard() -> str:
    return """do $$ begin
      if current_database()<>'postgres' or current_user<>'postgres'
        or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
        or (select count(*) from supabase_migrations.schema_migrations)<>141
        or (select max(version) from supabase_migrations.schema_migrations)<>'20260929180000'
        or to_regclass('public.notification_session_upgrade_qa') is not null
        or exists(select 1 from auth.users where id::text like '99720000-%')
        or exists(select 1 from auth.sessions where id::text like '99720000-%')
        or exists(select 1 from public.profiles where id::text like '99720000-%')
        or exists(select 1 from collect_hybrid.member_records where id::text like '99720000-%')
        or exists(select 1 from public.notification_device_tokens)
        or exists(select 1 from public.notification_deliveries)
        or exists(select 1 from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid()
          and backend_type='client backend' and state<>'idle') then
        raise exception 'Quiet exact141 post-upgrade fixture and removed9972 graph required'; end if;
    end $$;"""

def load_baseline() -> dict:
    expected = json.loads(BASELINE.read_text())
    for relation, value in expected.items():
        pieces = relation.split('.')
        if len(pieces) != 2 or pieces[0] not in SCHEMAS or not all(re.fullmatch(r'[a-z_][a-z_0-9]*', piece) for piece in pieces):
            raise RuntimeError('Unexpected baseline relation identifier')
        if not isinstance(value.get('rows'), int) or value['rows'] < 0 or not re.fullmatch('[0-9a-f]{64}', value.get('sha256', '')):
            raise RuntimeError('Malformed baseline fingerprint')
    if len(expected) != 124 or expected.get(SCOPED, {}).get('rows') != 560:
        raise RuntimeError('This repair requires the preserved124-table/560-event pre141 baseline')
    return expected

def fingerprints_sql(expected: dict) -> str:
    selects = []
    for relation in sorted(expected):
        table = '.'.join('"'+piece+'"' for piece in relation.split('.'))
        selects.append("select %s relation,count(*) row_count,encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),'sha256'),'hex') sha256 from %s t" % (quote(relation), table))
    return "select jsonb_object_agg(relation,jsonb_build_object('rows',row_count,'sha256',sha256)) from (" + ' union all '.join(selects) + ') digests'

def export_backup() -> list[dict]:
    # pg_restore is a decoder only: no --dbname/connection option, no SQL execution.
    output = command(['docker', 'exec', '-i', CONTAINER, 'pg_restore', '--data-only', '--schema=public', '--table=app_realtime_events', '--file=-'], BACKUP.read_bytes()).decode()
    pattern = r'^COPY public\.app_realtime_events \(id, area, created_at\) FROM stdin;\n(.*?)^\\\.$'
    blocks = re.findall(pattern, output, re.M | re.S)
    if len(blocks) != 1 or len(re.findall(r'^COPY ', output, re.M)) != 1:
        raise RuntimeError('Expected exactly one known COPY block from backup; refuse unknown dump shape')
    rows = []
    for line in blocks[0].splitlines():
        parts = line.split('\t')
        if len(parts) != 3 or not UUID.fullmatch(parts[0]) or not re.fullmatch('[a-z_]+', parts[1]) or '\\' in parts[2]:
            raise RuntimeError('Unexpected telemetry COPY value')
        dt.datetime.fromisoformat(parts[2])
        rows.append(dict(zip(('id', 'area', 'created_at'), parts)))
    if len(rows) != 560 or len({row['id'] for row in rows}) != 560:
        raise RuntimeError('Backup does not contain560 unique baseline events')
    return rows

def baseline_cte(rows: list[dict]) -> str:
    return 'baseline as (select * from jsonb_populate_recordset(null::public.app_realtime_events,' + literal(rows) + '))'

def canonical_snapshot(expected: dict, rows: list[dict]) -> dict:
    data = sql('begin isolation level repeatable read read only;\n' + guard() + '\n' + f"""
      with {baseline_cte(rows)}
      select jsonb_build_object(
        'backup_fingerprint',(select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg(to_jsonb(b)::text,E'\\n' order by to_jsonb(b)::text),''),'sha256'),'hex')) from baseline b),
        'baseline_rows',(select jsonb_agg(to_jsonb(b) order by b.id) from baseline b),
        'events',(select coalesce(jsonb_agg(jsonb_build_object('row',to_jsonb(e),'xmin',e.xmin::text) order by e.id),'[]') from public.app_realtime_events e),
        'catalog',(select jsonb_agg(schemaname||'.'||tablename order by schemaname,tablename) from pg_tables where schemaname in ('public','auth','collect_hybrid','collect_security','collect_admin_access')),
        'fingerprints',({fingerprints_sql(expected)}));
      rollback;
    """)
    return json.loads(data)

def describe_delta(expected: dict, snapshot: dict) -> tuple[list[dict], list[dict]]:
    if snapshot['backup_fingerprint'] != expected[SCOPED]:
        raise RuntimeError('Decoded backup rows do not match the recorded pre141 fingerprint')
    if snapshot['catalog'] != sorted(expected):
        raise RuntimeError('Application/Auth table catalog differs from the pre141 baseline')
    changed = {key: value for key, value in snapshot['fingerprints'].items() if key != SCOPED and value != expected[key]}
    if changed:
        raise RuntimeError('Non-telemetry changes present; no disposition permitted: ' + ','.join(sorted(changed)))
    old = {row['id']: row for row in snapshot['baseline_rows']}
    current = {event['row']['id']: event for event in snapshot['events']}
    if len(current) != len(snapshot['events']) or any(key not in current or current[key]['row'] != row for key, row in old.items()):
        raise RuntimeError('A baseline telemetry row was removed/modified; cleanup refused')
    added = [event for key, event in current.items() if key not in old]
    groups = []
    for xid in sorted({event['xmin'] for event in added}, key=int):
        batch = [event for event in added if event['xmin'] == xid]
        groups.append({'xmin': xid, 'rows': len(batch), 'areas': dict(sorted(collections.Counter(event['row']['area'] for event in batch).items())), 'created_at': sorted({event['row']['created_at'] for event in batch})})
    return added, groups

def read_trace(args) -> None:
    identity = fixture_identity(); expected = load_baseline(); rows = export_backup()
    snapshot = canonical_snapshot(expected, rows); added, groups = describe_delta(expected, snapshot)
    report = {'schema': 1, 'mode': 'read_only_trace', 'captured_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'fixture': identity, 'backup_path': str(BACKUP.relative_to(ROOT)), 'backup_sha256': sha(BACKUP.read_bytes()),
              'baseline_fingerprints_sha256': sha(BASELINE.read_bytes()), 'helper_sha256': sha(Path(__file__).read_bytes()),
              'baseline': expected, 'baseline_rows': snapshot['baseline_rows'], 'current_fingerprints': snapshot['fingerprints'],
              'added_events': added, 'xmin_groups': groups, 'unchanged_nontelemetry_tables': 123,
              'all560_baseline_rows_exact': True, 'attribution': 'UNPROVEN_ORIGINAL_XIDS_NOT_CAPTURED; root must review and explicitly attribute observed phase XIDs before any cleanup',
              'unknown_events_deleted': False, 'database_writes': False}
    destination = Path(args.output)
    if destination.exists():
        raise RuntimeError('Trace destination already exists; preserve earlier evidence')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'status': 'read_only_trace_saved', 'path': str(destination), 'trace_sha256': sha(destination.read_bytes()), 'added_event_count': len(added), 'xmin_groups': groups, 'cleanup_executed': False}, indent=2))

def apply_trace(args) -> None:
    if os.environ.get('COLLECT_NOTIFICATION_TELEMETRY_QA') != 'reviewed_isolated_trace':
        raise RuntimeError('Explicit root-reviewed isolated trace disposition flag required')
    destination = Path(args.output)
    if destination.exists():
        raise RuntimeError('Result destination exists; preserve prior disposition evidence')
    destination.parent.mkdir(parents=True, exist_ok=True)
    path = Path(args.trace)
    if sha(path.read_bytes()) != args.trace_sha256:
        raise RuntimeError('Reviewed trace digest mismatch')
    report = json.loads(path.read_text()); expected = load_baseline()
    if report.get('mode') != 'read_only_trace' or report.get('baseline') != expected or report.get('backup_sha256') != sha(BACKUP.read_bytes()) or report.get('baseline_fingerprints_sha256') != sha(BASELINE.read_bytes()):
        raise RuntimeError('Reviewed backup/baseline provenance mismatch')
    fixture_identity()
    rows = export_backup(); now = canonical_snapshot(expected, rows); added, groups = describe_delta(expected, now)
    if added != report.get('added_events') or now['fingerprints'] != report.get('current_fingerprints'):
        raise RuntimeError('Database changed since reviewed trace; capture and review a new trace')
    xids = [args.seed_xid, args.migration_xid, args.verify_xid]
    if not all(re.fullmatch(r'[0-9]+', xid) and 0<int(xid)<2**32 for xid in xids) or len(set(xids)) != 3 or list(map(int,xids)) != sorted(map(int,xids)):
        raise RuntimeError('Three distinct ordered observed phase XIDs required; no wraparound inference')
    wanted = [{'xmin': xids[0], 'rows': 5, 'areas': {'notifications': 4, 'profiles': 1}},
              {'xmin': xids[1], 'rows': 2, 'areas': {'notifications': 2}},
              {'xmin': xids[2], 'rows': 3, 'areas': {'notifications': 2, 'profiles': 1}}]
    if len(added) != 10 or len(groups) != 3 or any({key: group[key] for key in ('xmin','rows','areas')} != want or len(group['created_at']) != 1 for group,want in zip(groups,wanted)):
        raise RuntimeError('Unknown phase telemetry: refuse anything outside the exact reviewed5/2/3 fixture pattern')
    if [group['created_at'][0] for group in groups] != sorted(group['created_at'][0] for group in groups):
        raise RuntimeError('Phase timestamps are not ordered')
    # The explicit XIDs are root's attribution decision, recorded separately from
    # the original trace. We do not claim retrospective source capture existed.
    expected_added = literal(added)
    expected_current = literal(report['current_fingerprints'])
    expected_baseline = literal(expected)
    body = f"""begin isolation level serializable;
      set local lock_timeout='5s';
      {guard()}
      select pg_advisory_xact_lock(193517,141);
      lock table public.app_realtime_events in access exclusive mode;
      {guard()}
      do $$ declare n integer; begin
        if ({fingerprints_sql(expected)})<>{expected_current} then raise exception 'Reviewed full-table fingerprints changed before cleanup'; end if;
        if exists(select 1 from pg_trigger where tgrelid='public.app_realtime_events'::regclass and not tgisinternal)
          or exists(select 1 from pg_constraint where contype='f' and confrelid='public.app_realtime_events'::regclass) then
          raise exception 'Unexpected telemetry trigger/reference; cleanup refused'; end if;
        with approved as (select item->'row' body,item->>'xmin' xid from jsonb_array_elements({expected_added}) item)
        delete from public.app_realtime_events e using approved a
          where e.id=(a.body->>'id')::uuid and to_jsonb(e)=a.body and e.xmin::text=a.xid;
        get diagnostics n=row_count;
        if n<>10 then raise exception 'Exact reviewed telemetry delete count mismatch'; end if;
        if ({fingerprints_sql(expected)})<>{expected_baseline} then
          raise exception 'Original124-table fingerprints not restored; telemetry cleanup rolled back'; end if;
      end $$;
      select 'NOTIFICATION_UPGRADE_TELEMETRY_DISPOSITION_PASS';
      commit;
    """
    stdout = sql(body)
    if stdout.splitlines()[-1] != 'NOTIFICATION_UPGRADE_TELEMETRY_DISPOSITION_PASS':
        raise RuntimeError('Disposition result marker missing; inspect DB state before retrying')
    after = canonical_snapshot(expected, rows)
    after_added, _ = describe_delta(expected, after)
    if after_added or after['fingerprints'] != expected:
        raise RuntimeError('Post-commit baseline verification differs; do not rerun blindly')
    result = {'schema': 1, 'status': 'pass', 'captured_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'reviewed_trace_sha256': args.trace_sha256, 'backup_sha256': report['backup_sha256'],
              'root_attributed_phase_xids': dict(zip(('seed','migration','verify'),xids)),
              'attribution_basis': 'explicit root-reviewed legacy trace; original phase markers were absent',
              'deleted_events': added, 'preserved_original_events': 560, 'restored_table_count': 124,
              'fingerprints_before': report['current_fingerprints'], 'fingerprints_after': after['fingerprints'],
              'migration_changed': False, 'provider_calls': False, 'sql_stdout': stdout}
    destination = Path(args.output)
    if destination.exists():
        raise RuntimeError('Result destination exists; DB cleanup already succeeded; do not rerun')
    destination.parent.mkdir(parents=True, exist_ok=True); destination.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({'status': 'pass', 'result': str(destination), 'deleted_exact_events': 10, 'preserved_baseline_events': 560, 'restored_tables': 124}, indent=2))

def main() -> None:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest='mode', required=True)
    trace = modes.add_parser('trace'); trace.add_argument('--output', required=True)
    apply = modes.add_parser('apply'); apply.add_argument('--trace', required=True); apply.add_argument('--trace-sha256', required=True)
    for phase in ('seed','migration','verify'):
        apply.add_argument('--'+phase+'-xid', required=True)
    apply.add_argument('--output', required=True)
    args = parser.parse_args()
    if args.mode == 'trace': read_trace(args)
    else: apply_trace(args)

if __name__ == '__main__':
    main()
