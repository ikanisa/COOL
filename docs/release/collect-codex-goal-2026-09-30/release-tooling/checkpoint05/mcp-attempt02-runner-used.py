#!/usr/bin/env python3
"""Resolve and test the preserved MCP bridge offline in an isolated work copy.

This evidence runner does not load host credentials/configuration or call a hosted
tool. It does not approve the source or attest dependency provenance.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--packet", required=True, type=Path)
    args = parser.parse_args()
    candidate, workspace, packet = args.candidate.resolve(), args.workspace.resolve(), args.packet.resolve()
    packet.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("collect_snapshot", candidate / "scripts/qa/collect_release_candidate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    raw, _ = module.regular_bytes(candidate, module.MANIFEST)
    if module.sha(raw) != args.manifest_sha256:
        raise module.ReleaseError("CANDIDATE_MANIFEST_HASH_CHANGED")
    manifest = json.loads(raw)
    bridge = workspace / "tools/collect-notification-mcp"
    bridge_inputs = {name: item for name, item in manifest["source_files"].items()
                     if name.startswith("tools/collect-notification-mcp/")}
    fixture_inputs = {name: item for name, item in manifest["source_files"].items()
                      if name.startswith("contracts/collect-shadow-supervisor-v1.") and name.endswith(".json")}
    if "contracts/collect-shadow-supervisor-v1.lifecycle.fixture.json" not in fixture_inputs:
        raise module.ReleaseError("MCP_CONTRACT_FIXTURE_REQUIRED")
    expected = {**bridge_inputs, **fixture_inputs}

    def source_check():
        changed = []
        for name, item in expected.items():
            try:
                data, mode = module.regular_bytes(workspace, name)
                if {"sha256": module.sha(data), "bytes": len(data), "mode": mode} != item:
                    changed.append(name)
            except module.ReleaseError:
                changed.append(name)
        if changed:
            raise module.ReleaseError("MCP_SNAPSHOT_SOURCE_CHANGED", changed)

    source_check()
    if workspace == candidate or candidate in workspace.parents or bridge.is_symlink() or (bridge / "node_modules").exists():
        raise module.ReleaseError("MCP_ISOLATED_FRESH_WORKSPACE_REQUIRED")
    node = Path(manifest["toolchain"]["node"]["path"])
    pnpm = Path("/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pnpm/bin/pnpm.mjs")
    store = Path("/Volumes/PRO-G40/.pnpm-store/v11")
    if not node.is_file() or not pnpm.is_file() or not store.is_dir():
        raise module.ReleaseError("MCP_OFFLINE_RUNTIME_REQUIRED")
    pnpm_package = json.loads((pnpm.parent.parent / "package.json").read_text())
    if pnpm_package["version"] != "11.19.0":
        raise module.ReleaseError("MCP_PACKAGE_MANAGER_VERSION_CHANGED")
    runtime = {"node_path": str(node), "node_sha256": module.sha(node.read_bytes()),
               "node_version": manifest["toolchain"]["node"]["version"],
               "pnpm_path": str(pnpm), "pnpm_entrypoint_sha256": module.sha(pnpm.read_bytes()),
               "pnpm_version": pnpm_package["version"], "store": str(store)}
    commands = []
    with tempfile.TemporaryDirectory(prefix="collect-mcp-offline-home-") as clean_home:
        environment = {key: os.environ[key] for key in ("TMPDIR", "LANG", "LC_ALL") if key in os.environ}
        environment.update({"PATH": str(node.parent) + ":/usr/bin:/bin:/usr/sbin:/sbin", "HOME": clean_home,
                            "CI": "true", "COREPACK_ENABLE_NETWORK": "0", "pnpm_config_pm_on_fail": "ignore",
                            "npm_config_update_notifier": "false"})

        def run(argv, label, timeout):
            started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            print("Starting " + label, flush=True)
            try:
                result = subprocess.run(argv, cwd=bridge, env=environment, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=timeout, check=False)
            except subprocess.TimeoutExpired as error:
                result = subprocess.CompletedProcess(argv, 124, (error.stdout or b"") + b"\nBounded MCP checkpoint timeout.\n")
            module.screen_credentials(result.stdout, label + ".log")
            log = packet / (label + ".log")
            log.write_bytes(result.stdout)
            receipt = {"command": argv, "cwd": str(bridge), "exit_code": result.returncode,
                       "started_at_utc": started, "finished_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                       "log_sha256": module.sha(result.stdout), "candidate_manifest_sha256": args.manifest_sha256,
                       "runner_sha256": module.sha(Path(__file__).read_bytes()), "runtime": runtime,
                       "current_user_credentials_supplied": False, "host_config_loaded": False,
                       "hosted_tool_calls": 0, "otp_requests": 0, "provider_sends": 0}
            (packet / (label + ".result.json")).write_bytes(module.canonical(receipt))
            commands.append(receipt)
            print(result.stdout.decode(errors="replace")[-2500:], flush=True)
            if result.returncode:
                raise module.ReleaseError("MCP_CHECKPOINT_COMMAND_FAILED")
            return result.stdout

        if run([str(node), "--version"], "mcp-node-version", 15).decode().strip() != runtime["node_version"]:
            raise module.ReleaseError("MCP_NODE_VERSION_CHANGED")
        run([str(node), str(pnpm), "install", "--offline", "--frozen-lockfile", "--ignore-scripts",
             "--store-dir", str(store), "--verify-store-integrity"], "mcp-offline-install", 180)
        source_check()
        declared = manifest["toolchain"]["mcp_declared_packages"]
        direct = {}
        for name, version in declared.items():
            path = (bridge / "node_modules" / name / "package.json").resolve()
            if not path.is_file() or bridge not in path.parents:
                raise module.ReleaseError("MCP_DEPENDENCY_BINDING_INVALID")
            data = path.read_bytes()
            info = json.loads(data)
            if info["name"] != name or info["version"] != version:
                raise module.ReleaseError("MCP_DEPENDENCY_VERSION_CHANGED")
            direct[name] = {"version": version, "path": str(path), "package_json_sha256": module.sha(data)}
        dependency_files = {}
        package_manifests = {}
        for path in sorted((bridge / "node_modules").rglob("*")):
            name = path.relative_to(bridge / "node_modules").as_posix()
            if path.is_symlink():
                resolved = path.resolve()
                if not resolved.exists() or bridge not in resolved.parents:
                    raise module.ReleaseError("MCP_DEPENDENCY_BINDING_INVALID", [name])
            elif path.is_file():
                data = path.read_bytes()
                dependency_files[name] = {"sha256": module.sha(data), "bytes": len(data)}
                if path.name == "package.json":
                    info = json.loads(data)
                    if isinstance(info, dict) and isinstance(info.get("name"), str) and isinstance(info.get("version"), str):
                        package_manifests[name] = {"name": info["name"], "version": info["version"], "sha256": module.sha(data)}
        binding = {"status": "pass", "candidate_manifest_sha256": args.manifest_sha256, "bridge_source_files": bridge_inputs,
                   "bridge_source_file_count": len(bridge_inputs), "contract_fixtures": fixture_inputs,
                   "contract_fixture_file_count": len(fixture_inputs), "runtime": runtime, "direct_packages": direct,
                   "resolved_package_manifests": package_manifests, "dependency_file_count": len(dependency_files),
                   "dependency_files": dependency_files, "dependency_manifest_sha256": module.sha(module.canonical(dependency_files)),
                   "frozen_lock_offline_resolution": True, "install_scripts_enabled": False,
                   "all_module_links_inside_work_copy": True, "source_and_lock_unchanged": True,
                   "dependency_source_trust_attested": False}
        (packet / "mcp-dependency-binding.json").write_bytes(module.canonical(binding))
        run([str(node), str(pnpm), "check"], "mcp-typescript-check", 120)
        tests = sorted((bridge / "src").glob("*.test.ts"))
        if not tests:
            raise module.ReleaseError("MCP_TEST_FILES_REQUIRED")
        output = run([str(node), "--experimental-strip-types", "--test", *[str(path) for path in tests]], "mcp-snapshot-tests", 180)
        counts = {}
        for key in ("tests", "pass", "fail", "cancelled", "skipped", "todo"):
            match = re.search(rb"(?:# |\xe2\x84\xb9 )" + key.encode() + rb" (\d+)(?:\r?\n|$)", output)
            if not match:
                raise module.ReleaseError("MCP_TEST_SUMMARY_REQUIRED")
            counts[key] = int(match[1])
        if counts["tests"] != counts["pass"] or any(counts[key] for key in ("fail", "cancelled", "skipped", "todo")):
            raise module.ReleaseError("MCP_TEST_SUMMARY_FAILED")
        source_check()
        if module.sha(node.read_bytes()) != runtime["node_sha256"] or module.sha(pnpm.read_bytes()) != runtime["pnpm_entrypoint_sha256"]:
            raise module.ReleaseError("MCP_INSTALLED_RUNTIME_CHANGED")
        final = {"status": "pass", "kind": "exact_snapshot_synthetic_mcp_regression", "candidate_manifest_sha256": args.manifest_sha256,
                 "bridge_source_file_count": len(bridge_inputs), "contract_fixture_file_count": len(fixture_inputs),
                 "test_file_count": len(tests), "test_counts": counts,
                 "typescript_check": "pass", "runtime": runtime, "commands": commands,
                 "selected_bridge_source_unchanged": True, "source_current_tree_accepted": False,
                 "approvals": manifest["approvals"], "host_config_loaded": False, "hosted_tool_calls": 0,
                 "otp_requests": 0, "provider_sends": 0, "production_ready": False}
        (packet / "mcp-snapshot-verification.json").write_bytes(module.canonical(final))
        print(json.dumps({key: final[key] for key in ("status", "kind", "bridge_source_file_count", "test_file_count", "test_counts", "candidate_manifest_sha256")}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"status": "blocked", "reason_code": getattr(error, "code", "MCP_CHECKPOINT_FAILED"),
                          "affected_paths": getattr(error, "paths", []), "credential_values_reported": False, "production_ready": False}))
        raise SystemExit(2)
