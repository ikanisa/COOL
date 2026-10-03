#!/usr/bin/env python3
"""Package the accepted unsigned artifacts and their declared evidence."""
import gzip
import hashlib
import io
import json
import tarfile
from pathlib import Path
from bind_evidence import ROOT, HERE, RAPID, NATIVE, read, digest, emit, regular


def main():
    packet = read(HERE / 'evidence-binding.json')
    assert packet['status'] == 'pass'
    assert read(HERE / 'register-reconciliation.json')['status'] == 'pass'
    rows = {}

    def add(path, name):
        path = Path(path)
        assert regular(path), path
        assert not Path(name).is_absolute() and '..' not in Path(name).parts
        row = {'input': str(path), 'sha256': digest(path), 'bytes': path.stat().st_size,
               'mode_octal': oct(path.stat().st_mode & 0o777)}
        if name in rows:
            assert rows[name]['sha256'] == row['sha256'], name
        rows[name] = row

    for row in packet['evidence'].values():
        if 'path' in row:
            add(ROOT / row['path'], 'evidence/' + row['path'])
    for name in packet['executed_commands_and_logs']:
        add(ROOT / name, 'evidence/' + name)
    for path in NATIVE.rglob('*'):
        if regular(path) and '__pycache__' not in path.parts:
            add(path, 'evidence/' + str(path.relative_to(ROOT)))
    for path in HERE.rglob('*'):
        if not regular(path) or 'supplement' in path.relative_to(HERE).parts or '__pycache__' in path.parts or path.name.endswith('.tar.gz') or path.name in ['delivery-archive-readback.json']:
            continue
        add(path, 'evidence/' + str(path.relative_to(ROOT)))
    for name in ['local-implementation-register-2026-09-30.json', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md',
                 'production-remaining-tasks-2026-09-30.json', 'PRODUCTION_REMAINING_TASKS_2026-09-30.md',
                 'production-remaining-tasks-2026-09-30.validation.json']:
        add(ROOT / 'docs/release' / name, 'evidence/docs/release/' + name)
    for family in ['production', 'gateway']:
        row = packet['native_artifacts'][family]
        add(row['artifact'], 'builds/android/' + Path(row['artifact']).name)
    ios = packet['native_artifacts']['ios']
    bundle = Path(ios['artifact'])
    bundle_manifest = read(NATIVE / 'ios/bundle-manifest.json')
    assert not bundle_manifest['symlinks'], 'Explicitly handle any nonregular bundle member before delivery.'
    for name in bundle_manifest['files']:
        add(bundle / name, 'builds/ios/Collect.app/' + name)
    for family, row in packet['browser_artifacts'].items():
        for name in row['files']:
            add(Path(row['path']) / name, 'builds/' + family + '/' + name)
    archive = HERE / 'collect-unsigned-builds-and-evidence.tar.gz'
    assert not archive.exists(), 'Do not overwrite delivered evidence.'
    with archive.open('xb') as destination:
        with gzip.GzipFile(filename='', mode='wb', fileobj=destination, mtime=0, compresslevel=3) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as output:
                for name, row in sorted(rows.items()):
                    path = Path(row['input'])
                    assert digest(path) == row['sha256'], name
                    info = tarfile.TarInfo(name)
                    info.size = row['bytes']
                    info.mode = int(row['mode_octal'], 8)
                    info.mtime = 0
                    info.uid = info.gid = 0
                    info.uname = info.gname = ''
                    with path.open('rb') as stream:
                        output.addfile(info, stream)
    seen = set()
    with tarfile.open(archive, 'r:gz') as source:
        for member in source:
            assert member.isfile() and member.name in rows and member.name not in seen
            stream = source.extractfile(member)
            h = hashlib.sha256()
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(block)
            assert h.hexdigest() == rows[member.name]['sha256'], member.name
            seen.add(member.name)
    assert seen == rows.keys()
    result = {'status': 'pass', 'archive': str(archive), 'sha256': digest(archive), 'bytes': archive.stat().st_size,
              'members': len(rows), 'every_member_read_back_and_hash_verified': True, 'rows': rows,
              'separate_source_archive': packet['source_archive']['archive'],
              'separate_source_archive_sha256': packet['source_archive']['archive_sha256'],
              'scope': 'Unsigned QA Android/Gateway/iOS, exact actual Admin/Public browser artifacts, canonical and previous registers, terminal and failed evidence receipts and named command logs. Authored source is the separately hash-bound source archive.',
              'deployment_signing_provider_device_store_or_owner_release_claim': False,
              'command': ['python3', str(Path(__file__).resolve())]}
    emit(HERE / 'delivery-archive-readback.json', result)
    print(json.dumps({key: result[key] for key in ['status', 'archive', 'sha256', 'bytes', 'members']}))


if __name__ == '__main__':
    main()
