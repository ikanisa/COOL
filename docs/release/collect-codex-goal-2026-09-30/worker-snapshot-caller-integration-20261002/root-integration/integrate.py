import hashlib
import json
import pathlib
import re
import shutil
import subprocess
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
PACKET = ROOT / '.cache/receipt-worker-snapshot-capture-20261002'

def sha(path):
    with pathlib.Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def read(name):
    return json.loads((PACKET / name).read_text())

assert not (OUT / 'canonical-source-association.json').exists()
assert sha(PACKET / 'SEAL.json') == '2cc06138e510f731cd8b228d35ccbf2f1c8e6a68bb897d8e4e564205048f0d1f'
seal = read('SEAL.json')
for key in ['files_manifest', 'handoff', 'promotion_map', 'accepted_sql', 'accepted_units', 'syntax']:
    assert sha(PACKET / seal[key]['path']) == seal[key]['sha256'], key
members = read('FILES.json')['files']
for row in members:
    path = pathlib.Path(row['path'])
    assert not path.is_absolute() and '..' not in path.parts
    path = PACKET / path
    assert not path.is_symlink() and path.is_file()
    assert path.stat().st_size == row['bytes'] and sha(path) == row['sha256']
assert len(members) == 3536
sql = read('proof/sql-attempt6/result.json')
assert sql['status'] == 'passed' and len(sql['checks']) == 38 and all(c['passed'] for c in sql['checks'])
assert sql['driver']['status'] == 'passed'
assert sql['driver']['full_data_comparison'] == {'tables': 272, 'rows': 6266, 'sequences': 4, 'other_data': 0, 'all_match': True}
for path, row in sql['bindings'].items():
    path = pathlib.Path(path)
    assert path.stat().st_size == row['bytes'] and sha(path) == row['sha256']
readback = read('proof/final-closure/accepted-source-tool-dependency-readback.json')
for row in readback['rows']:
    path = pathlib.Path(row['path'])
    assert path.stat().st_size == row['bytes'] and sha(path) == row['sha256']
docker = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
absent = []
for result in sorted((PACKET / 'proof').glob('sql-attempt*/result.json')):
    for target in json.loads(result.read_text())['targets'].values():
        name = target['container_name']
        p = subprocess.run([docker, 'inspect', name], capture_output=True, text=True, timeout=15)
        assert p.returncode == 1 and 'no such object:' in p.stderr.lower(), name
        absent.append({'name': name, 'exit_code': p.returncode, 'stderr': p.stderr.strip()})
assert len(absent) == 12
mapping = read('PROMOTION_MAP.json')
for change in mapping['changes']:
    source = PACKET / change['source']
    target = ROOT / change['target']
    assert sha(source) == change['new_sha256']
    if change['old_sha256'] is None:
        assert not target.exists()
    else:
        assert sha(target) == change['old_sha256']
        backup = OUT / 'originals' / change['target']
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, backup)
    assert sha(PACKET / change['patch']) == change['patch_sha256']
(OUT / 'review.json').write_text(json.dumps({'status': 'source_and_packet_review_accepted',
    'helper_lines_read': 491, 'caller_delta_read': True, 'new_unit_source_read': True,
    'members_verified': 3536, 'selected205_bindings': len(sql['bindings']),
    'source_tool_readback': len(readback['rows']), 'targets_absent': absent,
    'actual_SQL_checks': 38, 'observed_blocking_source_defect': None,
    'limits': 'selected205 snapshot/full archive proof; canonical207 chronology, production role/Vault, native/scheduler, durable business overlay and RPO/RTO acceptance separate'}, indent=2) + '\n')
for change in mapping['changes']:
    source = PACKET / change['source']
    target = ROOT / change['target']
    if change['old_sha256'] is None:
        assert not target.exists()
    else:
        assert sha(target) == change['old_sha256']
    target.parent.mkdir(parents=True, exist_ok=True)
    mode = target.stat().st_mode & 0o777 if target.exists() else source.stat().st_mode & 0o777
    shutil.copyfile(source, target)
    target.chmod(mode)
    assert sha(target) == change['new_sha256']
commands = []
total_cases = total_assertions = 0
for i, name in enumerate(['collect_worker_snapshot_test.rb', 'collect_recovery_source_test.rb',
                          'collect_encrypted_database_backup_test.rb', 'production_archive_restore_test.rb']):
    argv = ['/usr/bin/ruby', 'scripts/tests/' + name, '--seed', '1042']
    p = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=45)
    (OUT / (str(i) + '.stdout')).write_bytes(p.stdout)
    (OUT / (str(i) + '.stderr')).write_bytes(p.stderr)
    commands.append({'argv': argv, 'exit_code': p.returncode,
                     'stdout_sha256': hashlib.sha256(p.stdout).hexdigest(),
                     'stderr_sha256': hashlib.sha256(p.stderr).hexdigest()})
    assert p.returncode == 0, name
    match = re.search(r'(\d+) runs, (\d+) assertions, 0 failures, 0 errors', p.stdout.decode())
    assert match, name
    total_cases += int(match[1]); total_assertions += int(match[2])
assert total_cases == 33 and total_assertions == 155
assert all(sha(ROOT / c['target']) == c['new_sha256'] for c in mapping['changes'])
result = {'status': 'six_exact_canonical_changes_integrated_and_current_units_passed',
          'canonical_sha256': {c['target']: c['new_sha256'] for c in mapping['changes']},
          'modified_originals_preserved': 4, 'unit_cases': total_cases,
          'unit_assertions': total_assertions, 'commands': commands,
          'SQL_checks_reused': 38, 'selected_SQL_cohort': 205,
          'canonical_migration_observation': 207, 'full_current_recovery': False,
          'durable_business_inactive_overlay': False, 'hosted': False,
          'timestamp': datetime.now(timezone.utc).isoformat()}
(OUT / 'canonical-source-association.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k not in ['canonical_sha256', 'commands']}, indent=2))
