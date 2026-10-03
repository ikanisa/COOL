#!/usr/bin/env python3
"""Private archive adapter proposal. Hash bindings do not authenticate a reviewer.

Never downloads, finds tools on PATH, broadens the maintained query/migration
contract, restores a hosted target, or certifies complete recovery.
"""
from __future__ import annotations
import argparse
import datetime as dt
import errno
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
import types

BASE_SHA = '9af50d207472eb8a69d5f7c712928b17305fcfb705408f42ad652c39b8bdac92'
BASE_PATH = Path(__file__).with_name('postgres_admission.py').absolute()
if any(p.is_symlink() for p in (BASE_PATH, *BASE_PATH.parents)):
    raise ValueError('PG_ARCHIVE_BASE_SOURCE_INDIRECT')
info = BASE_PATH.lstat()
if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > 65536:
    raise ValueError('PG_ARCHIVE_BASE_SOURCE_UNSAFE')
with BASE_PATH.open('rb') as handle:
    base_bytes = handle.read(65537)
if hashlib.sha256(base_bytes).hexdigest() != BASE_SHA:
    raise ValueError('PG_ARCHIVE_BASE_SOURCE_CHANGED')
pg = types.ModuleType('collect_archive_pinned_postgres_admission')
pg.__file__ = str(BASE_PATH)
exec(compile(base_bytes, str(BASE_PATH), 'exec'), pg.__dict__)
Refused = pg.Refused
BASE_IDENTITY = pg.regular(BASE_PATH, 65536)[1]
PROFILES = {
    'public_schema': ('public_schema.sql', ['--schema=public', '--schema-only', '--no-owner', '--no-privileges']),
    'public_data': ('public_data.sql', ['--schema=public', '--data-only', '--no-owner', '--no-privileges', '--format=plain']),
    'full_custom': ('database.dump', ['--format=custom', '--lock-wait-timeout=10s']),
    'restore_custom': (None, []),
}


def fail(condition, code):
    if not condition:
        raise Refused(code)


def pinned(ref, limit):
    fail(isinstance(ref, dict) and set(ref) == {'path', 'sha256'} and isinstance(ref['path'], str)
         and isinstance(ref['sha256'], str) and pg.HASH.fullmatch(ref['sha256']), 'PG_ARCHIVE_REFERENCE_INVALID')
    raw, identity = pg.regular(ref['path'], limit)
    fail(pg.sha(raw) == ref['sha256'], 'PG_ARCHIVE_BINDING_CHANGED')
    return raw, identity


def json_value(raw):
    try:
        value = json.loads(raw, object_pairs_hook=pg.unique)
    except (ValueError, UnicodeError) as error:
        raise Refused('PG_ARCHIVE_JSON_INVALID') from error
    fail(isinstance(value, dict), 'PG_ARCHIVE_JSON_INVALID')
    return value


def instant(value):
    try:
        result = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
        fail(result.utcoffset() == dt.timedelta(0), 'PG_ARCHIVE_TIME_INVALID')
        return result
    except (TypeError, ValueError, AttributeError) as error:
        raise Refused('PG_ARCHIVE_TIME_INVALID') from error


def group_exists(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False


def cleanup_group(process):
    """Kill/reap this runner's group and require absence within five seconds."""
    deadline = time.monotonic() + 5
    while True:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=max(0.001, deadline - time.monotonic()))
        except subprocess.TimeoutExpired as error:
            raise Refused('PG_ARCHIVE_GROUP_CLEANUP_TIMEOUT') from error
        if not group_exists(process.pid):
            return
        left = deadline - time.monotonic()
        fail(left > 0, 'PG_ARCHIVE_GROUP_CLEANUP_TIMEOUT')
        time.sleep(min(0.01, left))


def run(argv, env, timeout, limit, output=None, input_file=None):
    """Drain genuine stdout/stderr under one deadline; input is an admitted fd.

    Archives stream to an exclusive owner-only file rather than accumulate in
    memory. No raw child output or stderr is emitted on failure.
    """
    process = None
    failed = True
    result = bytearray()
    errors = bytearray()
    count = 0
    try:
        process = subprocess.Popen(argv, env=env, stdin=input_file or subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        deadline = time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            for stream, name in ((process.stdout, 'out'), (process.stderr, 'err')):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ, name)
            while selector.get_map():
                left = deadline - time.monotonic()
                fail(left > 0, 'PG_ARCHIVE_COMMAND_TIMEOUT')
                for key, _ in selector.select(min(left, 0.1)):
                    try:
                        chunk = os.read(key.fileobj.fileno(), 16384)
                    except BlockingIOError as error:
                        if error.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                            continue
                        raise
                    if not chunk:
                        selector.unregister(key.fileobj)
                    elif key.data == 'err':
                        errors.extend(chunk)
                        fail(len(errors) <= pg.OUTPUT_LIMIT, 'PG_ARCHIVE_STDERR_LIMIT')
                    else:
                        count += len(chunk)
                        fail(count <= limit, 'PG_ARCHIVE_STDOUT_LIMIT')
                        if output is None:
                            result.extend(chunk)
                        else:
                            output.write(chunk)
            try:
                code = process.wait(timeout=max(0.001, deadline - time.monotonic()))
            except subprocess.TimeoutExpired as error:
                raise Refused('PG_ARCHIVE_COMMAND_TIMEOUT') from error
        fail(time.monotonic() <= deadline, 'PG_ARCHIVE_COMMAND_TIMEOUT')
        fail(code == 0, 'PG_ARCHIVE_COMMAND_FAILED')
        fail(not errors, 'PG_ARCHIVE_COMMAND_WARNINGS_REFUSED')
        fail(not group_exists(process.pid), 'PG_ARCHIVE_RESIDUAL_PROCESS_GROUP')
        fail(time.monotonic() <= deadline, 'PG_ARCHIVE_COMMAND_TIMEOUT')
        failed = False
        return bytes(result), count
    except OSError as error:
        raise Refused('PG_ARCHIVE_COMMAND_UNAVAILABLE') from error
    finally:
        if process is not None:
            try:
                if failed or process.poll() is None:
                    cleanup_group(process)
            finally:
                for stream in (process.stdout, process.stderr):
                    if stream is not None:
                        stream.close()
                if not failed:
                    fail(time.monotonic() <= deadline, 'PG_ARCHIVE_COMMAND_TIMEOUT')


class ArchiveAdmission:
    def __init__(self, manifest, manifest_sha256, operation, operation_sha256, env=None):
        self.env = dict(os.environ if env is None else env)
        self.manifest_ref = {'path': manifest, 'sha256': manifest_sha256}
        self.job_ref = {'path': operation, 'sha256': operation_sha256}
        raw, self.manifest_identity = pinned(self.manifest_ref, 16384)
        self.value = json_value(raw)
        raw, self.job_identity = pinned(self.job_ref, 16384)
        self.job = json_value(raw)
        keys = {'schema_version', 'kind', 'review_reference', 'adapter_sha256', 'base_admission', 'clients', 'profiles', 'server_version_num', 'artifact_limit_bytes', 'tls_rootcert'}
        fail(set(self.value) == keys and type(self.value['schema_version']) is int and self.value['schema_version'] == 1
             and self.value['kind'] == 'collect_postgres_archive_admission', 'PG_ARCHIVE_MANIFEST_SCHEMA_INVALID')
        self.adapter_ref = {'path': str(Path(__file__).absolute()), 'sha256': self.value['adapter_sha256']}
        _, self.adapter_identity = pinned(self.adapter_ref, 65536)
        for record in (self.value, self.job):
            fail(isinstance(record.get('review_reference'), str) and re.fullmatch(r'[A-Za-z0-9._:/-]{1,160}', record['review_reference']),
                 'PG_ARCHIVE_REVIEW_REFERENCE_REQUIRED')
        fail(type(self.value['server_version_num']) is int and self.value['server_version_num'] == 170006,
             'PG_ARCHIVE_SERVER_OUTSIDE_PROPOSED_COHORT')
        fail(type(self.value['artifact_limit_bytes']) is int and 1024 <= self.value['artifact_limit_bytes'] <= 1024**3,
             'PG_ARCHIVE_ARTIFACT_LIMIT_INVALID')
        profiles = self.value['profiles']
        fail(isinstance(profiles, list) and profiles and len(set(profiles)) == len(profiles)
             and all(p in PROFILES for p in profiles), 'PG_ARCHIVE_PROFILE_INVALID')
        job_keys = {'schema_version', 'kind', 'review_reference', 'approved_at_utc', 'expires_at_utc', 'manifest_sha256',
                    'operation', 'profiles', 'target', 'source_binding', 'output_directory', 'input'}
        fail(set(self.job) == job_keys and type(self.job['schema_version']) is int and self.job['schema_version'] == 1
             and self.job['kind'] == 'collect_postgres_archive_operation_binding'
             and self.job['manifest_sha256'] == manifest_sha256, 'PG_ARCHIVE_OPERATION_BINDING_INVALID')
        self.time_guard()
        selected = self.job['profiles']
        fail(isinstance(selected, list) and selected and len(set(selected)) == len(selected)
             and set(selected) <= set(profiles), 'PG_ARCHIVE_OPERATION_SCOPE_INVALID')
        op = self.job['operation']
        fail(op in {'dump', 'restore'} and (op == 'restore' and selected == ['restore_custom']
             or op == 'dump' and 'restore_custom' not in selected and ('full_custom' not in selected or selected == ['full_custom'])),
             'PG_ARCHIVE_OPERATION_SCOPE_INVALID')
        # A current hosted restore controller/approval contract does not exist.
        fail(op != 'restore' or isinstance(self.job['target'], dict) and self.job['target'].get('kind') == 'local_rehearsal',
             'PG_ARCHIVE_HOSTED_RESTORE_ADAPTER_ABSENT')
        self.source_raw, self.source_identity = pinned(self.job['source_binding'], 32 * 1024 * 1024)
        self.tls_identity = None
        if self.value['tls_rootcert'] is not None:
            _, self.tls_identity = pinned(self.value['tls_rootcert'], 65536)
        self.directory = Path(self.job['output_directory'])
        fail(self.directory.is_absolute() and '..' not in self.directory.parts
             and not any(p.is_symlink() for p in (self.directory, *self.directory.parents)), 'PG_ARCHIVE_PRIVATE_DIRECTORY_REQUIRED')
        self.base = pg.Admission(self.value['base_admission']['path'], self.value['base_admission']['sha256'], self.env, 'query')
        fail(sum(t == self.job['target'] for t in self.base.value['targets']) == 1, 'PG_ARCHIVE_TARGET_UNBOUND')
        clients = self.value['clients']
        fail(isinstance(clients, dict) and set(clients) == {'pg_dump', 'pg_restore'}, 'PG_ARCHIVE_CLIENTS_REQUIRED')
        self.clients = {}
        self.identities = {}
        for name, value in clients.items():
            fail(isinstance(value, dict) and set(value) == {'path', 'sha256', 'version'}
                 and value['version'] == '17.6', 'PG_ARCHIVE_CLIENT_OUTSIDE_PROPOSED_COHORT')
            ref = {'path': value['path'], 'sha256': value['sha256']}
            _, self.identities[name] = pinned(ref, 128 * 1024 * 1024)
            fail(os.access(value['path'], os.X_OK), 'PG_ARCHIVE_CLIENT_NOT_EXECUTABLE')
            self.clients[name] = ref
        paths = [str(self.base.client)] + [c['path'] for c in self.clients.values()]
        fail(len(set(paths)) == 3, 'PG_ARCHIVE_CLIENT_ROLES_NOT_DISTINCT')
        self.input_binding = None
        if op == 'dump':
            fail(self.job['input'] is None, 'PG_ARCHIVE_DUMP_INPUT_UNEXPECTED')
        else:
            self.admit_input()
        self.probe_clients()

    @classmethod
    def from_environment(cls, env=None):
        env = os.environ if env is None else env
        return cls(env.get('COLLECT_POSTGRES_ARCHIVE_ADMISSION'), env.get('COLLECT_POSTGRES_ARCHIVE_ADMISSION_SHA256'),
                   env.get('COLLECT_POSTGRES_ARCHIVE_OPERATION'), env.get('COLLECT_POSTGRES_ARCHIVE_OPERATION_SHA256'), env)

    def time_guard(self):
        approved, expires = instant(self.job['approved_at_utc']), instant(self.job['expires_at_utc'])
        fail(approved <= dt.datetime.now(dt.timezone.utc) < expires and dt.timedelta(0) < expires - approved <= dt.timedelta(hours=24),
             'PG_ARCHIVE_OPERATION_EXPIRED_OR_FUTURE')

    def guard(self):
        self.time_guard()
        fail(not any(p.is_symlink() for p in (self.directory, *self.directory.parents)), 'PG_ARCHIVE_PRIVATE_DIRECTORY_REQUIRED')
        for ref, expected, limit in [(self.manifest_ref, self.manifest_identity, 16384), (self.job_ref, self.job_identity, 16384),
                                     (self.adapter_ref, self.adapter_identity, 65536), (self.job['source_binding'], self.source_identity, 32 * 1024 * 1024)]:
            fail(pinned(ref, limit)[1] == expected, 'PG_ARCHIVE_INPUT_IDENTITY_CHANGED')
        fail(pg.regular(BASE_PATH, 65536) == (base_bytes, BASE_IDENTITY), 'PG_ARCHIVE_BASE_SOURCE_CHANGED')
        if self.tls_identity is not None:
            fail(pinned(self.value['tls_rootcert'], 65536)[1] == self.tls_identity, 'PG_ARCHIVE_TLS_IDENTITY_CHANGED')
        self.base.guard()
        for name, ref in self.clients.items():
            fail(pinned(ref, 128 * 1024 * 1024)[1] == self.identities[name], 'PG_ARCHIVE_CLIENT_IDENTITY_CHANGED')
            override = self.env.get({'pg_dump': 'PG_DUMP_BIN', 'pg_restore': 'PG_RESTORE_BIN'}[name])
            fail(not override or override == ref['path'], 'PG_ARCHIVE_CLIENT_OVERRIDE_UNBOUND')

    def probe_clients(self):
        self.guard()
        values = [('psql', {'path': str(self.base.client)})] + list(self.clients.items())
        for name, ref in values:
            out, _ = run([ref['path'], '--version'], pg.local_environment(), self.base.value['timeouts']['version_seconds'], 1024)
            fail(out in ((f'{name} (PostgreSQL) 17.6\n').encode(), (f'{name} (PostgreSQL) 17.6\r\n').encode()),
                 'PG_ARCHIVE_CLIENT_VERSION_UNKNOWN_OR_DRIFTED')
        self.guard()

    def admit_input(self):
        value = self.job['input']
        fail(isinstance(value, dict) and set(value) == {'archive', 'bytes', 'capture_receipt'}, 'PG_ARCHIVE_RESTORE_INPUT_INVALID')
        raw, identity = pinned(value['archive'], self.value['artifact_limit_bytes'])
        fail(type(value['bytes']) is int and len(raw) == value['bytes'] and raw.startswith(b'PGDMP'), 'PG_ARCHIVE_RESTORE_INPUT_INVALID')
        receipt_raw, receipt_identity = pinned(value['capture_receipt'], 65536)
        receipt = json_value(receipt_raw)
        fail(receipt.get('kind') == 'collect_pg_archive_client_receipt' and receipt.get('status') == 'client_completed_artifact_bound'
             and receipt.get('operation') == 'dump' and receipt.get('profile') == 'full_custom'
             and receipt.get('manifest_sha256') == self.manifest_ref['sha256']
             and receipt.get('source_binding') == self.job['source_binding']
             and receipt.get('artifact') == dict(value['archive'], bytes=value['bytes'])
             and receipt.get('server_version_num') == 170006, 'PG_ARCHIVE_CAPTURE_RECEIPT_MISMATCH')
        fail(self.input_binding is None or self.input_binding == (identity, receipt_identity), 'PG_ARCHIVE_RESTORE_INPUT_CHANGED')
        self.input_binding = (identity, receipt_identity)

    def credentials(self, env):
        service, service_identity = self.base.service(env)
        # Confirm this exact service is the operation target, not another
        # permitted target in the base manifest.
        import configparser
        parser = configparser.ConfigParser(interpolation=None, strict=True)
        parser.read_string(service.decode())
        values = parser['collect_readiness']
        fail(not set(values) - {'host', 'port', 'user', 'dbname', 'sslmode', 'sslrootcert', 'connect_timeout', 'application_name'},
             'PG_ARCHIVE_CONNECTION_OPTIONS_UNBOUND')
        target = self.job['target']
        fail((values.get('host'), int(values.get('port', '5432')), values.get('user'), values.get('dbname'))
             == (target['host'], target['port'], target['user'], target['database']), 'PG_ARCHIVE_SERVICE_TARGET_MISMATCH')
        clean = pg.local_environment()
        clean.update(PGSERVICEFILE=env['PGSERVICEFILE'], PGPASSFILE='/dev/null', PGCONNECT_TIMEOUT='15')
        password = None
        if env.get('PGPASSFILE'):
            password = pg.regular(env['PGPASSFILE'], 8192)
            fail(not password[1][3] & 0o077, 'PG_ARCHIVE_PASSWORD_PERMISSIONS_INVALID')
            clean['PGPASSFILE'] = env['PGPASSFILE']
        if target['kind'] == 'supabase':
            fail(values.get('sslmode') == 'verify-full' and self.value['tls_rootcert'] is not None
                 and values.get('sslrootcert') == self.value['tls_rootcert']['path'], 'PG_ARCHIVE_HOSTED_PINNED_TLS_REQUIRED')
        else:
            fail(values.get('sslmode') == 'disable' and 'sslrootcert' not in values, 'PG_ARCHIVE_LOCAL_TLS_SCOPE_INVALID')
        return clean, (service, service_identity), password

    def credential_guard(self, env, service, password):
        fail(pg.regular(env['PGSERVICEFILE'], 8192) == service, 'PG_ARCHIVE_SERVICE_CHANGED')
        if password is not None:
            fail(pg.regular(env['PGPASSFILE'], 8192) == password, 'PG_ARCHIVE_PASSWORD_CHANGED')

    def server_probe(self, clean):
        self.probe_clients()
        query = "BEGIN READ ONLY; SET LOCAL statement_timeout='15000ms'; " + pg.SERVER_QUERY + ' COMMIT;'
        out, _ = run([str(self.base.client), 'service=collect_readiness', '-X', '-w', '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', query],
                     clean, self.base.value['timeouts']['server_seconds'], 1024)
        fail(re.fullmatch(rb'[0-9]{6}\r?\n', out), 'PG_ARCHIVE_SERVER_RESPONSE_INVALID')
        self.base.server(int(out))
        fail(int(out) == 170006, 'PG_ARCHIVE_SERVER_OUTSIDE_PROPOSED_COHORT')
        return int(out)

    def directory_guard(self):
        fail(self.directory.is_dir() and not self.directory.is_symlink(), 'PG_ARCHIVE_PRIVATE_DIRECTORY_REQUIRED')
        info = self.directory.stat()
        fail(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700, 'PG_ARCHIVE_DIRECTORY_PERMISSIONS_INVALID')

    def private_output(self, name):
        self.directory_guard()
        handle = (self.directory / name).open('xb')
        os.fchmod(handle.fileno(), 0o600)
        return handle

    def execute(self, args, env):
        self.guard()
        fail(args and args[0] == 'service=collect_readiness', 'PG_ARCHIVE_BOUND_SERVICE_REQUIRED')
        profile = None
        for selected in self.job['profiles']:
            name, flags = PROFILES[selected]
            if self.job['operation'] == 'dump' and args == ['service=collect_readiness', *flags, '--file=' + str(self.directory / name)]:
                profile = selected
            if self.job['operation'] == 'restore' and args == ['service=collect_readiness', '--exit-on-error', '--single-transaction', self.job['input']['archive']['path']]:
                profile = selected
        fail(profile is not None, 'PG_ARCHIVE_ARGUMENT_SCOPE_REFUSED')
        self.directory_guard()
        if profile != 'restore_custom':
            fail(not (self.directory / PROFILES[profile][0]).exists()
                 and not (self.directory / (PROFILES[profile][0] + '.admission.json')).exists(), 'PG_ARCHIVE_OUTPUT_EXISTS')
        clean, service, password = self.credentials(env)
        input_file = None
        output_file = None
        output_identity = None
        artifact_path = self.directory / PROFILES[profile][0] if profile != 'restore_custom' else None
        try:
            if profile == 'restore_custom':
                self.admit_input()
                # The validated inode stays open as stdin for listing/restore.
                input_file = open(self.job['input']['archive']['path'], 'rb')
                observed = os.fstat(input_file.fileno())
                fail((observed.st_dev, observed.st_ino, observed.st_size, observed.st_mode, observed.st_mtime_ns, observed.st_nlink) == self.input_binding[0],
                     'PG_ARCHIVE_RESTORE_INPUT_CHANGED')
                fail(pg.regular(self.job['input']['archive']['path'], self.value['artifact_limit_bytes'])[1] == self.input_binding[0],
                     'PG_ARCHIVE_RESTORE_INPUT_CHANGED')
                self.probe_clients()
                listing, _ = run([self.clients['pg_restore']['path'], '--list'], pg.local_environment(),
                                 self.base.value['timeouts']['operation_seconds'], pg.OUTPUT_LIMIT, input_file=input_file)
                fail(bool(listing), 'PG_ARCHIVE_TOC_EMPTY')
                input_file.seek(0)
            number = self.server_probe(clean)
            self.credential_guard(env, service, password)
            self.probe_clients()  # Re-observe actual banners immediately before use.
            self.credential_guard(env, service, password)
            if profile == 'restore_custom':
                self.admit_input()
                argv = [self.clients['pg_restore']['path'], '--dbname=service=collect_readiness', '-w', '--exit-on-error', '--single-transaction']
                raw, count = run(argv, clean, self.base.value['timeouts']['operation_seconds'], pg.OUTPUT_LIMIT, input_file=input_file)
                artifact = dict(self.job['input']['archive'], bytes=self.job['input']['bytes'])
                self.admit_input()
            else:
                output_file = self.private_output(PROFILES[profile][0])
                observed = os.fstat(output_file.fileno())
                output_identity = (observed.st_dev, observed.st_ino)
                flags = PROFILES[profile][1]
                argv = [self.clients['pg_dump']['path'], '--dbname=service=collect_readiness', '-w', *flags]
                readonly = dict(clean, PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=120000')
                _, count = run(argv, readonly, self.base.value['timeouts']['operation_seconds'], self.value['artifact_limit_bytes'], output=output_file)
                output_file.flush(); os.fsync(output_file.fileno()); output_file.close(); output_file = None
                data, _ = pg.regular(artifact_path, self.value['artifact_limit_bytes'])
                fail(count == len(data) and count > 0 and (profile != 'full_custom' or data.startswith(b'PGDMP')), 'PG_ARCHIVE_ARTIFACT_INVALID')
                artifact = {'path': str(artifact_path), 'sha256': pg.sha(data), 'bytes': count}
            self.guard()
            self.credential_guard(env, service, password)
            receipt = dict(kind='collect_pg_archive_client_receipt', status='client_completed_artifact_bound', operation=self.job['operation'], profile=profile,
                           manifest_sha256=self.manifest_ref['sha256'], operation_sha256=self.job_ref['sha256'], source_binding=self.job['source_binding'],
                           target=self.job['target'], artifact=artifact, clients=self.value['clients'], psql_sha256=self.base.value['client']['sha256'],
                           client_version_num=170006, server_version_num=number, argv_profile=profile, human_review_authenticated=False,
                           source_contract_semantics_validated=False, encrypted_destination_verified=False,
                           full_catalog_ACL_projection_recovery_accepted=False, production_ready=False)
            if profile == 'restore_custom':
                receipt['capture_receipt'] = self.job['input']['capture_receipt']
                receipt['toc_sha256'] = pg.sha(listing)
                receipt['client_stdout_sha256'] = pg.sha(raw)
            receipt_name = (artifact_path.name if artifact_path else 'restore') + '.admission.json'
            with self.private_output(receipt_name) as stream:
                stream.write((json.dumps(receipt, sort_keys=True, indent=2) + '\n').encode())
                stream.flush(); os.fsync(stream.fileno())
            return receipt
        except BaseException:
            if output_file is not None:
                output_file.close()
            if artifact_path is not None and output_identity is not None:
                # Never delete an existing file which the adapter did not create.
                if artifact_path.exists() and (artifact_path.stat().st_dev, artifact_path.stat().st_ino) == output_identity:
                    artifact_path.unlink(missing_ok=True)
            raise
        finally:
            if input_file is not None:
                input_file.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['output-directory', 'dump', 'restore'])
    parser.add_argument('args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        admitted = ArchiveAdmission.from_environment()
        if args.action == 'output-directory':
            fail(not args.args and admitted.job['operation'] == 'dump', 'PG_ARCHIVE_OPERATION_SCOPE_INVALID')
            print(admitted.directory)
        else:
            fail(admitted.job['operation'] == args.action, 'PG_ARCHIVE_OPERATION_SCOPE_INVALID')
            arguments = args.args[1:] if args.args[:1] == ['--'] else args.args
            admitted.execute(arguments, os.environ)
        return 0
    except (Refused, KeyError, TypeError, OSError) as error:
        print('[pg-archive-admission][REFUSED] ' + (str(error) if isinstance(error, Refused) else 'PG_ARCHIVE_INPUT_INVALID'), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
