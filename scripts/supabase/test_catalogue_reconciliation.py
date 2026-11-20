import contextlib
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from scripts.supabase import catalogue_reconciliation as catalogue


H1, H2 = "a" * 64, "b" * 64


def column(name="id", position="1"):
    return {"name": name, "position": position, "type_schema": "pg_catalog",
            "type_name": "text", "type_kind": "b", "type_modifier": "-1",
            "not_null": True, "identity": "", "generated": "", "collation": None,
            "default_sha256": None}


def constraint(name="users_pkey"):
    return {"name": name, "kind": "p", "definition_sha256": H1,
            "deferrable": False, "initially_deferred": False, "validated": True}


def relation(schema="app", name="users"):
    return {"schema": schema, "name": name, "kind": "r", "is_partition": False,
            "columns": [column()], "constraints": [constraint()]}


def classification(schema="app", name="users", category="business"):
    return {"schema": schema, "name": name, "classification": category}


def snapshots():
    local = {"format": catalogue.FORMAT, "environment": "local_self_hosted",
             "identity": "local-app", "captured_at": "2026-11-13T10:00:00Z",
             "covered_schemas": ["app", "private", "collect_sms"],
             "classifications": [classification()], "relations": [relation()]}
    cloud = copy.deepcopy(local)
    cloud.update(environment="managed_cloud", identity=catalogue.PROJECT,
                 captured_at="2026-11-13T10:01:00Z")
    return local, cloud


def names(records):
    return {(item["schema"], item["name"]) for item in records}


class CatalogueComparisonTests(unittest.TestCase):
    def test_identical_descriptors_are_review_only_not_data_or_schema_parity(self):
        local, cloud = snapshots()
        result = catalogue.compare(local, cloud)
        self.assertEqual(result["status"], "review_required")
        for key in ("structural_differences", "local_only_relations", "cloud_only_relations",
                    "unclassified_relations", "declared_missing_in_local", "declared_missing_in_cloud"):
            self.assertEqual(result[key], [], key)
        for key in ("classification_independently_verified", "catalogue_completeness_independently_verified",
                    "database_identity_independently_verified", "schema_parity_verified", "data_equality_verified",
                    "data_copy_authorized", "cutover_authorized"):
            self.assertIs(result[key], False, key)

    def test_comparison_uses_names_not_input_list_order(self):
        local, cloud = snapshots()
        for item in (local, cloud):
            item["relations"][0]["columns"].append(column("created_at", "2"))
            item["relations"][0]["constraints"].append(constraint("users_email_key"))
            item["classifications"].append(classification("private", "history", "archive_only"))
            item["relations"].append(relation("private", "history"))
        cloud["covered_schemas"].reverse()
        cloud["classifications"].reverse()
        cloud["relations"].reverse()
        cloud["relations"][1]["columns"].reverse()
        cloud["relations"][1]["constraints"].reverse()
        self.assertEqual(catalogue.compare(local, cloud)["structural_differences"], [])

    def test_reports_absent_unclassified_and_expected_missing_on_both_sides(self):
        local, cloud = snapshots()
        local["relations"].append(relation("private", "source_only"))
        cloud["relations"].append(relation("collect_sms", "target_only"))
        for item in (local, cloud):
            item["classifications"].extend([classification("private", "source_only", "identity_authority"),
                                            classification("private", "expected_but_absent", "operational_state")])
        result = catalogue.compare(local, cloud)
        self.assertEqual(names(result["local_only_relations"]), {("private", "source_only")})
        self.assertEqual(names(result["cloud_only_relations"]), {("collect_sms", "target_only")})
        self.assertEqual(names(result["unclassified_relations"]), {("collect_sms", "target_only")})
        self.assertEqual(names(result["declared_missing_in_local"]), {("private", "expected_but_absent")})
        self.assertEqual(names(result["declared_missing_in_cloud"]),
                         {("private", "source_only"), ("private", "expected_but_absent")})

    def test_classification_disagreement_and_explicit_unclassified_never_become_classified(self):
        local, cloud = snapshots()
        cloud["classifications"][0]["classification"] = "archive_only"
        local["relations"].append(relation("private", "pending"))
        cloud["relations"].append(relation("private", "pending"))
        for item in (local, cloud):
            item["classifications"].append(classification("private", "pending", "unclassified"))
        result = catalogue.compare(local, cloud)
        self.assertEqual(names(result["unclassified_relations"]), {("app", "users"), ("private", "pending")})
        self.assertEqual(result["classification_mismatches"],
                         [{"schema": "app", "name": "users", "local": "business", "cloud": "archive_only"}])

    def test_relation_column_and_constraint_changes_are_reported_with_both_values(self):
        local, cloud = snapshots()
        local["relations"][0]["columns"].append(column("only_local", "2"))
        cloud["relations"][0]["columns"].append(column("only_cloud", "3"))
        local["relations"][0]["constraints"].append(constraint("local_check"))
        cloud["relations"][0]["constraints"].append(constraint("cloud_check"))
        target = cloud["relations"][0]
        target.update(kind="p", is_partition=True)
        target["columns"][0].update(type_schema="private", type_name="account_id", type_kind="d",
                                   type_modifier="12", not_null=False, identity="a", generated="s",
                                   collation={"schema": "pg_catalog", "name": "default"}, default_sha256=H2)
        target["constraints"][0].update(kind="u", definition_sha256=H2, deferrable=True,
                                       initially_deferred=True, validated=False)
        result = catalogue.compare(local, cloud)
        self.assertEqual(len(result["structural_differences"]), 1)
        diff = result["structural_differences"][0]
        self.assertEqual({c["field"] for c in diff["relation_changes"]}, {"kind", "is_partition"})
        self.assertEqual(diff["columns_missing_in_cloud"], ["only_local"])
        self.assertEqual(diff["columns_missing_in_local"], ["only_cloud"])
        self.assertEqual(diff["constraints_missing_in_cloud"], ["local_check"])
        self.assertEqual(diff["constraints_missing_in_local"], ["cloud_check"])
        self.assertEqual({c["field"] for c in diff["columns_changed"][0]["changes"]},
                         {"type_schema", "type_name", "type_kind", "type_modifier", "not_null",
                          "identity", "generated", "collation", "default_sha256"})
        self.assertEqual({c["field"] for c in diff["constraints_changed"][0]["changes"]},
                         {"kind", "definition_sha256", "deferrable", "initially_deferred", "validated"})

    def test_real_postgres_collation_names_are_accepted_and_compared_exactly(self):
        for label in ("C", "POSIX", "C.UTF-8", "en-US-x-icu", "und-x-icu", "fr_FR.utf8",
                      "é-x-icu", "a" * 63, "é" * 31 + "a"):
            local, cloud = snapshots()
            for snapshot in (local, cloud):
                snapshot["relations"][0]["columns"][0]["collation"] = {"schema": "pg_catalog", "name": label}
            with self.subTest(label=label):
                self.assertEqual(catalogue.compare(local, cloud)["structural_differences"], [])
        local, cloud = snapshots()
        local["relations"][0]["columns"][0]["collation"] = {"schema": "pg_catalog", "name": "C"}
        cloud["relations"][0]["columns"][0]["collation"] = {"schema": "pg_catalog", "name": "c"}
        change = catalogue.compare(local, cloud)["structural_differences"][0]["columns_changed"][0]["changes"]
        self.assertEqual(change, [{"field": "collation", "local": {"schema": "pg_catalog", "name": "C"},
                                   "cloud": {"schema": "pg_catalog", "name": "c"}}])

    def test_collation_label_is_compared_as_data_not_executed_as_sql(self):
        local, cloud = snapshots()
        label = "example'; SELECT 1; --"
        local["relations"][0]["columns"][0]["collation"] = {"schema": "pg_catalog", "name": label}
        cloud["relations"][0]["columns"][0]["collation"] = {"schema": "pg_catalog", "name": "C"}
        with patch("subprocess.run", side_effect=AssertionError("unexpected process")):
            result = catalogue.compare(local, cloud)
        change = result["structural_differences"][0]["columns_changed"][0]["changes"][0]
        self.assertEqual(change["field"], "collation")
        self.assertEqual(change["local"]["name"], label)
        self.assertFalse(result["data_copy_authorized"])

    def test_unrepresentable_or_oversized_collation_labels_fail_closed(self):
        for label in ("", "a" * 64, "é" * 32, "bad\x00name", "bad\nname", "a\u202eb", "\ud800", None, 1, []):
            local, cloud = snapshots()
            local["relations"][0]["columns"][0]["collation"] = {"schema": "pg_catalog", "name": label}
            with self.subTest(label=repr(label)), self.assertRaises(ValueError):
                catalogue.compare(local, cloud)
        local, cloud = snapshots()
        local["relations"][0]["columns"][0]["collation"] = {"schema": "PG_catalog", "name": "C"}
        with self.assertRaises(ValueError):
            catalogue.compare(local, cloud)

    def test_observed_rematch_column_with_c_collation_is_a_valid_descriptor(self):
        local, cloud = snapshots()
        local["relations"].append({"schema": "private", "name": "burimunsi_rematch_jobs", "kind": "r",
            "is_partition": False, "columns": [dict(column("after_transaction_id"),
                collation={"schema": "pg_catalog", "name": "C"})], "constraints": []})
        result = catalogue.compare(local, cloud)
        self.assertEqual(result["local_only_relations"], [{"schema": "private", "name": "burimunsi_rematch_jobs"}])
        self.assertFalse(result["data_copy_authorized"])

    def test_column_position_change_is_detected(self):
        local, cloud = snapshots()
        cloud["relations"][0]["columns"][0]["position"] = "3"
        change = catalogue.compare(local, cloud)["structural_differences"][0]["columns_changed"][0]["changes"]
        self.assertEqual(change, [{"field": "position", "local": "1", "cloud": "3"}])

    def test_each_unknown_classification_is_rejected(self):
        for invalid in ("approved", "BUSINESS", "", None, [], 1):
            local, cloud = snapshots()
            local["classifications"][0]["classification"] = invalid
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                catalogue.compare(local, cloud)

    def test_duplicate_relation_classification_column_position_or_constraint_rejected(self):
        for kind in ("relation", "classification", "column", "position", "constraint"):
            local, cloud = snapshots()
            table = local["relations"][0]
            if kind == "relation":
                local["relations"].append(copy.deepcopy(table))
            elif kind == "classification":
                local["classifications"].append(copy.deepcopy(local["classifications"][0]))
            elif kind == "column":
                table["columns"].append(column(position="2"))
            elif kind == "position":
                table["columns"].append(column("other", "1"))
            else:
                table["constraints"].append(constraint())
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                catalogue.compare(local, cloud)

    def test_malformed_nested_types_fail_closed(self):
        mutations = (
            lambda x: x["relations"][0].update(schema=[]),
            lambda x: x["relations"][0].update(kind=[]),
            lambda x: x["relations"][0].update(is_partition=1),
            lambda x: x["relations"][0]["columns"][0].update(type_kind=[]),
            lambda x: x["relations"][0]["constraints"][0].update(kind=[]),
            lambda x: x["relations"][0]["columns"][0].update(not_null=1),
            lambda x: x["relations"][0]["constraints"][0].update(initially_deferred=True),
            lambda x: x["relations"][0]["columns"][0].update(position="01"),
            lambda x: x["relations"][0]["columns"][0].update(type_modifier="2147483648"),
            lambda x: x["relations"][0]["columns"][0].update(default_sha256="unavailable"),
            lambda x: x["relations"][0]["constraints"][0].update(definition_sha256=None),
            lambda x: x["relations"][0]["columns"][0].update(collation={"schema": "pg_catalog"}),
            lambda x: x["relations"][0]["columns"][0].update(name="users; DROP TABLE users"),
        )
        for index, mutate in enumerate(mutations):
            local, cloud = snapshots()
            mutate(local)
            with self.subTest(index=index), self.assertRaises(ValueError):
                catalogue.compare(local, cloud)

    def test_unsupported_envelopes_scope_and_wrong_identity_are_rejected(self):
        mutations = (
            lambda x: x.update(extra="not permitted"),
            lambda x: x.update(format="other"),
            lambda x: x.update(identity="other-project"),
            lambda x: x.update(captured_at="2026-11-13T10:00:00"),
            lambda x: x.update(captured_at="2026-02-30T10:00:00Z"),
            lambda x: x.update(covered_schemas=["app", "private", "private"]),
            lambda x: x.update(covered_schemas=["app", "private", "auth"]),
            lambda x: x.update(relations=[]),
            lambda x: x.update(classifications=[classification()] * (catalogue.MAX_CLASSIFICATIONS + 1)),
        )
        for index, mutate in enumerate(mutations):
            local, cloud = snapshots()
            mutate(local)
            with self.subTest(index=index), self.assertRaises(ValueError):
                catalogue.compare(local, cloud)

    def test_duplicate_json_keys_and_non_json_numeric_constants_are_rejected(self):
        for raw in ('{"format":"a","format":"b"}', '{"format":NaN}',
                    '{"inner":{"name":"a","name":"b"}}'):
            with self.subTest(raw=raw), tempfile.TemporaryDirectory() as temp:
                path = Path(temp) / "metadata.json"
                path.write_text(raw)
                with self.assertRaises(ValueError):
                    catalogue.load_metadata(path)

    def test_oversized_symlink_nonregular_and_invalid_utf8_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            large = root / "large.json"
            with large.open("wb") as f:
                f.seek(catalogue.MAX_INPUT_BYTES)
                f.write(b"x")
            with self.assertRaises(ValueError):
                catalogue.load_metadata(large)
            bad = root / "bad.json"
            bad.write_bytes(b"\xff")
            with self.assertRaises(UnicodeError):
                catalogue.load_metadata(bad)
            link = root / "link.json"
            link.symlink_to(bad)
            with self.assertRaises(OSError):
                catalogue.load_metadata(link)
            if hasattr(os, "mkfifo"):
                fifo = root / "input.fifo"
                os.mkfifo(fifo)
                with self.assertRaises(ValueError):
                    catalogue.load_metadata(fifo)

    def test_cli_reads_only_explicit_files_and_does_not_echo_invalid_content(self):
        local, cloud = snapshots()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first, second = root / "local.json", root / "cloud.json"
            first.write_text(json.dumps(local))
            second.write_text(json.dumps(cloud))
            env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
            command = [sys.executable, "-m", "scripts.supabase.catalogue_reconciliation", str(first), str(second)]
            ok = subprocess.run(command, check=False, capture_output=True, text=True, env=env)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertFalse(json.loads(ok.stdout)["data_copy_authorized"])
            first.write_text('{"duplicate":"synthetic-secret","duplicate":"synthetic-secret"}')
            bad = subprocess.run(command, check=False, capture_output=True, text=True, env=env)
            self.assertEqual(bad.returncode, 2)
            self.assertEqual(json.loads(bad.stdout)["status"], "invalid_input")
            self.assertEqual(json.loads(bad.stdout)["error_code"], "duplicate_json_key")
            self.assertNotIn("synthetic-secret", bad.stdout + bad.stderr)
            local["classifications"][0]["classification"] = "unexpected"
            first.write_text(json.dumps(local))
            invalid_class = subprocess.run(command, check=False, capture_output=True, text=True, env=env)
            self.assertEqual(invalid_class.returncode, 2)
            self.assertEqual(json.loads(invalid_class.stdout)["error_code"], "invalid_classification")

    def test_report_size_bound_returns_fail_closed_without_partial_report(self):
        local, cloud = snapshots()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            paths = [root / "local.json", root / "cloud.json"]
            for path, snapshot in zip(paths, (local, cloud)):
                path.write_text(json.dumps(snapshot))
            output = io.StringIO()
            with patch.object(catalogue, "MAX_OUTPUT_BYTES", 1), contextlib.redirect_stdout(output):
                code = catalogue.main([str(p) for p in paths])
            self.assertEqual(code, 2)
            self.assertEqual(json.loads(output.getvalue())["status"], "invalid_input")


if __name__ == "__main__":
    unittest.main()
