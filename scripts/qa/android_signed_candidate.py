#!/usr/bin/env python3
"""One protected Android candidate build; never publishes or creates approval."""
from __future__ import annotations

import argparse
import base64
from contextlib import ExitStack
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import time
from xml.parsers import expat

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
BUNDLETOOL_SHA256 = "a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
BUNDLETOOL_MAX_BYTES = 64 * 1024**2
JAVA_LAUNCHER_MAX_BYTES = 64 * 1024**2
AAB_MAX_BYTES = 4 * 1024**3
BUNDLETOOL_TIMEOUT_SECONDS = 120
BUNDLETOOL_STDOUT_MAX = 2 * 1024**2
BUNDLETOOL_STDERR_MAX = 64 * 1024
ANDROID_XML = "http://schemas.android.com/apk/res/android}"


class Blocked(ValueError):
    pass


# Only internally defined, nonsecret identifiers may be surfaced in composite
# diagnostics; exception text and captured tool output are never emitted.
SAFE_REASONS = frozenset("""
ANDROID_AAB_CHANGED_DURING_INSPECTION ANDROID_AAB_COPY_CHANGED ANDROID_AAB_INSPECTION_SPACE_REQUIRED
ANDROID_AAB_MANIFEST_XML_BOUND ANDROID_AAB_MANIFEST_XML_WRONG ANDROID_AAB_REQUIRED
ANDROID_AAB_SDK_DECLARATION_WRONG ANDROID_AAB_SDK_TOO_LOW_OR_INVALID ANDROID_APK_CHANGED_DURING_INSPECTION
ANDROID_APK_COPY_CHANGED ANDROID_APK_PROVENANCE_WRONG ANDROID_APK_REQUIRED ANDROID_APPROVAL_DIGEST_WRONG
ANDROID_APPROVAL_OBJECT_REQUIRED ANDROID_APPROVAL_SCOPE_OR_INPUT_WRONG ANDROID_APPROVAL_TIME_WRONG
ANDROID_APPROVED_INPUTS_CHANGED ANDROID_APPROVED_UPLOAD_CERT_REQUIRED ANDROID_ARTIFACT_PROVENANCE_WRONG
ANDROID_BUILDER_DESCENDANTS_SURVIVED ANDROID_BUILDER_GROUP_STATE_UNKNOWN ANDROID_BUILDER_GROUP_TEARDOWN_UNCONFIRMED
ANDROID_BUILDER_INTERRUPTED ANDROID_BUILDER_LIFECYCLE_UNRESOLVED ANDROID_BUILDER_TIMEOUT
ANDROID_BUNDLETOOL_CHANGED_DURING_INSPECTION ANDROID_BUNDLETOOL_DIGEST_WRONG ANDROID_BUNDLETOOL_FAILED
ANDROID_BUNDLETOOL_INTERRUPTED ANDROID_BUNDLETOOL_IO_FAILED ANDROID_BUNDLETOOL_LAUNCH_FAILED
ANDROID_BUNDLETOOL_OUTPUT_BOUND ANDROID_BUNDLETOOL_REQUIRED ANDROID_BUNDLETOOL_TIMEOUT
ANDROID_CANDIDATE_BLOCKED ANDROID_CANDIDATE_BUILD_FAILED ANDROID_CHECKOUT_COMMIT_WRONG ANDROID_CLEAN_CHECKOUT_REQUIRED
ANDROID_CLEANUP_FAILED ANDROID_DUPLICATE_JSON_KEY ANDROID_EXTERNAL_REVIEW_REQUIRED ANDROID_INSPECTION_INPUT_BOUND
ANDROID_INSPECTION_INPUT_CHANGED ANDROID_INSPECTION_INPUT_REQUIRED ANDROID_INSPECTION_PLATFORM_UNSUPPORTED
ANDROID_INSPECTOR_KIND_WRONG ANDROID_JAVA_LAUNCHER_CHANGED ANDROID_JAVA_REQUIRED ANDROID_KEYSTORE_INPUT_BOUND
ANDROID_KEYSTORE_INPUT_REQUIRED ANDROID_MAIN_IDENTITY_REQUIRED ANDROID_NEW_OUTPUT_REQUIRED ANDROID_NEW_PRIVATE_PATH_REQUIRED
ANDROID_OPERATION_ABORTED ANDROID_OPERATION_INTERRUPTED ANDROID_OPERATION_TIMEOUT ANDROID_PLAY_INTEGRITY_PROJECT_REQUIRED ANDROID_PREPARED_OUTPUT_REQUIRED
ANDROID_PRIVATE_PATH_SYMLINK ANDROID_PRIVATE_STAGE_NOT_OWNED ANDROID_PROCESS_FINALIZATION_FAILED ANDROID_PROCESS_SETTLEMENT_FAILED ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED
ANDROID_PROTECTED_REVIEW_POLICY_REQUIRED ANDROID_PROVIDER_PATH_ALREADY_EXISTS ANDROID_PUBLIC_PROVIDER_CONFIG_CHANGED
ANDROID_PUBLIC_PROVIDER_CONFIG_REQUIRED ANDROID_PUBLIC_PROVIDER_PACKAGE_WRONG ANDROID_REVIEWED_SOURCE_CHANGED
ANDROID_REVIEWED_SOURCE_WRONG ANDROID_SIGNATURE_INSPECTOR_FAILED ANDROID_SIGNATURE_INSPECTOR_INTERRUPTED
ANDROID_SIGNATURE_INSPECTOR_INVALID_OUTPUT ANDROID_SIGNATURE_INSPECTOR_IO_FAILED ANDROID_SIGNATURE_INSPECTOR_LAUNCH_FAILED ANDROID_SIGNATURE_INSPECTOR_OUTPUT_BOUND
ANDROID_SIGNATURE_INSPECTOR_TIMEOUT ANDROID_SIGNED_AAB_NOT_VERIFIED ANDROID_SIGNING_FIELD_REQUIRED
ANDROID_SOURCE_DIGEST_REQUIRED ANDROID_TOOL_FAILED ANDROID_TOOL_OUTPUT_BOUND ANDROID_UNEXPECTED_SIGNING_PROPERTIES
ANDROID_VERSION_REQUIRED
""".split())


def safe_reason(error, fallback="ANDROID_CANDIDATE_BLOCKED"):
    if isinstance(error, DiagnosticFailure):
        code = error.primary_reason
        return code if isinstance(code, str) and code in SAFE_REASONS else fallback
    annotated = getattr(error, "_collect_reason", None)
    if isinstance(annotated, str) and annotated in SAFE_REASONS:
        return annotated
    if isinstance(error, Blocked):
        code = str(error)
        if code in SAFE_REASONS:
            return code
    if isinstance(error, KeyboardInterrupt):
        return "ANDROID_OPERATION_INTERRUPTED"
    if isinstance(error, subprocess.TimeoutExpired):
        return "ANDROID_OPERATION_TIMEOUT"
    if isinstance(error, SystemExit):
        return "ANDROID_OPERATION_ABORTED"
    return fallback


class DiagnosticFailure(Blocked):
    """Preserve safe primary, settlement and cleanup outcomes separately."""
    def __init__(self, original, *, settlement=None, finalization=(), cleanup=None):
        self.primary_reason = safe_reason(original)
        self.settlement_reasons = list(original.settlement_reasons if isinstance(original, DiagnosticFailure) else
                                       (["ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"] if
                                        getattr(original, "_collect_settlement_unconfirmed", False) is True else []))
        self.finalization_failures = list(original.finalization_failures if isinstance(original, DiagnosticFailure) else ())
        self.cleanup_reason = (original.cleanup_reason if isinstance(original, DiagnosticFailure) else None)
        if settlement is not None:
            self.settlement_reasons.append(safe_reason(settlement, "ANDROID_PROCESS_SETTLEMENT_FAILED"))
        for step, error in finalization:
            if step in {"selector_close", "stdout_close", "stderr_close", "marker_release"}:
                self.finalization_failures.append({"step": step, "reason": safe_reason(error, "ANDROID_PROCESS_FINALIZATION_FAILED")})
        if cleanup is not None:
            self.cleanup_reason = safe_reason(cleanup, "ANDROID_CLEANUP_FAILED")
        super().__init__(self.primary_reason)

    @property
    def settlement_reason(self):
        return self.settlement_reasons[0] if self.settlement_reasons else None


def mark_unconfirmed(error):
    """Keep the original exception type when attaching a fixed outcome."""
    if isinstance(error, DiagnosticFailure):
        return DiagnosticFailure(error, settlement=Blocked("ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"))
    try:
        error._collect_settlement_unconfirmed = True
        return error
    except (AttributeError, TypeError):
        return DiagnosticFailure(error, settlement=Blocked("ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"))


def blocked_result(operation, error):
    result = {"status": "blocked", "operation": operation, "reason": safe_reason(error), "publication": False}
    if isinstance(error, DiagnosticFailure):
        reasons = [value if isinstance(value, str) and value in SAFE_REASONS else "ANDROID_PROCESS_SETTLEMENT_FAILED"
                   for value in error.settlement_reasons]
        finalization = []
        for value in error.finalization_failures:
            step = value.get("step") if isinstance(value, dict) else None
            code = value.get("reason") if isinstance(value, dict) else None
            finalization.append({"step": step if isinstance(step, str) and step in {"selector_close", "stdout_close", "stderr_close", "marker_release"} else "unknown",
                                 "reason": code if isinstance(code, str) and code in SAFE_REASONS else "ANDROID_PROCESS_FINALIZATION_FAILED"})
        cleanup_reason = error.cleanup_reason
        if cleanup_reason is not None and (not isinstance(cleanup_reason, str) or cleanup_reason not in SAFE_REASONS):
            cleanup_reason = "ANDROID_CLEANUP_FAILED"
    else:
        reasons = (["ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"] if
                   getattr(error, "_collect_settlement_unconfirmed", False) is True else [])
        finalization = []
        cleanup_reason = None
    if reasons:
        result["process_settlement"] = {"status": "blocked", "reason": reasons[0]}
        if len(reasons) > 1:
            result["process_settlement"]["additional_reasons"] = reasons[1:]
    if finalization:
        result["finalization"] = {"status": "blocked", "failures": finalization}
    if cleanup_reason is not None:
        result["cleanup"] = {"status": "blocked", "reason": cleanup_reason}
    return result


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


def regular_file_digest(path, maximum, destination=None):
    """Hash a bounded regular file, optionally making a private exact snapshot."""
    require(hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_NONBLOCK"), "ANDROID_INSPECTION_PLATFORM_UNSUPPORTED")
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        with ExitStack() as stack:
            source = stack.enter_context(os.fdopen(os.open(path, flags), "rb"))
            original = os.fstat(source.fileno())
            require(stat.S_ISREG(original.st_mode) and 0 < original.st_size <= maximum,
                    "ANDROID_INSPECTION_INPUT_REQUIRED")
            identity = lambda entry: (entry.st_dev, entry.st_ino, entry.st_mode, entry.st_size,
                                      entry.st_mtime_ns, entry.st_ctime_ns)
            require(identity(os.lstat(path)) == identity(original), "ANDROID_INSPECTION_INPUT_CHANGED")
            target = None
            if destination is not None:
                out_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
                target = stack.enter_context(os.fdopen(os.open(destination, out_flags, 0o600), "wb"))
            digest = hashlib.sha256()
            total = 0
            while True:
                chunk = source.read(min(1024 * 1024, maximum - total + 1))
                if not chunk:
                    break
                total += len(chunk)
                require(total <= maximum, "ANDROID_INSPECTION_INPUT_BOUND")
                digest.update(chunk)
                if target is not None:
                    target.write(chunk)
            require(total == original.st_size and identity(os.fstat(source.fileno())) == identity(original)
                    and identity(os.lstat(path)) == identity(original), "ANDROID_INSPECTION_INPUT_CHANGED")
            return digest.hexdigest()
    except OSError as error:
        raise Blocked("ANDROID_INSPECTION_INPUT_REQUIRED") from error


def bundletool_input():
    supplied = os.environ.get("COLLECT_BUNDLETOOL_JAR", "")
    require(bool(supplied) and Path(supplied).is_absolute(), "ANDROID_BUNDLETOOL_REQUIRED")
    jar = Path(supplied)
    require(regular_file_digest(jar, BUNDLETOOL_MAX_BYTES) == BUNDLETOOL_SHA256,
            "ANDROID_BUNDLETOOL_DIGEST_WRONG")
    java = shutil.which("java", path=os.environ.get("PATH", ""))
    require(bool(java), "ANDROID_JAVA_REQUIRED")
    launcher = Path(java).resolve()
    return jar, str(launcher), regular_file_digest(launcher, JAVA_LAUNCHER_MAX_BYTES)


def sdk_from_manifest(data):
    """Read only the Android SDK attributes from bounded UTF-8 bundletool XML."""
    try:
        require(0 < len(data) <= BUNDLETOOL_STDOUT_MAX, "ANDROID_AAB_MANIFEST_XML_BOUND")
        text = data.decode("utf-8")
        require("\x00" not in text, "ANDROID_AAB_MANIFEST_XML_WRONG")
        parser = expat.ParserCreate(namespace_separator="}")
        state = {"depth": 0, "elements": 0, "sdk_elements": 0, "compile": None, "target": None}

        def start(name, attributes):
            state["elements"] += 1
            require(state["elements"] <= 20000 and state["depth"] < 256 and len(attributes) <= 128,
                    "ANDROID_AAB_MANIFEST_XML_BOUND")
            if state["depth"] == 0:
                require(name == "manifest", "ANDROID_AAB_MANIFEST_XML_WRONG")
                state["compile"] = attributes.get(ANDROID_XML + "compileSdkVersion")
            if name == "uses-sdk":
                state["sdk_elements"] += 1
                require(state["depth"] == 1 and state["sdk_elements"] == 1,
                        "ANDROID_AAB_SDK_DECLARATION_WRONG")
                state["target"] = attributes.get(ANDROID_XML + "targetSdkVersion")
            state["depth"] += 1

        def end(_name):
            state["depth"] -= 1

        def reject_declaration(*_args):
            raise Blocked("ANDROID_AAB_MANIFEST_XML_WRONG")

        parser.StartElementHandler = start
        parser.EndElementHandler = end
        parser.StartDoctypeDeclHandler = reject_declaration
        parser.EntityDeclHandler = reject_declaration
        parser.ExternalEntityRefHandler = reject_declaration
        parser.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_NEVER)
        parser.Parse(text, True)
        require(state["sdk_elements"] == 1, "ANDROID_AAB_SDK_DECLARATION_WRONG")
        values = (state["compile"], state["target"])
        require(all(isinstance(value, str) and re.fullmatch(r"[0-9]{1,10}", value)
                    and 36 <= int(value) <= 2**31 - 1 for value in values), "ANDROID_AAB_SDK_TOO_LOW_OR_INVALID")
        return {"compile_sdk": int(values[0]), "target_sdk": int(values[1])}
    except (UnicodeDecodeError, expat.ExpatError) as error:
        raise Blocked("ANDROID_AAB_MANIFEST_XML_WRONG") from error


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
    bundletool_input()
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


def settle_bounded_tool(process):
    """Retain uncertainty for the builder or inspector if ownership cannot be proved."""
    if process is None:
        return False
    # Once reaped, a numeric group ID may no longer identify our process. Do
    # not signal that group; only a positive absence observation permits cleanup.
    if process.returncode is not None or process.poll() is not None:
        return not owned_group_exists(process.pid)
    # The live, unreaped leader still holds its PID. Make one bounded stop
    # attempt before reaping; never signal this numeric ID again after reaping.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError as error:
        raise Blocked("ANDROID_BUILDER_GROUP_TEARDOWN_UNCONFIRMED") from error
    return wait_for_owned_group_exit(process, BUILD_KILL_GRACE_SECONDS)


def run_bounded_tool(args, cwd, private, *, purpose="bundletool"):
    """Capture a tool's output without buffering past the limits or leaking diagnostics."""
    labels = {
        "bundletool": {"timeout": "ANDROID_BUNDLETOOL_TIMEOUT", "output": "ANDROID_BUNDLETOOL_OUTPUT_BOUND",
                       "failed": "ANDROID_BUNDLETOOL_FAILED", "launch": "ANDROID_BUNDLETOOL_LAUNCH_FAILED",
                       "io": "ANDROID_BUNDLETOOL_IO_FAILED", "interrupted": "ANDROID_BUNDLETOOL_INTERRUPTED"},
        "signature": {"timeout": "ANDROID_SIGNATURE_INSPECTOR_TIMEOUT", "output": "ANDROID_SIGNATURE_INSPECTOR_OUTPUT_BOUND",
                      "failed": "ANDROID_SIGNATURE_INSPECTOR_FAILED", "launch": "ANDROID_SIGNATURE_INSPECTOR_LAUNCH_FAILED",
                      "io": "ANDROID_SIGNATURE_INSPECTOR_IO_FAILED", "interrupted": "ANDROID_SIGNATURE_INSPECTOR_INTERRUPTED"},
    }
    require(purpose in labels, "ANDROID_INSPECTOR_KIND_WRONG")
    reason = labels[purpose]
    marker = private / "owned-builder-group"
    require(not marker.exists() and not marker.is_symlink(), "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED")
    marker.write_text("starting\n")
    process = None
    confirmed = False
    pending_error = None
    selector = None
    output = {"stdout": bytearray(), "stderr": bytearray()}
    limits = {"stdout": BUNDLETOOL_STDOUT_MAX, "stderr": BUNDLETOOL_STDERR_MAX}
    try:
        try:
            selector = selectors.DefaultSelector()
        except OSError as error:
            raise Blocked(reason["io"]) from error
        try:
            process = subprocess.Popen(args, cwd=cwd, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
                                       stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True)
        except OSError as error:
            raise Blocked(reason["launch"]) from error
        marker.write_text(str(process.pid) + "\n")
        for label in ("stdout", "stderr"):
            stream = getattr(process, label)
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, label)
        deadline = time.monotonic() + BUNDLETOOL_TIMEOUT_SECONDS
        while selector.get_map():
            remaining = deadline - time.monotonic()
            require(remaining > 0, reason["timeout"])
            events = selector.select(remaining)
            require(bool(events), reason["timeout"])
            for key, _ in events:
                chunk = os.read(key.fileobj.fileno(), 64 * 1024)
                if not chunk:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                label = key.data
                require(len(output[label]) + len(chunk) <= limits[label], reason["output"])
                output[label].extend(chunk)
        remaining = deadline - time.monotonic()
        require(remaining > 0, reason["timeout"])
        try:
            code = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired as error:
            raise Blocked(reason["timeout"]) from error
        require(code == 0, reason["failed"])
        require(not owned_group_exists(process.pid), "ANDROID_BUILDER_DESCENDANTS_SURVIVED")
        confirmed = True
        return bytes(output["stdout"])
    except BaseException as original:
        if isinstance(original, KeyboardInterrupt):
            original._collect_reason = reason["interrupted"]
        mapped = Blocked(reason["io"]) if isinstance(original, OSError) else original
        try:
            confirmed = settle_bounded_tool(process)
        except BaseException as settlement:
            pending_error = DiagnosticFailure(mapped, settlement=settlement)
            raise pending_error from None
        if confirmed is not True:
            confirmed = False
            mapped = mark_unconfirmed(mapped)
        pending_error = mapped
        if mapped is not original:
            raise mapped from original
        raise
    finally:
        finalization = []
        closeables = [("selector_close", selector)] if selector is not None else []
        if process is not None:
            closeables.extend((name + "_close", getattr(process, name)) for name in ("stdout", "stderr")
                              if getattr(process, name) is not None)
        for step, closeable in closeables:
            try:
                closeable.close()
            except BaseException as error:
                finalization.append((step, error))
        if confirmed and not finalization:
            try:
                marker.unlink(missing_ok=True)
            except BaseException as error:
                finalization.append(("marker_release", error))
        if finalization:
            original = pending_error if pending_error is not None else Blocked("ANDROID_PROCESS_FINALIZATION_FAILED")
            raise DiagnosticFailure(original, finalization=finalization) from None


def inspect_aab_sdk(aab, aab_snapshot, aab_digest, private, root, jar, java, java_digest):
    """Inspect the same private AAB snapshot used for signature and export."""
    require(shutil.disk_usage(private).free >= os.stat(jar).st_size + 64 * 1024**2,
            "ANDROID_AAB_INSPECTION_SPACE_REQUIRED")
    jar_snapshot = private / "manifest-bundletool.jar"
    require(regular_file_digest(aab_snapshot, AAB_MAX_BYTES) == aab_digest
            and regular_file_digest(aab, AAB_MAX_BYTES) == aab_digest,
            "ANDROID_AAB_CHANGED_DURING_INSPECTION")
    require(regular_file_digest(jar, BUNDLETOOL_MAX_BYTES, jar_snapshot) == BUNDLETOOL_SHA256,
            "ANDROID_BUNDLETOOL_DIGEST_WRONG")
    require(regular_file_digest(Path(java), JAVA_LAUNCHER_MAX_BYTES) == java_digest,
            "ANDROID_JAVA_LAUNCHER_CHANGED")
    result = run_bounded_tool([java, "-XX:+PerfDisableSharedMem", "-Djava.awt.headless=true", "-jar",
                               str(jar_snapshot), "dump", "manifest", "--bundle=" + str(aab_snapshot),
                               "--module=base"], root, private)
    require(regular_file_digest(aab_snapshot, AAB_MAX_BYTES) == aab_digest
            and regular_file_digest(aab, AAB_MAX_BYTES) == aab_digest,
            "ANDROID_AAB_CHANGED_DURING_INSPECTION")
    require(regular_file_digest(jar_snapshot, BUNDLETOOL_MAX_BYTES) == BUNDLETOOL_SHA256
            and regular_file_digest(jar, BUNDLETOOL_MAX_BYTES) == BUNDLETOOL_SHA256,
            "ANDROID_BUNDLETOOL_CHANGED_DURING_INSPECTION")
    require(regular_file_digest(Path(java), JAVA_LAUNCHER_MAX_BYTES) == java_digest,
            "ANDROID_JAVA_LAUNCHER_CHANGED")
    return {"module": "base", "aab_sha256": aab_digest, "bundletool_sha256": BUNDLETOOL_SHA256,
            "java_launcher_sha256": java_digest,
            **sdk_from_manifest(result)}


def run_builder(root, environment, log, private):
    marker = private / "owned-builder-group"
    # Unknown launch state is retained rather than allowing later cleanup to
    # delete files that an unconfirmed builder could still hold open.
    marker.write_text("starting\n")
    process = None
    confirmed = False
    pending_error = None
    try:
        process = subprocess.Popen(["bash", "scripts/android_play_store_build.sh"], cwd=root, env=environment,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        marker.write_text(str(process.pid) + "\n")
        code = process.wait(timeout=BUILD_TIMEOUT_SECONDS)
        require(not owned_group_exists(process.pid), "ANDROID_BUILDER_DESCENDANTS_SURVIVED")
        confirmed = True
        return code
    except BaseException as original:
        if isinstance(original, KeyboardInterrupt):
            original._collect_reason = "ANDROID_BUILDER_INTERRUPTED"
        elif isinstance(original, subprocess.TimeoutExpired):
            original._collect_reason = "ANDROID_BUILDER_TIMEOUT"
        try:
            confirmed = settle_bounded_tool(process)
        except BaseException as settlement:
            pending_error = DiagnosticFailure(original, settlement=settlement)
            raise pending_error from None
        if confirmed is not True:
            confirmed = False
            original = mark_unconfirmed(original)
        pending_error = original
        raise original
    finally:
        if confirmed:
            try:
                marker.unlink(missing_ok=True)
            except BaseException as error:
                original = pending_error if pending_error is not None else Blocked("ANDROID_PROCESS_FINALIZATION_FAILED")
                raise DiagnosticFailure(original, finalization=(("marker_release", error),)) from None


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
    jar, java, java_digest = bundletool_input()
    require(not private.exists() and not private.is_symlink(), "ANDROID_NEW_PRIVATE_PATH_REQUIRED")
    require(output.is_dir() and not output.is_symlink(), "ANDROID_PREPARED_OUTPUT_REQUIRED")
    google_file = root / "android/app/google-services.json"
    require(not google_file.exists() and not google_file.is_symlink(), "ANDROID_PROVIDER_PATH_ALREADY_EXISTS")
    properties = root / "android/key.properties"
    require(not properties.exists() and not properties.is_symlink(), "ANDROID_UNEXPECTED_SIGNING_PROPERTIES")
    private.mkdir(mode=0o700)
    primary_error = None
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
        # The builder has closed its owned group. Remove transient signing and
        # diagnostic bytes before starting either artifact inspector.
        key_file.unlink()
        (private / "build.log").unlink()
        del child, key, encoded
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
        require(shutil.disk_usage(private).free >= os.stat(aab).st_size + os.stat(jar).st_size + 64 * 1024**2,
                "ANDROID_AAB_INSPECTION_SPACE_REQUIRED")
        aab_snapshot = private / "manifest-candidate.aab"
        before = regular_file_digest(aab, AAB_MAX_BYTES, aab_snapshot)
        require(regular_file_digest(aab_snapshot, AAB_MAX_BYTES) == before,
                "ANDROID_AAB_CHANGED_DURING_INSPECTION")
        apk_before = sha(apk.read_bytes())
        require(regular_file_digest(Path(java), JAVA_LAUNCHER_MAX_BYTES) == java_digest,
                "ANDROID_JAVA_LAUNCHER_CHANGED")
        signature_output = run_bounded_tool([java, "-XX:+PerfDisableSharedMem", "-Djava.awt.headless=true",
                                              "scripts/qa/VerifySignedBundle.java", str(aab_snapshot),
                                              record["upload_certificate_sha256"]], root, private, purpose="signature")
        try:
            inspection = parsed(signature_output)
        except (ValueError, UnicodeError, TypeError) as error:
            raise Blocked("ANDROID_SIGNATURE_INSPECTOR_INVALID_OUTPUT") from error
        require(isinstance(inspection, dict), "ANDROID_SIGNATURE_INSPECTOR_INVALID_OUTPUT")
        require(inspection.get("status") == "pass" and inspection.get("signer_sha256") == record["upload_certificate_sha256"]
                and inspection.get("verified_payload_entries", 0) > 0, "ANDROID_SIGNED_AAB_NOT_VERIFIED")
        require(regular_file_digest(aab_snapshot, AAB_MAX_BYTES) == before
                and regular_file_digest(aab, AAB_MAX_BYTES) == before,
                "ANDROID_AAB_CHANGED_DURING_INSPECTION")
        require(regular_file_digest(Path(java), JAVA_LAUNCHER_MAX_BYTES) == java_digest,
                "ANDROID_JAVA_LAUNCHER_CHANGED")
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
        sdk_inspection = inspect_aab_sdk(aab, aab_snapshot, before, private, root, jar, java, java_digest)
        require(regular_file_digest(aab, AAB_MAX_BYTES) == before, "ANDROID_AAB_CHANGED_DURING_INSPECTION")
        require(regular_file_digest(aab_snapshot, AAB_MAX_BYTES) == before, "ANDROID_AAB_CHANGED_DURING_INSPECTION")
        require(sha(apk.read_bytes()) == apk_before, "ANDROID_APK_CHANGED_DURING_INSPECTION")
        source_check(root, pristine, record)
        inspection.update({"aab_sha256": before, "apk_sha256": apk_before, "aab_sdk": sdk_inspection,
                           "source_commit": record["source_commit"],
                           "source_manifest_sha256": record["source_manifest_sha256"],
                           "public_runtime_config_sha256": record["public_runtime_config_sha256"],
                           "google_services_sha256": record["google_services_sha256"],
                           "play_integrity_cloud_project_number": record["play_integrity_cloud_project_number"],
                           "application_id": PACKAGE, "version": version, "publication": False})
        shutil.copyfile(aab_snapshot, output / "Collect.aab")
        require(regular_file_digest(output / "Collect.aab", AAB_MAX_BYTES) == before
                and regular_file_digest(aab_snapshot, AAB_MAX_BYTES) == before
                and regular_file_digest(aab, AAB_MAX_BYTES) == before, "ANDROID_AAB_COPY_CHANGED")
        shutil.copyfile(apk, output / "Collect.apk")
        require(sha((output / "Collect.apk").read_bytes()) == apk_before, "ANDROID_APK_COPY_CHANGED")
        shutil.copyfile(pristine / source_export.MANIFEST, output / "source-manifest.json")
        for name, value in {"inspection.json": inspection, "public-profile.json": profile,
                            "build-manifest.json": build_manifest, "native-build.json": native,
                            "environment-policy.json": policy}.items():
            (output / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
        source_check(root, pristine, record)
    except BaseException as error:
        primary_error = error
        raise
    finally:
        try:
            cleanup()
        except BaseException as error:
            if primary_error is not None:
                raise DiagnosticFailure(primary_error, cleanup=error) from None
            raise DiagnosticFailure(Blocked("ANDROID_CLEANUP_FAILED"), cleanup=error) from None


def cleanup_operation():
    try:
        cleanup()
    except BaseException as error:
        raise DiagnosticFailure(Blocked("ANDROID_CLEANUP_FAILED"), cleanup=error) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("policy", "prepare", "build", "cleanup"))
    args = parser.parse_args()
    try:
        {"policy": policy_preflight, "prepare": prepare, "build": build, "cleanup": cleanup_operation}[args.operation]()
        print(json.dumps({"status": "pass", "operation": args.operation, "publication": False}))
        return 0
    except (Blocked, KeyboardInterrupt, SystemExit, subprocess.TimeoutExpired) as error:
        print(json.dumps(blocked_result(args.operation, error)))
        return 1
    except Exception:
        # Never print exceptions, subprocess output, aliases, keys or approval text.
        print(json.dumps({"status": "blocked", "operation": args.operation, "publication": False}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
