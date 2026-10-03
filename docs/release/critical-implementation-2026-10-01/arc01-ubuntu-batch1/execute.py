#!/usr/bin/env python3
"""Execute actual Make gate, malformed refusal and clean reviewed-source check."""
import datetime
import hashlib
import json
import os
import pathlib
import signal
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = pathlib.Path(__file__).resolve().parent
LOG = OUT / 'formatter-attempt1'
LOG.mkdir(exist_ok=False)
PLAN = json.loads((OUT / 'preparation-attempt2/execution-plan.json').read_text())
SOURCE = json.loads((OUT / 'preparation-attempt2/source-inventory.json').read_text())
BUILD = json.loads((OUT / 'ubuntu-build-attempt1/result.json').read_text())
ACQUIRED = json.loads((OUT / 'acquisition-attempt1/result.json').read_text())
assert BUILD['exit_code'] == 0 and not BUILD['timed_out']
assert ACQUIRED['status'] == 'PUBLISHER_CHECKSUM_AND_IMAGE_ID_VERIFIED'
PRIVATE = pathlib.Path(PLAN['private_root'])
CHECKOUT = pathlib.Path(PLAN['checkout'])
OWNER = BUILD['owner_label']
NAME = OWNER + '-format'
TAG = BUILD['tag'].replace(':proof', ':user-proof')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, data):
    (LOG / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def run(name, argv, deadline=90, require=True):
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    stamp = time.monotonic()
    with (LOG / (name + '.log')).open('wb') as stream:
        process = subprocess.Popen(argv, cwd=PRIVATE, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        write(name + '-process.json', {'argv': argv, 'pid': process.pid,
              'started_at_utc': start, 'deadline_seconds': deadline})
        timeout = False
        try:
            code = process.wait(timeout=deadline)
        except subprocess.TimeoutExpired:
            timeout = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=5)
    result = {'argv': argv, 'started_at_utc': start,
              'completed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'deadline_seconds': deadline, 'elapsed_seconds': time.monotonic() - stamp,
              'exit_code': code, 'timed_out': timeout,
              'log_sha256': sha(LOG / (name + '.log'))}
    write(name + '-result.json', result)
    if require:
        assert code == 0 and not timeout, result
    return result


def inside(name, command, deadline=90, require=True):
    return run(name, ['docker', 'exec', NAME, '/bin/bash', '-euo', 'pipefail',
                     '-c', command], deadline, require)


def private_hashes():
    return {key: sha(CHECKOUT / key) for key in SOURCE['copied_input_sha256']}


try:
    assert private_hashes() == SOURCE['copied_input_sha256']
    assert {key: sha(ROOT / key) for key in SOURCE['copied_input_sha256']} == SOURCE['copied_input_sha256']
    user_context = PRIVATE / 'ubuntu-user-context'
    user_context.mkdir(exist_ok=False)
    user_recipe = '\n'.join(['FROM ' + BUILD['tag'],
        'RUN useradd --create-home --uid 501 --user-group arc01', 'USER arc01', ''])
    (user_context / 'Dockerfile').write_text(user_recipe)
    (LOG / 'user-Dockerfile').write_text(user_recipe)
    run('user-image-build', ['docker', 'build', '--no-cache', '--network', 'none',
        '--progress', 'plain', '--tag', TAG, str(user_context)], 60)
    image = json.loads(subprocess.check_output(['docker', 'image', 'inspect', TAG]))[0]
    assert image['Config']['Labels']['com.collect.arc01.owner'] == OWNER
    assert image['Config']['User'] == 'arc01'
    write('user-image-inspect.json', image)
    harness = PRIVATE / 'harness'
    harness.mkdir(exist_ok=False)
    (harness / 'source-inventory.json').write_text(json.dumps(SOURCE, sort_keys=True))
    ruby = '''require 'json'
require 'digest'
require 'open3'
root = '/work/checkout'
Dir.chdir(root)
expected = JSON.parse(File.read('/opt/arc01/source-inventory.json'))
raw, error, status = Open3.capture3('git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.dart')
abort error unless status.success?
paths = raw.split("\\0").uniq.sort.select { |path| File.file?(path) }
paths.reject! { |path| path.start_with?('docs/release/') }
upstream = JSON.parse(File.read('third_party/gotrue/UPSTREAM-SHA256.json'))
paths.reject! do |path|
  path.start_with?('third_party/gotrue/') && upstream[path.delete_prefix('third_party/gotrue/')] == Digest::SHA256.file(path).hexdigest
end
fixture = 'lib/arc01_deliberately_unformatted_fixture.dart'
expected_paths = expected['applicable_formatter_paths']
expected_paths = (expected_paths + [fixture]).sort if File.file?(fixture)
abort 'Maintained inventory parity mismatch' unless paths == expected_paths
hashes = expected['copied_input_sha256'].keys.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
abort 'Private source bytes changed' unless hashes == expected['copied_input_sha256']
puts JSON.generate({inventory_exact: true, applicable_count: paths.size, paths: paths, source_sha256: hashes, fixture_present: File.file?(fixture), alternate_object_store: File.exist?('.git/objects/info/alternates'), root_package_config: File.exist?('.dart_tool/package_config.json')})
'''
    (harness / 'verify_inventory.rb').write_text(ruby)
    (LOG / 'verify_inventory.rb').write_text(ruby)
    run('container-create', ['docker', 'create', '--name', NAME,
        '--label', 'com.collect.arc01.owner=' + OWNER, '--network', 'none',
        '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
        '--memory', '1g', '--cpus', '2', '--pids-limit', '128',
        '--tmpfs', '/tmp:rw,size=64m', '--tmpfs', '/home/arc01:rw,uid=501,gid=501,size=16m',
        '--env', 'DART_SUPPRESS_ANALYTICS=true', '--env', 'CI=true',
        '--mount', 'type=bind,source=' + str(CHECKOUT) + ',target=/work/checkout',
        '--mount', 'type=bind,source=' + str(PRIVATE / 'runtime') + ',target=/opt/dart,readonly',
        '--mount', 'type=bind,source=' + str(harness) + ',target=/opt/arc01,readonly',
        image['Id'], '/bin/sleep', '900'], 30)
    run('container-start', ['docker', 'start', NAME], 30)
    state = json.loads(subprocess.check_output(['docker', 'inspect', NAME]))[0]
    assert state['Config']['Labels']['com.collect.arc01.owner'] == OWNER
    assert state['HostConfig']['NetworkMode'] == 'none' and not state['NetworkSettings']['Ports']
    assert state['Image'] == image['Id']
    assert state['HostConfig']['ReadonlyRootfs'] and state['HostConfig']['CapDrop'] == ['ALL']
    write('container-identity.json', state)
    inside('ubuntu-toolchain-preflight', '''cat /etc/os-release
uname -a
id
command -v git
git --version
command -v make
make --version
command -v ruby
ruby --version
command -v dart
dart --version
sha256sum /opt/dart/dart-sdk/bin/dart
dpkg-query -W git make ruby ruby3.2 ca-certificates
test "$(. /etc/os-release; printf '%s' "$ID")" = ubuntu
test "$(. /etc/os-release; printf '%s' "$VERSION_ID")" = 24.04
test "$(uname -m)" = aarch64
test "$(command -v dart)" = /opt/dart/dart-sdk/bin/dart
dart --version 2>&1 | grep -F '3.12.2'
''')
    inside('clean-private-git', '''git init --initial-branch=arc01-fixture
git config user.name 'Collect ARC01 synthetic formatter proof'
git config user.email 'arc01-fixture@synthetic.invalid'
git config core.autocrlf false
git config commit.gpgsign false
git add --force --all .
git commit --no-verify -m 'Exact reviewed formatter input fixture'
git status --porcelain=v1 --untracked-files=all
git rev-parse HEAD
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test ! -f .git/objects/info/alternates
test ! -e .dart_tool/package_config.json
''')
    inside('inventory-before', 'ruby /opt/arc01/verify_inventory.rb')
    initial = inside('initial-make-format-check', 'make format-check', require=False)
    if initial['exit_code'] != 0 or initial['timed_out']:
        raise RuntimeError('Current reviewed source fails actual Ubuntu Make gate; preserve exact changed files and do not edit frozen source')
    fixture = CHECKOUT / 'lib/arc01_deliberately_unformatted_fixture.dart'
    assert not fixture.exists()
    fixture.write_text("void main(){print('arc01_synthetic_fixture');}\n")
    (LOG / 'malformed-fixture.dart.txt').write_text(fixture.read_text())
    inside('inventory-with-untracked-malformed', 'ruby /opt/arc01/verify_inventory.rb')
    rejected = inside('malformed-make-format-check', 'make format-check', require=False)
    assert rejected['exit_code'] != 0 and not rejected['timed_out']
    assert 'Changed lib/arc01_deliberately_unformatted_fixture.dart' in (LOG / 'malformed-make-format-check.log').read_text()
    fixture.unlink()
    assert private_hashes() == SOURCE['copied_input_sha256']
    inside('inventory-after-fixture-removal', 'ruby /opt/arc01/verify_inventory.rb')
    final = inside('final-make-format-check', 'make format-check')
    inside('final-clean-git', '''git status --porcelain=v1 --untracked-files=all
git rev-parse HEAD
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test ! -f .git/objects/info/alternates
test ! -e .dart_tool/package_config.json
''')
    assert private_hashes() == SOURCE['copied_input_sha256']
    current = {key: sha(ROOT / key) for key in SOURCE['copied_input_sha256']}
    assert current == SOURCE['copied_input_sha256'], 'Root source changed since strict export'
    write('root-final-source-readback.json', current)
    write('result.json', {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'status': 'ACTUAL_UBUNTU_MAKE_GATE_PASS_WITH_MALFORMED_REJECTION',
          'applicable_reviewed_dart_count': len(SOURCE['applicable_formatter_paths']),
          'source_inputs': len(current), 'initial_pass': initial, 'malformed_rejection': rejected,
          'final_pass': final, 'root_and_private_inputs_unchanged': True,
          'container_image_id': image['Id'], 'ubuntu_base_manifest': PLAN['ubuntu_base'],
          'dart_publisher_sha256': PLAN['dart_zip_expected_sha256'],
          'make_or_ci_or_formatter_changed': False,
          'scope': 'Ubuntu24.04 LinuxARM64 formatter gate only; no Flutter, analyzer, build, full CI, hosted or other finding acceptance.'})
    print((LOG / 'result.json').read_text())
except Exception as error:
    write('failure.json', {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'type': type(error).__name__, 'error': str(error), 'source_changed_by_worker': False})
    raise
finally:
    states = subprocess.run(['docker', 'inspect', NAME], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if states.returncode == 0:
        state = json.loads(states.stdout)[0]
        assert state['Config']['Labels']['com.collect.arc01.owner'] == OWNER
        write('container-before-cleanup.json', state)
        subprocess.run(['docker', 'rm', '--force', NAME], check=True, stdout=subprocess.PIPE)
        gone = subprocess.run(['docker', 'inspect', NAME], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        write('container-cleanup.json', {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'name': NAME, 'owner': OWNER, 'removed': gone.returncode != 0,
              'readback_exit': gone.returncode})
        assert gone.returncode != 0
