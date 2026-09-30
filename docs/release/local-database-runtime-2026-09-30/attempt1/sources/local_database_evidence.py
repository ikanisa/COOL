#!/usr/bin/env python3
"""Consolidate actual143–146 runtime evidence; read the exact local fixture only.

This is a scoped database handover, not a full migration replay or release gate.
Historical failed runs remain intact. No provider/hosted request is made.
"""
from __future__ import annotations
import argparse
import datetime as dt
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("recorder", ROOT / "scripts/tests/local_offline_verification.py")
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
RELEASE = ROOT / "docs/release"
MIGRATIONS = {
    "20260930110000": ("retire_legacy_bank_scheduler", "5a7a4e7773b65e4fcf015ac079ea18d57cbe08d363bd8b07b87471018b941d85"),
    "20260930120000": ("roster_import_reload_recovery", "751be9afb6a1da5e221160b0201b0c3b7c532dc56f170f630ca03870929455b9"),
    "20260930130000": ("signed_otp_uncertain_recovery", "7c3fb624d65a9d70b8503d8fd5c265a8d452242638129b6d30de557633bbebe5"),
    "20260930140000": ("roster_resource_integrity", "d68f8fc45eb92b7ca34ac710548f105b926bfe9026e3214f0e8b030075026f4b"),
}
PACKETS = {
    "legacy-bank-scheduler-normal-owner-2026-09-30": [
        "canary142-root-attempt1", "populated142-root-attempt2", "adversarial142-root-attempt1",
        "apply143-root-attempt1", "observation143-root-attempt1", "final-verification143-root-attempt1",
        "normal-owner143-root-attempt1", "verified143-root-attempt1", "reapply143-root-attempt1"],
    "admin-roster-reload-2026-09-30": ["apply144-root-attempt1", "receipts144-root-attempt1",
        "adversarial144-root-attempt1", "concurrency144-root-attempt1"],
    "otp-uncertain-recovery-2026-09-30": ["correct145-root-attempt1", "rollback145-root-attempt2",
        "upgrade145-root-attempt1", "concurrency145-root-attempt2"],
    "upload-integrity-2026-09-30": ["apply146-root-attempt1", "rollback146-root-attempt1",
        "compatibility146-root-attempt1", "concurrency146-root-attempt1"],
}


def read(path: Path):
    return json.loads(path.read_text())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    require(output.is_relative_to(RELEASE) and not output.exists(), "Fresh repository release output required")
    bindings = {}
    source_paths = [Path(__file__).resolve(), ROOT / "scripts/tests/local_offline_verification.py",
                    ROOT / "scripts/tests/local_offline_verification_test.py",
                    ROOT / "scripts/tests/roster_resource_runtime_verification.py"]
    for version, (name, digest) in MIGRATIONS.items():
        source = ROOT / "supabase/migrations" / (version + "_" + name + ".sql")
        require(R.sha(source.read_bytes()) == digest, "Migration source drift: " + version)
        bindings[version] = digest
        source_paths.append(source)
    inputs = {}
    verified = []
    for family, attempts in PACKETS.items():
        for attempt in attempts:
            packet = RELEASE / family / attempt
            result = read(packet / "result.json")
            before, after = read(packet / "before.json"), read(packet / "after.json")
            stdout, stderr = packet / "stdout", packet / "stderr"
            require(result.get("status", "pass") == "pass", "Failed outer packet: " + attempt)
            require(result.get("sql_return_code", 0) == 0, "Failed command: " + attempt)
            require(result.get("stdout_sha256") == R.sha(stdout.read_bytes()), "Output hash differs: " + attempt)
            require(result.get("stderr_sha256") == R.sha(stderr.read_bytes()), "Error log hash differs: " + attempt)
            if result.get("unchanged"):
                require(before == after, "Rollback fingerprint mismatch: " + attempt)
            else:
                allowed = set(result.get("expected_changed_tables", []))
                require(all(name == "supabase_migrations.schema_migrations" or name in allowed
                            or after["tables"].get(name) == rows for name, rows in before["tables"].items()),
                        "Unrelated application table drift: " + attempt)
            for path in sorted(packet.rglob("*")):
                if path.is_file():
                    require(not path.is_symlink(), "Evidence symlink refused")
                    inputs[str(path.relative_to(ROOT))] = R.sha(path.read_bytes())
            verified.append({"packet": str(packet.relative_to(ROOT)),
                             "full_baseline_restored": before == after,
                             "tables_before": len(before["tables"]), "tables_after": len(after["tables"]),
                             "command_status_recorded": "sql_return_code" in result})
    scheduler = RELEASE / "legacy-bank-scheduler-normal-owner-2026-09-30"
    canary = read(scheduler / "canary142-root-attempt1/stdout")
    races = read(scheduler / "verified143-root-attempt1/stdout")
    require(canary.get("ok") and canary.get("checks") == 6 and canary.get("baseline_restored"), "Six scheduler canary races required")
    require(races.get("ok") and races.get("checks") == 9 and races.get("baseline_restored"), "Nine scheduler verification races required")
    normal = json.loads((scheduler / "normal-owner143-root-attempt1/stdout").read_text().splitlines()[-1])
    require(normal.get("checks") == 32, "32 normal-owner checks required")
    scheduler_snapshot = read(scheduler / "verified143-root-attempt1/races/checkpoint.json")["baseline"]
    final = scheduler_snapshot["final_verifications"][0]
    require(final["state"] == "retired_verified" and final["observation_seconds"] >= 30, "Postcommit scheduler interval required")
    require(len({scheduler_snapshot["retirement_audit"][0]["paused_xid"],
                 scheduler_snapshot["postcommit_observations"][0]["observation_xid"], final["verification_xid"]}) == 3,
            "Separate scheduler transactions required")
    roster = read(RELEASE / "admin-roster-reload-2026-09-30/concurrency144-root-attempt1/stdout")
    require(roster.get("status") == "pass" and len(roster["scenarios"]) == 6
            and roster["synthetic_graph_removed"] and roster["worker_sessions_remaining"] == 0, "Six roster races required")
    otp = read(RELEASE / "otp-uncertain-recovery-2026-09-30/concurrency145-root-attempt2/stdout")
    require(otp.get("pass") and len(otp["cases"]) == 6 and otp["table_fingerprints_restored"]
            and otp["provider_requests"] == 0, "Six OTP races required")
    resources = read(RELEASE / "upload-integrity-2026-09-30/concurrency146-root-attempt1/scenario-verification.json")
    require(resources["status"] == "pass" and resources["scenario_count"] == 7
            and all(resources["checks"].values()), "Seven resource races required")
    for family, attempt, marker in [
        ("otp-uncertain-recovery-2026-09-30", "rollback145-root-attempt2", "SIGNED_OTP_RECOVERY_UAT_PASS: 56 checks"),
        ("otp-uncertain-recovery-2026-09-30", "upgrade145-root-attempt1", "SIGNED_OTP_UPGRADE_UAT_PASS: 9 checks"),
        ("upload-integrity-2026-09-30", "rollback146-root-attempt1", "ROSTER_RESOURCE_UAT_CHECKS:29"),
        ("upload-integrity-2026-09-30", "compatibility146-root-attempt1", "FINAL146_COMPATIBILITY_PASS")]:
        require(marker in (RELEASE / family / attempt / "stdout").read_text(), "Missing actual SQL acceptance marker")
    R.guard(146, "20260930140000")
    live = R.snapshot()
    live_binding = json.loads(R.FIXTURE.sql("""begin isolation level repeatable read read only;
      select jsonb_build_object('bindings',(select jsonb_object_agg(version,encode(extensions.digest(statements[1],'sha256'),'hex'))
        from supabase_migrations.schema_migrations where version>='20260930110000'),
        'canonical_count',(select count(*) from cron.job where jobname='collect-daily-bank-reconciliation'),
        'canonical_active',(select active from cron.job where jobname='collect-daily-bank-reconciliation'),
        'bank_final_receipts',(select count(*) from collect_hybrid.legacy_bank_scheduler_verifications));rollback;"""))
    require(live_binding["bindings"] == bindings, "Live canonical migration source binding differs")
    require(live_binding["canonical_count"] == 1 and live_binding["canonical_active"] is False
            and live_binding["bank_final_receipts"] == 1, "Current local bank retirement drift")
    require(live["cron_jobs"] == read(scheduler / "reapply143-root-attempt1/after.json")["cron_jobs"]
            and live["cron_history"] == read(scheduler / "reapply143-root-attempt1/after.json")["cron_history"],
            "Scheduler metadata/history changed after143")
    require(live == R.snapshot(), "Local state changed during readback")
    output.mkdir(parents=True, mode=0o700)
    sources = output / "sources"
    sources.mkdir(mode=0o700)
    for path in source_paths:
        target = sources / path.name
        target.write_bytes(path.read_bytes())
        inputs[str(path.relative_to(ROOT))] = R.sha(path.read_bytes())
    tests = subprocess.run(["python3", "scripts/tests/local_offline_verification_test.py"],
                           cwd=ROOT, capture_output=True, timeout=30)
    (output / "recorder-tests.stdout").write_bytes(tests.stdout)
    (output / "recorder-tests.stderr").write_bytes(tests.stderr)
    require(tests.returncode == 0, "Evidence recorder fail-closed tests failed")
    R.save(output / "live-baseline.json", live)
    R.save(output / "live-source-binding.json", live_binding)
    require(all(R.sha((ROOT / path).read_bytes()) == digest for path, digest in inputs.items()), "Evidence changed during packaging")
    manifest = {
        "schema_version": 1, "status": "pass", "captured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "scope": "Actual isolated local143–146 installation, rollback, upgrade and blocking concurrency evidence",
        "fixture": R.FIXTURE.PROJECT, "migration_count": 146, "current_table_count": len(live["tables"]),
        "source_bindings": bindings, "verified_packets": verified, "input_hashes": inputs,
        "counts": {"scheduler_canary_races": 6, "scheduler_verification_races": 9, "scheduler_normal_owner_checks": 32,
                   "roster_reload_races": 6, "otp_recovery_checks": 56, "otp_v2_upgrade_checks": 9,
                   "otp_recovery_races": 6, "resource_checks": 29, "resource_races": 7, "recorder_corruption_tests": 8},
        "locally_completed_goal_items": ["L02"],
        "not_completed_here": ["L01 actual full browser lifecycle", "L06 final current Edge HTTP integration",
                               "L09-L13 final upload/evaluation HTTP integration", "L23 final clean/populated migration replay",
                               "all remaining24-item goal acceptance"],
        "limitations": ["Historical early scheduler/144 outer recorder omitted an explicit process exit field; actual completed typed inner receipts and full snapshot parity are retained. No exit code has been invented.",
                        "Current fixture retains generated financial fixtures; it is not representative customer acceptance data.",
                        "Global cron launches remain off and pg_net batch zero; no enabled provider dispatch was exercised.",
                        "Sequence allocations were not reset. Full clean replay through146 remains pending.",
                        "This packet does not close original production X02 or authorize deployment."],
        "provider_calls": 0, "hosted_calls": 0, "production_release_decision": "NO-GO",
    }
    R.save(output / "validation.json", manifest)
    print(json.dumps({"status": "pass", "packets": len(verified), "inputs": len(inputs),
                      "locally_completed": ["L02"], "manifest_sha256": R.sha((output / "validation.json").read_bytes())}))


if __name__ == "__main__":
    main()
