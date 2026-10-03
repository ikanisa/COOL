#!/usr/bin/env python3
"""Bounded affected Admin delta verification; never writes live application input."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
from urllib.parse import unquote, urlparse

sys.dont_write_bytecode = True
ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT = Path(__file__).resolve().parent
SOURCE = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1')
EXPORT = ROOT / '.cache/post-acceptance-admin-review-current1'
SDK = ROOT / '.cache/flutter-sdk-isolated-admin-browser-current1'
CONFIG = ROOT / '.cache/current-admin-browser-build-current2/.dart_tool/package_config.json'
sys.path.insert(0, str(ROOT / 'scripts/tests'))
import admin_read_gateway_gate as G

TESTS = ['test/' + n + '.dart' for n in [
    'admin_entity_audit_links_test', 'admin_entity_audit_page_test',
    'admin_exception_assignment_test', 'admin_exception_escalation_inbox_v2_models_test',
    'admin_exception_followup_sdk_test', 'admin_exception_followup_v2_models_test',
    'admin_exception_history_v2_models_test', 'admin_exception_history_v2_sdk_test',
    'admin_exception_workflow_sdk_test', 'admin_exception_workflow_test']]
RUNTIME = ['lib/admin/core/' + n + '.dart' for n in [
    'admin_entity_audit_link', 'admin_entity_audit_page', 'admin_exception_workflow_card',
    'admin_repository_base', 'admin_runtime', 'admin_exception_assignment_dialog',
    'admin_exception_escalation_inbox_v2_models', 'admin_exception_followup_v2_models',
    'admin_exception_history_runtime', 'admin_exception_history_v2_models']]

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def files(root):
    return {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}

def sdk_inputs():
    paths = set()
    for subtree in ['packages/flutter/lib', 'packages/flutter_test/lib', 'bin/cache/dart-sdk/lib']:
        paths.update(p for p in (SDK / subtree).rglob('*') if p.is_file())
    for name in ['bin/flutter', 'bin/internal/shared.sh', 'bin/cache/flutter.version.json',
                 'bin/cache/flutter_tools.snapshot', 'bin/cache/dart-sdk/bin/dart',
                 'bin/cache/dart-sdk/bin/dartvm', 'bin/cache/dart-sdk/bin/dartaotruntime',
                 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                 'bin/cache/artifacts/engine/darwin-x64/flutter_tester',
                 'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill']:
        p = SDK / name
        if p.is_file(): paths.add(p)
    return {str(p.relative_to(SDK)): sha(p) for p in sorted(paths)}

def package_inputs():
    result = {}
    for package in json.loads((EXPORT / '.dart_tool/package_config.json').read_text())['packages']:
        uri = urlparse(package['rootUri'])
        base = (Path(unquote(uri.path)) if uri.scheme == 'file' else EXPORT / '.dart_tool' / unquote(uri.path)).resolve(strict=True)
        paths = [base / 'pubspec.yaml', *(base / 'lib').rglob('*')]
        result[package['name']] = {'root': str(base), 'source': {
            str(p.relative_to(base)): sha(p) for p in sorted(paths) if p.is_file()}}
    return result

if sys.argv[1] == 'prepare':
    assert not EXPORT.exists()
    before = files(SOURCE)
    assert all(n in before for n in TESTS + RUNTIME)
    save('composite-before.json', before)
    # Copy declared files only: never follow unrelated MCP node_modules links.
    for name, digest in before.items():
        target = EXPORT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / name, target)
        assert sha(target) == digest
    assert files(EXPORT) == before and files(SOURCE) == before
    assert sha(EXPORT / 'pubspec.lock') == sha(CONFIG.parent.parent / 'pubspec.lock')
    config = json.loads(CONFIG.read_text())
    for p in config['packages']:
        if p['name'] == 'collect_app': p['rootUri'] = EXPORT.as_uri() + '/'
        elif p['name'] in ['file_saver', 'firebase_messaging', 'gotrue']:
            p['rootUri'] = (EXPORT / 'third_party' / p['name']).as_uri() + '/'
    (EXPORT / '.dart_tool').mkdir(exist_ok=True)
    (EXPORT / '.dart_tool/package_config.json').write_text(json.dumps(config, indent=2) + '\n')
    save('resolved-package-config.json', config)
    print('COPY SEALED', len(before), flush=True)
    raise SystemExit(0)

assert sys.argv[1] in ['verify', 'verify-inbox']
if sys.argv[1] == 'verify-inbox':
    TESTS = ['test/admin_exception_escalation_inbox_v2_models_test.dart']
    RUNTIME = []
before = json.loads((OUT / 'composite-before.json').read_text())
candidate = {n: sha(EXPORT / n) for n in before}
candidate.update(json.loads((OUT / 'sql-bridge-inputs.json').read_text())['inputs_sha256'])
changes = [n for n in before if before[n] != candidate[n]]
save('candidate-source.json', {'source': str(SOURCE), 'export': str(EXPORT),
    'inputs_sha256': candidate, 'private_derivative_changes': changes,
    'affected_runtime': RUNTIME, 'affected_tests': TESTS})
patch = ''.join(''.join(difflib.unified_diff((SOURCE / n).read_text().splitlines(True),
    (EXPORT / n).read_text().splitlines(True), fromfile='a/' + n, tofile='b/' + n)) for n in changes)
(OUT / 'candidate-derivative.patch').write_text(patch)
resource_files = ['lib/admin/core/admin_exception_workflow_card.dart',
                  'lib/admin/core/admin_exception_followup_v2_models.dart',
                  'test/admin_exception_assignment_test.dart']
(OUT / 'proposed-resource-admission.patch').write_text(''.join(''.join(difflib.unified_diff(
    (SOURCE / n).read_text().splitlines(True), (EXPORT / n).read_text().splitlines(True),
    fromfile='a/' + n, tofile='b/' + n)) for n in resource_files))
save('sdk-before.json', sdk_inputs())
save('package-inputs-before.json', package_inputs())
env = {k: v for k, v in os.environ.items() if k in
       {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', PATH=str(SDK / 'bin') + ':' + env['PATH'])
os.environ.clear(); os.environ.update(env)
commands = []
def run(name, argv, timeout=300):
    print('START', name, flush=True)
    value = {'name': name, **G.run_command(argv, EXPORT, OUT / (name + '.log'), timeout)}
    commands.append(value); save('execution.json', commands)
    print('END', name, value['exit_code'], flush=True)
    return value['exit_code'] == 0

dart = str(SDK / 'bin/cache/dart-sdk/bin/dart')
success = run('selected-format', [dart, 'format', '--output=none', '--set-exit-if-changed', *RUNTIME, *TESTS])
success &= run('selected-analysis', [dart, 'analyze', '--fatal-infos', *RUNTIME, *TESTS])
success &= run('affected-vm', [str(SDK / 'bin/flutter'), 'test', '--no-pub', '--concurrency=1',
    '--reporter=expanded', '--file-reporter=json:' + str(OUT / 'affected-vm.machine.jsonl'), *TESTS], 600)
summary = G.machine_summary(OUT / 'affected-vm.machine.jsonl')
sdk_after = sdk_inputs(); packages_after = package_inputs()
save('sdk-after.json', sdk_after); save('package-inputs-after.json', packages_after)
export_drift = [n for n, d in candidate.items() if not (EXPORT / n).is_file() or sha(EXPORT / n) != d]
source_drift = [n for n, d in before.items() if not (SOURCE / n).is_file() or sha(SOURCE / n) != d]
sdk_unchanged = sdk_after == json.loads((OUT / 'sdk-before.json').read_text())
packages_unchanged = packages_after == json.loads((OUT / 'package-inputs-before.json').read_text())
passing = success and not export_drift and not source_drift and sdk_unchanged and packages_unchanged and summary['runner_completed_successfully'] and not any(summary[n] for n in ['failed', 'errors', 'skipped', 'unfinished', 'event_errors'])
save('validation.json', {'status': 'pass' if passing else 'fail', 'commands': commands,
    'vm': summary, 'export_drift': export_drift, 'composite_drift': source_drift,
    'sdk_unchanged': sdk_unchanged, 'package_inputs_unchanged': packages_unchanged,
    'private_derivative_changes': changes, 'sql_executed': False, 'browser_builds': False,
    'native_builds': False, 'runtime_or_peer_test_writes': False,
    'scope': f'{len(TESTS)} affected Admin cohorts and selected fatal analysis/format on frozen composite with explicit private resource-admission patch. No whole-current/live or SQL acceptance claim.'})
print('RESULT', 'pass' if passing else 'fail', summary, flush=True)
raise SystemExit(0 if passing else 1)
