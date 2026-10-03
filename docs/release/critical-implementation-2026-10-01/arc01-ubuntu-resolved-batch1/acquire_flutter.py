#!/usr/bin/env python3
"""Authenticate exact public Linux Flutter archive without executing its scripts."""
import concurrent.futures
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.request

OUT = Path(__file__).resolve().parent
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIVATE = Path(BOUNDARY['private_root'])
ATTEMPT = OUT / 'acquisition-attempt1'
ATTEMPT.mkdir(exist_ok=False)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write(name, value):
    (ATTEMPT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def command(name, argv, deadline):
    start = time.monotonic()
    initial = {'argv': argv, 'started_at_utc': now(), 'deadline_seconds': deadline}
    with (ATTEMPT / (name + '.log')).open('wb') as log:
        process = subprocess.Popen(argv, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        write(name + '-process.json', {**initial, 'pid': process.pid})
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
    result = {**initial, 'completed_at_utc': now(),
              'elapsed_seconds': time.monotonic() - start, 'exit_code': code,
              'timed_out': timed_out, 'log_sha256': digest(ATTEMPT / (name + '.log'))}
    write(name + '-result.json', result)
    if code != 0 or timed_out:
        raise RuntimeError(name + ' failed; exact partial log and owned process result retained')
    return result


def archive():
    url = BOUNDARY['publisher_archive_url'] + '?generation=' + BOUNDARY['publisher_object_generation']
    with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=25) as response:
        head = {'at_utc': now(), 'url': url, 'status': response.status,
                'headers': dict(response.headers)}
    write('generation-pinned-head.json', head)
    if (head['status'] != 200
            or int(head['headers']['Content-Length']) != BOUNDARY['publisher_archive_bytes']
            or head['headers']['x-goog-generation'] != BOUNDARY['publisher_object_generation']):
        raise RuntimeError('Publisher object identity or complete size differs')
    partial = PRIVATE / 'flutter_linux_3.44.4-stable.tar.xz.partial'
    final = PRIVATE / 'flutter_linux_3.44.4-stable.tar.xz'
    if partial.exists() or final.exists():
        raise RuntimeError('Fresh exclusive archive path already exists')
    result = command('flutter-download', ['curl', '--fail', '--location',
                     '--connect-timeout', '15', '--max-time', '900', '--retry', '0',
                     '--silent', '--show-error', '--dump-header',
                     str(ATTEMPT / 'flutter-download-headers.txt'), '--write-out',
                     '%{url_effective} %{response_code} %{size_download}\n', '--output',
                     str(partial), url], 930)
    actual = digest(partial)
    bytes_count = partial.stat().st_size
    readback = {'at_utc': now(), 'sha256': actual, 'bytes': bytes_count,
                'expected_sha256': BOUNDARY['publisher_archive_sha256'],
                'expected_bytes': BOUNDARY['publisher_archive_bytes'],
                'archive_script_executed': False, 'download': result}
    write('archive-complete-readback.json', readback)
    if actual != BOUNDARY['publisher_archive_sha256'] or bytes_count != BOUNDARY['publisher_archive_bytes']:
        raise RuntimeError('Complete publisher archive digest or size mismatch')
    partial.rename(final)
    return {**readback, 'verified_archive': str(final)}


def image():
    result = command('ubuntu-amd64-pull', ['docker', 'pull', '--platform', 'linux/amd64',
                     BOUNDARY['ubuntu_manifest']], 180)
    raw = subprocess.check_output(['docker', 'image', 'inspect', BOUNDARY['ubuntu_manifest']], timeout=20)
    (ATTEMPT / 'ubuntu-amd64-image-inspect.json').write_bytes(raw)
    record = json.loads(raw)[0]
    expected = json.loads((OUT / 'preparation-attempt1/ubuntu-amd64-bootstrap-plan-identity.json').read_text())
    if record['Architecture'] != 'amd64' or record['Os'] != 'linux' or record['Id'] != expected['config_digest']:
        raise RuntimeError('Official Ubuntu actual local platform/image identity mismatch')
    return {'pull': result, 'image_id': record['Id'], 'architecture': record['Architecture']}


try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        a = pool.submit(archive)
        i = pool.submit(image)
        result = {'archive': a.result(), 'ubuntu': i.result()}
    write('result.json', {'at_utc': now(), 'status': 'AUTHENTICATED_ACQUISITION_ONLY',
                         **result, 'flutter_pub_bootstrap_executed': False,
                         'formatter_executed': False})
    print(json.dumps({'status': 'AUTHENTICATED_ACQUISITION_ONLY',
                      'archive': result['archive']['verified_archive'],
                      'archive_sha256': result['archive']['sha256'],
                      'ubuntu_image_id': result['ubuntu']['image_id']}, indent=2), flush=True)
except Exception as error:
    write('failure.json', {'at_utc': now(), 'type': type(error).__name__, 'error': str(error),
                           'archive_script_executed': False, 'formatter_executed': False})
    raise
