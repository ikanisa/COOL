#!/usr/bin/env python3
"""Trace then restore only an explicitly reviewed failed local OTP race graph.

Requires empty original OTP tables, the exact offline145 fixture and complete
matching root checkpoint fingerprints. Deletions bind every row and observed
XID, and the full139-table baseline is proved inside the cleanup transaction.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("offline", ROOT / "scripts/tests/local_offline_verification.py")
OFFLINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OFFLINE)
PREFIX = "qa_otp_race_20260930_"
OWNED = (
    "collect_security.signed_otp_evidence", "collect_security.signed_otp_requests",
    "public.otp_rate_limits", "collect_auth_security.otp_phone_locks",
    "collect_security.otp_policy",
)


def inspect(failed: Path) -> dict:
    OFFLINE.guard(145, "20260930130000")
    baseline = json.loads((failed / "before.json").read_text())
    checkpoint = json.loads((failed / "checkpoint145.json").read_text())
    if checkpoint["baseline"] != baseline["tables"] or checkpoint["fixture"] != OFFLINE.FIXTURE.PROJECT:
        raise RuntimeError("Root and harness baseline disagree")
    if len(baseline["tables"]) != 139 or any(baseline["tables"][table]["rows"] != 0 for table in OWNED):
        raise RuntimeError("This recovery accepts only the proven empty original OTP baseline")
    current = OFFLINE.snapshot()
    if any(current["tables"].get(table) != rows for table, rows in baseline["tables"].items() if table not in OWNED):
        raise RuntimeError("Unknown application/Auth/financial data changed")
    if any(current[key] != baseline[key] for key in ("controls_sha256", "cron_jobs", "cron_history")):
        raise RuntimeError("Catalog, cron or guard controls changed")
    parts = []
    for table in OWNED:
        parts.append(OFFLINE.literal(table) + ", (select coalesce(jsonb_agg(jsonb_build_object('row',to_jsonb(t),'xmin',t.xmin::text) order by to_jsonb(t)::text),'[]') from " + table + " t)")
    owned = json.loads(OFFLINE.FIXTURE.sql("select jsonb_build_object(" + ",".join(parts) + ");"))
    requests = owned["collect_security.signed_otp_requests"]
    allowed = {PREFIX + str(n): hashlib.sha256(("synthetic-otp-race-phone-" + str(n)).encode()).hexdigest() for n in range(1, 6)}
    body = hashlib.sha256(b"synthetic OTP race body; no real OTP or phone").hexdigest()
    if not 1 <= len(requests) <= 5 or any(r["row"]["hook_id"] not in allowed or
            r["row"]["payload_hash"] != body or r["row"]["phone_hash"] != allowed[r["row"]["hook_id"]] for r in requests):
        raise RuntimeError("Unexpected request identity; no broad prefix deletion allowed")
    hooks = {r["row"]["hook_id"]: r["row"]["attempt_id"] for r in requests}
    phones = {r["row"]["phone_hash"] for r in requests}
    if any(r["row"]["hook_id"] not in hooks or r["row"]["attempt_id"] != hooks[r["row"]["hook_id"]]
           for r in owned["collect_security.signed_otp_evidence"]):
        raise RuntimeError("Unattributed outcome evidence")
    for table in ("public.otp_rate_limits", "collect_auth_security.otp_phone_locks"):
        if len(owned[table]) != len(phones) or any(r["row"]["phone_hash"] not in phones for r in owned[table]):
            raise RuntimeError("Unexpected quota/lock rows")
    policy = owned["collect_security.otp_policy"]
    if len(policy) != 1 or policy[0]["row"] != dict(singleton=True, global_hourly_limit=100000,
                                                  global_daily_limit=1000000, enabled=True):
        raise RuntimeError("Unexpected local policy mutation")
    if any(not r["xmin"].isdigit() for rows in owned.values() for r in rows):
        raise RuntimeError("Malformed observed transaction attribution")
    return dict(schema_version=1, failed_packet=str(failed), baseline=baseline,
                current=current, owned=owned,
                completed_cases=[r["label"] for r in checkpoint["cases"]],
                failed_checkpoint_sha256=OFFLINE.sha((failed / "checkpoint145.json").read_bytes()),
                before_sha256=OFFLINE.sha((failed / "before.json").read_bytes()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("trace", "apply"))
    parser.add_argument("--failed-packet", type=Path, required=True)
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("--trace-sha256")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    failed = args.failed_packet.resolve()
    if not failed.is_relative_to(ROOT / "docs/release/otp-uncertain-recovery-2026-09-30"):
        raise RuntimeError("Only this task's OTP evidence packet can be selected")
    report = inspect(failed)
    if args.mode == "trace":
        if args.trace.exists():
            raise RuntimeError("Preserve previous trace")
        OFFLINE.save(args.trace, report)
        print(json.dumps(dict(trace_sha256=OFFLINE.sha(args.trace.read_bytes()),
                              requests=[dict(hook_id=r["row"]["hook_id"], state=r["row"]["status"], xmin=r["xmin"])
                                        for r in report["owned"]["collect_security.signed_otp_requests"]],
                              unchanged_other_tables=134)))
        return
    if not args.output or OFFLINE.sha(args.trace.read_bytes()) != args.trace_sha256:
        raise RuntimeError("Exact reviewed trace SHA and new output required")
    if json.loads(args.trace.read_text()) != report:
        raise RuntimeError("State changed since review; inspect again")
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / "docs/release/otp-uncertain-recovery-2026-09-30"):
        raise RuntimeError("Recovery output must stay in this task packet")
    before = OFFLINE.prepare(out, 145, "20260930130000")
    if before != report["current"]:
        raise RuntimeError("State changed while preserving backup")
    current = OFFLINE.literal(json.dumps(before["tables"])) + "::jsonb"
    baseline = OFFLINE.literal(json.dumps(report["baseline"]["tables"])) + "::jsonb"
    fingerprints = OFFLINE.FIXTURE.fingerprints_sql(before["tables"])
    source = "begin isolation level serializable; select pg_advisory_xact_lock(193517,145);\n"
    source += "lock table " + ",".join(OWNED) + " in access exclusive mode;\n"
    source += "do $$ begin if (" + fingerprints + ") is distinct from " + current + " then raise exception 'Reviewed full baseline changed'; end if; end $$;\n"
    source += "alter table collect_security.signed_otp_evidence disable trigger signed_otp_evidence_immutable;\n"
    for table in OWNED:
        rows = report["owned"][table]
        data = OFFLINE.literal(json.dumps(rows)) + "::jsonb"
        source += "do $$ declare n integer; begin delete from " + table + " t using jsonb_array_elements(" + data + ") a where to_jsonb(t)=a->'row' and t.xmin::text=a->>'xmin'; get diagnostics n=row_count; if n<>" + str(len(rows)) + " then raise exception 'Exact observed row/XID count changed'; end if; end $$;\n"
    source += "alter table collect_security.signed_otp_evidence enable trigger signed_otp_evidence_immutable;\n"
    source += "do $$ begin if (" + fingerprints + ") is distinct from " + baseline + " then raise exception 'Original139-table baseline not restored'; end if; end $$;\n"
    source += "select 'SIGNED_OTP_RACE_FIXTURE_RESTORED'; commit;\n"
    (out / "reviewed-source.sql").write_text(source)
    OFFLINE.execute(source, out)
    after = OFFLINE.snapshot()
    if after != report["baseline"]:
        raise RuntimeError("Original rows and controls not restored after commit")
    OFFLINE.finish(out, before, after, unchanged=False, expected_changed_tables=OWNED)
    OFFLINE.save(out / "restoration.json", dict(original_all139_tables_and_controls_restored=True,
                                                reviewed_trace_sha256=args.trace_sha256,
                                                owned_row_counts={t: len(rows) for t, rows in report["owned"].items()},
                                                sequences_restored=False))


if __name__ == "__main__":
    main()
