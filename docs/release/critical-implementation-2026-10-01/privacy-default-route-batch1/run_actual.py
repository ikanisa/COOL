#!/usr/bin/env python3
"""Execute only the actual default-provider regression, with source identities."""
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
FLUTTER = Path('/Volumes/PRO-G40/Development/Flutter/flutter')
TEST = 'test/features/privacy/privacy_default_route_integration_test.dart'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def identities():
    paths = sorted(ROOT.joinpath('lib').rglob('*.dart'))
    paths += [ROOT / TEST, ROOT / 'test/features/privacy/privacy_test_support.dart',
              ROOT / 'pubspec.yaml', ROOT / 'pubspec.lock',
              ROOT / '.dart_tool/package_config.json', Path(__file__).resolve()]
    tools = [FLUTTER / 'bin/flutter', FLUTTER / 'bin/cache/dart-sdk/bin/dart',
             FLUTTER / 'bin/cache/flutter_tools.snapshot',
             FLUTTER / 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
             FLUTTER / 'bin/cache/artifacts/engine/darwin-x64/flutter_tester',
             FLUTTER / 'packages/flutter/pubspec.yaml',
             FLUTTER / 'packages/flutter_test/pubspec.yaml']
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    selected = {'supabase_flutter', 'supabase', 'gotrue', 'postgrest', 'realtime_client',
                'riverpod', 'state_notifier', 'flutter_riverpod', 'go_router', 'http'}
    from urllib.parse import unquote, urlparse
    for package in config['packages']:
        if package['name'] in selected:
            uri = package['rootUri']
            location = Path(unquote(urlparse(uri).path)) if uri.startswith('file:') else (ROOT / '.dart_tool' / uri).resolve()
            paths += list(location.joinpath('lib').rglob('*.dart'))
            paths += [location / 'pubspec.yaml']
    paths += list(FLUTTER.joinpath('packages/flutter_test/lib').rglob('*.dart'))
    return {str(p): digest(p) for p in sorted(set(paths + tools))}

attempt = sys.argv[1]
destination = PACKET / attempt
destination.mkdir(exist_ok=False)
before = identities()
(destination / 'sources-before.json').write_text(json.dumps(before, indent=2) + '\n')
(destination / 'test-source.dart').write_bytes((ROOT / TEST).read_bytes())
command = [str(FLUTTER / 'bin/flutter'), 'test', '--no-pub', '--reporter', 'expanded', TEST]
start = datetime.now(timezone.utc).isoformat()
with (destination / 'actual-test.log').open('wb') as log:
    process = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
after = identities()
(destination / 'sources-after.json').write_text(json.dumps(after, indent=2) + '\n')
receipt = {'started_at': start, 'completed_at': datetime.now(timezone.utc).isoformat(),
           'command': command, 'exit_code': process.returncode,
           'source_count': len(before), 'source_before_after_equal': before == after,
           'changed_inputs': [p for p in sorted(set(before) | set(after)) if before.get(p) != after.get(p)],
           'actual_test_log_sha256': digest(destination / 'actual-test.log'),
           'test_source_sha256': digest(destination / 'test-source.dart'),
           'production_approval': False, 'hosted_native_acceptance': False}
(destination / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
print((destination / 'actual-test.log').read_text()[-2800:])
