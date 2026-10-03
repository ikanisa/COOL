#!/usr/bin/env python3
"""Bounded offline proof runner; writes only its own new proof directory."""
from pathlib import Path
import ast
import datetime as dt
import hashlib
import json
import os
import signal
import stat
import subprocess
import sys
import time

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(__file__).resolve().parent
PRIOR = ROOT / "docs/release/critical-implementation-2026-10-01/postgres-admission-preparation1"
REVIEW = OUT.parent / "current-source-after-review-corrections.json"
PYTHON = Path("/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def identity(path):
    s = path.lstat()
    if not stat.S_ISREG(s.st_mode) or path.is_symlink():
        raise RuntimeError("non-regular proof input: " + str(path))
    return {"bytes": s.st_size, "device": s.st_dev, "inode": s.st_ino,
            "links": s.st_nlink, "mode": stat.S_IMODE(s.st_mode),
            "mtime_ns": s.st_mtime_ns, "sha256": sha(path.read_bytes())}


def input_names():
    names = set(json.loads((PRIOR / "source-before.json").read_text())["inputs"])
    names.update(json.loads(REVIEW.read_text())["after_sha256"])
    for directory in ("contracts", "supabase/functions", "supabase/migrations"):
        for p in (ROOT / directory).rglob("*"):
            if p.is_file() or p.is_symlink():
                names.add(str(p.relative_to(ROOT)))
    return sorted(names)


def snapshot():
    return {name: identity(ROOT / name) for name in input_names()}


def methods(path):
    tree = ast.parse(path.read_text())
    return {n.name: ast.dump(n, include_attributes=False) for cls in tree.body
            if isinstance(cls, ast.ClassDef) for n in cls.body
            if isinstance(n, ast.FunctionDef) and n.name.startswith("test_")}


def qa_commands(path):
    lines = path.read_text().splitlines()
    i = lines.index("qa-tooling-test:") + 1
    result = []
    while i < len(lines) and lines[i].startswith("\t"):
        result.append(lines[i].lstrip("\t@"))
        i += 1
    return result


def semantic_binding():
    relative = "scripts/tests/supabase_delivery_contract_test.py"
    current = methods(ROOT / relative)
    candidate = methods(PRIOR / "candidate3" / relative)
    original = methods(PRIOR / "baseline" / relative)
    pre = methods(OUT.parent / "delivery-fixture-before-correction.py")
    result = {"actual_current_test_method_count": len(current),
              "original_method_count": len(original),
              "all_45_method_asts_equal_candidate3": current == candidate,
              "all_45_method_asts_equal_pre_shebang_correction": current == pre,
              "all_34_original_method_asts_preserved": all(current.get(k) == v for k, v in original.items()),
              "method_ast_sha256": {k: sha(v.encode()) for k, v in current.items()},
              "original_baseline_test_sha256": identity(PRIOR / "baseline" / relative)["sha256"],
              "candidate3_test_sha256": identity(PRIOR / "candidate3" / relative)["sha256"],
              "before_shebang_test_sha256": identity(OUT.parent / "delivery-fixture-before-correction.py")["sha256"],
              "current_test_identity": identity(ROOT / relative),
              "changed_fixture_context": "absolute sys.executable synthetic psql shebang only versus candidate3; new admission context versus original baseline is not claimed runtime-identical",
              "unchanged_manifest_timeouts_seconds": {"version": 1, "server": 3, "operation": 10}}
    production = ("scripts/qa/postgres_admission.py", "scripts/qa/backend_release_delivery.py",
                  "scripts/supabase_cli_helpers.sh", "scripts/supabase_production_readiness.sh")
    result["production_bytes_equal_candidate3"] = {
        name: (ROOT / name).read_bytes() == (PRIOR / "candidate3" / name).read_bytes() for name in production}
    old = qa_commands(PRIOR / "baseline/Makefile")
    new = qa_commands(ROOT / "Makefile")
    result["qa_commands"] = new
    result["qa_command_count"] = len(new)
    result["original_29_commands_retained_in_order"] = new[2:] == old
    result["first_two_new_commands"] = new[:2]
    result["root_review_hashes"] = json.loads(REVIEW.read_text())["after_sha256"]
    result["root_review_receipt_identity"] = identity(REVIEW)
    assert len(current) == 45 and len(original) == 34
    assert result["all_45_method_asts_equal_candidate3"]
    assert result["all_45_method_asts_equal_pre_shebang_correction"]
    assert result["all_34_original_method_asts_preserved"]
    assert all(result["production_bytes_equal_candidate3"].values())
    assert result["original_29_commands_retained_in_order"]
    assert new[:2] == ["python3 scripts/tests/test_postgres_admission.py",
                       "python3 scripts/tests/collect_schema_domain_map_test.py"]
    return result


def group_exists(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False


def stop_group(proc):
    if group_exists(proc.pid):
        os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    if group_exists(proc.pid):
        os.killpg(proc.pid, signal.SIGKILL)
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass


def run(name, command, deadline, env):
    start = time.monotonic()
    stdout = OUT / (name + ".stdout")
    stderr = OUT / (name + ".stderr")
    reason = None
    with stdout.open("wb") as out, stderr.open("wb") as err:
        proc = subprocess.Popen(command, cwd=ROOT, env=env, stdout=out, stderr=err,
                                start_new_session=True)
        print(json.dumps({"started": name, "pid": proc.pid, "deadline_seconds": deadline}), flush=True)
        while proc.poll() is None:
            if time.monotonic() - start > deadline:
                reason = "deadline"
                stop_group(proc)
                break
            if stdout.stat().st_size + stderr.stat().st_size > 4 * 1024 * 1024:
                reason = "output_limit"
                stop_group(proc)
                break
            time.sleep(0.05)
        proc.wait(timeout=3)
    residual = group_exists(proc.pid)
    if residual:
        stop_group(proc)
    until = time.monotonic() + 5
    while group_exists(proc.pid) and time.monotonic() < until:
        time.sleep(0.05)
    result = {"command": command, "cwd": str(ROOT), "pid": proc.pid, "pgid": proc.pid,
              "exit_code": proc.returncode, "elapsed_seconds": round(time.monotonic() - start, 3),
              "timeout_seconds": deadline, "output_limit_bytes": 4 * 1024 * 1024,
              "termination_reason": reason, "residual_group_on_leader_completion": residual,
              "process_group_absent": not group_exists(proc.pid),
              "stdout": identity(stdout), "stderr": identity(stderr)}
    write(name + ".json", result)
    print(json.dumps({"completed": name, "exit_code": proc.returncode,
                      "elapsed_seconds": result["elapsed_seconds"],
                      "process_group_absent": result["process_group_absent"]}), flush=True)
    return result


if __name__ == "__main__":
    if (OUT / "inputs-before.json").exists():
        raise SystemExit("Refuse proof overwrite")
    before = snapshot()
    reviewed = json.loads(REVIEW.read_text())["after_sha256"]
    mismatch = [name for name, digest in reviewed.items() if before[name]["sha256"] != digest]
    assert not mismatch, mismatch
    write("inputs-before.json", {"at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                                 "reviewed_12_inputs": {name: before[name] for name in reviewed},
                                 "all_transitive_inputs": before})
    semantics = semantic_binding()
    write("test-semantic-binding.json", semantics)
    env = {"PATH": str(PYTHON.parent) + os.pathsep + os.defpath,
           "LC_ALL": "C", "LANG": "C", "PYTHONDONTWRITEBYTECODE": "1",
           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "TMPDIR": "/private/tmp"}
    write("execution-inputs.json", {"python": identity(PYTHON), "python_path": str(PYTHON),
                                   "python_runtime_version": sys.version,
                                   "environment": env, "inherited_environment": False,
                                   "credential_environment": False,
                                   "real_provider_sql_docker_download": False,
                                   "cohort_script": identity(OUT / "consumer-cohort.py"),
                                   "additional_script": identity(OUT / "additional-ordering.py"),
                                   "runner": identity(Path(__file__)),
                                   "before_snapshot_sha256": sha((OUT / "inputs-before.json").read_bytes())})
    results = []
    results.append(run("make-dry-run", ["/usr/bin/make", "-n", "qa-tooling-test"], 15, env))
    assert results[-1]["exit_code"] == 0
    assert (OUT / "make-dry-run.stdout").read_text().splitlines() == semantics["qa_commands"]
    results.append(run("maintained-consumers27", [str(PYTHON), "-I", "-B", str(OUT / "consumer-cohort.py"), str(ROOT)], 900, env))
    results.append(run("maintained-ordering4", [str(PYTHON), "-I", "-B", str(OUT / "additional-ordering.py"), str(ROOT)], 350, env))
    after = snapshot()
    changes = [name for name in sorted(set(before) | set(after)) if before.get(name) != after.get(name)]
    write("inputs-after.json", {"at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                                "reviewed_12_inputs": {name: after[name] for name in reviewed},
                                "all_transitive_inputs": after, "full_identity_changes": changes})
    write("completed-results.json", {"results": results, "source_identity_changes": changes,
                                      "all_transitive_count": len(before),
                                      "reviewed_input_count": len(reviewed),
                                      "all_commands_completed": all(r["termination_reason"] is None for r in results),
                                      "all_process_groups_absent": all(r["process_group_absent"] for r in results),
                                      "all_exit_codes_zero": all(r["exit_code"] == 0 for r in results),
                                      "source_identity_unchanged": not changes,
                                      "scope": "maintained offline consumers; no real approval/provider/database/release acceptance"})
    raise SystemExit(0 if not changes and all(r["exit_code"] == 0 and r["termination_reason"] is None and r["process_group_absent"] for r in results) else 1)
