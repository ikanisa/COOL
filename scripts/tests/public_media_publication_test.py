#!/usr/bin/env python3
"""Actual filesystem checks for publication preservation and failed verification."""
import importlib.util
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "publication", Path(__file__).resolve().parents[1] / "assets/publish_public_app_media.py")
PUBLICATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLICATION)


class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "repo"
        self.root.mkdir()
        self.media = self.root / "web/public/app-screens"
        self.media.mkdir(parents=True)
        self.approved = self.root / PUBLICATION.PUBLISHED_METADATA_INPUT
        self.approved.parent.mkdir(parents=True)
        self.report_path = self.root / ".cache/capture/report.json"
        self.report_path.parent.mkdir(parents=True)
        self.review_path = self.report_path.parent / "review.json"
        self.packet = self.root / "docs/publication"
        (self.root / "pubspec.yaml").write_text("version: 1.2.4+23\n")
        self.runtime = "a" * 64
        self.old = {"screens": []}
        self.captures = {}
        approved_lines = []
        for identifier in sorted(PUBLICATION.REQUIRED):
            old_file = identifier + "-old.png"
            (self.media / old_file).write_bytes(("Synthetic prior image " + identifier).encode())
            old_sha = PUBLICATION.sha(self.media / old_file)
            self.old["screens"].append({"id": identifier, "file": old_file, "sha256": old_sha,
                                        "alt": identifier, "capture_kind": "browser_flutter_fixture"})
            approved_lines.append(old_sha + "  web/public/app-screens/" + old_file)
            capture = self.report_path.parent / (identifier + ".png")
            capture.write_bytes(("Synthetic replacement image " + identifier).encode())
            self.captures[identifier] = {
                "path": capture.relative_to(self.root).as_posix(), "sha256": PUBLICATION.sha(capture),
                "width": 1, "height": 1, "app_route": PUBLICATION.APP_ROUTES[identifier],
                "platform": "Chromium browser", "theme": "dark", "text_scale": 1}
        self.approved.write_text("\n".join(approved_lines) + "\n")
        (self.media / "manifest.json").write_text(json.dumps(self.old))
        (self.media / "capture-provenance.json").write_text('{"prior":"preserved"}')
        (self.media / "unrelated-product-evidence.txt").write_text("Leave this file intact")
        self.report = {"kind": "browser_flutter_fixture", "scope": "Synthetic publication unit fixture",
                       "finished_at": "2026-09-30T12:00:00Z"}
        self.report_path.write_text(json.dumps(self.report))
        self.review_path.write_text('{"unit_fixture":true}')
        self.linked = {}
        self.before = self.snapshot()

    def snapshot(self):
        return {**{path.name: path.read_bytes() for path in self.media.iterdir() if path.is_file()},
                "approved": self.approved.read_bytes()}

    def run_publication(self, final_failure=False, review=None, mutate_review=False):
        args = ["publication", "--capture-report", str(self.report_path),
                "--visual-review", str(self.review_path), "--packet", str(self.packet)]

        def admitted_capture(*_):
            if mutate_review:
                self.review_path.write_text('{"after_admission":true}')
            return self.report, review or {}, self.captures, self.linked

        with patch.object(PUBLICATION, "ROOT", self.root), patch.object(PUBLICATION, "MEDIA", self.media), \
                patch.object(sys, "argv", args), \
                patch.object(PUBLICATION.subprocess, "check_output", return_value=self.runtime), \
                patch.object(PUBLICATION, "validate_capture", side_effect=admitted_capture), \
                patch.object(PUBLICATION.subprocess, "run", side_effect=
                             subprocess.CalledProcessError(1, ["synthetic-final-validation"])
                             if final_failure else None):
            PUBLICATION.main()

    def test_review_can_correct_a_changed_screens_description(self):
        self.run_publication(review={"screens": [{"id": "home", "alt": "Recorded total and activity"}]})
        manifest = json.loads((self.media / "manifest.json").read_text())
        descriptions = {screen["id"]: screen["alt"] for screen in manifest["screens"]}
        self.assertEqual("Recorded total and activity", descriptions["home"])
        self.assertEqual("privacy", descriptions["privacy"])
        self.assertEqual(self.old, json.loads((self.packet / "previous-browser-media/manifest.json").read_text()))

    def test_forced_final_validation_failure_restores_all_owned_original_bytes(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_publication(final_failure=True)
        self.assertEqual(self.before, self.snapshot())
        failure = json.loads((self.packet / "publication-failure.json").read_text())
        self.assertTrue(failure["previous_media_and_approval_restored"])
        self.assertEqual("CalledProcessError", failure["failure_type"])
        self.assertEqual({"capture-report.json", "visual-review.json", "publication-failure.json"},
                         {path.name for path in self.packet.iterdir()})

    def test_unverified_rollback_retains_named_recovery_files(self):
        atomic_copy = PUBLICATION.atomic_copy

        def fail_restoring(source, target):
            if source.parent.name == "previous-media":
                raise PermissionError("Synthetic restoration failure")
            atomic_copy(source, target)

        with patch.object(PUBLICATION, "atomic_copy", side_effect=fail_restoring):
            with self.assertRaises(PUBLICATION.MediaRollbackError):
                self.run_publication(final_failure=True)
        failure = json.loads((self.packet / "publication-failure.json").read_text())
        self.assertFalse(failure["previous_media_and_approval_restored"])
        self.assertEqual("PermissionError", failure["rollback_error_type"])
        recovery = self.root / failure["recovery_directory"]
        self.assertEqual(self.packet, recovery.parent)
        self.assertEqual(self.before["manifest.json"], (recovery / "previous-media/manifest.json").read_bytes())
        self.assertEqual(self.before["approved"], (recovery / "approved-assets-before.sha256").read_bytes())
        self.assertFalse((self.packet / "publication.json").exists())

    def test_evidence_mutation_between_admission_and_staging_refuses_install(self):
        with self.assertRaisesRegex(ValueError, "evidence changed during publication preparation"):
            self.run_publication(mutate_review=True)
        self.assertEqual(self.before, self.snapshot())
        self.assertEqual({"capture-report.json", "visual-review.json"}, {path.name for path in self.packet.iterdir()})

    def test_success_records_prior_hashes_and_deletes_transaction_copies(self):
        self.run_publication()
        receipt = json.loads((self.packet / "publication.json").read_text())
        expected = {"web/public/app-screens/" + name: hashlib.sha256(data).hexdigest()
                    for name, data in self.before.items() if name not in {"approved", "unrelated-product-evidence.txt"}}
        expected[PUBLICATION.PUBLISHED_METADATA_INPUT] = hashlib.sha256(self.before["approved"]).hexdigest()
        self.assertEqual(expected, receipt["previous_sha256"])
        self.assertEqual({"capture-report.json", "visual-review.json", "publication.json", "previous-browser-media"},
                         {path.name for path in self.packet.iterdir()})
        previous = self.packet / "previous-browser-media"
        self.assertEqual(set(PUBLICATION.MEDIA_METADATA), {path.name for path in previous.iterdir()})
        for name in PUBLICATION.MEDIA_METADATA:
            self.assertEqual(self.before[name], (previous / name).read_bytes())
        self.assertEqual(self.before["unrelated-product-evidence.txt"], self.snapshot()["unrelated-product-evidence.txt"])
        self.assertFalse(any((self.media / row["file"]).exists() for row in self.old["screens"]))

    def test_native_publication_keeps_the_approval_input_explicitly_bound_by_capture(self):
        binding = self.report_path.parent / "source-binding-review.json"
        digest = hashlib.sha256(self.before["approved"]).hexdigest()
        binding.write_text(json.dumps({"native_capture_inputs": {PUBLICATION.PUBLISHED_METADATA_INPUT: digest}}))
        self.linked["source_binding_review"] = binding
        self.report.update(kind="native_ios_fixture", bundle_manifest={}, source_binding_review_sha256=PUBLICATION.sha(binding))
        self.report_path.write_text(json.dumps(self.report))
        self.run_publication()
        provenance = json.loads((self.media / "capture-provenance.json").read_text())
        prior = provenance["preserved_publication_input"]
        self.assertEqual(digest, prior["sha256"])
        self.assertEqual(PUBLICATION.PUBLISHED_METADATA_INPUT, prior["path"])
        self.assertEqual(self.before["approved"], (self.root / prior["preserved"]).read_bytes())
        self.assertEqual({"capture-report.json", "visual-review.json", "publication.json", "source_binding_review.json",
                          "approved-assets-before.sha256", "previous-browser-media"},
                         {path.name for path in self.packet.iterdir()})

    def test_replacement_collision_refuses_install_and_removes_transaction_copies(self):
        capture = self.captures["home"]
        target = self.media / ("home-" + capture["sha256"][:12] + ".png")
        target.write_bytes(b"Existing asset with different bytes")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "Replacement filename collides"):
            self.run_publication()
        self.assertEqual(before, self.snapshot())
        self.assertEqual({"capture-report.json", "visual-review.json"}, {path.name for path in self.packet.iterdir()})

    def test_competing_publication_is_rejected_before_packet_creation(self):
        with patch.object(PUBLICATION, "ROOT", self.root), patch.object(PUBLICATION, "MEDIA", self.media):
            with PUBLICATION.publication_lock():
                with self.assertRaises(BlockingIOError):
                    self.run_publication()
        self.assertEqual(self.before, self.snapshot())
        self.assertFalse(self.packet.exists())

    def test_previous_traversal_and_duplicate_route_are_rejected_before_preservation(self):
        for mutate in [lambda rows: rows[0].update(file="../outside.png"),
                       lambda rows: rows[0].update(id=rows[1]["id"])]:
            original = json.loads(json.dumps(self.old))
            mutate(original["screens"])
            (self.media / "manifest.json").write_text(json.dumps(original))
            before = self.snapshot()
            with self.assertRaises(ValueError):
                self.run_publication()
            self.assertEqual(before, self.snapshot())
            self.assertFalse(self.packet.exists())


if __name__ == "__main__":
    unittest.main()
