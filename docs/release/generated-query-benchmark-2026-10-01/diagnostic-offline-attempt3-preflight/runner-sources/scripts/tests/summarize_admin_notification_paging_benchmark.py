#!/usr/bin/env python3
"""Check private full-schema Admin notification paging plan transcripts."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache/financial-restore-qa-20260928"
BENCHMARK = ROOT / "scripts/tests/admin_notification_paging_benchmark.sql"
MIGRATION = ROOT / "supabase/migrations/20260929110000_admin_notification_page_before_delivery_counts.sql"
PARITY_RUNNER = ROOT / "scripts/tests/admin_notification_page_parity_uat.py"
PARITY_LOG = CACHE / "admin-notification-page-parity.stdout"
CASES = ("first-desc", "failed-asc", "deep-desc")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_run(events: int, candidate: bool) -> dict[str, object]:
    name = f"admin-notifications-{'candidate-' if candidate else ''}{events}"
    stdout_path = CACHE / f"{name}.stdout"
    stderr_path = CACHE / f"{name}.stderr"
    stdout = stdout_path.read_text()
    stderr = stderr_path.read_text()
    if (f"BENCHMARK_NOTIFICATION_EVENTS {events}" not in stdout
            or not stdout.rstrip().endswith("ROLLBACK")
            or f"INSERT 0 {events}" not in stdout):
        raise ValueError(f"Incomplete Admin notification benchmark: {name}")

    rows = re.findall(r"^\s*(first-desc|failed-asc|deep-desc)\s*\|"
                      r"\s*(\d+)\s*\|\s*(\d+)\s*$", stdout, re.MULTILINE)
    if [name for name, _, _ in rows] != list(CASES):
        raise ValueError(f"Missing benchmark cases in {name}")
    expected = (events + 1, events // 3, events + 1)
    if any(int(items) != 25 or int(total) != count
           for (_, items, total), count in zip(rows, expected)):
        raise ValueError(f"Incorrect page totals in {name}: {rows}")

    timings = [float(value) for value in re.findall(
        r"^Time:\s*([\d.]+)\s*ms$", stdout, re.MULTILINE)]
    if len(timings) != 3:
        raise ValueError(f"Expected three single-call timings in {name}")
    loops = [int(value) for value in re.findall(
        r"Index (?:Only )?Scan using "
        r"notification_deliveries_event_id_device_id_key[^\n]*loops=(\d+)",
        stderr)]
    expected_loops = ([25, 25, 25] if candidate else
                      [events + 1, events + 1, events // 3, events // 3,
                       events + 1, events + 1])
    if loops != expected_loops:
        raise ValueError(f"Delivery-count loop evidence changed in {name}: {loops}")
    query_prefix = "with page as materialized" if candidate else "with filtered as"
    plan_buffers = re.findall(
        rf"Query Text: {query_prefix}[\s\S]*?\n(?:Result|Aggregate)  "
        rf"\([^\n]*\n\s*Buffers: shared hit=(\d+)", stderr)
    if len(plan_buffers) != 3:
        raise ValueError(f"Missing three actual-buffer plans in {name}")
    return {
        "synthetic_events_inserted": events,
        "cases": {
            case: {"items": int(items), "total": int(total),
                   "single_call_elapsed_ms": time}
            for (case, items, total), time in zip(rows, timings)
        },
        "delivery_index_probe_loops": dict(zip(CASES,
            ([25, 25, 25] if candidate else
             [events + 1, events // 3, events + 1]))),
        "delivery_index_probe_count_per_case": 1 if candidate else 2,
        "top_plan_shared_buffer_hits": dict(zip(CASES, map(int, plan_buffers))),
        "private_log_sha256": {
            "stdout": sha256(stdout_path), "stderr": sha256(stderr_path),
        },
    }


def main() -> None:
    parity = PARITY_LOG.read_text()
    if (not parity.rstrip().endswith("ADMIN_NOTIFICATION_PAGE_PARITY_PASS_10")
            or len(re.findall(r"^[\w-]+\|\d+\|\d+$", parity, re.MULTILINE)) != 10):
        raise ValueError("Ten-case Admin notification JSON parity missing")
    report = {
        "status": "pass_local_candidate_not_release",
        "scope": "PostgreSQL 17.6 restored 133-migration fixture; proposed migration applied only inside rollback transactions",
        "method": "actual authenticated Admin RPC; nested auto_explain analyze/buffers; 25-row pages; exact totals",
        "limitations": [
            "single local execution per size and case; no p95 or p99",
            "synthetic one-user notification distribution and one delivery per event",
            "no full clean replay including proposed migration",
            "no hosted database, deployment, signed build or live index-build timing",
        ],
        "benchmark_sql_sha256": sha256(BENCHMARK),
        "candidate_migration_sha256": sha256(MIGRATION),
        "parity_runner_sha256": sha256(PARITY_RUNNER),
        "parity_transcript_sha256": sha256(PARITY_LOG),
        "runs": [
            {"events": events,
             "old": read_run(events, False),
             "candidate": read_run(events, True)}
            for events in (1000, 10000)
        ],
    }
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
