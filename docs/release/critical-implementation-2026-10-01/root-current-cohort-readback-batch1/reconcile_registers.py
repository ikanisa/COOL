#!/usr/bin/env python3
"""Reconcile scoped, actually executed cohorts without altering original rows."""
import datetime
import hashlib
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[4]
BASE = pathlib.Path(__file__).resolve().parent
REGISTER = BASE.parent
LEDGER = REGISTER / 'implementation-ledger.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(
        value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def packet(relative):
    path = REGISTER / relative
    if not path.is_file():
        raise RuntimeError(f'Missing completed packet: {relative}')
    return {'path': str(path.relative_to(ROOT)), 'sha256': sha(path)}


def add(row, relatives):
    seen = {entry['path'] for entry in row['evidence_packets']}
    for relative in relatives:
        entry = packet(relative)
        if entry['path'] not in seen:
            row['evidence_packets'].append(entry)
            seen.add(entry['path'])


timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
ledger = json.loads(LEDGER.read_text())
criteria = [(row['id'], row['acceptance_requirement_from_report'])
            for row in ledger['items']]
assert len(criteria) == 40
originals = {
    'production-remaining-tasks-2026-09-30.json':
        '404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f',
    'local-implementation-register-2026-09-30.json':
        '0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980',
}
documents = {name: json.loads((REGISTER.parent / name).read_text())
             for name in originals}
for name, expected in originals.items():
    assert canonical(documents[name]['items']) == expected, name

owned = [LEDGER, REGISTER / 'IMPLEMENTATION_REGISTER.md']
owned += [REGISTER.parent / name for name in originals]
owned += [REGISTER.parent / name for name in [
    'PRODUCTION_REMAINING_TASKS_2026-09-30.md',
    'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md']]
backup = BASE / 'registers-before'
backup.mkdir(exist_ok=False)
for path in owned:
    target = backup / path.relative_to(ROOT)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, target)
    assert sha(path) == sha(target)

rows = {row['id']: row for row in ledger['items']}
privacy = [
    'privacy-client-auth-batch2/batch.json',
    'privacy-ui-consumer-tests-batch1/batch.json',
    'privacy-ui-integration-batch1/batch.json',
    'root-current-cohort-readback-batch1/sealed-artifacts-readback.json',
]
add(rows['BE-05'], privacy)
rows['BE-05']['implementation_status'] = (
    'own_request_recovery_otp_and_logout_consumer_verified_full_lifecycle_open')
rows['BE-05']['next_action'] = (
    'The 202-migration packet passes 27 current-status plus 53 retained intake '
    'checks, 244-table rollback and 84 pinned-SDK client checks. The integrated '
    'member screen adds 25 route/widget checks and 39 default-logout/Auth '
    'regressions, with fixed errors, own-server canonical receipt recovery, '
    'explicit same-UUID retry and synchronous logout invalidation. The widget '
    'cohort uses a fixture financial repository and no production global '
    'redirect: same-UID OTP renewal through the actual default repository and '
    'appRouterProvider is being tested separately and is not accepted here. '
    'Configured CAPTCHA has no solver and safely shows assistance. Complete '
    'the approved per-class schedule/holds, principal/FK plan, bounded '
    'restartable erasure and derivative/export/backup/session-revocation and '
    'financial-preservation completion proof. No erasure or hosted acceptance.')
add(rows['BE-08'], ['privacy-client-auth-batch2/batch.json'])
add(rows['BE-06'], ['privacy-ui-integration-batch1/batch.json'])
rows['BE-06']['next_action'] = (
    'The privacy consumer disables OTP when configured CAPTCHA has no solver '
    'and exposes fixed help while retaining own-server status recovery. Main '
    'Auth CAPTCHA/provider integration and actual hosted admission, OTP '
    'delivery, account/session changes and recovery still require their '
    'original acceptance; no provider pass is inferred from synthetic HTTP.')

public = ['public-media-batch2/batch.json', 'public-share-ui-batch1/batch.json',
          'public-media-batch3/batch.json',
          'root-current-cohort-readback-batch1/sealed-artifacts-readback.json']
for finding in ['PD-01', 'PD-07', 'ARC-08']:
    add(rows[finding], public)
add(rows['PD-01'], ['privacy-ui-consumer-tests-batch1/batch.json'])
rows['PD-01']['implementation_status'] = (
    'current_local_public_and_privacy_rendering_verified_full_fidelity_open')
rows['PD-01']['next_action'] = (
    'Fresh private media compilation and full local public build pass 55 quality '
    'checks and 104 real browser cases with 378 originals, including top-of-page '
    'invalid group action and generic app-link states. All 348 copied authored '
    'inputs and 344 media inputs bind the dated runtime. Privacy widget checks '
    'cover 320px, 3x text, keyboard and four themes. Use the sole Revolut skill '
    'directly to review current Android/iOS, exact legal/deletion comparators, '
    'actual protected routes/interactions and full task outcomes; main-entry '
    'startup, native geometry, rights and independent owner acceptance remain '
    'outside the synthetic public preview. No full fidelity or release closure.')
rows['PD-07']['implementation_status'] = (
    'current_capability_copy_and_full_local_public_routes_verified')
rows['PD-07']['next_action'] = (
    'Reviewed capability source bindings include current own-account privacy '
    'intake eligibility while availability/actions/approval flags remain '
    'unchanged. The unchanged 15-route/20-input copy contract, fresh strict '
    'publication/static build, 55 quality checks and 104 browser cases pass '
    'for the dated local public candidate. Generic /app copy and inactive '
    'invalid-group roles are corrected and directly inspected. Obtain named '
    'approved availability/provider facts and actual conversion/support/store '
    'outcomes; no native, rights, legal, hosted or production approval.')

sdk = ['kotlin-sdk-candidate-plan1/packet-files.json',
       'kotlin-sdk-foundation-batch1/packet-files.json',
       'root-sdk-foundation-review-batch1/sealed-packets-readback.json',
       'root-sdk-foundation-review-batch1/exact-checkout-delta-review.json']
add(rows['ARC-09'], sdk)
rows['ARC-09']['next_action'] = (
    'Retained frozen app/file_saver compilation and 12 JVM units pass; included '
    'Flutter SDK KGP 2.2.20 and runtime KGP 2.0.0 remain unresolved. A fresh '
    'official 3.44.4 ARM64 archive has complete publisher SHA256/MD5 readback, '
    'canonical raw Git/tree binding and all tracked-source RAM comparison; '
    '33 exact Windows CRLF checkout representations and 15 contained cache '
    'framework aliases are individually reviewed. Root independently reread '
    '117 sealed foundation/plan leaves and all 33 canonical transformations. '
    'The archive is not yet expanded/executed/patched or selected. Complete '
    'physically independent full extraction/readback and the exact three-file '
    'SDK repair, actual compiler/runtime/ABI/current consumer tests, '
    'authenticated advisory/license triage and packaged AAB/IPA/web SBOM. '
    'Local DSSE/PGP signature verification remains unperformed.')
rows['ARC-01']['implementation_status'] = (
    'portable_executable_fix_verified_actual_clean_ubuntu_formatter_fails')
rows['ARC-01']['next_action'] = (
    'Actual Ubuntu 24.04.5 ARM64 with pinned Dart 3.12.2 executes the maintained '
    'Make command over all 669 captured Dart paths and fails: 15 formatting '
    'differences. Read-only language-resolution diagnostics distinguish '
    '12 missing-clean-package-config effects from three real host formatter '
    'failures. No malformed fixture or pass claim. Resolve the three files by '
    'their write owners, perform canonical pinned Flutter/enforced-lock Pub '
    'bootstrap in a fresh official Ubuntu amd64 checkout, then prove '
    'malformed rejection and all reviewed source acceptance through unchanged '
    'Make. Do not narrow the inventory or waive the gate.')
arc_failed = REGISTER / 'arc01-ubuntu-batch1/batch.json'
if arc_failed.exists():
    add(rows['ARC-01'], ['arc01-ubuntu-batch1/batch.json'])

for relative in [
    'root-current-cohort-readback-batch1/sealed-artifacts-readback.json',
    'root-sdk-foundation-review-batch1/sealed-packets-readback.json',
]:
    entry = packet(relative)
    ledger['evidence_current_readback'][relative] = {
        'checked_at_utc': timestamp, **entry,
        'scope': 'Independent sealed artifact readback only; dated cohort '
                 'limitations remain and the mutable checkout is not accepted.',
    }
ledger['supplementary_discovered_gaps']['privacy_global_route_consumer'] = {
    'status': 'test_coverage_gap_under_actual_default_consumer_review',
    'observed': 'The passing privacy route widget cohort substitutes the '
                'financial repository and omits the global Auth redirect. '
                'Actual same-UID/new-SID renewal with default repository and '
                'appRouterProvider is not covered by that evidence.',
    'next_action': 'Establish actual behavior with held native/cache/member '
                   'reads and the unchanged production guard before any fix '
                   'or successful integration claim.',
}
ledger['captured_at_utc'] = timestamp
assert [(x['id'], x['acceptance_requirement_from_report'])
        for x in ledger['items']] == criteria
assert [x['id'] for x in ledger['items'] if x['full_finding_closed']] == ['PD-14']
save(LEDGER, ledger)

new_packets = privacy + public + sdk
latest = []
seen = set()
for relative in new_packets:
    if relative not in seen:
        latest.append(packet(relative))
        seen.add(relative)
integration_note = (
    'Current scoped privacy UI/logout and 202-migration own-status evidence '
    'passes, while actual global-router OTP renewal is under review. Fresh '
    'local public publication/build passes 55 quality and 104 browser cases. '
    'Frozen native compilation and 12 JVM units pass; included SDK advisory '
    'components remain unresolved despite authenticated fresh foundation '
    'preflight. Actual clean Ubuntu formatting fails and has no fixture/pass '
    'claim. Full Edge still fails its genuine Pillow acquisition deadline. '
    'Only PD-14 authority hygiene is closed; all original row acceptance and '
    'immutable candidate/external requirements remain unchanged.')
for name, document in documents.items():
    extension = document['critical_review_implementation_extension']
    extension.update({'captured_at_utc': timestamp, 'sha256': sha(LEDGER),
                      'current_integration_note': integration_note})
    present = {x['path'] for x in extension['latest_scoped_evidence']}
    extension['latest_scoped_evidence'] += [
        x for x in latest if x['path'] not in present]
    assert canonical(document['items']) == originals[name]
    save(REGISTER.parent / name, document)

prose = (
    'Fresh public media comes from a physically private current source cohort '
    'and a new compilation. The strict local publication and full static build '
    'pass 55 quality checks and 104 browser cases across every one of 18 HTML '
    'entries at four viewports, plus group/app invitation states. All 378 '
    'original browser images are retained. Root independently verifies 2,007 '
    'indexed leaves from the privacy/public packets. Source and artifact '
    'identity establish those dated scopes; native task completion, exact '
    'Revolut fidelity, rights, legal and production approval remain open.\n\n'
    'The privacy consumer now recovers only an own-server canonical request, '
    'uses subject-bound fresh OTP, confirms before submission, retains the same '
    'UUID for an explicit retry and fences logout before any await. The new '
    '202-migration packet proves 27 own-status plus 53 preserved intake checks, '
    '244-table rollback and 84 client checks. Integrated route/widget and '
    'default-logout/Auth checks pass 25 and 39 tests respectively. The widget '
    'cohort substitutes financial data and omits the global Auth redirect; '
    'actual default-provider/router OTP renewal is being tested separately. '
    'Configured CAPTCHA has no solver and shows assistance. The approved '
    'retention/hold policy, principal/FK plan, full bounded erasure, derivatives, '
    'backups, session revocation and preserved journals/balances remain open.\n\n'
    'Actual clean Ubuntu formatting fails on the captured 669-file inventory. '
    'Twelve additional clean differences stem from absent package language '
    'resolution; three host formatting failures are real. No source was '
    'blindly reformatted and no fixture/pass claim is made. A fresh canonical '
    'Flutter/Pub bootstrap and reviewed source corrections are required.\n\n'
    'The prior frozen native application/file_saver compile and 12 JVM units '
    'pass; later source is outside that cohort. The included Flutter SDK still '
    'applies KGP 2.2.20 and resolves runtime KGP 2.0.0. Fresh official archive '
    'bytes match publisher SHA256/MD5 and canonical source metadata. Root '
    'independently verifies the exact 33 attribute-required Windows checkout '
    'line-ending differences and 117 sealed foundation/plan leaves. Full '
    'physical expansion, the three-file repair, compiler/runtime/ABI tests, '
    'advisory/licence acceptance and shipped SBOM remain open. The shared SDK '
    'is unchanged; local provenance signature verification is unperformed.\n\n'
    'Startup recovery/redacted diagnostics retain their scoped 12 and 58-test '
    'proofs. Named duty-owner alert delivery and outage/incident rehearsal '
    'remain open. The actual cold Edge Linux image still fails its 300-second '
    'Pillow download deadline. Safe archive relocation/restore and broad '
    'archive-free consumers remain unfinished. Full current candidate, '
    'financial/security/owner-populated migration, hosted/provider/device/store '
    'and artifact-bound release approval remain required. Production is NO-GO '
    'and the implementation goal remains active.\n')
table = ['| Finding | Local implementation | Full acceptance | Evidence |',
         '| --- | --- | --- | --- |']
for row in ledger['items']:
    links = []
    for entry in row['evidence_packets']:
        path = pathlib.PurePosixPath(entry['path'])
        label = '/'.join(path.parts[-2:])
        links.append(f'[{label}]({ROOT / path})')
    acceptance = 'Closed: authority hygiene only' if row['full_finding_closed'] else 'Open'
    table.append(f"| {row['id']} | {row['implementation_status']} | "
                 f"{acceptance} | {'; '.join(links)} |")
(REGISTER / 'IMPLEMENTATION_REGISTER.md').write_text(
    '# Critical findings implementation register\n\n'
    f'Updated {timestamp}. All 40 original finding IDs and acceptance '
    'requirements remain tracked. Only PD-14 sole-authority hygiene is closed. '
    'The mutable checkout has no newly accepted whole release candidate.\n\n'
    'Revolut remains the sole UI/UX and product visual design skill. Competing '
    'UI/design skills and the retired checklist/gates remain removed; unrelated '
    'technical/professional skills remain under the explicit owner scope. '
    'Fresh cleanup evidence verifies 141 recorded paths absent and checked '
    'current instructions/708 skill inputs clean. Protected, inaccessible and '
    'pruned discovery limits remain. Authority hygiene does not certify '
    'visual fidelity.\n\n' + '\n'.join(table) + '\n\n' + prose)

marker = '## Critical review implementation extension — 1 October 2026'
for name in ['PRODUCTION_REMAINING_TASKS_2026-09-30.md',
             'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md']:
    path = REGISTER.parent / name
    text = path.read_text()
    assert text.count(marker) == 1
    prefix = text.split(marker)[0]
    suffix = (f'{marker}\n\nUpdated {timestamp}. '
              '[The critical findings register]('
              f'{REGISTER / "IMPLEMENTATION_REGISTER.md"}) tracks all 40 '
              'findings with their original acceptance criteria. Only PD-14 '
              'authority hygiene is closed. The original 102 production and '
              '24 local rows remain byte-canonical unchanged; later scoped '
              'evidence does not accept the whole mutable checkout.\n\n' + prose)
    path.write_text(prefix + suffix)

for row in ledger['items']:
    for entry in row['evidence_packets']:
        assert sha(ROOT / entry['path']) == entry['sha256'], entry['path']
for name, expected in originals.items():
    actual = json.loads((REGISTER.parent / name).read_text())
    assert canonical(actual['items']) == expected
    assert actual['critical_review_implementation_extension']['sha256'] == sha(LEDGER)
result = {'schema_version': 1, 'checked_at_utc': timestamp,
          'finding_count': 40, 'original_criteria_unchanged': True,
          'closed_ids': ['PD-14'], 'original_rows_sha256': originals,
          'new_ledger_sha256': sha(LEDGER),
          'owned_files_after_sha256': {
              str(path.relative_to(ROOT)): sha(path) for path in owned},
          'all_linked_finding_packet_digests_match': True,
          'production_ready': False, 'goal_status': 'active'}
save(BASE / 'register-reconciliation.json', result)
print(json.dumps({'status': 'pass', 'ledger_sha256': sha(LEDGER),
                  'original_rows_unchanged': [102, 24], 'closed': ['PD-14']}))
