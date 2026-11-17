"""Read-only PostgreSQL TLS proof on the retained private published port.

The CLI accepts public CA PEM and an optional leaf-DER SHA256 on stdin, never a
password, host or port. It sends only PostgreSQL's eight-byte SSLRequest and
performs verified TLS; it sends no StartupMessage, authentication or SQL.
Importing this module performs no I/O.
"""
from __future__ import annotations
import hashlib
import json
import re
import socket
import ssl
import struct
import sys

HOST, PORT, SERVER_NAME = '127.0.0.1', 55102, 'db'
SSL_REQUEST = struct.pack('!II', 8, 80877103)
FORMAT = 'collect.retained-postgres-tls.proof.v1'


class TLSProbeError(RuntimeError):
    """Fixed codes only; peer/crypto diagnostics never escape."""


def leaf_sha256(pem):
    try:
        return hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()
    except Exception:
        raise TLSProbeError('postgres_tls_leaf_input_invalid') from None


def probe_postgres_tls(ca_pem, *, expected_leaf_sha256=None, _port=PORT):
    """The private port override is for isolated host tests, never CLI input."""
    if (not isinstance(ca_pem, str) or len(ca_pem) > 32768 or re.fullmatch(
            r'-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\r?\n?', ca_pem) is None):
        raise TLSProbeError('postgres_tls_ca_input_invalid')
    if expected_leaf_sha256 is not None and (not isinstance(expected_leaf_sha256, str)
            or re.fullmatch(r'[a-f0-9]{64}', expected_leaf_sha256) is None):
        raise TLSProbeError('postgres_tls_leaf_input_invalid')
    if type(_port) is not int or not 0 < _port < 65536:
        raise TLSProbeError('postgres_tls_endpoint_invalid')
    raw = None
    try:
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cadata=ca_pem)
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        # Retained certificates require an explicit db SAN. Never fall back to
        # a Common Name when the TLS library exposes this stricter setting.
        context.hostname_checks_common_name = False
        raw = socket.create_connection((HOST, _port), timeout=5)
        raw.sendall(SSL_REQUEST)
        if raw.recv(1) != b'S':
            raise TLSProbeError('postgres_tls_not_supported')
        with context.wrap_socket(raw, server_hostname=SERVER_NAME) as secured:
            # wrap_socket owns the underlying descriptor after this handoff.
            raw = None
            version, peer = secured.version(), secured.getpeercert(binary_form=True)
            if version not in ('TLSv1.2', 'TLSv1.3') or not peer:
                raise TLSProbeError('postgres_tls_protocol_unverified')
            fingerprint = hashlib.sha256(peer).hexdigest()
            if expected_leaf_sha256 is not None and fingerprint != expected_leaf_sha256:
                raise TLSProbeError('postgres_tls_leaf_mismatch')
            return {'format': FORMAT, 'verified': True, 'endpoint': f'{HOST}:{_port}',
                    'servername': SERVER_NAME, 'tls_version': version, 'leaf_der_sha256': fingerprint,
                    'ca_der_sha256': leaf_sha256(ca_pem), 'sql_sent': False, 'password_sent': False}
    except TLSProbeError:
        raise
    except (TimeoutError, socket.timeout):
        raise TLSProbeError('postgres_tls_timeout') from None
    except ssl.SSLCertVerificationError:
        raise TLSProbeError('postgres_tls_certificate_unverified') from None
    except Exception:
        raise TLSProbeError('postgres_tls_connection_unverified') from None
    finally:
        if raw is not None:
            raw.close()


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        if argv:
            raise TLSProbeError('postgres_tls_no_arguments_allowed')
        raw = sys.stdin.buffer.read(65537)
        if len(raw) > 65536:
            raise TLSProbeError('postgres_tls_input_invalid')
        def unique(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise TLSProbeError('postgres_tls_input_invalid')
                result[key] = value
            return result
        value = json.loads(raw, object_pairs_hook=unique)
        if not isinstance(value, dict) or set(value) not in ({'caPem'}, {'caPem', 'expectedLeafSha256'}):
            raise TLSProbeError('postgres_tls_input_invalid')
        proof = probe_postgres_tls(value['caPem'], expected_leaf_sha256=value.get('expectedLeafSha256'))
        print(json.dumps(proof, sort_keys=True))
        return 0
    except Exception as error:
        code = str(error) if isinstance(error, TLSProbeError) else 'postgres_tls_input_invalid'
        print(json.dumps({'verified': False, 'code': code}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
