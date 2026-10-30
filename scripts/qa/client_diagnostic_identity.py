#!/usr/bin/env python3
"""Bind safe diagnostics to the actual Dart inputs and public build profile.

This is a reproducible client-source identifier, not a signing, deployment or
complete native-artifact acceptance receipt. It never reads credentials or
collects raw application errors. Existing release provenance stays authoritative.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile

MAX_JAVASCRIPT_BYTES = 64 * 1024 * 1024


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def physical(path: Path):
    if path.is_symlink() or path.resolve() != path.absolute() or not path.is_file():
        raise ValueError("Diagnostic source inputs must be physical regular files")
    if path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError("Diagnostic source input exceeds its size bound")
    return path.read_bytes()


def public_profile(path: Path):
    value = json.loads(physical(path))
    if (not isinstance(value, dict) or not value or len(value) > 80
            or any(not isinstance(k, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]{0,79}", k)
                   or not isinstance(v, str) or len(v) > 4096 for k, v in value.items())):
        raise ValueError("Expected a bounded public Dart-define profile")
    return value


def identity(root: Path, surface: str, profile: dict):
    root = root.absolute()
    if root.resolve() != root or surface not in ("member", "admin"):
        raise ValueError("Expected a physical source root and supported surface")
    paths = [root / "pubspec.yaml", root / "pubspec.lock"]
    lib = root / "lib"
    if not lib.is_dir() or lib.is_symlink():
        raise ValueError("The actual client source tree is required")
    for folder in (lib, root / "third_party"):
        if not folder.exists():
            continue
        for current, directories, files in os.walk(folder, followlinks=False):
            directories[:] = sorted(d for d in directories if d not in
                                    (".git", ".dart_tool", "build", "node_modules"))
            if any((Path(current) / name).is_symlink() for name in directories):
                raise ValueError("Linked client source directories are refused")
            paths.extend(Path(current) / name for name in files
                         if name.endswith(".dart") and not name.startswith("._"))
    if len(paths) < 3 or len(paths) > 10000:
        raise ValueError("Client source file count is outside its bounds")
    hashes = {str(path.relative_to(root)): hashlib.sha256(physical(path)).hexdigest()
              for path in sorted(paths)}
    declarations = re.findall(r"^version:[ \t]*([^\r\n]+)$", physical(paths[0]).decode(), re.M)
    version = declarations[0].strip() if len(declarations) == 1 else ""
    if (len(version) > 32 or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\+[1-9][0-9]*", version)
            or profile.get("COLLECT_BUILD_VERSION", version) != version):
        raise ValueError("Diagnostic build version must equal the source pubspec version")
    public = {k: v for k, v in profile.items() if k != "COLLECT_BUILD_SOURCE_ID"}
    public["COLLECT_BUILD_VERSION"] = version
    body = {"format": "collect.client.diagnostic-source.v1", "surface": surface,
            "build_version": version, "files": hashes,
            "public_profile_sha256": hashlib.sha256(canonical(public)).hexdigest()}
    source = hashlib.sha256(canonical(body)).hexdigest()
    return {**body, "source_revision": source, "signing_or_deployment_acceptance": False}, {
        **public, "COLLECT_BUILD_SOURCE_ID": source}


def javascript_identity(path: Path, source_revision: str, build_version: str):
    """Observe exact quoted label bytes in the physical compiler output.

    This does not parse or execute JavaScript, prove that a label is reachable,
    or establish the identity of every artifact in a deployment. The existing
    candidate manifest separately binds the complete packaged artifact bytes.
    """
    if (not isinstance(source_revision, str)
            or not re.fullmatch(r"[a-f0-9]{64}", source_revision)
            or not isinstance(build_version, str) or len(build_version) > 32
            or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\+[1-9][0-9]*", build_version)):
        raise ValueError("Expected the exact bound diagnostic release labels")
    path = path.absolute()
    if path.name != "main.dart.js" or path.is_symlink() or path.resolve() != path:
        raise ValueError("Expected physical main.dart.js compiler output")
    before = path.stat(follow_symlinks=False)
    if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= MAX_JAVASCRIPT_BYTES:
        raise ValueError("Compiled JavaScript exceeds its size/type bounds")
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    stamp = lambda value: (value.st_dev, value.st_ino, value.st_size,
                           value.st_mtime_ns, value.st_ctime_ns)
    with os.fdopen(descriptor, "rb") as handle:
        if stamp(os.fstat(handle.fileno())) != stamp(before):
            raise ValueError("Compiled JavaScript changed before inspection")
        data = handle.read(MAX_JAVASCRIPT_BYTES + 1)
        if (len(data) != before.st_size
                or stamp(os.fstat(handle.fileno())) != stamp(before)):
            raise ValueError("Compiled JavaScript changed during inspection")
    if path.resolve() != path or stamp(path.stat(follow_symlinks=False)) != stamp(before):
        raise ValueError("Compiled JavaScript changed during inspection")
    for label in (source_revision, build_version):
        token = label.encode("ascii")
        if not any(quote + token + quote in data for quote in (b'"', b"'")):
            raise ValueError("Compiled JavaScript does not contain the bound diagnostic labels")
    return {"contract_version": 1, "surface": "admin", "artifact": "main.dart.js",
            "source_revision": source_revision, "build_version": build_version,
            "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
            "verification_scope": "quoted_label_bytes_present",
            "signing_or_deployment_acceptance": False}


def write_json(path: Path, value):
    path = path.absolute()
    if path.is_symlink() or path.parent.resolve() != path.parent:
        raise ValueError("Physical diagnostic output paths are required")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".diagnostic-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(value, output, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("bind", "verify"))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--surface", choices=("member", "admin"), required=True)
    parser.add_argument("--defines", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--javascript", type=Path,
                        help="On Admin verify, check bounded physical main.dart.js label bytes")
    args = parser.parse_args()
    try:
        if args.javascript and (args.action != "verify" or args.surface != "admin"):
            raise ValueError("Compiled JavaScript inspection is an Admin verification step")
        profile = public_profile(args.defines.absolute())
        manifest, updated = identity(args.root, args.surface, profile)
        if args.action == "verify":
            if json.loads(physical(args.manifest.absolute())) != manifest or profile != updated:
                raise ValueError("Client inputs or public build profile changed; rebuild required")
        else:
            if "COLLECT_BUILD_SOURCE_ID" in profile and profile["COLLECT_BUILD_SOURCE_ID"] != updated["COLLECT_BUILD_SOURCE_ID"]:
                raise ValueError("An existing source label does not match these build inputs")
            write_json(args.manifest, manifest)
            write_json(args.defines, updated)
        if args.metadata:
            metadata = json.loads(physical(args.metadata.absolute()))
            fields = {"diagnostics_source_revision": manifest["source_revision"],
                      "diagnostics_build_version": manifest["build_version"]}
            if not isinstance(metadata, dict):
                raise ValueError("Build metadata must be an object")
            if args.action == "verify":
                if any(metadata.get(k) != v for k, v in fields.items()):
                    raise ValueError("Build metadata and diagnostic source identity differ")
            else:
                write_json(args.metadata, {**metadata, **fields})
        if args.javascript:
            print(json.dumps(javascript_identity(args.javascript, manifest["source_revision"],
                                                 manifest["build_version"]), sort_keys=True))
    except (OSError, ValueError, UnicodeError):
        parser.exit(1, "Client diagnostic source binding failed; inspect the source and public build profile.\n")


if __name__ == "__main__":
    main()
