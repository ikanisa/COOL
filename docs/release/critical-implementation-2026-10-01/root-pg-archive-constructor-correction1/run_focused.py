"""Bounded synthetic focused cohort; never runs old SQL/Docker/provider suites."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import selectors
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
attempt = HERE / sys.argv[1]
attempt.mkdir(exist_ok=False)
test = HERE / 'candidate/scripts/tests/test_pg_archive_admission.py'
argv = [sys.executable, '-I', '-B', str(test), '-v', *sys.argv[2:]]
clean = {'PATH': os.defpath, 'LC_ALL': 'en_US.UTF-8', 'LANG': 'en_US.UTF-8', 'PYTHONDONTWRITEBYTECODE': '1', 'PYTHONUTF8': '1'}
clean['COLLECT_ARCHIVE_TEST_TRACE_DIR'] = str(attempt / 'safe-traces')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
inputs = json.loads((HERE / 'original-inputs.json').read_text())
before = {row['path']: sha(ROOT / row['path']) for row in inputs['files']}
assert all(before[row['path']] == row['sha256'] for row in inputs['files'])
proposed = {str(path.relative_to(HERE)): sha(path) for path in sorted((HERE / 'candidate').rglob('*')) if path.is_file()}
process = subprocess.Popen(argv, cwd=ROOT, env=clean, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
started = time.monotonic()
result = {'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'argv': argv, 'env': clean,
          'cwd': str(ROOT), 'pid': process.pid, 'pgid': process.pid, 'outer_seconds': 90, 'stream_limit_bytes': 4 * 1024 * 1024,
          'maintained_inputs_before': before, 'proposed_inputs_before': proposed}
streams = {'stdout': bytearray(), 'stderr': bytearray()}
failure = None
try:
    with selectors.DefaultSelector() as selector:
        for stream, name in [(process.stdout, 'stdout'), (process.stderr, 'stderr')]:
            selector.register(stream, selectors.EVENT_READ, name)
        while selector.get_map():
            left = 90 - (time.monotonic() - started)
            if left <= 0:
                raise TimeoutError('OUTER_TIMEOUT')
            for key, _ in selector.select(min(0.2, left)):
                chunk = os.read(key.fileobj.fileno(), 16384)
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    streams[key.data].extend(chunk)
                    if len(streams[key.data]) > 4 * 1024 * 1024:
                        raise RuntimeError('OUTER_STREAM_LIMIT')
    process.wait(timeout=max(0.01, 90 - (time.monotonic() - started)))
except BaseException as error:
    failure = type(error).__name__ + ':' + str(error)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=5)
finally:
    process.stdout.close(); process.stderr.close()
result.update(exit_code=process.returncode, elapsed_seconds=time.monotonic() - started, failure=failure)
for name, data in streams.items():
    (attempt / name).write_bytes(data)
    result[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
observed = subprocess.run(['/bin/ps', '-axo', 'pgid='], stdin=subprocess.DEVNULL, capture_output=True, timeout=5, env=clean)
result['owned_outer_process_group_absent'] = str(process.pid) not in observed.stdout.decode().split()
result['maintained_inputs_after'] = {name: sha(ROOT / name) for name in before}
result['proposed_inputs_after'] = {name: sha(HERE / name) for name in proposed}
result['maintained_inputs_unchanged'] = result['maintained_inputs_after'] == before
result['proposed_inputs_unchanged'] = result['proposed_inputs_after'] == proposed
result['status'] = 'pass' if process.returncode == 0 and failure is None and result['owned_outer_process_group_absent'] and result['maintained_inputs_unchanged'] and result['proposed_inputs_unchanged'] else 'failed'
(attempt / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ('status', 'exit_code', 'elapsed_seconds', 'failure', 'owned_outer_process_group_absent', 'maintained_inputs_unchanged', 'proposed_inputs_unchanged')}))
print(streams['stderr'].decode()[-15000:])
raise SystemExit(0 if result['status'] == 'pass' else 1)
