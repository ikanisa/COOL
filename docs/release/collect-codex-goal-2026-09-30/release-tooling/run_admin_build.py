#!/usr/bin/env python3
"""Pinned offline Admin compilation from a separately verified unapproved work copy."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[4]
WORK = Path("/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20260930-admin-build-02")
PACKET = Path(__file__).resolve().parent
EXPECTED = "4d49758c617893d96740bebc7ec9f34beac783c4d6019daadf754ed6e851a4fc"
CACHE = ROOT / ".cache/pub-cache-hygiene-20260930"
spec = importlib.util.spec_from_file_location("collect_candidate", ROOT / "scripts/qa/collect_release_candidate.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def selected_changes(manifest):
    changed = []
    for name, expected in manifest["source_files"].items():
        try:
            data, mode = module.regular_bytes(WORK, name)
            if {"sha256": module.sha(data), "bytes": len(data), "mode": mode} != expected:
                changed.append(name)
        except module.ReleaseError:
            changed.append(name)
    return changed


def run_command(command, name, environment, timeout):
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    print("Starting " + name, flush=True)
    result = subprocess.run(command, cwd=WORK, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=timeout, check=False)
    module.screen_credentials(result.stdout, name + ".log")
    (PACKET / (name + ".log")).write_bytes(result.stdout)
    receipt = {"command": command, "exit_code": result.returncode, "started_at_utc": started,
               "finished_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "log_sha256": module.sha(result.stdout), "backend_configuration_supplied": False,
               "otp_requests": 0, "provider_sends": 0, "hosted_mutations": 0}
    (PACKET / (name + ".result.json")).write_bytes(module.canonical(receipt))
    print(result.stdout.decode(errors="replace")[-4000:], flush=True)
    if result.returncode:
        raise module.ReleaseError("ADMIN_BUILD_COMMAND_FAILED")
    return receipt


def main():
    parser = module.SafeParser(description=__doc__)
    parser.add_argument("mode", choices=["plain", "evidence"])
    args = parser.parse_args()
    raw, _ = module.regular_bytes(WORK, module.MANIFEST)
    if module.sha(raw) != EXPECTED:
        raise module.ReleaseError("CANDIDATE_MANIFEST_HASH_CHANGED")
    manifest = json.loads(raw)
    changed = selected_changes(manifest)
    if changed:
        raise module.ReleaseError("CANDIDATE_BUILD_SOURCE_CHANGED", changed)
    sdk = Path(manifest["toolchain"]["flutter"]["sdk_path"])
    metadata = json.loads((sdk / "bin/cache/flutter.version.json").read_text())
    if metadata["frameworkVersion"] != manifest["toolchain"]["flutter"]["pin"] or metadata["frameworkRevision"] != manifest["toolchain"]["flutter"]["framework_revision"] or module.sha((sdk / "bin/flutter").read_bytes()) != manifest["toolchain"]["flutter"]["launcher_sha256"]:
        raise module.ReleaseError("CANDIDATE_FLUTTER_PIN_MISMATCH")
    if not CACHE.is_dir():
        raise module.ReleaseError("CANDIDATE_DEPENDENCY_CACHE_REQUIRED")
    environment = {key: os.environ[key] for key in ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL") if key in os.environ}
    environment.update({"PUB_CACHE": str(CACHE), "FLUTTER_SUPPRESS_ANALYTICS": "true", "CI": "true"})
    flutter = str(sdk / "bin/flutter")
    if args.mode == "plain":
        run_command([flutter, "pub", "get", "--offline", "--enforce-lockfile"], "admin02-pub-offline", environment, 240)
    configuration = WORK / ".dart_tool/package_config.json"
    config = json.loads(configuration.read_text())
    if config.get("configVersion") != 2 or config.get("generatorVersion") != manifest["toolchain"]["flutter"]["dart_version"]:
        raise module.ReleaseError("CANDIDATE_PACKAGE_BINDING_INVALID")
    expected_forks = {"file_saver": WORK / "third_party/file_saver", "firebase_messaging": WORK / "third_party/firebase_messaging", "gotrue": WORK / "third_party/gotrue", "collect_app": WORK}
    matched = set()
    counts = {"work_copy": 0, "installed_cache": 0, "installed_sdk": 0}
    for package in config["packages"]:
        uri = urlparse(package["rootUri"])
        if uri.scheme not in ("", "file"):
            raise module.ReleaseError("CANDIDATE_PACKAGE_BINDING_INVALID")
        path = Path(unquote(uri.path)) if uri.scheme == "file" else configuration.parent / unquote(package["rootUri"])
        path = path.resolve()
        if not path.is_dir():
            raise module.ReleaseError("CANDIDATE_PACKAGE_BINDING_INVALID")
        if package["name"] in expected_forks:
            if path != expected_forks[package["name"]].resolve():
                raise module.ReleaseError("CANDIDATE_LOCAL_FORK_BINDING_INVALID")
            matched.add(package["name"])
        if path == WORK or WORK in path.parents:
            counts["work_copy"] += 1
        elif path == CACHE or CACHE in path.parents:
            counts["installed_cache"] += 1
        elif path == sdk or sdk in path.parents:
            counts["installed_sdk"] += 1
        else:
            raise module.ReleaseError("CANDIDATE_PACKAGE_BINDING_INVALID")
    if matched != set(expected_forks):
        raise module.ReleaseError("CANDIDATE_LOCAL_FORK_BINDING_INVALID")
    locks = {name: module.sha((WORK / name).read_bytes()) for name in module.LOCKS}
    if locks != manifest["toolchain"]["lock_sha256"] or selected_changes(manifest):
        raise module.ReleaseError("CANDIDATE_BUILD_SOURCE_CHANGED")
    binding = {"status": "pass", "package_count": len(config["packages"]), "package_location_counts": counts,
               "local_forks_and_application_bound_inside_work_copy": True, "six_lock_inputs_unchanged": True,
               "selected_source_files_unchanged": True, "package_config_sha256": module.sha(configuration.read_bytes()),
               "candidate_manifest_sha256": EXPECTED, "dependency_cache": str(CACHE), "sdk_revision": metadata["frameworkRevision"],
               "dependency_source_trust_attested": False, "scope": "Offline enforced-lock resolution and existing package roots; no dependency trust or current-tree acceptance"}
    (PACKET / "admin02-dependency-binding.json").write_bytes(module.canonical(binding))
    output = WORK / ("build/admin_evidence" if args.mode == "evidence" else "build/web")
    command = [flutter, "build", "web", "--release", "--no-pub", "--no-wasm-dry-run", "--target", "lib/main_admin.dart"]
    if args.mode == "evidence":
        command.extend(["--dart-define=ADMIN_PWA_EVIDENCE_MODE=true", "--output", str(output)])
    name = "admin02-" + args.mode + "-build"
    receipt = run_command(command, name, environment, 600)
    changed = selected_changes(manifest)
    if changed:
        raise module.ReleaseError("CANDIDATE_BUILD_SOURCE_CHANGED", changed)
    files = {}
    for path in sorted(output.rglob("*")):
        if path.is_symlink():
            raise module.ReleaseError("CANDIDATE_SYMLINK_REFUSED")
        if path.is_file():
            data = path.read_bytes()
            files[path.relative_to(output).as_posix()] = {"sha256": module.sha(data), "bytes": len(data)}
    result = {"status": "pass", "kind": "synthetic_admin_evidence_bundle" if args.mode == "evidence" else "backend_unconfigured_admin_compilation",
              "workspace": str(WORK), "output": str(output), "source_snapshot_created_at_utc": manifest["created_at_utc"],
              "candidate_manifest_sha256": EXPECTED, "source_current_tree_accepted": False,
              "known_source_drift_report": "candidate02-current-drift.json", "approvals": manifest["approvals"],
              "artifact_files": files, "artifact_manifest_sha256": module.sha(module.canonical(files)),
              "artifact_file_count": len(files), "total_artifact_bytes": sum(v["bytes"] for v in files.values()),
              "selected_source_files_unchanged_after_build": True, "evidence_mode": args.mode == "evidence",
              "backend_configuration_supplied": False, "production_ready": False, "command_receipt": receipt}
    (PACKET / (name + ".json")).write_bytes(module.canonical(result))
    print(json.dumps({key:result[key] for key in ("status", "kind", "artifact_file_count", "artifact_manifest_sha256", "candidate_manifest_sha256", "production_ready")}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        result = {"status": "blocked", "reason_code": getattr(error, "code", "ADMIN_BUILD_FAILED"),
                  "affected_source_paths": getattr(error, "paths", []), "credential_values_reported": False}
        (PACKET / "admin02-build-blocked.json").write_bytes(module.canonical(result))
        print(json.dumps(result))
        raise SystemExit(2)
