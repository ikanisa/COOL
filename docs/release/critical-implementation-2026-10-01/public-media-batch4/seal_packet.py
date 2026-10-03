#!/usr/bin/env python3
"""Seal the newly executed local public candidate without changing product source."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

PACKET = Path(__file__).resolve().parent
ROOT = PACKET.parents[3]
CAPTURE = ROOT / '.cache/public-media-current-20261002-batch4-attempt1'
STATIC = ROOT / '.cache/public-static-current-20261002-batch4-attempt1'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(name):
    return json.loads((PACKET / name).read_text())


def write(name, value):
    (PACKET / name).write_text(json.dumps(value, indent=2) + '\n')


stage = read('media-fixture-stage.json')
capture = json.loads((CAPTURE / 'capture-report.json').read_text())
quality = read('quality-final.json')
coverage = read('browser-route-coverage.json')
readback = read('final-readback.json')
visual = read('visual-review.json')
assert readback['status'] == 'pass' and not readback['errors']
assert capture['status'] == 'captured_pending_visual_review' and not capture['errors']
assert len(capture['captures']) == 7
assert quality['summary'] == {'total': 55, 'passed': 55, 'failed': 0}
assert coverage['total_actual_cases'] == 104 and not coverage['missing']
assert coverage['maintained_original_pngs'] == 350
assert coverage['supplemental_genuine_top_original_pngs'] == 28
assert visual['capture_report_sha256'] == sha(CAPTURE / 'capture-report.json')
assert visual['native_acceptance'] is False
assert all(visual['pixel_comparison'][i]['byte_equal'] for i in range(7))

for name in ['capture-execution.attempt1.json', 'publication-execution.json',
             'static-build-execution.json', 'quality-execution.json',
             'browser-routes-execution.json', 'browser-routes-execution-supplemental-share.json']:
    assert read(name)['status'] == 'pass'

readme = '''# Current local public source/media/browser proof

A fresh physically private source copy, enforced offline dependency resolution,
new Flutter compilation and seven new original app screenshots passed the
maintained capture and publication gates. A new 55-file static artifact passed
all 55 quality checks and 104 actual local browser cases. Every one of its 18
HTML entries was rendered at four viewports; 350 maintained and 28 genuine
top-of-page originals are retained.

The V4 media closure contains 344 authored inputs and the private copy contains
348 including four separate product/static support inputs. Exactly the four
root-reviewed router, repository, scaffold and Security-heading amendments
changed from batch3. The new runtime hash is
`4dd7f2add4be7a33fbf9419b35bff7f39c09ddfe9099a78db40420d1d7e9b168`.
The copy uses maintained credential-screened regular reads and physical writes;
no hardlinks, root package configuration or old compiled artifact was reused.
The private stage resolved its own bindings through offline Pub with the
unchanged enforced lock. Pinned Flutter 3.44.4, Node, Chromium, full Playwright,
executed helpers and recorder were bound before and after actual phases.

All seven fresh PNGs are byte-identical to batch3 originals. This records a
genuine new build/capture and current source binding; the dated compilation,
review and source acceptance were not reused. Six relevant native Revolut
originals were reopened, and the corrected generic app and visibly disabled
invalid-group top controls were directly inspected at all four viewports.
The null-client deletion fixture truthfully shows service unavailable/Get help.
The publisher retained its accurate alt text, so no copy change was needed.

| Actual current local check | Outcome |
| --- | --- |
| Old media against current runtime | Maintained recapture refusal retained |
| Private credential-screened physical copy | 348 inputs, source/copy/readback equal |
| Own offline enforced lock Pub bindings | Exit 0, authored source and tools unchanged |
| Fresh compiler and real app capture | Exit 0, seven original route PNGs |
| Strict maintained local publisher | Exit 0, exact capture/review/build provenance |
| Fresh static artifact and quality | 55 files; 55 / 55 checks pass |
| Maintained browser routes/group states | 60 + 16 cases pass |
| Supplemental direct/UA invitation targets | 28 cases pass |
| Full direct entry coverage | 18 entries × four viewports, no missing cases |
| Final current/prior readback | 344 media + 348 private/support inputs; 1,320 dated indexed objects match |

The original capture, source/tool maps, build files, PNGs, logs and all prior
packets remain intact. Two owned orchestration assumptions are preserved
plainly: the first stale-refusal classifier missed the actual wording, and the
publication wrapper expected a retired deletion alt after the publisher had
correctly retained the accurate one. The actual stale build and valid
publication were not repeated. A new bounded continuation ran only the pending
static/quality phases through unchanged production gates. The original wrapper
and its failure remain hash-bound.

The initial tall-image impression of omitted Terms opening text was unconfirmed.
Root independently reopened the exact original and compared the current
fallback: the opening paragraph is fully visible through “transfer information.”
That separate bounded readback preserves the original publication review.
The document continues below the viewport and has no exact native Terms
comparator. Groups displays two named destinations while Home/detail display
four; route/navigation consistency is not accepted by this static media proof.

Acceptance covers this complete local public candidate scope. No store/native
link was clicked, no deployment or provider/backend call was performed, and all
canonical owner/publication/legal/provider approval flags remain false. Exact
native/legal/deletion comparators, full visual/interaction/navigation fidelity,
font/photography rights, authenticated privacy/erasure lifecycle, devices,
hosted behavior, provider/store and production acceptance remain open. The
fixture is not the broad strict release export, which remains required.
Design-authority hygiene and visual acceptance remain distinct.

`batch.json` binds the exact current manifest, provenance, runtime, content
contract, artifact and evidence index. `final-readback.json` re-reads executed
phase inputs, 143 retained compiled capture files, private authored sources,
all current managed pixels and 1,320 older indexed objects. Superseded managed
media/contract indices resolve only to explicit preserved objects with the
original SHA. The original batch3 private source copy is also verified intact;
its old source is never described as accepting these new sources.
'''
(PACKET / 'README.md').write_text(readme)

excluded = {'batch.json', 'evidence-files.json', 'seal-readback.json'}
files = set(path for path in PACKET.rglob('*')
            if path.is_file() and path.relative_to(PACKET).as_posix() not in excluded)
files.update(path for path in CAPTURE.rglob('*') if path.is_file())
files.update(path for path in STATIC.rglob('*') if path.is_file())
files.update(path for path in (ROOT / 'web/public/app-screens').iterdir() if path.is_file())
files.add(ROOT / 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256')
files.add(ROOT / 'docs/release/public-website-current-content-contract.json')
rows = []
for path in sorted(files):
    assert not path.is_symlink()
    rows.append({'path': path.relative_to(ROOT).as_posix(),
                 'size': path.stat().st_size, 'sha256': sha(path)})
write('evidence-files.json', {'files': rows, 'count': len(rows),
                            'excludes_self_and_seal': sorted(excluded)})
current_contract = ROOT / 'docs/release/public-website-current-content-contract.json'
assert sha(current_contract) == read('preparation.json')['current_content_contract_sha256']
batch = {
    'schema_version': 1,
    'status': 'sealed_pass_current_local_public_candidate_scope',
    'sealed_at_utc': datetime.now(timezone.utc).isoformat(),
    'scope': 'Fresh private synthetic Flutter media, strict local publication, complete local static quality and104 actual rendered/share cases. No broad release/native/fidelity/rights/legal/provider/hosted/device/store/production acceptance.',
    'source_fixture': stage['destination'],
    'source_fixture_manifest_sha256': stage['stage_manifest_sha256'],
    'media_source_count': stage['browser_source_file_count'],
    'copied_authored_source_count': stage['copied_source_file_count'],
    'runtime_sha256': capture['runtime_before_sha256'],
    'root4_production_sources': readback['root_reviewed_production_sources'],
    'fresh_compilation_and_capture': True,
    'old_compilation_capture_or_acceptance_reused': False,
    'original_pixels_edited': False,
    'capture_report': (CAPTURE / 'capture-report.json').relative_to(ROOT).as_posix(),
    'capture_report_sha256': sha(CAPTURE / 'capture-report.json'),
    'build_manifest_sha256': capture['build_manifest_sha256'],
    'compiled_capture_files_read': len(readback['fresh_compiled_capture_files_read']),
    'diagnostic_observer_sources': capture['diagnostic_observer_sources_before'],
    'directly_inspected_app_originals': 7,
    'directly_reopened_selected_native_reference_originals': 6,
    'directly_inspected_genuine_top_share_originals': 8,
    'pixel_delta_from_batch3': visual['pixel_delta_from_batch3'],
    'all_seven_fresh_pixels_equal_dated_batch3': True,
    'publication': {
        'strict_actual_publisher_passed': True,
        'prior_managed_files_preserved_before_mutation': read('prior-publication-preservation.json')['count'],
        'current_manifest_sha256': readback['current_manifest_sha256'],
        'current_provenance_sha256': readback['current_provenance_sha256'],
        'current_asset_hash_record_sha256': readback['current_asset_hash_record_sha256'],
        'alt_state': read('publication-alt-readback.json'),
        'copy_changed_after_publisher': False,
        'rights_or_publication_approval_granted': False,
    },
    'static_artifact': STATIC.relative_to(ROOT).as_posix(),
    'static_artifact_file_count': readback['static_artifact_file_count'],
    'static_artifact_sha256': readback['static_artifact_sha256'],
    'strict_quality_summary': quality['summary'],
    'rendered_route_coverage': coverage,
    'post_traversal_originals_separately_retained': True,
    'root_independent_terms_readback': {
        'path': 'root-independent-terms-readback.json',
        'sha256': sha(PACKET / 'root-independent-terms-readback.json'),
        'opening_content_omission_confirmed': False,
        'complete_document_or_exact_native_comparator_accepted': False,
    },
    'groups_navigation_consistency_accepted': False,
    'current_contract_sha256': sha(current_contract),
    'current_contract_mutated_by_this_batch': False,
    'canonical_approval': coverage['capability_approval_as_recorded'],
    'owned_wrapper_failure_preserved': True,
    'failed_stale_classifier_preserved': True,
    'valid_publication_not_repeated': True,
    'original_indexed_evidence_read_back': sum(len(row['indexed_originals']) for row in readback['prior_sealed_packets']),
    'old_batch3_private_source_originals_read': len(readback['old_batch3_private_source_originals']),
    'prior_packets_unchanged': True,
    'final_readback_sha256': sha(PACKET / 'final-readback.json'),
    'evidence_index': {'path': 'evidence-files.json', 'sha256': sha(PACKET / 'evidence-files.json'), 'file_count': len(rows), 'path_base': 'repository'},
    'native_full_visual_legal_hosted_provider_release_acceptance': False,
    'broad_strict_release_export_still_required': True,
}
write('batch.json', batch)
print(json.dumps({'batch_sha256': sha(PACKET / 'batch.json'),
                  'evidence_files': len(rows),
                  'current_manifest_sha256': readback['current_manifest_sha256'],
                  'current_provenance_sha256': readback['current_provenance_sha256'],
                  'asset_hash_record_sha256': readback['current_asset_hash_record_sha256']}))
