#!/usr/bin/env python3
"""Bounded offline consumer tests; preserves original failures and exact logs."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

PACKET = Path(__file__).resolve().parent
PYTHON = "/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3"
SANDBOX = ["/usr/bin/sandbox-exec", "-p", "(version 1) (allow default) (deny network*)"]

def run(name, command, cwd, output, deadline):
    started = time.monotonic()
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    proc = subprocess.Popen(SANDBOX + command, cwd=cwd, env=env, stdout=subprocess.PIPE,
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
    paths = {}
    for label, raw in (("stdout", stdout), ("stderr", stderr)):
        path = output / (name + "." + label)
        path.write_bytes(raw)
        paths[label] = {"path": str(path.relative_to(PACKET)), "bytes": len(raw),
                        "sha256": hashlib.sha256(raw).hexdigest()}
    result = {"command": SANDBOX + command, "cwd": str(cwd), "deadline_seconds": deadline,
              "elapsed_seconds": time.monotonic() - started, "exit_code": proc.returncode,
              "timed_out": timed_out, "owned_process_pid": proc.pid, "logs": paths}
    print(json.dumps({"case": name, "exit_code": proc.returncode,
                      "seconds": result["elapsed_seconds"], "timeout": timed_out}), flush=True)
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["baseline", "candidate"])
    args = parser.parse_args()
    source = PACKET / args.stage / "source"
    output = PACKET / (args.stage + "-checks")
    output.mkdir()
    results = {}
    commands = {
        "ruby-inventory-tests": (["/usr/bin/ruby", "scripts/tests/edge_function_inventory_test.rb"], 180),
        "python-delivery-tests": ([PYTHON, "-B", "scripts/tests/supabase_delivery_contract_test.py", "-v"], 300),
        "inventory-auth-check": (["/usr/bin/ruby", "scripts/edge_function_inventory.rb", "auth-check"], 20),
        "readiness-shell-syntax": (["/bin/bash", "-n", "scripts/supabase_production_readiness.sh"], 20),
        "network-denial-probe": ([PYTHON, "-B", "-c", "import socket; s=socket.socket();\ntry: s.connect(('127.0.0.1', 9))\nexcept PermissionError as e: print(type(e).__name__, e); raise SystemExit(0)\nexcept Exception as e: print(type(e).__name__, e); raise SystemExit(1)\nraise SystemExit(2)"], 20),
    }
    for name, (command, deadline) in commands.items():
        results[name] = run(name, command, source, output, deadline)
    (output / "results.json").write_text(json.dumps({
        "observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "stage": args.stage,
        "results": results, "actual_handler_or_sql_tests": False,
        "provider_or_hosted_operations": False,
        "network_policy": "OS deny network for owned command tree; CLI/curl/Deno transports remain synthetic",
    }, indent=2, sort_keys=True) + "\n")

if __name__ == "__main__":
    main()
