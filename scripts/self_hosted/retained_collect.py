"""Plan canonical Collect Edge on the existing retained local Supabase.

Default: read-only inspection and a sanitized dry-run. --execute is a separate
operator action: after the original Edge is absent, it can create only its replacement,
verify the read-only source mounts and start it. It never changes Auth, Kong,
PostgreSQL, Storage, networks, volumes, keys, schedules or provider settings.
Unconfirmed mutation outcomes stop without replay or destructive cleanup.
"""
from __future__ import annotations
import argparse
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import sys
import tarfile
import tomllib
from urllib.parse import quote, urlencode, urlsplit

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.self_hosted.configure import read_env
from scripts.self_hosted.release_operator import Operator
from scripts.supabase.deployment_profile import canonical_profile
from scripts.self_hosted.postgres_tls_probe import TLSProbeError, leaf_sha256, probe_postgres_tls

DOCKER_HOST = 'unix:///Volumes/SupaRuntime/.colima/supabase-local/docker.sock'
COLIMA_CONFIG = Path('/Volumes/SupaRuntime/.colima/supabase-local/colima.yaml')
EDGE = 'supabase_edge_runtime_local-app'
KONG = 'supabase_kong_local-app'
DATABASE = 'supabase_db_local-app'
AUTH = 'supabase_auth_local-app'
NETWORK = 'devctl-local-app'
CACHE = 'supabase_edge_runtime_local-app'
IMAGE = 'sha256:178c041398a33ded8219344382d0672a90051d1babbf0af03425cafe20039a75'
LABEL = 'io.collect.retained-edge'
PROJECT = 'local-app'
CLI_LABEL = 'com.supabase.cli.project'
MAX_RESPONSE = 8 * 1024 * 1024
FUNCTIONS = ('collect-api', 'admin-api', 'collect-jobs', 'collect-email-jobs', 'collect-sms', 'send-sms-hook')
DB_SETTINGS = "SELECT name,setting FROM pg_catalog.pg_settings WHERE name IN ('ssl','ssl_ca_file','ssl_cert_file','ssl_key_file','port') ORDER BY name"
FORBIDDEN_ENV = {'POSTGRES_PASSWORD', 'JWT_SECRET', 'JWT_KEYS', 'JWT_JWKS', 'SUPABASE_JWKS',
                 'SUPABASE_DB_URL', 'COLLECT_EDGE_PASSWORD', 'COLLECT_SMS_EDGE_PASSWORD',
                 'GOOGLE_CLIENT_ID', 'GOOGLE_SECRET'}
FLAG_NAMES = ('BURIMUNSI_NATIVE_ENABLED', 'BURIMUNSI_NATIVE_WORKERS_ENABLED', 'BURIMUNSI_NATIVE_UPLOADS_ENABLED',
              'MOMO_PROCESSING_PAUSED', 'COLLECT_SMS_ENABLED', 'DISPATCH_PAUSED', 'FCM_ENABLED')


def _public_ca(value):
    return isinstance(value, str) and len(value) <= 32768 and re.fullmatch(
        r'-----BEGIN CERTIFICATE-----\n[A-Za-z0-9+/=\n]+\n-----END CERTIFICATE-----', value) is not None


def probe_database_tls(ca, *, expected_leaf_sha256=None):
    """Public proof or None; no Docker utility, SQL or password is required."""
    try:
        return probe_postgres_tls(ca.strip() + '\n', expected_leaf_sha256=expected_leaf_sha256)
    except (TLSProbeError, AttributeError):
        return None


class RetainedError(RuntimeError):
    """Fixed codes only; daemon/provider details and private bodies stay private."""


class _UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__('localhost', timeout=30)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)


class DockerEngine:
    def __init__(self, host):
        if host != DOCKER_HOST:
            raise RetainedError('retained_docker_socket_required')
        path = Path(host[7:])
        if not stat.S_ISSOCK(path.stat().st_mode):
            raise RetainedError('retained_docker_socket_unavailable')
        self.host, self.path = host, str(path)

    def request(self, method, path, body=None, *, binary=False, missing=False):
        connection = _UnixHTTP(self.path)
        try:
            data = None if body is None else json.dumps(body, separators=(',', ':')).encode()
            connection.request(method, path, body=data, headers={} if data is None else {'Content-Type': 'application/json'})
            response = connection.getresponse()
            result = response.read(MAX_RESPONSE + 1)
            if len(result) > MAX_RESPONSE:
                raise RetainedError('retained_docker_response_too_large')
            if missing and response.status == 404:
                return None
            if not 200 <= response.status < 300:
                raise RetainedError('retained_docker_request_refused')
            return result if binary else json.loads(result) if result else None
        except RetainedError:
            raise
        except Exception:
            # A lost create/rename/start ACK is never automatically retried.
            raise RetainedError('retained_docker_outcome_unconfirmed') from None
        finally:
            connection.close()

    def inspect(self, name, *, missing=False):
        return self.request('GET', '/containers/' + quote(name, safe='') + '/json', missing=missing)

    def readonly(self, arguments, *, input=None):
        # Callers below use only fixed public metadata commands. Passwords,
        # keys and private environment values never enter command arguments.
        try:
            result = subprocess.run(['docker', '--host', self.host, 'exec', *(['-i'] if input is not None else []),
                                     *arguments], input=input, capture_output=True, timeout=30)
        except Exception:
            raise RetainedError('retained_metadata_unavailable') from None
        if len(result.stdout) + len(result.stderr) > MAX_RESPONSE:
            raise RetainedError('retained_metadata_too_large')
        return result


def _environment(container):
    return dict(value.split('=', 1) for value in container.get('Config', {}).get('Env', []))


def _network(container):
    return container.get('NetworkSettings', {}).get('Networks', {}).get(NETWORK, {})


def read_cli_configuration(path):
    """Read configuration without exposing any authored values on failure."""
    try:
        path = Path(path)
        info = path.lstat()
        if path.is_symlink() or not stat.S_ISREG(info.st_mode) or info.st_size > 1024 * 1024:
            raise ValueError()
        raw = path.read_bytes()
        config = tomllib.loads(raw.decode('utf8'))
        if config.get('project_id') != PROJECT or config.get('api', {}).get('port') != 55101:
            raise ValueError()
        return path.absolute(), raw, config
    except Exception:
        raise RetainedError('retained_cli_configuration_invalid') from None


def shared_locations(path=COLIMA_CONFIG):
    import yaml
    try:
        data = yaml.safe_load(path.read_text())
        paths = [Path(item['location']).expanduser().absolute() for item in data.get('mounts', [])
                 if isinstance(item, dict) and isinstance(item.get('location'), str)
                 and item.get('mountPoint') in (None, '', item['location'])]
    except Exception:
        raise RetainedError('retained_host_mounts_unavailable') from None
    return tuple(paths)


def observe(engine, ca, *, expected_leaf_sha256=None):
    """Metadata only in the returned object; full inspections are not retained."""
    import yaml
    edge = engine.inspect(EDGE, missing=True)
    kong, database, auth = (engine.inspect(name) for name in (KONG, DATABASE, AUTH))
    image = engine.request('GET', '/images/' + IMAGE + '/json')
    volume = engine.request('GET', '/volumes/' + CACHE)
    network = engine.request('GET', '/networks/' + NETWORK)
    listed = engine.request('GET', '/containers/json?' + urlencode({
        'all': '1', 'filters': json.dumps({'label': [CLI_LABEL + '=' + PROJECT]}, separators=(',', ':'))}))
    if not isinstance(listed, list):
        raise RetainedError('retained_cli_inventory_invalid')
    # Include exited/renamed originals. Adding another project-labelled Edge
    # would otherwise make the ordinary CLI stop/restart lifecycle ambiguous.
    cli_edges = sorted(value['Id'] for value in listed if
        any(name.startswith('/supabase_edge_runtime_') for name in value.get('Names', [])) or
        (value.get('Labels') or {}).get(LABEL) == 'true' or value.get('ImageID') == IMAGE)
    command = engine.readonly([KONG, 'cat', '/home/kong/kong.yml'])
    if command.returncode:
        raise RetainedError('retained_gateway_metadata_unavailable')
    try:
        services = yaml.safe_load(command.stdout).get('services', [])
        selected = [value for value in services if value.get('name') == 'functions-v1']
        route = selected[0] if len(selected) == 1 else {}
        routes = route.get('routes', [])
        upstream = route.get('url') or f"{route.get('protocol')}://{route.get('host')}:{route.get('port')}{route.get('path', '')}"
    except Exception:
        raise RetainedError('retained_gateway_metadata_invalid') from None
    command = engine.readonly([DATABASE, 'psql', '-XAtq', '-U', 'postgres', '-d', 'postgres', '-c', DB_SETTINGS])
    if command.returncode:
        raise RetainedError('retained_database_metadata_unavailable')
    try:
        settings = dict(line.split('|', 1) for line in command.stdout.decode().strip().splitlines())
    except Exception:
        raise RetainedError('retained_database_metadata_invalid') from None
    database_ports = database.get('NetworkSettings', {}).get('Ports', {})
    private_database_port = database_ports.get('5432/tcp') == [{'HostIp': '127.0.0.1', 'HostPort': '55102'}] \
        and all(not value for key, value in database_ports.items() if key != '5432/tcp')
    tls = False
    if settings.get('ssl') == 'on' and _public_ca(ca) and private_database_port:
        tls = probe_database_tls(ca, expected_leaf_sha256=expected_leaf_sha256) is not None
    auth_env = _environment(auth)
    return {'edge': None if edge is None else {'id': edge['Id'], 'image': edge['Image'],
             'running': edge['State']['Running'], 'status': edge['State']['Status'],
             'adapter_owned': (edge.get('Config', {}).get('Labels') or {}).get(LABEL) == 'true'},
            'database_id': database['Id'], 'kong_id': kong['Id'], 'auth_id': auth['Id'],
            'dependencies_running': all(value['State']['Running'] for value in (kong, database, auth)),
            'same_network': all(_network(value).get('NetworkID') == network['Id'] for value in (kong, database, auth)),
            'network_id': network['Id'], 'image_id': image['Id'],
            'cache': {'name': volume['Name'], 'created': volume.get('CreatedAt'), 'driver': volume['Driver']},
            'kong_aliases': _network(kong).get('Aliases') or [], 'database_aliases': _network(database).get('Aliases') or [],
            'loopback_api': kong.get('NetworkSettings', {}).get('Ports', {}).get('8000/tcp'),
            'function_upstream_matches': upstream == f'http://{EDGE}:8081/' and len(routes) == 1
              and routes[0].get('paths') == ['/functions/v1/'] and routes[0].get('strip_path') is True
              and routes[0].get('preserve_host') in (None, False),
            'ssl': settings.get('ssl'), 'database_tls_verified': tls,
            'private_database_port_matches': private_database_port,
            'cli_owned_edges': cli_edges,
            'auth_issuer': auth_env.get('GOTRUE_JWT_ISSUER'), 'auth_public_origin': auth_env.get('API_EXTERNAL_URL')}


class RetainedPlan:
    def __init__(self, operator, functions, topology, locations, cli_configuration):
        self.operator, self.topology = operator, topology
        self._cli_path, cli_raw, cli_config = cli_configuration
        self._cli_sha256 = hashlib.sha256(cli_raw).hexdigest()
        self._functions = dict(functions)
        root, profile = operator.root, operator.profile
        if any(not isinstance(value, str) or '\0' in value for value in functions.values()) or any(
                key in functions and functions[key] not in ('true', 'false') for key in FLAG_NAMES):
            raise RetainedError('retained_environment_invalid')
        if functions.get('COLLECT_DEPLOYMENT_PROFILE') != canonical_profile(profile) or functions.get('COLLECT_DEPLOYMENT_PROFILE_SHA256') != operator.meta['profile_sha256']:
            raise RetainedError('retained_function_profile_mismatch')
        if functions.get('BUILD_SOURCE_ID') != operator.meta['source_sha256'] or functions.get('APP_ENVIRONMENT') != profile['environment'] or functions.get('SUPABASE_URL') != profile['supabase_origin']:
            raise RetainedError('retained_function_identity_mismatch')
        if any(key in FORBIDDEN_ENV or key.startswith(('SMTP_', 'GOTRUE_')) or
               key.startswith('SUPABASE_INTERNAL_') and key != 'SUPABASE_INTERNAL_URL' for key in functions):
            raise RetainedError('retained_function_secret_boundary_invalid')
        if functions.get('SUPABASE_INTERNAL_URL') not in ('http://api-gw:8000', 'http://kong:8000'):
            raise RetainedError('retained_internal_origin_invalid')
        self._functions['SUPABASE_INTERNAL_URL'] = 'http://kong:8000'
        db = urlsplit(functions.get('COLLECT_DATABASE_URL', ''))
        if db.scheme not in ('postgres', 'postgresql') or db.hostname != 'db' or db.port not in (None, 5432) or db.path != '/postgres' or db.username != 'collect_edge' or not db.password or db.fragment or db.query not in ('', 'sslmode=verify-full'):
            raise RetainedError('retained_database_identity_invalid')
        if not _public_ca(functions.get('COLLECT_DB_CA_PEM')):
            raise RetainedError('retained_public_database_ca_required')
        edge = topology['edge']
        self.preconditions = {
            'retained_dependencies_running': topology['dependencies_running'],
            'retained_private_network': topology['same_network'],
            'original_cached_edge_image': topology['image_id'] == IMAGE,
            'original_deno_cache': topology['cache']['name'] == CACHE and topology['cache']['driver'] == 'local' and bool(topology['cache']['created']),
            'original_kong_function_route': topology['function_upstream_matches'],
            'existing_private_aliases': 'kong' in topology['kong_aliases'] and 'db' in topology['database_aliases'],
            'loopback_api_55101': topology['loopback_api'] == [{'HostIp': '127.0.0.1', 'HostPort': '55101'}],
            'verified_database_tls_db': topology['ssl'] == 'on' and topology['database_tls_verified'],
            'loopback_database_55102': topology['private_database_port_matches'],
            'auth_public_issuer': topology['auth_issuer'] == profile['supabase_origin'] + '/auth/v1' and topology['auth_public_origin'] == profile['supabase_origin'] + '/auth/v1',
            'original_edge_absent': edge is None,
            'no_duplicate_cli_owned_edge': not topology['cli_owned_edges'],
            'cli_generic_edge_disabled': cli_config.get('edge_runtime', {}).get('enabled') is False,
            'host_bind_within_existing_share': any(root == value or root.is_relative_to(value) for value in locations),
        }
        for name in FUNCTIONS:
            if not (root / 'source/supabase/functions' / name / 'index.ts').is_file():
                raise RetainedError('retained_canonical_function_missing')
        self._mount_checks = {}
        for relative in ('deploy/self-hosted/edge-main/index.ts', 'deploy/self-hosted/edge-main/router.ts',
                         'deploy/self-hosted/edge-main/environment.mjs', 'supabase/functions/_shared/serve.js'):
            content = (root / 'source' / relative).read_bytes()
            target = '/home/deno/main/' + relative.rsplit('/', 1)[-1] if '/edge-main/' in relative else '/home/deno/collect/' + relative
            self._mount_checks[target] = hashlib.sha256(content).hexdigest()

    def __repr__(self):
        return 'RetainedPlan(private_environment=redacted)'

    def describe(self):
        return {'dry_run': True, 'runtime_changed': False, 'target': EDGE, 'image_id': IMAGE,
                'network': NETWORK, 'cache_volume': CACHE, 'private_edge_port': 8081, 'published_edge_ports': [],
                'source_sha256': self.operator.meta['source_sha256'], 'profile_sha256': self.operator.meta['profile_sha256'],
                'cli_configuration_sha256': self._cli_sha256,
                'source_mount': str(self.operator.root / 'source'), 'source_read_only': True,
                'environment_fields': len(self._functions),
                'flags': {key: self._functions.get(key, 'unset') for key in FLAG_NAMES},
                'preconditions': self.preconditions, 'ready_to_create_edge': all(self.preconditions.values()),
                'root_actions': ['create_only_closed_edge', 'verify_read_only_mounts', 'start_only_new_edge'],
                'lifecycle': {'cli_project': PROJECT, 'generic_cli_edge_disabled_required': True,
                              'ordinary_cli_stop_includes_closed_edge': True,
                              'ordinary_cli_start_reinstalls_closed_edge': False,
                              'retained_operator_reinstall_required_after_stop': True},
                'admin': {'origin': self.operator.profile['admin_origin'], 'fresh_flutter_assets_required': True,
                          'use_existing_frontend_hosting': True, 'frontend_deployment_performed': False},
                'commissioning': {'database_migrations_performed': False, 'keys_rotated': False, 'providers_dispatched': False,
                                  'schedulers_installed': False, 'attested_https_proven': False, 'business_acceptance_proven': False}}

    def _create_body(self):
        return {'Image': IMAGE, 'Entrypoint': ['edge-runtime'],
                'Cmd': ['start', '--port', '8081', '--main-service', '/home/deno/main', '--user-worker-request-idle-timeout', '150000'],
                'Env': [key + '=' + value for key, value in sorted(self._functions.items())],
                'Labels': {CLI_LABEL: PROJECT, 'com.docker.compose.project': PROJECT,
                           LABEL: 'true', LABEL + '.source': self.operator.meta['source_sha256'],
                           LABEL + '.profile': self.operator.meta['profile_sha256']},
                'HostConfig': {'NetworkMode': NETWORK, 'ReadonlyRootfs': True, 'CapDrop': ['ALL'],
                    'SecurityOpt': ['no-new-privileges:true'], 'Tmpfs': {'/tmp': 'rw,nosuid,nodev,size=64m'},
                    'RestartPolicy': {'Name': 'unless-stopped'}, 'LogConfig': {'Type': 'json-file', 'Config': {'max-size': '10m', 'max-file': '5'}},
                    'Mounts': [{'Type': 'bind', 'Source': str(self.operator.root / 'source'), 'Target': '/home/deno/collect', 'ReadOnly': True},
                               {'Type': 'bind', 'Source': str(self.operator.root / 'source/deploy/self-hosted/edge-main'), 'Target': '/home/deno/main', 'ReadOnly': True},
                               {'Type': 'volume', 'Source': CACHE, 'Target': '/root/.cache/deno', 'VolumeOptions': {'NoCopy': True}}]},
                'NetworkingConfig': {'EndpointsConfig': {NETWORK: {'Aliases': ['edge_runtime', EDGE]}}}}


def plan(release, engine, *, cli_config, locations=None):
    operator = Operator(release)
    cli_configuration = read_cli_configuration(cli_config)
    functions = read_env(operator.root / 'private/functions.env')
    expected_leaf = leaf_sha256((operator.root / 'private/db-tls/server.crt').read_text())
    topology = observe(engine, functions.get('COLLECT_DB_CA_PEM'), expected_leaf_sha256=expected_leaf)
    return RetainedPlan(operator, functions, topology, shared_locations() if locations is None else locations, cli_configuration)


def _verify_mounted_file(archive, expected):
    try:
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:*') as tar:
            entries = tar.getmembers()
            if len(entries) != 1 or not entries[0].isfile() or entries[0].size > MAX_RESPONSE:
                raise ValueError()
            body = tar.extractfile(entries[0]).read(MAX_RESPONSE + 1)
            if hashlib.sha256(body).hexdigest() != expected:
                raise ValueError()
    except Exception:
        raise RetainedError('retained_host_mount_readback_failed') from None


def execute(selected, engine):
    if not all(selected.preconditions.values()):
        raise RetainedError('retained_preconditions_unmet')
    # Recheck the same seal, complete source, dependencies and actual TLS proof
    # immediately before the only lifecycle mutations. No stale plan can apply.
    current = plan(selected.operator.root, engine, cli_config=selected._cli_path)
    if not all(current.preconditions.values()) or current.topology != selected.topology or current._functions != selected._functions or current._cli_sha256 != selected._cli_sha256:
        raise RetainedError('retained_plan_changed')
    created = engine.request('POST', '/containers/create?' + urlencode({'name': EDGE}), current._create_body())
    identity = created.get('Id') if isinstance(created, dict) else None
    if not isinstance(identity, str) or not re.fullmatch(r'[a-f0-9]{64}', identity):
        raise RetainedError('retained_create_outcome_unconfirmed')
    # Failure leaves the replacement stopped and retained volumes intact. Never
    # rm/rm -v, delete a cache, recreate another service or start a different ID.
    for path, expected in current._mount_checks.items():
        archive = engine.request('GET', '/containers/' + identity + '/archive?' + urlencode({'path': path}), binary=True)
        _verify_mounted_file(archive, expected)
    actual_cache = engine.request('GET', '/volumes/' + CACHE)
    if any(actual_cache.get(key) != current.topology['cache'][name] for key, name in (('Name', 'name'), ('CreatedAt', 'created'), ('Driver', 'driver'))):
        raise RetainedError('retained_cache_changed')
    engine.request('POST', '/containers/' + identity + '/start')
    result = current.describe()
    result.update(dry_run=False, runtime_changed=True, new_edge_id=identity,
                  source_mount_readback_verified=True, container_start_acknowledged=True)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', required=True, type=Path)
    parser.add_argument('--cli-config', required=True, type=Path, help='Retained project config.toml; generic Edge must be explicitly disabled')
    parser.add_argument('--docker-host', required=True, choices=(DOCKER_HOST,))
    parser.add_argument('--execute', action='store_true', help='Explicit operator-only Edge replacement; default is read-only dry-run')
    args = parser.parse_args(argv)
    try:
        engine = DockerEngine(args.docker_host)
        selected = plan(args.release, engine, cli_config=args.cli_config)
        print(json.dumps(execute(selected, engine) if args.execute else selected.describe(), sort_keys=True))
        return 0
    except Exception as error:
        # No traceback, daemon error body, URL credentials, env or keys.
        code = str(error) if isinstance(error, RetainedError) else 'retained_configuration_invalid'
        print(json.dumps({'code': code, 'completed': False, 'automatic_replay': False}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
