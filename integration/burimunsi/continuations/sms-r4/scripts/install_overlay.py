#!/usr/bin/env python3
"""Install additive pure-policy sources only. Dry-run by default; never wire workers or migrate data."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class Refusal(RuntimeError):
    """No unrecognized file may be overwritten or silently adopted."""

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def checked(root: Path, rel: str) -> Path:
    parts = Path(rel).parts
    if not parts or Path(rel).is_absolute() or any(p in ("..", ".") for p in parts):
        raise Refusal("UNSAFE_PATH")
    p = root
    for segment in parts:
        p = p / segment
        if p.is_symlink():
            raise Refusal("SYMLINK_PATH")
    if not p.resolve().is_relative_to(root.resolve()):
        raise Refusal("PATH_ESCAPES_ROOT")
    return p

def plan(target: Path, app: str) -> list[tuple[Path, Path, str]]:
    if app not in ("burimunsi", "mmoney"):
        raise Refusal("UNKNOWN_APPLICATION")
    if target.is_symlink() or not target.is_dir():
        raise Refusal("EXISTING_DIRECTORY_REQUIRED")
    target = target.absolute()
    if any(p.is_symlink() for p in target.parents):
        raise Refusal("SYMLINK_ROOT")
    # This is a native project root, e.g. native/burimunsi, not the entire Collect root.
    core = "core/src/main/kotlin"
    prefix = "rw/ikanisa/burimunsi/core" if app == "burimunsi" else "com/ikanisa/mmoney/core"
    vendor = "buri" if app == "burimunsi" else "mmoney"
    entries = json.loads((ROOT / "vendor/PROVENANCE.json").read_text())["files"]
    for entry in entries:
        if not entry["path"].startswith(f"vendor/{vendor}/core/"):
            continue
        baseline = checked(ROOT, entry["path"])
        installed = checked(target, f"{core}/{prefix}/{baseline.name}")
        if digest(baseline) != entry["sha256"]:
            raise Refusal("PACKAGE_DEPENDENCY_HASH_MISMATCH")
        if not installed.is_file() or digest(installed) != entry["sha256"]:
            raise Refusal(f"UNRECOGNIZED_CORE_BASELINE:{installed.name}")
    common = ROOT / "src/main/kotlin"
    sources = [(p, p.relative_to(common).as_posix()) for p in sorted(common.rglob("*.kt"))]
    adapter = ROOT / "src/adapters" / app
    sources += [(p, f"rw/ikanisa/sms/adapters/{app}/{p.name}") for p in sorted(adapter.glob("*.kt"))]
    result = []
    for src, relative in sources:
        dst = checked(target, f"{core}/{relative}")
        if dst.exists():
            if not dst.is_file() or digest(dst) != digest(src):
                raise Refusal(f"LOCAL_EDIT_OR_COLLISION:{relative}")
            action = "already_present"
        else:
            action = "create"
        result.append((src, dst, action))
    return result

def install(target: Path, app: str, apply: bool = False) -> dict:
    items = plan(target, app)  # Preflight all paths before creating any file.
    if apply:
        for src, dst, action in items:
            # Recheck the complete plan to catch ordinary changes since preflight.
            # This installer requires an exclusively held checkout; it is not a hostile-filesystem sandbox.
            plan(target, app)
            if action == "already_present":
                continue
            checked(target, dst.relative_to(target.absolute()).as_posix())
            dst.parent.mkdir(parents=True, exist_ok=True)
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
            fd = os.open(dst, flags, 0o644)
            try:
                with os.fdopen(fd, "wb") as stream:
                    stream.write(src.read_bytes())
                    stream.flush()
                    os.fsync(stream.fileno())
            except BaseException:
                # Preserve partial evidence instead of silently deleting it. Next run will refuse a mismatch.
                raise
            if digest(dst) != digest(src):
                raise Refusal("WRITTEN_FILE_HASH_MISMATCH")
    return {"mode": "apply" if apply else "dry_run", "application": app,
            "runtime_wiring": "not_modified", "files": [
                {"path": str(dst.relative_to(target.absolute())), "sha256": digest(src), "action": action}
                for src, dst, action in items]}

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--target", required=True, type=Path)
    ap.add_argument("--application", required=True, choices=("burimunsi", "mmoney"))
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    try:
        print(json.dumps(install(args.target.absolute(), args.application, args.apply), indent=2))
        return 0
    except (Refusal, OSError, ValueError) as error:
        print(json.dumps({"status": "refused", "reason": str(error)}))
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
