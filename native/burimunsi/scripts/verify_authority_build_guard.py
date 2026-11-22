#!/usr/bin/env python3
"""Exercise real Gradle host admission in a disposable, offline project copy.

Configured variants use a distinct Cloud application identity. This check
neither builds an APK nor contacts a host or selects a device.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FILES = ('build.gradle.kts', 'settings.gradle.kts', 'gradle.properties',
         'app/build.gradle.kts', 'core/build.gradle.kts')
CLOUD_ONLY = 'BuriMunsi permits the Collect Supabase Cloud project only'
CASES = (
    ('offline', None, ()),
    ('old-shared-origin', CLOUD_ONLY, ('-PcollectSupabaseOrigin=https://supabase.collect.ikanisa.com',)),
    ('old-admin-origin', CLOUD_ONLY, ('-PcollectAdminOrigin=https://platform-admin.collect.ikanisa.com',)),
    ('cloud-shared', None, ('-PcollectSupabaseOrigin=https://rrlduytparvsjfmegalh.supabase.co',)),
    ('cloud-api-case-port', CLOUD_ONLY, ('-PburimunsiApiOrigin=https://RRlduytparvsjfmegalh.supabase.co:443',)),
    ('cloud-api-trailing-dot', CLOUD_ONLY, ('-PburimunsiApiOrigin=https://rrlduytparvsjfmegalh.supabase.co.',)),
    ('other-api', CLOUD_ONLY, ('-PburimunsiApiOrigin=https://platform-admin.collect.ikanisa.com',)),
    ('other-gateway', CLOUD_ONLY, ('-PcollectGatewayOrigin=https://platform-admin.collect.ikanisa.com/functions/v1/collect-api',)),
    ('other-cloud-project', CLOUD_ONLY, ('-PcollectSupabaseOrigin=https://different-project.supabase.co',)),
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, *, env, cwd, timeout):
    proc = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            start_new_session=True)
    try:
        output, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.communicate()
        raise RuntimeError('Gradle check timed out; cleanup after a forced kill is not guaranteed')
    return proc.returncode, output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path, help='Pinned Gradle archive')
    parser.add_argument('--gradle-cache', required=True, type=Path, help='Verified Gradle installation directory')
    parser.add_argument('--dependency-cache', required=True, type=Path, help='Read-only Gradle dependency cache')
    parser.add_argument('--android-sdk', required=True, type=Path)
    parser.add_argument('--java-home', required=True, type=Path)
    args = parser.parse_args()
    for name in FILES:
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError('Expected current Gradle source is unavailable: ' + name)
    original = {name: digest(ROOT / name) for name in FILES}
    checked = subprocess.run([sys.executable, str(ROOT / 'scripts/bootstrap_gradle.py'),
                              '--archive', str(args.archive), '--cache', str(args.gradle_cache)],
                             stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120, check=False)
    if checked.returncode:
        raise RuntimeError('Pinned Gradle verification failed: ' + checked.stderr[-1000:])
    launcher = json.loads(checked.stdout)['launcher']
    with tempfile.TemporaryDirectory(prefix='collect-authority-gradle-') as tmp:
        task = Path(tmp); project = task / 'project'; project.mkdir()
        for name in FILES:
            target = project / name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'JAVA_HOME': str(args.java_home),
               'ANDROID_HOME': str(args.android_sdk), 'ANDROID_SDK_ROOT': str(args.android_sdk),
               'ANDROID_USER_HOME': str(task / 'android-home'), 'GRADLE_USER_HOME': str(task / 'gradle-home'),
               'GRADLE_RO_DEP_CACHE': str(args.dependency_cache), 'TMPDIR': str(task), 'LC_ALL': 'C'}
        for label, expected_error, properties in CASES:
            command = [launcher, '-p', str(project), '--offline', '--no-daemon', '--console=plain',
                       '-Duser.home=' + str(task / 'home'), 'help', *properties]
            status, output = run(command, env=env, cwd=project, timeout=120)
            passed = status == 0 if expected_error is None else status != 0 and expected_error in output
            if not passed:
                raise RuntimeError(label + ' did not produce the expected result:\n' + output[-2000:])
            print(label + ': pass', flush=True)
    if any(digest(ROOT / name) != value for name, value in original.items()):
        raise RuntimeError('Gradle input changed during the qualification')
    print('Nine offline Gradle authority-admission cases passed; no APK or hosted request was made.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
