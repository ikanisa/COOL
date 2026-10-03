#!/usr/bin/env python3
"""Public publisher metadata and exact-source export for scoped Linux format QA."""
import concurrent.futures
import datetime
import gzip
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = pathlib.Path(__file__).resolve().parent / sys.argv[1]
OUT.mkdir(exist_ok=False)
PRIVATE = pathlib.Path('/Volumes/PRO-G40/Temporary') / (
    'collect-arc01-ubuntu-20261002-' + uuid.uuid4().hex[:12])
PRIVATE.mkdir(parents=True, exist_ok=False)
CHECKOUT = PRIVATE / 'checkout'
CHECKOUT.mkdir()
SDK_BASE = 'https://storage.googleapis.com/dart-archive/channels/stable/release/3.12.2/'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def fetch(url, headers=None):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}),
                                timeout=25) as response:
        body = response.read(4 * 1024 * 1024 + 1)
        assert len(body) <= 4 * 1024 * 1024
        return body, {'url': url, 'final_url': response.url,
                      'status': response.status, 'headers': dict(response.headers),
                      'sha256': hashlib.sha256(body).hexdigest()}


def sdk_metadata():
    result = {}
    for name, suffix in [('dart-version', 'VERSION'),
                         ('dart-sdk-sha256', 'sdk/dartsdk-linux-arm64-release.zip.sha256sum')]:
        body, metadata = fetch(SDK_BASE + suffix)
        (OUT / (name + '.response')).write_bytes(body)
        result[name] = metadata
    return result


def ubuntu_metadata():
    # Anonymous public registry access token is kept in memory only.
    auth_url = 'https://auth.docker.io/token?' + urllib.parse.urlencode({
        'service': 'registry.docker.io', 'scope': 'repository:library/ubuntu:pull'})
    token = json.loads(fetch(auth_url)[0])['token']
    headers = {'Authorization': 'Bearer ' + token,
               'Accept': 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'}
    body, metadata = fetch('https://registry-1.docker.io/v2/library/ubuntu/manifests/24.04', headers)
    (OUT / 'ubuntu24.04-index.response').write_bytes(body)
    index = json.loads(body)
    digest = 'sha256:' + hashlib.sha256(body).hexdigest()
    assert metadata['headers'].get('docker-content-digest', metadata['headers'].get('Docker-Content-Digest')) == digest
    arm = [entry for entry in index['manifests'] if entry.get('platform', {}).get('os') == 'linux'
           and entry.get('platform', {}).get('architecture') == 'arm64']
    assert len(arm) == 1
    headers['Accept'] = 'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
    arm_body, arm_metadata = fetch('https://registry-1.docker.io/v2/library/ubuntu/manifests/' + arm[0]['digest'], headers)
    assert 'sha256:' + hashlib.sha256(arm_body).hexdigest() == arm[0]['digest']
    (OUT / 'ubuntu24.04-arm64-manifest.response').write_bytes(arm_body)
    return {'official_repository': 'docker.io/library/ubuntu', 'tag_observed': '24.04',
            'index_digest': digest, 'arm64_manifest_digest': arm[0]['digest'],
            'config_digest': json.loads(arm_body)['config']['digest'],
            'index_response': metadata, 'arm64_response': arm_metadata}


write('private-boundary.json', {'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
      'private_root': str(PRIVATE), 'private_checkout': str(CHECKOUT),
      'root_checkout': str(ROOT), 'copies_root_git_or_cache_or_env_or_credentials': False})
try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        sdk_future = pool.submit(sdk_metadata)
        ubuntu_future = pool.submit(ubuntu_metadata)
        publisher = {'dart': sdk_future.result(), 'ubuntu': ubuntu_future.result()}
    write('publisher-metadata.json', publisher)
    version = json.loads((OUT / 'dart-version.response').read_text())
    assert version['version'] == '3.12.2'
    checksum = (OUT / 'dart-sdk-sha256.response').read_text().split()[0]
    assert len(checksum) == 64 and all(c in '0123456789abcdef' for c in checksum)
    raw = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others',
                                  '--exclude-standard', '--', '*.dart'], cwd=ROOT)
    with gzip.open(OUT / 'original-git-dart-inventory.nul.gz', 'wb') as stream:
        stream.write(raw)
    visible = sorted(set(raw.decode().rstrip('\0').split('\0')))
    existing = [key for key in visible if (ROOT / key).is_file()]
    non_docs = [key for key in existing if not key.startswith('docs/release/')]
    upstream = json.loads((ROOT / 'third_party/gotrue/UPSTREAM-SHA256.json').read_text())
    hashes = {key: sha(ROOT / key) for key in non_docs}
    upstream_exclusions = [key for key in non_docs if key.startswith('third_party/gotrue/')
        and upstream.get(key.removeprefix('third_party/gotrue/')) == hashes[key]]
    applicable = sorted(set(non_docs) - set(upstream_exclusions))
    configs = ['Makefile', 'scripts/qa/dart_format.rb', '.github/workflows/ci.yml',
               '.gitignore', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
               'third_party/gotrue/UPSTREAM-SHA256.json', 'third_party/gotrue/pubspec.yaml',
               'third_party/file_saver/pubspec.yaml']
    # Preserve any nearer package/language/style declarations used by formatter.
    for key in non_docs:
        parent = (ROOT / key).parent
        while parent != ROOT:
            for filename in ('pubspec.yaml', 'analysis_options.yaml'):
                if (parent / filename).is_file():
                    configs.append(str((parent / filename).relative_to(ROOT)))
            parent = parent.parent
    source = sorted(set(non_docs + configs))
    assert not any(not (ROOT / key).resolve().is_relative_to(ROOT) for key in source)
    before = {key: sha(ROOT / key) for key in source}
    write('root-inputs-before.json', before)
    for key in source:
        destination = CHECKOUT / key
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / key, destination)
        assert sha(destination) == before[key]
    after = {key: sha(ROOT / key) for key in source}
    assert after == before, 'Root source changed during strict export'
    write('root-inputs-after-export.json', after)
    write('source-inventory.json', {'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'git_visible_dart_paths': len(visible), 'existing_dart_paths': len(existing),
        'docs_snapshot_paths_excluded_by_actual_script': len(existing) - len(non_docs),
        'copied_non_docs_dart_paths': len(non_docs), 'hash_identical_upstream_exclusions': upstream_exclusions,
        'applicable_formatter_paths': applicable, 'copied_input_sha256': before,
        'root_symlinks': [key for key in source if (ROOT / key).is_symlink()],
        'private_copy_sha256': {key: sha(CHECKOUT / key) for key in source}})
    write('execution-plan.json', {'sdk_version': version, 'dart_zip_url': SDK_BASE + 'sdk/dartsdk-linux-arm64-release.zip',
        'dart_zip_expected_sha256': checksum, 'ubuntu_base': 'ubuntu@' + publisher['ubuntu']['arm64_manifest_digest'],
        'private_root': str(PRIVATE), 'checkout': str(CHECKOUT), 'applicable_dart_count': len(applicable),
        'source_inputs': len(source)})
    print(json.dumps({'metadata_authenticated': True, 'private_root': str(PRIVATE),
                     'applicable_dart_count': len(applicable), 'source_inputs': len(source)}, indent=2))
except Exception as error:
    write('preparation-failure.json', {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'type': type(error).__name__, 'error': str(error), 'private_root': str(PRIVATE)})
    raise
