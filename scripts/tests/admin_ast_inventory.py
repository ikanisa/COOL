#!/usr/bin/env python3
"""Network-free syntax audit using isolated, already cached parser dependencies."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = pathlib.Path('/Users/jeanbosco/.pub-cache/hosted/pub.dev')
PINS = {'analyzer': '8.2.0', '_fe_analyzer_shared': '89.0.0', 'glob': '2.2.0', 'watcher': '1.2.1'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot():
    paths = list(ROOT.glob('lib/admin/**/*.dart')) + [pathlib.Path(__file__).resolve(), ROOT / 'scripts/tests/admin_ast_inventory.dart', ROOT / '.dart_tool/package_config.json', ROOT / 'pubspec.lock']
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(paths)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--dart', required=True)
    p.add_argument('--output', required=True)
    args = p.parse_args()
    output = pathlib.Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    before = snapshot()
    original = ROOT / '.dart_tool/package_config.json'
    config = json.loads(original.read_text())
    for package in config['packages']:
        package['rootUri'] = urllib.parse.urljoin(original.as_uri(), package['rootUri'])
    pinned = []
    for name, version in PINS.items():
        path = CACHE / f'{name}-{version}'
        manifest = path / 'pubspec.yaml'
        if not re.search(r'^version:\s*' + re.escape(version) + r'\s*$', manifest.read_text(), re.M):
            raise ValueError(f'Cached parser manifest mismatch: {name}')
        config['packages'] = [item for item in config['packages'] if item['name'] != name]
        config['packages'].append({'name': name, 'rootUri': path.as_uri() + '/', 'packageUri': 'lib/', 'languageVersion': '3.7'})
        sources = {str(f.relative_to(path)): sha(f) for f in sorted(path.glob('lib/**/*.dart'))}
        pinned.append({'name': name, 'version': version, 'manifest_sha256': sha(manifest), 'library_source_sha256': sources})
    (output / 'parser-dependencies.json').write_text(json.dumps(pinned, indent=2) + '\n')
    package_config = output / 'package_config.json'
    package_config.write_text(json.dumps(config, indent=2) + '\n')
    argv = [str(pathlib.Path(args.dart).resolve(strict=True)), f'--packages={package_config}', str(ROOT / 'scripts/tests/admin_ast_inventory.dart'), str(ROOT)]
    run = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=40)
    (output / 'stdout').write_text(run.stdout)
    (output / 'stderr').write_text(run.stderr)
    if run.returncode:
        raise RuntimeError(f'AST parser failed; see {output}/stderr')
    data = json.loads(run.stdout)
    after = snapshot()
    (output / 'source-before.json').write_text(json.dumps(before, indent=2) + '\n')
    (output / 'source-after.json').write_text(json.dumps(after, indent=2) + '\n')
    (output / 'inventory.json').write_text(json.dumps(data, indent=2) + '\n')
    active = [unit for unit in data['units'] if not unit['fixture_only']]
    report = {'status': 'pass' if not data['parser_errors'] and before == after else 'fail', 'argv': argv,
              'source_unchanged': before == after, 'source_count': len(before), 'admin_units': len(data['units']),
              'active_admin_units': len(active), 'parser_errors': data['parser_errors'],
              **{key: sum(len(unit[key]) for unit in active) for key in ['declarations', 'invocations', 'providers', 'dialogs', 'callbacks']},
              'inventory_sha256': sha(output / 'inventory.json'), 'parser_dependencies_sha256': sha(output / 'parser-dependencies.json'),
              'app_dependency_configuration_changed': False, 'database_called': False, 'provider_called': False, 'network_called': False,
              'semantic_reachability_verified': False}
    (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if report['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
