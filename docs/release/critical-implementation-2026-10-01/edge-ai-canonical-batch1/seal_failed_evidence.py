"""Read and physically copy terminal failed-cohort evidence; never rerun QA."""
from pathlib import Path
import datetime as dt
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tomllib

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
OLD = E.parent / "edge-offline-canonical-batch1"
PROMOTION = E.parent / "root-ai-dispatch-promotion-batch1"


def observe(path):
    a = path.lstat()
    assert stat.S_ISREG(a.st_mode), str(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    b = path.lstat()
    identity = lambda s: [s.st_dev, s.st_ino, stat.S_IMODE(s.st_mode), s.st_size,
                          s.st_mtime_ns, s.st_ctime_ns, s.st_nlink]
    assert identity(a) == identity(b), str(path)
    return {"sha256": digest, "bytes": b.st_size, "mode": stat.S_IMODE(b.st_mode),
            "identity": identity(b)}


def save(name, value):
    p = E / name
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("x") as f:
        f.write(json.dumps(value, indent=2) + "\n")


def copy(original, destination):
    before = observe(original)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with original.open("rb") as src, destination.open("xb") as dst:
        shutil.copyfileobj(src, dst)
    os.chmod(destination, before["mode"])
    copied, after = observe(destination), observe(original)
    assert before == after
    assert all(before[k] == copied[k] for k in ["sha256", "bytes", "mode"])
    assert before["identity"][:2] != copied["identity"][:2]
    return {"original": str(original), "copy": str(destination),
            "before": before, "copied": copied, "after": after}


def inventory(base, name):
    # Isolate transitive module globals when reading two different checkouts.
    code = ("import sys,json;sys.path.insert(0,sys.argv[1]);"
            "import run_edge_ci;print(json.dumps([str(p) for p in run_edge_ci.source_paths()]))")
    result = subprocess.run([sys.executable, "-B", "-c", code, str(base / "scripts/qa")],
                            check=True, capture_output=True, text=True, timeout=15)
    paths = [Path(p) for p in json.loads(result.stdout)]
    return {str(p.relative_to(base)): observe(p) for p in paths}


def main():
    freeze = json.loads((E / "private-source-freeze.json").read_text())
    composition = json.loads((E / "composition-provenance.json").read_text())
    result = json.loads((E / "execution-result.json").read_text())
    private = Path(freeze["private_candidate"])
    output = private / ".cache/canonical"
    validation = json.loads((output / "validation.json").read_text())
    http = json.loads((output / "edge-http/report.json").read_text())["runtime_result"]
    assert result["exit_code"] == 1 and result["status"] == validation["status"] == "fail"
    assert result["private_source_unchanged"] and validation["source_unchanged"]
    assert validation["phases"]["edge_http"]["status"] == "fail"
    assert "linux_decoder" not in validation["phases"]
    assert "new_image_id" not in result
    files = sorted(p for p in output.rglob("*") if p.is_file())
    assert not any(p.is_symlink() for p in output.rglob("*"))
    if (E / "canonical-output-copy.json").exists():
        completed_copy = json.loads((E / "canonical-output-copy.json").read_text())
        copies = completed_copy["files"]
        assert len(copies) == len(files)
        for row in copies:
            assert observe(Path(row["original"])) == row["before"] == row["after"]
            assert observe(Path(row["copy"])) == row["copied"]
    else:
        copies = [copy(p, E / "canonical" / p.relative_to(output)) for p in files]
        save("canonical-output-copy.json", {"copied_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
             "count": len(copies), "bytes": sum(r["before"]["bytes"] for r in copies),
             "before_copy_after_sha_size_mode_equal": True, "physically_distinct": True, "files": copies})
    expected = {r["path"]: {"sha256": r["sha256"], "bytes": r["bytes"], "mode": r["copy_mode"]}
                for r in freeze["source_manifest"]}
    private_after = inventory(private, "failed_private_inventory")
    assert len(private_after) == 140 and set(private_after) == set(expected)
    assert all(all(private_after[n][k] == row[k] for k in row) for n, row in expected.items())
    old_batch = json.loads((OLD / "batch.json").read_text())
    old_after = {n: observe(OLD / n) for n in old_batch["artifacts"]}
    assert old_after == composition["original519_before"]
    old_seals = {n: observe(OLD / n) for n in composition["original519_seal_before_after"]}
    assert old_seals == composition["original519_seal_before_after"]
    base_after = {n: observe(Path(json.loads((OLD / "private-source-freeze.json").read_text())["private_candidate"]) / n)
                  for n in composition["original137_before_after"]}
    assert base_after == composition["original137_before_after"]
    root39 = {n: observe(ROOT / n) for n in composition["root39_before_after"]}
    assert root39 == composition["root39_before_after"]
    assert observe(PROMOTION / "packet-files.json") == composition["root_promotion_seal"]
    root25 = {n: observe(ROOT / n) for n in composition["current25_promotion_closure_before_after"]}
    closure_drift = {n: v for n, v in root25.items() if v != composition["current25_promotion_closure_before_after"][n]}
    external = {r["copy"]: observe(Path(r["copy"])) for r in freeze["external_inputs"]}
    assert all(external[r["copy"]]["sha256"] == r["sha256"] for r in freeze["external_inputs"])
    current_before = inventory(ROOT, "current_root_inventory")
    changed = {n: v for n, v in current_before.items() if n in expected and
               any(v[k] != expected[n][k] for k in ["sha256", "bytes", "mode"])}
    added = {n: v for n, v in current_before.items() if n not in expected}
    removed = sorted(set(expected) - set(current_before))
    snapshots = [copy(ROOT / n, E / "current-source-snapshots" / n) for n in sorted(set(changed) | set(added))]
    current_after = inventory(ROOT, "current_root_inventory_after")
    assert current_before == current_after
    configured = sorted(tomllib.loads((ROOT / "supabase/config.toml").read_text())["functions"])
    source_endpoints = sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts"))
    manifest = json.loads((ROOT / "contracts/edge-functions.json").read_text())
    save("final-source-input-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "private_count": 140, "private_manifest": private_after, "current_count": len(current_after),
         "current_before": current_before, "current_after": current_after, "changed": changed,
         "added": added, "removed": removed, "current_observation_stable": True,
         "current_changed_and_added_physical_copies": snapshots,
         "current_configured_endpoints": configured, "current_source_endpoints": source_endpoints,
         "current_manifest_endpoint_count": len(manifest["functions"]),
         "accepted_dated_loader_endpoint_count": len(http["literal_loader_entrypoints"]),
         "original519_unchanged": True, "original137_unchanged": True,
         "root39_promotion_unchanged": True, "root25_current_closure_drift": closure_drift,
         "external_input_readback": external, "current_checkout_acceptance": False})
    cache = Path(freeze["deno_cache"])
    cache_manifest = {str(p.relative_to(cache)): observe(p) for p in sorted(cache.rglob("*")) if p.is_file()}
    save("deno-cache-final.json", {"initial_count": 0, "final_count": len(cache_manifest),
         "final_bytes": sum(r["bytes"] for r in cache_manifest.values()), "files": cache_manifest})
    ps = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="],
                        check=True, capture_output=True, text=True, timeout=15)
    rows = {}
    for line in ps.stdout.splitlines():
        fields = line.split(None, 4)
        if len(fields) == 5:
            rows[fields[0]] = {"ppid": int(fields[1]), "pgid": int(fields[2]),
                               "stat": fields[3], "birth": fields[4]}
    observed = result["observed_owned_processes"]
    matched = {n: v for n, v in rows.items() if n in observed and v["birth"] == observed[n]["birth"]}
    live = {n: v for n, v in matched.items() if not v["stat"].startswith("Z")}
    assert not live
    save("owned-cleanup-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "command": ["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="],
         "deadline_seconds": 15, "exit_code": ps.returncode,
         "owned_original_identities": observed, "birth_matched_processes": matched,
         "live_owned_processes": live, "original_cleanup": result["remaining_owned_process_cleanup"],
         "http_reported_closed_owned_listeners": http["servers_closed"],
         "http_reported_cleanup_mode": http["cleanup_mode"],
         "docker_build_started": False, "linux_decoder_started": False,
         "new_task_image_or_container_identity_allocated": False,
         "no_image_existence_or_global_daemon_cleanup_claim": True})
    failures = [r for r in http["checks"] if r["status"] == "fail"]
    assert len(http["checks"]) == 91 and len(failures) == 7
    assert all(r["http_status"] == 503 and r["response"] == {"error": "roster_extraction_unavailable"}
               and [d["path"] for d in r["dependencies"]] == ["/auth/v1/user"] for r in failures)
    save("failure-analysis.json", {"actual_checks": 91, "passed": 84, "failed": 7,
         "failures": failures, "blocked_provider_attempts": http["blocked_provider_attempts"],
         "observed_boundary": "All seven AI image cases authenticated, then failed with fixed 503 before reservation or decoder work.",
         "source_causality": "The promoted handler requires tuple-bound AI policy before reservation. The unchanged dated HTTP fixture supplies model/decoder identity but no policy JSON/hash or organization/project identifiers.",
         "production_policy_changed": False, "approval_validity_or_provider_acceptance_claimed": False,
         "Linux_full_phase": "not reached", "identical_retry": False})
    save("phase-summary.json", {"canonical_status": "fail", "elapsed_seconds": result["elapsed_seconds"],
         "runner_contract_tests": 77, "types": 86,
         "unit_files": validation["phases"]["units"]["test_files"],
         "unit_tests": validation["phases"]["units"]["tests"],
         "unit_steps": validation["phases"]["units"]["steps"],
         "unit_failed": validation["phases"]["units"].get("failed"),
         "unit_ignored": validation["phases"]["units"].get("ignored"),
         "http_checks": 91, "http_passed": 84, "http_failed": 7,
         "linux_decoder": "not reached", "signed_linux_http": "not reached",
         "decoder_regressions": "not reached", "same_image_security": "not reached",
         "whole_build_linux_deadlines": [1200, 300, 600], "full_invocations": 1})
    print(json.dumps({"status": "failed_cohort_readback_complete", "output_files": len(copies),
                      "output_bytes": sum(r["before"]["bytes"] for r in copies),
                      "private_count": 140, "current_count": len(current_after),
                      "cache_count": len(cache_manifest), "current_changed": sorted(changed),
                      "current_added": sorted(added), "root25_drift": sorted(closure_drift)}, indent=2))


if __name__ == "__main__":
    main()
