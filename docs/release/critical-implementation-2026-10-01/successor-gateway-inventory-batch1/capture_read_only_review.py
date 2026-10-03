"""Bound a read-only successor review; never execute a handler or remote tool."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import os
import re
import stat
import subprocess
import tomllib

EVIDENCE = Path(__file__).absolute().parent
ROOT = EVIDENCE.parents[3]
NAMES = [
    "supabase/functions/collect-receipt-successor-gateway/handler.ts",
    "supabase/functions/collect-receipt-successor-gateway/handler_test.ts",
    "supabase/functions/collect-receipt-successor-gateway/index.ts",
    "supabase/functions/collect-receipt-successor-gateway/wire.ts",
    "supabase/config.toml", "contracts/edge-functions.json",
    "supabase/functions/_shared/supabase.ts", "supabase/functions/_shared/cors.ts",
    "supabase/functions/collect-android-gateway/handler.ts",
    "scripts/edge_function_inventory.rb", "scripts/edge_function_inventory.sh",
    "scripts/tests/edge_function_inventory_test.rb",
    "scripts/supabase_deploy.sh", "scripts/supabase_production_readiness.sh",
    "scripts/qa/backend_release_delivery.py", "scripts/tests/supabase_delivery_contract_test.py",
    "scripts/qa/edge_http_runtime_uat.ts", "scripts/qa/run_edge_http_uat.py",
    "scripts/qa/run_edge_ci.py", "scripts/qa/run_edge_unit_tests.py",
    "scripts/audits/collect_edge_function_local_gate.rb",
    "scripts/tests/collect_edge_function_local_gate_test.rb",
    "supabase/migrations/20260930211605_android_gateway_identity.sql",
    "supabase/migrations/20261001000519_safe_unstarted_receipt_cancel.sql",
    "supabase/migrations/20261001110000_receipt_operational_authority.sql",
    "supabase/migrations/20261002040000_receipt_unarmed_closure.sql",
    "supabase/migrations/20261002041000_receipt_successor_approvals.sql",
    "supabase/migrations/20261002043000_receipt_successor_execution.sql",
    "supabase/migrations/20261002070000_receipt_worker_history_storage.sql",
]


def read(path):
    before = path.lstat()
    assert stat.S_ISREG(before.st_mode) and before.st_nlink == 1
    data = path.read_bytes()
    after = path.lstat()
    identity = lambda s: [s.st_dev, s.st_ino, stat.S_IMODE(s.st_mode), s.st_size,
                          s.st_mtime_ns, s.st_ctime_ns, s.st_nlink]
    assert identity(before) == identity(after)
    return data, {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                  "mode": stat.S_IMODE(after.st_mode), "identity": identity(after)}


def save(name, value):
    with (EVIDENCE / name).open("x") as stream:
        stream.write(json.dumps(value, indent=2) + "\n")


def main():
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    original, copied = {}, {}
    for name in NAMES:
        data, original[name] = read(ROOT / name)
        target = EVIDENCE / "inputs" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
        os.chmod(target, original[name]["mode"])
        _, copied[name] = read(target)
        assert all(original[name][k] == copied[name][k] for k in ["sha256", "bytes", "mode"])
        assert original[name]["identity"][:2] != copied[name]["identity"][:2]
    manifest = json.loads((EVIDENCE / "inputs/contracts/edge-functions.json").read_text())
    config = tomllib.loads((EVIDENCE / "inputs/supabase/config.toml").read_text())
    source_entries = sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts"))
    loader = (EVIDENCE / "inputs/scripts/qa/edge_http_runtime_uat.ts").read_text()
    loader_entries = sorted(re.findall(r'import\("\.\./\.\./supabase/functions/([^/]+)/index\.ts"\)', loader))
    test = (EVIDENCE / "inputs/supabase/functions/collect-receipt-successor-gateway/handler_test.ts").read_text()
    relative = re.findall(r'from "(\./fixtures/[^\"]+\.json)"', test)
    fixture_readback = {}
    base = ROOT / "supabase/functions/collect-receipt-successor-gateway"
    for name in relative:
        path = base / name
        fixture_readback[name] = {"exists": path.exists(), "symlink": path.is_symlink()}
        if path.exists():
            fixture_readback[name]["file"] = read(path)[1]
    action_map = dict(re.findall(r'^\s*(\w+): "(gateway_receipt_successor_\w+_v1)"',
                     (EVIDENCE / "inputs/supabase/functions/collect-receipt-successor-gateway/wire.ts").read_text(), re.M))
    command = ["/usr/bin/ruby", "scripts/edge_function_inventory.rb", "auth-check"]
    result = subprocess.run(command, cwd=ROOT, env={"PATH": os.defpath}, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    (EVIDENCE / "actual-inventory-check.stdout").write_bytes(result.stdout)
    (EVIDENCE / "actual-inventory-check.stderr").write_bytes(result.stderr)
    after = {name: read(ROOT / name)[1] for name in NAMES}
    drift = {name: {"before": original[name], "after": after[name]} for name in NAMES if original[name] != after[name]}
    after_entries = sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts"))
    fixtures_after = {}
    for name in relative:
        path = base / name
        fixtures_after[name] = {"exists": path.exists(), "symlink": path.is_symlink()}
        if path.exists():
            fixtures_after[name]["file"] = read(path)[1]
    source_stable = not drift and source_entries == after_entries and fixture_readback == fixtures_after
    save("readback.json", {
        "started_at_utc": started, "finished_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "status": "read_only_preparation_complete" if source_stable else "review_source_drift",
        "source_count": len(NAMES), "source_before": original, "physical_copies": copied,
        "source_after": after, "source_drift": drift, "source_stable": source_stable,
        "repo_manifest_entries": sorted(r["name"] for r in manifest["functions"]),
        "repo_manifest_count": len(manifest["functions"]), "source_entries": source_entries,
        "source_entries_after": after_entries, "config_entries": sorted(config["functions"]),
        "literal_loader_entries": loader_entries,
        "successor_config": config["functions"].get("collect-receipt-successor-gateway"),
        "six_action_rpc_map": action_map, "declared_fixture_imports": fixture_readback,
        "declared_fixture_imports_after": fixtures_after,
        "declared_deno_test_count": len(re.findall(r'Deno\.test\(', test)),
        "actual_read_only_inventory_command": {"command": command, "deadline_seconds": 20,
            "exit_code": result.returncode, "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
            "stderr_sha256": hashlib.sha256(result.stderr).hexdigest(),
            "expected_inventory_failure_observed": result.returncode != 0 and b'collect-receipt-successor-gateway' in result.stderr},
        "maintained_source_writes": 0, "handler_execution": False, "canonical_gate_executed": False,
        "current_or_hosted_sql_executed": False, "provider_network_calls": False,
        "hosted_inventory_observed": False, "other_human_chat_messaged": False,
        "old_137_source_acceptance_modified_or_relabelled": False})
    print(json.dumps({"status": "read_only_preparation_complete" if source_stable else "review_source_drift",
          "sources": len(NAMES), "source_drift": sorted(drift), "manifest_count": len(manifest["functions"]),
          "source_config_loader_counts": [len(source_entries), len(config["functions"]), len(loader_entries)],
          "missing_imports": [n for n, v in fixture_readback.items() if not v["exists"]],
          "declared_tests": len(re.findall(r'Deno\.test\(', test)),
          "inventory_exit": result.returncode}, indent=2))


if __name__ == "__main__":
    main()
