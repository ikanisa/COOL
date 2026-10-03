#!/usr/bin/env python3
"""Run the shipping migration validator against exact-version fixture cohorts."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "scripts/migrations/validate_supabase_migrations.sh"
REQUIRED = (
    "202605230008_admin_panel.sql",
    "202605270001_sms_first_group_payment_intents.sql",
)


class MigrationVersions(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.migrations = self.root / "supabase/migrations"
        self.migrations.mkdir(parents=True)
        self.validator = self.root / "scripts/migrations" / VALIDATOR.name
        self.validator.parent.mkdir(parents=True)
        shutil.copyfile(VALIDATOR, self.validator)
        for name in REQUIRED:
            shutil.copyfile(ROOT / "supabase/migrations" / name, self.migrations / name)

    def add(self, name):
        (self.migrations / name).write_text("-- Local filename fixture; never executed.\n")

    def run_validator(self):
        return subprocess.run(
            ["bash", str(self.validator)], capture_output=True, text=True,
            timeout=10, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
        )

    def test_legacy_ids_remain_valid(self):
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Supabase migration validation passed", result.stdout)

    def test_distinct_seconds_in_one_minute_are_distinct_versions(self):
        self.add("20261002120001_first.sql")
        self.add("20261002120002_second.sql")
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_legacy_and_full_version_are_not_truncated_to_one_identity(self):
        self.add("202610021200_legacy.sql")
        self.add("20261002120000_full.sql")
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_duplicate_full_versions_refuse(self):
        self.add("20261002120001_first.sql")
        self.add("20261002120001_second.sql")
        result = self.run_validator()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate complete Supabase migration versions:", result.stderr)
        self.assertIn("20261002120001", result.stderr)

    def test_duplicate_legacy_versions_refuse(self):
        self.add("202605230008_duplicate.sql")
        result = self.run_validator()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("202605230008", result.stderr)

    def test_invalid_versions_and_names_refuse(self):
        for name in (
            "2026100212000_thirteen_digits.sql",
            "202610021200001_fifteen_digits.sql",
            "20261002120001.sql",
            "not_a_version.sql",
            "20261002120001_empty-name.sql",
            "20261002120001_line\nbreak.sql",
        ):
            with self.subTest(name=name):
                self.add(name)
                result = self.run_validator()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid Supabase migration filename:", result.stderr)
                (self.migrations / name).unlink()

    def test_symlink_cannot_hide_an_extra_migration(self):
        (self.migrations / "20261002120001_link.sql").symlink_to(self.migrations / REQUIRED[0])
        result = self.run_validator()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Supabase migration must be a regular file:", result.stderr)

    def test_required_security_content_is_still_checked(self):
        (self.migrations / REQUIRED[0]).write_text("-- No admin controls.\n")
        result = self.run_validator()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Admin migration is missing required pattern:", result.stderr)


if __name__ == "__main__":
    unittest.main()
