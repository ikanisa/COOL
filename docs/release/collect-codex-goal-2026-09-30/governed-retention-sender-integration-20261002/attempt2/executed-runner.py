import hashlib
import json
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import unquote, urlparse

ROOT = pathlib.Path(__file__).resolve().parents[2]
STAGE = pathlib.Path(__file__).resolve().parent
OUT = STAGE / sys.argv[1]
OUT.mkdir(exist_ok=False)
FLUTTER = pathlib.Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter')
DART = FLUTTER.parent / 'cache/dart-sdk/bin/dart'
SOURCES = ['lib/admin/core/admin_sender_picker.dart', 'lib/admin/core/admin_sender_retention_models.dart', 'lib/admin/core/admin_sender_retention_sdk.dart', 'lib/admin/core/admin_sender_retention_controller.dart', 'lib/admin/core/admin_sender_retention_host.dart', 'lib/admin/core/admin_sender_retention_view.dart', 'lib/admin/core/admin_sender_retention_checkpoint.dart', 'lib/admin/core/admin_sender_retention_checkpoint_stub.dart', 'lib/admin/core/admin_sender_retention_checkpoint_web.dart', 'lib/admin/core/admin_runtime.dart', 'lib/admin/core/admin_governed_settings_page.dart', 'lib/admin/core/admin_receipt_operations_card.dart', 'test/admin_sender_retention_models_test.dart', 'test/admin_sender_retention_controller_test.dart', 'test/admin_sender_retention_view_test.dart', 'test/admin_sender_retention_mount_test.dart', 'test/admin_governed_settings_widget_test.dart', 'test/admin_receipt_operations_card_test.dart']
TESTS = ['test/admin_sender_retention_mount_test.dart'] if len(sys.argv)>2 and sys.argv[2]=='mount-only' else SOURCES[-6:]
CONFIG = ROOT / '.dart_tool/package_config.json'
packages = {}
for item in json.loads(CONFIG.read_text())['packages']:
    uri = urlparse(item['rootUri'])
    base = pathlib.Path(unquote(uri.path)) if uri.scheme == 'file' else CONFIG.parent / unquote(item['rootUri'])
    packages[item['name']] = (base / item.get('packageUri', 'lib/')).resolve()

paths = {ROOT / name for name in SOURCES}
pending = list(paths)
visited = set()
while pending:
    path = pending.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    source = re.sub(r'/\*[\s\S]*?\*/|//[^\n]*', '', path.read_text())
    for directive in re.findall(r'^\s*(?:import|export|part)\s+(?!of\b)([^;]+);', source, re.MULTILINE):
        for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive):
            if uri.startswith('dart:'):
                continue
            if uri.startswith('package:'):
                package, relative = uri[8:].split('/', 1)
                target = packages[package] / relative
            else:
                target = path.parent / uri
            target = target.resolve()
            assert target.is_file(), str(target)
            pending.append(target)
paths = visited
paths.update(ROOT / name for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
    '.dart_tool/package_config.json', '.dart_tool/package_graph.json', 'assets/typefaces/Inter-Variable.ttf', 'test/fixtures/admin_receipt_operations_v2/observed-policy-default.json', 'Makefile', 'scripts/qa/revolut_design_authority.py'])
paths.update([FLUTTER, DART, FLUTTER.parent / 'cache/flutter_tools.snapshot',
    DART.parent / 'snapshots/dartdev_aot.dart.snapshot', pathlib.Path(__file__).resolve()])

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

bindings = {str(path): sha(path) for path in sorted(paths)}
(OUT / 'inputs.json').write_text(json.dumps(bindings, indent=2) + '\n')
for name in SOURCES:
    target = OUT / 'sources' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes((ROOT / name).read_bytes())
(OUT / 'executed-runner.py').write_bytes(pathlib.Path(__file__).read_bytes())
result = {'status': 'failed', 'commands': [], 'scope': 'Canonical Settings and receipt operations mounts, retained producer DTOs with explicitly synthetic Auth/HTTP and adapted sender fixture; no hosted service, real sender, reader speech, comparator parity or release artifact acceptance'}
try:
    for name, argv in [
        ('flutter-test', [str(FLUTTER), 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', *TESTS]),
        ('analysis', [str(DART), 'analyze', '--fatal-infos', *SOURCES]),
        ('design-authority', ['make', 'revolut-design-authority']),
    ]:
        started = datetime.now(timezone.utc).isoformat()
        completed = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=300)
        for channel in ['stdout', 'stderr']:
            (OUT / (name + '.' + channel)).write_bytes(getattr(completed, channel))
        result['commands'].append({'name': name, 'argv': argv, 'started_at': started,
            'finished_at': datetime.now(timezone.utc).isoformat(), 'exit_code': completed.returncode,
            'stdout_sha256': hashlib.sha256(completed.stdout).hexdigest(),
            'stderr_sha256': hashlib.sha256(completed.stderr).hexdigest()})
        assert completed.returncode == 0, name
    drift = [name for name, digest in bindings.items() if sha(pathlib.Path(name)) != digest]
    assert not drift, drift
    result.update(status='passed', captured_inputs=len(bindings), input_drift=drift)
finally:
    (OUT / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({name: value for name, value in result.items() if name != 'commands'}))
