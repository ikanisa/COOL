"""Real sealed-release validation; synthetic Docker Engine/CLI and public TLS.

No Docker socket, retained configuration, DB, provider or signing key is used.
"""
import copy
from contextlib import redirect_stdout, redirect_stderr
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import unittest
from unittest.mock import patch

from scripts.self_hosted import retained_collect as r
from scripts.self_hosted.prepare import dotenv
from scripts.self_hosted import test_release_source_identity as source_fixture
from scripts.supabase.deployment_profile import canonical_profile


PRIVATE = 'synthetic-private-marker-never-in-output'
CA = '-----BEGIN CERTIFICATE-----\nQQ==\n-----END CERTIFICATE-----'


def tar_file(data):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w') as archive:
        entry = tarfile.TarInfo('fixture.ts'); entry.size = len(data)
        archive.addfile(entry, io.BytesIO(data))
    return output.getvalue()


class Engine:
    """Narrow engine double; mutation requests are recorded, never performed."""
    def __init__(self, root, profile):
        self.root, self.profile = root, profile
        self.calls, self.commands, self.created = [], [], None
        self.ssl, self.tls, self.bad_mount, self.fail_create = 'on', True, False, False
        self.volume = {'Name': r.CACHE, 'CreatedAt': 'synthetic-original-cache', 'Driver': 'local'}
        self.network = {'Id': 'b' * 64}
        self.image = {'Id': r.IMAGE}
        def container(name, identity, aliases):
            return {'Id': identity * 64, 'Image': r.IMAGE, 'State': {'Running': True, 'Status': 'running'},
                    'Config': {'Env': ['PRIVATE_SOURCE=' + PRIVATE], 'Cmd': ['embedded script ' + PRIVATE], 'Labels': None},
                    'NetworkSettings': {'Networks': {r.NETWORK: {'NetworkID': self.network['Id'], 'Aliases': aliases}}}}
        self.containers = {r.EDGE: container(r.EDGE, 'a', ['edge_runtime']),
                           r.KONG: container(r.KONG, 'c', ['kong', 'api.supabase.internal']),
                           r.DATABASE: container(r.DATABASE, 'd', ['db', 'db.supabase.internal']),
                           r.AUTH: container(r.AUTH, 'e', ['auth'])}
        self.containers[r.EDGE]['State'] = {'Running': False, 'Status': 'exited'}
        self.containers[r.KONG]['NetworkSettings']['Ports'] = {'8000/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '55101'}]}
        self.containers[r.DATABASE]['NetworkSettings']['Ports'] = {'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '55102'}]}
        self.containers[r.AUTH]['Config']['Env'] += ['GOTRUE_JWT_ISSUER=' + profile['supabase_origin'] + '/auth/v1',
                                                   'API_EXTERNAL_URL=' + profile['supabase_origin'] + '/auth/v1']
        self.original_edge = self.containers.pop(r.EDGE)
        self.cli_edges = []
        self.upstream = 'http://' + r.EDGE + ':8081/'

    def inspect(self, name, *, missing=False):
        self.calls.append(('inspect', name))
        return copy.deepcopy(self.containers.get(name))

    def readonly(self, arguments, *, input=None):
        self.commands.append((arguments, input))
        if arguments == [r.KONG, 'cat', '/home/kong/kong.yml']:
            value = {'consumers': [{'private-fixture-only': PRIVATE}], 'services': [{
                'name': 'functions-v1', 'url': self.upstream, 'routes': [{'paths': ['/functions/v1/'], 'strip_path': True}]}]}
            return subprocess.CompletedProcess(arguments, 0, json.dumps(value).encode(), b'')
        if arguments[:2] == [r.DATABASE, 'psql']:
            return subprocess.CompletedProcess(arguments, 0, ('port|5432\nssl|' + self.ssl + '\nssl_ca_file|\nssl_cert_file|public-cert.pem\nssl_key_file|private-key-path-only.pem\n').encode(), b'')
        raise AssertionError('Unexpected metadata command')

    def request(self, method, path, body=None, **kwargs):
        self.calls.append((method, path))
        if method == 'GET' and path.startswith('/images/'):
            return copy.deepcopy(self.image)
        if method == 'GET' and path.startswith('/volumes/'):
            return copy.deepcopy(self.volume)
        if method == 'GET' and path.startswith('/networks/'):
            return copy.deepcopy(self.network)
        if method == 'GET' and path.startswith('/containers/json?'):
            return copy.deepcopy(self.cli_edges)
        if method == 'POST' and '/rename?' in path:
            return None
        if method == 'POST' and path.startswith('/containers/create?'):
            if self.fail_create:
                raise r.RetainedError('retained_docker_outcome_unconfirmed')
            self.created = copy.deepcopy(body)
            return {'Id': 'f' * 64, 'Warnings': [PRIVATE]}
        if method == 'GET' and '/archive?' in path:
            from urllib.parse import parse_qs, urlsplit
            target = parse_qs(urlsplit(path).query)['path'][0]
            relative = ('deploy/self-hosted/edge-main/' + target.rsplit('/', 1)[-1]
                        if target.startswith('/home/deno/main/') else target.removeprefix('/home/deno/collect/'))
            return tar_file(b'wrong source' if self.bad_mount else (self.root / 'source' / relative).read_bytes())
        if method == 'POST' and path.endswith('/start'):
            return None
        raise AssertionError('Unexpected engine operation')


class RetainedCollect(unittest.TestCase):
    def setUp(self):
        # Reuse the existing tiny, actually sealed source fixture. Its own
        # source-identity tests remain unchanged and independently executable.
        self.fixture = source_fixture.ReleaseSourceIdentity(methodName='runTest')
        self.fixture.setUp(); self.addCleanup(self.fixture.doCleanups)
        self.root, self.profile = self.fixture.root, self.fixture.profile
        self.functions = {'COLLECT_DEPLOYMENT_PROFILE': canonical_profile(self.profile),
            'COLLECT_DEPLOYMENT_PROFILE_SHA256': '', 'BUILD_SOURCE_ID': '', 'APP_ENVIRONMENT': 'qualification',
            'SUPABASE_URL': self.profile['supabase_origin'], 'SUPABASE_INTERNAL_URL': 'http://api-gw:8000',
            'COLLECT_DATABASE_URL': 'postgres://collect_edge:' + PRIVATE + '@db:5432/postgres', 'COLLECT_DB_CA_PEM': CA,
            'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_' + PRIVATE, 'SUPABASE_SECRET_KEY': 'sb_secret_' + PRIVATE,
            'DATA_ENCRYPTION_KEY': PRIVATE + '$$\n"quoted"', 'SESSION_ENCRYPTION_KEY': PRIVATE,
            'BURIMUNSI_NATIVE_ENABLED': 'false', 'BURIMUNSI_NATIVE_WORKERS_ENABLED': 'false', 'BURIMUNSI_NATIVE_UPLOADS_ENABLED': 'false'}
        for name in r.FUNCTIONS:
            self.fixture._write(self.root / 'source/supabase/functions' / name / 'index.ts', b'// synthetic canonical function\n')
        for name in ('index.ts', 'router.ts', 'environment.mjs'):
            self.fixture._write(self.root / 'source/deploy/self-hosted/edge-main' / name, ('// synthetic ' + name + '\n').encode())
        self.fixture._write(self.root / 'source/supabase/functions/_shared/serve.js', b'// synthetic host fixture\n')
        (self.root / 'private/db-tls/server.crt').write_text(CA)
        self.fixture._refresh_manifest_and_receipt()
        meta = json.loads((self.root / 'release.json').read_text())
        self.functions.update(BUILD_SOURCE_ID=meta['source_sha256'], COLLECT_DEPLOYMENT_PROFILE_SHA256=meta['profile_sha256'])
        self.seal_functions()
        self.engine = Engine(self.root, self.profile)
        self.probe_calls = []
        def probe(ca, *, expected_leaf_sha256=None):
            self.probe_calls.append((ca, expected_leaf_sha256))
            return {'verified': True} if self.engine.tls else None
        self.probe_patch = patch.object(r, 'probe_database_tls', side_effect=probe)
        self.probe_patch.start(); self.addCleanup(self.probe_patch.stop)
        self.cli_config = self.fixture.parent / 'config.toml'
        self.cli_config.write_text('project_id = "local-app"\n[api]\nport = 55101\n[edge_runtime]\nenabled = false\n')
        self.mounts = patch.object(r, 'shared_locations', return_value=(self.fixture.parent,))
        self.mounts.start(); self.addCleanup(self.mounts.stop)

    def seal_functions(self):
        (self.root / 'private/functions.env').write_text(dotenv(self.functions))
        self.fixture._refresh_manifest_and_receipt()

    def plan(self):
        return r.plan(self.root, self.engine, cli_config=self.cli_config)

    def mutations(self):
        return [call for call in self.engine.calls if call[0] == 'POST']

    def test_dry_run_has_no_lifecycle_changes_or_secret_output(self):
        selected = self.plan(); value = selected.describe()
        self.assertTrue(value['dry_run']); self.assertTrue(value['ready_to_create_edge'])
        self.assertEqual(self.mutations(), [])
        self.assertNotIn(PRIVATE, json.dumps(value)); self.assertNotIn(PRIVATE, repr(selected))
        self.assertFalse(value['commissioning']['business_acceptance_proven'])
        self.assertTrue(value['admin']['fresh_flutter_assets_required'])

    def test_private_json_env_preserves_newline_quotes_and_dollars_without_cli_envfile(self):
        selected = self.plan(); body = selected._create_body()
        env = dict(value.split('=', 1) for value in body['Env'])
        self.assertEqual(env['DATA_ENCRYPTION_KEY'], self.functions['DATA_ENCRYPTION_KEY'])
        self.assertEqual(env['COLLECT_DB_CA_PEM'], CA)
        self.assertEqual(env['SUPABASE_INTERNAL_URL'], 'http://kong:8000')
        self.assertEqual(self.functions['SUPABASE_INTERNAL_URL'], 'http://api-gw:8000')
        self.assertNotIn('SUPABASE_INTERNAL_JWT_SECRET', env)
        self.assertEqual(body['Entrypoint'], ['edge-runtime'])
        self.assertNotIn('PortBindings', body['HostConfig'])
        self.assertEqual([mount['ReadOnly'] for mount in body['HostConfig']['Mounts'][:2]], [True, True])
        self.assertEqual(body['HostConfig']['Mounts'][2]['Source'], r.CACHE)

    def test_tls_probe_authenticates_actual_db_name_with_public_ca_only(self):
        self.plan()
        self.assertEqual(self.probe_calls, [(CA, r.leaf_sha256(CA))])
        self.assertNotIn(PRIVATE, json.dumps([value[0] for value in self.engine.commands]))

    def test_ssl_off_or_wrong_ca_cannot_create_edge(self):
        for field, value in (('ssl', 'off'), ('tls', False)):
            with self.subTest(field=field):
                original = getattr(self.engine, field); setattr(self.engine, field, value)
                selected = self.plan(); self.assertFalse(selected.preconditions['verified_database_tls_db'])
                with self.assertRaisesRegex(r.RetainedError, '^retained_preconditions_unmet$'):
                    r.execute(selected, self.engine)
                setattr(self.engine, field, original)
        self.assertEqual(self.mutations(), [])

    def test_invalid_or_private_material_cannot_be_passed_as_ca(self):
        self.functions['COLLECT_DB_CA_PEM'] = CA + '\n-----BEGIN PRIVATE KEY-----\n' + PRIVATE
        self.seal_functions()
        with self.assertRaisesRegex(r.RetainedError, '^retained_public_database_ca_required$'):
            self.plan()
        self.assertEqual(self.probe_calls, [])

    def test_host_probe_never_runs_against_unverified_published_database_port(self):
        self.engine.containers[r.DATABASE]['NetworkSettings']['Ports']['5432/tcp'][0]['HostPort'] = '55444'
        selected = self.plan()
        self.assertFalse(selected.preconditions['loopback_database_55102'])
        self.assertFalse(selected.preconditions['verified_database_tls_db'])
        self.assertEqual(self.probe_calls, [])

    def test_existing_running_or_partial_adapter_edge_is_never_replaced(self):
        edge = self.engine.containers[r.EDGE] = self.engine.original_edge
        for change in ({}, {'running': True}, {'owned': True}, {'image': 'sha256:' + '0' * 64}):
            with self.subTest(change=change):
                old = copy.deepcopy(edge)
                if 'running' in change: edge['State']['Running'] = True
                if 'owned' in change: edge['Config']['Labels'] = {r.LABEL: 'true'}
                if 'image' in change: edge['Image'] = change['image']
                selected = self.plan(); self.assertFalse(selected.preconditions['original_edge_absent'])
                with self.assertRaises(r.RetainedError): r.execute(selected, self.engine)
                edge.clear(); edge.update(old)
        self.assertEqual(self.mutations(), [])

    def test_absent_edge_reuses_existing_cache_and_no_other_service(self):
        result = r.execute(self.plan(), self.engine)
        self.assertTrue(result['container_start_acknowledged'])
        self.assertEqual(len(self.mutations()), 2)
        self.assertNotIn('/rename?', json.dumps(self.mutations()))
        self.assertEqual(self.engine.created['Image'], r.IMAGE)
        self.assertEqual(self.engine.created['HostConfig']['NetworkMode'], r.NETWORK)
        self.assertEqual(self.engine.created['Labels'][r.CLI_LABEL], r.PROJECT)
        self.assertEqual(self.engine.created['Labels']['com.docker.compose.project'], r.PROJECT)

    def test_success_checks_mounts_before_exact_new_id_start(self):
        result = r.execute(self.plan(), self.engine)
        calls = self.engine.calls
        mutations = self.mutations()
        self.assertEqual(len(mutations), 2)
        self.assertIn('/containers/create?', mutations[0][1])
        self.assertEqual(mutations[1], ('POST', '/containers/' + 'f' * 64 + '/start'))
        archives = [index for index, value in enumerate(calls) if '/archive?' in value[1]]
        self.assertEqual(len(archives), 4)
        self.assertLess(max(archives), calls.index(mutations[1]))
        self.assertFalse(any(value[0] == 'DELETE' for value in calls))
        self.assertNotIn(PRIVATE, json.dumps(result)); self.assertFalse(result['commissioning']['keys_rotated'])

    def test_changed_host_mount_preserves_evidence_and_never_starts(self):
        self.engine.bad_mount = True
        with self.assertRaisesRegex(r.RetainedError, '^retained_host_mount_readback_failed$'):
            r.execute(self.plan(), self.engine)
        self.assertEqual(len(self.mutations()), 1)
        self.assertFalse(any(path.endswith('/start') for _, path in self.mutations()))

    def test_unknown_create_is_not_replayed_or_deleted(self):
        self.engine.fail_create = True
        with self.assertRaisesRegex(r.RetainedError, '^retained_docker_outcome_unconfirmed$'):
            r.execute(self.plan(), self.engine)
        self.assertEqual(len(self.mutations()), 1)
        self.assertFalse(any(value[0] == 'DELETE' for value in self.engine.calls))

    def test_replaced_cache_is_never_accepted_or_started(self):
        request = self.engine.request
        def changed(method, path, *args, **kwargs):
            value = request(method, path, *args, **kwargs)
            if method == 'GET' and path.startswith('/volumes/') and self.engine.created is not None:
                return {**value, 'CreatedAt': 'replacement-volume'}
            return value
        self.engine.request = changed
        with self.assertRaisesRegex(r.RetainedError, '^retained_cache_changed$'):
            r.execute(self.plan(), self.engine)
        self.assertFalse(any(path.endswith('/start') for _, path in self.mutations()))

    def test_changed_configuration_cannot_apply_old_plan(self):
        selected = self.plan(); self.functions['SESSION_ENCRYPTION_KEY'] += '-changed'; self.seal_functions()
        with self.assertRaisesRegex(r.RetainedError, '^retained_plan_changed$'):
            r.execute(selected, self.engine)
        self.assertEqual(self.mutations(), [])

    def test_generic_cli_edge_must_stay_disabled_and_config_is_revalidated(self):
        selected = self.plan()
        self.cli_config.write_text(self.cli_config.read_text().replace('enabled = false', 'enabled = true'))
        self.assertFalse(self.plan().preconditions['cli_generic_edge_disabled'])
        with self.assertRaisesRegex(r.RetainedError, '^retained_plan_changed$'):
            r.execute(selected, self.engine)
        self.assertEqual(self.mutations(), [])

    def test_renamed_cli_owned_original_refuses_duplicate_project_edge(self):
        self.engine.cli_edges = [{'Id': 'a' * 64, 'Names': ['/' + r.EDGE + '.preserved'],
                                  'ImageID': r.IMAGE, 'Labels': {r.CLI_LABEL: r.PROJECT}}]
        selected = self.plan()
        self.assertFalse(selected.preconditions['no_duplicate_cli_owned_edge'])
        with self.assertRaisesRegex(r.RetainedError, '^retained_preconditions_unmet$'):
            r.execute(selected, self.engine)
        self.assertEqual(self.mutations(), [])
        from urllib.parse import parse_qs, urlsplit
        listed = [path for method, path in self.engine.calls if method == 'GET' and path.startswith('/containers/json?')]
        query = parse_qs(urlsplit(listed[0]).query)
        self.assertEqual(query['all'], ['1'])
        self.assertEqual(json.loads(query['filters'][0]), {'label': [r.CLI_LABEL + '=' + r.PROJECT]})

    def test_duplicate_edge_appearing_after_plan_refuses_create(self):
        selected = self.plan()
        self.engine.cli_edges.append({'Id': 'a' * 64, 'Names': ['/renamed'], 'ImageID': r.IMAGE, 'Labels': {}})
        with self.assertRaisesRegex(r.RetainedError, '^retained_plan_changed$'):
            r.execute(selected, self.engine)
        self.assertEqual(self.mutations(), [])

    def test_wrong_project_or_loopback_port_is_refused_before_engine(self):
        for text in ('project_id = "other"\n[api]\nport = 55101\n',
                     'project_id = "local-app"\n[api]\nport = 54321\n'):
            with self.subTest(text=text):
                self.cli_config.write_text(text)
                with self.assertRaisesRegex(r.RetainedError, '^retained_cli_configuration_invalid$'):
                    self.plan()
        self.assertEqual(self.engine.calls, [])

    def test_source_change_fails_before_any_docker_access(self):
        (self.root / 'source/supabase/functions/collect-api/index.ts').write_text('// changed')
        with self.assertRaisesRegex(ValueError, '^Source file changed$'): self.plan()
        self.assertEqual(self.engine.calls, [])

    def test_unshared_host_path_is_explicit_precondition(self):
        selected = r.plan(self.root, self.engine, cli_config=self.cli_config, locations=(Path('/unshared-synthetic'),))
        self.assertFalse(selected.preconditions['host_bind_within_existing_share'])
        with self.assertRaises(r.RetainedError): r.execute(selected, self.engine)
        self.assertEqual(self.mutations(), [])

    def test_fixed_gateway_network_image_loopback_and_public_auth_remain_required(self):
        for name, change, expected in (
            ('route', lambda: setattr(self.engine, 'upstream', 'http://other:8081/'), 'original_kong_function_route'),
            ('image', lambda: self.engine.image.update(Id='sha256:' + '0' * 64), 'original_cached_edge_image'),
            ('network', lambda: self.engine.containers[r.KONG]['NetworkSettings']['Networks'][r.NETWORK].update(NetworkID='0' * 64), 'retained_private_network'),
            ('loopback', lambda: self.engine.containers[r.KONG]['NetworkSettings']['Ports']['8000/tcp'][0].update(HostIp='0.0.0.0'), 'loopback_api_55101'),
            ('auth', lambda: self.engine.containers[r.AUTH]['Config']['Env'].append('GOTRUE_JWT_ISSUER=http://localhost/auth/v1'), 'auth_public_issuer')):
            with self.subTest(name=name):
                self.engine = Engine(self.root, self.profile); change()
                selected = self.plan(); self.assertFalse(selected.preconditions[expected])
                with self.assertRaises(r.RetainedError): r.execute(selected, self.engine)
                self.assertEqual(self.mutations(), [])

    def test_auth_external_url_requires_canonical_auth_mount_not_bare_api_origin(self):
        self.assertTrue(self.plan().preconditions['auth_public_issuer'])
        self.engine.containers[r.AUTH]['Config']['Env'].append('API_EXTERNAL_URL=' + self.profile['supabase_origin'])
        selected = self.plan()
        self.assertFalse(selected.preconditions['auth_public_issuer'])
        with self.assertRaisesRegex(r.RetainedError, '^retained_preconditions_unmet$'):
            r.execute(selected, self.engine)
        self.assertEqual(self.mutations(), [])

    def test_root_signing_auth_smtp_and_untrusted_transport_are_not_inherited(self):
        for key in ('JWT_SECRET', 'SUPABASE_DB_URL', 'POSTGRES_PASSWORD', 'SMTP_PASS', 'GOTRUE_JWT_KEYS', 'SUPABASE_INTERNAL_JWT_SECRET'):
            with self.subTest(key=key):
                self.functions[key] = PRIVATE; self.seal_functions()
                with self.assertRaisesRegex(r.RetainedError, '^retained_function_secret_boundary_invalid$'): self.plan()
                del self.functions[key]
        self.functions['SUPABASE_INTERNAL_URL'] = 'http://attacker:8000'; self.seal_functions()
        with self.assertRaisesRegex(r.RetainedError, '^retained_internal_origin_invalid$'): self.plan()

    def test_cli_defaults_to_sanitized_dry_run(self):
        stdout = io.StringIO()
        with patch.object(r, 'DockerEngine', return_value=self.engine), redirect_stdout(stdout):
            code = r.main(['--release', str(self.root), '--cli-config', str(self.cli_config), '--docker-host', r.DOCKER_HOST])
        self.assertEqual(code, 0); self.assertTrue(json.loads(stdout.getvalue())['dry_run'])
        self.assertNotIn(PRIVATE, stdout.getvalue()); self.assertEqual(self.mutations(), [])

    def test_cli_failure_discards_private_parser_or_daemon_details(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(r, 'DockerEngine', return_value=self.engine), patch.object(r, 'plan', side_effect=ValueError(PRIVATE)), redirect_stdout(stdout), redirect_stderr(stderr):
            code = r.main(['--release', str(self.root), '--cli-config', str(self.cli_config), '--docker-host', r.DOCKER_HOST, '--execute'])
        self.assertEqual(code, 1); self.assertEqual(stdout.getvalue(), '')
        self.assertNotIn(PRIVATE, stderr.getvalue()); self.assertIn('retained_configuration_invalid', stderr.getvalue())

    def test_archive_rejects_links_without_extracting_anything(self):
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode='w') as archive:
            value = tarfile.TarInfo('link'); value.type = tarfile.SYMTYPE; value.linkname = '/outside'
            archive.addfile(value)
        with self.assertRaisesRegex(r.RetainedError, '^retained_host_mount_readback_failed$'):
            r._verify_mounted_file(output.getvalue(), hashlib.sha256(b'').hexdigest())

    def test_engine_discards_private_daemon_error_body(self):
        class Connection:
            status = 500
            def request(self, *args, **kwargs): pass
            def getresponse(self): return self
            def read(self, maximum): return PRIVATE.encode()
            def close(self): pass
        engine = object.__new__(r.DockerEngine); engine.path = '/synthetic-socket'
        with patch.object(r, '_UnixHTTP', return_value=Connection()):
            with self.assertRaisesRegex(r.RetainedError, '^retained_docker_request_refused$') as caught:
                engine.request('POST', '/containers/create', {'Env': ['PRIVATE=' + PRIVATE]})
        self.assertNotIn(PRIVATE, str(caught.exception))

    def test_only_explicit_retained_unix_socket_is_allowed(self):
        for endpoint in ('unix:///var/run/docker.sock', 'tcp://localhost:2375', 'ssh://other', ''):
            with self.subTest(endpoint=endpoint), patch.object(Path, 'stat') as metadata:
                with self.assertRaisesRegex(r.RetainedError, '^retained_docker_socket_required$'):
                    r.DockerEngine(endpoint)
                metadata.assert_not_called()


if __name__ == '__main__':
    unittest.main()
