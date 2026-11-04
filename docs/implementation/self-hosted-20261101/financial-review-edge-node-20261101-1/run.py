from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = Path('/Volumes/PRO-G40/Application Data/Codex/Codex-Home/worktrees/collect-consolidation-20261101/COLLECT')
RUN = Path(__file__).resolve().parent
SNAPSHOT = RUN / 'snapshot'
NODE = Path('/Volumes/PRO-G40/Development/Node/bin/node')
SANDBOX = Path('/usr/bin/sandbox-exec')
HEAD = '14f32d43961cd566e8834dae841ba67e475b21f5'
FLOOR = 4563402752
OUTPUT_CAP = 4194304
RESERVE = 16777216
SERVER = 'supabase/functions/_shared/domain/contribution_commands.js'
SOURCE_ROOTS = [
    'supabase/functions', 'supabase/retention-inventory.json',
    'scripts/supabase/run_edge_node_tests.mjs',
    # Context files identify the separately qualified native review case; this
    # Node run does not execute that case or claim a PostgreSQL result.
    'scripts/supabase/testing/self-hosted-contribution-review-runtime.ts',
    'scripts/supabase/testing/self-hosted-current-schema.mjs',
    'scripts/supabase/testing/current-self-hosted-native.mjs',
    'scripts/supabase/testing/current-self-hosted-native.test.mjs',
    '.github/workflows/supabase.yml', 'scripts/tests/test_collect_ci_policy.py',
]


def sha(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('regular input required: ' + str(path))
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            digest.update(block)
    return digest.hexdigest()


def save(path, data):
    with path.open('x', encoding='utf8') as stream:
        json.dump(data, stream, indent=2, sort_keys=True)
        stream.write('\n')


def capacities():
    result = {}
    for volume in ['/System/Volumes/Data', '/Volumes/PRO-G40']:
        stats = os.statvfs(volume)
        result[volume] = stats.f_bavail * stats.f_frsize
        if result[volume] < FLOOR + RESERVE:
            raise RuntimeError('capacity reserve not met: ' + volume)
    return result


def source_files():
    files = []
    for role in SOURCE_ROOTS:
        root = ROOT / role
        if root.is_symlink() or not root.exists() or root.resolve() != root:
            raise RuntimeError('physical source required: ' + str(root))
        paths = [root] if root.is_file() else root.rglob('*')
        for path in paths:
            if path.is_symlink():
                raise RuntimeError('source symlink refused: ' + str(path))
            if not path.is_file() or path.name.startswith('._') or path.name == '.DS_Store':
                continue
            if path.stat().st_size > 16777216 or path.name.startswith(('.env', '.dev.vars')) or path.suffix in {'.pem', '.key'}:
                raise RuntimeError('unreviewed source input refused: ' + str(path))
            files.append(path.relative_to(ROOT).as_posix())
    if len(files) != len(set(files)):
        raise RuntimeError('duplicate source role')
    return sorted(files)


def sources(root, roles):
    return {role: sha(root / role) for role in roles}


def tools():
    return {str(path): sha(path) for path in [NODE, SANDBOX, Path(sys.executable).resolve(), RUN / 'run.py', RUN / 'deny-network.sb']}


def group_absent(pid):
    try:
        os.killpg(pid, 0)
        return False
    except ProcessLookupError:
        return True
    except PermissionError:
        return None


def run_child(argv, stdout, stderr, env, timeout, poll_capacity=True):
    started = time.monotonic()
    reason = None
    signals = []
    with stdout.open('xb') as out, stderr.open('xb') as err:
        process = subprocess.Popen(argv, cwd=SNAPSHOT, env=env, stdout=out, stderr=err, start_new_session=True)
        try:
            while process.poll() is None:
                if poll_capacity:
                    capacities()
                if time.monotonic() - started > timeout:
                    raise TimeoutError('deadline')
                if os.fstat(out.fileno()).st_size > OUTPUT_CAP or os.fstat(err.fileno()).st_size > OUTPUT_CAP:
                    raise RuntimeError('output cap')
                time.sleep(.15)
        except BaseException as error:
            reason = type(error).__name__ + ': ' + str(error)
            if group_absent(process.pid) is False:
                os.killpg(process.pid, signal.SIGTERM)
                signals.append('TERM')
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                if group_absent(process.pid) is False:
                    os.killpg(process.pid, signal.SIGKILL)
                    signals.append('KILL')
                process.wait(timeout=3)
        process.wait(timeout=3)
    absent = group_absent(process.pid)
    # A surviving task-owned group invalidates the run and is explicitly stopped.
    if absent is False:
        os.killpg(process.pid, signal.SIGTERM)
        signals.append('TERM_LINGERING_GROUP')
        time.sleep(.3)
        if group_absent(process.pid) is False:
            os.killpg(process.pid, signal.SIGKILL)
            signals.append('KILL_LINGERING_GROUP')
        reason = reason or 'lingering process group'
        absent = group_absent(process.pid)
    return {'exit_code': process.returncode, 'reason': reason, 'signals_sent': signals,
            'process_group_absent': absent, 'waited': True,
            'elapsed_seconds': round(time.monotonic() - started, 3),
            'stdout_sha256': sha(stdout), 'stderr_sha256': sha(stderr)}


def prepare(expected_server):
    if not re.fullmatch('[0-9a-f]{64}', expected_server):
        raise RuntimeError('frozen server SHA-256 required')
    if SNAPSHOT.exists() or (RUN / 'INPUTS.json').exists():
        raise RuntimeError('fresh evidence directory required')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != HEAD:
        raise RuntimeError('canonical HEAD changed')
    free = capacities()
    roles = source_files()
    before = sources(ROOT, roles)
    if before[SERVER] != expected_server:
        raise RuntimeError('owner-frozen financial review server mismatch')
    SNAPSHOT.mkdir(mode=0o700)
    for role in roles:
        dest = SNAPSHOT / role
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / role, dest)
        dest.chmod(0o444)
    for directory, dirs, _ in os.walk(SNAPSHOT, topdown=False):
        for name in dirs:
            (Path(directory) / name).chmod(0o555)
    SNAPSHOT.chmod(0o555)
    if roles != source_files() or sources(ROOT, roles) != before or sources(SNAPSHOT, roles) != before:
        raise RuntimeError('source changed during snapshot')
    for name in ['tmp', 'home']:
        (RUN / name).mkdir(mode=0o700)
    pinned_tools = tools()
    version = subprocess.check_output([str(NODE), '--version'], text=True).strip()
    if not re.fullmatch(r'v24\.[0-9]+\.[0-9]+', version):
        raise RuntimeError('Node 24 required')
    tests = [role for role in roles if role.startswith('supabase/functions/_shared/tests/') and role.endswith('.test.mjs')]
    if not tests:
        raise RuntimeError('Node test files required')
    data = {'format': 'collect.edge-node.financial-review.inputs.v1', 'head': HEAD,
            'prepared_utc': datetime.now(timezone.utc).isoformat(), 'canonical_root': str(ROOT),
            'snapshot_root': str(SNAPSHOT), 'frozen_server_sha256': expected_server,
            'source_files': before, 'tools': pinned_tools, 'node_version': version,
            'test_files': tests, 'capacity_free_bytes': free, 'floor_bytes': FLOOR,
            'reserve_bytes': RESERVE, 'network_policy': 'deny network*',
            'node_home': str(RUN / 'home'), 'tmpdir': str(RUN / 'tmp'),
            'node_compile_cache': 'unset', 'deno_cache': 'unused',
            'os': platform.platform(), 'machine': platform.machine(),
            'hosted_acceptance': False, 'production_acceptance': False}
    save(RUN / 'INPUTS.json', data)
    print(json.dumps({'status': 'PREPARED', 'source_count': len(roles), 'test_files': len(tests),
                      'server_sha256': expected_server, 'node_version': version,
                      'capacity_free_bytes': free, 'snapshot': str(SNAPSHOT)}))


def run():
    if (RUN / 'RESULT.json').exists() or (RUN / 'suite.stdout').exists():
        raise RuntimeError('fresh run required')
    data = json.loads((RUN / 'INPUTS.json').read_text())
    roles = list(data['source_files'])
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != HEAD:
        raise RuntimeError('canonical HEAD changed')
    if source_files() != roles or sources(ROOT, roles) != data['source_files'] or sources(SNAPSHOT, roles) != data['source_files'] or tools() != data['tools']:
        raise RuntimeError('prepared inputs changed')
    capacities()
    env = {'HOME': str(RUN / 'home'), 'TMPDIR': str(RUN / 'tmp'),
           'XDG_CACHE_HOME': str(RUN / 'home' / '.cache'), 'PATH': '/usr/bin:/bin', 'NO_COLOR': '1'}
    # A loopback connection is deliberately denied by the sandbox before any
    # listener is reached. ECONNREFUSED would not prove a network policy.
    probe = "const s=require('node:net').connect(9,'127.0.0.1');s.on('error',e=>{console.log(e.code);process.exit(['EPERM','EACCES'].includes(e.code)?0:1)});setTimeout(()=>process.exit(2),2000).unref();"
    probe_result = run_child([str(SANDBOX), '-f', str(RUN / 'deny-network.sb'), str(NODE), '-e', probe], RUN / 'network-probe.stdout', RUN / 'network-probe.stderr', env, 10)
    if probe_result['exit_code'] != 0 or probe_result['reason'] or not probe_result['process_group_absent']:
        save(RUN / 'RESULT.json', {'status': 'FAIL', 'network_probe': probe_result, 'suite_started': False, 'production_acceptance': False})
        raise RuntimeError('network denial probe failed')
    command = [str(SANDBOX), '-f', str(RUN / 'deny-network.sb'), str(NODE), 'scripts/supabase/run_edge_node_tests.mjs']
    result = run_child(command, RUN / 'suite.stdout', RUN / 'suite.stderr', env, 120)
    try:
        parity = source_files() == roles and sources(ROOT, roles) == data['source_files'] and sources(SNAPSHOT, roles) == data['source_files'] and tools() == data['tools']
    except Exception:
        parity = False
    output = (RUN / 'suite.stdout').read_text(errors='replace')
    counts = {}
    for key in ['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo']:
        found = re.findall(r'(?m)^\S+ ' + key + r' (\d+)\s*$', output)
        counts[key] = int(found[-1]) if found else None
    passed = result['exit_code'] == 0 and result['reason'] is None and result['process_group_absent'] is True and parity and counts['tests'] == counts['pass'] and counts['tests'] not in (None, 0) and all(counts[k] == 0 for k in ['fail', 'cancelled', 'skipped', 'todo'])
    result.update({'format': 'collect.edge-node.financial-review.result.v1', 'passed': passed,
                   'network_probe': probe_result, 'network_denied_by_os_sandbox': True,
                   'inputs_unchanged': parity, 'test_files': len(data['test_files']), 'counts': counts,
                   'source_snapshot': str(SNAPSHOT), 'hosted_acceptance': False,
                   'production_acceptance': False})
    save(RUN / 'RESULT.json', result)
    print(json.dumps(result))
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['prepare', 'run'])
    parser.add_argument('--expected-server')
    args = parser.parse_args()
    try:
        if args.phase == 'prepare':
            prepare(args.expected_server or '')
        else:
            if args.expected_server:
                raise RuntimeError('unexpected argument')
            run()
    except BaseException as error:
        failure = RUN / ('PREPARE-FAILURE.json' if args.phase == 'prepare' else 'RUN-FAILURE.json')
        if not failure.exists():
            save(failure, {'phase': args.phase, 'error': type(error).__name__,
                           'message': str(error), 'production_acceptance': False})
        raise
