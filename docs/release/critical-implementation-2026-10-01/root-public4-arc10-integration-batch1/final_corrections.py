#!/usr/bin/env python3
"""Bind terminal SDK failure, correct actual class count and closure counters."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
REGISTER = HERE.parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def main():
    sdk = REGISTER / "kotlin-sdk-candidate-execution-batch1"
    manifest = sdk / "packet-files.json"
    assert sha(manifest) == "71be02949c0e2c303f8f3e1e1d014035f7ae3a6330cbd9ec05f707bef81aee95"
    assert sha(sdk / "source-freeze.json") == "fbae042714f6157094a0caa9dcff79715c0182f486b116e8ea42eb85b5282a62"
    entries = json.loads(manifest.read_text())
    assert len(entries["files"]) == entries["file_count"] == 57
    for name, digest in entries["files"].items():
        assert not Path(name).is_absolute() and ".." not in Path(name).parts
        assert sha(sdk / name) == digest, name
    result = json.loads((sdk / "terminal-native-failure-results.json").read_text())
    assert result["actual_exit_code"] == 1 and result["timed_out"] is False
    assert result["JUnit_tests_executed"] == result["JUnit_XML_files"] == 0
    assert result["main_class_files"] == 83 and result["main_output_regular_files"] == 84
    jar = Path(result["JAR_path"])
    assert sha(jar) == result["JAR_sha256"]
    main_root = jar.parents[1] / "classes/kotlin/main"
    actual = {str(path.relative_to(main_root)): sha(path) for path in main_root.rglob("*.class")}
    assert actual == result["class_sha256"] and len(actual) == 83
    with zipfile.ZipFile(jar) as zipped:
        jar_classes = {name: hashlib.sha256(zipped.read(name)).hexdigest()
                       for name in zipped.namelist() if name.endswith(".class")}
    assert jar_classes == actual
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    readback = {"at_utc": now, "status": "pass", "sdk_sealed_leaves_checked": 57,
                "manifest_sha256": sha(manifest), "source_freeze_sha256": sha(sdk / "source-freeze.json"),
                "actual_compiled_classes_and_jar_members_checked": 83, "main_regular_outputs": 84,
                "SDK_JUnit_executed": 0, "actual_exit_code": 1,
                "candidate_accepted": False, "shared_sdk_changed": False, "production_release_approved": False,
                "scope": "Artifact-bound terminal failure and limited main compilation; preserves all strict failures."}
    save(HERE / "sdk-execution-independent-readback.json", readback)
    ledger_path = REGISTER / "implementation-ledger.json"
    assert sha(ledger_path) == "557b24d798a6bfbb2d786660de2b6017275706b6784db564aac0a9884110bf20"
    owned = [ledger_path, REGISTER / "IMPLEMENTATION_REGISTER.md"]
    owned += [REGISTER.parent / name for name in ("production-remaining-tasks-2026-09-30.json", "local-implementation-register-2026-09-30.json", "PRODUCTION_REMAINING_TASKS_2026-09-30.md", "LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md")]
    before = HERE / "registers-before-counters-and-class-correction"
    before.mkdir(exist_ok=False)
    for path in owned:
        target = before / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    ledger = json.loads(ledger_path.read_text())
    row = next(row for row in ledger["items"] if row["id"] == "ARC-09")
    assert "produce84 classes" in row["next_action"]
    row["next_action"] = row["next_action"].replace("produce84 classes", "produce83 class files plus one Kotlin module metadata file (84 regular main outputs)")
    for path in (manifest, sdk / "source-freeze.json", HERE / "sdk-execution-independent-readback.json"):
        item = {"path": str(path.relative_to(ROOT)), "sha256": sha(path)}
        row["evidence_packets"].append(item)
        ledger["evidence_current_readback"][item["path"]] = {"checked_at_utc": now, **item, "scope": "Sealed actual failure/current main JAR readback; no SDK or app acceptance."}
    ledger["captured_at_utc"] = now
    save(ledger_path, ledger)
    for name in ("production-remaining-tasks-2026-09-30.json", "local-implementation-register-2026-09-30.json"):
        path = REGISTER.parent / name
        document = json.loads(path.read_text())
        ext = document["critical_review_implementation_extension"]
        ext.update({"captured_at_utc": now, "sha256": sha(ledger_path), "specialist_findings_closed": 2,
                    "closed_scope": "PD-02 current local provenance/served-build proof and PD-14 sole-authority hygiene; original production/local acceptance rows unchanged."})
        ext["latest_scoped_evidence"] += row["evidence_packets"][-3:]
        save(path, document)
    register = REGISTER / "IMPLEMENTATION_REGISTER.md"
    text = register.read_text().replace("Updated " + json.loads((before / ledger_path.relative_to(ROOT)).read_text())["captured_at_utc"] + ".", "Updated " + now + ".", 1)
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("| ARC-09 |"):
            links = [f"[{'/'.join(Path(item['path']).parts[-2:])}]({ROOT / item['path']})" for item in row["evidence_packets"]]
            lines[index] = f"| ARC-09 | {row['implementation_status']} | Open | {'; '.join(links)} |"
    register.write_text("\n".join(lines) + "\n")
    originals = {"production-remaining-tasks-2026-09-30.json": "404b4e7bc68b609af872e02b9523e4d8713a476a1b7b25549c7748df38c9b56f",
                 "local-implementation-register-2026-09-30.json": "0f336b290f279a168800d4e9b8b462e91f32b36111cec3bdbcfa14b2ce4c9980"}
    for name, expected in originals.items():
        v = json.loads((REGISTER.parent / name).read_text())
        assert hashlib.sha256(json.dumps(v["items"], sort_keys=True, separators=(",", ":")).encode()).hexdigest() == expected
        assert v["critical_review_implementation_extension"]["specialist_findings_closed"] == 2
        assert v["critical_review_implementation_extension"]["sha256"] == sha(ledger_path)
    save(HERE / "final-register-readback.json", {"at_utc": now, "status": "pass", "original_row_digests": originals,
         "closed_ids": ["PD-02", "PD-14"], "current_owned_files": {str(path.relative_to(ROOT)): sha(path) for path in owned},
         "class_count_correction": "83 class files + one module metadata file; initial84-class shorthand preserved in dated before-registers.",
         "closure_counter_correction": "Two local critical-finding closures; original acceptance rows remain unchanged.",
         "production_ready": False, "goal_status": "active"})
    print(json.dumps({"status": "PASS", "SDK_leaf_count": 57, "actual_main_classes": 83, "ledger_sha256": sha(ledger_path)}))


if __name__ == "__main__":
    main()
