#!/usr/bin/env python3
"""Run one bounded, authenticated local Collect jobs tick.

The host launcher uses the existing private jobs token and local ingress. The
server owns job selection, durable claims, retries and financial effects. This
program never reads SMS, prints credentials, or opens a public listener.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

TOKEN = re.compile(r'^[A-Za-z0-9_-]{32,256}$')
SHA = re.compile(r'^[a-f0-9]{64}$')


def endpoint(value: str) -> tuple[str, str]:
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or
        parsed.username is not None or parsed.password is not None or
        parsed.port is None or not 1 <= parsed.port <= 65535 or
        parsed.path != '/functions/v1/collect-jobs' or parsed.query or parsed.fragment):
        raise ValueError('A local Collect jobs endpoint is required')
    base = f'http://127.0.0.1:{parsed.port}'
    return base + parsed.path, base + '/functions/v1/collect-api/health'


def private_json(path: Path) -> dict:
    info = path.lstat()
    if (path.is_symlink() or not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
        or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 262144):
        raise ValueError('Private jobs credential is unavailable')
    value = json.loads(path.read_text(encoding='utf8'))
    if not isinstance(value, dict):
        raise ValueError('Private jobs credential is unavailable')
    return value


def read_identity(release: Path) -> tuple[str, str]:
    release = release.resolve(strict=True)
    meta = json.loads((release / 'release.json').read_text(encoding='utf8'))
    source = meta.get('source_sha256')
    token = private_json(release / 'private' / 'keys.json').get('COLLECT_JOB_TOKEN')
    if not isinstance(source, str) or not SHA.fullmatch(source) or not isinstance(token, str) or not TOKEN.fullmatch(token):
        raise ValueError('Exact release identity and jobs credential are required')
    return source, token


def tick(release: Path, url: str, opener=None) -> dict:
    job_url, health_url = endpoint(url)
    source, token = read_identity(release)
    opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(urllib.request.Request(health_url, headers={'Accept': 'application/json'}), timeout=10) as response:
        health = json.load(response)
    if not isinstance(health, dict) or health.get('database') != 'available' or health.get('release') != source:
        raise ValueError('Live backend does not match the selected release')
    dispatch = {'dispatch_id': str(uuid.uuid4())}
    settings_path = release / 'private' / 'provider-settings.json'
    settings = private_json(settings_path) if settings_path.exists() else {}
    canonical_enabled = settings.get('BURIMUNSI_CANONICAL_SCHEDULER_ENABLED') == 'true'
    if canonical_enabled:
        approval = settings.get('COLLECT_JOBS_PROCESSING_APPROVAL_SHA256')
        model = settings.get('MOMO_AI_MODEL')
        if (settings.get('COLLECT_JOBS_MODE') != 'receipt_processing_v1'
            or settings.get('MOMO_PROCESSING_PAUSED') != 'false'
            or not isinstance(approval, str) or not SHA.fullmatch(approval)
            or not isinstance(model, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}', model)):
            raise ValueError('Bound receipt dispatch is unavailable')
        dispatch['processing_admission'] = {'contract': 'collect.receipt-processing.v1',
            'source_sha256': source, 'approval_sha256': approval, 'model_id': model, 'batch_limit': 1}
    request = urllib.request.Request(job_url, method='POST',
        data=json.dumps(dispatch).encode('utf8'),
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json', 'Accept': 'application/json'})
    with opener.open(request, timeout=120) as response:
        if response.status != 200:
            raise ValueError('Jobs tick was not confirmed')
        result = json.load(response)
    if not isinstance(result, dict):
        raise ValueError('Jobs tick was not confirmed')
    native_ledger_enabled = settings.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED') == 'true'
    if native_ledger_enabled:
        for lane in ('native_auto_processing', 'native_sms_ledger'):
            if not isinstance(result.get(lane), dict) or result[lane].get('status') != 'complete':
                raise ValueError('Native SMS tick was not confirmed')
    elif 'native_auto_processing' in result or 'native_sms_ledger' in result:
        # A live response for either lane contradicts the sealed disabled
        # configuration. Never report a successful stop under config drift.
        raise ValueError('Native SMS disabled state was not confirmed')
    if canonical_enabled and (not isinstance(result.get('canonical_processing'), dict)
        or result['canonical_processing'].get('status') not in ('complete', 'busy', 'yielded')):
        raise ValueError('Canonical jobs tick was not confirmed')
    return {'status': 'complete', 'source_sha256': source,
            'native_auto_processing': 'complete' if native_ledger_enabled else 'disabled',
            'native_sms_ledger': 'complete' if native_ledger_enabled else 'disabled',
            **({'canonical_processing': result['canonical_processing']['status']} if canonical_enabled else {})}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--release', type=Path, required=True)
    p.add_argument('--endpoint', required=True)
    p.add_argument('--lock', type=Path, required=True)
    a = p.parse_args()
    try:
        parent = a.lock.parent.resolve(strict=True)
        if parent.stat().st_uid != os.getuid() or stat.S_IMODE(parent.stat().st_mode) & 0o077:
            raise ValueError('Private scheduler directory required')
        fd = os.open(a.lock, os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        with os.fdopen(fd, 'r+') as lock:
            info = os.fstat(lock.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
                raise ValueError('Private scheduler lock required')
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                print(json.dumps({'status': 'already_running'}))
                return 0
            print(json.dumps(tick(a.release, a.endpoint)))
            return 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, urllib.error.URLError):
        print(json.dumps({'status': 'unconfirmed', 'private_values_disclosed': False}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
