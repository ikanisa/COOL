"""Run the maintained Edge recipe from an exact source copy and empty Deno cache.

No hosted/project/provider operation is permitted by this local recipe. The
canonical runner preserves its own fixed execution permissions and Linux phase.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
DENO = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
PYTHON = Path("/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3")
DECODER_PYTHON = ROOT / ".cache/decoder-dependency-batch1/fixture-generator-venv/bin/python"
DOCKER = Path("/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker")
FROZEN_EDGE = {
    "supabase/functions/verify-play-integrity/index.ts":
        "3e5f2fb1ba52241aa2906f6ce97c04a81b6a97e33479a06a12400bbc5137b7ed",
    "supabase/functions/_shared/integrity_admission.ts":
        "e199493ea1dc150bc3472ad38d2ea906ee118e102bc8631b035d8b52dbea077c",
    "supabase/functions/_shared/integrity_admission_test.ts":
        "999c093490077ab1b16dea805ee3c8a7ab38359f1b3078aa283d0ca3395d138d",
    "scripts/tests/play_integrity_handler_test.ts":
        "41f181641d75cb9b56460ded224df53f76581c9fe7fa1a36f1b79d38b3a419b6",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    label = sys.argv[1] if len(sys.argv) == 2 else "attempt1"
    if label not in ("attempt1", "attempt2"):
        raise ValueError("Explicit bounded fresh attempt label required")
    private = ROOT / ".cache/edge-current-integration-batch1" / label
    packet = PACKET / label
    if private.exists() or packet.exists():
        raise ValueError("Fresh private cache and evidence directory required")
    spec = importlib.util.spec_from_file_location("cold_canonical", ROOT / "scripts/qa/run_edge_ci.py")
    canonical = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(canonical)
    paths = canonical.source_paths()
    before = {str(p.relative_to(ROOT)): sha(p) for p in paths}
    if any(before.get(name) != digest for name, digest in FROZEN_EDGE.items()):
        raise ValueError("Reviewed Edge source freeze has changed")
    if any(p.is_symlink() or not p.is_file() for p in paths):
        raise ValueError("Regular contained source files required")
    stage = private / "source"
    cache = private / "deno-dir"
    cache.mkdir(parents=True, mode=0o700)
    packet.mkdir(mode=0o700)
    for path in paths:
        target = stage / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    assert all(sha(stage / name) == value for name, value in before.items())
    initial_cache_files = len([p for p in cache.rglob("*") if p.is_file()])
    assert initial_cache_files == 0
    output = stage / ".cache/canonical-acceptance"
    command = [str(PYTHON), "-B", str(stage / "scripts/qa/run_edge_ci.py"),
               "--deno", str(DENO), "--decoder-python", str(DECODER_PYTHON),
               "--cache-dependencies", "--output", str(output)]
    # HOME is inherited unchanged for Docker's local context resolution only.
    # The maintained runner constructs its own sanitized execution environment.
    env = {key: os.environ[key] for key in ("HOME", "TMPDIR") if key in os.environ}
    env.update(PATH=os.pathsep.join([str(DOCKER.parent), os.defpath]),
               DENO_DIR=str(cache), NO_COLOR="1", PYTHONDONTWRITEBYTECODE="1",
               DENO_NO_UPDATE_CHECK="1")
    report = {"schema_version": 1, "status": "fail", "attempt": label,
              "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "command": command, "cwd": str(stage), "source_before": before,
              "reviewed_edge_freeze": FROZEN_EDGE, "fresh_dependency_cache": str(cache),
              "initial_dependency_cache_file_count": initial_cache_files,
              "runtime_sha256_before": sha(DENO), "real_lock_sha256_before": before[
                  "supabase/functions/deno.lock"],
              "provider_calls": 0, "current_sql_executed": False}
    (packet / "canonical-batch.json").write_text(json.dumps(report, indent=2) + "\n")
    start = time.monotonic()
    try:
        with (packet / "canonical-run.stdout").open("xb") as out, \
                (packet / "canonical-run.stderr").open("xb") as err:
            completed = subprocess.run(command, cwd=stage, env=env, stdout=out,
                                       stderr=err, timeout=1200)
        report["exit_code"] = completed.returncode
        result = json.loads((output / "validation.json").read_text())
        report["status"] = result["status"]
        report["phases"] = result["phases"]
        report["canonical_report_sha256"] = sha(output / "validation.json")
        report["packet_acceptance_report"] = "acceptance/validation.json"
        if result.get("error"):
            report["error"] = result["error"]
    except Exception as error:
        report["error"] = str(error)
    finally:
        after = {name: sha(ROOT / name) for name in before}
        stage_after = {name: sha(stage / name) for name in before}
        report.update(source_after=after, current_root_source_unchanged=after == before,
                      stage_source_unchanged=stage_after == before,
                      runtime_sha256_after=sha(DENO),
                      real_lock_sha256_after=sha(ROOT / "supabase/functions/deno.lock"),
                      elapsed_seconds=round(time.monotonic() - start, 3),
                      finished_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        if output.exists():
            shutil.copytree(output, packet / "acceptance")
        report["artifact_sha256"] = {str(p.relative_to(packet)): sha(p)
            for p in sorted(packet.rglob("*")) if p.is_file() and p.name != "canonical-batch.json"}
        if not report["current_root_source_unchanged"] or not report["stage_source_unchanged"] \
                or report["runtime_sha256_before"] != report["runtime_sha256_after"]:
            report.update(status="fail", error="Source or pinned runtime changed during acceptance")
        (packet / "canonical-batch.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "elapsed_seconds": report["elapsed_seconds"],
                      "source_count": len(before), "source_unchanged": report[
                          "current_root_source_unchanged"], "error": report.get("error"),
                      "report": str(packet / "canonical-batch.json")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
