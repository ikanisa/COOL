from pathlib import Path
import json, hashlib, datetime
ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
original = json.loads((OUT / "source-before.json").read_text())
delta = json.loads((OUT / "documentation-delta.json").read_text())
expected = {r["path"]: r["sha256"] for r in original["files"]}
expected[delta["path"]] = delta["current_sha256"]
current_before = {p: sha(ROOT / p) for p in expected}
assert current_before == expected, "current reconciled input mismatch"
prior = []
for name, digest in [("ai-import-review-batch1", "0c385cc5cbcc1d4b95af547552c547ec5d55e03ab481f8bd25e268ffaf287933"), ("ai-import-minimization-batch1", "b93aba57fc4910882b13eb17508d7242c9ad102b6c25b7aef1957cb178adcc7e"), ("ai-import-fixture-lint-batch1", "b3ff1456d00f31f742433e166b60733c2a312ce11b251f44ba18b4fb396df352")]:
    directory = OUT.parent / name
    assert sha(directory / "batch.json") == digest
    index = json.loads((directory / "evidence-index.json").read_text())
    for row in index["files"]:
        p = ROOT / row["path"]
        assert p.is_file() and p.stat().st_size == row["bytes"] and sha(p) == row["sha256"], "prior packet leaf changed"
    prior.append({"packet": name, "batch_sha256": digest, "index_sha256": sha(directory / "evidence-index.json"), "indexed_leaves": len(index["files"]), "preserved": True})
for row in original["files"]:
    assert sha(OUT / "source-before" / row["path"]) == row["sha256"]
assert sha(OUT / "source-reconciled" / delta["path"]) == delta["current_sha256"]
current_after = {p: sha(ROOT / p) for p in expected}
assert current_before == current_after == expected
readback = {"observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "status": "pass", "current_before": current_before, "current_after": current_after, "current_reconciled_inputs_stable": True, "original_investigation_all_inputs_unchanged": False, "exact_root_owned_doc_drift_count": 1, "all_other_31_inputs_unchanged": True, "original_drift_observation_preserved": "source-readback.json", "documentation_delta_sha256": sha(OUT / "documentation-delta.json"), "prior_packets": prior, "preserved_prior_leaves": sum(p["indexed_leaves"] for p in prior), "source_mutations_by_this_agent": [], "new_policy_tests_run": False, "policy_approval_values_selected": False}
(OUT / "current-source-readback.json").write_text(json.dumps(readback, indent=2) + "\n")
excluded = {"batch.json", "evidence-index.json", "seal-readback.json"}
files = [{"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size, "sha256": sha(p)} for p in sorted(OUT.rglob("*")) if p.is_file() and p.name not in excluded]
index = {"files": files, "scope": "read-only source observation, exact root documentation reconciliation, review proposal and unexecuted test plan; excludes batch/index/seal to avoid circular hashes", "excluded": sorted(excluded)}
(OUT / "evidence-index.json").write_text(json.dumps(index, indent=2) + "\n")
batch = {"id": "BE13-L04-ai-dispatch-policy-review-batch1", "sealed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "status": "READ_ONLY_PROPOSAL_COMPLETE_IMPLEMENTATION_AND_ACCEPTANCE_OPEN", "current_source_inputs": len(expected), "original_investigation_all_inputs_unchanged": False, "root_owned_doc_delta_count": 1, "current_reconciled_inputs_stable": True, "current_source_readback_sha256": sha(OUT / "current-source-readback.json"), "evidence_index": {"path": str((OUT / "evidence-index.json").relative_to(ROOT)), "sha256": sha(OUT / "evidence-index.json"), "indexed_leaves": len(files)}, "report": {"path": str((OUT / "README.md").relative_to(ROOT)), "sha256": sha(OUT / "README.md")}, "proposal": {"path": str((OUT / "proposal.json").relative_to(ROOT)), "sha256": sha(OUT / "proposal.json")}, "proposed_schema_sha256": sha(OUT / "proposed-approval.schema.json"), "planned_scenario_groups": 23, "new_policy_tests_run": False, "guard_implemented": False, "selected_owner_policy_values": False, "source_mutations_by_this_agent": [], "provider_calls": 0, "database_calls": 0, "Admin_gateway_writes": False, "prior_packets_preserved": True, "approval_acceptance": False, "whole_BE13_closed": False, "production_acceptance": False, "remaining": ["root review of schema and explicit preflight/replay placement", "scoped guard implementation and real old-source denial proof after Edge freeze", "actual owner/vendor processor/project/region/retention record", "immutable per-attempt policy lineage", "governed config provisioning/current readback", "deterministic decoder/retention/Admin disclosure/evaluation gates", "complete BE13 and production readiness"]}
(OUT / "batch.json").write_text(json.dumps(batch, indent=2) + "\n")
errors = []
for row in files:
    p = ROOT / row["path"]
    if not p.is_file() or p.stat().st_size != row["bytes"] or sha(p) != row["sha256"]:
        errors.append(row["path"])
final_current = {p: sha(ROOT / p) for p in expected}
if final_current != expected:
    errors.append("current source drift while sealing")
seal = {"status": "pass" if not errors else "fail", "observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "indexed_leaves": len(files), "current_source_inputs": len(expected), "preserved_prior_leaves": readback["preserved_prior_leaves"], "batch_sha256": sha(OUT / "batch.json"), "index_sha256": sha(OUT / "evidence-index.json"), "report_sha256": sha(OUT / "README.md"), "proposal_sha256": sha(OUT / "proposal.json"), "schema_sha256": sha(OUT / "proposed-approval.schema.json"), "exact_root_owned_doc_drift_preserved": True, "errors": errors, "guard_implementation_accepted": False, "approval_acceptance": False, "production_acceptance": False}
(OUT / "seal-readback.json").write_text(json.dumps(seal, indent=2) + "\n")
print(json.dumps(seal))
raise SystemExit(0 if not errors else 1)
