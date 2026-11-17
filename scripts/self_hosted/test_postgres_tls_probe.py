"""Real isolated PostgreSQL SSLRequest/TLS tests with ephemeral TEST material.

No retained endpoint, key, database, provider or SQL is used. The server speaks
only SSLRequest plus TLS and records that no application payload is sent.
"""
from contextlib import contextmanager, redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import shutil
import socket
import ssl
import threading
import unittest
from unittest.mock import patch

from scripts.self_hosted import postgres_tls_probe as p
from scripts.self_hosted import test_retained_database_tls as certificate_fixture


@unittest.skipUnless(shutil.which('openssl'), 'OpenSSL unavailable for isolated TEST certificate issuance')
class RealPostgresTLSProbe(unittest.TestCase):
    command = staticmethod(certificate_fixture.ActualOpenSSLCertificates.command)
    setUpClass = classmethod(certificate_fixture.ActualOpenSSLCertificates.setUpClass.__func__)

    @contextmanager
    def server(self, *, certificate='valid', response=b'S'):
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(('127.0.0.1', 0)); listener.listen(1); listener.settimeout(3)
        port = listener.getsockname()[1]
        recorded = {'request': b'', 'application_payload': b''}
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(self.base / (certificate + '.crt'), self.base / 'test-server.key')
        context.set_servername_callback(lambda _socket, name, _context: recorded.update(server_name=name))
        def run():
            raw = None
            try:
                raw, _ = listener.accept(); raw.settimeout(3)
                while len(recorded['request']) < 8:
                    chunk = raw.recv(8 - len(recorded['request']))
                    if not chunk:
                        return
                    recorded['request'] += chunk
                raw.sendall(response)
                if response != b'S':
                    return
                with context.wrap_socket(raw, server_side=True) as secured:
                    raw = None
                    recorded['application_payload'] = secured.recv(1024)
            except (ssl.SSLError, OSError):
                recorded['tls_rejected'] = True
            finally:
                if raw is not None:
                    raw.close()
                listener.close()
        worker = threading.Thread(target=run, daemon=True); worker.start()
        try:
            yield port, recorded
        finally:
            worker.join(4)
            listener.close()
            self.assertFalse(worker.is_alive())

    def ca_pem(self, *, other=False):
        return ((self.other if other else self.ca) / 'ca.crt').read_text()

    def test_real_sslrequest_ca_hostname_sni_and_exact_leaf_pin_succeed_without_sql(self):
        expected = p.leaf_sha256((self.base / 'valid.crt').read_text())
        with self.server() as (port, observed):
            result = p.probe_postgres_tls(self.ca_pem(), expected_leaf_sha256=expected, _port=port)
        self.assertEqual(observed['request'], p.SSL_REQUEST)
        self.assertEqual(observed['server_name'], 'db')
        self.assertEqual(observed['application_payload'], b'')
        self.assertTrue(result['verified']); self.assertEqual(result['leaf_der_sha256'], expected)
        self.assertIn(result['tls_version'], ('TLSv1.2', 'TLSv1.3'))
        self.assertFalse(result['sql_sent']); self.assertFalse(result['password_sent'])

    def test_real_untrusted_ca_is_rejected(self):
        with self.server() as (port, _):
            with self.assertRaisesRegex(p.TLSProbeError, '^postgres_tls_certificate_unverified$'):
                p.probe_postgres_tls(self.ca_pem(other=True), _port=port)

    def test_real_wrong_hostname_and_cn_only_certificate_are_rejected(self):
        for certificate in ('wrong-san', 'cn-only'):
            with self.subTest(certificate=certificate), self.server(certificate=certificate) as (port, _):
                with self.assertRaisesRegex(p.TLSProbeError, '^postgres_tls_certificate_unverified$'):
                    p.probe_postgres_tls(self.ca_pem(), _port=port)

    def test_real_leaf_pin_mismatch_is_rejected_after_valid_handshake(self):
        with self.server() as (port, _):
            with self.assertRaisesRegex(p.TLSProbeError, '^postgres_tls_leaf_mismatch$'):
                p.probe_postgres_tls(self.ca_pem(), expected_leaf_sha256='0' * 64, _port=port)

    def test_postgres_refusing_ssl_never_falls_back_to_plaintext(self):
        with self.server(response=b'N') as (port, observed):
            with self.assertRaisesRegex(p.TLSProbeError, '^postgres_tls_not_supported$'):
                p.probe_postgres_tls(self.ca_pem(), _port=port)
        self.assertEqual(observed['request'], p.SSL_REQUEST)
        self.assertEqual(observed['application_payload'], b'')


class ProbeInput(unittest.TestCase):
    def test_invalid_ca_key_or_leaf_pin_fails_before_any_connection(self):
        for ca, pin in (('-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----', None),
                        ('bad-ca', None), (certificate_fixture.CA.decode(), 'not-a-digest')):
            with self.subTest(pin=pin), patch.object(p.socket, 'create_connection') as connect:
                with self.assertRaises(p.TLSProbeError):
                    p.probe_postgres_tls(ca, expected_leaf_sha256=pin)
                connect.assert_not_called()

    def test_cli_rejects_host_port_password_and_duplicate_inputs_without_connecting(self):
        for value in ('{"caPem":"x","host":"outside.example"}', '{"caPem":"x","port":5432}',
                      '{"caPem":"x","password":"private-test-marker"}', '{"caPem":"x","caPem":"y"}'):
            stdin = io.TextIOWrapper(io.BytesIO(value.encode()))
            output, error = io.StringIO(), io.StringIO()
            with patch.object(p.sys, 'stdin', stdin), patch.object(p, 'probe_postgres_tls') as probe, redirect_stdout(output), redirect_stderr(error):
                rc = p.main([])
                probe.assert_not_called()
            self.assertEqual(rc, 1); self.assertEqual(output.getvalue(), '')
            self.assertNotIn('private-test-marker', error.getvalue())
            self.assertFalse(json.loads(error.getvalue())['verified'])

    def test_cli_uses_fixed_default_endpoint_and_returns_only_verified_public_proof(self):
        stdin = io.TextIOWrapper(io.BytesIO(json.dumps({'caPem': 'synthetic-test-ca'}).encode()))
        output = io.StringIO()
        with patch.object(p.sys, 'stdin', stdin), patch.object(p, 'probe_postgres_tls', return_value={'verified': True}) as probe, redirect_stdout(output):
            rc = p.main([])
        self.assertEqual(rc, 0)
        probe.assert_called_once_with('synthetic-test-ca', expected_leaf_sha256=None)


if __name__ == '__main__':
    unittest.main()
