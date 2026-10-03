#!/usr/bin/env python3
"""Proposed local, synthetic-only committed backup/restore and original replay.

Execution needs a separately retained review decision bound to this script and
inputs.json. This parser cannot authenticate that decision or manufacture one.
This is a proposed fixture-only compatibility cohort, not shipping admission.
"""
from __future__ import annotations
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
DOCKER = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
IMAGE = 'sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a'
CATALOG = 'scripts/sql/collect_recovery_source_catalog.sql'
TRANSPORT = 'scripts/sql/receipt_transport_platform_prerequisites.sql'
FINAL_SHA = '4516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c'
HASH = re.compile(r'[a-f0-9]{64}')
OPERATIONS = ['local_synthetic_dump', 'local_synthetic_restore', 'ordinary_original_migration_replay']
ENV = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
LIMIT = 64 * 1024**2


class Refused(ValueError):
    pass


def sha(body):
    return hashlib.sha256(body).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Refused('DUPLICATE_JSON_KEY')
        result[key] = value
    return result


def read(path, limit=LIMIT):
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts or any(p.is_symlink() for p in (path, *path.parents)):
        raise Refused('ABSOLUTE_UNSUBSTITUTED_PATH_REQUIRED')
    with path.open('rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit:
            raise Refused('BOUNDED_SINGLE_LINK_REGULAR_INPUT_REQUIRED')
        body = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    key = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_mode, s.st_nlink)
    if len(body) > limit or key(before) != key(after) or key(after) != key(path.lstat()):
        raise Refused('INPUT_CHANGED_DURING_READ')
    return body


def document(path):
    return json.loads(read(path), object_pairs_hook=unique)


def admit_review(value, code_sha, inputs_sha):
    expected = {'kind', 'decision', 'review_reference', 'code_sha256', 'inputs_sha256',
                'image_id', 'client_version', 'server_version_num', 'operations', 'scope'}
    if not isinstance(value, dict) or set(value) != expected:
        raise Refused('REVIEW_SCHEMA_INVALID')
    if value['kind'] != 'collect_local_synthetic_recovery_review_v1' or value['decision'] != 'admit':
        raise Refused('SEPARATE_REVIEW_DECISION_REQUIRED')
    if not re.fullmatch(r'[A-Za-z0-9._:/-]{1,160}', value['review_reference']):
        raise Refused('REVIEW_REFERENCE_REQUIRED')
    if value['code_sha256'] != code_sha or value['inputs_sha256'] != inputs_sha:
        raise Refused('REVIEW_INPUT_BINDING_CHANGED')
    if value['image_id'] != IMAGE or value['client_version'] != '17.6' or type(value['server_version_num']) is not int or value['server_version_num'] != 170006:
        raise Refused('COMPATIBILITY_OUTSIDE_PROPOSED_LOCAL_COHORT')
    if value['operations'] != OPERATIONS or value['scope'] != 'owned_networkless_synthetic_fixture_only':
        raise Refused('SCOPE_OUTSIDE_PROPOSED_LOCAL_COHORT')
    return value


def version(tool, output):
    prefix = 'psql' if tool == 'psql' else 'postgres' if tool == 'postgres' else tool
    if not re.fullmatch(re.escape(prefix) + r' \(PostgreSQL\) 17\.6(?: [^\r\n]*)?\n?', output):
        raise Refused('ACTUAL_CLIENT_OUTSIDE_17_6_COHORT')
    return '17.6'


def sealed_dump(path, expected):
    body = read(path)
    if not body.startswith(b'PGDMP') or not HASH.fullmatch(expected) or sha(body) != expected:
        raise Refused('DUMP_CONTENT_SEAL_CHANGED')
    return body


def owned(info, name):
    if not re.fullmatch(r'collect_ordinary_recovery_(source|restore)_[0-9a-f]{12}', name):
        raise Refused('OWNED_NAME_REQUIRED')
    if info['Image'] != IMAGE or info['Config']['Labels'].get('collect.recovery.owner') != name:
        raise Refused('OWNERSHIP_OR_IMAGE_CHANGED')
    host = info['HostConfig']
    if host['NetworkMode'] != 'none' or host['PortBindings'] or info['HostConfig'].get('Privileged'):
        raise Refused('NETWORK_OR_PRIVILEGED_SCOPE_CHANGED')
    tmpfs = host.get('Tmpfs', {})
    if tmpfs != {'/var/lib/postgresql/collect-rehearsal': 'rw,size=1073741824'}:
        raise Refused('EXACT_BOUNDED_TMPFS_REQUIRED')
    if host.get('Binds') or host.get('Devices') or host.get('CapAdd'):
        raise Refused('HOST_WRITE_OR_DEVICE_SCOPE_CHANGED')
    return True


def database_acl_sql(database):
    # Strict source database identity; no destination/name/SQL text from a caller.
    if database['name'] != 'postgres' or database['owner'] != 'postgres' or database['connection_limit'] != -1:
        raise Refused('DATABASE_OUTSIDE_FROZEN_FIXTURE')
    rows = []
    for entry in database['acl']:
        match = re.fullmatch(r'([a-z_]*)(=)([CTc]+)/postgres', entry)
        if not match:
            raise Refused('DATABASE_ACL_OUTSIDE_FIXTURE')
        role, _, permissions = match.groups()
        rows.append((role or 'PUBLIC', permissions))
    sql = []
    for role, permissions in rows:
        sql.append('revoke all on database postgres from ' + role + ';')
        names = {'C': 'CREATE', 'T': 'TEMPORARY', 'c': 'CONNECT'}
        sql.append('grant ' + ','.join(names[c] for c in permissions) + ' on database postgres to ' + role + ';')
    return ''.join(sql)


def restore_list(toc, catalog):
    # All data, original migration history, object definitions and ACL entries
    # remain. Only exact preinstalled platform extension/schema CREATE entries
    # and separately restored database control entries are omitted explicitly.
    schemas = {row[2] for row in catalog['extensions']} - {'pg_catalog'}
    extensions = {row[0] for row in catalog['extensions']}
    lines, omitted, seen = [], [], set()
    for line in toc.splitlines(keepends=True):
        match = re.fullmatch(r'(\d+);\s+\d+\s+\d+\s+(EXTENSION|SCHEMA|DATABASE|DATABASE PROPERTIES) - (\S+)(?: ([^\s]+))?\s*', line)
        skip = False
        if match:
            _, kind, name, _ = match.groups()
            skip = ((kind == 'EXTENSION' and name in extensions) or
                    (kind == 'SCHEMA' and name in schemas) or
                    (kind in {'DATABASE', 'DATABASE PROPERTIES'} and name == 'postgres'))
            if kind == 'EXTENSION':
                seen.add(name)
        if skip:
            omitted.append(line.rstrip())
            lines.append('; preinstalled exact frozen prerequisite: ' + line)
        else:
            lines.append(line)
    if not seen or not seen.issubset(extensions) or not any('TABLE DATA supabase_migrations schema_migrations' in line for line in lines):
        raise Refused('FULL_HISTORY_OR_EXTENSION_TOC_REQUIRED')
    if not any('TABLE DATA auth users' in line for line in lines):
        raise Refused('FULL_SYNTHETIC_AUTH_DATA_REQUIRED')
    return ''.join(lines), omitted


class Runner:
    def __init__(self, report, deadline):
        self.report, self.deadline, self.records = report, deadline, []

    def call(self, argv, body=None, check=True, timeout=120, limit=LIMIT):
        left = self.deadline - time.monotonic()
        if left <= 0:
            raise Refused('WHOLE_600_SECOND_DEADLINE')
        if isinstance(body, str):
            body = body.encode()
        if body is not None and len(body) > LIMIT:
            raise Refused('INPUT_LIMIT')
        process = subprocess.Popen(argv, env=ENV, stdin=subprocess.PIPE if body is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        end = time.monotonic() + min(timeout, left)
        out, err, offset = bytearray(), bytearray(), 0
        try:
            with selectors.DefaultSelector() as selector:
                for stream, label in [(process.stdout, 'out'), (process.stderr, 'err')]:
                    os.set_blocking(stream.fileno(), False)
                    selector.register(stream, selectors.EVENT_READ, label)
                if process.stdin is not None:
                    os.set_blocking(process.stdin.fileno(), False)
                    selector.register(process.stdin, selectors.EVENT_WRITE, 'in')
                while selector.get_map():
                    if time.monotonic() >= end:
                        raise Refused('BOUNDED_TOOL_DEADLINE')
                    for key, _ in selector.select(.05):
                        if key.data == 'in':
                            if offset == len(body):
                                selector.unregister(key.fileobj); key.fileobj.close(); continue
                            try:
                                offset += os.write(key.fileobj.fileno(), body[offset:offset + 16384])
                            except BrokenPipeError:
                                selector.unregister(key.fileobj); key.fileobj.close()
                        else:
                            chunk = os.read(key.fileobj.fileno(), 16384)
                            if not chunk:
                                selector.unregister(key.fileobj); continue
                            stream = out if key.data == 'out' else err
                            stream.extend(chunk)
                            if len(stream) > (limit if key.data == 'out' else 1024**2):
                                raise Refused('BOUNDED_TOOL_OUTPUT_LIMIT')
                code = process.wait(timeout=max(.001, end - time.monotonic()))
        except BaseException as error:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            command = ['POSTGRES_PASSWORD=<ephemeral-unlogged>' if str(a).startswith('POSTGRES_PASSWORD=') else a for a in argv]
            row = dict(command=command, status='refused', reason=str(error),
                input_sha256=sha(body) if body is not None else None,
                stdout_bytes=len(out), stdout_sha256=sha(out), stderr_bytes=len(err), stderr_sha256=sha(err))
            self.records.append(row)
            with (self.report / 'commands.jsonl').open('a') as log:
                log.write(json.dumps(row) + '\n')
            raise
        finally:
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None and not stream.closed:
                    stream.close()
        command = ['POSTGRES_PASSWORD=<ephemeral-unlogged>' if str(a).startswith('POSTGRES_PASSWORD=') else a for a in argv]
        row = dict(command=command, exit_code=code, input_sha256=sha(body) if body is not None else None,
            stdout_bytes=len(out), stdout_sha256=sha(out), stderr_bytes=len(err), stderr_sha256=sha(err))
        self.records.append(row)
        with (self.report / 'commands.jsonl').open('a') as log:
            log.write(json.dumps(row) + '\n')
        if check and code:
            # SQL/text is synthetic, but avoid exporting dump bodies in failures.
            raise Refused('TOOL_FAILED: ' + str(command[1:3]) + ': ' + bytes(err[-1500:]).decode(errors='replace'))
        return subprocess.CompletedProcess(argv, code, bytes(out), bytes(err))

    def text(self, argv, text=None, check=True, timeout=120):
        result = self.call(argv, text, check, timeout)
        return subprocess.CompletedProcess(argv, result.returncode, result.stdout.decode(), result.stderr.decode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, default=HERE / 'inputs.json')
    parser.add_argument('--review-record', type=Path, required=True)
    parser.add_argument('--review-record-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    absolute = lambda path: path if path.is_absolute() else Path.cwd() / path
    code_body, inputs_body = read(Path(__file__).resolve()), read(absolute(args.inputs))
    review_body = read(absolute(args.review_record), 16384)
    if not HASH.fullmatch(args.review_record_sha256) or sha(review_body) != args.review_record_sha256:
        raise Refused('REVIEW_RECORD_BINDING_CHANGED')
    review = admit_review(json.loads(review_body, object_pairs_hook=unique), sha(code_body), sha(inputs_body))
    inputs = json.loads(inputs_body, object_pairs_hook=unique)
    candidate = Path(inputs['candidate'])
    expected_candidate = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate1')
    report = args.output.resolve()
    if candidate != expected_candidate or report.exists() or not report.is_relative_to(candidate / 'docs/release'):
        raise Refused('FRESH_PRIVATE_OWNED_OUTPUT_REQUIRED')
    report.mkdir(parents=True, mode=0o700)
    record = dict(kind='collect_local_committed_synthetic_recovery_v1', status='running',
        shipping_restore_admission=False, proposed_local_compatibility_review=review,
        review_authentication=False, cases=[], targets={}, maintained_source_mutations=0,
        source_rows_copied=False, real_auth_or_customer_or_provider_rows=False,
        hosted_called=False, provider_called=False, production_app_export=False,
        full_BE08_closed=False, ARC08_restore_adapter_closed=False, ARC11_closed=False,
        whole_deadline_seconds=600, started_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    started = time.monotonic()
    whole_deadline = started + 600
    # Reserve one minute for failure reconciliation inside the whole600 bound.
    runner = Runner(report, started + 540)
    record['execution_budget_seconds'] = 540
    record['cleanup_budget_seconds'] = 60
    targets = []
    def save():
        (report / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    def case(name, ok=True):
        if not ok:
            raise AssertionError(name)
        record['cases'].append(dict(name=name, status='pass')); save(); print('PASS ' + name, flush=True)
    def freeze():
        for name, digest in {**inputs['sources'], **inputs['references']}.items():
            if sha(read(candidate / name)) != digest:
                raise Refused('PRIVATE_FROZEN_INPUT_DRIFT: ' + name)
        names = {str(p.relative_to(candidate)) for p in (candidate / 'supabase/migrations').glob('*.sql')}
        if names != {name for name in inputs['sources'] if name.startswith('supabase/migrations/')}:
            raise Refused('MIGRATION_SET_DRIFT')
    freeze()
    spec = importlib.util.spec_from_file_location('collect_current_release_upgrade_uat', candidate / 'scripts/tests/collect_current_release_upgrade_uat.py')
    replay = importlib.util.module_from_spec(spec); spec.loader.exec_module(replay)
    replay.command = runner.text
    replay.IMAGE = IMAGE
    reference = document(candidate / 'reference/observed-output/result.json')
    reference_pre = document(candidate / 'reference/observed-output/ordinary_populated/predecessor-effective-catalog.json')
    reference_final_body = read(candidate / 'reference/observed-output/ordinary_populated/final-effective-catalog.json')
    reference_final = json.loads(reference_final_body)
    if sha(reference_final_body) != FINAL_SHA or len(reference['preserved_columns']) != 18:
        raise Refused('REFERENCE_BINDING_CHANGED')
    items = []
    for row in reference['source_inventory']:
        body = read(candidate / row['path'])
        if sha(body) != row['sha256'] or inputs['sources'][row['path']] != row['sha256']:
            raise Refused('ORIGINAL_MIGRATION_CHANGED')
        items.append(dict(**row, body=body.decode()))
    if len(items) != 209 or reference_pre['migrations'] != [i['version'] for i in items[:124]]:
        raise Refused('EXACT_124_PLUS_85_CHAIN_REQUIRED')
    record['input_binding'] = dict(inputs_sha256=sha(inputs_body), code_sha256=sha(code_body),
        source_count=216, source_hashes=inputs['sources'], final_reference_sha256=FINAL_SHA,
        reference_data_hashes_not_reused=True)

    class Target(replay.Target):
        def __init__(self, phase):
            outcome = record['targets'][phase] = {}
            super().__init__(report, phase, outcome)
            self.name = 'collect_ordinary_recovery_' + phase + '_' + uuid.uuid4().hex[:12]
            self.tools = {}
            with (report / 'owned-targets.jsonl').open('a') as log:
                log.write(json.dumps(dict(name=self.name, phase=phase, image_id=IMAGE)) + '\n')
            targets.append(self)
        def __enter__(self):
            # Add the recovery ownership label to the inherited exact-image run.
            original = replay.command
            def creation(argv, *a, **kw):
                if argv[:2] == [DOCKER, 'run']:
                    argv = list(argv); argv[2:2] = ['--label', 'collect.recovery.owner=' + self.name]
                return original(argv, *a, **kw)
            replay.command = creation
            try:
                super().__enter__()
            finally:
                replay.command = original
            self.guard()
            self.identities()
            return self
        def guard(self):
            info = json.loads(runner.call([DOCKER, 'container', 'inspect', self.name], limit=1024**2).stdout)[0]
            owned(info, self.name)
            self.evidence['guard_verified'] = True
        def identities(self):
            for tool in ['psql', 'pg_dump', 'pg_restore', 'postgres']:
                # Fixed shell text only; no source/caller interpolation.
                path = runner.call([DOCKER, 'exec', self.name, '/bin/sh', '-c', 'command -v ' + tool]).stdout.decode().strip()
                if not re.fullmatch(r'/[A-Za-z0-9_./-]+', path):
                    raise Refused('ABSOLUTE_IN_IMAGE_TOOL_REQUIRED')
                resolved = runner.call([DOCKER, 'exec', self.name, 'readlink', '-f', path]).stdout.decode().strip()
                digest = runner.call([DOCKER, 'exec', self.name, 'sha256sum', resolved]).stdout.decode().split()[0]
                if not HASH.fullmatch(digest):
                    raise Refused('ACTUAL_TOOL_HASH_REQUIRED')
                observed = runner.call([DOCKER, 'exec', self.name, resolved, '--version']).stdout.decode()
                self.tools[tool] = dict(path=resolved, sha256=digest, version=version(tool, observed), raw_version=observed, image_id=IMAGE)
            self.evidence['actual_tools'] = self.tools
            if self.scalar("select current_setting('server_version_num');") != '170006':
                raise Refused('ACTUAL_SERVER_OUTSIDE_17_6_COHORT')
        def tool(self, tool, arguments, body=None, check=True):
            self.guard()
            identity = self.tools[tool]
            digest = runner.call([DOCKER, 'exec', self.name, 'sha256sum', identity['path']]).stdout.decode().split()[0]
            if digest != identity['sha256']:
                raise Refused('IN_IMAGE_TOOL_CHANGED')
            return runner.call([DOCKER, 'exec', '-i', self.name, identity['path'], *arguments], body, check)
        def sql(self, text, check=True, label='query', user='postgres'):
            # The inherited platform-init probes run before identity discovery.
            # Every admitted application/dump/restore consumer thereafter uses
            # the captured absolute in-image psql path with a fresh byte check.
            if 'psql' not in self.tools:
                return super().sql(text, check, label, user)
            with (self.report / 'queries.sql').open('a') as log:
                log.write('-- Offline synthetic target: ' + label + '\n' + text + '\n')
            result = self.tool('psql', ['-XqAt', '-U', user, '-d', 'postgres',
                '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
                "set search_path=public,extensions,auth;set timezone='UTC';\n" + text, False)
            value = subprocess.CompletedProcess(result.args, result.returncode, result.stdout.decode(), result.stderr.decode())
            with (self.report / 'queries.log').open('a') as log:
                log.write(json.dumps(dict(label=label, sql_sha256=sha(text.encode()), exit_code=value.returncode,
                    stdout_sha256=sha(result.stdout), stderr_sha256=sha(result.stderr))) + '\n')
            if check and value.returncode:
                raise Refused(label + ': ' + value.stderr[-1500:])
            return value
        def control(self, sql):
            return self.tool('psql', ['-XqAt', '-U', 'supabase_admin', '-d', 'template1', '-v', 'ON_ERROR_STOP=1'], sql)
        def close(self):
            # Even a failed/uncertain docker run is reconciled by the exact name.
            response = runner.call([DOCKER, 'container', 'inspect', self.name], check=False, timeout=15, limit=1024**2)
            if response.returncode == 0:
                owned(json.loads(response.stdout)[0], self.name)
                runner.call([DOCKER, 'rm', '--force', '--volumes', self.name], timeout=15)
            elif response.returncode != 1 or not re.search(rb'No such (?:container|object)', response.stderr, re.I):
                raise Refused('OWNED_CLEANUP_READBACK_UNKNOWN')
            absent = runner.call([DOCKER, 'container', 'inspect', self.name], check=False, timeout=15, limit=1024**2)
            if absent.returncode != 1 or not re.search(rb'No such (?:container|object)', absent.stderr, re.I):
                raise Refused('OWNED_CONTAINER_NOT_REMOVED')
            self.made = False; self.evidence['task_container_removed'] = True
        def __exit__(self, kind, error, traceback):
            if error is not None:
                self.evidence['first_failure'] = str(error)
            try:
                self.close()
            except BaseException as cleanup_error:
                self.evidence['deferred_cleanup_error'] = str(cleanup_error)
                if error is None:
                    raise
                # Retain the actual operation failure; final reserved cleanup
                # retries the same exact owner/name under the whole deadline.
            return False

    def ordinary(target):
        state = target.json("select jsonb_build_object('user',current_user,'role',current_role,'superuser',rolsuper,'create_db',rolcreatedb,'create_role',rolcreaterole,'bypass_rls',rolbypassrls)from pg_roles where rolname=current_user;")
        if state['user'] != 'postgres' or state['role'] != 'postgres' or state['superuser'] is not False:
            raise Refused('ORDINARY_INSTALLER_REQUIRED')
        return state
    def safeguards(target):
        target.guard()
        state = target.json("select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'cron_history',(select count(*)from cron.job_run_details),'net_queue',(select count(*)from net.http_request_queue));")
        if state != dict(cron='off', net='0', listen='', cron_history=0, net_queue=0):
            raise Refused('SCHEDULER_OR_NETWORK_SAFEGUARD_CHANGED')
        target.evidence['scheduler_safeguards'] = state
    def catalog(target, boundary, expected):
        ordinary(target)
        result = target.json(read(candidate / CATALOG).decode())
        if result['migrations'] != expected or result['server']['version'] != reference_pre['server']['version']:
            raise Refused('CATALOG_VERSION_BOUNDARY_CHANGED')
        body = (json.dumps(result, indent=2) + '\n').encode()
        if len(body) > 32 * 1024**2:
            raise Refused('CATALOG_LIMIT')
        path = target.report / (boundary + '-catalog.json'); path.write_bytes(body)
        target.evidence.setdefault('catalogs', {})[boundary] = dict(sha256=sha(body),
            canonical_sha256=sha(json.dumps(result, sort_keys=True, separators=(',', ':')).encode()),
            bytes=len(body), query_sha256=inputs['sources'][CATALOG], whole_catalog_and_effective_acls=True)
        return result, body
    def platform(target):
        shape, provenance = replay.platform_shape()
        if sha(shape.encode()) != reference['platform_bootstrap']['extracted_platform_sha256']:
            raise Refused('EXACT_PLATFORM_SHAPE_CHANGED')
        target.sql(shape, label='sealed schema-only platform fixture before application migration')
        for sql in ["create extension if not exists pg_cron with schema pg_catalog;",
                    "create extension if not exists pg_net with schema extensions;",
                    "alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;",
                    read(candidate / TRANSPORT).decode(),
                    "grant execute on function cron.alter_job(bigint,text,text,text,text,boolean)to postgres;",
                    "alter role postgres nosuperuser;"]:
            target.sql(sql, user='supabase_admin', label='exact privileged local platform prerequisite')
        target.evidence['platform_provenance'] = provenance
        ordinary(target); safeguards(target)
    def apply(target, selected, preserved=None):
        for item in selected:
            authority = ordinary(target)
            before = replay.fingerprints(target, reference['preserved_columns']) if preserved is not None else None
            replay.apply(target, [item], target.evidence)
            row = target.evidence['migrations'][-1]; row['authority'] = authority
            ordinary(target)
            if preserved is not None:
                after = replay.fingerprints(target, reference['preserved_columns'])
                if before != preserved or after != preserved:
                    raise AssertionError('18 committed projections changed at ' + item['version'])
                row['all_18_fresh_committed_projections_preserved'] = True
            save()

    save()
    try:
        socket = runner.call([DOCKER, 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], timeout=15).stdout.decode().strip()
        if not socket.startswith('unix://'):
            raise Refused('LOCAL_DOCKER_UNIX_SOCKET_REQUIRED')
        ENV['DOCKER_HOST'] = socket
        image = runner.call([DOCKER, 'image', 'inspect', IMAGE, '--format', '{{.Id}}'], timeout=15).stdout.decode().strip()
        if image != IMAGE:
            raise Refused('CACHED_IMMUTABLE_IMAGE_REQUIRED')
        source = Target('source')
        with source:
            platform(source); apply(source, items[:124])
            pre, _ = catalog(source, 'before-seed', [i['version'] for i in items[:124]])
            case('fresh predecessor whole catalog equals sealed ordinary124 reference', pre == reference_pre)
            replay.seed_populated(source, record, case)
            case('fresh synthetic projection cohort equals actual current209 reference cohort', record['preserved_columns'] == reference['preserved_columns'])
            # Independent psql invocations prove rows and registry are committed;
            # pg_dump is another process/session after all seed COMMITs.
            preserved = replay.fingerprints(source, reference['preserved_columns'])
            record['fresh_committed_predecessor_fingerprints'] = preserved
            case('all18 committed synthetic projections are present', len(preserved) == 18 and preserved['auth.users']['rows'] == 2)
            case('synthetic Auth rows have no password/token/session secrets', source.scalar("select not exists(select 1 from auth.users where id not in('99780000-0000-4000-8000-000000000001','99780000-0000-4000-8000-000000000002')or coalesce(encrypted_password,'')<>''or coalesce(confirmation_token,'')<>''or coalesce(recovery_token,'')<>''or coalesce(email_change_token_new,'')<>''or coalesce(email_change_token_current,'')<>''or coalesce(phone_change_token,'')<>''or coalesce(reauthentication_token,'')<>'')and not exists(select 1 from auth.sessions where id<>'99780000-0000-4000-8000-000000010001'or coalesce(refresh_token_hmac_key,'')<>'')and not exists(select 1 from auth.refresh_tokens);") == 't')
            committed, _ = catalog(source, 'committed-predecessor', [i['version'] for i in items[:124]])
            case('committed predecessor whole catalog remains exact reference', committed == reference_pre)
            safeguards(source)
            dump = source.tool('pg_dump', ['--format=custom', '--compress=0', '--no-password', '--username=supabase_admin', '--dbname=postgres']).stdout
            if not dump.startswith(b'PGDMP') or len(dump) > LIMIT:
                raise Refused('ACTUAL_BOUNDED_CUSTOM_ARCHIVE_REQUIRED')
            dump_path = report / 'committed-synthetic-predecessor.dump'
            with dump_path.open('xb') as stream:
                stream.write(dump); stream.flush(); os.fsync(stream.fileno())
            dump_path.chmod(0o600)
            record['dump_seal'] = dict(path=str(dump_path), bytes=len(dump), sha256=sha(dump), format='custom',
                full_database=True, filters=False, owner_or_acl_omission=False,
                pg_dump=source.tools['pg_dump'], dump_role='supabase_admin',
                role_globals_recreated_from_exact_image_fixture=True, real_rows_exported=False,
                committed_outside_seed_transaction=True)
            case('durable full logical dump exists after committed seed in separate session', sha(read(dump_path)) == sha(dump))
            case('source dump did not change18 projections', replay.fingerprints(source, reference['preserved_columns']) == preserved)
        case('source container removed before independently owned restore target', source.evidence['task_container_removed'])
        restored = Target('restore')
        with restored:
            if restored.tools != source.tools:
                raise Refused('INDEPENDENT_TARGET_TOOL_IDENTITY_CHANGED')
            d = committed['database']
            if (d['encoding'], d['locale_provider'], d['collate'], d['ctype'], d['locale']) != ('UTF8', 'i', 'en_US.UTF-8', 'en_US.UTF-8', 'en-US'):
                raise Refused('DATABASE_LOCALE_OUTSIDE_FROZEN_FIXTURE')
            restored.control("drop database postgres with(force);create database postgres with template=template0 owner=postgres encoding='UTF8' locale_provider=icu locale='en_US.UTF-8' icu_locale='en-US';")
            # pg_dump excludes cluster roles and extension member definitions.
            # This explicit prerequisite restores the admitted image globals and
            # exact extension owner/version/member metadata, not arbitrary SQL.
            for schema_name, owner_name, _ in committed['schemas']:
                if schema_name in {e[2] for e in committed['extensions']} - {'pg_catalog'}:
                    restored.sql('create schema if not exists ' + schema_name + ' authorization ' + owner_name + ';', user='supabase_admin', label='empty target exact extension schema prerequisite')
            for name, ext_version, schema_name, owner_name in committed['extensions']:
                if not re.fullmatch(r'[a-z0-9_-]+', name) or owner_name not in ('postgres', 'supabase_admin'):
                    raise Refused('EXTENSION_OUTSIDE_FROZEN_FIXTURE')
                restored.sql('create extension if not exists "' + name + '" with schema ' + schema_name + " version '" + ext_version + "';", user=owner_name, label='exact source extension owner/version prerequisite')
            restored.sql("alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;", user='supabase_admin', label='explicit exact extension member metadata omitted by pg_dump')
            restored.sql(database_acl_sql(d), label='exact source database owner-issued ACL prerequisite')
            toc = restored.tool('pg_restore', ['--list'], read(dump_path)).stdout.decode()
            listing, omitted = restore_list(toc, committed)
            list_path = report / 'full-restore-list.txt'; list_path.write_text(listing)
            # The allow-list is copied only into this labelled, networkless
            # container; the archive continues to arrive on stdin.
            runner.call([DOCKER, 'cp', str(list_path), restored.name + ':/tmp/collect-full-restore-list.txt'])
            record['restore_scope'] = dict(role='supabase_admin', local_fixture_only=True,
                archive_sha256=sha(read(dump_path)), list_sha256=sha(listing.encode()),
                explicitly_preinstalled_toc_entries=omitted,
                all_application_objects_data_history_and_acls_retained=True,
                inherited_role_globals_and_extension_members_explicit_prerequisites=True,
                shipping_postgres_admission_operations=['query', 'migration'], shipping_restore_not_admitted=True)
            # Seal failure prevents sending corrupted archive bytes to a target.
            corrupt = bytearray(read(dump_path)); corrupt[-1] ^= 1
            corrupt_path = report / 'deliberately-corrupt-synthetic.dump'; corrupt_path.write_bytes(corrupt)
            try:
                sealed_dump(corrupt_path, record['dump_seal']['sha256'])
            except Refused as error:
                case('corrupt dump negative rejects changed content before restore', str(error) == 'DUMP_CONTENT_SEAL_CHANGED')
            else:
                raise AssertionError('Corrupt archive was admitted')
            finally:
                corrupt_path.unlink()
            restored.tool('pg_restore', ['--exit-on-error', '--no-password', '--username=supabase_admin', '--dbname=postgres', '--use-list=/tmp/collect-full-restore-list.txt'], sealed_dump(dump_path, record['dump_seal']['sha256']))
            restored.sql('alter role postgres nosuperuser;', user='supabase_admin', label='end explicit privileged local restore before any forward migration')
            ordinary(restored)
            roundtrip, _ = catalog(restored, 'restored-predecessor', [i['version'] for i in items[:124]])
            case('complete restored predecessor catalog and effective ACLs exactly equal committed source', roundtrip == committed)
            fresh = replay.fingerprints(restored, reference['preserved_columns'])
            record['fresh_restored_predecessor_fingerprints'] = fresh
            case('all18 committed projection hashes exactly survive independent restore', fresh == preserved)
            safeguards(restored)
            # A real reversible wrong-ACL fault is observed from a read-only
            # catalog in the same transaction; rollback is only this fault probe.
            probe = restored.json("begin;grant select on public.payments to anon;" + read(candidate / CATALOG).decode().replace('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;', '').replace('COMMIT;', '') + 'rollback;')
            case('wrong ACL negative differs from full predecessor catalog', probe != committed)
            again, _ = catalog(restored, 'after-negative-rollback', [i['version'] for i in items[:124]])
            case('wrong ACL probe rollback restores exact predecessor before forward replay', again == committed)
            apply(restored, items[124:], preserved)
            final, final_body = catalog(restored, 'final209', [i['version'] for i in items])
            case('all85 original forward migrations execute as postgres NOSUPERUSER', len(restored.evidence['migrations']) == 85 and all(m['authority']['superuser'] is False for m in restored.evidence['migrations']))
            case('complete final209 catalog and effective ACLs equal actual sealed current209 reference', final == reference_final and sha(final_body) == FINAL_SHA)
            record['fresh_final_fingerprints'] = replay.fingerprints(restored, reference['preserved_columns'])
            case('all18 fresh committed projection hashes survive every forward migration', record['fresh_final_fingerprints'] == preserved)
            safeguards(restored)
        case('both independently owned containers removed', all(t.evidence.get('task_container_removed') for t in targets))
        freeze(); case('all216 admitted inputs and sealed reference remain unchanged')
        record['status'] = 'pass'
    except BaseException as error:
        record.update(status='failed', failure=str(error)); save(); raise
    finally:
        # Cleanup uses the reserved minute inside the same whole600 bound.
        runner.deadline = whole_deadline
        cleanup_errors = []
        for target in targets:
            try:
                target.close()
            except BaseException as error:
                cleanup_errors.append(dict(name=target.name, error=str(error)))
        record['cleanup_errors'] = cleanup_errors
        record['all_task_containers_removed'] = not cleanup_errors and all(t.evidence.get('task_container_removed') for t in targets)
        if cleanup_errors:
            record['status'] = 'failed'
        record['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat(); save()
        record['elapsed_seconds'] = time.monotonic() - started
        save()
    return 0 if record['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
