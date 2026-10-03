#!/usr/bin/env python3
"""Retain actual credential-free checks of this current, bounded source slice."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[4]
LEAF = Path(__file__).resolve().parent
BRIDGE = ROOT / "tools/collect-notification-mcp"
NODE = Path("/Volumes/PRO-G40/Development/Node/bin/node")
TSC = BRIDGE / "node_modules/.pnpm/typescript@7.0.2/node_modules/typescript/bin/tsc"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert sha(NODE) == "c3ec5c451750ec57acabfbc05c26de2fcad6dda84ab1b117a5c1eefaae28cbef"
    assert sha(TSC) == "2219f428a7e55aaf1f7ad85b9b0f0cf5078aeb76ccc9a7c6036c92d48f492ffd"
    assert not (LEAF / "checks.json").exists(), "evidence is immutable after this attempt"
    files = [*sorted((BRIDGE / "src").rglob("*.ts")),
             BRIDGE / "package.json", BRIDGE / "pnpm-lock.yaml", BRIDGE / "tsconfig.json",
             *sorted((ROOT / ".github/workflows").glob("*.yml")),
             ROOT / "scripts/qa/collect_ci_policy.py", ROOT / "scripts/tests/test_collect_ci_policy.py",
             ROOT / "scripts/qa/collect_release_acceptance.py", ROOT / "scripts/tests/test_collect_release_acceptance.py",
             Path(__file__).resolve()]
    before = {str(p.relative_to(ROOT)): sha(p) for p in files}
    (LEAF / "source-before.json").write_text(json.dumps(before, indent=2, sort_keys=True) + "\n")
    # Do not forward the host's Auth, profile, Keychain, MCP or provider variables.
    environment = {"PATH": str(NODE.parent) + ":/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"}
    if os.environ.get("TMPDIR"):
        environment["TMPDIR"] = os.environ["TMPDIR"]
    tests = sorted((BRIDGE / "src").glob("*.test.ts"))
    commands = [
        ("typescript", [str(NODE), str(TSC), "--noEmit"], BRIDGE),
        ("mcp-tests", [str(NODE), "--experimental-strip-types", "--test", *[str(p) for p in tests]], ROOT),
        ("ci-policy", [sys.executable, "scripts/qa/collect_ci_policy.py"], ROOT),
        ("tooling-tests", [sys.executable, "-m", "unittest", "scripts.tests.test_collect_ci_policy", "scripts.tests.test_collect_release_acceptance", "-v"], ROOT),
    ]
    report = {"started_at": datetime.now(timezone.utc).isoformat(), "commands": [], "bridge_test_files": len(tests),
              "node_sha256": sha(NODE), "compiler_sha256": sha(TSC), "credentials_forwarded": False,
              "otp_keychain_mcp_host_or_real_backend_calls_requested": False,
              "dependency_download_or_installation": False, "scope": "Current local bridge, selected CI declarations and acceptance tooling; synthetic tests only."}
    for name, argv, cwd in commands:
        with (LEAF / f"{name}.stdout.log").open("w") as out, (LEAF / f"{name}.stderr.log").open("w") as err:
            try:
                result = subprocess.run(argv, cwd=cwd, env=environment, stdout=out, stderr=err, timeout=120, check=False)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = 124
        report["commands"].append({"name": name, "argv": argv, "cwd": str(cwd), "exit_code": code})
        print(name, code, flush=True)
        if code:
            break
    after = {str(p.relative_to(ROOT)): sha(p) for p in files}
    (LEAF / "source-after.json").write_text(json.dumps(after, indent=2, sort_keys=True) + "\n")
    report["changed_inputs"] = [p for p in before if before[p] != after[p]]
    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    report["source_inputs"] = len(before)
    report["pass"] = len(report["commands"]) == len(commands) and all(r["exit_code"] == 0 for r in report["commands"]) and not report["changed_inputs"]
    (LEAF / "checks.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
