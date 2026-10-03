"""Root-only, one-shot checkpoint update. Drafting this file does not execute it."""
import argparse
import copy
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
BASE = HERE.parent
ROOT = HERE.parents[3]
PREFIX = str(BASE.relative_to(ROOT)) + '/'
LABELS = BASE / 'root-current-readiness-historical-labels1/label-result.json'
LABELS_SHA = '99b9ccf4f64931c9e2e81dccc2a0a1aca1a519a5a50825dbac7d1bf951a74c08'
CLOSED = ['ARC-04', 'PD-02', 'PD-14']
ITEMS = {
    'docs/release/production-remaining-tasks-2026-09-30.json': (102, '404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f'),
    'docs/release/local-implementation-register-2026-09-30.json': (24, '0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980'),
}
FIXED = {
    'ordinary-recovery-replay-execution4/packet-files.json': '2ee27affe5c488155729fb7a5bad0b20e975dd63d5753a988f5577efaec48975',
    'ordinary-recovery-replay-preparation5/packet-files.json': 'ee79028e37a0cbf9272584705994341b86304eb886a2631dfc8819126eb814f2',
    'hosted-parity-readback1/packet-files.json': '2d1dc0992d06f5fa0f071e80d5632d16fb6b2e3b3258457b776abacc8249acd7',
    'root-hosted-parity-readback-review1/review.json': '2fd7f34978a36fcc8c322714514f0dc773d8e2f0dcbc9951ccd2625d50297d2e',
    'ordinary-recovery-replay-execution5/packet-files.json': 'c75e8a35ea208f855217b11b73492eb9e58b8f9341286c353b9b62c0b70553ba',
    'ordinary-recovery-replay-execution5/readback.json': 'e5a5164f14636855cfa86be25fac2c7b218e7dfc40c5eb0a89afbe5589f968f9',
    'ordinary-recovery-replay-execution5/actual-result.json': '8ea040fcc835d24671c568cb039b217f61a76b3745ff7ae4f024bf149631efa7',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()


def canonical(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique_pairs)


def load_ref(ref):
    require(isinstance(ref, dict) and set(ref) == {'path', 'sha256'}, 'Incomplete reference')
    name, expected = ref['path'], ref['sha256']
    require(isinstance(name, str) and name.startswith(PREFIX) and '..' not in Path(name).parts,
            'References must be inside the private release evidence tree')
    require(isinstance(expected, str) and re.fullmatch('[0-9a-f]{64}', expected), 'Missing exact SHA256')
    path = ROOT / name
    require(path.is_file() and not path.is_symlink() and path.resolve() == path.absolute(), 'Missing or indirect evidence: ' + name)
    data = path.read_bytes()
    require(digest(data) == expected, 'Evidence drift: ' + name)
    return parse(data)


def observe(document, observation):
    require(isinstance(observation, dict) and set(observation) == {'pointer', 'expected'}, 'Incomplete observation')
    pointer = observation['pointer']
    require(isinstance(pointer, str) and pointer.startswith('/'), 'Missing exact JSON pointer')
    actual = document
    for token in pointer[1:].split('/'):
        token = token.replace('~1', '/').replace('~0', '~')
        actual = actual[int(token)] if isinstance(actual, list) else actual[token]
    require(type(actual) is type(observation['expected']) and actual == observation['expected'],
            'Observation mismatch: ' + pointer)
    return actual


def native_receipt(value):
    require(value['final'] is True, 'Native receipt still missing or running')
    packet, readback = load_ref(value['packet']), load_ref(value['readback'])
    leaf = Path(value['readback']['path']).relative_to(Path(value['packet']['path']).parent).as_posix()
    require(any(row['path'] == leaf and row['sha256'] == value['readback']['sha256'] for row in packet['files']),
            'Native final readback is not bound by its packet')
    require(value['terminal_status']['pointer'] == '/status', 'Bind the final readback status, not a child case status')
    status = observe(readback, value['terminal_status'])
    require(isinstance(status, str) and re.fullmatch(r'(?:pass|passed|fail|failed|complete|completed|unrun|not_run|not_admitted|unadmitted|refused|blocked)(?:[_:-].*)?', status),
            'Native receipt has no terminal disposition')
    return readback


def stage_outcome(document, binding, stage):
    require(set(binding) == {'outcome', 'stage_identity', 'observation'}, 'Incomplete whole-stage binding')
    identity = binding['stage_identity']
    pointer = binding['observation']['pointer']
    require(isinstance(pointer, str) and pointer.rsplit('/', 1)[-1] in ('stage_pass', 'outcome')
            and identity['pointer'] == pointer.rsplit('/', 1)[0] + '/stage'
            and identity['expected'] == stage and observe(document, identity) == stage,
            'Bind the matching whole-stage terminal object, not a child result')
    outcome, value = binding['outcome'], observe(document, binding['observation'])
    accepted = {
        'pass': value is True or isinstance(value, str) and value in ('pass', 'passed'),
        'failed': value is False or isinstance(value, str) and value in ('fail', 'failed', 'refused'),
        'unrun': isinstance(value, str) and value in ('unrun', 'not_run'),
        'not_admitted': value is False or isinstance(value, str) and value in ('not_admitted', 'unadmitted'),
    }
    require(outcome in accepted and accepted[outcome], 'Whole-stage outcome is not supported by its exact observation')
    return outcome


def item_contract(rows):
    return [{key: copy.deepcopy(value) for key, value in row.items()
             if key not in ('implementation_status', 'next_action', 'evidence_packets')} for row in rows]


def main(input_path):
    require(HERE.name == 'root-current-readiness-integration3', 'Wrong updater location')
    require(digest(LABELS.read_bytes()) == LABELS_SHA, 'Starting authority receipt changed')
    expected = parse(LABELS.read_bytes())['after_sha256']
    before = {name: (ROOT / name).read_bytes() for name in expected}
    require(len(before) == 6 and all(digest(data) == expected[name] for name, data in before.items()), 'Six-register starting fence changed')
    input_bytes = input_path.read_bytes()
    config = parse(input_bytes)
    require(set(config) == {'schema_version', 'captured_at_utc', 'recovery5', 'native_guard', 'native_stages'} and config['schema_version'] == 1,
            'Wrong checkpoint-input contract')
    now = config['captured_at_utc']
    require(isinstance(now, str) and datetime.datetime.fromisoformat(now.replace('Z', '+00:00')).utcoffset() == datetime.timedelta(0),
            'Missing final UTC checkpoint time')
    refs = [{'path': PREFIX + name, 'sha256': sha} for name, sha in FIXED.items()]
    fixed = {entry['path']: load_ref(entry) for entry in refs}
    require(config['recovery5'] == {key: {'path': PREFIX + 'ordinary-recovery-replay-execution5/' + name, 'sha256': FIXED['ordinary-recovery-replay-execution5/' + name]}
                                  for key, name in [('packet', 'packet-files.json'), ('readback', 'readback.json'), ('actual_result', 'actual-result.json')]},
            'Completed recovery5 binding changed')
    recovery = fixed[config['recovery5']['readback']['path']]
    actual = fixed[config['recovery5']['actual_result']['path']]
    require(actual['status'] == 'pass' and actual.get('completed_at') and len(actual['cases']) == 27
            and all(case['status'] == 'pass' for case in actual['cases']), 'Recovery5 is not the completed 27-case pass')
    require(recovery['passing_cases'] == 27 and recovery['whole_bounds'] == [600, 540, 60]
            and recovery['cleanup_errors'] == [] and recovery['both_owned_containers_removed'] is True,
            'Recovery5 bounded completion/cleanup mismatch')
    for key in ('current216_source_hashes_unchanged', 'admitted222_files_unchanged', 'restored_predecessor_catalog_and_effective_ACLs_passed',
                'forward85_original_migrations_complete_as_postgres_NOSUPERUSER', 'complete_final209_catalog_and_effective_ACLs_match_sealed_current209',
                'all18_projection_parity_before_after_repairs_restore_and_every_forward_migration', 'earlier_actual_failures_preserved_not_reclassified'):
        require(recovery[key] is True, 'Recovery5 scoped milestone missing: ' + key)
    for key in ('full_BE08_closed', 'ARC08_shipping_restore_adapter_closed', 'ARC11_full_system_recovery_closed', 'hosted_or_provider_execution', 'production_ready'):
        require(recovery[key] is False, 'Unsupported recovery5 closure: ' + key)
    hosted = fixed[PREFIX + 'root-hosted-parity-readback-review1/review.json']
    require(hosted['fresh_hosted_parity'] == 'unobserved' and hosted['fresh_hosted_permission_refused'] is True
            and hosted['no_additional_hosted_calls'] is True and hosted['no_finding_closed'] is True, 'Hosted unknown scope changed')
    guard, stages = native_receipt(config['native_guard']), native_receipt(config['native_stages'])
    passed = observe(guard, config['native_guard']['passing_cases'])
    total = observe(guard, config['native_guard']['total_cases'])
    reader_pass = observe(guard, config['native_guard']['reader_pass'])
    reader_seconds = observe(guard, config['native_guard']['reader_seconds'])
    require(type(passed) is int and type(total) is int and 0 <= passed <= total and total > 0 and type(reader_pass) is bool
            and type(reader_seconds) in (int, float) and math.isfinite(reader_seconds) and reader_seconds > 0, 'Invalid native guard counts/reader outcome')
    export = stage_outcome(stages, config['native_stages']['whole_export'], 'app-export')
    lock = stage_outcome(stages, config['native_stages']['whole_app_lock'], 'app-lock')
    native = stage_outcome(stages, config['native_stages']['whole_native'], 'native')
    admitted = observe(stages, config['native_stages']['native_admitted'])
    require(type(admitted) is bool and observe(stages, config['native_stages']['native_packages_built']) is False,
            'Bind actual native admission; this compilation/JVM/graph scope does not assemble packages')
    require(native != 'pass' or (export == lock == 'pass' and admitted), 'Native pass requires its admitted predecessor whole stages')
    require(native != 'not_admitted' or not admitted, 'Unadmitted native outcome contradicts admission')
    for value in (config['native_guard'], config['native_stages']):
        refs.extend([value['packet'], value['readback']])
    ledger_name = PREFIX + 'implementation-ledger.json'
    ledger = parse(before[ledger_name])
    original = item_contract(ledger['items'])
    require(len(original) == 40 and sorted(row['id'] for row in ledger['items'] if row['full_finding_closed']) == CLOSED, 'Original finding scope changed')
    rows = {row['id']: row for row in ledger['items']}
    recovery_note = ('Actual committed recovery5 passes 27/27 in 301.559782 seconds within 600/540/60 second bounds: durable dump, source removal, independent restore, '
                     'strict predecessor catalog/effective ACL parity, 85 original forward migrations, final 209 full catalog/ACL parity and all 18 projections after each migration. '
                     'Both owned containers are removed and cleanup has no errors. Original 216/admitted 222 inputs remain unchanged. Attempts 1–4 remain retained genuine failures; '
                     'attempt4 had 22 passes then failed on nonblocking stdin EAGAIN. No full owner/runtime/history, shipping restore adapter, real approval or full-system closure is inferred.')
    hosted_note = ('Fresh purpose-built read-only access to the exact linked Collect project was refused; hosted parity remains unknown and the cause is unclassified. '
                   'No further hosted calls were made. September 30 metadata has 124 IDs versus 209 current source IDs and three common ID/name differences; '
                   'its 11 Edge functions versus 13 current source/config/deploy/probe functions is a dated comparison, not today\'s pending inventory. '
                   'Fresh hosted migration/function/JWT/bundle/server/catalog and authorized runtime security acceptance remain unobserved.')
    native_note = (f'The final native guard receipt records {passed}/{total} cases and isolated reader pass={str(reader_pass).lower()} in {reader_seconds:.6f} seconds. '
                   f'The separately bound whole strict export outcome is {export}; whole app-lock outcome is {lock}. '
                   f'The separately bound native release-Kotlin compilation, SDK/Production graph and ProductionDebug JVM test outcome is {native}; native admission={str(admitted).lower()}. '
                   'This local stage does not assemble app packages. Packages remain unbuilt and all-flavor/ABI artifact completeness remains false. '
                   'Retained older export/app-lock failures stay failed; child or guard outcomes do not establish whole-stage success. '
                   'Complete remaining whole stages, all-flavor/ABI packages, store/device checks, advisory/license review and artifact-bound SBOM reconciliation; full ARC09 acceptance remains open.')
    row_refs = {
        **{ident: ['hosted-parity', 'root-hosted'] for ident in ('BE-01', 'BE-03', 'BE-10', 'ARC-03')},
        **{ident: ['ordinary-recovery'] for ident in ('BE-08', 'BE-09', 'ARC-08', 'ARC-11')},
        'ARC-09': [config['native_guard']['packet']['path'], config['native_guard']['readback']['path'], config['native_stages']['packet']['path'], config['native_stages']['readback']['path']],
        'PD-12': [entry['path'] for entry in refs],
    }
    for ident, selectors in row_refs.items():
        row = rows[ident]
        known = {entry['path']: entry['sha256'] for entry in row['evidence_packets']}
        for entry in refs:
            if any(token in entry['path'] for token in selectors):
                require(entry['path'] not in known or known[entry['path']] == entry['sha256'], 'Retained evidence path changed')
                if entry['path'] not in known:
                    row['evidence_packets'].append(entry)
                    known[entry['path']] = entry['sha256']
        if ident in ('BE-01', 'BE-03', 'BE-10', 'ARC-03'):
            row.update(implementation_status='current13_local_inventory_verified_fresh_hosted_permission_refused_parity_unknown', next_action=hosted_note + ' Obtain authorized exact-target readback and complete the original finding criterion.')
        elif ident in ('BE-08', 'BE-09', 'ARC-08', 'ARC-11'):
            # Existing maintained mapper/management findings remain visible alongside the new restore milestone.
            row.update(implementation_status='local_committed_recovery5_and_forward85_verified_full_acceptance_open', next_action=recovery_note + ' ' + {
                'BE-08': 'Maintained mapper49/management3 results remain valid in their exact scope; 125 function mappings, 74 objects and 58 caller sites remain unresolved. Resolve ownership, historical coverage and hosted runtime graph acceptance.',
                'BE-09': 'Complete approved database/permissions/Auth/Storage/configuration/queue/revocation recovery and independent RPO/RTO acceptance.',
                'ARC-08': 'Maintained PostgreSQL query/migration admission and management3 checks remain scoped passes. Complete shipping pg_dump/pg_restore admission, embedded CLI database tooling/image provenance and real approved client/server compatibility.',
                'ARC-11': 'Complete full-system dependencies, approved RPO/RTO measurement and independent owner recovery acceptance.',
            }[ident])
        elif ident == 'ARC-09':
            row.update(implementation_status=f'native_guard_scoped_receipt_whole_export_{export}_whole_app_lock_{lock}_whole_native_{native}_packages_unbuilt', next_action=native_note)
        else:
            row['next_action'] = 'The current checkpoint retains all 40 original findings and 102 production/24 local rows. ' + recovery_note + ' ' + hosted_note + ' ' + native_note + ' Complete the final source/dependency/artifact index after remaining integration and font-rights decisions.'
    checkpoint = dict(captured_at_utc=now, input_path=str(input_path.relative_to(ROOT)), input_sha256=digest(input_bytes),
                      references=refs, recovery5='scoped_local_pass27', hosted_parity='unknown_permission_refused',
                      native_guard_cases=[passed, total], native_reader_pass=reader_pass, whole_export=export, whole_app_lock=lock,
                      whole_native=native, native_admitted=admitted, native_packages_built=False,
                      all_flavor_ABI_artifact_completeness=False, closed_ids=CLOSED, full_findings_open=37,
                      release_decision='NO-GO', goal_status='active')
    for entry in refs:
        ledger['evidence_current_readback'][entry['path'].removeprefix(PREFIX)] = dict(checked_at_utc=now, **entry, scope='Exact completed scoped receipt or recorded terminal unrun disposition; no whole-system or release closure inferred.')
    ledger.update(captured_at_utc=now, latest_checkpoint=checkpoint, goal_status='active', release_decision='NO-GO',
                  candidate_status='Mutable shared checkout. Maintained mapper49 and management3 checks retain their exact scope. ' + recovery_note + ' ' + hosted_note + ' ' + native_note)
    require(item_contract(ledger['items']) == original, 'Original40 titles, criteria, acceptance/status or closure changed')
    note = (f'Current implementation checkpoint — {now}. **Three original findings remain closed (ARC-04, PD-02 and PD-14); 37 remain open in full. Production NO-GO; goal active.**\n\n'
            + recovery_note + '\n\n' + hosted_note + '\n\n' + native_note + '\n\n'
            + 'Maintained schema mapper49 and affected management3 checks retain their recorded scope. All 40 original human titles and acceptance criteria, 102 production rows and 24 local rows remain unchanged. '
              'The previous checkpoint below is superseded for current status; its observations and failures remain historical evidence. Hosted, device/provider, privacy/erasure, font rights, signed packages, full recovery and owner/release acceptance remain open.\n')
    outputs = {ledger_name: encoded(ledger)}
    lines = ['# Critical findings implementation register', '', f'Updated {now}. **37 findings remain open; production NO-GO; goal active.**', '',
             'Revolut remains the sole UI/UX and product visual design authority.', '',
             '| Finding | Original finding title | Current local implementation | Full acceptance | Latest scoped evidence |', '| --- | --- | --- | --- | --- |']
    for row in ledger['items']:
        links = '; '.join(f"[{Path(entry['path']).parent.name}]({ROOT / entry['path']})" for entry in row['evidence_packets'][-2:])
        safe = lambda value: str(value).replace('|', '\\|').replace('\n', ' ')
        lines.append(f"| {row['id']} | {safe(row['title'])} | {safe(row['implementation_status'].replace('_', ' '))} | {'Closed in original recorded scope' if row['full_finding_closed'] else 'Open'} | {links} |")
    lines += ['', note, f'All original criteria and retained evidence are in [implementation-ledger.json]({ROOT / ledger_name}).']
    outputs[PREFIX + 'IMPLEMENTATION_REGISTER.md'] = ('\n'.join(lines) + '\n').encode()
    for name, (count, item_sha) in ITEMS.items():
        document = parse(before[name])
        require(len(document['items']) == count and canonical(document['items']) == item_sha, 'Original item array changed: ' + name)
        original_items = copy.deepcopy(document['items'])
        extension = document['critical_review_implementation_extension']
        extension.update(captured_at_utc=now, sha256=digest(outputs[ledger_name]), specialist_findings_closed=3,
                         current_integration_note=note.strip(), current_schema_progress_note=note.strip(),
                         latest_checkpoint=dict(checkpoint, ledger_sha256=digest(outputs[ledger_name])))
        known = {entry['path']: entry['sha256'] for entry in extension['latest_scoped_evidence']}
        for entry in refs:
            require(entry['path'] not in known or known[entry['path']] == entry['sha256'], 'Original extension evidence changed')
            if entry['path'] not in known:
                extension['latest_scoped_evidence'].append(entry)
                known[entry['path']] = entry['sha256']
        require(document['items'] == original_items and canonical(document['items']) == item_sha, 'Original acceptance rows changed')
        outputs[name] = encoded(document)
    for name in ('docs/release/PRODUCTION_REMAINING_TASKS_2026-09-30.md', 'docs/release/LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md'):
        heading, rest = before[name].decode().split('\n', 1)
        require(rest.count('Current implementation checkpoint —') >= 1, 'Previous top checkpoint missing')
        rest = rest.replace('Current implementation checkpoint —', 'Historical implementation checkpoint (superseded by the checkpoint above) —', 1)
        outputs[name] = (heading + '\n\n' + note + '\n' + rest).encode()
    require(set(outputs) == set(expected), 'Updater is not restricted to the six canonical registers')
    require(all(digest((ROOT / name).read_bytes()) == sha for name, sha in expected.items()), 'Starting source fence drifted before writes')
    require(input_path.read_bytes() == input_bytes, 'Final checkpoint input changed before writes')
    for entry in refs:
        load_ref(entry)
    execution = HERE / 'execution'
    execution.mkdir(exist_ok=False)
    (execution / 'checkpoint-input.json').write_bytes(input_bytes)
    for name in expected:
        for boundary, data in [('before', before[name]), ('after', outputs[name])]:
            destination = execution / ('registers-' + boundary) / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
    written = []
    try:
        for name, data in outputs.items():
            destination = ROOT / name
            temporary = destination.with_name(destination.name + '.integration3.tmp')
            with temporary.open('xb') as stream:
                stream.write(data)
            os.replace(temporary, destination)
            written.append(name)
    except BaseException:
        for name in written:
            (ROOT / name).write_bytes(before[name])
        raise
    after = {name: digest((ROOT / name).read_bytes()) for name in expected}
    require(all(after[name] == digest(data) for name, data in outputs.items()), 'Written bytes do not match prepared output')
    receipt = dict(status='pass', captured_at_utc=now, before_sha256=expected, after_sha256=after,
                   original40_titles_criteria_status_and_closures_preserved=True,
                   original102_and24_item_sha256={name: value[1] for name, value in ITEMS.items()},
                   closed_ids=CLOSED, full_findings_open=37, ledger_sha256=after[ledger_name],
                   release_decision='NO-GO', goal_status='active', checkpoint=checkpoint, tests_rerun=False)
    (execution / 'reconciliation.json').write_bytes(encoded(receipt))
    files = [{'path': str(path.relative_to(execution)), 'bytes': path.stat().st_size, 'sha256': digest(path.read_bytes())}
             for path in sorted(execution.rglob('*')) if path.is_file()]
    (execution / 'packet-files.json').write_bytes(encoded(dict(status='sealed', files=files)))
    print(json.dumps(dict(status='pass', registers=6, open=37, closed=3, ledger_sha256=after[ledger_name], packet_sha256=digest((execution / 'packet-files.json').read_bytes()))))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=HERE / 'checkpoint-input.json')
    args = parser.parse_args()
    main(args.input.resolve())
