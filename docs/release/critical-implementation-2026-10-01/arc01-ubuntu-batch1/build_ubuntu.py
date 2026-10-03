#!/usr/bin/env python3
import datetime
import hashlib
import json
import os
import pathlib
import signal
import subprocess
import time

OUT = pathlib.Path(__file__).resolve().parent
LOG = OUT / 'ubuntu-build-attempt1'
LOG.mkdir(exist_ok=False)
PLAN = json.loads((OUT / 'preparation-attempt2/execution-plan.json').read_text())
PUBLISHER = json.loads((OUT / 'preparation-attempt2/publisher-metadata.json').read_text())
PRIVATE = pathlib.Path(PLAN['private_root'])
CONTEXT = PRIVATE / 'ubuntu-build-context'
CONTEXT.mkdir(exist_ok=False)
OWNER = PRIVATE.name
TAG = 'collect-arc01-' + OWNER.removeprefix('collect-arc01-') + ':proof'
base = json.loads(subprocess.check_output(['docker', 'image', 'inspect', PLAN['ubuntu_base']]))[0]
assert base['Id'] == PUBLISHER['ubuntu']['config_digest']
assert base['Os'] == 'linux' and base['Architecture'] == 'arm64'
dockerfile = '\n'.join([
    'FROM ' + PLAN['ubuntu_base'],
    'LABEL com.collect.arc01.owner="' + OWNER + '"',
    'RUN apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 update',
    'RUN DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y --no-install-recommends ca-certificates git make ruby',
    'RUN rm -rf /var/lib/apt/lists/*',
    'ENV PATH="/opt/dart/dart-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"',
    'WORKDIR /work/checkout',
    'CMD ["/bin/bash"]',
    '',
])
(CONTEXT / 'Dockerfile').write_text(dockerfile)
(LOG / 'Dockerfile').write_text(dockerfile)
argv = ['docker', 'build', '--no-cache', '--progress', 'plain', '--platform', 'linux/arm64',
        '--tag', TAG, '--iidfile', str(LOG / 'image-id.txt'), str(CONTEXT)]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
stamp = time.monotonic()
with (LOG / 'build.log').open('wb') as stream:
    process = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
    (LOG / 'process.json').write_text(json.dumps({'argv': argv, 'pid': process.pid,
          'deadline_seconds': 240, 'started_at_utc': started}, indent=2) + '\n')
    timed_out = False
    try:
        code = process.wait(timeout=240)
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
    'deadline_seconds': 240, 'elapsed_seconds': time.monotonic() - stamp,
    'exit_code': code, 'timed_out': timed_out, 'tag': TAG,
    'base_image_id': base['Id'], 'owner_label': OWNER,
    'log_sha256': hashlib.sha256((LOG / 'build.log').read_bytes()).hexdigest()}
if code == 0 and not timed_out:
    image = json.loads(subprocess.check_output(['docker', 'image', 'inspect', TAG]))[0]
    assert image['Config']['Labels']['com.collect.arc01.owner'] == OWNER
    result['image_id'] = image['Id']
    (LOG / 'image-inspect.json').write_text(json.dumps(image, indent=2) + '\n')
(LOG / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
assert code == 0 and not timed_out, 'Ubuntu prerequisite build failed; retain log and do not repeat unchanged timeout'
