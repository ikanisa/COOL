from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import time

p = Path('.cache') / ('admin-policy-read-attempt' + sys.argv[1])
p.mkdir(parents=True, exist_ok=False)
previous = json.loads(Path('.cache/admin-policy-read-attempt1/source-before.json').read_text())
files = [Path(name) for name in sorted(previous)]
def binding():
    return {str(x): {'sha256': hashlib.sha256(x.read_bytes()).hexdigest(),
                    'bytes': x.stat().st_size} for x in files}
before = binding()
(p / 'source-before.json').write_text(json.dumps(before, indent=2) + '\n')
(p / 'executed-runner.py').write_bytes(Path(__file__).read_bytes())
for f in files:
    destination = p / 'sources' / f
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(f.read_bytes())
steps = [('analysis', [
    '/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart', 'analyze',
    'lib/admin/core/admin_operating_policy_models.dart', 'lib/admin/core/admin_operating_policy_runtime.dart',
    'lib/admin/core/admin_operating_policy_card.dart', 'lib/admin/core/admin_automations_page.dart',
    'test/admin_operating_policy_models_test.dart', 'test/admin_operating_policy_runtime_test.dart',
    'test/support/admin_operating_policy_fixture.dart'], 120),
    ('flutter', ['/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter', 'test', '--no-pub',
                 '--concurrency=1', '--reporter=expanded', 'test/admin_operating_policy_models_test.dart',
                 'test/admin_operating_policy_runtime_test.dart'], 180)]
results = []
for name, command, deadline in steps:
    started = time.time()
    env = os.environ.copy()
    env['COLLECT_POLICY_CAPTURE_DIR'] = str((p / 'captures').resolve())
    try:
        r = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=deadline, env=env)
    except subprocess.TimeoutExpired as error:
        output = error.stdout.decode() if isinstance(error.stdout, bytes) else (error.stdout or '')
        (p / (name + '.log')).write_text(output)
        result = {'command': command, 'exit_code': 124, 'elapsed_seconds': time.time() - started,
                  'completion_marker': False}
    else:
        (p / (name + '.log')).write_text(r.stdout)
        result = {'command': command, 'exit_code': r.returncode, 'elapsed_seconds': time.time() - started,
                  'completion_marker': name != 'flutter' or 'All tests passed!' in r.stdout}
    after = binding()
    (p / ('source-after-' + name + '.json')).write_text(json.dumps(after, indent=2) + '\n')
    result['bound_inputs'] = len(files)
    result['source_unchanged'] = before == after
    (p / (name + '-result.json')).write_text(json.dumps(result, indent=2) + '\n')
    results.append(result)
    print(json.dumps({'stage': name, **result}), flush=True)
    print((p / (name + '.log')).read_text()[-5000:], flush=True)
    if result['exit_code'] or not result['completion_marker'] or before != after:
        break
(p / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
raise SystemExit(0 if len(results) == 2 and all(
    x['exit_code'] == 0 and x['completion_marker'] and x['source_unchanged'] for x in results) else 1)
