#!/usr/bin/env python3
"""Run only the warranted corrected copy test and retain failures before parsing."""
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
TEST = PACKET / 'share_copy_test.rb'
REGISTRY = ROOT / 'content/product/collect_capabilities.json'
files = [Path(__file__), TEST, REGISTRY, ROOT / 'scripts/public_static_site_build.rb',
    ROOT / 'scripts/product_capabilities.rb', ROOT / 'scripts/public_app_media.rb',
    ROOT / 'scripts/public_photography.rb', ROOT / 'scripts/qa/public_content_contract.rb',
    ROOT / 'scripts/qa/public_capability_contract.rb', ROOT / 'web/public/revolut.css',
    ROOT / 'web/public/layout.css', ROOT / 'docs/release/public-website-current-content-contract.json']
files += [ROOT / name for name in json.loads(REGISTRY.read_text())['source_inputs']]
files += sorted((ROOT / 'content/legal').glob('*.yaml'))
files += [Path(shutil.which('ruby')).resolve()]


def hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


before = hashes(files)
out_path = PACKET / 'share-copy-corrected-attempt3.stdout'
err_path = PACKET / 'share-copy-corrected-attempt3.stderr'
receipt_path = PACKET / 'share-copy-corrected-attempt3.json'
if any(path.exists() for path in [out_path, err_path, receipt_path]):
    raise SystemExit('Refuse to overwrite an actual attempt receipt')
with out_path.open('w') as out, err_path.open('w') as err:
    result = subprocess.run(['ruby', str(TEST)], cwd=ROOT, stdout=out, stderr=err)
after = hashes(files)
match = re.search(r'(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips', out_path.read_text())
counts = dict(zip(['runs', 'assertions', 'failures', 'errors', 'skips'], map(int, match.groups()))) if match else None
passed = result.returncode == 0 and before == after and counts is not None and counts['runs'] == 3 and counts['assertions'] == 38 and all(counts[key] == 0 for key in ['failures', 'errors', 'skips'])
receipt = {'status': 'pass' if passed else 'fail', 'actual_command': ['ruby', str(TEST)],
    'actual_exit_code': result.returncode, 'listed_inputs_unchanged': before == after,
    'actual_summary': counts, 'minitest_executed': counts is not None,
    'source_and_interpreter_before': before, 'source_and_interpreter_after': after,
    'stdout_sha256': hashlib.sha256(out_path.read_bytes()).hexdigest(),
    'stderr_sha256': hashlib.sha256(err_path.read_bytes()).hexdigest(),
    'scope': 'Actual corrected focused copy test only after root reconciles observed source bindings. No broader maintained-test reruns, full static/media/native/legal/hosted release acceptance.'}
receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key not in ['source_and_interpreter_before', 'source_and_interpreter_after']}))
raise SystemExit(0 if passed else 1)
