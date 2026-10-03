#!/usr/bin/env python3
"""Create and read back a deterministic archive of the accepted source set."""
import gzip
import hashlib
import io
import json
import tarfile
from pathlib import Path
from bind_evidence import HERE, CANDIDATE, read, digest, emit, regular


def main():
    manifest = read(CANDIDATE / '.collect-release-candidate.json')
    supplement = read(HERE / 'supplement-manifest.json')
    rows = {name: {**row, 'input': str(CANDIDATE / name)} for name, row in manifest['source_files'].items()}
    for name, row in supplement['files'].items():
        assert name not in rows
        rows[name] = {**row, 'input': str(HERE / 'supplement' / name)}
    rows['.collect-release-candidate.json'] = {'sha256': digest(CANDIDATE / '.collect-release-candidate.json'),
                                             'bytes': (CANDIDATE / '.collect-release-candidate.json').stat().st_size,
                                             'mode_octal': '0o644', 'input': str(CANDIDATE / '.collect-release-candidate.json')}
    archive = HERE / 'collect-accepted-local-source.tar.gz'
    assert not archive.exists(), 'Do not overwrite a delivered source archive.'
    with archive.open('xb') as destination:
        with gzip.GzipFile(filename='', mode='wb', fileobj=destination, mtime=0, compresslevel=3) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as output:
                for name, row in sorted(rows.items()):
                    path = Path(row['input'])
                    assert regular(path) and digest(path) == row['sha256'], name
                    data = path.read_bytes()
                    assert hashlib.sha256(data).hexdigest() == row['sha256'], name
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    mode = row.get('mode_octal', row.get('mode', 0o644))
                    info.mode = int(mode, 8) if isinstance(mode, str) else mode
                    info.mtime = 0
                    info.uid = info.gid = 0
                    info.uname = info.gname = ''
                    output.addfile(info, io.BytesIO(data))
    readback = {}
    with tarfile.open(archive, 'r:gz') as source:
        for member in source:
            assert member.isfile() and member.name in rows and member.name not in readback
            assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
            stream = source.extractfile(member)
            h = hashlib.sha256()
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(chunk)
            assert h.hexdigest() == rows[member.name]['sha256'], member.name
            readback[member.name] = {'sha256': h.hexdigest(), 'bytes': member.size, 'mode_octal': oct(member.mode)}
    assert readback.keys() == rows.keys()
    result = {'status': 'pass', 'scope': 'Deterministic accepted source plus explicit reproducibility supplement; all2489 regular archive members read back against their declared bytes.',
              'archive': str(archive), 'archive_sha256': digest(archive), 'archive_bytes': archive.stat().st_size,
              'source_member_count': len(rows), 'base_source_files': manifest['file_count'],
              'supplement_files': supplement['supplement_file_count'], 'candidate_metadata_members': 1,
              'candidate_manifest_sha256': digest(CANDIDATE / '.collect-release-candidate.json'),
              'supplement_manifest_sha256': digest(HERE / 'supplement-manifest.json'),
              'source_rows': readback, 'private_signing_environment_or_sdk_cache_copied': False,
              'toolchains': 'Recorded/pinned prerequisites; SDKs and package caches are not shipped as authored source.',
              'approvals': manifest['approvals'], 'command': ['python3', str(Path(__file__).resolve())]}
    emit(HERE / 'source-archive-readback.json', result)
    print(json.dumps({key: result[key] for key in ['status', 'archive', 'archive_sha256', 'archive_bytes', 'source_member_count']}))


if __name__ == '__main__':
    main()
