#!/usr/bin/env python3
"""Extract only a complete publisher-authenticated archive into private containment."""
import json
from pathlib import Path, PurePosixPath
import posixpath
import subprocess
import tarfile

from run_owned import now, sha, write

OUT = Path(__file__).resolve().parent
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIVATE = Path(BOUNDARY['private_root'])
ATTEMPT = OUT / 'sdk-extraction-attempt1'
ATTEMPT.mkdir(exist_ok=False)
RUNTIME = PRIVATE / 'runtime'
RUNTIME.mkdir(exist_ok=False)
ARCHIVE = PRIVATE / 'flutter_linux_3.44.4-stable.tar.xz'
try:
    acquisition = json.loads((OUT / 'acquisition-attempt1/result.json').read_text())
    if acquisition['status'] != 'AUTHENTICATED_ACQUISITION_ONLY':
        raise RuntimeError('No complete authenticated acquisition')
    if ARCHIVE.stat().st_size != BOUNDARY['publisher_archive_bytes'] or sha(ARCHIVE) != BOUNDARY['publisher_archive_sha256']:
        raise RuntimeError('Archive changed after complete acquisition')
    metadata = []
    with tarfile.open(ARCHIVE, mode='r:xz') as bundle:
        members = bundle.getmembers()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'flutter':
                raise RuntimeError('Archive path outside exclusive Flutter root')
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise RuntimeError('Archive contains unexpected device or special entry')
            if member.issym() or member.islnk():
                target = member.linkname
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(member.name), target)
                                              if member.issym() else target)
                if target.startswith('/') or not (resolved == 'flutter' or resolved.startswith('flutter/')):
                    raise RuntimeError('Archive link escapes exclusive Flutter root')
            metadata.append({'path': member.name, 'bytes': member.size,
                             'type': member.type.decode('ascii'), 'mode': oct(member.mode),
                             'link_target': member.linkname or None})
        write(ATTEMPT, 'validated-archive-members.json', {'at_utc': now(), 'member_count': len(metadata),
              'total_regular_file_bytes': sum(x.size for x in members if x.isfile()),
              'members': metadata, 'archive_sha256': BOUNDARY['publisher_archive_sha256'],
              'archive_scripts_executed': False})
        bundle.extractall(RUNTIME, members=members, filter='data')
    if sha(ARCHIVE) != BOUNDARY['publisher_archive_sha256']:
        raise RuntimeError('Archive changed while validated/extracted')
    sdk = RUNTIME / 'flutter'
    revision = subprocess.check_output(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], timeout=20).decode().strip()
    if revision != 'ad70ec4617166f1c38e5d2bfd388af71fda14f06':
        raise RuntimeError('Extracted SDK exact Git revision differs from publisher')
    identities = {name: sha(sdk / name) for name in ['bin/flutter', 'bin/dart',
                  'bin/cache/dart-sdk/bin/dart', 'bin/internal/engine.version']}
    write(ATTEMPT, 'result.json', {'at_utc': now(), 'status': 'VERIFIED_SAFE_EXTRACTION_ONLY',
          'sdk': str(sdk), 'sdk_git_revision': revision, 'sdk_file_sha256': identities,
          'member_count': len(metadata), 'archive_scripts_executed': False,
          'actual_linux_executable_preflight_not_yet_run': True})
    print(json.dumps({'status': 'VERIFIED_SAFE_EXTRACTION_ONLY', 'sdk': str(sdk),
                      'revision': revision}, indent=2))
except Exception as error:
    write(ATTEMPT, 'failure.json', {'at_utc': now(), 'type': type(error).__name__,
          'error': str(error), 'archive_scripts_executed': False})
    raise
