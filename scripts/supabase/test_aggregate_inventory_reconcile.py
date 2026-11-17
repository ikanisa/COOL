import copy
import json
from pathlib import Path
import re
import tempfile
import unittest

from scripts.supabase.aggregate_inventory_reconcile import (
    FORMAT, PROJECT, QUERY, REQUIRED_COMMON, compare, load_snapshot,
)


def snapshot(environment, identity):
    relations = [{"schema": schema, "name": name, "row_count": "0"}
                 for schema, name in sorted(REQUIRED_COMMON)]
    relations.append({"schema": "private", "name": "custody", "row_count": "1"})
    if environment == "local_self_hosted":
        relations.extend([
            {"schema": "supabase_migrations", "name": "collect_installation_steps", "row_count": "51"},
            {"schema": "collect_sms", "name": "messages", "row_count": "32"},
        ])
    return {"format": FORMAT, "environment": environment, "identity": identity,
            "captured_at": "2026-11-13T10:00:00Z", "relations": relations}


class AggregateInventoryReconciliationTest(unittest.TestCase):
    def setUp(self):
        self.local = snapshot("local_self_hosted", "local-app")
        self.cloud = snapshot("managed_cloud", PROJECT)

    def test_source_and_target_differences_never_authorize_copy(self):
        self.cloud["relations"].append({"schema": "private", "name": "cloud_only", "row_count": "2"})
        next(r for r in self.local["relations"] if r["schema"] == "app" and r["name"] == "users")["row_count"] = "2"
        next(r for r in self.cloud["relations"] if r["schema"] == "app" and r["name"] == "users")["row_count"] = "1"
        result = compare(self.local, self.cloud)
        self.assertEqual(result["status"], "inventory_only")
        self.assertEqual(result["different_count_relations"], [
            {"schema": "app", "name": "users", "local_row_count": "2", "cloud_row_count": "1"},
        ])
        self.assertIn({"schema": "collect_sms", "name": "messages", "row_count": "32"},
                      result["local_only_relations"])
        self.assertEqual(result["cloud_only_relations"], [
            {"schema": "private", "name": "cloud_only", "row_count": "2"},
        ])
        self.assertEqual(result["installation_journal_local_count"], "51")
        self.assertFalse(result["installation_journal_cloud_present"])
        for field in ("database_identity_independently_verified", "same_rows_or_principals_verified",
                      "storage_bytes_verified", "single_writer_verified", "data_copy_authorized",
                      "cutover_authorized", "provider_migration_history_is_data_transfer_authority"):
            self.assertFalse(result[field])

    def test_equal_counts_are_not_data_identity(self):
        result = compare(self.local, self.cloud)
        self.assertGreater(result["equal_count_relations"], 0)
        self.assertFalse(result["same_rows_or_principals_verified"])
        self.assertFalse(result["cutover_authorized"])

    def test_bad_identity_count_duplicate_and_missing_required_are_refused(self):
        for mutate in (
            lambda s: s.update(identity="another-project"),
            lambda s: s.update(captured_at="2026-11-13"),
            lambda s: s["relations"][0].update(row_count=1),
            lambda s: s["relations"][0].update(row_count="-1"),
            lambda s: s["relations"].append(copy.deepcopy(s["relations"][0])),
            lambda s: s["relations"][0].update(schema="other"),
            lambda s: s["relations"][0].update(raw_data="not allowed"),
            lambda s: s.update(relations=[r for r in s["relations"]
                                         if (r["schema"], r["name"]) != ("app", "users")]),
        ):
            altered = copy.deepcopy(self.cloud)
            mutate(altered)
            with self.subTest(altered=altered), self.assertRaises(ValueError):
                compare(self.local, altered)

    def test_local_installation_journal_is_required(self):
        self.local["relations"] = [r for r in self.local["relations"]
                                   if r["name"] != "collect_installation_steps"]
        with self.assertRaises(ValueError):
            compare(self.local, self.cloud)

    def test_duplicate_json_keys_and_symlinked_snapshot_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp).resolve() / "inventory.json"
            path.write_text('{"format":"a","format":"b"}')
            with self.assertRaises(ValueError):
                load_snapshot(path)
            path.write_text(json.dumps(self.local))
            link = path.with_name("alias.json")
            link.symlink_to(path)
            with self.assertRaises(ValueError):
                load_snapshot(link)

    def test_fixed_query_is_count_only_and_quotes_catalog_identifiers(self):
        self.assertIn("SELECT count(*) AS total FROM %I.%I", QUERY)
        self.assertIn("pg_catalog.format", QUERY)
        self.assertIn("NOT c.relispartition", QUERY)
        self.assertIsNone(re.search(r"\b(?:INSERT|UPDATE|DELETE|ALTER|DROP|CREATE|COPY)\b", QUERY, re.I))


if __name__ == "__main__":
    unittest.main()
