"""Independent root readback of the sealed immutable137 local Edge run."""
from pathlib import Path
import datetime
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
PACKET = OUT.parent / "edge-offline-canonical-batch1"


def sha(p):
    assert p.is_file() and not p.is_symlink(), p
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load(name):
    return json.loads((PACKET / name).read_text())


assert sha(PACKET / "batch.json") == "5c237457fb73a5eed997207e1e054969174b3777fa6ceeebe34cb46d5bfd327c"
batch = load("batch.json")
assert batch["artifact_count"] == len(batch["artifacts"]) == 519
for name, row in batch["artifacts"].items():
    p = PACKET / name
    assert p.resolve().is_relative_to(PACKET.resolve())
    assert p.stat().st_size == row["bytes"] and sha(p) == row["sha256"], name
checksum_rows = (PACKET / "SHA256SUMS").read_text().splitlines()
assert len(checksum_rows) == 520
for line in checksum_rows:
    digest, name = line.split("  ", 1)
    assert sha(PACKET / name) == digest, name
execution = load("execution-result.json")
canonical = load("canonical/validation.json")
assert execution["status"] == canonical["status"] == "pass"
assert execution["exit_code"] == 0 and execution["initial_deno_file_count"] == 0
assert execution["whole_deadline_seconds"] == 1200
assert execution["build_deadline_seconds"] == 300 and execution["linux_phase_deadline_seconds"] == 600
assert execution["elapsed_seconds"] < 1200
assert len(execution["private_source_before"]) == 137
assert execution["private_source_before"] == execution["private_source_after"]
private = Path(execution["private_candidate"])
for name, row in execution["private_source_after"].items():
    assert sha(private / name) == row["sha256"]
assert all(p["exit_code"] == 0 and p["status"] == "pass" for p in canonical["phases"].values())
assert canonical["source_before"] == canonical["source_after"] and canonical["source_unchanged"]
assert not canonical["current_sql_executed"] and canonical["provider_calls"] == 0
units = load("canonical/units/validation.json")
assert units["tests_passed"] == 565 and units["steps_passed"] == 32
assert units["test_file_count"] == 31
assert all(units[k] == 0 for k in ["tests_failed", "tests_ignored", "steps_failed", "steps_ignored"])
assert units["source_before"] == units["source_after"] and units["exit_code"] == 0
http = load("canonical/edge-http/report.json")
checks = http["runtime_result"]["checks"]
assert len(checks) == 91 and all(c["status"] == "pass" for c in checks)
assert http["exit_code"] == 0 and not http["final_acceptance"]
linux = load("canonical/linux-decoder/validation.json")
assert linux["passed"] and len(linux["cases"]) == 32
assert linux["source_before"] == linux["source_after"]
assert linux["synthetic_only"] and not linux["provider_accuracy_verified"]
negative = load("corrupted-lock-negative/supported-command-result.json")
assert negative["exit_code"] == 10 and negative["actual_integrity_rejection"]
assert negative["negative_lock_unchanged"] and negative["accepted_original_source_cache_unchanged"]
assert negative["pinned_check_has_cached_only_option"] is False
negative_logs = [p for p in (PACKET / "corrupted-lock-negative").rglob("*") if p.is_file() and p.suffix in [".stderr", ".stdout"]]
assert any("Integrity check failed" in p.read_text() for p in negative_logs)
cleanup = load("cleanup-readback/result.json")
assert cleanup["actual_task_supervisor_absent"] and cleanup["actual_task_security_container_absent"]
assert cleanup["fresh_image_has_zero_containers"] and not cleanup["actual_owned_live_processes"]
fixture = load("fixture-provenance.json")
assert fixture["origin_exact_finished_helper_runner_support_and_migration_hashes_verified"]
assert fixture["immutable_worker_manifest_sha256"] == "e5ed738a0aa4dc6cf870bf33352610074a6e46ab82705dd82440571b58a6a657"
assert fixture["synthetic_only"] and not fixture["provider_accuracy_verified"]
current_changed = {}
for name, row in execution["private_source_after"].items():
    current = ROOT / name
    observed = sha(current) if current.exists() else None
    if observed != row["sha256"]:
        current_changed[name] = {"accepted_sha256": row["sha256"], "current_sha256": observed}
receipt = {
    "observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "status": "pass_scoped_original137", "artifact_leaves": 519, "checksum_rows": 520,
    "original_sources": 137, "fresh_cache_initial_files": 0,
    "original_commands_exit_zero": True, "actual_results": batch["actual_results"],
    "negative_result": "Actual frozen-lock integrity exit10 under OS network denial; unsupported-argument attempt retained and excluded.",
    "original_cleanup_parser_error_retained": True, "owned_cleanup_independently_verified": True,
    "source_after_unchanged": True, "current_changed_accepted_inputs": current_changed,
    "current_combined_checkout_acceptance": False,
    "current_gateway": "Separate successor source/config exists; manifest and loader registration plus10 genuine fixtures remain incomplete.",
    "new_ai_promotion": "Exact reviewed7 changes need a separately bound full signed Linux HTTP run.",
    "current_sql_executed": False, "provider_accuracy_verified": False,
    "whole_production_acceptance": False,
}
with (OUT / "readback.json").open("x") as stream:
    stream.write(json.dumps(receipt, indent=2) + "\n")
files = [{"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size, "sha256": sha(p)} for p in sorted(OUT.iterdir()) if p.is_file()]
with (OUT / "packet-files.json").open("x") as stream:
    stream.write(json.dumps({"status": "sealed", "scope": "Root independent original519 integrity/phase/source/negative readback; current combined checkout remains unaccepted.", "files": files}, indent=2) + "\n")
print(json.dumps({"status": receipt["status"], "artifacts": 519, "checksums": 520, "current_different_inputs": list(current_changed)}))
