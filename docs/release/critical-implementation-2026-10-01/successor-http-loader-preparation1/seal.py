#!/usr/bin/env python3
"""Read back and seal this nonexecuted one-file proposal."""
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("preparation", OUT / "prepare.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def main():
    assert not (OUT / "batch.json").exists(), "packet already sealed"
    proposal = json.loads((OUT / "proposal.json").read_text())
    before = json.loads((OUT / "source-before.json").read_text())
    current = {name: prepare.read(prepare.ROOT / name)[1] for name in before}
    assert before == current, "maintained source drift requires a new base review"
    candidate = Path(proposal["candidate"]["path"])
    original = (OUT / "inputs" / prepare.QA).read_bytes()
    raw, facts = prepare.read(candidate)
    assert facts == {k: proposal["candidate"][k] for k in ("sha256", "bytes", "mode", "identity")}
    restored = raw.decode().replace(prepare.REGISTRATION, "", 1).replace(prepare.BRANCH, "", 1).encode()
    assert restored == original and sha(original) == prepare.BASE
    assert prepare.loader_names(raw.decode()) == json.loads((OUT / "current-discovery.json").read_text())["source_endpoints"]
    patch = (OUT / "full-candidate.patch").read_bytes()
    assert sha(patch) == proposal["patch"]["sha256"]
    prepare.dump("source-guard-at-seal.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                                               "maintained_inputs": len(before), "all_unchanged": True,
                                               "current_QA": current[prepare.QA], "candidate": facts})
    artifacts = {}
    for path in sorted(OUT.rglob("*")):
        if path.is_file() or path.is_symlink():
            _, row = prepare.read(path)
            artifacts[str(path.relative_to(OUT))] = {k: row[k] for k in ("sha256", "bytes", "mode")}
    prepare.dump("batch.json", {
        "sealed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "status": "private_one_file_HTTP_proposal_not_executed_or_promoted",
        "artifact_count": len(artifacts), "maintained_inputs": len(before),
        "current_loader_count": 12, "candidate_loader_count": 13,
        "source_config_manifest_count": 13,
        "dynamic_unit_entryfiles": 33, "successor_declared_tests": 25,
        "missing_observed_imports": 10,
        "base_SHA": prepare.BASE, "candidate_SHA": facts["sha256"], "patch_SHA": sha(patch),
        "maintained_source_writes": 0, "shared_promotion": False,
        "type_or_handler_or_SQL_or_native_execution": False,
        "provider_or_hosted_operations": False,
        "new_planned_HTTP_assertions": 6, "new_assertions_executed": False,
        "unit_filtering_or_generated_observations": False,
        "all_original_HTTP_bytes_restored_from_two_insertions": True,
        "artifacts": artifacts,
    })
    checks = {name: row["sha256"] for name, row in artifacts.items()}
    checks["batch.json"] = sha((OUT / "batch.json").read_bytes())
    (OUT / "SHA256SUMS").write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(checks.items())))
    print(json.dumps({"artifacts": len(artifacts), "checksum_rows": len(checks), "batch_sha256": checks["batch.json"],
                      "candidate_sha256": facts["sha256"], "patch_sha256": sha(patch)}))

if __name__ == "__main__":
    main()
