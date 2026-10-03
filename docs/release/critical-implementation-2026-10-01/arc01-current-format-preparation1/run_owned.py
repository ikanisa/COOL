"""Bounded owned subprocess receipts; no global process or container cleanup."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def write(directory, name, value):
    (directory / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def run(directory, name, argv, deadline, require_success=True):
    start = time.monotonic()
    initial = {'argv': argv, 'started_at_utc': now(), 'deadline_seconds': deadline}
    with (directory / (name + '.log')).open('wb') as log:
        process = subprocess.Popen(argv, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        write(directory, name + '-process.json', {**initial, 'pid': process.pid})
        timed_out = False
        try:
            code = process.wait(timeout=deadline)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=5)
    result = {**initial, 'completed_at_utc': now(), 'elapsed_seconds': time.monotonic() - start,
              'exit_code': code, 'timed_out': timed_out,
              'log_sha256': sha(directory / (name + '.log'))}
    write(directory, name + '-result.json', result)
    if timed_out or (require_success and code != 0):
        raise RuntimeError(name + ' failed; original complete or partial log retained')
    return result
