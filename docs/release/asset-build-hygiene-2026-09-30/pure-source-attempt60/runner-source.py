import hashlib
import importlib.util
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PACKET = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/pure-source-attempt60'
PYTHON = '/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
PACKET.mkdir(exist_ok=False)
(PACKET / 'runner-source.py').write_bytes(Path(__file__).read_bytes())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

spec = importlib.util.spec_from_file_location('source_export', ROOT / 'scripts/qa/native_source_export.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def source_inventory():
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
    result = {}
    for name in sorted(set(names)):
        if not name or not (module.selected(name) or name.startswith('scripts/')):
            continue
        path = ROOT / name
        if path.is_file() and not path.is_symlink():
            result[name] = sha(path)
    return result

before = source_inventory()
(PACKET / 'source-before.json').write_text(json.dumps(before, indent=2, sort_keys=True) + '\n')
commands, tests = [], []
env = {k: v for k, v in os.environ.items() if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}

def run(name, args, is_test=False):
    print('START', name, flush=True)
    started = time.monotonic()
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True)
    stdout, stderr = PACKET / (name + '.stdout'), PACKET / (name + '.stderr')
    stdout.write_bytes(result.stdout)
    stderr.write_bytes(result.stderr)
    commands.append({'name': name, 'command': args, 'exit_code': result.returncode,
                     'elapsed_seconds': round(time.monotonic() - started, 2),
                     'stdout_sha256': sha(stdout), 'stderr_sha256': sha(stderr)})
    (PACKET / 'execution.json').write_text(json.dumps({'status': 'running' if result.returncode == 0 else 'fail', 'commands': commands}, indent=2) + '\n')
    if is_test:
        output = (result.stdout + result.stderr).decode()
        ruby = re.search(r'(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips', output)
        python = re.search(r'Ran (\d+) tests?', output)
        assert ruby or python, 'Missing actual framework count: ' + name
        tests.append({'name': name, 'actual_tests': int(ruby.group(1) if ruby else python.group(1)),
                      'actual_assertions': int(ruby.group(2)) if ruby else None,
                      'ruby_failures_errors_skips': [int(ruby.group(i)) for i in (3, 4, 5)] if ruby else None})
    assert result.returncode == 0, name
    print('END', name, result.returncode, flush=True)

for name, args in [
    ('asset-integrity-tests', ['ruby', 'scripts/tests/asset_manifest_integrity_test.rb']),
    ('asset-hygiene-tests', ['ruby', 'scripts/tests/asset_hygiene_integration_test.rb']),
    ('reachability-tests', [PYTHON, 'scripts/tests/runtime_reachability_test.py']),
    ('supply-source-tests', [PYTHON, 'scripts/tests/supply_chain_source_test.py']),
    ('public-media-tests', ['ruby', 'scripts/tests/public_app_media_test.rb']),
    ('format-inventory-tests', ['ruby', 'scripts/tests/dart_format_test.rb']),
    ('native-export-tests', [PYTHON, 'scripts/tests/native_source_export_test.py']),
    ('native-provenance-tests', ['ruby', 'scripts/tests/native_build_provenance_test.rb']),
    ('media-source-binding-tests', [PYTHON, 'scripts/tests/public_media_source_binding_test.py']),
    ('media-publication-tests', [PYTHON, 'scripts/tests/public_media_publication_test.py']),
    ('observed-native-sbom-tests', [PYTHON, 'scripts/tests/gradle_observed_sbom_test.py']),
]:
    run(name, args, True)

run('asset-integrity', ['ruby', 'scripts/qa/asset_manifest_integrity.rb', '--json'])
run('group-integrity', ['ruby', 'scripts/qa/group_runtime_integrity.rb', '--root', '.', '--json'])
run('runtime-reachability', [PYTHON, 'scripts/qa/runtime_reachability.py', '--output', str(PACKET / 'runtime-reachability.json')])
inventory_args = [PYTHON, 'scripts/supply_chain/inventory.py', '--output', str(PACKET / 'source-inventory.json')]
run('inventory', inventory_args)
run('inventory-reproduction', inventory_args + ['--check'])
sbom_args = [PYTHON, 'scripts/supply_chain/source_sbom.py', '--inventory', str(PACKET / 'source-inventory.json'), '--output', str(PACKET / 'source-sbom.cdx.json')]
run('source-sbom', sbom_args)
run('source-sbom-reproduction', sbom_args + ['--check'])
run('sbom-schema', [PYTHON, 'scripts/supply_chain/validate_source_sbom.py', str(PACKET / 'source-sbom.cdx.json')])
run('recorder-syntax', ['/Volumes/PRO-G40/Development/Node/bin/node', '--check', 'scripts/qa/public_browser_app_media.mjs'])
after = source_inventory()
drift = {name: {'before_sha256': before.get(name), 'after_sha256': after.get(name)}
         for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)}
reachability = json.loads((PACKET / 'runtime-reachability.json').read_text())
sbom = json.loads((PACKET / 'source-sbom.cdx.json').read_text())
(PACKET / 'verification.json').write_text(json.dumps({
    'status': 'pass', 'commands': commands, 'tests': tests,
    'actual_tests': sum(row['actual_tests'] for row in tests),
    'actual_ruby_assertions': sum(row['actual_assertions'] or 0 for row in tests),
    'source_file_count_before': len(before), 'source_file_count_after': len(after),
    'source_before_sha256': sha(PACKET / 'source-before.json'), 'current_source_drift': drift,
    'current_source_acceptance': not drift,
    'source_sbom_components': len(sbom['components']),
    'reachability_report_sha256': sha(PACKET / 'runtime-reachability.json'),
    'scope': 'Independent dated local source/tooling regressions while application owners settle; deterministic source inventory/SBOM and exact drift reported; does not replace the final common application/native/media acceptance',
}, indent=2) + '\n')
print('PURE SOURCE PASS', sum(row['actual_tests'] for row in tests), 'tests;', len(drift), 'changed inputs', flush=True)
