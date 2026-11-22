#!/usr/bin/env python3
"""Pinned offline preparation plus separate explicit bounded PyPI acquisition.

The publisher-input receipt's expected SHA is supplied out of band by its
authorized producer. Origin acquisition is a separate, bounded HTTPS stage.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import stat
import signal
import ssl
import subprocess
import sys
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
    if (not isinstance(url, str) or len(url) > 2048
            or any(ord(c) < 32 or ord(c) == 127 or ord(c) > 126 for c in url)):
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


def publisher_fetch(url, destination, maximum, expected_sha=None, expected_size=None):
    """One direct verified-TLS request; called only in its bounded owned child.

    No proxy/environment handler, redirects, cookies, credentials or retry. A
    partial private body remains on failure but no trusted receipt is minted.
    """
    if isinstance(url, str) and url.startswith("https://pypi.org/"):
        origin(url, "pypi.org", "/pypi/")
    else:
        origin(url, "files.pythonhosted.org", "/packages/")
    parsed = urlsplit(url)
    if type(maximum) is not int or not 1 <= maximum <= MAX_WHEEL:
        deny("invalid_download_bound")
    if expected_sha is not None:
        digest(expected_sha)
    if expected_size is not None and (type(expected_size) is not int or not 1 <= expected_size <= maximum):
        deny("invalid_download_bound")
    path = absolute(destination)
    fds, edges = directories(path.parent)
    fd, connection = None, None
    try:
        connection = http.client.HTTPSConnection(parsed.netloc, 443, timeout=10,
                                                context=ssl.create_default_context())
        connection.request("GET", parsed.path, headers={"User-Agent": "Collect-wheelhouse-verifier/1",
                           "Accept-Encoding": "identity", "Connection": "close"})
        response = connection.getresponse()
        if response.status != 200:
            deny("publisher_http_status_denied")
        if response.getheader("Content-Encoding", "identity") != "identity":
            deny("publisher_content_encoding_denied")
        length = response.getheader("Content-Length")
        if length is not None and (not re.fullmatch(r"[0-9]{1,10}", length)
                                   or not 1 <= int(length) <= maximum
                                   or expected_size is not None and int(length) != expected_size):
            deny("publisher_content_length_denied")
        fd = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fds[-1])
        sha, size = hashlib.sha256(), 0
        while chunk := response.read(64 * 1024):
            size += len(chunk)
            if size > maximum or expected_size is not None and size > expected_size:
                deny("publisher_body_limit")
            sha.update(chunk)
            remaining = memoryview(chunk)
            while remaining:
                written = os.write(fd, remaining)
                if not written:
                    deny("publisher_body_write_failed")
                remaining = remaining[written:]
        actual_sha = sha.hexdigest()
        if (not size or length is not None and size != int(length)
                or expected_size is not None and size != expected_size
                or expected_sha is not None and actual_sha != expected_sha):
            deny("publisher_body_identity_mismatch")
        os.fchmod(fd, 0o444); os.fsync(fd)
        actual, named = os.fstat(fd), os.stat(path.name, dir_fd=fds[-1], follow_symlinks=False)
        if actual.st_nlink != 1 or identity(actual) != identity(named):
            deny("file_changed")
        recheck_directories(edges)
        return {"sha256": actual_sha, "size": size, "tls_origin": parsed.netloc,
                "redirects_followed": 0, "request_count": 1}
    except (OSError, http.client.HTTPException):
        deny("publisher_transport_failed")
    finally:
        if connection is not None:
            connection.close()
        if fd is not None:
            os.close(fd)
        for retained in reversed(fds):
            os.close(retained)


def bounded_fetch_process(command, stdout_path, stderr_path, timeout, *, own_process_group=True,
                          deadline_code="publisher_request_deadline"):
    """Enforce the actual request deadline and reap only the owned child group."""
    with stdout_path.open("xb") as stdout, stderr_path.open("xb") as stderr:
        child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
            start_new_session=own_process_group, env={"PATH": os.defpath, "PYTHONDONTWRITEBYTECODE": "1"})
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                if own_process_group:
                    os.killpg(child.pid, signal.SIGKILL)
                else:
                    child.kill()
            except ProcessLookupError:
                pass
            child.wait(timeout=2)
            with stderr_path.open("ab") as evidence:
                evidence.write(b"OWNED_PUBLISHER_REQUEST_DEADLINE child_reaped=true\n")
            deny(deadline_code)
    if code:
        deny("publisher_request_failed")


def fetch_owned(*, url, path, maximum, log_directory, ordinal, timeout, expected_sha=None, expected_size=None):
    command = [sys.executable, "-B", str(Path(__file__).absolute()), "--fetch", "--url", url,
               "--destination", str(path), "--maximum", str(maximum)]
    if expected_sha is not None:
        command += ["--expected-sha256", expected_sha]
    if expected_size is not None:
        command += ["--expected-size", str(expected_size)]
    stdout, stderr = log_directory / f"request-{ordinal:02d}.stdout", log_directory / f"request-{ordinal:02d}.stderr"
    # The HTTPS child itself has no subprocesses. It remains inside the outer
    # acquisition worker group so the whole-stage supervisor can reap both.
    bounded_fetch_process(command, stdout, stderr, timeout, own_process_group=False)
    result = strict_json(read_file(stdout, Budget(), MAX_RECEIPT).data)
    keys(result, ("sha256", "size", "tls_origin", "redirects_followed", "request_count"))
    if (result["tls_origin"] != urlsplit(url).netloc or type(result["request_count"]) is not int
            or result["request_count"] != 1 or type(result["redirects_followed"]) is not int
            or result["redirects_followed"] != 0):
        deny("publisher_request_receipt_invalid")
    observed = read_file(path, Budget(), maximum)
    if observed.sha256 != digest(result["sha256"]) or type(result["size"]) is not int or observed.size != result["size"]:
        deny("publisher_request_body_mismatch")
    return observed


def release_row(primary, package, version, locked_sha):
    document = strict_json(primary.data)
    urls = document.get("urls")
    if not isinstance(urls, list) or len(urls) > 4096:
        deny("invalid_publisher_release")
    matches = [u for u in urls if isinstance(u, dict) and isinstance(u.get("digests"), dict)
               and u["digests"].get("sha256") == locked_sha]
    if len(matches) != 1:
        deny("publisher_locked_wheel_missing_or_duplicate")
    selected = matches[0]
    row = {"package": package, "version": version, "filename": selected.get("filename"),
           "sha256": locked_sha, "size": selected.get("size"),
           "metadata_filename": package + "-" + version + "-pypi.json",
           "metadata_sha256": primary.sha256, "metadata_url": "https://pypi.org/pypi/" + package + "/" + version + "/json",
           "wheel_url": selected.get("url")}
    validate_wheel_row(row, {package: (version, locked_sha)})
    validate_release(primary.data, row)
    return row


def acquire_publisher_inputs(*, lock_file, lock_sha256, destination):
    """Separate explicit acquisition mode, at most 12 requests / 300 seconds.

    The immutable reviewed lock pins wheel bytes. TLS metadata authenticates the
    official origin; receipt pins preserve that particular observation for CI.
    """
    lock_path, output = absolute(lock_file), absolute(destination)
    if output == lock_path.parent or output.is_relative_to(lock_path.parent) or lock_path.parent.is_relative_to(output):
        deny("input_output_overlap")
    lock = read_file(lock_path, Budget(), MAX_RECEIPT)
    if lock.sha256 != digest(lock_sha256):
        deny("publisher_lock_mismatch")
    locked = parse_lock(lock.data)
    root_identity = directory_identity(lock_path.parent)
    output = new_directory(output)
    metadata, wheels, logs = [new_directory(output / name) for name in ("primary", "wheels", "logs")]
    roots = {p: directory_identity(p) for p in (output, metadata, wheels, logs)}
    write_new(output, "requirements.lock", lock.data)
    result = {"status": "fail", "mode": "official_publisher_acquisition", "lock_sha256": lock.sha256,
              "wheel_count": 0, "requests": [], "request_retries": 0, "redirects_followed": 0,
              "whole_deadline_seconds": 300, "socket_timeout_seconds": 10,
              "network_acquisition_performed": True, "package_installation_performed": False,
              "docker_execution_performed": False}
    started, deadline = time.monotonic(), time.monotonic() + 300
    rows, observations = [], []
    try:
        for ordinal, (package, (version, locked_sha)) in enumerate(sorted(locked.items())):
            metadata_name = package + "-" + version + "-pypi.json"
            metadata_url = "https://pypi.org/pypi/" + package + "/" + version + "/json"
            for kind in ("metadata", "wheel"):
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    deny("publisher_whole_deadline")
                timeout = min(45 if kind == "metadata" else 60, remaining)
                if kind == "metadata":
                    url, path, maximum, expected_sha, expected_size = metadata_url, metadata / metadata_name, MAX_METADATA, None, None
                else:
                    url, path, maximum, expected_sha, expected_size = row["wheel_url"], wheels / row["filename"], MAX_WHEEL, locked_sha, row["size"]
                request = {"ordinal": ordinal * 2 + (kind == "wheel") + 1, "kind": kind,
                           "package": package, "version": version, "url": url,
                           "deadline_seconds": timeout, "status": "fail"}
                result["requests"].append(request)
                observed = fetch_owned(url=url, path=path, maximum=maximum, log_directory=logs,
                    ordinal=request["ordinal"], timeout=timeout, expected_sha=expected_sha, expected_size=expected_size)
                if kind == "metadata":
                    row = release_row(observed, package, version, locked_sha)
                elif observed.sha256 != locked_sha or observed.size != row["size"]:
                    deny("wheel_bytes_mismatch")
                if observed.mode != 0o444:
                    deny("publisher_download_mode_mismatch")
                observations.append((path, observed, maximum))
                request.update(status="pass", sha256=observed.sha256, size=observed.size)
            rows.append(row)
            result["wheel_count"] = len(rows)
        after = read_file(lock_path, Budget(), MAX_RECEIPT)
        if after.sha256 != lock.sha256 or after.fingerprint != lock.fingerprint or directory_identity(lock_path.parent) != root_identity:
            deny("input_changed_during_acquisition")
        if names(metadata) != {r["metadata_filename"] for r in rows} or names(wheels) != {r["filename"] for r in rows}:
            deny("unexpected_acquired_paths")
        for path, observed, maximum in observations:
            after = read_file(path, Budget(), maximum)
            if after.sha256 != observed.sha256 or after.fingerprint != observed.fingerprint:
                deny("acquired_input_changed")
        if any(directory_identity(p) != expected for p, expected in roots.items()):
            deny("directory_identity_changed")
        recheck_file(lock_path, lock.fingerprint)
        for path, observed, _ in observations:
            recheck_file(path, observed.fingerprint)
        if time.monotonic() > deadline:
            deny("publisher_whole_deadline")
        receipt = {"format": FORMAT, "platform": PLATFORM, "lock_sha256": lock.sha256, "wheels": rows}
        raw = (json.dumps(receipt, sort_keys=True, indent=2) + "\n").encode()
        write_new(output, "publisher-inputs.json", raw)
        result.update(status="pass", publisher_receipt=str(output / "publisher-inputs.json"),
                      publisher_sha256=hashlib.sha256(raw).hexdigest(), wheel_source=str(wheels),
                      metadata_directory=str(metadata), wheel_bytes=sum(r["size"] for r in rows))
    except WheelhouseError as error:
        result["code"] = str(error)
        raise
    finally:
        result["elapsed_seconds"] = time.monotonic() - started
        write_new(output, "acquisition-result.json", (json.dumps(result, sort_keys=True, indent=2) + "\n").encode())
    return result


def supervise_acquisition(*, lock_file, lock_sha256, destination):
    """Actual CLI whole-process deadline, including TLS/DNS and filesystem stalls."""
    output = absolute(destination)
    lock_path = absolute(lock_file)
    digest(lock_sha256)
    if output == lock_path.parent or output.is_relative_to(lock_path.parent) or lock_path.parent.is_relative_to(output):
        deny("input_output_overlap")
    if os.path.lexists(output):
        deny("fresh_private_destination_required")
    proof = new_directory(output.with_name(output.name + "-supervision"))
    command = [sys.executable, "-B", str(Path(__file__).absolute()), "--acquire-worker",
               "--lock-file", str(lock_path), "--lock-sha256", lock_sha256,
               "--destination", str(output)]
    record = {"status": "fail", "whole_deadline_seconds": 300,
              "owned_process_group": True, "automatic_retry_count": 0}
    started = time.monotonic()
    try:
        bounded_fetch_process(command, proof / "stdout.log", proof / "stderr.log", 300,
                              deadline_code="publisher_whole_deadline")
        result = strict_json(read_file(proof / "stdout.log", Budget(), MAX_RECEIPT).data)
        if (result.get("status") != "pass" or result.get("lock_sha256") != lock_sha256
                or type(result.get("wheel_count")) is not int or result["wheel_count"] != 6
                or not isinstance(result.get("requests"), list) or len(result["requests"]) != 12
                or any(not isinstance(r, dict) or r.get("status") != "pass" for r in result["requests"])):
            deny("publisher_acquisition_receipt_invalid")
        retained = strict_json(read_file(output / "acquisition-result.json", Budget(), MAX_RECEIPT).data)
        if result != retained:
            deny("publisher_acquisition_receipt_invalid")
        receipt = read_file(output / "publisher-inputs.json", Budget(), MAX_RECEIPT)
        if receipt.sha256 != digest(result.get("publisher_sha256")):
            deny("publisher_receipt_pin_mismatch")
        record["status"] = "pass"
        return result
    except WheelhouseError as error:
        record["code"] = str(error)
        raise
    finally:
        record["elapsed_seconds"] = time.monotonic() - started
        write_new(proof, "supervision-result.json", (json.dumps(record, sort_keys=True, indent=2) + "\n").encode())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--acquire", action="store_true", help="Explicit separate bounded official-publisher acquisition")
    mode.add_argument("--acquire-worker", action="store_true", help=argparse.SUPPRESS)
    mode.add_argument("--fetch", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--lock-file", type=Path)
    parser.add_argument("--lock-sha256")
    parser.add_argument("--url", help=argparse.SUPPRESS)
    parser.add_argument("--maximum", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--expected-sha256", help=argparse.SUPPRESS)
    parser.add_argument("--expected-size", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--decoder-directory", type=Path)
    parser.add_argument("--wheel-source", type=Path)
    parser.add_argument("--publisher-receipt", type=Path)
    parser.add_argument("--publisher-sha256")
    parser.add_argument("--metadata-directory", type=Path)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.fetch:
        if args.url is None or args.maximum is None:
            parser.error("Explicit bounded publisher URL and maximum required")
        if any(v is not None for v in (args.lock_file, args.lock_sha256, args.decoder_directory, args.wheel_source,
                                      args.publisher_receipt, args.publisher_sha256, args.metadata_directory)):
            parser.error("Bounded fetch and other preparation inputs must be separate")
    elif args.acquire or args.acquire_worker:
        if args.lock_file is None or args.lock_sha256 is None:
            parser.error("--lock-file and --lock-sha256 required for explicit acquisition")
        if any(v is not None for v in (args.decoder_directory, args.wheel_source, args.publisher_receipt, args.publisher_sha256,
                                      args.metadata_directory, args.url, args.maximum, args.expected_sha256, args.expected_size)):
            parser.error("Acquisition and installation preparation inputs must be separate")
    elif any(v is None for v in (args.decoder_directory, args.wheel_source, args.publisher_receipt, args.publisher_sha256, args.metadata_directory)):
        parser.error("Explicit --decoder-directory, --wheel-source, --publisher-receipt, --publisher-sha256 and --metadata-directory required")
    elif any(v is not None for v in (args.lock_file, args.lock_sha256, args.url, args.maximum, args.expected_sha256, args.expected_size)):
        parser.error("Acquisition and installation preparation inputs must be separate")
    try:
        if args.fetch:
            result = publisher_fetch(args.url, args.destination, args.maximum, args.expected_sha256, args.expected_size)
        elif args.acquire_worker:
            result = acquire_publisher_inputs(lock_file=args.lock_file, lock_sha256=args.lock_sha256, destination=args.destination)
        elif args.acquire:
            result = supervise_acquisition(lock_file=args.lock_file, lock_sha256=args.lock_sha256, destination=args.destination)
        else:
            result = prepare_build_context(decoder_directory=args.decoder_directory, wheel_source=args.wheel_source,
                publisher_receipt=args.publisher_receipt, publisher_sha256=args.publisher_sha256,
                metadata_directory=args.metadata_directory, destination=args.destination)
        print(json.dumps(result, sort_keys=True))
        return 0
    except WheelhouseError as error:
        print(json.dumps({"status": "fail", "code": str(error), "network_acquisition_performed": args.acquire or args.acquire_worker or args.fetch}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
