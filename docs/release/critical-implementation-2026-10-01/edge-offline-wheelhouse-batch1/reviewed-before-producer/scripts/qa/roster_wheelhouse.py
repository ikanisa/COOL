#!/usr/bin/env python3
"""Pinned local-wheel preparation only; no network, installation or Docker run.

The publisher-input receipt's expected SHA is supplied out of band by its
authorized producer. Origin acquisition is a separate, bounded HTTPS stage.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import time
from urllib.parse import urlsplit

PACKAGES = frozenset(("defusedxml", "et-xmlfile", "openpyxl", "pillow", "pypdf", "pypdfium2"))
FORMAT = "collect_roster_wheelhouse_inputs_v1"
PLATFORM = "linux-aarch64-cp312"
WHEEL_KEYS = frozenset(("package", "version", "filename", "sha256", "size", "metadata_filename",
                        "metadata_sha256", "metadata_url", "wheel_url"))
MAX_METADATA = 4 * 1024 * 1024
MAX_RECEIPT = 128 * 1024
MAX_WHEEL = 32 * 1024 * 1024
MAX_TOTAL = 128 * 1024 * 1024


class WheelhouseError(ValueError):
    """Fixed denial code without payload/credential/OS text."""


def deny(code):
    raise WheelhouseError(code)


def digest(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        deny("invalid_digest")
    return value


def keys(value, expected):
    if not isinstance(value, dict) or set(value) != set(expected):
        deny("invalid_schema")


def basename(value):
    if not isinstance(value, str) or value in (".", "..") or not re.fullmatch(r"[A-Za-z0-9_.+-]{1,255}", value):
        deny("unsafe_filename")
    return value


def absolute(value):
    if not isinstance(value, (str, Path)) or not str(value):
        deny("invalid_path")
    raw = str(value)
    if "\\" in raw or "//" in raw or any(ord(c) < 32 or ord(c) == 127 or 0xD800 <= ord(c) <= 0xDFFF for c in raw):
        deny("unsafe_path")
    result = Path(raw).absolute()
    if len(str(result)) > 4096 or any(part in (".", "..") or len(part.encode()) > 255 for part in result.parts[1:]):
        deny("unsafe_path")
    return result


def strict_json(raw):
    def pairs(values):
        result = {}
        for key, value in values:
            if key in result:
                deny("duplicate_json_key")
            result[key] = value
        return result
    try:
        result = json.loads(raw.decode(), object_pairs_hook=pairs,
                            parse_constant=lambda _: deny("invalid_json"))
    except WheelhouseError:
        raise
    except (ValueError, UnicodeError, RecursionError):
        deny("invalid_json")
    if not isinstance(result, dict):
        deny("invalid_schema")
    return result


class Budget:
    def __init__(self):
        self.deadline = time.monotonic() + 30
        self.used = 0

    def check(self, count=0):
        self.used += count
        if self.used > MAX_TOTAL:
            deny("read_budget_exceeded")
        if time.monotonic() > self.deadline:
            deny("read_deadline_exceeded")


def identity(info, directory=False):
    value = (info.st_dev, info.st_ino, stat.S_IMODE(info.st_mode))
    return value if directory else value + (info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_nlink)


def directories(path):
    """Open/retain every ancestor without following symlinks."""
    fds, edges = [], []
    try:
        fds.append(os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW))
        for component in path.parts[1:]:
            fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fds[-1])
            edges.append((fds[-1], component, fd, identity(os.fstat(fd), True)))
            fds.append(fd)
        return fds, edges
    except OSError:
        for fd in reversed(fds):
            os.close(fd)
        deny("directory_missing_or_unsafe")


def recheck_directories(edges):
    for parent, name, fd, expected in edges:
        actual = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if not stat.S_ISDIR(actual.st_mode) or identity(actual, True) != expected or identity(os.fstat(fd), True) != expected:
            deny("path_changed")


@dataclass(frozen=True)
class File:
    data: bytes
    sha256: str
    size: int
    mode: int
    fingerprint: tuple


def read_file(path, budget, maximum):
    path = absolute(path)
    fds, edges = directories(path.parent)
    fd = None
    try:
        budget.check()
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fds[-1])
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            deny("nonregular_or_aliased_file")
        if before.st_size > maximum:
            deny("file_size_limit")
        chunks, size, sha = [], 0, hashlib.sha256()
        while chunk := os.read(fd, min(1024 * 1024, maximum - size + 1)):
            size += len(chunk)
            budget.check(len(chunk))
            if size > maximum or size > before.st_size:
                deny("file_changed")
            chunks.append(chunk)
            sha.update(chunk)
        after, named = os.fstat(fd), os.stat(path.name, dir_fd=fds[-1], follow_symlinks=False)
        if identity(before) != identity(after) or identity(before) != identity(named) or size != before.st_size:
            deny("file_changed")
        recheck_directories(edges)
        return File(b"".join(chunks), sha.hexdigest(), size, stat.S_IMODE(before.st_mode), identity(before))
    except OSError:
        deny("file_missing_or_unsafe")
    finally:
        if fd is not None:
            os.close(fd)
        for fd in reversed(fds):
            os.close(fd)


def recheck_file(path, expected):
    """Retain a final leaf/ancestor observation without another unbounded read."""
    path = absolute(path)
    fds, edges = directories(path.parent)
    fd = None
    try:
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fds[-1])
        actual = os.fstat(fd)
        named = os.stat(path.name, dir_fd=fds[-1], follow_symlinks=False)
        if (not stat.S_ISREG(actual.st_mode) or identity(actual) != tuple(expected)
                or identity(named) != tuple(expected)):
            deny("late_file_identity_changed")
        recheck_directories(edges)
    except OSError:
        deny("file_missing_or_unsafe")
    finally:
        if fd is not None:
            os.close(fd)
        for fd in reversed(fds):
            os.close(fd)


def parse_lock(raw):
    result = {}
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeError:
        deny("invalid_lock")
    for line in lines:
        if not line.strip() or line.startswith("#"):
            continue
        match = re.fullmatch(r"([a-z][a-z0-9-]*)==([0-9]+\.[0-9]+\.[0-9]+) --hash=sha256:([0-9a-f]{64})", line)
        if not match or match[1] in result:
            deny("invalid_lock")
        result[match[1]] = (match[2], match[3])
    if set(result) != PACKAGES:
        deny("exact_six_package_lock_required")
    return result


def origin(url, host, prefix):
    if not isinstance(url, str) or len(url) > 2048:
        deny("invalid_publisher_url")
    try:
        parsed = urlsplit(url)
    except ValueError:
        deny("invalid_publisher_url")
    if (parsed.scheme != "https" or parsed.netloc != host or parsed.query or parsed.fragment
            or not parsed.path.startswith(prefix) or "%" in parsed.path or "\\" in parsed.path
            or any(p in ("", ".", "..") for p in parsed.path.split("/")[1:])):
        deny("invalid_publisher_url")
    return parsed.path


def validate_wheel_row(row, locked):
    keys(row, WHEEL_KEYS)
    package, version = row["package"], row["version"]
    if not isinstance(package, str) or package not in locked or locked[package] != (version, digest(row["sha256"])):
        deny("publisher_lock_mismatch")
    filename = basename(row["filename"])
    parts = filename[:-4].split("-") if filename.endswith(".whl") else []
    if len(parts) != 5 or parts[0].replace("_", "-") != package or parts[1] != version:
        deny("wheel_name_identity_mismatch")
    python, abi, platform = parts[2:]
    if package == "pillow":
        valid = python == "cp312" and abi == "cp312" and platform == "manylinux_2_27_aarch64.manylinux_2_28_aarch64"
    elif package == "pypdfium2":
        valid = python == "py3" and abi == "none" and platform == "manylinux_2_17_aarch64.manylinux2014_aarch64"
    else:
        valid = python in ("py3", "py2.py3") and abi == "none" and platform == "any"
    if not valid:
        deny("linux_cp312_aarch64_wheel_required")
    if type(row["size"]) is not int or not 1 <= row["size"] <= MAX_WHEEL:
        deny("invalid_wheel_size")
    if basename(row["metadata_filename"]) != package + "-" + version + "-pypi.json":
        deny("metadata_filename_identity_mismatch")
    digest(row["metadata_sha256"])
    metadata_path = origin(row["metadata_url"], "pypi.org", "/pypi/")
    parts = metadata_path.split("/")
    if len(parts) != 5 or parts[2].lower().replace("_", "-") != package or parts[3:] != [version, "json"]:
        deny("metadata_release_identity_mismatch")
    if origin(row["wheel_url"], "files.pythonhosted.org", "/packages/").rsplit("/", 1)[-1] != filename:
        deny("wheel_origin_identity_mismatch")


def validate_release(raw, row):
    release = strict_json(raw)
    info, urls = release.get("info"), release.get("urls")
    if (not isinstance(info, dict) or not isinstance(info.get("name"), str)
            or info["name"].lower().replace("_", "-") != row["package"] or info.get("version") != row["version"]
            or not isinstance(urls, list) or len(urls) > 4096):
        deny("invalid_publisher_release")
    matches = [u for u in urls if isinstance(u, dict) and u.get("filename") == row["filename"]]
    if len(matches) != 1:
        deny("publisher_wheel_missing_or_duplicate")
    wheel = matches[0]
    if (not isinstance(wheel.get("digests"), dict) or wheel["digests"].get("sha256") != row["sha256"]
            or type(wheel.get("size")) is not int or wheel.get("size") != row["size"]
            or wheel.get("url") != row["wheel_url"] or wheel.get("yanked") is not False
            or wheel.get("packagetype") != "bdist_wheel"):
        deny("publisher_wheel_mismatch")


def write_new(directory, name, data):
    basename(name)
    fds, edges = directories(directory)
    fd = None
    try:
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o444, dir_fd=fds[-1])
        os.fchmod(fd, 0o444)
        remaining = memoryview(data)
        while remaining:
            written = os.write(fd, remaining)
            if not written:
                deny("copy_failed")
            remaining = remaining[written:]
        os.fsync(fd)
        recheck_directories(edges)
    except OSError:
        deny("copy_failed")
    finally:
        if fd is not None:
            os.close(fd)
        for fd in reversed(fds):
            os.close(fd)


def new_directory(path):
    path = absolute(path)
    fds, edges = directories(path.parent)
    try:
        os.mkdir(path.name, mode=0o700, dir_fd=fds[-1])
        recheck_directories(edges)
    except OSError:
        deny("fresh_private_destination_required")
    finally:
        for fd in reversed(fds):
            os.close(fd)
    return path


def directory_identity(path):
    fds, edges = directories(path)
    try:
        recheck_directories(edges)
        return identity(os.fstat(fds[-1]), True)
    except OSError:
        deny("path_changed")
    finally:
        for fd in reversed(fds):
            os.close(fd)


def names(path):
    try:
        return set(p.name for p in path.iterdir())
    except OSError:
        deny("directory_missing_or_unsafe")


def prepare_build_context(*, decoder_directory, wheel_source, publisher_receipt,
                          publisher_sha256, metadata_directory, destination):
    """Copy exact reviewed source and six wheels; partial failures stay retained."""
    decoder, source, receipt, metadata, output = map(absolute, (
        decoder_directory, wheel_source, publisher_receipt, metadata_directory, destination))
    if any(output == p or output.is_relative_to(p) or p.is_relative_to(output)
           for p in (decoder, source, metadata, receipt.parent)):
        deny("input_output_overlap")
    budget = Budget()
    roots = {p: directory_identity(p) for p in (decoder, source, metadata, receipt.parent)}
    pinned = read_file(receipt, budget, MAX_RECEIPT)
    if pinned.sha256 != digest(publisher_sha256):
        deny("publisher_receipt_pin_mismatch")
    document = strict_json(pinned.data)
    keys(document, ("format", "platform", "lock_sha256", "wheels"))
    if document["format"] != FORMAT or document["platform"] != PLATFORM:
        deny("unsupported_publisher_receipt")
    lock = read_file(decoder / "requirements.lock", budget, MAX_RECEIPT)
    if digest(document["lock_sha256"]) != lock.sha256:
        deny("publisher_lock_mismatch")
    locked = parse_lock(lock.data)
    rows = document["wheels"]
    if not isinstance(rows, list) or len(rows) != 6:
        deny("exact_six_publisher_wheels_required")
    selected, filenames, metadata_names, observations = set(), set(), set(), [(receipt, pinned, MAX_RECEIPT)]
    source_files = {"requirements.lock": lock}
    publisher_files = {"publisher-receipt.json": pinned}
    for name in ("Dockerfile", "decoder.py", "server.py"):
        source_files[name] = read_file(decoder / name, budget, MAX_METADATA)
    observations += [(decoder / name, observed, MAX_METADATA) for name, observed in source_files.items()]
    wheels = []
    for row in rows:
        validate_wheel_row(row, locked)
        if row["package"] in selected or row["filename"] in filenames or row["metadata_filename"] in metadata_names:
            deny("duplicate_publisher_mapping")
        selected.add(row["package"]); filenames.add(row["filename"]); metadata_names.add(row["metadata_filename"])
        primary = read_file(metadata / row["metadata_filename"], budget, MAX_METADATA)
        if primary.sha256 != row["metadata_sha256"]:
            deny("publisher_metadata_pin_mismatch")
        validate_release(primary.data, row)
        publisher_files[row["metadata_filename"]] = primary
        wheel = read_file(source / row["filename"], budget, MAX_WHEEL)
        if wheel.sha256 != row["sha256"] or wheel.size != row["size"]:
            deny("wheel_bytes_mismatch")
        observations += [(metadata / row["metadata_filename"], primary, MAX_METADATA),
                         (source / row["filename"], wheel, MAX_WHEEL)]
        wheels.append((row, wheel))
    if selected != PACKAGES:
        deny("exact_six_publisher_wheels_required")
    output = new_directory(output)
    wheelhouse = new_directory(output / "wheelhouse")
    publisher_output = new_directory(output.with_name(output.name + "-publisher-inputs"))
    roots.update({p: directory_identity(p) for p in (output, wheelhouse, publisher_output)})
    for name, observed in source_files.items():
        write_new(output, name, observed.data)
    for row, observed in wheels:
        write_new(wheelhouse, row["filename"], observed.data)
    for name, observed in publisher_files.items():
        write_new(publisher_output, name, observed.data)
    for path, before, maximum in observations:
        after = read_file(path, budget, maximum)
        if before.fingerprint != after.fingerprint or before.sha256 != after.sha256:
            deny("input_changed_during_copy")
    copied, copied_observations = {}, []
    for name, before in source_files.items():
        after = read_file(output / name, budget, MAX_METADATA)
        if after.sha256 != before.sha256:
            deny("copied_source_mismatch")
        copied[name] = after.sha256
        copied_observations.append((output / name, after))
    for row, before in wheels:
        after = read_file(wheelhouse / row["filename"], budget, MAX_WHEEL)
        if after.sha256 != before.sha256 or after.size != before.size:
            deny("copied_wheel_mismatch")
        copied_observations.append((wheelhouse / row["filename"], after))
    copied_publisher = {}
    for name, before in publisher_files.items():
        after = read_file(publisher_output / name, budget, MAX_METADATA)
        if after.sha256 != before.sha256 or after.size != before.size:
            deny("copied_publisher_mismatch")
        copied_publisher[name] = after.sha256
        copied_observations.append((publisher_output / name, after))
    if names(wheelhouse) != filenames or names(output) != set(source_files) | {"wheelhouse"}:
        deny("unexpected_copied_context_paths")
    if names(publisher_output) != set(publisher_files):
        deny("unexpected_copied_publisher_paths")
    if any(directory_identity(path) != expected for path, expected in roots.items()):
        deny("directory_identity_changed")
    for path, observed, _ in observations:
        recheck_file(path, observed.fingerprint)
    for path, observed in copied_observations:
        if observed.mode != 0o444:
            deny("copied_file_mode_mismatch")
        recheck_file(path, observed.fingerprint)
    budget.check()
    return {"format": "collect_roster_prepared_context_v1", "context": str(output), "wheelhouse": str(wheelhouse),
            "publisher_inputs": str(publisher_output), "publisher_before_copy_after_sha256": copied_publisher,
            "publisher_receipt_sha256": pinned.sha256, "lock_sha256": lock.sha256,
            "context_directory_identity": roots[output], "wheelhouse_directory_identity": roots[wheelhouse],
            "publisher_directory_identity": roots[publisher_output],
            "copied_files": [{"path": str(path), "sha256": observed.sha256,
                              "size": observed.size, "fingerprint": observed.fingerprint}
                             for path, observed in copied_observations],
            "platform": PLATFORM, "source_before_copy_after_sha256": copied,
            "wheels": [{key: row[key] for key in WHEEL_KEYS} for row, _ in wheels],
            "wheel_count": 6, "wheel_bytes": sum(observed.size for _, observed in wheels),
            "source_before_copy_after_equal": True, "wheel_before_copy_after_equal": True,
            "network_acquisition_performed": False, "package_installation_performed": False,
            "docker_execution_performed": False}


def verify_prepared_context(prepared):
    """Recheck the returned, pinned preparation immediately before Docker consumes it."""
    budget = Budget()
    observations = []
    roots = [(absolute(prepared[key]), tuple(prepared[identity_key])) for key, identity_key in (
        ("context", "context_directory_identity"), ("wheelhouse", "wheelhouse_directory_identity"),
        ("publisher_inputs", "publisher_directory_identity"))]
    for row in prepared["copied_files"]:
        path = absolute(row["path"])
        current = read_file(path, budget, MAX_WHEEL)
        if (current.sha256 != row["sha256"] or current.size != row["size"] or current.mode != 0o444
                or current.fingerprint != tuple(row["fingerprint"])):
            deny("prepared_context_changed")
        observations.append((path, current))
    context, wheelhouse, publisher = (p for p, _ in roots)
    if (names(context) != set(prepared["source_before_copy_after_sha256"]) | {"wheelhouse"}
            or names(wheelhouse) != {r["filename"] for r in prepared["wheels"]}
            or names(publisher) != set(prepared["publisher_before_copy_after_sha256"])):
        deny("unexpected_copied_context_paths")
    if any(directory_identity(path) != expected for path, expected in roots):
        deny("directory_identity_changed")
    for path, observed in observations:
        recheck_file(path, observed.fingerprint)
    budget.check()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--decoder-directory", type=Path, required=True)
    parser.add_argument("--wheel-source", type=Path, required=True)
    parser.add_argument("--publisher-receipt", type=Path, required=True)
    parser.add_argument("--publisher-sha256", required=True)
    parser.add_argument("--metadata-directory", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = prepare_build_context(decoder_directory=args.decoder_directory, wheel_source=args.wheel_source,
            publisher_receipt=args.publisher_receipt, publisher_sha256=args.publisher_sha256,
            metadata_directory=args.metadata_directory, destination=args.destination)
        print(json.dumps(result, sort_keys=True))
        return 0
    except WheelhouseError as error:
        print(json.dumps({"status": "fail", "code": str(error), "network_acquisition_performed": False}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
