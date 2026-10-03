#!/usr/bin/env python3
"""Bind actual capture invocation inputs without editing source or captures."""
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
SOURCE = Path('/Volumes/PRO-G40/Application Data/Codex/Codex-Home/reports/collect-media-fixture-sources/20261002-batch3-attempt2')
OUTPUT = ROOT / '.cache/public-media-current-20261002-batch3-attempt2'
FLUTTER = Path('/Volumes/PRO-G40/Development/Flutter/flutter')
NODE = Path('/Volumes/PRO-G40/Development/Node/bin/node')
CHROME = Path('/Users/jeanbosco/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')
PLAYWRIGHT = Path('/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core')

def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def hash_paths(paths):
    return {str(path): digest(path) for path in paths}

def graph(directory):
    return json.loads(subprocess.check_output(['ruby', '-r', './scripts/public_app_media', '-e',
        'puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)'], cwd=directory))

tool_paths = [NODE, CHROME, FLUTTER / 'bin/flutter', FLUTTER / 'bin/cache/flutter_tools.snapshot',
    FLUTTER / 'bin/cache/dart-sdk/bin/dart', FLUTTER / 'bin/cache/dart-sdk/bin/dartaotruntime',
    FLUTTER / 'bin/cache/dart-sdk/bin/snapshots/dart2js_aot.dart.snapshot',
    FLUTTER / 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot']
playwright_paths = sorted(path for path in PLAYWRIGHT.rglob('*') if path.is_file())
verifier_paths = [Path(__file__), ROOT / 'scripts/qa/public_browser_app_media.mjs', ROOT / 'scripts/qa/collect_diagnostic_observer.mjs',
                  ROOT / 'scripts/public_app_media.rb', ROOT / 'scripts/qa/asset_manifest_integrity.rb']
tool_before = hash_paths(tool_paths)
playwright_before = hash_paths(playwright_paths)
verifier_before = hash_paths(verifier_paths)
source_before = graph(SOURCE)
checkout_before = graph(ROOT)
assert source_before == checkout_before
environment = dict(os.environ, COLLECT_MEDIA_SOURCE=str(SOURCE), FLUTTER=str(FLUTTER / 'bin/flutter'),
                   COLLECT_MEDIA_CHROME=str(CHROME), PLAYWRIGHT_CORE_PATH=str(PLAYWRIGHT / 'index.js'))
environment.pop('COLLECT_MEDIA_REUSE_BUILD_REPORT', None)
started = datetime.now(timezone.utc).isoformat()
with (PACKET / 'capture.attempt2.stdout').open('w') as stdout, (PACKET / 'capture.attempt2.stderr').open('w') as stderr:
    result = subprocess.run([str(NODE), 'scripts/qa/public_browser_app_media.mjs', str(OUTPUT)],
                            cwd=ROOT, env=environment, stdout=stdout, stderr=stderr)
source_after = graph(SOURCE)
checkout_after = graph(ROOT)
tool_after = hash_paths(tool_paths)
playwright_after = hash_paths(playwright_paths)
verifier_after = hash_paths(verifier_paths)
unchanged = source_before == source_after == checkout_before == checkout_after and tool_before == tool_after and playwright_before == playwright_after and verifier_before == verifier_after
report_path = OUTPUT / 'capture-report.json'
capture = json.loads(report_path.read_text()) if report_path.exists() else {}
passed = result.returncode == 0 and unchanged and capture.get('status') == 'captured_pending_visual_review'
receipt = {'status': 'pass' if passed else 'fail', 'started_at_utc': started, 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
    'actual_command': [str(NODE), 'scripts/qa/public_browser_app_media.mjs', str(OUTPUT)], 'exit_code': result.returncode,
    'capture_report': str(report_path.relative_to(ROOT)), 'capture_report_sha256': digest(report_path) if report_path.exists() else None,
    'source_graph_before': source_before, 'source_graph_after': source_after, 'checkout_graph_before': checkout_before, 'checkout_graph_after': checkout_after,
    'toolchain_before': tool_before, 'toolchain_after': tool_after,
    'playwright_package_before': playwright_before, 'playwright_package_after': playwright_after,
    'verifier_before': verifier_before, 'verifier_after': verifier_after, 'all_observed_inputs_unchanged': unchanged,
    'reuse_old_compilation_or_capture': False, 'native_acceptance': False, 'hosted_release_accepted': False,
    'scope': 'Fresh actual browser fixture compilation/capture and exact stated source/tool/Playwright/verifier identity only; no full release/native/fidelity acceptance.'}
(PACKET / 'capture-execution.attempt2.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'status': receipt['status'], 'exit_code': result.returncode, 'source_files': len(source_before),
                  'all_observed_inputs_unchanged': unchanged, 'captures': len(capture.get('captures', []))}))
raise SystemExit(0 if passed else 1)
