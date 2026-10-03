#!/usr/bin/env python3
"""Validate private rollback-only full-schema recent-intent plan logs."""

from __future__ import annotations

import hashlib
import json
import re
import statistics
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache/financial-restore-qa-20260928"
BENCHMARK_SQL = ROOT / "scripts/tests/recent_intents_full_schema_benchmark.sql"
MIGRATION = ROOT / "supabase/migrations/20260928150000_relational_member_history_pages.sql"
CASE_PATTERN = re.compile(
    r"^\s*(recent-50|exact-old-id|missing-id|other-member-recent|other-member-exact)"
    r"\s*\|\s*(\d+)\s*\|\s*(\d+)"
    r"(?:\s*\|\s*(\d+))?(?:\s*\|\s*([tf])\s*\|\s*([tf])"
    r"\s*\|\s*([tf])\s*\|\s*([tf]))?\s*$",
    re.MULTILINE,
)
FUNCTION_PLAN_PATTERN = re.compile(
    r"LOG:\s+duration:\s+([\d.]+)\s+ms\s+plan:\s*\n"
    r"Query Text:\s+select collect_member_actions\.recent_intents"
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(intents: int) -> dict[str, object]:
    stdout_path = CACHE / f"recent-intents-{intents}.stdout"
    stderr_path = CACHE / f"recent-intents-{intents}.stderr"
    stdout = stdout_path.read_text()
    stderr = stderr_path.read_text()
    if (f"BENCHMARK_INTENTS {intents}\n" not in stdout
            or not stdout.rstrip().endswith("ROLLBACK")
            or stdout.count("ALTER TABLE") != 2
            or f"INSERT 0 {intents}\n" not in stdout):
        raise ValueError(f"Incomplete benchmark/rollback transcript for {intents} intents")

    expected_pending = intents - intents // 3 - intents // 5 + intents // 15
    matches = list(CASE_PATTERN.finditer(stdout))
    expected_cases = [
        "recent-50", "exact-old-id", "missing-id",
        "other-member-recent", "other-member-exact",
    ]
    if [match[1] for match in matches] != expected_cases:
        raise ValueError(f"Missing or duplicate intent cases for {intents} intents")
    cases = {}
    for match in matches:
        elapsed_match = re.search(r"^Time:\s*([\d.]+)\s*ms$",
                                  stdout[match.end():], re.MULTILINE)
        if not elapsed_match:
            raise ValueError(f"Missing psql timing after {match[1]}")
        cases[match[1]] = {
            "items": int(match[2]),
            "pending_count": int(match[3]),
            "elapsed_ms": float(elapsed_match[1]),
        }
        if match[4] is not None:
            cases[match[1]]["expected_pending"] = int(match[4])
        if match[5] is not None:
            cases[match[1]]["includes_50"] = match[5] == "t"
            cases[match[1]]["includes_51"] = match[6] == "t"
            cases[match[1]]["expired_visible"] = match[7] == "t"
            cases[match[1]]["receiver_resolved"] = match[8] == "t"

    if cases["recent-50"] != {
        "items": 50, "pending_count": expected_pending,
        "expected_pending": expected_pending,
        "includes_50": True, "includes_51": False,
        "expired_visible": True, "receiver_resolved": True,
        "elapsed_ms": cases["recent-50"]["elapsed_ms"],
    }:
        raise ValueError(f"Recent window/visibility invariant failed for {intents}")
    for name, expected_items in (("exact-old-id", 1), ("missing-id", 0)):
        if (cases[name]["items"] != expected_items
                or cases[name]["pending_count"] != expected_pending
                or cases[name].get("expected_pending") != expected_pending):
            raise ValueError(f"Exact-ID/pending invariant failed: {name}")
    for name in ("other-member-recent", "other-member-exact"):
        if cases[name]["items"] != 0 or cases[name]["pending_count"] != 0:
            raise ValueError(f"Cross-member visibility invariant failed: {name}")

    durations = [float(value) for value in FUNCTION_PLAN_PATTERN.findall(stderr)]
    if (len(durations) != 5 or "Buffers: shared" not in stderr
            or "payment_intents_member_recent_idx" not in stderr
            or "payment_intents_pkey" not in stderr
            or "payment_intents_member_pending_idx" not in stderr):
        raise ValueError(f"Missing nested actual-buffer/index plans for {intents}")
    return {
        "synthetic_intents_inserted": intents,
        "expected_active_pending": expected_pending,
        "cases": cases,
        "nested_function_plans": {
            "count": len(durations),
            "median_ms": round(statistics.median(durations), 3),
            "max_ms": round(max(durations), 3),
            "recent_index_scan_lines": len(re.findall(
                r"Index Scan using payment_intents_member_recent_idx", stderr)),
            "pending_index_scan_lines": len(re.findall(
                r"(?:Bitmap Index Scan|Index Only Scan)"
                r" using payment_intents_member_pending_idx", stderr)),
            "pending_seq_scan_lines": len(re.findall(
                r"Seq Scan on payment_intents intent", stderr)),
            "exact_id_pkey_scan_lines": len(re.findall(
                r"Index Scan using payment_intents_pkey", stderr)),
        },
        "private_log_sha256": {
            "stdout": sha256(stdout_path), "stderr": sha256(stderr_path),
        },
    }


def main() -> None:
    report = {
        "status": "pass_synthetic_plan_rehearsal_not_production_slo",
        "scope": "PostgreSQL 17.6 full restored local schema; synthetic intent reads; rollback only",
        "database": "collect_financial_restore_empty_20260928",
        "method": "user triggers disabled for performance-only row loading; reenabled before RPC calls; nested auto_explain analyze and buffers",
        "limitations": [
            "single actor owns synthetic intent history; not representative user distribution",
            "receiver table is tiny, so its lookup plan does not prove index scaling",
            "one local database run per size; timings are not p95 or p99",
            "no hosted Supabase, provider, notification or signed-app readback",
        ],
        "benchmark_sql_sha256": sha256(BENCHMARK_SQL),
        "history_migration_sha256": sha256(MIGRATION),
        "runs": [summarize(1000), summarize(10000)],
    }
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
