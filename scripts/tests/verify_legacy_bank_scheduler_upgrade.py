"""Compare root-owned normal-owner 142/143 snapshots; no database connection."""
import json
import sys
from datetime import datetime

NAME = "collect-daily-bank-reconciliation"
COMMAND_SHA256 = "58ca13bd6915f92b194de581f89815718ac50a5d702055a4df3f07c0486bd597"


def verify(before, after, phase="verified"):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    require(phase in ("paused", "verified"), "Unknown retirement phase")
    require((before["migration_count"], before["migration_max"]) == (142, "20260930100000"), "Expected exact 142 baseline")
    require((after["migration_count"], after["migration_max"]) == (143, "20260930110000"), "Expected exact 143 result")
    require(before["business_tables"] == after["business_tables"], "Business or historical financial rows changed")
    require(before["cron_history"] == after["cron_history"], "Cron run history changed")
    require(before["canonical_history"] == after["canonical_history"], "Canonical cron run history changed")
    require(before["retirement_audit"] == [] and before.get("postcommit_observations", []) == [] and before.get("final_verifications", []) == [], "Expected fresh upgrade without prior receipts")
    old_jobs = {job["id"]: job for job in before["cron_jobs"]}
    new_jobs = {job["id"]: job for job in after["cron_jobs"]}
    require(len(old_jobs) == len(before["cron_jobs"]) and len(new_jobs) == len(after["cron_jobs"]), "Duplicate cron job identifiers")
    require(old_jobs.keys() == new_jobs.keys(), "A cron job was added or removed")
    canonical = {job_id for job_id, job in old_jobs.items() if job["name"] == NAME}
    receipts = {row["job_id"]: row for row in after["retirement_audit"]}
    require(len(receipts) == len(after["retirement_audit"]) and len(canonical) == 1 and receipts.keys() == canonical, "Expected exactly one owner-bound canonical pause receipt")
    for job_id, old in old_jobs.items():
        expected = dict(old)
        if job_id in canonical:
            require(old["command_sha256"] == COMMAND_SHA256 and old["schedule"] == "30 21 * * *", "Unexpected canonical command or schedule")
            require(old["owner"] == "postgres" and old["database"] == "postgres" and old["host"] == "localhost" and old["port"] == 5432, "Unexpected normal-owner job routing")
            expected["active"] = False
            expected["metadata_sha256"] = new_jobs[job_id]["metadata_sha256"]
            row = receipts[job_id]
            require(row["job_name"] == NAME and row["job_owner"] == old["owner"] and row["database_name"] == old["database"] and row["schedule"] == old["schedule"], "Pause identity mismatch")
            require(row["command_sha256"] == COMMAND_SHA256 and row["was_active"] is old["active"], "Pause command or prior activity mismatch")
            require(row["inactive_metadata_sha256"] == new_jobs[job_id]["metadata_sha256"], "Inactive metadata binding differs")
            require(row["retirement_version"] == "20260930110000" and row["retirement_reason"] == "rwanda_momo_only_bank_scheduler_retired" and row["state"] == "paused_pending_verification", "Pause policy mismatch")
            require(row["paused_by"] == old["owner"] and bool(row["paused_at"]) and row["paused_xid"] > 0, "Pause installer metadata missing")
            require(row["history_rows"] == before["canonical_history"]["rows"] and row["history_sha256"] == before["canonical_history"]["sha256"], "Pause history binding differs")
        require(new_jobs[job_id] == expected, "Cron job changed beyond active=false")
    observations = after["postcommit_observations"]
    finals = after["final_verifications"]
    if phase == "paused":
        require(observations == [] and finals == [], "Pause must not invent a completed postcommit verification")
    else:
        require(len(observations) == 1 and len(finals) == 1, "Missing or duplicate postcommit verification")
        observation, final = observations[0], finals[0]
        job_id = next(iter(canonical))
        require(observation["job_id"] == job_id and final["job_id"] == job_id, "Verification identity mismatch")
        require(observation["observed_by"] == "postgres" and final["verified_by"] == "postgres", "Verification owner mismatch")
        require(final["state"] == "retired_verified", "Retirement is not verified")
        require(len({receipts[job_id]["paused_xid"], observation["observation_xid"], final["verification_xid"]}) == 3, "Phases must commit in three separate transactions")
        require(final["observation_readback_sha256"] == observation["readback_sha256"], "Observation binding mismatch")
        require(all(len(x) == 64 and all(c in "0123456789abcdef" for c in x) for x in (final["readback_sha256"], observation["readback_sha256"])), "Malformed readback digest")
        actual_seconds = (datetime.fromisoformat(final["verified_at"]) - datetime.fromisoformat(observation["observed_at"])).total_seconds()
        require(actual_seconds >= 30 and abs(float(final["observation_seconds"]) - actual_seconds) < 0.001, "Postcommit interval is too short or inconsistent")
    return {"ok": True, "phase": phase, "retired_jobs": len(canonical), "preserved_business_tables": len(before["business_tables"]), "preserved_cron_jobs": len(old_jobs), "preserved_cron_history_rows": before["cron_history"]["rows"]}


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        raise SystemExit("Usage: verify_legacy_bank_scheduler_upgrade.py BEFORE.json AFTER.json [paused|verified]")
    with open(sys.argv[1], encoding="utf-8") as handle:
        before = json.load(handle)
    with open(sys.argv[2], encoding="utf-8") as handle:
        after = json.load(handle)
    print(json.dumps(verify(before, after, sys.argv[3] if len(sys.argv) == 4 else "verified"), sort_keys=True))
