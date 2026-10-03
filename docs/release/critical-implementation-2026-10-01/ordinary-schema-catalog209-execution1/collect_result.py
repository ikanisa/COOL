from pathlib import Path
import datetime
import hashlib
import json
import shutil
import stat
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = HERE.parent
PREP = BASE / 'ordinary-schema-catalog209-preparation1'
OUTPUT = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-SCHEMA/20261002-candidate209-1/docs/release/ordinary-effective-catalog1')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2) + '\n' if isinstance(value, (dict, list)) else value)


def inventory(folder):
    rows = {}
    for path in sorted(folder.rglob('*')):
        info = path.lstat()
        if stat.S_ISDIR(info.st_mode):
            continue
        assert stat.S_ISREG(info.st_mode) and not path.is_symlink() and info.st_nlink == 1
        rows[str(path.relative_to(folder))] = sha(path)
    return rows


def seal(folder):
    rows = [dict(path=str((folder / name).relative_to(ROOT)), bytes=(folder / name).stat().st_size, sha256=digest)
            for name, digest in inventory(folder).items()]
    save(folder / 'packet-files.json', dict(status='sealed', files=rows))
    save(folder / 'SHA256SUMS', ''.join(row['sha256'] + '  ' + row['path'] + '\n' for row in rows)
         + sha(folder / 'packet-files.json') + '  ' + str((folder / 'packet-files.json').relative_to(ROOT)) + '\n')
    assert all(sha(ROOT / row['path']) == row['sha256'] for row in rows)
    return dict(path=str((folder / 'packet-files.json').relative_to(ROOT)), sha256=sha(folder / 'packet-files.json'), files=len(rows))


result = json.loads((HERE / 'execution-result.json').read_text())
assert result['status'] == 'pass' and result['exit_code'] == 0 and result['case_count'] == 37
assert result['source_before'] == result['source_after'] and len(result['source_after']) == 216
assert not result['current_source_drift'] and not result['current_added_migrations']
proof = json.loads((OUTPUT / 'result.json').read_text())
assert proof['status'] == 'pass' and len(proof['source_inventory']) == 209 and len(proof['cases']) == 37
assert all(case['status'] == 'pass' for case in proof['cases']) and proof['all_task_containers_removed']
assert not any(proof[key] for key in ['hosted_called', 'provider_called', 'shared_database_written', 'source_rows_copied', 'signed_jwt_tested', 'managed_hosted_owner_parity'])
versions = [item['version'] for item in proof['source_inventory']]
assert len(set(versions)) == 209
catalogs = []
for phase, details in proof['phases'].items():
    assert len(details['migrations']) == 209 and details['status'] == 'pass' and details['task_container_removed']
    assert all(item['status'] == 'pass' and item['actual_installer_authority']['superuser'] is False
               and item['actual_installer_authority']['current_user'] == item['actual_installer_authority']['current_role'] == 'postgres'
               for item in details['migrations'])
    if phase == 'populated':
        assert all(item.get('canonical_predecessor_preserved') is True for item in details['migrations'][124:])
    assert details['scheduler_readback'] == dict(cron='off', net='0', history=0)
    for boundary, record in details['effective_catalogs'].items():
        path = OUTPUT / record['path']
        catalog = json.loads(path.read_text())
        expected_versions = versions[:124] if boundary == 'predecessor' else versions
        assert sha(path) == record['sha256'] and catalog['migrations'] == expected_versions and catalog['server']['major'] == 17
        assert hashlib.sha256(json.dumps(catalog, sort_keys=True, separators=(',', ':')).encode()).hexdigest() == record['canonical_sha256']
        assert record['query_sha256'] == sha(OUTPUT / 'collect_recovery_source_catalog.sql')
        catalogs.append(dict(phase=phase, boundary=boundary, **record))
assert proof['phases']['clean']['effective_catalogs']['final']['sha256'] == proof['phases']['populated']['effective_catalogs']['final']['sha256']
assert proof['populated_predecessor_fingerprints'] == proof['populated_after_upgrade_fingerprints']
assert len(proof['populated_after_upgrade_fingerprints']) == 18
before = inventory(OUTPUT)
destination = HERE / 'observed-output'
assert not destination.exists()
shutil.copytree(OUTPUT, destination)
assert before == inventory(destination) == inventory(OUTPUT)
assert all(sha(ROOT / name) == digest for name, digest in result['source_after'].items())
assert set(str(path.relative_to(ROOT)) for path in (ROOT / 'supabase/migrations').glob('*.sql')) == set(name for name in result['source_after'] if name.startswith('supabase/migrations/'))
checks = []
env = dict(PATH='/usr/bin:/bin', DOCKER_HOST=(HERE / 'local-docker-socket.stdout').read_text().strip())
assert env['DOCKER_HOST'].startswith('unix://')
for target in result['owned_cleanup']:
    name = target['name']
    response = subprocess.run(['/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker', 'container', 'inspect', name], env=env, capture_output=True, text=True, timeout=15)
    assert response.returncode == 1 and ('no such container: ' + name in response.stderr.lower() or 'no such object: ' + name in response.stderr.lower())
    checks.append(dict(name=name, absent=True, stderr=response.stderr))
validator = ROOT / 'scripts/migrations/validate_supabase_migrations.sh'
response = subprocess.run(['bash', str(validator)], cwd=ROOT, capture_output=True, text=True, timeout=10)
assert response.returncode == 0
save(HERE / 'current209-validator.stdout', response.stdout)
save(HERE / 'current209-validator.stderr', response.stderr)
save(HERE / 'owner-collector-attempt1-refusal.json', dict(status='collector_syntax_refusal_before_execution', reason='Missing whitespace in conditional expression in first inline collector; Python parsed no statements and made no file changes.', actual_rehearsal_status='pass', rehearsal_rerun=False))
save(HERE / 'owner-readback.json', dict(status='pass', at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), actual_cases=37,
    migrations=209, source_inputs=216, copied_files=len(before), all_209_migrations_actual_NOSUPERUSER=True,
    authority_note='Local postgres retains CREATE ROLE/CREATE DB/BYPASSRLS and trusted memberships. Explicit platform preparation precedes application migration1. Hosted authority parity unproved.',
    catalogs=catalogs, preserved_projections=18, source_drift={}, fresh_owned_container_absence=checks,
    current209_validator=dict(exit_code=0, source_sha256=sha(validator)), full_BE08_closed=False, production_ready=False,
    remaining=['Domain/caller/owner mapping', 'Broader historical data and effective ACL preservation coverage', 'Committed predecessor backup/recovery and roll-forward', 'Hosted managed authority/runtime/provider acceptance']))
save(HERE / 'README.md', '# Current 209-migration ordinary-installer rehearsal\n\nAll 37 actual checks passed in 149.722 seconds against one frozen 216-input private candidate. All 209 application migrations ran as postgres NOSUPERUSER after explicit isolated platform preparation. The 124-version synthetic predecessor retained 18 financial, receipt, Auth and approval projections through all 85 pending migrations. Full final clean and populated schema catalogs match byte-for-byte and canonically. Scheduler dispatch stayed disabled; both owned containers were removed. The current 209-version shipping validator also passed.\n\nThe prior 208-version proof remains immutable and dated. This packet includes the new retention-control migration without changing its bytes. Local installer CREATE ROLE/CREATE DB/BYPASSRLS and trusted memberships remain explicit; managed hosted parity is unproved. Domain/caller mapping, broader historical data/ACL preservation, committed recovery and roll-forward, and hosted/provider acceptance remain open. Full BE-08 and production acceptance are not closed.\n')
save(PREP / 'README.md', '# Current 209-migration candidate preparation\n\n216 regular single-link inputs were copied byte-for-byte to a new physical internal-volume candidate. All 215 prior inputs are unchanged; the sole addition is the governed receipt-retention migration. Source identities and hashes before/after copying are recorded. The exact reviewed controller changes only its preparation-folder reference; existing 600-second deadline, image binding, original assertions and owned cleanup remain. No maintained source or application SQL was changed by this preparation. The separate execution packet records the actual result.\n')
print(json.dumps(dict(execution=seal(HERE), preparation=seal(PREP), final_catalog_sha256=proof['phases']['clean']['effective_catalogs']['final']['sha256'], final_counts=proof['phases']['clean']['effective_catalogs']['final']['counts'])))
