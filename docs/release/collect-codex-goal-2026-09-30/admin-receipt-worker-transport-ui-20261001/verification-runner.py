import hashlib
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse

root = pathlib.Path.cwd()
attempt = sys.argv[1]
expected = int(sys.argv[2])
out = root / '.cache/admin-receipt-worker-transport-ui-20261001' / attempt
out.mkdir()
sdk = pathlib.Path('/Volumes/PRO-G40/Development/Flutter/flutter')
config = root / '.dart_tool/package_config.json'
packages = {}
for item in json.loads(config.read_text())['packages']:
    uri = item['rootUri']
    base = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path)) if uri.startswith('file:') else config.parent / urllib.parse.unquote(uri)
    packages[item['name']] = (base / item.get('packageUri', 'lib/')).resolve()
tests = ['test/admin_receipt_worker_transport_test.dart', 'test/admin_receipt_worker_health_test.dart', 'test/admin_automations_test.dart', 'test/admin_receipt_deferral_test.dart']
queue = [root / p for p in tests]
paths = set()
while queue:
    source = queue.pop().resolve()
    if source in paths:
        continue
    assert source.is_file(), source
    paths.add(source)
    for directive in re.findall(r'(?m)^\s*(?:import|export|part)\s+(?!of\b)[^;]+;', source.read_text()):
        for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive):
            if uri.startswith('dart:'):
                continue
            if uri.startswith('package:'):
                package, rel = uri[8:].split('/', 1)
                queue.append(packages[package] / rel)
            else:
                queue.append(source.parent / uri)
prior = root / '.cache/admin-receipt-worker-health-20261001/attempt4/inputs-before.json'
paths.update(pathlib.Path(p) for p in json.loads(prior.read_text()))
paths.add(pathlib.Path(__file__).resolve())
paths.update(root / p for p in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.dart_tool/package_config.json'])
fixtures = root / 'docs/release/collect-codex-goal-2026-09-30/receipt-worker-transport-health-20261001/accepted-sql-attempt5'
paths.update(fixtures.glob('observed-detail-*.json'))
paths.update([fixtures / 'inputs/20261001160000_receipt_worker_transport_health.sql', fixtures / 'result.json'])
paths.update(sdk / p for p in ['bin/flutter', 'bin/dart', 'bin/cache/dart-sdk/bin/dart', 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot', 'bin/cache/dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot', 'bin/cache/flutter_tools.snapshot', 'bin/cache/flutter.version.json', 'bin/cache/engine.stamp', 'bin/cache/artifacts/engine/darwin-x64/flutter_tester', 'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill'])
paths = {p.resolve() for p in paths if p.is_file()}

def snapshot():
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

before = snapshot()
(out / 'inputs-before.json').write_text(json.dumps(before, indent=2))
commands = [
    [str(sdk / 'bin/dart'), 'analyze', 'lib/admin/core/admin_receipt_worker_transport_card.dart', 'lib/admin/core/admin_receipt_worker_transport_models.dart', 'lib/admin/core/admin_receipt_worker_card.dart', 'test/admin_receipt_worker_transport_test.dart'],
    [str(sdk / 'bin/flutter'), 'test', '--no-pub', *tests, '--reporter', 'json'],
]
results = []
for index, command in enumerate(commands):
    start = time.monotonic()
    with (out / ('analysis.log' if index == 0 else 'flutter.jsonl')).open('w') as stream:
        try:
            run = subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=150)
            code = run.returncode
        except subprocess.TimeoutExpired:
            code = 'timeout'
    results.append({'command': command, 'returncode': code, 'duration_seconds': round(time.monotonic() - start, 2)})
after = snapshot()
(out / 'inputs-after.json').write_text(json.dumps(after, indent=2))
events = []
for line in (out / 'flutter.jsonl').read_text().splitlines():
    try:
        events.append(json.loads(line))
    except json.JSONDecodeError:
        pass
hidden = {e['testID'] for e in events if e.get('type') == 'testDone' and e.get('hidden', False)}
visible = {e['test']['id'] for e in events if e.get('type') == 'testStart'} - hidden
complete = {e['testID'] for e in events if e.get('type') == 'testDone' and e.get('result') == 'success' and not e.get('skipped', False) and not e.get('hidden', False)}
terminal = [e for e in events if e.get('type') == 'done']
changed = [p for p in before if before[p] != after.get(p)]
accepted = all(r['returncode'] == 0 for r in results) and len(visible) == expected and visible.issubset(complete) and bool(terminal) and terminal[-1].get('success') is True and not changed
report = {'scope': 'current Admin worker transport SDK/dialog, worker health, Automations and receipt deferral integration', 'commands': results, 'accepted': accepted, 'expected_cases': expected, 'visible_cases': len(visible), 'completed_visible_cases': len(visible & complete), 'terminal': terminal[-1] if terminal else None, 'inputs': len(before), 'changed_inputs': changed, 'hosted_verified': False, 'physical_device_verified': False, 'visual_comparator_accepted': False, 'full_candidate_regression': False, 'optional_visual_capture_environment_disabled': True}
(out / 'verification.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report))
sys.exit(0 if accepted else 1)
