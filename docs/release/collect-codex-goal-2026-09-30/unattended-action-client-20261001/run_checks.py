#!/usr/bin/env python3
"""Credential-free local evidence capture. No host tool/backend/Keychain call."""
from pathlib import Path
import datetime, hashlib, json, os, subprocess, sys
ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
MODULE = ROOT / 'tools/collect-notification-mcp'
PACKET = ROOT / 'docs/release/collect-codex-goal-2026-09-30/unattended-action-client-20261001'
NODE = Path('/Volumes/PRO-G40/Development/Node/bin/node')
TSC = MODULE / 'node_modules/typescript/bin/tsc'
HELPER = ROOT / '.cache/collect-unattended-mcp-helper/unattended-keychain-self-test'
ENV = {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
def inputs():
    paths = list((MODULE / 'src').rglob('*')) + [MODULE / 'package.json', MODULE / 'pnpm-lock.yaml', MODULE / 'tsconfig.json', MODULE / 'README.md']
    paths += list((ROOT / 'supabase/functions/collect-receipt-supervisor').rglob('*'))
    paths += list((ROOT / 'contracts').glob('collect-shadow-supervisor-v1*'))
    paths += [ROOT / 'contracts/collect-operational-health-v1.schema.json', ROOT / 'contracts/collect-operational-health-v1.fixture.json']
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(set(paths)) if p.is_file() and p.suffix in ('.ts', '.swift', '.json', '.yaml', '.md') and 'node_modules' not in p.parts}
stable = sys.argv[1:] == ['--scoped-final-stable']
scoped = sys.argv[1:] == ['--scoped-final'] or stable
focused = sys.argv[1:] == ['--focused-final'] or scoped
if sys.argv[1:] and not focused: raise SystemExit('Unsupported evidence command')
attempt = PACKET / ('checks-scoped-final-stable' if stable else 'checks-scoped-final' if scoped else 'checks-final-focused' if focused else 'checks-attempt1')
attempt.mkdir(exist_ok=False)
before = inputs()
(attempt / 'sources-before.json').write_text(json.dumps(before, indent=2) + '\n')
commands = [
 ('typescript', [str(NODE), str(TSC), '--noEmit'], 60),
 ('node', [str(NODE), '--experimental-strip-types', '--test', *[str(p.relative_to(MODULE)) for p in sorted((MODULE/'src').glob('*.test.ts'))]], 120),
 ('hardware-parser', [str(HELPER), 'self-test'], 10),
]
if focused:
    commands = [commands[0], ('node', [str(NODE), '--experimental-strip-types', '--test', 'src/unattended_runner.test.ts', 'src/unattended_profile.test.ts'], 60)]
if scoped:
    commands = [commands[0], ('node', [str(NODE), '--experimental-strip-types', '--test', *[str(p.relative_to(MODULE)) for p in sorted((MODULE/'src').glob('unattended_*.test.ts'))]], 60)]
receipts = []
for name, command, timeout in commands:
    started = now()
    with (attempt / (name + '.stdout.log')).open('xb') as out, (attempt / (name + '.stderr.log')).open('xb') as err:
        try:
            result = subprocess.run(command, cwd=MODULE, env=ENV, stdout=out, stderr=err, timeout=timeout, check=False)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 'deadline'
    receipts.append({'name':name, 'command':command, 'started_at':started, 'finished_at':now(), 'exit_code':code, 'timeout_seconds':timeout})
    (attempt / 'commands.json').write_text(json.dumps(receipts, indent=2) + '\n')
    if code != 0: break
after = inputs()
(attempt / 'sources-after.json').write_text(json.dumps(after, indent=2) + '\n')
delta = [{'path':p, 'before':before.get(p), 'after':after.get(p)} for p in sorted(set(before)|set(after)) if before.get(p)!=after.get(p)]
receipt = {'kind':'current_combined_credential_free_bridge_checks','captured_at':now(),'commands':receipts,'source_inputs':len(before),'source_unchanged':not delta,'source_delta':delta,
 'node_path':str(NODE),'node_sha256':sha(NODE),'tsc_sha256':sha(TSC),'hardware_helper_sha256':sha(HELPER),
 'environment_keys':sorted(ENV),'source_freeze':False,'hosted_calls':0,'keychain_calls':0,'otp_requests':0,'live_sender_calls':0,'production_acceptance':False}
(attempt/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'attempt':str(attempt),'commands':[{'name':r['name'],'exit_code':r['exit_code']} for r in receipts], 'source_unchanged':not delta,'source_inputs':len(before),'delta_paths':[x['path'] for x in delta]}))
