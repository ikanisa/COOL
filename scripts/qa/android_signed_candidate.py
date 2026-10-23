#!/usr/bin/env python3
"""One protected Android candidate build; never publishes or creates approval."""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import collect_release_candidate as source_export
import native_build_config

ENVIRONMENT = "collect-android-signing"
PACKAGE = "app.cool.mobile"
AAB = "build/app/outputs/bundle/productionRelease/app-production-release.aab"
APK = "build/app/outputs/flutter-apk/app-production-release.apk"
BUILD_TIMEOUT_SECONDS = 3000
BUILD_TERM_GRACE_SECONDS = 5
BUILD_KILL_GRACE_SECONDS = 5


class Blocked(ValueError):
    pass


def require(condition, code):
    if not condition:
        raise Blocked(code)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def unique(items):
    result = {}
    for key, value in items:
        require(key not in result, "ANDROID_DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def parsed(data):
    return json.loads(data, object_pairs_hook=unique)


def command(args, **kwargs):
    try:
        result = subprocess.run(args, check=True, capture_output=True, timeout=120, **kwargs)
        require(len(result.stdout) < 2 * 1024**2, "ANDROID_TOOL_OUTPUT_BOUND")
        return result.stdout
    except (OSError, subprocess.SubprocessError) as error:
        raise Blocked("ANDROID_TOOL_FAILED") from error


def paths():
    root = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    temporary = Path(os.environ["RUNNER_TEMP"]).resolve()
    return root, temporary / "collect-android-pristine", temporary / "android-delivery", temporary / "collect-android-signing"


def workflow_identity(root):
    commit = os.environ.get("COLLECT_ANDROID_EXPECTED_COMMIT", "")
    require(os.environ.get("GITHUB_REPOSITORY") == "ikanisa/COOL"
            and os.environ.get("GITHUB_REF") == "refs/heads/main"
            and os.environ.get("GITHUB_SHA") == commit
            and re.fullmatch(r"[a-f0-9]{40}", commit), "ANDROID_MAIN_IDENTITY_REQUIRED")
    require(command(["git", "rev-parse", "HEAD"], cwd=root).decode().strip() == commit,
            "ANDROID_CHECKOUT_COMMIT_WRONG")
    return commit


def configuration_and_approval(root):
    commit = workflow_identity(root)
    pin = os.environ.get("COLLECT_ANDROID_APPROVED_UPLOAD_CERT_SHA256", "").replace(":", "").upper()
    require(re.fullmatch(r"[A-F0-9]{64}", pin), "ANDROID_APPROVED_UPLOAD_CERT_REQUIRED")
    number = os.environ.get("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", "")
    require(re.fullmatch(r"[1-9][0-9]+", number), "ANDROID_PLAY_INTEGRITY_PROJECT_REQUIRED")
    profile = native_build_config.configuration(dict(os.environ), "android", root / "pubspec.yaml")
    provider_raw = os.environ.get("COLLECT_ANDROID_GOOGLE_SERVICES_JSON", "").encode()
    require(0 < len(provider_raw) < 1024**2, "ANDROID_PUBLIC_PROVIDER_CONFIG_REQUIRED")
    source_export.screen_credentials(provider_raw, "android/app/google-services.json")
    provider = parsed(provider_raw)
    require(isinstance(provider, dict), "ANDROID_PUBLIC_PROVIDER_CONFIG_REQUIRED")
    require(any(row.get("client_info", {}).get("android_client_info", {}).get("package_name") == PACKAGE
                for row in provider.get("client", [])), "ANDROID_PUBLIC_PROVIDER_PACKAGE_WRONG")
    raw = os.environ.get("REVIEWED_ANDROID_APPROVAL_RECORD", "").encode()
    require(sha(raw) == os.environ.get("COLLECT_ANDROID_APPROVAL_SHA256"), "ANDROID_APPROVAL_DIGEST_WRONG")
    record = parsed(raw)
    require(isinstance(record, dict), "ANDROID_APPROVAL_OBJECT_REQUIRED")
    version = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", (root / "pubspec.yaml").read_text(), re.M)
    require(version is not None, "ANDROID_VERSION_REQUIRED")
    expected = {"schema_version": 1, "kind": "collect_android_candidate_approval", "decision": "approved",
                "operation": "signed_candidate", "environment": ENVIRONMENT, "application_id": PACKAGE,
                "source_commit": commit, "source_manifest_sha256": os.environ.get("COLLECT_ANDROID_SOURCE_SHA256"),
                "public_runtime_config_sha256": sha(canonical(profile)), "google_services_sha256": sha(provider_raw),
                "play_integrity_cloud_project_number": number, "upload_certificate_sha256": pin,
                "version": version[1], "build_number": version[2], "artifact": None}
    require(re.fullmatch(r"[a-f0-9]{64}", expected["source_manifest_sha256"] or ""), "ANDROID_SOURCE_DIGEST_REQUIRED")
    require(all(record.get(key) == value for key, value in expected.items()), "ANDROID_APPROVAL_SCOPE_OR_INPUT_WRONG")
    require(all(isinstance(record.get(key), str) and record[key].strip()
                for key in ("reviewer", "review_record")), "ANDROID_EXTERNAL_REVIEW_REQUIRED")
    start, end = (datetime.fromisoformat(record[key].replace("Z", "+00:00"))
                  for key in ("approved_at_utc", "expires_at_utc"))
    require(start.tzinfo is not None and end.tzinfo is not None
            and start <= datetime.now(timezone.utc) < end
            and 0 < (end - start).total_seconds() <= 7 * 86400, "ANDROID_APPROVAL_TIME_WRONG")
    return record, profile, provider_raw


def environment_policy():
    endpoint = "repos/ikanisa/COOL/environments/" + ENVIRONMENT
    policy = parsed(command(["gh", "api", endpoint]))
    branches = parsed(command(["gh", "api", endpoint + "/deployment-branch-policies?per_page=100"]))
    reviewers = [r for r in policy.get("protection_rules", []) if r.get("type") == "required_reviewers"]
    actual = branches.get("branch_policies", [])
    require(policy.get("name") == ENVIRONMENT and policy.get("can_admins_bypass") is False
            and len(reviewers) == 1 and reviewers[0].get("prevent_self_review") is True
            and reviewers[0].get("reviewers")
            and policy.get("deployment_branch_policy") == {"protected_branches": False, "custom_branch_policies": True}
            and branches.get("total_count") == 1
            and len(actual) == 1 and actual[0].get("name") == "main" and actual[0].get("type") == "branch",
            "ANDROID_PROTECTED_REVIEW_POLICY_REQUIRED")
    return {"read_at_utc": datetime.now(timezone.utc).isoformat(), "policy": policy, "branch_policies": branches}


def policy_preflight():
    # This read-only action runs in a job WITHOUT an environment reference.
    # Missing/unprotected environments fail before GitHub can auto-create the
    # signing job's environment or expose any signing-step secret inputs.
    root = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    workflow_identity(root)
    environment_policy()


def source_check(root, pristine, record):
    result = source_export.verify_candidate(pristine, root)
    require(result["status"] == "pass", "ANDROID_REVIEWED_SOURCE_CHANGED")
    manifest = parsed((pristine / source_export.MANIFEST).read_bytes())
    require(manifest.get("capture_classification") == "strict_unapproved_source_export"
            and not manifest.get("retain_source_drift")
            and manifest["base_head_observed"] == record["source_commit"]
            and manifest["source_manifest_sha256"] == record["source_manifest_sha256"],
            "ANDROID_REVIEWED_SOURCE_WRONG")
    return manifest


def prepare():
    root, pristine, output, _ = paths()
    record, _, _ = configuration_and_approval(root)
    require(not command(["git", "status", "--porcelain", "--untracked-files=all"], cwd=root), "ANDROID_CLEAN_CHECKOUT_REQUIRED")
    environment_policy()
    source_export.export_candidate(root, pristine, Path(os.environ["FLUTTER_ROOT"]))
    source_check(root, pristine, record)
    require(not output.exists() and not output.is_symlink(), "ANDROID_NEW_OUTPUT_REQUIRED")
    output.mkdir(mode=0o700)


def owned_group_exists(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False
    except OSError as error:
        raise Blocked("ANDROID_BUILDER_GROUP_STATE_UNKNOWN") from error


def wait_for_owned_group_exit(process, seconds):
    deadline = time.monotonic() + seconds
    while True:
        # poll reaps the direct wrapper as soon as it exits.
        reaped = process.poll() is not None
        try:
            absent = not owned_group_exists(process.pid)
        except Blocked:
            # A transient EPERM/unknown probe never establishes absence. Give
            # it only this bounded grace; unresolved state cannot permit cleanup.
            absent = False
        if absent and reaped:
            process.wait(timeout=0)
            return True
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(0.05, remaining))


def stop_owned_builder_group(process):
    for sig, grace in ((signal.SIGTERM, BUILD_TERM_GRACE_SECONDS),
                       (signal.SIGKILL, BUILD_KILL_GRACE_SECONDS)):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
        except OSError as error:
            raise Blocked("ANDROID_BUILDER_GROUP_TEARDOWN_UNCONFIRMED") from error
        if wait_for_owned_group_exit(process, grace):
            return
    raise Blocked("ANDROID_BUILDER_GROUP_TEARDOWN_UNCONFIRMED")


def run_builder(root, environment, log, private):
    marker = private / "owned-builder-group"
    # Unknown launch state is retained rather than allowing later cleanup to
    # delete files that an unconfirmed builder could still hold open.
    marker.write_text("starting\n")
    process = None
    confirmed = False
    try:
        process = subprocess.Popen(["bash", "scripts/android_play_store_build.sh"], cwd=root, env=environment,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        marker.write_text(str(process.pid) + "\n")
        code = process.wait(timeout=BUILD_TIMEOUT_SECONDS)
        require(not owned_group_exists(process.pid), "ANDROID_BUILDER_DESCENDANTS_SURVIVED")
        confirmed = True
        return code
    except BaseException:
        if process is not None:
            stop_owned_builder_group(process)
            confirmed = True
        raise
    finally:
        if confirmed:
            marker.unlink(missing_ok=True)


def cleanup():
    root, _, _, private = paths()
    if private.is_symlink():
        raise Blocked("ANDROID_PRIVATE_PATH_SYMLINK")
    if private.exists():
        require((private / "owned-stage").is_file()
                and (private / "owned-stage").read_text() == "collect-android-candidate-v1\n",
                "ANDROID_PRIVATE_STAGE_NOT_OWNED")
        # A separate always-cleanup invocation must never signal a stale PGID.
        # Only the owning Popen lifecycle removes this marker after reap and
        # group absence; any unresolved marker retains the whole private stage.
        marker = private / "owned-builder-group"
        require(not marker.exists() and not marker.is_symlink(), "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED")
        if (private / "google-services-created").is_file():
            (root / "android/app/google-services.json").unlink(missing_ok=True)
        shutil.rmtree(private)


def build():
    root, pristine, output, private = paths()
    record, profile, provider_raw = configuration_and_approval(root)
    source_check(root, pristine, record)
    policy = environment_policy()
    require(not private.exists() and not private.is_symlink(), "ANDROID_NEW_PRIVATE_PATH_REQUIRED")
    require(output.is_dir() and not output.is_symlink(), "ANDROID_PREPARED_OUTPUT_REQUIRED")
    google_file = root / "android/app/google-services.json"
    require(not google_file.exists() and not google_file.is_symlink(), "ANDROID_PROVIDER_PATH_ALREADY_EXISTS")
    properties = root / "android/key.properties"
    require(not properties.exists() and not properties.is_symlink(), "ANDROID_UNEXPECTED_SIGNING_PROPERTIES")
    private.mkdir(mode=0o700)
    try:
        (private / "owned-stage").write_text("collect-android-candidate-v1\n")
        encoded = os.environ.get("KEYSTORE_BASE64", "")
        require(0 < len(encoded) < 48 * 1024**2, "ANDROID_KEYSTORE_INPUT_REQUIRED")
        key = base64.b64decode("".join(encoded.split()), validate=True)
        require(0 < len(key) < 32 * 1024**2, "ANDROID_KEYSTORE_INPUT_BOUND")
        key_file = private / "upload.keystore"
        with key_file.open("xb") as stream:
            key_file.chmod(0o600)
            stream.write(key)
        child = dict(os.environ)
        child.pop("KEYSTORE_BASE64", None)
        child.pop("GH_TOKEN", None)
        child.pop("GITHUB_TOKEN", None)
        child["COOL_ANDROID_STORE_FILE"] = str(key_file)
        for secret, name in (("KEY_ALIAS", "COOL_ANDROID_KEY_ALIAS"), ("KEY_PASSWORD", "COOL_ANDROID_KEY_PASSWORD"),
                             ("STORE_PASSWORD", "COOL_ANDROID_STORE_PASSWORD")):
            require(bool(child.get(secret)), "ANDROID_SIGNING_FIELD_REQUIRED")
            child[name] = child.pop(secret)
        child["COOL_EXPECTED_UPLOAD_SIGNING_SHA256"] = record["upload_certificate_sha256"]
        child["COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY"] = "false"
        child["GRADLE_OPTS"] = "-Dorg.gradle.daemon=false -Dorg.gradle.caching=false -Dorg.gradle.configuration-cache=false"
        (private / "google-services-created").write_text("owned\n")
        with google_file.open("xb") as stream:
            google_file.chmod(0o600)
            stream.write(provider_raw)
        # Build diagnostics can contain Gradle alias/error text. Keep them private
        # and transient, never echo or archive them with the candidate.
        with (private / "build.log").open("xb") as log:
            code = run_builder(root, child, log, private)
        require(code == 0, "ANDROID_CANDIDATE_BUILD_FAILED")
        require(not google_file.is_symlink() and sha(google_file.read_bytes()) == record["google_services_sha256"],
                "ANDROID_PUBLIC_PROVIDER_CONFIG_CHANGED")
        current_record, current_profile, current_provider = configuration_and_approval(root)
        require(current_record == record and current_profile == profile and current_provider == provider_raw,
                "ANDROID_APPROVED_INPUTS_CHANGED")
        policy = environment_policy()
        source_check(root, pristine, record)
        aab = root / AAB
        apk = root / APK
        require(aab.is_file() and not aab.is_symlink(), "ANDROID_AAB_REQUIRED")
        require(apk.is_file() and not apk.is_symlink(), "ANDROID_APK_REQUIRED")
        before = sha(aab.read_bytes())
        apk_before = sha(apk.read_bytes())
        verifier_environment = {key: value for key, value in os.environ.items()
                                if key not in {"KEYSTORE_BASE64", "KEY_ALIAS", "KEY_PASSWORD", "STORE_PASSWORD",
                                               "GH_TOKEN", "GITHUB_TOKEN", "REVIEWED_ANDROID_APPROVAL_RECORD"}
                                and not key.startswith("COOL_ANDROID_")}
        inspection = parsed(command(["java", "scripts/qa/VerifySignedBundle.java", str(aab), record["upload_certificate_sha256"]],
                                    cwd=root, env=verifier_environment))
        require(inspection.get("status") == "pass" and inspection.get("signer_sha256") == record["upload_certificate_sha256"]
                and inspection.get("verified_payload_entries", 0) > 0, "ANDROID_SIGNED_AAB_NOT_VERIFIED")
        version = record["version"] + "+" + record["build_number"]
        build_manifest = parsed((root / (".cache/android_play_store_build/" + version + ".json")).read_bytes())
        native = parsed((root / ".cache/native-build/android.json").read_bytes())
        metadata = native["artifact_metadata"]["aab"]
        require(build_manifest.get("backend") == "supabase" and build_manifest.get("mobile_evidence_mode") is False
                and build_manifest.get("artifact_version") == version
                and build_manifest.get("public_runtime_config_sha256") == record["public_runtime_config_sha256"]
                and build_manifest["artifacts"]["aab"]["sha256"] == before
                and native["artifacts"]["aab"] == before
                and native.get("schema_version") == 3 and native.get("platform") == "android"
                and native.get("version") == version and native.get("source_file_count", 0) > 0
                and metadata["artifact_sha256"] == before and metadata.get("status") == "pass"
                and metadata.get("actual") == {"package": PACKAGE, "version_name": record["version"], "version_code": int(record["build_number"])}
                and native.get("release_approval") is False, "ANDROID_ARTIFACT_PROVENANCE_WRONG")
        apk_metadata = native["artifact_metadata"]["apk"]
        require(build_manifest["artifacts"]["apk"]["sha256"] == apk_before
                and native["artifacts"]["apk"] == apk_before
                and apk_metadata.get("artifact_sha256") == apk_before and apk_metadata.get("status") == "pass"
                and apk_metadata.get("actual") == {"package": PACKAGE, "version_name": record["version"],
                                                    "version_code": int(record["build_number"])},
                "ANDROID_APK_PROVENANCE_WRONG")
        require(sha(aab.read_bytes()) == before, "ANDROID_AAB_CHANGED_DURING_INSPECTION")
        require(sha(apk.read_bytes()) == apk_before, "ANDROID_APK_CHANGED_DURING_INSPECTION")
        source_check(root, pristine, record)
        inspection.update({"aab_sha256": before, "apk_sha256": apk_before, "source_commit": record["source_commit"],
                           "source_manifest_sha256": record["source_manifest_sha256"],
                           "public_runtime_config_sha256": record["public_runtime_config_sha256"],
                           "google_services_sha256": record["google_services_sha256"],
                           "play_integrity_cloud_project_number": record["play_integrity_cloud_project_number"],
                           "application_id": PACKAGE, "version": version, "publication": False})
        shutil.copyfile(aab, output / "Collect.aab")
        require(sha((output / "Collect.aab").read_bytes()) == before, "ANDROID_AAB_COPY_CHANGED")
        shutil.copyfile(apk, output / "Collect.apk")
        require(sha((output / "Collect.apk").read_bytes()) == apk_before, "ANDROID_APK_COPY_CHANGED")
        shutil.copyfile(pristine / source_export.MANIFEST, output / "source-manifest.json")
        for name, value in {"inspection.json": inspection, "public-profile.json": profile,
                            "build-manifest.json": build_manifest, "native-build.json": native,
                            "environment-policy.json": policy}.items():
            (output / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
        source_check(root, pristine, record)
    finally:
        cleanup()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("policy", "prepare", "build", "cleanup"))
    args = parser.parse_args()
    try:
        {"policy": policy_preflight, "prepare": prepare, "build": build, "cleanup": cleanup}[args.operation]()
        print(json.dumps({"status": "pass", "operation": args.operation, "publication": False}))
        return 0
    except Blocked as error:
        code = str(error)
        reason = code if re.fullmatch(r"ANDROID_[A-Z_]+", code) else "ANDROID_CANDIDATE_BLOCKED"
        print(json.dumps({"status": "blocked", "operation": args.operation, "reason": reason, "publication": False}))
        return 1
    except (source_export.ReleaseError, ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.SubprocessError):
        # Never print exceptions, subprocess output, aliases, keys or approval text.
        print(json.dumps({"status": "blocked", "operation": args.operation, "publication": False}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
