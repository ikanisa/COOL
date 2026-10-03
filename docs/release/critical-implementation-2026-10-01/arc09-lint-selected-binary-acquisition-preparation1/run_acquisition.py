#!/usr/bin/env python3
"""Private proposal: acquire reviewed publisher bytes; never write Gradle cache."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import subprocess
import threading
import time
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
import zipfile

ROOTS = ('https://dl.google.com/dl/android/maven2/', 'https://repo.maven.apache.org/maven2/')
WORK_SECONDS, REAP_SECONDS, REQUEST_SECONDS = 180, 2, 30
FILE_LIMIT, TOTAL_LIMIT = 128 * 1024**2, 512 * 1024**2
OUTPUT_PARENT = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09')
FIXED = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*\Z')


def utc(): return datetime.now(timezone.utc).isoformat()
def sha(raw): return hashlib.sha256(raw).hexdigest()
def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True); stream.write('\n')
        stream.flush(); os.fsync(stream.fileno())


def identity(s): return s.st_dev, s.st_ino, s.st_size, s.st_mode, s.st_mtime_ns, s.st_ctime_ns


def read(path, limit=FILE_LIMIT, deadline=None):
    path = Path(path)
    if not path.is_absolute() or path.resolve() != path: raise ValueError('Nonphysical input')
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > limit: raise ValueError('Special/oversized input')
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as stream:
        if identity(os.fstat(stream.fileno())) != identity(before): raise ValueError('Input raced before open')
        chunks = []
        while True:
            if deadline is not None and time.monotonic() >= deadline: raise TimeoutError('Whole work deadline')
            block = stream.read(1024**2)
            if not block: break
            chunks.append(block)
        if identity(os.fstat(stream.fileno())) != identity(before) or identity(path.lstat()) != identity(before):
            raise ValueError('Input changed during read')
    return b''.join(chunks)


def record(path, deadline=None):
    body = read(path, deadline=deadline)
    return {'path': str(path), 'bytes': len(body), 'sha256': sha(body), 'sha1': hashlib.sha1(body).hexdigest()}


def coordinate(c):
    if set(c) != {'group', 'name', 'version'}: raise ValueError('Unexpected coordinate fields')
    if not all(re.fullmatch(r'[A-Za-z0-9_-]+', p) for p in c['group'].split('.')): raise ValueError('Group path')
    if any(not FIXED.fullmatch(c[k]) for k in ('name', 'version')): raise ValueError('Nonfixed coordinate')
    if 'SNAPSHOT' in c['version'].upper() or c['version'].lower().startswith('latest.'):
        raise ValueError('Dynamic/snapshot version')
    return c['group'].replace('.', '/') + '/' + c['name'] + '/' + c['version'] + '/'


def valid_url(url):
    u = urlsplit(url)
    if (not any(url.startswith(root) for root in ROOTS) or u.username or u.password or u.query or u.fragment
            or u.scheme != 'https' or '%' in u.path or '..' in u.path.split('/') or '\\' in u.path):
        raise ValueError('URL outside exact official scope')
    return url


def safe_xml(raw):
    if b'<!DOCTYPE' in raw.upper() or b'<!ENTITY' in raw.upper(): raise ValueError('POM entities')
    return ET.fromstring(raw)


def derive_items(facts, graph):
    """Small allowlist of observed contracts; this does not resolve a Gradle graph."""
    if (graph.get('root_requested') != 'com.android.tools.lint:lint-gradle:32.0.1'
            or graph.get('repository_scope') != list(ROOTS) or graph.get('errors')
            or graph.get('complete_selected_tooling_metadata') is not True
            or graph.get('complete_selected_tooling_graph') is not False or graph.get('artifacts')):
        raise ValueError('Wrong/incomplete current metadata scope')
    components = {c['id']: c for c in graph['components'] if c['kind'] == 'module'}
    projections = facts['authoritative_completed_component_projections']
    proof_documents = []
    all_poms = []
    for projection in projections:
        raw = read(projection['path'], 2 * 1024**2)
        if sha(raw) != projection['sha256'] or len(raw) != projection['bytes']: raise ValueError('Projection fence')
        row = json.loads(raw); pom = row['publisher_POM']
        if row['status'] != 'METADATA_VERIFIED' or not pom['exact_Gradle_POM_match']: raise ValueError('Unverified POM')
        body = read(pom['body']['path'], 2 * 1024**2)
        if sha(body) != pom['body']['sha256']: raise ValueError('POM body fence')
        all_poms.append((row['component_id'], safe_xml(body)))
        proof_documents += [record(Path(projection['path'])), record(Path(pom['body']['path']))]
    if {c for c, _ in all_poms} != set(components): raise ValueError('69 selected POM coverage')
    # No classifier is fabricated. The acquired selected POM declarations must
    # contain no classified/non-JAR runtime requests. Effective parent/history
    # completeness remains limited; normal Gradle's full artifact comparison is
    # required before root accepts the file set or advances an AAB.
    for owner, xml in all_poms:
        ns = '{' + xml.tag.partition('}')[0][1:] + '}' if xml.tag.startswith('{') else ''
        for dep in xml.findall('.//' + ns + 'dependency'):
            value = lambda name: (dep.findtext(ns + name) or '').strip()
            if value('classifier'): raise ValueError('Unknown/classified request: ' + owner)
            if value('type') not in ('', 'jar', 'pom'): raise ValueError('Unmapped dependency type: ' + owner)
    items = []
    for file in facts['seven_exact_publisher_declared_file_plans']:
        url = valid_url(file['publisher_binary_URL']); parts = urlsplit(url).path.split('/')
        name, version, filename = parts[-3:]
        prefix = next(root for root in ROOTS if url.startswith(root))
        group = url[len(prefix):].rsplit('/' + name + '/' + version + '/' + filename, 1)[0].replace('/', '.')
        c = {'group': group, 'name': name, 'version': version}; coordinate(c)
        if c['group'] + ':' + name + ':' + version not in components: raise ValueError('Nonselected file owner')
        if filename != name + '-' + version + '.jar': raise ValueError('Unknown declared classifier')
        items.append({'coordinate': c, 'filename': filename, 'URL': url, 'kind': 'publisher-module-declared',
                      'declared_size': file['publisher_declared_size'], 'declared_hashes': file['publisher_declared_hashes'],
                      'classifier': None, 'extension': 'jar'})
    excluded = []
    for row in facts['61_POM_only_contract_facts']:
        c = row['coordinate']; relative = coordinate(c); variants = row['actual_selected_variants']
        if (len(variants) != 1 or variants[0]['name'] != 'default' or variants[0]['owner'] != row['component_id']
                or variants[0]['external_variant'] is not None): raise ValueError('Unknown selected Maven variant')
        attrs = {a['name']: a['value'] for a in variants[0]['attributes']}
        if attrs != {'org.gradle.status': 'release'}: raise ValueError('Unknown Maven/platform attributes')
        xml = next(xml for owner, xml in all_poms if owner == row['component_id'])
        ns = '{' + xml.tag.partition('}')[0][1:] + '}' if xml.tag.startswith('{') else ''
        packaging = xml.findtext(ns + 'packaging')
        packaging = packaging.strip() if packaging is not None else None
        if packaging != row['packaging_declared']: raise ValueError('POM packaging mismatch')
        if xml.find(ns + 'distributionManagement/' + ns + 'relocation') is not None: raise ValueError('Relocation unresolved')
        if packaging == 'pom':
            excluded.append({'component_id': row['component_id'], 'reason': 'POM/BOM: no JAR invented; actual Gradle optional-artifact behavior remains later evidence.'}); continue
        if packaging not in (None, 'jar', 'bundle'): raise ValueError('Unknown packaging: ' + str(packaging))
        pom_url = valid_url(row['verified_POM_URL']); suffix = c['name'] + '-' + c['version'] + '.pom'
        if not pom_url.endswith(relative + suffix): raise ValueError('POM URL/coordinate mismatch')
        filename = c['name'] + '-' + c['version'] + '.jar'
        items.append({'coordinate': c, 'filename': filename, 'URL': pom_url[:-len(suffix)] + filename,
                      'kind': 'standard-Maven-POM-runtime-contract', 'packaging_declared': packaging,
                      'declared_size': None, 'declared_hashes': {}, 'classifier': None, 'extension': 'jar',
                      'module_404_proof': row['official_module_404'], 'POM_body_sha256': row['verified_POM_SHA256'],
                      'basis': 'Observed default variant, absent/jar packaging or pinned Gradle9.1.0 bundle mapping; captured selected POM declarations contain no classifier/non-JAR runtime request.'})
    if len(items) != 67 or len({i['URL'] for i in items}) != 67: raise ValueError('Expected67 unique binary contracts')
    excluded.append({'component_id': 'org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0',
                     'reason': 'Authenticated available-at bridge uses already planned core-jvm target URL; no core root JAR invented.'})
    return sorted(items, key=lambda row: row['URL']), excluded, proof_documents


def zip_check(path, deadline):
    expanded = 0; names = set()
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if len(infos) > 100000: raise ValueError('ZIP entry bound')
        for info in infos:
            if time.monotonic() >= deadline: raise TimeoutError('ZIP whole deadline')
            name = info.filename.rstrip('/'); parsed = PurePosixPath(name)
            if (not name or '\\' in name or parsed.is_absolute() or '..' in parsed.parts or ':' in name
                    or str(parsed) != name or name in names or info.flag_bits & 1
                    or stat.S_ISLNK(info.external_attr >> 16)):
                raise ValueError('Unsafe/duplicate/encrypted ZIP entry')
            names.add(name); expanded += info.file_size
            if expanded > 2 * 1024**3: raise ValueError('ZIP expanded bound')
            with archive.open(info) as source:
                while source.read(1024**2):
                    if time.monotonic() >= deadline: raise TimeoutError('ZIP whole deadline')
    return {'members': len(infos), 'expanded_bytes': expanded, 'safe_paths_and_CRC_complete': True}


def group_absent(pgid):
    try: os.killpg(pgid, 0); return False
    except ProcessLookupError: return True


class Requests:
    def __init__(self, output, started):
        self.output = output; self.started = started; self.deadline = started + WORK_SECONDS
        self.lock = threading.Lock(); self.number = self.total = self.reserved = 0

    def fetch(self, url, limit):
        valid_url(url); remaining = self.deadline - time.monotonic()
        if remaining <= 0: raise TimeoutError('Whole request deadline')
        with self.lock:
            limit = min(limit, TOTAL_LIMIT - self.total - self.reserved)
            if limit <= 0: raise ValueError('Total body budget exhausted')
            self.reserved += limit; self.number += 1
            if self.number > 201: raise ValueError('201 request bound')
            directory = self.output / ('request-' + str(self.number).zfill(4)); directory.mkdir(mode=0o700)
        seconds = min(REQUEST_SECONDS, remaining)
        argv = ['/usr/bin/curl', '--disable', '--proxy', '', '--noproxy', '*', '--proto', '=https',
                '--proto-redir', '=https', '--tlsv1.2', '--connect-timeout', str(min(10, seconds)),
                '--max-time', str(seconds), '--retry', '0', '--max-filesize', str(limit), '--silent', '--show-error',
                '--output', str(directory / 'body'), '--dump-header', str(directory / 'headers'),
                '--write-out', '%{json}', url]
        receipt = {'URL': url, 'argv': argv, 'started_utc': utc(), 'no_credentials_config_proxy_redirect_retry': True,
                   'work_seconds_at_most': seconds, 'reap_seconds_at_most': REAP_SECONDS, 'reserved_body_limit': limit}
        save(directory / 'request.json', receipt)
        process = None
        try:
            with (directory / 'stdout').open('xb') as out, (directory / 'stderr').open('xb') as err:
                process = subprocess.Popen(argv, stdout=out, stderr=err, start_new_session=True,
                                           env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
                receipt['owned_PID_PGID'] = process.pid
                try: receipt['exit_code'] = process.wait(timeout=min(seconds, max(0, self.deadline - time.monotonic())))
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); receipt['timed_out'] = True
                    receipt['exit_code'] = process.wait(timeout=max(0.01, self.deadline + REAP_SECONDS - time.monotonic()))
            receipt['owned_group_absent'] = group_absent(process.pid)
            metadata = json.loads(read(directory / 'stdout', 2 * 1024**2))
            receipt['curl_metadata'] = metadata
            body = read(directory / 'body', limit)
            if (receipt['exit_code'] != 0 or not receipt['owned_group_absent'] or metadata.get('ssl_verify_result') != 0
                    or metadata.get('url_effective') != url or metadata.get('scheme', '').lower() != 'https'):
                raise ValueError('Incomplete HTTPS/TLS/process identity')
            status = metadata.get('http_code', metadata.get('response_code')); receipt['HTTP_status'] = status
            if status not in (200, 404): raise ValueError('HTTP status: ' + str(status))
            headers = read(directory / 'headers', 2 * 1024**2).decode('iso-8859-1')
            final_headers = re.split(r'(?m)^HTTP/[^\r\n]+\r?\n', headers)[-1]
            lengths = re.findall(r'(?im)^Content-Length:\s*(\d+)\s*$', final_headers)
            if status == 200 and (len(lengths) != 1 or int(lengths[0]) != len(body)):
                raise ValueError('Content-Length binding unknown/mismatch')
            receipt['content_length_matches'] = bool(lengths and int(lengths[0]) == len(body))
            return {'path': str(directory / 'body'), 'URL': url, 'HTTP_status': status, 'request_directory': str(directory)}
        except BaseException as error:
            receipt['error'] = {'type': type(error).__name__, 'message': str(error)}; raise
        finally:
            if process is not None and process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=REAP_SECONDS)
            receipt['finished_utc'] = utc()
            receipt['leaves'] = [record(f) for f in sorted(directory.iterdir()) if f.is_file()]
            actual = (directory / 'body').stat().st_size if (directory / 'body').exists() else 0
            with self.lock:
                self.reserved -= limit; self.total += actual; receipt['cumulative_body_bytes'] = self.total
            save(directory / 'receipt.json', receipt)


def checksum(raw, algorithm, item):
    length = 64 if algorithm == 'sha256' else 40
    # Accept bare hash, filename, or exact Maven relative path. Text is never a
    # command/path to read; other-coordinate sidecar paths are refused.
    match = re.fullmatch(r'([a-fA-F0-9]{' + str(length) + r'})(?:\s+\*?(\S+))?\s*', raw.decode('ascii'))
    relative = coordinate(item['coordinate']) + item['filename']
    if not match or (match[2] and match[2] not in (item['filename'], relative, '/maven2/' + relative)):
        raise ValueError('Unknown/cross-coordinate checksum format')
    return match[1].lower()


def acquire(requests, item):
    result = {'item': item, 'complete': False, 'requests': [], 'errors': []}
    try:
        published = requests.fetch(item['URL'], FILE_LIMIT); result['requests'].append(published)
        if published['HTTP_status'] != 200: raise ValueError('Publisher binary absent')
        body = read(published['path'], deadline=requests.deadline)
        hashes = {'sha256': sha(body), 'sha1': hashlib.sha1(body).hexdigest(), 'sha512': hashlib.sha512(body).hexdigest(), 'md5': hashlib.md5(body).hexdigest()}
        if item['declared_size'] is not None and len(body) != item['declared_size']: raise ValueError('Module size mismatch')
        for algorithm, expected in item['declared_hashes'].items():
            if algorithm not in hashes or hashes[algorithm] != expected: raise ValueError('Module hash mismatch')
        checks = {}
        for algorithm in ('sha256', 'sha1'):
            response = requests.fetch(item['URL'] + '.' + algorithm, 4096); result['requests'].append(response)
            if response['HTTP_status'] == 404:
                checks[algorithm] = {'available': False, 'actual_404_retained': True}; continue
            expected = checksum(read(response['path'], 4096, requests.deadline), algorithm, item)
            if expected != hashes[algorithm]: raise ValueError('Publisher sidecar mismatch')
            checks[algorithm] = {'available': True, 'matches': True, 'value': expected}
        if not any(c.get('matches') for c in checks.values()): raise ValueError('No publisher checksum available')
        if item['coordinate']['group'] == 'com.google.guava' and item['coordinate']['name'] == 'guava' and not checks['sha1'].get('matches'):
            raise ValueError('Guava module has no size/hash; authenticated binary SHA1 required')
        result['publisher_checksums'] = checks; result['publisher_body'] = record(Path(published['path']), requests.deadline)
        result['ZIP_readback'] = zip_check(published['path'], requests.deadline)
        result['complete'] = True
    except BaseException as error: result['errors'].append({'type': type(error).__name__, 'message': str(error)})
    return result


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--plan', required=True, type=Path)
    parser.add_argument('--plan-sha256', required=True); parser.add_argument('--output', type=Path)
    parser.add_argument('--validate-only', action='store_true'); args = parser.parse_args(); started = time.monotonic()
    raw = read(args.plan, 4 * 1024**2)
    if sha(raw) != args.plan_sha256: raise ValueError('Independent plan fence mismatch')
    plan = json.loads(raw)
    for fence in plan['input_fences']:
        actual = record(Path(fence['path']), started + WORK_SECONDS)
        if any(actual[k] != fence[k] for k in ('bytes', 'sha256')): raise ValueError('Source fence mismatch: ' + fence['path'])
    facts = json.loads(read(plan['facts_path'], 2 * 1024**2)); graph = json.loads(read(plan['current_graph_path'], 4 * 1024**2))
    items, excluded, proofs = derive_items(facts, graph)
    if plan['items'] != items or plan['excluded_components'] != excluded: raise ValueError('Plan differs from exact supported contracts')
    if args.validate_only:
        print(json.dumps({'status': 'READ_ONLY_PLAN_BINDINGS_MATCH', 'unique_binaries': len(items), 'network_calls': 0,
                          'cache_writes': 0, 'complete_selected_tooling_graph': False})); return
    output = args.output
    if (output is None or not output.is_absolute() or output.resolve() != output or output.parent != OUTPUT_PARENT
            or not output.name.startswith('lint32-selected-publisher-binaries')): raise ValueError('Fresh private output scope')
    output.mkdir(mode=0o700, exist_ok=False); requests = Requests(output, started); results = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = [executor.submit(acquire, requests, item) for item in items]
        for future in as_completed(futures):
            result = future.result(); results.append(result); save(output / ('item-' + str(len(results)).zfill(3) + '.json'), result)
    complete = len(results) == len(items) and all(r['complete'] for r in results)
    save(output / 'readback.json', {'kind': 'actual_publisher_binary_acquisition_only', 'recorded_utc': utc(),
         'plan': record(args.plan), 'status': 'PUBLISHER_BYTES_VERIFIED_PENDING_ROOT_CACHE_AND_GRADLE' if complete else 'INCOMPLETE_OR_MISMATCH',
         'planned_files': len(items), 'verified_files': sum(r['complete'] for r in results), 'actual_requests': requests.number,
         'retained_body_bytes': requests.total, 'work_deadline_seconds': WORK_SECONDS, 'separate_reap_margin_seconds': REAP_SECONDS,
         'actual_seconds': time.monotonic() - started, 'Gradle_cache_writes': 0, 'complete_selected_tooling_graph': False,
         'full_Gradle_artifact_set_comparison': 'pending', 'lint_AAB_license_release_acceptance': False})
    if not complete: raise SystemExit(1)


if __name__ == '__main__': main()
