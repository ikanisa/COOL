"""Read/copy complete terminal outputs and independently inspect owned cleanup."""
from pathlib import Path
import datetime as dt
import importlib.util
import json
import os
import re
import subprocess
import sys
import tomllib

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
PREP = E.parent / "edge-ai-canonical-inputs-preparation4"
spec = importlib.util.spec_from_file_location("prep4_local_helpers", PREP / "prepare_complete_inputs.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
observe, copy, packet = helpers.observe, helpers.copy, helpers.packet


def save(name, value):
    p = E / name
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("x") as f:
        f.write(json.dumps(value, indent=2) + "\n")


def tree(base):
    assert not any(p.is_symlink() for p in base.rglob("*"))
    return {str(p.relative_to(base)): observe(p) for p in sorted(base.rglob("*")) if p.is_file()}


def inventory(base):
    code = ("import sys,json;sys.path.insert(0,sys.argv[1]);import run_edge_ci;"
            "print(json.dumps([str(p) for p in run_edge_ci.source_paths()]))")
    r = subprocess.run([sys.executable, "-B", "-c", code, str(base / "scripts/qa")],
                       check=True, capture_output=True, text=True, timeout=15)
    return {str(Path(p).relative_to(base)): observe(Path(p)) for p in json.loads(r.stdout)}


def main():
    freeze = json.loads((E / "private-source-freeze.json").read_text())
    prepared = json.loads((E / "authorized-preparation-bindings.json").read_text())
    execution = json.loads((E / "execution-result.json").read_text())
    matrix = json.loads((PREP / "actual-cli-input-matrix.json").read_text())
    candidate = Path(freeze["private_candidate"])
    output = candidate / ".cache/canonical"
    validation = json.loads((output / "validation.json").read_text())
    assert execution["status"] == validation["status"] == "pass" and execution["exit_code"] == 0
    assert execution["private_source_unchanged"] and validation["source_unchanged"]
    assert all(validation["phases"][n]["status"] == "pass" for n in validation["required_phases"])
    files = sorted(p for p in output.rglob("*") if p.is_file())
    copies = [copy(p, E / "canonical" / p.relative_to(output)) for p in files]
    save("canonical-output-copy.json", {"copied_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "count": len(copies), "bytes": sum(r["before"]["bytes"] for r in copies),
         "before_copy_after_sha_size_mode_equal": True, "physical_identities_distinct": True, "files": copies})
    expected = {r["path"]: {"sha256": r["sha256"], "bytes": r["bytes"], "mode": r["copy_mode"]}
                for r in freeze["source_manifest"]}
    private = inventory(candidate)
    assert len(private) == 140 and set(private) == set(expected)
    assert all(all(private[n][k] == row[k] for k in row) for n, row in expected.items())
    assert packet(PREP)["leaves"] == prepared["prep4_artifacts_before"]
    assert observe(PREP / "batch.json")["sha256"] == prepared["prep4_batch_sha256"]
    assert observe(PREP / "SHA256SUMS")["sha256"] == prepared["prep4_checksum_sha256"]
    assert matrix["prior402_181_400_519_packets_before_after"] == {n: packet(E.parent / n)
        for n in matrix["prior402_181_400_519_packets_before_after"]}
    original_source_rows = matrix["source_copies"]
    assert all(observe(Path(r["original"])) == r["before"] == r["after"] for r in original_source_rows)
    external = {r["copy"]: observe(Path(r["copy"])) for r in freeze["external_inputs"]}
    assert len(external) == 13 and all(external[r["copy"]]["sha256"] == r["sha256"]
            and external[r["copy"]]["mode"] == 0o444 and external[r["copy"]]["identity"][-1] == 1 for r in freeze["external_inputs"])
    publisher = observe(Path(freeze["publisher_receipt_copy"]))
    assert publisher["sha256"] == freeze["publisher_sha256"]
    current_before = inventory(ROOT)
    added = {n: v for n, v in current_before.items() if n not in expected}
    changed = {n: v for n, v in current_before.items() if n in expected and
               any(v[k] != expected[n][k] for k in ["sha256", "bytes", "mode"])}
    removed = sorted(set(expected) - set(current_before))
    current_copies = [copy(ROOT / n, E / "current-source-snapshots" / n) for n in sorted(set(added) | set(changed))]
    current_after = inventory(ROOT)
    assert current_before == current_after
    configured = sorted(tomllib.loads((ROOT / "supabase/config.toml").read_text())["functions"])
    current_entries = sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts"))
    current_manifest = json.loads((ROOT / "contracts/edge-functions.json").read_text())
    cache = tree(Path(freeze["deno_cache"]))
    save("final-source-input-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "accepted_private_count": 140, "accepted_private_manifest": private, "accepted_private_unchanged": True,
         "current_count": len(current_after), "current_before": current_before, "current_after": current_after,
         "current_added": added, "current_changed": changed, "current_removed": removed, "current_drift_copies": current_copies,
         "current_configured_endpoints": configured, "current_source_endpoints": current_entries,
         "current_manifest_endpoint_count": len(current_manifest["functions"]), "private_dated_literal_loader_count": 12,
         "current_checkout_acceptance": False, "prep4_and_prior402_181_400_519_packets_unchanged": True,
         "prior_source140_unchanged": True, "all13_external_inputs": external,
         "cache_initial_count": 0, "cache_final_count": len(cache), "cache_final_bytes": sum(v["bytes"] for v in cache.values()),
         "cache_manifest": cache})
    units = json.loads((output / "units/validation.json").read_text())
    http_full = json.loads((output / "edge-http/report.json").read_text())
    http = http_full["runtime_result"]
    linux = json.loads((output / "linux-decoder/validation.json").read_text())
    assert units["tests_failed"] == units["tests_ignored"] == units["steps_failed"] == units["steps_ignored"] == 0
    assert len(http["checks"]) == 103 and all(r["status"] == "pass" for r in http["checks"])
    assert linux["passed"] and linux["source_before"] == linux["source_after"]
    assert http["configured_functions"] == http["source_entrypoints"] == http["literal_loader_entrypoints"]
    old_http = json.loads((E.parent / "edge-ai-canonical-batch1/canonical/edge-http/report.json").read_text())["runtime_result"]
    assert [r["label"] for r in http["checks"][:91]] == [r["label"] for r in old_http["checks"]]
    assert all(r["label"].startswith("roster AI approval:") for r in http["checks"][91:])
    commands = [json.loads(line) for line in (output / "linux-deno-commands.jsonl").read_text().splitlines()]
    assert len(commands) == 4 and all(c[1] not in ["test", "run"] or all(flag in c for flag in ["--cached-only", "--no-prompt"]) for c in commands)
    worker_root = candidate / "scripts/tests/fixtures/receipt_worker_observation_v1"
    worker = json.loads((worker_root / "manifest.json").read_text())
    worker_tree = tree(worker_root)
    assert set(worker_tree) == {"manifest.json", *worker["files"]}
    assert all(worker_tree[n]["sha256"] == sha for n, sha in worker["files"].items())
    origin = json.loads((worker_root / "result.json").read_text())
    assert origin["status"] == "pass" and origin["finished_at"] == worker["origin_finished_at"]
    assert all(origin[k] for k in ["sources_unchanged", "runner_unchanged", "support_unchanged"])
    fixtures_root = output / "linux-decoder/fixtures"
    fixtures = json.loads((fixtures_root / "manifest.json").read_text())
    fixture_tree = tree(fixtures_root)
    names = [r["path"] for r in fixtures["fixtures"]]
    assert len(names) == len(set(names)) and set(fixture_tree) == {"manifest.json", *names}
    assert all(fixture_tree[r["path"]]["sha256"] == r["sha256"] for r in fixtures["fixtures"])
    save("fixture-provenance.json", {"immutable_worker_manifest_sha256": worker_tree["manifest.json"]["sha256"],
         "immutable_worker_files": worker_tree, "worker_manifest": worker, "origin_receipt": origin,
         "generated_linux_fixture_count": len(names), "generated_linux_files": fixture_tree,
         "generated_linux_manifest_sha256": fixture_tree["manifest.json"]["sha256"],
         "generator_source_sha256": expected["tools/roster-decoder/generate_fixtures.py"]["sha256"],
         "generator_version_metadata": execution["fixture_generator_version_metadata"],
         "generation_log_sha256": observe(output / "linux-decoder/generation.log")["sha256"],
         "synthetic_only": fixtures["synthetic_only"], "provider_accuracy_verified": fixtures["provider_accuracy_verified"],
         "current_SQL_executed": False})
    security_name = linux["dependency_security"]["command"][4]
    assert re.fullmatch(r"collect_roster_decoder_[0-9a-f]{12}_dependency_security", security_name)
    task_name = security_name.removesuffix("_dependency_security")
    image_tag = task_name + ":qa"
    assert image_tag in (output / "linux-decoder/build.log").read_text()
    save("permissions-and-local-scope.json", {"dependency_cache_command": validation["phases"]["frozen_dependency_cache"]["command"],
         "type_check_command": validation["phases"]["types"]["command"], "unit_command": units["command"],
         "http_command": http_full["command"], "http_environment": http_full["environment"], "linux_deno_commands": commands,
         "dependency_security_command": linux["dependency_security"]["command"],
         "docker_build_recipe_from_executed_maintained_source": ["docker", "build", "--network=none", "--no-cache", "-t", image_tag, str(output / "linux-decoder/build-context")],
         "docker_build_recipe_source_sha256": expected["scripts/tests/verify_roster_decoder.py"]["sha256"],
         "fresh_image_id": linux["image_id"], "fresh_image_tag": image_tag, "decoder_build_sha256": linux["decoder_build_sha256"],
         "provider_denial_observations": http["blocked_provider_attempts"], "original91_and_new12_passed": True,
         "check_cache_distinction": "Deno2.5.6 check/cache frozen graph do not support cached-only and do not execute application runtime; test/run commands are cached-only/no-prompt.",
         "build_and_security_network": "Build network-none, Dockerfile RUN network-none, no-index/hash/all-binary offline pip, security container network-none.",
         "supervisor_network": "Actual isolated Docker bridge with published127.0.0.1 listener and synthetic random secret, not network-none.",
         "runtime_scope": "Loopback-only synthetic dependencies and provider host denials; no real Auth gateway/SQL/provider delivery/hosted acceptance.",
         "network_observation_limit": "Exact command/source/assertion and provider-denial records; no packet capture or independent observation of every packet.",
         "current_SQL_executed": validation["current_sql_executed"], "current_checkout_acceptance": False,
         "default_format_failure": "Previously observed unchanged baseline failure retained; no formatter pass/waiver."})
    docker = Path("/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker")
    host = (E / "docker-socket.stdout").read_text().strip()
    assert host.startswith("unix://")
    environment = {"PATH": os.defpath, "DOCKER_HOST": host}
    cleanup_commands = []
    for label, target in [("supervisor", execution["supervisor_container_id"]), ("security", security_name)]:
        cmd = [str(docker), "inspect", "--type", "container", target]
        readback = subprocess.run(cmd, env=environment, capture_output=True, text=True, timeout=15)
        (E / ("cleanup-" + label + ".stdout")).write_text(readback.stdout)
        (E / ("cleanup-" + label + ".stderr")).write_text(readback.stderr)
        absent = readback.returncode == 1 and ("no such object: " + target) in readback.stderr.lower()
        assert absent, (label, readback.returncode, readback.stderr)
        cleanup_commands.append({"label": label, "command": cmd, "deadline_seconds": 15,
             "exit_code": readback.returncode, "confirmed_exact_absent": absent,
             "stderr_sha256": observe(E / ("cleanup-" + label + ".stderr"))["sha256"]})
    command = [str(docker), "ps", "--all", "--filter", "ancestor=" + linux["image_id"], "--format", "{{.ID}}"]
    containers = subprocess.run(command, env=environment, check=True, capture_output=True, text=True, timeout=15)
    assert not containers.stdout.strip()
    ps = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="],
                        check=True, capture_output=True, text=True, timeout=15)
    table = {}
    for line in ps.stdout.splitlines():
        row = line.split(None, 4)
        if len(row) == 5:
            table[row[0]] = {"ppid": int(row[1]), "pgid": int(row[2]), "stat": row[3], "birth": row[4]}
    observed = execution["observed_owned_processes"]
    matched = {n: row for n, row in table.items() if n in observed and row["birth"] == observed[n]["birth"]}
    live = {n: row for n, row in matched.items() if not row["stat"].startswith("Z")}
    assert not live
    save("owned-cleanup-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "commands": cleanup_commands, "new_image_container_query": {"command": command, "exit_code": containers.returncode, "stdout": containers.stdout},
         "original_cleanup": execution["remaining_owned_process_cleanup"], "observed_original_process_identities": observed,
         "birth_matched_processes": matched, "live_owned_processes": live, "http_reported_closed_listeners": http["servers_closed"],
         "scoped_cleanup_pass": True, "new_local_image_retained": True, "global_daemon_cleanup_claimed": False})
    save("phase-summary.json", {"status": "pass", "elapsed_seconds": execution["elapsed_seconds"],
         "runner_contract_tests": 77, "types": validation["phases"]["types"]["files_checked"],
         "unit_files": units["test_file_count"], "unit_tests": units["tests_passed"], "unit_steps": units["steps_passed"],
         "unit_failed": 0, "unit_ignored": 0, "HTTP_checks": len(http["checks"]), "HTTP_failed": 0,
         "Linux_cases": len(linux["cases"]), "signed_Linux_HTTP": validation["phases"]["linux_decoder"]["integration"],
         "regressions": validation["phases"]["linux_decoder"]["regressions"], "security": linux["dependency_security"],
         "fresh_image_id": linux["image_id"], "fresh_image_tag": image_tag, "decoder_build_sha256": linux["decoder_build_sha256"],
         "actual_fresh_image_toolchain": execution["fresh_image_toolchain"], "whole_build_Linux_deadlines": [1200, 300, 600],
         "current_SQL_executed": False, "current_checkout_acceptance": False})
    print(json.dumps({"status": "complete_evidence_readback", "output_files": len(copies),
          "output_bytes": sum(r["before"]["bytes"] for r in copies), "cache_files": len(cache),
          "cache_bytes": sum(v["bytes"] for v in cache.values()), "current_count": len(current_after),
          "current_changed": sorted(changed), "current_added": sorted(added), "generated_fixtures": len(names),
          "owned_cleanup": "pass", "regressions_actual": validation["phases"]["linux_decoder"]["regressions"]["tests_passed"]}, indent=2))


if __name__ == "__main__":
    main()
