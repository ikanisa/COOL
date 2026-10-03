#!/usr/bin/env python3
"""Prepare separate build/harness inputs; does not execute Flutter or a browser."""
import hashlib
import json
from pathlib import Path
import shutil
from urllib.parse import unquote, urlparse

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT = Path(__file__).resolve().parent
SOURCE = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-integrated-local-candidate-20261001-current1')
BUILD = ROOT / '.cache/admin-integration-browser-build-current1'
HARNESS = ROOT / '.cache/admin-integration-browser-harness-current1'
SDK = ROOT / '.cache/flutter-sdk-isolated-admin-browser-current1'
PRIOR = ROOT / '.cache/current-admin-browser-build-current2'
BASE_MANIFEST_SHA = 'f6f632b614480293e38a97ede4fb1169c449cb1af9c90a56bb517338d0aea5b9'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def packages():
    result = {}
    for row in json.loads((BUILD / '.dart_tool/package_config.json').read_text())['packages']:
        uri = urlparse(row['rootUri'])
        base = (Path(unquote(uri.path)) if uri.scheme == 'file' else BUILD / '.dart_tool' / unquote(uri.path)).resolve(strict=True)
        result[row['name']] = {'root': str(base), 'files': {
            str(p.relative_to(base)): sha(p) for p in sorted([base / 'pubspec.yaml', *(base / 'lib').rglob('*')]) if p.is_file()}}
    return result

def sdk_inputs():
    paths = set()
    for tree in ['packages/flutter/lib', 'packages/flutter_localizations/lib',
                 'packages/flutter_web_plugins/lib', 'bin/cache/dart-sdk/lib',
                 'bin/cache/flutter_web_sdk', 'bin/cache/artifacts/engine']:
        paths.update(p for p in (SDK / tree).rglob('*') if p.is_file())
    for name in ['bin/flutter', 'bin/internal/shared.sh', 'bin/cache/flutter.version.json',
                 'bin/cache/flutter_tools.snapshot', 'bin/cache/dart-sdk/bin/dart',
                 'bin/cache/dart-sdk/bin/dartvm', 'bin/cache/dart-sdk/bin/dartaotruntime',
                 'bin/cache/dart-sdk/bin/snapshots/dart2js_aot.dart.snapshot',
                 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot']:
        p = SDK / name
        if p.is_file(): paths.add(p)
    return {str(p.relative_to(SDK)): sha(p) for p in sorted(paths)}

assert not BUILD.exists() and not HARNESS.exists()
manifest_path = SOURCE / '.collect-release-candidate.json'
assert sha(manifest_path) == BASE_MANIFEST_SHA
manifest = json.loads(manifest_path.read_text())
inputs = {n: v['sha256'] for n, v in manifest['source_files'].items()}
assert len(inputs) == 2175
for n, digest in inputs.items():
    p = SOURCE / n
    assert sha(p) == digest, n
    target = BUILD / n
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, target)
    assert sha(target) == digest, n
assert all(sha(SOURCE / n) == d for n, d in inputs.items())
supplements = json.loads((ROOT / 'docs/release/rapid-completion-2026-10-01/current-admin-browser-current2/copied-inputs.json').read_text())['supplemental_inputs']
for n, d in supplements.items():
    p = PRIOR / n
    assert sha(p) == d, n
    q = BUILD / n
    if q.exists(): assert sha(q) == d, n
    else:
        q.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, q)
assert all(sha(BUILD / n) == d for n, d in supplements.items())
for n in ['pubspec.yaml', 'pubspec.lock']:
    assert sha(BUILD / n) == sha(PRIOR / n), n
(BUILD / '.dart_tool').mkdir(exist_ok=True)
config = json.loads((PRIOR / '.dart_tool/package_config.json').read_text())
for row in config['packages']:
    if row['name'] == 'collect_app': row['rootUri'] = BUILD.as_uri() + '/'
    elif row['name'] in ['file_saver', 'firebase_messaging', 'gotrue']:
        row['rootUri'] = (BUILD / 'third_party' / row['name']).as_uri() + '/'
(BUILD / '.dart_tool/package_config.json').write_text(json.dumps(config, indent=2) + '\n')
shutil.copy2(PRIOR / '.dart_tool/package_graph.json', BUILD / '.dart_tool/package_graph.json')
executing = {}
for n in ['scripts/qa/current_browser_lifecycle.mjs', 'scripts/qa/local_browser_api_fixture.mjs']:
    q = HARNESS / n
    q.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(BUILD / n, q)
    executing[n] = sha(q)
    assert executing[n] == inputs[n]
package_map = packages()
sdk_map = sdk_inputs()
save('browser-packages-prepared.json', package_map)
save('browser-sdk-prepared.json', sdk_map)
save('browser-stage-prepared.json', {
    'status': 'prepared_execution_held', 'source': str(SOURCE),
    'manifest_sha256': BASE_MANIFEST_SHA, 'input_count': len(inputs),
    'build_root': str(BUILD), 'harness_root': str(HARNESS), 'sdk_root': str(SDK),
    'inputs_sha256': inputs, 'supplemental_inputs': supplements,
    'executing_harness_inputs': executing, 'package_count': len(package_map),
    'package_config_sha256': sha(BUILD / '.dart_tool/package_config.json'),
    'package_graph_sha256': sha(BUILD / '.dart_tool/package_graph.json'),
    'source_unchanged_during_copy': True,
    'needs_final_current2_snapshot_binding': True,
    'build_or_browser_or_vm_or_sql_executed': False,
    'required_authority_test_final_sha256': '3f03b5126e88fefdd0c96abe14e382d247f749086198ff068f7546627c2cbb62',
    'scope': 'One independent staging copy from strict current1. Final current2 can replace the one known test-only delta under hash guard; no build before root release. Harness has a separate workspaceRoot from buildRoot.'})
print('PREPARED', len(inputs), 'candidate files;', len(package_map), 'packages;', len(sdk_map), 'SDK inputs; execution HELD', flush=True)
