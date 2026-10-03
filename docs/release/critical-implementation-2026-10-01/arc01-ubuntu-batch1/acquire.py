#!/usr/bin/env python3
import concurrent.futures
import datetime
import hashlib
import json
import os
import pathlib
import signal
import subprocess
import time
import zipfile

OUT = pathlib.Path(__file__).resolve().parent
PREP = OUT / 'preparation-attempt2'
LOG = OUT / 'acquisition-attempt1'
LOG.mkdir(exist_ok=False)
PLAN = json.loads((PREP / 'execution-plan.json').read_text())
PRIVATE = pathlib.Path(PLAN['private_root'])
ARCHIVE = PRIVATE / 'dartsdk-linux-arm64-release.zip'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def run(name, argv, deadline):
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    stamp = time.monotonic()
    with (LOG / (name + '.log')).open('wb') as output:
        process = subprocess.Popen(argv, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        (LOG / (name + '-process.json')).write_text(json.dumps({
            'pid': process.pid, 'argv': argv, 'deadline_seconds': deadline,
            'started_at_utc': started}, indent=2) + '\n')
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
    result = {'argv': argv, 'started_at_utc': started,
              'completed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'deadline_seconds': deadline, 'elapsed_seconds': time.monotonic() - stamp,
              'exit_code': code, 'timed_out': timed_out,
              'log_sha256': digest(LOG / (name + '.log'))}
    (LOG / (name + '-result.json')).write_text(json.dumps(result, indent=2) + '\n')
    assert code == 0 and not timed_out, result
    return result


try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        sdk = pool.submit(run, 'dart-download', [
            'curl', '--fail', '--location', '--connect-timeout', '15',
            '--max-time', '240', '--retry', '0', '--silent', '--show-error',
            '--dump-header', str(LOG / 'dart-download-headers.txt'),
            '--write-out', '%{url_effective} %{response_code} %{size_download}\n',
            '--output', str(ARCHIVE), PLAN['dart_zip_url']], 260)
        image = pool.submit(run, 'ubuntu-pull', [
            'docker', 'pull', '--platform', 'linux/arm64', PLAN['ubuntu_base']], 150)
        results = {'dart_download': sdk.result(), 'ubuntu_pull': image.result()}
    actual = digest(ARCHIVE)
    assert actual == PLAN['dart_zip_expected_sha256'], actual
    runtime = PRIVATE / 'runtime'
    runtime.mkdir(exist_ok=False)
    with zipfile.ZipFile(ARCHIVE) as archive:
        for info in archive.infolist():
            target = runtime / info.filename
            assert target.resolve().is_relative_to(runtime), info.filename
            assert (info.external_attr >> 16) & 0o170000 != 0o120000, info.filename
        archive.extractall(runtime)
        for info in archive.infolist():
            mode = (info.external_attr >> 16) & 0o777
            if mode and not info.is_dir():
                (runtime / info.filename).chmod(mode)
    inspect = json.loads(subprocess.check_output(['docker', 'image', 'inspect', PLAN['ubuntu_base']]))
    (LOG / 'ubuntu-image-inspect.json').write_text(json.dumps(inspect, indent=2) + '\n')
    publisher = json.loads((PREP / 'publisher-metadata.json').read_text())
    assert len(inspect) == 1
    assert inspect[0]['Id'] == publisher['ubuntu']['config_digest']
    assert inspect[0]['Architecture'] == 'arm64' and inspect[0]['Os'] == 'linux'
    result = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'PUBLISHER_CHECKSUM_AND_IMAGE_ID_VERIFIED', 'commands': results,
        'archive_sha256': actual, 'archive_bytes': ARCHIVE.stat().st_size,
        'runtime': str(runtime), 'dart_executable_sha256': digest(runtime / 'dart-sdk/bin/dart'),
        'ubuntu_image_id': inspect[0]['Id'], 'ubuntu_manifest': PLAN['ubuntu_base']}
    (LOG / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
except Exception as error:
    (LOG / 'failure.json').write_text(json.dumps({
        'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'type': type(error).__name__, 'error': str(error),
        'archive_exists': ARCHIVE.exists()}, indent=2) + '\n')
    raise
