#!/usr/bin/env python3
"""Seal the finite full208 installer evidence without rerunning any target."""
import datetime
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OWNED = Path(__file__).resolve().parent

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(name, value):
    (OWNED / name).write_text(json.dumps(value, indent=2) + '\n')

def main():
    assert not (OWNED / 'MANIFEST.json').exists(), 'Preserve any existing seal'
    final = json.loads((OWNED / 'full208-attempt3/result.json').read_text())
    prior = json.loads((ROOT / 'docs/release/rapid-completion-2026-10-02/ordinary-current201-attempt1/result.json').read_text())
    launch = json.loads((OWNED / 'full208-attempt3-launch/receipt.json').read_text())
    freeze = json.loads((OWNED / 'full208-attempt3/root-frozen-inventory.json').read_text())
    expected = {r['path']: r['sha256'] for r in freeze['source_inventory']}
    current = {str(p.relative_to(ROOT)): digest(p) for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
    assert current == expected and len(current) == 208
    assert final['status'] == 'pass' and len(final['cases']) == 50 and launch['exit_code'] == 0
    assert launch['tools_and_sources_unchanged'] and launch['migration_sources_unchanged']
    assert all(digest(Path(n)) == h for n, h in launch['tools_and_sources_after'].items())
    final_names = {c['name'] for c in final['cases']}
    assert len(prior['cases']) == 36 and {c['name'] for c in prior['cases']} <= final_names
    assert all(c['status'] == 'pass' for c in final['cases'])
    assert len(final['preserved_columns']) == 18 and len(final['config_columns']) == 7
    assert final['all_task_containers_removed']
    applications = 0
    query_counts = {}
    for phase, outcome in final['phases'].items():
        rows = outcome['migrations']
        assert len(rows) == 208 and all(r['status'] == 'pass' for r in rows)
        assert [r['path'] for r in rows] == [r['path'] for r in freeze['source_inventory']]
        assert all(r['actual_installer_authority']['superuser'] is False and
                   r['actual_installer_authority']['current_user'] == 'postgres' and
                   r['actual_installer_authority']['current_role'] == 'postgres' for r in rows)
        assert outcome['status'] == 'pass' and outcome['task_container_removed'] and outcome['target_absence_verified']
        assert outcome['scheduler_readback'] == {'cron': 'off', 'net': '0', 'history': 0}
        assert outcome['guard']['network'] == 'none' and outcome['guard']['published_ports'] is False
        assert outcome['actual_pgdata_mount'] == {'path': '/var/lib/postgresql/collect-rehearsal',
            'docker_tmpfs_options': 'rw,size=1073741824', 'actual_filesystem_type': 'tmpfs'}
        applications += len(rows)
        records = []
        for line in (OWNED / 'full208-attempt3' / ('ordinary_' + phase) / 'queries.log').read_text().splitlines():
            if not line.startswith('{'): continue
            try: row = json.loads(line)
            except json.JSONDecodeError: continue
            if isinstance(row, dict) and set(row) == {'label', 'sql_sha256', 'exit_code'}:
                records.append(row)
        query_counts[phase] = {'actual_recorded_SQL_calls': len(records),
                               'nonzero_exit_codes': [r for r in records if r['exit_code'] != 0]}
    populated = final['phases']['populated']['migrations']
    protected_steps = [r for r in populated if r.get('canonical_predecessor_preserved')]
    assert len(protected_steps) == 84
    assert all(set(r['configuration_before']) == set(final['config_columns']) and
               set(r['configuration_after']) == set(final['config_columns']) for r in protected_steps)
    observations = json.loads((OWNED / 'full208-attempt3/ordinary_populated/combined-current-reader-observations.json').read_text())
    denial = observations['absent-approval-execution-v4']
    assert denial['result_kind'] == 'denied' and denial['sqlstate'] == '42501'
    assert denial['error_message'] == 'receipt_action_current_email_owner_required'
    assert denial['unchanged_fixture_email_identity'] == 'f' and denial['rpc_response'] is None
    assert not denial['unavailable_response_claimed'] and not denial['not_materialized_claimed']
    targets = json.loads((OWNED / 'final-target-absence.json').read_text())
    assert len(targets) == 5 and all(r['exit_code'] == 0 and r['absence_stdout'] == '' for r in targets)
    receipts = {
        'attempt1': {'session_id': 79227, 'initial_chunk': 'a8d76b', 'terminal_chunk': 'e20ee0', 'exit_code': 1,
            'applications': 0, 'checks_passed': 0, 'failure': 'private inspector used .Mounts for --tmpfs', 'targets_removed': 1},
        'attempt2': {'session_id': 61269, 'initial_chunk': 'f02496', 'terminal_chunk': '227db5', 'exit_code': 1,
            'applications': 416, 'checks_passed': 43, 'failure': 'private seam expected unavailable from unchanged phone fixture; actual email-owner denial', 'targets_removed': 2},
        'attempt3': {'session_id': 49970, 'initial_chunk': '2b2c6f', 'terminal_chunk': 'f6c207', 'exit_code': 0,
            'applications': 416, 'checks_passed': 50, 'targets_removed': 2},
        'not_a_combined_aggregate': True,
    }
    for i in range(1, 4):
        attempt = json.loads((OWNED / f'full208-attempt{i}/result.json').read_text())
        outer = json.loads((OWNED / f'full208-attempt{i}-launch/receipt.json').read_text())
        assert sum(len(o.get('migrations', [])) for o in attempt['phases'].values()) == receipts[f'attempt{i}']['applications']
        assert len(attempt['cases']) == receipts[f'attempt{i}']['checks_passed']
        assert outer['exit_code'] == receipts[f'attempt{i}']['exit_code']
        assert outer['tools_and_sources_unchanged'] and outer['migration_sources_unchanged']
        assert attempt['all_task_containers_removed']
    write('TERMINAL_RECEIPTS.json', receipts)
    config_changes = [{'path': r['path'], 'tables': r['configuration_changed_tables']}
                      for r in protected_steps if r['configuration_changed_tables']]
    verification = {
        'status': 'pass', 'scope': 'Frozen full migration installation candidate; no final product/artifact release freeze',
        'root_inventory_sha256': 'd5747f242b224c05be86096e98de8bd9bbf908f9b502765162359778ed4b2cf8',
        'frozen_migration_count': 208, 'successful_final_applications': applications,
        'final_checks': 50, 'original_current201_check_names_reused_and_passed': 36,
        'new_tmpfs_and_finite_reader_checks': 14, 'protected_projection_count': 18,
        'post124_migrations_with_before_after_protection': 84,
        'configuration_projection_count': 7, 'configuration_changed_migrations': config_changes,
        'actual_recorded_SQL_calls': query_counts,
        'final_source_readback': current, 'tool_helper_source_readback': launch['tools_and_sources_after'],
        'entire_frozen_source_graph_unchanged': True,
        'platform_scope': final['platform_bootstrap'],
        'ordinary_installer': final['phases']['populated']['ordinary_installer'],
        'inherited_roles': final['phases']['populated']['installer_inherited_roles'],
        'role_limitations': 'NOSUPERUSER application installation after explicit privileged platform bootstrap; CREATEDB, CREATEROLE, BYPASSRLS and retained trusted image role memberships remain. Managed hosted parity is not proved.',
        'fixture_facts': final['combined_reader_fixture_facts'], 'v4_actual_result': final['absent_approval_probe'],
        'original_fixture_not_mutated_to_email_owner': True,
        'all_five_attempt_targets_independently_absent': True,
        'canonical_product_defects_observed_in_scope': [],
        'API_native_UI_baselines_reexecuted': False, 'hosted_provider_device_calls': False,
        'source_rows_or_credentials_copied': False,
    }
    write('VERIFICATION.json', verification)
    handoff = '''# Frozen full208 ordinary installer rehearsal

Final attempt3 passed:208 migrations on each fresh clean/populated target,416 actual applications and50 checks. All36 original ordinary-current201 check names are present. The14 additional checks cover two actual tmpfs readbacks and the finite current authenticated read seam. This is a migration installation candidate, not a final product/artifact or release freeze.

Root freeze d5747f242b224c05be86096e98de8bd9bbf908f9b502765162359778ed4b2cf8 and every208 canonical source hash matched before and after. Exact ordinary UAT/helper/platform bytes and Python/Docker binaries are unchanged. The cached PG17.6 image identity is35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a. Each target is network-none, has no ports, keeps PGDATA on declared1GiB tmpfs and reads backcronoff/net0/history0. All five targets from three attempts were removed and their exact names independently verified absent.

The populated phase uses the unchanged124-version synthetic predecessor. All18 declared financial/receipt/Auth/approval column projections are preserved before/after each84 later migration and after final reads. All seven original configuration vectors are recorded at every step. Intentional differences occur at Rwanda scope and two Admin navigation migrations; exact before/after vectors and changed table names are retained in the result. This proves these declared projections, not all hosted data.

The read seam uses the existing fixture and claims only actual states: empty operational starts; unavailable evidence for an existing transaction UUID explicitly absent as a run; inactive worker health with incomplete observation. An absent approval is only a query UUID, never inserted or treated as a primary receipt. The unchanged phone fixture has email_identity=false, so v4 correctly refuses inspection withSQL42501 receipt_action_current_email_owner_required. Raw code/message/output are retained; no unavailable/not_materialized RPC response is manufactured. All18 financial/Auth/receipt/approval projections are rechecked after that denial.

Attempt1 is a failed command with zero application migrations: the private guard inspected Docker.Mounts rather than HostConfig.Tmpfs. Its exact driver, sources, error and cleanup are retained. Attempt2 is a failed command with416 applications and43 passing checks: the private seam expected an unavailable v4 reply before accounting for the fixture's valid email-owner denial. Attempt3 changes only the tmpfs inspection/readback and the fixture-denial seam/selection; base-aware patches are retained. Failed results are never aggregated into final50 or rewritten as successes.

The application installer is actually postgresNOSUPERUSER before migration1 and before/after every application. Explicit platform setup is privileged. CREATEDB/CREATEROLE/BYPASSRLS and trusted inherited image roles remain, and Auth/Storage is a retained schema-only prelude with synthetic claims. No hosted/provider/device, signed-JWT, managed owner parity or release acceptance is claimed. No operational principal/run, successor approval, carrier send or financial fixture was added. Existing scoped600/700/800/430/440 API/DTO/native/UI evidence is reused by exact installed source identity; no unrelated API/native/UI baseline was repeated. Root's current mounted Admin/native checks remain separate evidence.

Use MANIFEST.json/SEAL.json for the finite packet, VERIFICATION.json for exact current readback/config/authority facts, TERMINAL_RECEIPTS.json for actual sessions/statuses, and full208-attempt3/result.json plus each phase'squeries.sql/queries.log for actual calls. The earlier PLAN/PRIOR_BINDINGS files remain historical pre-freeze preparation evidence. Root alone owns canonical/docs promotion. No canonical/shared source was edited.
'''
    (OWNED / 'HANDOFF.md').write_text(handoff)
    members = {}
    total = 0
    for path in sorted(OWNED.rglob('*')):
        if path.is_symlink(): raise RuntimeError('Unexpected packet symlink: ' + str(path))
        if not path.is_file() or path.name in {'MANIFEST.json', 'SEAL.json'}: continue
        members[str(path.relative_to(OWNED))] = digest(path)
        total += path.stat().st_size
    write('MANIFEST.json', {'members': members})
    for name, h in members.items(): assert digest(OWNED / name) == h
    write('SEAL.json', {'manifest_sha256': digest(OWNED / 'MANIFEST.json'),
        'member_count': len(members), 'total_member_bytes': total,
        'verification_sha256': digest(OWNED / 'VERIFICATION.json'),
        'terminal_receipts_sha256': digest(OWNED / 'TERMINAL_RECEIPTS.json'),
        'final_result_sha256': digest(OWNED / 'full208-attempt3/result.json'),
        'final_driver_sha256': digest(OWNED / 'full_candidate_ordinary_rehearsal_attempt3.py'),
        'final_reader_sha256': digest(OWNED / 'combined_reader_seam_attempt3.py'),
        'root_frozen_inventory_sha256': verification['root_inventory_sha256'],
        'all_five_attempt_targets_absent': True,
        'sealed_at': datetime.datetime.now(datetime.timezone.utc).isoformat()})
    print((OWNED / 'SEAL.json').read_text())

if __name__ == '__main__':
    main()
