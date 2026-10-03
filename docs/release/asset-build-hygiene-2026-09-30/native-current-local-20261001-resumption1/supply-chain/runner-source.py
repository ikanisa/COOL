#!/usr/bin/env python3
"""Finite source inventory over native candidate plus explicitly captured non-native inputs."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
CACHE = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930')
SOURCE = CACHE / 'export-native-current-local-20261001-resumption1'
MANIFEST = ROOT / 'docs/release/rapid-completion-2026-10-01/native-source-resumption1.json'
EXPORT = CACHE / 'inventory-native-current-local-20261001-resumption1'
P = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/native-current-local-20261001-resumption1/supply-chain'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
P.mkdir(parents=True, exist_ok=False)
shutil.copy2(__file__, P / 'runner-source.py')
source = json.loads(MANIFEST.read_text())['source_sha256']
assert not EXPORT.exists()
for name, digest in source.items():
    path = SOURCE / name
    assert sha(path) == digest
    target = EXPORT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target)
extras = {
    'scripts/supply_chain/inventory.py', 'scripts/supply_chain/source_sbom.py', 'scripts/supply_chain/validate_source_sbom.py',
    'scripts/supply_chain/gradle_observed_sbom.py', 'Gemfile', 'Gemfile.lock', 'supabase/functions/deno.lock',
    'tools/public-photography/package.json', 'tools/public-photography/package-lock.json',
    'tools/collect-notification-mcp/package.json', 'tools/collect-notification-mcp/pnpm-lock.yaml',
    'tools/roster-decoder/requirements.lock', 'tools/roster-decoder/requirements.in', 'tools/roster-decoder/Dockerfile',
    'tools/roster-decoder/decoder.py', 'tools/roster-decoder/server.py',
}
extras.update(path.relative_to(ROOT).as_posix() for path in (ROOT / 'supabase/functions').rglob('*.ts'))
extras.update(path.relative_to(ROOT).as_posix() for path in (ROOT / 'docs/release/asset-build-hygiene-2026-09-30/schema').glob('*') if path.is_file())
runtime = json.loads((EXPORT / 'assets/group_covers/rwanda/runtime-manifest.json').read_text())
extras.update(row['source'] for row in runtime.get('records', []) if row['source'] not in source)
before = {name: sha(ROOT / name) for name in sorted(extras)}
for name, digest in before.items():
    assert name not in source or digest == source[name], 'Never overwrite root candidate: ' + name
    target = EXPORT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / name, target)
    assert sha(target) == digest
assert {path.relative_to(ROOT).as_posix() for path in (ROOT / 'supabase/functions').rglob('*.ts')} == {name for name in extras if name.startswith('supabase/functions/') and name.endswith('.ts')}
assert all(sha(ROOT / name) == digest for name, digest in before.items()), 'Non-native capture raced'
write(P / 'input-binding.json', {'native_candidate_manifest': str(MANIFEST), 'native_candidate_manifest_sha256': sha(MANIFEST),
      'native_candidate_source_sha256': source, 'additional_non_native_and_tooling_source_sha256': before,
      'scope': 'Frozen native root candidate plus at-copy non-native dependency declarations/Edge imports/tools. Backend inputs are separate from native compiler inputs; no mutable whole-repo equivalence.'})
commands = []
def run(name, argv):
    result = subprocess.run(argv, cwd=EXPORT, capture_output=True)
    (P / (name + '.stdout')).write_bytes(result.stdout)
    (P / (name + '.stderr')).write_bytes(result.stderr)
    commands.append({'name': name, 'argv': argv, 'exit_code': result.returncode, 'stdout_sha256': sha(P / (name + '.stdout')), 'stderr_sha256': sha(P / (name + '.stderr'))})
    write(P / 'execution.json', {'status': 'running' if result.returncode == 0 else 'fail', 'commands': commands})
    print(name, result.returncode, flush=True)
    assert result.returncode == 0, name
run('candidate-inventory', ['python3', str(EXPORT / 'scripts/supply_chain/inventory.py'), '--output', str(P / 'candidate-inventory.json')])
run('candidate-inventory-reproduction', ['python3', str(EXPORT / 'scripts/supply_chain/inventory.py'), '--output', str(P / 'candidate-inventory.json'), '--check'])
run('source-sbom', ['python3', str(EXPORT / 'scripts/supply_chain/source_sbom.py'), '--inventory', str(P / 'candidate-inventory.json'), '--output', str(P / 'source-sbom.cdx.json')])
run('source-sbom-reproduction', ['python3', str(EXPORT / 'scripts/supply_chain/source_sbom.py'), '--inventory', str(P / 'candidate-inventory.json'), '--output', str(P / 'source-sbom.cdx.json'), '--check'])
run('source-sbom-schema', ['python3', str(EXPORT / 'scripts/supply_chain/validate_source_sbom.py'), str(P / 'source-sbom.cdx.json')])
inventory = json.loads((P / 'candidate-inventory.json').read_text())
source_after = {name: sha(EXPORT / name) for name in source}
extra_after = {name: sha(EXPORT / name) for name in before}
assert source_after == source and extra_after == before
write(P / 'validation.json', {'status': 'pass', 'commands': commands, 'inventory_sha256': sha(P / 'candidate-inventory.json'),
      'source_sbom_sha256': sha(P / 'source-sbom.cdx.json'), 'native_source_unchanged': True, 'additional_inputs_unchanged': True,
      'live_additional_input_drift': {name: {'before': digest, 'after': sha(ROOT / name)} for name, digest in before.items() if sha(ROOT / name) != digest},
      'summary': inventory['summary'], 'checks': inventory['checks'],
      'scope': 'Reproducible source declarations/assets/fork integrity plus CycloneDX schema; actual Android graphs/APK and iOS bundle compiler bindings remain separate native packets. License unknowns remain explicit.'})
print('SUPPLY PASS', inventory['summary'], flush=True)
