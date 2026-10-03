#!/usr/bin/env python3
"""Build exclusive official amd64 Ubuntu prerequisites for canonical Flutter Pub."""
import json
from pathlib import Path
import subprocess

from run_owned import now, run, write

OUT = Path(__file__).resolve().parent
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIVATE = Path(BOUNDARY['private_root'])
ATTEMPT = OUT / 'ubuntu-build-attempt1'
ATTEMPT.mkdir(exist_ok=False)
OWNER = PRIVATE.name
TAG = OWNER + ':proof'
CONTEXT = PRIVATE / 'ubuntu-build-context'
CONTEXT.mkdir(exist_ok=False)
DOCKERFILE = '''FROM ''' + BOUNDARY['ubuntu_manifest'] + '''
LABEL com.collect.arc01.owner="''' + OWNER + '''"
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl git make ruby unzip xz-utils zip libglu1-mesa && rm -rf /var/lib/apt/lists/*
RUN groupadd --gid 1001 arc01 && useradd --uid 501 --gid 1001 --create-home --shell /bin/bash arc01
USER arc01
WORKDIR /work/checkout
ENV PATH=/opt/flutter/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
'''
(CONTEXT / 'Dockerfile').write_text(DOCKERFILE)
(ATTEMPT / 'Dockerfile').write_text(DOCKERFILE)
try:
    inspected = subprocess.check_output(['docker', 'image', 'inspect', BOUNDARY['ubuntu_manifest']], timeout=20)
    base = json.loads(inspected)[0]
    expected = json.loads((OUT / 'preparation-attempt1/ubuntu-amd64-bootstrap-plan-identity.json').read_text())
    if base['Id'] != expected['config_digest'] or base['Architecture'] != 'amd64':
        raise RuntimeError('Official local Ubuntu amd64 identity mismatch')
    result = run(ATTEMPT, 'build', ['docker', 'build', '--no-cache', '--progress', 'plain',
                '--platform', 'linux/amd64', '--tag', TAG, '--iidfile',
                str(ATTEMPT / 'image-id.txt'), str(CONTEXT)], 300)
    raw = subprocess.check_output(['docker', 'image', 'inspect', TAG], timeout=20)
    (ATTEMPT / 'image-inspect.json').write_bytes(raw)
    own = json.loads(raw)[0]
    if own['Architecture'] != 'amd64' or own['Config']['Labels'].get('com.collect.arc01.owner') != OWNER:
        raise RuntimeError('Owned image platform or label mismatch')
    write(ATTEMPT, 'result.json', {'at_utc': now(), 'process': result, 'tag': TAG,
          'owner': OWNER, 'image_id': own['Id'], 'official_base_image_id': base['Id'],
          'prerequisite_reference': 'https://docs.flutter.dev/install/manual',
          'runtime_emulation_executable_not_yet_tested': True})
    print(json.dumps({'status': 'OWNED_UBUNTU_PREREQUISITES_BUILT', 'image_id': own['Id']}, indent=2))
except Exception as error:
    write(ATTEMPT, 'failure.json', {'at_utc': now(), 'type': type(error).__name__, 'error': str(error)})
    raise
