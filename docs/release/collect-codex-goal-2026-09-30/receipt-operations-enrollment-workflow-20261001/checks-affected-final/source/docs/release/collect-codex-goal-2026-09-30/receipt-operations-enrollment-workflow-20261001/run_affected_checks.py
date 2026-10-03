#!/usr/bin/env python3
"""Retain actual bounded checks for this source scope; no credentials or hosted calls."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[4]
BRIDGE = ROOT / 'tools/collect-notification-mcp'
NODE = Path('/Volumes/PRO-G40/Development/Node/bin/node')
SWIFTC = Path('/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc')
LEAF = Path(__file__).resolve().parent / sys.argv[1]
LEAF.mkdir(exist_ok=False)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inputs():
    paths = list((BRIDGE / 'src').rglob('*.ts')) + list((BRIDGE / 'src').rglob('*.swift'))
    paths += list((BRIDGE / 'src/testing/unattended_enrollment_observed').glob('*.json'))
    paths += list((ROOT / 'supabase/functions/collect-receipt-supervisor').glob('*.ts'))
    paths += [BRIDGE / name for name in ('package.json', 'pnpm-lock.yaml', 'tsconfig.json', 'ENROLLMENT.md')]
    paths += [ROOT / 'supabase/migrations/20261001180000_receipt_operations_enrollment_workflow.sql', Path(__file__).resolve(), Path(__file__).resolve().with_name('run_node_checks.py')]
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(set(paths))}

def inventory():
    return {str(path.relative_to(BRIDGE)): digest(path) for path in sorted((BRIDGE / 'node_modules').rglob('*')) if path.is_file() and not path.is_symlink()}

before = inputs()
dependencies_before = inventory()
tools_before = {'node': digest(NODE), 'swiftc': digest(SWIFTC)}
(LEAF / 'sources-before.json').write_text(json.dumps(before, indent=2) + '\n')
(LEAF / 'dependencies-before.json').write_text(json.dumps(dependencies_before, indent=2) + '\n')
for name, expected in before.items():
    target = LEAF / 'source' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes((ROOT / name).read_bytes())
    if digest(target) != expected:
        raise RuntimeError('source copy readback mismatch')

commands = [
    ('node', [str(NODE), '--experimental-strip-types', '--test', *[f'src/unattended_{name}.test.ts' for name in ('client', 'journal', 'profile', 'runner', 'scheduler', 'stdio', 'store', 'enrollment', 'enrollment_observed')]], 90),
    ('swift-compile', [str(SWIFTC), 'src/unattended_keychain.swift', '-o', str(LEAF / 'unattended-keychain-self-test')], 90),
    ('swift-self-test', [str(LEAF / 'unattended-keychain-self-test'), 'self-test'], 10),
]
# Reuse the actual successful current TypeScript command, with exact prior
# source/dependency/Node bindings and byte-for-byte raw log association.
prior_leaf = Path(__file__).resolve().parent / 'checks-final-attempt3'
prior = json.loads((prior_leaf / 'verification.json').read_text())
prior_sources = json.loads((prior_leaf / 'sources-before.json').read_text())
prior_dependencies = json.loads((prior_leaf / 'dependencies-before.json').read_text())
prior_tsc = next(item for item in prior['checks'] if item['name'] == 'tsc')
if prior_tsc['exit_code'] != 0 or prior['source_drift'] or prior['dependency_drift'] or not prior['source_copy_readback'] or any(before.get(name) != value for name, value in prior_sources.items()) or prior_dependencies != dependencies_before or prior['tool_hashes_before']['node'] != tools_before['node'] or digest(prior_leaf / 'tsc.log') != prior_tsc['log_sha256']:
    raise RuntimeError('successful TypeScript association no longer matches current inputs')
(LEAF / 'associated-tsc.log').write_bytes((prior_leaf / 'tsc.log').read_bytes())
receipts = [{**prior_tsc, 'executed_here': False, 'associated_from': str(prior_leaf.relative_to(ROOT)),
             'exact_prior_input_count': len(prior_sources), 'source_dependency_node_readback': True}]

for name, command, timeout in commands:
    started = datetime.now(timezone.utc).isoformat()
    try:
        result = subprocess.run(command, cwd=BRIDGE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
                                env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
        output, code = result.stdout, result.returncode
    except subprocess.TimeoutExpired as error:
        output, code = error.stdout or b'', 124
    (LEAF / f'{name}.log').write_bytes(output)
    receipt = {'name': name, 'command': command, 'timeout_seconds': timeout, 'exit_code': code, 'started_at': started,
               'completed_at': datetime.now(timezone.utc).isoformat(), 'log_sha256': digest(LEAF / f'{name}.log')}
    if name == 'node':
        counts = {key: int(value) for key, value in re.findall(r'(?m)^(?:#|ℹ) (tests|pass|fail|cancelled|skipped|todo) (\d+)', output.decode('utf8'))}
        receipt['counts'] = counts
        if code == 0 and (not counts.get('tests') or counts.get('pass') != counts.get('tests') or any(counts.get(key) for key in ('fail', 'cancelled', 'skipped', 'todo'))):
            receipt['exit_code'] = code = 125
    if name == 'swift-self-test' and code == 0:
        receipt['self_test'] = json.loads(output)
    receipts.append(receipt)
    (LEAF / 'commands.json').write_text(json.dumps(receipts, indent=2) + '\n')
    if code:
        break

after = inputs()
dependencies_after = inventory()
tools_after = {'node': digest(NODE), 'swiftc': digest(SWIFTC)}
(LEAF / 'sources-after.json').write_text(json.dumps(after, indent=2) + '\n')
(LEAF / 'dependencies-after.json').write_text(json.dumps(dependencies_after, indent=2) + '\n')
drift = [name for name in sorted(set(before) | set(after)) if before.get(name) != after.get(name)]
dependency_drift = [name for name in sorted(set(dependencies_before) | set(dependencies_after)) if dependencies_before.get(name) != dependencies_after.get(name)]
copy_readback = all(digest(LEAF / 'source' / name) == expected for name, expected in before.items())
passed = len(receipts) == len(commands) + 1 and all(item['exit_code'] == 0 for item in receipts) and not drift and not dependency_drift and tools_before == tools_after and copy_readback
summary = {'status': 'PASS' if passed else 'INCOMPLETE', 'bound_source_count': len(before), 'bound_dependency_file_count': len(dependencies_before),
           'source_drift': drift, 'dependency_drift': dependency_drift, 'tool_hashes_before': tools_before, 'tool_hashes_after': tools_after,
           'source_copy_readback': copy_readback, 'checks': receipts, 'hosted_calls': False, 'keychain_calls': False, 'real_keys_created': False,
           'whole_current_history_aggregate': 'OPEN_AFTER_TRANSITIVE_CHANGES_AND_TWO_TIMEOUTS', 'host_profile_changed': False, 'scheduler_installed': False, 'scheduler_started': False}
(LEAF / 'verification.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({'status': summary['status'], 'bound_sources': len(before), 'source_drift': drift,
                  'checks': [{'name': item['name'], 'exit_code': item['exit_code'], **({'counts': item['counts']} if 'counts' in item else {})} for item in receipts]}))
sys.exit(0 if passed else 1)
