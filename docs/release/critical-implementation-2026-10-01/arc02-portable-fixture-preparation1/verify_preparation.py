#!/usr/bin/env python3
"""Read-only preservation check for this private proposal; never runs Flutter."""

import argparse
import hashlib
import json
import re
from pathlib import Path


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_text())


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-inputs", action="store_true")
    args = parser.parse_args()
    packet = Path(__file__).resolve().parent
    repo = packet.parents[3]
    proposed = packet / "proposed"
    before = packet / "before"
    evidence = packet / "evidence"
    changes = load(evidence / "source-deltas.json")
    bindings = load(evidence / "input-bindings.json")
    graph = load(evidence / "current41-test-import-graph.json")
    for path in packet.rglob("*"):
        require(not path.is_symlink(), f"Private packet symlink: {path}")
    expected = {entry["path"] for entry in changes}
    actual = {
        path.relative_to(proposed).as_posix()
        for path in proposed.rglob("*")
        if path.is_file()
    }
    require(expected == actual, "Proposed path set differs from source delta set")
    require(len(changes) == 49, "Unexpected proposed path count")
    patterns = [
        r"\btest\(", r"\btestWidgets\(", r"\bexpect\(", r"\bexpectLater\(",
        r"\bmatchesGoldenFile\(", r"\bdispose\(", r"\bskip\s*:",
    ]
    changed_dart = 0
    for entry in changes:
        rel = entry["path"]
        data = (proposed / rel).read_bytes()
        require(sha256(data) == entry["proposed_sha256"], f"Proposed hash: {rel}")
        require(Path(rel).suffix in {".dart", ".json"}, f"Unexpected source kind: {rel}")
        if entry["operation"] == "replace":
            changed_dart += 1
            old = (before / rel).read_bytes()
            require(sha256(old) == entry["before_sha256"], f"Before hash: {rel}")
            rebuilt = old.decode()
            for delta in entry["allowed_deltas"]:
                require(rebuilt.count(delta["old"]) == delta["count"], f"Delta count: {rel}")
                rebuilt = rebuilt.replace(delta["old"], delta["new"])
            require(rebuilt.encode() == data, f"Undeclared Dart delta: {rel}")
            for pattern in patterns:
                require(
                    len(re.findall(pattern, old.decode())) == len(re.findall(pattern, data.decode())),
                    f"Test/assertion/disposal token count changed: {rel}: {pattern}",
                )
            old_flags = re.findall(r"(?:bool|String)\.fromEnvironment\('[^']+'\)", old.decode())
            new_flags = re.findall(r"(?:bool|String)\.fromEnvironment\('[^']+'\)", data.decode())
            require(old_flags == new_flags, f"Existing capture flags changed: {rel}")
            if rel == "test/admin_roster_dialog_test.dart":
                require(data.count(b"matchesGoldenFile(") == 4, "Roster image matcher removed")
                require(b"LocalFileComparator(" in data, "Roster comparator output not isolated")
                require(b"tearDownAll(() => goldenFileComparator = previousComparator);" in data,
                        "Prior roster comparator not restored")
            if rel == "test/core/notification_registration_recovery_test.dart":
                require(b"file.parent.create" not in data, "Notification capture creates repository parents")
    require(changed_dart == 10, "Unexpected changed Dart count")
    copied = 0
    for path in proposed.glob("test/fixtures/*/provenance.json"):
        provenance = load(path)
        require(provenance["production_data"] is False, "Fixture provenance lost synthetic scope")
        for receipt in provenance["receipts"]:
            data = (path.parent / receipt["file"]).read_bytes()
            require(sha256(data) == receipt["sha256"], f"Receipt hash: {receipt['file']}")
            require(len(data) == receipt["bytes"], f"Receipt byte length: {receipt['file']}")
            json.loads(data)
            require(b"-----BEGIN PRIVATE KEY-----" not in data, "Private key receipt copied")
            require(b"-----BEGIN RSA PRIVATE KEY-----" not in data, "RSA private key receipt copied")
            if args.verify_inputs:
                require(data == (repo / receipt["source_path"]).read_bytes(),
                        f"Original observed receipt bytes differ: {receipt['source_path']}")
            copied += 1
    require(copied == 34, "Unexpected selected receipt count")
    reused = load(evidence / "reused-operations-fixtures.json")
    require(len(reused) == 4, "Unexpected reused operations receipt count")
    for receipt in reused:
        if args.verify_inputs:
            origin = (repo / receipt["source_path"]).read_bytes()
            current = (repo / receipt["existing_fixture_path"]).read_bytes()
            require(origin == current and sha256(current) == receipt["sha256"],
                    f"Operations fixture identity: {receipt['existing_fixture_path']}")
    require(graph["selected_test_count"] == 41, "Wrong affected suite count")
    require(graph["before_test_dart_closure_count"] == 59, "Wrong original test closure")
    require(graph["proposed_test_dart_closure_count"] == 60, "Wrong proposed test closure")
    require(len(graph["proposed_additional_edges"]) == 4, "Capture helper caller graph incomplete")
    if args.verify_inputs:
        for binding in bindings:
            require(sha256((repo / binding["path"]).read_bytes()) == binding["sha256"],
                    f"Live input drift: {binding['path']}")
    result = {
        "kind": "collect_private_portable_fixture_static_preservation",
        "status": "pass",
        "proposed_paths": len(changes),
        "changed_dart_files": changed_dart,
        "new_capture_helper": 1,
        "byte_exact_selected_receipts": copied,
        "reused_operations_receipts": len(reused),
        "input_bindings_checked": len(bindings) if args.verify_inputs else 0,
        "all_declared_deltas_reconstruct_exact_proposed_bytes": True,
        "assertion_registration_disposal_and_existing_capture_flags_preserved": True,
        "maintained_writes": 0,
        "flutter_dart_sql_provider_or_sdk_invocations": 0,
        "format_analysis_and_current41_runtime_proof": "Pending root integration and execution",
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
