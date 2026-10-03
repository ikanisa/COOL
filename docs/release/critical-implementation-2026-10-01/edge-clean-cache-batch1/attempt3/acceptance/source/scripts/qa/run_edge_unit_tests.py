#!/usr/bin/env python3
"""Pinned, frozen Edge unit acceptance using an immutable synthetic SQL contract.

The actual Linux decoder integration is a mandatory separate phase in
run_edge_ci.py. These dated observations test current decoders, not current SQL.
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
INTEGRATION = "supabase/functions/_shared/roster_decoder_integration_test.ts"
ACTUAL_HANDLER_TEST = "scripts/tests/play_integrity_handler_test.ts"
FIXTURE = ROOT / "docs/release/critical-implementation-2026-10-01/ci-batch1/worker-fixture-v1"
MANIFEST_SHA256 = "e5ed738a0aa4dc6cf870bf33352610074a6e46ab82705dd82440571b58a6a657"
OBSERVED = ("observed-worker-executed.json", "observed-worker-lookup.json",
            "observed-worker-expired-lookup.json")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_fixture(directory: Path) -> list[Path]:
    """Only the reviewed immutable contract is accepted, even when copied."""
    if directory.is_symlink():
        raise ValueError("Fixture directory must not be a symlink")
    directory = directory.resolve(strict=True)
    manifest_path = directory / "manifest.json"
    if manifest_path.is_symlink() or sha(manifest_path) != MANIFEST_SHA256:
        raise ValueError("Unrecognized immutable SQL observation manifest")
    manifest = json.loads(manifest_path.read_text())
    paths = [manifest_path]
    for name, expected in manifest["files"].items():
        path = directory / name
        if path.is_symlink() or not path.resolve(strict=True).is_relative_to(directory):
            raise ValueError("Contained regular fixture files required")
        if sha(path) != expected:
            raise ValueError(f"Immutable fixture hash mismatch: {name}")
        paths.append(path)
    receipt = json.loads((directory / "result.json").read_text())
    if any(receipt.get(k) is not True for k in
           ("sources_unchanged", "runner_unchanged", "support_unchanged")):
        raise ValueError("Original completed SQL observation provenance required")
    if receipt.get("status") != "pass" or receipt["finished_at"] != manifest["origin_finished_at"]:
        raise ValueError("Original completed SQL observation provenance required")
    bindings = {"executed-runner.py": "runner_sha256", "authority-support.py": "support_sha256",
                "executed-helper.py": "helper_sha256"}
    for name, field in bindings.items():
        if sha(directory / "inputs" / name) != receipt[field]:
            raise ValueError(f"Origin generator binding mismatch: {name}")
    for name, expected in receipt["migration_sha256"].items():
        if sha(directory / "inputs" / name) != expected:
            raise ValueError(f"Origin migration binding mismatch: {name}")
    if not all(name in manifest["files"] for name in OBSERVED):
        raise ValueError("All worker observations are required")
    return paths


def passed_summary(text: str) -> dict[str, int]:
    # Actual Deno output inserts nested t.step counts beside the test totals.
    # Anchor the complete line so a partial/malformed summary cannot hide counts.
    matches = re.findall(
        r"^(ok|FAILED) \| (\d+) passed(?: \((\d+) steps?\))? \| "
        r"(\d+) failed(?: \((\d+) steps?\))?"
        r"(?: \| (\d+) ignored(?: \((\d+) steps?\))?)?"
        r"(?: \((?:\d+ms|\d+s|\d+m\d+s)\))?$", text, re.MULTILINE)
    candidates = re.findall(r"^(?:ok|FAILED) \|", text, re.MULTILINE)
    if len(matches) != 1 or len(candidates) != 1:
        raise ValueError("Exactly one completed Deno summary required")
    status, *counts = matches[0]
    passed, steps_passed, failed, steps_failed, ignored, steps_ignored = (int(v or 0) for v in counts)
    if status != "ok" or passed == 0 or any((failed, ignored, steps_failed, steps_ignored)):
        raise ValueError("Nonempty tests with zero failures and zero ignored tests or steps required")
    result = {"tests_passed": passed, "tests_failed": failed, "tests_ignored": ignored}
    if any(counts[index] for index in (1, 3, 5)):
        result.update(steps_passed=steps_passed, steps_failed=steps_failed, steps_ignored=steps_ignored)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deno", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--worker-sql-report", type=Path, default=FIXTURE,
                        help="Reviewed immutable fixture contract, not a current SQL report")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not any(output.is_relative_to(ROOT / p) for p in ("docs/release", ".cache")):
        parser.error("Fresh repository release or cache directory required")
    output.mkdir(parents=True, mode=0o700)
    binary = args.deno.resolve()
    files = sorted((ROOT / "supabase/functions").rglob("*.ts"))
    files += sorted((ROOT / "supabase/functions").rglob("fixtures/*.json"))
    files += [ROOT / "supabase/functions/deno.lock", ROOT / ".dvmrc", Path(__file__).resolve(),
              ROOT / ACTUAL_HANDLER_TEST]
    before = None
    report = {"status": "fail", "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "network_permission": "127.0.0.1 only", "run_permission": False,
              "database_calls": 0, "provider_calls": 0,
              "phase_allocation": {INTEGRATION: "Required actual Linux phase in run_edge_ci.py"},
              "dated_sql_decoder_scope": "Immutable synthetic SQL observations only; no current SQL acceptance"}
    try:
        worker = args.worker_sql_report.resolve(strict=True)
        files += validate_fixture(args.worker_sql_report)
        fixtures = sorted((ROOT / "contracts/collect-android-attempt-archive-v3/fixtures").glob("*.json"))
        fixtures += sorted((ROOT / "contracts/collect-android-dispatch-v2/fixtures").glob("*.json"))
        if not fixtures or any(not p.is_file() or p.is_symlink() for p in fixtures):
            raise RuntimeError("Contained contract decoder fixtures required")
        files += fixtures
        if any(not p.is_relative_to(ROOT) for p in files):
            raise RuntimeError("Fixture contract must be contained in repository")
        hashes = lambda: {str(p.relative_to(ROOT)): sha(p) for p in files}
        before = hashes()
        report["source_before"] = before
        for file in files:
            target = output / "source" / file.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, target)
        info = json.loads(subprocess.check_output([str(binary), "info", "--json"], text=True, timeout=10))
        if info["denoVersion"] != (ROOT / ".dvmrc").read_text().strip():
            raise RuntimeError("Exact .dvmrc runtime required")
        tests = [str(p.relative_to(ROOT)) for p in files if p.name.endswith("_test.ts")
                 and str(p.relative_to(ROOT)) != INTEGRATION]
        command = [str(binary), "test", "--no-config", "--cached-only", "--no-prompt",
                   "--frozen", "--lock=supabase/functions/deno.lock", "--allow-env",
                   "--allow-net=127.0.0.1",
                   "--allow-read=" + ",".join(["supabase/functions", str(worker),
                       "contracts/collect-android-attempt-archive-v3/fixtures",
                       "contracts/collect-android-dispatch-v2/fixtures"]),
                   *tests, "--", str(worker)]
        report.update(command=command, test_files=tests, test_file_count=len(tests),
                      runtime={"version": info["denoVersion"], "sha256": sha(binary)},
                      dependency_lock_enforced=True, observation_manifest_sha256=MANIFEST_SHA256)
        env = {"PATH": os.defpath, "DENO_DIR": info["denoDir"],
               "NO_COLOR": "1", "DENO_NO_UPDATE_CHECK": "1"}
        with (output / "stdout").open("xb") as out, (output / "stderr").open("xb") as err:
            completed = subprocess.run(command, cwd=ROOT, env=env, stdout=out, stderr=err, timeout=120)
        report["exit_code"] = completed.returncode
        if completed.returncode:
            raise RuntimeError("Actual unit command failed")
        report.update(passed_summary((output / "stdout").read_text()), status="pass")
    except Exception as error:
        report["error"] = str(error)
    finally:
        try:
            after = {str(p.relative_to(ROOT)): sha(p) for p in files}
            report.update(source_after=after, source_unchanged=before is not None and before == after)
        except OSError as error:
            report.update(source_unchanged=False, source_verification_error=str(error))
        if not report["source_unchanged"]:
            report.update(status="fail")
            report.setdefault("error", "Source changed during unit acceptance")
        report["ended_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        for name in ("stdout", "stderr"):
            if (output / name).is_file():
                report[name + "_sha256"] = sha(output / name)
        (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report.get(key) for key in
                      ("status", "test_file_count", "tests_passed", "tests_failed", "tests_ignored", "error")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
