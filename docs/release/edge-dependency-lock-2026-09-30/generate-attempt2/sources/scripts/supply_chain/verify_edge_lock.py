#!/usr/bin/env python3
"""Generate or verify the exact cached Edge closure without executing entrypoints.

Generation is explicit and only creates a missing production lock. Verification
uses the frozen lock, cached-only compiler, all real entrypoints/tests and the
HTTP harness. New evidence directories and actual exit codes are mandatory.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "supabase/functions/deno.lock"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deno", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh release evidence directory required")
    if args.generate and LOCK.exists():
        parser.error("Preserve existing production lock; generation cannot overwrite it")
    if not args.generate and not LOCK.is_file():
        parser.error("Production dependency lock missing")
    output.mkdir(parents=True, mode=0o700)
    binary = args.deno.resolve()
    report = dict(status="fail", started_at=dt.datetime.now(dt.timezone.utc).isoformat(),
                  entrypoints_executed=False, provider_calls=0, database_calls=0, runs=[])
    paths = sorted((ROOT / "supabase/functions").rglob("*.ts")) + [
        ROOT / ".dvmrc", Path(__file__).resolve(), ROOT / "scripts/qa/edge_http_runtime_uat.ts"]
    sources = {str(p.relative_to(ROOT)): digest(p) for p in paths}
    report["source_before"] = sources
    for path in paths:
        copy = output / "sources" / path.relative_to(ROOT)
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, copy)
    try:
        info = json.loads(subprocess.check_output([str(binary), "info", "--json"], text=True, timeout=10))
        if info["denoVersion"] != (ROOT / ".dvmrc").read_text().strip():
            raise RuntimeError("Exact project Deno pin required")
        report["runtime"] = dict(path=str(binary), sha256=digest(binary), version=info["denoVersion"])
        env = dict(PATH=os.defpath, DENO_DIR=info["denoDir"], NO_COLOR="1", DENO_NO_UPDATE_CHECK="1")
        inputs = [str(p.relative_to(ROOT)) for p in paths if p.suffix == ".ts" and
                  (p.name in ("index.ts", "handler_test.ts", "edge_http_runtime_uat.ts") or p.name.endswith("_test.ts"))]
        report["compile_inputs"] = inputs
        candidate = output / "generated.lock" if args.generate else LOCK

        def run(name, target, frozen=True):
            command = [str(binary), "test", "--no-run", "--no-config", "--cached-only",
                       "--no-prompt", "--frozen" if frozen else "--frozen=false",
                       "--lock=" + str(target), *inputs]
            completed = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=60)
            for stream in ("stdout", "stderr"):
                (output / (name + "." + stream)).write_bytes(getattr(completed, stream))
            report["runs"].append(dict(name=name, command=command, exit_code=completed.returncode,
                                       stdout_sha256=digest(output / (name + ".stdout")),
                                       stderr_sha256=digest(output / (name + ".stderr"))))
            return completed.returncode

        if args.generate and run("generate-cached-closure", candidate, False):
            raise RuntimeError("Cached closure generation failed")
        before = digest(candidate)
        if run("frozen-cached-compile", candidate):
            raise RuntimeError("Frozen cached-only compiler failed")
        if digest(candidate) != before:
            raise RuntimeError("Frozen compiler changed dependency lock")
        lock = json.loads(candidate.read_text())
        if not lock.get("remote") or not lock.get("npm"):
            raise RuntimeError("Nonempty complete remote and npm dependency lock required")
        # Actual compiler denial, rather than an implementation-mirroring assertion.
        corrupt = json.loads(candidate.read_text())
        corrupt["remote"] = {name: "0" * 64 for name in corrupt["remote"]}
        tampered = output / "tampered.lock"
        tampered.write_text(json.dumps(corrupt) + "\n")
        if run("tampered-lock-denied", tampered) == 0:
            raise RuntimeError("Compiler accepted corrupted dependency integrities")
        if args.generate:
            if LOCK.exists():
                raise RuntimeError("Another worker created production lock; preserve both candidates")
            LOCK.write_bytes(candidate.read_bytes())
        report.update(status="pass", lock_sha256=digest(LOCK),
                      remote_modules=len(lock["remote"]), npm_packages=len(lock["npm"]),
                      frozen_compile=True, corrupted_integrities_denied=True)
        shutil.copyfile(LOCK, output / "verified.lock")
    except Exception as error:
        report["error"] = str(error)
    finally:
        report["source_after"] = {str(p.relative_to(ROOT)): digest(p) for p in paths}
        if sources != report["source_after"]:
            report.update(status="fail", error="Source changed during closure verification")
        report["finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report.get(key) for key in
                      ("status", "error", "remote_modules", "npm_packages", "lock_sha256")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
