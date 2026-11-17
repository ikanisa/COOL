#!/usr/bin/env python3
"""Compare two explicitly supplied, normalized PostgreSQL catalogues offline.

Usage: python3 scripts/supabase/catalogue_reconciliation.py LOCAL.json CLOUD.json

Input contract (JSON; arrays may be in any order):

{
  "format": "collect.supabase.catalogue-metadata.v1",
  "environment": "local_self_hosted",
  "identity": "local-app",
  "captured_at": "2026-11-13T10:00:00Z",
  "covered_schemas": ["app", "private", "collect_sms"],
  "classifications": [
    {"schema": "app", "name": "users", "classification": "business"}
  ],
  "relations": [{
    "schema": "app", "name": "users", "kind": "r", "is_partition": false,
    "columns": [{"name": "id", "position": "1", "type_schema": "pg_catalog",
      "type_name": "text", "type_kind": "b", "type_modifier": "-1",
      "not_null": true, "identity": "", "generated": "", "collation": null,
      "default_sha256": null}],
    "constraints": [{"name": "users_pkey", "kind": "p",
      "definition_sha256": "<64 lowercase hex characters>", "deferrable": false,
      "initially_deferred": false, "validated": true}]
  }]
}

The cloud input has environment "managed_cloud" and identity
"rrlduytparvsjfmegalh". A nullable collation is either null or an exact
{"schema": "pg_catalog", "name": "default"} object. The allowed caller-supplied
classifications are business, identity_authority, operational_state, reference,
archive_only and unclassified. They describe a review worklist only; they do not
approve or prescribe a transfer. List a relation even when it is expected but
not observed. An observed relation not identically classified in both inputs is
reported as unclassified. Unknown classification values are rejected.

This is a NEW normalized input contract, not the archive's native JSON format
and not a catalogue exporter. It follows the pg_class, pg_attribute, pg_type,
pg_attrdef and pg_constraint descriptors in current-archive/sql.mjs and
 data_promote.mjs. External, independently authorized capture must include all
ordinary/partitioned tables, including child partitions, in the three schemas;
position and typmod are canonical decimal text. Relation, column, constraint,
type and schema names must be lowercase ASCII PostgreSQL identifiers of at most
63 characters. Collation names are case-sensitive printable UTF-8 labels of at
most 63 bytes and are never used as SQL. Constraint kind must be a
PostgreSQL 17 pg_constraint kind: c, f, p, u, x or t. Each file is at most
8 MiB, each snapshot has at most 10,000 relations/classifications and 40,000
column/constraint descriptors, and report output is limited to 16 MiB.
Hash the exact UTF-8 result of
pg_catalog.pg_get_expr for a non-null default/generated expression and use null
only when the expression is absent. Hash the exact UTF-8 result of
pg_catalog.pg_get_constraintdef for every constraint, retaining the pg_constraint
flags separately. Use compatible PostgreSQL versions and identical, documented
search_path/deparser settings, or hashes may differ for equivalent definitions.
Never replace an unavailable expression or hash with null.

The utility reads only the two named local files. It cannot establish their
provenance, completeness, source/target identity, capture consistency, role
visibility or classification approval. It does not compare data, type definitions,
partition bounds, indexes, triggers, policies, functions, roles, grants, sequences,
provider schemas, Storage bodies, Auth identities or business invariants. Even
identical output descriptors prove neither schema parity nor transfer readiness.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import stat
import sys

FORMAT = "collect.supabase.catalogue-metadata.v1"
RESULT_FORMAT = "collect.supabase.catalogue-reconciliation.v1"
PROJECT = "rrlduytparvsjfmegalh"
SCHEMAS = frozenset(("app", "private", "collect_sms"))
CLASSIFICATIONS = frozenset(("business", "identity_authority", "operational_state",
                             "reference", "archive_only", "unclassified"))
TYPE_KINDS = frozenset(("b", "c", "d", "e", "p", "r", "m"))
CONSTRAINT_KINDS = frozenset(("c", "f", "p", "u", "x", "t"))
NAME = re.compile(r"[a-z_][a-z0-9_]{0,62}\Z")
HASH = re.compile(r"[a-f0-9]{64}\Z")
UTC = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?Z\Z")
POSITIVE = re.compile(r"[1-9][0-9]{0,4}\Z")
TYPMOD = re.compile(r"(?:-1|0|[1-9][0-9]{0,9})\Z")
MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_OUTPUT_BYTES = 16 * 1024 * 1024
MAX_RELATIONS = 10000
MAX_CLASSIFICATIONS = 10000
MAX_COLUMNS_PER_RELATION = 1600
MAX_CONSTRAINTS_PER_RELATION = 10000
MAX_DESCRIPTORS = 40000


class CatalogueInputError(ValueError):
    """A fixed, non-sensitive input failure code."""


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise CatalogueInputError("duplicate_json_key")
        value[key] = item
    return value


def _reject_constant(_value):
    raise CatalogueInputError("invalid_json_number")


def load_metadata(path):
    """Read a bounded regular file without following a final-component symlink."""
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_NONBLOCK"):
        raise CatalogueInputError("safe_file_inspection_unavailable")
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    fd = os.open(Path(path), flags)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_INPUT_BYTES:
            raise CatalogueInputError("invalid_metadata_file")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read(MAX_INPUT_BYTES + 1)
        after = os.fstat(fd)
        if (len(raw) > MAX_INPUT_BYTES or len(raw) != before.st_size
                or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
                    before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size,
                                             after.st_mtime_ns, after.st_ctime_ns)):
            raise CatalogueInputError("metadata_changed_or_oversized")
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_object,
                          parse_constant=_reject_constant)
    finally:
        os.close(fd)


def _exact(value, keys):
    return isinstance(value, dict) and set(value) == set(keys)


def _name(value):
    return isinstance(value, str) and NAME.fullmatch(value) is not None


def _digest(value):
    return isinstance(value, str) and HASH.fullmatch(value) is not None


def _key(row):
    if (not _name(row.get("name")) or not isinstance(row.get("schema"), str)
            or row.get("schema") not in SCHEMAS):
        raise CatalogueInputError("invalid_relation_name")
    return row["schema"], row["name"]


def _collation_name(value):
    # PostgreSQL collation names include case-sensitive C/POSIX and ICU
    # identifiers such as en-US-x-icu. They are data, never SQL identifiers.
    if not isinstance(value, str) or not value or not value.isprintable():
        return False
    try:
        return len(value.encode("utf-8", errors="strict")) <= 63
    except UnicodeError:
        return False


def _collation(value):
    return (value is None or _exact(value, ("schema", "name"))
            and _name(value["schema"]) and _collation_name(value["name"]))


def _column(value):
    keys = ("name", "position", "type_schema", "type_name", "type_kind", "type_modifier",
            "not_null", "identity", "generated", "collation", "default_sha256")
    if not _exact(value, keys):
        raise CatalogueInputError("invalid_column_fields")
    position, modifier = value["position"], value["type_modifier"]
    if (not _name(value["name"]) or not _name(value["type_schema"])
            or not _name(value["type_name"]) or not isinstance(value["type_kind"], str)
            or value["type_kind"] not in TYPE_KINDS
            or not isinstance(position, str) or POSITIVE.fullmatch(position) is None
            or int(position) > 32767 or not isinstance(modifier, str)
            or TYPMOD.fullmatch(modifier) is None or int(modifier) > 2147483647
            or type(value["not_null"]) is not bool or value["identity"] not in ("", "a", "d")
            or value["generated"] not in ("", "s") or not _collation(value["collation"])
            or (value["default_sha256"] is not None and not _digest(value["default_sha256"]))):
        raise CatalogueInputError("invalid_column_descriptor")
    return value


def _constraint(value):
    keys = ("name", "kind", "definition_sha256", "deferrable", "initially_deferred", "validated")
    if (not _exact(value, keys) or not _name(value["name"])
            or not isinstance(value["kind"], str) or value["kind"] not in CONSTRAINT_KINDS
            or not _digest(value["definition_sha256"])
            or any(type(value[key]) is not bool for key in ("deferrable", "initially_deferred", "validated"))
            or (value["initially_deferred"] and not value["deferrable"])):
        raise CatalogueInputError("invalid_constraint_descriptor")
    return value


def validate(snapshot, *, environment, identity):
    keys = ("format", "environment", "identity", "captured_at", "covered_schemas",
            "classifications", "relations")
    if (not _exact(snapshot, keys) or snapshot["format"] != FORMAT
            or snapshot["environment"] != environment or snapshot["identity"] != identity
            or not isinstance(snapshot["captured_at"], str)
            or UTC.fullmatch(snapshot["captured_at"]) is None):
        raise CatalogueInputError("invalid_metadata_envelope")
    try:
        datetime.fromisoformat(snapshot["captured_at"].replace("Z", "+00:00"))
    except ValueError as exc:
        raise CatalogueInputError("invalid_capture_time") from exc
    covered = snapshot["covered_schemas"]
    if (not isinstance(covered, list) or len(covered) != len(SCHEMAS)
            or any(not isinstance(s, str) for s in covered) or set(covered) != SCHEMAS):
        raise CatalogueInputError("invalid_covered_schemas")
    classifications = snapshot["classifications"]
    if not isinstance(classifications, list) or len(classifications) > MAX_CLASSIFICATIONS:
        raise CatalogueInputError("invalid_classification_list")
    classified = {}
    for item in classifications:
        if not _exact(item, ("schema", "name", "classification")):
            raise CatalogueInputError("invalid_classification_fields")
        key = _key(item)
        if key in classified:
            raise CatalogueInputError("duplicate_classification")
        if not isinstance(item["classification"], str) or item["classification"] not in CLASSIFICATIONS:
            raise CatalogueInputError("invalid_classification")
        classified[key] = item["classification"]
    records = snapshot["relations"]
    if not isinstance(records, list) or not 0 < len(records) <= MAX_RELATIONS:
        raise CatalogueInputError("invalid_relation_list")
    relations = {}
    descriptors = 0
    for item in records:
        if not _exact(item, ("schema", "name", "kind", "is_partition", "columns", "constraints")):
            raise CatalogueInputError("invalid_relation_fields")
        key = _key(item)
        if key in relations:
            raise CatalogueInputError("duplicate_relation")
        if (item["kind"] not in ("r", "p")
                or type(item["is_partition"]) is not bool
                or not isinstance(item["columns"], list)
                or len(item["columns"]) > MAX_COLUMNS_PER_RELATION
                or not isinstance(item["constraints"], list)
                or len(item["constraints"]) > MAX_CONSTRAINTS_PER_RELATION):
            raise CatalogueInputError("invalid_relation")
        descriptors += len(item["columns"]) + len(item["constraints"])
        if descriptors > MAX_DESCRIPTORS:
            raise CatalogueInputError("catalogue_descriptor_bound_exceeded")
        columns, positions, constraints = {}, set(), {}
        for raw in item["columns"]:
            column = _column(raw)
            if column["name"] in columns or column["position"] in positions:
                raise CatalogueInputError("duplicate_column_name_or_position")
            columns[column["name"]] = column
            positions.add(column["position"])
        for raw in item["constraints"]:
            constraint = _constraint(raw)
            if constraint["name"] in constraints:
                raise CatalogueInputError("duplicate_constraint_name")
            constraints[constraint["name"]] = constraint
        relations[key] = {"kind": item["kind"], "is_partition": item["is_partition"],
                          "columns": columns, "constraints": constraints}
    return {"relations": relations, "classifications": classified}


def _relation(key):
    return {"schema": key[0], "name": key[1]}


def _changed_fields(local, cloud, fields):
    return [{"field": field, "local": local[field], "cloud": cloud[field]}
            for field in fields if local[field] != cloud[field]]


def compare(local_snapshot, cloud_snapshot):
    local = validate(local_snapshot, environment="local_self_hosted", identity="local-app")
    cloud = validate(cloud_snapshot, environment="managed_cloud", identity=PROJECT)
    lr, cr = local["relations"], cloud["relations"]
    lc, cc = local["classifications"], cloud["classifications"]
    local_keys, cloud_keys = set(lr), set(cr)
    declared = set(lc) | set(cc)
    classification_mismatches = [dict(_relation(key), local=lc.get(key), cloud=cc.get(key))
                                 for key in sorted(declared) if lc.get(key) != cc.get(key)]
    agreed = {key for key in set(lc) & set(cc)
              if lc[key] == cc[key] and lc[key] != "unclassified"}
    unclassified = sorted((local_keys | cloud_keys | declared) - agreed)
    column_fields = ("position", "type_schema", "type_name", "type_kind", "type_modifier",
                     "not_null", "identity", "generated", "collation", "default_sha256")
    constraint_fields = ("kind", "definition_sha256", "deferrable", "initially_deferred", "validated")
    differences = []
    for key in sorted(local_keys & cloud_keys):
        a, b = lr[key], cr[key]
        ac, bc = a["columns"], b["columns"]
        ax, bx = a["constraints"], b["constraints"]
        changed_columns = [{"name": name, "changes": changes}
                           for name in sorted(set(ac) & set(bc))
                           if (changes := _changed_fields(ac[name], bc[name], column_fields))]
        changed_constraints = [{"name": name, "changes": changes}
                               for name in sorted(set(ax) & set(bx))
                               if (changes := _changed_fields(ax[name], bx[name], constraint_fields))]
        record = dict(_relation(key),
                      relation_changes=_changed_fields(a, b, ("kind", "is_partition")),
                      columns_missing_in_cloud=sorted(set(ac) - set(bc)),
                      columns_missing_in_local=sorted(set(bc) - set(ac)),
                      columns_changed=changed_columns,
                      constraints_missing_in_cloud=sorted(set(ax) - set(bx)),
                      constraints_missing_in_local=sorted(set(bx) - set(ax)),
                      constraints_changed=changed_constraints)
        if any(record[name] for name in ("relation_changes", "columns_missing_in_cloud", "columns_missing_in_local",
                                        "columns_changed", "constraints_missing_in_cloud", "constraints_missing_in_local",
                                        "constraints_changed")):
            differences.append(record)
    return {
        "format": RESULT_FORMAT,
        "status": "review_required",
        "local_captured_at": local_snapshot["captured_at"],
        "cloud_captured_at": cloud_snapshot["captured_at"],
        "local_relation_count": len(lr),
        "cloud_relation_count": len(cr),
        "local_only_relations": [_relation(key) for key in sorted(local_keys - cloud_keys)],
        "cloud_only_relations": [_relation(key) for key in sorted(cloud_keys - local_keys)],
        "declared_missing_in_local": [_relation(key) for key in sorted(declared - local_keys)],
        "declared_missing_in_cloud": [_relation(key) for key in sorted(declared - cloud_keys)],
        "classification_mismatches": classification_mismatches,
        "unclassified_relations": [_relation(key) for key in unclassified],
        "structural_differences": differences,
        "classification_independently_verified": False,
        "catalogue_completeness_independently_verified": False,
        "database_identity_independently_verified": False,
        "schema_parity_verified": False,
        "data_equality_verified": False,
        "data_copy_authorized": False,
        "cutover_authorized": False,
        "not_compared": ["rows", "type_definitions", "partition_bounds", "indexes", "triggers",
                         "policies", "functions", "roles_and_grants", "sequences", "provider_schemas",
                         "storage_objects", "auth_identities", "business_invariants"],
        "scope": "Supplied table, column and constraint descriptors only; no database connection or SQL execution.",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("local", help="Explicit local metadata JSON file")
    parser.add_argument("cloud", help="Explicit managed metadata JSON file")
    args = parser.parse_args(argv)
    try:
        result = compare(load_metadata(args.local), load_metadata(args.cloud))
        encoded = json.dumps(result, indent=2, ensure_ascii=True)
        if len(encoded.encode("utf-8")) > MAX_OUTPUT_BYTES:
            raise CatalogueInputError("report_bound_exceeded")
        print(encoded)
        return 0
    except (OSError, UnicodeError, ValueError, RecursionError) as exc:
        code = str(exc) if isinstance(exc, CatalogueInputError) else "malformed_or_unreadable_input"
        print(json.dumps({"status": "invalid_input", "error_code": code, "data_equality_verified": False,
                          "data_copy_authorized": False, "cutover_authorized": False}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
