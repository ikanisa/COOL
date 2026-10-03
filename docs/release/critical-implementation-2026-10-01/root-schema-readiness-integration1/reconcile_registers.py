"""Integrate completed current-schema evidence without changing original criteria."""
from pathlib import Path
import copy
import datetime
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = HERE.parent
EXPECTED = json.loads((BASE / 'usage-limit-checkpoint-20261002-0400/checkpoint.json').read_text())['canonical_registers_unchanged']
ORIGINAL_ROWS = {
    'production-remaining-tasks-2026-09-30.json': '404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f',
    'local-implementation-register-2026-09-30.json': '0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980',
}
PROOFS = {
    'migration-version-validation1/packet-files.json': '559438742dc3f1f0f753764018ff0ee1f621e164afaa2130881f1420772ea213',
    'ordinary-schema-catalog-preparation1/packet-files.json': '8accb69f30c7e964eb31c64f063e7359ab9df4d5ce28bf1e821bf74c24cf3961',
    'ordinary-schema-catalog-execution1/packet-files.json': '55cd0abe286d50615fcd13eb37ed0e0d56b10f1bf443ecfbac2065ffb7eafabc',
    'ordinary-schema-catalog209-preparation1/packet-files.json': '129680950a0f8b4018880732833d97fde7c6b524d41eded83a509ec836051c96',
    'ordinary-schema-catalog209-execution1/packet-files.json': '9ecf3c89a0197ae3169813863c940138754055a63b1be5bf3980462bb478ea4a',
    'kotlin-sdk-native-snapshot-preparation2/packet-files.json': '72aedc2004efaafe192f8e86a05dc08bf7df9425dcd68f08d9dd6898cf01c283',
    'cloudflare-readonly-attempt1/packet-files.json': 'e708bf9309e72c2b19e72058e98914a701f3571078633d89552de522e4599f5a',
    'root-sdk-native-snapshot-review2/preparation-review.json': 'cc1a792050dcdadf9781db9b339e9f6bbce63a5a35a57d50561e82c4ae94c40d',
}
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
canonical = lambda value: hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def packet(path, digest):
    assert sha(path) == digest, path
    document = json.loads(path.read_text())
    if path.name == 'packet-files.json':
        files = document['files']
        for row in files if isinstance(files, list) else [{'path': str((path.parent / name).relative_to(ROOT)), 'sha256': expected} for name, expected in files.items()]:
            leaf = ROOT / row['path']
            assert leaf.resolve().is_relative_to(path.parent.resolve()) and not leaf.is_symlink()
            assert sha(leaf) == row['sha256']
            if 'bytes' in row:
                assert leaf.stat().st_size == row['bytes']
    return document


assert all(sha(ROOT / name) == digest for name, digest in EXPECTED.items())
for name, digest in PROOFS.items():
    packet(BASE / name, digest)
actual = json.loads((BASE / 'ordinary-schema-catalog209-execution1/execution-result.json').read_text())
assert actual['status'] == 'pass' and actual['case_count'] == 37 and len(actual['source_after']) == 216
assert all(sha(ROOT / name) == digest for name, digest in actual['source_after'].items())
assert len(list((ROOT / 'supabase/migrations').glob('*.sql'))) == 209
backend = json.loads((BASE / 'root-successor-source154-validation1/promotion-result.json').read_text())
assert all(sha(ROOT / name) == digest for name, digest in backend['current_source_after'].items())
ledger_path = BASE / 'implementation-ledger.json'
ledger = json.loads(ledger_path.read_text())
criteria = [(row['id'], copy.deepcopy(row['acceptance_requirement_from_report'])) for row in ledger['items']]
assert len(criteria) == 40
assert sorted(row['id'] for row in ledger['items'] if row['full_finding_closed']) == ['ARC-04', 'PD-02', 'PD-14']
documents = {name: json.loads((BASE.parent / name).read_text()) for name in ORIGINAL_ROWS}
assert all(canonical(value['items']) == ORIGINAL_ROWS[name] for name, value in documents.items())
for name in EXPECTED:
    destination = HERE / 'registers-before' / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open('xb') as stream:
        stream.write((ROOT / name).read_bytes())
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
refs = [{'path': str((BASE / name).relative_to(ROOT)), 'sha256': digest} for name, digest in PROOFS.items()]
rows = {row['id']: row for row in ledger['items']}


def add_refs(ident, selected):
    known = {reference['path'] for reference in rows[ident]['evidence_packets']}
    rows[ident]['evidence_packets'] += [reference for reference in selected if reference['path'] not in known]


add_refs('BE-08', [reference for reference in refs if 'migration-version' in reference['path'] or 'ordinary-schema' in reference['path']])
rows['BE-08']['implementation_status'] = 'current209_ordinary_replay_and_complete_catalogs_verified_domain_recovery_open'
rows['BE-08']['next_action'] = (
    'The full-version validator preserves applied12-digit IDs and compares complete14-digit versions, rejecting malformed names and symlinks; all8 behavioral tests and the current209-version validation pass. '
    'The earlier208-chain actual37-case proof is retained unchanged. The later209-chain actual37-case rehearsal passes in149.722seconds on216 exact unchanged inputs. '
    'All209 application migrations run as postgres NOSUPERUSER after explicit isolated platform preparation; CREATE ROLE/CREATE DB/BYPASSRLS and trusted memberships remain disclosed. '
    'The124-version synthetic predecessor retains all18 tested financial/receipt/Auth/approval projections through85 pending migrations. Complete final clean/populated catalogs match byte-for-byte and canonically and inventory38schemas/902functions/997relations/3756columns plus owners, role memberships, effective ACLs, policies and dependencies. '
    'Scheduler dispatch stays disabled and both task containers are absent. Complete the domain/caller/owner map, broader historical financial/bank and effective ACL preservation, incompatibility cases, committed predecessor recovery with forward replay, and hosted managed-authority/runtime acceptance. No full BE08 or production closure is inferred.'
)
add_refs('ARC-09', [reference for reference in refs if 'native-snapshot' in reference['path']])
rows['ARC-09']['next_action'] = rows['ARC-09']['next_action'].replace('Source export/app resolution/native builds remain held while current shared integration is owned elsewhere.', 'The other human chat completed its current209 retention-control integration; its retained source is preserved. Source export/app resolution/native builds remain unexecuted.') + (
    ' The private snapshot derivative is independently reviewed: all56 safe leaves match, only authorization/main controller functions change, and34 snapshot guards plus31 unchanged original regressions pass with all42 source/tool identities current and owned groups absent. '
    'A fresh source fence and separate app-export admission remain required before execution. Held-source/workspace-lock/transient-write absence claims stay false; no whole-stage outer deadline or release approval is asserted.'
)
rows['ARC-08']['next_action'] = (
    'Exact official Supabase2.114.0 archive/checksum/digest and both arm64 executable bytes are recorded; the deployment controller binds launcher and companion and rejects drift. Unsigned/ad-hoc publisher-provenance limitations remain explicit. '
    'The shared PostgreSQL proposal is still private and unpromoted. Root review requires a source-reviewed supported client/server cohort, exact manifest/binary/target binding and bounded credential-free probes; a hashed claimed matrix alone is insufficient. '
    'Complete affected helper/readiness/deployment regressions and actual migration/restore adapter proof with the admitted exact toolchain. Supabase embedded DB-client/image provenance and pg_dump/pg_restore binding remain separate gaps. No actual external approval or hosted CLI effect is supplied.'
)
for ident in ('PD-05', 'ARC-07', 'PD-10'):
    add_refs(ident, [reference for reference in refs if 'cloudflare-' in reference['path']])
for reference in refs:
    ledger['evidence_current_readback'][reference['path'].removeprefix(str(BASE.relative_to(ROOT)) + '/')] = dict(checked_at_utc=now, **reference, scope='Exact recorded local scope or read-only UI access refusal; no full finding or production acceptance inferred.')
ledger['captured_at_utc'] = now
ledger['goal_status'] = 'active'
ledger['release_decision'] = 'NO-GO'
ledger['candidate_status'] += ' Current209 isolated ordinary-installer/catalog proof is now complete; domain/historical/recovery and hosted acceptance remain open. Native snapshot preparation is independently reviewed but actual app export/builds are still unexecuted.'
assert [(row['id'], row['acceptance_requirement_from_report']) for row in ledger['items']] == criteria
note = (
    '\n\nCurrent schema progress — ' + now + '. The shipping validator now preserves complete12/14-digit migration versions and rejects malformed/symlink inputs;8 behavioral cases pass. '
    'The actual current209-migration clean/populated rehearsal passes all37 checks in149.722seconds on216 unchanged inputs. All application migrations run as postgres NOSUPERUSER after explicit platform preparation, with remaining CREATE ROLE/CREATE DB/BYPASSRLS and trusted memberships disclosed. '
    'All18 tested predecessor projections are preserved through85 pending migrations. Full final catalogs match byte-for-byte and canonically, including38schemas/902functions/997relations/3756columns, owners, grants, policies and dependencies. Both test containers are absent and external dispatch remained disabled. '
    'Earlier208 evidence stays immutable. Domain/caller mapping, broader historical data/ACL preservation, committed recovery and forward replay, and managed hosted acceptance remain open.\n\n'
    'The native snapshot derivative has independent root review and34 new plus31 original passing guard tests, with56 sealed leaves and42 unchanged source/tool identities. Actual app export/pub/native builds have not run; a fresh source fence and separate stage admission remain necessary. The PostgreSQL integration remains an unpromoted private proposal pending supported-cohort and consumer proof.\n\n'
    'Cloudflare was confirmed running, but both native window reads timed out and Chrome was unavailable through the browser connector. No deployment/configuration state was observed or changed; no outage/authentication failure is inferred. Hosted parity remains unverified.\n\n'
    'All40 original criteria and original102 production/24 local rows remain unchanged. Closed findings remain ARC-04, PD-02 and PD-14;37 full findings remain open. Production remains NO-GO; goal active.\n'
)
assert all(sha(ROOT / name) == digest for name, digest in EXPECTED.items())
save(ledger_path, ledger)
critical = BASE / 'IMPLEMENTATION_REGISTER.md'
lines = critical.read_text().splitlines()
for ident in ('BE-08', 'ARC-08', 'ARC-09', 'PD-05', 'ARC-07', 'PD-10'):
    matches = [index for index, line in enumerate(lines) if line.startswith('| ' + ident + ' |')]
    assert len(matches) == 1
    item = rows[ident]
    links = '; '.join(f"[{'/'.join(Path(reference['path']).parts[-2:])}]({ROOT / reference['path']})" for reference in item['evidence_packets'])
    lines[matches[0]] = f"| {ident} | {item['implementation_status']} | Open | {links} |"
critical.write_text('\n'.join(lines) + note)
for name, document in documents.items():
    extension = document['critical_review_implementation_extension']
    extension.update(captured_at_utc=now, sha256=sha(ledger_path), specialist_findings_closed=3,
        closed_scope='ARC-04 complete original local CI criterion; PD-02 local provenance/served-build proof and PD-14 sole-authority hygiene. Original production/local acceptance rows unchanged.')
    known = {reference['path'] for reference in extension['latest_scoped_evidence']}
    extension['latest_scoped_evidence'] += [reference for reference in refs if reference['path'] not in known]
    extension['current_schema_progress_note'] = note.strip()
    assert canonical(document['items']) == ORIGINAL_ROWS[name]
    save(BASE.parent / name, document)
for name in ('PRODUCTION_REMAINING_TASKS_2026-09-30.md', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md'):
    path = BASE.parent / name
    path.write_text(path.read_text() + note)
for name, document in documents.items():
    current = json.loads((BASE.parent / name).read_text())
    assert canonical(current['items']) == ORIGINAL_ROWS[name] and current['critical_review_implementation_extension']['sha256'] == sha(ledger_path)
after = {name: sha(ROOT / name) for name in EXPECTED}
save(HERE / 'register-reconciliation.json', dict(status='pass', at_utc=now, original40_criteria_unchanged=True,
    original_row_digests=ORIGINAL_ROWS, before=EXPECTED, after=after, closed_ids=['ARC-04', 'PD-02', 'PD-14'], full_findings_open=37,
    source_migration_count=209, current154_source_unchanged=True, production_ready=False, goal_status='active'))
for name in EXPECTED:
    destination = HERE / 'registers-after' / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open('xb') as stream:
        stream.write((ROOT / name).read_bytes())
files = [dict(path=str(path.relative_to(ROOT)), bytes=path.stat().st_size, sha256=sha(path)) for path in sorted(HERE.rglob('*')) if path.is_file()]
save(HERE / 'packet-files.json', dict(status='sealed', files=files))
print(json.dumps(dict(status='pass', ledger_sha256=sha(ledger_path), sealed_leaves=len(files), current_source_migrations=209, closed=3, open=37)))
