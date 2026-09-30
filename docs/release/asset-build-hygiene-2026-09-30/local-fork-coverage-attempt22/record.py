#!/usr/bin/env python3
"""Retain dated collector acceptance; no Flutter build or final runtime claim."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
OWNED = ["scripts/supply_chain/inventory.py", "scripts/supply_chain/source_sbom.py",
         "scripts/qa/native_source_export.py", "scripts/qa/public_browser_app_media.mjs",
         "scripts/public_app_media.rb", "scripts/tests/supply_chain_source_test.py",
         "scripts/tests/native_source_export_test.py", "scripts/tests/public_app_media_test.rb", "scripts/qa/firebase_scene_callback_probe.py"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


spec = importlib.util.spec_from_file_location("collect_inventory", ROOT / OWNED[0])
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)
sources = {path: sha(ROOT / path) for path in OWNED}
rows, checks = inventory.dart_packages(sources)
before = dict(sources)
document = {"kind": "Dated Dart lock and local-fork candidate collector evidence",
            "source_sha256": sources, "packages": rows, "assets": [], "checks": {"dart": checks},
            "coverage": {"included": ["Current Dart lock declarations and all three regular local fork trees, license texts and provenance"],
                         "excluded": ["Other ecosystems", "Compiled native/web artifacts", "Whole current runtime acceptance",
                                      "Upstream archive authenticity", "License approval", "Hosted/provider/store acceptance"]}}
write("candidate-dart-inventory.json", document)
commands = [
    ("source-supply-chain-tests", [sys.executable, "scripts/tests/supply_chain_source_test.py"], 19),
    ("native-source-export-tests", [sys.executable, "scripts/tests/native_source_export_test.py"], 3),
    ("public-media-tests", ["ruby", "scripts/tests/public_app_media_test.rb"], 20),
    ("recorder-syntax", ["/Volumes/PRO-G40/Development/Node/bin/node", "--check", "scripts/qa/public_browser_app_media.mjs"], None),
    ("dart-sbom", [sys.executable, "scripts/supply_chain/source_sbom.py", "--inventory", str(OUT / "candidate-dart-inventory.json"), "--output", str(OUT / "candidate-dart-sbom.cdx.json")], None),
    ("dart-sbom-reproduction", [sys.executable, "scripts/supply_chain/source_sbom.py", "--inventory", str(OUT / "candidate-dart-inventory.json"), "--output", str(OUT / "candidate-dart-sbom.cdx.json"), "--check"], None),
    ("dart-sbom-schema", [sys.executable, "scripts/supply_chain/validate_source_sbom.py", str(OUT / "candidate-dart-sbom.cdx.json")], None),
]
receipts = []
for name, command, tests in commands:
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    stdout, stderr = OUT / (name + ".stdout"), OUT / (name + ".stderr")
    stdout.write_bytes(result.stdout)
    stderr.write_bytes(result.stderr)
    receipts.append({"name": name, "command": command, "exit_code": result.returncode,
                     "actual_test_count": tests, "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr)})
    if tests is not None:
        import re
        pattern = r"Ran (\d+) tests" if command[0] == sys.executable else r"(\d+) runs, (\d+) assertions"
        observed = re.search(pattern, (result.stdout + result.stderr).decode())
        assert observed and int(observed[1]) == tests, "Observed framework count must match declared packet total"
        if name == "public-media-tests":
            assert int(observed[2]) == 46
    if result.returncode:
        write("verification.json", {"status": "fail", "commands": receipts, "sources_before": before})
        raise SystemExit(result.returncode)
after = {path: sha(ROOT / path) for path in before}
current_rows, current_checks = inventory.dart_packages({})
unchanged = before == after and rows == current_rows and checks == current_checks
fingerprint = subprocess.run(["ruby", "-r", "./scripts/public_app_media", "-e", "puts PublicAppMedia.new(Dir.pwd).runtime_fingerprint"], cwd=ROOT, capture_output=True, check=True)
(OUT / "current-media-fingerprint.stdout").write_bytes(fingerprint.stdout)
(OUT / "current-media-fingerprint.stderr").write_bytes(fingerprint.stderr)
published = json.loads((ROOT / "web/public/app-screens/manifest.json").read_text())
sbom = json.loads((OUT / "candidate-dart-sbom.cdx.json").read_text())
write("verification.json", {"status": "pass" if unchanged else "fail", "kind": "local_fork_collector_acceptance",
                            "scope": "Dated collector, exact export boundary, Public fork freshness, source SBOM reproduction/schema; no Flutter/native build or final whole-runtime acceptance",
                            "whole_current_runtime_acceptance": False, "flutter_build_invoked": False,
                            "sources_before": before, "sources_after": after, "sources_unchanged": unchanged,
                            "commands": receipts, "actual_test_count": 42, "ruby_assertion_count": 46,
                            "forks": checks["local_forks"], "package_occurrences": len(rows),
                            "source_inputs": len(before), "sbom_components": len(sbom["components"]),
                            "inventory_sha256": sha(OUT / "candidate-dart-inventory.json"),
                            "sbom_sha256": sha(OUT / "candidate-dart-sbom.cdx.json"),
                            "recorder_sha256": sha(Path(__file__)),
                            "published_media_runtime_sha256": published["runtime_sha256"],
                            "current_media_runtime_sha256": fingerprint.stdout.decode().strip(),
                            "published_media_requires_recapture": published["runtime_sha256"] != fingerprint.stdout.decode().strip()})
print(json.dumps({"status": "pass" if unchanged else "fail", "tests": 42,
                  "verification_sha256": sha(OUT / "verification.json"), "forks": sorted(checks["local_forks"])}))
raise SystemExit(0 if unchanged else 1)
