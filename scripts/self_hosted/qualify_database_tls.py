"""Qualify the pinned PostgreSQL driver against a new task-owned TLS cluster.

Run with python -m scripts.self_hosted.qualify_database_tls. This helper accepts
only loopback port 55448 and a fresh private directory. It never discovers,
restarts, alters or stops another PostgreSQL cluster. No Docker/provider
acceptance is implied. Raw logs, credentials and test keys stay private.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.self_hosted.prepare import tls_keys

PORT = 55448
SOURCES = (
    'scripts/self_hosted/qualify_database_tls.py',
    'scripts/supabase/testing/self-hosted-database-tls.ts',
    'scripts/self_hosted/prepare.py',
    'supabase/functions/_shared/postgres.js',
    'supabase/functions/_shared/deployment-database.js',
    'supabase/functions/deno.lock',
)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fresh_file(path, content, mode=0o600):
    with path.open('xb') as stream:
        os.chmod(path, mode)
        stream.write(content)

def qualify(args):
    stage = 'preflight'
    base = args.private_directory.absolute()
    receipt = args.receipt.absolute()
    if base.exists() or base.parent.resolve(strict=True) != base.parent:
        raise ValueError('Fresh physical private directory required')
    if receipt.exists() or receipt.parent.resolve(strict=True) != receipt.parent:
        raise ValueError('Fresh physical receipt path required')
    binaries = args.pg_bin.resolve(strict=True)
    deno = args.deno.resolve(strict=True)
    cache = args.deno_cache.resolve(strict=True)
    for name in ('postgres', 'initdb', 'pg_ctl'):
        if not (binaries / name).is_file():
            raise ValueError('Exact native PostgreSQL toolchain required')
    # Check that this fixed qualification port is unused. Failure never leads
    # to stopping or modifying the process already using it.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(('127.0.0.1', PORT))
    source_pins = {name: digest(ROOT / name) for name in SOURCES}
    driver = cache / 'npm/registry.npmjs.org/postgres/3.4.7'
    package = json.loads((driver / 'package.json').read_text())
    if package.get('version') != '3.4.7':
        raise ValueError('Pinned postgres.js 3.4.7 cache required')
    driver_pins = {str(p.relative_to(driver)): digest(p)
                   for p in sorted((driver / 'src').glob('*.js'))}
    driver_pins['package.json'] = digest(driver / 'package.json')
    uid, gid = (65534, 65534) if os.getuid() == 0 else (os.getuid(), os.getgid())
    runner = ['setpriv', '--reuid=' + str(uid), '--regid=' + str(gid), '--clear-groups'] if os.getuid() == 0 else []
    os.umask(0o077)
    base.mkdir(mode=0o700)
    if os.getuid() == 0:
        os.chown(base, uid, gid)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    if os.getuid() == 0:
        os.chown(runtime, uid, gid)
    data, started = base / 'data', False
    result = None

    def run(command, *, private_name, env=None, timeout=30):
        completed = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=timeout)
        fresh_file(base / private_name, completed.stdout + b'\n' + completed.stderr)
        if completed.returncode:
            raise RuntimeError('Native qualification command failed; inspect private log')
        return completed.stdout

    try:
        stage = 'certificate_generation'
        tls_keys(base / 'db-tls')
        wrong = base / 'wrong-authority'
        wrong.mkdir(mode=0o700)
        tls_keys(wrong / 'db-tls')
        # Only the generated leaf and public CA go to the PostgreSQL process.
        # The helper moved the CA signing key into a separate mode0700 folder.
        if os.getuid() == 0:
            for name in ('db-tls', 'db-tls/server.key', 'db-tls/server.crt', 'db-tls/ca.crt'):
                os.chown(base / name, uid, gid)
        if (base / 'db-tls/ca.key').exists() or (base / 'db-ca').stat().st_mode & 0o077:
            raise ValueError('CA private custody failed')
        password = secrets.token_hex(32)
        password_file = base / 'bootstrap-password'
        fresh_file(password_file, (password + '\n').encode())
        if os.getuid() == 0:
            os.chown(password_file, uid, gid)
        stage = 'initialize_new_cluster'
        run(runner + [str(binaries / 'initdb'), '-D', str(data), '-U', 'collect_tls_bootstrap',
             '--encoding=UTF8', '--locale=C', '--auth-host=scram-sha-256',
             '--auth-local=scram-sha-256', '--pwfile=' + str(password_file)], private_name='initdb.private.log')
        password_file.unlink()
        configuration = (
            "\nlisten_addresses='127.0.0.1'\nport=55448\n"
            "unix_socket_directories='" + str(runtime).replace("'", "''") + "'\n"
            "timezone='UTC'\nlog_timezone='UTC'\nssl=on\nssl_min_protocol_version='TLSv1.2'\n"
            "ssl_cert_file='" + str(base / 'db-tls/server.crt').replace("'", "''") + "'\n"
            "ssl_key_file='" + str(base / 'db-tls/server.key').replace("'", "''") + "'\n"
            "password_encryption='scram-sha-256'\nlog_statement='none'\n"
            "log_min_error_statement='panic'\n"
        )
        with (data / 'postgresql.conf').open('a') as stream:
            stream.write(configuration)
        (data / 'pg_hba.conf').write_text(
            'local all all scram-sha-256\n'
            'hostnossl all all 127.0.0.1/32 reject\n'
            'hostssl all all 127.0.0.1/32 scram-sha-256\n'
        )
        stage = 'start_new_cluster'
        run(runner + [str(binaries / 'pg_ctl'), '-D', str(data), '-l', str(runtime / 'server.private.log'),
             '-w', '-t', '20', 'start'], private_name='start.private.log')
        started = True
        # No URL or secret reaches argv or a public result.
        fixture = base / 'fixture.private.json'
        fresh_file(fixture, json.dumps({
            'contract': 'collect.selfhost.tls.fixture.v1', 'synthetic': True,
            'bootstrap_url': 'postgres://collect_tls_bootstrap:' + password + '@127.0.0.1:55448/postgres',
            'restricted_password': secrets.token_hex(32),
            'ca_file': str(base / 'db-tls/ca.crt'),
            'wrong_ca_file': str(wrong / 'db-tls/ca.crt'),
        }).encode())
        stage = 'postgres_driver_qualification'
        env = {key: os.environ[key] for key in ('PATH', 'LD_LIBRARY_PATH') if key in os.environ}
        env.update({'DENO_DIR': str(cache), 'COLLECT_CI_SYNTHETIC': 'true', 'COLLECT_TLS_FIXTURE_FILE': str(fixture)})
        completed = subprocess.run([str(deno), 'run', '--frozen', '--cached-only',
            '--config', 'supabase/functions/deno.json', '--allow-read=' + str(base) + ',' + str(ROOT) + ',' + str(cache),
            '--allow-env', '--allow-net=127.0.0.1:55448',
            'scripts/supabase/testing/self-hosted-database-tls.ts'],
            cwd=ROOT, env=env, capture_output=True, timeout=90)
        fresh_file(base / 'driver.private.log', completed.stdout + b'\n' + completed.stderr)
        result = json.loads(completed.stdout)
        if completed.returncode or result.get('passed') is not True:
            raise RuntimeError('Driver qualification refused; private diagnostic retained')
        stage = 'source_readback'
        if source_pins != {name: digest(ROOT / name) for name in SOURCES} or driver_pins != {
                **{str(p.relative_to(driver)): digest(p) for p in sorted((driver / 'src').glob('*.js'))},
                'package.json': digest(driver / 'package.json')}:
            raise ValueError('Qualification source changed during execution')
        result.update({'checked_at': datetime.now(timezone.utc).isoformat(),
            'source_sha256': source_pins, 'driver_sha256': driver_pins,
            'certificate_sha256': {'ca': digest(base / 'db-tls/ca.crt'),
                'server': digest(base / 'db-tls/server.crt'), 'wrong_ca': digest(wrong / 'db-tls/ca.crt')},
            'private_keys_disclosed': False, 'private_logs_retained': True,
            'other_clusters_modified': False})
    except Exception as error:
        result = {'contract': 'collect.selfhost.postgres-tls.native.v1', 'passed': False,
            'stage': stage, 'error_class': type(error).__name__, 'private_logs_retained': True,
            'production_acceptance': False, 'other_clusters_modified': False,
            'source_sha256': source_pins, 'driver_sha256': driver_pins,
            **({'driver_result': result} if result is not None else {})}
    finally:
        # pg_ctl is scoped to the exact new data directory created above.
        # It never uses the port to find, signal or stop another server.
        if started:
            try:
                run(runner + [str(binaries / 'pg_ctl'), '-D', str(data), '-w', '-t', '20', '-m', 'fast', 'stop'],
                    private_name='stop.private.log')
                if result is not None:
                    result['owned_cluster_stopped'] = True
            except Exception:
                if result is not None:
                    result.update({'passed': False, 'owned_cluster_stopped': False, 'cleanup_unconfirmed': True})
    fresh_file(receipt, (json.dumps(result, indent=2) + '\n').encode(), 0o644)
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True)
    parser.add_argument('--deno', type=Path, required=True)
    parser.add_argument('--deno-cache', type=Path, required=True)
    parser.add_argument('--private-directory', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = qualify(args)
        print(json.dumps({'passed': result['passed'], 'scenarios': len(result.get('scenarios', [])),
            'owned_loopback_port': PORT, 'owned_cluster_stopped': result.get('owned_cluster_stopped'),
            'production_acceptance': False, 'private_values_disclosed': False}, sort_keys=True))
        sys.exit(0 if result['passed'] else 1)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({'passed': False, 'error_class': type(error).__name__, 'private_values_disclosed': False}), file=sys.stderr)
        sys.exit(1)
