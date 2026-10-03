#!/usr/bin/env python3
"""Read-only, explicitly pinned evidence relocation reader.

This reader neither runs an archive engine nor establishes restore acceptance.
An authorized caller must first pin independently verified file-cohort receipts.
Database backup/restore receipts are not file-cohort authority. Verified reads
return immutable bytes; no unchecked payload path is handed to a consumer.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import time
from typing import Any, Iterable


class EvidenceResolutionError(Exception):
    """Fixed denial code, deliberately excluding raw paths/body/OS errors."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def _deny(code: str) -> None:
    raise EvidenceResolutionError(code)


def _keys(value: Any, expected: Iterable[str]) -> dict:
    if not isinstance(value, dict) or set(value) != set(expected):
        _deny("invalid_schema")
    return value


def _text(value: Any, maximum: int = 256) -> str:
    if (not isinstance(value, str) or not value or len(value) > maximum
            or any(ord(c) < 32 or ord(c) == 127 or 0xD800 <= ord(c) <= 0xDFFF for c in value)):
        _deny("invalid_identity")
    return value


def _digest(value: Any) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        _deny("invalid_digest")
    return value


def _integer(value: Any, minimum: int, maximum: int) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        _deny("invalid_integer")
    return value


def _parts(value: Any, *, absolute: bool = False) -> tuple[str, ...]:
    value = _text(value, 4096)
    if "\\" in value or any(c in value for c in "*?[]"):
        _deny("unsafe_path")
    if absolute:
        if not value.startswith("/") or value.startswith("//"):
            _deny("unsafe_path")
        value = value[1:]
    elif value.startswith("/"):
        _deny("unsafe_path")
    parts = tuple(value.split("/"))
    if any(not p or p in (".", "..") or len(p.encode("utf-8")) > 255 for p in parts):
        _deny("unsafe_path")
    return parts


def _duplicate_keys(pairs: list[tuple[str, Any]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            _deny("duplicate_json_key")
        result[key] = value
    return result


def _json(raw: bytes) -> dict:
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_duplicate_keys,
                           parse_constant=lambda _: _deny("invalid_json"))
    except EvidenceResolutionError:
        raise
    except (ValueError, UnicodeError, RecursionError):
        _deny("invalid_json")
    if not isinstance(value, dict):
        _deny("invalid_schema")
    return value


@dataclass(frozen=True)
class Limits:
    metadata_bytes: int = 4 * 1024 * 1024
    native_receipt_bytes: int = 16 * 1024 * 1024
    file_bytes: int = 128 * 1024 * 1024
    total_bytes: int = 512 * 1024 * 1024
    entries: int = 4096
    anchors: int = 256
    seconds: float = 30.0

    def __post_init__(self):
        for value in (self.metadata_bytes, self.native_receipt_bytes, self.file_bytes,
                      self.total_bytes, self.entries, self.anchors):
            if type(value) is not int or value <= 0:
                _deny("invalid_limits")
        if (type(self.seconds) not in (int, float) or not 0 < self.seconds <= 300
                or self.total_bytes > 4 * 1024 ** 3 or self.file_bytes > 1024 ** 3
                or self.metadata_bytes > 16 * 1024 ** 2
                or self.native_receipt_bytes > 64 * 1024 ** 2
                or self.entries > 65536 or self.anchors > 4096):
            _deny("invalid_limits")


class _Budget:
    def __init__(self, limits: Limits):
        self.limits = limits
        self.deadline = time.monotonic() + limits.seconds
        self.used = 0

    def check(self, count: int = 0):
        self.used += count
        if self.used > self.limits.total_bytes:
            _deny("read_budget_exceeded")
        if time.monotonic() > self.deadline:
            _deny("read_deadline_exceeded")


@dataclass(frozen=True)
class _Root:
    path: str
    device: str
    inode: str
    mode: int

    @classmethod
    def parse(cls, value: Any):
        _keys(value, ("path", "device", "inode", "mode"))
        _parts(value["path"], absolute=True)
        if (not isinstance(value["device"], str) or not value["device"].isdigit()
                or not isinstance(value["inode"], str) or not value["inode"].isdigit()):
            _deny("invalid_root_identity")
        return cls(value["path"], value["device"], value["inode"],
                   _integer(value["mode"], 0, 0o7777))

    def matches(self, info: os.stat_result) -> bool:
        return (stat.S_ISDIR(info.st_mode) and str(info.st_dev) == self.device
                and str(info.st_ino) == self.inode and stat.S_IMODE(info.st_mode) == self.mode)


@dataclass(frozen=True)
class _Artifact:
    path: str
    sha256: str
    size: int

    @classmethod
    def parse(cls, value: Any, maximum: int):
        _keys(value, ("path", "sha256", "size"))
        _parts(value["path"], absolute=True)
        return cls(value["path"], _digest(value["sha256"]),
                   _integer(value["size"], 1, maximum))


@dataclass(frozen=True)
class _File:
    sha256: str
    size: int
    mode: int
    mtime_ns: int
    data: bytes | None
    fingerprint: tuple


def _identity(info: os.stat_result, directory: bool = False) -> tuple:
    identity = (info.st_dev, info.st_ino, stat.S_IMODE(info.st_mode))
    return identity if directory else identity + (info.st_size, info.st_mtime_ns,
                                                   info.st_ctime_ns, info.st_nlink)


def _directories_check(edges: list[tuple[int, str, int, tuple]], root: _Root | None,
                       root_fd: int | None):
    for parent_fd, component, child_fd, expected in edges:
        named = os.stat(component, dir_fd=parent_fd, follow_symlinks=False)
        if (not stat.S_ISDIR(named.st_mode) or _identity(named, True) != expected
                or _identity(os.fstat(child_fd), True) != expected):
            _deny("path_changed_during_read")
    if root and (root_fd is None or not root.matches(os.fstat(root_fd))):
        _deny("root_identity_mismatch")


def _read_file(root: _Root | None, path: str, budget: _Budget, maximum: int,
               *, collect: bool, private: bool = False, missing_ok: bool = False,
               observe_only: bool = False) -> _File | None:
    """Open every ancestor without following links; recheck names and FDs."""
    if not all(hasattr(os, name) for name in ("O_DIRECTORY", "O_NOFOLLOW", "O_NONBLOCK")):
        _deny("unsupported_filesystem_guards")
    relative = _parts(path, absolute=root is None)
    prefix = _parts(root.path, absolute=True) if root else ()
    components = prefix + relative
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    file_flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    directories: list[int] = []
    edges: list[tuple[int, str, int, tuple]] = []
    file_fd = None
    root_fd = None
    try:
        budget.check()
        directories.append(os.open("/", directory_flags))
        for number, component in enumerate(components[:-1], 1):
            parent_fd = directories[-1]
            child_fd = os.open(component, directory_flags, dir_fd=parent_fd)
            info = os.fstat(child_fd)
            directories.append(child_fd)
            edges.append((parent_fd, component, child_fd, _identity(info, True)))
            if root and number == len(prefix):
                root_fd = child_fd
                if not root.matches(info):
                    _deny("root_identity_mismatch")
        if root and root_fd is None:
            _deny("root_identity_mismatch")
        file_fd = os.open(components[-1], file_flags, dir_fd=directories[-1])
        before = os.fstat(file_fd)
        mode = stat.S_IMODE(before.st_mode)
        if not stat.S_ISREG(before.st_mode):
            _deny("nonregular_file")
        if before.st_nlink != 1:
            _deny("file_alias")
        if private and mode not in (0o400, 0o600):
            _deny("unprotected_metadata")
        if before.st_size > maximum:
            _deny("file_size_limit")
        digest = hashlib.sha256()
        chunks = [] if collect else None
        size = 0
        while not observe_only:
            budget.check()
            chunk = os.read(file_fd, min(1024 * 1024, maximum - size + 1))
            if not chunk:
                break
            size += len(chunk)
            budget.check(len(chunk))
            if size > maximum or size > before.st_size:
                _deny("file_changed_during_read")
            digest.update(chunk)
            if chunks is not None:
                chunks.append(chunk)
        after = os.fstat(file_fd)
        named = os.stat(components[-1], dir_fd=directories[-1], follow_symlinks=False)
        if ((not observe_only and size != before.st_size) or _identity(before) != _identity(after)
                or _identity(before) != _identity(named)):
            _deny("file_changed_during_read")
        _directories_check(edges, root, root_fd)
        budget.check()
        return _File(digest.hexdigest(), before.st_size, mode, before.st_mtime_ns,
                     b"".join(chunks) if chunks is not None else None, _identity(before))
    except EvidenceResolutionError:
        raise
    except OSError as error:
        if error.errno == errno.ENOENT:
            if missing_ok and root_fd is not None and root.matches(os.fstat(root_fd)):
                try:
                    _directories_check(edges, root, root_fd)
                except OSError:
                    _deny("path_changed_during_read")
                budget.check()
                return None
            _deny("artifact_missing")
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            _deny("unsafe_path")
        _deny("artifact_unavailable")
    finally:
        if file_fd is not None:
            os.close(file_fd)
        for fd in reversed(directories):
            os.close(fd)


def _read_pin(pin: _Artifact, budget: _Budget, maximum: int, *, collect: bool) -> bytes | None:
    result = _read_file(None, pin.path, budget, maximum, collect=collect, private=True)
    if result.sha256 != pin.sha256 or result.size != pin.size:
        _deny("pinned_artifact_mismatch")
    return result.data


@dataclass(frozen=True)
class OriginalReference:
    original_path: str
    sha256: str
    source_epoch: str

    def __post_init__(self):
        _parts(self.original_path)
        _digest(self.sha256)
        _text(self.source_epoch)


@dataclass(frozen=True)
class Resolution:
    original_path: str
    sha256: str
    size: int
    mode: int
    original_present: bool


IDENTITY_KEYS = ("source_repository_id", "source_epoch", "source_manifest_sha256",
                 "repository_id", "snapshot_id")
ENTRY_KEYS = ("original_path", "snapshot_path", "sha256", "size", "mode", "source_mtime_ns")
PIN_KEYS = ("catalog", "engine_receipt", "engine_native_receipt", "restore_receipt", "restore_native_receipt")


class EvidenceResolver:
    @classmethod
    def from_pinned_config(cls, path: str | Path | None, sha256: str | None,
                           *, limits: Limits | None = None):
        if path is None or sha256 is None:
            _deny("trusted_inputs_required")
        limits = limits or Limits()
        expected = _digest(sha256)
        actual = _read_file(None, str(path), _Budget(limits), limits.metadata_bytes,
                            collect=True, private=True)
        if actual.sha256 != expected:
            _deny("trust_document_mismatch")
        return cls(_Artifact(str(path), expected, actual.size), _json(actual.data), limits)

    def __init__(self, trust_pin: _Artifact, document: dict, limits: Limits):
        expected_keys = ("format", *IDENTITY_KEYS, "source_root", "payload_root", "engine",
                         *PIN_KEYS, "source_anchors")
        _keys(document, expected_keys)
        if document["format"] != "collect_evidence_resolution_trust_v1":
            _deny("unsupported_trust_format")
        self._limits = limits
        self._trust_pin = trust_pin
        self._identity = {key: _digest(document[key]) if key.endswith("sha256") or key in
                          ("repository_id", "snapshot_id") else _text(document[key]) for key in IDENTITY_KEYS}
        self._source = _Root.parse(document["source_root"])
        self._payload = _Root.parse(document["payload_root"])
        source_path, payload_path = Path(self._source.path), Path(self._payload.path)
        if source_path.is_relative_to(payload_path) or payload_path.is_relative_to(source_path):
            _deny("overlapping_source_and_restore")
        if self._payload.mode not in (0o500, 0o700):
            _deny("unprotected_restore_root")
        _keys(document["engine"], ("name", "version", "executable_sha256"))
        self._engine = {"name": _text(document["engine"]["name"]),
                        "version": _text(document["engine"]["version"]),
                        "executable_sha256": _digest(document["engine"]["executable_sha256"])}
        self._pins = {key: _Artifact.parse(document[key], limits.native_receipt_bytes if "native" in key
                                          else limits.metadata_bytes) for key in PIN_KEYS}
        for pin in (trust_pin, *self._pins.values()):
            if Path(pin.path).is_relative_to(source_path) or Path(pin.path).is_relative_to(payload_path):
                _deny("metadata_must_be_out_of_band")
        if len({pin.path for pin in (trust_pin, *self._pins.values())}) != 6:
            _deny("duplicate_artifact_paths")
        anchors = document["source_anchors"]
        if not isinstance(anchors, list) or not 1 <= len(anchors) <= limits.anchors:
            _deny("invalid_source_anchors")
        self._anchors = []
        for anchor in anchors:
            _keys(anchor, ("path", "sha256", "size", "mode"))
            _parts(anchor["path"])
            self._anchors.append((anchor["path"], _digest(anchor["sha256"]),
                                  _integer(anchor["size"], 1, limits.metadata_bytes),
                                  _integer(anchor["mode"], 0, 0o7777)))
        if len({a[0] for a in self._anchors}) != len(self._anchors):
            _deny("duplicate_source_anchors")
        if self._identity["source_manifest_sha256"] not in {a[1] for a in self._anchors}:
            _deny("original_manifest_anchor_required")

    def _anchors_check(self, budget: _Budget):
        for path, digest, size, mode in self._anchors:
            actual = _read_file(self._source, path, budget, self._limits.metadata_bytes, collect=False)
            if (actual.sha256, actual.size, actual.mode) != (digest, size, mode):
                _deny("source_index_drift")

    def _pins_check(self, budget: _Budget):
        _read_pin(self._trust_pin, budget, self._limits.metadata_bytes, collect=False)
        for key, pin in self._pins.items():
            _read_pin(pin, budget, self._limits.native_receipt_bytes if "native" in key
                      else self._limits.metadata_bytes, collect=False)
        self._anchors_check(budget)

    def _entries(self, value: Any) -> dict[str, dict]:
        if not isinstance(value, list) or not 1 <= len(value) <= self._limits.entries:
            _deny("invalid_catalog_entries")
        entries = {}
        snapshot_paths = set()
        for row in value:
            _keys(row, ENTRY_KEYS)
            _parts(row["original_path"])
            _parts(row["snapshot_path"])
            _digest(row["sha256"])
            _integer(row["size"], 1, self._limits.file_bytes)
            _integer(row["mode"], 0, 0o7777)
            _integer(row["source_mtime_ns"], 0, 2 ** 63 - 1)
            if row["original_path"] in entries or row["snapshot_path"] in snapshot_paths:
                _deny("duplicate_catalog_mapping")
            entries[row["original_path"]] = row
            snapshot_paths.add(row["snapshot_path"])
        return entries

    def _identity_check(self, document: dict):
        for key, value in self._identity.items():
            if document[key] != value:
                _deny("evidence_identity_mismatch")

    def _bundle(self, budget: _Budget) -> dict[str, dict]:
        _read_pin(self._trust_pin, budget, self._limits.metadata_bytes, collect=False)
        docs = {key: _json(_read_pin(self._pins[key], budget, self._limits.metadata_bytes, collect=True))
                for key in ("catalog", "engine_receipt", "restore_receipt")}
        for key in ("engine_native_receipt", "restore_native_receipt"):
            _read_pin(self._pins[key], budget, self._limits.native_receipt_bytes, collect=False)
        catalog = docs["catalog"]
        _keys(catalog, ("format", *IDENTITY_KEYS, "entries"))
        if catalog["format"] != "collect_evidence_relocation_v1":
            _deny("unsupported_catalog_format")
        self._identity_check(catalog)
        entries = self._entries(catalog["entries"])
        engine = docs["engine_receipt"]
        common = ("format", "status", "scope", *IDENTITY_KEYS, "engine", "catalog_sha256", "native_receipt_sha256")
        _keys(engine, (*common, "full_data_integrity", "encrypted_repository_verified"))
        if (engine["format"] != "collect_evidence_engine_verification_v1" or engine["status"] != "verified"
                or engine["scope"] != "complete_file_cohort" or engine["full_data_integrity"] is not True
                or engine["encrypted_repository_verified"] is not True):
            _deny("verified_file_cohort_engine_receipt_required")
        self._identity_check(engine)
        if (engine["engine"] != self._engine or engine["catalog_sha256"] != self._pins["catalog"].sha256
                or engine["native_receipt_sha256"] != self._pins["engine_native_receipt"].sha256):
            _deny("engine_receipt_binding_mismatch")
        restored = docs["restore_receipt"]
        _keys(restored, (*common, "engine_receipt_sha256", "independent_verification", "payload_root", "files"))
        if (restored["format"] != "collect_evidence_restore_verification_v1" or restored["status"] != "verified"
                or restored["scope"] != "complete_file_cohort" or restored["independent_verification"] is not True):
            _deny("independent_file_cohort_restore_receipt_required")
        self._identity_check(restored)
        if (restored["engine"] != self._engine or restored["catalog_sha256"] != self._pins["catalog"].sha256
                or restored["native_receipt_sha256"] != self._pins["restore_native_receipt"].sha256
                or restored["engine_receipt_sha256"] != self._pins["engine_receipt"].sha256
                or _Root.parse(restored["payload_root"]) != self._payload):
            _deny("restore_receipt_binding_mismatch")
        if self._entries(restored["files"]) != entries:
            _deny("partial_or_conflicting_restore_receipt")
        self._anchors_check(budget)
        return entries

    def _resolve(self, reference: OriginalReference, entries: dict, budget: _Budget,
                 *, collect: bool) -> tuple[Resolution, bytes | None, tuple]:
        if not isinstance(reference, OriginalReference):
            _deny("invalid_reference")
        if reference.source_epoch != self._identity["source_epoch"]:
            _deny("reference_epoch_mismatch")
        row = entries.get(reference.original_path)
        if row is None:
            _deny("original_path_not_cataloged")
        if row["sha256"] != reference.sha256:
            _deny("original_digest_conflict")
        restored = _read_file(self._payload, row["snapshot_path"], budget,
                              self._limits.file_bytes, collect=collect)
        expected = (row["sha256"], row["size"], row["mode"])
        if (restored.sha256, restored.size, restored.mode) != expected:
            _deny("restored_payload_mismatch")
        original = _read_file(self._source, row["original_path"], budget,
                              self._limits.file_bytes, collect=False, missing_ok=True)
        if original is not None and ((original.sha256, original.size, original.mode) != expected
                                    or original.mtime_ns != row["source_mtime_ns"]):
            _deny("original_source_drift")
        return Resolution(reference.original_path, restored.sha256, restored.size,
                          restored.mode, original is not None), restored.data, (
                              (self._payload, row["snapshot_path"], restored, False),
                              (self._source, row["original_path"], original, True))

    def _observations_check(self, observations: Iterable[tuple], budget: _Budget):
        # Whole-byte hashes above remain authoritative. This final descriptor
        # fence detects replacements/in-place changes during later metadata reads
        # without returning a pathname or multiplying whole-cohort byte reads.
        for root, path, expected, missing_ok in observations:
            actual = _read_file(root, path, budget, self._limits.file_bytes,
                                collect=False, missing_ok=missing_ok, observe_only=True)
            if ((expected is None) != (actual is None) or
                    (expected is not None and expected.fingerprint != actual.fingerprint)):
                _deny("file_changed_after_read")

    def read_bytes(self, reference: OriginalReference) -> bytes:
        budget = _Budget(self._limits)
        entries = self._bundle(budget)
        _, data, observations = self._resolve(reference, entries, budget, collect=True)
        self._pins_check(budget)
        self._observations_check(observations, budget)
        return data

    def verify_reference(self, reference: OriginalReference) -> Resolution:
        return self.verify_many((reference,))[0]

    def verify_many(self, references: Iterable[OriginalReference]) -> tuple[Resolution, ...]:
        budget = _Budget(self._limits)
        bounded = []
        try:
            iterator = iter(references)
        except TypeError:
            _deny("invalid_references")
        for reference in iterator:
            budget.check()
            if len(bounded) == self._limits.entries:
                _deny("invalid_references")
            bounded.append(reference)
        references = tuple(bounded)
        if not 1 <= len(references) <= self._limits.entries or any(not isinstance(r, OriginalReference) for r in references):
            _deny("invalid_references")
        if len({r.original_path for r in references}) != len(references):
            _deny("duplicate_references")
        entries = self._bundle(budget)
        resolved = tuple(self._resolve(reference, entries, budget, collect=False) for reference in references)
        self._pins_check(budget)
        self._observations_check((observation for result in resolved for observation in result[2]), budget)
        return tuple(result[0] for result in resolved)


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        _deny("invalid_arguments")


def main(argv: list[str] | None = None) -> int:
    parser = _Parser(description=__doc__)
    parser.add_argument("--trust-config")
    parser.add_argument("--trust-sha256")
    parser.add_argument("--original-path")
    parser.add_argument("--original-sha256")
    parser.add_argument("--epoch")
    try:
        args = parser.parse_args(argv)
        resolver = EvidenceResolver.from_pinned_config(args.trust_config, args.trust_sha256)
        result = resolver.verify_reference(OriginalReference(args.original_path, args.original_sha256, args.epoch))
        print(json.dumps({"status": "verified_reference_bytes", "sha256": result.sha256,
                          "size": result.size, "mode": result.mode, "original_present": result.original_present,
                          "archive_or_restore_operations_performed": False,
                          "production_release_approved": False}, sort_keys=True))
        return 0
    except EvidenceResolutionError as error:
        print(json.dumps({"status": "unresolved", "code": error.code,
                          "archive_or_restore_operations_performed": False,
                          "production_release_approved": False}, sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
