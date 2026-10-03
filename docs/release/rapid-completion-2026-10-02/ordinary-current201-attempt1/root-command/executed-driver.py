from pathlib import Path
import datetime, hashlib, json, os, subprocess, sys

root = Path.cwd()
report = root / 'docs/release/rapid-completion-2026-10-02/ordinary-current201-attempt1'
driver = root / '.cache/current201-rehearsal-command-20261002'
assert not report.exists() and not driver.exists()
driver.mkdir(parents=True)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
paths = sorted((root / 'supabase/migrations').glob('*.sql'))
assert len(paths) == 201
paths += [root / 'scripts/tests/current_ordinary_installer_rehearsal.py', root / 'scripts/tests/collect_current_release_upgrade_uat.py', root / 'scripts/sql/receipt_transport_platform_prerequisites.sql']
bindings = {str(p.relative_to(root)): sha(p) for p in paths}
tools = {str(p): sha(p) for p in [Path('/usr/bin/python3'), Path('/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker')]}
command = ['/usr/bin/python3', 'scripts/tests/current_ordinary_installer_rehearsal.py', '--output', str(report)]
environment = os.environ.copy()
environment['PYTHONDONTWRITEBYTECODE'] = '1'
environment['PYTHONUTF8'] = '1'
evidence = {'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'command': command, 'cwd': str(root), 'canonical_migration_count': 201, 'source_bindings': bindings, 'tools': tools, 'exit_code': None, 'scope': 'Every captured current201 migration on separate clean and synthetic populated local targets; shipping application DDL NOSUPERUSER after explicit platform-owner setup; no live service, provider or device calls. Current candidate proof, not final goal acceptance.'}
(driver / 'execution.json').write_text(json.dumps(evidence, indent=2) + '\n')
(driver / 'executed-driver.py').write_bytes(Path(__file__).read_bytes())
with (driver / 'stdout.log').open('w') as stdout, (driver / 'stderr.log').open('w') as stderr:
    completed = subprocess.run(command, cwd=root, env=environment, stdout=stdout, stderr=stderr, timeout=1800)
evidence.update(exit_code=completed.returncode, completed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), inputs_unchanged=all(sha(root / rel) == h for rel, h in bindings.items()), tools_unchanged=all(sha(Path(p)) == h for p, h in tools.items()), migration_set_unchanged={str(p.relative_to(root)) for p in (root / 'supabase/migrations').glob('*.sql')} == {k for k in bindings if k.startswith('supabase/migrations/')})
(driver / 'execution.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps({k: v for k, v in evidence.items() if k not in ['source_bindings', 'tools']}))
print((driver / 'stdout.log').read_text()[-6000:])
print((driver / 'stderr.log').read_text()[-5000:])
sys.exit(completed.returncode)
