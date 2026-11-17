#!/usr/bin/env python3
"""Serialize supported retained mutations without modifying sealed backend source.

Historical direct executors must be retired from the supported operation path
by the controlled bootstrap. Read-only inspection does not use this wrapper.
"""
import argparse
import importlib.util
import json
import os
import plistlib
import signal
import stat
import subprocess
import sys
from pathlib import Path

_coord_path = Path(__file__).resolve().parent/'operation_lock.py'
_coord_stat = _coord_path.lstat()
if (_coord_path.resolve()!=_coord_path or not stat.S_ISREG(_coord_stat.st_mode)
    or _coord_stat.st_uid!=os.getuid() or _coord_stat.st_nlink!=1
    or stat.S_IMODE(_coord_stat.st_mode)!=0o600):
    raise RuntimeError('operation_coordinator_identity')
_coord_spec = importlib.util.spec_from_file_location('collect_host_operation_lock', _coord_path)
if _coord_spec is None or _coord_spec.loader is None:
    raise RuntimeError('operation_coordinator_unavailable')
operation_lock = importlib.util.module_from_spec(_coord_spec)
_coord_spec.loader.exec_module(operation_lock)

BASE = Path('/Volumes/SupaRuntime/collect-production/releases/testing-candidate-033-member-only')
RELEASES = Path('/Volumes/SupaRuntime/collect-production/releases')
PRODUCTION = RELEASES/'production-20261113-001'
SOURCE_SHA256 = 'f691215e0df1ce7400d0d83115132744fb1f308e58cc40d75d532ed740f890ee'
PROFILE_SHA256 = '18f9b92d996651911d57693b7ba7e3c1c782c85cf17142983f2061ea592de5c1'
CLI_CONFIG = Path('/Users/jeanbosco/Documents/Supabase/local/development/projects/app/supabase/config.toml')
DOCKER_HOST = 'unix:///Volumes/SupaRuntime/.colima/supabase-local/docker.sock'
TIMEOUT = 180
MODULE_BOOTSTRAP = 'import sys,runpy; source=sys.argv.pop(1); module=sys.argv.pop(1); sys.path.insert(0,source); runpy.run_module(module,run_name="__main__")'
START_PLIST = Path('/Users/jeanbosco/Library/LaunchAgents/com.ikanisa.collect.runtime-startup.plist')
START_SCRIPT = Path('/Volumes/PRO-G40/Projects/COLLECT-Production/runtime-startup-lock-v1/runtime_startup.py')


class OutcomeUnconfirmed(RuntimeError):
    pass


def read_private(path):
    path=Path(path);st=path.lstat()
    if path.resolve()!=path or not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or stat.S_IMODE(st.st_mode)!=0o600:
        raise ValueError('protected_control_file_required')
    return path.read_bytes()


def checked_adoption():
    """Refuse retained mutations if rollback restored the lock-unaware agent."""
    value=plistlib.loads(read_private(START_PLIST));args=value.get('ProgramArguments',[])
    if not(value.get('Label')=='com.ikanisa.collect.runtime-startup' and value.get('RunAtLoad') is True
           and isinstance(args,list) and len(args)>=2 and args.count(str(START_SCRIPT))==1 and args[-1]=='--run'):
        raise ValueError('lock_aware_startup_not_adopted')
    settings=json.loads(read_private(Path(args[-2])))
    if not(settings.get('enabled') is True and settings.get('release_root') in (str(BASE),str(PRODUCTION))
           and settings.get('release_source_sha256')==SOURCE_SHA256):
        raise ValueError('lock_aware_startup_binding_changed')


def checked_release(release):
    release = Path(release)
    if (not release.is_absolute() or release not in (BASE,PRODUCTION)
        or release.resolve(strict=True) != release or release.parent != RELEASES or not release.is_dir()):
        raise ValueError('physical_release_required')
    # Import from the sealed production source, then require the
    # target's own source/configuration seal to match the reviewed same source.
    sys.path.insert(0, str(PRODUCTION/'source'))
    from scripts.self_hosted.release_operator import Operator
    operator = Operator(release)
    if operator.meta['source_sha256'] != SOURCE_SHA256 or operator.meta['profile_sha256'] != PROFILE_SHA256:
        raise ValueError('approved_source_required')
    return release


def child_command(action, release):
    base = [sys.executable, '-I', '-B', '-c', MODULE_BOOTSTRAP, str(PRODUCTION/'source')]
    if action == 'retained_edge':
        return base + ['scripts.self_hosted.retained_collect',
                '--release', str(release), '--cli-config', str(CLI_CONFIG),
                '--docker-host', DOCKER_HOST, '--execute']
    raise ValueError('unsupported_retained_mutation')


def invoke(action, release, *, root=None, process=None):
    with operation_lock.coordinated('operator_'+action, str(release), root=root) as permit:
        checked_adoption()
        release = checked_release(release)
        command = child_command(action, release)
        permit.arm()
        spawn = process or subprocess.Popen
        child = spawn(command, cwd=PRODUCTION/'source', stdin=subprocess.DEVNULL,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                      start_new_session=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE':'1', 'PYTHONPATH':str(PRODUCTION/'source')})
        try:
            result = child.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired as exc:
            # The daemon-side action may have succeeded. Keep the durable
            # marker and require read-only reconciliation; never replay.
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait(timeout=5)
            raise OutcomeUnconfirmed('operator_timeout') from exc
        if result:
            raise OutcomeUnconfirmed('operator_outcome_unconfirmed')
        return {'complete':True, 'action':action, 'automatic_retry':False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('retained_edge',))
    parser.add_argument('--release', required=True, type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(invoke(args.action, args.release), sort_keys=True))
    except Exception as error:
        print(json.dumps({'complete':False,'error_type':type(error).__name__,
                          'automatic_retry':False,'reconcile_before_mutation':True}), file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
