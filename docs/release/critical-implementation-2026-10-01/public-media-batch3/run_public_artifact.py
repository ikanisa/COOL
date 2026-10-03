#!/usr/bin/env python3
"""Observe actual publisher, static build and strict quality inputs separately."""
import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
BUILD = ROOT / '.cache/public-static-current-20261002-batch3-attempt1'
CAPTURE = ROOT / '.cache/public-media-current-20261002-batch3-attempt2/capture-report.json'


def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def hashes(paths):
    return {str(path): sha(path) for path in sorted(set(paths))}


def regular_tree(directory):
    result = []
    for path in sorted(directory.rglob('*')):
        if path.is_symlink():
            raise ValueError('Aliased observed input: ' + str(path))
        if path.is_file():
            result.append(path)
    return result


def graph():
    return json.loads(subprocess.check_output(['ruby', '-r', './scripts/public_app_media', '-e',
        'puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)'], cwd=ROOT))


fixed = [Path(__file__), ROOT / 'scripts/assets/publish_public_app_media.py',
    ROOT / 'scripts/public_static_site_build.rb', ROOT / 'scripts/public_photography.rb',
    ROOT / 'scripts/assets/build_public_photography.mjs', ROOT / 'scripts/product_capabilities.rb',
    ROOT / 'scripts/generate_product_capability_content.rb', ROOT / 'scripts/public_app_media.rb',
    ROOT / 'scripts/qa/asset_manifest_integrity.rb', ROOT / 'scripts/qa/public_capability_contract.rb',
    ROOT / 'scripts/qa/public_content_contract.rb', ROOT / 'scripts/public_website_quality_gate.sh',
    ROOT / 'scripts/qa/collect_diagnostic_observer.mjs', ROOT / 'scripts/qa/public_browser_app_media.mjs',
    ROOT / 'docs/PRODUCT.md', ROOT / 'docs/release/public-website-content-baseline.json',
    ROOT / 'docs/release/public-website-current-content-contract.json', CAPTURE, PACKET / 'visual-review.json']
contract = json.loads((ROOT / 'docs/release/public-website-current-content-contract.json').read_text())
fixed += [ROOT / name for name in contract['reviewed_source_sha256']]
fixed += [ROOT / contract['current_comparison_file'], ROOT / 'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt121/content-comparison.json']
fixed += regular_tree(ROOT / 'content/legal') + regular_tree(ROOT / 'content/product')
fixed += regular_tree(ROOT / 'assets/marketing/rwanda')
toolchain = [Path(shutil.which(name)).resolve() for name in ['python3', 'ruby', 'bash']]


def execute(name, command, stdout_name, additional, environment=None):
    started = datetime.now(timezone.utc).isoformat()
    source_before = graph()
    inputs_before = hashes(fixed + additional)
    toolchain_before = hashes(toolchain)
    with (PACKET / stdout_name).open('w') as stdout, (PACKET / (name + '.stderr')).open('w') as stderr:
        result = subprocess.run(command, cwd=ROOT, env=environment, stdout=stdout, stderr=stderr)
    source_after = graph()
    inputs_after = hashes(fixed + additional)
    toolchain_after = hashes(toolchain)
    unchanged = source_before == source_after and inputs_before == inputs_after and toolchain_before == toolchain_after
    receipt = {'status': 'pass' if result.returncode == 0 and unchanged else 'fail',
        'actual_command': command, 'exit_code': result.returncode, 'started_at_utc': started,
        'finished_at_utc': datetime.now(timezone.utc).isoformat(), 'all_observed_inputs_unchanged': unchanged,
        'source_before': source_before, 'source_after': source_after,
        'inputs_before': inputs_before, 'inputs_after': inputs_after,
        'toolchain_before': toolchain_before, 'toolchain_after': toolchain_after,
        'scope': 'Actual stated local step and exact observed input identity; no native, legal, provider, hosted or release acceptance.'}
    (PACKET / (name + '-execution.json')).write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'step': name, 'status': receipt['status'], 'exit_code': result.returncode, 'inputs_unchanged': unchanged}), flush=True)
    if receipt['status'] != 'pass':
        raise SystemExit(1)


assert not (PACKET / 'publication').exists() and not BUILD.exists(), 'Fresh output paths required'
execute('publication', ['python3', 'scripts/assets/publish_public_app_media.py', '--capture-report', str(CAPTURE),
    '--visual-review', str(PACKET / 'visual-review.json'), '--packet', str(PACKET / 'publication')],
    'publication.stdout', [])
# The current fixture truthfully renders the no-service recovery state. Preserve
# the exact maintained publisher output before this owner-authorized copy-only
# metadata correction; do not modify its capture/provenance/review evidence.
manifest_path = ROOT / 'web/public/app-screens/manifest.json'
published = manifest_path.read_bytes()
assert published == (PACKET / 'publication/replacement-media/manifest.json').read_bytes()
preserved = PACKET / 'publication/publisher-produced-manifest-before-alt.json'
preserved.write_bytes(published)
manifest_before = json.loads(published)
manifest_after = json.loads(published)
row = next(row for row in manifest_after['screens'] if row['id'] == 'account-deletion')
old_alt = 'Collect account deletion screen before any reason or submission is selected'
new_alt = 'Collect account deletion request unavailable without a configured signed-in service, with a Get help action'
assert row['alt'] == old_alt
assert row['sha256'] == next(row for row in json.loads(CAPTURE.read_text())['captures'] if row['id'] == 'account-deletion')['sha256']
row['alt'] = new_alt
restored = json.loads(json.dumps(manifest_after))
next(row for row in restored['screens'] if row['id'] == 'account-deletion')['alt'] = old_alt
assert restored == manifest_before
manifest_path.write_text(json.dumps(manifest_after, indent=2, ensure_ascii=False) + '\n')
final_manifest = PACKET / 'publication/final-manifest-after-alt.json'
final_manifest.write_bytes(manifest_path.read_bytes())
(PACKET / 'publication-alt-correction.json').write_text(json.dumps({
    'status': 'pass', 'scope': 'Exact one-field owner-authorized account-deletion alt correction after strict publication. No source, pixels, capture/provenance, rights or new approval change.',
    'path': 'web/public/app-screens/manifest.json', 'field': 'screens[id=account-deletion].alt',
    'before': old_alt, 'after': new_alt, 'one_field_only': restored == manifest_before,
    'publisher_produced_manifest': str(preserved.relative_to(ROOT)), 'publisher_produced_manifest_sha256': sha(preserved),
    'current_manifest_sha256': sha(manifest_path), 'final_preserved_manifest': str(final_manifest.relative_to(ROOT)),
    'final_preserved_manifest_sha256': sha(final_manifest), 'native_acceptance': False, 'publication_approval': False,
}, indent=2) + '\n')
assert manifest_path.read_bytes() == final_manifest.read_bytes()
static_inputs = regular_tree(ROOT / 'web/public') + regular_tree(ROOT / 'web/.well-known')
static_inputs += [ROOT / 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256']
environment = dict(os.environ, PUBLIC_BUILD_DIR=str(BUILD))
execute('static-build', ['ruby', 'scripts/public_static_site_build.rb'], 'static-build.stdout', static_inputs, environment)
artifact = {str(path.relative_to(BUILD)): sha(path) for path in regular_tree(BUILD)}
(PACKET / 'static-artifact.before.json').write_text(json.dumps(artifact, indent=2) + '\n')
execute('quality', ['bash', 'scripts/public_website_quality_gate.sh', '--json'], 'quality-final.json',
    static_inputs + regular_tree(BUILD), environment)
