#!/usr/bin/env python3
"""Seal or verify exact postprocessed Cloudflare Admin candidate bytes.

Usage: admin_cloudflare_artifact.py record|verify BUILD_ROOT SOURCE_JSON ARTIFACT_JSON

The artifact manifest must be outside BUILD_ROOT. Verification is local and
read-only; a consistent seal establishes no hosted, role, provider, migration,
recovery, device, or production acceptance. It performs no builds or deployment.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import sys

from admin_cloudflare_source import (
    SourceError, SHA256, canonical, parse_json, physical_path, read_json, relative_path,
    validate_source_manifest, write_json,
)


CANDIDATE_STATUS = 'candidate_requires_hosted_acceptance'
SCHEMA_VERSION = 1
FIELDS = {
    'schema_version', 'files', 'source_commit', 'source_dirty', 'source_manifest_sha256',
    'main_dart_js_sha256', 'version_json_sha256', 'minimum_core_schema_migration',
    'source_release_status', 'hosted_acceptance_verified', 'artifact_manifest_sha256',
}


class ArtifactError(ValueError):
    pass


def _locations(build_root, source_manifest, artifact_manifest):
    if '..' in Path(build_root).parts or '..' in Path(artifact_manifest).parts:
        raise ArtifactError('Build and artifact paths must not contain parent traversal')
    build = physical_path(build_root, directory=True)
    source_path = physical_path(source_manifest)
    artifact_path = physical_path(artifact_manifest, allow_missing=True)
    if artifact_path.is_relative_to(build) or artifact_path == source_path:
        raise ArtifactError('Artifact manifest must be outside the build and distinct from source manifest')
    return build, source_path, artifact_path


def _files(build):
    paths = []

    def on_error(error):
        raise ArtifactError('Cannot inspect the complete Admin output bundle') from error

    # Unlike source inventory, output inventory has no ignored files. Any extra
    # bytes copied into this bundle would be deployed and must enter the seal.
    for folder, directories, names in os.walk(build, followlinks=False, onerror=on_error):
        parent = Path(folder)
        for name in directories:
            physical_path(parent / name, directory=True)
        for name in names:
            paths.append(physical_path(parent / name))
    rows = []
    for path in sorted(paths, key=lambda path: path.relative_to(build).as_posix()):
        data = path.read_bytes()
        rows.append({'path': relative_path(path.relative_to(build).as_posix()),
                     'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    if not rows:
        raise ArtifactError('Admin output inventory is empty')
    return rows


def _candidate(build, source_path):
    source = validate_source_manifest(read_json(source_path))
    version_path = physical_path(build / 'version.json')
    main_path = physical_path(build / 'main.dart.js')
    main_bytes = main_path.read_bytes()
    if not main_bytes:
        raise ArtifactError('Admin main.dart.js is empty')
    main_digest = hashlib.sha256(main_bytes).hexdigest()
    version_bytes = version_path.read_bytes()
    version = parse_json(version_bytes)
    if not isinstance(version, dict) or version.get('backend') != 'cloudflare':
        raise ArtifactError('Admin candidate must identify the Cloudflare backend')
    for key in ('source_commit', 'source_dirty', 'source_manifest_sha256'):
        if version.get(key) != source[key] or (key == 'source_dirty' and type(version.get(key)) is not bool):
            raise ArtifactError('Admin version and frozen source identity disagree')
    if version.get('main_dart_js_sha256') != main_digest:
        raise ArtifactError('Admin main.dart.js bytes differ from version identity')
    if version.get('source_release_status') != CANDIDATE_STATUS or version.get('operational_migration_complete') is not False:
        raise ArtifactError('Artifact identity cannot grant hosted or production acceptance')
    migration = version.get('minimum_core_schema_migration')
    if not isinstance(migration, str) or not re.fullmatch(r'[0-9]{4}_[A-Za-z0-9_]+\.sql', migration):
        raise ArtifactError('Admin candidate minimum schema migration is invalid')
    if f'deploy/admin-api/migrations/{migration}' not in {row['path'] for row in source['files']}:
        raise ArtifactError('Admin candidate minimum migration is absent from its frozen source')
    # Control files are necessary for the artifact to be the completed output,
    # rather than just a main JS file and metadata supplied to this tool.
    for name in ('index.html', 'flutter_bootstrap.js', '_headers', 'robots.txt', 'assets/FontManifest.json',
                 'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json'):
        physical_path(build / name)
    rows = _files(build)
    by_path = {row['path']: row for row in rows}
    version_digest = hashlib.sha256(version_bytes).hexdigest()
    if by_path['main.dart.js']['sha256'] != main_digest or by_path['version.json']['sha256'] != version_digest:
        raise ArtifactError('Admin main/version bytes changed while preparing the artifact seal')
    return {
        'schema_version': SCHEMA_VERSION,
        'files': rows,
        'source_commit': source['source_commit'],
        'source_dirty': source['source_dirty'],
        'source_manifest_sha256': source['source_manifest_sha256'],
        'main_dart_js_sha256': main_digest,
        'version_json_sha256': version_digest,
        'minimum_core_schema_migration': migration,
        'source_release_status': CANDIDATE_STATUS,
        'hosted_acceptance_verified': False,
    }


def validate_artifact_manifest(value):
    if not isinstance(value, dict) or set(value) != FIELDS:
        raise ArtifactError('Stored Admin artifact manifest shape is invalid')
    if type(value['schema_version']) is not int or value['schema_version'] != SCHEMA_VERSION:
        raise ArtifactError('Stored Admin artifact schema version is invalid')
    if value['source_release_status'] != CANDIDATE_STATUS or value['hosted_acceptance_verified'] is not False:
        raise ArtifactError('Stored Admin artifact claims unsupported acceptance')
    if type(value['source_dirty']) is not bool or not isinstance(value['source_commit'], str) or not re.fullmatch(r'(?:[0-9a-f]{40}|[0-9a-f]{64})', value['source_commit']):
        raise ArtifactError('Stored Admin artifact source identity is invalid')
    for key in ('source_manifest_sha256', 'main_dart_js_sha256', 'version_json_sha256', 'artifact_manifest_sha256'):
        if not isinstance(value[key], str) or not SHA256.fullmatch(value[key]):
            raise ArtifactError('Stored Admin artifact hash is invalid')
    if not isinstance(value['minimum_core_schema_migration'], str) or not re.fullmatch(r'[0-9]{4}_[A-Za-z0-9_]+\.sql', value['minimum_core_schema_migration']):
        raise ArtifactError('Stored Admin artifact minimum schema is invalid')
    rows = value['files']
    if not isinstance(rows, list) or not rows:
        raise ArtifactError('Stored Admin artifact file inventory is empty or invalid')
    prior = None
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'path', 'sha256', 'bytes'}:
            raise ArtifactError('Stored Admin artifact file record is invalid')
        path = relative_path(row['path'])
        if prior is not None and path <= prior:
            raise ArtifactError('Stored Admin artifact files must be sorted and unique')
        prior = path
        if not isinstance(row['sha256'], str) or not SHA256.fullmatch(row['sha256']) or type(row['bytes']) is not int or row['bytes'] < 0:
            raise ArtifactError('Stored Admin artifact file facts are invalid')
    body = {key: item for key, item in value.items() if key != 'artifact_manifest_sha256'}
    if value['artifact_manifest_sha256'] != hashlib.sha256(canonical(body)).hexdigest():
        raise ArtifactError('Stored Admin artifact manifest digest is invalid')
    return value


def record_artifact(build_root, source_manifest, artifact_manifest):
    build, source_path, artifact_path = _locations(build_root, source_manifest, artifact_manifest)
    value = _candidate(build, source_path)
    value['artifact_manifest_sha256'] = hashlib.sha256(canonical(value)).hexdigest()
    validate_artifact_manifest(value)
    write_json(artifact_path, value)
    return value


def verify_artifact(build_root, source_manifest, artifact_manifest):
    build, source_path, artifact_path = _locations(build_root, source_manifest, artifact_manifest)
    recorded = validate_artifact_manifest(read_json(artifact_path))
    current = _candidate(build, source_path)
    current['artifact_manifest_sha256'] = hashlib.sha256(canonical(current)).hexdigest()
    if current != recorded:
        raise ArtifactError('Admin output bytes or source identity differ from the sealed candidate')
    return recorded


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('record', 'verify'))
    parser.add_argument('build_root', type=Path)
    parser.add_argument('source_manifest', type=Path)
    parser.add_argument('artifact_manifest', type=Path)
    arguments = parser.parse_args(argv)
    try:
        action = record_artifact if arguments.mode == 'record' else verify_artifact
        value = action(arguments.build_root, arguments.source_manifest, arguments.artifact_manifest)
    except (ArtifactError, SourceError, OSError) as error:
        print(f'Admin artifact identity refused: {error}', file=sys.stderr)
        return 1
    import json
    print(json.dumps({'status': 'pass', 'mode': arguments.mode, 'file_count': len(value['files']),
                      'artifact_manifest_sha256': value['artifact_manifest_sha256'],
                      'source_manifest_sha256': value['source_manifest_sha256'],
                      'source_release_status': value['source_release_status'],
                      'hosted_acceptance_verified': False}, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
