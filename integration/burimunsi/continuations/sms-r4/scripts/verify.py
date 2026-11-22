#!/usr/bin/env python3
"""Reproduce this SMS workstream's host checks. No network, Gradle, Android or carrier execution."""
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
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def input_hashes() -> dict[str, str]:
    files = [p for folder in ("src", "host", "tests", "scripts", "fixtures", "vendor", "provenance")
             for p in (ROOT / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    return {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(files)}

def run(cmd: list[str], out: Path, stem: str, timeout: int = 180) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=timeout,
                            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    (out / f"{stem}.stdout.log").write_text(result.stdout)
    (out / f"{stem}.stderr.log").write_text(result.stderr)
    return result

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", type=Path, required=True, help="A new, nonexistent output directory")
    ap.add_argument("--kotlinc", default=shutil.which("kotlinc") or "")
    ap.add_argument("--java", default=shutil.which("java") or "")
    ap.add_argument("--require-external", action="store_true", help="Return blocked while external acceptance is unexecuted")
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    inputs = input_hashes()
    record = {"schema_version": 1, "scope": "SMS policies R4 authenticated journal and trusted-checkpoint host verification",
        "started_at": dt.datetime.now(dt.timezone.utc).isoformat(), "inputs": inputs,
        "input_set_sha256": hashlib.sha256(json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "suites": [], "external_gates": [
            {"name": n, "status": "blocked", "reason": r} for n, r in [
                ("native_runtime_adapter_wiring", "Shared encrypted-journal adapter is implemented; Android ciphertext transactions, checkpoint service, worker wiring, lifecycle fence and legacy migration are not wired or qualified."),
                ("android_compile_instrumentation", "Not executed by this host-only runner."),
                ("storage_anti_rollback_and_encryption", "AES-GCM and checkpoint coordination pass host tests. No independently rollback-resistant checkpoint backend or Android durable ciphertext port is deployed; joint local rollback remains undetectable."),
                ("carrier_delivery", "No authorized handset/SIM/live carrier observations supplied."),
                ("hosted_ingestion_idempotency", "No deployed service or real database tested."),
                ("actual_collect_checkout_import", "Only temporary repository fixtures used.")]]}
    try:
        provenance = json.loads((ROOT / "vendor/PROVENANCE.json").read_text())
        bad = [x["path"] for x in provenance["files"] if sha(ROOT / x["path"]) != x["sha256"]]
        record["suites"].append({"name": "pinned_dependency_hashes", "status": "passed" if not bad else "failed",
                                 "checks": len(provenance["files"]), "mismatches": bad})
        if bad:
            raise ValueError("Pinned source dependency mismatch")
        tools_ready = True
        for name, value in (("kotlinc", args.kotlinc), ("java", args.java)):
            try:
                if not value:
                    raise FileNotFoundError(name)
                result = run([value, "-version"], out, f"tool-{name}", 30)
                if result.returncode:
                    raise RuntimeError(name)
                record[name] = (result.stdout + result.stderr).strip()
            except (OSError, RuntimeError):
                tools_ready = False
                record[name] = "blocked: prerequisite unavailable"
        py = run([sys.executable, "-m", "unittest", "discover", "-s", "tests/python", "-v"], out, "python")
        match = re.search(r"Ran (\d+) tests?", py.stderr)
        count = int(match.group(1)) if match else 0
        record["suites"].append({"name": "python_tooling", "status": "passed" if py.returncode == 0 and count else "failed",
                                "exit_code": py.returncode, "tests": count})
        bc = sorted((ROOT / "vendor/buri/core").glob("*.kt"))
        mc = sorted((ROOT / "vendor/mmoney/core").glob("*.kt"))
        br = ROOT / "vendor/buri/receiver"
        bt = ROOT / "vendor/buri/tests"
        suites = [
            ("protected_r4", sorted((ROOT / "src").rglob("*.kt")) + bc + mc + sorted((ROOT / "tests/protected").glob("*.kt")),
             "rw.ikanisa.sms.protectedtests.ProtectedChecksKt", []),
            ("persistence_r3", sorted((ROOT / "src").rglob("*.kt")) + sorted((ROOT / "host").rglob("*.kt")) + bc + mc + sorted((ROOT / "tests/persistence").glob("*.kt")),
             "rw.ikanisa.sms.persistence.tests.PersistenceChecksKt", []),
            ("policies_r2", sorted((ROOT / "src").rglob("*.kt")) + bc + mc + sorted((ROOT / "tests/kotlin").glob("*.kt")),
             "rw.ikanisa.sms.policy.tests.PolicyChecksKt", [str(ROOT)]),
            ("buri_core", bc + [bt / "CoreChecks.kt"], "rw.ikanisa.burimunsi.core.CoreChecks", []),
            ("buri_receiver", [br / n for n in ("ReceiptCipher.kt", "ReceiptAckPolicy.kt", "SmsQueueOwnerPolicy.kt", "MomoGatewayPolicy.kt", "MomoMultipartPolicy.kt", "MomoGatewayWakeupGate.kt", "SmsQueueEventBus.kt")] + [bt / "ReceiverChecks.kt"],
             "rw.ikanisa.burimunsi.receiverchecks.ReceiverChecksKt", []),
            ("buri_reliability", [br / n for n in ("ReceiptCipher.kt", "ReceiptAckPolicy.kt", "BuriQueueFile.kt", "BuriReceiverReliability.kt")] + [bt / "ReliabilityChecks.kt"],
             "app.cool.mobile.receiver_sms.ReliabilityChecksKt", []),
            ("mmoney_sms", mc + sorted((ROOT / "vendor/mmoney/platform").glob("*.kt")) + sorted((ROOT / "vendor/mmoney/data").glob("*.kt")) + sorted((ROOT / "vendor/mmoney/tests").glob("*.kt")),
             "SmsReliabilityProbeKt", [])]
        with tempfile.TemporaryDirectory(prefix="sms-policy-verify-") as tmp:
            for name, sources, main_class, argv in suites:
                row = {"name": name, "status": "blocked", "inputs": [p.relative_to(ROOT).as_posix() for p in sources]}
                record["suites"].append(row)
                if name == "persistence_r3" and os.name != "posix":
                    row["reason"] = "POSIX host filesystem required; Android is not substituted"
                    continue
                if not tools_ready:
                    row["reason"] = "Kotlin compiler or Java runtime missing"
                    continue
                # R1 prepares this tombstone guard deterministically; do not compile its raw upstream input.
                sources = [ROOT / "vendor/buri/effective/ReceiptAckPolicy.kt" if p == br / "ReceiptAckPolicy.kt" else p for p in sources]
                row["inputs"] = [p.relative_to(ROOT).as_posix() for p in sources]
                jar = Path(tmp) / (name + ".jar")
                build_cmd = [args.kotlinc, *map(str, sources), "-jvm-target", "17", "-include-runtime", "-d", str(jar)]
                build = run(build_cmd, out, name + ".compile")
                row["compile_exit_code"] = build.returncode
                if build.returncode:
                    row["status"] = "failed"
                    continue
                row["jar_sha256"] = sha(jar)
                executed = run([args.java, "-Xmx512m", "-cp", str(jar), main_class, *argv], out, name)
                row["exit_code"] = executed.returncode
                row["status"] = "failed"
                if executed.returncode == 0:
                    if executed.stdout.lstrip().startswith("{"):
                        details = json.loads(executed.stdout)
                        if details.get("status") == "passed":
                            row["status"] = "passed"
                            row.update({key: details[key] for key in ("tests", "checks", "assertions", "failed", "model_events", "malformed_inputs", "child_processes") if key in details})
                            (out / (name + ".json")).write_text(json.dumps(details, indent=2) + "\n")
                    else:
                        plan = re.findall(r"^1\.\.(\d+)\s*$", executed.stdout, re.M)
                        passed = re.findall(r"^ok \d+ -", executed.stdout, re.M)
                        if len(plan) == 1 and int(plan[0]) == len(passed) and len(passed) > 0:
                            row.update(status="passed", checks=len(passed))
                print(f"{name}: {row['status']}", flush=True)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        record["runner_error"] = str(error)
    finally:
        current = input_hashes()
        record["inputs_unchanged"] = current == inputs
        statuses = [s["status"] for s in record["suites"]]
        record["local_status"] = ("failed" if "failed" in statuses or "runner_error" in record or not record["inputs_unchanged"]
                                  else "blocked" if "blocked" in statuses else "passed")
        record["external_acceptance"] = "blocked"
        record["finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        record["exit_code"] = 1 if record["local_status"] == "failed" else 2 if record["local_status"] == "blocked" or args.require_external else 0
        (out / "verification.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({"local_status": record["local_status"], "external_acceptance": "blocked", "summary": str(out / "verification.json")}))
    return record["exit_code"]

if __name__ == "__main__":
    raise SystemExit(main())
