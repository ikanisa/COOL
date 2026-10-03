#!/usr/bin/env python3
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
stage = Path(sys.argv[1])
receipt_path = PACKET / sys.argv[2]
if receipt_path.parent != PACKET or receipt_path.exists():
    raise SystemExit('Fresh packet receipt required')
flutter = Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


manifest = json.loads((stage / '.collect-media-fixture-source.json').read_text())
source_before = {name: sha(stage / name) for name in manifest['source_files']}
tools = [Path(__file__), flutter, flutter.parent / 'cache/flutter_tools.snapshot', flutter.parent / 'cache/dart-sdk/bin/dart']
tool_before = {str(path): sha(path) for path in tools}
out_path = receipt_path.with_suffix('.stdout')
err_path = receipt_path.with_suffix('.stderr')
with out_path.open('w') as out, err_path.open('w') as err:
    result = subprocess.run([str(flutter), 'pub', 'get', '--offline', '--enforce-lockfile'], cwd=stage, stdout=out, stderr=err)
source_after = {name: sha(stage / name) for name in manifest['source_files']}
tool_after = {str(path): sha(path) for path in tools}
bindings = {name: sha(stage / name) for name in ['pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json', '.flutter-plugins-dependencies'] if (stage / name).exists()}
receipt = {'actual_command': [str(flutter), 'pub', 'get', '--offline', '--enforce-lockfile'], 'actual_exit_code': result.returncode,
    'source_before': source_before, 'source_after': source_after, 'toolchain_before': tool_before, 'toolchain_after': tool_after,
    'own_stage_generated_bindings': bindings, 'authored_sources_unchanged': source_before == source_after,
    'toolchain_unchanged': tool_before == tool_after,
    'status': 'pass' if result.returncode == 0 and source_before == source_after and tool_before == tool_after else 'fail',
    'scope': 'Own private stage offline enforced lock resolution; no copied root package configuration, broad source or native/release acceptance.'}
receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: receipt[key] for key in ['status', 'actual_exit_code', 'authored_sources_unchanged', 'toolchain_unchanged', 'own_stage_generated_bindings']}))
raise SystemExit(result.returncode or int(source_before != source_after or tool_before != tool_after))
