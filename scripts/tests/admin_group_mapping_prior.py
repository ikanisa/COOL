#!/usr/bin/env python3
"""Prove the old owned member-key mapping with the corrected semantic probe."""
import argparse
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]


def digest(value):
    return hashlib.sha256(value).hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--flutter', required=True)
    p.add_argument('--output', required=True)
    args = p.parse_args()
    out = pathlib.Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'lib/admin/core/admin_detail_specs.dart'
    original = source.read_bytes()
    token = b"            'active_members',\n"
    if original.count(token) != 1:
        raise ValueError('Owned current mapping does not match reviewed candidate.')
    prior = original.replace(token, b'', 1)
    (out / 'current-spec.dart').write_bytes(original)
    (out / 'old-mapping-spec.dart').write_bytes(prior)
    argv = [str(pathlib.Path(args.flutter).resolve(strict=True)), 'test', '--no-pub',
            'test/admin_runtime_control_gap_test.dart', '--plain-name', 'GAP-A15', '--reporter', 'expanded']
    result = None
    try:
        source.write_bytes(prior)
        result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=35)
    finally:
        if source.read_bytes() != prior:
            # Do not overwrite someone else's unexpected source mutation.
            (out / 'restore-conflict.json').write_text(json.dumps({'source': str(source), 'saved_source': str(out / 'current-spec.dart')}))
            raise RuntimeError('Unexpected concurrent source mutation; restore requires review.')
        source.write_bytes(original)
    log = result.stdout + result.stderr
    (out / 'tests.log').write_text(log)
    reproduced = result.returncode == 1 and 'Test failed. See exception logs above.' in log and 'unbounded' not in log and 'Compilation failed' not in log
    report = {'argv': argv, 'exit_code': result.returncode, 'gap_reproduced': reproduced,
              'source_restored': source.read_bytes() == original, 'old_mapping_sha256': digest(prior),
              'current_spec_sha256': digest(original), 'tests_sha256': digest(log.encode()),
              'scope': 'controlled projection of old owned key mapping; corrected Tooltip/count widget probe',
              'database_called': False, 'provider_called': False}
    (out / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if reproduced and report['source_restored'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
