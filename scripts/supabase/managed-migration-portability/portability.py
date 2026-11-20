#!/usr/bin/env python3
"""Read-only inventory of the locked Collect migration chain.

This is a lexical inspection, not a SQL parser or an authorization to deploy.
It neither connects to PostgreSQL nor executes migrations. See README.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

ROOT = Path(__file__).resolve().parents[3]
NAME = re.compile(r"^[0-9]{14}_[a-z0-9_]+\.sql$")
SHA = re.compile(r"^[a-f0-9]{64}$")
SIGNATURE = r"(?:app|private|collect_sms)\.[a-z_][a-z0-9_]*\([a-z0-9_.,\[\] ]*\)"
TUPLE = re.compile(r"\(\s*'(?P<sig>" + SIGNATURE + r")'\s*,\s*'(?P<sha>[a-f0-9]{64})'", re.I)
CREATED = re.compile(r"\bCREATE\s+(?:OR\s+REPLACE\s+)?(?P<kind>FUNCTION|TABLE|VIEW|SCHEMA)\s+(?:IF\s+NOT\s+EXISTS\s+)?(?P<name>(?:app|private|collect_sms)\.[a-z_][a-z0-9_]*|(?:app|private|collect_sms))\b", re.I)
LOOKUP = re.compile(r"\bto_reg(?P<kind>procedure|class|namespace)\s*\(\s*'(?P<name>[^']+)'\s*\)\s*(?P<condition>IS\s+(?:NOT\s+)?NULL)?", re.I)
DIRECT = re.compile(r"'(?P<sig>" + SIGNATURE + r")'\s*::\s*regprocedure\s*\)\s*IS\s+DISTINCT\s+FROM\s*'(?P<sha>[a-f0-9]{64})'", re.I)
INLINE = re.compile(
    r"(?:to_regprocedure\s*\(\s*'(?P<sig1>" + SIGNATURE + r")'\s*\)|'(?P<sig2>" + SIGNATURE + r")'\s*::\s*regprocedure)"
    r"(?:(?!;|::\s*regprocedure|to_regprocedure\s*\().){0,1200}?"
    r"encode\s*\(\s*sha256\s*\(\s*convert_to\s*\(\s*(?:[a-z_][a-z0-9_]*\.)?prosrc\s*,\s*'UTF8'\s*\)\s*\)\s*,\s*'hex'\s*\)\s*=\s*'(?P<sha>[a-f0-9]{64})'",
    re.I | re.S,
)

MAX_FILES = 1000
MAX_FILE_BYTES = 12 * 1024 * 1024
MAX_TOTAL_BYTES = 128 * 1024 * 1024


class InventoryError(ValueError):
    """Inputs cannot be reliably inventoried."""


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InventoryError("duplicate_json_key")
        result[key] = value
    return result


def _read_regular(path: Path) -> bytes:
    """Read a bounded physical file, refusing symlinks and concurrent changes."""
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_FILE_BYTES:
        raise InventoryError("nonregular_or_oversized_input")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        identity = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns)
        if identity(before) != identity(opened):
            raise InventoryError("input_changed_during_read")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(MAX_FILE_BYTES + 1)
        if len(data) > MAX_FILE_BYTES or identity(opened) != identity(os.fstat(fd)):
            raise InventoryError("input_changed_during_read")
    finally:
        os.close(fd)
    if identity(before) != identity(path.lstat()):
        raise InventoryError("input_changed_during_read")
    return data


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _line(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _names(directory: Path) -> list[str]:
    names = sorted(item.name for item in directory.iterdir()
                   if item.name.endswith(".sql") and not item.name.startswith("._"))
    if len(names) > MAX_FILES or any(not NAME.fullmatch(name) for name in names):
        raise InventoryError("unexpected_migration_filename")
    return names


def snapshot(root: Path) -> tuple[dict, list[tuple[dict, str]], str]:
    root = root.resolve(strict=True)
    directory = root / "supabase" / "migrations"
    lock_path = root / "deploy" / "self-hosted" / "migrations.lock.json"
    for path in (directory, lock_path.parent):
        if path.resolve(strict=True) != path or not path.is_dir():
            raise InventoryError("nonphysical_input_directory")
    lock_bytes = _read_regular(lock_path)
    lock = json.loads(lock_bytes, object_pairs_hook=_unique)
    if not isinstance(lock, dict) or set(lock) != {"format", "original_count", "migrations"} \
            or lock["format"] != "collect.selfhost.migrations.v1" \
            or type(lock["original_count"]) is not int or lock["original_count"] != 16 \
            or not isinstance(lock["migrations"], list):
        raise InventoryError("invalid_lock")
    items = lock["migrations"]
    if not 16 <= len(items) <= MAX_FILES:
        raise InventoryError("invalid_migration_count")
    for item in items:
        if not isinstance(item, dict) or set(item) != {"name", "sha256", "transaction"} \
                or not isinstance(item["name"], str) or not NAME.fullmatch(item["name"]) \
                or not isinstance(item["sha256"], str) or not SHA.fullmatch(item["sha256"]) \
                or item["transaction"] not in ("outer", "wrap"):
            raise InventoryError("invalid_lock_entry")
    names = [item["name"] for item in items]
    if names != sorted(names) or len(set(names)) != len(names) \
            or len({name[:14] for name in names}) != len(names) or _names(directory) != names:
        raise InventoryError("migration_set_or_order_mismatch")
    result = []
    total = 0
    for item in items:
        data = _read_regular(directory / item["name"])
        total += len(data)
        if total > MAX_TOTAL_BYTES or not data.strip() or _digest(data) != item["sha256"]:
            raise InventoryError("migration_hash_or_size_mismatch")
        result.append((item, data.decode("utf-8", errors="strict")))
    # A source owner may be editing while the inventory runs; never mix versions.
    if _read_regular(lock_path) != lock_bytes or _names(directory) != names:
        raise InventoryError("source_changed_during_inventory")
    for item, _ in result:
        if _digest(_read_regular(directory / item["name"])) != item["sha256"]:
            raise InventoryError("source_changed_during_inventory")
    if _read_regular(lock_path) != lock_bytes or _names(directory) != names:
        raise InventoryError("source_changed_during_inventory")
    return lock, result, _digest(lock_bytes)


def _base(signature: str) -> str:
    return signature.split("(", 1)[0].lower()


def _flags(name: str, text: str) -> list[str]:
    flags = []
    lower = text.lower()
    if name == "20261101013157_collect_deployment_identity.sql":
        if not re.search(r"profile\s*->>\s*'mode'\s+is\s+distinct\s+from\s+'self_hosted'", text, re.I):
            raise InventoryError("deployment_identity_anchor_changed")
        flags.append("self_hosted_only_deployment_binding")
    if name == "20261110181002_collect_local_stopped_admission.sql":
        if "collect_fence_local_stopped_admissions" not in lower:
            raise InventoryError("local_stopped_anchor_changed")
        flags.append("local_vm_stopped_executor_protocol")
    if "prosrc" in lower or "pg_get_functiondef" in lower:
        flags.append("function_definition_sensitive_review_required")
    if "_collect_member_realtime_metadata_sha" in lower:
        flags.append("provider_realtime_metadata_pin")
    if re.search(r"collect_fence_control[\s\S]{0,300}\bmode\s*(?:=|<>|not\s+in|in)\s*['(]", text, re.I) \
            or "_collect_fence_require_operator()" in lower:
        flags.append("fence_state_or_operator_precondition")
    if re.search(r"^\s*--[^\n]*(?:unregistered|unverified design draft|inspection-only)", text, re.I | re.M):
        flags.append("draft_or_inspection_only_source_comment")
    return flags


def inspect(root: Path) -> dict:
    lock, files, lock_sha = snapshot(root)
    seen: dict[str, list[str]] = {}
    rows = []
    for index, (item, text) in enumerate(files):
        definitions = [{"name": match.group("name").lower(), "kind": match.group("kind").lower(),
                        "line": _line(text, match.start())} for match in CREATED.finditer(text)]
        lookups = []
        for match in LOOKUP.finditer(text):
            name = match.group("name").lower()
            if not re.fullmatch(r"[a-z_][a-z0-9_.]*(?:\([a-z0-9_.,\[\] ]*\))?", name):
                continue
            prior = seen.get(_base(name), [])
            condition = " ".join((match.group("condition") or "unspecified").upper().split())
            lookups.append({"kind": match.group("kind").lower(), "name": name,
                            "condition": condition, "line": _line(text, match.start()),
                            "previous_textual_definition": prior[-1] if prior else None})
        pins = []
        matches = ([(match, "literal_tuple") for match in TUPLE.finditer(text)]
                   + [(match, "direct_regprocedure_comparison") for match in DIRECT.finditer(text)]
                   + [(match, "inline_prosrc_comparison") for match in INLINE.finditer(text)])
        for match, source_form in sorted(matches, key=lambda value: value[0].start()):
            signature = (match.group("sig1") or match.group("sig2") if source_form == "inline_prosrc_comparison"
                         else match.group("sig")).lower()
            prior = seen.get(_base(signature), [])
            pins.append({"signature": signature, "sha256": match.group("sha"),
                         "line": _line(text, match.start()),
                         "source_form": source_form,
                         "previous_textual_definition": prior[-1] if prior else None})
        rows.append({"position": index + 1, "name": item["name"], "sha256": item["sha256"],
                     "transaction": item["transaction"],
                     "previous_migration": files[index - 1][0]["name"] if index else None,
                     "flags": _flags(item["name"], text), "literal_lookups": lookups,
                     "candidate_function_preimages": pins, "textual_definitions": definitions})
        for definition in definitions:
            seen.setdefault(definition["name"], []).append(item["name"])
    names = {row["name"] for row in rows}
    required = {"20261101013157_collect_deployment_identity.sql",
                "20261110181002_collect_local_stopped_admission.sql"}
    if not required <= names:
        raise InventoryError("required_known_migration_missing")
    return {"format": "collect.managed-portability-inventory.v1", "inventory_status": "complete",
            "managed_deployment_decision": "NO_GO", "migration_count": len(rows),
            "lock_sha256": lock_sha, "original_count": lock["original_count"],
            "limits": ["Static lexical candidates only; dynamic SQL, overloads, implicit dependencies and all preimages are not exhaustively parsed.",
                       "A prior textual definition does not prove the installed PostgreSQL object or its body, ACL, owner or attributes.",
                       "The chain, provider-managed state, data, operations, keys and deployment are not qualified by this inventory."],
            "migrations": rows}


def probe_sql(inventory: dict, name: str) -> str:
    """Generate a read-only, parameter-free candidate pg_proc inspection query."""
    matches = [row for row in inventory["migrations"] if row["name"] == name]
    if len(matches) != 1 or not matches[0]["candidate_function_preimages"]:
        raise InventoryError("migration_has_no_extracted_preimages")
    pins = matches[0]["candidate_function_preimages"]
    # Signatures and hashes were captured by strict, quote-free regexes above.
    values = ",\n".join("    ('%s','%s')" % (pin["signature"], pin["sha256"]) for pin in pins)
    return ("-- Candidate body-hash inspection for %s. No migration or data writes.\n" % name
            + "-- Run only at the exact predecessor checkpoint; this is NOT deployment qualification.\n"
            + "BEGIN READ ONLY;\nSET LOCAL search_path=pg_catalog;\nSET LOCAL statement_timeout='5s';\nWITH expected(signature, candidate_sha256) AS (VALUES\n" + values + "\n)\n"
            + "SELECT e.signature,e.candidate_sha256, p.oid IS NOT NULL AS present,\n"
            + "  CASE WHEN p.oid IS NULL THEN NULL ELSE pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc,'UTF8')),'hex') END AS observed_prosrc_sha256,\n"
            + "  pg_catalog.pg_get_userbyid(p.proowner) AS owner, p.prosecdef AS security_definer, p.proconfig AS configuration, p.proacl::text AS acl\n"
            + "FROM expected e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)\n"
            + "ORDER BY e.signature;\nROLLBACK;\n")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--probe-sql", metavar="MIGRATION", help="Emit candidate read-only catalog SQL for one exact migration")
    args = parser.parse_args(argv)
    try:
        result = inspect(args.root)
        if args.probe_sql:
            print(probe_sql(result, args.probe_sql), end="")
        else:
            print(json.dumps(result, indent=2, sort_keys=True))
        # A successful inventory deliberately is not a release GO.
        return 0
    except (InventoryError, OSError, UnicodeError, json.JSONDecodeError, TypeError, KeyError, ValueError) as error:
        code = str(error) if isinstance(error, InventoryError) else "invalid_or_unavailable_input"
        print(json.dumps({"inventory_status": "refused", "managed_deployment_decision": "NO_GO", "code": code}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
