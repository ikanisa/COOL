"""Refresh implementation status while preserving all original acceptance rows."""
from pathlib import Path
import copy
import datetime
import hashlib
import json

HERE = Path(__file__).resolve().parent
BASE = HERE.parent
ROOT = HERE.parents[3]
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
canonical = lambda value: hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
expected = json.loads((HERE / 'expected-registers.json').read_text())['before_sha256']
original_rows = {
    'production-remaining-tasks-2026-09-30.json': '404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f',
    'local-implementation-register-2026-09-30.json': '0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980',
}
proofs = {
    'root-tooling-source-integration1/consumer-validation2/packet-files.json': '059c0825a5eb04ac81e667a2bb7afaa9b0636e0d3b6d4eed759e96e149e88168',
    'root-tooling-source-integration1/management-comment-correction1/consumer-proof1/packet-files.json': 'd5626fc2c9870c945d34245d90583a1fb55b2cec34337b88f78e82235be0f79e',
    'root-schema-lineage-integration1/packet-files.json': '98a2f19c01459bc9be512dd87842a1c1df686f43305b2c6ab9f054afde1857bf',
    'root-schema-drop-lineage-correction1/packet-files.json': '957df417426e5f23cc0249a29a5ff50191444260d266e8f7c8a89f801ed18cd8',
    'ordinary-recovery-replay-preparation3/packet-files.json': 'df7ee7c7569307f7a287ec78bae46701ead6a72848138bf4df2b904590cbbe45',
    'ordinary-recovery-replay-execution3/packet-files.json': '7225b7bc12a48cc78266c5d53e2c939e1faf50069e887ec38bb6c6f8f70d58ca',
    'kotlin-sdk-native-consumer-app-export3/packet-files.json': '6b253388d2233cda9f3d5b783f3e9bfbca6fe3f272b672c4dec79d8ea40cf92a',
    'kotlin-sdk-native-app-lock1/packet-files.json': '91a584e4889e5f7355706a3ee778be4773412d15c12de870fb9f78b8d64c3e54',
    'cloudflare-cli-readback1/seal.json': '093c80c83d61a8a62c797c9f2dc00bfd93a346eabd07a30366b0c859cc0176eb',
    'public-legal-live-readback1/packet-files.json': 'a128caf2269b6dc406901be7c46ab09ae6207b03d8ae9766c7fa2ad0112b416c',
    'root-public-provider-readback-review1/review.json': '979ea63845c66fec849418f2bc2f47db0bd5a919e34909ce663559ff833a734f',
}

def save(path, document):
    path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + '\n')

assert all(sha(ROOT / name) == digest for name, digest in expected.items())
assert all(sha(BASE / name) == digest for name, digest in proofs.items())
ledger_path = BASE / 'implementation-ledger.json'
ledger = json.loads(ledger_path.read_text())
criteria = [(row['id'], copy.deepcopy(row['acceptance_requirement_from_report'])) for row in ledger['items']]
assert len(criteria) == 40
assert sorted(row['id'] for row in ledger['items'] if row['full_finding_closed']) == ['ARC-04', 'PD-02', 'PD-14']
documents = {name: json.loads((BASE.parent / name).read_text()) for name in original_rows}
assert all(canonical(value['items']) == original_rows[name] for name, value in documents.items())
for name in expected:
    destination = HERE / 'registers-before' / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open('xb') as stream:
        stream.write((ROOT / name).read_bytes())
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
refs = [{'path': str((BASE / name).relative_to(ROOT)), 'sha256': digest} for name, digest in proofs.items()]
rows = {row['id']: row for row in ledger['items']}

def add(ident, selectors):
    known = {entry['path'] for entry in rows[ident]['evidence_packets']}
    rows[ident]['evidence_packets'] += [entry for entry in refs if any(token in entry['path'] for token in selectors) and entry['path'] not in known]

add('ARC-08', ['consumer-validation2', 'management-comment-correction1', 'ordinary-recovery'])
add('BE-08', ['schema-lineage', 'schema-drop', 'ordinary-recovery'])
add('BE-09', ['ordinary-recovery'])
add('ARC-11', ['ordinary-recovery'])
add('ARC-09', ['native-consumer-app-export3', 'native-app-lock1'])
for ident in ('PD-04', 'PD-05', 'PD-07'):
    add(ident, ['cloudflare-cli', 'public-legal-live', 'public-provider'])
add('PD-12', list(proofs))
rows['ARC-08']['implementation_status'] = 'maintained_postgres_admission_and_affected_consumers_verified_real_toolchain_acceptance_open'
rows['ARC-08']['next_action'] = (
    'The reviewed PostgreSQL admission module, delivery/helper/readiness consumers, tests, Make wiring and documentation are now maintained. '
    'The dated current consumer proof has 27 actual passes, three additional passes and one genuine management failure, plus a separate passing client-drift trace. '
    'Root corrected only the leading-line-comment outer BEGIN normalization. Its affected consumer and extra BEGIN/COMMIT refusal checks now pass 3/3 in100.109seconds: each of two writes follows the exact server-version query and readback matches209 migrations. '
    'The failed attempt remains failed and immutable; no fresh full45/27 pass is claimed. Transports, versions and approvals in those behavioral tests are synthetic. '
    'Actual isolated PostgreSQL17.6 migration proof exists separately; committed restore3 completes pg_restore but fails full predecessor catalog/effectiveACL equality. '
    'Complete the real client/server provenance and approved compatibility cohort, embedded CLI database tooling/image provenance, shipping dump/restore admission and successful restore with original forward replay. Hosted/release acceptance remains open.'
)
rows['BE-08']['implementation_status'] = 'current209_catalogs_and_maintained_reasoned_domain_map_verified_committed_recovery_failed'
rows['BE-08']['next_action'] = (
    'The actual209 clean/populated ordinary-installer proof remains37/37 passing with complete matching catalogs and18 preserved projections. '
    'The maintained mapper now passes49 tests and fresh independent recomputation of all five outputs. The unqualified DROP lineage ambiguity is corrected conservatively across schemas and overloads, preserving qualified scope and all44 prior test ASTs. It preserves20 catalog categories,4157 grants,18 caller seams and664 selected sources. '
    'Two exact signature/body-bound static renames are recovered; all127 prior gaps have reasoned records, leaving125 unresolved functions (34application/public and91platform),74 unclassified objects and58 unresolved/dynamic caller sites. '
    'Business ownership and runtime graph completeness remain unverified. Committed recovery attempts1/2/3 remain genuine failures; attempt3 passes15 checks and completes pg_restore, then refuses full predecessor catalog/effectiveACL mismatch before forward replay. '
    'Resolve the captured parity differences, complete85 original forward migrations with18 preserved projections, broaden historical data/ACL coverage, resolve owner/caller gaps and obtain managed hosted/runtime acceptance. No full BE08 closure is inferred.'
)
rows['ARC-09']['implementation_status'] = 'actual_strict_app_export_verified_pub_child_pass_whole_app_lock_failed_native_unrun'
rows['ARC-09']['next_action'] = (
    'The isolated authenticated SDK foundation, enforced SDK resolution and startup proofs remain valid. Fresh strict app export3 completes as a whole stage with2510 original files and protected68020 metadata paths unchanged; prior export failures remain retained. '
    'The actual locked app pub child passes in294.027seconds with original lock bytes, but the whole app-lock stage fails because its reader refuses generated ios/Runner/GeneratedPluginRegistrant.h. Root retained all13 control originals and rechecked all2510 authored byte/size/mode identities. '
    'Review exact SDK-template-bound iOS registrants and the exact SDK integration_test package binding, preserve this failed cohort, and execute a fresh whole export/app-lock retry. Native compile remains unrun and unadmitted. '
    'Then complete actual all-flavor/ABI AAB/IPA/web packages, advisory/license review and artifact-bound SBOM reconciliation. No release or next-stage success is inferred from the pub child.'
)
rows['PD-04']['implementation_status'] = 'local_copy_corrected_live_deletion_form_promise_still_unimplemented'
rows['PD-04']['next_action'] = (
    'Local canonical support content and app instructions are corrected. Anonymous live readback still finds the old public form promise with zero form/input elements, old Settings navigation and older service wording. '
    'The anonymous WhatsApp support landing resolves to the expected number; no message/request was sent and the mail channel was not exercised. '
    'Publish/read back the reviewed intended build through the authorized provider route and verify the actual supported no-app request, acknowledgement/status and duplicate/failure outcomes. Request intake does not prove completed erasure.'
)
rows['PD-05']['implementation_status'] = 'local_legal_graph_corrected_live404_and_anchor_gaps_observed'
rows['PD-05']['next_action'] = (
    'Local generated legal destinations/anchors and dated public4 captures are retained. Fresh anonymous GET readback observes404 for live /subprocessors/, /privacy-request/ and /cookies/, four failing privacy/terms edges and a missing /data-deletion/#retained-data-summary anchor. '
    'All seven sampled live HTML hashes differ from the reviewed local candidate. Read-only Cloudflare API identifies collect-public and an active September7 deployment, but custom-domain permission is denied and the public hostname-to-worker binding is unverified. '
    'No provider mutation or current-candidate deployment is supplied. Obtain authorized route/artifact publication and exact served-build legal destination/content verification plus promised privacy outcomes. Full legal/publication acceptance remains open.'
)
rows['PD-12']['next_action'] = (
    'This checkpoint refreshes all40 critical findings using current scoped implementation outcomes and retained failures, while preserving the original102 production and24 local acceptance rows. '
    'The maintained schema map has current semantic proof; app export3, whole app-lock failure, committed restore3 failure and live legal/provider observations are explicitly separated. '
    'Older packets retain their producer inputs and scopes. New technical source changes make previous strict source fences dated; a new fence is required for the next app export. '
    'Complete a final source/dependency/artifact index after remaining integration and font-rights decisions. A whole native/Admin/backend/public release candidate is not accepted.'
)
for ident in ('BE-09', 'ARC-11'):
    rows[ident]['next_action'] = (
        'The fresh synthetic committed predecessor is durably dumped in a separate session; its source container is removed before independent restore. '
        'Restore3 passes exact30-role and GraphQL metadata/membership prerequisites and pg_restore itself, then fails full predecessor catalog/effectiveACL equality; both task containers are absent. '
        'Forward replay and18 projection restoration checks are not yet reached. Resolve parity, then complete database/permissions/Auth/Storage/configuration/queue/revocation recovery, approved RPO/RTO measurement and independent acceptance. Synthetic database restoration alone cannot close full-system recovery.'
    )
for entry in refs:
    ledger['evidence_current_readback'][entry['path'].removeprefix(str(BASE.relative_to(ROOT)) + '/')] = dict(checked_at_utc=now, **entry, scope='Retained exact scoped outcome; producer inputs and whole-stage failures stay explicit. No whole candidate, owner approval or release acceptance inferred.')
ledger.update(captured_at_utc=now, goal_status='active', release_decision='NO-GO', candidate_status=(
    'Mutable shared checkout. Current154 backend proof and209 ordinary migration/catalog proof remain separately scoped. '
    'Reviewed PostgreSQL admission and schema mapper are maintained; affected management3 and mapper49 checks pass. '
    'Strict app export3 passes, but whole app-lock1 and committed recovery3 fail their guards. Native packages remain unbuilt. '
    'Anonymous live legal gaps and limited read-only Cloudflare identity are recorded. No deployment, signed package, whole candidate or production acceptance is inferred.'
))
assert [(row['id'], row['acceptance_requirement_from_report']) for row in ledger['items']] == criteria
note = (
    f'Current implementation checkpoint — {now}. Three original findings remain closed (ARC-04, PD-02 and PD-14);37 remain open in full. Production NO-GO; goal active.\n\n'
    'PostgreSQL admission is now maintained. The corrected two-migration management path and two transaction-boundary negatives pass3/3; the previous failed probe remains recorded. The schema mapper passes49 maintained tests and fresh full five-output recomputation, including conservative unqualified DROP handling. Two exact static renames resolve;125 function mappings,74 object classifications and58 caller sites remain unresolved.\n\n'
    'Committed restore3 passes15 checks, including role/GraphQL prerequisites and pg_restore, but fails complete predecessor catalog/effectiveACL equality. Both containers are removed; original forward replay is not reached. Earlier failed recovery cohorts remain immutable.\n\n'
    'Strict app export3 passes as a whole stage. Locked app pub resolution passes as a child in294.027seconds, but whole app-lock1 fails on an unreviewed generated iOS registrant. All2510 original authored files and lock bytes are unchanged. Native compilation has not run. A reviewed guard correction and fresh source fence/export/app-lock retry remain required.\n\n'
    'Anonymous live legal readback finds three404 destinations, a missing retained-data anchor and an old deletion-form promise without a form. All seven sampled HTML hashes differ from the local candidate. Read-only Cloudflare API identifies the worker and a September7 deployment; public hostname binding/current-candidate deployment remain unverified. No provider configuration or publication was changed.\n\n'
    'All40 original critical acceptance requirements and102 production/24 local rows remain unchanged. Retained packets are dated producer evidence. Hosted, device, provider, privacy/erasure, font rights, signed packages, full recovery and owner/release acceptance remain open. This checkpoint supersedes older implementation-status prose below; the original acceptance rows and dated observations remain historical evidence.\n'
)
assert all(sha(ROOT / name) == digest for name, digest in expected.items())
save(ledger_path, ledger)
lines = ['# Critical findings implementation register', '', f'Updated {now}. **37 findings remain open; production NO-GO; goal active.**', '',
         'Revolut is the sole UI/UX and product visual design authority. Technical and professional skills retain their separate scopes. The retired checklist and competing design references are not acceptance authorities.', '',
         '| Finding | Local implementation | Full acceptance | Latest scoped evidence |', '| --- | --- | --- | --- |']
for row in ledger['items']:
    links = '; '.join(f"[{Path(entry['path']).parent.name}]({ROOT / entry['path']})" for entry in row['evidence_packets'][-2:])
    lines.append(f"| {row['id']} | {row['implementation_status']} | {'Closed in recorded original scope' if row['full_finding_closed'] else 'Open'} | {links} |")
lines += ['', note, f'All original criteria and the complete retained evidence history are in [implementation-ledger.json]({ledger_path}).']
(BASE / 'IMPLEMENTATION_REGISTER.md').write_text('\n'.join(lines) + '\n')
(HERE / 'CURRENT_PROGRESS.md').write_text('# Current implementation evidence\n\n' + note)
for name, document in documents.items():
    extension = document['critical_review_implementation_extension']
    extension.update(captured_at_utc=now, sha256=sha(ledger_path), specialist_findings_closed=3,
                     current_integration_note=note.strip(), current_schema_progress_note=note.strip())
    known = {entry['path'] for entry in extension['latest_scoped_evidence']}
    extension['latest_scoped_evidence'] += [entry for entry in refs if entry['path'] not in known]
    assert canonical(document['items']) == original_rows[name]
    save(BASE.parent / name, document)
for name in ('PRODUCTION_REMAINING_TASKS_2026-09-30.md', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md'):
    path = BASE.parent / name
    old = path.read_text()
    heading, rest = old.split('\n', 1)
    path.write_text(heading + '\n\n' + note + '\n' + rest)
assert [(row['id'], row['acceptance_requirement_from_report']) for row in json.loads(ledger_path.read_text())['items']] == criteria
for name in original_rows:
    current = json.loads((BASE.parent / name).read_text())
    assert canonical(current['items']) == original_rows[name] and current['critical_review_implementation_extension']['sha256'] == sha(ledger_path)
after = {name: sha(ROOT / name) for name in expected}
save(HERE / 'reconciliation.json', dict(status='pass', at_utc=now, before=expected, after=after,
     original40_criteria_unchanged=True, original_row_digests=original_rows, closed_ids=['ARC-04', 'PD-02', 'PD-14'],
     full_findings_open=37, production_ready=False, goal_status='active'))
for name in expected:
    destination = HERE / 'registers-after' / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open('xb') as stream:
        stream.write((ROOT / name).read_bytes())
files = [{'path':str(path.relative_to(HERE)), 'bytes':path.stat().st_size, 'sha256':sha(path)} for path in sorted(HERE.rglob('*')) if path.is_file()]
save(HERE / 'packet-files.json', dict(status='sealed', files=files))
print(json.dumps(dict(status='pass', registers=6, original_criteria=40, original_production_rows=102,
                     original_local_rows=24, open=37, closed=3, ledger_sha256=sha(ledger_path), packet_sha256=sha(HERE / 'packet-files.json'))))
