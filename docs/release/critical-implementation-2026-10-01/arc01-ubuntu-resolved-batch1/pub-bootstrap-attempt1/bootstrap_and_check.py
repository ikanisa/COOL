#!/usr/bin/env python3
"""Actual canonical Pub and unchanged Make on a dated exclusive candidate."""
import difflib
import json
from pathlib import Path
import re
import subprocess

from run_owned import now, run, sha, write

OUT = Path(__file__).resolve().parent
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIVATE = Path(BOUNDARY['private_root'])
CHECKOUT = PRIVATE / 'checkout'
OWNER = PRIVATE.name
SOURCE = json.loads((OUT / 'source-export-attempt1/source-inventory.json').read_text())
INPUTS = SOURCE['copied_input_sha256']
EXPECTED = SOURCE['applicable_formatter_paths']
CORRECTIONS = BOUNDARY['private_candidate_correction_paths']
PUB = OUT / 'pub-bootstrap-attempt1'
FORMAT = OUT / 'formatter-candidate-attempt1'
PUB.mkdir(exist_ok=False)
FORMAT.mkdir(exist_ok=False)
CACHE = PRIVATE / 'pub-cache'
CACHE.mkdir(exist_ok=False)
HARNESS = PRIVATE / 'harness'
HARNESS.mkdir(exist_ok=False)
IMAGE = json.loads((OUT / 'ubuntu-build-attempt2/result.json').read_text())['image_id']
SDK = json.loads((OUT / 'sdk-extraction-attempt1/result.json').read_text())
INVENTORY_RUBY = '''require 'json'
require 'digest'
root = Dir.pwd
upstream = JSON.parse(File.read('third_party/gotrue/UPSTREAM-SHA256.json'))
raw = IO.popen(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.dart'], &:read)
files = raw.split("\\0").uniq.sort.select { |p| File.file?(p) }
files.reject! { |p| p.start_with?('docs/release/') }
files.reject! do |p|
  p.start_with?('third_party/gotrue/') && upstream[p.delete_prefix('third_party/gotrue/')] == Digest::SHA256.file(p).hexdigest
end
puts JSON.generate({count: files.length, paths: files})
'''
(HARNESS / 'inventory.rb').write_text(INVENTORY_RUBY)
(FORMAT / 'inventory.rb').write_text(INVENTORY_RUBY)


def hashes():
    return {path: sha(CHECKOUT / path) if (CHECKOUT / path).is_file() else None for path in INPUTS}


def create(directory, name, network):
    argv = ['docker', 'create', '--name', name, '--label', 'com.collect.arc01.owner=' + OWNER,
            '--platform', 'linux/amd64', '--network', network, '--read-only',
            '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--memory', '4g',
            '--cpus', '3', '--pids-limit', '256', '--env', 'CI=true',
            '--env', 'DART_SUPPRESS_ANALYTICS=true', '--env', 'FLUTTER_SUPPRESS_ANALYTICS=true',
            '--env', 'PUB_CACHE=/work/pub-cache', '--tmpfs', '/home/arc01:rw,uid=501,gid=1001,size=64m',
            '--tmpfs', '/tmp:rw,size=256m', '--mount',
            'type=bind,source=' + str(CHECKOUT) + ',target=/work/checkout', '--mount',
            'type=bind,source=' + str(PRIVATE / 'runtime') + ',target=/opt/flutter', '--mount',
            'type=bind,source=' + str(CACHE) + ',target=/work/pub-cache', '--mount',
            'type=bind,source=' + str(HARNESS) + ',target=/opt/arc01,readonly', IMAGE, '/bin/sleep', '1800']
    run(directory, 'container-create', argv, 30)
    raw = subprocess.check_output(['docker', 'inspect', name], timeout=15)
    (directory / 'container-identity.json').write_bytes(raw)
    identity = json.loads(raw)[0]
    if (identity['Image'] != IMAGE or identity['Config']['Labels'].get('com.collect.arc01.owner') != OWNER
            or identity['HostConfig']['NetworkMode'] != network
            or identity['HostConfig']['PortBindings'] or identity['HostConfig']['Privileged']):
        raise RuntimeError('Owned container exact identity/network/port mismatch')
    run(directory, 'container-start', ['docker', 'start', name], 20)


def execute(directory, phase, name, script, deadline, require_success=True):
    return run(directory, phase, ['docker', 'exec', name, '/bin/bash', '-euo', 'pipefail',
               '-c', script], deadline, require_success)


def cleanup(directory, name):
    observed = subprocess.run(['docker', 'inspect', name], capture_output=True, timeout=15)
    if observed.returncode == 0:
        identity = json.loads(observed.stdout)[0]
        (directory / 'container-before-cleanup.json').write_bytes(observed.stdout)
        if identity['Image'] != IMAGE or identity['Config']['Labels'].get('com.collect.arc01.owner') != OWNER:
            raise RuntimeError('Refusing cleanup of non-owned container')
        stopped = subprocess.run(['docker', 'stop', '--time', '5', name], capture_output=True, timeout=20)
        removed = subprocess.run(['docker', 'rm', name], capture_output=True, timeout=20)
        if removed.returncode != 0:
            raise RuntimeError('Owned container removal failed')
    else:
        stopped = removed = None
    final = subprocess.run(['docker', 'inspect', name], capture_output=True, text=True, timeout=15)
    absent = final.returncode == 1 and 'No such object' in final.stderr
    write(directory, 'container-cleanup.json', {'at_utc': now(), 'name': name, 'owner': OWNER,
          'stop_exit': stopped.returncode if stopped else None,
          'remove_exit': removed.returncode if removed else None,
          'readback_exit': final.returncode, 'removed': absent})
    if not absent:
        raise RuntimeError('Owned container absence not proved')


def inventory(name, phase, extra=None):
    execute(FORMAT, phase, name, 'ruby /opt/arc01/inventory.rb', 30)
    actual = json.loads((FORMAT / (phase + '.log')).read_text())
    expected = sorted(EXPECTED + ([extra] if extra else []))
    if actual['paths'] != expected or actual['count'] != len(expected):
        raise RuntimeError('Actual full maintained Git inventory differs from frozen candidate')
    return actual


def gate(name, phase, changed, expected_exit):
    result = execute(FORMAT, phase, name, 'make format-check', 120, False)
    output = (FORMAT / (phase + '.log')).read_text()
    observed_changes = sorted(line.removeprefix('Changed ') for line in output.splitlines()
                              if line.startswith('Changed '))
    count = len(EXPECTED) + (1 if phase == 'malformed-make-format-check' else 0)
    match = re.search(r'Formatted (\d+) files \((\d+) changed\)', output)
    if result['exit_code'] != expected_exit or observed_changes != sorted(changed) or not match:
        raise RuntimeError('Actual Make exit/change evidence differs: ' + phase)
    if int(match.group(1)) != count or int(match.group(2)) != len(changed):
        raise RuntimeError('Actual Make complete-source counts differ: ' + phase)
    return {**result, 'formatted_files': count, 'would_change_paths': observed_changes}


pub_name = OWNER + '-pub'
format_name = OWNER + '-format'
fixture = 'tool/qa/arc01_malformed_formatter_fixture.dart'
try:
    if hashes() != INPUTS or len(list(CACHE.iterdir())):
        raise RuntimeError('Source export changed or Pub cache not fresh')
    create(PUB, pub_name, 'bridge')
    try:
        preflight = '''cat /etc/os-release
uname -m
id
command -v git
git --version
command -v make
make --version
command -v ruby
ruby --version
command -v flutter
command -v dart
git -C /opt/flutter/flutter rev-parse HEAD
flutter --version --machine
dart --version
sha256sum /opt/flutter/flutter/bin/cache/dart-sdk/bin/dart
dpkg-query -W ca-certificates curl git make ruby ruby3.2 unzip xz-utils zip libglu1-mesa
'''
        execute(PUB, 'actual-linux-toolchain-preflight', pub_name, preflight, 120)
        log = (PUB / 'actual-linux-toolchain-preflight.log').read_text()
        if 'VERSION_ID="24.04"' not in log or '\nx86_64\n' not in log or 'linux_x64' not in log:
            raise RuntimeError('Actual official Ubuntu amd64/Dart executable preflight not proved')
        if '"frameworkVersion": "3.44.4"' not in log or '"dartSdkVersion": "3.12.2"' not in log:
            raise RuntimeError('Actual pinned Flutter/Dart version mismatch')
        if SDK['sdk_file_sha256']['bin/cache/dart-sdk/bin/dart'] != sha(PRIVATE / 'runtime/flutter/bin/cache/dart-sdk/bin/dart'):
            raise RuntimeError('Actual Dart binary changed after authenticated extraction')
        execute(PUB, 'clean-independent-git', pub_name, '''test ! -d .git
git init
git config user.name 'Collect ARC01 private fixture'
git config user.email 'arc01-private-fixture@invalid.example'
git add --all --force .
git commit -m 'Exact dated ARC01 formatter fixture'
test -z "$(git status --porcelain)"
test ! -e .git/objects/info/alternates
git rev-parse HEAD
''', 90)
        lock_before = sha(CHECKOUT / 'pubspec.lock')
        result = execute(PUB, 'canonical-enforced-lock-pub-get', pub_name,
                         'flutter pub get --enforce-lockfile', 420)
        if sha(CHECKOUT / 'pubspec.lock') != lock_before or hashes() != INPUTS:
            raise RuntimeError('Canonical Pub modified source or enforced lockfile')
        config = CHECKOUT / '.dart_tool/package_config.json'
        package = json.loads(config.read_text())
        selected = [row for row in package['packages'] if row['name'] in
                    ['collect_app', 'firebase_messaging', 'gotrue', 'file_saver', 'flutter_lints']]
        write(PUB, 'result.json', {'at_utc': now(), 'status': 'ACTUAL_CANONICAL_PUB_BOOTSTRAP_PASS',
              'process': result, 'lockfile_before_sha256': lock_before,
              'lockfile_after_sha256': sha(CHECKOUT / 'pubspec.lock'),
              'package_config_sha256': sha(config), 'selected_generated_packages': selected,
              'pub_cache_initially_empty': True, 'root_source_written': False,
              'private_source_byte_changes': 0})
    finally:
        cleanup(PUB, pub_name)
    create(FORMAT, format_name, 'none')
    try:
        inventory(format_name, 'original-inventory')
        original = gate(format_name, 'original-make-format-check', CORRECTIONS, 2)
        before = hashes()
        prior_text = {path: (CHECKOUT / path).read_text() for path in CORRECTIONS}
        execute(FORMAT, 'private-three-file-formatter', format_name,
                'dart format ' + ' '.join(CORRECTIONS), 90)
        after = hashes()
        changed = sorted(path for path in INPUTS if before[path] != after[path])
        if changed != sorted(CORRECTIONS):
            raise RuntimeError('Private proposed correction exceeds exact three authorized files')
        diffs = ''.join(''.join(difflib.unified_diff(prior_text[path].splitlines(keepends=True),
                         (CHECKOUT / path).read_text().splitlines(keepends=True),
                         fromfile='before/' + path, tofile='candidate/' + path)) for path in CORRECTIONS)
        (FORMAT / 'private-three-file-candidate.diff').write_text(diffs)
        write(FORMAT, 'private-candidate-source.json', {'at_utc': now(),
              'before_sha256': before, 'candidate_sha256': after, 'changed_paths': changed,
              'root_source_written': False, 'current_root_acceptance': False})
        inventory(format_name, 'candidate-inventory')
        candidate = gate(format_name, 'candidate-make-format-check', [], 0)
        if (CHECKOUT / fixture).exists():
            raise RuntimeError('Synthetic fixture path already exists')
        (CHECKOUT / fixture).write_text("void main(){print('arc01-synthetic-formatter-fixture');}\n")
        inventory(format_name, 'malformed-inventory', fixture)
        malformed = gate(format_name, 'malformed-make-format-check', [fixture], 2)
        (CHECKOUT / fixture).unlink()
        inventory(format_name, 'restored-inventory')
        restored = gate(format_name, 'restored-make-format-check', [], 0)
        if hashes() != after:
            raise RuntimeError('Candidate source changed across actual negative/restored Make proof')
        write(FORMAT, 'result.json', {'at_utc': now(), 'status': 'DATED_PRIVATE_CANDIDATE_MAKE_PASS',
              'original_source_actual_failure': original, 'private_candidate_actual_pass': candidate,
              'malformed_fixture_actual_rejection': malformed, 'restored_candidate_actual_pass': restored,
              'full_applicable_dart_count': len(EXPECTED), 'only_private_correction_paths': changed,
              'fixture_removed': not (CHECKOUT / fixture).exists(), 'root_source_written': False,
              'current_root_acceptance': False, 'candidate_sha256': after})
    finally:
        if (CHECKOUT / fixture).exists():
            (CHECKOUT / fixture).unlink()
        cleanup(FORMAT, format_name)
    print(json.dumps({'status': 'DATED_PRIVATE_CANDIDATE_MAKE_PASS',
                      'applicable_count': len(EXPECTED), 'current_root_acceptance': False}, indent=2))
except Exception as error:
    write(OUT, 'execution-failure.json', {'at_utc': now(), 'type': type(error).__name__,
          'error': str(error), 'root_source_written': False, 'current_root_acceptance': False})
    raise
