#!/usr/bin/env python3
"""Copy a verified candidate to a separate unapproved build workspace; no Flutter."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile


def prepare(root, source, destination, expected_manifest_sha256):
    spec = importlib.util.spec_from_file_location("collect_candidate", root / "scripts/qa/collect_release_candidate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    source = source.resolve()
    destination = destination.absolute()
    for ancestor in [destination, *destination.parents]:
        if ancestor.is_symlink():
            raise module.ReleaseError("CANDIDATE_DESTINATION_SYMLINK")
    destination = destination.resolve()
    if destination.exists() or root == destination or root in destination.parents or source == destination or source in destination.parents:
        raise module.ReleaseError("CANDIDATE_DESTINATION_NOT_ISOLATED")
    readback = module.verify_candidate(source, expected_manifest_sha256=expected_manifest_sha256)
    if readback["status"] != "pass":
        raise module.ReleaseError("CANDIDATE_READBACK_REQUIRED", [item["path"] for item in readback["changes"]])
    raw, _ = module.regular_bytes(source, module.MANIFEST)
    manifest = json.loads(raw)
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".collect-build-copy-", dir=destination.parent))
    try:
        for name, expected in manifest["source_files"].items():
            data, mode = module.regular_bytes(source, name)
            if {"sha256": module.sha(data), "bytes": len(data), "mode": mode} != expected:
                raise module.ReleaseError("CANDIDATE_SOURCE_CHANGED", [name])
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(mode)
        (staging / module.MANIFEST).write_bytes(raw)
        staging.rename(destination)
        copy_readback = module.verify_candidate(destination, expected_manifest_sha256=expected_manifest_sha256)
        if copy_readback["status"] != "pass":
            raise module.ReleaseError("CANDIDATE_COPY_INVALID", [item["path"] for item in copy_readback["changes"]])
        return {"status": "pass", "kind": "unapproved_build_work_copy", "source_candidate": str(source),
                "workspace": str(destination), "manifest_sha256": expected_manifest_sha256,
                "file_count": manifest["file_count"], "copy_readback": copy_readback,
                "candidate_approvals": manifest["approvals"], "flutter_commands": 0,
                "scope": "Exact source copy only; generated bindings and build output will be separately recorded"}
    finally:
        if staging.exists():
            shutil.rmtree(staging)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = prepare(args.root.resolve(), args.candidate, args.workspace, args.manifest_sha256)
    except Exception as error:
        result = {"status": "blocked", "reason_code": getattr(error, "code", "BUILD_COPY_FAILED"),
                  "affected_source_paths": getattr(error, "paths", []), "credential_values_reported": False}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps(result, sort_keys=True))
    raise SystemExit(0 if result["status"] == "pass" else 2)
