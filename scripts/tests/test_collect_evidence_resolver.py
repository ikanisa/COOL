#!/usr/bin/env python3
"""Synthetic filesystem falsifications; no archive/restore/engine acceptance."""
from __future__ import annotations

import contextlib
from copy import deepcopy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "audits/collect_evidence_resolver.py"
SPEC = importlib.util.spec_from_file_location("collect_evidence_resolver", MODULE_PATH)
resolver_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = resolver_module
SPEC.loader.exec_module(resolver_module)
EvidenceResolver = resolver_module.EvidenceResolver
EvidenceResolutionError = resolver_module.EvidenceResolutionError
Limits = resolver_module.Limits
OriginalReference = resolver_module.OriginalReference


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(document):
    return (json.dumps(document, sort_keys=True, ensure_ascii=True) + "\n").encode()


def root_identity(path):
    info = path.stat()
    return {"path": str(path), "device": str(info.st_dev), "inode": str(info.st_ino),
            "mode": stat.S_IMODE(info.st_mode)}


def write(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(mode)


class Fixture:
    """Structural receipt fixtures only; independently verified inputs are simulated."""
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory(prefix="collect-resolver-fixture-")
        self.base = Path(self.temp.name).resolve()
        self.source = self.base / "original-source"
        self.payload = self.base / "synthetic-restored-payload"
        self.metadata = self.base / "explicit-test-authority"
        for path in (self.source, self.payload, self.metadata):
            path.mkdir(mode=0o700)
            path.chmod(0o700)
        self.anchor = "indexes/original-manifest.json"
        self.anchor_bytes = b'{"scope":"synthetic-no-engine-no-real-restoration"}\n'
        write(self.source / self.anchor, self.anchor_bytes)
        self.identity = {"source_repository_id": "synthetic-collect-fixture",
                         "source_epoch": "synthetic-epoch-1",
                         "source_manifest_sha256": digest(self.anchor_bytes),
                         "repository_id": digest(b"synthetic-repository"),
                         "snapshot_id": digest(b"synthetic-full-snapshot")}
        self.engine_identity = {"name": "synthetic-test-engine", "version": "fixture-only",
                                "executable_sha256": digest(b"NOT an installed engine")}
        self.entries = []
        self.data = (b"synthetic alpha payload\x00not customer data\n",
                     b"synthetic beta payload\xffnot customer data\n")
        for index, name in enumerate(("alpha", "beta")):
            original = f"docs/evidence/{name}.bin"
            snapshot = f"cohort/{name}.bin"
            mode = 0o640 if index == 0 else 0o600
            write(self.source / original, self.data[index], mode)
            write(self.payload / snapshot, self.data[index], mode)
            self.entries.append({"original_path": original, "snapshot_path": snapshot,
                                 "sha256": digest(self.data[index]), "size": len(self.data[index]),
                                 "mode": mode, "source_mtime_ns": (self.source / original).stat().st_mtime_ns})
        self.paths = {key: self.metadata / (key + ".json") for key in
                      ("catalog", "engine_receipt", "restore_receipt")}
        self.paths.update({key: self.metadata / (key + ".log") for key in
                           ("engine_native_receipt", "restore_native_receipt")})
        self.config = self.metadata / "caller-pinned-trust.json"
        self.seal()

    def close(self):
        self.temp.cleanup()

    def artifact(self, key):
        path = self.paths[key]
        data = path.read_bytes()
        return {"path": str(path), "sha256": digest(data), "size": len(data)}

    def seal(self, *, catalog=None, engine=None, restored=None, trust=None,
             raw_catalog=None, raw_engine=None, raw_restore=None):
        # An intentionally re-pinned malicious fixture tests semantic checks.
        # Tamper tests instead edit bytes AFTER this operation, retaining old pins.
        self.catalog = {"format": "collect_evidence_relocation_v1", **self.identity,
                        "entries": deepcopy(self.entries)}
        if catalog:
            catalog(self.catalog)
        write(self.paths["catalog"], raw_catalog if raw_catalog is not None else json_bytes(self.catalog))
        for key in ("engine_native_receipt", "restore_native_receipt"):
            write(self.paths[key], b"FIXTURE ONLY: no archive engine or real restoration occurred.\n" + key.encode())
        self.engine = {"format": "collect_evidence_engine_verification_v1", "status": "verified",
                       "scope": "complete_file_cohort", **self.identity,
                       "engine": deepcopy(self.engine_identity),
                       "catalog_sha256": self.artifact("catalog")["sha256"],
                       "native_receipt_sha256": self.artifact("engine_native_receipt")["sha256"],
                       "full_data_integrity": True, "encrypted_repository_verified": True}
        if engine:
            engine(self.engine)
        write(self.paths["engine_receipt"], raw_engine if raw_engine is not None else json_bytes(self.engine))
        self.restored = {"format": "collect_evidence_restore_verification_v1", "status": "verified",
                         "scope": "complete_file_cohort", **self.identity,
                         "engine": deepcopy(self.engine_identity),
                         "catalog_sha256": self.artifact("catalog")["sha256"],
                         "native_receipt_sha256": self.artifact("restore_native_receipt")["sha256"],
                         "engine_receipt_sha256": self.artifact("engine_receipt")["sha256"],
                         "independent_verification": True, "payload_root": root_identity(self.payload),
                         "files": deepcopy(self.catalog["entries"])}
        if restored:
            restored(self.restored)
        write(self.paths["restore_receipt"], raw_restore if raw_restore is not None else json_bytes(self.restored))
        self.trust = {"format": "collect_evidence_resolution_trust_v1", **self.identity,
                      "source_root": root_identity(self.source), "payload_root": root_identity(self.payload),
                      "engine": deepcopy(self.engine_identity),
                      **{key: self.artifact(key) for key in self.paths},
                      "source_anchors": [{"path": self.anchor, "sha256": digest(self.anchor_bytes),
                                          "size": len(self.anchor_bytes), "mode": 0o600}]}
        if trust:
            trust(self.trust)
        write(self.config, json_bytes(self.trust))
        self.config_sha = digest(self.config.read_bytes())

    def resolver(self, limits=None):
        return EvidenceResolver.from_pinned_config(self.config, self.config_sha, limits=limits)

    def ref(self, index=0, **changes):
        values = {"original_path": self.entries[index]["original_path"],
                  "sha256": self.entries[index]["sha256"], "source_epoch": self.identity["source_epoch"]}
        values.update(changes)
        return OriginalReference(**values)

    def original(self, index=0):
        return self.source / self.entries[index]["original_path"]

    def restored_file(self, index=0):
        return self.payload / self.entries[index]["snapshot_path"]


class ResolverTest(unittest.TestCase):
    def setUp(self):
        self.f = Fixture()
        self.addCleanup(self.f.close)

    def denied(self, expected, action=None):
        with self.assertRaises(EvidenceResolutionError) as observed:
            (action or (lambda: self.f.resolver().verify_reference(self.f.ref())))()
        self.assertEqual(observed.exception.code, expected)
        self.assertEqual(str(observed.exception), expected)

    def test_present_original_and_whole_restored_bytes(self):
        reader = self.f.resolver()
        result = reader.verify_reference(self.f.ref())
        self.assertTrue(result.original_present)
        self.assertEqual((result.sha256, result.size, result.mode),
                         (digest(self.f.data[0]), len(self.f.data[0]), 0o640))
        self.assertEqual(reader.read_bytes(self.f.ref()), self.f.data[0])
        self.assertFalse(hasattr(result, "snapshot_path"))

    def test_absent_original_requires_full_verified_bundle(self):
        self.f.original().unlink()
        reader = self.f.resolver()
        self.assertFalse(reader.verify_reference(self.f.ref()).original_present)
        self.assertEqual(reader.read_bytes(self.f.ref()), self.f.data[0])
        self.f.paths["restore_receipt"].unlink()
        self.denied("artifact_missing", lambda: reader.read_bytes(self.f.ref()))

    def test_missing_original_parent_is_an_observation(self):
        self.f.original().unlink()
        self.f.original(1).unlink()
        self.f.original().parent.rmdir()
        self.assertFalse(self.f.resolver().verify_reference(self.f.ref()).original_present)

    def test_original_presence_is_never_a_trust_shortcut(self):
        self.denied("trusted_inputs_required", lambda: EvidenceResolver.from_pinned_config(None, None))
        self.f.paths["engine_native_receipt"].unlink()
        self.denied("artifact_missing")

    def test_original_path_and_digest_and_epoch_all_required(self):
        for changes, expected in (({"original_path": "docs/elsewhere/alpha.bin"}, "original_path_not_cataloged"),
                                  ({"sha256": digest(b"wrong digest")}, "original_digest_conflict"),
                                  ({"source_epoch": "later-epoch"}, "reference_epoch_mismatch")):
            with self.subTest(changes=changes):
                self.denied(expected, lambda: self.f.resolver().verify_reference(self.f.ref(**changes)))

    def test_batch_complete_and_duplicate_denial(self):
        reader = self.f.resolver()
        results = reader.verify_many((self.f.ref(), self.f.ref(1)))
        self.assertEqual([r.sha256 for r in results], [r["sha256"] for r in self.f.entries])
        self.denied("duplicate_references", lambda: reader.verify_many((self.f.ref(), self.f.ref())))
        self.f.restored_file(1).unlink()
        self.denied("artifact_missing", lambda: reader.verify_many((self.f.ref(), self.f.ref(1))))

    def test_invalid_empty_and_non_reference_batch(self):
        reader = self.f.resolver()
        for references in ((), None, ("an unchecked path",)):
            with self.subTest(references=references):
                self.denied("invalid_references", lambda: reader.verify_many(references))

    def test_unbounded_generator_stops_at_limit_plus_one(self):
        yielded = []
        def references():
            while True:
                yielded.append(1)
                yield self.f.ref()
        reader = self.f.resolver(Limits(entries=2))
        self.denied("invalid_references", lambda: reader.verify_many(references()))
        self.assertEqual(len(yielded), 3)

    def test_missing_each_authority_artifact_denies(self):
        for key in self.f.paths:
            with self.subTest(key=key):
                self.f.seal()
                self.f.paths[key].unlink()
                self.denied("artifact_missing")

    def test_catalog_tamper_even_after_reader_construction(self):
        reader = self.f.resolver()
        self.f.paths["catalog"].write_bytes(b"tampered catalog")
        self.denied("pinned_artifact_mismatch", lambda: reader.read_bytes(self.f.ref()))

    def test_native_receipt_tamper_denies(self):
        for key in ("engine_native_receipt", "restore_native_receipt"):
            with self.subTest(key=key):
                self.f.seal()
                self.f.paths[key].write_bytes(b"replaced native receipt")
                self.denied("pinned_artifact_mismatch")

    def test_caller_trust_digest_cannot_be_derived_from_tamper(self):
        self.f.config.write_bytes(b"replacement trust configuration")
        self.denied("trust_document_mismatch", self.f.resolver)

    def test_existing_reader_rechecks_pinned_trust(self):
        reader = self.f.resolver()
        self.f.config.write_bytes(b"late trust replacement")
        self.denied("pinned_artifact_mismatch", lambda: reader.read_bytes(self.f.ref()))

    def test_raw_database_backup_receipt_rejected(self):
        raw = json_bytes({"status": "DATABASE_ARCHIVE_CAPTURED_NOT_FULL_RECOVERY_ACCEPTANCE",
                          "encrypted_remount_hash_verified": True})
        self.f.seal(raw_engine=raw)
        self.denied("invalid_schema")

    def test_raw_production_database_restore_receipt_rejected(self):
        self.f.seal(raw_restore=json_bytes({"status": "pass", "roles": [], "catalog_verified": True}))
        self.denied("invalid_schema")

    def test_failed_partial_or_sampled_engine_scope_denies(self):
        for key, value in (("status", "failed"), ("status", "in_progress"), ("scope", "sampled"),
                           ("full_data_integrity", False), ("full_data_integrity", 1),
                           ("encrypted_repository_verified", False), ("encrypted_repository_verified", 1),
                           ("format", "database_archive_v1")):
            with self.subTest(key=key, value=value):
                self.f.seal(engine=lambda d: d.update({key: value}))
                self.denied("verified_file_cohort_engine_receipt_required")

    def test_unverified_or_partial_restore_scope_denies(self):
        for key, value in (("status", "failed"), ("scope", "subset"), ("independent_verification", False),
                           ("independent_verification", 1), ("format", "database_restore_v1")):
            with self.subTest(key=key, value=value):
                self.f.seal(restored=lambda d: d.update({key: value}))
                self.denied("independent_file_cohort_restore_receipt_required")

    def test_full_catalog_restore_membership_required(self):
        self.f.seal(restored=lambda d: d["files"].pop())
        self.denied("partial_or_conflicting_restore_receipt")
        self.f.seal(restored=lambda d: d["files"][0].update({"sha256": digest(b"other") }))
        self.denied("partial_or_conflicting_restore_receipt")

    def test_repository_snapshot_epoch_manifest_exact_in_all_receipts(self):
        for document in ("catalog", "engine", "restored"):
            for key in resolver_module.IDENTITY_KEYS:
                with self.subTest(document=document, key=key):
                    value = digest(b"wrong identity") if key.endswith("sha256") or key.endswith("id") else "wrong epoch"
                    self.f.seal(**{document: lambda d: d.update({key: value})})
                    self.denied("evidence_identity_mismatch")

    def test_partial_snapshot_identity_in_trust_denies(self):
        self.f.seal(trust=lambda d: d.update({"snapshot_id": d["snapshot_id"][:12]}))
        self.denied("invalid_digest", self.f.resolver)

    def test_engine_identity_and_native_binding_exact(self):
        for key in ("catalog_sha256", "native_receipt_sha256"):
            with self.subTest(key=key):
                self.f.seal(engine=lambda d: d.update({key: digest(b"mismatched binding")}))
                self.denied("engine_receipt_binding_mismatch")
        self.f.seal(engine=lambda d: d["engine"].update({"version": "other version"}))
        self.denied("engine_receipt_binding_mismatch")

    def test_restore_native_engine_and_catalog_associations_exact(self):
        for key in ("catalog_sha256", "native_receipt_sha256", "engine_receipt_sha256"):
            with self.subTest(key=key):
                self.f.seal(restored=lambda d: d.update({key: digest(b"mismatched binding")}))
                self.denied("restore_receipt_binding_mismatch")
        self.f.seal(restored=lambda d: d["engine"].update({"executable_sha256": digest(b"other engine")}))
        self.denied("restore_receipt_binding_mismatch")

    def test_duplicate_original_or_snapshot_paths_deny(self):
        for field in ("original_path", "snapshot_path"):
            with self.subTest(field=field):
                self.f.seal(catalog=lambda d: d["entries"][1].update({field: d["entries"][0][field]}))
                self.denied("duplicate_catalog_mapping")

    def test_duplicate_json_keys_cannot_select_a_second_mapping(self):
        raw = json_bytes(self.f.catalog).decode().replace('"format":', '"format":"forged", "format":', 1).encode()
        self.f.seal(raw_catalog=raw)
        self.denied("duplicate_json_key")

    def test_unknown_fields_fail_closed(self):
        for document in ("catalog", "engine", "restored", "trust"):
            with self.subTest(document=document):
                self.f.seal(**{document: lambda d: d.update({"unreviewed_override": True})})
                self.denied("invalid_schema")

    def test_invalid_json_constants_and_encoding_denied(self):
        for raw in (b"{\"format\":NaN}", b"{\"format\":Infinity}", b"\xff", b"[1,2]", b"{"):
            with self.subTest(raw=raw):
                self.f.seal(raw_catalog=raw)
                self.denied("invalid_schema" if raw == b"[1,2]" else "invalid_json")

    def test_surrogates_and_control_characters_denied(self):
        for path in ("bad\ud800", "bad\nname", "bad\x7fname"):
            with self.subTest(path=repr(path)):
                self.denied("invalid_identity", lambda: self.f.ref(original_path=path))

    def test_relative_path_traversal_absolute_glob_and_alias_denied(self):
        for path in ("../cohort/alpha.bin", "/cohort/alpha.bin", "cohort//alpha.bin", "./alpha.bin",
                     "cohort/../alpha.bin", "cohort/alpha*", "cohort\\alpha.bin", "cohort/alpha.bin/"):
            with self.subTest(path=path):
                self.denied("unsafe_path", lambda: self.f.ref(original_path=path))
                self.f.seal(catalog=lambda d: d["entries"][0].update({"snapshot_path": path}))
                self.denied("unsafe_path")

    def test_metadata_requires_canonical_absolute_out_of_band_paths(self):
        self.f.seal(trust=lambda d: d["catalog"].update({"path": "relative/catalog.json"}))
        self.denied("unsafe_path", self.f.resolver)
        self.f.seal(trust=lambda d: d["catalog"].update({"path": str(self.f.source / "catalog.json")}))
        self.denied("metadata_must_be_out_of_band", self.f.resolver)
        self.f.seal(trust=lambda d: d["catalog"].update({"path": str(self.f.payload / "catalog.json")}))
        self.denied("metadata_must_be_out_of_band", self.f.resolver)

    def test_duplicate_artifact_and_anchor_paths_deny(self):
        self.f.seal(trust=lambda d: d.update({"engine_native_receipt": deepcopy(d["restore_native_receipt"])}))
        self.denied("duplicate_artifact_paths", self.f.resolver)
        self.f.seal(trust=lambda d: d["source_anchors"].append(deepcopy(d["source_anchors"][0])))
        self.denied("duplicate_source_anchors", self.f.resolver)

    def test_original_manifest_anchor_is_required(self):
        self.f.seal(trust=lambda d: d.update({"source_manifest_sha256": digest(b"unknown manifest")}))
        self.denied("original_manifest_anchor_required", self.f.resolver)

    def test_source_index_bytes_mode_and_absence_deny(self):
        anchor = self.f.source / self.f.anchor
        anchor.write_bytes(b"new index")
        self.denied("source_index_drift")
        write(anchor, self.f.anchor_bytes, 0o640)
        self.denied("source_index_drift")
        anchor.unlink()
        self.denied("artifact_missing")

    def test_payload_whole_bytes_mode_size_and_missing_deny(self):
        target = self.f.restored_file()
        target.write_bytes(b"X" * len(self.f.data[0]))
        self.denied("restored_payload_mismatch")
        write(target, self.f.data[0], 0o644)
        self.denied("restored_payload_mismatch")
        write(target, b"", 0o640)
        self.denied("restored_payload_mismatch")
        target.unlink()
        self.denied("artifact_missing")

    def test_original_bytes_mode_or_epoch_mtime_drift_deny(self):
        target = self.f.original()
        target.write_bytes(b"X" * len(self.f.data[0]))
        self.denied("original_source_drift")
        write(target, self.f.data[0], 0o644)
        self.denied("original_source_drift")
        target.chmod(0o640)
        os.utime(target, ns=(target.stat().st_atime_ns, self.f.entries[0]["source_mtime_ns"] + 1_000_000))
        self.denied("original_source_drift")

    def test_payload_root_wrong_inode_or_mode_denied(self):
        self.f.payload.chmod(0o500)
        self.denied("root_identity_mismatch")
        self.f.payload.chmod(0o700)
        moved = self.f.base / "old-payload"
        self.f.payload.rename(moved)
        self.f.payload.mkdir(mode=0o700)
        write(self.f.restored_file(), self.f.data[0], 0o640)
        self.denied("root_identity_mismatch")

    def test_wrong_restore_root_receipt_even_with_equal_bytes_denies(self):
        other = self.f.base / "other-restored-root"
        other.mkdir(mode=0o700)
        write(other / self.f.entries[0]["snapshot_path"], self.f.data[0], 0o640)
        self.f.seal(restored=lambda d: d.update({"payload_root": root_identity(other)}))
        self.denied("restore_receipt_binding_mismatch")

    def test_unprotected_restore_root_and_overlap_denied(self):
        self.f.seal(trust=lambda d: d["payload_root"].update({"mode": 0o755}))
        self.denied("unprotected_restore_root", self.f.resolver)
        self.f.seal(trust=lambda d: d.update({"payload_root": root_identity(self.f.source)}))
        self.denied("overlapping_source_and_restore", self.f.resolver)

    def test_all_authority_files_require_private_modes(self):
        for path in (*self.f.paths.values(), self.f.config):
            with self.subTest(path=path.name):
                path.chmod(0o644)
                self.denied("unprotected_metadata")
                path.chmod(0o600)

    def test_payload_and_original_symlink_leaves_denied(self):
        for target in (self.f.restored_file(), self.f.original()):
            with self.subTest(target=target):
                preserved = target.with_name(target.name + ".original")
                target.rename(preserved)
                target.symlink_to(preserved)
                self.denied("unsafe_path")
                target.unlink()
                preserved.rename(target)

    def test_payload_source_and_metadata_symlink_ancestors_denied(self):
        for directory in (self.f.restored_file().parent, self.f.original().parent, self.f.metadata):
            with self.subTest(directory=directory.name):
                preserved = directory.with_name(directory.name + "-actual")
                directory.rename(preserved)
                directory.symlink_to(preserved, target_is_directory=True)
                self.denied("unsafe_path")
                directory.unlink()
                preserved.rename(directory)

    def test_metadata_symlink_leaf_denied(self):
        target = self.f.paths["catalog"]
        preserved = target.with_name("catalog.actual.json")
        target.rename(preserved)
        target.symlink_to(preserved)
        self.denied("unsafe_path")

    def test_payload_root_symlink_denied(self):
        moved = self.f.base / "actual-payload"
        self.f.payload.rename(moved)
        self.f.payload.symlink_to(moved, target_is_directory=True)
        self.denied("unsafe_path")

    def test_hardlink_aliases_rejected_for_payload_source_and_metadata(self):
        for target in (self.f.restored_file(), self.f.original(), self.f.paths["catalog"]):
            with self.subTest(target=target.name):
                alias = self.f.base / "hardlinked-alias"
                os.link(target, alias)
                self.denied("file_alias")
                alias.unlink()

    def test_fifo_and_directory_cannot_be_read_as_payload(self):
        target = self.f.restored_file()
        target.unlink()
        os.mkfifo(target, 0o640)
        self.denied("nonregular_file")
        target.unlink()
        target.mkdir(mode=0o640)
        self.denied("nonregular_file")

    def test_restore_leaf_replacement_while_reading_detected(self):
        target = self.f.restored_file()
        identity = (target.stat().st_dev, target.stat().st_ino)
        real_read = os.read
        changed = []
        def swapping_read(fd, size):
            info = os.fstat(fd)
            if not changed and (info.st_dev, info.st_ino) == identity:
                changed.append(True)
                target.rename(target.with_name("retired.bin"))
                write(target, self.f.data[0], 0o640)
            return real_read(fd, size)
        with patch.object(resolver_module.os, "read", side_effect=swapping_read):
            self.denied("file_changed_during_read")
        self.assertTrue(changed)

    def test_inplace_restore_change_while_reading_detected(self):
        target = self.f.restored_file()
        identity = (target.stat().st_dev, target.stat().st_ino)
        real_read = os.read
        changed = []
        def mutating_read(fd, size):
            info = os.fstat(fd)
            if not changed and (info.st_dev, info.st_ino) == identity:
                changed.append(True)
                target.write_bytes(b"Z" * len(self.f.data[0]))
            return real_read(fd, size)
        with patch.object(resolver_module.os, "read", side_effect=mutating_read):
            self.denied("file_changed_during_read")
        self.assertTrue(changed)

    def test_restore_ancestor_replacement_while_reading_detected(self):
        target = self.f.restored_file()
        parent = target.parent
        identity = (target.stat().st_dev, target.stat().st_ino)
        real_read = os.read
        changed = []
        def swapping_read(fd, size):
            info = os.fstat(fd)
            if not changed and (info.st_dev, info.st_ino) == identity:
                changed.append(True)
                parent.rename(parent.with_name("retired-cohort"))
                write(target, self.f.data[0], 0o640)
            return real_read(fd, size)
        with patch.object(resolver_module.os, "read", side_effect=swapping_read):
            self.denied("path_changed_during_read")
        self.assertTrue(changed)

    def test_late_anchor_drift_during_payload_read_detected(self):
        target = self.f.restored_file()
        identity = (target.stat().st_dev, target.stat().st_ino)
        real_read = os.read
        changed = []
        def mutating_read(fd, size):
            info = os.fstat(fd)
            if not changed and (info.st_dev, info.st_ino) == identity:
                changed.append(True)
                (self.f.source / self.f.anchor).write_bytes(b"later index")
            return real_read(fd, size)
        with patch.object(resolver_module.os, "read", side_effect=mutating_read):
            self.denied("source_index_drift", lambda: self.f.resolver().read_bytes(self.f.ref()))
        self.assertTrue(changed)

    def test_late_catalog_drift_during_payload_read_detected(self):
        target = self.f.restored_file()
        identity = (target.stat().st_dev, target.stat().st_ino)
        real_read = os.read
        changed = []
        def mutating_read(fd, size):
            info = os.fstat(fd)
            if not changed and (info.st_dev, info.st_ino) == identity:
                changed.append(True)
                self.f.paths["catalog"].write_bytes(b"later catalog")
            return real_read(fd, size)
        with patch.object(resolver_module.os, "read", side_effect=mutating_read):
            self.denied("pinned_artifact_mismatch", lambda: self.f.resolver().read_bytes(self.f.ref()))
        self.assertTrue(changed)

    def test_read_bytes_remains_immutable_after_payload_later_changes(self):
        data = self.f.resolver().read_bytes(self.f.ref())
        self.f.restored_file().write_bytes(b"later bytes")
        self.assertIs(type(data), bytes)
        self.assertEqual(data, self.f.data[0])

    def mutate_during_final_metadata_check(self, mutation):
        marker = self.f.paths["engine_native_receipt"]
        identity = (marker.stat().st_dev, marker.stat().st_ino)
        real_read = os.read
        starts = []
        changed = []
        def mutating_read(fd, size):
            info = os.fstat(fd)
            if (info.st_dev, info.st_ino) == identity and os.lseek(fd, 0, os.SEEK_CUR) == 0:
                starts.append(1)
                if len(starts) == 2:
                    mutation()
                    changed.append(True)
            return real_read(fd, size)
        with patch.object(resolver_module.os, "read", side_effect=mutating_read):
            self.denied("file_changed_after_read", lambda: self.f.resolver().read_bytes(self.f.ref()))
        self.assertTrue(changed)

    def test_payload_late_inplace_rewrite_detected_before_return(self):
        self.mutate_during_final_metadata_check(lambda: self.f.restored_file().write_bytes(b"late replacement bytes"))

    def test_payload_late_same_byte_inode_replacement_detected(self):
        target = self.f.restored_file()
        def replace():
            target.rename(target.with_name("late-retired.bin"))
            write(target, self.f.data[0], 0o640)
        self.mutate_during_final_metadata_check(replace)

    def test_original_late_drift_detected_before_return(self):
        self.mutate_during_final_metadata_check(lambda: self.f.original().write_bytes(b"late original drift"))

    def test_original_late_absence_detected_before_return(self):
        self.mutate_during_final_metadata_check(lambda: self.f.original().unlink())

    def test_original_late_appearance_detected_before_return(self):
        target = self.f.original()
        target.unlink()
        def appear():
            write(target, self.f.data[0], 0o640)
            os.utime(target, ns=(target.stat().st_atime_ns, self.f.entries[0]["source_mtime_ns"]))
        self.mutate_during_final_metadata_check(appear)

    def test_earlier_batch_payload_drift_during_later_hash_detected(self):
        target = self.f.restored_file(1)
        identity = (target.stat().st_dev, target.stat().st_ino)
        real_read = os.read
        changed = []
        def mutating_read(fd, size):
            info = os.fstat(fd)
            if not changed and (info.st_dev, info.st_ino) == identity:
                changed.append(True)
                self.f.restored_file(0).write_bytes(b"late earlier-cohort drift")
            return real_read(fd, size)
        with patch.object(resolver_module.os, "read", side_effect=mutating_read):
            self.denied("file_changed_after_read", lambda: self.f.resolver().verify_many((self.f.ref(), self.f.ref(1))))
        self.assertTrue(changed)

    def test_bounds_on_metadata_native_file_entries_and_total(self):
        self.denied("file_size_limit", lambda: self.f.resolver(Limits(metadata_bytes=32)))
        self.denied("invalid_integer", lambda: self.f.resolver(Limits(native_receipt_bytes=16)))
        self.denied("invalid_integer", lambda: self.f.resolver(Limits(file_bytes=16)).verify_reference(self.f.ref()))
        self.denied("invalid_catalog_entries", lambda: self.f.resolver(Limits(entries=1)).verify_reference(self.f.ref()))
        self.denied("read_budget_exceeded", lambda: self.f.resolver(Limits(total_bytes=16)))

    def test_inprocess_read_deadline_checked(self):
        reader = self.f.resolver()
        with patch.object(resolver_module.time, "monotonic", side_effect=[0.0, 31.0]):
            self.denied("read_deadline_exceeded", lambda: reader.verify_reference(self.f.ref()))

    def test_invalid_unbounded_limits_deny(self):
        for changes in ({"metadata_bytes": 0}, {"file_bytes": True}, {"seconds": float("nan")},
                        {"seconds": 301}, {"anchors": 4097}, {"entries": 65537},
                        {"native_receipt_bytes": 65 * 1024 ** 2}, {"total_bytes": 5 * 1024 ** 3}):
            with self.subTest(changes=changes):
                self.denied("invalid_limits", lambda: Limits(**changes))

    def test_cli_success_is_metadata_only_and_not_release_authority(self):
        out = io.StringIO()
        reference = self.f.ref()
        with contextlib.redirect_stdout(out):
            status = resolver_module.main(["--trust-config", str(self.f.config), "--trust-sha256", self.f.config_sha,
                                           "--original-path", reference.original_path, "--original-sha256", reference.sha256,
                                           "--epoch", reference.source_epoch])
        self.assertEqual(status, 0)
        result = json.loads(out.getvalue())
        self.assertEqual(result["status"], "verified_reference_bytes")
        self.assertFalse(result["archive_or_restore_operations_performed"])
        self.assertFalse(result["production_release_approved"])
        self.assertNotIn("synthetic alpha", out.getvalue())
        self.assertNotIn(str(self.f.base), out.getvalue())

    def test_cli_missing_inputs_and_invalid_arguments_fixed_redacted_errors(self):
        for args, expected in (([], "trusted_inputs_required"), (["--secret-token", "raw-secret"], "invalid_arguments"),
                               (["--trust-config", str(self.f.config), "--trust-sha256", "raw-secret"], "invalid_digest")):
            with self.subTest(args=args):
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    status = resolver_module.main(args)
                self.assertEqual(status, 2)
                result = json.loads(out.getvalue())
                self.assertEqual(result["code"], expected)
                self.assertNotIn("raw-secret", out.getvalue())
                self.assertNotIn(str(self.f.base), out.getvalue())


if __name__ == "__main__":
    unittest.main()
