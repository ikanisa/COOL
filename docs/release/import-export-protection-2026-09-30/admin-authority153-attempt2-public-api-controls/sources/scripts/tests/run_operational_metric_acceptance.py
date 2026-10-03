"""Root-only actual148 metric concurrency with complete fixture preservation."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
PATHS = ['scripts/tests/operational_metric_concurrency_uat.rb',
         'scripts/tests/operational_health_authority_concurrency.rb',
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
    parser.add_argument('--suite', choices=['writer', 'health_authority'], default='writer')
    parser.add_argument('--schema-version', type=int, choices=[148, 150, 153], default=148)
    parser.add_argument('--read-kind', choices=['health', 'runtime_control', 'runtime_control_events', 'runtime_control_write', 'admin_notification'], default='health')
    parser.add_argument('--rehearse-runtime-authority-correction', action='store_true')
    args = parser.parse_args()
    if args.read_kind != 'health' and (args.suite != 'health_authority' or args.schema_version not in (150, 153)):
        parser.error('Governed-control authority probes require actual150 or153 authority suite')
    if args.schema_version == 153 and args.suite != 'health_authority':
        parser.error('153 extension currently binds authority consumers only')
    if args.rehearse_runtime_authority_correction and (args.read_kind == 'health' or args.schema_version != 150):
        parser.error('Correction rehearsal requires an unpatched150 governed-control authority probe')
    latest = {148: '20260930160000', 150: '20260930180000', 153: '20260930220000'}[args.schema_version]
    paths = PATHS[:]
    if args.schema_version >= 150:
        paths += ['supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql',
                  'supabase/migrations/20260930180000_operational_health_authority.sql']
    if args.read_kind.startswith('runtime_control'):
        paths += ['supabase/migrations/20260930150000_runtime_control_governance.sql']
    patch = 'supabase/migrations/20260930220000_runtime_control_authority.sql'
    if args.schema_version == 153:
        paths += ['supabase/migrations/20260930200000_admin_automation_navigation.sql',
                  'supabase/migrations/20260930210000_shadow_supervisor_runs.sql', patch]
    if args.rehearse_runtime_authority_correction:
        paths += [patch]
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'docs/release'):
        parser.error('Fresh repository release output required')
    spec = importlib.util.spec_from_file_location('fixture', ROOT / 'scripts/tests/local_offline_verification.py')
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    before = fixture.prepare(output, args.schema_version, latest)
    inputs = {p: sha(ROOT / p) for p in paths}
    for p in paths:
        target = output / 'sources' / p
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / p).read_bytes())
    env = os.environ.copy()
    env.update(COLLECT_OPERATIONAL_METRICS_QA='isolated_clone',
               COLLECT_HEALTH_AUTHORITY_QA='isolated_clone',
               COLLECT_HEALTH_SCHEMA_COUNT=str(args.schema_version),
               COLLECT_AUTHORITY_READ_KIND=args.read_kind,
               COLLECT_OPERATIONAL_HEALTH_SHA=inputs[PATHS[-1]],
               COLLECT_RUNTIME_CONTROL_CHECKPOINT=str(output / 'concurrency-checkpoint.json'))
    if args.rehearse_runtime_authority_correction:
        env.update(COLLECT_AUTHORITY_PATCH_SOURCE=str(ROOT / patch),
                   COLLECT_AUTHORITY_PATCH_SHA=inputs[patch])
    command = ['ruby', '-EUTF-8:UTF-8', PATHS[0 if args.suite == 'writer' else 1]]
    timed_out = False
    started = time.monotonic()
    with (output / 'stdout').open('xb') as out, (output / 'stderr').open('xb') as err:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=out,
                                   stderr=err, start_new_session=True)
        try:
            process.wait(timeout=300)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Only this recorder's newly created process group is controlled.
            # Always retain streamed logs and inspect real fixture restoration.
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
    after = fixture.snapshot()
    guard_error = None
    try:
        guard = fixture.guard(args.schema_version, latest)
    except Exception as error:
        guard = None
        guard_error = str(error)
    fixture.save(output / 'after.json', after)
    final_inputs = {p: sha(ROOT / p) for p in paths}
    case_file = output / 'concurrency-checkpoint.json'
    cases = json.loads(case_file.read_text()) if case_file.exists() else {}
    observed_cases = cases.get('cases_passed' if args.suite == 'writer' else 'cases_observed', 0)
    blocking_races = sum(bool(c.get('blocking')) for c in cases.get('cases', []))
    expected_cases = 5 if args.suite == 'writer' else (2 if args.read_kind == 'admin_notification' else 6)
    expected_races = 4 if args.suite == 'writer' else (0 if args.read_kind == 'admin_notification' else 6)
    passed = (not timed_out and guard is not None and process.returncode == 0
              and before == after and inputs == final_inputs
              and cases.get('status') == 'pass' and observed_cases == expected_cases
              and blocking_races == expected_races
              and cases.get('worker_sessions_remaining') == 0)
    if args.read_kind == 'admin_notification':
        passed = passed and cases.get('positive_authority_controls_passed') == 2
    result = {'status': 'pass' if passed else 'fail', 'command': command,
              'suite': args.suite, 'installed_schema_count': args.schema_version, 'timed_out': timed_out, 'elapsed_seconds': time.monotonic() - started,
              'authority_read_kind': args.read_kind,
              'correction_rehearsed_inside_rolled_back_read_transactions': args.rehearse_runtime_authority_correction,
              'correction_installed': args.schema_version == 153,
              'return_code': process.returncode, 'actual_cases': observed_cases,
              'actual_blocking_races': blocking_races,
              'all_table_catalog_cron_fingerprints_restored': before == after,
              'table_count': len(after['tables']), 'guard': guard, 'guard_error': guard_error,
              'source_before': inputs, 'source_after': final_inputs,
              'source_unchanged': inputs == final_inputs,
              'stdout_sha256': sha(output / 'stdout'),
              'stderr_sha256': sha(output / 'stderr'),
              'case_checkpoint_sha256': sha(case_file) if case_file.exists() else None,
              'provider_called': False, 'hosted_called': False,
              'sequences_restored': False,
              'scope': ('Two actual public Admin notification RPC positive controls and established Repeatable Read probes after committed role/Auth revocation; no blocking-race claim'
                        if args.read_kind == 'admin_notification' else 'Actual ordinary-owner/service RPC telemetry writer races and attribution-controlled committed cleanup'
                        if args.suite == 'writer' else 'Actual installed ' + args.read_kind + ' reads with gated access and Auth revocation in both orders and established Repeatable Read snapshots') + '; not final whole-system acceptance'}
    fixture.save(output / 'validation.json', result)
    print(json.dumps({k: result[k] for k in ['status', 'actual_cases', 'actual_blocking_races', 'all_table_catalog_cron_fingerprints_restored', 'source_unchanged']}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
