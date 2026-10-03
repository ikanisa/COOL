#!/usr/bin/env python3
"""Independent exact public compiler body, bounded; no SDK/cache writes."""
import datetime
import hashlib
import json
import os
import signal
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORIGIN = HERE / 'public-origin'
LIMIT = 128 * 1024 ** 2


def main():
    started = time.monotonic()
    signal.signal(signal.SIGALRM, lambda signum, frame: (_ for _ in ()).throw(TimeoutError('fixed 300s public body deadline')))
    signal.alarm(300)
    index = json.loads((ORIGIN / 'candidate-origin-index.json').read_text())['records']
    pom = (ORIGIN / 'compiler-pom').read_bytes()
    checksum = (ORIGIN / 'compiler-jar-sha1').read_bytes()
    if hashlib.sha256(pom).hexdigest() != '269d98cc4c68670c11e4aeb404e1c7c6f31b782321908d7268ba25cd236d59b2' or hashlib.sha256(checksum).hexdigest() != index['compiler-jar-sha1']['sha256']:
        raise ValueError('reviewed independent exact compiler metadata drift')
    expected = checksum.decode('ascii').strip()
    if expected != '23b042894dcabe39edd0f8bd30b7be0f25fe9933':
        raise ValueError('published exact checksum identity drift')
    url = index['compiler-pom']['url'].removesuffix('.pom') + '.jar'
    exact = 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-compiler-embeddable/2.4.20/kotlin-compiler-embeddable-2.4.20.jar'
    if url != exact:
        raise ValueError('exact source-derived publisher URL differs')
    target = ORIGIN / 'compiler-independent-publisher.jar.part'
    record = {'primary_url': url, 'metadata_derived_url': True, 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'actual_process_deadline_seconds': 300, 'request_timeout_seconds': 30, 'maximum_bytes': LIMIT, 'published_SHA1': expected, 'independently_published_SHA256_available': False, 'SDK_or_cache_execution_or_mutation': False, 'no_private_source_sent': True}
    try:
        h1 = hashlib.sha1()
        h256 = hashlib.sha256()
        count = 0
        request = urllib.request.Request(url, headers={'User-Agent': 'Collect-public-publisher-origin-verification/1.0', 'Accept-Encoding': 'identity'})
        with target.open('xb') as out, urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200 or response.url != url:
                raise ValueError('exact public artifact status/origin differs')
            record.update({'http_status': response.status, 'final_url': response.url, 'content_length': response.headers.get('Content-Length')})
            length = record['content_length']
            if length is None or int(length) > LIMIT:
                raise ValueError('publisher artifact length bound')
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                count += len(chunk)
                if count > LIMIT:
                    raise ValueError('actual artifact byte bound')
                out.write(chunk)
                h1.update(chunk)
                h256.update(chunk)
            out.flush()
            os.fsync(out.fileno())
        if count != int(length) or h1.hexdigest() != expected:
            raise ValueError('complete publisher bytes/checksum mismatch')
        r256 = hashlib.sha256()
        with target.open('rb') as inp:
            for chunk in iter(lambda: inp.read(1024 * 1024), b''):
                r256.update(chunk)
        if r256.hexdigest() != h256.hexdigest() or target.is_symlink() or target.stat().st_nlink != 1:
            raise ValueError('independent artifact physical readback mismatch')
        final = target.with_suffix('')
        if final.exists():
            raise ValueError('existing final artifact; no overwrite')
        os.rename(target, final)
        record.update({'status': 'EXACT_HTTPS_PUBLISHER_BODY_SHA1_AND_FULL_SHA256_READBACK_PASS', 'artifact_path': str(final), 'bytes': count, 'actual_SHA1': h1.hexdigest(), 'actual_SHA256': h256.hexdigest(), 'readback_SHA256': r256.hexdigest(), 'not_a_published_SHA256_claim': True, 'actual_cache_artifact_comparison_pending': True})
    except Exception as error:
        record.update({'status': 'ACTUAL_PUBLIC_BODY_FETCH_FAILURE_RETAINED', 'exception_type': type(error).__name__, 'public_error': str(error), 'partial_preserved': target.exists()})
    finally:
        signal.alarm(0)
        record['actual_seconds'] = round(time.monotonic() - started, 3)
        with (ORIGIN / 'compiler-independent-publisher-body.json').open('x') as out:
            json.dump(record, out, indent=2, sort_keys=True)
            out.write('\n')
            out.flush()
            os.fsync(out.fileno())
    print(json.dumps(record, indent=2))
    return 0 if record['status'].endswith('_PASS') else 1


if __name__ == '__main__':
    raise SystemExit(main())
