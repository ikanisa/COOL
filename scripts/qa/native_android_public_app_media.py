#!/usr/bin/env python3
"""Two-phase, isolated native Android media capture; never a release builder.

prepare builds/inspects only. capture requires the exact separately reviewed APK
hash, refuses an existing fixture package, and reuses the integration-test driver.
Neither phase is called by website generation or publication.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("native_media_publication", ROOT / "scripts/assets/publish_public_app_media.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
PACKAGE = P.ANDROID_PACKAGE
TARGET = "tool/native_public_app_media_capture.dart"
DRIVER = "test_driver/integration_test.dart"
PROTECTED = ("app.cool.mobile", "app.cool.mobile.dev")

def need(value, message):
    if not value:
        raise ValueError(message)

def write(path, value):
    path = Path(path)
    need(not path.exists(), "Fresh evidence path required: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
    return {"path": str(path), "sha256": P.sha(path)}

def regular(root, relative):
    P.relative_input(relative)
    path = root / relative
    need(path.resolve().is_relative_to(root) and path.is_file(), "Missing source input: " + relative)
    cursor = root
    for part in Path(relative).parts:
        cursor /= part
        need(not cursor.is_symlink(), "Symlink source input refused: " + relative)
    return path

def source_inputs(checkout, source, manifest):
    raw = json.loads(manifest.read_text())
    declared = raw.get("source_sha256", raw)
    inputs = {name: (value["sha256"] if isinstance(value, dict) else value)
              for name, value in declared.items() if P.native_input(name)}
    need(inputs and TARGET in inputs and DRIVER in inputs and "android/app/src/media_capture/AndroidManifest.xml" in inputs,
         "Complete source export with native fixture/driver/flavor required")
    for name, digest in inputs.items():
        need(re.fullmatch(r"[0-9a-f]{64}", digest) and P.sha(regular(checkout, name)) == digest and
             P.sha(regular(source, name)) == digest, "Native source differs: " + name)
    return inputs

def controls(checkout, source):
    result = {}
    for name in P.ANDROID_CAPTURE_CONTROLS:
        result[name] = P.sha(regular(checkout, name))
        need(P.sha(regular(source, name)) == result[name], "Capture control export differs: " + name)
    return result

def environment():
    # Inherit tool/cache locations, never account/provider/signing credentials.
    names = {"PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "JAVA_HOME", "ANDROID_HOME", "ANDROID_SDK_ROOT",
             "ADB_SERVER_SOCKET", "ANDROID_ADB_SERVER_PORT", "ANDROID_USER_HOME", "ANDROID_PREFS_ROOT", "PUB_CACHE", "GRADLE_USER_HOME", "FLUTTER_ROOT",
             "FLUTTER_SUPPRESS_ANALYTICS", "DART_SUPPRESS_ANALYTICS", "CI"}
    env = {k: v for k, v in os.environ.items() if k in names}
    env.update(COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY="false", FLUTTER_SUPPRESS_ANALYTICS="true",
               DART_SUPPRESS_ANALYTICS="true", CI="true", PYTHONDONTWRITEBYTECODE="1")
    return env

def command(out, name, argv, cwd, env, timeout=900):
    need(re.fullmatch(r"[a-z0-9-]+", name), "Invalid command evidence role")
    stdout, stderr = out / (name + ".stdout"), out / (name + ".stderr")
    need(not stdout.exists() and not stderr.exists(), "Command evidence already exists")
    with stdout.open("xb") as a, stderr.open("xb") as b:
        result = subprocess.run(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=a, stderr=b, timeout=timeout)
    os.chmod(stdout, 0o600); os.chmod(stderr, 0o600)
    need(stdout.stat().st_size + stderr.stat().st_size <= 8 * 1024 * 1024, "Command output exceeded evidence bound")
    row = {"name": name, "command": [str(x) for x in argv], "exit_code": result.returncode,
           "stdout_sha256": P.sha(stdout), "stderr_sha256": P.sha(stderr)}
    write(out / (name + ".command.json"), row)
    need(result.returncode == 0, "Native capture command failed: " + name)
    return row

def observation_log(out, name, payload, commands):
    # Host-assembled observations retain their individual actual command logs.
    path = out / (name + ".stdout")
    write(path, payload)
    (out / (name + ".stderr")).write_bytes(b"")
    row = {"name": name, "kind": "host_observation", "exit_code": 0, "stdout_sha256": P.sha(path),
           "stderr_sha256": P.sha(out / (name + ".stderr")), "observations": commands}
    write(out / (name + ".command.json"), row)
    return row

def runtime(source, ruby, env):
    # The qualified macOS system Ruby produces the same fingerprint without
    # automatic gem activation; that mode avoided startup forks in the local
    # custody probe. Other Ruby installations keep their original loading
    # behavior because their dependencies may be supplied by gems.
    ruby_options = ["--disable-gems"] if sys.platform == "darwin" and ruby == "/usr/bin/ruby" else []
    result = subprocess.run([ruby, *ruby_options, "-r", "./scripts/public_app_media", "-e", "puts PublicAppMedia.new(Dir.pwd).runtime_fingerprint"],
                            cwd=source, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True, timeout=60)
    digest = result.stdout.strip()
    need(re.fullmatch(r"[0-9a-f]{64}", digest), "Invalid runtime fingerprint")
    return digest

def rebound_control_changes(prepared):
    """Describe a separately admitted recorder-only rebind without hiding it."""
    rebind = prepared.get("capture_control_rebind")
    if rebind is None:
        return []
    recorder = "scripts/qa/native_android_public_app_media.py"
    need(isinstance(rebind, dict) and
         rebind.get("kind") == "existing_compiled_APK_reviewed_capture_control_successor" and
         rebind.get("changed_capture_controls") == [recorder] and
         rebind.get("changed_compiled_inputs") == [] and
         rebind.get("new_build_or_signing_executed") is False and
         recorder not in prepared["source_inputs"],
         "Unsupported compiled-input or capture-control rebind")
    return [recorder]

def prepare(args):
    checkout, source, out = args.checkout.resolve(), args.source.resolve(), args.output.resolve()
    need(source != checkout and out.is_relative_to(source / ".cache"), "Use an isolated source export and its private .cache packet")
    need(not out.exists() and not (source / "build").exists(), "Fresh source/build/output owner required")
    need(not (source / "android/key.properties").exists(), "Signing configuration is not a fixture input")
    out.mkdir(parents=True, mode=0o700)
    P.ROOT = checkout
    before = source_inputs(checkout, source, args.source_manifest)
    control_before = controls(checkout, source)
    env = environment()
    fingerprint = runtime(source, args.ruby, env)
    defines = ["COLLECT_MOBILE_EVIDENCE_MODE=true", "COLLECT_NATIVE_MEDIA_PACKAGE=" + PACKAGE, "COLLECT_BACKEND=cloudflare"]
    argv = [args.flutter, "build", "apk", "--debug", "--no-pub", "--flavor", "media_capture", "--target", TARGET]
    argv += ["--dart-define=" + value for value in defines]
    commands = [command(out, "native-build", argv, source, env)]
    apk = source / "build/app/outputs/flutter-apk/app-media_capture-debug.apk"
    need(apk.is_file(), "Exact media_capture debug APK is missing")
    retained = out / "retained"; retained.mkdir(); shutil.copyfile(apk, retained / "base.apk")
    commands.append(command(out, "apk-manifest", [args.apkanalyzer, "manifest", "print", str(retained / "base.apk")], source, env))
    facts = P.android_manifest_facts((out / "apk-manifest.stdout").read_text())
    matches = []
    for path in (source / "build/app/intermediates").glob("**/AndroidManifest.xml"):
        if "media_captureDebug" in str(path) and any(x in str(path) for x in ("packaged_manifests", "merged_manifests")):
            try:
                if P.android_manifest_facts(path.read_text()) == facts:
                    matches.append(path)
            except (ValueError, P.ET.ParseError):
                pass
    need(matches, "Actual matching merged manifest proof is absent")
    shutil.copyfile(sorted(matches)[0], out / "merged-manifest.xml")
    commands.append(command(out, "apk-signature", [args.apksigner, "verify", "--verbose", "--print-certs", str(retained / "base.apk")], source, env))
    certificates = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})", (out / "apk-signature.stdout").read_text())
    need(len(certificates) == 1, "One verified APK signing certificate required")
    need(source_inputs(checkout, source, args.source_manifest) == before and controls(checkout, source) == control_before and
         runtime(source, args.ruby, env) == fingerprint, "Source or runtime changed during native build")
    write(out / "source-export-final.json", {"destination": str(source), "source_sha256": before})
    write(out / "driver-source-binding.json", {"path": DRIVER, "sha256": before[DRIVER]})
    write(out / "prepared.json", {"status": "prepared_pending_root_review", "checkout": str(checkout), "source": str(source),
        "runtime_sha256": fingerprint, "source_inputs": before, "capture_controls": control_before, "commands": commands,
        "android": dict(facts, flavor="media_capture", build_type="debug", retained_apk_sha256=P.sha(retained / "base.apk"),
                        certificate_sha256=certificates[0].lower()), "ruby": args.ruby, "flutter": args.flutter,
        "apkanalyzer": args.apkanalyzer, "apksigner": args.apksigner})
    print(json.dumps({"status": "prepared_pending_root_review", "packet": str(out), "apk_sha256": P.sha(retained / "base.apk")}))

def cleanup_failed_drive(out, prepared, apk, adb, source, env, commands, prior,
                         reviewed_sha256, absence_verified):
    """Retain failure; clean only a previously absent, exact-readback fixture."""
    receipt = {"status": "failed_drive_cleanup_unverified", "capture_accepted": False,
               "package_name": PACKAGE, "absent_before_capture": absence_verified,
               "reviewed_apk_sha256": reviewed_sha256, "installed_apk_sha256": None,
               "normal_stop": False, "uninstall_acknowledged": False,
               "absent_after_cleanup": False, "protected_metadata_unchanged": False,
               "cleanup_error_type": None}
    deadline = time.monotonic() + 90

    def observe(name, suffix):
        remaining = deadline - time.monotonic()
        need(remaining > 0, "Failed-drive cleanup budget exhausted")
        row = command(out, name, adb + suffix, source, env, min(60, remaining))
        commands.append(row)
        return (out / (name + ".stdout")).read_text().strip()

    try:
        need(PACKAGE == "app.cool.mobile.mediafixture" and PACKAGE not in PROTECTED and
             prepared["android"].get("package_name") == PACKAGE and absence_verified is True and
             re.fullmatch(r"[0-9a-f]{64}", reviewed_sha256) and P.sha(apk) == reviewed_sha256,
             "Failed-drive cleanup lacks reviewed isolated fixture authority")
        paths = observe("failed-drive-installed-package", ["shell", "pm", "path", PACKAGE]).splitlines()
        if not paths:
            receipt["status"] = "failed_drive_no_installed_fixture_cleanup_skipped"
        else:
            need(len(paths) == 1 and paths[0].startswith("package:/data/app/") and
                 paths[0].endswith("/base.apk"), "Single installed fixture APK required")
            installed = out / "failed-drive-installed"
            installed.mkdir()
            remaining = deadline - time.monotonic()
            need(remaining > 0, "Failed-drive cleanup budget exhausted")
            commands.append(command(out, "failed-drive-installed-pull", adb +
                ["pull", paths[0][8:], str(installed / "base.apk")], source, env, min(60, remaining)))
            receipt["installed_apk_sha256"] = P.sha(installed / "base.apk")
            if receipt["installed_apk_sha256"] != reviewed_sha256:
                receipt["status"] = "failed_drive_installed_identity_mismatch_cleanup_skipped"
            else:
                observe("failed-drive-fixture-stop", ["shell", "am", "force-stop", PACKAGE])
                receipt["normal_stop"] = True
                need(observe("failed-drive-fixture-uninstall", ["uninstall", PACKAGE]) == "Success",
                     "Owned fixture uninstall was not acknowledged")
                receipt["uninstall_acknowledged"] = True
                need(not observe("failed-drive-fixture-absence-after", ["shell", "pm", "list", "packages", PACKAGE]),
                     "Owned fixture remains after normal cleanup")
                receipt["absent_after_cleanup"] = True
                after = {}
                for index, package in enumerate(PROTECTED):
                    raw = observe("failed-drive-original-app-after-" + str(index), ["shell", "dumpsys", "package", package])
                    after[package] = sorted(line.strip() for line in raw.splitlines()
                                           if re.match(r"\s*(versionCode=|versionName=|codePath=)", line))
                receipt["protected_metadata_unchanged"] = after == prior
                need(receipt["protected_metadata_unchanged"], "Original Collect app metadata changed")
                receipt["status"] = "failed_drive_exact_fixture_cleanup_completed"
    except (OSError, ValueError, subprocess.SubprocessError) as cleanup_error:
        # The original drive error is re-raised by the caller. This separate
        # receipt reports cleanup failure without copying private raw output.
        receipt["cleanup_error_type"] = type(cleanup_error).__name__
    receipt["commands"] = [row for row in commands if row["name"].startswith("failed-drive-")]
    write(out / "failed-drive-cleanup.json", receipt)
    return receipt


def run_native_drive(out, prepared, apk, adb, source, env, drive_env, commands,
                     prior, reviewed_sha256, absence_verified):
    try:
        commands.append(command(out, "native-drive", [prepared["flutter"], "drive", "--no-pub", "--driver=" + DRIVER, "--target=" + TARGET,
            "--flavor", "media_capture", "--debug", "--keep-app-running", "-d", adb[-1], "--use-application-binary=" + str(apk)], source, drive_env, 420))
        log = (out / "native-drive.stdout").read_text()
        need("All tests passed" in log and "collect_native_media:complete:7:network-attempts=0" in log,
             "Native route/no-network completion absent")
        return log
    except (OSError, ValueError, subprocess.SubprocessError) as drive_error:
        try:
            cleanup_failed_drive(out, prepared, apk, adb, source, env, commands, prior,
                                 reviewed_sha256, absence_verified)
        except Exception as cleanup_error:
            # Receipt I/O or an unexpected cleanup fault must never replace
            # the drive failure. Retain only type names if file evidence fails.
            try:
                print(json.dumps({"status": "failed_drive_cleanup_error",
                    "capture_accepted": False, "drive_error_type": type(drive_error).__name__,
                    "cleanup_error_type": type(cleanup_error).__name__}), file=sys.stderr)
            finally:
                raise drive_error from cleanup_error
        raise


def capture(args):
    out = args.packet.resolve(); prepared = json.loads((out / "prepared.json").read_text())
    need(prepared["status"] == "prepared_pending_root_review", "Prepared artifact inspection required")
    rebound_changes = rebound_control_changes(prepared)
    need(PACKAGE == "app.cool.mobile.mediafixture" and PACKAGE not in PROTECTED and
         prepared["android"].get("package_name") == PACKAGE and
         prepared["android"].get("flavor") == "media_capture" and
         prepared["android"].get("build_type") == "debug" and prepared["android"].get("debuggable") is True,
         "Isolated debug fixture required before capture or cleanup")
    checkout, source = Path(prepared["checkout"]), Path(prepared["source"])
    P.ROOT = checkout
    apk = out / "retained/base.apk"
    need(args.reviewed_apk_sha256 == prepared["android"]["retained_apk_sha256"] == P.sha(apk), "Separately reviewed exact APK required")
    env = environment(); commands = prepared["commands"].copy()
    need(controls(checkout, source) == prepared["capture_controls"] and runtime(source, prepared["ruby"], env) == prepared["runtime_sha256"], "Capture controls or runtime changed")
    for name, digest in prepared["source_inputs"].items():
        need(P.sha(regular(checkout, name)) == digest and P.sha(regular(source, name)) == digest, "Native source drift before install")
    adb = [args.adb, "-s", args.device]
    def observe(name, suffix):
        row = command(out, name, adb + suffix, source, env, 60); commands.append(row)
        return (out / (name + ".stdout")).read_text().strip()
    state = observe("device-authorization", ["get-state"])
    need(state == "device", "Authorized Android device required")
    absence_verified = not observe("fixture-package-absence", ["shell", "pm", "list", "packages", PACKAGE])
    need(absence_verified, "Refuse to overwrite an installed fixture or its data")
    def protected(prefix):
        result = {}
        for index, package in enumerate(PROTECTED):
            raw = observe(prefix + "-" + str(index), ["shell", "dumpsys", "package", package])
            result[package] = sorted(line.strip() for line in raw.splitlines() if re.match(r"\s*(versionCode=|versionName=|codePath=)", line))
        return result
    prior = protected("original-app-before")
    reads = {}
    for name, prop in [("model", "ro.product.model"), ("android-release", "ro.build.version.release"), ("api", "ro.build.version.sdk"), ("abi", "ro.product.cpu.abi")]:
        reads[name] = observe("device-" + name, ["shell", "getprop", prop])
    size = observe("device-size", ["shell", "wm", "size"])
    density = observe("device-density", ["shell", "wm", "density"])
    sizes = re.findall(r"(?:Physical|Override) size: (\d+)x(\d+)", size)
    densities = re.findall(r"(?:Physical|Override) density: (\d+)", density)
    need(sizes and densities, "Actual device display profile required")
    profile = {"device_id_sha256": hashlib.sha256(args.device.encode()).hexdigest(), "model": reads["model"],
               "android_release": reads["android-release"], "api": int(reads["api"]), "abi": reads["abi"],
               "width": int(sizes[-1][0]), "height": int(sizes[-1][1]), "density_dpi": int(densities[-1])}
    commands.append(observation_log(out, "device-profile", profile, [row for row in commands if row["name"].startswith("device-")]))
    screens = out / "screenshots"; screens.mkdir()
    drive_env = env | {"INTEGRATION_SCREENSHOT_DIR": str(screens)}
    log = run_native_drive(out, prepared, apk, adb, source, env, drive_env, commands,
                           prior, args.reviewed_apk_sha256, absence_verified)
    installed_path = observe("installed-package", ["shell", "pm", "path", PACKAGE]).splitlines()
    need(len(installed_path) == 1 and installed_path[0].startswith("package:/data/app/") and installed_path[0].endswith("/base.apk"), "Single installed fixture APK required")
    installed = out / "installed"; installed.mkdir()
    commands.append(command(out, "installed-pull", adb + ["pull", installed_path[0][8:], str(installed / "base.apk")], source, env, 60))
    need(P.sha(installed / "base.apk") == P.sha(apk), "Installed APK readback differs")
    android = prepared["android"] | {"installed_apk_sha256": P.sha(installed / "base.apk"), "device_profile": profile}
    identity = {k: android[k] for k in ("package_name", "version_name", "version_code", "certificate_sha256", "retained_apk_sha256", "installed_apk_sha256")}
    commands.append(observation_log(out, "installed-bundle", identity, [row for row in commands if row["name"] in {"installed-package", "installed-pull", "apk-manifest", "apk-signature"}]))
    # The fixture was absent before this capture. Remove only that exact owned
    # package after its installed APK bytes match the separately reviewed APK.
    # A failed drive uses a separate readback-gated cleanup and still fails.
    observe("fixture-stop", ["shell", "am", "force-stop", PACKAGE])
    need(observe("fixture-uninstall", ["uninstall", PACKAGE]) == "Success", "Owned fixture uninstall was not acknowledged")
    need(not observe("fixture-absence-after", ["shell", "pm", "list", "packages", PACKAGE]), "Owned fixture remains after normal cleanup")
    after = protected("original-app-after"); need(after == prior, "Original Collect app metadata changed")
    captures = []
    for name, route in P.APP_ROUTES.items():
        match = re.search(r"collect_native_media:pass:" + re.escape(name + ":" + route + ":") + r"([^\r\n]+)", log)
        image = screens / (name + ".png"); need(match and image.is_file(), "Missing asserted route image: " + name)
        header = image.read_bytes()[:24]; need(header.startswith(b"\x89PNG\r\n\x1a\n"), "Native frame is not PNG")
        captures.append({"id": name, "app_route": route, "marker": match[1], "marker_verified": True,
            "path": image.relative_to(source).as_posix(), "sha256": P.sha(image), "width": int.from_bytes(header[16:20], "big"),
            "height": int.from_bytes(header[20:24], "big"), "capture_kind": "native_android_fixture", "platform": "Android device",
            "capture_surface": "flutter_android_surface", "theme": "dark", "text_scale": 1.0})
    need(controls(checkout, source) == prepared["capture_controls"] and runtime(source, prepared["ruby"], env) == prepared["runtime_sha256"], "Source/runtime drift after capture")
    for name, digest in prepared["source_inputs"].items():
        need(P.sha(regular(checkout, name)) == digest and P.sha(regular(source, name)) == digest, "Native compilation input drift after capture")
    binding = {"kind": "native_capture_source_binding_review", "status": "pass", "runtime_sha256": prepared["runtime_sha256"],
        "runtime_matches_capture": True, "native_input_checkout_changes": [], "native_input_export_changes": [],
        "post_export_checkout_changes": rebound_changes, "export_source_changes_during_build": [],
        "native_capture_inputs": prepared["source_inputs"], "native_capture_input_count": len(prepared["source_inputs"])}
    if rebound_changes:
        binding["capture_control_rebind"] = prepared["capture_control_rebind"]
    write(out / "source-binding.json", binding)
    evidence_files = {"merged_manifest": out / "merged-manifest.xml", "apk_manifest": out / "apk-manifest.stdout",
        "apk_signature": out / "apk-signature.stdout", "installed_apk_identity": out / "installed-bundle.stdout", "device_profile": out / "device-profile.stdout"}
    report = {"kind": "native_android_fixture", "status": "captured_pending_visual_review", "native_capture_passed": True,
        "scope": "Seven actual Android Flutter surface captures with synthetic data in an isolated debug fixture; no production or native journey acceptance.",
        "finished_at": datetime.now(timezone.utc).isoformat(), "capture_surface": "flutter_android_surface",
        "source": str(source), "runtime_before_sha256": prepared["runtime_sha256"], "runtime_after_sha256": prepared["runtime_sha256"],
        "source_files_unchanged_before_build": True, "native_capture_inputs_unchanged": True, "errors": [],
        "provider_calls": 0, "hosted_calls": 0, "database_calls": 0, "installed_matches_retained_bundle": True,
        "retained_bundle": (out / "retained").relative_to(source).as_posix(), "installed_bundle": str(installed),
        "bundle_manifest": {"base.apk": P.sha(apk)}, "android": android, "captures": captures, "commands": commands,
        "existing_app_metadata_before": prior, "existing_app_metadata_after": after,
        "fixture_cleanup": {"package_name": PACKAGE, "absent_before_capture": True,
                            "installed_apk_sha256_before_cleanup": android["installed_apk_sha256"],
                            "normal_stop": True, "uninstall_acknowledged": True, "absent_after_cleanup": True,
                            "commands": ["fixture-stop", "fixture-uninstall", "fixture-absence-after"]},
        "capture_controls_before": prepared["capture_controls"], "capture_controls_after": controls(checkout, source),
        "android_evidence": {role: {"path": path.relative_to(source).as_posix(), "sha256": P.sha(path)} for role, path in evidence_files.items()},
        "raw_run_errors_retained": []}
    if rebound_changes:
        # The original actual build remains the build evidence; do not present
        # the recorder-only successor as a newly compiled or signed artifact.
        report["capture_control_rebind"] = prepared["capture_control_rebind"]
    write(out / "raw.json", report)
    report.update(raw_capture_report=(out / "raw.json").relative_to(source).as_posix(), raw_capture_report_sha256=P.sha(out / "raw.json"),
        source_binding_review=(out / "source-binding.json").relative_to(source).as_posix(), source_binding_review_sha256=P.sha(out / "source-binding.json"))
    write(out / "capture-report.json", report)
    print(json.dumps({"status": "captured_pending_visual_review", "packet": str(out), "capture_report_sha256": P.sha(out / "capture-report.json")}))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="phase", required=True)
    build = sub.add_parser("prepare", help="Build and inspect only; stop before any device operation")
    build.add_argument("--checkout", type=Path, default=ROOT)
    for name in ("source", "source-manifest", "output"):
        build.add_argument("--" + name, type=Path, required=True)
    for name in ("flutter", "ruby", "apkanalyzer", "apksigner"):
        build.add_argument("--" + name, required=True)
    device = sub.add_parser("capture", help="Use only the exact separately reviewed fixture APK")
    device.add_argument("--packet", type=Path, required=True)
    for name in ("adb", "device", "reviewed-apk-sha256"):
        device.add_argument("--" + name, required=True)
    args = parser.parse_args()
    try:
        (prepare if args.phase == "prepare" else capture)(args)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"status": "fail", "reason": str(error)}), file=sys.stderr)
        raise SystemExit(1)

if __name__ == "__main__":
    main()
