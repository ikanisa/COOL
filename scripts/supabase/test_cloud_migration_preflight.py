import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import scripts.supabase.cloud_migration_preflight as preflight
from scripts.supabase.cloud_migration_preflight import (
    INPUT_FORMAT, LOCK_FORMAT, PROJECT, compare, load_json,
)


class CloudMigrationPreflightTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.directory = self.root / "supabase/migrations"
        self.directory.mkdir(parents=True)
        self.lock_path = self.root / "supabase/managed-migration-history/source-migrations.lock.json"
        self.lock_path.parent.mkdir(parents=True)
        self.lock = {"format": LOCK_FORMAT, "original_count": 1, "migrations": []}
        self.cloud = {"format": INPUT_FORMAT, "project_ref": PROJECT, "records": []}
        self.add_migration("20261020134444_initial.sql", "synthetic initial statement\n")
        self.write_lock()
        subprocess.run(["git", "-C", str(self.root), "add", "supabase/migrations"], check=True)

    def add_migration(self, filename, body, *, statement_count=1):
        (self.directory / filename).write_text(body)
        version, name = filename[:-4].split("_", 1)
        digest = hashlib.sha256(body.encode()).hexdigest()
        self.lock["migrations"].append({"name": filename, "sha256": digest, "transaction": "outer"})
        self.cloud["records"].append({
            "version": version, "name": name, "statement_count": statement_count,
            "statement_sha256": digest if statement_count == 1 else None,
        })

    def write_lock(self):
        self.lock_path.write_text(json.dumps(self.lock))

    def test_equal_metadata_never_claims_schema_or_deployment_readiness(self):
        result = compare(self.root, self.cloud)
        self.assertEqual(result["status"], "matching_history_metadata_only")
        self.assertFalse(result["cloud_identity_independently_verified"])
        self.assertFalse(result["local_review_independently_verified"])
        self.assertFalse(result["schema_parity_verified"])
        self.assertFalse(result["deployment_accepted"])
        self.assertFalse(result["routing_changed"])

    def test_untracked_and_missing_cloud_migrations_require_review(self):
        filename = "20261109234517_burimunsi_native.sql"
        self.add_migration(filename, "synthetic new statement")
        self.cloud["records"].pop()
        self.write_lock()
        result = compare(self.root, self.cloud)
        self.assertEqual(result["status"], "review_required")
        self.assertEqual(result["findings"]["untracked_local"], [filename])
        self.assertEqual(result["findings"]["missing_from_cloud"], [filename])

    def test_reports_changed_local_name_hash_extra_and_unknown_statements(self):
        self.add_migration("20261020140000_second.sql", "synthetic second")
        self.add_migration("20261020150000_third.sql", "synthetic third", statement_count=2)
        self.write_lock()
        (self.directory / "20261020134444_initial.sql").write_text("changed outside lock")
        self.cloud["records"][0]["statement_sha256"] = "a" * 64
        self.cloud["records"][1]["name"] = "different_name"
        self.cloud["records"].append({"version": "20261201000000", "name": "extra",
                                      "statement_count": 0, "statement_sha256": None})
        (self.directory / "20261202000000_unreviewed.sql").write_text("not in the lock")
        findings = compare(self.root, self.cloud)["findings"]
        self.assertEqual(findings["changed_local"], ["20261020134444_initial.sql"])
        self.assertEqual(findings["statement_hash_mismatches"][0]["version"], "20261020134444")
        self.assertEqual(findings["name_mismatches"][0]["version"], "20261020140000")
        self.assertEqual(findings["statement_hash_unverified"], [
            {"version": "20261020150000", "statement_count": 2},
        ])
        self.assertEqual(findings["extra_in_cloud"][0]["version"], "20261201000000")
        self.assertEqual(findings["unexpected_local"], ["20261202000000_unreviewed.sql"])
        self.assertIn("20261202000000_unreviewed.sql", findings["untracked_local"])

    def test_missing_local_and_known_local_only_migration_require_review(self):
        filename = "20261110181002_collect_local_stopped_admission.sql"
        self.add_migration(filename, "synthetic local-specific")
        self.write_lock()
        (self.directory / "20261020134444_initial.sql").unlink()
        findings = compare(self.root, self.cloud)["findings"]
        self.assertEqual(findings["missing_local"], ["20261020134444_initial.sql"])
        self.assertEqual(findings["local_only_review_required"][0]["filename"], filename)

    def test_duplicate_or_malformed_cloud_data_is_refused(self):
        for mutate in (
            lambda v: v["records"].append(copy.deepcopy(v["records"][0])),
            lambda v: v["records"][0].update(statement_count=2),
            lambda v: v["records"][0].update(statement_count=True),
            lambda v: v.update(project_ref="other"),
            lambda v: v["records"][0].update(unexpected="field"),
        ):
            data = copy.deepcopy(self.cloud)
            mutate(data)
            with self.subTest(data=data), self.assertRaises(ValueError):
                compare(self.root, data)

    def test_duplicate_json_keys_and_duplicate_local_versions_are_refused(self):
        path = self.root / "metadata.json"
        path.write_text('{"format": "a", "format": "b"}')
        with self.assertRaises(ValueError):
            load_json(path)
        self.lock["migrations"].append(copy.deepcopy(self.lock["migrations"][0]))
        self.write_lock()
        with self.assertRaises(ValueError):
            compare(self.root, self.cloud)

    def test_symlinked_migration_is_refused(self):
        path = self.directory / "20261020134444_initial.sql"
        path.unlink()
        target = self.root / "elsewhere.sql"
        target.write_text("synthetic initial statement\n")
        path.symlink_to(target)
        with self.assertRaises(ValueError):
            compare(self.root, self.cloud)

    def test_empty_local_lock_is_not_a_matching_history(self):
        self.lock.update(original_count=0, migrations=[])
        self.write_lock()
        with self.assertRaises(ValueError):
            compare(self.root, {"format": INPUT_FORMAT, "project_ref": PROJECT, "records": []})

    def test_source_change_during_comparison_is_refused(self):
        inspect = preflight.local_inventory
        calls = 0

        def changing_inventory(root):
            nonlocal calls
            result = inspect(root)
            calls += 1
            if calls == 1:
                (self.directory / "20261020134444_initial.sql").write_text("changed concurrently")
            return result

        with patch.object(preflight, "local_inventory", side_effect=changing_inventory):
            with self.assertRaisesRegex(ValueError, "changed during comparison"):
                compare(self.root, self.cloud)


if __name__ == "__main__":
    unittest.main()
