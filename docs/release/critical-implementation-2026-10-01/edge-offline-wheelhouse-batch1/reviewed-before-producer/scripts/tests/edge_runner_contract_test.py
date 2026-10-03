"""Fail-closed tests for accepting dated SQL decoder inputs and Deno completion."""
from pathlib import Path
import shutil
import importlib.util
import subprocess
import time
import sys
import tempfile
import unittest
from copy import deepcopy
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/qa"))
from run_edge_unit_tests import FIXTURE, passed_summary, validate_fixture
sys.path.insert(0, str(ROOT / "scripts/tests"))
from roster_wheelhouse_test import WheelhouseContract
import run_edge_ci


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


class CommandEvidence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location(
            "roster_command_gate", ROOT / "scripts/tests/verify_roster_decoder.py")
        cls.gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.gate)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.log = Path(self.temp.name) / "command.log"

    def tearDown(self):
        self.temp.cleanup()

    def test_real_stdout_stderr_and_stdin_are_preserved(self):
        text = self.gate.run([sys.executable, "-c",
            "import sys; print(sys.stdin.read()); print('diagnostic',file=sys.stderr)"],
            self.log, input="synthetic input")
        self.assertIn("synthetic input", text)
        self.assertIn("diagnostic", text)
        self.assertEqual(text, self.log.read_text())

    def test_real_failed_command_preserves_output(self):
        with self.assertRaisesRegex(RuntimeError, "Command failed"):
            self.gate.run([sys.executable, "-c",
                "import sys; print('synthetic failure',flush=True); sys.exit(7)"], self.log)
        self.assertIn("synthetic failure", self.log.read_text())

    def test_real_deadline_preserves_partial_output_and_terminates_owned_child(self):
        pid_file = Path(self.temp.name) / "child-pid"
        child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)"
        script = ("import subprocess,sys,time; from pathlib import Path; "
                  "p=subprocess.Popen([sys.executable,'-c',sys.argv[2]]); "
                  "Path(sys.argv[1]).write_text(str(p.pid)); "
                  "print('before deadline',flush=True); time.sleep(30)")
        with self.assertRaisesRegex(RuntimeError, "Command timed out"):
            self.gate.run([sys.executable, "-c", script, str(pid_file), child],
                          self.log, timeout=0.4)
        self.assertIn("before deadline", self.log.read_text())
        self.assertIn("owned_parent_reaped=True", self.log.read_text())
        self.assertTrue(pid_file.exists())
        pid = pid_file.read_text()
        for _ in range(20):
            status = subprocess.run(["ps", "-p", pid, "-o", "stat="],
                capture_output=True, text=True).stdout.strip()
            if not status or status.startswith("Z"):
                break
            time.sleep(0.05)
        self.assertTrue(not status or status.startswith("Z"), status)


class DenoCompletion(unittest.TestCase):
    def test_completed_nonempty_summary(self):
        self.assertEqual(passed_summary("ok | 201 passed | 0 failed (1s)\n")["tests_passed"], 201)

    def test_completed_nested_step_summary(self):
        summary = passed_summary("ok | 561 passed (32 steps) | 0 failed (2s)\n")
        self.assertEqual(summary, {"tests_passed": 561, "tests_failed": 0, "tests_ignored": 0,
                                  "steps_passed": 32, "steps_failed": 0, "steps_ignored": 0})
        self.assertEqual(passed_summary("ok | 1 passed | 0 failed (1m10s)")["tests_passed"], 1)

    def test_failed_or_ignored_nested_steps_are_rejected(self):
        for value in (
            "FAILED | 560 passed (31 steps) | 1 failed (1 step) (2s)",
            "ok | 1 passed (1 step) | 0 failed (1 step) (2s)",
            "ok | 1 passed (1 step) | 0 failed | 0 ignored (1 step) (2s)",
            "ok | 1 passed (1 step) | 0 failed | 1 ignored (2s)",
        ):
            with self.subTest(value=value), self.assertRaises(ValueError):
                passed_summary(value)


    def test_partial_malformed_or_ambiguous_nested_summaries_are_rejected(self):
        for value in (
            "ok | 561 passed (32 steps) | 0 failed (",
            "ok | 561 passed (32 steps) | 0 failed | 9 skipped",
            "ok | 561 passed (32 steps) | 0 failed (1 ignored step)",
            "ok | 561 passed (32 steps) | 0 failed (partial)",
            "ok | 1 passed (1 step) | 0 failed\nok | 1 passed | 0 failed",
            "ok | 1 passed (1 step) | 0 failed\nok | 1 passed (",
            "FAILED | 1 passed (1 step) | 0 failed",
        ):
            with self.subTest(value=value), self.assertRaises(ValueError):
                passed_summary(value)

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


class OfflineCallerContract(unittest.TestCase):
    def test_canonical_command_forwards_every_exact_explicit_input(self):
        args = SimpleNamespace(wheel_source=Path("relative-wheels"),
            publisher_receipt=Path("relative-receipt.json"), publisher_sha256="a" * 64,
            metadata_directory=Path("relative-metadata"))
        command = run_edge_ci.linux_decoder_command(args, Path("/private/python"), Path("/private/evidence"))
        self.assertEqual(command, [sys.executable, "scripts/tests/verify_roster_decoder.py",
            "--python", "/private/python", "--output", "/private/evidence/linux-decoder",
            "--wheel-source", str(args.wheel_source.absolute()),
            "--publisher-receipt", str(args.publisher_receipt.absolute()),
            "--publisher-sha256", "a" * 64, "--metadata-directory", str(args.metadata_directory.absolute())])

    def test_receipt_requires_all_offline_fences_not_self_reported_pass(self):
        healthy = {"wheelhouse_rechecked_before_build": True, "wheelhouse": {
            "wheel_count": 6, "publisher_receipt_sha256": "a" * 64,
            "source_before_copy_after_equal": True, "wheel_before_copy_after_equal": True,
            "network_acquisition_performed": False, "package_installation_performed": False,
            "docker_execution_performed": False}}
        self.assertEqual(run_edge_ci.require_wheelhouse_receipt(healthy, "a" * 64), healthy["wheelhouse"])
        for key in healthy["wheelhouse"]:
            with self.subTest(missing=key):
                current = deepcopy(healthy); del current["wheelhouse"][key]
                with self.assertRaises(RuntimeError): run_edge_ci.require_wheelhouse_receipt(current, "a" * 64)
        for key, value in (("wheel_count", True), ("wheel_count", 6.0), ("publisher_receipt_sha256", "b" * 64),
            ("network_acquisition_performed", True), ("package_installation_performed", True),
            ("docker_execution_performed", True), ("source_before_copy_after_equal", 1)):
            with self.subTest(changed=key):
                current = deepcopy(healthy); current["wheelhouse"][key] = value
                with self.assertRaises(RuntimeError): run_edge_ci.require_wheelhouse_receipt(current, "a" * 64)
        del healthy["wheelhouse_rechecked_before_build"]
        with self.assertRaises(RuntimeError): run_edge_ci.require_wheelhouse_receipt(healthy, "a" * 64)

    def test_actual_cli_requires_all_inputs_before_any_gate_or_docker(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "must-not-be-created"
            for script, initial in (("scripts/qa/run_edge_ci.py", ["--deno", "missing", "--decoder-python", "missing"]),
                                    ("scripts/tests/verify_roster_decoder.py", ["--python", "missing"])):
                with self.subTest(script=script):
                    completed = subprocess.run([sys.executable, "-B", script, *initial, "--output", str(output)],
                        cwd=ROOT, capture_output=True, text=True, timeout=10)
                    self.assertEqual(completed.returncode, 2)
                    for option in ("--wheel-source", "--publisher-receipt", "--publisher-sha256", "--metadata-directory"):
                        self.assertIn(option, completed.stderr)
                    self.assertFalse(output.exists())

    def test_dynamic_canonical_inventory_contains_new_actual_consumer_sources(self):
        paths = set(run_edge_ci.source_paths())
        for path in ("scripts/qa/roster_wheelhouse.py", "scripts/tests/roster_wheelhouse_test.py",
                     "tools/roster-decoder/Dockerfile", "scripts/tests/verify_roster_decoder.py"):
            self.assertIn(ROOT / path, paths)

    def test_actual_build_command_preserves_private_context_and_no_network_cache(self):
        spec = importlib.util.spec_from_file_location("roster_build_command", ROOT / "scripts/tests/verify_roster_decoder.py")
        gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)
        self.assertEqual(gate.docker_build_command("synthetic:qa", Path("/private/copied-context")),
            ["docker", "build", "--network=none", "--no-cache", "-t", "synthetic:qa", "/private/copied-context"])



if __name__ == "__main__":
    unittest.main()
