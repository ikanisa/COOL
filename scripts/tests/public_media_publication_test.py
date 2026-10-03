#!/usr/bin/env python3
"""Actual filesystem checks for publication preservation and failed verification."""
import importlib.util
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
        self.before = self.snapshot()

    def snapshot(self):
        return {**{path.name: path.read_bytes() for path in self.media.iterdir() if path.is_file()},
                "approved": self.approved.read_bytes()}

    def run_publication(self, final_failure=False):
        args = ["publication", "--capture-report", str(self.report_path),
                "--visual-review", str(self.review_path), "--packet", str(self.packet)]
        with patch.object(PUBLICATION, "ROOT", self.root), patch.object(PUBLICATION, "MEDIA", self.media), \
                patch.object(sys, "argv", args), \
                patch.object(PUBLICATION.subprocess, "check_output", return_value=self.runtime), \
                patch.object(PUBLICATION, "validate_capture", return_value=(self.report, {}, self.captures, {})), \
                patch.object(PUBLICATION.subprocess, "run", side_effect=
                             subprocess.CalledProcessError(1, ["synthetic-final-validation"])
                             if final_failure else None):
            PUBLICATION.main()

    def test_forced_final_validation_failure_restores_all_owned_original_bytes(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_publication(final_failure=True)
        self.assertEqual(self.before, self.snapshot())
        failure = json.loads((self.packet / "publication-failure.json").read_text())
        self.assertTrue(failure["previous_media_and_approval_restored"])
        self.assertEqual("CalledProcessError", failure["failure_type"])
        self.assertFalse((self.packet / "publication.json").exists())

    def test_success_preserves_prior_images_and_unrelated_evidence(self):
        self.run_publication()
        historic = self.packet / "previous-browser-media"
        for name, data in self.before.items():
            if name not in {"approved", "unrelated-product-evidence.txt"}:
                self.assertEqual(data, (historic / name).read_bytes())
        self.assertEqual(self.before["unrelated-product-evidence.txt"],
                         (self.media / "unrelated-product-evidence.txt").read_bytes())
        self.assertEqual(self.before["approved"], (self.packet / "approved-assets-before.sha256").read_bytes())
        self.assertTrue((self.packet / "publication.json").exists())
        self.assertFalse(any((self.media / row["file"]).exists() for row in self.old["screens"]))

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
