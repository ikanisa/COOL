"""Prepare exact public dependencies and preserved synthetic bytes for a probe.

This is not a deployment installer. No npm installation scripts run. Archives
are checksum verified; only named regular files are read from them. The output
directory must be new. No application database or configuration is modified.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent

def sha(data):
    return hashlib.sha256(data).hexdigest()

def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(data)

def prepare(target, archive_directory):
    target = target.absolute()
    if target.exists() or target.parent.resolve(strict=True) != target.parent:
        raise ValueError('Fresh physical prepared directory required')
    os.umask(0o077)
    target.mkdir(mode=0o700)
    lock = json.loads((HERE / 'dependencies.lock.json').read_text())
    receipts, selected = [], {}
    for package in lock['packages']:
        url = package['tarball_url']
        if not url.startswith('https://registry.npmjs.org/') or '?' in url or '#' in url:
            raise ValueError('Only pinned public npm archive URLs are accepted')
        cached = archive_directory / (package['sha256'] + '.tgz') if archive_directory else None
        if cached and cached.is_file():
            data = cached.read_bytes()
        else:
            request = urllib.request.Request(url, headers={'User-Agent': 'Collect-Synthetic-Dependency-Probe/1'})
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.geturl() != url:
                    raise ValueError('Archive URL redirected outside its pinned identity')
                data = response.read(package['bytes'] + 1)
        integrity = 'sha512-' + base64.b64encode(hashlib.sha512(data).digest()).decode()
        if len(data) != package['bytes'] or sha(data) != package['sha256'] or integrity != package['integrity']:
            raise ValueError('Pinned archive byte identity refused')
        write(target / 'archives' / (package['sha256'] + '.tgz'), data)
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            def member(name):
                item = archive.getmember('package/' + name)
                if not item.isfile() or item.size > 40 * 1024 * 1024:
                    raise ValueError('Expected bounded regular package member')
                stream = archive.extractfile(item)
                if stream is None:
                    raise ValueError('Package member missing')
                return stream.read()
            metadata = json.loads(member('package.json'))
            if metadata['name'] != package['name'] or metadata['version'] != package['version']:
                raise ValueError('Package metadata identity refused')
            names = {
                '@imagemagick/magick-wasm': ('image', 'dist/index.js', 'dist/x86/magick.wasm'),
                '@hyzyla/pdfium': ('pdfium', 'dist/index.esm.browser.js', 'dist/pdfium.wasm'),
                '@neslinesli93/qpdf-wasm': ('qpdf', 'dist/qpdf.js', 'dist/qpdf.wasm'),
            }
            files = {}
            if package['name'] in names:
                service, javascript, wasm = names[package['name']]
                original = member(javascript)
                files = {javascript: sha(original), wasm: sha(member(wasm))}
                if service == 'qpdf':
                    adapted = (HERE / 'qpdf-prefix.js.in').read_bytes() + original + (HERE / 'qpdf-suffix.js.in').read_bytes()
                    if adapted.count(original) != 1:
                        raise ValueError('Original qpdf JavaScript bytes must remain complete and unchanged')
                    write(target / service / 'vendor/original-qpdf.cjs', original)
                else:
                    adapted = original
                write(target / service / 'vendor/parser.js', adapted)
                write(target / service / 'vendor/parser.wasm', member(wasm))
                selected[service] = package['name'] + '@' + package['version']
                write(target / service / 'index.ts', (HERE / (service + '.ts')).read_bytes())
        receipts.append({**package, 'archive_sha512_verified': True, 'selected_original_members': files})
    shutil.copytree(HERE / 'corpus', target / 'corpus')
    provenance = json.loads((HERE / 'corpus-provenance.json').read_text())
    for item in provenance['files']:
        data = (target / 'corpus' / item['path']).read_bytes()
        if sha(data) != item['sha256'] or len(data) != item['bytes']:
            raise ValueError('Preserved synthetic corpus identity refused')
    main = (HERE / 'main.ts.in').read_text()
    if main.count('__PREPARED_ROOT_JSON__') != 1:
        raise ValueError('Exact probe root placeholder required')
    write(target / 'main/index.ts', main.replace('__PREPARED_ROOT_JSON__', json.dumps(str(target))).encode())
    inputs = sorted(({'path': str(p.relative_to(HERE)), 'sha256': sha(p.read_bytes())}
                     for p in HERE.rglob('*') if p.is_file() and '__pycache__' not in p.parts),
                    key=lambda item: item['path'])
    receipt = {'contract': 'collect.roster.native-probe.prepared.v1', 'synthetic_only': True,
               'parser_contract_qualified': False, 'production_acceptance': False,
               'packages': receipts, 'selected_services': selected, 'source_inputs': inputs,
               'corpus_provenance_sha256': sha((HERE / 'corpus-provenance.json').read_bytes())}
    write(target / 'prepared.json', (json.dumps(receipt, indent=2) + '\n').encode())
    return {'prepared': True, 'services': len(selected), 'archives_verified': len(receipts),
            'corpus_files': len(provenance['files']), 'production_acceptance': False}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--archive-directory', type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.directory, args.archive_directory), sort_keys=True))
