#!/usr/bin/env python3
"""Run the actual v1/v2 Edge contracts with exact local source bindings."""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = pathlib.Path('supabase/functions/collect-receipt-supervisor')
TESTS = ['handler_test.ts', 'wire_test.ts', 'operations_contract_test.ts',
         'operations_wire_test.ts']
INPUTS = ['handler.ts', 'operations_contract.ts', *TESTS,
          'fixtures/observed-proof.json', 'fixtures/observed-health.json',
          'fixtures/observed-reconciled.json', 'fixtures/observed-operations-v2.json']


def sha(value):
    return hashlib.sha256(value).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report-dir', required=True)
    parser.add_argument('--deno', default=shutil.which('deno') or str(pathlib.Path.home() / '.local/bin/deno'))
    args = parser.parse_args()
    report = pathlib.Path(args.report_dir).resolve()
    assert not report.exists(), 'Use a fresh evidence directory'
    report.mkdir(parents=True)
    copied = report / 'inputs'
    copied.mkdir()
    sources = [BASE / item for item in INPUTS]
    sources.append(pathlib.Path(__file__).resolve().relative_to(ROOT))
    before = {}
    for relative in sources:
        body = (ROOT / relative).read_bytes()
        before[str(relative)] = sha(body)
        target = copied / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    command = [args.deno, 'test', '--no-remote', '--allow-read=' + str(BASE / 'fixtures'),
               *[str(BASE / test) for test in TESTS]]
    version = subprocess.run([args.deno, '--version'], capture_output=True, text=True, check=True).stdout
    binding = dict(started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   command=command, cwd=str(ROOT), runtime=version, source_sha256=before,
                   hosted_called=False, device_used=False, sms_sent=False)
    (report / 'execution-binding.json').write_text(json.dumps(binding, indent=2) + '\n')
    observed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    (report / 'stdout.log').write_text(observed.stdout)
    (report / 'stderr.log').write_text(observed.stderr)
    after = {str(relative): sha((ROOT / relative).read_bytes()) for relative in sources}
    matched = re.search(r'(\d+) passed \| (\d+) failed', observed.stdout)
    result = dict(exit_code=observed.returncode, passed=int(matched[1]) if matched else None,
                  failed=int(matched[2]) if matched else None, source_unchanged=before == after,
                  source_sha256_after=after, finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    result['status'] = 'pass' if observed.returncode == 0 and matched and matched[2] == '0' and before == after else 'failed'
    (report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'passed', 'failed', 'source_unchanged']}))
    if result['status'] != 'pass':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
