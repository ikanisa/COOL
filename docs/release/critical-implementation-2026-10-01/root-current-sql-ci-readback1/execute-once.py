from __future__ import annotations
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
OUTPUT = ROOT / ".cache/root-current-sql-ci-execution1"
DOCKER = Path("/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker")
HOST = "unix:///Users/jeanbosco/.docker/run/docker.sock"
FIXTURE = "062f1f21d8ab847b4c94db4e4c86dc84af668157904e341e92bd9e6385c5f04d"
SOURCE = ROOT / "scripts/qa/run_sql_ci.py"
AUTHORITY = ROOT / "docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/execution-result.json"

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            h.update(block)
    return h.hexdigest()

def write(name, obj):
    with (PACKET / name).open("x") as stream:
        json.dump(obj, stream, indent=2)
        stream.write("\n")

def absent(pid):
    try:
        os.killpg(pid, 0)
        return False
    except ProcessLookupError:
        return True

assert ".".join(map(str, sys.version_info[:3])) == "3.12.14"
assert not OUTPUT.exists()
spec = importlib.util.spec_from_file_location("owned_sql_ci", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
before = module.source_inventory(ROOT)
assert len(before) == 219
original = json.loads(AUTHORITY.read_text())["source_after"]
assert len(original) == 216
original_before = {rel: sha(ROOT / rel) for rel in original}
assert original_before == original
cli = DOCKER.resolve(strict=True)
assert cli == DOCKER and not DOCKER.is_symlink()
docker_pin = sha(cli)
env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
       "PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8", "PYTHONDONTWRITEBYTECODE": "1"}
argv = [sys.executable, "-I", "-B", str(SOURCE), "--docker", str(cli),
        "--docker-sha256", docker_pin, "--docker-host", HOST,
        "--fixture-lock-sha256", FIXTURE, "--output", str(OUTPUT)]
write("execution-inputs.json", {"argv": argv, "environment": env, "source219_before": before,
      "original216_before": original_before, "original216_authority_sha256": sha(AUTHORITY),
      "tooling": {"python": sys.version, "python_executable": sys.executable,
                  "python_physical": str(Path(sys.executable).resolve()),
                  "python_sha256": sha(Path(sys.executable).resolve()),
                  "docker_physical": str(cli), "docker_sha256": docker_pin},
      "launcher_sha256": sha(Path(__file__)), "bound_seconds": 650,
      "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
      "scope": "One maintained local synthetic SQL recipe execution; no acquisition/provider/network/APP/SDK/source writes"})
start = time.monotonic()
deadline = start + 650
limit = 64 * 1024**2
stdout = PACKET / "launcher.stdout"
stderr = PACKET / "launcher.stderr"
timed_out = overflow = residual = False
with stdout.open("xb") as out, stderr.open("xb") as err:
    child = subprocess.Popen(argv, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                             stdout=out, stderr=err, start_new_session=True)
    write("active-process.json", {"pid": child.pid, "pgid": child.pid, "bound_seconds": 650,
          "observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "status": "running"})
    try:
        while child.poll() is None:
            timed_out = time.monotonic() >= deadline
            overflow = stdout.stat().st_size + stderr.stat().st_size > limit
            if timed_out or overflow:
                break
            time.sleep(.1)
        timed_out = timed_out or time.monotonic() >= deadline
        residual = child.poll() is not None and not absent(child.pid)
    finally:
        if child.poll() is None or not absent(child.pid):
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        child.wait(timeout=5)
    observe = time.monotonic() + 5
    group_absent = False
    permission_refusals = 0
    while time.monotonic() < observe:
        try:
            group_absent = absent(child.pid)
        except PermissionError:
            permission_refusals += 1
        if group_absent:
            break
        time.sleep(.02)
    overflow = overflow or stdout.stat().st_size + stderr.stat().st_size > limit
source_after = module.source_inventory(ROOT)
original_after = {rel: sha(ROOT / rel) for rel in original}
result = {"argv": argv, "pid": child.pid, "pgid": child.pid, "exit_code": child.returncode,
          "bound_seconds": 650, "elapsed_seconds": time.monotonic() - start,
          "timed_out": timed_out, "output_overflow": overflow,
          "residual_group_required_stop": residual, "owned_process_group_absent": group_absent,
          "post_stop_permission_refusals": permission_refusals,
          "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr),
          "source219_after": source_after, "source219_unchanged": before == source_after,
          "original216_after": original_after, "original216_unchanged": original == original_after,
          "completed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
          "pass": child.returncode == 0 and not timed_out and not overflow and not residual and group_absent
                  and before == source_after and original == original_after}
write("launcher-result.json", result)
print(json.dumps({k: result[k] for k in ("exit_code", "elapsed_seconds", "timed_out", "owned_process_group_absent", "source219_unchanged", "original216_unchanged", "pass")}))
sys.exit(0 if result["pass"] else 1)
