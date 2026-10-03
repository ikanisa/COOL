#!/usr/bin/env python3
"""Private current-source ARC01 proof; maintained source is never written."""
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse

from run_owned import now, run, sha, write

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
PRIOR = ROOT / 'docs/release/critical-implementation-2026-10-01/arc01-ubuntu-resolved-batch1'
REUSE = ROOT / 'docs/release/critical-implementation-2026-10-01/arc01-ubuntu-current-preparation-batch1'
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIVATE = Path(BOUNDARY['private_root'])
CHECKOUT = PRIVATE / 'checkout'
PRIOR_PRIVATE = Path(json.loads((PRIOR / 'preparation-attempt1/private-boundary.json').read_text())['private_root'])
SDK_RUNTIME = PRIOR_PRIVATE / 'runtime'
SDK = SDK_RUNTIME / 'flutter'
CACHE = PRIOR_PRIVATE / 'pub-cache'
IMAGE = 'sha256:9f7337c32d1c03ade6f785fb71e018c02cce33b8b88a2c14e3c8edae1328935e'
DOCKER = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
OWNER = PRIVATE.name
NAME = OWNER + '-format'
EXEC = OUT / 'execution3'
EXEC.mkdir(exist_ok=False)
HARNESS = PRIVATE / 'harness3'
HARNESS.mkdir(exist_ok=False)
SOURCE = json.loads((OUT / 'source-export-attempt1/source-inventory.json').read_text())
INPUTS = SOURCE['copied_input_sha256']
EXPECTED = SOURCE['applicable_formatter_paths']
CORRECTIONS = BOUNDARY['private_candidate_correction_paths']
FIXTURE = 'tool/qa/arc01_malformed_formatter_fixture.dart'
START = time.monotonic()
WHOLE_SECONDS = 720
PREP_ONLY = sys.argv[1:] == ['prepare-three-only']
if sys.argv[1:] and not PREP_ONLY:
    raise RuntimeError('Unknown execution mode')
inventory_script = (PRIOR / 'formatter-candidate-attempt2/inventory.rb').read_bytes()
(HARNESS / 'inventory.rb').write_bytes(inventory_script)
(EXEC / 'inventory.rb').write_bytes(inventory_script)


def call(phase, argv, deadline=120, success=True):
    remaining = WHOLE_SECONDS - (time.monotonic() - START)
    if remaining <= 0:
        raise RuntimeError('Whole bounded execution exceeded before ' + phase)
    return run(EXEC, phase, argv, min(deadline, remaining), success)


def execute(phase, command, deadline=120, success=True):
    return call(phase, [DOCKER, 'exec', NAME, '/bin/bash', '-euo', 'pipefail', '-c', command], deadline, success)


def source_hashes(base):
    return {p: sha(base / p) if (base / p).is_file() else None for p in INPUTS}


def cache_readback():
    receipt = json.loads((REUSE / 'reusable-private-pub-cache-readback.json').read_text())
    actual_files = {}
    actual_links = {}
    for p in sorted(CACHE.rglob('*')):
        rel = str(p.relative_to(CACHE))
        if p.is_symlink():
            actual_links[rel] = str(p.readlink())
        elif p.is_file():
            actual_files[rel] = sha(p)
    if actual_files != receipt['files_sha256'] or actual_links != receipt['links']:
        raise RuntimeError('Previously verified exclusive Pub cache inputs changed')
    write(EXEC, 'pub-cache-readback.json', {
        'at_utc': now(), 'files_sha256': actual_files, 'links': actual_links,
        'cache_root': str(CACHE), 'prior_receipt_sha256': sha(REUSE / 'reusable-private-pub-cache-readback.json'),
        'cache_modified_by_readback': False,
    })


def dependencies():
    prior_source = json.loads((PRIOR / 'source-export-attempt1/source-inventory.json').read_text())
    dependency_paths = sorted(set(prior_source['local_dependency_input_paths']) | {'.fvmrc', 'pubspec.yaml', 'pubspec.lock'})
    if len(dependency_paths) != 171:
        raise RuntimeError('Expected 171 exact canonical dependency inputs')
    expected = {p: prior_source['copied_input_sha256'][p] for p in dependency_paths + ['analysis_options.yaml']}
    actual = {p: sha(ROOT / p) for p in expected}
    if actual != expected or any(INPUTS.get(p) != value for p, value in actual.items()):
        raise RuntimeError('Canonical Pub declaration, dependency, or analysis input changed')
    sdk_receipt = json.loads((PRIOR / 'sdk-extraction-attempt1/result.json').read_text())
    sdk_hashes = {p: sha(SDK / p) for p in sdk_receipt['sdk_file_sha256']}
    sdk_revision = subprocess.check_output(['git', '-C', str(SDK), 'rev-parse', 'HEAD'], timeout=15).decode().strip()
    if sdk_hashes != sdk_receipt['sdk_file_sha256'] or sdk_revision != sdk_receipt['sdk_git_revision']:
        raise RuntimeError('Pinned authenticated Linux SDK changed')
    config_path = PRIOR_PRIVATE / 'checkout/.dart_tool/package_config.json'
    pub_receipt = json.loads((PRIOR / 'pub-bootstrap-attempt1/result.json').read_text())
    if sha(config_path) != pub_receipt['package_config_sha256']:
        raise RuntimeError('Original canonical enforced-lock Linux package config changed')
    package = json.loads(config_path.read_text())
    if len(package['packages']) != 168:
        raise RuntimeError('Original generated package root count changed')
    roots = []
    for row in package['packages']:
        root_uri = urlparse(urljoin('file:///work/checkout/.dart_tool/package_config.json', row['rootUri']))
        if root_uri.scheme != 'file':
            raise RuntimeError('Non-file package root')
        container_path = Path(unquote(root_uri.path))
        mappings = [(Path('/work/checkout'), CHECKOUT), (Path('/work/pub-cache'), CACHE), (Path('/opt/flutter'), SDK_RUNTIME)]
        for prefix, host in mappings:
            if container_path.is_relative_to(prefix):
                mapped = host / container_path.relative_to(prefix)
                break
        else:
            raise RuntimeError('Package root outside exact readonly dependency mounts: ' + row['name'])
        if not mapped.is_dir() or not (mapped / 'pubspec.yaml').is_file():
            raise RuntimeError('Generated package root absent: ' + row['name'])
        roots.append({'name': row['name'], 'rootUri': row['rootUri'], 'container_root': str(container_path), 'current_host_root': str(mapped), 'exists': True, 'declared_library_directory_exists': (mapped / row.get('packageUri', 'lib/')).is_dir()})
    cache_readback()
    (CHECKOUT / '.dart_tool').mkdir(exist_ok=True)
    shutil.copyfile(config_path, CHECKOUT / '.dart_tool/package_config.json')
    write(EXEC, 'dependency-reuse.json', {
        'at_utc': now(), 'canonical_dependency_input_count': 171, 'current_dependency_sha256': actual,
        'analysis_options_current_sha256': actual['analysis_options.yaml'], 'sdk_current_sha256': sdk_hashes,
        'sdk_git_revision': sdk_revision, 'original_generated_package_config_sha256': sha(config_path),
        'private_copied_package_config_sha256': sha(CHECKOUT / '.dart_tool/package_config.json'),
        'package_root_count': 168, 'package_roots': roots, 'canonical_pub_repeated': False,
        'dependency_upgrade_or_download': False,
    })


def inventory(phase, fixture=False):
    execute(phase, 'ruby /opt/arc01/inventory.rb', 30)
    actual = json.loads((EXEC / (phase + '.log')).read_text())
    expected = sorted(EXPECTED + ([FIXTURE] if fixture else []))
    if actual['paths'] != expected or actual['count'] != len(expected):
        raise RuntimeError('Actual Make Git Dart inventory differs from complete frozen current source')
    return actual


def gate(phase, changed, exit_code, fixture=False):
    result = execute(phase, 'make format-check', 120, False)
    output = (EXEC / (phase + '.log')).read_text()
    observed = sorted(line.removeprefix('Changed ') for line in output.splitlines() if line.startswith('Changed '))
    count = len(EXPECTED) + int(fixture)
    match = re.search(r'Formatted (\d+) files \((\d+) changed\)', output)
    if result['exit_code'] != exit_code or result['timed_out'] or observed != sorted(changed) or not match:
        raise RuntimeError('Actual canonical Make exit/change evidence differs: ' + phase)
    if int(match.group(1)) != count or int(match.group(2)) != len(changed):
        raise RuntimeError('Actual complete formatter counts differ: ' + phase)
    return {**result, 'applicable_dart_count': count, 'would_change_paths': observed}


def cleanup():
    before = subprocess.run([DOCKER, 'inspect', NAME], capture_output=True, text=True, timeout=15)
    if before.returncode == 0:
        (EXEC / 'container-before-cleanup.json').write_text(before.stdout)
        identity = json.loads(before.stdout)[0]
        if identity['Image'] != IMAGE or identity['Config']['Labels'].get('com.collect.arc01.owner') != OWNER:
            raise RuntimeError('Refusing cleanup of unowned container')
        stop = subprocess.run([DOCKER, 'stop', '--time', '5', NAME], capture_output=True, text=True, timeout=20)
        remove = subprocess.run([DOCKER, 'rm', NAME], capture_output=True, text=True, timeout=20)
        if remove.returncode:
            raise RuntimeError('Owned removal failed')
    else:
        stop = remove = None
    final = subprocess.run([DOCKER, 'inspect', NAME], capture_output=True, text=True, timeout=15)
    listing = subprocess.run([DOCKER, 'container', 'ls', '--all', '--filter', 'label=com.collect.arc01.owner=' + OWNER, '--format', '{{json .}}'], capture_output=True, text=True, timeout=15)
    absent = (final.returncode == 1 and final.stdout.strip() == '[]' and final.stderr.strip() == 'error: no such object: ' + NAME and listing.returncode == 0 and not listing.stdout.strip())
    write(EXEC, 'container-cleanup.json', {
        'at_utc': now(), 'name': NAME, 'owner': OWNER, 'stop_exit': stop.returncode if stop else None,
        'remove_exit': remove.returncode if remove else None, 'readback_exit': final.returncode,
        'readback_stdout': final.stdout, 'readback_stderr': final.stderr,
        'owner_listing_exit': listing.returncode, 'owner_listing_stdout': listing.stdout,
        'owner_listing_stderr': listing.stderr, 'removed': absent,
    })
    if not absent:
        raise RuntimeError('Owned container absence not established')


try:
    if len(EXPECTED) != 709 or source_hashes(ROOT) != INPUTS or source_hashes(CHECKOUT) != INPUTS:
        raise RuntimeError('Current full source drift or inventory count mismatch before proof')
    if any(INPUTS.get(p) != value for p, value in BOUNDARY['expected_current_three_file_sha256'].items()):
        raise RuntimeError('Current three-file preimages changed')
    dependencies()
    call('container-create', [
        DOCKER, 'create', '--name', NAME, '--label', 'com.collect.arc01.owner=' + OWNER,
        '--platform', 'linux/amd64', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges', '--memory', '4g', '--cpus', '3', '--pids-limit', '256',
        '--env', 'CI=true', '--env', 'DART_SUPPRESS_ANALYTICS=true', '--env', 'FLUTTER_SUPPRESS_ANALYTICS=true',
        '--env', 'PUB_CACHE=/work/pub-cache', '--env', 'DART=/opt/flutter/flutter/bin/cache/dart-sdk/bin/dart', '--tmpfs', '/home/arc01:rw,uid=501,gid=1001,size=64m',
        '--tmpfs', '/tmp:rw,size=256m', '--mount', 'type=bind,source=' + str(CHECKOUT) + ',target=/work/checkout',
        '--mount', 'type=bind,source=' + str(SDK_RUNTIME) + ',target=/opt/flutter,readonly',
        '--mount', 'type=bind,source=' + str(CACHE) + ',target=/work/pub-cache,readonly',
        '--mount', 'type=bind,source=' + str(HARNESS) + ',target=/opt/arc01,readonly', IMAGE, '/bin/sleep', '720',
    ], 30)
    identity_raw = subprocess.check_output([DOCKER, 'inspect', NAME], timeout=15)
    (EXEC / 'container-identity.json').write_bytes(identity_raw)
    identity = json.loads(identity_raw)[0]
    if identity['Image'] != IMAGE or identity['Config']['Labels'].get('com.collect.arc01.owner') != OWNER or identity['HostConfig']['NetworkMode'] != 'none' or identity['HostConfig']['PortBindings'] or identity['HostConfig']['Privileged']:
        raise RuntimeError('Exact Ubuntu image, ownership or network isolation changed')
    call('container-start', [DOCKER, 'start', NAME], 20)
    execute('private-clean-git', 'test -d .git\ntest -z "$(git status --porcelain)"\ntest ! -e .git/objects/info/alternates\ngit rev-parse HEAD', 30)
    execute('toolchain-current', 'cat /etc/os-release\nuname -m\n"$DART" --version\nsha256sum /opt/flutter/flutter/bin/cache/dart-sdk/bin/dart\nmake --version\nruby --version', 30)
    if 'VERSION_ID="24.04"' not in (EXEC / 'toolchain-current.log').read_text() or 'linux_x64' not in (EXEC / 'toolchain-current.log').read_text():
        raise RuntimeError('Actual current Ubuntu Linux Dart execution not established')
    inventory('original-inventory')
    original = None if PREP_ONLY else gate('original-make-format-check', CORRECTIONS, 2)
    before = source_hashes(CHECKOUT)
    texts = {p: (CHECKOUT / p).read_text() for p in CORRECTIONS}
    execute('private-three-file-format', '"$DART" format ' + ' '.join(CORRECTIONS), 90)
    after = source_hashes(CHECKOUT)
    changed = sorted(p for p in INPUTS if before[p] != after[p])
    if changed != sorted(CORRECTIONS):
        raise RuntimeError('Proposed formatting exceeded exactly current three files')
    diff = ''.join(''.join(difflib.unified_diff(texts[p].splitlines(keepends=True), (CHECKOUT / p).read_text().splitlines(keepends=True), fromfile='before/' + p, tofile='proposed/' + p)) for p in CORRECTIONS)
    (EXEC / 'current-three-file.diff').write_text(diff)
    for p in CORRECTIONS:
        target = OUT / 'proposed' / p
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(CHECKOUT / p, target)
    write(EXEC, 'candidate-source.json', {'at_utc': now(), 'before_sha256': before, 'candidate_sha256': after, 'changed_paths': changed, 'root_source_written': False, 'current_root_acceptance': False})
    if PREP_ONLY:
        root_after = source_hashes(ROOT)
        write(EXEC, 'root-inputs-after-preparation.json', root_after)
        if root_after != INPUTS:
            raise RuntimeError('Maintained input drift during private three-file preparation')
        write(EXEC, 'result.json', {
            'at_utc': now(), 'status': 'THREE_CURRENT_FILE_FORMAT_PROPOSALS_PREPARED_ONLY',
            'three_before_sha256': {p: before[p] for p in CORRECTIONS},
            'three_proposed_sha256': {p: after[p] for p in CORRECTIONS},
            'whole_execution_bound_seconds': WHOLE_SECONDS,
            'whole_execution_elapsed_seconds_before_cleanup': time.monotonic() - START,
            'source_inputs': len(INPUTS), 'applicable_dart_count': len(EXPECTED),
            'complete_make_proof_executed': False, 'root_source_written': False,
            'current_root_acceptance': False, 'root_source_unchanged_during_preparation': True,
            'final_complete_source_capture_and_make_held_for_root_batch_integration': True,
        })
    else:
        inventory('candidate-inventory')
        candidate = gate('candidate-make-format-check', [], 0)
        if (CHECKOUT / FIXTURE).exists():
            raise RuntimeError('Owned malformed fixture path existed')
        (CHECKOUT / FIXTURE).write_text("void main(){print('arc01-synthetic-formatter-fixture');}\n")
        inventory('malformed-inventory', True)
        malformed = gate('malformed-make-format-check', [FIXTURE], 2, True)
        (CHECKOUT / FIXTURE).unlink()
        inventory('restored-inventory')
        restored = gate('restored-make-format-check', [], 0)
        root_after = source_hashes(ROOT)
        write(EXEC, 'root-inputs-after-proof.json', root_after)
        if source_hashes(CHECKOUT) != after or root_after != INPUTS:
            raise RuntimeError('Maintained input drift or private candidate changed across actual proof')
        dependency_reuse = json.loads((EXEC / 'dependency-reuse.json').read_text())
        if {p: sha(ROOT / p) for p in dependency_reuse['current_dependency_sha256']} != dependency_reuse['current_dependency_sha256'] or sha(PRIOR_PRIVATE / 'checkout/.dart_tool/package_config.json') != dependency_reuse['original_generated_package_config_sha256'] or {p: sha(SDK / p) for p in dependency_reuse['sdk_current_sha256']} != dependency_reuse['sdk_current_sha256']:
            raise RuntimeError('Reused dependency inputs changed across actual proof')
        write(EXEC, 'result.json', {
            'at_utc': now(), 'status': 'CURRENT_PRIVATE_CANDIDATE_ORIGINAL_MAKE_PASS',
            'whole_execution_elapsed_seconds_before_cleanup': time.monotonic() - START, 'whole_execution_bound_seconds': WHOLE_SECONDS,
            'original_current_source_actual_failure': original, 'private_candidate_actual_pass': candidate,
            'malformed_fixture_actual_rejection': malformed, 'restored_reviewed_candidate_actual_pass': restored,
            'full_applicable_dart_count': 709, 'only_private_correction_paths': changed,
            'three_before_sha256': {p: before[p] for p in CORRECTIONS}, 'three_proposed_sha256': {p: after[p] for p in CORRECTIONS},
            'fixture_removed': not (CHECKOUT / FIXTURE).exists(), 'maintained_source_unchanged': True,
            'root_source_written': False, 'current_root_acceptance': False, 'network': 'none',
        })
except Exception as error:
    write(EXEC, 'failure.json', {'at_utc': now(), 'type': type(error).__name__, 'error': str(error), 'root_source_written': False, 'current_root_acceptance': False})
    raise
finally:
    if (CHECKOUT / FIXTURE).exists():
        (CHECKOUT / FIXTURE).unlink()
    cleanup()

print(json.dumps({'status': 'THREE_CURRENT_FILE_FORMAT_PROPOSALS_PREPARED_ONLY' if PREP_ONLY else 'CURRENT_PRIVATE_CANDIDATE_ORIGINAL_MAKE_PASS', 'full_applicable_dart_count': 709, 'maintained_source_written': False, 'current_root_acceptance': False}))
