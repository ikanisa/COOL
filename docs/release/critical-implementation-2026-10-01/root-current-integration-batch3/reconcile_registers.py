#!/usr/bin/env python3
"""One-shot integration of independently checked AI and standalone SDK scopes."""
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
EXPECTED_LEDGER = '3da193b34db38e4b60f25ad67f87098af1054bcba7b3ca3068874c031dba437a'
ORIGINALS = {
    'production-remaining-tasks-2026-09-30.json': '404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f',
    'local-implementation-register-2026-09-30.json': '0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def reference(relative):
    path = BASE / relative
    return {'path': str(path.relative_to(ROOT)), 'sha256': sha(path)}


def add(row, references):
    existing = {item['path'] for item in row['evidence_packets']}
    row['evidence_packets'].extend(item for item in references if item['path'] not in existing)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-packet-sha256', required=True)
    args = parser.parse_args()
    sdk = BASE / 'kotlin-sdk-candidate2-execution-batch1'
    assert sha(sdk / 'packet-files.json') == args.sdk_packet_sha256
    manifest = json.loads((sdk / 'packet-files.json').read_text())
    assert len(manifest['files']) == 47
    for name, expected in manifest['files'].items():
        path = sdk / name
        assert path.resolve().is_relative_to(sdk) and path.is_file() and not path.is_symlink()
        assert sha(path) == expected, name
    assert sha(LEDGER) == EXPECTED_LEDGER
    assert sha(HERE / 'ai-fixture-independent-readback.json') == '1c210aa8f7c0b89f7a32908864dfec048e1ff0bc4fd4cce0101337c86c81b5a3'
    assert sha(HERE / 'sdk-candidate2-independent-original-readback.json') == 'f6d9419613c31344a031efda4db316a47e479c5cb666eab57bb011f0338de1e9'
    fixture = json.loads((BASE / 'ai-import-fixture-lint-batch1/batch.json').read_text())
    for path, expected in fixture['source_after'].items():
        assert sha(ROOT / path) == expected, path
    terminal = json.loads((sdk / 'workflow-terminal.json').read_text())
    assert terminal['compiler_exit_code'] == terminal['complete_source_readback_exit_code'] == 0
    assert terminal['source_delta_count'] == 8 and terminal['candidate_promoted'] is False
    ledger = json.loads(LEDGER.read_text())
    criteria = [(row['id'], row['acceptance_requirement_from_report']) for row in ledger['items']]
    assert len(criteria) == 40
    documents = {name: json.loads((BASE.parent / name).read_text()) for name in ORIGINALS}
    assert all(canonical(document['items']) == ORIGINALS[name] for name, document in documents.items())
    owned = [LEDGER, BASE / 'IMPLEMENTATION_REGISTER.md'] + [BASE.parent / name for name in ORIGINALS]
    owned += [BASE.parent / name for name in ('PRODUCTION_REMAINING_TASKS_2026-09-30.md', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md')]
    backup = HERE / 'registers-before'
    backup.mkdir(exist_ok=False)
    for path in owned:
        target = backup / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        assert sha(path) == sha(target)
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    rows = {row['id']: row for row in ledger['items']}
    ai = [reference(name) for name in (
        'ai-import-review-batch1/batch.json', 'ai-import-minimization-batch1/batch.json',
        'ai-import-fixture-lint-batch1/batch.json',
        'root-current-integration-batch3/ai-design-independent-readback.json',
        'root-current-integration-batch3/ai-fixture-independent-readback.json')]
    native = [reference(name) for name in (
        'kotlin-sdk-task-compatibility-plan2/packet-files.json',
        'kotlin-sdk-candidate2-preparation-batch1/packet-files.json',
        'root-sdk-foundation-review-batch1/candidate2-preparation-readback.json',
        'kotlin-sdk-candidate2-execution-batch1/packet-files.json',
        'root-current-integration-batch3/sdk-candidate2-independent-original-readback.json')]
    add(rows['BE-13'], ai)
    rows['BE-13']['implementation_status'] = 'ai_filename_minimization_and_scoped_regressions_verified_processor_and_lifecycle_open'
    rows['BE-13']['next_action'] = 'Current data-path review distinguishes original decoder input, internal source custody and OpenAI dispatch. Provider PDF filename is now fixed collect-roster.pdf while original internal filename/hash/bytes remain; unchanged-source negative runs the same tests and fails exactly2 cases, while corrected current scope passes109 tests, frozen cached-only types, default3-file lint and format. A separate test-only fixture change preserves synchronous event/assertion/error behavior and closes the3 original require-await errors; their historical failure remains. Root independently checks audit9/minimization77/fixture76 leaves, current18 imports and87 cached modules. Explicit processor/project/region/transfer/retention approval, retained personal source/derivative/backup deletion and holds, actual account spend and extraction accuracy remain unverified. Admin disclosure changes are held with their active write owner; runtime approval configuration is a read-only proposal, not an applied or approved policy. Whole BE13 remains open.'
    add(rows['ARC-09'], native)
    rows['ARC-09']['implementation_status'] = 'authenticated_eight_file_sdk_strict_compiler_and_all_test_families_verified_native_and_release_scope_open'
    rows['ARC-09']['next_action'] = 'Candidate1 actual failure remains preserved. Fresh independent candidate2 uses exactly the reviewed3 version/checker plus5 task/test compatibility changes: no other authored bytes changed. Real full strict compileKotlin/compileTestKotlin/validatePlugins/test/jar/runtime-graph command passes in199.24s; complete built readback passes10.07s. Root reads original16 XML suites:137 tests across all14 source families, zero failures/errors/skips, including previous-KGP rejection, stable-fixed acceptance and original NPE behavior. All83 physical main class bytes match the184326-byte JAR. Critical core/compiler2.4.20 publisher bindings are scoped; actual runtime stdlib1.7.10/compiler reflect1.6.10, embedded KotlinDSL2.2 compatibility warnings and unchanged template/maxKnown2.3.20 remain recorded. Prepare separately reviewed isolated bootstrap/current all-flavor ABI/JVM/unsigned-package consumers without mutating completed candidate2 or shared SDK. Full transitive origin/licence/advisory and shipped AAB/IPA/web SBOM reconciliation, selection and release acceptance remain open.'
    add(rows['PD-14'], [ai[3]])
    ledger['captured_at_utc'] = now
    ledger['candidate_status'] = 'Mutable checkout; current public4 local scope remains distinct. Authenticated candidate2 full standalone SDK recipe and AI filename slice pass. Current cold Edge, Ubuntu write-owner integration, full native/export, hosted/provider/device/store and release acceptance remain open.'
    for item in ai + native:
        ledger['evidence_current_readback'][item['path'].removeprefix('docs/release/critical-implementation-2026-10-01/')] = {'checked_at_utc': now, **item, 'scope': 'Independently checked local scope only; no whole-finding or production approval inferred.'}
    assert [(row['id'], row['acceptance_requirement_from_report']) for row in ledger['items']] == criteria
    assert [row['id'] for row in ledger['items'] if row['full_finding_closed']] == ['PD-02', 'PD-14']
    save(LEDGER, ledger)
    prose = ('Current public4 binds344 media inputs/348 private authored inputs to fresh compilation and seven original captures,55 quality checks,104 browser cases and378 original screenshots. Root checks704 leaves and current media/source/metadata bindings. PD-02 retains its stated local provenance/current served-build closure; native visual/task/comparator acceptance, font rights and hosted/provider/store/release approval remain open.\n\n'
             'Actual default privacy renewal and owner isolation pass their four cases. The historical full136-case run preserves134 passes/two Security heading failures; the exact semantic correction passes37 affected checks, analyzer and sole-authority hygiene. Full retention/holds, Auth principal/session revocation, restartable erasure, derivatives/exports/backups and financial preservation remain open.\n\n'
             'The read-only pinned evidence reader passes61 synthetic cases. All98 real missing-trust probes resolve0 references and preserve73,167,256 original bytes. No archive, key, restore, copy, consumer migration or removal occurred. Real encrypted storage, independent restore, custody/metadata policy and archive-free build acceptance remain open.\n\n'
             'Canonical Ubuntu private formatting passes670 sources and rejects a malformed671st fixture, but three original files remain with their active write owner and no fresh current root Make is accepted. The earlier cold Edge300-second transfer failure is retained. Offline wheel preparation/CI continuation is under review; no new complete canonical Linux/HTTP/security pass is claimed.\n\n'
             'The current AI filename slice passes109 regression cases, pinned frozen cached-only types, default three-file lint and formatting. Root checks audit9/minimization77/fixture76 sealed leaves, current18 imports and87 cached modules; original failed-source and baseline-lint observations remain historical. Full processor, region, retention/holds/deletion, spend, hosted accuracy and Admin disclosure acceptance remain open.\n\n'
             'Fresh authenticated SDK candidate2 passes the complete strict standalone compiler/plugin validation/JAR/runtime recipe and137 tests across14 source families/16 original XML suites, zero failures/errors/skips. The exact eight-file source scope and83 physical main classes/JAR are independently checked. Candidate1 failures remain preserved. Mixed transitive versions/KotlinDSL warnings, bootstrap/current native ABI/all-flavor unsigned packages, complete licence/advisory/SBOM, controlled SDK selection and release remain open.\n\n'
             'Revolut remains the sole design authority: the refreshed root check finds all141 recorded competing design paths absent and the retired checklist absent. Existing protected/pruned/inaccessible computer-wide discovery limits remain. The40 original acceptance requirements,102 production rows and24 local rows are preserved; PD-02 andPD-14 retain their limited closures,38 critical findings remain open in full. Production is NO-GO; the goal remains active.\n')
    for name, document in documents.items():
        ext = document['critical_review_implementation_extension']
        ext.update(captured_at_utc=now, sha256=sha(LEDGER), specialist_findings_closed=2)
        ext['current_integration_note'] = prose
        seen = {item['path'] for item in ext['latest_scoped_evidence']}
        ext['latest_scoped_evidence'] += [item for item in ai + native if item['path'] not in seen]
        assert canonical(document['items']) == ORIGINALS[name]
        save(BASE.parent / name, document)
    path = BASE / 'IMPLEMENTATION_REGISTER.md'
    old = path.read_text()
    old_date = json.loads((backup / LEDGER.relative_to(ROOT)).read_text())['captured_at_utc']
    old = old.replace('Updated ' + old_date + '.', 'Updated ' + now + '.', 1)
    lines = old.splitlines()
    for finding in ('BE-13', 'ARC-09', 'PD-14'):
        row = rows[finding]
        label = 'Closed: authority hygiene only' if row['full_finding_closed'] else 'Open'
        links = [f"[{'/'.join(Path(item['path']).parts[-2:])}]({ROOT / item['path']})" for item in row['evidence_packets']]
        replacement = f"| {finding} | {row['implementation_status']} | {label} | {'; '.join(links)} |"
        matches = [i for i, line in enumerate(lines) if line.startswith('| ' + finding + ' |')]
        assert len(matches) == 1
        lines[matches[0]] = replacement
    last_table_row = max(i for i, line in enumerate(lines) if line.startswith('| '))
    path.write_text('\n'.join(lines[:last_table_row + 1]) + '\n\n' + prose)
    for name in ('PRODUCTION_REMAINING_TASKS_2026-09-30.md', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md'):
        path = BASE.parent / name
        marker = '## Critical review implementation extension — 1 October 2026'
        before = path.read_text()
        assert before.count(marker) == 1
        path.write_text(before.split(marker)[0] + marker + '\n\nUpdated ' + now + '. [Current critical findings register](' + str(BASE / 'IMPLEMENTATION_REGISTER.md') + ').\n\n' + prose)
    for name, expected in ORIGINALS.items():
        current = json.loads((BASE.parent / name).read_text())
        assert canonical(current['items']) == expected
        assert current['critical_review_implementation_extension']['sha256'] == sha(LEDGER)
    result = {'at_utc': now, 'status': 'pass', 'original40_criteria_unchanged': True,
              'original_row_digests': ORIGINALS, 'closed_ids': ['PD-02', 'PD-14'],
              'current_owned_files': {str(path.relative_to(ROOT)): sha(path) for path in owned},
              'sdk_packet_leaves_checked': len(manifest['files']), 'production_ready': False, 'goal_status': 'active'}
    save(HERE / 'register-reconciliation.json', result)
    print(json.dumps({'status': 'PASS', 'ledger_sha256': sha(LEDGER), 'closed': result['closed_ids'], 'original_rows': [102, 24]}))


if __name__ == '__main__':
    main()
