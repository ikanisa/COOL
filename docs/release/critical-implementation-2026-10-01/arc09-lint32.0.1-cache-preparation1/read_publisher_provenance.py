#!/usr/bin/env python3
"""Proposed bounded public readback; never writes Gradle caches or grants acceptance."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile

ROOTS = ('https://dl.google.com/dl/android/maven2/', 'https://repo.maven.apache.org/maven2/')
CACHE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/gradle-home/caches/modules-2/files-2.1')
FIXED = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*\Z')
TOTAL_BODY_LIMIT = 512 * 1024**2
ARTIFACT_LIMIT = 128 * 1024**2


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(path, value):
    with path.open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True); out.write('\n')
        out.flush(); os.fsync(out.fileno())


def identity(row):
    return row.st_dev, row.st_ino, row.st_size, row.st_mode, row.st_mtime_ns, row.st_ctime_ns


def file_hash(path, limit=ARTIFACT_LIMIT, deadline=None):
    if path.resolve() != path: raise ValueError('Nonphysical named input')
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > limit:
        raise ValueError('Special or oversized input')
    hashes = {'sha256': hashlib.sha256(), 'sha1': hashlib.sha1()}
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as source:
        if identity(os.fstat(source.fileno())) != identity(before): raise ValueError('Input raced before open')
        for chunk in iter(lambda: source.read(1024**2), b''):
            if deadline is not None and time.monotonic() >= deadline: raise TimeoutError('Whole publisher readback deadline')
            for value in hashes.values(): value.update(chunk)
        if identity(os.fstat(source.fileno())) != identity(before): raise ValueError('Input FD changed')
        if identity(path.lstat()) != identity(before): raise ValueError('Input named path replaced')
    return {'bytes': before.st_size, **{name: value.hexdigest() for name, value in hashes.items()}}


def coordinate(row):
    group, name, version = (row[key] for key in ('group', 'name', 'version'))
    if not all(re.fullmatch(r'[A-Za-z0-9_-]+', segment) for segment in group.split('.')):
        raise ValueError('Invalid group path')
    for value in (name, version):
        if not FIXED.fullmatch(value): raise ValueError('Invalid or dynamic coordinate')
    if 'SNAPSHOT' in version.upper() or version.lower().startswith('latest.'):
        raise ValueError('Nonfixed version refused')
    extension = row.get('extension', 'pom')
    if not re.fullmatch(r'[A-Za-z0-9]+', extension): raise ValueError('Invalid extension')
    classifier = row.get('classifier')
    if classifier is not None and not FIXED.fullmatch(classifier): raise ValueError('Invalid classifier')
    filename = name + '-' + version + (('-' + classifier) if classifier else '') + '.' + extension
    return group.replace('.', '/') + '/' + name + '/' + version + '/' + filename


def pom_coordinate(path):
    body = path.read_bytes()
    if b'<!DOCTYPE' in body.upper() or b'<!ENTITY' in body.upper(): raise ValueError('POM entities/doctype refused')
    root = ET.fromstring(body)
    ns = '{' + root.tag.partition('}')[0][1:] + '}' if root.tag.startswith('{') else ''
    def text(node, name):
        found = node.find(ns + name) if node is not None else None
        return found.text.strip() if found is not None and found.text else None
    parent = root.find(ns + 'parent')
    raw = {'group': text(root, 'groupId') or text(parent, 'groupId'),
           'name': text(root, 'artifactId'), 'version': text(root, 'version') or text(parent, 'version')}
    properties = root.find(ns + 'properties')
    props = {} if properties is None else {node.tag.rsplit('}', 1)[-1]: (node.text or '').strip() for node in properties}
    for key, suffix in [('group', 'groupId'), ('name', 'artifactId'), ('version', 'version')]:
        if raw[key] is not None:
            props['project.' + suffix] = raw[key]; props['pom.' + suffix] = raw[key]
    token = re.compile(r'\$\{([^}]+)\}')
    for _ in range(8):
        changed = {key: token.sub(lambda match: props.get(match[1], match[0]), value)
                   for key, value in props.items()}
        if changed == props: break
        props = changed
    result = {key: None if value is None else token.sub(lambda match: props.get(match[1], match[0]), value)
              for key, value in raw.items()}
    if any(value is None or '${' in value for value in result.values()):
        raise ValueError('POM coordinate inheritance/property binding unknown')
    return result


def zip_readback(path, deadline):
    members = expanded = 0
    with zipfile.ZipFile(path) as archive:
        if len(archive.infolist()) > 100000: raise ValueError('JAR member bound exceeded')
        for info in archive.infolist():
            if time.monotonic() >= deadline: raise TimeoutError('Whole publisher readback deadline')
            expanded += info.file_size
            if expanded > 2 * 1024**3: raise ValueError('JAR expanded-byte bound exceeded')
            with archive.open(info) as stream:
                while stream.read(1024**2):
                    if time.monotonic() >= deadline: raise TimeoutError('JAR readback deadline')
            members += 1
    return {'members': members, 'expanded_bytes': expanded, 'CRC_readback_complete': True}


class Requests:
    def __init__(self, output):
        self.output = output; self.started = time.monotonic(); self.deadline = self.started + 180
        self.lock = threading.Lock(); self.number = self.body_total = 0

    def fetch(self, url, limit):
        if not any(url.startswith(root) for root in ROOTS): raise ValueError('URL outside official repository scope')
        remaining = self.deadline - time.monotonic()
        if remaining <= 0: raise TimeoutError('Whole publisher readback deadline')
        with self.lock:
            self.number += 1
            if self.number > 1600: raise ValueError('Public request count bound exceeded')
            directory = self.output / ('request-' + str(self.number).zfill(4))
            directory.mkdir(mode=0o700)
        argv = ['/usr/bin/curl', '--disable', '--silent', '--show-error', '--proto', '=https',
                '--proto-redir', '=https', '--tlsv1.2', '--connect-timeout', '10',
                '--max-time', str(min(30, remaining)), '--max-filesize', str(limit),
                '--dump-header', str(directory / 'response.headers'), '--output', str(directory / 'response.body'),
                '--write-out', '%{json}', url]
        receipt = {'requested_url': url, 'argv': argv, 'started_utc': now(),
                   'redirect_following': False, 'automatic_retries': False,
                   'credentials_or_inherited_proxy_environment': False}
        save(directory / 'request.json', receipt)
        with (directory / 'curl.metadata').open('xb') as metadata, (directory / 'curl.stderr').open('xb') as stderr:
            process = subprocess.Popen(argv, stdout=metadata, stderr=stderr,
                                       env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
            try: receipt['exit_code'] = process.wait(timeout=min(30, remaining) + 2)
            except subprocess.TimeoutExpired:
                process.kill(); receipt['exit_code'] = process.wait(); receipt['controller_timeout'] = True
        metadata_raw = (directory / 'curl.metadata').read_bytes()
        try: details = json.loads(metadata_raw)
        except ValueError: details = None
        receipt['curl_metadata'] = details
        receipt['finished_utc'] = now()
        receipt['files'] = {path.name: file_hash(path, limit if path.name == 'response.body' else 4 * 1024**2)
                            for path in directory.iterdir() if path.is_file()}
        body = directory / 'response.body'
        length = body.stat().st_size if body.exists() else 0
        with self.lock:
            self.body_total += length
            receipt['cumulative_body_bytes'] = self.body_total
        receipt['transport_identity_ok'] = bool(receipt['exit_code'] == 0 and details
            and details.get('ssl_verify_result') == 0 and details.get('url_effective') == url
            and details.get('scheme', '').lower() == 'https')
        save(directory / 'receipt.json', receipt)
        if self.body_total > TOTAL_BODY_LIMIT: raise ValueError('Total public retained body byte bound exceeded')
        if not receipt['transport_identity_ok']: raise ValueError('Public TLS/URL/transport evidence incomplete: ' + str(directory))
        code = details.get('http_code', details.get('response_code'))
        if code not in (200, 404): raise ValueError('Unexpected public HTTP status: ' + str(code))
        return {'request_directory': str(directory), 'url': url, 'http_status': code,
                'body': str(body), 'receipt_sha256': file_hash(directory / 'receipt.json')['sha256']}


def verify_item(requests, item, kind):
    result = {'kind': kind, 'coordinate': {key: item[key] for key in ('group', 'name', 'version')},
              'cached_input': item, 'requests': [], 'complete': False, 'errors': []}
    try:
        if time.monotonic() >= requests.deadline: raise TimeoutError('Whole publisher readback deadline')
        cached = Path(item['path'])
        if not cached.is_relative_to(CACHE): raise ValueError('Input outside the pinned private module cache')
        observed = file_hash(cached, deadline=requests.deadline)
        if any(observed[key] != item[key] for key in ('bytes', 'sha256', 'sha1')): raise ValueError('Captured cache artifact changed')
        relative = coordinate(item)
        published = None
        for root in ROOTS:
            request = requests.fetch(root + relative, 4 * 1024**2 if kind == 'pom' else ARTIFACT_LIMIT)
            result['requests'].append(request)
            if request['http_status'] == 200:
                published = request; break
        if published is None: raise ValueError('No public artifact at either allowed repository')
        body = Path(published['body'])
        publisher_hashes = file_hash(body, deadline=requests.deadline)
        if any(publisher_hashes[key] != observed[key] for key in ('bytes', 'sha256', 'sha1')):
            raise ValueError('Publisher bytes do not equal exact selected cached bytes')
        result['publisher_body'] = publisher_hashes; result['publisher_url'] = published['url']
        checksums = {}
        for algorithm, length in [('sha256', 64), ('sha1', 40)]:
            request = requests.fetch(published['url'] + '.' + algorithm, 4096)
            result['requests'].append(request)
            if request['http_status'] == 404:
                checksums[algorithm] = {'available': False, 'actual_HTTP_404_retained': True}; continue
            text = Path(request['body']).read_text(encoding='ascii').strip()
            match = re.fullmatch(r'([a-fA-F0-9]{' + str(length) + r'})(?:\s+\*?([^\s]+))?', text)
            if match is None or (match[2] and match[2] != relative.rsplit('/', 1)[-1]):
                raise ValueError('Unknown publisher checksum format/name')
            if match[1].lower() != observed[algorithm]: raise ValueError('Publisher checksum mismatch')
            checksums[algorithm] = {'available': True, 'matches': True, 'value': match[1].lower()}
        result['publisher_checksums'] = checksums
        if not any(row.get('matches') for row in checksums.values()): raise ValueError('No publisher checksum available')
        result['checksum_strength'] = 'published-sha256-and-computed-byte-binding' if checksums['sha256'].get('matches') else 'published-sha1-only-with-TLS-and-computed-SHA256-byte-binding'
        if kind == 'pom':
            result['actual_POM_coordinate'] = pom_coordinate(body)
            if result['actual_POM_coordinate'] != result['coordinate']: raise ValueError('POM coordinate mismatch')
        elif item.get('extension') == 'jar': result['JAR_readback'] = zip_readback(body, requests.deadline)
        after = file_hash(cached, deadline=requests.deadline)
        if after != observed: raise ValueError('Cached input changed during publisher readback')
        result['complete'] = True
    except BaseException as error:
        result['errors'].append({'type': type(error).__name__, 'error': str(error)})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--graph', required=True, type=Path)
    parser.add_argument('--graph-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    graph_hash = file_hash(args.graph, 32 * 1024**2)
    if graph_hash['sha256'] != args.graph_sha256: raise ValueError('Exact selected graph changed')
    graph = json.loads(args.graph.read_bytes())
    if (graph.get('root_requested') != 'com.android.tools.lint:lint-gradle:32.0.1'
            or graph.get('repository_scope') != list(ROOTS)
            or graph.get('complete_selected_tooling_graph') is not True or graph.get('errors')):
        raise ValueError('Incomplete or different selected tooling graph')
    if len(graph['components']) > 160 or len(graph['artifacts']) > 192 or len(graph['edges']) > 1024:
        raise ValueError('Captured selected graph bounds exceeded')
    modules = {(row['group'], row['name'], row['version']) for row in graph['components'] if row['kind'] == 'module'}
    poms = {(row['group'], row['name'], row['version']) for row in graph['poms']}
    if modules != poms or len(poms) != len(graph['poms']): raise ValueError('Selected module/POM coverage differs')
    if sum(row['bytes'] for row in graph['artifacts'] + graph['poms']) > TOTAL_BODY_LIMIT:
        raise ValueError('Exact selected input byte bound exceeded')
    output = args.output
    if not output.is_absolute() or output.resolve() != output: raise ValueError('Nonphysical output')
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    requests = Requests(output)
    plan = [('artifact', row) for row in graph['artifacts']] + [('pom', row) for row in graph['poms']]
    results = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(verify_item, requests, row, kind): (kind, row) for kind, row in plan}
        for future in as_completed(futures):
            result = future.result(); results.append(result)
            save(output / ('item-' + str(len(results)).zfill(4) + '.json'), result)
    complete = len(results) == len(plan) and all(row['complete'] for row in results)
    save(output / 'readback.json', {'schema_version': 1, 'captured_at_utc': now(),
        'status': 'MECHANICAL_READBACK_COMPLETE' if complete else 'INCOMPLETE_OR_MISMATCH',
        'graph': {'path': str(args.graph), **graph_hash}, 'root_requested': graph['root_requested'],
        'declared_repository_scope': list(ROOTS), 'selected_graph_counts': graph['counts'],
        'planned_items': len(plan), 'completed_items': sum(row['complete'] for row in results),
        'actual_requests': requests.number, 'retained_body_bytes': requests.body_total,
        'published_SHA256_missing_items': sum(not row.get('publisher_checksums', {}).get('sha256', {}).get('available', False) for row in results),
        'public_request_and_item_work_deadline_seconds': 180,
        'bounded_inflight_curl_reap_margin_seconds': 2,
        'actual_seconds': round(time.monotonic() - requests.started, 3),
        'per_request_seconds_at_most': 30,
        'concurrency': 4, 'automatic_retries': False, 'credential_use': False,
        'Gradle_cache_writes_in_this_phase': False, 'Gradle_module_metadata_lineage_proved': False,
        'complete_packaged_SBOM': False, 'licence_security_or_owner_acceptance': False,
        'AAB_built': False, 'production_release_approval': False})
    return 0 if complete else 1


if __name__ == '__main__':
    raise SystemExit(main())
