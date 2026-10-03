"""Bind completed private outputs without executing another acceptance gate."""
from pathlib import Path
import datetime as dt
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import sys
import tomllib

EVIDENCE = Path(__file__).absolute().parent
ROOT = EVIDENCE.parents[3]
FREEZE = json.loads((EVIDENCE / "private-source-freeze.json").read_text())
CANDIDATE = Path(FREEZE["private_candidate"])
OUTPUT = CANDIDATE / ".cache/canonical"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def observation(path):
    before = path.lstat()
    assert stat.S_ISREG(before.st_mode) and before.st_nlink == 1, str(path)
    value = {"sha256": digest(path), "bytes": before.st_size,
             "mode": stat.S_IMODE(before.st_mode)}
    after = path.lstat()
    assert (before.st_dev, before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns,
            before.st_ctime_ns, before.st_nlink) == (after.st_dev, after.st_ino, after.st_mode,
            after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_nlink), str(path)
    return value, [after.st_dev, after.st_ino, stat.S_IMODE(after.st_mode),
                   after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_nlink]


def tree(directory):
    result = {}
    for path in sorted(directory.rglob("*")):
        info = path.lstat()
        assert not stat.S_ISLNK(info.st_mode), str(path)
        if stat.S_ISDIR(info.st_mode):
            continue
        result[str(path.relative_to(directory))] = observation(path)[0]
    return result


def save(name, value):
    with (EVIDENCE / name).open("x") as stream:
        stream.write(json.dumps(value, indent=2) + "\n")


def dynamic_root():
    sys.path.insert(0, str(ROOT / "scripts/qa"))
    spec = importlib.util.spec_from_file_location("edge_seal_readback", ROOT / "scripts/qa/run_edge_ci.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    paths = module.source_paths()
    return {str(p.relative_to(ROOT)): observation(p)[0] for p in paths}


def main():
    before = tree(OUTPUT)
    destination = EVIDENCE / "canonical"
    destination.mkdir()
    copied = []
    for name, value in before.items():
        source, target = OUTPUT / name, destination / name
        source_before, source_identity = observation(source)
        assert source_before == value
        target.parent.mkdir(parents=True, exist_ok=True)
        with source.open("rb") as origin, target.open("xb") as out:
            shutil.copyfileobj(origin, out)
        os.chmod(target, value["mode"])
        copied_value, copied_identity = observation(target)
        source_after, after_identity = observation(source)
        assert value == copied_value == source_after
        assert source_identity == after_identity
        assert source_identity[:2] != copied_identity[:2]
        copied.append({"path": name, **value, "original_identity": source_identity,
                       "copy_identity": copied_identity, "original_after_identity": after_identity})
    assert tree(OUTPUT) == before == tree(destination)
    save("canonical-output-copy.json", {"copied_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "original": str(OUTPUT), "copy": str(destination), "files": len(before),
         "bytes": sum(v["bytes"] for v in before.values()),
         "before_copy_after_hash_size_mode_equal": True, "physical_file_identities_distinct": True,
         "manifest": copied})

    expected = {r["path"]: {"sha256": r["sha256"], "bytes": r["bytes"], "mode": r["copy_mode"]}
                for r in FREEZE["source_manifest"]}
    private = {name: observation(CANDIDATE / name)[0] for name in expected}
    assert private == expected
    root = dynamic_root()
    added = sorted(root.keys() - expected.keys())
    removed = sorted(expected.keys() - root.keys())
    changed = {name: {"accepted": expected[name], "current": root[name]}
               for name in root.keys() & expected.keys() if root[name] != expected[name]}
    cache = tree(Path(FREEZE["deno_cache"]))
    negative_copy = json.loads((EVIDENCE / "corrupted-lock-negative/copy-and-mutation.json").read_text())
    negative_cache = {row["path"]: {k: row[k] for k in ["sha256", "bytes", "mode"]}
                      for row in negative_copy["manifest"] if row.get("kind") == "cache"}
    assert cache == negative_cache
    current_config = tomllib.loads((ROOT / "supabase/config.toml").read_text())
    assert observation(ROOT / "supabase/config.toml")[0] == root["supabase/config.toml"]
    configured = sorted(current_config.get("functions", {}))
    current_entrypoints = sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts"))
    externals = []
    for row in FREEZE["external_inputs"]:
        original, private_input = observation(Path(row["original"]))[0], observation(Path(row["copy"]))[0]
        assert original["sha256"] == private_input["sha256"] == row["sha256"]
        assert original["bytes"] == private_input["bytes"] == row["bytes"]
        assert original["mode"] == row["original_mode"] and private_input["mode"] == row["copy_mode"]
        externals.append({"kind": row["kind"], "original": row["original"], "copy": row["copy"],
                          "sha256": row["sha256"], "bytes": row["bytes"], "original_mode": original["mode"],
                          "copy_mode": private_input["mode"]})
    save("final-source-input-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "accepted_source_count": len(expected), "current_dynamic_source_count": len(root),
         "private_accepted_sources_unchanged": True, "current_added_paths": added,
         "current_removed_paths": removed, "current_changed_sources": changed,
         "current_dynamic_manifest": root,
         "current_configured_functions": configured, "current_source_entrypoints": current_entrypoints,
         "current_configured_function_count": len(configured), "current_source_entrypoint_count": len(current_entrypoints),
         "accepted_literal_loader_count": 12,
         "endpoint_manifest_implication": "Accepted configured/source/literal loader parity was12. Current successor gateway changes config and source endpoints; the original12 loader proof is not current13 endpoint acceptance.",
         "current_checkout_is_same_accepted_input_set": not added and not removed and not changed,
         "cold_cache_initial_files": FREEZE["initial_deno_file_count"], "cold_cache_final_files": len(cache),
         "cold_cache_final_bytes": sum(v["bytes"] for v in cache.values()),
         "accepted_cache_unchanged_since_negative_copy": True, "cache_manifest": cache,
         "external_inputs_unchanged": True, "external_inputs": externals})

    worker_root = CANDIDATE / "scripts/tests/fixtures/receipt_worker_observation_v1"
    worker = json.loads((worker_root / "manifest.json").read_text())
    worker_tree = tree(worker_root)
    assert set(worker_tree) == {"manifest.json", *worker["files"]}
    assert all(worker_tree[n]["sha256"] == sha for n, sha in worker["files"].items())
    origin = json.loads((worker_root / "result.json").read_text())
    assert origin["status"] == "pass" and origin["finished_at"] == worker["origin_finished_at"]
    assert origin["sources_unchanged"] and origin["runner_unchanged"] and origin["support_unchanged"]
    for field, name in [("runner_sha256", "inputs/executed-runner.py"),
                        ("support_sha256", "inputs/authority-support.py"),
                        ("helper_sha256", "inputs/executed-helper.py")]:
        assert origin[field] == worker_tree[name]["sha256"]
    assert all(origin["migration_sha256"][n.rsplit("/", 1)[1]] == sha
               for n, sha in worker["files"].items() if n.endswith(".sql"))
    fixtures_root = OUTPUT / "linux-decoder/fixtures"
    fixtures = json.loads((fixtures_root / "manifest.json").read_text())
    fixture_tree = tree(fixtures_root)
    names = [r["path"] for r in fixtures["fixtures"]]
    assert len(names) == len(set(names)) and set(fixture_tree) == {"manifest.json", *names}
    assert all(fixture_tree[r["path"]]["sha256"] == r["sha256"] for r in fixtures["fixtures"])
    execution = json.loads((EVIDENCE / "execution-result.json").read_text())
    save("fixture-provenance.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "immutable_worker_manifest_sha256": worker_tree["manifest.json"]["sha256"],
         "immutable_worker_files": worker_tree, "worker_manifest": worker, "origin_receipt": origin,
         "origin_exact_finished_helper_runner_support_and_migration_hashes_verified": True,
         "generated_linux_manifest_sha256": fixture_tree["manifest.json"]["sha256"],
         "generated_linux_fixture_count": len(names), "generated_linux_files": fixture_tree,
         "generated_linux_generator_sha256": expected["tools/roster-decoder/generate_fixtures.py"]["sha256"],
         "generator_command": [execution["command"][execution["command"].index("--decoder-python") + 1],
                               "tools/roster-decoder/generate_fixtures.py", str(fixtures_root)],
         "generator_version_metadata": execution["fixture_generator_version_metadata"],
         "generation_log_sha256": digest(OUTPUT / "linux-decoder/generation.log"),
         "synthetic_only": fixtures["synthetic_only"],
         "provider_accuracy_verified": fixtures["provider_accuracy_verified"],
         "current_sql_execution_or_hosted_provider_device_acceptance_claimed": False})

    validation = json.loads((OUTPUT / "validation.json").read_text())
    units = json.loads((OUTPUT / "units/validation.json").read_text())
    http = json.loads((OUTPUT / "edge-http/report.json").read_text())
    linux = json.loads((OUTPUT / "linux-decoder/validation.json").read_text())
    linux_commands = [json.loads(line) for line in (OUTPUT / "linux-deno-commands.jsonl").read_text().splitlines()]
    assert units["tests_failed"] == units["tests_ignored"] == 0
    assert http["runtime_result"]["configured_functions"] == http["runtime_result"]["source_entrypoints"] == http["runtime_result"]["literal_loader_entrypoints"]
    assert all(command[1] not in ("test", "run") or ("--cached-only" in command and "--no-prompt" in command)
               for command in linux_commands)
    save("permissions-and-local-scope.json", {
        "observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "dependency_cache_command": validation["phases"]["frozen_dependency_cache"]["command"],
        "type_check_command": validation["phases"]["types"]["command"],
        "unit_command": units["command"], "http_command": http["command"],
        "linux_deno_commands": linux_commands,
        "dependency_security_command": linux["dependency_security"]["command"],
        "docker_build_command": ["docker", "build", "--network=none", "--no-cache", "-t",
             "collect_roster_decoder_5fbdff83cc2b:qa", str(OUTPUT / "linux-decoder/build-context")],
        "dockerfile_sha256": expected["tools/roster-decoder/Dockerfile"]["sha256"],
        "check_cache_distinction": "Pinned Deno check/cache support frozen lock, not --cached-only; neither executes application runtime code. test/run use cached-only/no-prompt.",
        "unit_network_read_subprocess_boundary": "127.0.0.1 only; exact functions/immutable worker/contract reads; no allow-run grant.",
        "http_environment": http["environment"],
        "http_recorded_provider_denials": http["runtime_result"]["blocked_provider_attempts"],
        "http_configured_source_literal_loader_parity_count": len(http["runtime_result"]["configured_functions"]),
        "decoder_supervisor_network": "Isolated Docker bridge with published listener only 127.0.0.1 and synthetic random local secret for actual HTTP cases. It is not network-none.",
        "docker_build_and_security_network": "Actual build --network=none and Dockerfile RUN --network=none; security container --network none. Offline pip --no-index --require-hashes --only-binary=:all:.",
        "environment_source": "Task-owned driver and maintained callers construct restricted child environments; no inherited customer/provider credentials or .env import.",
        "network_observation_limit": "Exact permission commands, synthetic transport/assertions and recorded denials are retained. No packet capture or claim of independently observed zero network traffic. Frozen public dependency acquisition was explicitly allowed.",
        "canonical_report_provider_calls": validation["provider_calls"],
        "current_sql_executed": validation["current_sql_executed"],
        "immutable_worker_contract_scope": validation["sql_scope"],
        "corrupt_check_network_constraint": "Supported full83 frozen check in independent physical source/cache copy under actual sandbox-exec deny network*, independently socket-probed EPERM; real exit10 integrity mismatch.",
        "original_arc04_local_contract_evidence": "Fresh pinned cache/types/tests, immutable generated/observation fixture bindings, frozen lock and real corrupted referenced-module denial are proved on the accepted137 source cohort. Parent assesses finding closure.",
        "separate_release_scope": "BE10/current SQL, successor-gateway/current141 verification, real Auth/gateway/RLS/providers, deployment/device/store and whole production acceptance are not inferred from this local finding proof."})
    print(json.dumps({"copied_output_files": len(before), "copied_output_bytes": sum(v["bytes"] for v in before.values()),
          "accepted_sources": len(expected), "current_dynamic_sources": len(root),
          "added": added, "changed": sorted(changed), "worker_files": len(worker_tree),
          "generated_fixtures": len(names), "cache_files": len(cache)}, indent=2))


if __name__ == "__main__":
    main()
