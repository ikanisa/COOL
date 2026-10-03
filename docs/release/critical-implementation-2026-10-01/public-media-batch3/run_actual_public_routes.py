#!/usr/bin/env python3
"""Run the maintained complete browser QA against one unchanged local artifact."""
import functools
import hashlib
import http.server
import json
import os
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
ATTEMPT = ''
BUILD = ROOT / '.cache/public-static-current-20261002-batch3-attempt1'


def manifest():
    files = {}
    for path in sorted(BUILD.rglob('*')):
        if path.is_symlink():
            raise ValueError('Aliased static artifact')
        if path.is_file():
            files[path.relative_to(BUILD).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return files


before = manifest()
verifier_paths = [Path(__file__), ROOT / 'scripts/qa/public_browser_local_network.cjs', ROOT / 'scripts/qa/collect_diagnostic_observer.mjs', ROOT / 'scripts/public_website_route_rendered_qa.js', ROOT / 'scripts/qa/public_capability_contract.rb', ROOT / 'scripts/product_capabilities.rb', ROOT / 'content/product/collect_capabilities.json', ROOT / 'scripts/qa/public_content_contract.rb', ROOT / 'scripts/public_app_media.rb', ROOT / 'scripts/qa/asset_manifest_integrity.rb', ROOT / 'docs/release/public-website-current-content-contract.json']
toolchain_paths = [Path('/Volumes/PRO-G40/Development/Node/bin/node'), Path('/Users/jeanbosco/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'), Path('/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js')]
playwright_package = Path('/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core')
toolchain_paths += sorted(path for path in playwright_package.rglob('*') if path.is_file() and path not in toolchain_paths)
def hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
verifier_before = hashes(verifier_paths)
toolchain_before = hashes(toolchain_paths)
server_log = (PACKET / ('browser-server' + ATTEMPT + '.log')).open('w')


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        server_log.write(format % args + '\n')
        server_log.flush()


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(BUILD)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
origin = f'http://127.0.0.1:{server.server_port}/'
environment = dict(os.environ, PUBLIC_WEBSITE_QA_URL=origin,
                   PUBLIC_WEBSITE_QA_OUT=str(PACKET / ('browser-routes' + ATTEMPT)), PUBLIC_BUILD_DIR=str(BUILD),
                   PLAYWRIGHT_CORE_PATH='/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js',
                   PUBLIC_WEBSITE_CHROME_PATH='/Users/jeanbosco/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')
try:
    with (PACKET / ('browser-routes' + ATTEMPT + '.stdout')).open('w') as stdout, (PACKET / ('browser-routes' + ATTEMPT + '.stderr')).open('w') as stderr:
        result = subprocess.run(['/Volumes/PRO-G40/Development/Node/bin/node', 'scripts/public_website_route_rendered_qa.js'], cwd=ROOT, env=environment, stdout=stdout, stderr=stderr)
    after = manifest()
    verifier_after = hashes(verifier_paths)
    toolchain_after = hashes(toolchain_paths)
    inputs_unchanged = verifier_before == verifier_after and toolchain_before == toolchain_after
    report = {'status': 'pass' if result.returncode == 0 and before == after and inputs_unchanged else 'fail',
              'command': ['node', 'scripts/public_website_route_rendered_qa.js'], 'exit_code': result.returncode,
              'artifact_unchanged': before == after, 'verifier_unchanged': verifier_before == verifier_after, 'verifier_before': verifier_before, 'verifier_after': verifier_after, 'toolchain_unchanged': toolchain_before == toolchain_after, 'toolchain_before': toolchain_before, 'toolchain_after': toolchain_after, 'artifact_files': before, 'artifact_files_after': after,
              'build': str(BUILD), 'loopback_origin': origin,
              'script_sha256': hashlib.sha256((ROOT / 'scripts/public_website_route_rendered_qa.js').read_bytes()).hexdigest(),
              'scope': 'Actual complete maintained rendered-route and share-link QA on one unchanged local static artifact. No hosted/provider/native/release acceptance.'}
    (PACKET / ('browser-routes-execution' + ATTEMPT + '.json')).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['status', 'exit_code', 'artifact_unchanged', 'loopback_origin']}))
    raise SystemExit(0 if report['status'] == 'pass' else 1)
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
    server_log.close()
