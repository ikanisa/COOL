#!/usr/bin/env python3
"""Package the finite integrated-source overlay; leave accepted archives intact."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import stat
import tarfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BASE = OUT.parent / 'final-candidate-current1'
CURRENT = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-integrated-local-candidate-20261001-current2')
PEER = ROOT / 'docs/release/collect-codex-goal-2026-09-30/admin-exception-history-ui-20261001'
EXPECTED_CURRENT = '24b1719665694a2f09b18ee78e8cf6d4e33f416a5fd0c42edd747f0f22867a6a'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def regular(path):
    assert not path.is_symlink() and path.is_file(), str(path)
    return path.read_bytes(), stat.S_IMODE(path.stat().st_mode)


def main():
    target = OUT / 'collect-integrated-source-overlay.tar.gz'
    assert not target.exists(), 'Do not overwrite a delivered archive'
    base_receipt = json.loads((BASE / 'source-archive-readback.json').read_text())
    base_rows = base_receipt['source_rows']
    archive = Path(base_receipt['archive'])
    assert digest(archive.read_bytes()) == base_receipt['archive_sha256']
    manifest_bytes, mode = regular(CURRENT / '.collect-release-candidate.json')
    assert digest(manifest_bytes) == EXPECTED_CURRENT
    manifest = json.loads(manifest_bytes)
    rows = manifest['source_files']
    prior = json.loads((BASE / 'evidence-binding.json').read_text())
    previous_source = Path(prior['source_export'])
    old = json.loads((previous_source / '.collect-release-candidate.json').read_text())['source_files']
    added = sorted(rows.keys() - old.keys())
    changed = sorted(name for name in rows.keys() & old.keys() if rows[name] != old[name])
    deleted = sorted(old.keys() - rows.keys())
    assert not deleted, 'Unexpected deletion requires a new explicit overlay policy'
    members = {}
    for name in added + changed:
        data, file_mode = regular(CURRENT / name)
        assert {'sha256': digest(data), 'bytes': len(data), 'mode': file_mode} == rows[name]
        members[name] = (data, file_mode, 'changed_or_added_selected_source')
    peer = json.loads((PEER / 'verification.json').read_text())
    documentation_inputs = {}
    for item in peer['current_source_bindings']:
        try:
            name = str(Path(item['path']).relative_to(ROOT))
        except ValueError:
            continue
        if not name.startswith('docs/'):
            continue
        frozen = PEER / 'sources' / name
        data, file_mode = regular(frozen if frozen.exists() else ROOT / name)
        assert digest(data) == item['sha256'], name
        documentation_inputs[name] = {'sha256': digest(data), 'bytes': len(data), 'mode': file_mode}
        if base_rows.get(name, {}).get('sha256') != digest(data):
            members[name] = (data, file_mode, 'declared_SQL_decoder_reference_fixture')
    members['.collect-release-candidate.json'] = (manifest_bytes, mode, 'current_source_metadata')
    supplement_manifest = json.loads((BASE / 'supplement-manifest.json').read_text())
    supplement = {name: value for name, value in supplement_manifest['files'].items() if name not in rows}
    for name, value in documentation_inputs.items():
        supplement[name] = value
    packaged_rows = {name: {'sha256': digest(data), 'bytes': len(data), 'mode': file_mode, 'origin': origin}
                     for name, (data, file_mode, origin) in sorted(members.items())}
    overlay = {
        'schema_version': 1, 'kind': 'finite_integrated_source_overlay',
        'base_archive': archive.name, 'base_archive_sha256': base_receipt['archive_sha256'],
        'current_manifest_sha256': EXPECTED_CURRENT,
        'current_source_manifest_sha256': manifest['source_manifest_sha256'],
        'current_source_files': rows, 'current_source_count': len(rows),
        'added': added, 'changed': changed, 'deleted': deleted,
        'declared_reproduction_supplement': supplement,
        'overlay_rows': packaged_rows,
        'scope': 'Apply over the separately hash-bound accepted source archive. SDKs, dependency caches, credentials, signing files and build outputs are excluded. Old reproduction-only files remain distinguishable from selected source. No release authorization is inferred.',
    }
    (OUT / 'source-overlay-manifest.json').write_bytes(encoded(overlay))
    members['.collect-source-overlay.json'] = (encoded(overlay), 0o644, 'overlay_reconstruction_metadata')
    with target.open('xb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode='w') as tar:
                for name, (data, file_mode, _) in sorted(members.items()):
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    info.mode = file_mode
                    info.mtime = 0
                    info.uid = info.gid = 0
                    tar.addfile(info, io.BytesIO(data))
    readback = {}
    with tarfile.open(target, 'r:gz') as tar:
        for member in tar:
            assert member.isfile() and not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
            data = tar.extractfile(member).read()
            expected, file_mode, origin = members[member.name]
            assert data == expected and member.mode == file_mode
            readback[member.name] = {'sha256': digest(data), 'bytes': len(data), 'mode': file_mode, 'origin': origin}
    union = dict(base_rows)
    union.update(readback)
    mismatches = [name for name, value in rows.items()
                  if name not in union or union[name]['sha256'] != value['sha256'] or union[name]['bytes'] != value['bytes']]
    supplement_mismatches = [name for name, value in supplement.items()
                            if name not in union or union[name]['sha256'] != value['sha256']]
    assert not mismatches and not supplement_mismatches
    result = {
        'status': 'pass', 'kind': 'base_archive_plus_integrated_overlay_readback',
        'current_manifest_sha256': EXPECTED_CURRENT,
        'base_archive_sha256': base_receipt['archive_sha256'],
        'base_archive_current_hash_matches': True,
        'base_member_readback_reused': str(BASE / 'source-archive-readback.json'),
        'base_member_readback_sha256': digest((BASE / 'source-archive-readback.json').read_bytes()),
        'overlay': str(target), 'overlay_bytes': target.stat().st_size,
        'overlay_sha256': digest(target.read_bytes()), 'overlay_members': len(readback),
        'every_overlay_member_read_back': True, 'added_selected_files': len(added),
        'changed_selected_files': len(changed), 'deleted_selected_files': len(deleted),
        'current_selected_source_files': len(rows), 'virtual_union_mismatches': mismatches,
        'declared_supplement_files': len(supplement), 'supplement_mismatches': supplement_mismatches,
        'source_archive_rebuilt': False, 'test_or_build_rerun': False,
        'production_release_authorized': False,
        'rows': readback,
    }
    (OUT / 'source-overlay-readback.json').write_bytes(encoded(result))
    print(json.dumps({key: value for key, value in result.items() if key != 'rows'}))


if __name__ == '__main__':
    main()
