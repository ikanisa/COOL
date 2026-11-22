#!/usr/bin/env python3
"""Extract pinned receiver sources with a closed, paired Buri runtime upload gate.

Use the bundled exact Collect snapshot by default, or an explicit checkout (never
mix missing checkout files with the bundle). Output is a dedicated build directory.
A lock excludes cooperating writers; source/build trees must be exclusively owned.
A crash during promotion can leave a backup/lock and fail the build closed; it does
not authorize deleting unrelated files or silently regenerating altered outputs.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile

from receiver_adaptations import queue_disposition, reliability_adapt, replace_once

NATIVE = Path(__file__).absolute().parents[1]
PACKAGE = NATIVE.parents[1]
MANIFEST = NATIVE / 'integration/receiver-sources.json'
BUNDLED_ROOT = PACKAGE / 'upstream/collect'
PROVENANCE = 'receiver-provenance.json'


def git_blob(raw: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()


def safe_path(path: Path) -> Path:
    """Reject links before resolving; a linked ancestor is unsafe too."""
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError(f'Symbolic links are forbidden: {part.name}')
    return path


def regular_bytes(path: Path) -> bytes:
    safe_path(path)
    if not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f'Missing regular source: {path.name}')
    if path.stat().st_size > 2_000_000:
        raise ValueError(f'Source exceeds bounded input size: {path.name}')
    return path.read_bytes()


def prepare(collect_root: Path, manifest_path: Path = MANIFEST) -> tuple[dict[str, bytes], dict]:
    root = safe_path(collect_root)
    manifest = json.loads(regular_bytes(manifest_path))
    relative = PurePosixPath(manifest['root'])
    if relative.is_absolute() or '..' in relative.parts or not relative.parts:
        raise ValueError('Unsafe receiver manifest path.')
    files = manifest['files']
    if not isinstance(files, dict) or not files or len(files) > 64:
        raise ValueError('Invalid receiver source manifest.')
    prepared: dict[str, bytes] = {}
    evidence = []
    for name, expected in sorted(files.items()):
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*\.kt', name) or not re.fullmatch(r'[0-9a-f]{40}', expected):
            raise ValueError('Unsafe receiver source entry.')
        raw = regular_bytes(root / str(relative) / name)
        blob = git_blob(raw)
        if blob != expected:
            raise ValueError(f'Unreviewed source drift: {name}; expected {expected}, got {blob}')
        text = raw.decode('utf-8')
        output_name = name
        if name == 'MemberSmsJobs.kt':
            output_name = 'MemberSmsUploadPolicy.kt'
            text = queue_disposition(text)
        elif name == 'CollectSmsReceiver.kt':
            hook = 'MemberSmsJobs.ensure(context.applicationContext)'
            if text.count(hook) != 2:
                raise ValueError('Unexpected member scheduler call sites.')
            text = text.replace(hook, 'Unit /* Dedicated gateway: no member capture scheduler. */')
            hook = 'if (body.isEmpty()) return@executeCapture'
            text = replace_once(text, hook, hook + '\n                    if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) return@executeCapture')
        elif name == 'MomoGatewayRecovery.kt':
            hook = 'val bindingCreated = try { Instant.parse(binding.optString("created_at")).toEpochMilli() } catch (_: Exception) { null }'
            replacement = '''if (!BuriCapturePolicy.retain(context, binding, sender, body, subscription)) {
                        // Uncertain SIM/profile stops before checkpointing relevant evidence.
                        if (!BuriCapturePolicy.routeConfigured(binding, subscription)) {
                            state.park("sim_or_profile_uncertain")
                            return false
                        }
                        advanced = maxOf(advanced, id)
                        continue
                    }
                    ''' + hook
            text = replace_once(text, hook, replacement)
        elif name == 'MomoGatewayHttp.kt':
            hook = 'if (status !in 200..299) throw ResponseFailure(status)'
            text = replace_once(text, hook, hook + '\n            check(connection.getHeaderField("Content-Type").orEmpty().substringBefore(\';\').trim().equals("application/json", ignoreCase = true)) { "Gateway returned a non-JSON response" }')
        text = reliability_adapt(name, text)
        if name == 'MomoGatewayPolicy.kt' and 'fun gatewayUploadsAdmitted(runtimeAdmission: Boolean = false): Boolean = runtimeAdmission' not in text:
            raise ValueError('Closed runtime upload admission was not installed.')
        for forbidden in ('MemberSmsJobs.', 'class MemberSmsJobService', 'class MemberSmsUploader', 'ProtectedSnapshotStore', 'access_token'):
            if forbidden in text:
                raise ValueError(f'Unexpected member-session implementation in {output_name}')
        if output_name in prepared:
            raise ValueError('Duplicate generated receiver path.')
        generated = text.encode('utf-8')
        prepared[output_name] = generated
        evidence.append({'file': output_name, 'sourceFile': name, 'sourceGitBlob': blob,
                         'sourceSha256': hashlib.sha256(raw).hexdigest(),
                         'generatedSha256': hashlib.sha256(generated).hexdigest(),
                         'changed': generated != raw})
    if 'SmsQueueStore.kt' in prepared and 'MemberSmsUploadPolicy.kt' not in prepared:
        raise ValueError('Missing queue-disposition dependency; extraction cannot compile.')
    required_admission = {
        'MomoGatewayPolicy.kt': 'gatewayUploadsAdmitted(runtimeAdmission: Boolean = false)',
        'MomoGatewayStore.kt': 'fun active(): Boolean = BuriCapturePolicy.uploadsAdmitted(context)',
        'MomoGatewayHttp.kt': 'gatewayUploadsAdmitted(uploadAdmission(token, body))',
        'MomoGatewayJobs.kt': 'uploadAdmission = { token, body -> BuriCapturePolicy.uploadRequestAdmitted(context, token, body) }',
    }
    for name, fragment in required_admission.items():
        if fragment not in prepared.get(name, b'').decode('utf-8'):
            raise ValueError('Incomplete closed receiver transport admission; no output written.')
    provenance = {'contractVersion': 2, 'sourceRepository': manifest['repository'],
                  'sourceCommit': manifest['commit'], 'uploadHoldPreserved': False, 'upstreamUploadHoldPreserved': True,
                  'runtimeUploadAdmission': 'paired_resumed_receiver_v1', 'defaultUploadAdmission': False,
                  'memberSessionImplementationIncluded': False, 'reliabilityRevision': 'sms-r1', 'files': evidence}
    prepared[PROVENANCE] = (json.dumps(provenance, indent=2) + '\n').encode()
    return prepared, provenance


def check_existing(out: Path) -> None:
    """Only replace a previously generated, intact, single-level output tree."""
    if not out.exists():
        return
    if not out.is_dir():
        raise ValueError('Output is not a generated directory.')
    children = list(out.iterdir())
    if not children:
        return
    for child in children:
        if child.is_symlink() or not child.is_file():
            raise ValueError('Unexpected output entry; preserve it and use a fresh build directory.')
    try:
        old = json.loads(regular_bytes(out / PROVENANCE))
        rows = old['files']
        if not isinstance(rows, list) or not rows or len(rows) > 64:
            raise ValueError('Invalid provenance file list.')
        names = [row['file'] for row in rows]
        if len(set(names)) != len(names) or any(not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*\.kt', name) for name in names):
            raise ValueError('Invalid provenance paths.')
        if {c.name for c in children} != set(names) | {PROVENANCE}:
            raise ValueError('Unexpected generated output file.')
        for row in rows:
            if hashlib.sha256(regular_bytes(out / row['file'])).hexdigest() != row['generatedSha256']:
                raise ValueError('Generated receiver was locally modified.')
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise ValueError('Output provenance is missing or invalid.') from error


def extract(collect_root: Path | None, output: Path, manifest_path: Path = MANIFEST) -> dict:
    root = safe_path(collect_root if collect_root is not None else BUNDLED_ROOT)
    out = safe_path(output)
    manifest = json.loads(regular_bytes(manifest_path))
    source_directory = root / manifest['root']
    if ('build' not in out.parts or out == root or out in root.parents or
            out == source_directory or out in source_directory.parents or source_directory in out.parents):
        raise ValueError('Output must be a dedicated build directory outside the receiver source directory.')
    prepared, provenance = prepare(root, manifest_path)  # validate ALL inputs before writes
    out.parent.mkdir(parents=True, exist_ok=True)
    safe_path(out.parent)
    lock = out.parent / ('.' + out.name + '.receiver.lock')
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    stage: Path | None = None
    backup: Path | None = None
    try:
        os.close(fd)
        check_existing(out)
        if out.is_dir() and {f.name for f in out.iterdir()} == set(prepared) and all((out/n).read_bytes() == body for n, body in prepared.items()):
            return {'preparedFiles': len(provenance['files']), 'changed': False, 'sourceCommit': provenance['sourceCommit']}
        stage = Path(tempfile.mkdtemp(prefix='.' + out.name + '.stage-', dir=out.parent))
        for name, body in prepared.items():
            with (stage / name).open('xb') as stream:
                stream.write(body)
                stream.flush()
                os.fsync(stream.fileno())
        safe_path(out)
        check_existing(out)
        if out.exists():
            backup = Path(tempfile.mkdtemp(prefix='.' + out.name + '.backup-', dir=out.parent))
            backup.rmdir()
            os.replace(out, backup)
        try:
            os.replace(stage, out)
            stage = None
        except BaseException:
            if backup is not None and not out.exists():
                os.replace(backup, out)
                backup = None
            raise
        if backup is not None:
            shutil.rmtree(backup)
            backup = None
        return {'preparedFiles': len(provenance['files']), 'changed': True, 'sourceCommit': provenance['sourceCommit']}
    finally:
        if stage is not None and stage.exists():
            shutil.rmtree(stage)
        # A failed restoration leaves the backup for explicit recovery, not deletion.
        lock.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect-root', type=Path, help='Explicit pinned checkout; default: bundled exact sources.')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.collect_root, args.output)
    print(json.dumps({**result, 'uploadHoldPreserved': False, 'upstreamUploadHoldPreserved': True,
                      'runtimeUploadAdmission': 'paired_resumed_receiver_v1', 'defaultUploadAdmission': False, 'upstreamModified': False,
                      'scope': 'Deterministic source extraction only; not an Android build.'}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
