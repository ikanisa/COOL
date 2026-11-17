"""Plan, or explicitly install, TLS on the existing retained Supabase PG17.

No container, volume, network, Auth key, HBA policy or connection is replaced.
The default performs only certificate validation and read-only observations.
--execute additionally requires a new protected state file. Any uncertain write
stops without retry, deletion or rollback; the operator must reconcile forward.
"""
from __future__ import annotations
import argparse
import hashlib
import hmac
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tarfile
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.self_hosted.configure import private_file, read_env
from scripts.self_hosted.release_operator import Operator
from scripts.self_hosted.retained_collect import DATABASE, DOCKER_HOST, NETWORK, PROJECT, CLI_LABEL, DockerEngine, probe_database_tls
from scripts.self_hosted.postgres_tls_probe import leaf_sha256

IMAGE = 'sha256:c141fd17ac6a76c4323e90b3aee8ff1a23d2e89e547c2b963cfadc309c079cc2'
VOLUME = 'supabase_db_local-app'
PGDATA = '/var/lib/postgresql/data'
TLS_DIR = PGDATA + '/.collect-tls'
FILES = ('ca.crt', 'server.crt', 'server.key')
MAX_BYTES = 65536
SETTINGS = ('ssl', 'ssl_cert_file', 'ssl_key_file', 'ssl_ca_file')
OBSERVE_SQL = """SELECT json_build_object(
'major',current_setting('server_version_num')::int/10000,
'data_directory',current_setting('data_directory'),'port',current_setting('port'),
'socket_directory',current_setting('unix_socket_directories'),
'bootstrap_role',(SELECT rolname FROM pg_roles WHERE oid=10),
'current_user',current_user,'session_user',session_user,
'superuser',(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),
'file_errors',(SELECT count(*) FROM pg_file_settings WHERE error IS NOT NULL),
'settings',(SELECT json_object_agg(name,json_build_object('setting',setting,
'source',source,'sourcefile',sourcefile,'context',context,'pending_restart',pending_restart))
FROM pg_settings WHERE name IN ('ssl','ssl_cert_file','ssl_key_file','ssl_ca_file')))
"""
ALTERS = (
    "ALTER SYSTEM SET ssl_cert_file = '.collect-tls/server.crt'",
    "ALTER SYSTEM SET ssl_key_file = '.collect-tls/server.key'",
    "ALTER SYSTEM SET ssl = 'on'",
)
RELOAD = 'SELECT pg_reload_conf()'
PRESENCE = 'if test -e ' + TLS_DIR + ' || test -L ' + TLS_DIR + '; then printf present; else printf absent; fi'
PSQL = ('psql', '-XAtq', '--no-password', '-v', 'ON_ERROR_STOP=1', '-h', '/var/run/postgresql',
        '-p', '5432', '-U', 'supabase_admin', '-d', 'postgres', '-c')


class TLSError(RuntimeError):
    def __init__(self, code, *, phase='preflight', reconcile=False):
        super().__init__(code)
        self.phase, self.reconcile = phase, reconcile


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _json(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))


def _openssl(arguments, *, input=None, pass_fds=()):
    try:
        result = subprocess.run(['openssl', *arguments], input=input, pass_fds=pass_fds, capture_output=True, timeout=15)
        if result.returncode or len(result.stdout) + len(result.stderr) > MAX_BYTES:
            raise ValueError()
        return result.stdout
    except Exception:
        raise TLSError('retained_tls_certificate_validation_failed') from None


def _read(engine, arguments, *, input=None):
    try:
        result = engine.readonly(arguments, input=input)
        if result.returncode or len(result.stdout) + len(result.stderr) > MAX_BYTES:
            raise ValueError()
        return result.stdout
    except Exception:
        raise TLSError('retained_tls_metadata_unavailable') from None


def _sql(engine, identity, statement):
    raw = _read(engine, [identity, *PSQL, statement])
    try:
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except Exception:
        raise TLSError('retained_tls_database_metadata_invalid') from None


def _protected_directory(path):
    try:
        info = path.lstat()
        if path.resolve(strict=True) != path or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError()
    except Exception:
        raise TLSError('retained_tls_protected_directory_required') from None


def _explicit_db_san(text):
    """Read only the actual SAN extension in portable x509 -text output.

    Admit exact DNS names only. CNs, comments, nested extension text, URI/IP
    values and duplicate SAN sections cannot supply the hostname proof. The
    generated retained leaf contains DNS:db; no wildcard/CN fallback is needed.
    """
    lines = text.splitlines()
    headers = [index for index, line in enumerate(lines)
               if re.fullmatch(rb' *X509v3 extensions: *', line)]
    if len(headers) != 1:
        return False
    start = headers[0]
    base = len(lines[start]) - len(lines[start].lstrip(b' '))
    block = []
    for line in lines[start + 1:]:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(b' '))
        if indent <= base:
            break
        block.append((indent, line.strip()))
    if not block:
        return False
    extension_indent = min(indent for indent, _ in block)
    sans = [index for index, (indent, line) in enumerate(block) if indent == extension_indent
            and re.fullmatch(rb'X509v3 Subject Alternative Name: *(?:critical)?', line)]
    if len(sans) != 1:
        return False
    values = []
    for indent, line in block[sans[0] + 1:]:
        if indent <= extension_indent:
            break
        values.append(line)
    names = [part.strip() for part in b' '.join(values).split(b',')]
    return bool(names) and all(re.fullmatch(rb'DNS:[A-Za-z0-9][A-Za-z0-9.-]{0,252}', name) for name in names) \
        and any(name.lower() == b'dns:db' for name in names)


class Certificates:
    def __init__(self, operator):
        directory = operator.root / 'private/db-tls'
        _protected_directory(directory.parent)
        _protected_directory(directory)
        if (directory / 'ca.key').exists() or (directory / 'ca.key').is_symlink():
            raise TLSError('retained_tls_ca_private_key_must_stay_outside')
        self._files = {}
        try:
            for name in FILES:
                path = directory / name
                private_file(path)
                if path.stat().st_mode & 0o777 != 0o600 or path.stat().st_size > MAX_BYTES:
                    raise ValueError()
                raw = path.read_bytes()
                if not raw:
                    raise ValueError()
                self._files[name] = raw
        except Exception:
            raise TLSError('retained_tls_owned_0600_inputs_required') from None
        # Validate the bytes captured above, not path contents that could change
        # between validation and archive construction. OpenSSL stdin is private;
        # only public-key DER/SAN output is retained in memory.
        ca, leaf, key = (self._files[name] for name in FILES)
        for certificate in (ca, leaf):
            if re.fullmatch(rb'-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\r?\n?', certificate) is None:
                raise TLSError('retained_tls_public_certificates_required')
            _openssl(['x509', '-checkend', '0', '-noout'], input=certificate)
        if re.fullmatch(rb'-----BEGIN (?:RSA |EC )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]+-----END (?:RSA |EC )?PRIVATE KEY-----\r?\n?', key) is None:
            raise TLSError('retained_tls_unencrypted_leaf_key_required')
        public_key = _openssl(['pkey', '-passin', 'pass:', '-pubout', '-outform', 'DER'], input=key)
        certificate_key = _openssl(['x509', '-pubkey', '-noout'], input=leaf)
        certificate_key = _openssl(['pkey', '-pubin', '-outform', 'DER'], input=certificate_key)
        if not public_key or not hmac.compare_digest(public_key, certificate_key):
            raise TLSError('retained_tls_leaf_key_mismatch')
        text = _openssl(['x509', '-text', '-noout', '-nameopt', 'RFC2253'], input=leaf)
        if not _explicit_db_san(text):
            raise TLSError('retained_tls_explicit_db_san_required')
        # Hold the public CA's validated file descriptor while the captured leaf
        # travels on stdin. No key is written to a temporary file or argv.
        fd = os.open(directory / 'ca.crt', os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if os.read(fd, MAX_BYTES + 1) != ca:
                raise TLSError('retained_tls_certificate_inputs_changed')
            os.lseek(fd, 0, os.SEEK_SET)
            # LibreSSL 3.3 does not expose verify -verify_hostname. The signed
            # exact DNS:db SAN proof above supplies that hostname check, while
            # verify independently authenticates the chain, purpose and time.
            _openssl(['verify', '-CAfile', '/dev/fd/' + str(fd), '-purpose', 'sslserver', '/dev/stdin'],
                     input=leaf, pass_fds=(fd,))
            os.lseek(fd, 0, os.SEEK_SET)
            if os.read(fd, MAX_BYTES + 1) != ca:
                raise TLSError('retained_tls_certificate_inputs_changed')
        finally:
            os.close(fd)
        functions = read_env(operator.root / 'private/functions.env')
        if functions.get('COLLECT_DB_CA_PEM', '').strip().encode() != ca.strip():
            raise TLSError('retained_tls_sealed_client_ca_mismatch')
        self.hashes = {name: _sha(raw) for name, raw in self._files.items()}

    def __repr__(self):
        return 'Certificates(leaf_private_key=redacted)'

    def archive(self, uid, gid):
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode='w', format=tarfile.USTAR_FORMAT) as archive:
            for name in FILES:
                entry = tarfile.TarInfo(name)
                entry.mode, entry.uid, entry.gid = 0o600, uid, gid
                entry.size, entry.mtime = len(self._files[name]), 0
                archive.addfile(entry, io.BytesIO(self._files[name]))
        return output.getvalue()


class TLSRuntime(DockerEngine):
    def write(self, arguments, *, input=None):
        try:
            result = subprocess.run(['docker', '--host', self.host, *arguments], input=input,
                                    capture_output=True, timeout=30)
            if result.returncode or len(result.stdout) + len(result.stderr) > MAX_BYTES:
                raise ValueError()
            return result.stdout
        except Exception:
            raise TLSError('retained_tls_write_outcome_unconfirmed') from None


def observe(engine):
    try:
        container = engine.inspect(DATABASE)
        identity = container['Id']
        volume = engine.request('GET', '/volumes/' + VOLUME)
        network = engine.request('GET', '/networks/' + NETWORK)
        uid = int(_read(engine, [identity, 'id', '-u', 'postgres']).strip())
        gid = int(_read(engine, [identity, 'id', '-g', 'postgres']).strip())
        owner = _read(engine, [identity, 'stat', '-c', '%u:%g:%a:%F', PGDATA]).decode().strip()
        presence = _read(engine, [identity, 'sh', '-c', PRESENCE]).decode()
        metadata = _sql(engine, identity, OBSERVE_SQL)
        return {'container_id': identity, 'image': container['Image'], 'name': container['Name'],
                'running': container['State']['Running'],
                'project_label': (container.get('Config', {}).get('Labels') or {}).get(CLI_LABEL),
                'network_mode': container.get('HostConfig', {}).get('NetworkMode'),
                'networks': {name: {'id': value.get('NetworkID'), 'aliases': value.get('Aliases') or []}
                             for name, value in container['NetworkSettings']['Networks'].items()},
                'ports': container['NetworkSettings'].get('Ports', {}),
                'mounts': [{key: value.get(key) for key in ('Type', 'Name', 'Destination', 'RW')}
                           for value in container.get('Mounts', [])],
                'volume': {key: volume.get(key) for key in ('Name', 'Driver', 'CreatedAt')},
                'network_id': network['Id'], 'uid': uid, 'gid': gid, 'data_owner': owner,
                'tls_directory': presence, 'database': metadata}
    except TLSError:
        raise
    except Exception:
        raise TLSError('retained_tls_topology_invalid') from None


class TLSPlan:
    def __init__(self, operator, certificates, topology):
        self.operator, self.certificates, self.topology = operator, certificates, topology
        self.configuration_sha256 = _sha((operator.root / 'private/configuration.json').read_bytes())
        db, networks = topology['database'], topology['networks']
        settings = db.get('settings', {})
        self.preconditions = {
            'exact_retained_running_database': topology['name'] == '/' + DATABASE and topology['running'] is True
                and re.fullmatch(r'[a-f0-9]{64}', topology['container_id']) is not None,
            'pinned_pg17_image': topology['image'] == IMAGE,
            'existing_cli_project': topology['project_label'] == PROJECT,
            'single_existing_private_network': topology['network_mode'] == NETWORK and set(networks) == {NETWORK}
                and networks[NETWORK]['id'] == topology['network_id'] and 'db' in networks[NETWORK]['aliases'],
            'original_loopback_database_port': topology['ports'].get('5432/tcp') == [{'HostIp': '127.0.0.1', 'HostPort': '55102'}]
                and all(not value for key, value in topology['ports'].items() if key != '5432/tcp'),
            'original_persistent_database_volume': topology['mounts'] == [
                {'Type': 'volume', 'Name': VOLUME, 'Destination': PGDATA, 'RW': True}]
                and topology['volume']['Name'] == VOLUME and topology['volume']['Driver'] == 'local'
                and bool(topology['volume']['CreatedAt']),
            'native_pg17_bootstrap_and_data_directory': db.get('major') == 17 and db.get('data_directory') == PGDATA
                and db.get('port') == '5432' and db.get('socket_directory') == '/var/run/postgresql'
                and db.get('bootstrap_role') == 'supabase_admin' and db.get('current_user') == 'supabase_admin'
                and db.get('session_user') == 'supabase_admin' and db.get('superuser') is True and db.get('file_errors') == 0,
            'verified_postgres_volume_ownership': topology['uid'] > 0 and topology['gid'] > 0
                and topology['data_owner'] in (f"{topology['uid']}:{topology['gid']}:700:directory",
                                               f"{topology['uid']}:{topology['gid']}:750:directory"),
            'exclusive_tls_directory_absent': topology['tls_directory'] == 'absent',
            'original_ssl_off_and_paths_blank': set(settings) == set(SETTINGS)
                and settings.get('ssl', {}).get('setting') == 'off'
                and all(settings.get(name, {}).get('setting') == '' for name in SETTINGS if name != 'ssl'),
            'ssl_reload_without_command_line_override': set(settings) == set(SETTINGS)
                and all(value.get('context') == 'sighup' and value.get('source') in ('default', 'configuration file')
                        and value.get('pending_restart') is False for value in settings.values()),
        }
        self.signature = _sha(_json({'topology': topology, 'files': certificates.hashes,
            'configuration': self.configuration_sha256, 'source': operator.meta['source_sha256'],
            'profile': operator.meta['profile_sha256']}).encode())

    def describe(self):
        return {'format': 'collect.retained-database-tls.plan.v1', 'dry_run': True, 'runtime_changed': False,
                'container_id': self.topology['container_id'], 'image': IMAGE, 'target': DATABASE,
                'persistent_directory': TLS_DIR, 'plan_sha256': self.signature,
                'source_sha256': self.operator.meta['source_sha256'], 'profile_sha256': self.operator.meta['profile_sha256'],
                'certificate_sha256': {name: digest for name, digest in self.certificates.hashes.items() if name != 'server.key'},
                'postgres_uid': self.topology['uid'], 'postgres_gid': self.topology['gid'],
                'preconditions': self.preconditions, 'ready_to_enable_tls': all(self.preconditions.values()),
                'new_containers': 0, 'mounts_changed': False, 'keys_rotated': False, 'ca_private_key_copied': False,
                'existing_connections_terminated': False, 'hba_changed': False,
                'tls_verified': False, 'database_tls_only_required_for_all_existing_clients': False,
                'automatic_retry': False, 'operator_reconciliation_required_after_uncertain_write': True}


def plan(release, engine):
    operator = Operator(release)
    return TLSPlan(operator, Certificates(operator), observe(engine))


class Journal:
    def __init__(self, path, selected):
        self.path = Path(path).absolute()
        _protected_directory(self.path.parent)
        self.value = {'format': 'collect.retained-database-tls.state.v1', 'plan_sha256': selected.signature,
                      'container_id': selected.topology['container_id'], 'status': 'pending',
                      'attempted_phase': None, 'acknowledged_phase': None, 'reconcile_required': False}
        try:
            fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            self.identity = (os.fstat(fd).st_dev, os.fstat(fd).st_ino)
            with os.fdopen(fd, 'w') as target:
                target.write(_json(self.value) + '\n'); target.flush(); os.fsync(target.fileno())
        except Exception:
            raise TLSError('retained_tls_new_private_state_file_required') from None

    def save(self, **changes):
        self.value.update(changes)
        try:
            private_file(self.path)
            # Append-only intent/ACK history preserves earlier complete records
            # after a torn write. Never truncate or replace prior evidence.
            fd = os.open(self.path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
            info = os.fstat(fd)
            if (info.st_dev, info.st_ino) != self.identity:
                os.close(fd)
                raise ValueError()
            with os.fdopen(fd, 'w') as target:
                target.write(_json(self.value) + '\n'); target.flush(); os.fsync(target.fileno())
        except Exception:
            raise TLSError('retained_tls_private_state_outcome_unconfirmed', phase=self.value['attempted_phase'] or 'state', reconcile=True) from None


def _installed(engine, identity, selected):
    uid, gid = selected.topology['uid'], selected.topology['gid']
    directory = _read(engine, [identity, 'stat', '-c', '%u:%g:%a:%F', TLS_DIR]).decode().strip()
    if directory != f'{uid}:{gid}:700:directory':
        raise TLSError('retained_tls_installed_files_unverified')
    for name in FILES:
        path = TLS_DIR + '/' + name
        info = _read(engine, [identity, 'stat', '-c', '%u:%g:%a:%F:%h', path]).decode().strip()
        checksum = _read(engine, [identity, 'sha256sum', path]).decode().split()
        if info != f'{uid}:{gid}:600:regular file:1' or not checksum or checksum[0] != selected.certificates.hashes[name]:
            raise TLSError('retained_tls_installed_files_unverified')


def _same_database(left, right):
    ignored = {'database', 'tls_directory'}
    return {key: value for key, value in left.items() if key not in ignored} == {
        key: value for key, value in right.items() if key not in ignored}


def execute(selected, engine, *, state_file):
    if not all(selected.preconditions.values()):
        raise TLSError('retained_tls_preconditions_unmet')
    current = plan(selected.operator.root, engine)
    if current.signature != selected.signature or not all(current.preconditions.values()):
        raise TLSError('retained_tls_plan_changed')
    journal = Journal(state_file, current)
    identity, uid, gid = (current.topology[name] for name in ('container_id', 'uid', 'gid'))
    phase = 'directory_create'
    try:
        def write(name, arguments, *, input=None):
            nonlocal phase
            phase = name
            journal.save(status='in_progress', attempted_phase=name, reconcile_required=True)
            raw = engine.write(arguments, input=input)
            journal.save(acknowledged_phase=name)
            return raw

        write('directory_create', ['exec', '--user', f'{uid}:{gid}', identity, 'mkdir', '-m', '0700', '--', TLS_DIR])
        owner = _read(engine, [identity, 'stat', '-c', '%u:%g:%a:%F', TLS_DIR]).decode().strip()
        contents = _read(engine, [identity, 'find', TLS_DIR, '-mindepth', '1', '-maxdepth', '1', '-print'])
        if owner != f'{uid}:{gid}:700:directory' or contents:
            raise TLSError('retained_tls_exclusive_directory_unverified')
        write('certificate_copy', ['cp', '--archive', '-', identity + ':' + TLS_DIR], input=current.certificates.archive(uid, gid))
        _installed(engine, identity, current)
        copied_source = observe(engine)
        if (not _same_database(current.topology, copied_source)
                or copied_source['database'] != current.topology['database']):
            raise TLSError('retained_tls_database_identity_changed')
        for name, statement in zip(('set_certificate', 'set_leaf_key', 'enable_ssl'), ALTERS):
            write(name, ['exec', identity, *PSQL, statement])
        if write('configuration_reload', ['exec', identity, *PSQL, RELOAD]).strip() != b't':
            raise TLSError('retained_tls_reload_not_acknowledged')
        phase = 'tls_verification'
        expected = {'ssl': 'on', 'ssl_cert_file': '.collect-tls/server.crt', 'ssl_key_file': '.collect-tls/server.key'}
        for attempt in range(20):
            observed = _sql(engine, identity, OBSERVE_SQL)
            settings = observed.get('settings', {})
            if observed.get('file_errors') == 0 and all(
                settings.get(name, {}).get('setting') == value and settings[name].get('source') == 'configuration file'
                and settings[name].get('sourcefile') == PGDATA + '/postgresql.auto.conf'
                and settings[name].get('pending_restart') is False for name, value in expected.items()):
                break
            if attempt == 19:
                raise TLSError('retained_tls_reload_settings_unverified')
            time.sleep(0.1)
        proof = probe_database_tls(current.certificates._files['ca.crt'].decode('ascii'),
            expected_leaf_sha256=leaf_sha256(current.certificates._files['server.crt'].decode('ascii')))
        if proof is None:
            raise TLSError('retained_tls_handshake_unverified')
        _installed(engine, identity, current)
        after = observe(engine)
        initial_database = {key: value for key, value in current.topology['database'].items() if key != 'settings'}
        final_database = {key: value for key, value in after['database'].items() if key != 'settings'}
        if (not _same_database(current.topology, after) or initial_database != final_database
                or after['database']['settings'].get('ssl_ca_file') != current.topology['database']['settings']['ssl_ca_file']):
            raise TLSError('retained_tls_database_identity_changed')
        journal.save(status='complete', attempted_phase='complete', acknowledged_phase='tls_verification', reconcile_required=False)
        report = current.describe()
        report.update(dry_run=False, runtime_changed=True, tls_verified=True,
                      persistent_settings_verified=True, state_file_created=True)
        return report
    except Exception as error:
        code = str(error) if isinstance(error, TLSError) else 'retained_tls_write_outcome_unconfirmed'
        try:
            journal.save(status='reconcile_required', attempted_phase=phase, failure_code=code, reconcile_required=True)
        except Exception:
            pass
        raise TLSError(code, phase=phase, reconcile=True) from None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', required=True, type=Path)
    parser.add_argument('--docker-host', required=True, choices=(DOCKER_HOST,))
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--state-file', type=Path, help='New owned0600 state file under an owned0700 parent; required for --execute')
    args = parser.parse_args(argv)
    if args.execute != bool(args.state_file):
        parser.error('--execute and a new --state-file are required together')
    try:
        engine = TLSRuntime(args.docker_host)
        selected = plan(args.release, engine)
        print(json.dumps(execute(selected, engine, state_file=args.state_file) if args.execute else selected.describe(), sort_keys=True))
        return 0
    except Exception as error:
        print(json.dumps({'code': str(error) if isinstance(error, TLSError) else 'retained_tls_configuration_invalid',
            'phase': error.phase if isinstance(error, TLSError) else 'preflight',
            'reconcile_required': error.reconcile if isinstance(error, TLSError) else False,
            'completed': False, 'automatic_retry': False}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
