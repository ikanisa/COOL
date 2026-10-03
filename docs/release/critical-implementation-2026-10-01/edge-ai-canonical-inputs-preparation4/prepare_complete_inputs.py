"""Prepare/validate every real offline CLI input without invoking canonical QA."""
from pathlib import Path
import datetime as dt
import hashlib
import importlib.util
import json
import os
import stat
import subprocess
import sys

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
PRIOR = E.parent / "edge-ai-canonical-batch3"
ORIGINAL = E.parent / "edge-offline-canonical-batch1"
spec = importlib.util.spec_from_file_location("prior_preparation_helpers", PRIOR / "prepare_private_cohort.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
observe, copy, packet = helpers.observe, helpers.copy, helpers.packet
COHORT = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-EDGE-AI-INPUTS-20261002-PREPARATION4")
PIN = "58ba030a43beab73906753486051c6a3499a00a70bfa1c9e018a0fb4554cfa74"


def save(name, value):
    with (E / name).open("x") as stream:
        stream.write(json.dumps(value, indent=2) + "\n")


def file_row(path):
    actual = observe(path)
    assert actual["identity"][-1] == 1
    return {"path": str(path), "kind": "regular_file", "sha256": actual["sha256"],
            "bytes": actual["bytes"], "mode_octal": oct(actual["mode"]), "mode": actual["mode"],
            "links": actual["identity"][-1], "symlink": False, "identity": actual["identity"]}


def directory_row(path):
    info = path.lstat()
    assert stat.S_ISDIR(info.st_mode) and not path.is_symlink()
    entries = {str(p.relative_to(path)): file_row(p) for p in sorted(path.rglob("*")) if p.is_file()}
    assert not any(p.is_symlink() for p in path.rglob("*"))
    return {"path": str(path), "kind": "directory", "mode_octal": oct(stat.S_IMODE(info.st_mode)),
            "links": info.st_nlink, "symlink": False, "file_count": len(entries), "files": entries,
            "manifest_sha256": hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()}


def main():
    prior_packets = {name: packet(E.parent / name) for name in ["edge-offline-canonical-batch1",
         "edge-ai-canonical-batch1", "edge-ai-canonical-batch2", "edge-ai-canonical-batch3"]}
    assert prior_packets["edge-ai-canonical-batch3"]["seals"]["batch.json"]["sha256"] == "933a3ed6c02e6b1c75485ef9e93ca815a402c1c9b88ec80eaa0e477db396c222"
    prior_freeze = json.loads((PRIOR / "private-source-freeze.json").read_text())
    original_freeze = json.loads((ORIGINAL / "private-source-freeze.json").read_text())
    baseline = Path(prior_freeze["private_candidate"])
    original_receipt = Path(original_freeze["publisher_receipt_copy"])
    assert observe(original_receipt)["sha256"] == PIN
    prior_before = {r["path"]: observe(baseline / r["path"]) for r in prior_freeze["source_manifest"]}
    assert len(prior_before) == 140 and all(prior_before[r["path"]]["sha256"] == r["sha256"]
             and prior_before[r["path"]]["mode"] == r["copy_mode"] for r in prior_freeze["source_manifest"])
    assert prior_before["scripts/qa/edge_http_runtime_uat.ts"]["sha256"] == "27fcd434f5a4c5c30d298c1df2e1e059c22e206e82ec42e6a84523f9c12293c9"
    COHORT.mkdir(mode=0o700)
    source, inputs, cache = COHORT / "source", COHORT / "inputs", COHORT / "deno-cache"
    source.mkdir(mode=0o700); inputs.mkdir(mode=0o700); cache.mkdir(mode=0o700)
    source_copies = [copy(baseline / n, source / n) for n in sorted(prior_before)]
    external_copies, externals = [], []
    for row in original_freeze["external_inputs"]:
        original = Path(row["copy"])
        assert observe(original)["sha256"] == row["sha256"]
        target = inputs / original.relative_to(Path(original_freeze["cohort"]) / "inputs")
        evidence = copy(original, target)
        assert evidence["copied"]["mode"] == 0o444 and evidence["copied"]["identity"][-1] == 1
        external_copies.append(evidence)
        externals.append({"kind": row["kind"], "original": str(original), "copy": str(target),
             "sha256": evidence["copied"]["sha256"], "bytes": evidence["copied"]["bytes"],
             "original_mode": evidence["before"]["mode"], "copy_mode": evidence["copied"]["mode"],
             "original_identity": evidence["before"]["identity"], "copy_identity": evidence["copied"]["identity"]})
    publisher_path = inputs / "publisher-inputs.json"
    receipt_copy = copy(original_receipt, publisher_path)
    assert receipt_copy["copied"]["sha256"] == PIN and receipt_copy["copied"]["mode"] == 0o444
    # The separately bound receipt is now also in the explicit full input list.
    external_copies.append(receipt_copy)
    externals.append({"kind": "publisher_receipt", "original": str(original_receipt), "copy": str(publisher_path),
             "sha256": PIN, "bytes": receipt_copy["copied"]["bytes"], "original_mode": receipt_copy["before"]["mode"],
             "copy_mode": receipt_copy["copied"]["mode"], "original_identity": receipt_copy["before"]["identity"],
             "copy_identity": receipt_copy["copied"]["identity"]})
    auxiliary = copy(Path(prior_freeze["auxiliary_dated12_manifest"]["copy"]), inputs / "dated12-edge-functions.json")
    code = ("import sys,json;sys.path.insert(0,sys.argv[1]);import run_edge_ci;"
            "print(json.dumps([str(p) for p in run_edge_ci.source_paths()]))")
    discovery = subprocess.run([sys.executable, "-B", "-c", code, str(source / "scripts/qa")],
                               check=True, capture_output=True, text=True, timeout=15)
    names = sorted(str(Path(p).relative_to(source)) for p in json.loads(discovery.stdout))
    assert names == sorted(prior_before)
    manifest = []
    for name in names:
        copied = observe(source / name)
        original = prior_before[name]
        assert all(copied[k] == original[k] for k in ["sha256", "bytes", "mode"])
        manifest.append({"path": name, "sha256": copied["sha256"], "bytes": copied["bytes"],
             "before_mode": original["mode"], "copy_mode": copied["mode"], "after_mode": original["mode"],
             "before_identity": original["identity"], "copy_identity": copied["identity"], "after_identity": original["identity"],
             "origin": str(baseline / name), "origin_class": "unchanged_reviewed140"})
    driver = PRIOR / "run_private_canonical.py"
    assert observe(driver)["sha256"] == "011e3d8ff57d96b519075343723bdb524f46cbc2e09d76f5965fb0a26e4a8e2e"
    driver_copy = copy(driver, E / "run_private_canonical.py")
    # Run only the reviewed local read/copy validator, with no acquisition/build.
    sys.path.insert(0, str(source / "scripts/qa"))
    spec = importlib.util.spec_from_file_location("reviewed_wheelhouse_preparation4", source / "scripts/qa/roster_wheelhouse.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    prepared = module.prepare_build_context(decoder_directory=source / "tools/roster-decoder",
        wheel_source=inputs / "wheels", publisher_receipt=publisher_path, publisher_sha256=PIN,
        metadata_directory=inputs / "primary", destination=COHORT / "review-only-build-context")
    module.verify_prepared_context(prepared)
    assert prepared["wheel_count"] == 6 and prepared["publisher_receipt_sha256"] == PIN
    assert prepared["network_acquisition_performed"] is False and prepared["docker_execution_performed"] is False
    assert prepared["package_installation_performed"] is False
    save("reviewed-helper-validation.json", prepared)
    deno = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
    decoder_python = ROOT / ".cache/decoder-dependency-batch1/fixture-generator-venv/bin/python"
    assert observe(deno)["sha256"] == "a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0"
    resolved_python = decoder_python.resolve(strict=True)
    assert observe(resolved_python)["sha256"] == "69b35956b6a60fdcc0e7a11c062cbd89dd389caa8a3c862221feb56105f2a643"
    command = [sys.executable, "-B", "scripts/qa/run_edge_ci.py", "--deno", str(deno),
        "--decoder-python", str(decoder_python), "--wheel-source", str(inputs / "wheels"),
        "--publisher-receipt", str(publisher_path), "--publisher-sha256", PIN,
        "--metadata-directory", str(inputs / "primary"), "--cache-dependencies", "--output", str(source / ".cache/canonical")]
    matrix = {"working_directory_source140": directory_row(source), "canonical_caller": file_row(source / "scripts/qa/run_edge_ci.py"),
        "outer_python_executable": {"CLI_path": sys.executable, "CLI_symlink": Path(sys.executable).is_symlink(), "resolved": file_row(Path(sys.executable).resolve(strict=True))},
        "--deno": file_row(deno), "--decoder-python": {"CLI_path": str(decoder_python), "CLI_symlink": decoder_python.is_symlink(), "resolved": file_row(resolved_python)},
        "--wheel-source": directory_row(inputs / "wheels"), "--publisher-receipt": file_row(publisher_path),
        "--publisher-sha256": {"value": PIN, "matched_whole_file": True}, "--metadata-directory": directory_row(inputs / "primary"),
        "frozen_lock": file_row(source / "supabase/functions/deno.lock"), "DENO_DIR": directory_row(cache),
        "--output": {"path": str(source / ".cache/canonical"), "must_be_new": True, "exists": (source / ".cache/canonical").exists()}}
    assert matrix["--wheel-source"]["file_count"] == matrix["--metadata-directory"]["file_count"] == 6
    assert matrix["DENO_DIR"]["file_count"] == 0 and matrix["--output"]["exists"] is False
    assert len(externals) == 13 and all(row["copy_mode"] == 0o444 for row in externals)
    assert prior_before == {n: observe(baseline / n) for n in prior_before}
    assert prior_packets == {n: packet(E.parent / n) for n in prior_packets}
    assert not list(cache.iterdir())
    freeze = {"frozen_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "root": str(ROOT),
        "private_candidate": str(source), "cohort": str(COHORT), "source_count": 140,
        "composition": "Unchanged reviewed140 with corrected QA27fc and complete authenticated13 offline inputs; dated12 loader, no current-checkout acceptance.",
        "exact_current_dynamic_inventory": False, "exact_composed_private_dynamic_inventory": True,
        "before_copy_after_mode_hash_equal": True, "all_private_file_inodes_distinct": True,
        "initial_deno_file_count": 0, "deno_cache": str(cache), "source_manifest": manifest,
        "publisher_receipt_original": str(original_receipt), "publisher_receipt_copy": str(publisher_path),
        "publisher_sha256": PIN, "wheel_source": str(inputs / "wheels"), "metadata_directory": str(inputs / "primary"),
        "external_inputs": externals, "auxiliary_dated12_manifest": auxiliary,
        "maintained_source_mutations": 0, "network_acquisition": False, "full_gate_started": False}
    save("private-source-freeze.json", freeze)
    save("actual-cli-input-matrix.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "status": "all_actual_inputs_present_authenticated_and_physically_bound", "exact_future_command": command,
        "command_executed": False, "matrix": matrix, "outer_driver_sha256": driver_copy["copied"]["sha256"],
        "reviewed_validator_sha256": observe(source / "scripts/qa/roster_wheelhouse.py")["sha256"],
        "actual_helper_recheck": "pass", "source_copies": source_copies, "offline_input_copies": external_copies,
        "prior402_181_400_519_packets_before_after": prior_packets,
        "publisher_receipt_separate_copy_now_explicit": True, "missing_batch3_reason": "Publisher receipt was bound outside12 old wheel/metadata rows and never copied into the declared CLI path.",
        "canonical_invocations": 0, "HTTP_Linux_build_runtime_invocations": 0, "production_acceptance": False})
    print(json.dumps({"status": "review_only_complete_inputs_validated", "candidate": str(source),
          "source_files": 140, "offline_files": 13, "wheel_count": 6,
          "receipt_sha256": PIN, "receipt_bytes": receipt_copy["copied"]["bytes"],
          "initial_cache_files": 0, "canonical_invocations": 0}, indent=2))


if __name__ == "__main__":
    main()
