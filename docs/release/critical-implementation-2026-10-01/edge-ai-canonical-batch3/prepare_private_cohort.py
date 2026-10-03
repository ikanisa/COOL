"""Physically copy failed140 and replace only the root-approved typed HTTP fixture."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
FAILED = E.parent / "edge-ai-canonical-batch2"
ORIGINAL = E.parent / "edge-offline-canonical-batch1"
PROMOTION = E.parent / "root-edge-ai-http-fixture-promotion2"
COHORT = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-EDGE-AI-20261002-BATCH3")
QA = "scripts/qa/edge_http_runtime_uat.ts"


def observe(path):
    before = path.lstat()
    assert stat.S_ISREG(before.st_mode) and before.st_nlink == 1, str(path)
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    after = path.lstat()
    identity = lambda s: [s.st_dev, s.st_ino, stat.S_IMODE(s.st_mode), s.st_size,
                          s.st_mtime_ns, s.st_ctime_ns, s.st_nlink]
    assert identity(before) == identity(after), str(path)
    return {"sha256": sha, "bytes": after.st_size, "mode": stat.S_IMODE(after.st_mode),
            "identity": identity(after)}


def copy(source, target):
    before = observe(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as src, target.open("xb") as dst:
        shutil.copyfileobj(src, dst)
    os.chmod(target, before["mode"])
    actual, after = observe(target), observe(source)
    assert before == after
    assert all(before[k] == actual[k] for k in ["sha256", "bytes", "mode"])
    assert before["identity"][:2] != actual["identity"][:2]
    return {"original": str(source), "copy": str(target), "before": before,
            "copied": actual, "after": after}


def save(name, value):
    with (E / name).open("x") as f:
        f.write(json.dumps(value, indent=2) + "\n")


def packet(directory):
    batch = json.loads((directory / "batch.json").read_text())
    observations = {n: observe(directory / n) for n in batch["artifacts"]}
    assert all(all(observations[n][k] == row[k] for k in ["sha256", "bytes", "mode"])
               for n, row in batch["artifacts"].items())
    return {"leaves": observations, "seals": {n: observe(directory / n) for n in ["batch.json", "SHA256SUMS"]}}


def main():
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    assert observe(FAILED / "batch.json")["sha256"] == "98fc0cb31a6f9509ecd026560b5842bb0371c9d3107aca222cb518f3ddc7f4b7"
    assert observe(ORIGINAL / "batch.json")["sha256"] == "5c237457fb73a5eed997207e1e054969174b3777fa6ceeebe34cb46d5bfd327c"
    failed_before, original_before = packet(FAILED), packet(ORIGINAL)
    earlier_failed400 = packet(E.parent / "edge-ai-canonical-batch1")
    assert len(earlier_failed400["leaves"]) == 400
    assert len(failed_before["leaves"]) == 181 and len(original_before["leaves"]) == 519
    prior = json.loads((FAILED / "private-source-freeze.json").read_text())
    composition = json.loads((FAILED / "composition-provenance.json").read_text())
    baseline = Path(prior["private_candidate"])
    prior_before = {r["path"]: observe(baseline / r["path"]) for r in prior["source_manifest"]}
    assert len(prior_before) == 140
    assert all(prior_before[r["path"]]["sha256"] == r["sha256"] and prior_before[r["path"]]["mode"] == r["copy_mode"]
               for r in prior["source_manifest"])
    original_source = Path(json.loads((ORIGINAL / "private-source-freeze.json").read_text())["private_candidate"])
    original137 = {n: observe(original_source / n) for n in composition["original137_before_after"]}
    assert original137 == composition["original137_before_after"]
    root39 = {n: observe(ROOT / n) for n in composition["root39_before_after"]}
    root25 = {n: observe(ROOT / n) for n in composition["current25_promotion_closure_before_after"]}
    assert root39 == composition["root39_before_after"] and root25 == composition["current25_promotion_closure_before_after"]
    fixture_seal = observe(PROMOTION / "packet-files.json")
    assert fixture_seal["sha256"] == "eee7156644ad404ab878d8b809d9d0c17876c401541be6ea45755de0362028ac"
    fixture_manifest = {row["path"]: row for row in json.loads((PROMOTION / "packet-files.json").read_text())["files"]}
    fixture4 = {n: observe(ROOT / n) for n in fixture_manifest}
    assert all(fixture4[n]["sha256"] == row["sha256"] and fixture4[n]["bytes"] == row["bytes"] for n, row in fixture_manifest.items())
    fixture_promotion = json.loads((PROMOTION / "promotion.json").read_text())
    assert fixture_promotion["applied_sha256"] == "27fcd434f5a4c5c30d298c1df2e1e059c22e206e82ec42e6a84523f9c12293c9"
    current_qa = observe(ROOT / QA)
    assert current_qa["sha256"] == fixture_promotion["applied_sha256"]
    assert prior_before[QA]["sha256"] == fixture_promotion["base_sha256"]
    COHORT.mkdir(mode=0o700)
    candidate, inputs, cache = COHORT / "source", COHORT / "inputs", COHORT / "deno-cache"
    candidate.mkdir(mode=0o700); inputs.mkdir(mode=0o700); cache.mkdir(mode=0o700)
    source_copies = [copy(baseline / n, candidate / n) for n in sorted(prior_before)]
    (candidate / QA).unlink()  # Only the newly owned physical copy, never its source.
    approved_delta = copy(ROOT / QA, candidate / QA)
    code = ("import sys,json;sys.path.insert(0,sys.argv[1]);import run_edge_ci;"
            "print(json.dumps([str(p) for p in run_edge_ci.source_paths()]))")
    run = subprocess.run([sys.executable, "-B", "-c", code, str(candidate / "scripts/qa")],
                         check=True, capture_output=True, text=True, timeout=15)
    discovered = sorted(str(Path(p).relative_to(candidate)) for p in json.loads(run.stdout))
    assert discovered == sorted(prior_before)
    manifest = []
    for n in discovered:
        origin = ROOT / n if n == QA else baseline / n
        before, actual, after = observe(origin), observe(candidate / n), observe(origin)
        assert before == after and all(before[k] == actual[k] for k in ["sha256", "bytes", "mode"])
        manifest.append({"path": n, "sha256": actual["sha256"], "bytes": actual["bytes"],
             "before_mode": before["mode"], "copy_mode": actual["mode"], "after_mode": after["mode"],
             "before_identity": before["identity"], "copy_identity": actual["identity"], "after_identity": after["identity"],
             "origin": str(origin), "origin_class": "root_approved_HTTP_fixture" if n == QA else "preserved_failed140"})
    external_copies, external = [], []
    for row in prior["external_inputs"]:
        origin = Path(row["copy"])
        assert observe(origin)["sha256"] == row["sha256"]
        destination = inputs / origin.relative_to(Path(prior["cohort"]) / "inputs")
        copied = copy(origin, destination)
        external_copies.append(copied)
        external.append({"kind": row["kind"], "original": str(origin), "copy": str(destination),
             "sha256": copied["copied"]["sha256"], "bytes": copied["copied"]["bytes"],
             "original_mode": copied["before"]["mode"], "copy_mode": copied["copied"]["mode"],
             "original_identity": copied["before"]["identity"], "copy_identity": copied["copied"]["identity"]})
    auxiliary = copy(Path(prior["auxiliary_dated12_manifest"]["copy"]), inputs / "dated12-edge-functions.json")
    assert current_qa == observe(ROOT / QA) and fixture4 == {n: observe(ROOT / n) for n in fixture4}
    assert fixture_seal == observe(PROMOTION / "packet-files.json")
    assert failed_before == packet(FAILED) and original_before == packet(ORIGINAL)
    assert earlier_failed400 == packet(E.parent / "edge-ai-canonical-batch1")
    assert prior_before == {n: observe(baseline / n) for n in prior_before}
    assert original137 == {n: observe(original_source / n) for n in original137}
    assert root39 == {n: observe(ROOT / n) for n in root39} and root25 == {n: observe(ROOT / n) for n in root25}
    assert not list(cache.iterdir())
    freeze = {"frozen_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "root": str(ROOT),
        "private_candidate": str(candidate), "cohort": str(COHORT), "source_count": len(manifest),
        "exact_current_dynamic_inventory": False, "exact_composed_private_dynamic_inventory": True,
        "composition": "Exact preserved failed140 plus the single root-approved HTTP fixture; retains dated12 config/loader and separate12 manifest, no current-checkout acceptance.",
        "before_copy_after_mode_hash_equal": True, "all_private_file_inodes_distinct": True,
        "initial_deno_file_count": 0, "deno_cache": str(cache), "source_manifest": manifest,
        "publisher_receipt_original": prior["publisher_receipt_copy"],
        "publisher_receipt_copy": str(inputs / "publisher-inputs.json"),
        "publisher_sha256": prior["publisher_sha256"], "wheel_source": str(inputs / "wheels"),
        "metadata_directory": str(inputs / "primary"), "external_inputs": external,
        "auxiliary_dated12_manifest": auxiliary, "maintained_source_mutations": 0,
        "network_acquisition": False, "full_gate_started": False}
    save("private-source-freeze.json", freeze)
    save("composition-provenance.json", {"started_at_utc": started, "frozen_at_utc": freeze["frozen_at_utc"],
        "original_failed181_before_after": failed_before, "earlier_failed400_before_after": earlier_failed400, "original_passed519_before_after": original_before,
        "failed140_before_after": prior_before, "original137_before_after": original137,
        "root39_before_after": root39, "current25_promotion_closure_before_after": root25,
        "root_fixture3_before_after": fixture4, "root_fixture_promotion_seal": fixture_seal,
        "baseline140_physical_copies": source_copies, "sole_approved_QA_delta": approved_delta,
        "external_physical_copies": external_copies, "source140_discovered": discovered,
        "current_checkout_acceptance_claimed": False, "unchanged_default_format_failure_disclosed": True})
    (E / "private-source-freeze.sha256").write_text(observe(E / "private-source-freeze.json")["sha256"] + "\n")
    print(json.dumps({"status": "private140_frozen", "source_count": len(manifest),
          "initial_cache_count": 0, "sole_delta_sha256": current_qa["sha256"],
          "prior181_400_519_and140_137_unchanged": True, "current_checkout_acceptance_claimed": False}, indent=2))


if __name__ == "__main__":
    main()
