#!/usr/bin/env python3
"""Seal one private five-consumer candidate without promoting it."""
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
PACKET = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("prepare", PACKET / "prepare_source.py")
prepared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepared)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def main():
    assert not (PACKET / "batch.json").exists(), "sealed packet already exists"
    verification = json.loads((PACKET / "verification.json").read_text())
    before = json.loads((PACKET / "source-before.json").read_text())
    current = {name: prepared.read(prepared.ROOT / name)[1] for name in before}
    drift = {name: {"before": before[name], "after": current[name]}
             for name in before if before[name] != current[name]}
    assert not (set(drift) & set(verification["changed_files"])), "five consumer bases changed"
    prepared.dump(PACKET / "source-guard-at-seal.json", {
        "observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "maintained_inputs": len(before), "drift": drift,
        "all_copied_sources_unchanged": not drift,
        "five_consumer_bases_unchanged": True,
        "consumers": {name: current[name] for name in verification["changed_files"]},
    })
    artifacts = {}
    for path in sorted(PACKET.rglob("*")):
        if not (path.is_file() or path.is_symlink()):
            continue
        name = str(path.relative_to(PACKET))
        raw, facts = prepared.read(path)
        artifacts[name] = {key: facts[key] for key in ("sha256", "bytes", "mode")}
    batch = {
        "sealed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "status": "private_consumer_candidate_verified_not_promoted",
        "artifact_count": len(artifacts), "maintained_inputs": len(before),
        "changed_files": verification["changed_files"],
        "candidate_patch_sha256": verification["candidate_patch_sha256"],
        "actual_private_tests": {"ruby": 17, "ruby_assertions": 173, "python_delivery": 34,
                                  "failures": 0, "errors": 0, "skips": 0},
        "actual_original_baselines": {"ruby_cases": 6, "ruby_errors": 1,
                                       "python_cases": 30, "python_pass": 19,
                                       "python_failures": 10, "python_errors": 1},
        "old_case_assertions_preserved": {"ruby": 6, "python": 30},
        "OS_network_denial_proved": True,
        "intended_private_inventory": {"endpoints": 13, "custom_auth": 8},
        "shared_HTTP_loader_unchanged": True,
        "declared_successor_handler_tests": 25, "successor_handler_tests_executed": False,
        "missing_observed_fixtures": 10,
        "source_copy_and_current_scope_drift": drift,
        "maintained_source_writes": 0, "shared_promotion": False,
        "handler_SQL_or_provider_execution": False, "hosted_or_network_operations": False,
        "combined_canonical_acceptance": False, "production_acceptance": False,
        "remaining_dependencies": [
            "Root full-patch review and exact consumer/source hash authorization before promotion",
            "Genuine ten observed JSON fixtures with immutable origin/source/completion/hash proof",
            "Separate literal thirteenth real HTTP loader and exact signed successor behavior branch",
            "Root AI and HTTP fixture reconciliation, newly discovered source freeze and full canonical gate",
            "Current SQL/hosted/device/carrier/approved delivery and release requirements",
        ],
        "artifacts": artifacts,
    }
    prepared.dump(PACKET / "batch.json", batch)
    rows = {name: facts["sha256"] for name, facts in artifacts.items()}
    rows["batch.json"] = sha((PACKET / "batch.json").read_bytes())
    (PACKET / "SHA256SUMS").write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(rows.items())))
    print(json.dumps({"artifact_count": len(artifacts), "checksum_rows": len(rows),
                      "batch_sha256": rows["batch.json"], "patch_sha256": verification["candidate_patch_sha256"]}))

if __name__ == "__main__":
    main()
