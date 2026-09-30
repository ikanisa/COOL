#!/usr/bin/env python3
"""Record the reviewed146 concurrency suite on the exact offline local fixture.

The suite owns and restores its synthetic graph. This outer recorder independently
backs up and compares every application/Auth/Realtime table and catalog control.
It cannot select a hosted URL, alternate project, migration or test harness.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "collect_offline_recorder", ROOT / "scripts/tests/local_offline_verification.py"
)
RECORDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECORDER)
MIGRATION = ROOT / "supabase/migrations/20260930140000_roster_resource_integrity.sql"
MIGRATION_SHA = "d68f8fc45eb92b7ca34ac710548f105b926bfe9026e3214f0e8b030075026f4b"
HARNESS = ROOT / "scripts/tests/roster_resource_concurrency_uat.rb"
HARNESS_SHA = "157b532a972b2280d16b2bb0a968dfad73d4fe6b3419c1f4f04c8090e4f9a9da"
SCENARIOS = (
    "same_request_never_redispatches",
    "competing_active_slots_atomically_limited",
    "concurrent_finish_is_exactly_once_and_not_refunded",
    "concurrent_verified_source_receipt_is_immutable",
    "ambiguous_completion_retains_full_charge_and_one_active_slot",
    "stale_repeatable_read_last_slot_aborts40001",
    "feature_revocation_fences_waiting_upload_reservation",
)


def main() -> None:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "docs/release"):
        parser.error("Evidence must be inside this repository's docs/release")
    for source, digest in ((MIGRATION, MIGRATION_SHA), (HARNESS, HARNESS_SHA)):
        if RECORDER.sha(source.read_bytes()) != digest:
            parser.error("Reviewed146 source changed: " + source.name)
    before = RECORDER.prepare(output, 146, "20260930140000")
    sources = output / "executed-sources"
    sources.mkdir(mode=0o700)
    for source in (MIGRATION, HARNESS, Path(__file__).resolve()):
        (sources / source.name).write_bytes(source.read_bytes())
    environment = os.environ.copy()
    environment.update(
        COLLECT_ROSTER_PROVENANCE_QA="isolated_clone",
        COLLECT_ROSTER_CHECKPOINT=str(output / "checkpoint146.json"),
        COLLECT_ROSTER_RESOURCE_MIGRATION_SHA=MIGRATION_SHA,
    )
    command = ["ruby", str(HARNESS)]
    try:
        with (output / "stdout").open("xb") as stdout, (output / "stderr").open("xb") as stderr:
            completed = subprocess.run(command, cwd=ROOT, env=environment,
                                       stdout=stdout, stderr=stderr, timeout=240)
        return_code = completed.returncode
    except subprocess.TimeoutExpired:
        # Do not start another run or destroy a graph after an unknown outcome.
        return_code = -1
    checkpoint = json.loads((output / "checkpoint.json").read_text())
    checkpoint.update(sql_return_code=return_code, command=command,
                      migration_sha256=MIGRATION_SHA, harness_sha256=HARNESS_SHA,
                      controller_sha256=RECORDER.sha(Path(__file__).read_bytes()))
    RECORDER.save(output / "checkpoint.json", checkpoint)
    after = RECORDER.snapshot()
    RECORDER.finish(output, before, after, unchanged=True)
    RECORDER.guard(146, "20260930140000")
    result = json.loads((output / "stdout").read_text())
    observed = tuple(item["scenario"] for item in result.get("scenarios", []))
    checks = {
        "harness_passed": result.get("status") == "pass",
        "all_reviewed_scenarios": observed == SCENARIOS,
        "migration_bound": result.get("migration_sha256") == MIGRATION_SHA,
        "harness_bound": result.get("source_sha256") == HARNESS_SHA,
        "financial_rows_unchanged": result.get("financial_rows_unchanged") is True,
        "synthetic_graph_removed": result.get("synthetic_graph_removed") is True,
        "workers_removed": result.get("worker_sessions_remaining") == 0,
        "provider_calls_zero": result.get("provider_calls") == 0,
        "hosted_auth_requests_zero": result.get("hosted_auth_requests") == 0,
        "charges_exact": result.get("charges") == {"requests": 4, "cost_units": 40000, "bytes": 400},
    }
    RECORDER.save(output / "scenario-verification.json", {
        "status": "pass" if all(checks.values()) else "fail",
        "checks": checks, "scenario_count": len(observed),
        "result_sha256": RECORDER.sha((output / "stdout").read_bytes()),
    })
    if not all(checks.values()):
        raise RuntimeError("146 scenario acceptance failed: " + json.dumps(checks))
    print(json.dumps({"status": "pass", "scenarios": len(observed),
                      "tables_restored": len(before["tables"])}))


if __name__ == "__main__":
    main()
