#!/usr/bin/env python3
"""Read back exact current media closure and retain dated packet identities."""
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent


def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def read(name):
    return json.loads((PACKET / name).read_text())


errors = []
stage = read('media-fixture-stage.attempt1.json')
source = Path(stage['destination'])
graph = json.loads(subprocess.check_output(['ruby', '-r', './scripts/public_app_media', '-e',
    'puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)'], cwd=ROOT))
if graph != stage['browser_sources_before']:
    errors.append('Current exact media graph changed')
copied = {name: sha(source / name) for name in stage['source_files']}
expected_copied = {name: item['sha256'] for name, item in stage['source_files'].items()}
if copied != expected_copied:
    errors.append('Immutable staged authored sources changed')
bindings = read('fixture-pub-get.attempt1.json')['generated_bindings']
binding_after = {name: sha(source / name) for name in bindings}
if bindings != binding_after:
    errors.append('Own staged runtime bindings changed')

prior_rows = []
for before in read('prior-sealed-packets.before.json'):
    directory = PACKET.parent / before['packet']
    original = json.loads((directory / 'batch.json').read_text())
    row = {'packet': before['packet'], 'batch_sha256_before': before['batch_sha256_before'],
        'batch_sha256_after': sha(directory / 'batch.json'), 'report_sha256_before': before['report_sha256_before'],
        'report_sha256_after': sha(directory / 'README.md'), 'indexed_files': [], 'exceptions': []}
    entries = original.get('evidence_sha256', {})
    entries.update({str((directory / item['path']).relative_to(ROOT)): item['sha256'] for item in original.get('artifacts', [])})
    for name, expected in entries.items():
        path = ROOT / name
        observed = sha(path)
        resolved = path
        if observed != expected and name in ['web/public/app-screens/manifest.json', 'web/public/app-screens/capture-provenance.json']:
            resolved = PACKET / 'publication/previous-browser-media' / path.name
            row['exceptions'].append({'original_indexed_path': name, 'original_sha256': expected,
                'current_published_sha256': observed, 'preserved_original_path': str(resolved.relative_to(ROOT)),
                'preserved_original_sha256': sha(resolved),
                'reason': 'Explicit fresh source-bound publication supersedes mutable current metadata; dated packet bytes and exact old originals remain intact.'})
        final = sha(resolved)
        row['indexed_files'].append({'original_path': name, 'expected_sha256': expected,
            'resolved_original_path': str(resolved.relative_to(ROOT)), 'observed_sha256': final, 'match': final == expected})
        if final != expected:
            errors.append('Prior indexed original differs: ' + name)
    if row['batch_sha256_before'] != row['batch_sha256_after'] or row['report_sha256_before'] != row['report_sha256_after']:
        errors.append('Original sealed packet changed: ' + before['packet'])
    prior_rows.append(row)

capture_path = ROOT / '.cache/public-media-current-20261002-batch2-attempt1/capture-report.json'
capture = json.loads(capture_path.read_text())
published = json.loads((ROOT / 'web/public/app-screens/manifest.json').read_text())
screens = []
for image in capture['captures']:
    final = next(row for row in published['screens'] if row['id'] == image['id'])
    source_sha = sha(ROOT / image['path'])
    published_sha = sha(ROOT / 'web/public/app-screens' / final['file'])
    if source_sha != image['sha256'] or source_sha != final['sha256'] or source_sha != published_sha:
        errors.append('Current original/publication pixel binding differs: ' + image['id'])
    screens.append({'id': image['id'], 'capture_path': image['path'], 'published_file': final['file'],
        'capture_sha256': source_sha, 'published_sha256': published_sha})
observer_after = {name: sha(ROOT / name) for name in capture['diagnostic_observer_sources_before']}
if observer_after != capture['diagnostic_observer_sources_before'] or observer_after != capture['diagnostic_observer_sources_after']:
    errors.append('Exact diagnostic observer/recorder binding differs')

# Extend the actual earlier interpreter/verifier endpoint bindings through this
# final readback. This is identity of listed files, not whole-SDK provenance.
phase_bindings = []
for receipt_name, fields in [
    ('capture-execution.attempt1.json', ['toolchain_before', 'playwright_package_before', 'verifier_before']),
    ('publication-execution.json', ['inputs_before', 'toolchain_before']),
    ('static-build-execution.json', ['inputs_before', 'toolchain_before']),
    ('quality-execution.json', ['inputs_before', 'toolchain_before']),
    ('browser-routes-execution.json', ['verifier_before', 'toolchain_before']),
    ('browser-routes-execution-supplemental-share.json', ['verifier_before', 'toolchain_before']),
]:
    phase = read(receipt_name)
    checked = 0
    mismatches = []
    for field in fields:
        for name, expected in phase[field].items():
            observed = sha(Path(name))
            checked += 1
            if observed != expected:
                mismatches.append({'path': name, 'expected_sha256': expected, 'observed_sha256': observed})
    if phase['status'] != 'pass' or mismatches:
        errors.append('Executed phase final binding differs: ' + receipt_name)
    phase_bindings.append({'executed_receipt': receipt_name, 'receipt_sha256': sha(PACKET / receipt_name),
        'listed_inputs_checked': checked, 'all_current_listed_inputs_match_actual_before_endpoint': not mismatches,
        'mismatches': mismatches})

receipt = {'status': 'pass' if not errors else 'fail', 'observed_at_utc': datetime.now(timezone.utc).isoformat(),
    'current_media_graph': graph, 'current_media_graph_matches_original_staged_graph': graph == stage['browser_sources_before'],
    'stage_original_source_count': len(copied), 'stage_original_sources_unchanged': copied == expected_copied,
    'staged_binding_hashes': binding_after, 'staged_bindings_unchanged': binding_after == bindings,
    'diagnostic_observer_sources_current': observer_after, 'prior_sealed_packets': prior_rows,
    'executed_phase_final_bindings': phase_bindings,
    'screens': screens, 'errors': errors, 'scope': 'Exact current media graph, private authored source/runtime bindings, unedited image lineage and preserved original indexed evidence only; no broad export or acceptance.'}
(PACKET / 'final-readback.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'status': receipt['status'], 'graph_count': len(graph), 'stage_source_count': len(copied),
    'prior_indexed_files_checked': sum(len(row['indexed_files']) for row in prior_rows), 'errors': errors}))
raise SystemExit(0 if not errors else 1)
