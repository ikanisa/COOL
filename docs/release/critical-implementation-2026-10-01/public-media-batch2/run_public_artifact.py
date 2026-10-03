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
BUILD = ROOT / '.cache/public-static-current-20261002-batch2-attempt1'
CAPTURE = ROOT / '.cache/public-media-current-20261002-batch2-attempt1/capture-report.json'


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
static_inputs = regular_tree(ROOT / 'web/public') + regular_tree(ROOT / 'web/.well-known')
static_inputs += [ROOT / 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256']
environment = dict(os.environ, PUBLIC_BUILD_DIR=str(BUILD))
execute('static-build', ['ruby', 'scripts/public_static_site_build.rb'], 'static-build.stdout', static_inputs, environment)
artifact = {str(path.relative_to(BUILD)): sha(path) for path in regular_tree(BUILD)}
(PACKET / 'static-artifact.before.json').write_text(json.dumps(artifact, indent=2) + '\n')
execute('quality', ['bash', 'scripts/public_website_quality_gate.sh', '--json'], 'quality-final.json',
    static_inputs + regular_tree(BUILD), environment)
