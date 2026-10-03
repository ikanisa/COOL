"""SQL recipe boundaries using local synthetic processes; no Docker/SQL calls."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

BASE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sql_ci", BASE / "scripts/qa/run_sql_ci.py")
sql = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sql)


class SqlRecipeBoundaries(unittest.TestCase):
    def setUp(self):
        cache = BASE / ".cache"
        cache.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="sql-boundary-", dir=cache)
        self.root = Path(self.temp.name)
        self.fixture = self.root / sql.FIXTURES
        self.fixture.mkdir(parents=True)
        for name in ("manifest.json", "predecessor.json", "platform-bootstrap.sql"):
            shutil.copyfile(BASE / sql.FIXTURES / name, self.fixture / name)
        self.lock = json.loads((self.fixture / "manifest.json").read_text())
        self.pin = sql.file_sha(self.fixture / "manifest.json")
        self.sources = dict(self.lock["helpers"])
        self.sources.update({f"{sql.FIXTURES}/{n}": pin for n, pin in self.lock["files"].items()})
        predecessor = json.loads((self.fixture / "predecessor.json").read_text())
        self.sources.update({f"supabase/migrations/{r['version']}_{r['name']}.sql": "0" * 64
                             for r in predecessor["migrations"]})
        self.env = sql.clean_env(self.root, "unix:///var/run/docker.sock")
        self.trace_patch = None
        trace = os.environ.get("SQL_CI_BOUNDARY_TRACE")
        if trace:
            directory = Path(trace)
            directory.mkdir(parents=True, exist_ok=True)
            original = sql.run_process

            def recorded(*args, **kwargs):
                result = original(*args, **kwargs)
                with (directory / "process-results.jsonl").open("a") as stream:
                    stream.write(json.dumps({"test": self.id(), "result": result}) + "\n")
                stem = str(result["pid"])
                for label, path in (("stdout", args[4]), ("stderr", args[5])):
                    shutil.copyfile(path, directory / (stem + "." + label))
                return result

            self.trace_patch = patch.object(sql, "run_process", side_effect=recorded)
            self.trace_patch.start()

    def tearDown(self):
        if self.trace_patch:
            self.trace_patch.stop()
        self.temp.cleanup()

    def test_exact_fixture_lock_and_historical_prefix(self):
        self.assertEqual(sql.fixture_lock(self.root, self.pin, self.sources), self.lock)
        prefix = [p for p in self.sources if p.startswith("supabase/migrations/")]
        self.assertEqual(len(prefix), 124)

    def test_changed_whole_manifest_is_refused(self):
        path = self.fixture / "manifest.json"
        path.write_bytes(path.read_bytes() + b"\n")
        with self.assertRaisesRegex(sql.Refused, "WHOLE_LOCK_MISMATCH"):
            sql.fixture_lock(self.root, self.pin, self.sources)

    def test_new_hash_does_not_authorize_another_runtime_cohort(self):
        value = copy.deepcopy(self.lock)
        value["runtime"]["image_id"] = "sha256:" + "a" * 64
        path = self.fixture / "manifest.json"
        path.write_text(json.dumps(value))
        with self.assertRaisesRegex(sql.Refused, "RUNTIME_COHORT_UNREVIEWED"):
            sql.fixture_lock(self.root, sql.file_sha(path), self.sources)

    def test_changed_fixture_and_original_helper_bytes_are_refused(self):
        for rel in (f"{sql.FIXTURES}/platform-bootstrap.sql", sql.HELPERS[0]):
            with self.subTest(rel=rel):
                changed = dict(self.sources)
                changed[rel] = "b" * 64
                with self.assertRaises(sql.Refused):
                    sql.fixture_lock(self.root, self.pin, changed)

    def test_prefix_reordering_is_refused(self):
        prefix = [rel for rel in self.sources if rel.startswith("supabase/migrations/")]
        other = {rel: pin for rel, pin in self.sources.items() if rel not in prefix}
        other.update({rel: self.sources[rel] for rel in reversed(prefix)})
        with self.assertRaisesRegex(sql.Refused, "HISTORICAL_PREFIX_DRIFTED"):
            sql.fixture_lock(self.root, self.pin, other)

    def test_symlink_fixture_is_refused(self):
        path = self.fixture / "manifest.json"
        saved = self.fixture / "original.json"
        path.rename(saved)
        path.symlink_to(saved)
        with self.assertRaisesRegex(sql.Refused, "NOT_BOUNDED_REGULAR_FILE"):
            sql.fixture_lock(self.root, self.pin, self.sources)

    def test_exact_docker_path_and_bytes_before_any_invocation(self):
        fake = self.root / "fake-docker"
        fake.write_text("#!/bin/sh\nexit 0\n")
        fake.chmod(0o700)
        pin = sql.file_sha(fake)
        self.assertEqual(sql.docker_path(fake, pin), fake)
        fake.write_text("#!/bin/sh\nexit 7\n")
        with self.assertRaisesRegex(sql.Refused, "DOCKER_BYTES_DRIFTED"):
            sql.docker_path(fake, pin)
        with self.assertRaisesRegex(sql.Refused, "EXACT_EXECUTABLE_REQUIRED"):
            sql.docker_path(Path("fake-docker"), pin)

    def test_remote_socket_and_inherited_credentials_are_refused_or_scrubbed(self):
        for value in ("tcp://localhost:2375", "ssh://operator@host", "unix:///var/../run/docker.sock"):
            with self.assertRaises(sql.Refused):
                sql.local_socket(value)
        self.assertNotIn("SUPABASE_ACCESS_TOKEN", self.env)
        self.assertNotIn("DATABASE_URL", self.env)
        self.assertEqual(self.env["DOCKER_HOST"], "unix:///var/run/docker.sock")
        self.assertEqual(list(Path(self.env["DOCKER_CONFIG"]).iterdir()), [])
        result = sql.run_process(["/bin/sh", "-c", "env"], self.root, self.env, time.monotonic() + 5,
                                 self.root / "env.stdout", self.root / "env.stderr")
        self.assertTrue(result["pass"])
        self.assertTrue(result["owned_process_group_absent"])

    def test_real_process_timeout_refuses_success_and_removes_group(self):
        result = sql.run_process(["/bin/sh", "-c", "sleep 2"], self.root, self.env, time.monotonic() + .05,
                                 self.root / "timeout.stdout", self.root / "timeout.stderr")
        self.assertFalse(result["pass"])
        self.assertTrue(result["timed_out"])
        self.assertTrue(result["owned_process_group_absent"])

    def test_expired_bound_refuses_before_spawn(self):
        with self.assertRaisesRegex(sql.Refused, "BEFORE_SPAWN"):
            sql.run_process(["/bin/sh", "-c", "exit 0"], self.root, self.env, time.monotonic() - 1,
                            self.root / "late.stdout", self.root / "late.stderr")
        self.assertFalse((self.root / "late.stdout").exists())

    def test_detached_stdio_descendant_is_not_terminal_success(self):
        result = sql.run_process(["/bin/sh", "-c", "sleep 2 >/dev/null 2>&1 & exit 0"],
                                 self.root, self.env, time.monotonic() + 5,
                                 self.root / "descendant.stdout", self.root / "descendant.stderr")
        self.assertFalse(result["pass"])
        self.assertTrue(result["residual_group_required_stop"])
        self.assertTrue(result["owned_process_group_absent"])

    def test_post_kill_probe_refusal_requires_later_actual_group_absence(self):
        original = sql.os.killpg
        killed = False
        refused = False

        def transient(pgid, sig):
            nonlocal killed, refused
            if sig == 0 and killed and not refused:
                refused = True
                raise PermissionError(1, 'Synthetic post-stop probe refusal')
            value = original(pgid, sig)
            if sig == 9:
                killed = True
            return value

        with patch.object(sql.os, 'killpg', side_effect=transient):
            result = sql.run_process(["/bin/sh", "-c", "sleep 20 >/dev/null 2>&1 & exit 0"],
                                     self.root, self.env, time.monotonic() + 5,
                                     self.root / "probe.stdout", self.root / "probe.stderr")
        self.assertTrue(refused)
        self.assertFalse(result['pass'])
        self.assertTrue(result['residual_group_required_stop'])
        self.assertGreaterEqual(result['group_probe_permission_refusals'], 1)
        self.assertTrue(result['owned_process_group_absent'])
        with self.assertRaises(ProcessLookupError):
            original(result['pid'], 0)

    def cleanup_adapter(self, value, *, daemon_error=False):
        name = "collect_current_rehearsal_ordinary_clean_abcdef123456"
        fake = self.root / "cleanup-docker"
        # Genuine subprocesses implement metadata/absence state only, not SQL.
        fake.write_text("#!/bin/sh\n"
                        + f"printf '%s\\n' \"$1\" >> '{self.root / 'calls'}'\n"
                        + f"if [ \"$1\" = rm ]; then touch '{self.root / 'removed'}'; exit 0; fi\n"
                        + ("printf 'permission denied\\n' >&2; exit 1\n" if daemon_error else
                           f"if [ -f '{self.root / 'removed'}' ]; then printf 'No such container: {name}\\n' >&2; exit 1; fi\n"
                           + "printf '%s\\n' '" + json.dumps(value) + "'\n"))
        fake.chmod(0o700)
        results = []

        def metadata(label, tail, deadline, accept=(0,)):
            result = sql.run_process([str(fake), *tail], self.root, self.env, deadline,
                                     self.root / (label + ".stdout"), self.root / (label + ".stderr"))
            results.append(result)
            if result["exit_code"] not in accept:
                raise sql.Refused("Synthetic CLI unexpected status")
            return result, (self.root / (label + ".stdout")).read_text(), (self.root / (label + ".stderr")).read_text()

        entry = {"name": name, "image_id": sql.IMAGE_ID}
        return name, entry, metadata, results

    def test_owned_cleanup_uses_actual_cli_and_requires_absence_after_remove(self):
        name = "collect_current_rehearsal_ordinary_clean_abcdef123456"
        value = {"Image": sql.IMAGE_ID, "Config": {"Labels": {"collect.rehearsal.owner": name}},
                 "HostConfig": {"NetworkMode": "none", "PortBindings": {}}}
        name, entry, invoke, results = self.cleanup_adapter(value)
        observations, fallback = sql.cleanup_owned([entry], invoke, time.monotonic() + 5)
        self.assertEqual(observations, [{"name": name, "verified_absent": True}])
        self.assertTrue(fallback)
        self.assertEqual((self.root / "calls").read_text().splitlines(), ["container", "rm", "container"])
        self.assertTrue(all(r["owned_process_group_absent"] for r in results))

    def test_cleanup_refuses_unknown_label_or_network_without_removal(self):
        value = {"Image": sql.IMAGE_ID, "Config": {"Labels": {}},
                 "HostConfig": {"NetworkMode": "bridge", "PortBindings": {}}}
        _, entry, invoke, _ = self.cleanup_adapter(value)
        with self.assertRaisesRegex(sql.Refused, "UNBOUND_TARGET"):
            sql.cleanup_owned([entry], invoke, time.monotonic() + 5)
        self.assertEqual((self.root / "calls").read_text().splitlines(), ["container"])
        self.assertFalse((self.root / "removed").exists())

    def test_daemon_error_is_not_absence(self):
        _, entry, invoke, _ = self.cleanup_adapter({}, daemon_error=True)
        with self.assertRaisesRegex(sql.Refused, "ABSENCE_UNPROVED"):
            sql.cleanup_owned([entry], invoke, time.monotonic() + 5)
        self.assertFalse((self.root / "removed").exists())

    def test_wrong_image_platform_refuses_before_original_rehearsal(self):
        stage = self.root / "repo"
        paths = sql.source_inventory(BASE)
        for rel in paths:
            target = stage / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(BASE / rel, target)
        fake = self.root / "wrong-image-docker"
        trace = self.root / "image-calls"
        fake.write_text("#!/bin/sh\n" + f"printf '%s\\n' \"$1\" >> '{trace}'\n"
                        + "printf '%s\\n' '" + json.dumps({"Id": sql.IMAGE_ID, "Os": "linux", "Architecture": "amd64"}) + "'\n")
        fake.chmod(0o700)
        output = stage / ".cache/refused-image"
        argv = ["run_sql_ci", "--docker", str(fake), "--docker-sha256", sql.file_sha(fake),
                "--docker-host", "unix:///var/run/docker.sock", "--fixture-lock-sha256", self.pin,
                "--output", str(output)]
        with patch.object(sql, "ROOT", stage), patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(sql.main(), 1)
        actual = json.loads((output / "validation.json").read_text())
        self.assertFalse(actual["current_SQL_executed"])
        self.assertEqual(trace.read_text().splitlines(), ["image"])
        self.assertTrue(actual["source_unchanged"])
        self.assertFalse((output / "child.py").exists())

    def test_capture_detects_added_or_changed_migrations(self):
        stage = self.root / "inventory"
        paths = sql.source_inventory(BASE)
        for rel in paths:
            target = stage / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(BASE / rel, target)
        before = sql.source_inventory(stage)
        migration = next(rel for rel in before if rel.startswith("supabase/migrations/"))
        path = stage / migration
        path.write_bytes(path.read_bytes() + b"\n-- synthetic input drift\n")
        self.assertNotEqual(sql.source_inventory(stage), before)
        extra = stage / "supabase/migrations/20990101000000_synthetic_added.sql"
        extra.write_text("select 1;")
        self.assertIn(str(extra.relative_to(stage)), sql.source_inventory(stage))

    def test_complete_case_and_current_inventory_binding_cannot_be_narrowed(self):
        migrations = []
        for rel, pin in self.sources.items():
            if rel.startswith("supabase/migrations/"):
                version, name = Path(rel).stem.split("_", 1)
                migrations.append({"path": rel, "version": version, "name": name, "sha256": pin})
        # Report-contract fixture only; no SQL result is claimed or executed.
        result = {"status": "pass", "all_task_containers_removed": True, "source_inventory": migrations,
                  "cases": [{"name": name, "status": "pass"} for name in self.lock["expected_cases"]],
                  **{k: False for k in ("hosted_called", "provider_called", "source_rows_copied",
                                       "shared_database_written", "managed_hosted_owner_parity")}}
        self.assertTrue(sql.acceptance(result, self.lock, self.sources))
        for field in ("cases", "source_inventory"):
            with self.subTest(field=field):
                narrowed = copy.deepcopy(result)
                narrowed[field].pop()
                self.assertFalse(sql.acceptance(narrowed, self.lock, self.sources))


if __name__ == "__main__":
    unittest.main()
