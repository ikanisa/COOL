#!/usr/bin/env python3
"""Adversarial source/lock SBOM checks; no package install or network access."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import yaml

ROOT = Path(__file__).resolve().parents[2]


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


inventory = module("collect_inventory", "scripts/supply_chain/inventory.py")
sbom = module("collect_source_sbom", "scripts/supply_chain/source_sbom.py")


class SourceSupplyChainTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.decoder = self.root / "tools/roster-decoder"
        self.decoder.mkdir(parents=True)
        for name in ["decoder.py", "server.py"]:
            (self.decoder / name).write_text("# synthetic source\n")
        (self.decoder / "requirements.in").write_text("Pillow==12.0.0\n")
        (self.decoder / "requirements.lock").write_text("pillow==12.0.0 --hash=sha256:" + "a" * 64 + "\n")
        (self.decoder / "Dockerfile").write_text("FROM python:3.12-slim-bookworm@sha256:" + "b" * 64 + "\n")

    def test_architecture_scope_hash_and_container_provenance_retained(self):
        with patch.object(inventory, "ROOT", self.root):
            rows, check = inventory.decoder_packages({})
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["integrity"], "a" * 64)
        self.assertEqual(rows[0]["qualifier"], "Linux aarch64 / Python3.12 wheel lock")
        self.assertEqual(rows[1]["ecosystem"], "oci")
        self.assertEqual(check["requirements_declaration_lock_mismatches"], [])

    def test_missing_hash_unpinned_base_and_duplicate_lock_rejected(self):
        cases = [("requirements.lock", "pillow==12.0.0\n"),
                 ("Dockerfile", "FROM python:3.12-slim-bookworm\n"),
                 ("requirements.lock", ("pillow==12.0.0 --hash=sha256:" + "a" * 64 + "\n") * 2)]
        for name, contents in cases:
            path = self.decoder / name
            before = path.read_text()
            path.write_text(contents)
            with self.subTest(name=name, contents=contents), patch.object(inventory, "ROOT", self.root):
                with self.assertRaises(ValueError):
                    inventory.decoder_packages({})
            path.write_text(before)

    def test_version_drift_is_explicit(self):
        (self.decoder / "requirements.in").write_text("Pillow==13.0.0\n")
        with patch.object(inventory, "ROOT", self.root):
            _, check = inventory.decoder_packages({})
        self.assertEqual(check["requirements_declaration_lock_mismatches"], ["pillow"])

    def local_fork(self):
        directory = self.root / "third_party/gotrue"
        (directory / "lib").mkdir(parents=True)
        (directory / "pubspec.yaml").write_text("name: gotrue\nversion: 2.27.1\n")
        (directory / "LICENSE").write_text("Synthetic MIT license fixture\n")
        (directory / "COLLECT_FORK.md").write_text("Synthetic provenance; no upstream authenticity claim\n")
        runtime = directory / "lib/gotrue.dart"
        runtime.write_text("// original source\n")
        (directory / "UPSTREAM-SHA256.json").write_text(json.dumps({"lib/gotrue.dart": inventory.digest(runtime)}))
        (self.root / "pubspec.yaml").write_text(yaml.safe_dump({"version": "1.2.4+23", "dependency_overrides": {"gotrue": {"path": "third_party/gotrue"}}}))
        lock = {"packages": {"gotrue": {"version": "2.27.1", "source": "path", "dependency": "direct overridden",
                                      "description": {"path": "third_party/gotrue", "relative": True}}}}
        (self.root / "pubspec.lock").write_text(yaml.safe_dump(lock))
        return directory, lock

    def test_local_fork_runtime_license_and_provenance_are_bound_without_archive_hash_claim(self):
        directory, _ = self.local_fork()
        sources = {}
        with patch.object(inventory, "ROOT", self.root):
            rows, check = inventory.dart_packages(sources)
        self.assertEqual(rows[0]["license_assertion"], "MIT")
        self.assertIsNone(rows[0]["integrity"])
        self.assertIn("third_party/gotrue/lib/gotrue.dart", sources)
        self.assertIn("third_party/gotrue/UPSTREAM-SHA256.json", sources)
        fork = check["local_forks"]["gotrue"]
        self.assertEqual(fork["tree_file_count"], 5)
        self.assertEqual(fork["upstream_changed_files"], [])
        self.assertEqual(fork["upstream_missing_files"], [])
        self.assertIn("COLLECT_FORK.md", fork["fork_added_files"])
        evidence = {"source_sha256": sources, "assets": [], "packages": rows,
                    "checks": {"dart": check}, "coverage": {"included": [], "excluded": []}}
        path = self.root / "inventory.json"
        path.write_text(json.dumps(evidence))
        with patch.object(sbom, "ROOT", self.root):
            component = sbom.build(path)["components"][0]
            properties = {p["name"]: p["value"] for p in component["properties"]}
            self.assertEqual(properties["collect:local_tree_sha256"], fork["tree_sha256"])
            self.assertNotIn("hashes", component)
            (directory / "lib/gotrue.dart").write_text("// mutated runtime\n")
            with self.assertRaisesRegex(ValueError, "source drift"):
                sbom.build(path)

    def test_new_local_fork_file_invalidates_existing_sbom_while_generated_cache_is_excluded(self):
        directory, _ = self.local_fork()
        sources = {}
        with patch.object(inventory, "ROOT", self.root):
            rows, check = inventory.dart_packages(sources)
        value = {"source_sha256": sources, "assets": [], "packages": rows, "checks": {"dart": check},
                 "coverage": {"included": [], "excluded": []}}
        path = self.root / "inventory.json"
        path.write_text(json.dumps(value))
        cache = directory / ".dart_tool"
        cache.mkdir()
        (cache / "generated.json").write_text("synthetic cache")
        with patch.object(sbom, "ROOT", self.root):
            sbom.build(path)
            (directory / "lib/new_source.dart").write_text("// new source not in recorded inventory\n")
            with self.assertRaisesRegex(ValueError, "local fork drift"):
                sbom.build(path)

    def test_local_fork_lock_version_path_escape_and_symlink_rejected(self):
        directory, lock = self.local_fork()
        lock_path = self.root / "pubspec.lock"
        for description, version in [({"path": "../outside", "relative": True}, "2.27.1"),
                                     ({"path": "third_party/gotrue", "relative": False}, "2.27.1"),
                                     ({"path": "third_party/gotrue", "relative": True}, "2.27.2")]:
            lock["packages"]["gotrue"].update(description=description, version=version)
            lock_path.write_text(yaml.safe_dump(lock))
            with self.subTest(description=description, version=version), patch.object(inventory, "ROOT", self.root):
                with self.assertRaises(ValueError):
                    inventory.dart_packages({})
        lock["packages"]["gotrue"].update(description={"path": "third_party/gotrue", "relative": True}, version="2.27.1")
        lock_path.write_text(yaml.safe_dump(lock))
        outside = self.root.parent / (self.root.name + "-outside")
        outside.mkdir()
        self.addCleanup(lambda: outside.rmdir())
        (directory / "external").symlink_to(outside, target_is_directory=True)
        with patch.object(inventory, "ROOT", self.root), self.assertRaisesRegex(ValueError, "symlink"):
            inventory.dart_packages({})

    def test_local_fork_missing_provenance_and_bad_upstream_source_hash_rejected(self):
        directory, _ = self.local_fork()
        provenance = directory / "COLLECT_FORK.md"
        provenance.unlink()
        with patch.object(inventory, "ROOT", self.root), self.assertRaises(FileNotFoundError):
            inventory.dart_packages({})
        provenance.write_text("Synthetic provenance\n")
        upstream = directory / "UPSTREAM-SHA256.json"
        for document in [{"../escape": "a" * 64}, {"lib/gotrue.dart": "bad"}, {}]:
            upstream.write_text(json.dumps(document))
            with self.subTest(document=document), patch.object(inventory, "ROOT", self.root), self.assertRaises(ValueError):
                inventory.dart_packages({})

    def test_actual_reviewed_forks_include_all_runtime_and_original_license_evidence(self):
        sources = {}
        rows, check = inventory.dart_packages(sources)
        self.assertEqual(set(check["local_forks"]), {"file_saver", "gotrue", "firebase_messaging"})
        self.assertEqual(check["local_forks"]["gotrue"]["upstream_file_count"], 79)
        self.assertEqual(check["local_forks"]["gotrue"]["upstream_missing_files"], [])
        for name in ["file_saver", "gotrue", "firebase_messaging"]:
            for path in (ROOT / "third_party" / name / "lib").rglob("*.dart"):
                self.assertEqual(sources[path.relative_to(ROOT).as_posix()], inventory.digest(path))
        self.assertEqual(next(row for row in rows if row["name"] == "gotrue")["license_assertion"], "MIT")
        self.assertEqual(next(row for row in rows if row["name"] == "firebase_messaging")["license_assertion"], "BSD-3-Clause")

    def test_gradle_lock_retains_both_selected_classpaths_and_exact_versions(self):
        path = self.root / "android/app/gradle.lockfile"
        path.parent.mkdir(parents=True)
        path.write_text("androidx.activity:activity:1.12.4=productionReleaseRuntimeClasspath\n"
                        "androidx.activity:activity:1.8.1=productionReleaseCompileClasspath\nempty=\n")
        sources = {}
        with patch.object(inventory, "ROOT", self.root):
            rows, check = inventory.gradle_lock_packages(sources)
        self.assertEqual([r["version"] for r in rows], ["1.12.4", "1.8.1"])
        self.assertEqual(check["entry_count"], 2)
        self.assertEqual(sources["android/app/gradle.lockfile"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_gradle_lock_rejects_dynamic_duplicate_missing_and_unreviewed_scope(self):
        path = self.root / "android/app/gradle.lockfile"
        path.parent.mkdir(parents=True)
        valid = "g:n:1.0=productionReleaseCompileClasspath,productionReleaseRuntimeClasspath\n"
        for text in [valid * 2, valid.replace("1.0", "1.+"), valid.replace("productionReleaseRuntimeClasspath", "devDebugRuntimeClasspath"),
                     "g:n:1.0=productionReleaseCompileClasspath\n", "malformed\n"]:
            path.write_text(text)
            with self.subTest(text=text), patch.object(inventory, "ROOT", self.root):
                with self.assertRaises(ValueError):
                    inventory.gradle_lock_packages({})

    def test_sri_becomes_correct_digest_and_git_revision_is_not_hash(self):
        digest = bytes(range(64))
        self.assertEqual(sbom.component_hash("sha512-" + base64.b64encode(digest).decode()),
                         [{"alg": "SHA-512", "content": digest.hex()}])
        self.assertEqual(sbom.component_hash("0123456789" * 4), [])
        with self.assertRaises(ValueError):
            sbom.component_hash("sha512-" + base64.b64encode(b"short").decode())

    def edge_lock(self):
        path = self.root / "supabase/functions/deno.lock"
        path.parent.mkdir(parents=True, exist_ok=True)
        uri = "https://example.org/sdk@1.0.0/mod.ts"
        lock = {"version": "5", "remote": {uri: "a" * 64},
                "npm": {"package@1.0.0": {"integrity": "sha512-" + base64.b64encode(bytes(range(64))).decode()}},
                "specifiers": {"npm:package@1.0.0": "1.0.0"},
                "redirects": {"https://example.org/sdk": uri}}
        path.write_text(json.dumps(lock))
        return path, lock, uri

    def test_deno_lock_keeps_integrity_redirects_and_source_hash(self):
        path, _, uri = self.edge_lock()
        sources = {}
        with patch.object(inventory, "ROOT", self.root):
            rows, check = inventory.edge_lock_packages(sources, {uri, "npm:package@1.0.0"})
        self.assertEqual(check["remote_modules"], 1)
        self.assertEqual(check["npm_packages"], 1)
        self.assertEqual(rows[0]["integrity"], "a" * 64)
        self.assertEqual(sources["supabase/functions/deno.lock"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(check["direct_imports_missing_from_lock"], [])

    def test_deno_invalid_remote_npm_hash_and_unpinned_version_rejected(self):
        path, lock, uri = self.edge_lock()
        variants = []
        for key, value in [("remote", {uri: "not_sha256"}),
                           ("npm", {"package@1.0.0": {"integrity": "sha512-" + base64.b64encode(b"short").decode()}}),
                           ("npm", {"package@latest": lock["npm"]["package@1.0.0"]}),
                           ("version", "6")]:
            candidate = dict(lock)
            candidate[key] = value
            variants.append(candidate)
        for candidate in variants:
            path.write_text(json.dumps(candidate))
            with self.subTest(candidate=candidate), patch.object(inventory, "ROOT", self.root):
                with self.assertRaises(ValueError):
                    inventory.edge_lock_packages({}, {uri})

    def test_deno_missing_direct_import_dependency_and_specifier_rejected(self):
        path, lock, uri = self.edge_lock()
        for direct in [{"https://example.org/unlocked.ts"}, {"npm:missing@1.0.0"}]:
            with self.subTest(direct=direct), patch.object(inventory, "ROOT", self.root):
                with self.assertRaisesRegex(ValueError, "missing"):
                    inventory.edge_lock_packages({}, direct)
        lock["npm"]["package@1.0.0"]["dependencies"] = ["missing"]
        path.write_text(json.dumps(lock))
        with patch.object(inventory, "ROOT", self.root), self.assertRaisesRegex(ValueError, "dependency"):
            inventory.edge_lock_packages({}, {uri})
        lock["npm"]["package@1.0.0"].pop("dependencies")
        lock["specifiers"]["npm:package@1.0.0"] = "2.0.0"
        path.write_text(json.dumps(lock))
        with patch.object(inventory, "ROOT", self.root), self.assertRaisesRegex(ValueError, "specifier"):
            inventory.edge_lock_packages({}, {uri})

    def test_deno_cyclic_unlocked_and_credential_redirects_rejected(self):
        path, lock, uri = self.edge_lock()
        alias = "https://example.org/sdk"
        for redirects in [{alias: uri, uri: alias},
                          {alias: "https://example.org/missing"},
                          {alias: "https://secret@example.org/credential"}]:
            lock["redirects"] = redirects
            path.write_text(json.dumps(lock))
            with self.subTest(redirects=redirects), patch.object(inventory, "ROOT", self.root):
                with self.assertRaises(ValueError):
                    inventory.edge_lock_packages({}, {uri})

    def test_actual_edge_inventory_closes_all_imports_and_pins(self):
        sources = {}
        rows, check = inventory.edge_packages(sources)
        lock = check["resolved_dependency_lock"]
        self.assertEqual(lock["remote_modules"], 45)
        self.assertEqual(lock["npm_packages"], 5)
        self.assertEqual(len([r for r in rows if r["ecosystem"] == "deno-remote"]), 45)
        self.assertEqual(len([r for r in rows if r["ecosystem"] == "deno-npm"]), 5)
        self.assertIn("supabase/functions/deno.lock", sources)

    def evidence(self):
        source, asset = self.root / "source", self.root / "asset"
        source.write_text("source\n")
        asset.write_bytes(b"asset")
        row = inventory.row("oci", "python:3.12", None, "base declaration", "Dockerfile",
                            integrity="b" * 64, origin="python:3.12", qualifier="declared only")
        value = {"source_sha256": {"source": sbom.digest(source)},
                 "assets": [{"path": "asset", "sha256": sbom.digest(asset), "bytes": 5,
                             "declared_in": "pubspec.yaml", "license_evidence": "unknown"}],
                 "packages": [row, dict(row)],
                 "checks": {"dart": {"pubspec_version": "1.2.4+23"}},
                 "coverage": {"included": ["source locks"], "excluded": ["signed artifact"]}}
        path = self.root / "inventory.json"
        path.write_text(json.dumps(value))
        return path

    def test_dedup_and_unknown_acceptance_remain_explicit(self):
        path = self.evidence()
        with patch.object(sbom, "ROOT", self.root):
            result = sbom.build(path)
        self.assertEqual(len(result["components"]), 2)
        self.assertEqual(result["components"][0]["type"], "container")
        properties = {p["name"]: p["value"] for p in result["metadata"]["properties"]}
        self.assertEqual(properties["collect:license_approval"], "false")
        self.assertEqual(properties["collect:vulnerability_clearance"], "not evaluated")

    def test_source_or_asset_drift_cannot_generate_sbom(self):
        for name in ["source", "asset"]:
            path = self.evidence()
            (self.root / name).write_text("changed")
            with self.subTest(name=name), patch.object(sbom, "ROOT", self.root):
                with self.assertRaisesRegex(ValueError, "drift"):
                    sbom.build(path)

    def test_inventory_path_escape_rejected(self):
        path = self.evidence()
        document = json.loads(path.read_text())
        document["source_sha256"] = {"../outside": "a" * 64}
        path.write_text(json.dumps(document))
        with patch.object(sbom, "ROOT", self.root):
            with self.assertRaisesRegex(ValueError, "drift"):
                sbom.build(path)


if __name__ == "__main__":
    unittest.main()
