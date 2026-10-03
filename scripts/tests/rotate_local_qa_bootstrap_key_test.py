#!/usr/bin/env python3
"""Local QA rotation boundary and ambiguous Engine-response regressions.

Uses only synthetic keys and in-memory Engine objects. The actual cryptographic
and unchanged-source acceptance remains in the execution runner, not these tests.
"""
import copy
import hashlib
import subprocess
import unittest
from unittest.mock import patch

import rotate_local_qa_bootstrap_key as K

SYNTHETIC_KEY = "0123456789abcdef" * 4
SYNTHETIC_HASH = hashlib.sha256(SYNTHETIC_KEY.encode()).hexdigest()


def fixture():
    return dict(Id="original", Image=K.IMAGE_ID, Name="/" + K.U.CONTAINER,
        State=dict(Running=True), Mounts=[dict(Type="volume", Name=K.U.CONTAINER,
        Destination="/var/lib/postgresql/data", RW=True)], Config=dict(Image=K.IMAGE,
        Labels={"com.docker.compose.project": K.PROJECT}, Cmd=None,
        Env=["SYNTHETIC_SETTING=preserved"], Entrypoint=["sh", "-c",
            "mkdir -p /etc/postgresql-custom\ncat <<'EOF' > /etc/postgresql-custom/pgsodium_root.key\n"
            + SYNTHETIC_KEY + "\nEOF\ndocker-entrypoint.sh postgres -D /etc/postgresql\n"]))


class MemoryEngine:
    def __init__(self, original, replacement=None):
        self.containers = {original["Id"]: copy.deepcopy(original)}
        if replacement:
            self.containers[replacement["Id"]] = copy.deepcopy(replacement)
        self.calls = []

    def inspect(self, ref):
        value = self.containers.get(ref)
        if value is None:
            value = next((v for v in self.containers.values() if v["Name"] == "/" + ref), None)
        return copy.deepcopy(value)

    def call(self, method, path, body=None):
        self.calls.append((method, path))
        ref = path.split("/")[2].split("?")[0]
        value = self.containers[ref]
        if method == "DELETE":
            del self.containers[ref]
        elif "/stop" in path:
            value["State"]["Running"] = False
        elif "/start" in path:
            value["State"]["Running"] = True
        elif "/rename" in path:
            name = "/" + path.split("name=", 1)[1]
            if any(v["Name"] == name for v in self.containers.values()):
                raise RuntimeError("container_name_conflict")
            value["Name"] = name


def replacement(original, token="rotation", running=True):
    value = copy.deepcopy(original)
    value.update(Id="replacement", Name="/" + K.U.CONTAINER, State=dict(Running=running))
    value["Config"]["Labels"]["collect.qa.bootstrap.rotation"] = token
    return value


class RotationTests(unittest.TestCase):
    def reviewed(self, value):
        with patch.object(K, "EXPOSED", SYNTHETIC_HASH):
            return K.reviewed_config(value)

    def test_removes_literal_and_preserves_unrelated_configuration(self):
        original = fixture()
        updated, key = self.reviewed(original)
        self.assertEqual(key, SYNTHETIC_KEY)
        self.assertNotIn(SYNTHETIC_KEY, updated["Entrypoint"][2])
        self.assertEqual(updated["Env"], original["Config"]["Env"])
        self.assertEqual(updated["Labels"], original["Config"]["Labels"])
        self.assertEqual(original["Config"]["Entrypoint"][2].count(SYNTHETIC_KEY), 1)

    def test_rejects_wrong_image_project_volume_and_mount(self):
        for field, bad in [("image", "wrong"), ("project", "wrong"), ("volume", "other"),
                           ("mount", "bind"), ("readonly", False), ("destination", "/other")]:
            with self.subTest(field=field):
                value = fixture()
                if field == "image": value["Image"] = bad
                if field == "project": value["Config"]["Labels"]["com.docker.compose.project"] = bad
                if field == "volume": value["Mounts"][0]["Name"] = bad
                if field == "mount": value["Mounts"][0]["Type"] = bad
                if field == "readonly": value["Mounts"][0]["RW"] = bad
                if field == "destination": value["Mounts"][0]["Destination"] = bad
                with self.assertRaises(RuntimeError): self.reviewed(value)

    def test_rejects_stopped_container_or_changed_command(self):
        for change in ("stopped", "cmd", "entry"):
            value = fixture()
            if change == "stopped": value["State"]["Running"] = False
            if change == "cmd": value["Config"]["Cmd"] = ["postgres"]
            if change == "entry": value["Config"]["Entrypoint"][:2] = ["bash", "-c"]
            with self.assertRaises(RuntimeError): self.reviewed(value)

    def test_rejects_wrong_duplicate_and_alternate_key_copies(self):
        for change in ("wrong", "duplicate", "env"):
            value = fixture()
            if change == "wrong": value["Config"]["Entrypoint"][2] = value["Config"]["Entrypoint"][2].replace(SYNTHETIC_KEY, "a" * 64)
            if change == "duplicate": value["Config"]["Entrypoint"][2] += "\n" + SYNTHETIC_KEY
            if change == "env": value["Config"]["Env"].append("OTHER=" + SYNTHETIC_KEY)
            with self.assertRaises(RuntimeError): self.reviewed(value)

    def test_missing_mounted_key_fails_before_postgres_bootstrap(self):
        updated, _ = self.reviewed(fixture())
        boundary = next(line for line in updated["Entrypoint"][2].splitlines() if line.startswith("test -s "))
        script = boundary.replace(K.KEYFILE, "/dev/null") + "\nprintf MUST_NOT_RUN\n"
        run = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertEqual(run.stdout, "")

    def test_reconciles_create_response_loss_by_exact_owned_name(self):
        original = fixture()
        original["Name"], original["State"]["Running"] = "/prior", False
        engine = MemoryEngine(original, replacement(original))
        with patch.object(K, "wait_ready"):
            K.restore_original(engine, original, None, "rotation", True, True, False, "hash")
        self.assertNotIn("replacement", engine.containers)
        self.assertTrue(engine.containers["original"]["State"]["Running"])
        self.assertEqual(engine.containers["original"]["Name"], "/" + K.U.CONTAINER)
        self.assertTrue(all("v=false" in p for m,p in engine.calls if m == "DELETE"))

    def test_recovery_refuses_unrelated_replacement_without_mutation(self):
        original = fixture()
        original["Name"] = "/prior"
        engine = MemoryEngine(original, replacement(original, token="someone_else"))
        with self.assertRaisesRegex(RuntimeError, "unrecognized"):
            K.restore_original(engine, original, None, "rotation", True, True, False, "hash")
        self.assertEqual(engine.calls, [])

    def test_stopped_replacement_is_deleted_without_redundant_stop(self):
        original = fixture()
        original["Name"], original["State"]["Running"] = "/prior", False
        engine = MemoryEngine(original, replacement(original, running=False))
        with patch.object(K, "wait_ready"):
            K.restore_original(engine, original, "replacement", "rotation", True, True, False, "hash")
        self.assertFalse(any("/replacement/stop" in p for _,p in engine.calls))

    def test_recovery_is_idempotent_after_lost_rename_or_start_response(self):
        original = fixture()
        engine = MemoryEngine(original)
        with patch.object(K, "wait_ready"):
            for _ in range(2):
                K.restore_original(engine, original, None, "rotation", True, True, False, "hash")
        self.assertEqual(engine.calls, [])

    def test_failed_partial_install_cleanup_uses_hash_guard(self):
        original = fixture()
        engine = MemoryEngine(original)
        expected = "b" * 64
        with patch.object(K, "wait_ready"), patch.object(K.subprocess, "run",
                return_value=subprocess.CompletedProcess([], 0)) as run:
            K.restore_original(engine, original, None, "rotation", False, False, True, expected)
        shell = run.call_args.args[0][-1]
        self.assertIn("sha256sum", shell)
        self.assertIn(expected + " && rm --", shell)

    def test_failed_key_hash_guard_does_not_report_success(self):
        original = fixture()
        engine = MemoryEngine(original)
        with patch.object(K, "wait_ready"), patch.object(K.subprocess, "run",
                return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaisesRegex(RuntimeError, "cleanup_failed"):
                K.restore_original(engine, original, None, "rotation", False, False, True, "hash")


if __name__ == "__main__":
    unittest.main(verbosity=2)
