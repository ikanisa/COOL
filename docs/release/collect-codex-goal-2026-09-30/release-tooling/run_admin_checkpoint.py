#!/usr/bin/env python3
"""Pinned offline Admin checkpoint build; explicit candidate/workspace, public configuration only.

Uses the existing source-export/readback primitives; keeps a pristine candidate
separate from generated bindings/output. An actual build never grants trust,
review, freeze, owner approval, deployment or production acceptance.
"""
import base64
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import stat
import time
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[4]
WORK = None
CANDIDATE = None
PACKET = Path(__file__).resolve().parent
EXPECTED = None
LABEL = None
CACHE = ROOT / ".cache/pub-cache-hygiene-20260930"
PUBLIC_CONFIG = None
PUBLIC_KEY_BYTES = None
PROJECT_REF = "lhbowpbcpwoiparwnwgt"
PUBLIC_DEFINE_KEYS = frozenset({"SUPABASE_URL", "SUPABASE_ANON_KEY", "ENABLE_ADMIN_PANEL", "APP_ENVIRONMENT"})
spec = importlib.util.spec_from_file_location("collect_candidate", ROOT / "scripts/qa/collect_release_candidate.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)



def validate_public_defines(data):
    """Validate four explicit public AppEnv inputs; no remote key attestation."""
    def pairs(items):
        output = {}
        for key, value in items:
            if key in output:
                raise module.ReleaseError("PUBLIC_CONFIG_DUPLICATE_KEY")
            output[key] = value
        return output
    try:
        config = json.loads(data.decode("utf-8"), object_pairs_hook=pairs)
    except module.ReleaseError:
        raise
    except (ValueError, UnicodeError):
        raise module.ReleaseError("PUBLIC_CONFIG_JSON_INVALID")
    if not isinstance(config, dict) or set(config) != PUBLIC_DEFINE_KEYS:
        raise module.ReleaseError("PUBLIC_CONFIG_KEYS_INVALID")
    if config["SUPABASE_URL"] != "https://" + PROJECT_REF + ".supabase.co":
        raise module.ReleaseError("PUBLIC_CONFIG_PROJECT_INVALID")
    if config["APP_ENVIRONMENT"] != "production" or not (config["ENABLE_ADMIN_PANEL"] is True or config["ENABLE_ADMIN_PANEL"] == "true"):
        raise module.ReleaseError("PUBLIC_CONFIG_ENVIRONMENT_INVALID")
    key = config["SUPABASE_ANON_KEY"]
    if not isinstance(key, str) or len(key) > 4096:
        raise module.ReleaseError("PUBLIC_CONFIG_KEY_INVALID")
    if re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{20,200}", key):
        form = "public_publishable_key"
    else:
        parts = key.split(".")
        if len(parts) != 3 or not all(re.fullmatch(r"[A-Za-z0-9_-]+", part) for part in parts):
            raise module.ReleaseError("PUBLIC_CONFIG_KEY_INVALID")
        try:
            decode = lambda value: json.loads(base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)))
            header, claims = decode(parts[0]), decode(parts[1])
        except (ValueError, UnicodeError):
            raise module.ReleaseError("PUBLIC_CONFIG_KEY_INVALID")
        allowed = {"iss", "ref", "role", "iat", "exp"}
        if not isinstance(header, dict) or header != {"alg": "HS256", "typ": "JWT"} or not isinstance(claims, dict) or set(claims) != allowed or claims["role"] != "anon" or claims["ref"] != PROJECT_REF or claims["iss"] != "supabase" or any(type(claims[name]) is not int for name in ("iat", "exp")) or not 0 < claims["iat"] <= time.time() + 300 or claims["exp"] <= time.time() or claims["exp"] <= claims["iat"]:
            raise module.ReleaseError("PUBLIC_CONFIG_KEY_INVALID")
        if len(parts[2]) < 32:
            raise module.ReleaseError("PUBLIC_CONFIG_KEY_INVALID")
        form = "public_anon_jwt"
    return config, {"key_form": form, "keys": sorted(PUBLIC_DEFINE_KEYS), "project_allowlist_match": True,
                    "privileged_or_user_credentials_allowed": False, "remote_authentication_attested": False}


def read_public_defines(path, expected_sha256):
    path = path.absolute()
    if not re.fullmatch(r"[a-f0-9]{64}", expected_sha256 or ""):
        raise module.ReleaseError("PUBLIC_CONFIG_HASH_REQUIRED")
    for ancestor in [path, *path.parents]:
        if ancestor.is_symlink():
            raise module.ReleaseError("PUBLIC_CONFIG_SYMLINK_REFUSED")
    path = path.resolve()
    if path == ROOT or ROOT in path.parents or (CANDIDATE and (path == CANDIDATE or CANDIDATE in path.parents)) or (WORK and (path == WORK or WORK in path.parents)):
        raise module.ReleaseError("PUBLIC_CONFIG_LOCATION_INVALID")
    try:
        before = path.stat()
        parent = path.parent.stat()
        if not stat.S_ISREG(before.st_mode) or stat.S_IMODE(before.st_mode) != 0o600 or before.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) != 0o700 or parent.st_uid != os.getuid() or before.st_size > 16 * 1024:
            raise module.ReleaseError("PUBLIC_CONFIG_PERMISSIONS_INVALID")
        raw, mode = module.regular_bytes(path.parent, path.name)
        if mode != 0o600 or module.sha(raw) != expected_sha256:
            raise module.ReleaseError("PUBLIC_CONFIG_HASH_CHANGED")
    except OSError:
        raise module.ReleaseError("PUBLIC_CONFIG_FILE_REQUIRED")
    config, metadata = validate_public_defines(raw)
    return raw, config, {**metadata, "source_path": str(path), "sha256": expected_sha256,
                          "bytes": len(raw), "file_mode": "0600", "parent_mode": "0700"}


def stage_public_defines(raw):
    folder = WORK / ".collect-build-inputs"
    path = folder / "admin-public-defines.json"
    if folder.is_symlink() or path.is_symlink():
        raise module.ReleaseError("PUBLIC_CONFIG_SYMLINK_REFUSED")
    folder.mkdir(mode=0o700, exist_ok=True)
    if stat.S_IMODE(folder.stat().st_mode) != 0o700:
        raise module.ReleaseError("PUBLIC_CONFIG_PERMISSIONS_INVALID")
    if path.exists():
        if module.sha(path.read_bytes()) != module.sha(raw) or stat.S_IMODE(path.stat().st_mode) != 0o600:
            raise module.ReleaseError("PUBLIC_CONFIG_STAGED_CHANGED")
    else:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
    if module.sha(path.read_bytes()) != module.sha(raw):
        raise module.ReleaseError("PUBLIC_CONFIG_STAGED_CHANGED")
    return path


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
    try:
        result = subprocess.run(command, cwd=WORK, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        result = subprocess.CompletedProcess(command, 124, (error.stdout or b"") + b"\nBounded compilation command timeout.\n")
    module.screen_credentials(result.stdout, name + ".log")
    raw_stdout_sha256 = module.sha(result.stdout)
    occurrences = result.stdout.count(PUBLIC_KEY_BYTES) if PUBLIC_KEY_BYTES else 0
    safe_stdout = result.stdout.replace(PUBLIC_KEY_BYTES, b"[PUBLIC_CONFIG_KEY_REDACTED]") if PUBLIC_KEY_BYTES else result.stdout
    (PACKET / (name + ".log")).write_bytes(safe_stdout)
    receipt = {"command": command, "exit_code": result.returncode, "started_at_utc": started,
               "finished_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "log_sha256": module.sha(safe_stdout), "raw_stdout_sha256": raw_stdout_sha256,
               "public_key_occurrences_redacted": occurrences, "checkpoint_runner_sha256": module.sha(Path(__file__).read_bytes()),
               "source_exporter_sha256": module.sha((ROOT / "scripts/qa/collect_release_candidate.py").read_bytes()),
               "backend_configuration_supplied": PUBLIC_CONFIG is not None,
               "public_configuration": PUBLIC_CONFIG,
               "otp_requests": 0, "provider_sends": 0, "hosted_mutations": 0}
    (PACKET / (name + ".result.json")).write_bytes(module.canonical(receipt))
    print(safe_stdout.decode(errors="replace")[-4000:], flush=True)
    if result.returncode:
        raise module.ReleaseError("ADMIN_BUILD_COMMAND_FAILED")
    return receipt


def main():
    global WORK, CANDIDATE, PACKET, EXPECTED, LABEL, CACHE, PUBLIC_CONFIG, PUBLIC_KEY_BYTES
    parser = module.SafeParser(description=__doc__)
    parser.add_argument("mode", choices=["plain", "configured", "evidence"])
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--packet", required=True, type=Path)
    parser.add_argument("--label", required=True)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--defines-file", type=Path)
    parser.add_argument("--defines-sha256")
    args = parser.parse_args()
    if args.mode == "configured":
        if not args.defines_file or not args.defines_sha256:
            raise module.ReleaseError("PUBLIC_CONFIG_REQUIRED")
    elif args.defines_file or args.defines_sha256:
        raise module.ReleaseError("PUBLIC_CONFIG_MODE_INVALID")
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,40}", args.label):
        raise module.ReleaseError("ADMIN_BUILD_LABEL_INVALID")
    if not re.fullmatch(r"[a-f0-9]{64}", args.manifest_sha256):
        raise module.ReleaseError("CANDIDATE_MANIFEST_HASH_INVALID")
    for selected in (args.workspace, args.candidate):
        for ancestor in [selected.absolute(), *selected.absolute().parents]:
            if ancestor.is_symlink():
                raise module.ReleaseError("CANDIDATE_SYMLINK_REFUSED")
    WORK, CANDIDATE = args.workspace.resolve(), args.candidate.resolve()
    PACKET, EXPECTED, LABEL, CACHE = args.packet.resolve(), args.manifest_sha256, args.label, args.cache.resolve()
    if WORK == ROOT or ROOT in WORK.parents or WORK == CANDIDATE or CANDIDATE in WORK.parents:
        raise module.ReleaseError("CANDIDATE_DESTINATION_NOT_ISOLATED")
    PACKET.mkdir(parents=True, exist_ok=True)
    raw_defines = None
    staged_defines = None
    PUBLIC_CONFIG = None
    PUBLIC_KEY_BYTES = None
    if args.mode == "configured":
        raw_defines, public_values, PUBLIC_CONFIG = read_public_defines(args.defines_file, args.defines_sha256)
        PUBLIC_KEY_BYTES = public_values["SUPABASE_ANON_KEY"].encode("utf-8")
    source_readback = module.verify_candidate(CANDIDATE, expected_manifest_sha256=EXPECTED)
    if source_readback["status"] != "pass":
        raise module.ReleaseError("CANDIDATE_READBACK_REQUIRED", [item["path"] for item in source_readback["changes"]])
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
    if args.mode in ("plain", "configured"):
        run_command([flutter, "pub", "get", "--offline", "--enforce-lockfile"], LABEL + "-pub-offline", environment, 240)
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
               "checkpoint_runner_sha256": module.sha(Path(__file__).read_bytes()),
               "source_exporter_sha256": module.sha((ROOT / "scripts/qa/collect_release_candidate.py").read_bytes()),
               "dependency_source_trust_attested": False, "scope": "Offline enforced-lock resolution and existing package roots; no dependency trust or current-tree acceptance"}
    (PACKET / (LABEL + "-dependency-binding.json")).write_bytes(module.canonical(binding))
    if raw_defines is not None:
        staged_defines = stage_public_defines(raw_defines)
        PUBLIC_CONFIG = {**PUBLIC_CONFIG, "staged_path": str(staged_defines)}
    output = WORK / {"plain": "build/web", "configured": "build/admin_configured", "evidence": "build/admin_evidence"}[args.mode]
    command = [flutter, "build", "web", "--release", "--no-pub", "--no-wasm-dry-run", "--target", "lib/main_admin.dart"]
    if args.mode == "evidence":
        command.extend(["--dart-define=ADMIN_PWA_EVIDENCE_MODE=true", "--output", str(output)])
    elif args.mode == "configured":
        command.extend(["--dart-define-from-file", str(staged_defines), "--output", str(output)])
    name = LABEL + "-" + args.mode + "-build"
    receipt = run_command(command, name, environment, 600)
    changed = selected_changes(manifest)
    if changed:
        raise module.ReleaseError("CANDIDATE_BUILD_SOURCE_CHANGED", changed)
    if args.mode == "configured":
        read_public_defines(args.defines_file, args.defines_sha256)
        if module.sha(staged_defines.read_bytes()) != args.defines_sha256:
            raise module.ReleaseError("PUBLIC_CONFIG_STAGED_CHANGED")
    files = {}
    for path in sorted(output.rglob("*")):
        if path.is_symlink():
            raise module.ReleaseError("CANDIDATE_SYMLINK_REFUSED")
        if path.is_file():
            data = path.read_bytes()
            files[path.relative_to(output).as_posix()] = {"sha256": module.sha(data), "bytes": len(data)}
    candidate_final = module.verify_candidate(CANDIDATE, expected_manifest_sha256=EXPECTED)
    if candidate_final["status"] != "pass":
        raise module.ReleaseError("CANDIDATE_READBACK_REQUIRED", [item["path"] for item in candidate_final["changes"]])
    result = {"status": "pass", "kind": {"evidence": "synthetic_admin_evidence_bundle", "plain": "backend_unconfigured_admin_compilation", "configured": "public_project_configured_admin_compilation"}[args.mode],
              "workspace": str(WORK), "output": str(output), "source_snapshot_created_at_utc": manifest["created_at_utc"],
              "candidate_manifest_sha256": EXPECTED, "source_current_tree_accepted": False,
              "original_tree_stability_after_capture_attested": False, "approvals": manifest["approvals"],
              "artifact_files": files, "artifact_manifest_sha256": module.sha(module.canonical(files)),
              "artifact_file_count": len(files), "total_artifact_bytes": sum(v["bytes"] for v in files.values()),
              "selected_source_files_unchanged_after_build": True, "pristine_candidate_final_readback": candidate_final, "evidence_mode": args.mode == "evidence",
              "backend_configuration_supplied": PUBLIC_CONFIG is not None,
               "public_configuration": PUBLIC_CONFIG, "live_authentication_verified": False, "deployment_verified": False, "production_ready": False, "command_receipt": receipt}
    (PACKET / (name + ".json")).write_bytes(module.canonical(result))
    print(json.dumps({key:result[key] for key in ("status", "kind", "artifact_file_count", "artifact_manifest_sha256", "candidate_manifest_sha256", "production_ready")}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        result = {"status": "blocked", "reason_code": getattr(error, "code", "ADMIN_BUILD_FAILED"),
                  "affected_source_paths": getattr(error, "paths", []), "credential_values_reported": False, "workspace": str(WORK) if WORK else None, "production_ready": False}
        (PACKET / ((LABEL or "checkpoint") + "-build-blocked.json")).write_bytes(module.canonical(result))
        print(json.dumps(result))
        raise SystemExit(2)
