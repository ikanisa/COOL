#!/usr/bin/env python3
"""Seal the already itemized local content review after actual frozen route proof."""
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent


def sha(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Regular evidence file required')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


execution_path = PACKET / 'browser-routes-execution-attempt3.json'
render_path = PACKET / 'browser-routes-attempt3/route_rendered_qa.json'
execution = json.loads(execution_path.read_text())
render = json.loads(render_path.read_text())
if not (execution['status'] == 'pass' and execution['exit_code'] == 0 and
        execution['artifact_unchanged'] and execution['verifier_unchanged'] and execution['toolchain_unchanged'] and
        render['status'] == 'pass' and not render['blockedNetworkRequests'] and
        len(render['results']) == 60 and len(render['shareResults']) == 16 and
        all(not row['failures'] for row in render['results'] + render['shareResults'])):
    raise ValueError('Final actual frozen browser proof did not pass')
for path, expected in execution['verifier_after'].items():
    if sha(Path(path)) != expected:
        raise ValueError('Final verifier/helper source changed')
comparison = json.loads((PACKET / 'route-delta-review.prepared.json').read_text())
capture_path = ROOT / '.cache/public-media-current-20261001-batch1-attempt3/capture-report.json'
capture = json.loads(capture_path.read_text())
publication = json.loads((PACKET / 'publication-attempt3/publication.json').read_text())
current_media_sources = json.loads(subprocess.check_output([
    'ruby', '-r', './scripts/public_app_media', '-e',
    'puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)',
], cwd=ROOT))
if not (capture['status'] == 'captured_pending_visual_review' and capture['sources_unchanged'] and
        not capture['errors'] and not capture['external_requests'] and
        current_media_sources == capture['checkout_browser_sources_after'] and publication['status'] == 'pass' and
        publication['runtime_sha256'] == capture['runtime_after_sha256']):
    raise ValueError('Current media/source publication proof changed')
for name, expected in publication['published'].items():
    if sha(ROOT / 'web/public/app-screens' / name) != expected:
        raise ValueError('Published original capture changed')
current_path = ROOT / 'docs/release/public-website-current-content-contract.json'
prior_bytes = current_path.read_bytes()
prior = json.loads(prior_bytes)
if hashlib.sha256(prior_bytes).hexdigest() != comparison['previous_contract_sha256']:
    raise ValueError('Current content contract changed since explicit review')
for row in comparison['routes']:
    if row['review_status'] != 'locally_reviewed_source_observed_product_delta' or not row['historical_matches_baseline']:
        raise ValueError('Unreviewed route delta')
    if sha(ROOT / row['current_html_file']) != row['current_html_sha256'] or sha(ROOT / row['current_text_file']) != row['current_sha256']:
        raise ValueError('Reviewed current route evidence changed')
source_names = json.loads(subprocess.check_output([
    'ruby', '-r', './scripts/qa/public_content_contract', '-e',
    'puts JSON.generate(PublicContentContract::SOURCES)',
], cwd=ROOT))
sources = {name: sha(ROOT / name) for name in source_names}
if sources['scripts/public_static_site_build.rb'] != comparison['builder_sha256'] or sources['content/product/collect_capabilities.json'] != comparison['capability_registry_sha256']:
    raise ValueError('Reviewed capability/builder source changed')
reviewed_at = datetime.now(timezone.utc).isoformat()
comparison.update({
    'status': 'pass', 'reviewed_at': reviewed_at,
    'reviewer': 'Codex local source/content delta review',
    'browser_report': render_path.relative_to(ROOT).as_posix(), 'browser_report_sha256': sha(render_path),
    'browser_execution': execution_path.relative_to(ROOT).as_posix(), 'browser_execution_sha256': sha(execution_path),
    'fresh_capture_report': '.cache/public-media-current-20261001-batch1-attempt3/capture-report.json',
    'fresh_capture_report_sha256': sha(capture_path),
    'reviewed_source_sha256': sources, 'native_acceptance': False,
    'legal_release_approved': False, 'publication_approved': False,
    'review_limit': 'Reviewed source-observed product deltas and real local HTML/browser outcomes only. Historical baseline and legal body/rights are retained; approved availability/provider/hosted/native/release evidence remains open.'
})
comparison_path = PACKET / 'content-comparison.json'
write(comparison_path, comparison)
(PACKET / 'previous-current-content-contract.json').write_bytes(prior_bytes)
reason = 'Itemized all15 actual current route deltas against the historical baseline and immediately preceding legal/content review. Use source-observed RW/RWF/platform capability states and supported Android/email destinations, qualify planned/provider services without invented arrangements, retain unchanged legal body/rights, and bind current genuine media plus76 passing frozen local browser scenarios. No external approval inferred.'
prior.update({
    'hashes': {row['route']: row['current_sha256'] for row in comparison['routes']},
    'reviewed_source_sha256': sources,
    'current_comparison_file': comparison_path.relative_to(ROOT).as_posix(),
    'current_comparison_sha256': sha(comparison_path),
    'latest_source_review': {
        'reviewed_at': reviewed_at, 'reviewer': 'Codex local implementation/content review',
        'reason': reason, 'current_builder_sha256': sources['scripts/public_static_site_build.rb'],
        'comparison_file': comparison_path.relative_to(ROOT).as_posix(),
        'browser_report_sha256': sha(render_path), 'fresh_media_runtime_sha256': capture['runtime_after_sha256']
    },
    'legal_release_approved': False, 'publication_approved': False,
})
prior['reviewed_changes']['source_observed_capability_correction'] = reason
prior['reviewed_changes']['fresh_media_and_heading_layout'] = 'Fresh synthetic Flutter browser captures inspected and published byte-identically; actual desktop provider heading overflow repaired in the shared website grid without changing copy/fonts. Native/full visual/provider/hosted/rights acceptance remains open.'
write(current_path, prior)
print(json.dumps({'status': 'local_engineering_reviewed', 'routes': len(comparison['routes']), 'source_count': len(sources),
                  'contract_sha256': sha(current_path), 'comparison_sha256': sha(comparison_path),
                  'publication_approved': False, 'legal_release_approved': False}))
