#!/usr/bin/env python3
"""Deliver current browser artifacts and finite evidence; reuse earlier archives."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import stat
import tarfile

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
BASE = OUT.parent / 'final-candidate-current1'
RELEASE = ROOT / 'docs/release'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    archive = OUT / 'collect-integrated-browser-and-evidence.tar.gz'
    assert not archive.exists(), 'Delivered archives are immutable'
    assert json.loads((OUT / 'integration-acceptance.json').read_text())['status'] == 'pass'
    excluded = {'collect-integrated-source-overlay.tar.gz', archive.name,
                'delivery-readback.json', 'delivery-manifest.json', 'PACKET-MANIFEST.json'}
    files = {path for path in OUT.rglob('*') if path.is_file() and path.name not in excluded
             and '__pycache__' not in path.parts}
    peer = RELEASE / 'collect-codex-goal-2026-09-30/admin-exception-history-ui-20261001'
    files.update(path for path in peer.rglob('*') if path.is_file()
                 and 'sources' not in path.relative_to(peer).parts and '__pycache__' not in path.parts)
    extra = [
        OUT.parent / 'post-acceptance-delta-current1/sql-ordinary187',
        OUT.parent / 'post-acceptance-delta-current1/mcp-review',
        RELEASE / 'collect-codex-goal-2026-09-30/exception-inbox-audit-v2-20261001/affected-plan-attempt1',
    ]
    for parent in extra:
        assert parent.is_dir()
        files.update(path for path in parent.rglob('*') if path.is_file()
                     and path.suffix in {'.json', '.log', '.txt', '.md', '.py', '.sql', '.diff'}
                     and not {'__pycache__', 'node_modules', '.dart_tool'} & set(path.parts))
    for name in ['local-implementation-register-2026-09-30.json', 'LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md',
                 'production-remaining-tasks-2026-09-30.json', 'PRODUCTION_REMAINING_TASKS_2026-09-30.md',
                 'production-remaining-tasks-2026-09-30.validation.json']:
        files.add(RELEASE / name)
    rows = {}
    for path in sorted(files):
        assert not path.is_symlink(), str(path)
        name = str(path.relative_to(ROOT))
        assert not any(part.startswith('.env') and part != '.env.example' for part in path.parts)
        assert path.suffix.lower() not in {'.p12', '.pfx', '.p8', '.pem', '.key', '.jks', '.keystore', '.mobileprovision'}
        data = path.read_bytes()
        rows[name] = {'sha256': digest(data), 'bytes': len(data), 'mode': stat.S_IMODE(path.stat().st_mode)}
    manifest = {
        'schema_version': 1, 'kind': 'integrated_browser_and_finite_evidence_delivery',
        'rows': rows, 'members': len(rows),
        'scope': 'Current actual Admin/Public browser artifacts and bounded integration proof, commands, source bindings, preserved failures and canonical registers. External SDK/dependency source copies from the peer packet are intentionally omitted; its sealed manifest and exact consumed-input hashes are retained. Authored source is the earlier source archive plus the separately verified overlay.',
        'prior_unsigned_native_delivery': json.loads((BASE / 'delivery-archive-readback.json').read_text())['sha256'],
        'current_source_overlay': json.loads((OUT / 'source-overlay-readback.json').read_text())['overlay_sha256'],
    }
    (OUT / 'delivery-manifest.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
    files.add(OUT / 'delivery-manifest.json')
    with archive.open('xb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode='w') as tar:
                for path in sorted(files):
                    data = path.read_bytes()
                    info = tarfile.TarInfo(str(path.relative_to(ROOT)))
                    info.size = len(data)
                    info.mode = stat.S_IMODE(path.stat().st_mode)
                    info.mtime = info.uid = info.gid = 0
                    tar.addfile(info, io.BytesIO(data))
    actual = {}
    with tarfile.open(archive, 'r:gz') as tar:
        for member in tar:
            assert member.isfile() and not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
            data = tar.extractfile(member).read()
            path = ROOT / member.name
            assert digest(data) == digest(path.read_bytes()) and member.mode == stat.S_IMODE(path.stat().st_mode)
            actual[member.name] = {'sha256': digest(data), 'bytes': len(data), 'mode': member.mode}
    assert len(actual) == len(rows) + 1
    result = {
        'status': 'pass', 'archive': str(archive), 'bytes': archive.stat().st_size,
        'sha256': digest(archive.read_bytes()), 'members': len(actual),
        'every_member_read_back_and_hash_verified': True, 'rows': actual,
        'current_authored_source_separate': 'accepted source archive plus integrated source overlay',
        'prior_native_delivery_reused': str(BASE / 'collect-unsigned-builds-and-evidence.tar.gz'),
        'prior_native_delivery_sha256': manifest['prior_unsigned_native_delivery'],
        'scope': manifest['scope'], 'production_release_accepted': False,
    }
    (OUT / 'delivery-readback.json').write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'rows'}))


if __name__ == '__main__':
    main()
