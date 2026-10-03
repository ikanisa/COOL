#!/usr/bin/env python3
"""Reconcile local acceptance without changing the original production criteria."""
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from bind_evidence import ROOT, HERE, RAPID, read, emit, digest

RELEASE = ROOT / 'docs/release'
NAMES = ['local-implementation-register-2026-09-30.json',
         'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md',
         'production-remaining-tasks-2026-09-30.json',
         'PRODUCTION_REMAINING_TASKS_2026-09-30.md',
         'production-remaining-tasks-2026-09-30.validation.json']


def main():
    packet = read(HERE / 'evidence-binding.json')
    assert packet['status'] == 'pass', 'Final declared candidate/evidence binding must pass before closure.'
    assert packet['accepted_candidate_readback']['status'] == 'pass'
    assert read(HERE / 'admin-inventory/validation.json')['status'] == 'pass'
    native = read(ROOT / packet['evidence']['native_terminal']['path'])
    assert native['status'] == 'pass'
    native_current = read(ROOT / packet['evidence']['final_gateway_full_tests']['path'])
    assert native_current['status'] == 'pass' and native_current['both_full_suites_executed_against_final_six_file_derivative']
    assert packet['current_Admin_route_action_criterion_met_in_declared_local_scope']
    backup = HERE / 'prior-registers'
    backup.mkdir(exist_ok=False)
    previous_hashes = {}
    for name in NAMES:
        shutil.copy2(RELEASE / name, backup / name)
        previous_hashes[name] = digest(backup / name)
        assert previous_hashes[name] == digest(RELEASE / name)
    local = read(backup / NAMES[0])
    production = read(backup / NAMES[2])
    previous_validation = read(backup / NAMES[4])
    local_criteria = [(row['id'], row['local_acceptance']) for row in local['items']]
    production_criteria = [(row['id'], row['original_acceptance'], row['open'], row['priority'], row['evidence_status']) for row in production['items']]
    ledger = read(RAPID / 'requested-task-evidence-ledger1/ledger.json')
    requested = {row['id']: row for row in ledger['items']}
    assert len(requested) == 18
    now = datetime.now(timezone.utc).isoformat()
    binding_path = str((HERE / 'evidence-binding.json').relative_to(ROOT))
    binding_sha = digest(HERE / 'evidence-binding.json')
    evidence_rows = list(packet['evidence'].values())
    for row in local['items']:
        if row['id'] not in requested:
            assert row['status'] == 'complete', 'An unrequested original local item was not complete.'
            continue
        criterion = requested[row['id']]
        assert row['local_acceptance'] == criterion['exact_local_acceptance']
        row['previous_verification'] = {key: row[key] for key in ['status', 'verified_progress', 'evidence_limit'] if key in row}
        row['status'] = 'complete'
        row['completed_at_utc'] = now
        row['completion_manifest_sha256'] = binding_sha
        row['completion_evidence'] = sorted(set(row.get('completion_evidence', []) + [binding_path,
            'docs/release/rapid-completion-2026-10-01/requested-task-evidence-ledger1/ledger.json']))
        row['verified_progress'] = criterion['covered_criteria'] + ' Final matching consumer source, named-case union, builds and supplemental fixtures are bound in the final immutable candidate packet.'
        row['completion_scope'] = 'Tested immutable candidate captured2026-10-01T14:35Z; later concurrent mutable-checkout edits are excluded and remain unaccepted.'
        row['evidence_limit'] = 'Local criterion only; no hosted/provider/device/signing/store/owner approval or100 percent design fidelity acceptance.'
        if 'privacy_acceptance' in row:
            row['privacy_acceptance'] = 'Reference-only browser storage, expired/departed session rejection and private checkpoint scrub accepted within the declared final candidate and browser inputs.'
    local['previous_latest_verified_local_result'] = local['latest_verified_local_result']
    local['captured_at_utc'] = now
    local['snapshot_revision'] += 1
    local['source_migration_count'] = packet['source_migrations']
    extra_versions = ['20261001110000', '20261001120000', '20261001130000', '20261001140000',
                      '20261001150000', '20261001160000', '20261001170000', '20261001180000']
    local['staged_source_migrations'] = sorted(set(local['staged_source_migrations'] + extra_versions))
    assert local['source_migration_count'] - len(local['staged_source_migrations']) == local['current_local_migration_count'] == 154
    local['locally_closed_goal_items'] = [row['id'] for row in local['items'] if row['status'] == 'complete']
    assert len(local['locally_closed_goal_items']) == 24
    local['local_open_items'] = []
    local['acceptance_candidate'] = {'manifest_sha256': packet['candidate_manifest_sha256'], 'source': packet['source_export'],
                                   'capture': '2026-10-01T14:35Z', 'supplement': packet['evidence']['source_supplement'],
                                   'approval': 'unapproved; no production-release acceptance'}
    local['latest_verified_local_result'] = {'scope': 'All24 original local criteria complete against the declared tested immutable candidate; later concurrent edits are not accepted.',
         'whole_goal_complete': True, 'whole_mutable_checkout_accepted': False, 'source_migration_count': 185,
         'retained_shared_installed_migration_count': 154, 'retained_shared_table_count': 153,
         'clean_and_populated_migration_applications': 370, 'counts': packet['acceptance_counts'],
         'manifest': binding_path, 'manifest_sha256': binding_sha, 'evidence_packets': evidence_rows,
         'later_live_source_readback': packet['evidence']['live_source_readback']}
    assert local_criteria == [(row['id'], row['local_acceptance']) for row in local['items']]
    emit(RELEASE / NAMES[0], local)
    local_md = ['# Collect local implementation register', '', f'Captured: {now}. Revision{local["snapshot_revision"]}.', '',
                '**24 of24 local criteria complete against the tested immutable candidate;0 local items remain in this accepted scope.**', '',
                '**Later concurrent changes in the live checkout remain unverified. Production release remains NO-GO.**', '',
                f'Accepted source: `{packet["candidate_manifest_sha256"]}`;2,117 files plus371 explicitly selected reproduction files.185 source migrations;370 clean/populated ordinary-installer applications. The retained shared fixture remains154 migrations/153 tables with31 source versions staged.', '',
                f'[Final acceptance packet](rapid-completion-2026-10-01/final-candidate-current1/evidence-binding.json). All original local and production criteria and prior failures are preserved.', '',
                '| ID | Task | Status | Verified local result |', '| --- | --- | --- | --- |']
    for row in local['items']:
        local_md.append(f'| {row["id"]} | {row["title"]} | {row["status"]} | {row["verified_progress"].replace("|", "\\|")} |')
    local_md += ['', '## Original local acceptance criteria', '']
    for row in local['items']:
        local_md += [f'### {row["id"]} — {row["title"]}', '', row['local_acceptance'], '']
    (RELEASE / NAMES[1]).write_text('\n'.join(local_md))
    production['supersedes_captured_at_utc'] = production['captured_at_utc']
    production['captured_at_utc'] = now
    production['snapshot_revision'] += 1
    production['local_progress_refreshed_at_utc'] = now
    production['source_migration_count'] = 185
    production['staged_source_migrations'] = local['staged_source_migrations']
    production['staged_source_versions'] = local['staged_source_migrations']
    production['current_local_goal_closed_ids'] = local['locally_closed_goal_items']
    production['local_progress_readback'] = binding_path
    production['local_progress_note'] = 'All24 original local criteria complete on the declared tested immutable2117-file candidate and371-file reproduction supplement.185 source migrations,370 ordinary clean/populated applications; retained shared fixture154/153 with31 staged. Later concurrent live changes are explicitly unaccepted. Original101 production checks remain open; external state was not refreshed.'
    production['current_local_scoped_packets'] = evidence_rows
    production['accepted_local_candidate'] = local['acceptance_candidate']
    production['previous_in_progress'] = production['in_progress']
    production['in_progress'] = {'ids': [], 'work': 'Requested local implementation work is complete within the accepted immutable candidate. Later concurrent development belongs to the live checkout and requires separate acceptance.'}
    production['previous_immediate_engineering_subtasks'] = production['immediate_engineering_subtasks']
    production['immediate_engineering_subtasks'] = [{'parent_ids': ['Q01', 'Q03', 'O01'], 'work': 'Choose an approved source set for release; later concurrent edits have no acceptance in this final local packet.'},
        {'parent_ids': ['O01', 'S08', 'F03', 'F10'], 'work': 'Retain approved hosted rollout, actual provider/device/role evidence and release authority against the selected source set.'},
        {'parent_ids': ['U01', 'Q03', 'X01'], 'work': 'Complete applicable external comparator, device, interaction and owner review on the exact release artifacts.'}]
    production['release_decision'] = 'NO-GO'
    production['frozen_candidate'] = False
    production['full_current_source_acceptance'] = False
    production['declared_immutable_local_candidate_acceptance'] = True
    production['external_state_refreshed_for_this_report'] = False
    for row in production['items']:
        local_ids = [item['id'] for item in local['items'] if row['id'] in item['parent_ids'].split('/')]
        if local_ids:
            row['scoped_local_implementation'] = {'local_ids': local_ids, 'status': 'complete_against_declared_candidate', 'manifest': binding_path, 'sha256': binding_sha}
    assert production_criteria == [(row['id'], row['original_acceptance'], row['open'], row['priority'], row['evidence_status']) for row in production['items']]
    assert sum(row['open'] for row in production['items']) == production['open_acceptance_checks'] == 101
    emit(RELEASE / NAMES[2], production)
    old_md = (backup / NAMES[3]).read_text()
    preserved_tables = old_md[old_md.index('## G — Source and governance'):]
    prod_md = ['# Collect — remaining production acceptance', '', f'**Snapshot: {now}; revision{production["snapshot_revision"]}. Release decision: NO-GO.**', '',
       '**101 original production checks remain open. All24 local implementation criteria are complete against the named immutable candidate.**', '',
       'The original production table and acceptance wording below are retained. Its source observations are dated; local implementation completion is recorded separately by parent ID in the JSON register. No external acceptance or owner approval is inferred.', '',
       production['local_progress_note'], '', '[Final local evidence](rapid-completion-2026-10-01/final-candidate-current1/evidence-binding.json). [Local criteria](LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md).', '', preserved_tables]
    (RELEASE / NAMES[3]).write_text('\n'.join(prod_md))
    validation = {'status': 'pass', 'validated_at_utc': now, 'scope': 'Criteria-preserving local reconciliation against a declared immutable candidate; no current live-checkout or external-state acceptance.',
      'snapshot_revision': production['snapshot_revision'], 'local_snapshot_revision': local['snapshot_revision'],
      'sha256': {name: digest(RELEASE / name) for name in NAMES[:4]}, 'prior_revision_preserved': previous_hashes,
      'all_original_ids_preserved': True, 'original_criteria_preserved': True, 'local_criteria_preserved': True,
      'unique_open_rows': 101, 'closed_ids': ['G06'], 'local_goal_closed_ids': local['locally_closed_goal_items'],
      'priority_counts': production['open_by_priority'], 'source_migration_count': 185, 'installed_migration_count': 154,
      'installed_table_count': 153, 'staged_source_versions': local['staged_source_migrations'],
      'ordinary_current_clean_and_populated_verified': True, 'latest_ordinary_local_ddl_replay': 185,
      'latest_ordinary_local_ddl_replay_sha256': packet['evidence']['ordinary185']['sha256'],
      'full_current_source_acceptance': False, 'declared_immutable_local_candidate_acceptance': True,
      'final_candidate_manifest_sha256': packet['candidate_manifest_sha256'], 'final_evidence_sha256': binding_sha,
      'external_state_refreshed': False, 'production_release_accepted': False}
    emit(RELEASE / NAMES[4], validation)
    emit(HERE / 'register-reconciliation.json', validation)
    print(json.dumps({'status': 'pass', 'local_complete': 24, 'local_open': 0,
                      'requested_complete': 18, 'production_open': 101, 'production_decision': 'NO-GO',
                      'local_revision': local['snapshot_revision'], 'production_revision': production['snapshot_revision']}))


if __name__ == '__main__':
    main()
