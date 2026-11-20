"""Offline contract tests and an opt-in owned synthetic PostgreSQL fixture."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("collect_portability", HERE / "portability.py")
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)

IDENTITY = "20261101013157_collect_deployment_identity.sql"
STOPPED = "20261110181002_collect_local_stopped_admission.sql"
BODY = " SELECT 1 "
BODY_HASH = hashlib.sha256(BODY.encode()).hexdigest()


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="collect-portability-")
        self.root = Path(self.temp.name).resolve()
        self.directory = self.root / "supabase" / "migrations"
        self.directory.mkdir(parents=True)
        self.lock_path = self.root / "supabase" / "managed-migration-history" / "source-migrations.lock.json"
        self.lock_path.parent.mkdir(parents=True)
        self.files = [(f"20261001{index:06d}_fixture.sql", "SELECT 1;\n") for index in range(16)]
        self.files[0] = (self.files[0][0], "CREATE FUNCTION private.example() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;\n")
        self.files.append((IDENTITY, "SELECT profile->>'mode' IS DISTINCT FROM 'self_hosted';\n"))
        self.files.append((STOPPED, "-- collect_fence_local_stopped_admissions\nSELECT * FROM (VALUES ('private.example()','" + BODY_HASH + "')) v;\n"))
        self.write_files()

    def tearDown(self):
        self.temp.cleanup()

    def write_files(self):
        entries = []
        for name, text in self.files:
            raw = text.encode()
            (self.directory / name).write_bytes(raw)
            entries.append({"name": name, "sha256": hashlib.sha256(raw).hexdigest(), "transaction": "outer"})
        self.lock = {"format": "collect.selfhost.migrations.v1", "original_count": 16, "migrations": entries}
        self.save_lock()

    def save_lock(self):
        self.lock_path.write_text(json.dumps(self.lock), encoding="utf-8")

    def test_chain_maps_preimage_and_remains_no_go(self):
        result = tool.inspect(self.root)
        self.assertEqual(result["managed_deployment_decision"], "NO_GO")
        self.assertEqual(result["migration_count"], 18)
        identity, stopped = result["migrations"][-2:]
        self.assertIn("self_hosted_only_deployment_binding", identity["flags"])
        self.assertIn("local_vm_stopped_executor_protocol", stopped["flags"])
        self.assertEqual(stopped["previous_migration"], IDENTITY)
        pin = stopped["candidate_function_preimages"][0]
        self.assertEqual((pin["signature"], pin["sha256"]), ("private.example()", BODY_HASH))
        self.assertEqual(pin["previous_textual_definition"], self.files[0][0])
        sql = tool.probe_sql(result, STOPPED)
        self.assertIn("BEGIN READ ONLY;", sql)
        self.assertIn("ROLLBACK;", sql)
        self.assertNotIn("CREATE ", sql)
        with self.assertRaisesRegex(tool.InventoryError, "no_extracted_preimages"):
            tool.probe_sql(result, IDENTITY)

    def test_changed_or_missing_sql_refuses(self):
        path = self.directory / self.files[0][0]
        path.write_text("SELECT 999;\n")
        with self.assertRaisesRegex(tool.InventoryError, "migration_hash"):
            tool.inspect(self.root)
        path.unlink()
        with self.assertRaisesRegex(tool.InventoryError, "migration_set"):
            tool.inspect(self.root)

    def test_extra_or_duplicate_migration_refuses(self):
        extra = self.directory / "20261110181002_extra.sql"
        extra.write_text("SELECT 1;")
        with self.assertRaisesRegex(tool.InventoryError, "migration_set"):
            tool.inspect(self.root)
        extra.unlink()
        self.lock["migrations"].append(dict(self.lock["migrations"][-1]))
        self.save_lock()
        with self.assertRaisesRegex(tool.InventoryError, "migration_set"):
            tool.inspect(self.root)

    def test_subsequent_cloud_migrations_are_outside_the_historical_inventory(self):
        expected = tool.inspect(self.root)
        (self.directory / "20261114123456_later_cloud_change.sql").write_text("SELECT 1;")
        self.assertEqual(tool.inspect(self.root), expected)

    def test_duplicate_json_key_and_symlink_refuse(self):
        self.lock_path.write_text('{"format":"a","format":"b","original_count":16,"migrations":[]}')
        with self.assertRaisesRegex(tool.InventoryError, "duplicate_json_key"):
            tool.inspect(self.root)
        self.save_lock()
        source = self.directory / self.files[0][0]
        source.unlink()
        source.symlink_to(self.directory / self.files[1][0])
        with self.assertRaisesRegex(tool.InventoryError, "nonregular"):
            tool.inspect(self.root)

    def test_draft_comments_are_reported_not_authorized(self):
        name, text = self.files[-1]
        self.files[-1] = (name, "-- UNREGISTERED DRAFT.\n" + text)
        self.write_files()
        result = tool.inspect(self.root)
        self.assertIn("draft_or_inspection_only_source_comment", result["migrations"][-1]["flags"])
        self.assertEqual(result["managed_deployment_decision"], "NO_GO")

    def test_inline_and_direct_prosrc_pins_are_candidates(self):
        name, text = self.files[-1]
        text += ("SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private.example()') "
                 "AND p.prosecdef AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='" + BODY_HASH + "';\n")
        text += ("SELECT 1 WHERE (SELECT prosrc FROM pg_proc WHERE oid='private.example()'::regprocedure) "
                 "IS DISTINCT FROM '" + BODY_HASH + "';\n")
        self.files[-1] = (name, text)
        self.write_files()
        pins = tool.inspect(self.root)["migrations"][-1]["candidate_function_preimages"]
        self.assertEqual([pin["source_form"] for pin in pins],
                         ["literal_tuple", "inline_prosrc_comparison", "direct_regprocedure_comparison"])
        self.assertTrue(all(pin["signature"] == "private.example()" for pin in pins))

    def test_missing_anchor_and_reordered_lock_refuse(self):
        self.lock["migrations"][-2], self.lock["migrations"][-1] = self.lock["migrations"][-1], self.lock["migrations"][-2]
        self.save_lock()
        with self.assertRaisesRegex(tool.InventoryError, "migration_set"):
            tool.inspect(self.root)
        self.lock["migrations"][-2], self.lock["migrations"][-1] = self.lock["migrations"][-1], self.lock["migrations"][-2]
        self.save_lock()
        self.files[-2] = (IDENTITY, "SELECT 'managed';\n")
        self.write_files()
        with self.assertRaisesRegex(tool.InventoryError, "deployment_identity_anchor_changed"):
            tool.inspect(self.root)


@unittest.skipUnless(os.environ.get("COLLECT_PORTABILITY_PG_BIN"), "explicit synthetic PostgreSQL binary directory not supplied")
class SyntheticCatalogTests(InventoryTests):
    def test_generated_catalog_probe_against_owned_synthetic_pg17(self):
        """Create only our own Unix-socket cluster; never inspect another server."""
        binary = Path(os.environ["COLLECT_PORTABILITY_PG_BIN"]).resolve(strict=True)
        for name in ("initdb", "pg_ctl", "psql"):
            self.assertTrue((binary / name).is_file(), name)
        data = self.root / "fixture-data"
        # macOS Unix-domain socket paths are short; the default temp hierarchy
        # can exceed that limit even when initdb and the server are otherwise valid.
        socket_temp = tempfile.TemporaryDirectory(prefix="cp-", dir="/tmp")
        socket = Path(socket_temp.name).resolve()
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LC_ALL": "C",
               "PGHOST": str(socket), "PGPORT": "55478", "PGUSER": "collect_portability_fixture",
               "PGDATABASE": "postgres", "PGCONNECT_TIMEOUT": "3"}
        init = [str(binary / "initdb"), "-D", str(data), "--username=collect_portability_fixture",
                "--auth=trust", "--encoding=UTF8", "--no-locale"]
        subprocess.run(init, env=env, check=True, capture_output=True, text=True, timeout=60)
        options = f"-c listen_addresses='' -c unix_socket_directories='{socket}' -p 55478 -c unix_socket_permissions=0700"
        started = False
        try:
            subprocess.run([str(binary / "pg_ctl"), "-D", str(data), "-l", str(self.root / "fixture.log"),
                            "-o", options, "-w", "start"], env=env, check=True, capture_output=True, text=True, timeout=60)
            started = True
            def psql(sql):
                return subprocess.run([str(binary / "psql"), "-X", "--no-psqlrc", "--set=ON_ERROR_STOP=1", "-qAt"],
                                      input=sql, env=env, check=True, capture_output=True, text=True, timeout=10).stdout.strip()
            self.assertEqual(psql("SHOW server_version_num;" )[:2], "17")
            psql("CREATE SCHEMA private; CREATE FUNCTION private.example() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;")
            output = psql(tool.probe_sql(tool.inspect(self.root), STOPPED)).split("|")
            self.assertEqual(output[0:4], ["private.example()", BODY_HASH, "t", BODY_HASH])
            psql("CREATE OR REPLACE FUNCTION private.example() RETURNS int LANGUAGE sql AS $$ SELECT 2 $$;")
            changed = psql(tool.probe_sql(tool.inspect(self.root), STOPPED)).split("|")
            self.assertEqual(changed[2], "t")
            self.assertNotEqual(changed[3], BODY_HASH)
            psql("DROP FUNCTION private.example();")
            missing = psql(tool.probe_sql(tool.inspect(self.root), STOPPED)).split("|")
            self.assertEqual(missing[2], "f")
        finally:
            if started or (data / "postmaster.pid").exists():
                subprocess.run([str(binary / "pg_ctl"), "-D", str(data), "-m", "fast", "-w", "stop"],
                               env=env, check=True, capture_output=True, text=True, timeout=30)
            socket_temp.cleanup()


if __name__ == "__main__":
    unittest.main(verbosity=2)
