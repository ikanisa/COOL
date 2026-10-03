#!/usr/bin/env python3
"""Seal this owned packet without modifying any canonical or reused prerequisite."""
from pathlib import Path
import datetime
import difflib
import hashlib
import json
import stat
import subprocess

STAGE = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/collect-inactive-recovery-overlay-20261002')
ROOT = STAGE.parent.parent


def digest(path):
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or path.is_symlink():
        raise RuntimeError('non-regular input: ' + str(path))
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    after = path.stat()
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
        raise RuntimeError('input changed while hashing: ' + str(path))
    return {'bytes': after.st_size, 'sha256': h.hexdigest()}


def read(relative):
    return json.loads((STAGE / relative).read_text())


def write(relative, value):
    path = STAGE / relative
    if path.exists():
        raise RuntimeError('refuse overwrite: ' + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


if (STAGE / 'SEAL.json').exists():
    raise RuntimeError('already sealed; do not rewrite')

observed = datetime.datetime.now(datetime.timezone.utc).isoformat()
sql = read('proof/sql-attempt17/result.json')
units = read('proof/final-units4/result.json')
assert sql['status'] == units['status'] == 'passed'
assert len(sql['driver']['checks']) == 78 and all(c['passed'] for c in sql['driver']['checks'])
assert len(sql['checks']) == 2 and all(c['passed'] for c in sql['checks'])
assert units['unchanged'] and units['before'] == units['after']
assert all(c['exit_code'] == 0 for c in units['commands'])

vectors = []
for name in ['SOURCE_INPUTS.json', 'ADDITIONAL_INPUTS.json', 'CANONICAL208.json']:
    for entry in read(name)['files']:
        vectors.append((name, str((ROOT / entry['path']).resolve()), {'bytes': entry['bytes'], 'sha256': entry['sha256']}))
for path, value in sql['bindings'].items():
    vectors.append(('proof/sql-attempt17/result.json:bindings', path, value))
for path, value in units['before'].items():
    vectors.append(('proof/final-units4/result.json:before', path, value))
for relative, value in read('validation-current-origins.json')['originals'].items():
    vectors.append(('validation-current-origins.json:' + relative, value['source'], {'bytes': value['bytes'], 'sha256': value['sha256']}))

current = {}
associations = []
for origin, path, expected in vectors:
    validation_path = Path(path)
    preserved = {str(ROOT / p): Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/collect-inactive-restore-root-integration-20261002') / 'originals' / p for p in ['scripts/audits/collect_recovery_source.rb', 'scripts/tests/production_archive_restore.rb']}
    validation_path = preserved.get(path, validation_path)
    actual = current.setdefault(path, digest(validation_path))
    if actual != expected:
        raise RuntimeError('source/tool binding changed: ' + origin + ':' + path)
    associations.append({'origin': origin, 'original_path': path, 'validation_path': str(validation_path), 'role': 'preserved preintegration input' if path in preserved else 'unchanged bound input', **actual})
canonical = sorted(p.name for p in (ROOT / 'supabase/migrations').glob('*.sql'))
expected_canonical = sorted(Path(e['path']).name for e in read('CANONICAL208.json')['files'])
assert len(canonical) == 209 and set(canonical) == set(expected_canonical) | {'20261002090000_governed_receipt_retention_controls.sql'}
assert digest(ROOT / 'supabase/migrations/20261002090000_governed_receipt_retention_controls.sql')["sha256"] == 'f45ddd4e4f1ced3c9b030b2a13e39f1df9f46c09eda8d1e1c52a6e7c3b324f6d'
assert read('CURRENT_SCOPE_ADDITIONS.json')['binding'] == digest(ROOT / 'supabase/migrations/20261002090000_governed_receipt_retention_controls.sql')
write('ROOT_SEAL_EXECUTION.json', {'root_sealer': digest(Path(__file__).resolve()), 'source': str(Path(__file__).resolve()), 'scope': 'Resume rejected Docker-unavailable seal. Two canonical inputs now integrated; their preserved preintegration bytes are validated separately, with current canonical bytes matched to the seven promotion records.209 addition remains outside SQL78.'})

promotion = read('PROMOTION_MAP.json')['files']
for item in promotion:
    assert digest(STAGE / item['source']) == item['new']
    assert digest(ROOT / item['target']) == item['new']
    if item['expected_old'] != 'absent':
        assert digest(STAGE / item['original']) == item['expected_old']
        assert digest(Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/collect-inactive-restore-root-integration-20261002') / 'originals' / item['target']) == item['expected_old']

docker = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
cleanup = []
attempts = []
for number in range(1, 18):
    relative = 'proof/sql-attempt%d/result.json' % number
    result = read(relative)
    target = result['targets']['sql']['container_name']
    command = [docker, 'inspect', target]
    response = subprocess.run(command, capture_output=True, text=True, timeout=20)
    assert response.returncode == 1 and 'no such object' in response.stderr.lower() and response.stdout.strip() == '[]', 'owned target remains or absence unverified: ' + target
    cleanup.append({'attempt': number, 'target': target, 'argv': command, 'exit_code': response.returncode, 'stdout': response.stdout, 'stderr': response.stderr, 'absent': True, 'original_cleanup_claim': result['targets']['sql'].get('task_container_removed'), 'manual_receipt': 'proof/sql-attempt3/failed-entry-cleanup.json' if number == 3 else None})
    driver = result.get('driver', {})
    attempts.append({'attempt': number, 'result': relative, 'binding': digest(STAGE / relative), 'status': result['status'], 'driver_checks_passed': sum(c.get('passed') is True for c in driver.get('checks', [])), 'driver_checks_total': len(driver.get('checks', [])), 'outer_checks_passed': sum(c.get('passed') is True for c in result.get('checks', [])), 'frozen_input_scope': 'earlier input history, do not aggregate or relabel as final acceptance' if number != 17 else 'final accepted input', 'error': result.get('error')})
write('FINAL_CLEANUP.json', {'observed_at': observed, 'scope': 'read-only exact seventeen owned Docker target absence checks; no cleanup of unrelated targets', 'commands': cleanup, 'all_absent': True, 'active_handle': None})
write('ATTEMPT_INDEX.json', {'scope': 'all retained failures and preceding scoped passes; final acceptance is attempt17 only', 'attempts': attempts, 'unit_failures': [{'path': 'proof/final-units/FAILED.json', 'binding': digest(STAGE / 'proof/final-units/FAILED.json'), 'reason': 'minimal adapter lacked unchanged CLI dependencies; later final-units2 used exact current dependency tree'}, {'path': 'proof/final-units3/FAILED.json', 'binding': digest(STAGE / 'proof/final-units3/FAILED.json'), 'reason': 'all commands passed and bindings unchanged but final adapter summary comparison compared tuples to retained JSON arrays; corrected finite framing passed final-units4'}], 'unit_acceptance': {'path': 'proof/final-units4/result.json', 'binding': digest(STAGE / 'proof/final-units4/result.json')}, 'uncaptured_prelaunch_note': 'An initial directory-preparation error happened before a target was created; no raw terminal receipt was retained. It is not proof or a counted test.'})
write('FINAL_VALIDATION.json', {'format': 'collect-inactive-restore-final-bindings-v1', 'observed_at': observed, 'source_association_count': len(associations), 'distinct_bound_paths': len(current), 'associations': associations, 'all_bound_bytes_match': True, 'preserved_preintegration_inputs': 2, 'current_canonical_promotion_exact': True, 'canonical_migration_count': 208, 'canonical208_inventory': digest(STAGE / 'CANONICAL208.json'), 'selected205_archive': {'path': '.cache/receipt-worker-history-storage-20261002/sql-attempt12/commands/00405.stdout', 'binding': current[str(ROOT / '.cache/receipt-worker-history-storage-20261002/sql-attempt12/commands/00405.stdout')], 'scope': 'reused exact plain selected205 source corpus, no full208 archive replay'}, 'accepted_sql': {'path': 'proof/sql-attempt17/result.json', 'binding': digest(STAGE / 'proof/sql-attempt17/result.json'), 'driver_checks': 78, 'outer_checks': 2, 'scope': sql['scope']}, 'accepted_units': {'path': 'proof/final-units4/result.json', 'binding': digest(STAGE / 'proof/final-units4/result.json'), 'scopes': [{'cases': 13, 'assertions': 87, 'scope': 'new owner/result boundaries'}, {'cases': 6, 'assertions': 16, 'scope': 'exact caller branch using synthetic adapter'}, {'cases': 13, 'assertions': 59, 'scope': 'original source contract'}, {'cases': 7, 'assertions': 25, 'scope': 'original restore functions'}], 'ruby_syntax_checks': 11}})

members = []
for path in sorted(STAGE.rglob('*')):
    relative = str(path.relative_to(STAGE))
    if path.is_symlink():
        raise RuntimeError('symlink in packet: ' + relative)
    if path.is_file() and relative not in ['MANIFEST.json', 'SEAL.json']:
        members.append({'path': relative, **digest(path)})
write('MANIFEST.json', {'format': 'collect-inactive-restore-packet-manifest-v1', 'scope': 'owned regular files including all failed/accepted raw receipts; external sealed prerequisites remain thin exact SHA references', 'excluded': ['MANIFEST.json', 'SEAL.json'], 'member_count': len(members), 'total_bytes': sum(e['bytes'] for e in members), 'files': members})
write('SEAL.json', {'format': 'collect-inactive-restore-packet-seal-v1', 'sealed_at': observed, 'packet': str(STAGE), 'manifest': digest(STAGE / 'MANIFEST.json'), 'member_count': len(members), 'total_bytes': sum(e['bytes'] for e in members), 'proposal': digest(STAGE / 'PROPOSAL.md'), 'promotion_map': digest(STAGE / 'PROMOTION_MAP.json'), 'final_validation': digest(STAGE / 'FINAL_VALIDATION.json'), 'accepted_sql': digest(STAGE / 'proof/sql-attempt17/result.json'), 'accepted_units': digest(STAGE / 'proof/final-units4/result.json'), 'cleanup': digest(STAGE / 'FINAL_CLEANUP.json'), 'canonical_write': 'root seven-file promotion now complete; exact preserved inputs and canonical readback separately bound', 'hosted_or_live_action': False, 'all_owned_targets_absent': True, 'active_handle': None, 'required_next_boundary': 'root affected canonical caller43/210 passed separately; complete209/native/scheduler/archive recovery and external production acceptance remain open'})
print(json.dumps({'status': 'sealed', 'seal': digest(STAGE / 'SEAL.json'), 'manifest': digest(STAGE / 'MANIFEST.json'), 'member_count': len(members), 'total_bytes': sum(e['bytes'] for e in members), 'source_associations': len(associations), 'distinct_current_paths': len(current), 'promotable_files': len(promotion)}, indent=2))
