#!/usr/bin/env python3
"""Bind iOS effects to reviewed bytes. Never creates an approval or uploads.

Approval records are metadata, not signatures proving a human's identity.
Protected GitHub environments must independently control signing/publishing.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import collect_release_candidate as source_export
import native_build_config

TARGET = {"bundle_id": "app.cool.mobile", "apple_id": "6783960331", "team_id": "63STJ5N27W",
          "api_url": "https://platform-admin.collect.ikanisa.com", "public_url": "https://collect.ikanisa.com",
          "admin_url": "https://platform-admin.collect.ikanisa.com"}
ENVIRONMENTS = {"signed_candidate": "collect-ios-signing", "testflight_internal": "collect-ios-testflight",
                "metadata": "collect-ios-metadata", "screenshots": "collect-ios-metadata",
                "privacy_public": "collect-ios-privacy"}


class GuardError(ValueError):
    pass


def fail(code):
    raise GuardError(code)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def runtime_configuration_sha256(root=None):
    try:
        values = native_build_config.configuration(dict(os.environ), "ios",
                                                   Path(root) / "pubspec.yaml" if root is not None else None)
    except (ValueError, TypeError) as error:
        raise GuardError("IOS_PUBLIC_BUILD_CONFIGURATION_WRONG") from error
    return digest(json.dumps(values, sort_keys=True, separators=(",", ":")).encode())


def required(name):
    value = os.environ.get("COLLECT_IOS_" + name, "").strip()
    if not value:
        fail("IOS_" + name + "_REQUIRED")
    return value


def sha_value(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value):
        fail("IOS_SHA256_INVALID")
    return value


def read_file(path):
    path = Path(path).absolute()
    if any(part.is_symlink() for part in [path, *path.parents]):
        fail("IOS_SYMLINK_REFUSED")
    try:
        before = path.stat()
        if not stat.S_ISREG(before.st_mode) or before.st_size > 1024 * 1024 * 1024:
            fail("IOS_FILE_INVALID")
        data = path.read_bytes()
        after = path.stat()
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            fail("IOS_FILE_CHANGED")
        return data
    except OSError as error:
        raise GuardError("IOS_FILE_MISSING") from error


def run_command(command, **kwargs):
    try:
        return subprocess.run(command, check=True, capture_output=True, timeout=120, **kwargs)
    except (OSError, subprocess.SubprocessError) as error:
        # Do not echo commands containing credential arguments.
        raise GuardError("IOS_TOOL_FAILED:" + Path(command[0]).name) from error


def timestamp(value):
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if result.tzinfo is None:
            fail("IOS_APPROVAL_TIME_INVALID")
        return result.astimezone(timezone.utc)
    except (AttributeError, ValueError) as error:
        raise GuardError("IOS_APPROVAL_TIME_INVALID") from error


def approval(operation):
    if operation not in ENVIRONMENTS:
        fail("IOS_OPERATION_UNSUPPORTED")
    if os.environ.get("GITHUB_REPOSITORY", "ikanisa/COOL") != "ikanisa/COOL":
        fail("IOS_REPOSITORY_WRONG")
    if os.environ.get("GITHUB_SHA", required("EXPECTED_COMMIT")) != required("EXPECTED_COMMIT"):
        fail("IOS_WORKFLOW_COMMIT_WRONG")
    raw = read_file(required("APPROVAL_FILE"))
    if digest(raw) != sha_value(required("APPROVAL_SHA256")):
        fail("IOS_APPROVAL_CHANGED")
    try:
        record = json.loads(raw)
        if record["schema_version"] != 1 or record["kind"] != "collect_ios_delivery_approval" or record["decision"] != "approved":
            fail("IOS_APPROVAL_INVALID")
        if record["operation"] != operation or record["environment"] != ENVIRONMENTS[operation]:
            fail("IOS_APPROVAL_SCOPE_WRONG")
        if record["target"] != TARGET:
            fail("IOS_TARGET_WRONG")
        if record["source_commit"] != required("EXPECTED_COMMIT") or record["source_manifest_sha256"] != sha_value(required("SOURCE_SHA256")):
            fail("IOS_APPROVAL_SOURCE_WRONG")
        if not all(isinstance(record[key], str) and record[key].strip() for key in ("reviewer", "review_record")):
            fail("IOS_REVIEW_RECORD_REQUIRED")
        now = datetime.now(timezone.utc)
        start, end = timestamp(record["approved_at_utc"]), timestamp(record["expires_at_utc"])
        if not start <= now < end or (end - start).total_seconds() > 7 * 24 * 3600:
            fail("IOS_APPROVAL_STALE")
        if operation == "testflight_internal":
            artifact = record.get("artifact")
            if not isinstance(artifact, dict):
                fail("IOS_APPROVED_ARTIFACT_REQUIRED")
            sha_value(artifact.get("ipa_sha256"))
            sha_value(artifact.get("inspection_sha256"))
        return record
    except (KeyError, TypeError, ValueError) as error:
        if isinstance(error, GuardError):
            raise
        raise GuardError("IOS_APPROVAL_INVALID") from error


def source_identity(root, files):
    observed = {}
    for parent, directories, names in os.walk(root, followlinks=False):
        for name in directories + names:
            path = Path(parent) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink() and not source_export.exclusion(relative):
                fail("IOS_SOURCE_SYMLINK")
        directories[:] = [name for name in directories if not source_export.exclusion((Path(parent) / name).relative_to(root).as_posix())]
        for name in names:
            path = Path(parent) / name
            relative = path.relative_to(root).as_posix()
            if source_export.exclusion(relative):
                continue
            data, mode = source_export.regular_bytes(root, relative)
            observed[relative] = {"sha256": digest(data), "bytes": len(data), "mode": mode}
    if observed != files:
        fail("IOS_WORKING_SOURCE_CHANGED")


def check(operation=None, root=None, inspect_artifact=True):
    operation = operation or required("OPERATION")
    if required("EXPECTED_REF") != "refs/heads/main" or not re.fullmatch(r"[a-f0-9]{40}", required("EXPECTED_COMMIT")):
        fail("IOS_REF_OR_COMMIT_INVALID")
    record = approval(operation)
    candidate = Path(required("CANDIDATE")).absolute()
    result = source_export.verify_candidate(candidate)
    if result["status"] != "pass":
        fail("IOS_CANDIDATE_CHANGED")
    manifest = json.loads(read_file(candidate / source_export.MANIFEST))
    if manifest.get("retain_source_drift") or manifest.get("capture_classification") != "strict_unapproved_source_export":
        fail("IOS_NON_ATOMIC_CANDIDATE")
    if manifest["base_head_observed"] != required("EXPECTED_COMMIT") or manifest["source_manifest_sha256"] != required("SOURCE_SHA256"):
        fail("IOS_CANDIDATE_SOURCE_WRONG")
    root = Path(root or required("WORKDIR")).absolute()
    source_identity(root, manifest["source_files"])
    version = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", (root / "pubspec.yaml").read_text(), re.M)
    if not version or record.get("version") != version[1] or record.get("build_number") != version[2]:
        fail("IOS_PACKAGE_VERSION_WRONG")
    if operation == "signed_candidate":
        if record.get("artifact") is not None:
            fail("IOS_SIGNING_CANNOT_APPROVE_FUTURE_ARTIFACT")
        if record.get("runtime_configuration_sha256") != runtime_configuration_sha256(root):
            fail("IOS_PUBLIC_BUILD_CONFIGURATION_WRONG")
    if operation == "testflight_internal":
        artifact = record.get("artifact", {})
        ipa = Path(required("IPA"))
        inspection_path = Path(required("INSPECTION"))
        if digest(read_file(ipa)) != sha_value(artifact.get("ipa_sha256")) or digest(read_file(inspection_path)) != sha_value(artifact.get("inspection_sha256")):
            fail("IOS_ARTIFACT_NOT_APPROVED")
        inspection = json.loads(read_file(inspection_path))
        if inspection.get("source_commit") != record["source_commit"] or inspection.get("source_manifest_sha256") != record["source_manifest_sha256"]:
            fail("IOS_INSPECTION_SOURCE_WRONG")
        if inspect_artifact and inspect_ipa(ipa, record) != inspection:
            fail("IOS_SIGNED_INSPECTION_CHANGED")
    return record


def prepare(source, candidate, workdir, sdk):
    if required("EXPECTED_REF") != "refs/heads/main":
        fail("IOS_REF_WRONG")
    commit = required("EXPECTED_COMMIT")
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        fail("IOS_COMMIT_INVALID")
    observed = run_command(["git", "rev-parse", "HEAD"], cwd=source, text=True).stdout.strip()
    if commit != observed:
        fail("IOS_COMMIT_WRONG")
    if run_command(["git", "status", "--porcelain", "--untracked-files=all"], cwd=source, text=True).stdout:
        fail("IOS_CHECKOUT_DIRTY")
    operation = required("OPERATION")
    if operation != "unsigned_candidate":
        approval(operation)
    source_export.export_candidate(source, candidate, sdk)
    manifest = json.loads(read_file(candidate / source_export.MANIFEST))
    if manifest["source_manifest_sha256"] != sha_value(required("SOURCE_SHA256")):
        fail("IOS_REVIEWED_SOURCE_WRONG")
    if workdir.exists() or workdir.is_symlink():
        fail("IOS_WORKDIR_EXISTS")
    shutil.copytree(candidate, workdir)
    if operation != "unsigned_candidate":
        check(operation, workdir, inspect_artifact=False) if operation != "testflight_internal" else source_identity(workdir, manifest["source_files"])
    return {"status": "pass", "source_commit": commit, "source_manifest_sha256": manifest["source_manifest_sha256"],
            "source_file_count": manifest["file_count"], "operation": operation,
            "scope": "Exact source bytes; review identity and environment enforcement are external."}


def verify_environment(operation=None):
    record = approval(operation or required("OPERATION"))
    environment = record["environment"]
    endpoint = "repos/ikanisa/COOL/environments/" + environment
    raw = run_command(["gh", "api", "-H", "Accept: application/vnd.github+json", endpoint]).stdout
    branches_raw = run_command(["gh", "api", "-H", "Accept: application/vnd.github+json", endpoint + "/deployment-branch-policies?per_page=100"]).stdout
    policy, branches = json.loads(raw), json.loads(branches_raw)
    if policy.get("name") != environment or policy.get("can_admins_bypass") is not False:
        fail("IOS_ENVIRONMENT_BYPASS_OR_IDENTITY_UNVERIFIED")
    reviewers = [item for item in policy.get("protection_rules", []) if item.get("type") == "required_reviewers"]
    if len(reviewers) != 1 or reviewers[0].get("prevent_self_review") is not True or not reviewers[0].get("reviewers"):
        fail("IOS_ENVIRONMENT_REVIEW_POLICY_UNVERIFIED")
    if policy.get("deployment_branch_policy") != {"protected_branches": False, "custom_branch_policies": True}:
        fail("IOS_ENVIRONMENT_BRANCH_POLICY_UNVERIFIED")
    actual = branches.get("branch_policies", [])
    if branches.get("total_count") != 1 or len(actual) != 1 or actual[0].get("name") != "main" or actual[0].get("type") != "branch":
        fail("IOS_ENVIRONMENT_MAIN_ONLY_POLICY_REQUIRED")
    return {"status": "pass", "repository": "ikanisa/COOL", "environment": environment,
            "read_at_utc": datetime.now(timezone.utc).isoformat(), "policy_sha256": digest(raw),
            "branch_policy_sha256": digest(branches_raw), "policy": policy, "branch_policies": branches,
            "scope": "Fresh GitHub policy readback; source/artifact approval metadata is separately checked."}


def plist_output(raw):
    start = raw.find(b"<?xml")
    if start < 0:
        fail("IOS_SIGNED_PLIST_INVALID")
    try:
        return plistlib.loads(raw[start:])
    except plistlib.InvalidFileException as error:
        raise GuardError("IOS_SIGNED_PLIST_INVALID") from error


def profile_valid(profile):
    entitlements = profile.get("Entitlements", {})
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime) or expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        fail("IOS_PROFILE_EXPIRED")
    if profile.get("TeamIdentifier") != [TARGET["team_id"]] or entitlements.get("application-identifier") != TARGET["team_id"] + "." + TARGET["bundle_id"]:
        fail("IOS_PROFILE_TARGET_WRONG")
    if entitlements.get("aps-environment") != "production" or entitlements.get("get-task-allow") is not False or profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        fail("IOS_PROFILE_DISTRIBUTION_WRONG")
    if not re.fullmatch(r"[A-Za-z0-9-]{8,64}", profile.get("UUID", "")):
        fail("IOS_PROFILE_UUID_INVALID")


def inspect_ipa(ipa, record):
    before = digest(read_file(ipa))
    with tempfile.TemporaryDirectory(prefix="collect-ipa-inspect-") as temp:
        # Resolve only this newly allocated directory: macOS's /var temp alias
        # is a system symlink. User-supplied artifact paths remain refused.
        root = Path(temp).resolve()
        try:
            with zipfile.ZipFile(ipa) as archive:
                members = archive.infolist()
                if len(members) > 100000 or sum(item.file_size for item in members) > 4 * 1024**3:
                    fail("IOS_IPA_SIZE_INVALID")
                seen = set()
                for item in members:
                    path = PurePosixPath(item.filename)
                    mode = item.external_attr >> 16
                    if item.filename in seen or path.is_absolute() or ".." in path.parts or "\\" in item.filename or stat.S_ISLNK(mode):
                        fail("IOS_IPA_PATH_INVALID")
                    seen.add(item.filename)
                    archive.extract(item, root)
                    if mode & 0o111 and not item.is_dir():
                        (root / item.filename).chmod(0o755)
        except (OSError, zipfile.BadZipFile) as error:
            raise GuardError("IOS_IPA_INVALID") from error
        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            fail("IOS_IPA_APP_INVALID")
        app = apps[0]
        info = plistlib.loads(read_file(app / "Info.plist"))
        identity = {"bundle_id": info.get("CFBundleIdentifier"), "version": info.get("CFBundleShortVersionString"), "build_number": info.get("CFBundleVersion")}
        if identity != {"bundle_id": TARGET["bundle_id"], "version": record["version"], "build_number": record["build_number"]}:
            fail("IOS_IPA_IDENTITY_WRONG")
        signer_requirement = 'anchor apple generic and certificate leaf[subject.OU] = "' + TARGET["team_id"] + '"'
        run_command(["/usr/bin/codesign", "--verify", "--deep", "--strict", "-R", signer_requirement, str(app)])
        signature = run_command(["/usr/bin/codesign", "--display", "--verbose=4", str(app)])
        authorities = [line.removeprefix("Authority=") for line in (signature.stdout + signature.stderr).decode().splitlines() if line.startswith("Authority=")]
        if not authorities or not authorities[0].startswith(("Apple Distribution:", "iPhone Distribution:")):
            fail("IOS_DISTRIBUTION_SIGNER_REQUIRED")
        output = run_command(["/usr/bin/codesign", "--display", "--entitlements", ":-", str(app)])
        entitlements = plist_output(output.stdout + output.stderr)
        if entitlements.get("application-identifier") != TARGET["team_id"] + "." + TARGET["bundle_id"] or entitlements.get("com.apple.developer.team-identifier") != TARGET["team_id"] or entitlements.get("aps-environment") != "production" or entitlements.get("get-task-allow") is not False:
            fail("IOS_SIGNED_ENTITLEMENTS_WRONG")
        # The notification bridge reads this shipped Info.plist value to choose
        # its APNS endpoint. A correct signature does not prove that value agrees
        # with the entitlement; reject missing/unexpanded/mismatched markers.
        runtime_apns_environment = info.get("CollectAPNSEnvironment")
        if runtime_apns_environment != entitlements.get("aps-environment"):
            fail("IOS_RUNTIME_APNS_ENVIRONMENT_WRONG")
        if "applinks:collect.ikanisa.com" not in entitlements.get("com.apple.developer.associated-domains", []):
            fail("IOS_SIGNED_LINK_ENTITLEMENT_MISSING")
        profile_path = app / "embedded.mobileprovision"
        profile_output = run_command(["/usr/bin/security", "cms", "-D", "-i", str(profile_path)])
        profile = plist_output(profile_output.stdout)
        profile_valid(profile)
        # Inventory every embedded app/SDK privacy manifest, without pretending
        # this inventory attests API usage or legal adequacy of store answers.
        privacy = {}
        for path in sorted(app.rglob("*.xcprivacy")):
            data = read_file(path)
            value = plistlib.loads(data)
            if not isinstance(value, dict):
                fail("IOS_PRIVACY_MANIFEST_INVALID")
            privacy[path.relative_to(app).as_posix()] = {"sha256": digest(data), "manifest": value}
        if "PrivacyInfo.xcprivacy" not in privacy or privacy["PrivacyInfo.xcprivacy"]["manifest"].get("NSPrivacyTracking") is not False:
            fail("IOS_APP_PRIVACY_MANIFEST_MISSING")
        if digest(read_file(ipa)) != before:
            fail("IOS_IPA_CHANGED_DURING_INSPECTION")
        return {"schema_version": 1, "kind": "collect_signed_ios_inspection", "ipa_sha256": before,
                "source_commit": record["source_commit"], "source_manifest_sha256": record["source_manifest_sha256"],
                "identity": identity, "entitlements": entitlements, "runtime_apns_environment": runtime_apns_environment,
                "profile_sha256": digest(read_file(profile_path)),
                "signing_authorities": authorities, "signer_requirement": signer_requirement,
                "profile_uuid": profile["UUID"], "profile_expiration_utc": profile["ExpirationDate"].isoformat() + "Z",
                "privacy_manifests": privacy, "signature_verification": "codesign --verify --deep --strict -R Apple-anchor-and-team-requirement",
                "scope": "Signature/identity and embedded manifest inventory; not device, API-usage, rights or store approval."}


def signing_paths():
    return Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())) / "collect-ios-signing"


def cleanup_signing():
    directory = signing_paths()
    state = directory / "state.json"
    if not state.exists():
        return {"status": "no_signing_state"}
    record = json.loads(read_file(state))
    failures = []
    try:
        run_command(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *record["previous_keychains"]])
    except GuardError:
        failures.append("restore_keychain_list")
    keychain = directory / "signing.keychain-db"
    if keychain.exists():
        try:
            run_command(["/usr/bin/security", "delete-keychain", str(keychain)])
        except GuardError:
            failures.append("delete_keychain")
    profile = record.get("installed_profile")
    if profile:
        path = Path(profile)
        expected = Path.home() / "Library/MobileDevice/Provisioning Profiles"
        if path.parent != expected or path.is_symlink():
            fail("IOS_CLEANUP_PROFILE_PATH_WRONG")
        try:
            path.unlink(missing_ok=True)
        except OSError:
            failures.append("remove_profile")
    for name in ("distribution.p12", "profile.mobileprovision"):
        (directory / name).unlink(missing_ok=True)
    if failures:
        record["cleanup_failures"] = failures
        state.write_text(json.dumps(record))
        fail("IOS_SIGNING_CLEANUP_INCOMPLETE:" + ",".join(failures))
    shutil.rmtree(directory)
    return {"status": "cleaned"}


def import_signing():
    check("signed_candidate")  # First, before decoding/importing any credential.
    verify_environment("signed_candidate")
    directory = signing_paths()
    directory.mkdir(mode=0o700, exist_ok=False)
    previous = shlex.split(run_command(["/usr/bin/security", "list-keychains", "-d", "user"], text=True).stdout)
    state = {"previous_keychains": previous, "installed_profile": None}
    state_path = directory / "state.json"
    state_path.write_text(json.dumps(state))
    try:
        certificate, profile = directory / "distribution.p12", directory / "profile.mobileprovision"
        for path, name in ((certificate, "APPLE_CERTIFICATE_BASE64"), (profile, "APPLE_PROVISIONING_PROFILE_BASE64")):
            value = os.environ.get(name, "")
            if not value:
                fail("IOS_SIGNING_SECRET_REQUIRED")
            try:
                path.write_bytes(base64.b64decode(value, validate=True))
            except ValueError as error:
                raise GuardError("IOS_SIGNING_BASE64_INVALID") from error
            path.chmod(0o600)
        decoded = plist_output(run_command(["/usr/bin/security", "cms", "-D", "-i", str(profile)]).stdout)
        profile_valid(decoded)
        installed = Path.home() / "Library/MobileDevice/Provisioning Profiles" / (decoded["UUID"] + ".mobileprovision")
        if installed.exists():
            fail("IOS_EXISTING_PROFILE_REFUSED")
        installed.parent.mkdir(parents=True, exist_ok=True)
        with installed.open("xb") as handle:
            # Record ownership only after exclusive creation. A concurrent
            # existing profile must never be removed by our failure cleanup.
            state["installed_profile"] = str(installed)
            state_path.write_text(json.dumps(state))
            handle.write(read_file(profile))
        installed.chmod(0o600)
        password = os.environ.get("KEYCHAIN_PASSWORD", "")
        certificate_password = os.environ.get("APPLE_CERTIFICATE_PASSWORD", "")
        if not password or not certificate_password:
            fail("IOS_SIGNING_SECRET_REQUIRED")
        keychain = directory / "signing.keychain-db"
        run_command(["/usr/bin/security", "create-keychain", "-p", password, str(keychain)])
        run_command(["/usr/bin/security", "set-keychain-settings", "-lut", "21600", str(keychain)])
        run_command(["/usr/bin/security", "unlock-keychain", "-p", password, str(keychain)])
        run_command(["/usr/bin/security", "import", str(certificate), "-P", certificate_password, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security", "-t", "cert", "-f", "pkcs12", "-k", str(keychain)])
        run_command(["/usr/bin/security", "list-keychains", "-d", "user", "-s", str(keychain), *previous])
        run_command(["/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain)])
        certificate.unlink()
        profile.unlink()
        return {"status": "imported_scoped_signing_material"}
    except Exception:
        cleanup_signing()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "check", "verify-environment", "inspect", "import-signing", "cleanup-signing"])
    parser.add_argument("--source", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--workdir", type=Path)
    parser.add_argument("--flutter-sdk", type=Path)
    parser.add_argument("--operation")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            if not all([args.source, args.candidate, args.workdir]):
                fail("IOS_PREPARE_PATHS_REQUIRED")
            result = prepare(args.source.resolve(), args.candidate.absolute(), args.workdir.absolute(), args.flutter_sdk)
        elif args.command == "check":
            record = check(args.operation)
            result = {"status": "pass", "operation": record["operation"], "source_manifest_sha256": record["source_manifest_sha256"]}
        elif args.command == "verify-environment":
            result = verify_environment(args.operation)
            if args.output:
                args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        elif args.command == "inspect":
            record = check("signed_candidate")
            result = inspect_ipa(Path(required("IPA")), record)
            if not args.output or args.output.exists():
                fail("IOS_NEW_INSPECTION_PATH_REQUIRED")
            args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        elif args.command == "import-signing":
            result = import_signing()
        else:
            result = cleanup_signing()
        print(json.dumps(result, sort_keys=True))
        return 0
    except (GuardError, source_export.ReleaseError, OSError, ValueError, KeyError, TypeError) as error:
        code = str(error) if isinstance(error, (GuardError, source_export.ReleaseError)) else "IOS_INPUT_INVALID"
        print(json.dumps({"status": "blocked", "code": code}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
