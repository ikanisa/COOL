#!/usr/bin/env python3
"""Local synthetic checks only. No credentials, network install or profile writes."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
BRIDGE = ROOT / "tools/collect-notification-mcp"
PACKET = Path(__file__).resolve().parent
NODE = Path("/Volumes/PRO-G40/Development/Node/bin/node")
COMPILER = BRIDGE / "node_modules/.pnpm/typescript@7.0.2/node_modules/typescript/bin/tsc"

def utc():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_binding():
    paths = set((BRIDGE / "src").rglob("*"))
    paths.update(BRIDGE / name for name in ("package.json", "pnpm-lock.yaml", "tsconfig.json"))
    paths.update((ROOT / "contracts").glob("collect-shadow-supervisor-v1*"))
    paths.update((ROOT / "supabase/functions/collect-receipt-supervisor").rglob("*"))
    paths.add(ROOT / "supabase/migrations/20261001000400_receipt_supervisor_identity.sql")
    return {str(p.relative_to(ROOT)): {"sha256": sha(p), "bytes": p.stat().st_size}
            for p in sorted(paths) if p.is_file()}

def main():
    before = source_binding()
    node_hash, compiler_hash = sha(NODE), sha(COMPILER)
    (PACKET / "combined-source-before.json").write_text(json.dumps({
        "checked_at_utc": utc(), "source_files": before, "node_sha256": node_hash,
        "compiler_sha256": compiler_hash, "runner_sha256": sha(Path(__file__))
    }, indent=2, sort_keys=True) + "\n")
    node_version = subprocess.run([str(NODE), "--version"], capture_output=True,
                                  text=True, check=True, env={}).stdout.strip()
    tests = sorted((BRIDGE / "src").glob("*.test.ts"))
    with tempfile.TemporaryDirectory(prefix="collect-mcp-synthetic-home-") as home:
        environment = {"HOME": home, "PATH": str(NODE.parent) + ":/usr/bin:/bin",
                       "TMPDIR": home, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
                       "CI": "true", "COREPACK_ENABLE_NETWORK": "0"}
        def run(name, command):
            started = utc()
            completed = subprocess.run(command, cwd=BRIDGE, env=environment,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       timeout=120, check=False)
            log = PACKET / (name + ".log")
            log.write_bytes(completed.stdout)
            receipt = {"command": command, "cwd": str(BRIDGE), "exit_code": completed.returncode,
                       "started_at_utc": started, "finished_at_utc": utc(),
                       "log_sha256": sha(log), "node_version": node_version,
                       "node_sha256": node_hash, "compiler_sha256": compiler_hash,
                       "runner_sha256": sha(Path(__file__)), "credential_free_environment": True,
                       "actual_endpoint_calls": 0, "keychain_calls": 0, "provider_sends": 0,
                       "real_key_or_profile_created": False, "host_allowlist_changed": False,
                       "dependency_install_requested": False}
            (PACKET / (name + ".command.json")).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
            if name == "combined-current-tests":
                text = completed.stdout.decode("utf-8", errors="replace")
                receipt["test_file_count"] = len(tests)
                receipt["test_counts"] = {key: int(re.search(r"^# " + key + r" (\d+)$", text, re.M).group(1))
                                          for key in ("tests", "pass", "fail", "cancelled", "skipped", "todo")}
            return name, receipt
        jobs = [("combined-current-typescript", [str(NODE), str(COMPILER), "--noEmit"]),
                ("combined-current-tests", [str(NODE), "--experimental-strip-types", "--test", "--test-reporter=tap", "--test-concurrency=2"] +
                 [str(p.relative_to(BRIDGE)) for p in tests])]
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda job: run(*job), jobs))
    after = source_binding()
    unchanged = before == after and sha(NODE) == node_hash and sha(COMPILER) == compiler_hash
    for name, receipt in results:
        receipt.update({"source_files_before": before, "source_files_after": after,
                        "source_unchanged_during_run": unchanged,
                        "scope": "Current bridge synthetic regressions including new supervisor journal; separate from source05 evidence."})
        (PACKET / (name + ".result.json")).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"name": name, "exit_code": receipt["exit_code"],
                          "source_unchanged": unchanged, "source_file_count": len(before),
                          "test_counts": receipt.get("test_counts"), "test_file_count": receipt.get("test_file_count")}))
    if not unchanged or any(r["exit_code"] for _, r in results):
        raise SystemExit(1)

if __name__ == "__main__":
    main()
