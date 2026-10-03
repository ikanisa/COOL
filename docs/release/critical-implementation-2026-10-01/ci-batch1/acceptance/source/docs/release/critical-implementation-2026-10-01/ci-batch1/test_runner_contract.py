"""Fail-closed tests for accepting dated SQL decoder inputs and Deno completion."""
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts/qa"))
from run_edge_unit_tests import FIXTURE, passed_summary, validate_fixture


class FixtureProvenance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.fixture = Path(self.temp.name) / "fixture"
        shutil.copytree(FIXTURE, self.fixture)

    def tearDown(self):
        self.temp.cleanup()

    def test_reviewed_contract_accepts_copy(self):
        self.assertEqual(len(validate_fixture(self.fixture)), 12)

    def test_observation_substitution_is_rejected(self):
        (self.fixture / "observed-worker-executed.json").write_text('{"status":"pass"}')
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            validate_fixture(self.fixture)

    def test_self_reported_pass_cannot_replace_sql_receipt(self):
        (self.fixture / "result.json").write_text('{"status":"pass","sources_unchanged":true}')
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            validate_fixture(self.fixture)

    def test_generator_substitution_is_rejected(self):
        (self.fixture / "inputs/executed-runner.py").write_text("print('pass')")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            validate_fixture(self.fixture)

    def test_manifest_rewrite_is_rejected(self):
        manifest = self.fixture / "manifest.json"
        manifest.write_text(manifest.read_text().replace("immutable", "current"))
        with self.assertRaisesRegex(ValueError, "Unrecognized"):
            validate_fixture(self.fixture)

    def test_symlink_fixture_is_rejected(self):
        target = self.fixture / "observed-worker-executed.json"
        saved = target.read_bytes()
        target.unlink()
        external = Path(self.temp.name) / "outside.json"
        external.write_bytes(saved)
        target.symlink_to(external)
        with self.assertRaisesRegex(ValueError, "Contained"):
            validate_fixture(self.fixture)


class DenoCompletion(unittest.TestCase):
    def test_completed_nonempty_summary(self):
        self.assertEqual(passed_summary("ok | 201 passed | 0 failed (1s)\n")["tests_passed"], 201)

    def test_ignored_actual_integration_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "zero ignored"):
            passed_summary("ok | 0 passed | 0 failed | 10 ignored (1ms)")

    def test_partial_ignored_integration_is_rejected(self):
        with self.assertRaises(ValueError):
            passed_summary("ok | 1 passed | 0 failed | 9 ignored (1ms)")

    def test_empty_or_failed_or_ambiguous_completion_is_rejected(self):
        for value in ("", "ok | 0 passed | 0 failed", "FAILED | 3 passed | 1 failed",
                      "ok | 1 passed | 0 failed\nok | 1 passed | 0 failed"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                passed_summary(value)


if __name__ == "__main__":
    unittest.main()
