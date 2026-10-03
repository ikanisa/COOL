#!/usr/bin/env python3
"""Verify the isolated historical financial upgrade evidence and source hashes."""

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "docs/release/financial-core-2026-09-28"
CUTOFF = "20260925190000"
EVIDENCE_THROUGH = "20260928174000"
CONTAINER = "supabase_db_collect_financial_qa_20260928"
PROJECT = "collect_financial_qa_20260928"
WORKDIR = str(ROOT / ".cache/financial-qa-20260928")


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def read_json(name):
    return json.loads((EVIDENCE / name).read_text())


def verify_report(name, expected_paths):
    report = read_json(name)
    require(report.get("status") == "pass", f"{name}: replay did not pass")
    require(report.get("container") == CONTAINER, f"{name}: wrong container")
    require(report.get("target_provenance") == {
        "project": PROJECT, "workdir": WORKDIR
    }, f"{name}: wrong Docker-label provenance")
    require(report.get("cron_launch_active_jobs") is False,
            f"{name}: scheduled jobs were not disabled")
    rows = report.get("migrations")
    require(isinstance(rows, list) and len(rows) == len(expected_paths),
            f"{name}: migration count differs")
    for row, path in zip(rows, expected_paths):
        require(row.get("migration") == path.name and row.get("status") == "pass",
                f"{name}: migration sequence or status differs")
        actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        require(row.get("sha256") == actual_hash,
                f"{name}: current migration source differs from executed source")
    return report


def main():
    all_migrations = sorted((ROOT / "supabase/migrations").glob("*.sql"))
    migrations = [p for p in all_migrations if p.name[:14] <= EVIDENCE_THROUGH]
    newer = [p.name for p in all_migrations if p.name[:14] > EVIDENCE_THROUGH]
    predecessor = [p for p in migrations if p.name[:14] <= CUTOFF]
    successor = [p for p in migrations if p.name[:14] > CUTOFF]
    require(len(predecessor) == 127 and len(successor) == 6,
            "Migration inventory changed; rerun upgrade rehearsal")
    before_report = verify_report("historical-pre.json", predecessor)
    after_report = verify_report("historical-upgrade.json", successor)
    require(before_report.get("synthetic_bootstrap_owner") is True,
            "Predecessor has no synthetic bootstrap owner")
    require("through 20260925190000" in before_report.get("mode", ""),
            "Predecessor mode does not declare bounded replay")
    require("continuation after 20260925190000" in after_report.get("mode", ""),
            "Successor mode does not declare bounded continuation")
    before = read_json("historical-pre-snapshot.json")
    after = read_json("historical-post-snapshot.json")
    after_uat = read_json("historical-post-uat-snapshot.json")
    after_uat_state = read_json("historical-post-uat-state.json")
    require(before.get("migration_count") == 127 and
            before.get("last_migration") == CUTOFF and
            before.get("receipt_contract_version") == 0,
            "Predecessor snapshot is not the expected legacy contract")
    require(after.get("migration_count") == 133 and
            after.get("last_migration") == "20260928174000" and
            after.get("receipt_contract_version") == 2,
            "Successor snapshot is not the expected v2 contract")
    require(before.get("evidence_rows") == after.get("evidence_rows") == 16 and
            before.get("evidence_sha256") == after.get("evidence_sha256"),
            "Historical financial/evidence rows changed during migration")
    require(before.get("group_balance_rwf") == after.get("group_balance_rwf") == 1500,
            "Historical group balance changed")
    require(before.get("posted_status") == after.get("posted_status") == "posted" and
            before.get("review_status") == after.get("review_status") == "review",
            "Historical payment status changed unexpectedly")
    require(before.get("intent_status") == "pending" and
            after.get("intent_status") == "cancelled",
            "Unverified historical payer intent was not cancelled")
    require(after_uat == after and after_uat_state == {
        "auth_users": 1,
        "payments": 2,
        "raw_sms": 3,
        "migrations": 133,
        "temporary_signup_exists": False,
    }, "Rollback-only UAT changed persistent fixture state")
    uat = (EVIDENCE / "historical-verify.stdout").read_text()
    require(uat.count("HISTORICAL_FINANCIAL_UPGRADE_UAT_PASS: 9 assertions") == 1 and
            "ERROR:" not in uat,
            "Post-upgrade UAT did not report nine clean rollback-only assertions")
    print(json.dumps({
        "status": ("pass_historical_snapshot_newer_migrations_unreplayed"
                   if newer else "pass"),
        "migration_sequence": "127 predecessor + 6 successor = 133",
        "covered_through": EVIDENCE_THROUGH,
        "newer_migrations_not_covered": newer,
        "historical_evidence_rows": 16,
        "historical_evidence_sha256": after["evidence_sha256"],
        "post_upgrade_assertions": 9,
        "limitations": "synthetic local fixture; no hosted/provider/device/rollback acceptance",
    }, sort_keys=True))


if __name__ == "__main__":
    main()
