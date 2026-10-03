#!/usr/bin/env python3
"""One private, verified official JDK download and exact retained proof staging."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone

REPO = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PRIVATE = Path('/Users/jeanbosco/.codex/tmp/collect-android-native-proof-20261001')
LEAF = REPO / 'docs/release/collect-codex-goal-2026-09-30/android-attempt-archive-native-arm64-20261001'
OLD = REPO / 'docs/release/collect-codex-goal-2026-09-30/android-attempt-archive/native-final-unverified'


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def fetch(url, dest, seconds, maximum):
    if not url.startswith('https://github.com/adoptium/temurin21-binaries/releases/download/'):
        raise RuntimeError('Nonofficial release asset refused')
    if dest.exists():
        raise RuntimeError('Existing download refused')
    result = subprocess.run([
        '/usr/bin/curl', '--fail', '--silent', '--show-error', '--location',
        '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '15',
        '--max-time', str(seconds), '--max-filesize', str(maximum), '--output', str(dest), url,
    ], capture_output=True, timeout=seconds + 10)
    (PRIVATE / (dest.name + '.fetch.stderr')).write_bytes(result.stderr)
    if result.returncode != 0 or not dest.is_file() or dest.stat().st_size > maximum:
        raise RuntimeError('Bounded official asset download failed')


def closure(root):
    result = {}
    for p in sorted(root.rglob('*')):
        rel = str(p.relative_to(root))
        if p.is_symlink():
            resolved = p.resolve(strict=True)
            if not resolved.is_relative_to(root.resolve()):
                raise RuntimeError('Runtime symlink escaped private toolchain')
            result[rel] = {'kind': 'symlink', 'target': os.readlink(p)}
        elif p.is_file():
            result[rel] = {'kind': 'file', 'bytes': p.stat().st_size, 'sha256': sha(p),
                           'mode': oct(p.stat().st_mode & 0o777)}
        elif p.is_dir():
            result[rel] = {'kind': 'directory', 'mode': oct(p.stat().st_mode & 0o777)}
        else:
            raise RuntimeError('Unexpected runtime filesystem entry')
    return result


def main():
    os.umask(0o077)
    started = now()
    selection = json.loads((PRIVATE / 'toolchain-selection.json').read_text())
    fetch(selection['checksum']['browser_download_url'], PRIVATE / 'official.sha256.txt', 60, 4096)
    checksum_text = (PRIVATE / 'official.sha256.txt').read_text()
    expected = checksum_text.split()[0]
    if len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected):
        raise RuntimeError('Invalid official SHA256')
    archive = PRIVATE / selection['archive']['name']
    fetch(selection['archive']['browser_download_url'], archive, 300, 240 * 1024 * 1024)
    actual = sha(archive)
    if actual != expected or archive.stat().st_size != selection['archive']['size']:
        raise RuntimeError('Official archive checksum/size mismatch: extraction refused')
    extracted = PRIVATE / 'jdk'
    extracted.mkdir(mode=0o700)
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        if len(members) > 20000 or sum(m.size for m in members) > 1024 * 1024 * 1024:
            raise RuntimeError('Unbounded toolchain archive refused')
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise RuntimeError('Unsafe toolchain archive entry')
            if member.issym() or member.islnk():
                target = member.linkname if member.islnk() else posixpath.join(posixpath.dirname(member.name), member.linkname)
                target = posixpath.normpath(target)
                if target.startswith('/') or target == '..' or target.startswith('../'):
                    raise RuntimeError('Unsafe toolchain archive link')
        tar.extractall(extracted, members=members, filter='data')
    java_paths = list(extracted.glob('*/Contents/Home/bin/java'))
    if len(java_paths) != 1:
        raise RuntimeError('Unexpected JDK layout')
    java = java_paths[0]
    arch = subprocess.run(['/usr/bin/file', str(java)], capture_output=True, text=True, check=True, timeout=10).stdout.strip()
    if 'arm64' not in arch or 'x86_64' in arch:
        raise RuntimeError('Native arm64 JDK unavailable')
    env = {'PATH': os.defpath, 'HOME': str(PRIVATE), 'LANG': 'C.UTF-8', 'TMPDIR': str(PRIVATE)}
    version = subprocess.run([str(java), '-version'], capture_output=True, timeout=20, env=env)
    if version.returncode or b'21.0.' not in version.stderr:
        raise RuntimeError('JDK21 version preflight failed')
    (LEAF / 'java-version.stderr').write_bytes(version.stderr)
    (LEAF / 'java-version.stdout').write_bytes(version.stdout)
    # Freeze all runtime bytes, retaining only owner execute/read permission.
    for p in sorted(extracted.rglob('*'), reverse=True):
        if p.is_symlink():
            continue
        mode = 0o500 if p.is_dir() or p.stat().st_mode & 0o111 else 0o400
        p.chmod(mode)
    runtime = closure(extracted)
    write(LEAF / 'jdk-runtime-closure.json', runtime)
    (LEAF / 'official-release-metadata.json').write_bytes((PRIVATE / 'official-release-metadata.json').read_bytes())
    (LEAF / 'official.sha256.txt').write_text(checksum_text)
    write(LEAF / 'toolchain-provenance.json', {
        'captured_at': now(), 'official_metadata_url': selection['metadata_url'],
        'browsed_primary_sources': selection['browse_primary'], 'release_tag': selection['tag'],
        'published_at': selection['published_at'], 'archive_name': archive.name,
        'archive_url': selection['archive']['browser_download_url'],
        'checksum_url': selection['checksum']['browser_download_url'],
        'archive_sha256': actual, 'archive_bytes': archive.stat().st_size,
        'checksum_verified_before_extraction': True, 'archive_retained_private': str(archive),
        'jdk_root': str(extracted), 'java': str(java), 'architecture_observation': arch,
        'runtime_closure_sha256': sha(LEAF / 'jdk-runtime-closure.json'),
        'no_global_install_or_java_configuration_changed': True,
        'supply_chain_limit': 'SHA256 matches official HTTPS release asset; no independent signature/reproducible-build verification claimed.',
    })
    previous = json.loads((OLD / 'validation.json').read_text())
    stage = PRIVATE / 'stage'
    stage.mkdir(mode=0o700)
    source = stage / 'source'
    binaries = stage / 'binaries'
    staged = {}
    for name, expected in previous['source_sha256'].items():
        origin = REPO / name
        if origin.is_symlink() or sha(origin) != expected:
            raise RuntimeError('Selected source drift before staging: ' + name)
        dest = source / name
        dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copyfile(origin, dest)
        if sha(dest) != expected:
            raise RuntimeError('Copied source failed readback')
        dest.chmod(0o400)
        evidence = LEAF / 'source' / name
        evidence.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copyfile(dest, evidence)
    for index, (name, expected) in enumerate(previous['binary_sha256'].items()):
        origin = Path(name)
        if origin.is_symlink() or sha(origin) != expected:
            raise RuntimeError('Selected dependency drift before staging: ' + name)
        binaries.mkdir(mode=0o700, exist_ok=True)
        dest = binaries / (str(index).zfill(2) + '-' + origin.name)
        shutil.copyfile(origin, dest)
        if sha(dest) != expected:
            raise RuntimeError('Copied dependency failed readback')
        dest.chmod(0o400)
        staged[name] = {'path': str(dest), 'sha256': expected, 'bytes': dest.stat().st_size}
    shims = stage / 'shims'
    shims.mkdir(mode=0o700)
    for name, expected in previous['shim_sha256'].items():
        origin = OLD / 'shims' / name
        if sha(origin) != expected:
            raise RuntimeError('Captured shim drift')
        dest = shims / name
        shutil.copyfile(origin, dest)
        dest.chmod(0o400)
        evidence = LEAF / 'shims' / name
        evidence.parent.mkdir(mode=0o700, exist_ok=True)
        shutil.copyfile(dest, evidence)
    for directory in (source, binaries, shims):
        for p in sorted(directory.rglob('*'), reverse=True):
            if p.is_dir():
                p.chmod(0o500)
        directory.chmod(0o500)
    changed = [p for p, expected in previous['source_sha256'].items() if sha(REPO / p) != expected]
    if changed:
        raise RuntimeError('Source changed during capture: ' + ','.join(changed))
    result = {'status': 'staged', 'capture_started_at': started, 'capture_completed_at': now(),
              'private_root': str(PRIVATE), 'source_root': str(source), 'java': str(java),
              'source_sha256': previous['source_sha256'], 'source_changes': changed,
              'binary_sha256': previous['binary_sha256'], 'staged_binaries': staged,
              'shim_sha256': previous['shim_sha256'], 'shim_root': str(shims),
              'jdk_root': str(extracted), 'jdk_runtime_closure_sha256': sha(LEAF / 'jdk-runtime-closure.json'),
              'prior_receipt_sha256': sha(OLD / 'validation.json'),
              'source_scope': 'Exact unchanged 36 selected inputs/14 original binary pins/5 shims; new native arm64 JDK21 runtime closure.'}
    write(LEAF / 'staging.json', result)
    write(PRIVATE / 'staging.json', result)
    print(json.dumps({'status': 'staged', 'source_count': len(previous['source_sha256']),
                      'original_binary_pins': len(staged), 'runtime_files': sum(v['kind'] == 'file' for v in runtime.values()),
                      'java': str(java), 'release': selection['tag']}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        write(LEAF / 'staging-failure.json', {'status': 'failed', 'at': now(), 'error_type': type(error).__name__, 'reason': str(error)})
        raise
