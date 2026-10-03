#!/usr/bin/env python3
"""Create a bounded release-gate association without changing acceptance records."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from datetime import datetime, timezone


def sha(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError("ACCEPTANCE_SOURCE_INPUT_INVALID")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def acceptance_state(*, preparation_authorized: bool, proof_verified: bool) -> dict:
    return {
        "preparation_authorized": preparation_authorized,
        "external_proof_verified": proof_verified,
        "acceptance": "verified" if proof_verified else "open",
        "authorization_substitutes_for_identity_device_delivery_or_security_proof": False,
    }


def assemble(progress: dict, master: dict, observations: dict, authorization: bool) -> dict:
    tasks = progress.get("tasks")
    if not isinstance(tasks, list) or {r.get("id") for r in tasks if isinstance(r, dict)} != {
        f"C{i:02}" for i in range(1, 37)
    } or len(tasks) != 36:
        raise ValueError("ACCEPTANCE_TASK_INVENTORY_INVALID")
    if set(observations) != {"collect_notification_health", "get_collect_health"}:
        raise ValueError("ACCEPTANCE_OBSERVATION_INVALID")
    allowed = {"OPERATOR_SESSION_REAUTHENTICATION_REQUIRED", "COLLECT_CURRENT_USER_SESSION_REQUIRED"}
    if any(code not in allowed for code in observations.values()):
        raise ValueError("ACCEPTANCE_OBSERVATION_INVALID")
    master_items = master.get("items")
    if not isinstance(master_items, list) or len({r["id"] for r in master_items}) != len(master_items):
        raise ValueError("ACCEPTANCE_MASTER_INVENTORY_INVALID")
    open_ids = [r["id"] for r in master_items if r["open"]]
    known_ids = {r["id"] for r in master_items}
    rows = []
    for row in tasks:
        parents = row.get("master_ids", [])
        if not isinstance(parents, list) or any(p not in known_ids for p in parents):
            raise ValueError("ACCEPTANCE_MASTER_BINDING_INVALID")
        rows.append({
            "id": row["id"], "task": row["task"],
            "recorded_implementation_status": row["status"],
            "recorded_implementation_evidence": row.get("implementation_evidence"),
            "remaining_acceptance_work": row["closure"],
            "master_ids": parents,
            "current_business_preparation": "delegated_to_agent" if authorization else "authorization_unrecorded",
            **acceptance_state(preparation_authorized=authorization, proof_verified=False),
        })
    return {
        "contract_version": 1, "generated_at": datetime.now(timezone.utc).isoformat(),
        "scope": "Release preparation and evidence association; no master-register closures or production GO.",
        "user_authorization": {
            "preparation_and_fixes_authorized": authorization,
            "source": "Current owner's direct authorization relayed by root in this session",
            "business_decisions_may_be_prepared_without_repeating_owner_questions": authorization,
            "specific_policy_choices_recorded_or_activated_by_this_tool": False,
            "identity_credentials_entitlements_device_carrier_or_legal_facts_created": False,
        },
        "task_count": len(rows), "open_task_acceptance_count": len(rows),
        "original_master_item_count": len(master_items), "original_master_open_count": len(open_ids),
        "original_master_open_ids": open_ids, "feature_and_master_counts_are_additive": False,
        "source06": progress.get("source_checkpoint06"),
        "mcp_current_observations": {k: {"reason_code": v, "authenticated_read_verified": False} for k, v in observations.items()},
        "tasks": rows,
        "release_decision": "NO_GO", "source_trusted_reviewed_or_frozen": False,
        "parent_registers_changed": False,
        "limits": [
            "Historical scoped tests remain tied to their own bytes, dates and environments; counts are not summed.",
            "Delegated execution authorization is recorded separately from specific implemented policy decisions and actual external proof.",
            "Source06 is a retained non-atomic unapproved implementation checkpoint, not a current-tree freeze.",
            "This is a bounded input association, not a complete secret/history/vendor/legal/security audit.",
            "Missing current authentication prevents successful installed MCP backend acceptance.",
        ],
    }


def generate(root: Path, observations: dict, authorization: bool) -> dict:
    paths = [
        "docs/release/collect-codex-goal-2026-09-30/implementation-progress.json",
        "docs/release/production-remaining-tasks-2026-09-30.json",
        "docs/release/local-implementation-register-2026-09-30.json",
    ]
    blobs = {}
    for path in paths:
        target = root / path
        if target.is_symlink() or not target.is_file():
            raise ValueError("ACCEPTANCE_SOURCE_INPUT_INVALID")
        blobs[path] = target.read_bytes()
    progress = json.loads(blobs[paths[0]])
    master = json.loads(blobs[paths[1]])
    report = assemble(progress, master, observations, authorization)
    report["register_input_hashes"] = {p: hashlib.sha256(b).hexdigest() for p, b in blobs.items()}
    inputs = [*sorted((root / ".github/workflows").glob("*.yml")),
              *sorted((root / "tools/collect-notification-mcp/src").rglob("*.ts")),
              root / "tools/collect-notification-mcp/package.json",
              root / "tools/collect-notification-mcp/pnpm-lock.yaml",
              root / "scripts/qa/collect_ci_policy.py",
              root / "scripts/tests/test_collect_ci_policy.py",
              root / "scripts/qa/collect_release_acceptance.py"]
    report["current_selected_input_hashes"] = {str(p.relative_to(root)): sha(p) for p in inputs}
    migrations = sorted((root / "supabase/migrations").glob("*.sql"))
    report["current_migration_inventory"] = {p.name: sha(p) for p in migrations}
    report["current_migration_count"] = len(migrations)
    report["source_observation_completed_at"] = datetime.now(timezone.utc).isoformat()
    report["register_drift_observed_during_association"] = [p for p, b in blobs.items() if (root / p).read_bytes() != b]
    report["selected_input_drift_observed_during_association"] = [
        p for p, digest in report["current_selected_input_hashes"].items() if sha(root / p) != digest
    ]
    report["current_tree_fully_scanned_or_accepted"] = False
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mcp-observation", type=Path, required=True)
    parser.add_argument("--delegated-preparation-authorized", action="store_true")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output must be a new file; historical evidence cannot be overwritten")
    receipt = json.loads(args.mcp_observation.read_text())
    if receipt.get("scope") != "Actual installed MCP tool calls; projected reason codes only" or receipt.get("raw_credentials_or_customer_data_retained") is not False:
        raise ValueError("ACCEPTANCE_OBSERVATION_INVALID")
    report = generate(args.root.resolve(), receipt.get("reason_codes", {}), args.delegated_preparation_authorized)
    # These reason codes are a supplied observation association, not fresh calls.
    # The caller must retain the actual MCP observation receipt separately.
    report["mcp_observations_source"] = "Separately retained actual installed MCP tool observation receipt; no tool calls by this generator."
    report["mcp_observation_receipt_sha256"] = sha(args.mcp_observation)
    report["mcp_observations_recorded_at"] = receipt.get("recorded_at")
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: report[k] for k in ["task_count", "original_master_open_count", "current_migration_count", "release_decision"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
