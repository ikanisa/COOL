#!/usr/bin/env python3
"""Record offline diagnostic admission tests; no Docker or database execution."""
import argparse
import json
from pathlib import Path
import sys

from roster_fresh_auth_gate import ROOT, command, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'docs/release'):
        parser.error('A fresh repository release packet is required')
    output.mkdir(parents=True, exist_ok=False)
    files = sorted((ROOT / 'scripts/tests').glob('*.py'))
    before = {str(path.relative_to(ROOT)): sha(path) for path in files}
    captured = output / 'runner-sources'
    for path in files:
        target = captured / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
        if sha(target) != before[str(path.relative_to(ROOT))]:
            raise RuntimeError('Source changed during diagnostic capture')
    (output / 'inputs.json').write_text(json.dumps(before, indent=2) + '\n')
    receipt = command('tests', [sys.executable, str(ROOT / 'scripts/tests/current_generated_query_benchmark_test.py')],
                      ROOT, output, timeout=30)
    unchanged = all(path.is_file() and sha(path) == before[str(path.relative_to(ROOT))] for path in files)
    result = {'status': 'pass' if receipt['exit_code'] == 0 and unchanged else 'fail',
              'command': receipt, 'source_inputs_unchanged': unchanged,
              'inputs_sha256': sha(output / 'inputs.json'),
              'sql_executed': False, 'docker_executed': False,
              'hosted_called': False, 'provider_called': False,
              'actual_shell_segment_executed_with_fake_psql': True,
              'credential_fixture': 'synthetic offline sentinel; no QA credential read or copied',
              'scope': 'Argument/role-transition/failure/plan admission mechanics only; actual server diagnostic connection remains unproved.'}
    (output / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return int(result['status'] != 'pass')


if __name__ == '__main__':
    sys.exit(main())
