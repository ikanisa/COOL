"""Root-only revision refresh; preserve every original local/production criterion."""
import collections
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = Path(__file__).resolve().parent
RELEASE = ROOT / 'docs/release'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def read(path):
    return json.loads(path.read_text())


def main():
    preserved = read(BASE / 'prior-registers/preservation.json')
    for name, expected in preserved.items():
        assert sha(BASE / 'prior-registers' / name) == expected
        assert sha(RELEASE / name) == expected, 'Unexpected concurrent register change'
    local = read(RELEASE / 'local-implementation-register-2026-09-30.json')
    production = read(RELEASE / 'production-remaining-tasks-2026-09-30.json')
    local_before = {r['id']: r['local_acceptance'] for r in local['items']}
    prod_before = {r['id']: r['original_acceptance'] for r in production['items']}
    assert len(local_before) == 24 and len(prod_before) == 102
    assert local['snapshot_revision'] == 4 and production['snapshot_revision'] == 6
    spec = importlib.util.spec_from_file_location('fixture', ROOT / 'scripts/tests/local_offline_verification.py')
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    guard = fixture.guard(148, '20260930160000')
    state = fixture.snapshot()
    assert len(state['tables']) == 146
    assert state == read(BASE / 'local-readback.json')['snapshot']
    installed = json.loads(fixture.FIXTURE.sql("select jsonb_agg(version order by version) from supabase_migrations.schema_migrations;"))
    registry_hashes = json.loads(fixture.FIXTURE.sql("select jsonb_object_agg(version,encode(extensions.digest(statements[1],'sha256'),'hex')) from supabase_migrations.schema_migrations where version in ('20260930150000','20260930160000');"))
    sql_governance = read(RELEASE / 'runtime-controls-2026-09-30/sql-runtime-acceptance-attempt1/validation.json')
    assert registry_hashes == sql_governance['current_registry_source_sha256']
    assert sql_governance['status'] == 'pass' and sql_governance['uat_assertions'] == 110
    assert sql_governance['actual_blocking_races'] == 11
    migrations = {p.name[:14]: p for p in sorted((ROOT / 'supabase/migrations').glob('*.sql'))}
    for version, expected in registry_hashes.items():
        assert sha(migrations[version]) == expected
    staged = sorted(set(migrations) - set(installed))
    assert set(installed) <= set(migrations)
    retained = read(RELEASE / 'hosted-readback-2026-09-30/migrations.json')['migrations']
    hosted_versions = {str(r['version']) for r in retained}
    assert len(hosted_versions) == 124
    absent = sorted(set(migrations) - hosted_versions)
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    packet_paths = [
        'runtime-controls-2026-09-30/sql-runtime-acceptance-attempt1/validation.json',
        'runtime-controls-2026-09-30/client-runtime-attempt2/validation.json',
        'runtime-controls-2026-09-30/notification-ui-runtime-attempt2/validation.json',
        'financial-observability-2026-09-30/install148-normal-owner-attempt1/result.json',
        'financial-observability-2026-09-30/uat148-installed-rollback-attempt1/result.json',
        'financial-observability-2026-09-30/http-frozen-attempt1/report.json',
        'financial-observability-2026-09-30/unit-frozen-attempt1/validation.json',
        'financial-observability-2026-09-30/health-ui-attempt2/validation.json',
        'admin-full-coverage-2026-09-30/sql-reads148-attempt3/result.json',
        'admin-full-coverage-2026-09-30/sql-reads148-attempt4-extended/result.json',
        'admin-full-coverage-2026-09-30/acceptance-attempt2/validation.json',
        'shared-ui-accessibility-2026-09-30/attempt6/browser-evidence/report.json',
        'asset-build-hygiene-2026-09-30/native-export-attempt18-ios/artifact-verification.json',
        'asset-build-hygiene-2026-09-30/wrapper-provenance-attempt16/checksum-verification.json',
        'asset-build-hygiene-2026-09-30/source-inventory-after-wrapper-attempt17/verification.json',
        'asset-build-hygiene-2026-09-30/local-fork-coverage-attempt19/verification.json',
    ]
    packets = [{'path': str((RELEASE / p).relative_to(ROOT)), 'sha256': sha(RELEASE / p)} for p in packet_paths]
    health = read(RELEASE / packet_paths[7]); assert health['status'] == 'pass' and health['test_count'] == 39 and health['source_unchanged']
    unit = read(RELEASE / packet_paths[6]); assert unit['status'] == 'pass' and unit['tests_passed'] == 309 and unit['source_unchanged']
    http = read(RELEASE / packet_paths[5]); assert http['status'] == 'pass' and len(http['runtime_result']['checks']) == 76
    for relative in packet_paths[8:10]:
        r = read(RELEASE / relative); assert r['status'] == 'pass' and r['unchanged'] and r['tables_after'] == 146
    compact = read(RELEASE / packet_paths[11]); assert compact['status'] == 'pass' and len(compact['cases']) == 25 and len(compact['checks']) == 205
    status_entries = subprocess.run(['git', 'status', '--porcelain', '-z'], cwd=ROOT,
                                    capture_output=True, check=True).stdout.count(b'\0')
    readback = {'captured_at_utc': now, 'identity': guard, 'table_count': 146,
                'snapshot': state, 'installed_versions': installed,
                'installed_147_148_source_sha256': registry_hashes,
                'source_migration_count': len(migrations), 'staged_source_versions': staged,
                'hosted_called': False, 'provider_called': False}
    save(BASE / 'current-readback.json', readback)
    updates = {
        'L01': 'Memory-only web Auth/PKCE and a bounded GoTrue broadcast fork are implemented; source149 fresh-sign-in lineage/CAS recovery is a draft, not installed. Scoped SDK tests are being extended; final normal Admin/browser storage, recovery and concurrency acceptance remain. The earlier persistent-token contradiction is preserved as dated evidence.',
        'L03': 'Six reproduced read/Auth/expiry defects corrected; retained focused gate has265 passing tests and14 clean analyzer inputs. Actual17 installed148 read receipts now exist. Current fork/support-state/action matrix and final-source session acceptance remain.',
        'L04': 'Strict actor/record/read contracts and scoped action ACK fixes implemented. Actual17 installed148 receipts available for DTO acceptance; full active-action request/ACK/session/audit matrix and final-source gate remain.',
        'L05': 'Inventory identifies24 routes,71 RPC/function symbols (55 active mappings,16 legacy/unrouted),19 providers and16 dialogs. Full state/permission/session/audit matrix and confirmed member-count/config/support-read corrections are underway.',
        'L07': 'Scoped Admin redaction and current frozen Edge HTTP/unit checks pass at their captures. Full client/Edge/log/export negative coverage and final-source binding remain.',
        'L16': 'Sticky session/read/expiry corrections and scoped SDK tests implemented. Full missed/duplicate-event, offline/reconnect/revocation/private-cache matrix and final-source acceptance remain.',
        'L17': 'Declared compact/shared correction is verified by120 widget tests,11 clean analyzer inputs and25 actual Chrome cases/205 assertions; 320x568 at1x/2x plus390x1x inspected. Prior-source whole-word negative reproduced. Remaining unsampled applicable local surface/state coverage and final integrated source bind remain.',
        'L18': 'Prior actual normal browser/PWA37-check/16-case packet remains dated. Current memory-only Auth/fork and149 recovery require new normal multi-tab/reload/offline/logout/current-artifact acceptance.',
        'L19': '148 installed with ordinary owner privileges:36 actual SQL assertions and complete146-table rollback. Current receipt integration passes76 actual frozen HTTP checks and309 Edge unit tests. Actual SQL-bound health UI passes39 tests/two clean analyzer inputs; expiry hides measurements/alerts/old scheduler and refresh is explicit. Response procedures documented; concurrency/performance/response rehearsal and final integration remain.',
        'L20': 'Corrected147 installed and source-bound:26 control families,110 actual SQL checks and11 blocking races. Retained client gate205 tests and notification recovery UI6 tests pass. Dynamic-control inventory, all consumer/audit coverage and current final integration remain.',
        'L21': '195/195 runtime Dart sources reachable at the retained capture; cleanup bytes remain, but current gotrue/Admin/health/native changes require final reachability/asset/dependency and seven Public media rebind. Earlier completion certificate remains historical.',
        'L22': 'Deno2.5.6 locked45 remote/5 npm closure, corruption denial,309 Edge units/76 HTTP checks verified. Exact Android Gradle wrapper checksum enforcement and dated unsigned Android/iOS builds pass; retained source inventory688 components. New local-fork collectors pass41 tests/43 assertions. Final source-bound formatter/analyzer/media/SBOM/native rebuild and substantive Firebase scene callback correction remain.',
        'L23': 'Exact quiet installed148 registry/146 tables and installed147/148 source hashes verified.149 exists as uninstalled draft. Last complete clean replay remains141; final clean/populated/compatibility/full-suite/concurrency/mutation acceptance remains.',
        'L24': 'Original five registers preserved with hashes; this refresh binds16 newer scoped evidence packets and a fresh full local readback. Every original24 local and102 production acceptance string is preserved. Final single-source evidence/hand-over still requires remaining implementation and integrated acceptance.',
    }
    for row in local['items']:
        if row['id'] in updates:
            row['verified_progress'] = updates[row['id']]
    l01 = next(r for r in local['items'] if r['id'] == 'L01')
    l01['privacy_acceptance'] = 'Not achieved: implementation corrected; full normal browser/storage/fresh-Auth recovery evidence pending.'
    l21 = next(r for r in local['items'] if r['id'] == 'L21')
    l21['historical_completion'] = {k: l21.pop(k) for k in ['completed_at_utc', 'completion_manifest_sha256']}
    local['historical_latest_verified_local_result'] = local['latest_verified_local_result']
    local['latest_verified_local_result'] = {'scope': 'Scoped current148 readback and retained147/148/client/Edge/browser/native packets; no whole-goal claim', 'readback': str((BASE / 'current-readback.json').relative_to(ROOT)), 'readback_sha256': sha(BASE / 'current-readback.json'), 'evidence_packets': packets, 'migration_count': 148, 'table_count': 146, 'whole_goal_complete': False}
    local.update(captured_at_utc=now, snapshot_revision=5, current_local_migration_count=148,
                 current_local_table_count=146, source_migration_count=len(migrations),
                 staged_source_migrations=staged)
    local_md = ['# Collect local implementation register', '', f'Captured: {now}. Revision5.', '',
                '**6 of24 local goals verified complete;18 remain open.** Original102 production criteria retain their acceptance scope.', '',
                'Installed local registry:148 migrations/146 tables. Source149 is an uninstalled draft. Final whole-source acceptance is pending.', '',
                '| ID | Task | Status | Remaining scope or verified result |', '| --- | --- | --- | --- |']
    for row in local['items']:
        text = row.get('verified_progress') or row.get('evidence_limit') or row['local_acceptance']
        local_md.append(f"| {row['id']} | {row['title']} | {row['status']} | {text.replace('|', '/')} |")
    local_md += ['', '## Original local acceptance criteria', '']
    for row in local['items']:
        local_md += [f"### {row['id']} — {row['title']}", '', row['local_acceptance'], '']
    (RELEASE / 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md').write_text('\n'.join(local_md))
    save(RELEASE / 'local-implementation-register-2026-09-30.json', local)
    prod_md = (RELEASE / 'PRODUCTION_REMAINING_TASKS_2026-09-30.md').read_text()
    body = prod_md[prod_md.index('## G — Source and governance:'):]
    prefix = f"""# Collect — exhaustive remaining production tasks

**Snapshot: 30 September2026 (Africa/Kigali), revision7. Release decision: NO-GO.**

**101 acceptance checks remain open:99 of100 original tasks, plus X01 and X02.** G06 is locally closed. This is an acceptance count; substantial implementation exists within open tasks. Crosscutting checks overlap other tasks.

| Priority | Open |
| --- | ---: |
| P0 |24|
| P1 |71|
| P2 |4|
| Crosscutting |2|
| **Total** |**101**|

Evidence states remain67 Partial,27 External,7 Unverified. No production criterion has been narrowed or closed by this local refresh.

Source: HEAD `{production['base_commit']}` plus{status_entries} captured working-tree entries at `{now}`. No release candidate is frozen. {len(migrations)} migration source files are present; the exact isolated registry has148 installed migrations and146 tables. Staged source versions: {', '.join(staged) or 'none'}. Last complete clean replay remains141.

## Latest verified local progress and limits

- **A08:** corrected147 is installed;26 governed control families,110 actual SQL checks and11 blocking races. Retained client205-test and notification recovery UI6-test packets pass; full current consumer/audit integration remains.
- **O06:**148 is installed;36 actual SQL assertions with146-table rollback equivalence. Current receipt telemetry has76 actual frozen loopback HTTP checks and309 Edge unit tests. Health UI has39 actual-SQL-bound contract/widget tests, clean analysis and explicit expiry/refresh. Response procedures are documented; full concurrency/performance/rehearsal acceptance remains.
- **S09/U06/P07:** retained read/Auth/expiry gate passes265 tests. Actual17 installed148 read receipts include routed details, nullable suppressed SMS, SLA and approval. Additional reproduced support/config/member-mapping corrections and full route/action matrix are underway.
- **U02/U04/U05:** scoped shared compact correction passes120 widget tests and25 actual Chrome cases/205 assertions, including1x/2x text, keyboard and meaningful prior-source failure. Full applicable surface/state coverage and final-source integration remain.
- **A01/P07/U08:** memory-only web Auth and a bounded local GoTrue fork are implemented.149 fresh-sign-in roster recovery is a draft; full normal browser/Auth/storage/recovery acceptance remains open. Prior SDK persistent-token failures are preserved.
- **Q01/Q02/Q07/A05:** reviewed Gradle wrapper provenance/checksum enforcement, dated unsigned Android/iOS artifacts and new local-fork collectors pass. Final-source media/reachability/formatter/analyzer/SBOM/native rebuilds remain. The substantive Firebase scene callback return-type defect remains under correction; build success does not clear it.
- **L02/L06/L09/L10/L11/L13:** six existing local goal closures remain verified. Other local goals are partially implemented and remain open. [Current local register](LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md) retains every original criterion.
- Retained hosted metadata contains124 versions. Current filename comparison finds{len(absent)} local versions absent from that retained set; it does not establish current deployed state. No hosted, provider, signing, store, Drive-permission or physical-device acceptance was refreshed.

The [new local progress packet](local-progress-2026-09-30/attempt3-source148/validation.json) binds the exact local registry/table/catalog/cron readback, preserved earlier registers and16 newer scoped packets. Existing packet failures remain preserved. Final clean/populated replay and single-source full acceptance are pending; generated local fixtures do not establish representative customer acceptance.

"""
    (RELEASE / 'PRODUCTION_REMAINING_TASKS_2026-09-30.md').write_text(prefix + body)
    production.update(snapshot_revision=7, supersedes_captured_at_utc=production['captured_at_utc'],
        captured_at_utc=now, source_migration_count=len(migrations),
        working_tree_status_entries=status_entries, working_tree_entry_count=status_entries,
        local_upgrade_registry_migration_count=148, isolated_local_registry_migration_count=148,
        isolated_local_table_count=146, staged_source_migrations=staged,
        local_progress_refreshed_at_utc=now,
        local_progress_note='6 local goals closed;18open.147/148 installed;149 uninstalled draft. Memory-only Auth/fork implemented but full literal privacy/recovery acceptance pending. Current health39/SQL147110+11/Edge309+76/shared120+205 and dated native artifacts retained; final clean replay141.',
        local_versions_absent_from_retained_hosted_readback=len(absent))
    production['local_fixture_readonly_observation'].update(migration_count=148,
        last_migration='20260930160000', table_count=146, worker_sessions_remaining=0,
        captured_at_utc=now, scope='Exact quiet local guard and complete table/catalog/cron readback; no provider/hosted calls')
    host = production['hosted_observation']
    host['current_local_missing_migrations'] = [{'version': v, 'path': str(migrations[v].relative_to(ROOT)), 'sha256': sha(migrations[v])} for v in absent]
    host['current_local_missing_migration_count'] = len(absent)
    host['current_local_comparison_scope'] = 'Current filename/hash comparison against retained124-version readback only; no hosted refresh'
    production['current_local_scoped_packets'] = packets
    production['new_evidence_packets'] = list(dict.fromkeys([*production['new_evidence_packets'], *[r['path'] for r in packets]]))
    for source in production['source_documents']:
        source['sha256'] = sha(ROOT / source['path'])
    save(RELEASE / 'production-remaining-tasks-2026-09-30.json', production)
    assert {r['id']: r['local_acceptance'] for r in local['items']} == local_before
    assert {r['id']: r['original_acceptance'] for r in production['items']} == prod_before
    assert [r['id'] for r in local['items'] if r['status'] == 'complete'] == local['locally_closed_goal_items']
    assert len([r for r in production['items'] if r['open']]) == 101
    assert [r['id'] for r in production['items'] if not r['open']] == ['G06']
    assert all(sha(ROOT / r['path']) == r['sha256'] for r in packets)
    canonical = ['local-implementation-register-2026-09-30.json', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md',
                 'production-remaining-tasks-2026-09-30.json', 'PRODUCTION_REMAINING_TASKS_2026-09-30.md']
    validation = {'status': 'pass', 'validated_at_utc': now, 'scope': 'Register integrity and scoped local progress; not final whole-system acceptance',
        'snapshot_revision': 7, 'local_snapshot_revision': 5, 'original_criteria_preserved': True,
        'local_criteria_preserved': True, 'all_original_ids_preserved': True, 'unique_open_rows': 101,
        'closed_ids': ['G06'], 'local_goal_closed_ids': local['locally_closed_goal_items'],
        'priority_counts': dict(collections.Counter(r['priority'] for r in production['items'] if r['open'])),
        'evidence_counts': dict(collections.Counter(r['evidence_status'] for r in production['items'] if r['open'])),
        'source_documents_match': all(sha(ROOT / r['path']) == r['sha256'] for r in production['source_documents']),
        'sha256': {str((RELEASE / p).relative_to(ROOT)): sha(RELEASE / p) for p in canonical},
        'prior_revision_preserved': preserved, 'new_scoped_evidence_packets': packets,
        'installed_migration_count': 148, 'installed_table_count': 146, 'staged_source_versions': staged,
        'installed147148source_matches': True, 'full_current_source_acceptance': False,
        'last_complete_clean_replay': 141, 'external_state_refreshed': False}
    save(RELEASE / 'production-remaining-tasks-2026-09-30.validation.json', validation)
    save(BASE / 'validation.json', {**validation, 'register_validation_sha256': sha(RELEASE / 'production-remaining-tasks-2026-09-30.validation.json'), 'refresh_script_sha256': sha(Path(__file__))})
    print(json.dumps({k: validation[k] for k in ['status','snapshot_revision','local_snapshot_revision','installed_migration_count','installed_table_count','unique_open_rows','staged_source_versions']}))


if __name__ == '__main__':
    main()
