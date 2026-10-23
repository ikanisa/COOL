#!/usr/bin/env python3
"""Exact identity, scope, corruption and no-approval license witness checks."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

PATH = Path(__file__).resolve().parents[1] / "supply_chain/cached_license_evidence.py"
spec = importlib.util.spec_from_file_location("cached_license_evidence", PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LicenseEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.cache = self.root / "cache"
        self.repo.mkdir()
        self.cache.mkdir()
        self.declaration = self.repo / "pubspec.lock"
        self.declaration.write_text("exact declared fixture\n")
        self.package = self.cache / "fixture-1.2.3"
        self.package.mkdir()
        (self.package / "pubspec.yaml").write_text("name: fixture\nversion: 1.2.3\n")
        (self.package / "LICENSE").write_text("Synthetic local license witness.\n")
        self.config = self.repo / "packages.json"
        self.config.write_text(json.dumps({"packages": [{"name": "fixture", "rootUri": self.package.as_uri()}]}))
        self.inventory = self.repo / "inventory.json"
        self.row = {"ecosystem": "dart", "name": "fixture", "version": "1.2.3", "evidence": "pubspec.lock", "integrity": "a" * 64}
        self.write_inventory([self.row])

    def write_inventory(self, rows):
        self.inventory.write_text(json.dumps({"packages": rows, "source_sha256": {"pubspec.lock": hashlib.sha256(self.declaration.read_bytes()).hexdigest()}}))

    def build(self, **args):
        return module.build(self.inventory, self.repo, self.config, [self.cache], **args)

    def test_exact_dart_identity_binds_text_without_approval_or_archive_claim(self):
        result = self.build()
        row = result["packages"][0]
        self.assertEqual(row["status"], "local_license_text")
        self.assertFalse(row["license_approval"])
        self.assertFalse(row["package_archive_integrity_verified"])
        self.assertNotIn("license_assertion", row)
        self.assertIn(str(self.package / "LICENSE"), result["input_bindings"])
        self.assertEqual(result, self.build())

    def test_version_mismatch_never_uses_another_package_license(self):
        self.row["version"] = "9.9.9"
        self.write_inventory([self.row])
        result = self.build()
        self.assertEqual(result["packages"][0]["status"], "package_identity_unproved")
        self.assertNotIn(str(self.package / "LICENSE"), result["input_bindings"])

    def test_scope_is_explicit_and_remote_roots_are_not_read(self):
        result = module.build(self.inventory, self.repo, self.config, [])
        self.assertEqual(result["packages"][0]["status"], "package_root_outside_explicit_scope")
        self.config.write_text(json.dumps({"packages": [{"name": "fixture", "rootUri": "https://example.invalid/package"}]}))
        self.assertEqual(self.build()["packages"][0]["status"], "package_root_not_local")

    def test_symlink_license_escape_is_rejected(self):
        target = self.root / "unrelated"
        target.write_text("not a package license")
        (self.package / "LICENSE").unlink()
        (self.package / "LICENSE").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular file"):
            self.build()

    def test_large_text_and_changed_declaration_are_refused(self):
        (self.package / "LICENSE").write_bytes(b"x" * (module.MAX_TEXT + 1))
        with self.assertRaisesRegex(ValueError, "bounded text"):
            self.build()
        self.declaration.write_text("changed")
        with self.assertRaisesRegex(ValueError, "declaration changed"):
            self.build()

    def test_empty_license_and_duplicate_config_do_not_create_evidence(self):
        (self.package / "LICENSE").write_text("\n")
        self.assertEqual(self.build()["packages"][0]["status"], "license_text_missing")
        data = json.loads(self.config.read_text())
        data["packages"] *= 2
        self.config.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.build()

    def pom(self, body, digest="hash1"):
        path = self.cache / "org.example" / "fixture" / "1.2.3" / digest / "fixture-1.2.3.pom"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
        self.row.update(ecosystem="maven", name="org.example:fixture")
        self.write_inventory([self.row])
        return path

    def test_exact_namespaced_pom_retains_publisher_words_without_spdx_inference(self):
        self.pom('<project xmlns="http://maven.apache.org/POM/4.0.0"><parent><groupId>org.example</groupId><version>1.2.3</version></parent><artifactId>fixture</artifactId><licenses><license><name>Publisher license name</name><url>https://example.invalid/license</url></license></licenses></project>')
        row = self.build(maven_roots=[self.cache])["packages"][0]
        self.assertEqual(row["status"], "pom_license_metadata")
        self.assertEqual(row["poms"][0]["declared_licenses"][0]["name"], "Publisher license name")
        self.assertFalse(row["artifact_license_contents_verified"])
        self.assertFalse(row["license_approval"])

    def test_entity_pom_and_coordinate_escape_are_refused(self):
        self.pom('<!DOCTYPE project [<!ENTITY x SYSTEM "file:///etc/passwd">]><project/>')
        with self.assertRaisesRegex(ValueError, "entity-bearing"):
            self.build(maven_roots=[self.cache])
        self.row["name"] = "../../outside:fixture"
        self.write_inventory([self.row])
        with self.assertRaisesRegex(ValueError, "coordinate"):
            self.build(maven_roots=[self.cache])

    def test_mismatched_pom_and_conflicting_metadata_remain_unproved(self):
        template = '<project><groupId>org.example</groupId><artifactId>fixture</artifactId><version>{version}</version><licenses><license><name>{name}</name></license></licenses></project>'
        self.pom(template.format(version="4.0.0", name="wrong version"))
        self.assertEqual(self.build(maven_roots=[self.cache])["packages"][0]["status"], "exact_pom_unavailable")
        self.pom(template.format(version="1.2.3", name="A"))
        self.pom(template.format(version="1.2.3", name="B"), "hash2")
        self.assertEqual(self.build(maven_roots=[self.cache])["packages"][0]["status"], "conflicting_pom_license_metadata")

    def test_witness_membership_and_bytes_must_survive_collection(self):
        read = module.Witnesses()
        read.read(self.package / "LICENSE", self.cache)
        read.members(self.package, "*")
        (self.package / "NOTICE").write_text("late added witness")
        with self.assertRaisesRegex(ValueError, "membership changed"):
            read.finish()
        (self.package / "NOTICE").unlink()
        (self.package / "LICENSE").write_text("changed bytes")
        with self.assertRaisesRegex(ValueError, "changed after"):
            read.finish()


if __name__ == "__main__":
    unittest.main()
