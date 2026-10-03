#!/usr/bin/env python3
"""Drain successful engine stdout without changing its stdin, args or exit code."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

LIMIT = 65536
tool = Path(__file__).resolve()
engine = tool.with_name('font-subset.original')
config = json.loads(tool.with_name('font-subset-wrapper-config.json').read_text())
digest = hashlib.sha256(engine.read_bytes()).hexdigest()
if digest != config['original_sha256']:
    print('Original font-subset hash admission failed', file=sys.stderr)
    raise SystemExit(125)
log_root = Path(config['proof_log_directory'])
log_root.mkdir(parents=True, exist_ok=True)
total = 0
stream_digest = hashlib.sha256()
prefix = bytearray()
failure = []
started = time.time()
process = subprocess.Popen([str(engine), *sys.argv[1:]], stdin=None,
                           stdout=subprocess.PIPE, stderr=None)

def drain():
    global total
    try:
        while True:
            chunk = process.stdout.read(65536)
            if not chunk:
                break
            total += len(chunk)
            stream_digest.update(chunk)
            if len(prefix) < LIMIT:
                prefix.extend(chunk[:LIMIT - len(prefix)])
    except BaseException as error:
        failure.append(repr(error))
    finally:
        process.stdout.close()

reader = threading.Thread(target=drain, name='font-subset-stdout-drain')
reader.start()
code = process.wait()
reader.join()
record = {
    'engine': str(engine), 'original_engine_sha256': digest,
    'wrapper_sha256': hashlib.sha256(tool.read_bytes()).hexdigest(),
    'argv': sys.argv[1:], 'engine_exit_code': code, 'started_at_unix': started,
    'stdout_total_bytes': total, 'stdout_sha256': stream_digest.hexdigest(),
    'stdout_prefix_bytes': len(prefix), 'stdout_prefix_limit_bytes': LIMIT,
    'stdout_prefix_base64': base64.b64encode(prefix).decode('ascii'),
    'stdout_fully_drained': not failure, 'drain_errors': failure,
    'stdin_inherited_unchanged': True, 'stderr_inherited_unchanged': True,
    'font_outputs_not_modified_by_wrapper': True,
}
fd, name = tempfile.mkstemp(prefix='font-subset-', suffix='.json', dir=log_root)
with os.fdopen(fd, 'w') as receipt:
    json.dump(record, receipt, indent=2, sort_keys=True)
    receipt.write('\n')
if failure:
    print('font-subset stdout drain failed; retained receipt: ' + name, file=sys.stderr)
    raise SystemExit(125)
if code < 0:
    # Shell-style propagation retains the genuine terminating signal failure.
    raise SystemExit(128 - code)
raise SystemExit(code)
