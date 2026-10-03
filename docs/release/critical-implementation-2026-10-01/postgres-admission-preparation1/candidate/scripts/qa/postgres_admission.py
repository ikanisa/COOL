#!/usr/bin/env python3
"""Admit an externally reviewed PostgreSQL client/matrix; never create approval.

No installer, PATH search, remote probe or database write runs during local
admission. Server compatibility can only be observed after a target-bound read.
The retained manifest digest is a binding, not authentication of its reviewer.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
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

HASH = re.compile(r'[a-f0-9]{64}')
VERSION = re.compile(r'(?:1[4-9]|[2-9][0-9])\.[0-9]{1,3}')
REF = re.compile(r'[a-z0-9]{20}')
SERVER_QUERY = "select current_setting('server_version_num')::integer as server_version_num;"
MANIFEST_LIMIT = 16384
OUTPUT_LIMIT = 2 * 1024 * 1024
OPERATIONS = {'query', 'migration', 'restore'}


class Refused(ValueError):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise Refused('PG_DUPLICATE_JSON_KEY')
        value[key] = item
    return value


def regular(path, limit):
    """Do not follow path substitutions, including a substituted parent."""
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts:
        raise Refused('PG_ABSOLUTE_PATH_REQUIRED')
    try:
        if any(p.is_symlink() for p in (path, *path.parents)):
            raise Refused('PG_SYMLINK_REFUSED')
        fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
        with os.fdopen(fd, 'rb') as handle:
            before = os.fstat(handle.fileno())
            if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit:
                raise Refused('PG_REGULAR_SINGLE_LINK_INPUT_REQUIRED')
            data = handle.read(limit + 1)
            after = os.fstat(handle.fileno())
        observed = path.lstat()
        identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mode, s.st_mtime_ns, s.st_nlink)
        if len(data) > limit or identity(before) != identity(after) or identity(after) != identity(observed):
            raise Refused('PG_INPUT_CHANGED_DURING_READ')
        return data, identity(after)
    except OSError as error:
        raise Refused('PG_INPUT_UNAVAILABLE') from error


def bounded(argv, env, timeout, limit=OUTPUT_LIMIT, inherit_stdin=False):
    """Bound both output streams while running; never return raw tool stderr."""
    process = None
    failed = True
    try:
        process = subprocess.Popen(argv, env=env, stdin=None if inherit_stdin else subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        streams = {'stdout': bytearray(), 'stderr': bytearray()}
        deadline = time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
            selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
            while selector.get_map():
                left = deadline - time.monotonic()
                if left <= 0:
                    raise Refused('PG_COMMAND_TIMEOUT')
                for key, _ in selector.select(min(left, 0.1)):
                    chunk = os.read(key.fileobj.fileno(), 16384)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    streams[key.data].extend(chunk)
                    if len(streams[key.data]) > limit:
                        raise Refused('PG_COMMAND_OUTPUT_LIMIT')
            try:
                code = process.wait(timeout=max(0.001, deadline - time.monotonic()))
            except subprocess.TimeoutExpired as error:
                raise Refused('PG_COMMAND_TIMEOUT') from error
        failed = False
        return code, bytes(streams['stdout'])
    except OSError as error:
        raise Refused('PG_COMMAND_UNAVAILABLE') from error
    finally:
        if process is not None:
            # Descendants which retain pipes share this new process group.
            if failed or process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    stream.close()


def local_environment():
    # Never lend release/database credentials or loader injection variables to
    # an executable's version probe. Selection is already an absolute path.
    return {'PATH': os.defpath, 'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}


class Admission:
    def __init__(self, manifest, expected_sha256, env=None, operation='query'):
        self.env = os.environ if env is None else env
        self.path = Path(manifest or '')
        self.expected = expected_sha256
        self.operation = operation
        if not HASH.fullmatch(expected_sha256 or '') or operation not in OPERATIONS:
            raise Refused('PG_MANIFEST_BINDING_REQUIRED')
        raw, self.manifest_identity = regular(self.path, MANIFEST_LIMIT)
        if sha(raw) != expected_sha256:
            raise Refused('PG_MANIFEST_HASH_CHANGED')
        try:
            value = json.loads(raw, object_pairs_hook=unique)
        except (ValueError, UnicodeError) as error:
            raise Refused('PG_MANIFEST_JSON_INVALID') from error
        keys = {'schema_version', 'kind', 'review_reference', 'client', 'server_matrix', 'targets', 'timeouts'}
        if not isinstance(value, dict) or set(value) != keys or type(value['schema_version']) is not int or value['schema_version'] != 1 or value['kind'] != 'collect_postgres_admission':
            raise Refused('PG_MANIFEST_SCHEMA_INVALID')
        review = value['review_reference']
        if not isinstance(review, str) or not re.fullmatch(r'[A-Za-z0-9._:/-]{1,160}', review):
            raise Refused('PG_REVIEW_REFERENCE_REQUIRED')
        client = value['client']
        if not isinstance(client, dict) or set(client) != {'path', 'sha256', 'version'} or not isinstance(client['path'], str) or not HASH.fullmatch(client.get('sha256', '')) or not VERSION.fullmatch(client.get('version', '')):
            raise Refused('PG_CLIENT_SCHEMA_INVALID')
        self.client = Path(client['path'])
        raw_client, self.client_identity = regular(self.client, 128 * 1024 * 1024)
        if not os.access(self.client, os.X_OK) or sha(raw_client) != client['sha256']:
            raise Refused('PG_CLIENT_HASH_CHANGED_OR_NOT_EXECUTABLE')
        if self.env.get('PSQL_BIN') and self.env['PSQL_BIN'] != str(self.client):
            raise Refused('PG_CLIENT_OVERRIDE_UNBOUND')
        matrix = value['server_matrix']
        if not isinstance(matrix, list) or not 1 <= len(matrix) <= 16:
            raise Refused('PG_MATRIX_REQUIRED')
        for row in matrix:
            if not isinstance(row, dict) or set(row) != {'client_version', 'server_version_num_min', 'server_version_num_max', 'operations'}:
                raise Refused('PG_MATRIX_INVALID')
            low, high, ops = row['server_version_num_min'], row['server_version_num_max'], row['operations']
            if row['client_version'] != client['version'] or type(low) is not int or type(high) is not int or not 140000 <= low <= high <= 999999 or low // 10000 != high // 10000 or not isinstance(ops, list) or not ops or len(set(ops)) != len(ops) or any(op not in OPERATIONS for op in ops):
                raise Refused('PG_MATRIX_INVALID')
        targets = value['targets']
        if not isinstance(targets, list) or not 1 <= len(targets) <= 8:
            raise Refused('PG_TARGETS_REQUIRED')
        for target in targets:
            if not isinstance(target, dict) or set(target) != {'kind', 'project_ref', 'host', 'port', 'user', 'database'} or type(target['port']) is not int or not 1 <= target['port'] <= 65535:
                raise Refused('PG_TARGET_INVALID')
            if any(not isinstance(target[key], str) or not target[key] or len(target[key]) > 160 or any(ord(c) < 33 for c in target[key]) for key in ('host', 'user', 'database')):
                raise Refused('PG_TARGET_INVALID')
            if target['kind'] == 'supabase':
                ref = target['project_ref']
                bound = target['host'] == f'db.{ref}.supabase.co' or (target['host'].endswith('.pooler.supabase.com') and target['user'] == f'postgres.{ref}')
                if not isinstance(ref, str) or not REF.fullmatch(ref) or not bound or target['database'] != 'postgres':
                    raise Refused('PG_TARGET_INVALID')
            elif target['kind'] != 'local_rehearsal' or target['project_ref'] is not None or target['host'] not in {'localhost', '127.0.0.1', '::1'}:
                raise Refused('PG_TARGET_INVALID')
        limits = value['timeouts']
        if not isinstance(limits, dict) or set(limits) != {'version_seconds', 'server_seconds', 'operation_seconds'}:
            raise Refused('PG_TIMEOUTS_INVALID')
        for name, ceiling in [('version_seconds', 10), ('server_seconds', 30), ('operation_seconds', 600)]:
            if type(limits[name]) not in (int, float) or not 0.05 <= limits[name] <= ceiling:
                raise Refused('PG_TIMEOUTS_INVALID')
        self.value = value
        code, observed = bounded([str(self.client), '--version'], local_environment(), limits['version_seconds'], limit=1024)
        if code or observed not in ((f"psql (PostgreSQL) {client['version']}\n").encode(), (f"psql (PostgreSQL) {client['version']}\r\n").encode()):
            raise Refused('PG_CLIENT_VERSION_UNKNOWN_OR_WRONG')
        self.guard()

    @classmethod
    def from_environment(cls, env=None, operation='query'):
        env = os.environ if env is None else env
        return cls(env.get('COLLECT_POSTGRES_ADMISSION'), env.get('COLLECT_POSTGRES_ADMISSION_SHA256'), env, operation)

    def guard(self):
        manifest, identity = regular(self.path, MANIFEST_LIMIT)
        client, client_identity = regular(self.client, 128 * 1024 * 1024)
        if sha(manifest) != self.expected or identity != self.manifest_identity:
            raise Refused('PG_MANIFEST_CHANGED_AFTER_ADMISSION')
        if sha(client) != self.value['client']['sha256'] or client_identity != self.client_identity:
            raise Refused('PG_CLIENT_CHANGED_AFTER_ADMISSION')
        if self.env.get('PSQL_BIN') and self.env['PSQL_BIN'] != str(self.client):
            raise Refused('PG_CLIENT_OVERRIDE_UNBOUND')

    def project(self, ref):
        if not any(t['kind'] == 'supabase' and t['project_ref'] == ref for t in self.value['targets']):
            raise Refused('PG_APPROVED_PROJECT_NOT_IN_MANIFEST')

    def server(self, number):
        self.guard()
        if type(number) is not int or not any(r['server_version_num_min'] <= number <= r['server_version_num_max'] and self.operation in r['operations'] for r in self.value['server_matrix']):
            raise Refused('PG_SERVER_MATRIX_REFUSED')
        return {'manifest_sha256': self.expected, 'client_version': self.value['client']['version'],
                'client_sha256': self.value['client']['sha256'], 'server_version_num': number,
                'operation': self.operation, 'observed_after_target_bound_read': True,
                'human_review_authenticated': False}

    def management_rows(self, raw, ref):
        self.project(ref)
        try:
            rows = json.loads(raw, object_pairs_hook=unique)
        except (ValueError, UnicodeError) as error:
            raise Refused('PG_SERVER_RESPONSE_INVALID') from error
        if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict) or set(rows[0]) != {'server_version_num'}:
            raise Refused('PG_SERVER_RESPONSE_INVALID')
        return self.server(rows[0]['server_version_num'])

    def service(self, env):
        raw, identity = regular(Path(env.get('PGSERVICEFILE', '')), 8192)
        if identity[3] & 0o077:
            raise Refused('PG_SERVICE_PERMISSIONS_INVALID')
        parser = configparser.ConfigParser(interpolation=None, strict=True)
        try:
            parser.read_string(raw.decode())
            if parser.sections() != ['collect_readiness'] or parser.defaults():
                raise ValueError()
            value = dict(parser['collect_readiness'])
            port = int(value.get('port', '5432'))
        except (ValueError, UnicodeError, configparser.Error) as error:
            raise Refused('PG_SERVICE_INVALID') from error
        # options/hostaddr/service/passfile can change the reviewed connection
        # or session. Other existing libpq security/keepalive options remain.
        allowed = {'host', 'dbname', 'port', 'user', 'sslmode', 'connect_timeout', 'channel_binding', 'application_name', 'target_session_attrs', 'gssencmode', 'sslrootcert', 'sslcert', 'sslkey', 'keepalives', 'keepalives_idle', 'keepalives_interval', 'keepalives_count'}
        if set(value) - allowed:
            raise Refused('PG_SERVICE_OPTIONS_UNBOUND')
        matches = [t for t in self.value['targets'] if (t['host'], t['port'], t['user'], t['database']) == (value.get('host'), port, value.get('user'), value.get('dbname'))]
        if len(matches) != 1:
            raise Refused('PG_SERVICE_TARGET_UNBOUND')
        if matches[0]['kind'] == 'supabase' and env.get('SUPABASE_PROJECT_REF') != matches[0]['project_ref']:
            raise Refused('PG_SERVICE_PROJECT_MISMATCH')
        return raw, identity

    def psql(self, args, env):
        if not args or args[0] != 'service=collect_readiness':
            raise Refused('PG_BOUND_SERVICE_ARGUMENT_REQUIRED')
        # Exclude every connection argument. SQL/file/variable/output flags
        # retain their existing semantics; SQL authorization is caller-owned.
        allowed = {'-Atq', '-At', '-q', '-X', '-A', '-t', '-v', '-c', '-f'}
        index = 1
        while index < len(args):
            flag = args[index]
            if flag not in allowed:
                raise Refused('PG_CLIENT_ARGUMENT_UNBOUND')
            index += 1
            if flag in {'-v', '-c', '-f'}:
                if index == len(args):
                    raise Refused('PG_CLIENT_ARGUMENT_INVALID')
                index += 1
        service_raw, identity = self.service(env)
        clean = dict(env)
        for name in list(clean):
            if name.startswith('PG') or name in {'BASH_ENV', 'ENV', 'LD_PRELOAD', 'PYTHONPATH', 'PYTHONHOME', 'SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'DATABASE_URL', 'DATABASE_POOLER_URL', 'READINESS_DATABASE_URL', 'COLLECT_PSQL_URL'} or name.startswith('DYLD_'):
                clean.pop(name, None)
        clean.update(PGSERVICEFILE=env['PGSERVICEFILE'], PGCONNECT_TIMEOUT='15')
        password = None
        if env.get('PGPASSFILE'):
            password, pass_identity = regular(Path(env['PGPASSFILE']), 8192)
            if pass_identity[3] & 0o077:
                raise Refused('PG_PASSWORD_FILE_PERMISSIONS_INVALID')
            clean['PGPASSFILE'] = env['PGPASSFILE']
        self.guard()
        code, raw = bounded([str(self.client), 'service=collect_readiness', '-X', '-w', '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', SERVER_QUERY], clean, self.value['timeouts']['server_seconds'], limit=1024)
        if code or not re.fullmatch(rb'[0-9]{6}\r?\n', raw):
            raise Refused('PG_SERVER_RESPONSE_INVALID')
        self.server(int(raw))
        if regular(Path(env['PGSERVICEFILE']), 8192) != (service_raw, identity):
            raise Refused('PG_SERVICE_CHANGED_DURING_PROBE')
        if password is not None and regular(Path(env['PGPASSFILE']), 8192) != (password, pass_identity):
            raise Refused('PG_PASSWORD_FILE_CHANGED_DURING_PROBE')
        self.guard()
        code, data = bounded([str(self.client), *args, '-X', '-w'], clean, self.value['timeouts']['operation_seconds'], inherit_stdin=True)
        if code:
            raise Refused('PG_CLIENT_OPERATION_FAILED')
        self.guard()
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['local', 'project', 'psql'])
    parser.add_argument('args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        admission = Admission.from_environment()
        if args.action == 'project':
            if len(args.args) != 1:
                raise Refused('PG_PROJECT_ARGUMENT_REQUIRED')
            admission.project(args.args[0])
        elif args.action == 'local':
            print(f"psql (PostgreSQL) {admission.value['client']['version']}")
        else:
            argv = args.args[1:] if args.args[:1] == ['--'] else args.args
            sys.stdout.buffer.write(admission.psql(argv, os.environ))
        return 0
    except (Refused, TypeError, KeyError, OSError) as error:
        print('[postgres-admission][FAIL] ' + (str(error) if isinstance(error, Refused) else 'PG_INPUT_INVALID'), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
