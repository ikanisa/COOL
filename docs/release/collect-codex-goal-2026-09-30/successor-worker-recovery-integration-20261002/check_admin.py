import hashlib
import json
import pathlib
import re
import subprocess
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent / 'admin-current-attempt1'
OUT.mkdir(exist_ok=False)
FLUTTER = pathlib.Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter')
DART = FLUTTER.parent / 'cache/dart-sdk/bin/dart'
tests = ['test/admin_receipt_operational_history_test.dart',
         'test/admin_receipt_operational_history_recovery_test.dart',
         'test/admin_worker_cold_consumer_test.dart']

def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

paths = set((ROOT / 'lib').rglob('*.dart'))
paths.update(ROOT / p for p in tests)
for p in ['pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
          '.dart_tool/package_graph.json', 'test/support/admin_read_fixture.dart']:
    paths.add(ROOT / p)
for p in ['test/fixtures/admin_receipt_operational_recovery_actual',
          'test/fixtures/receipt-worker-cold',
          'test/fixtures/admin_receipt_operational_history_actual',
          'test/fixtures/admin_automatic_gateway_observed',
          'test/fixtures/admin_transaction_lifecycle_actual']:
    paths.update(x for x in (ROOT / p).rglob('*') if x.is_file())
paths.update([FLUTTER, DART, FLUTTER.parent / 'cache/flutter_tools.snapshot',
              DART.parent / 'snapshots/dartdev_aot.dart.snapshot', pathlib.Path(__file__).resolve()])
dependency = ROOT / '.cache/receipt-repeat-run-recovery-20261002/dependency-source-bindings.json'
dependencies = json.loads(dependency.read_text())
for name, expected in dependencies.items():
    assert sha(pathlib.Path(name)) == expected
    paths.add(pathlib.Path(name))
bindings = {str(p): sha(p) for p in sorted(paths)}
(OUT / 'inputs.json').write_text(json.dumps(bindings, indent=2) + '\n')
commands = []
result = {'status': 'failed', 'commands': commands, 'scope': 'Affected canonical Admin model/SDK/provider/view consumer closure; synthetic Auth/HTTP and local producer fixtures; no complete UI or hosted acceptance'}
try:
    for name, argv in [
        ('flutter-test', [str(FLUTTER), 'test', '--no-pub', '--reporter', 'expanded', *tests]),
        ('analysis', [str(DART), 'analyze', '--fatal-infos',
            'lib/admin/core/admin_receipt_operational_history_models.dart',
            'lib/admin/core/admin_receipt_operational_history_sdk.dart',
            'lib/admin/core/admin_receipt_operational_history_view.dart',
            'test/admin_receipt_operational_history_recovery_test.dart',
            'test/admin_worker_cold_consumer_test.dart'])]:
        start = datetime.now(timezone.utc).isoformat()
        completed = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=180)
        for stream in ['stdout', 'stderr']:
            (OUT / (name + '.' + stream)).write_bytes(getattr(completed, stream))
        commands.append({'name': name, 'argv': argv, 'started_at': start,
                         'finished_at': datetime.now(timezone.utc).isoformat(),
                         'exit_code': completed.returncode,
                         'stdout_sha256': hashlib.sha256(completed.stdout).hexdigest(),
                         'stderr_sha256': hashlib.sha256(completed.stderr).hexdigest()})
        assert completed.returncode == 0, name
    output = (OUT / 'flutter-test.stdout').read_text()
    match = re.search(r'\+(\d+): All tests passed!', output)
    assert match and int(match.group(1)) == 51
    drift = [p for p, expected in bindings.items() if sha(pathlib.Path(p)) != expected]
    assert not drift, drift
    result.update(status='passed', checks=51, analysis_files=5,
                  bound_inputs=len(bindings), input_drift=drift)
finally:
    (OUT / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k != 'commands'}, indent=2))
