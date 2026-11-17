import contextlib
import hashlib
import copy
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from scripts.supabase import catalogue_capture as capture
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


def response():
    return [{"payload": {"format": capture.CAPTURE_FORMAT, "status": "ok",
            "context": dict(capture.CONTEXT, server_version_num="170011"),
            "covered_schemas": ["app", "private", "collect_sms"],
            "present_schemas": ["app", "private"],
            "counts": {"relations": 1, "columns": 1, "constraints": 1},
            "relations": [relation()]}}]


def classes():
    return [{"schema": "app", "name": "users", "classification": "business"}]


_DEFAULT = object()


def build(data=_DEFAULT, **override):
    args = {"environment": "local_self_hosted", "identity": "local-app",
            "captured_at": "2026-11-13T10:00:00Z", "classifications": classes()}
    args.update(override)
    return capture.build_metadata(response() if data is _DEFAULT else data, **args)


class CatalogueCaptureTests(unittest.TestCase):
    def test_fixed_sql_contains_only_catalogue_sources_and_bounded_read(self):
        sql = capture.SQL
        self.assertTrue(sql.startswith("WITH\ncontext AS MATERIALIZED"))
        self.assertTrue(sql.endswith(";"))
        self.assertEqual(sql.count(";"), 1)
        self.assertIn("pg_catalog.pg_namespace", sql)
        self.assertIn("WHERE g.context_ok IS TRUE AND n.nspname", sql)
        self.assertIn("pg_catalog.pg_class", sql)
        self.assertIn("pg_catalog.pg_attribute", sql)
        self.assertIn("pg_catalog.pg_type", sql)
        self.assertIn("pg_catalog.pg_attrdef", sql)
        self.assertIn("pg_catalog.pg_constraint", sql)
        self.assertIn("pg_catalog.pg_get_expr", sql)
        self.assertIn("pg_catalog.pg_get_constraintdef", sql)
        self.assertIn("pg_catalog.sha256(pg_catalog.convert_to", sql)
        self.assertIn("LIMIT 10001", sql)
        self.assertEqual(sql.count("LIMIT 40001"), 2)
        self.assertIn("b.column_count+b.constraint_count<=40000", sql)
        self.assertIn("pg_catalog.octet_length(a.payload::text)>" + str(capture.MAX_CAPTURE_PAYLOAD_BYTES), sql)
        self.assertIn("<=", sql)
        self.assertIn(str(capture.MAX_EXPRESSION_BYTES), sql)
        self.assertNotRegex(sql, r"(?i)\b(?:insert|update|delete|truncate|copy|drop|alter|create|execute)\b")
        self.assertNotRegex(sql, r"(?i)\b(?:app|private|collect_sms)\.[a-z_][a-z0-9_]*\b")

    def test_builds_exact_comparator_format_without_provenance_claims(self):
        result = build()
        self.assertEqual(result["format"], catalogue.FORMAT)
        self.assertEqual(result["environment"], "local_self_hosted")
        self.assertEqual(result["identity"], "local-app")
        self.assertEqual(result["captured_at"], "2026-11-13T10:00:00Z")
        self.assertEqual(set(result), {"format", "environment", "identity", "captured_at", "covered_schemas", "classifications", "relations"})
        catalogue.validate(result, environment="local_self_hosted", identity="local-app")
        cloud = build(environment="managed_cloud", identity=catalogue.PROJECT)
        compared = catalogue.compare(result, cloud)
        self.assertEqual(compared["status"], "review_required")
        self.assertFalse(compared["catalogue_completeness_independently_verified"])
        self.assertFalse(compared["database_identity_independently_verified"])
        self.assertFalse(compared["data_equality_verified"])
        self.assertFalse(compared["cutover_authorized"])

    def test_result_does_not_alias_the_supplied_response_or_classifications(self):
        source = response()
        supplied = classes()
        result = build(source, classifications=supplied)
        source[0]["payload"]["relations"][0]["columns"][0]["type_name"] = "mutated"
        supplied[0]["classification"] = "unclassified"
        self.assertEqual(result["relations"][0]["columns"][0]["type_name"], "text")
        self.assertEqual(result["classifications"][0]["classification"], "business")

    def test_schema_and_descriptor_drift_survives_normalization(self):
        local = response()
        cloud = response()
        column_cloud = cloud[0]["payload"]["relations"][0]["columns"][0]
        column_cloud.update(type_name="int8", not_null=False, default_sha256=H2)
        cloud[0]["payload"]["relations"][0]["constraints"][0]["definition_sha256"] = H2
        cloud[0]["payload"]["relations"].append(relation("private", "target_only"))
        cloud[0]["payload"]["counts"] = {"relations": 2, "columns": 2, "constraints": 2}
        a = build(local)
        b = build(cloud, environment="managed_cloud", identity=catalogue.PROJECT)
        result = catalogue.compare(a, b)
        self.assertEqual(result["cloud_only_relations"], [{"schema": "private", "name": "target_only"}])
        self.assertEqual(result["unclassified_relations"], [{"schema": "private", "name": "target_only"}])
        change = result["structural_differences"][0]
        self.assertEqual({x["field"] for x in change["columns_changed"][0]["changes"]},
                         {"type_name", "not_null", "default_sha256"})
        self.assertEqual(change["constraints_changed"][0]["changes"][0]["field"], "definition_sha256")

    def test_requires_independent_exact_identity_timestamp_and_known_classifications(self):
        for kwargs in ({"environment": "managed_cloud", "identity": "local-app"},
                       {"identity": "incorrect"}, {"captured_at": "2026-11-13"},
                       {"classifications": [{"schema": "app", "name": "users", "classification": "approved"}]},
                       {"classifications": classes() * 2}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                build(**kwargs)

    def test_malformed_truncated_or_extra_response_fails_closed(self):
        data = response()
        invalid = [None, {}, [], data * 2, [{}], [{"payload": "not-jsonb"}],
                   [{"payload": {"format": capture.CAPTURE_FORMAT, "status": "refused", "reason": "capture_bound"}}]]
        for candidate in invalid:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                build(candidate)
        for field in ("format", "status", "context", "covered_schemas", "present_schemas", "counts", "relations"):
            partial = response()
            del partial[0]["payload"][field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                build(partial)
        extra = response()
        extra[0]["payload"]["unexpected"] = "unreviewed"
        with self.assertRaises(ValueError):
            build(extra)
        refused = [{"payload": {"format": capture.CAPTURE_FORMAT, "status": "refused", "reason": "capture_bound"}}]
        with self.assertRaisesRegex(capture.CaptureInputError, "^capture_refused_capture_bound$"):
            build(refused)

    def test_truncated_relation_column_or_constraint_list_is_detected(self):
        for area in ("relations", "columns", "constraints"):
            data = response()
            if area == "relations":
                data[0]["payload"]["relations"] = []
            else:
                data[0]["payload"]["relations"][0][area] = []
            with self.subTest(area=area), self.assertRaises(ValueError):
                build(data)

    def test_extra_dropped_or_unrepresentable_columns_or_constraints_are_refused(self):
        mutations = (
            lambda r: r["columns"][0].pop("default_sha256"),
            lambda r: r["columns"][0].update(default_sha256="unavailable"),
            lambda r: r["columns"][0].update(type_kind="unknown"),
            lambda r: r["columns"][0].update(row_value="must never be present"),
            lambda r: r["constraints"][0].pop("definition_sha256"),
            lambda r: r["constraints"][0].update(definition_sha256=None),
            lambda r: r["constraints"][0].update(kind="unknown"),
        )
        for index, mutation in enumerate(mutations):
            data = response()
            mutation(data[0]["payload"]["relations"][0])
            with self.subTest(index=index), self.assertRaises(ValueError):
                build(data)

    def test_capture_context_drift_is_refused(self):
        changes = {"server_version_num": "160005", "server_encoding": "LATIN1", "client_encoding": "LATIN1",
                   "search_path": "public, pg_catalog", "timezone": "Africa/Kigali", "date_style": "SQL, MDY",
                   "interval_style": "iso_8601", "bytea_output": "escape", "extra_float_digits": "1",
                   "standard_conforming_strings": "off", "quote_all_identifiers": "on", "statement_timeout": "0",
                   "lock_timeout": "0", "transaction_read_only": "off", "transaction_isolation": "read committed"}
        for field, value in changes.items():
            data = response()
            data[0]["payload"]["context"][field] = value
            with self.subTest(field=field), self.assertRaises(capture.CaptureInputError):
                build(data)

    def test_schema_presence_and_coverage_are_separate_and_validated(self):
        data = response()
        result = build(data)
        self.assertIn("collect_sms", result["covered_schemas"])
        self.assertNotIn("collect_sms", data[0]["payload"]["present_schemas"])
        for present in (["app", "app"], ["unknown"], ["private"], ["app", []]):
            changed = response()
            changed[0]["payload"]["present_schemas"] = present
            with self.subTest(present=present), self.assertRaises(ValueError):
                build(changed)
        changed = response()
        changed[0]["payload"]["covered_schemas"] = ["app", "private"]
        with self.assertRaises(ValueError):
            build(changed)

    def test_counts_types_and_limits_are_checked(self):
        for key, value in (("relations", True), ("columns", -1), ("constraints", "1"),
                           ("relations", catalogue.MAX_RELATIONS + 1),
                           ("columns", catalogue.MAX_DESCRIPTORS + 1)):
            data = response()
            data[0]["payload"]["counts"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                build(data)
        data = response()
        data[0]["payload"]["relations"][0]["columns"] = [column("c" + str(i), str(i+1))
                                                           for i in range(catalogue.MAX_COLUMNS_PER_RELATION + 1)]
        data[0]["payload"]["counts"]["columns"] = catalogue.MAX_COLUMNS_PER_RELATION + 1
        with self.assertRaises(ValueError):
            build(data)

    def test_duplicate_relations_columns_and_constraints_are_rejected(self):
        for area in ("relation", "column", "constraint"):
            data = response()
            payload = data[0]["payload"]
            row = payload["relations"][0]
            if area == "relation":
                payload["relations"].append(copy.deepcopy(row))
                payload["counts"] = {"relations": 2, "columns": 2, "constraints": 2}
            elif area == "column":
                row["columns"].append(copy.deepcopy(row["columns"][0]))
                payload["counts"]["columns"] = 2
            else:
                row["constraints"].append(copy.deepcopy(row["constraints"][0]))
                payload["counts"]["constraints"] = 2
            with self.subTest(area=area), self.assertRaises(ValueError):
                build(data)

    def test_response_and_comparator_output_size_bounds_fail_closed(self):
        with patch.object(capture, "MAX_CAPTURE_PAYLOAD_BYTES", 10), self.assertRaises(capture.CaptureInputError):
            build()
        with patch.object(catalogue, "MAX_INPUT_BYTES", 10), self.assertRaises(capture.CaptureInputError):
            build()

    def test_cli_emits_comparator_json_and_unverified_missing_schema_notice(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result_file, classes_file = root / "result.json", root / "classes.json"
            result_file.write_text(json.dumps(response()))
            classes_file.write_text(json.dumps(classes()))
            env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
            command = [sys.executable, "-m", "scripts.supabase.catalogue_capture", "--response", str(result_file),
                       "--environment", "local_self_hosted", "--identity", "local-app", "--captured-at", "2026-11-13T10:00:00Z",
                       "--classifications", str(classes_file)]
            ok = subprocess.run(command, check=False, capture_output=True, text=True, env=env)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            output, notice = json.loads(ok.stdout), json.loads(ok.stderr)
            catalogue.validate(output, environment="local_self_hosted", identity="local-app")
            self.assertEqual(notice["missing_schemas"], ["collect_sms"])
            self.assertEqual(notice["server_version_num"], "170011")
            self.assertEqual(notice["query_sha256"], hashlib.sha256((capture.SQL + "\n").encode()).hexdigest())
            for key in ("schema_presence_in_comparator_metadata", "query_origin_independently_verified",
                        "provenance_independently_verified", "database_identity_independently_verified",
                        "catalogue_completeness_independently_verified", "data_equality_verified",
                        "data_copy_authorized", "cutover_authorized"):
                self.assertFalse(notice[key])
            result_file.write_text('{"sensitive":"synthetic-secret","sensitive":"synthetic-secret"}')
            bad = subprocess.run(command, check=False, capture_output=True, text=True, env=env)
            self.assertEqual(bad.returncode, 2)
            self.assertEqual(json.loads(bad.stdout)["error_code"], "duplicate_json_key")
            self.assertNotIn("synthetic-secret", bad.stdout + bad.stderr)

    def test_sql_mode_rejects_capture_arguments_and_injection_attempts(self):
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        command = [sys.executable, "-m", "scripts.supabase.catalogue_capture", "--sql", "--identity", "app; DROP TABLE users"]
        result = subprocess.run(command, check=False, capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("DROP TABLE", result.stderr)
        printed = subprocess.run([sys.executable, "-m", "scripts.supabase.catalogue_capture", "--sql"],
                                 check=False, capture_output=True, text=True, env=env)
        self.assertEqual(printed.returncode, 0)
        self.assertEqual(printed.stdout, capture.SQL + "\n")
        self.assertEqual(hashlib.sha256(printed.stdout.encode()).hexdigest(),
                         hashlib.sha256((capture.SQL + "\n").encode()).hexdigest())

    @unittest.skipUnless(os.environ.get("COLLECT_CATALOGUE_SYNTHETIC_PGLITE_MODULE"),
                         "Set COLLECT_CATALOGUE_SYNTHETIC_PGLITE_MODULE for the in-memory PostgreSQL fixture")
    def test_fixed_sql_in_memory_postgres_hash_drift_and_refusals(self):
        # A supplied local PGlite module runs entirely in memory with synthetic
        # schemas; it opens no socket and requires no real database or provider.
        source = r"""
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.COLLECT_CATALOGUE_SYNTHETIC_PGLITE_MODULE);
const db=new PGlite();const sql=readFileSync(0,'utf8');
const sha=s=>createHash('sha256').update(s,'utf8').digest('hex');
const begin=`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
 SET LOCAL search_path=pg_catalog; SET LOCAL TIME ZONE 'UTC'; SET LOCAL DateStyle='ISO, YMD';
 SET LOCAL IntervalStyle=postgres; SET LOCAL bytea_output=hex; SET LOCAL extra_float_digits=3;
 SET LOCAL client_encoding='UTF8'; SET LOCAL standard_conforming_strings=on; SET LOCAL quote_all_identifiers=off;
 SET LOCAL statement_timeout='30s'; SET LOCAL lock_timeout='5s';`;
try{
 await db.exec(`CREATE SCHEMA app; CREATE SCHEMA private;
  CREATE TABLE app.users(id text PRIMARY KEY, active boolean DEFAULT true NOT NULL);
  CREATE TABLE private.synthetic(id integer PRIMARY KEY);`);
 await db.exec(begin);const first=(await db.query(sql)).rows[0].payload;assert.equal(first.status,'ok');
 const expression=(await db.query(`SELECT pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS expression
  FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_class c ON c.oid=d.adrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum=d.adnum
  WHERE n.nspname='app' AND c.relname='users' AND a.attname='active'`)).rows[0].expression;
 const definition=(await db.query(`SELECT pg_catalog.pg_get_constraintdef(x.oid) AS definition
  FROM pg_catalog.pg_constraint x JOIN pg_catalog.pg_class c ON c.oid=x.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='app' AND c.relname='users' AND x.conname='users_pkey'`)).rows[0].definition;
 const user=first.relations.find(r=>r.schema==='app'&&r.name==='users');
 assert.equal(user.columns.find(c=>c.name==='active').default_sha256,sha(expression));
 assert.equal(user.constraints.find(c=>c.name==='users_pkey').definition_sha256,sha(definition));
 assert.deepEqual(first.present_schemas,['app','private']);await db.exec('ROLLBACK');
 await db.exec(`ALTER TABLE app.users ALTER COLUMN active SET DEFAULT false;
  ALTER TABLE app.users ADD COLUMN note text; CREATE SCHEMA collect_sms;`);
 await db.exec(begin);const second=(await db.query(sql)).rows[0].payload;assert.equal(second.status,'ok');await db.exec('ROLLBACK');
 await db.exec('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');
 assert.equal((await db.query(sql)).rows[0].payload.reason,'capture_context');await db.exec('ROLLBACK');
 const value='x'.repeat(17000);await db.exec(`CREATE TABLE app.long_default(id text DEFAULT '${value}');`);
 await db.exec(begin);const refused=(await db.query(sql)).rows[0].payload;
 assert.deepEqual(refused,{format:'collect.supabase.catalogue-capture.v1',status:'refused',reason:'capture_bound'});
 assert.ok(!JSON.stringify(refused).includes(value));await db.exec('ROLLBACK');
 console.log(JSON.stringify({first,second}));
}finally{await db.close()}
"""
        result = subprocess.run(["node", "--input-type=module", "-e", source], input=capture.SQL,
                                text=True, capture_output=True, timeout=30, check=False, env=os.environ.copy())
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        local = build([{"payload": data["first"]}])
        cloud = build([{"payload": data["second"]}], environment="managed_cloud", identity=catalogue.PROJECT)
        result = catalogue.compare(local, cloud)
        diff = next(r for r in result["structural_differences"] if r["schema"] == "app" and r["name"] == "users")
        self.assertEqual(diff["columns_missing_in_local"], ["note"])
        self.assertEqual(diff["columns_changed"][0]["changes"][0]["field"], "default_sha256")
        self.assertNotIn("collect_sms", data["first"]["present_schemas"])
        self.assertIn("collect_sms", data["second"]["present_schemas"])
        self.assertFalse(result["data_copy_authorized"])

    def test_invalid_data_does_not_produce_a_partial_comparator_file(self):
        data = response()
        data[0]["payload"]["counts"]["columns"] = 4
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result_file, classes_file = root / "result.json", root / "classes.json"
            result_file.write_text(json.dumps(data))
            classes_file.write_text(json.dumps(classes()))
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = capture.main(["--response", str(result_file), "--environment", "local_self_hosted", "--identity", "local-app",
                                     "--captured-at", "2026-11-13T10:00:00Z", "--classifications", str(classes_file)])
            self.assertEqual(code, 2)
            failed = json.loads(output.getvalue())
            self.assertEqual(failed["status"], "invalid_input")
            self.assertEqual(failed["error_code"], "capture_count_mismatch")
            self.assertFalse(failed["data_copy_authorized"])
            self.assertNotIn("relations", failed)


if __name__ == "__main__":
    unittest.main()
