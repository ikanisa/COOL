#!/usr/bin/env python3
"""Record the explicitly authorized single-package offline path rebind."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import yaml

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
FLUTTER = "/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter"
files = ["pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json", ".flutter-plugins-dependencies"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


env = {key: value for key, value in os.environ.items() if key in {"HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"}}
env["PUB_CACHE"] = str(ROOT / ".cache/pub-cache-hygiene-20260930")
commands = []
for name, command in [("pinned-version", [FLUTTER, "--version", "--machine"]),
                      ("offline-reviewed-rebind", [FLUTTER, "pub", "get", "--offline"]),
                      ("offline-enforced-lock", [FLUTTER, "pub", "get", "--offline", "--enforce-lockfile"])]:
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
    stdout, stderr = OUT / (name + ".stdout"), OUT / (name + ".stderr")
    stdout.write_bytes(result.stdout); stderr.write_bytes(result.stderr)
    commands.append({"name": name, "command": command, "exit_code": result.returncode,
                     "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr)})
    if result.returncode:
        (OUT / "execution-failed.json").write_text(json.dumps({"commands": commands}, indent=2) + "\n")
        raise SystemExit(result.returncode)
    if name == "pinned-version":
        version = json.loads(result.stdout)
        assert version["flutterVersion"] == "3.44.4"
        assert version["frameworkRevision"] == "ad70ec4617166f1c38e5d2bfd388af71fda14f06"
before = yaml.safe_load((OUT / "before-pubspec.lock").read_text())
after = yaml.safe_load((ROOT / "pubspec.lock").read_text())
assert set(before["packages"]) == set(after["packages"])
version_changes = [name for name in before["packages"] if before["packages"][name]["version"] != after["packages"][name]["version"]]
package_changes = [name for name in before["packages"] if before["packages"][name] != after["packages"][name]]
assert version_changes == []
assert package_changes == ["firebase_messaging"]
assert after["packages"]["firebase_messaging"]["description"] == {"path": "third_party/firebase_messaging", "relative": True}
assert after["packages"]["firebase_messaging"]["version"] == "16.5.0"
assert after["packages"]["gotrue"] == before["packages"]["gotrue"]
before_manifest = yaml.safe_load((OUT / "before-pubspec.yaml").read_text())
manifest = yaml.safe_load((ROOT / "pubspec.yaml").read_text())
assert manifest["dependencies"] == before_manifest["dependencies"]
assert manifest["dev_dependencies"] == before_manifest["dev_dependencies"]
expected = dict(before_manifest.get("dependency_overrides", {}))
expected["firebase_messaging"] = {"path": "third_party/firebase_messaging"}
assert manifest["dependency_overrides"] == expected
current = {}
for name in files:
    path = ROOT / name
    (OUT / ("after-" + path.name)).write_bytes(path.read_bytes())
    current[name] = sha(path)
config = json.loads((ROOT / ".dart_tool/package_config.json").read_text())
entry = next(package for package in config["packages"] if package["name"] == "firebase_messaging")
assert entry["rootUri"] == "../third_party/firebase_messaging"
plugins = json.loads((ROOT / ".flutter-plugins-dependencies").read_text())
resolved = {platform: [row["path"] for row in rows if row["name"] == "firebase_messaging"]
            for platform, rows in plugins["plugins"].items()}
assert all(paths == [str(ROOT / "third_party/firebase_messaging") + "/"] for paths in resolved.values() if paths)
report = {"status": "pass", "kind": "single_reviewed_package_path_binding", "commands": commands,
          "flutter_version": version, "version_changes": version_changes, "changed_lock_packages": package_changes,
          "package_count": len(after["packages"]), "gotrue_binding_preserved": True,
          "manifest_direct_dependencies_preserved": True, "current_source_sha256": current,
          "resolved_firebase_package": entry, "resolved_plugin_platforms": resolved,
          "offline_execution": True, "signed_or_provider_acceptance": False,
          "recorder_sha256": sha(Path(__file__))}
(OUT / "verification.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print(json.dumps({"status": "pass", "changed_packages": package_changes, "version_changes": version_changes,
                  "verification_sha256": sha(OUT / "verification.json")}))
