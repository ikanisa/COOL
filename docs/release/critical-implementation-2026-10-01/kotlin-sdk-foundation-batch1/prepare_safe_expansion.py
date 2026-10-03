#!/usr/bin/env python3
"""Read-only archive admission and prepared writer. No extraction CLI exists.

The writer may be called only in a separately authorized future task after all
reported exceptions have been explicitly reviewed. Current admission is strict.
"""
import copy
import hashlib
import json
import os
import posixpath
import shutil
import stat
import time
import unicodedata
import zipfile
from collections import Counter
from pathlib import Path

PACKET = Path(__file__).resolve().parent
MAX_TOTAL = 12 * 1024**3
MAX_MEMBER = 1024**3
MAX_ENTRIES = 200000
SOURCE_READ_LIMIT = 160 * 1024**2


def blob_id(body):
    return hashlib.sha1(b"blob " + str(len(body)).encode() + b"\0" + body).hexdigest()


def canonical(name):
    path = name[:-1] if name.endswith("/") else name
    parts = path.split("/")
    if (not path or path.startswith("/") or "\\" in path or ":" in parts[0]
            or any(ord(c) < 32 for c in path)
            or any(p in ("", ".", "..") for p in parts)):
        raise ValueError("unsafe archive path")
    if parts[0] != "flutter":
        raise ValueError("unexpected publisher root")
    return path


def kind(info):
    value = stat.S_IFMT(info.external_attr >> 16)
    if value == stat.S_IFLNK:
        return "symlink"
    if value == stat.S_IFDIR and info.is_dir():
        return "directory"
    if value in (0, stat.S_IFREG) and not info.is_dir():
        return "regular"
    raise ValueError("special or inconsistent archive file type")


def contained_target(path, target):
    if (not target or target.startswith("/") or "\\" in target
            or any(ord(c) < 32 for c in target) or ":" in target.split("/")[0]):
        raise ValueError("absolute or unsafe symlink target")
    combined = posixpath.normpath(posixpath.join(posixpath.dirname(path), target))
    if combined != "flutter" and not combined.startswith("flutter/"):
        raise ValueError("symlink target escapes publisher root")
    return combined


def resolve_link(path, targets, entries):
    current = contained_target(path, targets[path])
    seen = {path}
    while True:
        parts = current.split("/")
        replaced = False
        for index in range(1, len(parts) + 1):
            prefix = "/".join(parts[:index])
            if prefix in targets:
                if prefix in seen:
                    raise ValueError("symlink cycle")
                seen.add(prefix)
                current = contained_target(prefix, targets[prefix])
                if parts[index:]:
                    current = posixpath.normpath(current + "/" + "/".join(parts[index:]))
                replaced = True
                break
        if not replaced:
            if current not in entries and not any(n.startswith(current + "/") for n in entries):
                raise ValueError("symlink target missing from archive")
            return current


def check_metadata(infos, targets, official_links, reviewed_extra_links=None):
    reviewed_extra_links = reviewed_extra_links or {}
    issues = []
    entries = {}
    aliases = {}
    total = sum(i.file_size for i in infos)
    if len(infos) > MAX_ENTRIES:
        issues.append({"kind": "entry_bound", "entries": len(infos)})
    if total > MAX_TOTAL:
        issues.append({"kind": "total_size_bound", "bytes": total})
    for info in infos:
        try:
            name = canonical(info.filename)
            file_kind = kind(info)
            if name in entries:
                raise ValueError("duplicate archive identity")
            alias = unicodedata.normalize("NFC", name).casefold()
            if alias in aliases and aliases[alias] != name:
                raise ValueError("NFC/case alias")
            aliases[alias] = name
            if (info.file_size < 0 or info.compress_size < 0 or info.file_size > MAX_MEMBER
                    or (info.file_size and info.file_size / max(info.compress_size, 1) > 1000)):
                raise ValueError("member size/compression bound")
            if info.flag_bits & 1:
                raise ValueError("encrypted archive member")
            if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise ValueError("unreviewed compression method")
            if (info.external_attr >> 16) & (stat.S_ISUID | stat.S_ISGID):
                raise ValueError("special permission bits")
            if name == "flutter/.git/objects/info/alternates":
                raise ValueError("external object-store alternates forbidden")
            entries[name] = file_kind
        except ValueError as error:
            issues.append({"kind": "member_rejected", "path": info.filename, "error": str(error)})
    for name in entries:
        parts = name.split("/")
        for index in range(1, len(parts)):
            parent = "/".join(parts[:index])
            if parent in entries and entries[parent] != "directory":
                issues.append({"kind": "ancestor_collision", "path": name, "parent": parent})
    link_rows = []
    for path, target in targets.items():
        row = {"path": path, "target": target, "publisher_tree_link": path in official_links,
               "explicitly_reviewed_cache_link": path in reviewed_extra_links}
        try:
            if entries.get(path) != "symlink":
                raise ValueError("link target has no symlink member")
            row["resolved_target"] = resolve_link(path, targets, entries)
            row["contained"] = True
            if path in official_links:
                if target != official_links[path]:
                    raise ValueError("publisher-tree link byte drift")
            elif path in reviewed_extra_links:
                if target != reviewed_extra_links[path]:
                    raise ValueError("reviewed cache link byte drift")
                marker = "/FlutterMacOS.framework/"
                if marker not in path:
                    raise ValueError("reviewed cache link is outside the exact framework type")
                framework = path.split(marker, 1)[0] + "/FlutterMacOS.framework"
                if not row["resolved_target"].startswith(framework + "/"):
                    raise ValueError("reviewed cache link escapes its own framework")
            else:
                issues.append({"kind": "unreviewed_extra_link", "path": path, "target": target})
        except ValueError as error:
            row.update(contained=False, error=str(error))
            issues.append({"kind": "link_rejected", "path": path, "error": str(error)})
        link_rows.append(row)
    for path in official_links:
        if path not in targets:
            issues.append({"kind": "missing_publisher_link", "path": path})
    for path in reviewed_extra_links:
        if path not in targets:
            issues.append({"kind": "missing_reviewed_cache_link", "path": path})
    return {"admitted": not issues, "issues": issues, "entries": entries,
            "links": link_rows, "expanded_bytes": total}


def source_compare(archive, infos, source_tree):
    available = {canonical(i.filename): i for i in infos}
    expected = {"flutter/" + n["path"]: n for n in source_tree if n["mode"] != "040000"}
    declared = sum(available[n].file_size for n in expected if n in available)
    if declared > SOURCE_READ_LIMIT:
        raise ValueError("bounded source read total exceeded")
    missing = []
    changed = []
    matched = 0
    mode_mismatches = []
    selected = {}
    license_paths = []
    for path, node in expected.items():
        if path not in available:
            missing.append(path)
            continue
        info = available[path]
        if info.file_size > 8 * 1024**2:
            raise ValueError("bounded source member read exceeded")
        body = archive.read(info)  # RAM only; ZIP reader verifies CRC. No filesystem expansion.
        identity = blob_id(body)
        expected_mode = int(node["mode"], 8)
        actual_mode = info.external_attr >> 16
        if (stat.S_IFMT(expected_mode) != stat.S_IFMT(actual_mode)
                or (stat.S_IFMT(expected_mode) == stat.S_IFREG
                    and bool(expected_mode & 0o111) != bool(actual_mode & 0o111))):
            mode_mismatches.append({"path": path, "expected": node["mode"], "actual": oct(actual_mode)})
        row = {"path": path, "expected_blob_sha1": node["sha"], "actual_blob_sha1": identity,
               "expected_bytes": node["size"], "actual_bytes": len(body),
               "actual_sha256": hashlib.sha256(body).hexdigest()}
        if identity != node["sha"] or len(body) != node["size"]:
            changed.append(row)
        else:
            matched += 1
        if "license" in path.rsplit("/", 1)[-1].lower():
            license_paths.append(row)
        if path.endswith("/SKILL.md") or path == "flutter/pubspec.lock":
            selected[path] = row
    return {"passed": not (missing or changed or mode_mismatches), "expected_leaf_source_entries": len(expected),
            "source_bytes_read_in_memory": declared, "matched": matched, "missing": missing,
            "changed": changed, "mode_mismatches": mode_mismatches,
            "license_file_comparisons": license_paths, "selected_comparisons": selected}


def require_admission(report):
    if not report["metadata"]["admitted"] or not report["source_comparison"]["passed"]:
        raise ValueError("unreviewed archive/link/source exceptions prohibit expansion")


def expand_previously_authorized_archive(archive_path, destination, report):
    """Prepared, NOT EXECUTED. Requires future authorization and strict admission.

    No option blesses source or link deltas. Review exceptions in a future exact
    manifest/code change before use; never reinterpret today's report as approval.
    """
    require_admission(report)  # All current actual extras block BEFORE any writes.
    archive_path = Path(archive_path)
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError("destination must be fresh")
    deadline = time.monotonic() + 600
    def bounded():
        if time.monotonic() > deadline:
            raise TimeoutError("fixed expansion deadline exceeded")
    sha = hashlib.sha256()
    with archive_path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024**2), b""):
            bounded(); sha.update(chunk)
    if sha.hexdigest() != report["archive_sha256"]:
        raise ValueError("archive digest drift before expansion")
    if shutil.disk_usage(destination.parent).free < report["metadata"]["expanded_bytes"] + 2 * 1024**3:
        raise ValueError("insufficient current expansion headroom")
    # Ensure no destination ancestor is a symlink; no shared SDK/object store is used.
    for parent in (destination.parent, *destination.parent.parents):
        if parent.is_symlink():
            raise ValueError("destination ancestor link")
    destination.mkdir(mode=0o700)
    manifest = {}
    with zipfile.ZipFile(archive_path) as archive:
        infos = archive.infolist()
        def local(name):
            parts = canonical(name).split("/")[1:]
            return destination.joinpath(*parts)
        def parents(path):
            for parent in reversed(path.parents):
                if parent == destination or destination in parent.parents:
                    if parent.exists():
                        if not stat.S_ISDIR(parent.lstat().st_mode):
                            raise ValueError("non-directory ancestor")
                    else:
                        parent.mkdir(mode=0o700)
        for info in infos:
            bounded()
            entry_kind = kind(info)
            if entry_kind == "symlink":
                continue  # Links are created only after every regular byte is verified.
            path = local(info.filename)
            parents(path)
            if entry_kind == "directory":
                if not path.exists(): path.mkdir(mode=0o700)
                continue
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
            digest = hashlib.sha256(); size = 0
            fd = os.open(path, flags, 0o600)
            with os.fdopen(fd, "wb") as output, archive.open(info) as source:
                while True:
                    bounded(); chunk = source.read(1024**2)
                    if not chunk: break
                    size += len(chunk)
                    if size > info.file_size: raise ValueError("expanded member overrun")
                    output.write(chunk); digest.update(chunk)
                output.flush(); os.fsync(output.fileno())
            if size != info.file_size: raise ValueError("expanded member truncation")
            os.chmod(path, 0o755 if (info.external_attr >> 16) & 0o111 else 0o644)
            if path.lstat().st_nlink != 1: raise ValueError("shared writable inode")
            manifest[info.filename] = {"kind": "regular", "bytes": size, "sha256": digest.hexdigest(), "CRC": info.CRC}
        for row in report["metadata"]["links"]:
            bounded(); path = local(row["path"]); parents(path)
            os.symlink(row["target"], path)
            if not path.resolve().is_relative_to(destination.resolve()):
                raise ValueError("materialized link escapes destination")
            manifest[row["path"]] = {"kind": "symlink", "target": row["target"]}
    # A future authorized caller must perform independent full byte/source/license
    # readback and installed-SDK inode comparison before accepting this directory.
    return manifest
