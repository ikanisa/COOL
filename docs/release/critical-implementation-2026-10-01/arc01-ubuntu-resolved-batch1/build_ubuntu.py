#!/usr/bin/env python3
"""Build exclusive official amd64 Ubuntu prerequisites for canonical Flutter Pub."""
import json
from pathlib import Path
import subprocess
import sys

from run_owned import now, run, write

OUT = Path(__file__).resolve().parent
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIVATE = Path(BOUNDARY['private_root'])
SECOND = sys.argv[1:] == ['bounded-fetch-attempt2']
if sys.argv[1:] and not SECOND:
    raise RuntimeError('Unexpected build mode')
ATTEMPT = OUT / ('ubuntu-build-attempt2' if SECOND else 'ubuntu-build-attempt1')
ATTEMPT.mkdir(exist_ok=False)
OWNER = PRIVATE.name
TAG = OWNER + (':proof2' if SECOND else ':proof')
CONTEXT = PRIVATE / ('ubuntu-build-context2' if SECOND else 'ubuntu-build-context')
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
if SECOND:
    prior = json.loads((OUT / 'ubuntu-build-attempt1/build-result.json').read_text())
    if not prior['timed_out'] or prior['deadline_seconds'] != 300:
        raise RuntimeError('Original real build deadline failure not preserved')
    DOCKERFILE = DOCKERFILE.replace('apt-get update', 'apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=25 update').replace(
        'apt-get install', 'apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=25 install')
    (CONTEXT / 'Dockerfile').write_text(DOCKERFILE)
    (ATTEMPT / 'Dockerfile').write_text(DOCKERFILE)
    write(ATTEMPT, 'changed-acquisition-plan.json', {'at_utc': now(),
          'original_attempt': 'ubuntu-build-attempt1', 'original_actual_deadline': 300,
          'observed_stalls': 'APT libssl3t64 and libcurl4t64 HTTP requests stalled then internally retried',
          'new_request_timeout_seconds': 25, 'new_request_retries': 0,
          'new_total_build_deadline_seconds': 600, 'new_context': str(CONTEXT), 'new_tag': TAG,
          'official_signed_repositories_and_base_unchanged': True})
try:
    inspected = subprocess.check_output(['docker', 'image', 'inspect', BOUNDARY['ubuntu_manifest']], timeout=20)
    base = json.loads(inspected)[0]
    expected = json.loads((OUT / 'preparation-attempt1/ubuntu-amd64-bootstrap-plan-identity.json').read_text())
    if base['Id'] != expected['config_digest'] or base['Architecture'] != 'amd64':
        raise RuntimeError('Official local Ubuntu amd64 identity mismatch')
    result = run(ATTEMPT, 'build', ['docker', 'build', '--no-cache', '--progress', 'plain',
                '--platform', 'linux/amd64', '--tag', TAG, '--iidfile',
                str(ATTEMPT / 'image-id.txt'), str(CONTEXT)], 600 if SECOND else 300)
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
