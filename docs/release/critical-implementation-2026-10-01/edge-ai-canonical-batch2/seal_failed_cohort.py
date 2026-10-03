"""Seal the terminal type failure and unchanged inputs; no acceptance invocation."""
from pathlib import Path
import datetime as dt
import importlib.util
import json
import subprocess
import sys
import tomllib

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
spec = importlib.util.spec_from_file_location("owned_batch2_preparation", E / "prepare_private_cohort.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
observe, copy, packet, save = helpers.observe, helpers.copy, helpers.packet, helpers.save


def inventory(base):
    code = ("import sys,json;sys.path.insert(0,sys.argv[1]);import run_edge_ci;"
            "print(json.dumps([str(p) for p in run_edge_ci.source_paths()]))")
    result = subprocess.run([sys.executable, "-B", "-c", code, str(base / "scripts/qa")],
                            check=True, capture_output=True, text=True, timeout=15)
    return {str(Path(n).relative_to(base)): observe(Path(n)) for n in json.loads(result.stdout)}


def main():
    freeze = json.loads((E / "private-source-freeze.json").read_text())
    provenance = json.loads((E / "composition-provenance.json").read_text())
    result = json.loads((E / "execution-result.json").read_text())
    private = Path(freeze["private_candidate"])
    output = private / ".cache/canonical"
    validation = json.loads((output / "validation.json").read_text())
    assert result["status"] == validation["status"] == "fail" and result["exit_code"] == 1
    assert result["private_source_unchanged"] and validation["source_unchanged"]
    assert set(validation["phases"]) == {"runner_contract", "frozen_dependency_cache", "types"}
    assert validation["phases"]["types"]["status"] == "fail"
    assert not any(p.is_symlink() for p in output.rglob("*"))
    files = sorted(p for p in output.rglob("*") if p.is_file())
    copies = [copy(p, E / "canonical" / p.relative_to(output)) for p in files]
    save("canonical-output-copy.json", {"copied_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "count": len(copies), "bytes": sum(r["before"]["bytes"] for r in copies),
         "before_copy_after_sha_size_mode_equal": True, "physical_identities_distinct": True, "files": copies})
    expected = {r["path"]: {"sha256": r["sha256"], "bytes": r["bytes"], "mode": r["copy_mode"]}
                for r in freeze["source_manifest"]}
    private_after = inventory(private)
    assert set(private_after) == set(expected) and len(private_after) == 140
    assert all(all(private_after[n][k] == row[k] for k in row) for n, row in expected.items())
    assert packet(E.parent / "edge-ai-canonical-batch1") == provenance["original_failed400_before_after"]
    assert packet(E.parent / "edge-offline-canonical-batch1") == provenance["original_passed519_before_after"]
    prior_source = Path(json.loads((E.parent / "edge-ai-canonical-batch1/private-source-freeze.json").read_text())["private_candidate"])
    original_source = Path(json.loads((E.parent / "edge-offline-canonical-batch1/private-source-freeze.json").read_text())["private_candidate"])
    assert provenance["failed140_before_after"] == {n: observe(prior_source / n) for n in provenance["failed140_before_after"]}
    assert provenance["original137_before_after"] == {n: observe(original_source / n) for n in provenance["original137_before_after"]}
    assert provenance["root39_before_after"] == {n: observe(ROOT / n) for n in provenance["root39_before_after"]}
    assert provenance["current25_promotion_closure_before_after"] == {n: observe(ROOT / n) for n in provenance["current25_promotion_closure_before_after"]}
    promotion = E.parent / "root-edge-ai-http-fixture-promotion1"
    assert provenance["root_fixture4_before_after"] == {n: observe(promotion / n) for n in provenance["root_fixture4_before_after"]}
    assert provenance["root_fixture_promotion_seal"] == observe(promotion / "packet-files.json")
    external = {r["copy"]: observe(Path(r["copy"])) for r in freeze["external_inputs"]}
    assert all(external[r["copy"]]["sha256"] == r["sha256"] for r in freeze["external_inputs"])
    current_before = inventory(ROOT)
    added = {n: v for n, v in current_before.items() if n not in expected}
    changed = {n: v for n, v in current_before.items() if n in expected and
               any(v[k] != expected[n][k] for k in ["sha256", "bytes", "mode"])}
    removed = sorted(set(expected) - set(current_before))
    current_copies = [copy(ROOT / n, E / "current-source-snapshots" / n) for n in sorted(set(added) | set(changed))]
    current_after = inventory(ROOT)
    assert current_before == current_after
    configured = sorted(tomllib.loads((ROOT / "supabase/config.toml").read_text())["functions"])
    endpoints = sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts"))
    manifest = json.loads((ROOT / "contracts/edge-functions.json").read_text())
    cache = Path(freeze["deno_cache"])
    cached = {str(p.relative_to(cache)): observe(p) for p in sorted(cache.rglob("*")) if p.is_file()}
    save("final-source-input-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "private_manifest": private_after, "private_count": 140, "private_unchanged": True,
         "current_before": current_before, "current_after": current_after, "current_count": len(current_after),
         "current_changed": changed, "current_added": added, "current_removed": removed,
         "current_drift_physical_copies": current_copies, "current_configured_endpoints": configured,
         "current_source_endpoints": endpoints, "current_manifest_endpoint_count": len(manifest["functions"]),
         "private_dated_literal_loader_count": 12, "current_checkout_acceptance": False,
         "prior_failed400_140_and_passed519_137_unchanged": True,
         "root39_current25_and_fixture_promotion4_unchanged": True, "external_inputs": external,
         "cache_initial_count": 0, "cache_final_count": len(cached),
         "cache_final_bytes": sum(v["bytes"] for v in cached.values()), "cache_manifest": cached})
    ps = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="],
                        check=True, capture_output=True, text=True, timeout=15)
    table = {}
    for line in ps.stdout.splitlines():
        fields = line.split(None, 4)
        if len(fields) == 5:
            table[fields[0]] = {"ppid": int(fields[1]), "pgid": int(fields[2]), "stat": fields[3], "birth": fields[4]}
    owned = result["observed_owned_processes"]
    matched = {n: row for n, row in table.items() if n in owned and row["birth"] == owned[n]["birth"]}
    live = {n: row for n, row in matched.items() if not row["stat"].startswith("Z")}
    assert not live
    save("owned-cleanup-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "command": ["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="], "deadline_seconds": 15,
         "exit_code": ps.returncode, "observed_owned_identities": owned, "birth_matched_processes": matched,
         "live_owned_processes": live, "original_cleanup": result["remaining_owned_process_cleanup"],
         "http_started": False, "docker_build_started": False, "linux_decoder_started": False,
         "new_task_image_or_container_identity_allocated": False, "no_global_daemon_absence_claim": True})
    type_log = (output / "types.stderr").read_text()
    assert "TS2783 [ERROR]" in type_log and "TS2785 [ERROR]" in type_log
    attempted = [arg for arg in validation["phases"]["types"]["command"] if arg.endswith(".ts")]
    save("failure-analysis.json", {"status": "type_failure", "full_invocations": 1,
         "elapsed_seconds": result["elapsed_seconds"], "runner_contracts": "77 passed",
         "frozen_dependency_cache": "passed", "type_files_attempted": len(attempted), "type_result": "fail",
         "diagnostics": ["TS2783 duplicate ROSTER_AI_APPROVAL_JSON", "TS2785 const-union environmentPatch spread always overwrites this property"],
         "affected_source": "scripts/qa/edge_http_runtime_uat.ts", "affected_lines": [1303, 1307],
         "unit_http_build_linux_regression_security": "not reached", "source_mutation": False,
         "retry": False, "prior_failures_preserved": True,
         "proposed_repair": "Represent the separate override map without duplicate object-literal spread; preserve every negative value/deletion and all original assertions. Root review and new execution authorization required."})
    print(json.dumps({"status": "failed_type_cohort_readback_complete", "output_files": len(copies),
          "output_bytes": sum(r["before"]["bytes"] for r in copies), "cache_files": len(cached),
          "cache_bytes": sum(v["bytes"] for v in cached.values()), "current_count": len(current_after),
          "current_changed": sorted(changed), "current_added": sorted(added)}, indent=2))


if __name__ == "__main__":
    main()
