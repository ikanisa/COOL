import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
NAME = sys.argv[1]
P = ROOT / 'docs/release/asset-build-hygiene-2026-09-30' / NAME
EXPORT = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930') / ('export-' + NAME)
SDK = ROOT / '.cache/flutter-sdk-isolated-asset-attempt28'
FLUTTER = str(SDK / 'bin/flutter')
ENV = {key: value for key, value in os.environ.items()
       if key in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
ENV.update({'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
            'PUB_CACHE': str(ROOT / '.cache/pub-cache-hygiene-20260930'),
            'PATH': str(SDK / 'bin') + ':' + ENV['PATH']})
P.mkdir(exist_ok=False)
(P / 'runner-source.py').write_bytes(Path(__file__).read_bytes())
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
commands = []

def run(name, argv, cwd=EXPORT):
    print('START', name, flush=True)
    started = time.monotonic()
    with (P / (name + '.stdout')).open('wb') as out, (P / (name + '.stderr')).open('wb') as err:
        result = subprocess.run(argv, cwd=cwd, env=ENV, stdout=out, stderr=err, timeout=600)
    commands.append({'name': name, 'command': argv, 'exit_code': result.returncode,
                     'elapsed_seconds': round(time.monotonic() - started, 2),
                     'stdout_sha256': sha(P / (name + '.stdout')),
                     'stderr_sha256': sha(P / (name + '.stderr'))})
    (P / 'execution.json').write_text(json.dumps({'status': 'running', 'commands': commands}, indent=2) + '\n')
    print('END', name, result.returncode, flush=True)
    return result.returncode

assert run('source-export', ['python3', str(ROOT / 'scripts/qa/native_source_export.py'),
                             '--destination', str(EXPORT), '--report', str(P / 'source-export.json')], ROOT) == 0
source = json.loads((P / 'source-export.json').read_text())['source_sha256']
assert run('export-git-init', ['git', 'init', '-q']) == 0
assert run('pub-enforce-offline', [FLUTTER, 'pub', 'get', '--offline', '--enforce-lockfile']) == 0
tests = ['test/gateway/gateway_enrollment_lifecycle_test.dart', 'test/gateway/gateway_safety_test.dart']
code = run('widgets', [FLUTTER, 'test', '--no-pub', '--reporter', 'expanded', *tests])
analysis = run('fatal-analysis', [FLUTTER, 'analyze', '--no-pub', '--fatal-infos', '--fatal-warnings',
                                 'lib/gateway', 'lib/main_gateway.dart', *tests])
changes = {name: {'before': value, 'after': sha(EXPORT / name) if (EXPORT / name).is_file() else None}
           for name, value in source.items() if not (EXPORT / name).is_file() or sha(EXPORT / name) != value}
drift = {name: {'before': value, 'after': sha(ROOT / name) if (ROOT / name).is_file() else None}
         for name, value in source.items() if not (ROOT / name).is_file() or sha(ROOT / name) != value}
(P / 'validation.json').write_text(json.dumps({
    'status': 'pass' if code == analysis == 0 and not changes else 'fail',
    'commands': commands, 'source_inputs': len(source), 'source_export_sha256': sha(P / 'source-export.json'),
    'export_source_changes': changes, 'checkout_drift': drift,
    'tested_gateway_frontend_sha256': source['lib/gateway/gateway_app.dart'],
    'scope': 'Actual production Gateway enrollment route/dialog/widget transitions with existing synthetic platform fixture; exact copied source, no SQL, Android dispatch, provider or complete application/native acceptance',
}, indent=2, sort_keys=True) + '\n')
print('DONE', code, analysis, flush=True)
