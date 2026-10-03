#!/usr/bin/env python3
"""Bounded offline T13 client regression with exact before/after source binding."""
from pathlib import Path
import datetime
import hashlib
import json
import subprocess
import sys

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
MODULE = ROOT / 'tools/collect-notification-mcp'
PACKET = Path(__file__).resolve().parent
NODE = Path('/Volumes/PRO-G40/Development/Node/bin/node')
TSC = MODULE / 'node_modules/typescript/bin/tsc'
ENV = {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def inputs():
    paths = list((MODULE / 'src').rglob('*'))
    paths += [MODULE / name for name in ['package.json', 'pnpm-lock.yaml', 'package-lock.json', 'tsconfig.json', 'README.md']]
    paths += list((ROOT / 'supabase/functions/collect-receipt-supervisor').rglob('*'))
    paths += list((ROOT / 'contracts').glob('collect-shadow-supervisor-v1*'))
    paths += [ROOT / 'contracts/collect-operational-health-v1.schema.json', ROOT / 'contracts/collect-operational-health-v1.fixture.json']
    return {str(path.relative_to(ROOT)): sha(path) for path in sorted(set(paths))
            if path.is_file() and path.suffix in ['.ts', '.swift', '.json', '.yaml', '.md'] and 'node_modules' not in path.parts}

if len(sys.argv) != 2 or not sys.argv[1].startswith('checks-') or '/' in sys.argv[1]:
    raise SystemExit('Explicit new evidence leaf required')
attempt = PACKET / sys.argv[1]
attempt.mkdir(exist_ok=False)
before = inputs()
(attempt / 'sources-before.json').write_text(json.dumps(before, indent=2) + '\n')
tools_before = {str(path): sha(path) for path in [NODE, TSC]}
commands = [('typescript', [str(NODE), str(TSC), '--noEmit'], 60),
            ('node', [str(NODE), '--experimental-strip-types', '--test',
                      *[str(path.relative_to(MODULE)) for path in sorted((MODULE / 'src').glob('unattended_*.test.ts'))]], 180)]
receipts = []
for name, command, timeout in commands:
    started = now()
    with (attempt / (name + '.stdout.log')).open('xb') as out, (attempt / (name + '.stderr.log')).open('xb') as err:
        try:
            result = subprocess.run(command, cwd=MODULE, env=ENV, stdout=out, stderr=err, timeout=timeout, check=False)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 'deadline'
    receipts.append({'name': name, 'command': command, 'started_at': started,
                     'finished_at': now(), 'exit_code': code, 'timeout_seconds': timeout})
    (attempt / 'commands.json').write_text(json.dumps(receipts, indent=2) + '\n')
    if code != 0:
        break
after = inputs()
tools_after = {str(path): sha(path) for path in [NODE, TSC]}
(attempt / 'sources-after.json').write_text(json.dumps(after, indent=2) + '\n')
delta = [{'path': path, 'before': before.get(path), 'after': after.get(path)}
         for path in sorted(set(before) | set(after)) if before.get(path) != after.get(path)]
receipt = {'kind': 'bounded_offline_unattended_client_history_regression', 'captured_at': now(),
           'commands': receipts, 'source_inputs': len(before), 'source_unchanged': not delta,
           'source_delta': delta, 'tools_before': tools_before, 'tools_after': tools_after,
           'toolchain_unchanged': tools_before == tools_after, 'environment_keys': sorted(ENV),
           'hosted_calls': 0, 'keychain_calls': 0, 'otp_requests': 0, 'live_sender_calls': 0,
           'source_freeze': False, 'production_acceptance': False}
(attempt / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'attempt': str(attempt), 'exit_codes': [r['exit_code'] for r in receipts],
                  'source_inputs': len(before), 'source_unchanged': not delta, 'delta_paths': [row['path'] for row in delta]}))
raise SystemExit(0 if len(receipts) == 2 and all(r['exit_code'] == 0 for r in receipts)
                 and not delta and tools_before == tools_after else 2)
