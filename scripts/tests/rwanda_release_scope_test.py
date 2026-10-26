#!/usr/bin/env python3
"""Check that active release copy and artifact claims match Rwanda-only scope."""

import hashlib
import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PACKET = ROOT / "docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json"


class RwandaReleaseScopeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet = json.loads(PACKET.read_text())

    def test_packet_version_matches_source(self):
        pubspec = (ROOT / "pubspec.yaml").read_text()
        match = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec)
        self.assertIsNotNone(match)
        release = self.packet["target_release"]
        self.assertEqual(release["version_name"], match.group(1))
        self.assertEqual(release["version_code"], int(match.group(2)))

    def test_active_play_listing_is_rwanda_only_and_matches_fastlane(self):
        listing = self.packet["store_listing"]
        full = listing["full_description"]
        fastlane = (ROOT / "fastlane/metadata/android/en-US/full_description.txt").read_text().strip()
        self.assertEqual(full.strip(), fastlane)
        self.assertIn("Rwanda", full)
        self.assertIn("MTN MoMo", full)
        self.assertIn("Airtel Money", full)
        self.assertLessEqual(len(full), 4000)
        for obsolete in (r"\bdiaspora\b", r"\bSEPA\b", r"\bIBAN\b", r"\bBIC\b", r"bank[ -]transfer"):
            self.assertNotRegex(full, re.compile(obsolete, re.IGNORECASE))
        self.assertTrue(
            all("diaspora" not in entry["segment"].lower()
                for entry in listing["growth_surfaces"]["custom_store_listings"])
        )

    def test_artifact_metadata_does_not_certify_missing_bytes(self):
        release = self.packet["target_release"]
        for kind in ("aab", "apk"):
            path = ROOT / release[kind + "_path"]
            expected = release.get(kind + "_sha256")
            if path.is_file():
                self.assertEqual(expected, hashlib.sha256(path.read_bytes()).hexdigest())
            else:
                self.assertFalse(expected, f"Missing {kind} cannot retain an approval hash")
                self.assertIn("blocked", release["candidate_status"])

    def test_historical_store_audits_are_not_current_approval(self):
        self.assertIn("unverified", self.packet["scope_review_status"])
        self.assertIn("pending", self.packet["console_completion_status"])
        self.assertIn("unverified", self.packet["target_release"]["play_console_state"])
        self.assertIn("Historical snapshot notice", (ROOT / "docs/release/RELEASE_BLOCKERS.md").read_text())


if __name__ == "__main__":
    unittest.main()
