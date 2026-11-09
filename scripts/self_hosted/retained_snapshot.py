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
DATABASE_PROPERTIES_SQL = """SELECT json_build_object('owner',pg_get_userbyid(d.datdba),
'acl',(SELECT json_agg(json_build_object('grantor',pg_get_userbyid(a.grantor),
'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
'privilege',a.privilege_type,'grantable',a.is_grantable) ORDER BY a.grantor,a.grantee,a.privilege_type)
FROM aclexplode(coalesce(d.datacl,acldefault('d',d.datdba))) a),
'settings',(SELECT setconfig FROM pg_db_role_setting WHERE setdatabase=d.oid AND setrole=0))
FROM pg_database d WHERE datname='postgres'"""


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
                 for path in (base, roles, properties, config, env_path)}
    after = docker.inspect(source['Id'])
    if after['Image'] != source['Image'] or not after['State']['Running']:
        raise ValueError('Source identity/state changed during snapshot')
    receipt = {'format': 'collect.retained.pg17.snapshot.v3', 'operation_id': str(uuid.uuid4()),
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
    if receipt.get('format') != 'collect.retained.pg17.snapshot.v3':
        raise ValueError('Snapshot receipt required')
    uuid.UUID(receipt['operation_id'])
    if receipt.get('bootstrap_role') != 'supabase_admin':
        raise ValueError('Native bootstrap identity observation required')
    if not re.fullmatch(r'sha256:[a-f0-9]{64}', receipt['image_id']):
        raise ValueError('Exact local image identity required')
    if set(receipt['files']) != {'database.private.dump', 'roles.private.sql', 'database-properties.private.json', 'configuration.private.tar', 'source.private.env'}:
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
                '--encoding=UTF8', '--locale=C.UTF-8', '--no-instructions'])
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
    actual = docker.inspect(identity)
    if actual['HostConfig']['NetworkMode'] != 'none' or actual['HostConfig'].get('PortBindings'):
        raise ValueError('Clone network isolation changed')
    # Restore only inside this newly created, labelled, network-isolated cluster.
    # Native roles/ownership are preserved; role passwords are deliberately absent.
    docker.run(['exec', '-i', identity, 'psql', '-h', '/tmp', '-U', receipt['bootstrap_role'],
                '-d', 'postgres', '-Xq', '-v', 'ON_ERROR_STOP=1'],
               input=restore_roles_sql((directory / 'roles.private.sql').read_text(), receipt['bootstrap_role']).encode())
    error = directory / 'restore.private.stderr'
    with error.open('xb') as stderr, (directory / 'database.private.dump').open('rb') as stream:
        os.chmod(error, 0o600)
        restored = subprocess.run(docker.argv + ['exec', '-i', identity, 'pg_restore',
                                  '-h', '/tmp', '-U', receipt['bootstrap_role'], '-d', 'postgres',
                                  '--clean', '--if-exists', '--single-transaction', '--exit-on-error'],
                                  stdin=stream, stdout=subprocess.DEVNULL, stderr=stderr, timeout=180)
    if restored.returncode:
        state['status'] = 'restore_failed'; save()
        raise RuntimeError('Owned clone restore failed; private diagnostic retained')
    docker.run(['exec', '-i', identity, 'psql', '-h', '/tmp', '-U', receipt['bootstrap_role'],
                '-d', 'postgres', '-Xq', '-v', 'ON_ERROR_STOP=1'],
               input=restore_database_properties(json.loads((directory / 'database-properties.private.json').read_text())).encode())
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
