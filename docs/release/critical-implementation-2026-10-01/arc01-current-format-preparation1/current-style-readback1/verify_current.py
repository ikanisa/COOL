#!/usr/bin/env python3
"""Compose the preserved full Make proof with two changed Dart format checks."""
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

from run_owned import run, sha, write

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[4]
BASE = OUT.parent / 'final-proof2'
DOCKER = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
IMAGE = 'sha256:9f7337c32d1c03ade6f785fb71e018c02cce33b8b88a2c14e3c8edae1328935e'
SDK_RUNTIME = Path('/Volumes/PRO-G40/Temporary/collect-arc01-ubuntu-resolved-20261002-35c1bc3c8800/runtime')
CACHE = SDK_RUNTIME.parent / 'pub-cache'
EXACT_TWO = {
    'scripts/tests/admin_receipt_source_busy_test.dart': 'b341d0bcd5fed131d0f0a1d517f6da990eb278929aa941110f87152941ed1993',
    'test/support/test_capture_paths.dart': '1053c008625b9df2bcc9d661da0dd6d27b84312e6aaaf672025024d3ca2b37f1',
}
SOURCE = json.loads((BASE / 'source-export-attempt1/source-inventory.json').read_text())
REUSE = json.loads((BASE / 'execution1/dependency-reuse.json').read_text())
INPUTS = SOURCE['copied_input_sha256']
EXPECTED_DART = SOURCE['applicable_formatter_paths']
CONTROLS = sorted({'.fvmrc', '.gitignore', 'Makefile', 'scripts/qa/dart_format.rb',
                   'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
                   'third_party/gotrue/UPSTREAM-SHA256.json'} |
                  {p for p in INPUTS if Path(p).name in ('pubspec.yaml', 'analysis_options.yaml')})
PRIVATE = Path('/Volumes/PRO-G40/Temporary') / ('collect-arc01-current-style-' + uuid.uuid4().hex)
PRIVATE.mkdir(exist_ok=False)
CHECKOUT = PRIVATE / 'checkout'
CHECKOUT.mkdir()
OWNER = PRIVATE.name
NAME = OWNER + '-format'
START = time.monotonic()
WHOLE_BOUND = 180


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def call(name, argv, deadline=30, success=True):
    remaining = WHOLE_BOUND - (time.monotonic() - START)
    if remaining <= 0:
        raise RuntimeError('Whole bounded partial readback expired before ' + name)
    return run(OUT, name, argv, min(deadline, remaining), success)


def current_scope():
    raw = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others',
                                  '--exclude-standard', '--', '*.dart'], cwd=ROOT, timeout=30)
    paths = sorted(set(p.decode() for p in raw.split(b'\0') if p))
    non_docs = [p for p in paths if not p.startswith('docs/release/') and (ROOT / p).is_file()]
    if non_docs != SOURCE['non_docs_dart_paths']:
        raise RuntimeError('Maintained Git Dart inventory changed; full proof cannot be reused')
    current = {p: sha(ROOT / p) for p in non_docs}
    changed = sorted(p for p in current if current[p] != INPUTS[p])
    if changed != sorted(EXACT_TWO) or any(current[p] != value for p, value in EXACT_TWO.items()):
        raise RuntimeError('Changed Dart scope or exact frozen two-file preimages differ')
    controls = {p: sha(ROOT / p) for p in CONTROLS}
    if any(value != INPUTS[p] for p, value in controls.items()):
        raise RuntimeError('Formatter, inventory, language or analysis control changed')
    return {'at_utc': now(), 'dart_sha256': current, 'formatter_control_sha256': controls,
            'applicable_dart_count': len(EXPECTED_DART),
            'unchanged_applicable_dart_count': len(EXPECTED_DART) - len(EXACT_TWO),
            'changed_applicable_dart_paths': changed,
            'hash_identical_upstream_inputs_unchanged': True}


def cleanup():
    observed = subprocess.run([DOCKER, 'inspect', NAME], capture_output=True, text=True, timeout=15)
    stop = remove = None
    if observed.returncode == 0:
        (OUT / 'owned-container-before-cleanup.json').write_text(observed.stdout)
        identity = json.loads(observed.stdout)[0]
        if identity['Image'] != IMAGE or identity['Config']['Labels'].get('com.collect.arc01.owner') != OWNER:
            raise RuntimeError('Refusing cleanup of unowned container')
        stop = subprocess.run([DOCKER, 'stop', '--time', '5', NAME], capture_output=True, text=True, timeout=20)
        remove = subprocess.run([DOCKER, 'rm', NAME], capture_output=True, text=True, timeout=20)
        if remove.returncode:
            raise RuntimeError('Owned container removal failed')
    final = subprocess.run([DOCKER, 'inspect', NAME], capture_output=True, text=True, timeout=15)
    listing = subprocess.run([DOCKER, 'container', 'ls', '--all', '--filter',
                              'label=com.collect.arc01.owner=' + OWNER, '--format', '{{json .}}'],
                             capture_output=True, text=True, timeout=15)
    absent = (final.returncode == 1 and final.stdout.strip() == '[]'
              and final.stderr.strip() == 'error: no such object: ' + NAME
              and listing.returncode == 0 and not listing.stdout.strip())
    write(OUT, 'owned-container-cleanup.json', {
        'at_utc': now(), 'container_name': NAME, 'owner': OWNER,
        'stop_exit': stop.returncode if stop else None, 'remove_exit': remove.returncode if remove else None,
        'inspect_exit': final.returncode, 'inspect_stdout': final.stdout, 'inspect_stderr': final.stderr,
        'owner_listing_exit': listing.returncode, 'owner_listing_stdout': listing.stdout,
        'owner_listing_stderr': listing.stderr, 'removed': absent,
    })
    if not absent:
        raise RuntimeError('Exact owned container absence not established')


try:
    if sha(BASE / 'packet-files.json') != '8035002b7108f93776afb83c6f3b2d9c4f9f32627c00a5e059e12ed7b2ac6d37':
        raise RuntimeError('Preserved full Make packet hash differs')
    for p, expected in json.loads((BASE / 'packet-files.json').read_text())['files'].items():
        if sha(BASE / p) != expected:
            raise RuntimeError('Preserved full Make leaf changed: ' + p)
    before = current_scope()
    write(OUT, 'current-scope-before.json', before)
    sdk_before = {p: sha(SDK_RUNTIME / 'flutter' / p) for p in REUSE['sdk_current_sha256']}
    if sdk_before != REUSE['sdk_current_sha256']:
        raise RuntimeError('Exact pinned Linux SDK inputs changed')
    cache_basis = json.loads((BASE / 'execution1/pub-cache-readback.json').read_text())
    cache_files = {str(p.relative_to(CACHE)): sha(p) for p in sorted(CACHE.rglob('*')) if p.is_file() and not p.is_symlink()}
    cache_links = {str(p.relative_to(CACHE)): str(p.readlink()) for p in CACHE.rglob('*') if p.is_symlink()}
    if cache_files != cache_basis['files_sha256'] or cache_links != cache_basis['links']:
        raise RuntimeError('Readonly canonical formatter dependency cache differs')
    config = SDK_RUNTIME.parent / 'checkout/.dart_tool/package_config.json'
    if sha(config) != REUSE['original_generated_package_config_sha256']:
        raise RuntimeError('Canonical generated language metadata changed')
    copied = sorted(set(EXACT_TWO) | {'pubspec.yaml', 'analysis_options.yaml'})
    for p in copied:
        target = CHECKOUT / p
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / p, target)
        if sha(target) != (EXACT_TWO.get(p) or INPUTS[p]):
            raise RuntimeError('Frozen private partial copy mismatch: ' + p)
    (CHECKOUT / '.dart_tool').mkdir()
    shutil.copyfile(config, CHECKOUT / '.dart_tool/package_config.json')
    write(OUT, 'reused-basis.json', {
        'at_utc': now(), 'full_original_make_packet_sha256': sha(BASE / 'packet-files.json'),
        'full_original_make_result_sha256': sha(BASE / 'execution1/result.json'),
        'full_original_make_independent_readback_sha256': sha(BASE / 'execution1/independent-readback.json'),
        'sdk_sha256': sdk_before, 'canonical_generated_package_config_sha256': sha(config),
        'private_copied_generated_package_config_sha256': sha(CHECKOUT / '.dart_tool/package_config.json'),
        'verified_readonly_cache_file_count': len(cache_files), 'verified_readonly_cache_link_count': len(cache_links),
        'collect_language_version': next(p['languageVersion'] for p in json.loads(config.read_text())['packages'] if p['name'] == 'collect_app'),
        'private_checkout': str(CHECKOUT), 'full_make_repeated': False,
        'malformed_and_restored_make_proof_repeated': False,
    })
    call('container-create', [DOCKER, 'create', '--name', NAME, '--label', 'com.collect.arc01.owner=' + OWNER,
        '--platform', 'linux/amd64', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
        '--security-opt', 'no-new-privileges', '--memory', '512m', '--cpus', '1', '--pids-limit', '64',
        '--env', 'DART_SUPPRESS_ANALYTICS=true', '--env', 'PUB_CACHE=/work/pub-cache',
        '--mount', 'type=bind,source=' + str(CHECKOUT) + ',target=/work/checkout,readonly',
        '--mount', 'type=bind,source=' + str(SDK_RUNTIME) + ',target=/opt/flutter,readonly',
        '--mount', 'type=bind,source=' + str(CACHE) + ',target=/work/pub-cache,readonly',
        '--tmpfs', '/home/arc01:rw,uid=501,gid=1001,size=32m', '--tmpfs', '/tmp:rw,size=32m',
        IMAGE, '/bin/sleep', '180'], 30)
    identity_raw = subprocess.check_output([DOCKER, 'inspect', NAME], timeout=15)
    (OUT / 'owned-container-identity.json').write_bytes(identity_raw)
    identity = json.loads(identity_raw)[0]
    if identity['Image'] != IMAGE or identity['Config']['Labels'].get('com.collect.arc01.owner') != OWNER or identity['HostConfig']['NetworkMode'] != 'none' or identity['HostConfig']['PortBindings'] or identity['HostConfig']['Privileged']:
        raise RuntimeError('Exact owned image or isolation differs')
    call('container-start', [DOCKER, 'start', NAME], 20)
    command = 'exec /opt/flutter/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed --language-version=3.12 ' + ' '.join(EXACT_TWO)
    proof = call('actual-linux-two-file-format-check', [DOCKER, 'exec', NAME, '/bin/bash', '-euo', 'pipefail', '-c', command], 30)
    log = (OUT / 'actual-linux-two-file-format-check.log').read_text()
    match = re.search(r'Formatted (\d+) files \((\d+) changed\)', log)
    if not match or tuple(map(int, match.groups())) != (2, 0):
        raise RuntimeError('Actual two-file Linux format proof count differs')
    after = current_scope()
    write(OUT, 'current-scope-after.json', after)
    if before['dart_sha256'] != after['dart_sha256'] or before['formatter_control_sha256'] != after['formatter_control_sha256']:
        raise RuntimeError('Current frozen formatter inputs changed during partial proof')
    if {p: sha(SDK_RUNTIME / 'flutter' / p) for p in sdk_before} != sdk_before or sha(config) != REUSE['original_generated_package_config_sha256']:
        raise RuntimeError('Reused SDK or language metadata changed during partial proof')
    if any(sha(CHECKOUT / p) != (EXACT_TWO.get(p) or INPUTS[p]) for p in copied):
        raise RuntimeError('Readonly private source changed')
    write(OUT, 'result.json', {
        'at_utc': now(), 'status': 'CURRENT_710_FORMAT_APPLICABILITY_COMPOSITION_PASS',
        'actual_changed_file_format_check': proof, 'actual_linux_checked_file_count': 2,
        'actual_linux_changed_file_count': 0, 'unchanged_applicable_dart_count': 708,
        'current_applicable_dart_count': 710, 'changed_current_sha256': EXACT_TWO,
        'previous_sha256': {p: INPUTS[p] for p in EXACT_TWO},
        'formatter_control_paths_unchanged': CONTROLS, 'language_version': '3.12',
        'preserved_full_make_and_negative_restored_packet_sha256': sha(BASE / 'packet-files.json'),
        'full_make_repeated': False, 'negative_or_restored_make_repeated': False,
        'source_before_after_unchanged': True, 'maintained_source_written': False,
        'whole_bound_seconds': WHOLE_BOUND, 'elapsed_before_cleanup_seconds': time.monotonic() - START,
        'sdk_app_native_cache_changes': False, 'current_closure_decision_owner': 'root',
    })
except Exception as error:
    write(OUT, 'failure.json', {'at_utc': now(), 'type': type(error).__name__, 'error': str(error), 'maintained_source_written': False})
    raise
finally:
    cleanup()

print(json.dumps({'status': 'CURRENT_710_FORMAT_APPLICABILITY_COMPOSITION_PASS', 'checked_changed_files': 2, 'unchanged_applicable_dart_files': 708, 'full_make_repeated': False}))
