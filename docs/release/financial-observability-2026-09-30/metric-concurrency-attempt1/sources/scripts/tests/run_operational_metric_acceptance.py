"""Root-only actual148 metric concurrency with complete fixture preservation."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PATHS = ['scripts/tests/operational_metric_concurrency_uat.rb',
         'scripts/tests/runtime_control_concurrency_uat.rb',
         'scripts/tests/local_offline_verification.py',
         'scripts/tests/notification_upgrade_telemetry.py',
         'scripts/tests/run_operational_metric_acceptance.py',
         'supabase/migrations/20260930160000_redacted_operational_health.sql']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'docs/release'):
        parser.error('Fresh repository release output required')
    spec = importlib.util.spec_from_file_location('fixture', ROOT / PATHS[2])
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    before = fixture.prepare(output, 148, '20260930160000')
    inputs = {p: sha(ROOT / p) for p in PATHS}
    for p in PATHS:
        target = output / 'sources' / p
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / p).read_bytes())
    env = os.environ.copy()
    env.update(COLLECT_OPERATIONAL_METRICS_QA='isolated_clone',
               COLLECT_OPERATIONAL_HEALTH_SHA=inputs[PATHS[5]],
               COLLECT_RUNTIME_CONTROL_CHECKPOINT=str(output / 'concurrency-checkpoint.json'))
    command = ['ruby', '-EUTF-8:UTF-8', PATHS[0]]
    with (output / 'stdout').open('xb') as out, (output / 'stderr').open('xb') as err:
        process = subprocess.run(command, cwd=ROOT, env=env, stdout=out,
                                 stderr=err, timeout=150)
    after = fixture.snapshot()
    guard = fixture.guard(148, '20260930160000')
    fixture.save(output / 'after.json', after)
    final_inputs = {p: sha(ROOT / p) for p in PATHS}
    case_file = output / 'concurrency-checkpoint.json'
    cases = json.loads(case_file.read_text()) if case_file.exists() else {}
    passed = (process.returncode == 0 and before == after and inputs == final_inputs
              and cases.get('status') == 'pass' and cases.get('cases_passed') == 5
              and cases.get('blocking_races') == 4
              and cases.get('worker_sessions_remaining') == 0)
    result = {'status': 'pass' if passed else 'fail', 'command': command,
              'return_code': process.returncode, 'actual_cases': cases.get('cases_passed', 0),
              'actual_blocking_races': cases.get('blocking_races', 0),
              'all_table_catalog_cron_fingerprints_restored': before == after,
              'table_count': len(after['tables']), 'guard': guard,
              'source_before': inputs, 'source_after': final_inputs,
              'source_unchanged': inputs == final_inputs,
              'stdout_sha256': sha(output / 'stdout'),
              'stderr_sha256': sha(output / 'stderr'),
              'case_checkpoint_sha256': sha(case_file) if case_file.exists() else None,
              'provider_called': False, 'hosted_called': False,
              'sequences_restored': False,
              'scope': 'Actual ordinary-owner/service RPC telemetry writer races and attribution-controlled committed cleanup; not Admin permission races or final whole-system acceptance'}
    fixture.save(output / 'validation.json', result)
    print(json.dumps({k: result[k] for k in ['status', 'actual_cases', 'actual_blocking_races', 'all_table_catalog_cron_fingerprints_restored', 'source_unchanged']}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
