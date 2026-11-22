#!/usr/bin/env python3
"""Inventory tracked working-copy files in the requested Git path scope."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
PATHSPECS = {
    "source": [":(top,exclude,literal)docs/release"],
    "release-evidence": [":(top,literal)docs/release"],
    "checkout": [],
}
PRIVATE_SUFFIXES = {".jks", ".keystore", ".p12", ".p8"}


def file_record(root, name):
    path = root / name
    try:
        metadata = path.lstat()
    except (FileNotFoundError, NotADirectoryError):
        return None
    if not stat.S_ISREG(metadata.st_mode) or path.parent.resolve() != path.parent:
        return None

    record = {"path": name, "bytes": metadata.st_size}
    if path.name.startswith(".env") or path.suffix.lower() in PRIVATE_SUFFIXES:
        return {**record, "classification": "private-review-required"}

    digest = hashlib.sha256()
    with path.open("rb") as source:
        if not os.path.samestat(metadata, os.fstat(source.fileno())):
            raise RuntimeError(f"File was replaced during inventory: {name}")
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
        final = os.fstat(source.fileno())
    if (metadata.st_size, metadata.st_ctime_ns) != (final.st_size, final.st_ctime_ns) or not os.path.samestat(
        metadata, path.lstat()
    ):
        raise RuntimeError(f"File changed during inventory: {name}")
    return {**record, "classification": "tracked", "sha256": digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--scope", choices=PATHSPECS, default="source",
                        help="source excludes docs/release, release-evidence selects it, checkout selects both")
    args = parser.parse_args()
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--", *PATHSPECS[args.scope]], cwd=ROOT
    )
    files = []
    for raw in names.split(b"\0"):
        if raw:
            record = file_record(ROOT, os.fsdecode(raw))
            if record is not None:
                files.append(record)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report = {"source_commit": head, "scope": args.scope, "files": files,
              "reachability_proven": False, "private_values_exported": False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    stream = tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False, mode="w", encoding="utf-8")
    temporary = Path(stream.name)
    try:
        with stream:
            json.dump(report, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, args.output)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
