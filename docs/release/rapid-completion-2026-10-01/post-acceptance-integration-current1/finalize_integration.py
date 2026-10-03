#!/usr/bin/env python3
"""Bind terminal integration results and add evidence without closing release gates."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
RELEASE = ROOT / 'docs/release'
PEER = RELEASE / 'collect-codex-goal-2026-09-30/admin-exception-history-ui-20261001'
EXPECTED = '24b1719665694a2f09b18ee78e8cf6d4e33f416a5fd0c42edd747f0f22867a6a'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def read(path):
    return json.loads(path.read_text())


def reference(path):
    return {'path': str(path.relative_to(ROOT)), 'sha256': sha(path)}


def main():
    assert not (OUT / 'integration-acceptance.json').exists(), 'Final packets are immutable'
    now = datetime.now(timezone.utc).isoformat()
    capture = read(OUT / 'candidate-current2-export.json')
    assert capture['status'] == 'pass' and capture['manifest_sha256'] == EXPECTED
    candidate = Path(capture['destination'])
    manifest = read(candidate / '.collect-release-candidate.json')
    source = manifest['source_files']
    current = read(OUT / 'final-source-readback.json')
    assert current['status'] == 'pass' and not current['changes'] and current['manifest_sha256'] == EXPECTED
    browser_path = OUT / 'admin/browser-acceptance.json'
    browser = read(browser_path)
    assert browser['status'] == 'pass' and browser['production_admin_build_executed_once']
    peer = read(PEER / 'verification.json')
    vm = read(PEER / 'attempt3/verification.json')
    assert vm['accepted'] and vm['completed_visible_cases'] == 657 and vm['all_requested_suites_executed']
    assert peer['hygiene']['exit_code'] == 0
    overlay = read(OUT / 'source-overlay-manifest.json')
    supplemental = overlay['declared_reproduction_supplement']
    peer_bindings, peer_exclusions, binding_errors = {}, [], []
    for value in peer['current_source_bindings']:
        assert value['current_readback'], value['path']
        try:
            name = str(Path(value['path']).relative_to(ROOT))
        except ValueError:
            peer_exclusions.append({'path': value['path'], 'reason': 'declared_external_dependency_or_toolchain'})
            continue
        expected = (source.get(name) or supplemental.get(name) or {}).get('sha256')
        if expected is None:
            assert name.startswith(('.cache/', '.dart_tool/')), name
            peer_exclusions.append({'path': name, 'reason': 'declared_execution_configuration_or_toolchain'})
            continue
        peer_bindings[name] = {'sha256': value['sha256'], 'matches': expected == value['sha256']}
        if not peer_bindings[name]['matches']:
            binding_errors.append(name)
    mcp_path = OUT / 'mcp/current-integrated-acceptance.json'
    mcp = read(mcp_path)
    assert mcp['status'] == 'pass' and mcp['all151_source_inputs_match_tested_private_proof']
    mcp_source = read(OUT / 'mcp/current-source-binding.json')
    mcp_bindings = {}
    for name, expected in mcp_source['source_sha256'].items():
        actual = (source.get(name) or supplemental.get(name) or {}).get('sha256')
        mcp_bindings[name] = {'sha256': expected, 'matches': actual == expected}
        if actual != expected:
            binding_errors.append(name)
    assert not binding_errors, binding_errors
    sql_path = OUT / 'sql-ordinary-current-body/current-ordinary-body-acceptance.json'
    sql = read(sql_path)
    assert sql['status'] == 'pass' and sql['case_count'] == 21 and sql['all_task_containers_removed']
    assert source['supabase/migrations/20261001200000_exception_inbox_audit_v2.sql']['sha256'] == sql['current_migration_sha256']
    reuse_path = OUT / 'unchanged-consumer-reuse/acceptance.json'
    reuse = read(reuse_path)
    assert reuse['status'] == 'pass', reuse.get('failures')
    delivery = read(OUT / 'source-overlay-readback.json')
    assert delivery['status'] == 'pass' and not delivery['virtual_union_mismatches']
    refs = [OUT / 'candidate-current2-export.json', OUT / 'final-source-readback.json',
            PEER / 'verification.json', PEER / 'attempt3/verification.json', PEER / 'MANIFEST.json',
            mcp_path, OUT / 'mcp/current-source-binding.json', sql_path, reuse_path, browser_path,
            OUT / 'source-overlay-readback.json', OUT / 'source-overlay-manifest.json']
    findings_path = OUT / 'known-open-parallel-review/findings.json'
    findings = read(findings_path)
    assert len(findings['findings']) == 6 and all(value['state'] == 'open' for value in findings['findings'])
    finding_drift = [value['path'] for value in findings['source_bindings']
                     if source[value['path']]['sha256'] != value['sha256']]
    assert not finding_drift, finding_drift
    refs.append(findings_path)
    receipt = {
        'schema_version': 1, 'kind': 'integrated_local_delta_acceptance', 'status': 'pass',
        'captured_at_utc': now, 'candidate_manifest_sha256': EXPECTED,
        'source_manifest_sha256': manifest['source_manifest_sha256'],
        'selected_source_files': len(source), 'source_bytes': manifest['total_bytes'],
        'source_migration_count': len(manifest['migration_versions']),
        'source': str(candidate), 'source_readback_unchanged': True,
        'critical_fixes_integrated': ['scheduler final admission after awaited setup',
                                     'browser recovery resource admission before encoding and JSON decoding'],
        'counts': {'current_Admin_VM_cases': 657, 'current_Admin_VM_suites': 19,
                   'current_MCP_unique_composed_cases': 413, 'MCP_Python_preparation_cases': 12,
                   'new_ordinary_owner_SQL_body_checks': 21,
                   'current_query_plan_checks_separate_scope': 37,
                   'browser_checks': browser['browser_check_count'],
                   'successful_final_Admin_production_builds': 1,
                   'Admin_production_build_attempts': browser.get('production_admin_build_attempts', 2)},
        'evidence': [reference(path) for path in refs],
        'Admin_application_and_reproduction_bindings': peer_bindings,
        'Admin_declared_execution_prerequisites_not_in_authored_source': peer_exclusions,
        'MCP_current_candidate_bindings': mcp_bindings,
        'source_binding_errors': binding_errors,
        'SQL_composition': {
            'prior_full_ordinary_rehearsal': '187 clean plus187 populated applications,36 checks; earlier a835 reader body',
            'prior_migrations_unchanged': 186,
            'changed_reader': '37 query-plan checks plus21 actual new/retained ordinary-owner checks against7f6aea',
            'whole187_latest_body_replayed': False,
            'overlapping_SQL_cases_summed_as_unique': False,
        },
        'original_local_24_criterion_acceptance': 'Retained immutable185-migration acceptance plus controlled affected-source delta; original acceptance wording is preserved.',
        'whole_current_Flutter_suite_rerun': False, 'native_or_Edge_rebuilt': False,
        'native_and_Edge_reuse': reference(reuse_path),
        'actual_hosted_provider_signing_store_or_device_acceptance': False,
        'visual_fidelity_certified': False, 'production_release_decision': 'NO-GO',
        'known_open_parallel_work': {
            'owner_chat': 'Connect Collect to Codex MCP',
            'thread_id': '01a0f32e-14a4-7d92-aa87-8ca1f381e41e',
            'finding_receipt': reference(findings_path),
            'open_findings': findings['findings'],
            'reported_source_bindings_match_candidate': True,
            'reported_gap': 'Goals6/11/13: continuous ACK retention, permanent global request-ID reservation, expandable native recovery indexes, scheduler hot/cold maintenance, indexed worker source sweep and worker cold-history restore.',
            'root_independently_verified': False,
            'scope': 'Reported by the source owner after this frozen capture; continuous-retention and cross-action UUID guarantees are excluded from reused native proof and this integration acceptance.',
            'implementation_status': 'Parallel owner preparing correction privately; no source write in this frozen pass.',
        },
        'limits': 'Affected consumer proof is composed with matching unchanged inputs. No claim that657 is a full app suite,413 a fresh rerun, all v2 positive states were executed in the browser, or the latest187 SQL bodies were replayed twice. Synthetic loopback and isolated SQL results do not replace production acceptance.',
    }
    save(OUT / 'integration-acceptance.json', receipt)
    old_names = ['local-implementation-register-2026-09-30.json', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md',
                 'production-remaining-tasks-2026-09-30.json', 'PRODUCTION_REMAINING_TASKS_2026-09-30.md',
                 'production-remaining-tasks-2026-09-30.validation.json']
    before = OUT / 'registers-before-integration'
    before.mkdir(exist_ok=False)
    for name in old_names:
        shutil.copy2(RELEASE / name, before / name)
    local = read(RELEASE / old_names[0])
    production = read(RELEASE / old_names[2])
    original_local = [item['local_acceptance'] for item in local['items']]
    original_production = [(item['id'], item['original_acceptance'], item['priority'], item['evidence_status'], item['open']) for item in production['items']]
    ref = reference(OUT / 'integration-acceptance.json')
    local['snapshot_revision'] += 1
    local['captured_at_utc'] = now
    local['source_migration_count'] = 187
    local['staged_source_migrations'] = 33
    local['post_acceptance_integrated_delta'] = {**ref, 'status': 'pass', 'candidate_manifest_sha256': EXPECTED,
                                                'scope': receipt['limits'], 'source_migrations': 187}
    local['known_open_parallel_work'] = receipt['known_open_parallel_work']
    affected = {'L03', 'L04', 'L05', 'L07', 'L14', 'L15', 'L18', 'L22', 'L23', 'L24'}
    for item in local['items']:
        if item['id'] in affected:
            item['post_acceptance_integrated_delta_evidence'] = ref
    save(RELEASE / old_names[0], local)
    production['snapshot_revision'] += 1
    production['captured_at_utc'] = now
    production['source_migration_count'] = 187
    production['staged_source_migrations'] = 33
    for version in ['20261001190000', '20261001200000']:
        if version not in production['staged_source_versions']:
            production['staged_source_versions'].append(version)
    production['integrated_local_delta_acceptance'] = {**ref, 'status': 'pass', 'candidate_manifest_sha256': EXPECTED}
    production['known_open_parallel_work'] = receipt['known_open_parallel_work']
    production['current_local_scoped_packets'].append({**ref, 'reported_status': 'pass', 'scope': receipt['limits']})
    production['local_progress_note'] = 'Original24 local criteria remain complete in their immutable acceptance scope. Current2175-file integration additionally accepts the affected Admin/MCP/SQL delta and one browser/PWA build through composed matching-input proof. All101 original production checks remain open; hosted/provider/device/signing/visual/owner gates were not closed.'
    production['in_progress'] = {'ids': [], 'work': 'This local integration pass is complete. Independent development in other chats and production acceptance have their own task registers.'}
    production['immediate_engineering_subtasks'][0]['work'] = 'Select and approve the captured release source and artifacts; the current integrated local delta now has scoped acceptance evidence.'
    save(RELEASE / old_names[2], production)
    for name in [old_names[1], old_names[3]]:
        text = (RELEASE / name).read_text()
        lines = text.splitlines()
        if name == old_names[1]:
            lines[2] = f'Captured: {now}. Revision {local["snapshot_revision"]}.'
        else:
            lines[2] = f'**Snapshot: {now}; revision {production["snapshot_revision"]}. Release decision: NO-GO.**'
        text = '\n'.join(lines) + '\n'
        text = text.replace('Later concurrent changes in the live checkout remain unverified.', 'The subsequent Admin/MCP/SQL integration has matching-source local evidence below.')
        text = text.replace('Later concurrent live changes are explicitly unaccepted.', 'The subsequent controlled integration is accepted within its declared affected-source scope.')
        addition = (f'\n## Integrated local update — {now}\n\n'
                    '**The two review corrections are integrated and the current Admin browser/PWA artifact is verified.** '
                    'The 2,175-file capture contains 187 migrations. The 657-case affected Admin run and strict analysis passed. '
                    'The 413 MCP cases form a composed proof with matching inputs. The latest SQL reader has 21 ordinary-owner checks plus 37 query-plan checks; '
                    'the preceding full 187-migration clean/populated rehearsal remains explicitly bound to its earlier reader body. '
                    'Unchanged native and Edge consumer proof is reused only through the new input/readback maps. '
                    'All original 24 local criteria and 102 production criteria are preserved; 101 production checks remain open.\n\n'
                    '[Integrated acceptance](rapid-completion-2026-10-01/post-acceptance-integration-current1/INTEGRATION.md). '
                    '[Machine-readable evidence](rapid-completion-2026-10-01/post-acceptance-integration-current1/integration-acceptance.json).\n')
        marker = '\n## G —' if name == old_names[3] else '\n| ID |'
        assert marker in text
        text = text.replace(marker, addition + marker, 1)
        (RELEASE / name).write_text(text)
    assert [item['local_acceptance'] for item in local['items']] == original_local
    assert [(item['id'], item['original_acceptance'], item['priority'], item['evidence_status'], item['open']) for item in production['items']] == original_production
    assert len(local['items']) == 24 and not local['local_open_items']
    assert sum(item['open'] for item in production['items']) == 101
    integrity = {'status': 'pass', 'captured_at_utc': now, 'all24_local_criteria_preserved': True,
                 'all102_production_criteria_and_states_preserved': True, 'local_complete': 24,
                 'requested_complete': 18, 'production_open': 101, 'release_decision': 'NO-GO',
                 'integration_acceptance': ref, 'local_revision': local['snapshot_revision'],
                 'production_revision': production['snapshot_revision'],
                 'canonical_sha256': {name: sha(RELEASE / name) for name in old_names[:4]}}
    save(OUT / 'register-integrity.json', integrity)
    validation = read(before / old_names[4])
    validation['snapshot_revision'] = production['snapshot_revision']
    validation['local_snapshot_revision'] = local['snapshot_revision']
    validation['validated_at_utc'] = now
    validation['sha256'] = sha(RELEASE / old_names[2])
    validation['source_migration_count'] = 187
    validation['staged_source_versions'] = production['staged_source_versions']
    validation['integrated_local_delta_acceptance'] = ref
    validation['scope'] = 'Original criteria and states preserved; historical185-migration local acceptance retained, with current187 affected delta composed through matching-input evidence. No production or whole-current-source regression acceptance inferred.'
    save(RELEASE / old_names[4], validation)
    report = f'''# Collect integrated local acceptance

**Status: complete for this integration pass. Production release: NO-GO.**

The current captured source has 2,175 selected files and 187 migrations. The earlier immutable 24-item local acceptance remains intact. This packet adds matching-source evidence for the subsequent Admin/MCP/SQL changes; independent work in other chats remains governed by its own register.

## Corrections integrated

| Correction | Why it was required | Result |
| --- | --- | --- |
| Scheduler admission after awaited setup | A tick admitted earlier could resume after durable disable or identity expiry and still invoke the runner. | Permission and identity are rechecked immediately before invocation; non-invoked outcomes are recorded. Current 66 scheduler cases plus 347 unchanged cases compose 413 MCP cases; type checking and 12 Python preparation cases pass. |
| Recovery input bounds before encoding and parsing | An oversized sessionStorage value could allocate UTF8 and decode JSON before resource limits rejected it. | Code-unit admission precedes encoding, byte admission precedes JSON decoding, and bounded quarantine survives reload. Both ASCII and multibyte regression cases pass within the 657-case combined run. |
| Current joined audit reader | The earlier UNION plan read excessive equal-time records before applying its outer limit. | Each source arm now applies its authorization-compatible bounds, paired cursor and limit before UNION. The 37 query-plan checks and 21 ordinary-owner new/retained-body checks pass. |

The other chat's route-origin and opening-generation guards were preserved. Exact acknowledgements, session changes and authority refusal remain covered by the actual 19-suite, 657-case run. Strict analysis and sole-design-authority hygiene pass. Hygiene does not certify visual fidelity.

## Verified scope

- Admin: 657 actual VM cases across 19 suites, with 135 new history/inbox cases. One production Admin build and {browser['browser_check_count']} actual browser/PWA checks passed.
- Browser fixtures are synthetic loopback data. The actual SQL decoder/SDK and widget proofs establish the new positive v2 contracts; no claim is made that every positive v2 state was exercised in the browser.
- SQL: the preceding 187 clean plus 187 populated ordinary-installer applications and 36 checks retain their earlier a835 reader-body provenance. The 186 migration files are unchanged. The changed 7f6aea reader is separately covered by 37 plan checks and 21 ordinary-owner checks. Overlapping database cases are not summed as unique coverage.
- MCP: 413 unique composed cases, including 66 corrected scheduler cases and 347 unchanged cases, plus 12 preparation cases. Real launchd, Keychain and provider operations were not invoked.
- Unsigned Android/Gateway/iOS and Edge results are reused only where exact consumer, dependency/toolchain and artifact readback maps match. Broad native, Edge and full Flutter reruns were avoided.
- Current source readback, locks, input maps, terminal logs and artifact maps are bound by [integration-acceptance.json](integration-acceptance.json). Rejected/stalled runs and their causal fixture corrections remain preserved.

The first final browser-build attempt stopped at a pinned Flutter/font-subset pipe deadlock before browser launch. The corrected command uses a private output-draining wrapper around the identical engine binary, with original arguments, standard input, font outputs and exit status preserved. Its bounded log and complete output digest, failed attempt and actual final artifact are recorded separately. Application source and the shared SDK were unchanged; one successful final build is claimed.

The corrected Admin and Public builds passed. Its browser driver then timed out while typing after a repeated sign-in: DOM focus preceded the Flutter editor's input readiness. The private continuation brings the page forward, clicks the current named field and waits two frames while retaining the exact native-editor value assertion. Both accepted bundles are reused under hash guards; no third Admin or Public build is performed. This harness correction and the failed captures are preserved separately from application source.

## Source delivery

Use the earlier [accepted source archive](../final-candidate-current1/collect-accepted-local-source.tar.gz) together with [the integrated source overlay](collect-integrated-source-overlay.tar.gz). Their SHA256 values and every overlay member are verified in [source-overlay-readback.json](source-overlay-readback.json). The overlay carries 58 added and 16 changed selected-source files; no selected-source deletion occurred. The declared source and reproduction-only files are distinguishable in [source-overlay-manifest.json](source-overlay-manifest.json). SDKs, caches, secrets and signing material are excluded.

The portable build/evidence delivery is recorded in [delivery-readback.json](delivery-readback.json). Prior archives remain intact. Original 24 local criteria and 102 production criteria are preserved in [register-integrity.json](register-integrity.json); 101 production checks remain open.

## Remaining release acceptance

The owner of **Connect Collect to Codex MCP** reported six additional local requirements against 11 source files that match this capture. Three owners are preparing the corrections privately. These findings were not independently reproduced by this chat; their guarantees are excluded from reused native/MCP/SQL tests and this frozen integration pass. They remain open in that chat's register. The [read-only findings receipt](known-open-parallel-review/findings.json) is preserved here.

| Open local requirement | Why it remains necessary |
| --- | --- |
| Continuous heartbeat ACK retention | Legacy 256-request/512KiB archives bound lifetime sender availability. |
| Permanent global native request-ID reservation | A compacted request's identity must remain reserved across a changed action or attempt. |
| Expandable native indexes and complete recovery | Finite per-prefix and late-observation caps need bounded expansion and a complete recovery closure. |
| Scheduler hot/cold maintenance and inactive restore | Existing admission limits fail closed; continuous operation also needs lossless maintenance and read-through. |
| Indexed worker source sweep | Limiting output after lifetime duplicate/deferral aggregation does not bound the underlying scan. |
| Worker cold-history preservation and restore | Maintenance must retain original IDs, acknowledgements and foreign-key provenance. |

Hosted/Auth/provider behavior, physical devices, signing/store release, trusted-source governance, visual comparators and owner release acceptance retain their existing gates. No deployment or production approval is inferred from this local packet.
'''
    (OUT / 'INTEGRATION.md').write_text(report)
    print(json.dumps({'status': 'pass', 'acceptance': reference(OUT / 'integration-acceptance.json'), 'registers': integrity}))


if __name__ == '__main__':
    main()
