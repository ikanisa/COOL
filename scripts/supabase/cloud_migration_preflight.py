#!/usr/bin/env python3
"""Compare supplied managed-project history metadata to the local migration lock.

This program never connects to a database, runs SQL, or changes a migration.
Supply a JSON envelope containing format, project_ref and records. Each record
has version, name, statement_count and statement_sha256. The hash must describe
the exact UTF-8 bytes of the one stored statement; zero or multiple stored
statements have a null hash and are deliberately treated as unverified.

For the selected project, an operator can capture only the necessary metadata
using a provider's read-only SQL interface:

SELECT version::text, name::text, COALESCE(cardinality(statements), 0)
  AS statement_count,
  CASE WHEN cardinality(statements) = 1
    THEN encode(sha256(convert_to(statements[1], 'UTF8')), 'hex')
    ELSE NULL END AS statement_sha256
FROM supabase_migrations.schema_migrations ORDER BY version;

Wrap the rows as {"format":"collect.supabase.cloud-migration-history.v1",
"project_ref":"rrlduytparvsjfmegalh","records":[...]}. The declared project
reference is not provider authentication; verify project identity separately.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

PROJECT = "rrlduytparvsjfmegalh"
INPUT_FORMAT = "collect.supabase.cloud-migration-history.v1"
LOCK_FORMAT = "collect.selfhost.migrations.v1"
FILE_RE = re.compile(r"^([0-9]{14})_([a-z0-9_]+)\.sql$")
HASH_RE = re.compile(r"^[a-f0-9]{64}$")
LOCAL_REVIEW = {
    "20261110181002_collect_local_stopped_admission.sql":
        "Records a stopped local VM executor; managed-cloud applicability requires separate review.",
}
MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_MIGRATIONS = 10000


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate JSON key")
        value[key] = item
    return value


def load_json(path):
    path = Path(path).absolute()
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_INPUT_BYTES:
        raise ValueError("invalid metadata or lock file")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)


def _exact_keys(value, keys):
    return isinstance(value, dict) and set(value) == set(keys)


def validate_cloud(value):
    if (not _exact_keys(value, ("format", "project_ref", "records"))
            or value["format"] != INPUT_FORMAT or value["project_ref"] != PROJECT
            or not isinstance(value["records"], list) or len(value["records"]) > MAX_MIGRATIONS):
        raise ValueError("invalid cloud metadata envelope")
    records = {}
    for row in value["records"]:
        if not _exact_keys(row, ("version", "name", "statement_count", "statement_sha256")):
            raise ValueError("invalid cloud migration fields")
        version, name, count, digest = (row["version"], row["name"],
                                        row["statement_count"], row["statement_sha256"])
        if (not isinstance(version, str) or not re.fullmatch(r"[0-9]{14}", version)
                or not isinstance(name, str) or not re.fullmatch(r"[a-z0-9_]+", name)
                or type(count) is not int or not 0 <= count <= 100000
                or (count == 1 and (not isinstance(digest, str) or not HASH_RE.fullmatch(digest)))
                or (count != 1 and digest is not None) or version in records):
            raise ValueError("invalid or duplicate cloud migration")
        records[version] = row
    return records


def local_inventory(root):
    root = Path(root).absolute()
    if root.resolve() != root:
        raise ValueError("source root must be physical")
    lock = load_json(root / "supabase/managed-migration-history/source-migrations.lock.json")
    if (not _exact_keys(lock, ("format", "original_count", "migrations"))
            or lock["format"] != LOCK_FORMAT
            or type(lock["original_count"]) is not int
            or not isinstance(lock["migrations"], list)
            or not 1 <= lock["original_count"] <= len(lock["migrations"]) <= MAX_MIGRATIONS):
        raise ValueError("invalid local migration lock")
    git_root = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
        stderr=subprocess.DEVNULL, text=True,
    ).strip()
    if Path(git_root).resolve() != root:
        raise ValueError("source root is not the Git root")
    tracked_raw = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "--cached", "-z", "--", "supabase/migrations"],
        stderr=subprocess.DEVNULL,
    )
    tracked = set(tracked_raw.decode("utf-8").split("\0"))
    directory = root / "supabase/migrations"
    if directory.is_symlink() or not directory.is_dir() or directory.resolve() != directory:
        raise ValueError("invalid migration directory")
    local = {}
    previous = ""
    for row in lock["migrations"]:
        if (not _exact_keys(row, ("name", "sha256", "transaction"))
                or not isinstance(row["name"], str)
                or not isinstance(row["sha256"], str)
                or not HASH_RE.fullmatch(row["sha256"])
                or row["transaction"] not in ("wrap", "outer")):
            raise ValueError("invalid local migration lock record")
        match = FILE_RE.fullmatch(row["name"])
        if not match or match.group(1) <= previous:
            raise ValueError("unsorted or duplicate local migration version")
        version, name = match.groups()
        previous = version
        path = directory / row["name"]
        item = {"version": version, "name": name, "filename": row["name"],
                "locked_sha256": row["sha256"],
                "tracked": "supabase/migrations/" + row["name"] in tracked,
                "local_review": LOCAL_REVIEW.get(row["name"])}
        if not path.exists() and not path.is_symlink():
            item["local_state"] = "missing"
        else:
            if (path.is_symlink() or not path.is_file() or path.resolve() != path
                    or path.stat().st_size > 16 * 1024 * 1024):
                raise ValueError("nonphysical local migration")
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            item["local_state"] = "match" if actual == row["sha256"] else "changed"
            item["actual_sha256"] = actual
        local[version] = item
    names = {row["filename"] for row in local.values()}
    unexpected = sorted(p.name for p in directory.iterdir()
                        if p.name.endswith(".sql") and p.name not in names)
    unexpected_untracked = [name for name in unexpected
                            if "supabase/migrations/" + name not in tracked]
    return local, unexpected, unexpected_untracked


def compare(root, cloud_value):
    cloud = validate_cloud(cloud_value)
    local, unexpected, unexpected_untracked = local_inventory(root)
    missing, extra, changed_name, changed_statement, unverified = [], [], [], [], []
    for version, item in local.items():
        remote = cloud.get(version)
        if remote is None:
            missing.append(item["filename"])
        elif remote["name"] != item["name"]:
            changed_name.append({"version": version, "local_name": item["name"],
                                 "cloud_name": remote["name"]})
        elif remote["statement_count"] != 1:
            unverified.append({"version": version, "statement_count": remote["statement_count"]})
        elif remote["statement_sha256"] != item["locked_sha256"]:
            changed_statement.append({"version": version, "local_sha256": item["locked_sha256"],
                                      "cloud_statement_sha256": remote["statement_sha256"]})
    for version, item in cloud.items():
        if version not in local:
            extra.append({"version": version, "name": item["name"]})
    findings = {
        "missing_from_cloud": missing,
        "extra_in_cloud": sorted(extra, key=lambda row: row["version"]),
        "name_mismatches": changed_name,
        "statement_hash_mismatches": changed_statement,
        "statement_hash_unverified": unverified,
        "untracked_local": sorted([r["filename"] for r in local.values() if not r["tracked"]]
                                  + unexpected_untracked),
        "changed_local": [r["filename"] for r in local.values() if r["local_state"] == "changed"],
        "missing_local": [r["filename"] for r in local.values() if r["local_state"] == "missing"],
        "unexpected_local": unexpected,
        "local_only_review_required": [
            {"filename": r["filename"], "reason": r["local_review"]}
            for r in local.values() if r["local_review"]
        ],
    }
    if (local, unexpected, unexpected_untracked) != local_inventory(root):
        raise ValueError("local migration inventory changed during comparison")
    return {
        "format": "collect.supabase.cloud-migration-preflight.v1",
        "project_ref": PROJECT,
        "local_locked_count": len(local),
        "cloud_record_count": len(cloud),
        "status": "review_required" if any(findings.values()) else "matching_history_metadata_only",
        "findings": findings,
        "read_only": True,
        "cloud_identity_independently_verified": False,
        "local_review_independently_verified": False,
        "local_only_review_list_exhaustive": False,
        "schema_parity_verified": False,
        "deployment_accepted": False,
        "routing_changed": False,
        "scope": "Point-in-time supplied history metadata and local lock only; matching history does not prove schema or release readiness.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metadata", help="Explicit provider-history metadata JSON file")
    args = parser.parse_args()
    try:
        result = compare(Path(__file__).resolve().parents[2], load_json(args.metadata))
        print(json.dumps(result, indent=2))
        return 0 if result["status"] == "matching_history_metadata_only" else 1
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError, json.JSONDecodeError):
        print(json.dumps({"status": "invalid_input", "read_only": True,
                          "deployment_accepted": False, "routing_changed": False}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
