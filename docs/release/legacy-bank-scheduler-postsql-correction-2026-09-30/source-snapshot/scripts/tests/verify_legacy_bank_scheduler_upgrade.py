"""Compare isolated 142/143 snapshots. Reads files only; never connects to a DB."""
import json
import sys

NAME = "collect-daily-bank-reconciliation"
COMMAND_SHA256 = "58ca13bd6915f92b194de581f89815718ac50a5d702055a4df3f07c0486bd597"


def verify(before, after):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    require((before["migration_count"], before["migration_max"]) == (142, "20260930100000"), "Expected exact 142 baseline")
    require((after["migration_count"], after["migration_max"]) == (143, "20260930110000"), "Expected exact 143 result")
    require(before["business_tables"] == after["business_tables"], "Business or historical financial rows changed")
    require(before["cron_history"] == after["cron_history"], "Cron run history changed")
    require(before["retirement_audit"] == [], "Expected fresh upgrade without prior retirement receipts")
    old_jobs = {job["id"]: job for job in before["cron_jobs"]}
    new_jobs = {job["id"]: job for job in after["cron_jobs"]}
    require(len(old_jobs) == len(before["cron_jobs"]) and len(new_jobs) == len(after["cron_jobs"]), "Duplicate cron job identifiers")
    require(old_jobs.keys() == new_jobs.keys(), "A cron job was added or removed")
    receipts = {row["job_id"]: row for row in after["retirement_audit"]}
    require(len(receipts) == len(after["retirement_audit"]), "Duplicate retirement receipts")
    canonical = {job_id for job_id, job in old_jobs.items() if job["name"] == NAME}
    require(receipts.keys() == canonical and len(canonical) <= 2, "Retirement receipt coverage differs from canonical jobs")
    for job_id, old in old_jobs.items():
        expected = dict(old)
        if job_id in canonical:
            require(old["command_sha256"] == COMMAND_SHA256 and old["schedule"] == "30 21 * * *", "Unexpected canonical command or schedule")
            require(old["owner"] in ("postgres", "supabase_admin") and old["database"] == "postgres" and old["host"] == "localhost", "Unexpected canonical job routing")
            expected["active"] = False
            row = receipts[job_id]
            require(row["job_name"] == NAME and row["job_owner"] == old["owner"] and row["database_name"] == old["database"] and row["schedule"] == old["schedule"], "Receipt identity mismatch")
            require(row["command_sha256"] == COMMAND_SHA256 and row["was_active"] is old["active"], "Receipt command or prior activity mismatch")
            require(row["retirement_version"] == "20260930110000" and row["retirement_reason"] == "rwanda_momo_only_bank_scheduler_retired", "Receipt policy mismatch")
            require(row["retired_by"] in ("postgres", "supabase_admin") and bool(row["retired_at"]), "Receipt installer metadata missing")
        require(new_jobs[job_id] == expected, "Cron job changed beyond the intended active=false")
    return {"ok": True, "retired_jobs": len(canonical), "preserved_business_tables": len(before["business_tables"]), "preserved_cron_jobs": len(old_jobs), "preserved_cron_history_rows": before["cron_history"]["rows"]}


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: verify_legacy_bank_scheduler_upgrade.py BEFORE.json AFTER.json")
    with open(sys.argv[1], encoding="utf-8") as handle:
        before = json.load(handle)
    with open(sys.argv[2], encoding="utf-8") as handle:
        after = json.load(handle)
    print(json.dumps(verify(before, after), sort_keys=True))
