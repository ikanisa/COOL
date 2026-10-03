"""Apply the five reviewed consumer files after exact packet and source checks."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
BASE = HERE.parent
ROOT = HERE.parents[3]


def sha(path):
    assert path.is_file() and not path.is_symlink(), path
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    with path.open('x') as output:
        json.dump(value, output, indent=2)
        output.write('\n')


def packet(name, digest, count):
    directory = BASE / name
    path = directory / 'batch.json'
    assert sha(path) == digest
    entries = json.loads(path.read_text())['artifacts']
    assert len(entries) == count
    for relative, row in entries.items():
        leaf = directory / relative
        assert leaf.resolve().is_relative_to(directory.resolve())
        assert sha(leaf) == row['sha256'] and leaf.stat().st_size == row['bytes']
    return entries


packet('successor-gateway-consumer-preparation1', '252b1e0310597fc36dc25ed7f41416ad47412ac66d68d6e64778bbad019957fd', 814)
packet('successor-gateway-consumer-current-readback1', 'b13fa4e2885ca8a7ea40b2f973bae8f468fa7bb40e6bdd4ee164302297a9015f', 15)
prepared = BASE / 'successor-gateway-consumer-preparation1'
rows = json.loads((prepared / 'verification.json').read_text())['changed_files']
assert len(rows) == 5
identities = {}
for name, row in rows.items():
    path = ROOT / name
    assert sha(path) == row['before']['sha256']
    candidate = prepared / 'candidate/source' / name
    assert sha(candidate) == row['candidate']['sha256']
    identities[name] = path.stat()
    for label, source in [('before', path), ('after', candidate)]:
        target = HERE / label / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as output:
            output.write(source.read_bytes())
        assert sha(target) == sha(source)
for name, row in rows.items():
    assert (ROOT / name).stat() == identities[name] and sha(ROOT / name) == row['before']['sha256']
for name, row in rows.items():
    path = ROOT / name
    path.write_bytes((prepared / 'candidate/source' / name).read_bytes())
    os.chmod(path, row['before']['mode'])
    assert sha(path) == row['candidate']['sha256']
save(HERE / 'promotion.json', {
    'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'review': 'Root reviewed the complete 358-line patch; all original cases remain with inventory-count adaptation and new rejection cases.',
    'exact_five_applied': rows,
    'private_delivery_tests_reused': 34,
    'private_delivery_scope': 'Exact unchanged reviewed sources with synthetic transport under OS network denial.',
    'HTTP_loader_or_SQL_or_handler_changed': False,
    'hosted_or_provider_operations': False,
})
checks = {}
for name, command, deadline in [
    ('inventory-tests', ['/usr/bin/ruby', 'scripts/tests/edge_function_inventory_test.rb'], 180),
    ('auth-check', ['/usr/bin/ruby', 'scripts/edge_function_inventory.rb', 'auth-check'], 20),
    ('shell-syntax', ['/bin/bash', '-n', 'scripts/supabase_production_readiness.sh'], 20),
]:
    started = time.monotonic()
    command = ['/usr/bin/sandbox-exec', '-p', '(version 1) (allow default) (deny network*)'] + command
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=deadline)
    for label, body in [('stdout', result.stdout), ('stderr', result.stderr)]:
        (HERE / (name + '.' + label)).write_bytes(body)
    checks[name] = {'command': command, 'deadline_seconds': deadline, 'elapsed_seconds': time.monotonic() - started, 'exit_code': result.returncode}
for name, row in rows.items():
    assert sha(ROOT / name) == row['candidate']['sha256']
save(HERE / 'applied-verification.json', {'checks': checks, 'source_unchanged_after_checks': True, 'status': 'pass' if all(row['exit_code'] == 0 for row in checks.values()) else 'fail', 'real_handler_or_SQL_tests_executed': False, 'production_ready': False})
files = [{'path': str(path.relative_to(ROOT)), 'bytes': path.stat().st_size, 'sha256': sha(path)} for path in sorted(HERE.rglob('*')) if path.is_file()]
save(HERE / 'packet-files.json', {'files': files, 'scope': 'Exact five applied successor inventory/readiness consumers and actual current bounded checks; no full handler/SQL/HTTP or hosted acceptance.'})
print(json.dumps({'applied_files': 5, 'checks': checks, 'packet_sha256': sha(HERE / 'packet-files.json')}))
