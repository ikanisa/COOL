#!/usr/bin/env python3
"""Only the missing current compile graph; runtime comes from accepted build task."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

R = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
C = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930')
B = R / 'docs/release/asset-build-hygiene-2026-09-30/native-current-local-20261001-resumption1'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['production', 'gateway'])
    mode = parser.parse_args().platform
    p = B / mode
    e = C / ('export-native-current-local-20261001-resumption1-' + mode)
    assert json.loads((p / 'artifact-verification.json').read_text())['status'] == 'pass'
    assert not (p / 'compile-graph.json').exists()
    shutil.copy2(__file__, p / 'compile-graph-runner.py')
    source = json.loads((p / 'source-export.json').read_text())['source_sha256']
    assert all(sha(e / name) == digest for name, digest in source.items())
    flavor = 'production' if mode == 'production' else 'internal_gateway'
    sdk = R / ('.cache/flutter-sdk-isolated-asset-attempt' + ('23' if mode == 'production' else '136'))
    env = {k: v for k, v in os.environ.items() if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
    env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', JAVA_HOME='/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home',
               PUB_CACHE=str(R / '.cache/pub-cache-hygiene-20260930'), PATH=str(sdk / 'bin') + ':/Users/jeanbosco/.local/bin:' + env['PATH'])
    argv = ['./gradlew', '-I', str(e / 'scripts/supply_chain/gradle_runtime_inventory.init.gradle'), ':app:collectRuntimeGraph',
            '-PcollectInventoryConfiguration=' + flavor + 'ReleaseCompileClasspath', '-Ptarget=' + ('lib/main.dart' if mode == 'production' else 'lib/main_gateway.dart'),
            '-PcollectUnsignedLocalQa=true', '--offline', '--no-daemon', '--max-workers=2', '--console=plain']
    started = time.monotonic()
    write(p / 'compile-graph-execution.json', {'status': 'running', 'pid': os.getpid(), 'argv': argv})
    with (p / 'compile-graph.stdout').open('wb') as out, (p / 'compile-graph.stderr').open('wb') as err:
        result = subprocess.run(argv, cwd=e / 'android', env=env, stdout=out, stderr=err)
    write(p / 'compile-graph-execution.json', {'status': 'pass' if result.returncode == 0 else 'fail', 'argv': argv, 'exit_code': result.returncode,
          'elapsed_seconds': round(time.monotonic() - started, 2), 'stdout_sha256': sha(p / 'compile-graph.stdout'), 'stderr_sha256': sha(p / 'compile-graph.stderr')})
    assert result.returncode == 0
    captures = re.findall(r'COLLECT_RUNTIME_GRAPH_BEGIN\s*(.*?)\s*COLLECT_RUNTIME_GRAPH_END', (p / 'compile-graph.stdout').read_text(), re.S)
    assert len(captures) == 1
    graph = json.loads(captures[0])
    assert graph['configuration'] == flavor + 'ReleaseCompileClasspath'
    write(p / 'compile-graph.json', graph)
    assert all(sha(e / name) == digest for name, digest in source.items())
    helper = B / 'supply-chain' / 'observed-sbom-helper.py'
    if not helper.exists():
        frozen = C / 'inventory-native-current-local-20261001-resumption1/scripts/supply_chain/gradle_observed_sbom.py'
        shutil.copy2(frozen, helper)
    spec = importlib.util.spec_from_file_location('observed_native_inventory_' + mode, helper)
    observed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(observed)
    runtime = json.loads((p / 'runtime-graph.json').read_text())
    evidence = {file.relative_to(R).as_posix(): sha(file) for file in [p / 'compile-graph.json', p / 'runtime-graph.json']}
    bom, inventory = observed.build([runtime, graph], evidence, flavor)
    write(p / 'observed-sbom.cdx.json', bom)
    write(p / 'observed-inventory.json', inventory)
    duplicate_bom, duplicate_inventory = observed.build([runtime, graph], evidence, flavor)
    assert bom == duplicate_bom and inventory == duplicate_inventory
    validator_path = C / 'inventory-native-current-local-20261001-resumption1/scripts/supply_chain/validate_source_sbom.py'
    validator_spec = importlib.util.spec_from_file_location('offline_native_schema_' + mode, validator_path)
    validator = importlib.util.module_from_spec(validator_spec)
    validator_spec.loader.exec_module(validator)
    errors = validator.validate(p / 'observed-sbom.cdx.json')
    assert not errors
    write(p / 'observed-sbom-validation.json', {'status': 'pass', 'compile_graph_sha256': sha(p / 'compile-graph.json'),
          'runtime_graph_sha256': sha(p / 'runtime-graph.json'), 'sbom_sha256': sha(p / 'observed-sbom.cdx.json'),
          'helper_sha256': sha(helper), 'inventory_sha256': sha(p / 'observed-inventory.json'), 'reproduction_verified': True,
          'schema_errors': errors, 'components': inventory['components'], 'external_artifact_occurrences': inventory['external_artifact_occurrences'],
          'scope': 'Only missing current compile observation ran; current runtime reused from actual native build. Complete external AAR/JAR hashes, project edges, deterministic CycloneDX/schema; no license/advisory or signed/device/store acceptance.'})
    print('OBSERVED SBOM PASS', mode, inventory['components'], flush=True)

if __name__ == '__main__':
    main()
