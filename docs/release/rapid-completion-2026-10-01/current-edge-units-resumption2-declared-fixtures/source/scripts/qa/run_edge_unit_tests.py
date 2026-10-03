#!/usr/bin/env python3
"""Run all local Edge unit files with the actual pinned frozen Deno runtime.

The named Linux decoder integration file is exercised by its separate sandbox
acceptance packet. Network permission is restricted to the worker's actual
loopback HTTP test. Dated SQL observations are decoder inputs, not SQL execution.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EXCLUDED = "supabase/functions/_shared/roster_decoder_integration_test.ts"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deno", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--worker-sql-report", type=Path, required=True,
                        help="Accepted synthetic worker SQL packet for the observed decoder")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh repository release directory required")
    output.mkdir(parents=True, mode=0o700)
    binary = args.deno.resolve()
    files = sorted((ROOT / "supabase/functions").rglob("*.ts"))
    files += [ROOT / "supabase/functions/deno.lock", ROOT / ".dvmrc", Path(__file__).resolve()]
    worker = args.worker_sql_report.resolve(strict=True)
    if not worker.is_relative_to(ROOT / "docs/release"):
        parser.error("Contained synthetic worker evidence required")
    receipt = worker / "result.json"
    accepted = json.loads(receipt.read_text())
    if accepted.get("status") != "pass" or not accepted.get("sources_unchanged"):
        parser.error("Completed accepted worker SQL observations required")
    observed = [worker / name for name in ("observed-worker-executed.json",
                "observed-worker-lookup.json", "observed-worker-expired-lookup.json")]
    fixtures = sorted((ROOT / "contracts/collect-android-attempt-archive-v3/fixtures").glob("*.json"))
    fixtures += sorted((ROOT / "contracts/collect-android-dispatch-v2/fixtures").glob("*.json"))
    if not fixtures or any(not p.is_file() or p.is_symlink() for p in observed + fixtures):
        parser.error("Actual contained decoder fixtures required")
    files += [receipt, *observed, *fixtures]
    hashes = lambda: {str(p.relative_to(ROOT)): sha(p) for p in files}
    before = hashes()
    report = {"status": "fail", "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "source_before": before, "network_permission": "127.0.0.1 only",
              "run_permission": False, "database_calls": 0, "provider_calls": 0,
              "exclusions": {EXCLUDED: "Actual Linux sandbox/adapter integration has separate acceptance"}}
    report["dated_sql_decoder_scope"] = "Immutable synthetic SQL observations only; no current server installation inferred"
    for file in files:
        target = output / "source" / file.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(file, target)
    try:
        info = json.loads(subprocess.check_output([str(binary), "info", "--json"], text=True, timeout=10))
        if info["denoVersion"] != (ROOT / ".dvmrc").read_text().strip():
            raise RuntimeError("Exact .dvmrc runtime required")
        tests = [str(p.relative_to(ROOT)) for p in files if p.name.endswith("_test.ts")
                 and str(p.relative_to(ROOT)) != EXCLUDED]
        command = [str(binary), "test", "--no-config", "--cached-only", "--no-prompt",
                   "--frozen", "--lock=supabase/functions/deno.lock", "--allow-env",
                   "--allow-net=127.0.0.1",
                   "--allow-read=" + ",".join(["supabase/functions", str(worker),
                       "contracts/collect-android-attempt-archive-v3/fixtures",
                       "contracts/collect-android-dispatch-v2/fixtures"]),
                   *tests, "--", str(worker)]
        report.update(command=command, test_files=tests, test_file_count=len(tests),
                      runtime={"version": info["denoVersion"], "sha256": sha(binary)},
                      dependency_lock_enforced=True)
        env = {"PATH": os.defpath, "DENO_DIR": info["denoDir"],
               "NO_COLOR": "1", "DENO_NO_UPDATE_CHECK": "1"}
        with (output / "stdout").open("xb") as out, (output / "stderr").open("xb") as err:
            completed = subprocess.run(command, cwd=ROOT, env=env, stdout=out, stderr=err, timeout=60)
        report["exit_code"] = completed.returncode
        match = re.search(r"ok \| (\d+) passed \| (\d+) failed", (output / "stdout").read_text())
        if completed.returncode or not match or int(match[2]) != 0 or int(match[1]) == 0:
            raise RuntimeError("Actual complete nonempty unit command did not pass")
        report.update(status="pass", tests_passed=int(match[1]), tests_failed=int(match[2]))
    except Exception as error:
        report["error"] = str(error)
    finally:
        after = hashes()
        report.update(source_after=after, source_unchanged=before == after,
                      ended_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        if before != after:
            report.update(status="fail", error="Source changed during unit acceptance")
        for name in ("stdout", "stderr"):
            if (output / name).is_file():
                report[name + "_sha256"] = sha(output / name)
        (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report.get(key) for key in ("status", "test_file_count", "tests_passed", "tests_failed", "error")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
