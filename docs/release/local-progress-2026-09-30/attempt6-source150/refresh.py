"""Preserve all criteria and refresh scoped local progress from real readback."""
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path.cwd().resolve()
OUT = Path(__file__).resolve().parent
BASE = ROOT / 'docs/release'
FILES = ['local-implementation-register-2026-09-30.json',
         'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md',
         'production-remaining-tasks-2026-09-30.json',
         'PRODUCTION_REMAINING_TASKS_2026-09-30.md',
         'production-remaining-tasks-2026-09-30.validation.json']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def inventory():
    result = {}
    for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
        version = path.name.split('_', 1)[0]
        if not re.fullmatch(r'[0-9]{12}|[0-9]{14}', version) or version in result:
            raise RuntimeError('Invalid/duplicate migration version')
        result[version] = dict(path=str(path.relative_to(ROOT)), sha256=sha(path.read_bytes()))
    return result


prior = {name: (BASE / name).read_bytes() for name in FILES}
archive = OUT / 'prior-registers'
archive.mkdir(mode=0o700)
for name, data in prior.items():
    (archive / name).write_bytes(data)
prior_hashes = {name: sha(data) for name, data in prior.items()}
save(OUT / 'prior-register-hashes.json', prior_hashes)
local = json.loads(prior[FILES[0]])
prod = json.loads(prior[FILES[2]])
local_criteria = {x['id']: x['local_acceptance'] for x in local['items']}
production_criteria = {x['id']: x['original_acceptance'] for x in prod['items']}
closed_local = [x['id'] for x in local['items'] if x['status'] == 'complete']
closed_prod = [x['id'] for x in prod['items'] if not x['open']]
source = inventory()
spec = importlib.util.spec_from_file_location('fixture', ROOT / 'scripts/tests/local_offline_verification.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
guard = fixture.guard(150, '20260930180000')
snapshot = fixture.snapshot()
installed = json.loads(fixture.FIXTURE.sql("select json_agg(jsonb_build_object('version',version,'statement_sha256',encode(extensions.digest(statements[1],'sha256'),'hex')) order by version) from supabase_migrations.schema_migrations;"))
for version in ['20260930170000', '20260930180000']:
    row = next(x for x in installed if x['version'] == version)
    if row['statement_sha256'] != source[version]['sha256']:
        raise RuntimeError('Installed reviewed149/150 source mismatch')
staged = sorted(set(source) - {x['version'] for x in installed})
save(OUT / 'current-readback.json', dict(
    guard=guard, snapshot=snapshot, installed_registry=installed, source_inventory=source,
    staged_source_versions=staged, hosted_called=False, provider_called=False))
PACKETS = [
    'roster-fresh-auth-2026-09-30/install149-normal-owner-attempt1/result.json',
    'roster-fresh-auth-2026-09-30/uat149-installed-rollback-attempt3-exact-ack/result.json',
    'roster-fresh-auth-2026-09-30/concurrency150-attempt2-typed-arrays/validation.json',
    'roster-fresh-auth-2026-09-30/auth-export-attempt5/validation.json',
    'financial-observability-2026-09-30/install150-normal-owner-attempt1/result.json',
    'financial-observability-2026-09-30/health-authority-concurrency150-attempt1/validation.json',
    'financial-observability-2026-09-30/alert-matrix150-rollback-attempt1/result.json',
    'financial-observability-2026-09-30/metric-concurrency150-attempt1/validation.json',
    'admin-full-coverage-2026-09-30/isolated-attempt15-sensitive-paging/validation.json',
    'asset-build-hygiene-2026-09-30/native-export-attempt28-ios/artifact-verification.json',
    'asset-build-hygiene-2026-09-30/native-export-attempt28-android-remaining/apk-verification.json',
    'asset-build-hygiene-2026-09-30/native-export-attempt28-android-remaining/jvm-tests.json',
    'asset-build-hygiene-2026-09-30/public-media-publication-attempt30/publication.json',
    'asset-build-hygiene-2026-09-30/native-provenance-coverage-attempt31/verification.json',
]
packets = []
for relative in PACKETS:
    path = BASE / relative
    result = json.loads(path.read_text())
    if isinstance(result, list):
        expected = {'app.cool.mobile.receiver_sms.SmsQueueWorkerTest': 1,
                    'app.cool.mobile.receiver_sms.SmsQueueOwnerPolicyTest': 3,
                    'app.cool.mobile.receiver_sms.CollectSmsReceiverTest': 8}
        if not relative.endswith('/jvm-tests.json') or {x['name']: int(x['tests']) for x in result} != expected or any(int(x[k]) != 0 for x in result for k in ['failures', 'errors', 'skipped']):
            raise RuntimeError('Incomplete JVM result: ' + relative)
    elif not isinstance(result, dict) or result.get('status') in ('fail', 'failed') or result.get('passed') is False:
        raise RuntimeError('Selected packet failed: ' + relative)
    packets.append(dict(path='docs/release/' + relative, sha256=sha(path.read_bytes())))
updates = {
    'L01': '149 is installed with ordinary owner privileges;51 rollback assertions and36 fresh-Auth/lineage/quota scenarios with31 observed blocking races pass on150, restoring all149 tables/catalog/cron and leaving0 workers. Copied Auth acceptance passes123 tests and28 real Chrome privacy checks; its original receipt aggregation limitation is retained. Full normal Admin fresh-sign-in/reload dialogue protection and final browser integration remain.',
    'L03': 'Retained focused Auth/read/expiry acceptance and actual17 SQL read receipts remain. Current protected-SMS permission A-to-B-to-A and explicit paging recovery pass7 tests with clean scoped analysis. Full same-session loading/role/capability/revocation coverage across every provider and dialog, including roster, remains.',
    'L04': 'Strict actor/record/read contracts and149 transfer/commit receipts are verified in scoped SQL/Dart packets. Full operation-specific request/ACK/session/audit matrix and final-source aggregate acceptance remain.',
    'L05': 'Current route inventory declares25 Admin routes. Sensitive SMS and paging corrections pass their7-test packet; expanded aggregate matrices retain unresolved coverage and fixture findings. Complete route/action/state/permission/session/audit integration, including new navigation and shadow history, remains.',
    'L08': '150 health access passes6 actual revocation races;149 roster recovery passes stale-snapshot session/approval/role/permission revocation in both directions within the36-scenario packet. Full local role, cross-group, raw-SMS, effective grants/RLS and final-definition negative matrix remains.',
    'L19': '148 telemetry and150 authority correction are installed. Current150 acceptance passes180 alert assertions,5 metric-writer cases with4 blocking races and6 health-authority races; each restores all149 tables/catalog/cron. Retained39 health UI tests and76 HTTP/309 Edge checks remain scoped. Realistic performance, operator-response rehearsal and final interface integration remain.',
    'L21': 'Current seven Public previews were captured, visually reviewed and published with preserved originals and exact source bindings. Subsequent authorized Admin safety corrections will require a new final bind; final reachability/dependency closure remains.',
    'L22': 'Retained export evidence proves unsigned Android production APK/lint/JVM acceptance and complete unsigned arm64 iOS compilation. The Firebase scene callback correction compiles in the complete app. The native provenance collector now covers Admin/local forks and passes7 mutation tests/111 assertions. These exports retain explicit live-checkout drift; final-source formatting/analysis/native/media/inventory/SBOM bind remains.',
    'L23': 'Exact quiet installed150 registry/149 tables and reviewed149/150 source matches are verified. Current source inventory and staged versions are recorded separately; navigation/shadow remain uninstalled. Last complete clean replay remains141. Final clean/populated/compatibility/full-suite/concurrency/mutation acceptance remains.',
    'L24': 'Every original24 local and102 production acceptance criterion is preserved. This revision binds14 newer scoped packets, a fresh150 readback, dynamic source/staged inventory and hashes of all five prior registers. One final source snapshot and complete handover remain pending.',
}
for item in local['items']:
    if item['id'] in updates:
        item['verified_progress'] = updates[item['id']]
    if item['id'] == 'L01':
        item['privacy_acceptance'] = 'Full closure pending: memory-only Auth/privacy primitive checks pass; normal Admin recovery and authorization transition coverage remain.'
now = dt.datetime.now(dt.timezone.utc).isoformat()
local.update(captured_at_utc=now, snapshot_revision=local.get('snapshot_revision', 0) + 1,
             current_local_migration_count=150, current_local_table_count=len(snapshot['tables']),
             source_migration_count=len(source), staged_source_migrations=staged)
local['latest_verified_local_result'] = dict(
    scope='Fresh150 readback and source-bound scoped packets; final whole-goal acceptance unproven',
    readback=str((OUT / 'current-readback.json').relative_to(ROOT)),
    readback_sha256=sha((OUT / 'current-readback.json').read_bytes()),
    evidence_packets=packets, migration_count=150, table_count=len(snapshot['tables']),
    whole_goal_complete=False)
previous_capture = prod.get('captured_at_utc')
prod.update(captured_at_utc=now, supersedes_captured_at_utc=previous_capture,
            snapshot_revision=prod.get('snapshot_revision', 0) + 1,
            base_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
            source_migration_count=len(source), local_upgrade_registry_migration_count=150,
            installed_table_count=len(snapshot['tables']), staged_source_versions=staged)
prod['working_tree_status_entries'] = len(subprocess.check_output(['git', 'status', '--porcelain'], text=True).splitlines())
prod['new_evidence_packets'] = list(dict.fromkeys(prod.get('new_evidence_packets', []) + [x['path'] for x in packets]))
prod['evidence_manifest_observations'] = prod.get('evidence_manifest_observations', []) + packets
prod['local_progress_readback'] = local['latest_verified_local_result']['readback']
for item in prod['items']:
    if item['id'] == 'O06':
        item['current_evidence'] = updates['L19'] + ' Hosted/operator/provider acceptance remains open.'
        item['remaining_work'] = 'Finish realistic metric/query performance, local response rehearsal and final interface integration; verify deployed measurements, redaction and operator response against the original acceptance criterion.'
    if item['id'] == 'A01':
        item['current_evidence'] = updates['L01'] + ' Deployed operator approval/audit/permissions and provider acceptance remain open.'
local_md = ['# Collect local implementation register', '',
            f'Captured: {now}. Revision{local["snapshot_revision"]}.', '',
            f'**{len(closed_local)} of24 local goals verified complete;{24-len(closed_local)} remain open.** Original102 production criteria retain their acceptance scope.', '',
            f'Installed local registry:150 migrations/{len(snapshot["tables"])} tables. {len(source)} source files; staged versions: {", ".join(staged) or "none"}. Final whole-source acceptance is pending.', '',
            '| ID | Task | Status | Remaining scope or verified result |',
            '| --- | --- | --- | --- |']
for item in local['items']:
    cells = [item['id'], item['title'], item['status'], item.get('verified_progress') or item['local_acceptance']]
    local_md.append('| ' + ' | '.join(str(value).replace('|', r'\|') for value in cells) + ' |')
local_md += ['', '## Original local acceptance criteria', '']
for item in local['items']:
    local_md += [f'### {item["id"]} — {item["title"]}', '', item['local_acceptance'], '']
local_text = '\n'.join(local_md)
tail = '## G —' + prior[FILES[3]].decode().split('## G —', 1)[1]
prod_text = f"""# Collect — exhaustive remaining production tasks

**Snapshot: 30 September2026 (Africa/Kigali), revision{prod['snapshot_revision']}. Release decision: NO-GO.**

**101 acceptance checks remain open:99 of100 original tasks, plus X01 and X02.** G06 remains locally closed; the original acceptance scope is preserved.

| Priority | Open |
| --- | ---: |
| P0 |24|
| P1 |71|
| P2 |4|
| Crosscutting |2|
| **Total** |**101**|

Evidence states remain67 Partial,27 External,7 Unverified. No production criterion is narrowed or closed by this local refresh.

Source: HEAD {prod['base_commit']} plus{prod['working_tree_status_entries']} captured working-tree entries at {now}. No release candidate is frozen. {len(source)} source migrations are present; the isolated registry has150 installed migrations/{len(snapshot['tables'])} tables. Staged versions: {', '.join(staged)}. Last complete clean replay remains141.

## Latest verified local progress and limits

- **A01/L01:** {updates['L01']}
- **S09/L03–L05:** {updates['L03']} {updates['L05']}
- **S08/L08:** {updates['L08']}
- **O06/L19:** {updates['L19']}
- **A08/L20:** retained147 acceptance covers26 governed families,110 SQL checks and11 races; final all-consumer/audit integration remains.
- **Q01/Q02/Q07/L21–L22:** {updates['L21']} {updates['L22']}
- **Local goals:** six closures remain L02/L06/L09/L10/L11/L13;18 remain open. The [local register](LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md) preserves every criterion.
- Retained hosted metadata is dated. No hosted, provider, signing, store, Drive-permission or physical-device acceptance is refreshed.

The [local progress packet]({OUT.relative_to(BASE)}/validation.json) binds the fresh registry/table/catalog/cron readback, all five prior registers and14 newer scoped packets. Failed packets and their separately verified restoration remain preserved. Final clean/populated replay, complete local acceptance and single-source handover are pending.

""" + tail
for reference in prod.get('source_documents', []):
    path = ROOT / reference['path']
    reference['sha256'] = sha(prod_text.encode()) if path == BASE / FILES[3] else sha(path.read_bytes())
if {x['id']: x['local_acceptance'] for x in local['items']} != local_criteria:
    raise RuntimeError('Local criterion changed')
if {x['id']: x['original_acceptance'] for x in prod['items']} != production_criteria:
    raise RuntimeError('Production criterion changed')
if [x['id'] for x in local['items'] if x['status'] == 'complete'] != closed_local or [x['id'] for x in prod['items'] if not x['open']] != closed_prod:
    raise RuntimeError('Closure scope changed')
if source != inventory() or snapshot != fixture.snapshot() or any((BASE / name).read_bytes() != data for name, data in prior.items()):
    raise RuntimeError('Source/fixture/register changed before writes')
save(BASE / FILES[0], local)
(BASE / FILES[1]).write_text(local_text)
save(BASE / FILES[2], prod)
(BASE / FILES[3]).write_text(prod_text)
validation = dict(
    status='pass', validated_at_utc=now,
    scope='Original register integrity and scoped local evidence; not final whole-system acceptance',
    snapshot_revision=prod['snapshot_revision'], local_snapshot_revision=local['snapshot_revision'],
    original_criteria_preserved=True, local_criteria_preserved=True, all_original_ids_preserved=True,
    unique_open_rows=sum(x['open'] for x in prod['items']), closed_ids=closed_prod,
    local_goal_closed_ids=closed_local, priority_counts=prod['open_by_priority'],
    evidence_counts=prod['open_by_evidence_status'],
    source_documents_match=all(sha((ROOT / x['path']).read_bytes()) == x['sha256'] for x in prod['source_documents']),
    sha256={'docs/release/' + name: sha((BASE / name).read_bytes()) for name in FILES[:-1]},
    prior_revision_preserved=prior_hashes, new_scoped_evidence_packets=packets,
    installed_migration_count=150, installed_table_count=len(snapshot['tables']),
    source_migration_count=len(source), staged_source_versions=staged,
    installed149150source_matches=True, full_current_source_acceptance=False,
    last_complete_clean_replay=141, external_state_refreshed=False)
save(BASE / FILES[4], validation)
for name in FILES:
    if sha((archive / name).read_bytes()) != prior_hashes[name]:
        raise RuntimeError('Preserved prior register changed')
for name, field, criteria in [(FILES[0], 'local_acceptance', local_criteria),
                              (FILES[2], 'original_acceptance', production_criteria)]:
    if {x['id']: x[field] for x in json.loads((BASE / name).read_text())['items']} != criteria:
        raise RuntimeError('Saved original criterion changed')
validation['refresh_script_sha256'] = sha(Path(__file__).read_bytes())
validation['canonical_output_sha256'] = {name: sha((BASE / name).read_bytes()) for name in FILES}
save(OUT / 'validation.json', validation)
print(json.dumps(dict(status='pass', local_revision=local['snapshot_revision'],
                      production_revision=prod['snapshot_revision'], installed_count=150,
                      source_count=len(source), staged=staged, local_closed=closed_local,
                      local_open=24-len(closed_local), production_open=validation['unique_open_rows'])))
