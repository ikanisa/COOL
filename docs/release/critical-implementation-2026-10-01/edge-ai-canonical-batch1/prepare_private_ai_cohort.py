"""Compose only the accepted137 baseline and exact reviewed seven AI changes."""
from pathlib import Path
import datetime as dt
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import sys

EVIDENCE = Path(__file__).absolute().parent
ROOT = EVIDENCE.parents[3]
OLD = ROOT / "docs/release/critical-implementation-2026-10-01/edge-offline-canonical-batch1"
PROMOTION = ROOT / "docs/release/critical-implementation-2026-10-01/root-ai-dispatch-promotion-batch1"
COHORT = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-EDGE-AI-20261002-BATCH1")


def observation(path):
    info = path.lstat()
    assert stat.S_ISREG(info.st_mode) and info.st_nlink == 1, str(path)
    value = hashlib.sha256(path.read_bytes()).hexdigest()
    after = path.lstat()
    identity = lambda i: [i.st_dev, i.st_ino, stat.S_IMODE(i.st_mode), i.st_size,
                          i.st_mtime_ns, i.st_ctime_ns, i.st_nlink]
    assert identity(info) == identity(after), str(path)
    return {"sha256": value, "bytes": info.st_size, "mode": stat.S_IMODE(info.st_mode),
            "identity": identity(after)}


def stable_copy(original, copied, mode=None):
    before = observation(original)
    copied.parent.mkdir(parents=True, exist_ok=True)
    with original.open("rb") as source, copied.open("xb") as target:
        shutil.copyfileobj(source, target)
    os.chmod(copied, before["mode"] if mode is None else mode)
    actual, after = observation(copied), observation(original)
    assert before == after
    assert before["sha256"] == actual["sha256"] and before["bytes"] == actual["bytes"]
    assert before["identity"][:2] != actual["identity"][:2]
    return before, actual, after


def packet(directory, manifest):
    result = {}
    for name, expected in manifest.items():
        value = observation(directory / name)
        assert value["sha256"] == expected["sha256"] and value["bytes"] == expected["bytes"]
        if "mode" in expected:
            assert value["mode"] == expected["mode"]
        result[name] = value
    return result


def save(name, value):
    with (EVIDENCE / name).open("x") as stream:
        stream.write(json.dumps(value, indent=2) + "\n")


def main():
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    old_batch = json.loads((OLD / "batch.json").read_text())
    assert observation(OLD / "batch.json")["sha256"] == "5c237457fb73a5eed997207e1e054969174b3777fa6ceeebe34cb46d5bfd327c"
    old_before = packet(OLD, old_batch["artifacts"])
    old_index_before = {name: observation(OLD / name) for name in ["batch.json", "SHA256SUMS"]}
    promotion_seal_before = observation(PROMOTION / "packet-files.json")
    assert promotion_seal_before["sha256"] == "22254ff78ce9066b6ff329446f8230edce567dda48996ec6e1c69bf316c62400"
    leaves = json.loads((PROMOTION / "packet-files.json").read_text())["files"]
    promotion_manifest = {r["path"]: r for r in leaves}
    promotion_before = packet(ROOT, promotion_manifest)
    assert len(promotion_before) == 39
    review = json.loads((PROMOTION / "root-review.json").read_text())
    changes = review["authorized_changes"]
    verification = json.loads((PROMOTION / "applied-verification.json").read_text())
    assert review["status"] == verification["status"] == "pass" and len(changes) == 7
    assert len(verification["source_before"]) == 25
    closure_before = {name: observation(ROOT / name) for name in verification["source_before"]}
    assert all(closure_before[n]["sha256"] == sha for n, sha in verification["source_before"].items())
    base_freeze = json.loads((OLD / "private-source-freeze.json").read_text())
    base = Path(base_freeze["private_candidate"])
    base_before = {r["path"]: observation(base / r["path"]) for r in base_freeze["source_manifest"]}
    assert len(base_before) == 137
    assert all(base_before[r["path"]]["sha256"] == r["sha256"] and base_before[r["path"]]["mode"] == r["copy_mode"]
               for r in base_freeze["source_manifest"])
    COHORT.mkdir(mode=0o700)
    candidate, inputs, cache = COHORT / "source", COHORT / "inputs", COHORT / "deno-cache"
    candidate.mkdir(mode=0o700); inputs.mkdir(mode=0o700); cache.mkdir(mode=0o700)
    baseline_copies = []
    for name in sorted(base_before):
        before, copied, after = stable_copy(base / name, candidate / name)
        baseline_copies.append({"path": name, "before": before, "copy": copied, "after": after})
    authored_changes = []
    for change in changes:
        name = change["path"]
        installed = observation(ROOT / name)
        assert installed["sha256"] == change["candidate_sha256"] and installed["bytes"] == change["candidate_bytes"]
        assert closure_before[name] == installed
        destination = candidate / name
        baseline_value = base_before.get(name)
        assert (baseline_value["sha256"] if baseline_value else None) == change["base_sha256"]
        if destination.exists():
            destination.unlink()  # Own private copy only; accepted originals are immutable.
        before, copied, after = stable_copy(ROOT / name, destination)
        authored_changes.append({"path": name, "base": baseline_value, "before": before,
                                 "copy": copied, "after": after})
    changed_names = {r["path"] for r in changes}
    names = sorted(set(base_before) | changed_names)
    assert len(names) == 140
    for name in names:
        expected = closure_before[name] if name in changed_names else base_before[name]
        copied = observation(candidate / name)
        assert all(expected[k] == copied[k] for k in ["sha256", "bytes", "mode"])
    # Discover the actual maintained graph from this composed private source.
    sys.path.insert(0, str(candidate / "scripts/qa"))
    spec = importlib.util.spec_from_file_location("private_ai_edge_inventory", candidate / "scripts/qa/run_edge_ci.py")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    discovered = sorted(str(p.relative_to(candidate)) for p in module.source_paths())
    assert discovered == names
    manifest = []
    for name in discovered:
        origin = ROOT / name if name in changed_names else base / name
        before, copied, after = observation(origin), observation(candidate / name), observation(origin)
        assert before == after
        manifest.append({"path": name, "sha256": copied["sha256"], "bytes": copied["bytes"],
             "before_mode": before["mode"], "copy_mode": copied["mode"], "after_mode": after["mode"],
             "before_identity": before["identity"], "copy_identity": copied["identity"],
             "after_identity": after["identity"], "origin": str(origin),
             "origin_class": "reviewed_current_ai" if name in changed_names else "accepted_immutable137"})
    externals = []
    for row in base_freeze["external_inputs"]:
        original = Path(row["copy"])
        assert observation(original)["sha256"] == row["sha256"]
        target = inputs / original.relative_to(Path(base_freeze["cohort"]) / "inputs")
        before, copied, after = stable_copy(original, target)
        externals.append({"kind": row["kind"], "original": str(original), "copy": str(target),
             "sha256": copied["sha256"], "bytes": copied["bytes"], "original_mode": before["mode"],
             "copy_mode": copied["mode"], "original_identity": before["identity"], "copy_identity": copied["identity"]})
    auxiliary = ROOT / "docs/release/critical-implementation-2026-10-01/successor-gateway-inventory-batch1/inputs/contracts/edge-functions.json"
    a_before, a_copy, a_after = stable_copy(auxiliary, inputs / "dated12-edge-functions.json")
    assert len(json.loads((inputs / "dated12-edge-functions.json").read_text())["functions"]) == 12
    auxiliary_binding = {"original": str(auxiliary), "copy": str(inputs / "dated12-edge-functions.json"),
                         "before": a_before, "copy_observation": a_copy, "after": a_after,
                         "canonical_source_graph_member": False, "role": "Explicit dated intended12 inventory snapshot, not a claimed original137 runtime input"}
    old_after = packet(OLD, old_batch["artifacts"])
    assert old_before == old_after
    assert old_index_before == {name: observation(OLD / name) for name in old_index_before}
    promotion_after = packet(ROOT, promotion_manifest)
    assert promotion_before == promotion_after and promotion_seal_before == observation(PROMOTION / "packet-files.json")
    assert closure_before == {name: observation(ROOT / name) for name in closure_before}
    assert base_before == {name: observation(base / name) for name in base_before}
    assert not list(cache.iterdir())
    freeze = {"frozen_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "root": str(ROOT),
       "private_candidate": str(candidate), "cohort": str(COHORT), "source_count": len(manifest),
       "exact_current_dynamic_inventory": False, "exact_composed_private_dynamic_inventory": True,
       "composition": "Exact immutable accepted137 plus exact reviewed7 AI changes (4 replacements,3 additions); retained dated12 config/loader and separate12 manifest snapshot.",
       "before_copy_after_mode_hash_equal": True, "all_private_file_inodes_distinct": True,
       "initial_deno_file_count": 0, "deno_cache": str(cache), "source_manifest": manifest,
       "publisher_receipt_original": base_freeze["publisher_receipt_copy"],
       "publisher_receipt_copy": str(inputs / "publisher-inputs.json"),
       "publisher_sha256": base_freeze["publisher_sha256"], "wheel_source": str(inputs / "wheels"),
       "metadata_directory": str(inputs / "primary"), "external_inputs": externals,
       "auxiliary_dated12_manifest": auxiliary_binding, "maintained_source_mutations": 0,
       "network_acquisition": False, "full_gate_started": False}
    save("private-source-freeze.json", freeze)
    save("composition-provenance.json", {"started_at_utc": started, "frozen_at_utc": freeze["frozen_at_utc"],
         "original519_before": old_before, "original519_after": old_after,
         "original519_seal_before_after": old_index_before, "original137_before_after": base_before,
         "baseline137_physical_copies": baseline_copies, "exact_reviewed7_physical_changes": authored_changes,
         "root_promotion_seal": promotion_seal_before, "root39_before_after": promotion_before,
         "current25_promotion_closure_before_after": closure_before, "source_140_discovered": discovered,
         "current_checkout_gate_claimed": False, "successor_missing_fixtures_not_omitted_from_current_acceptance_claim": True})
    (EVIDENCE / "private-source-freeze.sha256").write_text(observation(EVIDENCE / "private-source-freeze.json")["sha256"] + "\n")
    print(json.dumps({"status": "private_composed140_frozen", "source_count": len(manifest),
          "initial_cache_files": 0, "cohort": str(COHORT), "original519_unchanged": True,
          "root39_and_current25_unchanged": True, "current_checkout_acceptance_claimed": False}, indent=2))


if __name__ == "__main__":
    main()
