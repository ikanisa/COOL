#!/usr/bin/env python3
"""Write the user handover from terminal, reconciled evidence only."""
from bind_evidence import ROOT, HERE, RAPID, read


def main():
    packet = read(HERE / 'evidence-binding.json')
    local = read(ROOT / 'docs/release/local-implementation-register-2026-09-30.json')
    production = read(ROOT / 'docs/release/production-remaining-tasks-2026-09-30.json')
    ledger = read(RAPID / 'requested-task-evidence-ledger1/ledger.json')
    assert packet['status'] == 'pass' and len(local['locally_closed_goal_items']) == 24
    assert len(ledger['requested_ids']) == 18
    lines = ['# Final local implementation handover', '',
      '**18 requested items complete against the tested immutable candidate. The original local register is24/24 complete.**', '',
      '**The live checkout contains later concurrent Admin/MCP edits that are excluded from this acceptance. They were preserved. Production release remains NO-GO, with101 original production checks unaccepted.**', '',
      '## Accepted source and reproducibility', '',
      '- Source captured2026-10-01T14:35Z:2,117 files; manifest `dba11a4a0deb5822c528c92d770c79d50fa705037f5f23fbd8aed08bcc907fdd`.',
      '-371 explicitly selected additional decoder/document/upstream regression inputs are included for reproducing the existing commands.',
      '- [Source archive](collect-accepted-local-source.tar.gz):2,489 members,142,024,221 bytes; every member read back against its hash. SHA-256 `2525fe8e5ed34d8bcd858b6419d65f55eebef02fac6559c2f51e5e4fde6cdbd6`.',
      '- [Fixture selection and assembly](supplement-manifest.json); [source archive readback](source-archive-readback.json); [final evidence binding](evidence-binding.json).',
      '- Original failures, timeouts, earlier packets and previous registers are retained. Tests were composed from completed cohorts and corrections only where their source, dependencies and executed inputs matched.', '',
      '## Verified results', '',
      '| Scope | Accepted result |', '| --- | --- |',
      '| Flutter |5,014 registered VM cases in227 cohorts; repeated names preserved as separate registered cases; fatal analysis passed |',
      '| Browser |15 real Chrome component cases;88 actual production Admin/Public browser and PWA checks;28 routes in56 authority states |',
      '| Edge |552 unit cases across29 files;90 actual HTTP checks across12 entrypoints |',
      '| MCP |390 unique successful cases across29 modules; type checking passed |',
      '| Database |185 clean and185 populated ordinary-installer migration applications;36 checks; named compatibility/rollback/upgrade and concurrency proofs retained |',
      '| Benchmarks |Genuine1,000/10,000-record data;104 current Admin cases plus unchanged history/window/concurrent paging acceptance |',
      '| Native |Production12 JVM cases; final Gateway141 Gradle JVM and190 standalone cases in separate suites; Android API compile and both flavor lint gates passed |',
      '| Supply chain |686 source SBOM components; observed200 production and187 Gateway components; schema and reproduction passed |',
      '| Assets |93 declared assets verified,91 raster decodes;264/264 runtime Dart source reachability; zero unresolved directives/assets |', '',
      '## Requested task closure', '', '| ID | Verified implementation and acceptance |', '| --- | --- |']
    items = {row['id']: row for row in ledger['items']}
    for identity in ledger['requested_ids']:
        lines.append('| ' + identity + ' | ' + items[identity]['covered_criteria'].replace('|', '\\|') + ' Final source and accepted consumers are bound. |')
    lines += ['', '## Unsigned local artifacts', '',
      '| Artifact | SHA-256 |', '| --- | --- |']
    for family in ['production', 'gateway']:
        row = packet['native_artifacts'][family]
        lines.append(f'| [{family} APK]({row["artifact"]}) | `{row["sha256"]}` |')
    row = packet['native_artifacts']['ios']
    lines += [f'| [iOS Collect.app]({row["artifact"]}) | Executable `{row["main_executable_sha256"]}`; bundle manifest `{row["bundle_manifest_sha256"]}` |', '',
      '[Builds and evidence archive](collect-unsigned-builds-and-evidence.tar.gz) packages the unsigned artifacts, exact Admin/Public artifacts and selected evidence. Its checksum and full member readback are in `delivery-archive-readback.json`, written after packing.', '',
      'Production Android has37 reviewed lint warnings, Gateway40; iOS23 reviewed warning strings (19 primary and4 duplicate renderings). These were individually dispositioned. The record does not claim zero warnings.', '',
      '## Limits and remaining release work', '',
      '- Acceptance names one tested local source set. The later live-checkout changes have no acceptance in this packet; no commit, reset, overwrite or push was used to remove them.',
      '- The retained shared database remains154 migrations/153 tables. The185-source rehearsal used private clean/populated databases, with the shared fixture preserved.31 source versions remain staged for that retained fixture.',
      '- No signing, hosted migration rollout, real provider/device/store delivery, source provenance approval or owner production-release approval is claimed.',
      '- Revolut remains the sole design authority. Local compact/enlarged-text, focus, semantics and affected-state regressions passed;100 percent comparator fidelity and external review are unverified.',
      '- [Local register](../../LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md) retains all24 criteria. [Production register](../../PRODUCTION_REMAINING_TASKS_2026-09-30.md) retains all102 original criteria and101 open acceptance checks.', '',
      '## Reproduction', '',
      'Extract the source archive into a fresh directory. Its paths already include the selected supplementary fixtures. Use the pinned versions and locks in `.collect-release-candidate.json`; SDKs/package caches, signing inputs and production credentials are external build prerequisites rather than authored source.', '',
      'Exact suite/build commands, declared synthetic boundaries, input scopes and log hashes are recorded in the final evidence packet and its linked receipts. The source/build/evidence archives have complete member-level readbacks. No production authorization is implied by successful archive verification.', '']
    (HERE / 'HANDOVER.md').write_text('\n'.join(lines))
    print('Final handover written from accepted evidence.')


if __name__ == '__main__':
    main()
