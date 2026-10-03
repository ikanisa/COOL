"""Preserve original criteria and reconcile exact reviewed local scopes."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
BASE = HERE.parent
ROOT = HERE.parents[3]
LEDGER = BASE / 'implementation-ledger.json'
EXPECTED_LEDGER = 'e548729952cbc4ae857abe68f5923f652de3a7109d3d01551185a4be15f1ed79'
ORIGINALS = {
    'production-remaining-tasks-2026-09-30.json': '404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f',
    'local-implementation-register-2026-09-30.json': '0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980',
}
PROOFS = {
    'root-ai-dispatch-promotion-batch1/packet-files.json': '22254ff78ce9066b6ff329446f8230edce567dda48996ec6e1c69bf316c62400',
    'root-edge-canonical-review-batch1/packet-files.json': 'b1bbd91e078226a18892bd79bfa28245f244ad5ace20284617b86fea488a9b9c',
    'root-edge-offline-integration-batch1/packet-files.json': '6051997f834d2b18b3226b464249e7bd21ac7fa1d18367779ef0fa0ef84a4ffb',
    'root-ci-policy-current-batch1/packet-files.json': '3c1a56782766eea0fac884cbd7828fa841c3c88a332e51dba4b4350b9630a38d',
    'successor-gateway-inventory-batch1/batch.json': '95f41f4995d9d1c0b7cf400c3d0e2b01929474e006d57f43bb1c994b201e30e0',
    'successor-gateway-consumer-preparation1/batch.json': '252b1e0310597fc36dc25ed7f41416ad47412ac66d68d6e64778bbad019957fd',
    'root-successor-consumer-promotion1/packet-files.json': '75a25f8f9a116d96e7c955477d996bb98730a0bcace3e80a7b170c91b002f6be',
    'edge-ai-canonical-batch2/batch.json': '98fc0cb31a6f9509ecd026560b5842bb0371c9d3107aca222cb518f3ddc7f4b7',
    'edge-ai-http-fixture-preparation2/batch.json': '8327151022c8760bf4ae2f989597cbf663b88ba5210cc1951faa0e38b70e49be',
    'root-edge-ai-http-fixture-promotion2/packet-files.json': 'eee7156644ad404ab878d8b809d9d0c17876c401541be6ea45755de0362028ac',
    'kotlin-sdk-native-consumer-foundation1/packet-files.json': 'c76d92111dd1f167022245add0c5e2f3949137c1965abd4972ecbb2aabaeb2b5',
    'kotlin-sdk-native-consumer-sdk-lock1/packet-files.json': '8c59acde48be61ff7bc98e28eb09565e13a4cddd10f4cdd96ea4a6ffb9ac8f44',
    'kotlin-sdk-native-consumer-startup1/packet-files.json': '0230bcb675837b43ec67026d5a1f7f25180e5e13126bbfaa2ae27ba4f5459096',
    'edge-ai-canonical-batch3/batch.json': '933a3ed6c02e6b1c75485ef9e93ca815a402c1c9b88ec80eaa0e477db396c222',
    'edge-ai-canonical-inputs-preparation4/batch.json': '2df3ff50d6a6a917e8648b1bcc88f7ab4fb82082470430f2bd729ff090233288',
    'edge-ai-canonical-batch4/batch.json': '60c491c3b045e808175a84cf52d768a42cc4d9215faa74d348945b9ad3956a8b',
    'root-roster-ai-policy-documentation1/packet-files.json': 'eef11c4fec051ad5440160c1c22e094fcf19c0f5fdb9f33bb78fb3a696048d7f',
    'successor-observed-fixture-discovery1/packet-files.json': '1737e9f9b1e322e6a0c11546c2045518bcf7b83325d89895a26a32a8d4f297d1',
    'successor-observed-fixture-import-proposal1/packet-files.json': '807bdc7169a82f50dfbf1ba0518e6f540cf1806874bc5357f1822d61c4b7cb9b',
    'root-successor-source154-validation1/packet-files.json': '506057f500a37d5a3f799645cc803d11727a8520373f1ce4d7a61c8dd4f4033d',
}


def sha(path):
    assert path.is_file() and not path.is_symlink(), path
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def ref(name):
    path = BASE / name
    return {'path': str(path.relative_to(ROOT)), 'sha256': sha(path)}


def readback(name, digest):
    path = BASE / name
    assert sha(path) == digest, name
    document = json.loads(path.read_text())
    entries = document.get('files', document.get('artifacts'))
    if isinstance(entries, list):
        for row in entries:
            leaf = ROOT / row['path']
            assert leaf.resolve().is_relative_to(path.parent.resolve())
            assert sha(leaf) == row['sha256'] and leaf.stat().st_size == row['bytes']
    elif isinstance(entries, dict):
        for relative, row in entries.items():
            leaf = path.parent / relative
            assert leaf.resolve().is_relative_to(path.parent.resolve())
            assert sha(leaf) == (row if isinstance(row, str) else row['sha256'])
    else:
        raise AssertionError('Unreviewed evidence index shape: ' + name)
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--edge-failure-sha256', required=True)
    parser.add_argument('--native-preparation-sha256', required=True)
    parser.add_argument('--extra-proof', action='append', default=[], help='Exact additional evidence path=SHA256')
    args = parser.parse_args()
    proofs = dict(PROOFS)
    proofs['edge-ai-canonical-batch1/batch.json'] = args.edge_failure_sha256
    proofs['kotlin-sdk-native-consumer-preparation1/packet-files.json'] = args.native_preparation_sha256
    for value in args.extra_proof:
        name, digest = value.rsplit('=', 1)
        assert len(digest) == 64 and not Path(name).is_absolute() and '..' not in Path(name).parts
        proofs[name] = digest
    for name, digest in proofs.items():
        readback(name, digest)
    applied = json.loads((BASE / 'root-ai-dispatch-promotion-batch1/applied-verification.json').read_text())
    assert applied['status'] == 'pass' and applied['test_counts'] == [['213', '0']]
    for name, expected in applied['source_after'].items():
        assert sha(ROOT / name) == expected, name
    assert sha(LEDGER) == EXPECTED_LEDGER
    ledger = json.loads(LEDGER.read_text())
    criteria = [(r['id'], r['acceptance_requirement_from_report']) for r in ledger['items']]
    assert len(criteria) == 40
    documents = {name: json.loads((BASE.parent / name).read_text()) for name in ORIGINALS}
    assert all(canonical(d['items']) == ORIGINALS[name] for name, d in documents.items())
    owned = [LEDGER, BASE / 'IMPLEMENTATION_REGISTER.md'] + [BASE.parent / name for name in ORIGINALS]
    owned += [BASE.parent / name for name in ('PRODUCTION_REMAINING_TASKS_2026-09-30.md', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md')]
    before = {str(p.relative_to(ROOT)): sha(p) for p in owned}
    for p in owned:
        target = HERE / 'registers-before' / p.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(p.read_bytes())
        assert sha(p) == sha(target)
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    rows = {r['id']: r for r in ledger['items']}
    references = [ref(name) for name in proofs]
    edge_refs = [r for r in references if 'edge' in r['path'] or 'ci-policy' in r['path'] or 'successor' in r['path']]
    current154 = json.loads((BASE / 'root-successor-source154-validation1/promotion-result.json').read_text())
    assert current154['status'] == 'pass' and current154['current_source154_matches_accepted_private_source'] is True
    assert len(current154['current_source_after']) == 154
    assert all(sha(ROOT / name) == digest for name, digest in current154['current_source_after'].items())
    for ident in ('ARC-04', 'BE-10'):
        row = rows[ident]
        known = {r['path'] for r in row['evidence_packets']}
        row['evidence_packets'] += [r for r in edge_refs if r['path'] not in known]
        row['implementation_status'] = 'current_full_backend_154_verified_current_SQL_and_hosted_integration_open'
        row['next_action'] = (
            'Offline image acquisition is repaired through exact six Linux wheels, whole publisher metadata and receipt, physical isolated copies, hash-locked no-index installation and unchanged300/600/1200-second deadlines. '
            'Root checks the original519 evidence leaves/520 checksum rows: fresh-cache original137 source cohort passes77 contracts,83 types,565 unit tests/32 steps,91 HTTP checks,32 Linux cases,14 signed decoder HTTP cases,159 regressions and6 security tests. '
            'The supported compiler rejects a genuinely corrupted imported lock digest with exit10 under OS network denial; the earlier unsupported cached-only check argument and cleanup-parser error remain separate failed diagnostics. '
            'Current CI acquisition wiring and12 policy tests/six workflow policies pass locally; hosted CI has not been executed here. '
            'Exact AI promotion passes213 affected cases. Earlier frozen140 attempts retain seven HTTP fixture failures, a duplicate-property compiler error, and a missing publisher receipt before the Linux build. '
            'The synthetic approval fixture and its duplicate-property type correction are now applied without changing original assertions. The separately completed full140 proof passes77 contracts,86 types,643 units/32 steps,103 HTTP checks,32 Linux cases,14 signed decoder HTTP cases,212 actual regressions and6 security tests, with a fresh no-cache/network-none offline image in44.629seconds. Preserve prior HTTP/type/missing-receipt preparation failures separately. '
            'The five successor inventory/readiness consumers are now applied:13 intended repository functions,8 custom auth endpoints,17 current Ruby tests/173 assertions and authentication/Bash syntax pass; exact private34 delivery tests pass with synthetic transport. All ten genuine fixture originals are independently bound to completed52/22 local SQL producers and matching final Edge source. Root reviewed the exact478-line11-file import/loader proposal, prepared the complete154 current source graph and13 physical offline inputs, and completed one fresh full gate in42.519seconds:77 contracts,90 types,33 unit suites/668 tests/32 steps,109 HTTP checks,32 Linux cases,14 signed decoder HTTP cases,212 regressions and6 same-image security tests. All25 gateway tests pass with zero failures/ignored cases. Exactly11 reviewed files are applied; every maintained154 source hash equals the accepted private candidate and all other208 input guards remain unchanged. The literal loader now registers13. Current SQL and hosted acceptance remain separate. '
            'Keep actual current database integration separate. The original ARC-04 local criterion is fulfilled by this exact current154 graph, the immutable generated observations and the unchanged lock/runtime corruption proof. Hosted execution, current SQL and release acceptance remain separate findings.'
        )
    arc04 = rows['ARC-04']
    arc04.update(implementation_status='closed_current_local_frozen_runner_contract',
                 acceptance_status='closed_complete_original_local_criterion',
                 full_finding_closed=True,
                 closure_scope='Complete original ARC-04 local CI/lock/runner contract: current154 fresh-cache full recipe, exact lock/runtime, narrowly scoped execution, reused genuine corruption negative and generated immutable observations. Current SQL, hosted, native and production requirements remain separate.',
                 closed_at_utc=now)
    arc04['next_action'] = 'Original ARC-04 acceptance is fulfilled. Current154 fresh-cache full recipe passes 77 contracts, 90 types, 668 unit tests and 32 steps, 109 HTTP checks and all Linux/signed/regression/security phases. All 25 gateway tests pass on verified generated observations. The current lock/runtime pins retain the valid real corrupted-import rejection under OS network denial. Exact11 promotion binds all154 maintained hashes to the tested candidate; root and independent reviewer verify 548 leaves/549 checksums. Preserve this proof and original failures. Recheck affected inputs if the accepted graph changes. Current SQL, hosted CI and production acceptance remain open in their own findings.'
    ai = rows['BE-13']
    known = {r['path'] for r in ai['evidence_packets']}
    ai['evidence_packets'] += [r for r in references if ('ai-' in r['path'] or 'edge-ai-' in r['path']) and r['path'] not in known]
    ai['implementation_status'] = 'dispatch_guard_and_full_frozen_backend_verified_processor_lifecycle_open'
    ai['next_action'] = (
        'Root fully reviewed and applied exactly seven files. A bounded20-field server approval JSON and independent whole-byte SHA pin bind purpose, active window, processor/project/model/decoder endpoints and build, plus represented evidence references. '
        'An immutable nine-value effective configuration snapshot is rechecked synchronously before reservation, inside actual decoder fetch after HMAC, and directly before provider fetch after ACK/body construction. Existing trim/default normalization remains explicit. '
        'Missing/revoked/expired/mismatched records deny AI extraction; no actual policy values or approval were provisioned. Original109 cases remain byte-preserved; all213 affected tests, frozen cached-only types, default seven-file lint and format pass on applied source. '
        'Earlier private140 attempts preserve seven HTTP fixture failures, a duplicate-property type error and an omitted publisher receipt before Linux. Exact minimal fixture corrections and all13 explicit offline inputs are now verified. The subsequent fresh full140 run passes86 types,643 units/32 steps,103 HTTP checks,32 Linux cases,14 signed decoder HTTP cases,212 regressions and6 security cases with the same image. The later full154 gateway integration also passes and exactly11 reviewed consumer/fixture files are applied by byte agreement. Complete current SQL-chain acceptance remains separate. '
        'Source-bound operator documentation now enumerates the exact20 fields/four server values and current data path; official OpenAI data-control guidance was checked2October2026. Actual vendor/project/region/transfer/retention acceptance, durable policy lineage, source/derivative/backup erasure and holds, spend/model accuracy and truthful Admin disclosure remain open; Admin is held by its current writer. A valid representation does not establish real approval.'
    )
    native = rows['ARC-09']
    native_ref = ref('kotlin-sdk-native-consumer-preparation1/packet-files.json')
    known_native = {r['path'] for r in native['evidence_packets']}
    native['evidence_packets'] += [r for r in references if 'kotlin-sdk-native' in r['path'] and r['path'] not in known_native]
    native['implementation_status'] = 'private_sdk_foundation_locked_resolution_and_startup_verified_native_app_open'
    native['next_action'] = (
        'Authenticated Flutter3.44.4 publisher archive and exact8 SDK source changes are retained; isolated standalone candidate2 passes strict compile/plugin/JAR checks and137 tests across14 families. '
        'The new physically independent internal SDK foundation passes exact22415 publisher members,15660 source entries and71 legal paths; all68020 protected original metadata paths are unchanged. '
        'Enforced SDK pub resolution passes with original lock bytes and103 packages bound to owned roots. The unchanged private SDK startup passes in2.019seconds (controller35.085seconds) with exact pinned versions and full source verification. The extra reader inode-equality failure is retained and the publisher atomic same-byte engine.stamp replacement is explained; no SDK retry or byte override occurred. '
        'Source export/app resolution/native builds remain held while current shared integration is owned elsewhere. Preserve actual source/lock/SDK pins and no automatic stage advancement. '
        'Complete all-flavor/ABI native packages and artifact-bound advisory/licence/SBOM reconciliation, including AAB/IPA/web, before closing ARC09; publisher inventory/schema checks alone do not establish those acceptances.'
    )
    rows['PD-05']['next_action'] = (
        'Existing privacy destinations/anchors and generated legal graph pass locally, including unique IDs. The earlier stale-media prerequisite is resolved in the dated public4 build, which has seven fresh compiled captures and bounded downstream evidence. '
        'Those captures do not prove every legal destination or privacy outcome. Bind every generated link to intended content in an exact served build, then obtain public live GET/readback and the promised privacy-request outcome. Legal/publication acceptance remains unverified.'
    )
    gaps = ledger['supplementary_discovered_gaps']
    gaps['current_image_dependency_transport']['status'] = 'local_offline_acquisition_and_real_image_build_verified_hosted_producer_open'
    gaps['current_image_dependency_transport']['current_resolution'] = {'evidence': edge_refs, 'observed': 'Original stalls and preparation failures are retained. Real no-cache offline images and all Linux/security phases pass on the original137, composed140 and current154 graphs with exact six-wheel/publisher inputs. The current154 proof also covers all25 gateway tests and all109 HTTP checks. CI acquisition has synthetic deadline/transport negatives and reviewed wiring; no hosted producer run is claimed.'}
    gaps['flutter_included_gradle_kotlin']['current_resolution'] = {'evidence': native_ref, 'observed': 'Authenticated isolated eight-file candidate2 passed strict compiler/plugin/JAR recipe and137 tests across14 families; shared selected SDK remains unchanged. New independent SDK foundation is expanded and exact8 applied with full source/metadata readback; enforced original SDK lock resolution and unchanged pinned startup also pass. Shared SDK selection, app export, app resolution, native packages and release acceptance remain open.'}
    gaps['successor_edge_consumer_inventory'] = {'status': 'inventory_readiness_and_current154_backend_gate_verified_current_SQL_and_hosted_open', 'evidence': ref('successor-gateway-inventory-batch1/batch.json'), 'observed': 'Dated inventory gap is partly resolved by exact5 applied consumers and current17 Ruby/173 assertions/auth13/8custom/Bash checks, with private34 delivery tests. All ten genuine observation origins are bound to completed52/22 producers, the13-function literal loader and exact ten imports are applied, and the current154 graph passes90 types/668 unit tests including all25 gateway cases/109 HTTP checks and all Linux/regression/security phases. Original144 inputs were unchanged through private testing and the resulting154 maintained hashes equal the tested candidate. Current SQL, hosted activation and SMS/carrier acceptance remain separate. Intended repository active inventory is separate from hosted activation; existing device_signature mode/builtin runtime values suffice.'}
    ledger['captured_at_utc'] = now
    ledger['candidate_status'] = 'Mutable checkout. Exact AI7 applied with213 affected checks and completed full frozen140 and current154 cold backend acceptance; prior HTTP/type/input failures retained. Successor inventory/readiness5 plus reviewed loader/ten observed imports are applied; current SQL-chain and hosted proof remain pending. Private SDK foundation/locked resolution/startup pass; app/native, hosted/provider/device/store and release acceptance remain open.'
    for reference in references:
        ledger['evidence_current_readback'][reference['path'].removeprefix('docs/release/critical-implementation-2026-10-01/')] = {'checked_at_utc': now, **reference, 'scope': 'Exact bounded local evidence; no whole-finding or production approval inferred.'}
    assert [(r['id'], r['acceptance_requirement_from_report']) for r in ledger['items']] == criteria
    assert [r['id'] for r in ledger['items'] if r['full_finding_closed']] == ['ARC-04', 'PD-02', 'PD-14']
    assert all(sha(ROOT / name) == expected for name, expected in before.items())
    save(LEDGER, ledger)
    prose = (
        'Revolut remains the sole UI/UX design authority. All 141 recorded competing design paths and the retired checklist and gates are absent in the checked scope. The computer scan has protected, pruned, inaccessible and archive-format limits. Coding, security, testing, finance and professional skills remain available under the owner’s clarified scope.\n\n'
        'Exactly seven reviewed AI files are applied. All 213 affected tests, frozen type checks, default lint and formatting pass. A separately pinned server policy is checked before charging and immediately before decoder and provider dispatch. No actual processor or owner approval is provisioned. Source-bound operator documentation records the exact 20 policy fields, four server values and current data path. Vendor, project, region, transfer, retention, durable policy lineage, erasure and holds, spend, accuracy and Admin acceptance remain open.\n\n'
        'The original frozen 137-file backend completed all phases with a fresh cache and authenticated offline image. A genuinely corrupted imported lock digest was rejected with exit 10 under OS network denial. The frozen 140-file AI composition subsequently passed the full recipe. Earlier HTTP fixture, duplicate-property compiler, publisher-receipt preparation and collector failures are retained separately; their corrections preserve original assertions. Current CI acquisition wiring and 12 policy tests covering six workflow policies pass locally. Hosted CI and live publisher acquisition are not certified.\n\n'
        'The current 154-file backend graph completed the full recipe once in 42.519 seconds: 77 runner contracts, 90 type files, 33 unit suites with 668 passed tests and 32 steps, 109 HTTP checks, 32 Linux decoder cases, 14 signed decoder HTTP cases, 212 regressions and six same-image security tests. All 25 gateway tests passed, with zero failed or ignored tests and steps. The fresh cache, no-cache image build, network-none installation and all 13 offline inputs are recorded. The build, Linux and whole-run deadlines remain 300, 600 and 1,200 seconds.\n\n'
        'Root verified all ten genuine observation originals against completed local SQL producer outputs and matching Edge source, then applied only the reviewed loader change and ten exact JSON additions. All 154 maintained hashes equal the tested private candidate, and all other original input guards stayed unchanged. The intended source, typed manifest and literal HTTP loader now agree on 13 functions. Seventeen Ruby tests with 173 assertions and 34 private delivery tests also pass, with the latter scoped to synthetic transport. The observation fixtures test current decoders; they do not certify the complete current SQL chain, hosted activation or SMS and carrier delivery.\n\n'
        'Root verified and removed only the fresh task image after confirming its sole owned tag and zero containers. The supervisor container and birth-matched owned processes are absent. All 507 canonical output files are retained in the sealed proof, along with actual commands, tool identities, input provenance, pre/post source hashes and cleanup readbacks.\n\n'
        'The isolated eight-file Flutter SDK change has strict standalone compiler, plugin and JAR proof with 137 passing tests across 14 families. The new private SDK foundation verifies 22,415 publisher members, 15,660 source entries and 71 legal paths; all 68,020 protected original metadata paths remain unchanged. Enforced SDK pub resolution preserves original lock bytes and binds 103 packages to owned roots. The unchanged private SDK startup passes with exact pinned versions and full source checks. A reader’s inode-equality refusal is retained: the publisher script atomically replaces engine.stamp with identical bytes. App export, app dependency resolution and native builds have not run. The source-snapshot concurrency review is preparation only. All-flavor and ABI packages, advisory and licence review, packaged SBOM reconciliation and release selection remain open.\n\n'
        'Dated public media and compiled-browser proof, privacy renewal and owner isolation, and evidence-reader results retain their original scopes. Native visual comparison, font rights, every live legal link and promised privacy outcome, erasure, holds and revocation, encrypted archives, independent full restore and archive-free builds remain open. The obsolete PD-05 stale-media prerequisite is corrected without claiming live legal or privacy acceptance.\n\n'
        'All 40 original acceptance requirements, 102 production rows and 24 local rows are preserved. ARC-04 is closed for its complete original local criterion. PD-02 and PD-14 retain their limited closures; 37 findings remain open in full. Production remains NO-GO and the implementation goal stays active.\n\n'
    )
    path = BASE / 'IMPLEMENTATION_REGISTER.md'
    lines = path.read_text().splitlines()
    original_date = json.loads((HERE / 'registers-before' / LEDGER.relative_to(ROOT)).read_text())['captured_at_utc']
    lines = [line.replace('Updated ' + original_date + '.', 'Updated ' + now + '.', 1) for line in lines]
    for ident in ('BE-10', 'BE-13', 'ARC-04', 'ARC-09', 'PD-05'):
        row = rows[ident]
        links = [f"[{'/'.join(Path(r['path']).parts[-2:])}]({ROOT / r['path']})" for r in row['evidence_packets']]
        matches = [i for i, line in enumerate(lines) if line.startswith('| ' + ident + ' |')]
        assert len(matches) == 1
        lines[matches[0]] = f"| {ident} | {row['implementation_status']} | {'Closed' if row['full_finding_closed'] else 'Open'} | {'; '.join(links)} |"
    last = max(i for i, line in enumerate(lines) if line.startswith('| '))
    path.write_text('\n'.join(lines[:last + 1]) + '\n\n' + prose)
    for name, document in documents.items():
        extension = document['critical_review_implementation_extension']
        extension.update(captured_at_utc=now, sha256=sha(LEDGER), specialist_findings_closed=3, current_integration_note=prose)
        seen = {r['path'] for r in extension['latest_scoped_evidence']}
        extension['latest_scoped_evidence'] += [r for r in references if r['path'] not in seen]
        assert canonical(document['items']) == ORIGINALS[name]
        save(BASE.parent / name, document)
    for name in ('PRODUCTION_REMAINING_TASKS_2026-09-30.md', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md'):
        path = BASE.parent / name
        marker = '## Critical review implementation extension — 1 October 2026'
        body = path.read_text()
        assert body.count(marker) == 1
        path.write_text(body.split(marker)[0] + marker + '\n\nUpdated ' + now + '. [Current critical findings register](' + str(BASE / 'IMPLEMENTATION_REGISTER.md') + ').\n\n' + prose)
    for name, expected in ORIGINALS.items():
        d = json.loads((BASE.parent / name).read_text())
        assert canonical(d['items']) == expected and d['critical_review_implementation_extension']['sha256'] == sha(LEDGER)
    result = {'at_utc': now, 'status': 'pass', 'original40_criteria_unchanged': True, 'original_row_digests': ORIGINALS, 'closed_ids': ['ARC-04', 'PD-02', 'PD-14'], 'current_owned_files': {str(p.relative_to(ROOT)): sha(p) for p in owned}, 'production_ready': False, 'goal_status': 'active'}
    save(HERE / 'register-reconciliation.json', result)
    for p in owned:
        target = HERE / 'registers-after' / p.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(p.read_bytes())
    files = [{'path': str(p.relative_to(ROOT)), 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in sorted(HERE.rglob('*')) if p.is_file()]
    save(HERE / 'packet-files.json', {'status': 'sealed', 'scope': 'Six canonical registers reconciled while preserving all40 original criteria and102/24 original rows. ARC-04 original local criterion is closed;37 full findings and production NO-GO remain.', 'files': files})
    print(json.dumps({'status': 'pass', 'ledger_sha256': sha(LEDGER), 'closed': result['closed_ids'], 'sealed_leaves': len(files)}))


if __name__ == '__main__':
    main()
