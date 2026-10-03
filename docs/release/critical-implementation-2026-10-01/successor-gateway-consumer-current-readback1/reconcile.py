#!/usr/bin/env python3
"""Read-only current reconciliation; writes only this new readback directory."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
PACKET = OUT.parent / "successor-gateway-consumer-preparation1"
PIN = "252b1e0310597fc36dc25ed7f41416ad47412ac66d68d6e64778bbad019957fd"
QA_NAME = "scripts/qa/edge_http_runtime_uat.ts"
QA_SHA = "1896e5b1fe1d21a9f0a883ad2222a7fdf5d0594b90bb0edd3c064c7fc32921c7"
errors = []

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def identity(st):
    return [st.st_dev, st.st_ino, stat.S_IMODE(st.st_mode), st.st_size,
            st.st_mtime_ns, st.st_ctime_ns, st.st_nlink]

def read(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError(f"symlink refused: {path}")
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError(f"not a unique regular file: {path}")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        opened = os.fstat(fd)
        assert identity(before) == identity(opened), path
        with os.fdopen(fd, "rb", closefd=False) as handle:
            raw = handle.read()
        assert identity(opened) == identity(os.fstat(fd)), path
    finally:
        os.close(fd)
    assert identity(before) == identity(path.lstat()), path
    return raw, {"sha256": sha(raw), "bytes": len(raw), "mode": stat.S_IMODE(before.st_mode),
                 "identity": identity(before)}

def dump(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def observe_inputs(before):
    result = {}
    for name in before:
        try:
            result[name] = read(ROOT / name)[1]
        except (OSError, AssertionError, ValueError) as error:
            result[name] = {"error": str(error)}
    return result

def run(name, command, deadline):
    cmd = ["/usr/bin/sandbox-exec", "-p", "(version 1) (allow default) (deny network*)"] + command
    started = time.monotonic()
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=deadline)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            stdout, stderr = proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
    logs = {}
    for label, raw in (("stdout", stdout), ("stderr", stderr)):
        filename = name + "." + label
        (OUT / filename).write_bytes(raw)
        logs[label] = {"path": str(OUT / filename), "sha256": sha(raw), "bytes": len(raw)}
    return {"command": cmd, "cwd": str(ROOT), "deadline_seconds": deadline,
            "elapsed_seconds": time.monotonic() - started, "exit_code": proc.returncode,
            "timed_out": timed_out, "logs": logs}

def main():
    raw, _ = read(PACKET / "batch.json")
    assert sha(raw) == PIN, "sealed packet identity changed"
    batch = json.loads(raw)
    artifacts = {}
    for name, expected in batch["artifacts"].items():
        raw, facts = read(PACKET / name)
        assert all(facts[k] == expected[k] for k in ("sha256", "bytes", "mode")), name
        artifacts[name] = {k: facts[k] for k in ("sha256", "bytes", "mode")}
    assert len(artifacts) == batch["artifact_count"] == 814
    rows = (PACKET / "SHA256SUMS").read_text().splitlines()
    checked_names = set()
    for row in rows:
        digest, name = row.split("  ", 1)
        assert name not in checked_names, name
        checked_names.add(name)
        assert read(PACKET / name)[1]["sha256"] == digest, name
    assert len(rows) == 815 and checked_names == set(artifacts) | {"batch.json"}
    actual = {str(p.relative_to(PACKET)) for p in PACKET.rglob("*") if p.is_file() or p.is_symlink()}
    assert actual == set(artifacts) | {"batch.json", "SHA256SUMS"}
    dump("packet-artifact-readback.json", {"packet": str(PACKET), "batch_sha256": PIN,
                                           "artifacts_verified": len(artifacts), "checksums_verified": len(rows),
                                           "artifacts": artifacts})

    inputs = json.loads(read(PACKET / "source-before.json")[0])
    assert len(inputs) == 385
    current = observe_inputs(inputs)
    dump("maintained-inputs-current-before-commands.json", current)
    changes = json.loads(read(PACKET / "verification.json")[0])["changed_files"]
    consumers = {}
    for name, row in changes.items():
        candidate = PACKET / "candidate/source" / name
        facts = read(candidate)[1]
        assert facts["sha256"] == row["candidate"]["sha256"] and facts["bytes"] == row["candidate"]["bytes"], name
        base_matches = all(current[name].get(k) == row["before"][k] for k in ("sha256", "bytes", "mode"))
        consumers[name] = {"candidate_path": str(candidate), "maintained_path": str(ROOT / name),
                           "base_sha256": row["before"]["sha256"], "candidate_sha256": facts["sha256"],
                           "current": current[name], "current_base_matches": base_matches}
        if not base_matches:
            errors.append("maintained consumer base changed: " + name)
    assert len(consumers) == 5
    dump("five-consumer-readback.json", consumers)

    checks = json.loads(read(PACKET / "candidate-checks/results.json")[0])["results"]
    assert all(row["exit_code"] == 0 and not row["timed_out"] for row in checks.values())
    for row in checks.values():
        for log in row["logs"].values():
            raw, facts = read(PACKET / log["path"])
            assert facts["sha256"] == log["sha256"] and facts["bytes"] == log["bytes"]
    python_log = read(PACKET / checks["python-delivery-tests"]["logs"]["stderr"]["path"])[0].decode()
    assert len(re.findall(r"^test_.* \.\.\. ok$", python_log, re.M)) == 34
    assert re.search(r"Ran 34 tests in [0-9.]+s\s+OK\s*\Z", python_log)
    corrected = json.loads(read(PACKET / "candidate-corrected-ruby-check/results.json")[0])["result"]
    assert corrected["exit_code"] == 0 and not corrected["timed_out"]
    ruby_path = Path(corrected["logs"]["stdout"]["path"])
    if not ruby_path.is_absolute():
        ruby_path = PACKET / ruby_path
    ruby_log = read(ruby_path)[0].decode()
    assert "17 runs, 173 assertions, 0 failures, 0 errors, 0 skips" in ruby_log
    dump("actual-private-results-readback.json", {
        "source": "sealed original completed logs, not a new suite run",
        "ruby": {"cases": 17, "assertions": 173, "failures": 0, "errors": 0, "skips": 0,
                 "elapsed_seconds": corrected["elapsed_seconds"], "deadline_seconds": corrected["deadline_seconds"]},
        "python": {"cases": 34, "failures": 0, "errors": 0, "skips": 0,
                   "elapsed_seconds": checks["python-delivery-tests"]["elapsed_seconds"],
                   "deadline_seconds": checks["python-delivery-tests"]["deadline_seconds"]},
        "whole_python_suite_rerun": False,
    })

    commands = {
        "current-ruby-inventory-tests": (["/usr/bin/ruby", "scripts/tests/edge_function_inventory_test.rb"], 180),
        "current-inventory-auth-check": (["/usr/bin/ruby", "scripts/edge_function_inventory.rb", "auth-check"], 20),
        "current-readiness-shell-syntax": (["/bin/bash", "-n", "scripts/supabase_production_readiness.sh"], 20),
    }
    results = {name: run(name, cmd, deadline) for name, (cmd, deadline) in commands.items()}
    dump("bounded-current-checks.json", results)
    after = observe_inputs(inputs)
    dump("maintained-inputs-current-after-commands.json", after)
    command_drift = {name: {"before": current[name], "after": after[name]} for name in inputs if current[name] != after[name]}
    drift = {name: {"source_before": inputs[name], "current": after[name]} for name in inputs if inputs[name] != after[name]}
    intentional = {}
    other = dict(drift)
    if QA_NAME in drift and after[QA_NAME].get("sha256") == QA_SHA:
        intentional[QA_NAME] = other.pop(QA_NAME)
    elif after[QA_NAME].get("sha256") != QA_SHA:
        errors.append("root QA fixture change does not match authorized SHA")
    if command_drift:
        errors.append("source inputs changed during read-only commands")
    if other:
        errors.append("additional source drift requires separate reconciliation")
    dump("current-drift-classification.json", {"intentional_root_QA_fixture_change": intentional,
                                               "other_drift": other, "during_command_drift": command_drift})
    summary = {
        "observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "status": "read_only_current_reconciliation_complete" if not errors else "read_only_reconciliation_found_drift",
        "original_packet": str(PACKET), "original_batch_sha256": PIN,
        "verified_artifacts": 814, "verified_checksums": 815,
        "keyed_maintained_inputs": len(inputs), "five_base_hashes_match": all(v["current_base_matches"] for v in consumers.values()),
        "candidate_paths": {name: row["candidate_path"] for name, row in consumers.items()},
        "intentional_QA_drift_count": len(intentional), "other_drift_count": len(other),
        "command_source_drift_count": len(command_drift), "errors": errors,
        "private_recorded_tests": {"ruby_cases": 17, "ruby_assertions": 173, "python_cases": 34,
                                   "failures": 0, "errors": 0, "skips": 0},
        "actual_current_checks": {name: {"exit_code": row["exit_code"], "deadline_seconds": row["deadline_seconds"],
                                         "timed_out": row["timed_out"]} for name, row in results.items()},
        "current_inventory_failure_expected_until_consumer_promotion": True,
        "maintained_source_writes": 0, "original_packet_writes": 0,
        "whole_python_suite_rerun": False, "handler_SQL_native_execution": False,
        "external_operations": False, "shared_source_promotion": False,
    }
    dump("readback.json", summary)
    artifacts_new = {}
    for path in sorted(OUT.rglob("*")):
        if path.is_file():
            _, facts = read(path)
            artifacts_new[str(path.relative_to(OUT))] = {k: facts[k] for k in ("sha256", "bytes", "mode")}
    dump("batch.json", {"status": summary["status"], "artifact_count": len(artifacts_new), "artifacts": artifacts_new})
    rows_new = {name: row["sha256"] for name, row in artifacts_new.items()}
    rows_new["batch.json"] = sha((OUT / "batch.json").read_bytes())
    (OUT / "SHA256SUMS").write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(rows_new.items())))
    print(json.dumps({"artifacts": 814, "checksums": 815, "bases_match": summary["five_base_hashes_match"],
                      "intentional_drift": len(intentional), "other_drift": len(other), "errors": errors,
                      "current_checks": summary["actual_current_checks"], "readback_batch_sha256": rows_new["batch.json"]}))

if __name__ == "__main__":
    main()
