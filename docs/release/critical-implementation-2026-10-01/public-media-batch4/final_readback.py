#!/usr/bin/env python3
"""Bind current local candidate and resolve dated mutable indices by exact hash."""
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(name):
    return json.loads((PACKET / name).read_text())


errors = []
stage = read('media-fixture-stage.json')
source = Path(stage['destination'])
graph = json.loads(subprocess.check_output(['ruby', '-r', './scripts/public_app_media', '-e',
    'puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)'], cwd=ROOT))
if graph != stage['browser_sources_before']:
    errors.append('Current media graph changed')
copied = {name: sha(source / name) for name in stage['source_files']}
expected = {name: row['sha256'] for name, row in stage['source_files'].items()}
if copied != expected:
    errors.append('Private authored source changed')
bindings = read('own-pub-bindings.json')['own_stage_generated_bindings']
binding_after = {name: sha(source / name) for name in bindings}
if bindings != binding_after:
    errors.append('Private generated runtime binding changed')

# Only these known preserved objects may resolve a superseded mutable index.
# Never equate duplicate basenames with equal content; require the original SHA.
preservation_roots = [
    PACKET / 'previous-publication-before-mutation', PACKET / 'publication',
    PACKET.parent / 'public-media-batch2/publication',
    PACKET.parent / 'public-media-batch3/publication',
    PACKET.parent / 'privacy-route-source-integration-batch1/before/docs/release/public-website-current-content-contract.json',
    PACKET.parent / 'privacy-ui-integration-batch1/public-content-contract-before.json',
]
preserved = {}
for directory in preservation_roots:
    paths = [directory] if directory.is_file() else list(directory.rglob('*'))
    for path in paths:
        if path.is_symlink():
            raise ValueError('Aliased preservation input')
        if path.is_file():
            preserved.setdefault(sha(path), []).append(path)
mutable_names = {'web/public/app-screens/manifest.json', 'web/public/app-screens/capture-provenance.json',
    'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256', 'docs/release/public-website-current-content-contract.json'}
old_packets = []
for name, digest in read('preparation.json')['old_sealed_packets'].items():
    directory = PACKET.parent / name
    old = json.loads((directory / 'batch.json').read_text())
    if sha(directory / 'batch.json') != digest:
        errors.append('Prior sealed batch changed: ' + name)
    indexed = dict(old.get('evidence_sha256', {}))
    indexed.update({str((directory / row['path']).relative_to(ROOT)): row['sha256'] for row in old.get('artifacts', [])})
    indexed.update({str((directory / path).relative_to(ROOT)): row['sha256'] for path, row in old.get('artifact_bindings', {}).items()})
    if 'evidence_index' in old:
        old_index_path = directory / old['evidence_index']['path']
        if sha(old_index_path) != old['evidence_index']['sha256']:
            errors.append('Prior evidence index changed: ' + name)
        old_rows = json.loads(old_index_path.read_text())['files']
        indexed.update({str((directory / row['path']).relative_to(ROOT)): row['sha256'] for row in old_rows})
    checked = []
    for path, expected_sha in indexed.items():
        current = ROOT / path
        current_sha = sha(current) if current.exists() else None
        resolved = current
        relocated = False
        if current_sha != expected_sha and (path in mutable_names or path.startswith('web/public/app-screens/')):
            candidates = preserved.get(expected_sha, [])
            if candidates:
                resolved = candidates[0]
                relocated = True
        observed = sha(resolved) if resolved.exists() else None
        if observed != expected_sha:
            errors.append('Prior indexed original differs: ' + path)
        checked.append({'original_path': path, 'expected_sha256': expected_sha, 'current_sha256': current_sha,
            'resolved_exact_original': str(resolved.relative_to(ROOT)), 'observed_sha256': observed,
            'explicit_preserved_object_resolution': relocated, 'match': observed == expected_sha})
    old_packets.append({'packet': name, 'sealed_batch_sha256': digest, 'sealed_batch_unchanged': sha(directory / 'batch.json') == digest,
        'indexed_originals': checked})

capture_path = ROOT / '.cache/public-media-current-20261002-batch4-attempt1/capture-report.json'
capture = json.loads(capture_path.read_text())
published_path = ROOT / 'web/public/app-screens/manifest.json'
published = json.loads(published_path.read_text())
screens = []
for image in capture['captures']:
    row = next(row for row in published['screens'] if row['id'] == image['id'])
    capture_sha = sha(ROOT / image['path'])
    published_sha = sha(ROOT / 'web/public/app-screens' / row['file'])
    if capture_sha != image['sha256'] or capture_sha != row['sha256'] or capture_sha != published_sha:
        errors.append('Current original pixel binding changed: ' + image['id'])
    screens.append({'id': image['id'], 'capture_sha256': capture_sha, 'published_sha256': published_sha,
        'current_file': row['file'], 'alt': row['alt']})
observer = {name: sha(ROOT / name) for name in capture['diagnostic_observer_sources_before']}
if observer != capture['diagnostic_observer_sources_before'] or observer != capture['diagnostic_observer_sources_after']:
    errors.append('Diagnostic observer/recorder current binding changed')
alt = read('publication-alt-readback.json')
if sha(published_path) != alt['current_manifest_sha256'] or sha(ROOT / alt['final_preserved_manifest']) != alt['current_manifest_sha256']:
    errors.append('Unchanged accurate final published manifest changed')

phases = []
for name, fields in [
    ('capture-execution.attempt1.json', ['toolchain_before', 'playwright_package_before', 'verifier_before']),
    ('publication-execution.json', ['inputs_before', 'toolchain_before']),
    ('static-build-execution.json', ['inputs_before', 'toolchain_before']),
    ('quality-execution.json', ['inputs_before', 'toolchain_before']),
    ('browser-routes-execution.json', ['verifier_before', 'toolchain_before']),
    ('browser-routes-execution-supplemental-share.json', ['verifier_before', 'toolchain_before']),
]:
    phase = read(name)
    checked = 0
    mismatches = []
    for field in fields:
        for path, expected_sha in phase[field].items():
            observed = sha(Path(path))
            checked += 1
            if observed != expected_sha:
                mismatches.append({'path': path, 'expected_sha256': expected_sha, 'observed_sha256': observed})
    if phase['status'] != 'pass' or mismatches:
        errors.append('Current executed phase binding changed: ' + name)
    phases.append({'receipt': name, 'receipt_sha256': sha(PACKET / name), 'listed_inputs_checked': checked,
        'all_current_inputs_equal_actual_before_endpoint': not mismatches, 'mismatches': mismatches})
# The physically private original batch3 source remains dated and unmodified.
old_stage = json.loads((PACKET.parent / 'public-media-batch3/media-fixture-stage.attempt2.json').read_text())
old_source = Path(old_stage['destination'])
old_source_checked = []
for relative, row in old_stage['source_files'].items():
    observed = sha(old_source / relative)
    if observed != row['sha256']:
        errors.append('Original batch3 private source changed: ' + relative)
    old_source_checked.append({'path': relative, 'sha256': observed, 'match': observed == row['sha256']})
root_authored = {name: sha(ROOT / name) for name in stage['source_files']}
if root_authored != expected:
    errors.append('Current authored media/support source no longer equals private stage')
source_hardlinks = [name for name in stage['source_files'] if (source / name).stat().st_nlink != 1]
if source_hardlinks:
    errors.append('Private authored source is hardlinked')
root_production = {name: sha(ROOT / name) for name in read('current-cohort-delta.json')['root4_runtime_sources']}
if root_production != read('current-cohort-delta.json')['root4_runtime_sources']:
    errors.append('Reviewed root4 production source changed')
artifact_before = read('static-artifact.before.json')
artifact_directory = ROOT / '.cache/public-static-current-20261002-batch4-attempt1'
artifact_after = {path.relative_to(artifact_directory).as_posix(): sha(path) for path in sorted(artifact_directory.rglob('*')) if path.is_file()}
if artifact_before != artifact_after:
    errors.append('Current static artifact changed')
if sha(ROOT / 'docs/release/public-website-current-content-contract.json') != read('preparation.json')['current_content_contract_sha256']:
    errors.append('Parent-owned current content contract changed')
capture_build_checks = []
for relative, expected_sha in capture['build_files'].items():
    observed_sha = sha(capture_path.parent / 'build' / relative)
    if observed_sha != expected_sha:
        errors.append('Fresh retained compiled capture artifact changed: ' + relative)
    capture_build_checks.append({'path': relative, 'sha256': observed_sha, 'match': observed_sha == expected_sha})
receipt = {'status': 'pass' if not errors else 'fail', 'read_back_at_utc': datetime.now(timezone.utc).isoformat(),
    'current_media_graph': graph, 'current_media_graph_matches_stage': graph == stage['browser_sources_before'],
    'private_authored_source_count': len(copied), 'private_authored_sources_unchanged': copied == expected,
    'private_runtime_bindings': binding_after, 'private_runtime_bindings_unchanged': binding_after == bindings,
    'observer_current': observer, 'current_manifest_sha256': sha(published_path),
    'current_provenance_sha256': sha(ROOT / 'web/public/app-screens/capture-provenance.json'),
    'current_asset_hash_record_sha256': sha(ROOT / 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256'),
    'fresh_compiled_capture_files_read': capture_build_checks,
    'root_reviewed_production_sources': root_production,
    'current_authored_media_support_equal_private': root_authored == expected,
    'private_hardlinked_authored_paths': source_hardlinks,
    'static_artifact_file_count': len(artifact_after),
    'static_artifact_sha256': artifact_after,
    'root_independent_terms_readback_sha256': sha(PACKET / 'root-independent-terms-readback.json'),
    'old_batch3_private_source_originals': old_source_checked,
    'original_batch3_source_is_current_acceptance': False,
    'screens': screens, 'prior_sealed_packets': old_packets, 'executed_phase_current_bindings': phases,
    'errors': errors, 'scope': 'Exact current local media/static/browser candidate identity and original evidence preservation. No broad source export, native/fidelity/rights/legal/provider/hosted/device/store/production acceptance.'}
(PACKET / 'final-readback.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'status': receipt['status'], 'source_count': len(graph), 'private_source_count': len(copied),
    'prior_indexed_originals': sum(len(row['indexed_originals']) for row in old_packets), 'errors': errors}))
raise SystemExit(0 if not errors else 1)
