#!/usr/bin/env python3
"""Publish byte-identical, visually inspected local browser or native captures.

Requires a completed strict capture report and a separately recorded review.
Preserves previous native captures and provenance. Grants no native acceptance.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import os
import tempfile
from pathlib import Path
from urllib.parse import urljoin, urlsplit, unquote

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "web/public/app-screens"
REQUIRED = {"home", "groups", "group-detail", "security", "privacy", "terms", "account-deletion"}
APP_ROUTES = {"home": "/home", "groups": "/groups", "group-detail": "/groups/qa-private-group",
              "security": "/settings/security", "privacy": "/settings/legal/privacy",
              "terms": "/settings/legal/terms", "account-deletion": "/settings/account/delete"}
PUBLISHED_METADATA_INPUT = "assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256"
BROWSER_DIAGNOSTIC_INPUTS = {"scripts/qa/collect_diagnostic_observer.mjs",
                             "scripts/qa/public_browser_app_media.mjs"}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local(path: Path) -> Path:
    absolute = path.absolute()
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT) or not absolute.is_relative_to(ROOT):
        raise ValueError("Repository-local regular evidence required")
    relative = absolute.relative_to(ROOT)
    if ".." in relative.parts:
        raise ValueError("Repository-local regular evidence required")
    cursor = ROOT
    for part in relative.parts:
        cursor = cursor / part
        if cursor.is_symlink():
            raise ValueError("Repository-local regular evidence required")
    return resolved


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def atomic_copy(source: Path, target: Path) -> None:
    """Replace a local file after its complete replacement bytes are available."""
    local(target)
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".media-publication-", delete=False) as handle:
        temporary = Path(handle.name)
    try:
        shutil.copyfile(source, temporary)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def validate_previous_manifest(old: dict) -> list[dict]:
    rows = old.get("screens")
    if (not isinstance(rows, list) or len(rows) != 7 or
            any(not isinstance(row, dict) for row in rows) or
            any(not isinstance(row.get("id"), str) for row in rows) or
            {row.get("id") for row in rows} != REQUIRED or
            len({row.get("file") for row in rows if isinstance(row.get("file"), str)}) != 7):
        raise ValueError("Previous media requires exactly seven unique known routes/files")
    for row in rows:
        if (not isinstance(row.get("file"), str) or not re.fullmatch(r"[a-z0-9-]+\.png", row["file"]) or
                not isinstance(row.get("sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", row["sha256"]) or
                not isinstance(row.get("alt"), str) or
                row.get("capture_kind") not in {"browser_flutter_fixture", "native_ios_fixture"}):
            raise ValueError("Previous media filename, hash or provenance is invalid")
    return rows



def evidence(path: Path, expected: str):
    path = local(path)
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or sha(path) != expected:
        raise ValueError("Hash-bound capture evidence changed")
    return json.loads(path.read_text())


def native_input(relative: str) -> bool:
    return relative.startswith(("lib/", "assets/", "licenses/", "android/", "ios/", "third_party/")) or relative in {
        "pubspec.yaml", "pubspec.lock", ".fvmrc", ".metadata", "tool/native_public_app_media_capture.dart",
        "test/fixtures/collect_repository_fixture.dart", "test_driver/integration_test.dart"}


def relative_input(relative: str) -> None:
    if not isinstance(relative, str) or not relative or relative.startswith("/") or any(part in {"", ".", ".."} for part in relative.split("/")):
        raise ValueError("Invalid native input path")


def file_manifest(directory: Path) -> dict:
    if directory.is_symlink() or not directory.is_dir() or directory.suffix != ".app":
        raise ValueError("Native application bundle required")
    result = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError("Native bundle escapes its retained directory")
        if path.is_file():
            if path.is_symlink() or not path.resolve().is_relative_to(directory.resolve()):
                raise ValueError("Native bundle escapes its retained directory")
            result[path.relative_to(directory).as_posix()] = sha(path)
    if "Info.plist" not in result:
        raise ValueError("Native bundle metadata missing")
    return result


def validate_native(report_path: Path, report: dict, runtime: str) -> dict:
    if report.get("native_capture_passed") is not True or report.get("installed_matches_retained_bundle") is not True or report.get("errors") != []:
        raise ValueError("Completed authentic native capture required")
    if report.get("source_files_unchanged_before_build") is not True or any(report.get(k) != 0 for k in ("provider_calls", "hosted_calls", "database_calls")):
        raise ValueError("Native source or network boundary failed")
    commands = report.get("commands", [])
    if not commands or any(row.get("exit_code") != 0 for row in commands):
        raise ValueError("Native build/install/capture command failed")
    names = [row["name"] for row in commands]
    if any(not re.fullmatch(r"[a-z0-9-]+", name) for name in names) or len(names) != len(set(names)) or not {"native-drive", "installed-bundle"}.issubset(names) or not {"native-build", "native-direct-build"}.intersection(names):
        raise ValueError("Native build/install/capture command evidence incomplete")
    for row in commands:
        for stream in ("stdout", "stderr"):
            path = local(report_path.parent / (row["name"] + "." + stream))
            if sha(path) != row[stream + "_sha256"]:
                raise ValueError("Native command log drift")
    drive = local(report_path.parent / "native-drive.stdout")
    log = drive.read_text()
    if "collect_native_media:complete:7:network-attempts=0" not in log:
        raise ValueError("Native no-network completion marker absent")
    for row in report["captures"]:
        if "collect_native_media:pass:" + row["id"] + ":" + row["app_route"] + ":" + row["marker"] not in log:
            raise ValueError("Native route-marker evidence absent")
    retained = local(ROOT / report["retained_bundle"])
    expected = report["bundle_manifest"]
    installed = Path(report["installed_bundle"])
    if installed.resolve() == retained.resolve():
        raise ValueError("Installed native app must be verified separately from retained bundle")
    if file_manifest(retained) != expected or file_manifest(installed) != expected:
        raise ValueError("Installed or retained native bundle differs")
    source = Path(report["source"])
    linked = {"native_drive_log": drive}
    if "source_binding_review" in report:
        binding_path = local(ROOT / report["source_binding_review"])
        binding = evidence(binding_path, report["source_binding_review_sha256"])
        raw_path = local(ROOT / report["raw_capture_report"])
        raw = evidence(raw_path, report["raw_capture_report_sha256"])
        allowed_raw_errors = ([], ["Source drift during native capture"])
        if raw.get("errors") not in allowed_raw_errors or report.get("raw_run_errors_retained") != raw.get("errors"):
            raise ValueError("Unexpected raw native capture failure")
        for key in raw.keys() - {"status", "native_capture_passed", "errors"}:
            if report.get(key) != raw.get(key):
                raise ValueError("Source binding changed actual native capture evidence")
        if binding.get("kind") != "native_capture_source_binding_review" or binding.get("status") != "pass" or binding.get("runtime_sha256") != runtime or binding.get("runtime_matches_capture") is not True:
            raise ValueError("Native source-binding review failed")
        if binding.get("native_input_checkout_changes") != [] or binding.get("native_input_export_changes") != [] or report.get("native_capture_inputs_unchanged") is not True:
            raise ValueError("Native compilation input changed")
        if any(native_input(p) for p in binding.get("post_export_checkout_changes", []) + binding.get("export_source_changes_during_build", [])):
            raise ValueError("Native drift incorrectly exempted as unused source")
        inputs = binding["native_capture_inputs"]
        if not inputs or len(inputs) != binding["native_capture_input_count"]:
            raise ValueError("Native input binding incomplete")
        export_path = local(report_path.parent / "source-export-final.json")
        driver_path = local(report_path.parent / "driver-source-binding.json")
        export, driver = json.loads(export_path.read_text()), json.loads(driver_path.read_text())
        expected_inputs = {path: digest for path, digest in export["source_sha256"].items() if native_input(path)}
        if driver["path"] != "test_driver/integration_test.dart" or export["destination"] != str(source):
            raise ValueError("Native export or driver binding differs")
        expected_inputs[driver["path"]] = driver["sha256"]
        if expected_inputs != inputs:
            raise ValueError("Native input inventory differs from source export")
        for relative, expected_hash in inputs.items():
            relative_input(relative)
            if not native_input(relative) or sha(local(ROOT / relative)) != expected_hash or sha(source / relative) != expected_hash:
                raise ValueError("Native capture source drift: " + relative)
        linked.update(source_binding_review=binding_path, raw_capture_report=raw_path,
                      source_export=export_path, driver_source_binding=driver_path)
    else:
        if report.get("source_files_unchanged_after_capture") is not True or report.get("checkout_matches_export_after_capture") is not True:
            raise ValueError("Native source capture needs explicit reviewed binding")
        export = json.loads((report_path.parent / "source-export-final.json").read_text())
        for relative, expected_hash in export["source_sha256"].items():
            if sha(local(ROOT / relative)) != expected_hash or sha(source / relative) != expected_hash:
                raise ValueError("Native capture source drift: " + relative)
    return linked


def validate_capture(report_path: Path, review_path: Path, runtime: str):
    report, review = json.loads(report_path.read_text()), json.loads(review_path.read_text())
    kind = report.get("kind")
    if report.get("status") != "captured_pending_visual_review" or kind not in {"browser_flutter_fixture", "native_ios_fixture"}:
        raise ValueError("Successful source-bound capture required")
    if report.get("runtime_before_sha256") != runtime or report.get("runtime_after_sha256") != runtime:
        raise ValueError("Runtime changed after capture")
    if not isinstance(report.get("scope"), str) or not report["scope"] or not isinstance(report.get("finished_at"), str) or not report["finished_at"]:
        raise ValueError("Completed capture scope and timestamp required")
    if review.get("status") != "pass" or review.get("capture_report_sha256") != sha(report_path) or review.get("runtime_sha256") != runtime or review.get("native_acceptance") is not False:
        raise ValueError("Exact separate visual review required; media review grants no native acceptance")
    rows, inspected = report["captures"], review["screens"]
    captures = {row["id"]: row for row in rows}
    inspections = {row["id"]: row for row in inspected}
    if len(rows) != 7 or len(inspected) != 7 or set(captures) != REQUIRED or set(inspections) != REQUIRED:
        raise ValueError("All seven current routes must be captured and reviewed exactly once")
    for row in captures.values():
        path = local(ROOT / row["path"])
        checked = inspections[row["id"]]
        header = path.read_bytes()[:24]
        if not header.startswith(b"\x89PNG\r\n\x1a\n") or int.from_bytes(header[16:20], "big") != row["width"] or int.from_bytes(header[20:24], "big") != row["height"]:
            raise ValueError("Capture PNG dimensions changed")
        if row["app_route"] != APP_ROUTES[row["id"]] or row["marker_verified"] is not True or sha(path) != row["sha256"] or checked["sha256"] != row["sha256"] or checked["reviewed_for_website"] is not True:
            raise ValueError("Unreviewed or changed route capture")
        if row.get("capture_kind", kind) != kind or row.get("theme") not in {"dark", "light"} or row.get("text_scale") != 1.0 or not row.get("platform"):
            raise ValueError("Exact capture platform and theme evidence required")
        if kind == "browser_flutter_fixture" and row["platform"] != "Chromium browser" or kind == "native_ios_fixture" and not row["platform"].startswith("iOS Simulator"):
            raise ValueError("Capture platform differs from execution evidence")
    linked = {}
    if kind == "native_ios_fixture":
        linked = validate_native(report_path, report, runtime)
    else:
        validate_browser_diagnostic_binding(report)
        if report.get("sources_unchanged") is not True or report.get("sources_before") != report.get("sources_after") or not report.get("sources_after"):
            raise ValueError("Unchanged browser source binding required")
        if report.get("errors") != [] or report.get("external_requests") != [] or report.get("remote_resources_blocked_before_http") is not True or any(report.get(k) != 0 for k in ("provider_calls", "hosted_calls", "database_calls")):
            raise ValueError("Browser source/network boundary failed")
        if any(url != "https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2" for url in report.get("blocked_engine_font_requests", [])):
            raise ValueError("Unexpected browser blocked resource")
        if not any(row.get("name") == "flutter-build" and row.get("exit_code") == 0 for row in report.get("commands", [])):
            raise ValueError("Successful browser build evidence required")
        if "reused_compilation" in report:
            validate_browser_reused_compilation(report)
        if "isolated_source_export" in report:
            validate_browser_source_binding(report, runtime)
        build = report["build_files"]
        if not 1 <= len(build) <= 10_000 or not {"main.dart.js", "flutter_bootstrap.js"}.issubset(build) or any(build.get(path) != digest for path, digest in report["served_resources"].items()) or hashlib.sha256(json.dumps(build, separators=(",", ":")).encode()).hexdigest() != report["build_manifest_sha256"] or report["served_resources"].get("main.dart.js") != build.get("main.dart.js") or review.get("build_manifest_sha256") != report["build_manifest_sha256"]:
            raise ValueError("Browser build/served/review binding failed")
        for relative, expected in report["sources_after"].items():
            if sha(local(ROOT / relative)) != expected:
                raise ValueError("Capture source drift: " + relative)
        for relative, expected in build.items():
            if sha(local(report_path.parent / "build" / relative)) != expected:
                raise ValueError("Capture build drift: " + relative)
    return report, review, captures, linked


def validate_browser_reused_compilation(report: dict) -> None:
    validate_browser_diagnostic_binding(report)
    reuse = report["reused_compilation"]
    previous_path = local(ROOT / reuse["capture_report"])
    previous = evidence(previous_path, reuse["capture_report_sha256"])
    validate_browser_diagnostic_binding(previous)
    if (previous.get("kind") != "browser_flutter_fixture" or previous.get("runtime_fingerprint_version") != 4
            or previous.get("browser_entrypoint") != "tool/public_app_media_capture.dart"
            or previous.get("source_root") != report.get("source_root")
            or reuse.get("source_root") != report.get("source_root")
            or previous.get("sources_before") != report.get("sources_before")
            or previous.get("generated_bindings_before") != report.get("generated_bindings_before")
            or previous.get("flutter") != report.get("flutter")
            or previous.get("build_files") != report.get("build_files")
            or previous.get("build_manifest_sha256") != report.get("build_manifest_sha256")):
        raise ValueError("Reused browser compilation source/binding/artifact differs")
    directory = local(ROOT / reuse["original_build_directory"])
    if directory != previous_path.parent / "build":
        raise ValueError("Reused browser compilation directory differs")
    observed = {}
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory)
        if any(part.startswith(".") or "GeneratedPluginRegistrant" in part for part in relative.parts):
            continue
        local(path)
        if path.is_file():
            observed[relative.as_posix()] = sha(path)
    if observed != report["build_files"]:
        raise ValueError("Reused browser compilation bytes or input set changed")
    builds = [row for row in previous.get("commands", []) if row.get("name") == "flutter-build"]
    current = [row for row in report.get("commands", []) if row.get("name") == "flutter-build"]
    if (len(builds) != 1 or builds[0].get("exit_code") != 0 or len(current) != 1
            or current[0] != {**builds[0], "reused_verified_compilation": True}):
        raise ValueError("Reused browser compiler command differs")
    for stream in ("stdout", "stderr"):
        if sha(local(previous_path.parent / ("flutter-build." + stream))) != builds[0][stream + "_sha256"]:
            raise ValueError("Reused browser compiler command log changed")


def validate_browser_diagnostic_binding(report: dict) -> None:
    """Require the observer that prevented handled errors evading capture QA."""
    expected = {relative: sha(local(ROOT / relative))
                for relative in sorted(BROWSER_DIAGNOSTIC_INPUTS)}
    if (report.get("diagnostic_observer_sources_before") != expected or
            report.get("diagnostic_observer_sources_after") != expected):
        raise ValueError("Browser diagnostic observer binding is incomplete or changed")
    if report.get("capture_recorder_sha256") != expected["scripts/qa/public_browser_app_media.mjs"]:
        raise ValueError("Browser capture recorder changed")


def validate_browser_source_binding(report: dict, runtime: str) -> None:
    """Bind the actual compilation directory without adopting its generated paths."""
    isolated = report.get("isolated_source_export")
    source = Path(report.get("source_root", ""))
    if type(isolated) is not bool or not source.is_absolute() or source.resolve() != source:
        raise ValueError("Explicit canonical browser compilation directory required")
    if isolated != (source != ROOT.resolve()) or (isolated and source.is_relative_to(ROOT.resolve())):
        raise ValueError("Isolated browser source must be outside the checkout")
    if (report.get("checkout_runtime_before_sha256") != runtime or
            report.get("checkout_runtime_after_sha256") != runtime):
        raise ValueError("Current checkout does not match the captured export")
    if report.get("runtime_fingerprint_version") is not None:
        if (report.get("runtime_fingerprint_version") != 4 or
                report.get("browser_entrypoint") != "tool/public_app_media_capture.dart"):
            raise ValueError("Unknown browser source graph contract")
        snapshots = []
        for directory in (ROOT, source):
            output = subprocess.check_output([
                "ruby", "-r", "./scripts/public_app_media", "-e",
                "puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)"],
                cwd=directory, text=True)
            snapshot = json.loads(output)
            if snapshot != report.get("sources_after"):
                raise ValueError("Browser reachable source closure differs from actual source")
            fingerprint = hashlib.sha256("".join(
                relative + "\0" + digest + "\n" for relative, digest in snapshot.items()).encode()).hexdigest()
            if fingerprint != runtime:
                raise ValueError("Browser graph fingerprint differs from source closure")
            snapshots.append(snapshot)
        if (report.get("checkout_browser_sources_before") != snapshots[0] or
                report.get("checkout_browser_sources_after") != snapshots[0]):
            raise ValueError("Browser checkout graph observation is incomplete")
    bindings = report.get("generated_bindings_before")
    if (not isinstance(bindings, dict) or
            set(bindings) != {".dart_tool/package_config.json", ".flutter-plugins-dependencies"} or
            bindings != report.get("generated_bindings_after") or
            report.get("generated_bindings_unchanged") is not True):
        raise ValueError("Browser compilation bindings changed or are incomplete")
    for relative, expected in bindings.items():
        path = source / relative
        if (not isinstance(expected, str) or not re.fullmatch(r"[a-f0-9]{64}", expected) or
                not path.is_file() or path.is_symlink() or
                not path.resolve().is_relative_to(source) or sha(path) != expected):
            raise ValueError("Browser compilation binding differs from actual export")
    expected_roots = {"collect_app": source, "file_saver": source / "third_party/file_saver",
                      "gotrue": source / "third_party/gotrue",
                      "firebase_messaging": source / "third_party/firebase_messaging"}
    config_path = source / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    packages = config.get("packages")
    if not isinstance(packages, list):
        raise ValueError("Browser package binding inventory is malformed")
    for name, expected_root in expected_roots.items():
        rows = [row for row in packages if isinstance(row, dict) and row.get("name") == name]
        if len(rows) != 1 or not isinstance(rows[0].get("rootUri"), str):
            raise ValueError("Required browser local package binding missing")
        uri = urlsplit(urljoin(config_path.as_uri(), rows[0]["rootUri"]))
        if (uri.scheme != "file" or uri.netloc or uri.query or uri.fragment or
                not expected_root.is_dir() or expected_root.resolve() != expected_root or
                Path(unquote(uri.path)).resolve() != expected_root):
            raise ValueError("Browser local package points outside its declared export")
    plugin_manifest = json.loads((source / ".flutter-plugins-dependencies").read_text())
    platforms = plugin_manifest.get("plugins")
    if not isinstance(platforms, dict) or any(not isinstance(rows, list) for rows in platforms.values()):
        raise ValueError("Browser plugin binding inventory is malformed")
    seen = set()
    for rows in platforms.values():
        for row in rows:
            if not isinstance(row, dict) or row.get("name") not in {"file_saver", "firebase_messaging"}:
                continue
            path = row.get("path")
            if (not isinstance(path, str) or not Path(path).is_absolute() or
                    Path(path).resolve() != expected_roots[row["name"]]):
                raise ValueError("Browser local plugin points outside its declared export")
            seen.add(row["name"])
    expected_strings = {name: str(path) for name, path in expected_roots.items()}
    if (seen != {"file_saver", "firebase_messaging"} or
            report.get("resolved_local_bindings_before") != expected_strings or
            report.get("resolved_local_bindings_after") != expected_strings):
        raise ValueError("Browser local package/plugin bindings changed or are incomplete")
    recorder = ROOT / "scripts/qa/public_browser_app_media.mjs"
    if report.get("capture_recorder_sha256") != sha(recorder):
        raise ValueError("Browser capture recorder changed")
    validate_browser_diagnostic_binding(report)
    for relative in {"scripts/public_app_media.rb", "scripts/qa/asset_manifest_integrity.rb"}:
        if (relative not in report["sources_after"] or
                sha(local(ROOT / relative)) != report["sources_after"][relative]):
            raise ValueError("Browser capture helper closure is incomplete or changed")
    for relative, expected in report["sources_after"].items():
        # The repository-local check below also rejects traversal before any
        # corresponding export path is opened.
        local(ROOT / relative)
        path = source / relative
        if (not path.is_file() or path.is_symlink() or
                not path.resolve().is_relative_to(source) or sha(path) != expected):
            raise ValueError("Browser captured source differs from actual export")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-report", type=Path, required=True)
    parser.add_argument("--visual-review", type=Path, required=True)
    parser.add_argument("--packet", type=Path, required=True)
    args = parser.parse_args()
    report_path, review_path = local(args.capture_report), local(args.visual_review)
    report, review = json.loads(report_path.read_text()), json.loads(review_path.read_text())
    packet = local(args.packet)
    if packet.exists():
        raise FileExistsError("Fresh media publication packet required")
    graph_scoped = report.get("kind") == "browser_flutter_fixture" and report.get("runtime_fingerprint_version") == 4
    method = "browser_runtime_fingerprint" if graph_scoped else "runtime_fingerprint"
    runtime = subprocess.check_output(["ruby", "-r", "./scripts/public_app_media", "-e", "puts PublicAppMedia.new(Dir.pwd)." + method], cwd=ROOT, text=True).strip()
    report, review, captures, linked = validate_capture(report_path, review_path, runtime)
    kind = report["kind"]
    old = json.loads((MEDIA / "manifest.json").read_text())
    validate_previous_manifest(old)
    packet.mkdir(parents=True)
    old_kinds = {row["capture_kind"] for row in old["screens"]}
    historic = packet / ("previous-native-media" if old_kinds == {"native_ios_fixture"} else "previous-browser-media")
    historic.mkdir()
    for name in ["manifest.json", "capture-provenance.json"]:
        shutil.copyfile(MEDIA / name, historic / name)
    for row in old["screens"]:
        path = local(MEDIA / row["file"])
        if sha(path) != row["sha256"]:
            raise ValueError("Prior published capture differs from its manifest")
        shutil.copyfile(path, historic / row["file"])
        if sha(historic / row["file"]) != row["sha256"]:
            raise ValueError("Prior capture preservation failed")
    approved = ROOT / "assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256"
    shutil.copyfile(approved, packet / "approved-assets-before.sha256")
    shutil.copyfile(report_path, packet / "capture-report.json")
    shutil.copyfile(review_path, packet / "visual-review.json")
    alt = {row["id"]: row["alt"] for row in old["screens"]}
    screens = []
    staged = packet / "replacement-media"
    staged.mkdir()
    for id_, row in sorted(captures.items()):
        filename = id_ + "-" + row["sha256"][:12] + ".png"
        if (MEDIA / filename).exists():
            path = local(MEDIA / filename)
            if sha(path) != row["sha256"]:
                raise ValueError("Replacement filename collides with different existing bytes")
            if not (historic / filename).exists():
                shutil.copyfile(path, historic / filename)
        shutil.copyfile(ROOT / row["path"], staged / filename)
        if sha(staged / filename) != row["sha256"]:
            raise ValueError("Published screenshot differs from inspected capture")
        screens.append({"id": id_, "file": filename, "capture": row["path"], "sha256": row["sha256"],
                        "width": row["width"], "height": row["height"], "reviewed_for_website": True,
                        "capture_kind": kind, "alt": alt[id_], "app_route": row["app_route"],
                        "platform": row["platform"], "theme": row["theme"], "text_scale": row["text_scale"], "data": "synthetic example data"})
    provenance = {"status": "pass", "kind": kind, "runtime_sha256": runtime,
                  "native_capture_passed": kind == "native_ios_fixture", "scope": report["scope"],
                  "capture_report": (packet / "capture-report.json").relative_to(ROOT).as_posix(),
                  "capture_report_sha256": sha(packet / "capture-report.json"),
                  "visual_review": (packet / "visual-review.json").relative_to(ROOT).as_posix(),
                  "visual_review_sha256": sha(packet / "visual-review.json"), "captures": list(captures.values())}
    if kind == "native_ios_fixture":
        provenance["installed_matches_retained_bundle"] = True
        provenance["bundle_manifest_sha256"] = hashlib.sha256(json.dumps(report["bundle_manifest"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        for role, path in linked.items():
            target = packet / (role + path.suffix)
            shutil.copyfile(path, target)
            provenance[role] = target.relative_to(ROOT).as_posix()
            provenance[role + "_sha256"] = sha(target)
        if "source_binding_review" in linked:
            inputs = json.loads(linked["source_binding_review"].read_text())["native_capture_inputs"]
            if PUBLISHED_METADATA_INPUT in inputs:
                preserved_input = packet / "approved-assets-before.sha256"
                if sha(preserved_input) != inputs[PUBLISHED_METADATA_INPUT]:
                    raise ValueError("Prepublication asset approval input changed")
                provenance["preserved_publication_input"] = {
                    "path": PUBLISHED_METADATA_INPUT,
                    "preserved": preserved_input.relative_to(ROOT).as_posix(),
                    "sha256": sha(preserved_input)}
    version = re.search(r"(?m)^version:\s*([^\s#]+)", (ROOT / "pubspec.yaml").read_text())
    if not version:
        raise ValueError("Current pubspec version is required")
    manifest = {"schema_version": 2, "generated_at": report["finished_at"], "runtime_sha256": runtime,
                "runtime_fingerprint_version": 4 if graph_scoped else 3, "app_version": version.group(1), "scope": report["scope"], "screens": screens}
    write_json(staged / "manifest.json", manifest)
    write_json(staged / "capture-provenance.json", provenance)
    old_paths = {"web/public/app-screens/" + row["file"] for row in old["screens"]}
    lines = [line for line in approved.read_text().splitlines() if line.split("  ", 1)[1] not in old_paths]
    lines.extend(row["sha256"] + "  web/public/app-screens/" + row["file"] for row in screens)
    staged_approved = packet / "approved-assets-replacement.sha256"
    staged_approved.write_text("\n".join(sorted(lines, key=lambda line: line.split("  ", 1)[1])) + "\n")
    preserved = {path.name: sha(path) for path in historic.iterdir() if path.is_file()}
    replacement_names = {row["file"] for row in screens}
    try:
        for row in screens:
            atomic_copy(staged / row["file"], MEDIA / row["file"])
        for name in ["manifest.json", "capture-provenance.json"]:
            atomic_copy(staged / name, MEDIA / name)
        atomic_copy(staged_approved, approved)
        for row in old["screens"]:
            if row["file"] not in replacement_names:
                (MEDIA / row["file"]).unlink()
        subprocess.run(["ruby", "-r", "./scripts/public_app_media", "-e", "puts PublicAppMedia.new(Dir.pwd).screens.keys.join(',')"], cwd=ROOT, check=True)
    except BaseException as failure:
        restored = False
        rollback_error = None
        try:
            for name in preserved:
                atomic_copy(historic / name, MEDIA / name)
            for name in replacement_names - preserved.keys():
                (MEDIA / name).unlink(missing_ok=True)
            atomic_copy(packet / "approved-assets-before.sha256", approved)
            restored = (all(sha(MEDIA / name) == expected for name, expected in preserved.items()) and
                        not any((MEDIA / name).exists() for name in replacement_names - preserved.keys()) and
                        sha(approved) == sha(packet / "approved-assets-before.sha256"))
        except BaseException as error:
            rollback_error = type(error).__name__
        write_json(packet / "publication-failure.json", {
            "status": "fail", "failure_type": type(failure).__name__,
            "previous_media_and_approval_restored": restored,
            "rollback_error_type": rollback_error, "preserved_sha256": preserved})
        if not restored:
            raise RuntimeError("Media publication failed and exact restoration could not be verified") from failure
        raise
    write_json(packet / "publication.json", {"status": "pass", "scope": "Byte-identical reviewed interface previews; design and release acceptance remain open.",
                                            "native_capture_passed": kind == "native_ios_fixture", "runtime_sha256": runtime,
                                            "published": {row["file"]: row["sha256"] for row in screens},
                                            "old_media_preserved": {row["file"]: row["sha256"] for row in old["screens"]}})
    print("Published reviewed " + kind + " media; previous images and provenance preserved.")


if __name__ == "__main__":
    main()
