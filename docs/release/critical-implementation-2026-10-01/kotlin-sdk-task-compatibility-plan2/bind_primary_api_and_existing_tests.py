#!/usr/bin/env python3
"""Review evidence only: authenticated existing APIs, source and dependencies."""
import concurrent.futures
import hashlib
import json
import os
import signal
import time
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORIGIN = HERE / 'public-origin'
OWNED = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/private-gradle/sdk-kotlin-2.4.20-candidate1/caches/modules-2/files-2.1')
GRADLE_ZIP = Path('/Users/jeanbosco/.gradle/wrapper/dists/gradle-9.1.0-all/7wzd0jkjit61aq2p43wpjgij9/gradle-9.1.0-all.zip')
GRADLE_SHA = 'b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85'
REQUESTS = {
    'kotlin-assertFailsWith.html': 'https://kotlinlang.org/api/core/kotlin-test/kotlin.test/assert-fails-with.html',
    'kotlin-assertTrue.html': 'https://kotlinlang.org/api/core/kotlin-test/kotlin.test/assert-true.html',
    'kotlin-test.module': 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-test/2.4.20/kotlin-test-2.4.20.module',
    'kotlin-test-junit5.module': 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-test-junit5/2.4.20/kotlin-test-junit5-2.4.20.module',
    'kotlin-test-junit5.pom': 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-test-junit5/2.4.20/kotlin-test-junit5-2.4.20.pom',
}


def fetch(pair):
    name, url = pair
    tick = time.monotonic()
    result = {'primary_url': url, 'request_timeout_seconds': 30}
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'Collect-public-api-review/1.0', 'Accept-Encoding': 'identity'})
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read(4 * 1024 ** 2 + 1)
            if len(body) > 4 * 1024 ** 2 or response.status != 200:
                raise ValueError('bounded primary API body/status differs')
            with (ORIGIN / name).open('xb') as out:
                out.write(body)
            result.update({'http_status': response.status, 'final_url': response.url, 'bytes': len(body), 'SHA256': hashlib.sha256(body).hexdigest()})
    except Exception as error:
        result.update({'failed': True, 'exception_type': type(error).__name__, 'public_error': str(error)})
    result['actual_seconds'] = round(time.monotonic() - tick, 3)
    return name, result


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    ORIGIN.mkdir()
    started = time.monotonic()
    signal.signal(signal.SIGALRM, lambda signum, frame: (_ for _ in ()).throw(TimeoutError('fixed120s primary review deadline')))
    signal.alarm(120)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        index = dict(pool.map(fetch, REQUESTS.items()))
    signal.alarm(0)
    with (ORIGIN / 'primary-api-origin-index.json').open('x') as out:
        json.dump({'records': index, 'actual_seconds': round(time.monotonic() - started, 3), 'actual_process_deadline_seconds': 120, 'private_source_sent': False, 'SDK_source_modified_or_executed': False}, out, indent=2, sort_keys=True)
        out.write('\n')
    if any(row.get('failed') for row in index.values()):
        raise ValueError('actual public API acquisition failure retained')
    if digest(GRADLE_ZIP) != GRADLE_SHA or GRADLE_ZIP.resolve() != GRADLE_ZIP:
        raise ValueError('independently authenticated exact Gradle distribution drift')
    docs = {}
    with zipfile.ZipFile(GRADLE_ZIP) as archive:
        for name, member in {
            'Gradle-9.1.0-PathSensitive.java': 'gradle-9.1.0/src/core-api/org/gradle/api/tasks/PathSensitive.java',
            'Gradle-9.1.0-PathSensitivity.java': 'gradle-9.1.0/src/core-api/org/gradle/api/tasks/PathSensitivity.java',
            'Gradle-9.1.0-DisableCachingByDefault.java': 'gradle-9.1.0/src/core-api/org/gradle/work/DisableCachingByDefault.java',
        }.items():
            entry = archive.getinfo(member)
            if entry.file_size > 64 * 1024:
                raise ValueError('reviewed publisher source byte bound')
            body = archive.read(entry)
            with (ORIGIN / name).open('xb') as out:
                out.write(body)
            docs[name] = {'archive_member': member, 'bytes': len(body), 'SHA256': hashlib.sha256(body).hexdigest(), 'CRC32': entry.CRC, 'authenticated_publisher_distribution_SHA256': GRADLE_SHA, 'publisher_source_URL': 'https://github.com/gradle/gradle/blob/v9.1.0/subprojects/core-api/src/main/java/' + member.split('/org/', 1)[1].join(['org/', '']), 'primary_distribution_checksum_URL': 'https://services.gradle.org/distributions/gradle-9.1.0-all.zip.sha256'}
    tests = {}
    for module in ('kotlin-test', 'kotlin-test-junit5'):
        base = OWNED / 'org.jetbrains.kotlin' / module / '2.4.20'
        actual_module = list(base.glob('*/' + module + '-2.4.20.module'))
        actual_jar = list(base.glob('*/' + module + '-2.4.20.jar'))
        if len(actual_module) != 1 or len(actual_jar) != 1:
            raise ValueError('genuine cold resolver test artifacts absent/duplicate')
        primary = (ORIGIN / (module + '.module')).read_bytes()
        if digest(actual_module[0]) != hashlib.sha256(primary).hexdigest():
            raise ValueError('actual test module metadata differs from independently fetched publisher bytes')
        metadata = json.loads(primary)
        component = metadata['component']
        if component['group'] != 'org.jetbrains.kotlin' or component['module'] != module or component['version'] != '2.4.20':
            raise ValueError('publisher exact existing test component identity differs')
        files = [file for variant in metadata['variants'] for file in variant.get('files', []) if file['name'] == actual_jar[0].name]
        sha = digest(actual_jar[0])
        if not files or any(file['size'] != actual_jar[0].stat().st_size or file['sha256'] != sha for file in files):
            raise ValueError('actual existing public test API body differs from primary module descriptor')
        tests[module] = {'actual_cache_path': str(actual_jar[0]), 'bytes': actual_jar[0].stat().st_size, 'SHA256': sha, 'independent_publisher_descriptor_match': True, 'new_dependency_or_source_write': False}
    with (HERE / 'primary-api-existing-dependency-binding.json').open('x') as out:
        json.dump({'status': 'PRIMARY_API_AND_EXISTING_DEPENDENCY_REVIEW_BINDINGS_PASS', 'Gradle_exact_publisher_source': docs, 'existing_test_components': tests, 'path_default_preservation': 'Authenticated Gradle9.1 PathSensitive.java says missing annotation default ABSOLUTE; proposed explicit annotation preserves that default.', 'cacheability': 'DisableCachingByDefault describes existing default; does not opt task into caching and does not bypass property validation.', 'assertion_semantics': 'Public kotlin.test assertTrue/False keep the exact current boolean arguments; assertFailsWith<NullPointerException> keeps the exact current expected exception and block.', 'genuine_complete_test_compile_and_execution_after_fix': 'pending actual reviewed new compiler command', 'SDK_source_modified_or_executed': False}, out, indent=2, sort_keys=True)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())
    print(json.dumps({'exact_primary_API_source_bound': True, 'actual_existing_public_test_artifacts_publisher_match': True, 'source_write_or_SDK_execution': False}))


if __name__ == '__main__':
    main()
