#!/usr/bin/env python3
"""Compare count-only local and managed Supabase inventories offline.

This program does not connect to Postgres, run SQL, copy data, or approve a
cutover. `--sql` prints the fixed, read-only inventory query to run separately
under an authorized account on each database. Wrap each result as:

{"format":"collect.supabase.aggregate-inventory.v1",
 "environment":"local_self_hosted"|"managed_cloud",
 "identity":"local-app"|"rrlduytparvsjfmegalh",
 "captured_at":"2026-11-13T00:00:00Z",
 "relations":[{"schema":"app","name":"users","row_count":"1"}, ...]}

An operator must independently verify each database's identity and the
completeness and consistency of each capture. The query returns relation names
and counts only; it does not retrieve identifiers, rows, credentials or SQL
statements. Independently captured databases can change between captures.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import sys

FORMAT = "collect.supabase.aggregate-inventory.v1"
PROJECT = "rrlduytparvsjfmegalh"
SCHEMAS = {"app", "private", "collect_sms", "auth", "storage", "supabase_migrations"}
REQUIRED_COMMON = {
    ("app", "users"), ("app", "collections"), ("app", "memberships"),
    ("app", "payments"), ("app", "ledger_entries"), ("app", "momo_transactions"),
    ("auth", "users"), ("auth", "sessions"), ("storage", "objects"),
    ("storage", "buckets"), ("supabase_migrations", "schema_migrations"),
}
REQUIRED_LOCAL = {("supabase_migrations", "collect_installation_steps")}
MAX_BYTES = 4 * 1024 * 1024
MAX_RELATIONS = 10000

# The only dynamic SQL in this displayed query is a count(*) whose identifiers
# come from PostgreSQL's own catalog and are escaped with format(%I).
QUERY = """WITH selected AS (
  SELECT n.nspname AS schema, c.relname AS name
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition
    AND n.nspname IN ('app', 'private', 'collect_sms', 'auth', 'storage', 'supabase_migrations')
)
SELECT schema, name,
  (pg_catalog.xpath('/table/row/total/text()',
    pg_catalog.query_to_xml(pg_catalog.format('SELECT count(*) AS total FROM %I.%I', schema, name),
                            true, false, '')))[1]::text AS row_count
FROM selected ORDER BY schema, name;"""


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate JSON key")
        value[key] = item
    return value


def load_snapshot(path):
    path = Path(path).absolute()
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError("invalid inventory file")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)


def validate(snapshot, *, environment, identity):
    if (not isinstance(snapshot, dict)
            or set(snapshot) != {"format", "environment", "identity", "captured_at", "relations"}
            or snapshot["format"] != FORMAT or snapshot["environment"] != environment
            or snapshot["identity"] != identity or not isinstance(snapshot["captured_at"], str)
            or not isinstance(snapshot["relations"], list)
            or not 0 < len(snapshot["relations"]) <= MAX_RELATIONS):
        raise ValueError("invalid inventory envelope")
    try:
        captured = datetime.fromisoformat(snapshot["captured_at"].replace("Z", "+00:00"))
        if captured.tzinfo is None:
            raise ValueError("timezone required")
    except ValueError as exc:
        raise ValueError("invalid capture time") from exc
    relations = {}
    for row in snapshot["relations"]:
        if not isinstance(row, dict) or set(row) != {"schema", "name", "row_count"}:
            raise ValueError("invalid relation record")
        schema, name, count = row["schema"], row["name"], row["row_count"]
        if (not isinstance(schema, str) or schema not in SCHEMAS
                or not isinstance(name, str) or not re.fullmatch(r"[a-z0-9_]+", name)
                or not isinstance(count, str) or not re.fullmatch(r"(?:0|[1-9][0-9]{0,18})", count)
                or (schema, name) in relations):
            raise ValueError("invalid or duplicate relation record")
        relations[(schema, name)] = int(count)
    required = REQUIRED_COMMON | (REQUIRED_LOCAL if environment == "local_self_hosted" else set())
    if not required.issubset(relations) or not any(schema == "private" for schema, _ in relations):
        raise ValueError("required inventory relations missing")
    return relations


def compare(local_snapshot, cloud_snapshot):
    local = validate(local_snapshot, environment="local_self_hosted", identity="local-app")
    cloud = validate(cloud_snapshot, environment="managed_cloud", identity=PROJECT)

    def item(key, count):
        return {"schema": key[0], "name": key[1], "row_count": str(count)}

    shared = set(local) & set(cloud)
    differences = [{"schema": key[0], "name": key[1], "local_row_count": str(local[key]),
                    "cloud_row_count": str(cloud[key])}
                   for key in sorted(shared) if local[key] != cloud[key]]
    local_only = [item(key, local[key]) for key in sorted(set(local) - set(cloud))]
    cloud_only = [item(key, cloud[key]) for key in sorted(set(cloud) - set(local))]
    return {
        "format": "collect.supabase.aggregate-reconciliation.v1",
        "status": "inventory_only",
        "local_captured_at": local_snapshot["captured_at"],
        "cloud_captured_at": cloud_snapshot["captured_at"],
        "local_relation_count": len(local),
        "cloud_relation_count": len(cloud),
        "equal_count_relations": sum(1 for key in shared if local[key] == cloud[key]),
        "different_count_relations": differences,
        "local_only_relations": local_only,
        "cloud_only_relations": cloud_only,
        "installation_journal_local_count": str(local[("supabase_migrations", "collect_installation_steps")]),
        "installation_journal_cloud_present": ("supabase_migrations", "collect_installation_steps") in cloud,
        "provider_migration_history_is_data_transfer_authority": False,
        "database_identity_independently_verified": False,
        "same_rows_or_principals_verified": False,
        "storage_bytes_verified": False,
        "single_writer_verified": False,
        "data_copy_authorized": False,
        "cutover_authorized": False,
        "scope": "Count-only snapshots under each querying role; equal counts do not establish equal data.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sql", action="store_true", help="Print the fixed aggregate-only SELECT")
    parser.add_argument("local", nargs="?")
    parser.add_argument("cloud", nargs="?")
    args = parser.parse_args()
    if args.sql and args.local is None and args.cloud is None:
        print(QUERY)
        return 0
    if args.sql or not args.local or not args.cloud:
        parser.error("provide --sql or local and cloud inventory paths")
    try:
        print(json.dumps(compare(load_snapshot(args.local), load_snapshot(args.cloud)), indent=2))
        return 0
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        print(json.dumps({"status": "invalid_input", "data_copy_authorized": False,
                          "cutover_authorized": False}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
