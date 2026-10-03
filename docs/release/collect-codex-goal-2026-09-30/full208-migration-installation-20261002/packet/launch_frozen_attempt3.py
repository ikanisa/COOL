#!/usr/bin/env python3
"""Retain exact command/tool/source bindings around the owned full208 run."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OWNED = ROOT / '.cache/receipt-full-candidate-rehearsal-20261002'
FREEZE = ROOT / '.cache/receipt-successor-execution-root-integration-20261002/migration-freeze.json'
FREEZE_SHA = 'd5747f242b224c05be86096e98de8bd9bbf908f9b502765162359778ed4b2cf8'
DRIVER = OWNED / 'full_candidate_ordinary_rehearsal_attempt3.py'
DRIVER_SHA = '3c63fa61aed0735d20fccfd24a3f84c3bce7796dee20be58c153290c67b920ec'
READER = OWNED / 'combined_reader_seam_attempt3.py'
READER_SHA = '19bf64469226ff7ab4930d5d5222949935de5c5e2169a560bc66f3f97afdf213'
DOCKER = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
IMAGE = 'public.ecr.aws/supabase/postgres:17.6.1.095'
IMAGE_ID = 'sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    attempt = 'full208-attempt3'
    launch = OWNED / (attempt + '-launch')
    report = OWNED / attempt
    assert not launch.exists() and not report.exists(), 'Preserve all prior attempts'
    freeze = json.loads(FREEZE.read_text())
    prior = json.loads((OWNED / 'PRIOR_BINDINGS.json').read_text())
    bindings = {str(FREEZE): FREEZE_SHA, str(DRIVER): DRIVER_SHA,
                str(READER): READER_SHA, **prior['tools'],
                **{str(ROOT / n): h for n, h in freeze['helpers'].items()}}
    observed = {n: sha(n) for n in bindings}
    assert observed == bindings, 'Pinned tools/helper/freeze source drift'
    inventory = {r['path']: r['sha256'] for r in freeze['source_inventory']}
    current = {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
    assert current == inventory and len(current) == freeze['migration_count'] == 208
    image = subprocess.run([DOCKER, 'image', 'inspect', IMAGE, '--format', '{{.Id}}'],
                           capture_output=True, text=True, timeout=30, check=True)
    assert image.stdout.strip() == IMAGE_ID, 'Cached image identity drift'
    argv = ['/usr/bin/python3', str(DRIVER), '--output', str(report), '--inventory',
            str(FREEZE), '--inventory-sha256', FREEZE_SHA]
    launch.mkdir(mode=0o700)
    receipt = {'command': argv, 'cwd': str(ROOT), 'tools_and_sources_before': observed,
               'image': IMAGE, 'actual_cached_image_id': image.stdout.strip(),
               'migration_count': len(current), 'migration_sources_before': current,
               'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    (launch / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Starting frozen full208 clean/populated ordinary rehearsal; exact output retained in ' + str(launch), flush=True)
    try:
        with (launch / 'stdout.log').open('w') as stdout, (launch / 'stderr.log').open('w') as stderr:
            result = subprocess.run(argv, cwd=ROOT, stdout=stdout, stderr=stderr)
        receipt['exit_code'] = result.returncode
    finally:
        receipt['tools_and_sources_after'] = {n: sha(n) for n in bindings}
        receipt['migration_sources_after'] = {str(p.relative_to(ROOT)): sha(p)
                                             for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
        receipt['tools_and_sources_unchanged'] = receipt['tools_and_sources_after'] == observed
        receipt['migration_sources_unchanged'] = receipt['migration_sources_after'] == current
        receipt['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (launch / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: receipt[k] for k in ('exit_code', 'tools_and_sources_unchanged',
                     'migration_sources_unchanged', 'completed_at')}), flush=True)
    if not receipt['tools_and_sources_unchanged'] or not receipt['migration_sources_unchanged']:
        raise RuntimeError('Frozen source/tool drift during execution')
    sys.exit(receipt['exit_code'])

if __name__ == '__main__':
    main()
