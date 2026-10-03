#!/usr/bin/env python3
"""Root-owned outer backup/source/restoration gate for the exact local147 races."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "offline_recorder", ROOT / "scripts/tests/local_offline_verification.py"
)
RECORDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECORDER)
MIGRATION = "supabase/migrations/20260930150000_runtime_control_governance.sql"
HARNESS = "scripts/tests/runtime_control_concurrency_uat.rb"
REVIEWED_MIGRATION_SHA = "8029f6de3cd8618a32b6b68a1a312624b0a7d585a07c43056ecc5046dc345a1f"
REVIEWED_HARNESS_SHA = "8a4fd34839105f991f3b08d69583cb780f794f986216d7294f4f2b50a2a02419"
INPUTS = (MIGRATION, HARNESS, "scripts/tests/runtime_control_governance_uat.sql",
          "scripts/tests/local_offline_verification.py",
          "scripts/tests/notification_upgrade_telemetry.py",
          "scripts/tests/run_runtime_control_acceptance.py",
          "docs/release/runtime-controls-2026-09-30/contracts/client-contract-v2.json")


def hashes() -> dict[str, str]:
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in INPUTS}


def main() -> None:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh repository release evidence directory required")
    before_sources = hashes()
    if (before_sources[MIGRATION], before_sources[HARNESS]) != (
            REVIEWED_MIGRATION_SHA, REVIEWED_HARNESS_SHA):
        raise RuntimeError("Reviewed migration/harness bytes differ; do not execute")
    ruby = shutil.which("ruby")
    if not ruby:
        raise RuntimeError("Local Ruby runtime is missing")
    ruby_path = Path(ruby).resolve()
    ruby_sha = RECORDER.sha(ruby_path.read_bytes())
    before = RECORDER.prepare(output, 147, "20260930150000")
    for relative in INPUTS:
        target = output / "sources" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / relative).read_bytes())
    RECORDER.save(output / "source-hashes-before.json", before_sources)
    checkpoint = json.loads((output / "checkpoint.json").read_text())
    command = [str(ruby_path), "-E", "UTF-8:UTF-8", HARNESS]
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
           "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
           "COLLECT_RUNTIME_CONTROLS_QA": "isolated_clone",
           "COLLECT_RUNTIME_CONTROL_MIGRATION_SHA": REVIEWED_MIGRATION_SHA,
           "COLLECT_RUNTIME_CONTROL_CHECKPOINT": str(output / "harness-checkpoint.json")}
    failure = None
    return_code = None
    try:
        with (output / "stdout").open("xb") as out, (output / "stderr").open("xb") as err:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=out,
                                    stderr=err, timeout=240)
        return_code = result.returncode
        if return_code:
            raise RuntimeError("Actual147 race command failed; preserve checkpoint and inspect state")
        body = json.loads((output / "stdout").read_text())
        if (body.get("baseline_table_count") != 145
                or body.get("worker_sessions_remaining") != 0
                or body.get("synthetic_rows_removed") is not True
                or body.get("baseline_sha256_before") != body.get("baseline_sha256_after")
                or body.get("controls_sha256_before") != body.get("controls_sha256_after")):
            raise RuntimeError("Actual race command did not prove complete restoration")
    except Exception as error:
        failure = {"type": type(error).__name__, "message": str(error)}
    checkpoint.update(sql_return_code=return_code, operation="eleven_real147_blocking_races",
                      command=command, ruby_sha256=ruby_sha,
                      ended_at_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                      source_hashes_before=before_sources, failure=failure)
    RECORDER.save(output / "checkpoint.json", checkpoint)
    after_sources = hashes()
    RECORDER.save(output / "source-hashes-after.json", after_sources)
    after = RECORDER.snapshot()
    RECORDER.save(output / "after.json", after)
    if failure or before_sources != after_sources:
        RECORDER.save(output / "failure.json", {
            "command_failure": failure, "baseline_restored": before == after,
            "sources_unchanged": before_sources == after_sources,
            "actual_return_code": return_code})
        raise RuntimeError("147 acceptance failed; no automatic retry or cleanup")
    RECORDER.finish(output, before, after, unchanged=True)
    RECORDER.guard(147, "20260930150000")


if __name__ == "__main__":
    main()
