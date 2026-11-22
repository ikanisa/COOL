"""Filesystem, process and SDK operations used by the native pipeline."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


class PipelineError(ValueError):
    """An execution gate failed; no success attestation is permitted."""


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def fresh_dir(path: Path) -> Path:
    path = path.expanduser().absolute()
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise PipelineError('Evidence directory must not traverse symlinks.')
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise PipelineError('Use a new empty evidence directory; stale results are not reusable.')
    path.mkdir(parents=True, exist_ok=True)
    return path


def contained_file(base: Path, relative: str) -> Path:
    p = Path(relative)
    if p.is_absolute() or '..' in p.parts or '\\' in relative:
        raise PipelineError('Unsafe artifact path.')
    path = base / p
    if any(v.is_symlink() for v in (path, *path.parents)):
        raise PipelineError('Artifact links are forbidden.')
    if base.resolve() not in path.resolve().parents or not path.is_file():
        raise PipelineError('Missing/out-of-tree artifact: ' + relative)
    return path


def command(args: list[str], log: Path, *, timeout: int = 120, env: dict | None = None) -> str:
    """Stream directly to a retained log, syncing progress while the child runs.

    No shell expansion; log only bounded commands without credentials. Child
    output bypasses Python buffers so interruption does not discard the build
    transcript. Sync at most every second, and again on every normal exit path.
    """
    process = None
    try:
        with log.open('wb', buffering=0) as output:
            try:
                process = subprocess.Popen([str(v) for v in args], stdout=output,
                                           stderr=subprocess.STDOUT, env=env)
                deadline = time.monotonic() + timeout
                while True:
                    try:
                        process.wait(timeout=max(0, min(1, deadline - time.monotonic())))
                        break
                    except subprocess.TimeoutExpired as error:
                        os.fsync(output.fileno())
                        if time.monotonic() >= deadline:
                            process.kill()
                            process.wait()
                            output.write(b'\nTIMED OUT\n')
                            raise PipelineError('Command timed out: ' + Path(str(args[0])).name) from error
            except OSError as error:
                output.write((str(error) + '\n').encode('utf-8', errors='replace'))
                raise PipelineError('Tool could not be executed: ' + str(args[0])) from error
            finally:
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait()
                os.fsync(output.fileno())
    except OSError as error:
        raise PipelineError('Tool could not be executed: ' + str(args[0])) from error
    if process.returncode:
        raise PipelineError(f'Command failed ({process.returncode}); see {log.name}')
    return log.read_text(encoding='utf-8', errors='replace')


def sdk_path(value: str | None) -> Path:
    sdk = value or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise PipelineError('Set ANDROID_HOME or supply --sdk.')
    return Path(sdk).expanduser().absolute()


def sdk_tool(sdk: Path, name: str) -> Path:
    if name == 'adb':
        p = sdk / 'platform-tools/adb'
    elif name in ('apksigner', 'zipalign', 'aapt2'):
        p = sdk / 'build-tools/36.0.0' / name
    else:
        # Prefer the SDK owner's selected latest directory; otherwise refuse ambiguity.
        p = sdk / 'cmdline-tools/latest/bin' / name
        if not p.is_file():
            choices = sorted(sdk.glob('cmdline-tools/*/bin/' + name))
            if len(choices) != 1:
                raise PipelineError('Select one installed command-line-tools version for ' + name)
            p = choices[0]
    if not p.is_file() or not os.access(p, os.X_OK):
        raise PipelineError('SDK tool missing/not executable: ' + str(p))
    return p
