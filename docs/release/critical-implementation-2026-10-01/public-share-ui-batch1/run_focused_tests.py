#!/usr/bin/env python3
"""Retain actual affected tests and their exact listed execution inputs."""
import hashlib
import json
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
CASES = [
    ('share-copy', PACKET / 'share_copy_test.rb'),
    ('static-routes', ROOT / 'scripts/tests/public_static_routes_test.rb'),
    ('legal-security-rendering', ROOT / 'scripts/tests/public_legal_rendering_test.rb'),
    ('public-links', ROOT / 'scripts/tests/public_website_links_test.rb'),
    ('capability-denials', ROOT / 'scripts/tests/public_capability_contract_test.rb'),
    ('capability-content', ROOT / 'scripts/tests/product_capability_content_test.rb'),
    ('content-contract', ROOT / 'scripts/tests/public_content_contract_test.rb'),
]
files = [Path(__file__), ROOT / 'scripts/public_static_site_build.rb', ROOT / 'scripts/public_app_media.rb',
    ROOT / 'scripts/public_photography.rb', ROOT / 'scripts/product_capabilities.rb',
    ROOT / 'scripts/qa/public_content_contract.rb', ROOT / 'scripts/qa/public_capability_contract.rb',
    ROOT / 'scripts/qa/public_static_routes.rb', ROOT / 'scripts/qa/public_website_links.rb',
    ROOT / 'scripts/generate_product_capability_content.rb', ROOT / 'content/product/collect_capabilities.json',
    ROOT / 'docs/release/public-website-current-content-contract.json',
    ROOT / 'lib/features/settings/settings_screen.dart', ROOT / 'lib/features/settings/settings_subscreens.dart',
    ROOT / 'lib/features/status/account_legal_screens.dart']
files += sorted((ROOT / 'content/legal').glob('*.yaml'))
tool = Path(shutil.which('ruby')).resolve()


def hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def run(case):
    name, test = case
    before = hashes(files + [test, tool])
    with (PACKET / (name + '.stdout')).open('w') as out, (PACKET / (name + '.stderr')).open('w') as err:
        result = subprocess.run(['ruby', str(test)], cwd=ROOT, stdout=out, stderr=err)
    after = hashes(files + [test, tool])
    match = re.search(r'(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips', (PACKET / (name + '.stdout')).read_text())
    counts = dict(zip(['runs', 'assertions', 'failures', 'errors', 'skips'], map(int, match.groups()))) if match else None
    receipt = {'status': 'pass' if result.returncode == 0 and before == after else 'fail',
        'actual_command': ['ruby', str(test)], 'actual_exit_code': result.returncode,
        'source_and_interpreter_before': before, 'source_and_interpreter_after': after,
        'listed_inputs_unchanged': before == after, 'actual_summary': counts,
        'scope': 'Actual named maintained/focused tests and listed input identity only; no full static/media/native/legal/hosted release acceptance.'}
    (PACKET / (name + '-tests.json')).write_text(json.dumps(receipt, indent=2) + '\n')
    return {'test': name, 'status': receipt['status'], 'summary': counts}


with ThreadPoolExecutor(max_workers=4) as executor:
    rows = list(executor.map(run, CASES))
(PACKET / 'focused-test-results.json').write_text(json.dumps(rows, indent=2) + '\n')
print(json.dumps(rows, indent=2))
# Preserve a real contract denial rather than change an unowned source binding.
raise SystemExit(0 if all(row['status'] == 'pass' for row in rows) else 1)
