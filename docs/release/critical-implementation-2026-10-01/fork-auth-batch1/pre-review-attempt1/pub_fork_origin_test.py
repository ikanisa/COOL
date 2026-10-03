#!/usr/bin/env python3
"""Adversarial archive, delta and retained-source verification; network is mocked."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("pub_fork_origin", ROOT / "scripts/supply_chain/verify_pub_forks.py")
origin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(origin)


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def tar_bytes(entries):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as archive:
        for name, content, kind in entries:
            member = tarfile.TarInfo(name)
            if kind == "file":
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
            else:
                member.type = {"directory": tarfile.DIRTYPE, "symlink": tarfile.SYMTYPE,
                               "hardlink": tarfile.LNKTYPE, "fifo": tarfile.FIFOTYPE}[kind]
                member.linkname = "outside" if kind in ("symlink", "hardlink") else ""
                archive.addfile(member)
    return stream.getvalue()


class PubForkOriginTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.name, self.version = "firebase_messaging", "16.5.0"
        self.upstream = {"LICENSE": b"Synthetic preserved license\n", "pubspec.yaml": b"upstream\n",
                         "lib/unchanged.dart": b"unchanged runtime\n", "lib/changed.dart": b"old\n",
                         "example/demo.dart": b"omitted example\n"}
        self.fork = {k: v for k, v in self.upstream.items() if k != "example/demo.dart"}
        self.fork["lib/changed.dart"] = b"reviewed replacement\n"
        self.fork["COLLECT_FORK.md"] = b"Synthetic governance, not approval\n"
        self.fork["UPSTREAM-SHA256.json"] = encoded(origin.hashes(self.upstream))
        self.manifest = {"package": self.name, "version": self.version,
                         "fork_path": "third_party/" + self.name,
                         "upstream_manifest_sha256": origin.digest(self.fork["UPSTREAM-SHA256.json"]),
                         "delta": {"changed": {}, "added": {}, "omitted": {}}}
        for kind, names in (("changed", ["lib/changed.dart"]),
                            ("added", ["COLLECT_FORK.md", "UPSTREAM-SHA256.json"]),
                            ("omitted", ["example/demo.dart"])):
            for name in names:
                row = {"rationale": "Explicit synthetic review rationale"}
                if kind != "added": row["upstream_sha256"] = origin.digest(self.upstream[name])
                if kind != "omitted": row["fork_sha256"] = origin.digest(self.fork[name])
                self.manifest["delta"][kind][name] = row
        self.archive = tar_bytes([(k, v, "file") for k, v in self.upstream.items()])
        self.manifest["archive_sha256"] = origin.digest(self.archive)
        self.metadata = {"version": self.version, "pubspec": {"name": self.name, "version": self.version},
                         "archive_url": f"https://pub.dev/api/archives/{self.name}-{self.version}.tar.gz",
                         "archive_sha256": origin.digest(self.archive), "published": "synthetic fixture"}
        self.cache = self.root / "cache"
        self.cache_package = self.cache / self.name
        self.cache_package.mkdir(parents=True)
        (self.cache_package / "metadata.json").write_bytes(encoded(self.metadata))
        self.archive_path = self.cache_package / f"{self.name}-{self.version}.tar.gz"
        self.archive_path.write_bytes(self.archive)
        self.fork_path = self.root / self.manifest["fork_path"]
        for name, data in self.fork.items():
            path = self.fork_path / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def test_positive_offline_verification_binds_every_retained_byte(self):
        with patch.object(origin, "public_download", side_effect=AssertionError("Offline verification attempted network")):
            result = origin.verify(self.name, self.manifest, self.cache, self.root)
        self.assertEqual(result["retained_files_sha256"], origin.hashes(self.fork))
        self.assertEqual(result["upstream_files_sha256"], origin.hashes(self.upstream))
        self.assertEqual(result["unchanged_license_notice_files"], ["LICENSE"])
        self.assertEqual(result["omitted"], ["example/demo.dart"])

    def test_actual_archive_byte_drift_is_rejected(self):
        self.archive_path.write_bytes(self.archive + b"trailing mutation")
        with self.assertRaisesRegex(ValueError, "archive content digest mismatch"):
            origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_metadata_foreign_origin_version_package_and_digest_are_rejected(self):
        variants = [("archive_url", "https://attacker.invalid/package.tar.gz"),
                    ("archive_url", self.metadata["archive_url"] + "?other=1"),
                    ("version", "16.5.1"), ("archive_sha256", "f" * 64),
                    ("pubspec", {"name": "different", "version": self.version})]
        for key, value in variants:
            changed = {**self.metadata, key: value}
            (self.cache_package / "metadata.json").write_bytes(encoded(changed))
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, "metadata origin/identity/digest mismatch"):
                origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_unreviewed_unchanged_source_mutation_is_rejected(self):
        (self.fork_path / "lib/unchanged.dart").write_bytes(b"unreviewed runtime replacement")
        with self.assertRaisesRegex(ValueError, "Unreviewed fork delta: changed"):
            origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_reviewed_source_second_mutation_is_rejected(self):
        (self.fork_path / "lib/changed.dart").write_bytes(b"different implementation")
        with self.assertRaisesRegex(ValueError, "Reviewed fork byte drift"):
            origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_new_hidden_source_or_generated_file_is_not_excluded(self):
        for name in ("lib/new.dart", ".hidden", ".dart_tool/generated.dart"):
            path = self.fork_path / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("new retained input")
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unreviewed fork delta: added"):
                origin.verify(self.name, self.manifest, self.cache, self.root)
            path.unlink()

    def test_unlisted_runtime_removal_is_rejected(self):
        (self.fork_path / "lib/unchanged.dart").unlink()
        with self.assertRaisesRegex(ValueError, "Unreviewed fork delta: omitted"):
            origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_manifest_cannot_authorize_runtime_omission(self):
        fork, manifest = copy.deepcopy(self.fork), copy.deepcopy(self.manifest)
        del fork["lib/unchanged.dart"]
        manifest["delta"]["omitted"]["lib/unchanged.dart"] = {
            "upstream_sha256": origin.digest(self.upstream["lib/unchanged.dart"]), "rationale": "Invalid runtime omission"}
        with self.assertRaisesRegex(ValueError, "Runtime/platform/package/license omission"):
            origin.compare(manifest, self.upstream, fork)

    def test_missing_and_modified_license_are_rejected(self):
        for value in (None, b"substituted license"):
            fork = dict(self.fork)
            if value is None: del fork["LICENSE"]
            else: fork["LICENSE"] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "license/notice loss or mutation"):
                origin.compare(self.manifest, self.upstream, fork)

    def test_changed_license_cannot_be_approved_as_delta(self):
        fork, manifest = dict(self.fork), copy.deepcopy(self.manifest)
        fork["LICENSE"] = b"relicensed"
        manifest["delta"]["changed"]["LICENSE"] = {
            "upstream_sha256": origin.digest(self.upstream["LICENSE"]),
            "fork_sha256": origin.digest(fork["LICENSE"]), "rationale": "Invalid relicensing"}
        with self.assertRaisesRegex(ValueError, "license/notice loss or mutation"):
            origin.compare(manifest, self.upstream, fork)

    def test_retained_cache_manifest_rewriting_is_rejected(self):
        (self.fork_path / "UPSTREAM-SHA256.json").write_bytes(encoded({"LICENSE": origin.digest(self.upstream["LICENSE"])}))
        with self.assertRaisesRegex(ValueError, "cache manifest drift"):
            origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_cache_manifest_must_cover_every_official_file_even_if_new_digest_is_allowed(self):
        fork, manifest = dict(self.fork), copy.deepcopy(self.manifest)
        fork["UPSTREAM-SHA256.json"] = encoded({"LICENSE": origin.digest(self.upstream["LICENSE"])})
        manifest["upstream_manifest_sha256"] = origin.digest(fork["UPSTREAM-SHA256.json"])
        with self.assertRaisesRegex(ValueError, "does not match official archive files"):
            origin.compare(manifest, self.upstream, fork)

    def test_reviewed_delta_upstream_hash_and_rationale_are_required(self):
        for key, value in (("upstream_sha256", "0" * 64), ("rationale", " ")):
            manifest = copy.deepcopy(self.manifest)
            manifest["delta"]["changed"]["lib/changed.dart"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                origin.compare(manifest, self.upstream, self.fork)

    def test_reviewed_manifest_actual_byte_drift_is_rejected(self):
        directory = self.root / "manifests"; directory.mkdir()
        for name in origin.PACKAGES:
            source = ROOT / "scripts/supply_chain/fork_deltas" / (name + ".json")
            (directory / source.name).write_bytes(source.read_bytes())
            origin.load_reviewed(name, directory)
            (directory / source.name).write_bytes(source.read_bytes() + b" ")
            with self.subTest(package=name), self.assertRaisesRegex(ValueError, "Reviewed delta manifest drift"):
                origin.load_reviewed(name, directory)

    def test_unsafe_tar_paths_and_duplicates_are_rejected_without_extraction(self):
        for name in ("../escape", "/absolute", "a/../escape", "./alias", "a//alias", "a\\alias", "C:/escape", "bad\npath"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unsafe/noncanonical path"):
                origin.archive_files(tar_bytes([(name, b"payload", "file")]))
        with self.assertRaisesRegex(ValueError, "Duplicate archive path"):
            origin.archive_files(tar_bytes([("file", b"one", "file"), ("file", b"two", "file")]))
        self.assertFalse((self.root / "escape").exists())

    def test_tar_symlink_hardlink_device_and_file_directory_collision_are_rejected(self):
        for kind in ("symlink", "hardlink", "fifo"):
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "link/device/unsupported"):
                origin.archive_files(tar_bytes([("link", b"", kind)]))
        with self.assertRaisesRegex(ValueError, "file/directory collision"):
            origin.archive_files(tar_bytes([("parent", b"file", "file"), ("parent/child", b"child", "file")]))
        with self.assertRaisesRegex(ValueError, "Duplicate archive path"):
            origin.archive_files(tar_bytes([("same/", b"", "directory"), ("same", b"file", "file")]))

    def test_archive_expansion_bounds_are_enforced(self):
        with patch.object(origin, "MAX_FILE", 1), self.assertRaisesRegex(ValueError, "member exceeds size bound"):
            origin.archive_files(self.archive)
        with patch.object(origin, "MAX_TREE", 1), self.assertRaisesRegex(ValueError, "expanded size bound"):
            origin.archive_files(self.archive)
        with patch.object(origin, "MAX_ENTRIES", 1), self.assertRaisesRegex(ValueError, "entry limit"):
            origin.archive_files(self.archive)

    def test_source_symlink_and_symlink_directory_are_rejected(self):
        for path in (self.fork_path / "lib/link.dart", self.fork_path / "linked-directory"):
            path.symlink_to(self.archive_path)
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "Symlink fork input"):
                origin.verify(self.name, self.manifest, self.cache, self.root)
            path.unlink()

    def test_cache_symlink_duplicate_json_keys_are_rejected(self):
        metadata_path = self.cache_package / "metadata.json"
        metadata_path.unlink(); metadata_path.symlink_to(self.archive_path)
        with self.assertRaisesRegex(ValueError, "Symlink input"):
            origin.verify(self.name, self.manifest, self.cache, self.root)
        metadata_path.unlink(); metadata_path.write_bytes(b'{"version":"16.5.0","version":"16.5.0"}')
        with self.assertRaisesRegex(ValueError, "Duplicate JSON key"):
            origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_source_drift_during_verification_is_rejected(self):
        changed = {**self.fork, "lib/changed.dart": b"changed during comparison"}
        with patch.object(origin, "tree_files", side_effect=[dict(self.fork), changed]), self.assertRaisesRegex(ValueError, "inputs changed during comparison"):
            origin.verify(self.name, self.manifest, self.cache, self.root)

    def test_public_download_rejects_redirected_response_origin(self):
        class Response:
            url = "https://attacker.invalid/archive"
            def __enter__(self): return self
            def __exit__(self, *args): return None
            def read(self, maximum): raise AssertionError("Foreign content must not be read")
        with patch.object(origin.urllib.request, "build_opener") as opener:
            opener.return_value.open.return_value = Response()
            with self.assertRaisesRegex(ValueError, "Unexpected public-download origin"):
                origin.public_download(self.metadata["archive_url"], origin.MAX_ARCHIVE)

    def test_fetch_only_requests_exact_public_urls_and_preserves_existing_cache(self):
        fresh = self.root / "fresh-cache"
        with patch.object(origin, "public_download", side_effect=[encoded(self.metadata), self.archive]) as download:
            receipt = origin.fetch(self.name, self.manifest, fresh)
        self.assertEqual([call.args[0] for call in download.call_args_list],
                         [f"https://pub.dev/api/packages/{self.name}/versions/{self.version}", self.metadata["archive_url"]])
        self.assertEqual(receipt["archive_sha256"], origin.digest(self.archive))
        before = (fresh / self.name / "metadata.json").read_bytes()
        with patch.object(origin, "public_download", side_effect=[encoded(self.metadata), self.archive]), self.assertRaisesRegex(ValueError, "already exists"):
            origin.fetch(self.name, self.manifest, fresh)
        self.assertEqual((fresh / self.name / "metadata.json").read_bytes(), before)

    def test_fetch_refuses_foreign_metadata_archive_drift_and_symlink_destination(self):
        for meta, archive in (({**self.metadata, "archive_url": "https://other.invalid/package"}, self.archive),
                              (self.metadata, self.archive + b"changed")):
            with patch.object(origin, "public_download", side_effect=[encoded(meta), archive]), self.assertRaises(ValueError):
                origin.fetch(self.name, self.manifest, self.root / "refused-cache")
        linked = self.root / "linked-cache"; linked.symlink_to(self.cache, target_is_directory=True)
        with patch.object(origin, "public_download", side_effect=[encoded(self.metadata), self.archive]), self.assertRaisesRegex(ValueError, "Symlink input"):
            origin.fetch(self.name, self.manifest, linked)


if __name__ == "__main__":
    unittest.main(verbosity=2)
