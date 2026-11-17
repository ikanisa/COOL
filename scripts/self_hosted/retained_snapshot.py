"""Private native logical snapshot and isolated rehearsal of retained Supabase.

This is database/configuration custody for migration rehearsal, not a complete
encrypted production backup: Storage objects, external providers and independent
recovery-key custody require their own acceptance. No source database migration,
credential rotation, host port, image pull or second business backend is created.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tarfile
import time
import uuid

SOURCE_NAME = 'supabase_db_local-app'
LABEL = 'io.collect.retained-rehearsal'
SNAPSHOT_FORMAT = 'collect.retained.pg17.snapshot.v4'
DATABASE_PROPERTIES_SQL = """SELECT json_build_object('owner',pg_get_userbyid(d.datdba),
'acl',(SELECT json_agg(json_build_object('grantor',pg_get_userbyid(a.grantor),
'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
'privilege',a.privilege_type,'grantable',a.is_grantable) ORDER BY a.grantor,a.grantee,a.privilege_type)
FROM aclexplode(coalesce(d.datacl,acldefault('d',d.datdba))) a),
'settings',(SELECT setconfig FROM pg_db_role_setting WHERE setdatabase=d.oid AND setrole=0))
FROM pg_database d WHERE datname='postgres'"""
DATABASE_LOCALE_SQL = """SELECT json_build_object('encoding',pg_encoding_to_char(d.encoding),
'provider',d.datlocprovider,'collate',d.datcollate,'ctype',d.datctype,
'locale',d.datlocale,'icu_rules',d.daticurules,'version',d.datcollversion)
FROM pg_database d WHERE datname='postgres'"""


def database_locale_arguments(value):
    """Preserve the actual PG17 locale, including ICU, before restoring indexes."""
    fields = {'encoding', 'provider', 'collate', 'ctype', 'locale', 'icu_rules', 'version'}
    if not isinstance(value, dict) or set(value) != fields or value['encoding'] != 'UTF8':
        raise ValueError('Exact native UTF8 database locale observation required')
    if value['provider'] not in ('c', 'i'):
        raise ValueError('Reviewed libc or ICU database locale provider required')
    for name in ('collate', 'ctype'):
        if not isinstance(value[name], str) or not re.fullmatch(r'[A-Za-z0-9_.@+\-]{1,128}', value[name]):
            raise ValueError('Native database locale name required')
    version = value['version']
    if version is not None and (not isinstance(version, str) or not 1 <= len(version) <= 128 or '\0' in version):
        raise ValueError('Native database collation version required')
    args = ['--encoding=UTF8', '--locale-provider=' + ('icu' if value['provider'] == 'i' else 'libc'),
            '--lc-collate=' + value['collate'], '--lc-ctype=' + value['ctype']]
    if value['provider'] == 'i':
        locale, rules = value['locale'], value['icu_rules']
        if not isinstance(locale, str) or not re.fullmatch(r'[A-Za-z0-9_.@=;+\-]{1,256}', locale) or version is None:
            raise ValueError('Native ICU locale and version required')
        if rules is not None and (not isinstance(rules, str) or len(rules) > 8192 or '\0' in rules):
            raise ValueError('Native ICU collation rules required')
        args.append('--icu-locale=' + locale)
        if rules is not None:
            args.append('--icu-rules=' + rules)
    elif value['locale'] is not None or value['icu_rules'] is not None:
        raise ValueError('libc observation cannot contain ICU settings')
    return args


def require_database_locale(observed, expected):
    database_locale_arguments(expected)
    if observed != expected:
        raise ValueError('Restored database locale differs from retained source')


def snapshot_database_locale(directory, receipt):
    # Older receipts retain their existing read-only custody/qualification use,
    # but cannot authorize another restore with an invented default locale.
    if receipt.get('format') != SNAPSHOT_FORMAT:
        raise ValueError('Snapshot with observed native database locale required')
    value = json.loads((directory / 'database-locale.private.json').read_text())
    database_locale_arguments(value)
    return value


# Measured initdb state from the prior strict single-transaction failed restore:
# no custom schemas, only plpgsql and zero public relations. Check a superset of
# that absence before restoring forward; never infer freshness from a name alone.
FRESH_RESTORE_SQL = """SELECT json_build_object(
'major',current_setting('server_version_num')::int/10000,
'database',current_database(),'current_user',current_user,'session_user',session_user,
'bootstrap_role',(SELECT rolname FROM pg_roles WHERE oid=10),
'custom_schemas',(SELECT coalesce(json_agg(nspname ORDER BY nspname),'[]'::json) FROM pg_namespace
 WHERE nspname NOT IN ('pg_catalog','information_schema','public','pg_toast') AND nspname !~ '^pg_(temp_[0-9]+|toast_temp_[0-9]+)$'),
'user_relations',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast') AND n.nspname !~ '^pg_(temp_[0-9]+|toast_temp_[0-9]+)$'),
'user_functions',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast') AND n.nspname !~ '^pg_(temp_[0-9]+|toast_temp_[0-9]+)$'),
'extensions',(SELECT json_agg(extname ORDER BY extname) FROM pg_extension),
'foreign_servers',(SELECT count(*) FROM pg_foreign_server),
'event_triggers',(SELECT count(*) FROM pg_event_trigger),
'publications',(SELECT count(*) FROM pg_publication))"""


def require_owned_fresh_clone(actual, receipt, identity, volume):
    """Prove this exact newly created UUID-labelled isolated volume/container."""
    mounts = actual.get('Mounts', [])
    ports = actual.get('NetworkSettings', {}).get('Ports') or {}
    if (not re.fullmatch(r'[a-f0-9]{64}', identity or '')
            or identity == receipt['source_container_id']
            or actual.get('Id') != identity or actual.get('Image') != receipt['image_id']
            or actual.get('Name') != '/collect-buri-rehearsal-' + receipt['operation_id'][:8]
            or actual.get('State', {}).get('Running') is not True
            or actual.get('Config', {}).get('Labels', {}).get(LABEL) != receipt['operation_id']
            or actual.get('HostConfig', {}).get('NetworkMode') != 'none'
            or actual.get('HostConfig', {}).get('PortBindings') or any(ports.values())
            or len(mounts) != 1 or mounts[0].get('Type') != 'volume'
            or mounts[0].get('Name') != volume or mounts[0].get('Destination') != '/var/lib/postgresql'
            or mounts[0].get('RW') is not True):
        raise ValueError('Exact owned fresh isolated clone required')


def require_fresh_restore_target(observed, bootstrap_role):
    expected = {'major': 17, 'database': 'postgres', 'current_user': bootstrap_role,
                'session_user': bootstrap_role, 'bootstrap_role': bootstrap_role,
                'custom_schemas': [], 'user_relations': 0, 'user_functions': 0,
                'extensions': ['plpgsql'], 'foreign_servers': 0, 'event_triggers': 0,
                'publications': 0}
    if bootstrap_role != 'supabase_admin' or observed != expected:
        raise ValueError('Measured empty initdb restore target required')
    return {'fresh_target_verified': True, 'restore_method': 'forward_only',
            'strict_single_transaction': True}


def forward_restore_arguments(identity, bootstrap_role):
    if not re.fullmatch(r'[a-f0-9]{64}', identity or '') or bootstrap_role != 'supabase_admin':
        raise ValueError('Exact native restore identity required')
    return ['exec', '-i', identity, 'pg_restore', '-h', '/tmp', '-U', bootstrap_role,
            '-d', 'postgres', '--single-transaction', '--exit-on-error', '--no-password']


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def private_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        os.chmod(path, 0o600)
        json.dump(value, stream, indent=2)
        stream.write('\n')


def physical_directory(path, *, fresh=False):
    path = path.expanduser().absolute()
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Physical private directory required')
    if fresh:
        path.mkdir(mode=0o700)
    mode = path.stat()
    if not path.is_dir() or mode.st_uid != os.getuid() or mode.st_mode & 0o077:
        raise ValueError('Owner-only directory required')
    return path


def validate_tar(path):
    # Physical backups cannot redirect extraction into host/config/key paths.
    names = set()
    with tarfile.open(path, 'r:') as archive:
        for entry in archive:
            name = Path(entry.name)
            if name.is_absolute() or '..' in name.parts or '\\' in entry.name:
                raise ValueError('Unsafe snapshot member')
            normalized = name.as_posix()
            if normalized in names:
                raise ValueError('Duplicate snapshot member')
            names.add(normalized)
            if not (entry.isfile() or entry.isdir()) or entry.size < 0:
                raise ValueError('Linked/special snapshot member refused')
    if not names:
        raise ValueError('Empty snapshot refused')
    return len(names)


def restore_roles_sql(sql, bootstrap_role):
    # PG16+ GRANTED BY preserves a special bootstrap-superuser identity (OID10).
    # Merely creating a different superuser with that name changes grant semantics.
    # Keep every grant and ALTER; omit only CREATE for the same initdb-created role.
    if bootstrap_role != 'supabase_admin':
        raise ValueError('Reviewed native Supabase bootstrap role required')
    statement = 'CREATE ROLE ' + bootstrap_role + ';'
    if sql.splitlines().count(statement) != 1:
        raise ValueError('Exact bootstrap role creation statement required')
    return '\n'.join(line for line in sql.splitlines() if line != statement) + '\n'


def restore_database_properties(value):
    identifier = lambda text: '"' + str(text).replace('"', '""') + '"'
    literal = lambda text: "'" + str(text).replace("'", "''") + "'"
    if set(value) != {'owner', 'acl', 'settings'} or not value['acl']:
        raise ValueError('Exact native database property observation required')
    statements = ['BEGIN;', 'ALTER DATABASE postgres OWNER TO ' + identifier(value['owner']) + ';',
                  'REVOKE ALL ON DATABASE postgres FROM PUBLIC;']
    for grantee in sorted({row['grantee'] for row in value['acl']} - {'PUBLIC'}):
        statements.append('REVOKE ALL ON DATABASE postgres FROM ' + identifier(grantee) + ';')
    for row in value['acl']:
        if row['privilege'] not in {'CREATE', 'CONNECT', 'TEMPORARY'} or not isinstance(row['grantable'], bool):
            raise ValueError('Unexpected native database privilege')
        statements.extend(['SET LOCAL ROLE ' + identifier(row['grantor']) + ';',
                           'GRANT ' + row['privilege'] + ' ON DATABASE postgres TO ' +
                           ('PUBLIC' if row['grantee'] == 'PUBLIC' else identifier(row['grantee'])) +
                           (' WITH GRANT OPTION' if row['grantable'] else '') + ';', 'RESET ROLE;'])
    for setting in value['settings'] or []:
        key, content = setting.split('=', 1)
        statements.append('ALTER DATABASE postgres SET ' + identifier(key) + ' TO ' + literal(content) + ';')
    return '\n'.join(statements + ['COMMIT;'])


class Docker:
    def __init__(self, host, directory):
        if not host.startswith('unix:///'):
            raise ValueError('Explicit local Unix Docker socket required')
        socket = Path(host[7:])
        if not stat.S_ISSOCK(socket.stat().st_mode):
            raise ValueError('Docker socket unavailable')
        binary = shutil.which('docker')
        if not binary:
            raise ValueError('Docker CLI unavailable')
        self.argv = [binary, '--host', host]
        self.directory = directory
        self.counter = 0
        self.prefix = uuid.uuid4().hex[:12]

    def run(self, args, *, input=None, output=None, timeout=60):
        self.counter += 1
        error = self.directory / f'command-{self.prefix}-{self.counter:03d}.private.stderr'
        with error.open('xb') as stderr:
            os.chmod(error, 0o600)
            if output:
                with output.open('xb') as stdout:
                    os.chmod(output, 0o600)
                    result = subprocess.run(self.argv + args, input=input, stdout=stdout,
                                            stderr=stderr, timeout=timeout)
            else:
                result = subprocess.run(self.argv + args, input=input, stdout=subprocess.PIPE,
                                        stderr=stderr, timeout=timeout)
        if result.returncode:
            raise RuntimeError(f'Docker operation failed; private diagnostic {error.name}')
        return b'' if output else result.stdout

    def inspect(self, identity):
        values = json.loads(self.run(['inspect', identity]))
        if len(values) != 1:
            raise ValueError('One exact container required')
        return values[0]


def snapshot(args):
    out = physical_directory(args.directory, fresh=True)
    docker = Docker(args.docker_host, out)
    source = docker.inspect(args.source_id)
    if source['Id'] != args.source_id or source['Name'] != '/' + SOURCE_NAME or not source['State']['Running']:
        raise ValueError('Exact running retained source required')
    sql = "SELECT json_build_object('major',current_setting('server_version_num')::int/10000,'tablespaces',(SELECT count(*) FROM pg_tablespace WHERE spcname NOT IN ('pg_default','pg_global')),'data_directory',current_setting('data_directory'),'bootstrap_role',(SELECT rolname FROM pg_roles WHERE oid=10))"
    platform = json.loads(docker.run(['exec', source['Id'], 'psql', '-U', 'postgres', '-d', 'postgres', '-XAtq', '-c', sql]))
    if platform != {'major': 17, 'tablespaces': 0, 'data_directory': '/var/lib/postgresql/data', 'bootstrap_role': 'supabase_admin'}:
        raise ValueError('Reviewed PG17 single-data-directory source required')
    if shutil.disk_usage(out).free < 2 * 1024 ** 3:
        raise ValueError('At least 2GiB private snapshot space required')
    raw_locale = docker.run(['exec', source['Id'], 'psql', '-U', 'postgres', '-d', 'postgres',
                            '-XAtq', '-v', 'ON_ERROR_STOP=1', '-c', DATABASE_LOCALE_SQL])
    locale_value = json.loads(raw_locale)
    database_locale_arguments(locale_value)
    locale_path = out / 'database-locale.private.json'
    private_json(locale_path, locale_value)
    env = source['Config']['Env']
    if any('\n' in value or '\r' in value for value in env):
        raise ValueError('Multiline environment requires an explicit private custody adapter')
    env_path = out / 'source.private.env'
    with env_path.open('x') as stream:
        os.chmod(env_path, 0o600)
        stream.write('\n'.join(env) + '\n')
    base = out / 'database.private.dump'
    docker.run(['exec', source['Id'], 'pg_dump', '-U', 'postgres', '-d', 'postgres',
                '--format=custom', '--no-password'], output=base, timeout=300)
    roles = out / 'roles.private.sql'
    docker.run(['exec', source['Id'], 'pg_dumpall', '-U', 'postgres', '--roles-only',
                '--no-role-passwords', '--no-password'], output=roles)
    properties = out / 'database-properties.private.json'
    raw_properties = docker.run(['exec', source['Id'], 'psql', '-U', 'postgres', '-d', 'postgres',
                                 '-XAtq', '-c', DATABASE_PROPERTIES_SQL])
    private_json(properties, json.loads(raw_properties))
    config = out / 'configuration.private.tar'
    docker.run(['exec', source['Id'], 'tar', '-C', '/etc/postgresql', '-cf', '-', '.'], output=config)
    inventory = {path.name: {'bytes': path.stat().st_size, 'sha256': digest(path),
                 **({'members': validate_tar(path)} if path.suffix == '.tar' else {})}
                 for path in (base, roles, properties, config, env_path, locale_path)}
    after = docker.inspect(source['Id'])
    if after['Image'] != source['Image'] or not after['State']['Running']:
        raise ValueError('Source identity/state changed during snapshot')
    receipt = {'format': SNAPSHOT_FORMAT, 'operation_id': str(uuid.uuid4()),
               'docker_host': args.docker_host, 'source_container_id': source['Id'],
               'source_name': SOURCE_NAME, 'image_id': source['Image'], 'files': inventory,
               'source_running': True, 'source_migrated': False,
               # pg_dumpall omits password hashes. Native configuration and DB
               # settings still contain credentials and remain private secrets.
               'role_password_hashes_dumped': False,
               'configuration_contains_private_credentials': True,
               'bootstrap_role': platform['bootstrap_role'],
               'scope': 'Private native logical DB/config/role snapshot; not complete encrypted production recovery'}
    private_json(out / 'snapshot.json', receipt)
    return {'status': 'snapshot_verified', 'directory': str(out), 'source_migrated': False}


def verify_snapshot(directory):
    receipt = json.loads((directory / 'snapshot.json').read_text())
    if receipt.get('format') not in ('collect.retained.pg17.snapshot.v3', SNAPSHOT_FORMAT):
        raise ValueError('Snapshot receipt required')
    uuid.UUID(receipt['operation_id'])
    if receipt.get('bootstrap_role') != 'supabase_admin':
        raise ValueError('Native bootstrap identity observation required')
    if not re.fullmatch(r'sha256:[a-f0-9]{64}', receipt['image_id']):
        raise ValueError('Exact local image identity required')
    files = {'database.private.dump', 'roles.private.sql', 'database-properties.private.json', 'configuration.private.tar', 'source.private.env'}
    if receipt['format'] == SNAPSHOT_FORMAT:
        files.add('database-locale.private.json')
    if set(receipt['files']) != files:
        raise ValueError('Exact private snapshot file set required')
    for name, expected in receipt['files'].items():
        path = directory / name
        if path.is_symlink() or path.stat().st_mode & 0o077 or digest(path) != expected['sha256'] or path.stat().st_size != expected['bytes']:
            raise ValueError('Private snapshot identity/permissions changed')
        if path.suffix == '.tar':
            validate_tar(path)
    return receipt


def clone(args):
    directory = physical_directory(args.directory)
    receipt = verify_snapshot(directory)
    locale_value = snapshot_database_locale(directory, receipt)
    if (directory / 'clone.json').exists():
        raise ValueError('Reconcile existing clone receipt; never restart an unknown operation')
    docker = Docker(receipt['docker_host'], directory)
    op = receipt['operation_id']
    name = 'collect-buri-rehearsal-' + op[:8]
    volume = name + '-data'
    state = {'format': 'collect.retained.pg17.clone.v1', 'operation_id': op,
             'source_container_id': receipt['source_container_id'], 'image_id': receipt['image_id'],
             'volume': volume, 'helper_id': None, 'container_id': None, 'network': 'none',
             'published_ports': [], 'status': 'creating', 'source_migrated': False}
    if docker.run(['volume', 'ls', '--filter', 'name=^' + volume + '$', '--format', '{{.Name}}']).strip():
        raise ValueError('Clone volume already exists; reconcile original ownership before any retry')
    if docker.run(['ps', '-a', '--filter', 'name=' + name, '--format', '{{.ID}}']).strip():
        raise ValueError('Clone container name exists; reconcile original ownership before any retry')
    def save():
        path = directory / 'clone.json'
        if path.exists():
            path.write_text(json.dumps(state, indent=2) + '\n')
        else:
            private_json(path, state)
    # Journal intent before the first daemon mutation; an uncertain outcome is
    # recovered by this UUID label, never a second create using a new identity.
    save()
    docker.run(['volume', 'create', '--label', LABEL + '=' + op, volume])
    helper = docker.run(['create', '--pull', 'never', '--name', name + '-extract', '--label', LABEL + '=' + op,
                         '--network', 'none', '--memory', '256m', '--cpus', '1', '--user', '0',
                         '--mount', 'type=volume,source=' + volume + ',destination=/var/lib/postgresql',
                         '--entrypoint', '/bin/sh', receipt['image_id'], '-c', 'sleep 86400']).decode().strip()
    state['helper_id'] = helper; save()
    docker.run(['start', helper])
    docker.run(['exec', helper, 'mkdir', '-p', '/var/lib/postgresql/data', '/var/lib/postgresql/collect-config'])
    for file, target in [('configuration.private.tar', '/var/lib/postgresql/collect-config')]:
        # stdin is a private file, not shell substitution or a command argument.
        with (directory / file).open('rb') as stream:
            result = subprocess.run(docker.argv + ['exec', '-i', helper, 'tar', '-xf', '-', '-C', target],
                                    stdin=stream, capture_output=True, timeout=180)
        if result.returncode:
            raise RuntimeError('Owned snapshot extraction failed')
    docker.run(['exec', helper, 'chown', '-R', 'postgres:postgres', '/var/lib/postgresql/data', '/var/lib/postgresql/collect-config'])
    docker.run(['exec', '--user', 'postgres', helper, 'initdb', '-D', '/var/lib/postgresql/data',
                '-U', receipt['bootstrap_role'], '--auth-local=trust', '--auth-host=reject',
                *database_locale_arguments(locale_value), '--no-instructions'])
    docker.run(['stop', '--time', '5', helper])
    identity = docker.run(['create', '--pull', 'never', '--name', name, '--label', LABEL + '=' + op,
                           '--network', 'none', '--memory', '2g', '--cpus', '2', '--user', 'postgres',
                           '--env-file', str(directory / 'source.private.env'),
                           '--mount', 'type=volume,source=' + volume + ',destination=/var/lib/postgresql',
                           '--entrypoint', 'postgres', receipt['image_id'], '-D', '/var/lib/postgresql/data',
                           '-c', 'config_file=/var/lib/postgresql/collect-config/postgresql.conf',
                           '-c', 'hba_file=/var/lib/postgresql/data/pg_hba.conf',
                           '-c', 'ident_file=/var/lib/postgresql/data/pg_ident.conf',
                           '-c', 'listen_addresses=', '-c', 'unix_socket_directories=/tmp']).decode().strip()
    state['container_id'] = identity; save()
    docker.run(['start', identity])
    for _ in range(30):
        probe = subprocess.run(docker.argv + ['exec', identity, 'pg_isready', '-h', '/tmp', '-U', 'postgres'], capture_output=True, timeout=5)
        if probe.returncode == 0:
            break
        time.sleep(1)
    else:
        docker.run(['logs', identity], output=directory / 'clone-startup.private.log')
        raise RuntimeError('Owned clone did not become ready; preserve diagnostics and UUID')
    require_owned_fresh_clone(docker.inspect(identity), receipt, identity, volume)
    observed_locale = json.loads(docker.run(['exec', identity, 'psql', '-h', '/tmp', '-U', receipt['bootstrap_role'],
                                            '-d', 'postgres', '-XAtq', '-v', 'ON_ERROR_STOP=1', '-c', DATABASE_LOCALE_SQL]))
    private_json(directory / 'fresh-database-locale.private.json', observed_locale)
    require_database_locale(observed_locale, locale_value)
    # Restore only inside this newly created, labelled, network-isolated cluster.
    # Native roles/ownership are preserved; role passwords are deliberately absent.
    docker.run(['exec', '-i', identity, 'psql', '-h', '/tmp', '-U', receipt['bootstrap_role'],
                '-d', 'postgres', '-Xq', '-v', 'ON_ERROR_STOP=1'],
               input=restore_roles_sql((directory / 'roles.private.sql').read_text(), receipt['bootstrap_role']).encode())
    # --clean references schemas that do not exist in initdb (including native
    # collect_sms), and can fail before restoring anything. Forward restore is
    # allowed only after proving both newly owned custody and actual empty catalog.
    require_owned_fresh_clone(docker.inspect(identity), receipt, identity, volume)
    observed = json.loads(docker.run(['exec', identity, 'psql', '-h', '/tmp', '-U', receipt['bootstrap_role'],
                                     '-d', 'postgres', '-XAtq', '-v', 'ON_ERROR_STOP=1', '-c', FRESH_RESTORE_SQL]))
    fresh = require_fresh_restore_target(observed, receipt['bootstrap_role'])
    private_json(directory / 'fresh-restore-target.private.json', observed)
    state.update(fresh, status='restoring_verified_fresh_target'); save()
    require_owned_fresh_clone(docker.inspect(identity), receipt, identity, volume)
    error = directory / 'restore.private.stderr'
    with error.open('xb') as stderr, (directory / 'database.private.dump').open('rb') as stream:
        os.chmod(error, 0o600)
        restored = subprocess.run(docker.argv + forward_restore_arguments(identity, receipt['bootstrap_role']),
                                  stdin=stream, stdout=subprocess.DEVNULL, stderr=stderr, timeout=180)
    if restored.returncode:
        state['status'] = 'restore_failed'; save()
        raise RuntimeError('Owned clone restore failed; private diagnostic retained')
    docker.run(['exec', '-i', identity, 'psql', '-h', '/tmp', '-U', receipt['bootstrap_role'],
                '-d', 'postgres', '-Xq', '-v', 'ON_ERROR_STOP=1'],
               input=restore_database_properties(json.loads((directory / 'database-properties.private.json').read_text())).encode())
    restored_locale = json.loads(docker.run(['exec', identity, 'psql', '-h', '/tmp', '-U', receipt['bootstrap_role'],
                                            '-d', 'postgres', '-XAtq', '-v', 'ON_ERROR_STOP=1', '-c', DATABASE_LOCALE_SQL]))
    private_json(directory / 'restored-database-locale.private.json', restored_locale)
    require_database_locale(restored_locale, locale_value)
    state['source_database_locale_preserved'] = True
    state['status'] = 'ready_for_schema_rehearsal'; save()
    return {'status': state['status'], 'container_id': identity, 'source_migrated': False,
            'network': 'none', 'published_ports': []}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['snapshot', 'clone'])
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--docker-host')
    parser.add_argument('--source-id')
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    if not args.execute:
        print(json.dumps({'action': args.action, 'execute': False,
                          'source_migrated': False, 'requires': 'Explicit --execute; exact retained source; fresh owner-only destination'}))
        return
    if args.action == 'snapshot' and (not args.docker_host or not args.source_id or not re.fullmatch(r'[a-f0-9]{64}', args.source_id)):
        parser.error('Snapshot requires explicit Unix Docker host and full inspected source container ID')
    print(json.dumps(snapshot(args) if args.action == 'snapshot' else clone(args)))


if __name__ == '__main__':
    main()
