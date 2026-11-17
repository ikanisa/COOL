"""Real sealed source checks with synthetic Engine/crypto responses.

No Docker socket, retained files, database, provider or certificate creation.
The separate OpenSSL rejection case exercises only malformed in-memory input.
"""
import copy
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.self_hosted import retained_database_tls as t
from scripts.self_hosted import test_release_source_identity as source_fixture
from scripts.self_hosted.prepare import dotenv, seal_configuration

CA = b'-----BEGIN CERTIFICATE-----\nQQ==\n-----END CERTIFICATE-----\n'
LEAF = b'-----BEGIN CERTIFICATE-----\nQg==\n-----END CERTIFICATE-----\n'
KEY = b'-----BEGIN PRIVATE KEY-----\nQw==\n-----END PRIVATE KEY-----\n'
PRIVATE = 'synthetic-private-diagnostic-never-print'
IDENTITY = 'a' * 64


class Engine:
    def __init__(self):
        self.container = {'Id': IDENTITY, 'Image': t.IMAGE, 'Name': '/' + t.DATABASE,
            'State': {'Running': True}, 'Config': {'Labels': {t.CLI_LABEL: t.PROJECT},
                'Env': ['PRIVATE=' + PRIVATE], 'Cmd': ['embedded script ' + PRIVATE]},
            'HostConfig': {'NetworkMode': t.NETWORK},
            'NetworkSettings': {'Networks': {t.NETWORK: {'NetworkID': 'b' * 64, 'Aliases': ['db', 'db.supabase.internal']}},
                               'Ports': {'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '55102'}]}},
            'Mounts': [{'Type': 'volume', 'Name': t.VOLUME, 'Destination': t.PGDATA, 'RW': True}]}
        self.volume = {'Name': t.VOLUME, 'Driver': 'local', 'CreatedAt': 'original-volume-creation'}
        self.metadata = {'major': 17, 'data_directory': t.PGDATA, 'port': '5432',
            'socket_directory': '/var/run/postgresql', 'bootstrap_role': 'supabase_admin',
            'current_user': 'supabase_admin', 'session_user': 'supabase_admin', 'superuser': True, 'file_errors': 0,
            'settings': {name: {'setting': 'off' if name == 'ssl' else '', 'source': 'default',
                'sourcefile': None, 'context': 'sighup', 'pending_restart': False} for name in t.SETTINGS}}
        self.uid, self.gid = 105, 106
        self.directory = False
        self.directory_mode, self.directory_contents = '700', b''
        self.installed, self.calls, self.writes, self.inputs = {}, [], [], []
        self.pending = {}
        self.lost_phase = None
        self.handshake = True
        self.reload_stale, self.reload_ack, self.wrong_owner = False, True, False
        self.corrupt_copy = False

    def inspect(self, name):
        self.calls.append(('inspect', name))
        assert name == t.DATABASE
        return copy.deepcopy(self.container)

    def request(self, method, path):
        self.calls.append((method, path))
        assert method == 'GET'
        if path == '/volumes/' + t.VOLUME:
            return copy.deepcopy(self.volume)
        if path == '/networks/' + t.NETWORK:
            return {'Id': 'b' * 64}
        raise AssertionError('Unexpected engine operation')

    def readonly(self, arguments, *, input=None):
        self.calls.append(('readonly', list(arguments)))
        assert arguments[0] == IDENTITY
        command = arguments[1:]
        if command == ['id', '-u', 'postgres']:
            raw = str(self.uid).encode()
        elif command == ['id', '-g', 'postgres']:
            raw = str(self.gid).encode()
        elif command == ['stat', '-c', '%u:%g:%a:%F', t.PGDATA]:
            raw = f'{self.uid}:{self.gid}:700:directory'.encode()
        elif command == ['sh', '-c', t.PRESENCE]:
            raw = b'present' if self.directory else b'absent'
        elif command == [*t.PSQL, t.OBSERVE_SQL]:
            raw = json.dumps(self.metadata).encode()
        elif command == ['stat', '-c', '%u:%g:%a:%F', t.TLS_DIR]:
            assert self.directory
            raw = f'{self.uid}:{self.gid}:{self.directory_mode}:directory'.encode()
        elif command[:2] == ['find', t.TLS_DIR]:
            # The retained image uses BusyBox, which has -print but no -printf.
            assert command == ['find', t.TLS_DIR, '-mindepth', '1', '-maxdepth', '1', '-print']
            raw = self.directory_contents
        elif command[:3] == ['stat', '-c', '%u:%g:%a:%F:%h']:
            name = command[-1].rsplit('/', 1)[-1]
            member = self.installed[name]
            raw = f"{member.uid}:{member.gid}:{'644' if self.wrong_owner else '600'}:regular file:1".encode()
        elif command[0] == 'sha256sum':
            name = command[-1].rsplit('/', 1)[-1]
            member = self.installed[name]
            raw = (hashlib.sha256(member.body).hexdigest() + '  ' + command[-1]).encode()
        else:
            raise AssertionError('Unexpected read-only command')
        return subprocess.CompletedProcess(arguments, 0, raw, b'')

    def write(self, arguments, *, input=None):
        self.writes.append(list(arguments))
        if arguments[:3] == ['exec', '--user', f'{self.uid}:{self.gid}']:
            assert arguments[3:] == [IDENTITY, 'mkdir', '-m', '0700', '--', t.TLS_DIR]
            assert not self.directory
            self.directory = True
            phase, result = 'directory_create', b''
        elif arguments == ['cp', '--archive', '-', IDENTITY + ':' + t.TLS_DIR]:
            assert self.directory and not self.installed
            with tarfile.open(fileobj=io.BytesIO(input), mode='r:') as archive:
                for member in archive.getmembers():
                    assert member.name in t.FILES and member.isfile() and member.mode == 0o600
                    self.installed[member.name] = SimpleNamespace(uid=member.uid, gid=member.gid, mode=member.mode,
                        body=archive.extractfile(member).read())
            if self.corrupt_copy:
                self.installed['server.crt'].body = b'corrupt'
            phase, result = 'certificate_copy', b''
        else:
            assert arguments[:2] == ['exec', IDENTITY] and arguments[2:-1] == list(t.PSQL)
            statement = arguments[-1]
            if statement == t.RELOAD:
                if not self.reload_stale:
                    for name, value in self.pending.items():
                        self.metadata['settings'][name].update(setting=value, source='configuration file',
                            sourcefile=t.PGDATA + '/postgresql.auto.conf')
                phase, result = 'configuration_reload', b't\n' if self.reload_ack else b'f\n'
            else:
                position = t.ALTERS.index(statement)
                name, value = (('ssl_cert_file', '.collect-tls/server.crt'),
                               ('ssl_key_file', '.collect-tls/server.key'), ('ssl', 'on'))[position]
                self.pending[name] = value
                phase, result = ('set_certificate', 'set_leaf_key', 'enable_ssl')[position], b''
        if self.lost_phase == phase:
            raise t.TLSError('retained_tls_write_outcome_unconfirmed')
        return result


class RetainedDatabaseTLS(unittest.TestCase):
    def setUp(self):
        self.fixture = source_fixture.ReleaseSourceIdentity(methodName='runTest')
        self.fixture.setUp(); self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        (self.root / 'private').chmod(0o700)
        self.tls = self.root / 'private/db-tls'; self.tls.chmod(0o700)
        for name, raw in zip(t.FILES, (CA, LEAF, KEY)):
            (self.tls / name).write_bytes(raw); (self.tls / name).chmod(0o600)
        authority = self.root / 'private/db-ca'; authority.mkdir(mode=0o700)
        (authority / 'ca.key').write_text(PRIVATE); (authority / 'ca.key').chmod(0o600)
        (self.root / 'private/functions.env').write_text(dotenv({'COLLECT_DB_CA_PEM': CA.decode().strip()}))
        seal_configuration(self.root)
        self.engine = Engine()
        self.state = self.fixture.parent / 'tls-state.jsonl'
        self.expired, self.mismatch, self.san, self.chain = False, False, b'DNS:db', True
        self.openssl_calls = []
        self.crypto = patch.object(t, '_openssl', side_effect=self.openssl)
        self.crypto.start(); self.addCleanup(self.crypto.stop)
        def probe(ca, *, expected_leaf_sha256=None):
            self.engine.inputs.append(ca.encode())
            self.assertEqual(expected_leaf_sha256, t.leaf_sha256(LEAF.decode()))
            return {'verified': True} if self.engine.handshake else None
        self.probe_patch = patch.object(t, 'probe_database_tls', side_effect=probe)
        self.probe_patch.start(); self.addCleanup(self.probe_patch.stop)

    def openssl(self, args, *, input=None, pass_fds=()):
        self.openssl_calls.append((list(args), input))
        if args[0] == 'x509' and '-checkend' in args:
            if self.expired:
                raise t.TLSError('retained_tls_certificate_validation_failed')
            return b'Certificate will not expire'
        if args[0] == 'x509' and '-pubkey' in args:
            return b'public-leaf-key'
        if args[0] == 'x509' and '-text' in args:
            return b'Certificate:\n    Data:\n        X509v3 extensions:\n            X509v3 Subject Alternative Name:\n                ' + self.san + b'\n    Signature Algorithm: synthetic\n'
        if args[0] == 'pkey':
            return b'other-public-key' if self.mismatch and '-pubin' not in args else b'public-key-DER'
        if args[0] == 'verify':
            assert '-verify_hostname' not in args
            assert args[args.index('-purpose') + 1] == 'sslserver'
            assert len(pass_fds) == 1 and os.read(pass_fds[0], t.MAX_BYTES) == CA
            if not self.chain:
                raise t.TLSError('retained_tls_certificate_validation_failed')
            return b'/dev/stdin: OK\n'
        raise AssertionError('Unexpected cryptography command')

    def plan(self):
        return t.plan(self.root, self.engine)

    def execute(self, selected=None):
        return t.execute(selected or self.plan(), self.engine, state_file=self.state)

    def records(self):
        return [json.loads(line) for line in self.state.read_text().splitlines()]

    def test_default_plan_is_read_only_and_never_discloses_private_material(self):
        selected = self.plan(); result = selected.describe()
        self.assertTrue(result['dry_run']); self.assertTrue(result['ready_to_enable_tls'])
        self.assertFalse(result['tls_verified']); self.assertFalse(self.state.exists())
        self.assertEqual(self.engine.writes, [])
        self.assertNotIn(PRIVATE, json.dumps(result)); self.assertNotIn(KEY.decode(), json.dumps(result))
        self.assertNotIn('server.key', result['certificate_sha256'])
        self.assertNotIn(KEY.decode(), repr(selected.certificates))

    def test_complete_flow_preserves_source_identity_uses_bootstrap_role_and_verified_handshake(self):
        before = copy.deepcopy(self.engine.container)
        result = self.execute()
        self.assertTrue(result['tls_verified']); self.assertTrue(result['persistent_settings_verified'])
        self.assertEqual(self.engine.container, before)
        self.assertEqual(len(self.engine.writes), 6)
        sql = [command[-1] for command in self.engine.writes if command[:2] == ['exec', IDENTITY]]
        self.assertEqual(sql, [*t.ALTERS, t.RELOAD])
        self.assertTrue(all('BEGIN' not in command and 'COMMIT' not in command for command in sql))
        self.assertEqual(set(self.engine.installed), set(t.FILES))
        for member in self.engine.installed.values():
            self.assertEqual((member.uid, member.gid, member.mode), (105, 106, 0o600))
        self.assertEqual(self.engine.inputs, [CA])
        self.assertEqual(self.records()[-1]['status'], 'complete')
        self.assertFalse(self.records()[-1]['reconcile_required'])
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.root / 'private/db-ca/ca.key').read_text(), PRIVATE)
        self.assertNotIn(PRIVATE, json.dumps(result)); self.assertNotIn(PRIVATE, self.state.read_text())
        self.assertNotIn(KEY.decode(), json.dumps(self.engine.writes))

    def test_existing_partial_directory_is_never_reused_or_overwritten(self):
        self.engine.directory = True
        selected = self.plan()
        self.assertFalse(selected.preconditions['exclusive_tls_directory_absent'])
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_preconditions_unmet$'):
            self.execute(selected)
        self.assertEqual(self.engine.writes, []); self.assertFalse(self.state.exists())

    def test_exact_container_image_volume_network_port_and_native_authority_required(self):
        cases = (
            ('image', lambda e: e.container.update(Image='sha256:' + '0' * 64), 'pinned_pg17_image'),
            ('label', lambda e: e.container['Config']['Labels'].clear(), 'existing_cli_project'),
            ('volume', lambda e: e.container['Mounts'][0].update(Name='other'), 'original_persistent_database_volume'),
            ('network', lambda e: e.container['HostConfig'].update(NetworkMode='other'), 'single_existing_private_network'),
            ('port', lambda e: e.container['NetworkSettings']['Ports']['5432/tcp'][0].update(HostIp='0.0.0.0'), 'original_loopback_database_port'),
            ('role', lambda e: e.metadata.update(bootstrap_role='postgres'), 'native_pg17_bootstrap_and_data_directory'),
            ('data', lambda e: e.metadata.update(data_directory='/other'), 'native_pg17_bootstrap_and_data_directory'),
            ('uid', lambda e: setattr(e, 'uid', 0), 'verified_postgres_volume_ownership'),
            ('ssl', lambda e: e.metadata['settings']['ssl'].update(setting='on'), 'original_ssl_off_and_paths_blank'),
            ('override', lambda e: e.metadata['settings']['ssl'].update(source='command line'), 'ssl_reload_without_command_line_override'))
        for name, change, condition in cases:
            with self.subTest(name=name):
                self.engine = Engine(); change(self.engine)
                selected = self.plan(); self.assertFalse(selected.preconditions[condition])
                with self.assertRaises(t.TLSError): self.execute(selected)
                self.assertEqual(self.engine.writes, [])
        self.assertFalse(self.state.exists())

    def test_changed_source_authority_after_plan_denies_all_mutations(self):
        selected = self.plan(); self.engine.volume['CreatedAt'] = 'replaced-volume'
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_plan_changed$'):
            self.execute(selected)
        self.assertEqual(self.engine.writes, [])

    def test_source_replaced_or_ssl_policy_changed_during_copy_stops_before_alter_system(self):
        original = self.engine.write
        for name in ('volume', 'policy'):
            with self.subTest(name=name):
                self.engine = Engine(); self.state = self.fixture.parent / (name + '-changed.jsonl')
                original = self.engine.write
                def changed(arguments, *, input=None):
                    result = original(arguments, input=input)
                    if arguments[0] == 'cp':
                        if name == 'volume': self.engine.volume['CreatedAt'] = 'replaced-during-copy'
                        else: self.engine.metadata['settings']['ssl_cert_file']['setting'] = '/other/certificate'
                    return result
                self.engine.write = changed
                with self.assertRaisesRegex(t.TLSError, '^retained_tls_database_identity_changed$') as caught:
                    self.execute()
                self.assertTrue(caught.exception.reconcile)
                self.assertEqual(len(self.engine.writes), 2); self.assertEqual(self.engine.pending, {})

    def test_private_input_permissions_ca_custody_and_symlinks_fail_before_engine(self):
        path = self.tls / 'server.key'; original = path.read_bytes()
        path.chmod(0o644)
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_owned_0600_inputs_required$'): self.plan()
        path.chmod(0o600)
        path.unlink(); path.symlink_to(self.root / 'private/db-ca/ca.key')
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_owned_0600_inputs_required$'): self.plan()
        path.unlink(); path.write_bytes(original); path.chmod(0o600)
        (self.tls / 'ca.key').write_text(PRIVATE)
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_ca_private_key_must_stay_outside$'): self.plan()
        self.assertEqual(self.engine.calls, [])

    def test_expiry_wrong_san_wrong_key_and_bad_chain_fail_closed(self):
        for field, value, code in (
            ('expired', True, 'certificate_validation_failed'), ('mismatch', True, 'leaf_key_mismatch'),
            ('san', b'DNS:database, DNS:db.attacker', 'explicit_db_san_required'),
            ('chain', False, 'certificate_validation_failed')):
            original = getattr(self, field)
            with self.subTest(field=field):
                setattr(self, field, value)
                with self.assertRaisesRegex(t.TLSError, '^retained_tls_' + code + '$'): self.plan()
            setattr(self, field, original)
        self.assertEqual(self.engine.calls, [])

    def test_mismatched_sealed_client_ca_is_refused(self):
        (self.root / 'private/functions.env').write_text(dotenv({'COLLECT_DB_CA_PEM': LEAF.decode()}))
        seal_configuration(self.root)
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_sealed_client_ca_mismatch$'): self.plan()
        self.assertEqual(self.engine.calls, [])

    def test_lost_write_ack_preserves_partial_files_and_intent_without_replay(self):
        for index, phase in enumerate(('directory_create', 'certificate_copy', 'set_certificate', 'set_leaf_key', 'enable_ssl', 'configuration_reload')):
            with self.subTest(phase=phase):
                self.engine = Engine(); self.engine.lost_phase = phase
                self.state = self.fixture.parent / ('state-' + str(index) + '.jsonl')
                with self.assertRaisesRegex(t.TLSError, '^retained_tls_write_outcome_unconfirmed$') as caught:
                    self.execute()
                self.assertTrue(caught.exception.reconcile)
                self.assertEqual(caught.exception.phase, phase)
                self.assertEqual(len(self.engine.writes), index + 1)
                self.assertTrue(self.engine.directory)
                if index > 0:
                    self.assertEqual(set(self.engine.installed), set(t.FILES))
                record = self.records()[-1]
                self.assertEqual(record['status'], 'reconcile_required')
                self.assertEqual(record['attempted_phase'], phase)
                self.assertTrue(any(row['attempted_phase'] == phase for row in self.records()[:-1]))
                self.assertNotIn(PRIVATE, self.state.read_text())

    def test_occupied_exclusive_directory_or_bad_copy_never_reaches_sql(self):
        for name in ('occupied', 'bad_copy', 'bad_mode'):
            with self.subTest(name=name):
                self.engine = Engine(); self.state = self.fixture.parent / (name + '.jsonl')
                if name == 'occupied': self.engine.directory_contents = b'preexisting-file\n'
                if name == 'bad_copy': self.engine.corrupt_copy = True
                if name == 'bad_mode': self.engine.wrong_owner = True
                with self.assertRaises(t.TLSError) as caught: self.execute()
                self.assertTrue(caught.exception.reconcile)
                self.assertLessEqual(len(self.engine.writes), 2)
                self.assertEqual(self.engine.pending, {})

    @unittest.skipUnless(shutil.which('find'), 'Portable find unavailable')
    def test_real_find_print_checks_empty_and_occupied_directory_with_busybox_flag_boundary(self):
        for occupied in (False, True):
            with self.subTest(occupied=occupied), tempfile.TemporaryDirectory(prefix='collect-find-test-') as area:
                if occupied:
                    (Path(area) / 'unexpected-file').write_text('synthetic fixture')
                self.engine = Engine(); self.state = self.fixture.parent / ('find-' + str(occupied) + '.jsonl')
                readonly = self.engine.readonly
                calls = []
                def portable(arguments, *, input=None):
                    if arguments[1:3] == ['find', t.TLS_DIR]:
                        calls.append(list(arguments))
                        # Emulate the retained BusyBox boundary even on hosts
                        # whose find happens to accept GNU-only extensions.
                        if '-printf' in arguments:
                            return subprocess.CompletedProcess(arguments, 1, b'', b'find: unrecognized: -printf')
                        return subprocess.run(['find', area, *arguments[3:]], capture_output=True, timeout=5)
                    return readonly(arguments, input=input)
                self.engine.readonly = portable
                if occupied:
                    with self.assertRaisesRegex(t.TLSError, '^retained_tls_exclusive_directory_unverified$'):
                        self.execute()
                    self.assertEqual(len(self.engine.writes), 1)
                else:
                    self.assertTrue(self.execute()['tls_verified'])
                self.assertEqual(len(calls), 1)
                self.assertNotIn('-printf', calls[0])

    def test_reload_rejection_staleness_or_tls_verify_failure_never_claims_success(self):
        for name in ('reload_ack', 'reload_stale', 'handshake'):
            with self.subTest(name=name):
                self.engine = Engine(); self.state = self.fixture.parent / (name + '.jsonl')
                setattr(self.engine, name, name == 'reload_stale')
                with patch.object(t.time, 'sleep'), self.assertRaises(t.TLSError) as caught: self.execute()
                self.assertTrue(caught.exception.reconcile)
                self.assertEqual(self.records()[-1]['status'], 'reconcile_required')
                self.assertEqual(len(self.engine.writes), 6)
                self.assertTrue(self.engine.directory); self.assertEqual(set(self.engine.installed), set(t.FILES))

    def test_existing_state_or_public_parent_refuses_before_database_write(self):
        self.state.write_text('preserved-old-evidence')
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_new_private_state_file_required$'): self.execute()
        self.assertEqual(self.state.read_text(), 'preserved-old-evidence')
        public = self.fixture.parent / 'public'; public.mkdir(mode=0o755)
        self.state = public / 'state.jsonl'
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_protected_directory_required$'): self.execute()
        self.assertEqual(self.engine.writes, [])

    def test_replaced_private_journal_cannot_overwrite_other_evidence(self):
        selected = self.plan(); journal = t.Journal(self.state, selected)
        previous = self.fixture.parent / 'original-state.jsonl'
        self.state.rename(previous)
        self.state.write_text('independent-evidence'); self.state.chmod(0o600)
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_private_state_outcome_unconfirmed$'):
            journal.save(status='in_progress', attempted_phase='directory_create')
        self.assertEqual(self.state.read_text(), 'independent-evidence')
        self.assertEqual(len(previous.read_text().splitlines()), 1)
        self.assertEqual(self.engine.writes, [])

    def test_real_write_transport_streams_private_input_and_redacts_unknown_outcome(self):
        runtime = object.__new__(t.TLSRuntime); runtime.host = t.DOCKER_HOST
        with patch.object(t.subprocess, 'run', side_effect=subprocess.TimeoutExpired('docker', 30)) as command:
            with self.assertRaisesRegex(t.TLSError, '^retained_tls_write_outcome_unconfirmed$'):
                runtime.write(['cp', '--archive', '-', IDENTITY + ':' + t.TLS_DIR], input=KEY)
        args = command.call_args.args[0]
        self.assertEqual(args[:3], ['docker', '--host', t.DOCKER_HOST])
        self.assertNotIn(KEY.decode(), json.dumps(args)); self.assertEqual(command.call_args.kwargs['input'], KEY)

    def test_public_certificate_file_is_also_required_to_be_protected_input(self):
        (self.tls / 'ca.crt').chmod(0o644)
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_owned_0600_inputs_required$'):
            self.plan()
        self.assertEqual(self.engine.calls, [])

    def test_private_engine_error_and_key_material_never_enter_cli_output(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(t, 'TLSRuntime', return_value=self.engine), redirect_stdout(stdout):
            rc = t.main(['--release', str(self.root), '--docker-host', t.DOCKER_HOST])
        self.assertEqual(rc, 0); self.assertTrue(json.loads(stdout.getvalue())['dry_run'])
        self.assertEqual(self.engine.writes, [])
        stdout = io.StringIO()
        with patch.object(t, 'TLSRuntime', side_effect=ValueError(PRIVATE)), redirect_stdout(stdout), redirect_stderr(stderr):
            rc = t.main(['--release', str(self.root), '--docker-host', t.DOCKER_HOST])
        self.assertEqual(rc, 1); self.assertNotIn(PRIVATE, stderr.getvalue()); self.assertEqual(stdout.getvalue(), '')

    def test_changed_sealed_source_fails_before_engine(self):
        (self.root / 'source/supabase/functions/fixture.js').write_text('// changed')
        with self.assertRaisesRegex(ValueError, '^Source file changed$'): self.plan()
        self.assertEqual(self.engine.calls, [])


class SANParser(unittest.TestCase):
    def test_only_direct_signed_san_dns_entries_supply_db_hostname(self):
        template = (b'Certificate:\n    Data:\n        Subject: CN=db\n        X509v3 extensions:\n'
                    b'            X509v3 Subject Alternative Name: critical\n                %s\n'
                    b'            X509v3 Extended Key Usage:\n                TLS Web Server Authentication\n'
                    b'    Signature Algorithm: sha256WithRSAEncryption\n')
        self.assertTrue(t._explicit_db_san(template % b'DNS:db'))
        self.assertTrue(t._explicit_db_san(template % b'DNS:elsewhere.example, DNS:db'))
        for value in (b'DNS:db.attacker', b'URI:https://example.test/, DNS:db', b'CN=db', b'IP Address:127.0.0.1'):
            with self.subTest(value=value):
                self.assertFalse(t._explicit_db_san(template % value))

    def test_cn_comment_nested_dns_text_and_duplicate_sections_are_not_san_proof(self):
        for text in (
            b'Certificate:\n    Data:\n        Subject: CN=DNS:db\n',
            b'Certificate:\n    Data:\n        X509v3 extensions:\n            Netscape Comment:\n                DNS:db\n',
            b'Certificate:\n    Data:\n        X509v3 extensions:\n            Other Extension:\n                X509v3 Subject Alternative Name:\n                    DNS:db\n',
            b'Certificate:\n    Data:\n        X509v3 extensions:\n            X509v3 Subject Alternative Name:\n                DNS:db\n            X509v3 Subject Alternative Name:\n                DNS:db\n'):
            with self.subTest(text=text):
                self.assertFalse(t._explicit_db_san(text))


@unittest.skipUnless(shutil.which('openssl'), 'OpenSSL unavailable')
class ActualOpenSSLCertificates(unittest.TestCase):
    """Isolated self-issued TEST material; no retained/production key is read."""
    @classmethod
    def setUpClass(cls):
        cls.area = tempfile.TemporaryDirectory(prefix='collect-tls-portability-test-')
        cls.addClassCleanup(cls.area.cleanup)
        cls.base = Path(cls.area.name).resolve()
        cls.ca = cls.base / 'test-ca'; cls.ca.mkdir(mode=0o700)
        cls.other = cls.base / 'other-test-ca'; cls.other.mkdir(mode=0o700)
        ca_config = cls.base / 'test-ca.cnf'
        ca_config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ca_ext\n[dn]\n[ca_ext]\n'
                             'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n')
        for authority in (cls.ca, cls.other):
            cls.command(['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '2',
                '-subj', '/CN=Collect isolated TEST CA', '-config', str(ca_config),
                '-keyout', str(authority / 'ca.key'), '-out', str(authority / 'ca.crt')])
        cls.command(['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-subj', '/CN=db',
            '-keyout', str(cls.base / 'test-server.key'), '-out', str(cls.base / 'test-server.csr')])
        for name, san in (('valid', 'DNS:db'), ('wrong-san', 'DNS:db.attacker'), ('cn-only', None)):
            extension = cls.base / (name + '.cnf')
            extension.write_text('[leaf]\nbasicConstraints=critical,CA:FALSE\n'
                'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n'
                'subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\n' +
                (('subjectAltName=' + san + '\n') if san else ''))
            cls.command(['x509', '-req', '-sha256', '-in', str(cls.base / 'test-server.csr'),
                '-CA', str(cls.ca / 'ca.crt'), '-CAkey', str(cls.ca / 'ca.key'), '-CAcreateserial',
                '-days', '2', '-extfile', str(extension), '-extensions', 'leaf', '-out', str(cls.base / (name + '.crt'))])

    @staticmethod
    def command(arguments):
        try:
            result = subprocess.run(['openssl', *arguments], capture_output=True, timeout=30)
            if result.returncode:
                raise ValueError()
        except Exception:
            raise RuntimeError('isolated_test_certificate_issuance_failed') from None

    def setUp(self):
        self.release = self.base / self.id().rsplit('.', 1)[-1]
        private = self.release / 'private'; private.mkdir(parents=True, mode=0o700)
        self.directory = private / 'db-tls'; self.directory.mkdir(mode=0o700)
        self.install('ca.crt', self.ca / 'ca.crt')
        self.install('server.crt', self.base / 'valid.crt')
        self.install('server.key', self.base / 'test-server.key')
        self.operator = SimpleNamespace(root=self.release)
        self.client_ca()

    def install(self, name, source):
        shutil.copyfile(source, self.directory / name)
        (self.directory / name).chmod(0o600)

    def client_ca(self):
        path = self.release / 'private/functions.env'
        path.write_text(dotenv({'COLLECT_DB_CA_PEM': (self.directory / 'ca.crt').read_text().strip()}))
        path.chmod(0o600)

    def test_actual_host_accepts_valid_ca_leaf_key_and_explicit_db_san(self):
        selected = t.Certificates(self.operator)
        self.assertEqual(set(selected.hashes), set(t.FILES))

    def test_actual_host_rejects_wrong_san_even_with_db_common_name(self):
        self.install('server.crt', self.base / 'wrong-san.crt')
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_explicit_db_san_required$'):
            t.Certificates(self.operator)

    def test_actual_host_rejects_cn_only_without_san(self):
        self.install('server.crt', self.base / 'cn-only.crt')
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_explicit_db_san_required$'):
            t.Certificates(self.operator)

    def test_actual_host_rejects_wrong_leaf_key(self):
        self.install('server.key', self.other / 'ca.key')
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_leaf_key_mismatch$'):
            t.Certificates(self.operator)

    def test_actual_host_rejects_wrong_ca_with_matching_leaf_key(self):
        self.install('ca.crt', self.other / 'ca.crt'); self.client_ca()
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_certificate_validation_failed$'):
            t.Certificates(self.operator)


class OpenSSLRejection(unittest.TestCase):
    @unittest.skipUnless(shutil.which('openssl'), 'OpenSSL unavailable')
    def test_actual_openssl_rejects_malformed_in_memory_key_with_fixed_error(self):
        with self.assertRaisesRegex(t.TLSError, '^retained_tls_certificate_validation_failed$'):
            t._openssl(['pkey', '-passin', 'pass:', '-pubout', '-outform', 'DER'], input=PRIVATE.encode())


if __name__ == '__main__':
    unittest.main()
