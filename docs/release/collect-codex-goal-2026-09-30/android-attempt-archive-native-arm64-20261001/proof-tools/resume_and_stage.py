#!/usr/bin/env python3
"""Continue the same official immutable asset once, then stage on internal APFS."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from datetime import datetime, timezone

REPO = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
EXTERNAL = Path('/Users/jeanbosco/.codex/tmp/collect-android-native-proof-20261001')
PRIVATE = Path('/Users/jeanbosco/.cache/collect-android-native-proof-20261001')
LEAF = REPO / 'docs/release/collect-codex-goal-2026-09-30/android-attempt-archive-native-arm64-20261001'
TOOLS = REPO / '.cache/android-attempt-archive-native-arm64-20261001'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def main():
    os.umask(0o077)
    PRIVATE.mkdir(mode=0o700, exist_ok=False)
    if PRIVATE.resolve() != PRIVATE:
        raise RuntimeError('Internal cache resolves through a symlink')
    mount = subprocess.run(['/bin/df', '-h', str(PRIVATE)], capture_output=True, text=True, check=True, timeout=10).stdout
    if '/System/Volumes/Data' not in mount:
        raise RuntimeError('Internal APFS mount gate failed')
    (LEAF / 'internal-cache-preflight.txt').write_text(mount)
    selection = json.loads((EXTERNAL / 'toolchain-selection.json').read_text())
    archive_name = selection['archive']['name']
    for name in ('official-release-metadata.json', 'toolchain-selection.json', 'official.sha256.txt', archive_name):
        origin = EXTERNAL / name
        if not origin.is_file() or origin.is_symlink():
            raise RuntimeError('Retained official download evidence unavailable')
        shutil.copyfile(origin, PRIVATE / name)
        if sha(origin) != sha(PRIVATE / name):
            raise RuntimeError('Transfer to internal APFS failed readback')
    archive = PRIVATE / archive_name
    partial_hash = sha(archive)
    initial_bytes = archive.stat().st_size
    receipt = {'state': 'started', 'started_at': now(), 'original_external_path': str(EXTERNAL),
               'original_external_resolved': str(EXTERNAL.resolve()), 'internal_root': str(PRIVATE),
               'initial_partial_bytes': initial_bytes, 'initial_partial_sha256': partial_hash,
               'same_official_archive_url': selection['archive']['browser_download_url'],
               'bound_seconds': 900, 'resume_from_existing_partial': True,
               'no_archive_restart_or_toolchain_selection_change': True}
    (LEAF / 'download-continuation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'state': 'download_continuation', 'initial_bytes': initial_bytes, 'bound_seconds': 900}), flush=True)
    started = time.monotonic()
    result = subprocess.run([
        '/usr/bin/curl', '--fail', '--silent', '--show-error', '--location', '--proto', '=https', '--proto-redir', '=https',
        '--connect-timeout', '15', '--max-time', '900', '--max-filesize', str(240 * 1024 * 1024), '--continue-at', '-',
        '--output', str(archive), selection['archive']['browser_download_url'],
    ], capture_output=True, timeout=910)
    (LEAF / 'download-continuation.stderr').write_bytes(result.stderr)
    expected = (PRIVATE / 'official.sha256.txt').read_text().split()[0]
    actual = sha(archive)
    receipt.update({'state': 'terminal', 'finished_at': now(), 'exit_code': result.returncode,
                    'wall_seconds': time.monotonic() - started, 'final_bytes': archive.stat().st_size,
                    'final_sha256': actual, 'expected_official_sha256': expected,
                    'checksum_verified': actual == expected, 'exact_expected_bytes': archive.stat().st_size == selection['archive']['size']})
    (LEAF / 'download-continuation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if result.returncode or actual != expected or archive.stat().st_size != selection['archive']['size']:
        raise RuntimeError('Finite continuation failed; no further automatic asset retry')
    # Reuse the captured preparer's exact validation/extraction/copy logic offline.
    spec = importlib.util.spec_from_file_location('native_proof_prepare', TOOLS / 'prepare_stage.py')
    prepare = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(prepare)
    prepare.PRIVATE = PRIVATE
    def verified_existing(url, dest, seconds, maximum):
        if url not in (selection['archive']['browser_download_url'], selection['checksum']['browser_download_url']):
            raise RuntimeError('Unexpected asset requested during offline staging')
        if not dest.is_file() or dest.stat().st_size > maximum:
            raise RuntimeError('Previously verified asset unavailable')
    prepare.fetch = verified_existing
    prepare.main()
    print(json.dumps({'state': 'staging_terminal', 'status': 'staged', 'private_root': str(PRIVATE)}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        (LEAF / 'continuation-staging-failure.json').write_text(json.dumps({'at': now(), 'type': type(error).__name__, 'reason': str(error)}, indent=2) + '\n')
        raise
