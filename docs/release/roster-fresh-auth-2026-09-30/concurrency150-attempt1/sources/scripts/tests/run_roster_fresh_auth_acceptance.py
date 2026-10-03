"""Run the complete reviewed roster races on the exact offline150 fixture."""
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
HARNESS = 'scripts/tests/roster_fresh_auth_concurrency_uat.rb'
MIGRATION149 = 'supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql'
MIGRATION150 = 'supabase/migrations/20260930180000_operational_health_authority.sql'
REVIEWED = {
    MIGRATION149: '53e5591e5901acc345101c5113a0c75b7b993011b5743119a59f52c883ceb00d',
    MIGRATION150: 'd81f9bf124ff51dc33579fdf6b59e55229eb3e152c87528a8e372fc491ab0747',
}
PATHS = [HARNESS, MIGRATION149, MIGRATION150,
         'scripts/tests/run_roster_fresh_auth_acceptance.py',
         'scripts/tests/local_offline_verification.py',
         'scripts/tests/notification_upgrade_telemetry.py']
EXPECTED = [
    'exact_request_replay_waits_for_one_branch',
    'response_loss_status_and_distinct_request_old_leaf_denial',
]
for operation in ['checkpoint', 'review', 'stage', 'execute', 'commit']:
    EXPECTED.extend([f'transfer_wins_old_{operation}_denied',
                     f'old_{operation}_wins_stale_transfer_denied'])
for operation in ['preview', 'resources']:
    EXPECTED.extend([f'transfer_wins_original_service_{operation}_replay_denied',
                     f'original_service_{operation}_replay_wins_before_transfer'])
EXPECTED.append('old_session_deleted_fresh_transfer_review_explicit_commit')
AUTHORITIES = ['current_session', 'approval', 'role', 'moderate_permission', 'read_permission']
EXPECTED.extend(f'repeatable_read_{authority}_revocation_wins' for authority in AUTHORITIES)
EXPECTED.extend(f'transfer_wins_before_{authority}_revocation' for authority in AUTHORITIES)
EXPECTED.extend([
    'feature_revocation_wins_transfer', 'transfer_wins_before_feature_revocation',
    'JWT_deadline_crosses_blocked_transfer', 'source_deadline_crosses_blocked_transfer',
    'A_B_C_lineage_and_eight_handoff_ceiling', 'nineteen_human_reviews_across_lineage',
    'forty_staged_intents_across_lineage',
    'repeatable_read_distinct_import_actor_draft_quota',
    'repeatable_read_distinct_request_actor_source_quota',
])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'docs/release'):
        parser.error('Fresh repository release output required')
    inputs = {path: sha(ROOT / path) for path in PATHS}
    if any(inputs[path] != digest for path, digest in REVIEWED.items()):
        parser.error('Previously reviewed installed migration source changed')
    spec = importlib.util.spec_from_file_location('fixture', ROOT / PATHS[-2])
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    before = fixture.prepare(output, 150, '20260930180000')
    for path in PATHS:
        target = output / 'sources' / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / path).read_bytes())
    if inputs != {path: sha(ROOT / path) for path in PATHS}:
        raise RuntimeError('Reviewed inputs changed before execution; no races started')
    fixture.save(output / 'reviewed-inputs.json', inputs)
    env = os.environ.copy()
    env.update(COLLECT_ROSTER_PROVENANCE_QA='isolated_clone',
               COLLECT_ROSTER_CHECKPOINT=str(output / 'concurrency-checkpoint.json'),
               COLLECT_ROSTER_FRESH_AUTH_MIGRATION_SHA=inputs[MIGRATION149],
               COLLECT_ROSTER_AUTHORITY_MIGRATION_SHA=inputs[MIGRATION150])
    command = ['ruby', '-EUTF-8:UTF-8', HARNESS]
    started = time.monotonic()
    timed_out = False
    with (output / 'stdout').open('xb') as out, (output / 'stderr').open('xb') as err:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=out,
                                   stderr=err, start_new_session=True)
        fixture.save(output / 'execution.json', dict(status='running', pid=process.pid,
                                                     command=command, source=inputs))
        try:
            process.wait(timeout=600)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
    fixture.save(output / 'execution.json', dict(status='terminal', pid=process.pid,
                                                 command=command, return_code=process.returncode,
                                                 timed_out=timed_out))
    after = None
    guard = None
    readback_error = None
    try:
        after = fixture.snapshot()
        guard = fixture.guard(150, '20260930180000')
    except Exception as error:
        readback_error = str(error)
    fixture.save(output / 'after.json', after)
    final_inputs = {path: sha(ROOT / path) for path in PATHS}
    checkpoint_file = output / 'concurrency-checkpoint.json'
    checkpoint = json.loads(checkpoint_file.read_text()) if checkpoint_file.exists() else {}
    result = checkpoint.get('result') or checkpoint.get('scenario_result') or {}
    scenarios = result.get('scenarios', [])
    names = [case.get('scenario') for case in scenarios]
    blocking = [case for case in scenarios if case.get('lock_wait')]
    overlaps_valid = all(case['lock_wait'].get('wait_type') == 'Lock'
                         and case['lock_wait'].get('blocking_pids') for case in blocking)
    passed = (process.returncode == 0 and not timed_out and readback_error is None
              and checkpoint.get('phase') == 'complete' and result.get('status') == 'pass'
              and names == EXPECTED and len(blocking) == 31 and overlaps_valid
              and result.get('financial_rows_unchanged') is True
              and result.get('synthetic_graph_removed') is True
              and result.get('worker_sessions_remaining') == 0
              and before == after and inputs == final_inputs
              and result.get('source_sha256') == inputs[HARNESS]
              and result.get('migration_sha256') == inputs[MIGRATION149]
              and result.get('authority_migration_sha256') == inputs[MIGRATION150])
    validation = dict(status='pass' if passed else 'fail', command=command,
                      return_code=process.returncode, timed_out=timed_out,
                      elapsed_seconds=time.monotonic() - started,
                      expected_scenarios=EXPECTED, actual_scenarios=names,
                      actual_blocking_races=len(blocking), overlapping_waits_verified=overlaps_valid,
                      all_table_catalog_cron_fingerprints_restored=before == after,
                      table_count=len(after['tables']) if after else None,
                      source_before=inputs, source_after=final_inputs,
                      source_unchanged=inputs == final_inputs, guard=guard,
                      readback_error=readback_error,
                      stdout_sha256=sha(output / 'stdout'), stderr_sha256=sha(output / 'stderr'),
                      checkpoint_sha256=sha(checkpoint_file) if checkpoint_file.exists() else None,
                      hosted_called=False, provider_called=False, sequences_restored=False,
                      scope='Complete149 fresh Auth/lineage/quota race harness on installed150; ordinary-owner synthetic fixture only; not whole-system acceptance')
    fixture.save(output / 'validation.json', validation)
    print(json.dumps({key: validation[key] for key in [
        'status', 'actual_scenarios', 'actual_blocking_races',
        'all_table_catalog_cron_fingerprints_restored', 'source_unchanged', 'readback_error']}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
