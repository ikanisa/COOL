#!/usr/bin/env python3
"""Summarize private, rollback-only full-schema history plan logs."""

from __future__ import annotations

import hashlib
import json
import re
import statistics
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache/financial-restore-qa-20260928"
BENCHMARK_SQL = ROOT / "scripts/tests/member_history_full_schema_benchmark.sql"
MIGRATION = ROOT / "supabase/migrations/20260928150000_relational_member_history_pages.sql"
CASE_PATTERN = re.compile(
    r"^\s*(newest|oldest|highest|lowest)\s*\|\s*(all|private)\s*\|"
    r"\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*$",
    re.MULTILINE,
)
FUNCTION_PLAN_PATTERN = re.compile(
    r"LOG:\s+duration:\s+([\d.]+)\s+ms\s+plan:\s*\n"
    r"Query Text:\s+select collect_member_actions\.history_page"
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(rows: int) -> dict[str, object]:
    stdout_path = CACHE / f"history-{rows}.stdout"
    stderr_path = CACHE / f"history-{rows}.stderr"
    stdout = stdout_path.read_text()
    stderr = stderr_path.read_text()
    if f"BENCHMARK_ROWS {rows}\n" not in stdout or not stdout.rstrip().endswith("ROLLBACK"):
        raise ValueError(f"Incomplete benchmark output for {rows} rows")
    if stdout.count("ALTER TABLE") != 2 or f"INSERT 0 {rows}\n" not in stdout:
        raise ValueError(f"Benchmark seed/trigger transcript invalid for {rows} rows")
    cases = [
        {
            "sort": match[1],
            "scope": match[2],
            "first_total": int(match[3]),
            "first_items": int(match[4]),
            "deep_total": int(match[5]),
            "deep_items": int(match[6]),
        }
        for match in CASE_PATTERN.finditer(stdout)
    ]
    if len(cases) != 8 or len({(case["sort"], case["scope"]) for case in cases}) != 8:
        raise ValueError(f"Missing sort/scope cases for {rows} rows")
    for case in cases:
        expected = rows + 1 if case["scope"] == "all" else rows // 2 + 1
        if (case["first_total"], case["deep_total"], case["first_items"],
                case["deep_items"]) != (expected, expected, 50, 50):
            raise ValueError(f"Incorrect page count for {rows}: {case}")
    search = {}
    for name in ("private-title-search", "no-match-search"):
        match = re.search(rf"^\s*{name}\s*\|\s*(\d+)\s*\|\s*(\d+)\s*$", stdout,
                          re.MULTILINE)
        if not match:
            raise ValueError(f"Missing {name} for {rows} rows")
        search[name] = {"total": int(match[1]), "items": int(match[2])}
    if search != {
        "private-title-search": {"total": rows // 2 + 1, "items": 50},
        "no-match-search": {"total": 0, "items": 0},
    }:
        raise ValueError(f"Search result mismatch for {rows} rows")
    elapsed = [float(value) for value in re.findall(r"^Time:\s*([\d.]+)\s*ms$",
                                                  stdout, re.MULTILINE)]
    if len(elapsed) != 3:
        raise ValueError(f"Expected three psql elapsed timings for {rows} rows")
    wrapper_durations = [float(value) for value in FUNCTION_PLAN_PATTERN.findall(stderr)]
    if len(wrapper_durations) != 18 or "Buffers: shared" not in stderr:
        raise ValueError(f"Nested analyzed buffer plans missing for {rows} rows")
    return {
        "synthetic_payments_inserted": rows,
        "visible_all_count": rows + 1,
        "visible_private_count": rows // 2 + 1,
        "cases": cases,
        "search": search,
        "elapsed_ms": {
            "eight_sort_scope_first_and_deep_cases": elapsed[0],
            "private_title_search": elapsed[1],
            "no_match_search": elapsed[2],
        },
        "nested_function_plans": {
            "count": len(wrapper_durations),
            "median_ms": round(statistics.median(wrapper_durations), 3),
            "max_ms": round(max(wrapper_durations), 3),
            "payment_seq_scan_lines": len(re.findall(r"Seq Scan on payments payment", stderr)),
            "payment_history_index_scan_lines": len(re.findall(
                r"Index Scan using payments_history_", stderr)),
            "top_n_heapsort_lines": len(re.findall(r"Sort Method: top-N heapsort", stderr)),
        },
        "private_log_sha256": {
            "stdout": sha256(stdout_path),
            "stderr": sha256(stderr_path),
        },
    }


def main() -> None:
    report = {
        "status": "pass_synthetic_plan_rehearsal_not_production_slo",
        "scope": "PostgreSQL 17.6 full restored local schema; synthetic read-plan rows; rollback only",
        "database": "collect_financial_restore_empty_20260928",
        "method": "user triggers disabled for performance-only row loading; reenabled before RPC calls; nested auto_explain analyze and buffers",
        "limitations": [
            "no provider-confirmed evidence or journals for benchmark rows",
            "synthetic scale is not a measured production workload",
            "one local database run per size; timings are not p95 or p99",
            "no hosted Supabase or signed-app readback",
        ],
        "benchmark_sql_sha256": sha256(BENCHMARK_SQL),
        "history_migration_sha256": sha256(MIGRATION),
        "runs": [summarize(1000), summarize(10000)],
    }
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
