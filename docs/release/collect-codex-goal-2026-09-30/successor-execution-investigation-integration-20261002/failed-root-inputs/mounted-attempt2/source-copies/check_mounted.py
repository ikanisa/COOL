import hashlib
import json
import pathlib
import subprocess
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent / sys.argv[1]
OUT.mkdir(exist_ok=False)
FLUTTER = pathlib.Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter')
DART = FLUTTER.parent / 'cache/dart-sdk/bin/dart'
tests = ['test/admin_receipt_successor_execution_mount_test.dart',
         'test/admin_receipt_successor_view_test.dart']
def sha(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()
paths = set((ROOT / 'lib').rglob('*.dart'))
paths.update(ROOT / p for p in tests)
paths.update(ROOT / p for p in ['test/support/successor_fixture.dart',
    'test/support/execution_fixture.dart', 'test/support/execution_api_fixture.dart',
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
    '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
    'assets/typefaces/Inter-Variable.ttf'])
paths.update((ROOT / 'test/fixtures').glob('successor_*.json'))
paths.update([FLUTTER, DART, FLUTTER.parent / 'cache/flutter_tools.snapshot',
              DART.parent / 'snapshots/dartdev_aot.dart.snapshot', pathlib.Path(__file__).resolve()])
dependency = ROOT / '.cache/receipt-repeat-run-recovery-20261002/dependency-source-bindings.json'
for n, h in json.loads(dependency.read_text()).items():
    assert sha(pathlib.Path(n)) == h
    paths.add(pathlib.Path(n))
bindings = {str(p): sha(p) for p in sorted(paths)}
(OUT / 'inputs.json').write_text(json.dumps(bindings, indent=2) + '\n')
commands = []
result = {'status': 'failed', 'commands': commands,
    'scope': 'Actual canonical mounted caller and affected legacy review; real pinned SDK/Auth/HTTP with declared synthetic Auth/transport and adapted join fixtures; no hosted/full visual acceptance'}
try:
    for name, argv in [
        ('flutter-test', [str(FLUTTER), 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', *tests]),
        ('analysis', [str(DART), 'analyze', '--fatal-infos',
            'lib/admin/core/admin_receipt_successor_view.dart', *tests]),
        ('sole-authority', ['make', 'revolut-design-authority'])]:
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
    drift = [p for p, expected in bindings.items() if sha(pathlib.Path(p)) != expected]
    assert not drift, drift
    result.update(status='passed', analysis_files=3, bound_inputs=len(bindings), input_drift=drift)
finally:
    (OUT / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k:v for k,v in result.items() if k != 'commands'}))
