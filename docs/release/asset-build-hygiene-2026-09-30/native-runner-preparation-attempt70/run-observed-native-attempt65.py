import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt51'
P = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/observed-native-attempt65'
PYTHON = '/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
SDK = ROOT / '.cache/flutter-sdk-isolated-asset-attempt23'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert json.loads((BASE / 'execution.json').read_text())['status'] == 'pass'
exports = {
    'production': Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt51'),
    'internal_gateway': Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt63-gateway'),
}
parents = {
    'production': ROOT / 'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt53-android',
    'internal_gateway': ROOT / 'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt63-gateway',
}
for parent in parents.values():
    assert json.loads((parent / 'execution.json').read_text())['status'] == 'pass'
P.mkdir(exist_ok=False)
(P / 'runner-source.py').write_bytes(Path(__file__).read_bytes())
inputs = {**json.loads((BASE / 'source-export.json').read_text())['source_sha256'],
          **json.loads((BASE / 'additional-public-tooling-source.json').read_text())['sha256']}
tool_names = ['scripts/supply_chain/gradle_observed_sbom.py', 'scripts/supply_chain/validate_source_sbom.py']
tool_hashes = {name: sha(ROOT / name) for name in tool_names}
assert all(tool_hashes[name] == inputs[name] for name in tool_names)
env = {k: v for k, v in os.environ.items()
       if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
env.update({'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
            'JAVA_HOME': '/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home',
            'PUB_CACHE': str(ROOT / '.cache/pub-cache-hygiene-20260930'),
            'PATH': str(SDK / 'bin') + ':/Users/jeanbosco/.local/bin:' + env['PATH']})
commands = []

def run(name, argv, cwd=ROOT):
    print('START', name, flush=True)
    started = time.monotonic()
    result = subprocess.run(argv, cwd=cwd, env=env, capture_output=True)
    (P / (name + '.stdout')).write_bytes(result.stdout)
    (P / (name + '.stderr')).write_bytes(result.stderr)
    commands.append({'name': name, 'command': argv, 'exit_code': result.returncode,
                     'elapsed_seconds': round(time.monotonic() - started, 2),
                     'stdout_sha256': sha(P / (name + '.stdout')),
                     'stderr_sha256': sha(P / (name + '.stderr'))})
    (P / 'execution.json').write_text(json.dumps({'status': 'running' if result.returncode == 0 else 'fail',
                                                'commands': commands}, indent=2) + '\n')
    assert result.returncode == 0, name
    print('END', name, flush=True)
    return result.stdout.decode()

reports = {}
for flavor, export in exports.items():
    init = export / 'scripts/supply_chain/gradle_runtime_inventory.init.gradle'
    assert sha(init) == inputs['scripts/supply_chain/gradle_runtime_inventory.init.gradle']
    graphs = {}
    for role in ['Runtime', 'Compile']:
        configuration = flavor + 'Release' + role + 'Classpath'
        output = run(flavor + '-' + role.lower() + '-graph',
                     ['./gradlew', '-I', str(init), ':app:collectRuntimeGraph',
                      '-PcollectInventoryConfiguration=' + configuration, '--offline', '--no-daemon'], export / 'android')
        captures = re.findall(r'COLLECT_RUNTIME_GRAPH_BEGIN\s*(.*?)\s*COLLECT_RUNTIME_GRAPH_END', output, re.S)
        assert len(captures) == 1
        graph = json.loads(captures[0])
        assert graph['configuration'] == configuration
        path = P / (flavor + '-' + role.lower() + '-graph.json')
        path.write_text(json.dumps(graph, indent=2, sort_keys=True) + '\n')
        graphs[role] = path
    bom, inventory = P / (flavor + '-sbom.cdx.json'), P / (flavor + '-inventory.json')
    args = [PYTHON, str(ROOT / 'scripts/supply_chain/gradle_observed_sbom.py'),
            '--runtime-graph', str(graphs['Runtime']), '--compile-graph', str(graphs['Compile']),
            '--flavor', flavor, '--output', str(bom), '--inventory', str(inventory)]
    run(flavor + '-sbom', args)
    run(flavor + '-reproduction', args + ['--check'])
    run(flavor + '-schema', [PYTHON, str(ROOT / 'scripts/supply_chain/validate_source_sbom.py'), str(bom)])
    reports[flavor] = {'inventory_sha256': sha(inventory), 'sbom_sha256': sha(bom),
                       'parent_build_execution_sha256': sha(parents[flavor] / 'execution.json'),
                       'parent_artifact_sha256': sha(parents[flavor] / 'apk-verification.json'),
                       'counts': {key: json.loads(inventory.read_text())[key]
                                  for key in ['components', 'external_artifact_occurrences']}}
assert all(sha(ROOT / name) == value for name, value in tool_hashes.items())
for export in exports.values():
    assert all((export / name).is_file() and sha(export / name) == value
               for name, value in inputs.items())
(P / 'verification.json').write_text(json.dumps({
    'status': 'pass', 'commands': commands, 'tool_source_sha256': tool_hashes,
    'parent_source_export_sha256': sha(BASE / 'source-export.json'), 'reports': reports,
    'scope': 'Two separately named actual unsigned-build compile/runtime graphs and observed external JAR/AAR hashes; source/graph/artifact binding, reproduction and offline schema validation. Gateway observation does not certify the production lock or installed-device/provider/store behavior.',
}, indent=2, sort_keys=True) + '\n')
print('OBSERVED NATIVE PASS', flush=True)
