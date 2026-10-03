#!/usr/bin/env python3
"""Synthetic pinned-input/file-copy falsifications; no real acquisition/build."""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/qa"))
import roster_wheelhouse as wheelhouse


def sha(data):
    return hashlib.sha256(data).hexdigest()


def body(document):
    return (json.dumps(document, sort_keys=True) + "\n").encode()


class WheelhouseContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="roster-wheelhouse-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.decoder, self.source, self.metadata, self.authority = [self.base / n for n in ("decoder", "wheels", "primary", "pins")]
        for directory in (self.decoder, self.source, self.metadata, self.authority):
            directory.mkdir(mode=0o700)
        self.destination = self.base / "fresh-context"
        self.receipt = self.authority / "publisher-inputs.json"
        self.rows, self.payloads, self.releases = [], {}, {}
        versions = {"defusedxml": "0.7.1", "et-xmlfile": "2.0.0", "openpyxl": "3.1.5",
                    "pillow": "12.3.0", "pypdf": "6.19.0", "pypdfium2": "5.2.0"}
        tags = {"pillow": "cp312-cp312-manylinux_2_27_aarch64.manylinux_2_28_aarch64",
                "pypdfium2": "py3-none-manylinux_2_17_aarch64.manylinux2014_aarch64"}
        for package in sorted(versions):
            version = versions[package]
            filename = package.replace("-", "_") + "-" + version + "-" + tags.get(package, "py3-none-any") + ".whl"
            data = b"SYNTHETIC TEST INPUT, NOT a real installable wheel: " + package.encode()
            (self.source / filename).write_bytes(data)
            metadata_filename = package + "-" + version + "-pypi.json"
            url = "https://files.pythonhosted.org/packages/ab/cd/fixture/" + filename
            release = {"info": {"name": package, "version": version}, "urls": [{"filename": filename,
                "digests": {"sha256": sha(data)}, "size": len(data), "url": url,
                "yanked": False, "packagetype": "bdist_wheel"}]}
            (self.metadata / metadata_filename).write_bytes(body(release))
            self.rows.append({"package": package, "version": version, "filename": filename,
                "sha256": sha(data), "size": len(data), "metadata_filename": metadata_filename,
                "metadata_sha256": sha(body(release)), "metadata_url": "https://pypi.org/pypi/" + package + "/" + version + "/json",
                "wheel_url": url})
            self.payloads[package], self.releases[package] = data, release
        lock = "# synthetic six-package Linux lock\n" + "".join(f'{r["package"]}=={r["version"]} --hash=sha256:{r["sha256"]}\n' for r in self.rows)
        (self.decoder / "requirements.lock").write_text(lock)
        for name in ("Dockerfile", "decoder.py", "server.py"):
            (self.decoder / name).write_bytes(b"SYNTHETIC source-copy fixture only: " + name.encode())
        self.document = {"format": wheelhouse.FORMAT, "platform": wheelhouse.PLATFORM,
                         "lock_sha256": sha(lock.encode()), "wheels": deepcopy(self.rows)}
        self.seal()

    def seal(self):
        self.receipt.write_bytes(body(self.document))
        self.pin = sha(self.receipt.read_bytes())

    def prepare(self):
        return wheelhouse.prepare_build_context(decoder_directory=self.decoder, wheel_source=self.source,
            publisher_receipt=self.receipt, publisher_sha256=self.pin,
            metadata_directory=self.metadata, destination=self.destination)

    def denied(self, code, action=None):
        with self.assertRaises(wheelhouse.WheelhouseError) as observed:
            (action or self.prepare)()
        self.assertEqual(str(observed.exception), code)

    def row(self, package="pillow"):
        return next(r for r in self.document["wheels"] if r["package"] == package)

    def update_release(self, package, mutate):
        release = deepcopy(self.releases[package])
        mutate(release)
        row = self.row(package)
        raw = body(release)
        (self.metadata / row["metadata_filename"]).write_bytes(raw)
        row["metadata_sha256"] = sha(raw)
        self.seal()

    def test_exact_six_private_bytes_and_publisher_copies(self):
        before = {p: p.read_bytes() for d in (self.source, self.metadata, self.decoder) for p in d.iterdir()}
        result = self.prepare()
        self.assertEqual(result["wheel_count"], 6)
        self.assertEqual(result["publisher_receipt_sha256"], self.pin)
        self.assertEqual(set(p.name for p in self.destination.iterdir()), {"Dockerfile", "decoder.py", "server.py", "requirements.lock", "wheelhouse"})
        self.assertEqual(set(p.name for p in (self.destination / "wheelhouse").iterdir()), {r["filename"] for r in self.rows})
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o700)
        for row in self.rows:
            copied = self.destination / "wheelhouse" / row["filename"]
            self.assertEqual(copied.read_bytes(), self.payloads[row["package"]])
            self.assertEqual(stat.S_IMODE(copied.stat().st_mode), 0o444)
        publisher = Path(result["publisher_inputs"])
        self.assertEqual((publisher / "publisher-receipt.json").read_bytes(), self.receipt.read_bytes())
        self.assertEqual(len(list(publisher.iterdir())), 7)
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        self.assertFalse(result["network_acquisition_performed"])
        self.assertFalse(result["package_installation_performed"])
        self.assertFalse(result["docker_execution_performed"])

    def test_source_pool_mac_wheel_is_never_selected_or_copied(self):
        extra = self.source / "pillow-12.3.0-cp312-cp312-macosx_11_0_arm64.whl"
        extra.write_bytes(b"fixture-only non-Linux pool member")
        result = self.prepare()
        self.assertEqual(result["wheel_count"], 6)
        self.assertFalse((self.destination / "wheelhouse" / extra.name).exists())
        self.assertEqual(extra.read_bytes(), b"fixture-only non-Linux pool member")

    def test_mac_native_mapping_is_denied(self):
        row = self.row(); row["filename"] = "pillow-12.3.0-cp312-cp312-macosx_11_0_arm64.whl"; self.seal()
        self.denied("linux_cp312_aarch64_wheel_required")

    def test_wrong_python_and_x86_abi_mappings_are_denied(self):
        for filename in ("pillow-12.3.0-cp311-cp311-manylinux_2_27_aarch64.manylinux_2_28_aarch64.whl",
                         "pillow-12.3.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"):
            with self.subTest(filename=filename):
                self.row()["filename"] = filename; self.seal()
                self.denied("linux_cp312_aarch64_wheel_required")

    def test_missing_and_tampered_wheel_deny_without_destination(self):
        row = self.row(); target = self.source / row["filename"]
        target.write_bytes(b"tampered" + self.payloads["pillow"])
        self.denied("wheel_bytes_mismatch")
        target.unlink(); self.denied("file_missing_or_unsafe")
        self.assertFalse(self.destination.exists())

    def test_same_size_substituted_wheel_is_denied(self):
        row = self.row(); (self.source / row["filename"]).write_bytes(b"X" * row["size"])
        self.denied("wheel_bytes_mismatch")

    def test_publisher_receipt_pin_is_out_of_band(self):
        self.receipt.write_bytes(b"rewritten authority")
        self.denied("publisher_receipt_pin_mismatch")

    def test_metadata_hash_and_missing_metadata_deny(self):
        target = self.metadata / self.row()["metadata_filename"]
        target.write_bytes(b"tampered release")
        self.denied("publisher_metadata_pin_mismatch")
        target.unlink(); self.denied("file_missing_or_unsafe")

    def test_lock_whole_digest_mismatch_denies(self):
        lock = self.decoder / "requirements.lock"; lock.write_bytes(lock.read_bytes() + b"# new input\n")
        self.denied("publisher_lock_mismatch")

    def test_lock_missing_extra_duplicate_or_unpinned_entries_deny(self):
        target = self.decoder / "requirements.lock"; original = target.read_text()
        variants = ("\n".join(original.splitlines()[:-1]) + "\n",
                    original + "unknown==1.0.0 --hash=sha256:" + "0" * 64 + "\n",
                    original + original.splitlines()[1] + "\n",
                    original.replace(" --hash=sha256:" + self.rows[0]["sha256"], ""))
        for raw in variants:
            with self.subTest(raw=raw[:30]):
                target.write_text(raw); self.document["lock_sha256"] = sha(raw.encode()); self.seal()
                self.denied("invalid_lock" if "unknown" not in raw and len(raw.splitlines()) >= 7 else "exact_six_package_lock_required")

    def test_receipt_exact_six_and_no_duplicate_mapping(self):
        self.document["wheels"].pop(); self.seal(); self.denied("exact_six_publisher_wheels_required")
        self.document["wheels"] = deepcopy(self.rows); self.document["wheels"][1] = deepcopy(self.document["wheels"][0]); self.seal()
        self.denied("duplicate_publisher_mapping")

    def test_unknown_receipt_and_row_fields_deny(self):
        self.document["bypass"] = True; self.seal(); self.denied("invalid_schema")
        del self.document["bypass"]; self.row()["bypass"] = True; self.seal(); self.denied("invalid_schema")

    def test_json_duplicate_and_constants_deny(self):
        raw = body(self.document).replace(b'"format":', b'"format":"forged", "format":', 1)
        self.receipt.write_bytes(raw); self.pin = sha(raw); self.denied("duplicate_json_key")
        self.receipt.write_bytes(b'{"format":NaN}'); self.pin = sha(self.receipt.read_bytes()); self.denied("invalid_json")

    def test_wrong_platform_and_receipt_format_deny(self):
        self.document["platform"] = "macos-arm64-cp312"; self.seal(); self.denied("unsupported_publisher_receipt")
        self.document["platform"] = wheelhouse.PLATFORM; self.document["format"] = "unverified"; self.seal(); self.denied("unsupported_publisher_receipt")

    def test_path_traversal_and_metadata_alias_deny(self):
        self.row()["filename"] = "../secret.whl"; self.seal(); self.denied("unsafe_filename")
        self.row()["filename"] = next(r["filename"] for r in self.rows if r["package"] == "pillow")
        self.row()["metadata_filename"] = "different.json"; self.seal(); self.denied("metadata_filename_identity_mismatch")

    def test_unsafe_package_and_boolean_sizes_deny(self):
        self.row()["size"] = True; self.seal(); self.denied("invalid_wheel_size")
        self.row()["size"] = next(r["size"] for r in self.rows if r["package"] == "pillow")
        self.row()["package"] = ["pillow"]; self.seal(); self.denied("publisher_lock_mismatch")

    def test_non_official_http_credentials_redirect_destination_url_deny(self):
        original = self.row()["wheel_url"]
        for url in (original.replace("https:", "http:"), original.replace("files.pythonhosted.org", "example.invalid"),
                    original.replace("files.pythonhosted.org", "user:secret@files.pythonhosted.org"), original + "?token=secret"):
            with self.subTest(url=url):
                self.row()["wheel_url"] = url; self.seal(); self.denied("invalid_publisher_url")

    def test_wrong_publisher_release_identity_denies(self):
        for key, value in (("name", "different"), ("version", "6.7.0")):
            with self.subTest(key=key):
                self.update_release("pillow", lambda d: d["info"].update({key: value}))
                self.denied("invalid_publisher_release")

    def test_yanked_sdist_size_digest_or_url_mismatch_denies(self):
        for key, value in (("yanked", True), ("packagetype", "sdist"), ("size", 1), ("url", "https://example.invalid/file"),
                           ("digests", {"sha256": "0" * 64}), ("digests", None)):
            with self.subTest(key=key):
                self.update_release("pillow", lambda d: d["urls"][0].update({key: value}))
                self.denied("publisher_wheel_mismatch")

    def test_duplicate_release_wheel_denies(self):
        self.update_release("pillow", lambda d: d["urls"].append(deepcopy(d["urls"][0])))
        self.denied("publisher_wheel_missing_or_duplicate")

    def test_symlink_wheel_and_symlink_metadata_leaf_deny(self):
        for target in (self.source / self.row()["filename"], self.metadata / self.row()["metadata_filename"]):
            with self.subTest(target=target.name):
                moved = target.with_name(target.name + ".actual"); target.rename(moved); target.symlink_to(moved)
                self.denied("file_missing_or_unsafe")
                target.unlink(); moved.rename(target)

    def test_symlink_source_and_destination_ancestor_deny(self):
        moved = self.base / "actual-source"; self.source.rename(moved); self.source.symlink_to(moved, target_is_directory=True)
        self.denied("directory_missing_or_unsafe")
        self.source.unlink(); moved.rename(self.source)
        linked = self.base / "destination-link"; linked.symlink_to(self.base, target_is_directory=True)
        self.destination = linked / "fresh-context"; self.denied("directory_missing_or_unsafe")

    def test_hardlink_and_fifo_source_wheel_deny(self):
        target = self.source / self.row()["filename"]; linked = self.base / "hardlink"
        os.link(target, linked); self.denied("nonregular_or_aliased_file"); linked.unlink()
        target.unlink(); os.mkfifo(target); self.denied("nonregular_or_aliased_file")

    def test_existing_destination_and_source_overlap_deny(self):
        self.destination.mkdir(); self.denied("fresh_private_destination_required")
        self.destination = self.source / "new-child"; self.denied("input_output_overlap")

    def test_drift_during_real_source_read_is_detected(self):
        target = self.source / self.row()["filename"]; expected = target.stat().st_ino
        real_read = os.read; changed = []
        def mutate(fd, size):
            if not changed and os.fstat(fd).st_ino == expected:
                changed.append(True); target.write_bytes(b"new bytes")
            return real_read(fd, size)
        with patch.object(wheelhouse.os, "read", side_effect=mutate):
            self.denied("file_changed")
        self.assertTrue(changed)

    def test_source_drift_during_copy_fails_and_preserves_partial_output(self):
        real_write = wheelhouse.write_new; changed = []
        def mutate(directory, name, data):
            real_write(directory, name, data)
            if not changed:
                changed.append(True); (self.decoder / "decoder.py").write_bytes(b"changed source")
        with patch.object(wheelhouse, "write_new", side_effect=mutate):
            self.denied("input_changed_during_copy")
        self.assertTrue(self.destination.exists())
        self.assertEqual(len(list((self.destination / "wheelhouse").iterdir())), 6)

    def test_source_directory_identity_swap_during_copy_denies(self):
        real_write = wheelhouse.write_new; changed = []
        def mutate(directory, name, data):
            real_write(directory, name, data)
            if not changed:
                changed.append(True); old = self.base / "retired-source"; self.source.rename(old); self.source.mkdir()
                for path in old.iterdir(): path.rename(self.source / path.name)
        with patch.object(wheelhouse, "write_new", side_effect=mutate):
            # Renaming actual leaves updates ctime; the earlier leaf fence denies
            # before the final directory fence is reached.
            self.denied("input_changed_during_copy")
        self.assertTrue(changed)

    def test_extra_copied_wheel_cannot_masquerade_as_exact_set(self):
        real_write = wheelhouse.write_new; added = []
        def mutate(directory, name, data):
            real_write(directory, name, data)
            if directory.name == "wheelhouse" and not added:
                added.append(True); (directory / "unexpected.whl").write_bytes(b"extra")
        with patch.object(wheelhouse, "write_new", side_effect=mutate):
            self.denied("unexpected_copied_context_paths")

    def test_copied_wheel_tamper_denies(self):
        real_write = wheelhouse.write_new
        def corrupt(directory, name, data):
            real_write(directory, name, data)
            if directory.name == "wheelhouse":
                path = directory / name; path.chmod(0o600); path.write_bytes(b"corrupted copy")
        with patch.object(wheelhouse, "write_new", side_effect=corrupt):
            self.denied("copied_wheel_mismatch")

    def test_bounds_reject_oversized_metadata_wheel_and_expired_operation(self):
        with patch.object(wheelhouse, "MAX_METADATA", 10): self.denied("file_size_limit")
        with patch.object(wheelhouse, "MAX_WHEEL", 10): self.denied("invalid_wheel_size")
        with patch.object(wheelhouse, "MAX_TOTAL", 10): self.denied("read_budget_exceeded")
        with patch.object(wheelhouse.time, "monotonic", side_effect=[0, 31]): self.denied("read_deadline_exceeded")

    def test_late_original_drift_after_input_rehash_is_denied(self):
        real_read = wheelhouse.read_file; changed = []
        def mutate(path, budget, maximum):
            value = real_read(path, budget, maximum)
            if path == self.destination / "server.py" and not changed:
                changed.append(True); (self.decoder / "decoder.py").write_bytes(b"late source mutation")
            return value
        with patch.object(wheelhouse, "read_file", side_effect=mutate):
            self.denied("late_file_identity_changed")
        self.assertTrue(changed)

    def test_late_copy_drift_after_that_copy_was_checked_is_denied(self):
        real_read = wheelhouse.read_file; changed = []
        def mutate(path, budget, maximum):
            value = real_read(path, budget, maximum)
            if path == self.destination / "server.py" and not changed:
                changed.append(True); target = self.destination / "decoder.py"
                target.chmod(0o600); target.write_bytes(b"late destination mutation")
            return value
        with patch.object(wheelhouse, "read_file", side_effect=mutate):
            self.denied("late_file_identity_changed")
        self.assertTrue(changed)

    def test_prepared_context_full_bytes_recheck_accepts_original(self):
        result = self.prepare()
        self.assertIsNone(wheelhouse.verify_prepared_context(result))

    def test_prepared_context_changed_source_denies_before_docker(self):
        result = self.prepare(); target = self.destination / "decoder.py"
        target.chmod(0o600); target.write_bytes(b"replaced before build"); target.chmod(0o444)
        self.denied("prepared_context_changed", lambda: wheelhouse.verify_prepared_context(result))

    def test_prepared_context_mode_change_denies_even_with_same_bytes(self):
        result = self.prepare(); (self.destination / "decoder.py").chmod(0o644)
        self.denied("prepared_context_changed", lambda: wheelhouse.verify_prepared_context(result))

    def test_prepared_context_inode_replacement_denies_even_with_same_bytes(self):
        result = self.prepare(); target = self.destination / "decoder.py"; data = target.read_bytes()
        target.rename(self.base / "former-decoder.py"); target.write_bytes(data); target.chmod(0o444)
        self.denied("prepared_context_changed", lambda: wheelhouse.verify_prepared_context(result))

    def test_prepared_context_missing_symlink_and_extra_deny(self):
        result = self.prepare(); target = self.destination / "decoder.py"
        target.rename(self.base / "former-decoder.py")
        self.denied("file_missing_or_unsafe", lambda: wheelhouse.verify_prepared_context(result))
        target.symlink_to(self.base / "former-decoder.py")
        self.denied("file_missing_or_unsafe", lambda: wheelhouse.verify_prepared_context(result))

    def test_prepared_context_extra_wheel_denies_with_other_files_unchanged(self):
        result = self.prepare()
        (self.destination / "wheelhouse" / "unreviewed.whl").write_bytes(b"unexpected")
        self.denied("unexpected_copied_context_paths", lambda: wheelhouse.verify_prepared_context(result))

    def test_restrictive_umask_does_not_make_receipt_mode_inaccurate(self):
        original = os.umask(0o077)
        try:
            result = self.prepare()
            wheelhouse.verify_prepared_context(result)
            self.assertTrue(all(stat.S_IMODE(Path(r["path"]).stat().st_mode) == 0o444 for r in result["copied_files"]))
        finally:
            os.umask(original)


if __name__ == "__main__":
    unittest.main()
