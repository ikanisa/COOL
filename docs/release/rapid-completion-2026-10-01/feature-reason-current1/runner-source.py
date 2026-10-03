#!/usr/bin/env python3
"""Affected production feature-reason UI and shared default regressions only."""
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
sys.path.insert(0, str(ROOT / 'scripts/tests'))
import final_flutter_acceptance as F
import admin_read_gateway_gate as G

OUT = ROOT / 'docs/release/rapid-completion-2026-10-01/feature-reason-current1'
EXPORT = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-essential-feature-reason-current1')
SDK = ROOT / '.cache/flutter-sdk-isolated-gateway-motion-root192'
CHANGED = ['lib/admin/shared/components/admin_confirm_dialog.dart',
           'lib/admin/core/admin_list_runtime.dart',
           'test/admin_custom_action_ui_test.dart']
DEFAULT_TESTS = ['test/admin_reason_dialog_bounds_test.dart',
                 'test/admin_reason_dialog_focus_test.dart']
TESTS = [CHANGED[-1], *DEFAULT_TESTS]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def sdk_inputs():
    paths = set()
    for subtree in ['packages/flutter/lib', 'packages/flutter_test/lib',
                    'bin/cache/dart-sdk/lib']:
        paths.update(p for p in (SDK / subtree).rglob('*') if p.is_file())
    for name in ['bin/flutter', 'bin/internal/shared.sh',
                 'bin/cache/flutter.version.json', 'bin/cache/flutter_tools.snapshot',
                 'bin/cache/dart-sdk/bin/dart', 'bin/cache/dart-sdk/bin/dartvm',
                 'bin/cache/dart-sdk/bin/dartaotruntime',
                 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                 'bin/cache/artifacts/engine/darwin-x64/flutter_tester',
                 'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill']:
        p = SDK / name
        if p.is_file():
            paths.add(p)
    return {str(p.relative_to(SDK)): sha(p) for p in sorted(paths)}


def package_inputs():
    config = json.loads((EXPORT / '.dart_tool/package_config.json').read_text())
    from urllib.parse import urlparse, unquote
    result = {}
    for package in config['packages']:
        uri = urlparse(package['rootUri'])
        base = (Path(unquote(uri.path)) if uri.scheme == 'file'
                else EXPORT / '.dart_tool' / unquote(uri.path)).resolve(strict=True)
        paths = [base / 'pubspec.yaml', *(base / 'lib').rglob('*.dart')]
        result[package['name']] = {'root': str(base), 'source': {
            str(p.relative_to(base)): sha(p) for p in sorted(paths) if p.is_file()}}
    return result


assert not EXPORT.exists() and not (OUT / 'source-before.json').exists()
before = F.declared_files()
save(OUT / 'source-before.json', before)
sdk_before = sdk_inputs()
save(OUT / 'sdk-before.json', sdk_before)
for name, digest in before.items():
    target = EXPORT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / name, target)
    assert sha(target) == digest and sha(ROOT / name) == digest, name
# The consumed Flutter application scope must also be stable after the full copy.
guard = {name: digest for name, digest in before.items()
         if name.startswith(('lib/', 'third_party/', 'assets/'))
         or name in TESTS or name in ['pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml']}
assert all(sha(ROOT / name) == digest for name, digest in guard.items())
save(OUT / 'source-export.json', {'export': str(EXPORT), 'inputs_sha256': before,
                                'consumed_source_guard': guard})
print('COPY SEALED', len(before), 'inputs', flush=True)
env = {k: v for k, v in os.environ.items() if k in
       {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true',
           PUB_CACHE=str(ROOT / '.cache/pub-cache-hygiene-20260930'),
           PATH=str(SDK / 'bin') + ':' + env['PATH'])
commands = []


def run(name, argv, timeout=300):
    print('START', name, flush=True)
    prior = dict(os.environ)
    try:
        os.environ.clear()
        os.environ.update(env)
        result = G.run_command(argv, EXPORT, OUT / (name + '.log'), timeout)
    finally:
        os.environ.clear()
        os.environ.update(prior)
    commands.append({'name': name, **result})
    save(OUT / 'execution.json', {'commands': commands})
    print('END', name, result['exit_code'], flush=True)
    return result['exit_code'] == 0


success = run('toolchain', [str(SDK / 'bin/flutter'), '--version', '--machine'], 30)
version = json.loads((OUT / 'toolchain.log').read_text())
assert version['frameworkVersion'] == '3.44.4' and version['dartSdkVersion'] == '3.12.2'
assert version['frameworkRevision'] == 'ad70ec4617166f1c38e5d2bfd388af71fda14f06'
success &= run('pub', [str(SDK / 'bin/flutter'), 'pub', 'get', '--offline', '--enforce-lockfile'], 90)
assert sha(EXPORT / 'pubspec.lock') == before['pubspec.lock']
packages_before = package_inputs()
save(OUT / 'package-inputs-before.json', packages_before)
package_config = EXPORT / '.dart_tool/package_config.json'
save(OUT / 'resolved-package-config.json', json.loads(package_config.read_text()))
dart = str(SDK / 'bin/cache/dart-sdk/bin/dart')
success &= run('selected-format', [dart, 'format', '--output=none', '--set-exit-if-changed',
                                 *CHANGED, *DEFAULT_TESTS])
success &= run('selected-analysis', [dart, 'analyze', '--fatal-infos',
                                   *CHANGED, *DEFAULT_TESTS])
success &= run('feature-flag-ui', [str(SDK / 'bin/flutter'), 'test', '--no-pub',
    '--concurrency=1', '--reporter=expanded',
    '--file-reporter=json:' + str(OUT / 'feature-flag.machine.jsonl'),
    '--plain-name', 'featureFlag production UI', CHANGED[-1]], 300)
success &= run('shared-default-and-focus', [str(SDK / 'bin/flutter'), 'test', '--no-pub',
    '--concurrency=1', '--reporter=expanded',
    '--file-reporter=json:' + str(OUT / 'shared-default.machine.jsonl'), *DEFAULT_TESTS], 180)
feature_summary = G.machine_summary(OUT / 'feature-flag.machine.jsonl')
default_summary = G.machine_summary(OUT / 'shared-default.machine.jsonl')
export_drift = [name for name, digest in before.items()
                if not (EXPORT / name).is_file() or sha(EXPORT / name) != digest]
source_drift = {name: {'before': digest, 'after': sha(ROOT / name) if (ROOT / name).is_file() else None}
                for name, digest in guard.items()
                if not (ROOT / name).is_file() or sha(ROOT / name) != digest}
non_consumed_drift = [name for name, digest in before.items() if name not in guard
                     and (not (ROOT / name).is_file() or sha(ROOT / name) != digest)]
sdk_after = sdk_inputs()
packages_after = package_inputs()
save(OUT / 'sdk-after.json', sdk_after)
save(OUT / 'package-inputs-after.json', packages_after)
passing = success and not source_drift and not export_drift and sdk_before == sdk_after and packages_before == packages_after
for summary, expected in [(feature_summary, 17), (default_summary, 9)]:
    passing &= (summary['runner_completed_successfully'] and summary['passed'] == expected
                and not any(summary[n] for n in ['failed', 'errors', 'skipped', 'unfinished', 'event_errors']))
report = {'status': 'pass' if passing else 'fail', 'commands': commands,
    'feature_flag_summary': feature_summary, 'shared_default_summary': default_summary,
    'consumed_source_input_count': len(guard), 'source_drift': source_drift,
    'export_drift': export_drift, 'non_consumed_source_drift': non_consumed_drift,
    'sdk_unchanged': sdk_before == sdk_after, 'package_inputs_unchanged': packages_before == packages_after,
    'changed_source_sha256': {name: before[name] for name in CHANGED},
    'sql_executed': False, 'provider_credentials_supplied': False,
    'browser_builds': False, 'native_builds': False,
    'scope': 'One 17-case actual production featureFlag UI selection with locked SDK synthetic HTTP; nine shared default-bound/focus regressions. Selected format/analysis only. No full Admin, server audit or runtime-family closure claim.'}
save(OUT / 'validation.json', report)
print('RESULT', report['status'], flush=True)
raise SystemExit(0 if passing else 1)
