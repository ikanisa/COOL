#!/usr/bin/env python3
"""Independent dated readback of two completed, scoped worker packets."""
import datetime
import hashlib
import json
from pathlib import Path
import stat

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
PACKETS = HERE.parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked(path, expected, size=None):
    info = path.lstat()
    assert stat.S_ISREG(info.st_mode), path
    actual = sha(path)
    assert actual == expected, (str(path), actual, expected)
    assert size is None or info.st_size == size, path
    return {"path": str(path), "sha256": actual, "bytes": info.st_size}


def local(base, name):
    relative = Path(name)
    assert not relative.is_absolute() and ".." not in relative.parts
    return base / relative


def main():
    result = {"at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "Independent artifact readback and reviewed current input equality only.",
              "production_release_approved": False, "whole_mutable_candidate_accepted": False}
    public = PACKETS / "public-media-batch4"
    checked(public / "batch.json", "b1fe2972c3a0bd63c41d4cdbefede83a1643d47fff6cdcbb39865b18bd786f95")
    checked(public / "evidence-files.json", "7978afc42ba2eaa1990d779a49efb66bdf1a6fb33c5b2fe5a916ed898b6e60fb")
    checked(public / "seal-readback.json", "d7dcde936b27b783016c51b8b1b8b4801a6de660c63eafa867149cfa1b44f69c")
    batch = json.loads((public / "batch.json").read_text())
    files = json.loads((public / "evidence-files.json").read_text())
    assert files["count"] == len(files["files"]) == 704
    assert len({x["path"] for x in files["files"]}) == 704
    leaves = [checked(local(ROOT, x["path"]), x["sha256"], x["size"]) for x in files["files"]]
    current = json.loads((public / "final-readback.json").read_text())
    assert current["status"] == "pass" and current["errors"] == []
    media = {name: sha(local(ROOT, name)) for name in current["current_media_graph"]}
    assert media == current["current_media_graph"] and len(media) == 344
    four = [checked(local(ROOT, name), value) for name, value in batch["root4_production_sources"].items()]
    assert batch["strict_quality_summary"] == {"total": 55, "passed": 55, "failed": 0}
    coverage = batch["rendered_route_coverage"]
    assert coverage["missing"] == [] and coverage["total_actual_cases"] == 104
    assert coverage["observed_direct_entry_viewport_count"] == coverage["required_entry_viewport_count"] == 72
    assert coverage["maintained_original_pngs"] + coverage["supplemental_genuine_top_original_pngs"] == 378
    assert all(batch["canonical_approval"][key] is False for key in
               ("owner_approved", "publication_approved", "legal_release_approved", "provider_approved"))
    assert batch["native_full_visual_legal_hosted_provider_release_acceptance"] is False
    contract = local(ROOT, "docs/release/public-website-current-content-contract.json")
    checked(contract, batch["current_contract_sha256"])
    result["public"] = {"batch_sha256": sha(public / "batch.json"), "indexed_leaves": leaves,
                        "current_media_inputs_checked": len(media), "reviewed_four_sources": four,
                        "quality_checks": 55, "actual_browser_cases": 104,
                        "original_pngs": 378, "scope_accepted": "current_local_public_candidate_only"}

    archive = PACKETS / "archive-resolver-batch1"
    checked(archive / "batch.json", "21d0546577fbaba9a85f86dbf260b98910bb975bee01ff19a9ebacdab4f71ff1")
    checked(archive / "SHA256SUMS", "5d043f2d3d3f2d9549f3b7577f38101b2b5088eb35511468ad7bb7ad98e20bd0")
    ab = json.loads((archive / "batch.json").read_text())
    assert len(ab["artifacts"]) == 14
    artifacts = [checked(local(archive, x["path"]), x["sha256"], x["bytes"]) for x in ab["artifacts"]]
    checksum_rows = []
    for line in (archive / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        checksum_rows.append(checked(local(archive, name), digest))
    assert len(checksum_rows) == 15
    source = [checked(local(ROOT, x["path"]), x["sha256"], x["bytes"]) for x in ab["owned_source_bindings"]]
    assert ab["actual_test_count"] == 61 and ab["actual_test_exit_code"] == 0
    assert ab["actual_missing_trust_cli_denials"] == 98 and ab["incoming_references_resolved"] == 0
    assert ab["original_source_before_after_unchanged"] is True
    assert ab["ARC10_full_acceptance_met"] is False
    assert type(ab["original_files_moved_or_removed"]) is int and ab["original_files_moved_or_removed"] == 0
    result["archive_reader"] = {"batch_sha256": sha(archive / "batch.json"), "artifacts": artifacts,
                                "checksum_rows_checked": 15, "current_source": source,
                                "reviewed_full_code_and_tests": True, "actual_tests": 61,
                                "actual_trust_denials": 98, "references_resolved": 0,
                                "scope_accepted": "read_only_reader_implementation_only",
                                "archive_restore_removal_acceptance": False}
    result["status"] = "pass"
    output = HERE / "independent-packet-readback.json"
    assert not output.exists(), "Use a new dated cohort for changed inputs."
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": "PASS", "public_leaves": len(leaves), "archive_leaves": len(artifacts),
                      "readback_sha256": sha(output)}))


if __name__ == "__main__":
    main()
