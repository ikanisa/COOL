#!/usr/bin/env python3
"""Compile the reviewed Cloudflare SQLite schema into the historical PostgreSQL baseline."""

import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import re
import sqlite3

from sqlite_compatibility import translate_sql, translate_trigger

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MIGRATIONS = HERE.parent / "migrations"
BASELINE_MIGRATION = "20261020134444_collect_curated_platform_baseline.sql"
STORAGE_CORRECTION = "20261020174856_collect_retention_retry_authority.sql"
ADDITIVE_MIGRATIONS = {
    "client-diagnostics.sql": "20261029120000_collect_client_diagnostics.sql",
    "notification-delivery.sql": "20261029130000_collect_notification_delivery.sql",
    "admission-archive.sql": "20261101012309_collect_admission_archive.sql",
    "member-history-pagination.sql": "20261101012310_collect_member_history_pagination.sql",
}
SOURCE_COUNTS = {"table": 97, "index": 34, "trigger": 169, "view": 2}

PREAMBLE = """-- Generated from the exact source bodies in source_manifest.json. Do not hand-edit.
BEGIN;
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS api;
REVOKE ALL ON SCHEMA app,private,api FROM PUBLIC;
SET LOCAL search_path=app,pg_catalog;
"""
# A schema-local default revoke cannot remove the global PUBLIC EXECUTE grant.
FUNCTION_GRANTS = (
    "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private,api FROM PUBLIC;\n"
    "DO $$DECLARE r text;BEGIN FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP "
    "IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE "
    "format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private,api FROM %I',r);END IF;END LOOP;END$$;\n"
)


def matches_file(path, expected, description):
    if not path.is_file() or path.read_bytes() != expected:
        raise SystemExit(f"{description}: {path.relative_to(ROOT)}")


def check_additive_migrations():
    for source_name, migration_name in ADDITIVE_MIGRATIONS.items():
        matches_file(MIGRATIONS / migration_name, (HERE / source_name).read_bytes(), "Additive source drift")

    definition = re.compile(
        r"CREATE (?:OR REPLACE )?FUNCTION private\.assert_storage_delete_authorized\(p_key text\)[\s\S]*?END\$\$;"
    )
    current = definition.findall((HERE / "storage.sql").read_text(encoding="utf-8"))
    migrated = definition.findall((MIGRATIONS / STORAGE_CORRECTION).read_text(encoding="utf-8"))
    if len(current) != 1 or len(migrated) != 1:
        raise SystemExit("Expected one storage authorization definition per source")
    if current[0] != migrated[0].replace("CREATE OR REPLACE FUNCTION ", "CREATE FUNCTION ", 1):
        raise SystemExit("Current Storage definition differs from its additive migration")


def read_source_inventory(db):
    inputs = []
    for path in sorted((ROOT / "deploy/platform-api/migrations").glob("[0-9]*.sql")):
        body = path.read_bytes()
        inputs.append({"path": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(body).hexdigest()})
        db.executescript(body.decode("utf-8"))

    db.row_factory = sqlite3.Row
    objects = db.execute(
        "SELECT type,name,tbl_name,sql FROM sqlite_master "
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY rowid"
    ).fetchall()
    by_type = {name: [item for item in objects if item["type"] == name] for name in SOURCE_COUNTS}
    counts = {name: len(items) for name, items in by_type.items()}
    if counts != SOURCE_COUNTS:
        raise ValueError(f"Source inventory changed: {counts!r}")
    return inputs, objects, by_type, counts


def render_tables(db, tables):
    foreign_keys = []
    # Add foreign keys after all tables to preserve the source schema cycles.
    for table in tables:
        name = table["name"]
        sql = re.sub(r"\bREFERENCES\s+(\w+)\s*\((\w+)\)", "", table["sql"], flags=re.I)
        yield translate_sql(sql) + ";\n"
        for index, sequence, target, column, target_column, update, delete, _ in db.execute(
            'PRAGMA foreign_key_list("' + name + '")'
        ):
            if sequence != 0:
                raise ValueError("Composite FK requires review")
            foreign_keys.append(
                f"ALTER TABLE app.{name} ADD CONSTRAINT fk_{name}_{index} FOREIGN KEY ({column}) "
                f"REFERENCES app.{target}({target_column}) ON UPDATE {update} ON DELETE {delete} "
                "DEFERRABLE INITIALLY IMMEDIATE;\n"
            )
    yield from foreign_keys


def sql_string(value):
    return "'" + value.replace("'", "''") + "'"


def render_static_seeds(db, tables):
    # Only the role/capability definition catalog is seeded.
    for table in tables:
        name = table["name"]
        rows = db.execute('SELECT * FROM "' + name + '"').fetchall()
        if not rows:
            continue
        if name != "admin_account_role_capabilities":
            raise ValueError("Unreviewed source seed table: " + name)
        for role, permission in rows:
            yield (
                "INSERT INTO app.admin_account_role_capabilities(role,permission) "
                f"VALUES({sql_string(role)},{sql_string(permission)});\n"
            )


def render_views_and_indexes(objects):
    for item in objects:
        if item["type"] not in {"index", "view"}:
            continue
        translated = translate_sql(item["sql"])
        if item["type"] == "view":
            translated = re.sub(r"^(CREATE VIEW \w+) AS ", r"\1 WITH (security_invoker=true) AS ", translated)
        yield translated + ";\n"


def render_assisted_sms_view(views):
    # Preserve all source eligibility predicates and add the managed phone proof.
    sql = next(view["sql"] for view in views if view["name"] == "assisted_sms_current_jobs")
    source_proof = "AND (u.member_type!='app' OR EXISTS(SELECT 1 FROM auth_otp_verifications"
    managed_proof = "private.managed_phone_binding(u.id,consent.phone_verification_challenge_id,u.phone)"
    if sql.count(source_proof) != 1:
        raise ValueError("Review changed assisted SMS phone-proof predicate")
    updated = sql.replace(
        source_proof, f"AND (u.member_type!='app' OR {managed_proof} OR EXISTS(SELECT 1 FROM auth_otp_verifications"
    )
    return re.sub(
        r"^CREATE VIEW (\w+) AS ",
        r"CREATE OR REPLACE VIEW app.\1 WITH (security_invoker=true) AS ",
        translate_sql(updated),
    ) + ";\n"


def render_baseline(db, objects, by_type):
    def read_source(name):
        return (HERE / name).read_bytes().decode("utf-8")

    pieces = [PREAMBLE, read_source("compatibility.sql")]
    pieces.extend(render_tables(db, by_type["table"]))
    pieces.extend(render_static_seeds(db, by_type["table"]))
    pieces.extend(render_views_and_indexes(objects))
    pieces.append("CREATE UNIQUE INDEX admin_users_email_casefold ON app.admin_users(lower(email));\n")
    pieces.extend(translate_trigger(trigger["sql"]) for trigger in by_type["trigger"])
    # The baseline is bound to the original Storage source. Corrections are additive.
    pieces.extend((read_source("baseline-inputs/storage.sql"), read_source("authority.sql")))
    pieces.append(render_assisted_sms_view(by_type["view"]))
    pieces.extend((read_source("financial.sql"), read_source("managed-retention.sql"), FUNCTION_GRANTS, "COMMIT;\n"))
    return "".join(pieces).encode("utf-8")


def compile_baseline():
    with closing(sqlite3.connect(":memory:")) as db:
        inputs, objects, by_type, counts = read_source_inventory(db)
        output = render_baseline(db, objects, by_type)
    manifest = {
        "format": "collect.supabase.baseline.v1",
        "source_counts": counts,
        "source_migrations": inputs,
        "baseline_sha256": hashlib.sha256(output).hexdigest(),
        "source_table_names": [item["name"] for item in by_type["table"]],
        "source_trigger_names": [item["name"] for item in by_type["trigger"]],
        "translation": "shape-preserving PostgreSQL17, explicit compatibility functions and curated authority/financial additions",
        "semantic_equivalence_accepted": False,
    }
    return output, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify generated source bytes without writing")
    args = parser.parse_args()

    check_additive_migrations()
    output, manifest = compile_baseline()
    matches_file(MIGRATIONS / BASELINE_MIGRATION, output, "Immutable baseline differs")
    artifacts = {"baseline.sql": output, "source_manifest.json": (json.dumps(manifest, indent=2) + "\n").encode("utf-8")}
    for name, expected in artifacts.items():
        path = HERE / name
        if args.check:
            matches_file(path, expected, "Generated source drift")
        else:
            path.write_bytes(expected)

    print(json.dumps({
        "checked" if args.check else "generated": str(HERE / "baseline.sql"),
        "sha256": manifest["baseline_sha256"],
        **manifest["source_counts"],
    }))


if __name__ == "__main__":
    main()
