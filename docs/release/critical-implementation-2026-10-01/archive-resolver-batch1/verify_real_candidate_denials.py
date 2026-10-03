#!/usr/bin/env python3
"""Read-only 98-source readback and actual CLI missing-authority denials."""
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
PROOF = Path(__file__).resolve().parent
MANIFEST = ROOT / "docs/release/critical-implementation-2026-10-01/archive-cleanup-batch1/first-batch-candidate-manifest.json"
EXPECTED_MANIFEST_SHA = "da7af8d83064ab7311940d3bdf361d6e64e55013fb680048284a4805976f9408"
MODULE = ROOT / "scripts/audits/collect_evidence_resolver.py"
INDEX = ROOT / "docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/ios-source-compile1/verification.json"
SPEC = importlib.util.spec_from_file_location("collect_evidence_resolver_readback", MODULE)
READER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = READER
SPEC.loader.exec_module(READER)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def readback(manifest):
    info = ROOT.stat()
    source = READER._Root(str(ROOT), str(info.st_dev), str(info.st_ino), stat.S_IMODE(info.st_mode))
    budget = READER._Budget(READER.Limits(seconds=30))
    result = []
    for row in manifest["files"]:
        # This is original-source inventory only, not relocation resolution.
        actual = READER._read_file(source, row["path"], budget, 128 * 1024 * 1024, collect=False)
        result.append({"original_path": row["path"], "sha256": actual.sha256,
                       "size": actual.size, "mode": actual.mode, "mtime_ns": actual.mtime_ns,
                       "device": str(actual.fingerprint[0]), "inode": str(actual.fingerprint[1]),
                       "manifest_bytes_mode_epoch_match": (actual.sha256, actual.size, actual.mode, actual.mtime_ns)
                       == (row["sha256"], row["logical_bytes"], row["mode"], row["mtime_ns"])})
    return result


def main():
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    begin = time.monotonic()
    raw_manifest = MANIFEST.read_bytes()
    if sha(raw_manifest) != EXPECTED_MANIFEST_SHA:
        raise RuntimeError("frozen_candidate_manifest_changed")
    manifest = json.loads(raw_manifest)
    if len(manifest["files"]) != 98 or manifest["logical_bytes"] != 73167256:
        raise RuntimeError("unexpected_candidate_scope")
    before = readback(manifest)
    index_before = sha(INDEX.read_bytes())
    module_before = sha(MODULE.read_bytes())
    outcomes = []
    for row in manifest["files"]:
        if time.monotonic() - begin > 45:
            raise RuntimeError("overall_deadline_exceeded")
        command = [sys.executable, "-B", str(MODULE), "--original-path", row["path"],
                   "--original-sha256", row["sha256"], "--epoch", "unassigned-pending-verified-catalog"]
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        try:
            out, err = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)
            raise RuntimeError("owned_cli_deadline_exceeded")
        response = json.loads(out)
        correct = (process.returncode == 2 and not err and response == {
            "status": "unresolved", "code": "trusted_inputs_required",
            "archive_or_restore_operations_performed": False, "production_release_approved": False})
        outcomes.append({"original_path": row["path"], "original_sha256": row["sha256"],
                         "exit_code": process.returncode, "response": response,
                         "expected_denial_observed": correct})
    after = readback(manifest)
    result = {"started_at_utc": started, "ended_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "elapsed_seconds": time.monotonic() - begin, "overall_deadline_seconds": 45,
              "each_owned_cli_deadline_seconds": 2,
              "manifest_path": str(MANIFEST.relative_to(ROOT)), "manifest_sha256": EXPECTED_MANIFEST_SHA,
              "original_index_path": str(INDEX.relative_to(ROOT)), "original_index_sha256_before": index_before,
              "original_index_sha256_after": sha(INDEX.read_bytes()),
              "module_sha256_before": module_before, "module_sha256_after": sha(MODULE.read_bytes()),
              "candidate_count": 98, "logical_bytes": 73167256,
              "incoming_references_unresolved": sum(r["expected_denial_observed"] for r in outcomes),
              "incoming_references_resolved": 0,
              "unassigned_epoch_used_only_to_exercise_missing_authority_denial": True,
              "actual_source_epoch_or_archive_identity_invented": False,
              "source_inventory_before": before, "source_inventory_after": after,
              "source_inventory_unchanged": before == after,
              "original_manifest_matched_count": sum(r["manifest_bytes_mode_epoch_match"] for r in after),
              "outcomes": outcomes, "verified_archive_inputs_provided": False,
              "archive_or_restore_performed": False, "moves_or_removals_performed": False,
              "production_release_approved": False, "ARC10_full_acceptance_met": False}
    result["read_only_denial_acceptance_passed"] = (result["source_inventory_unchanged"]
        and result["original_manifest_matched_count"] == 98 and result["incoming_references_unresolved"] == 98
        and result["original_index_sha256_before"] == result["original_index_sha256_after"]
        and result["module_sha256_before"] == result["module_sha256_after"])
    (PROOF / "real-candidate-denials.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("read_only_denial_acceptance_passed", "incoming_references_unresolved",
                     "incoming_references_resolved", "original_manifest_matched_count", "source_inventory_unchanged",
                     "elapsed_seconds", "ARC10_full_acceptance_met")}))
    return 0 if result["read_only_denial_acceptance_passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
