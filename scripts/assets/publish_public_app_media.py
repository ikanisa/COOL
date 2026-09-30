#!/usr/bin/env python3
"""Publish byte-identical, visually inspected local browser route captures.

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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "web/public/app-screens"
REQUIRED = {"home", "groups", "group-detail", "security", "privacy", "terms", "account-deletion"}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local(path: Path) -> Path:
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT) or path.is_symlink():
        raise ValueError("Repository-local regular evidence required")
    return resolved


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


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
    runtime = subprocess.check_output(["ruby", "-r", "./scripts/public_app_media", "-e", "puts PublicAppMedia.new(Dir.pwd).runtime_fingerprint"], cwd=ROOT, text=True).strip()
    if report["status"] != "captured_pending_visual_review" or report["kind"] != "browser_flutter_fixture" or not report["sources_unchanged"]:
        raise ValueError("Successful source-bound browser capture required")
    if report["runtime_before_sha256"] != runtime or report["runtime_after_sha256"] != runtime:
        raise ValueError("Runtime changed after capture")
    if review["status"] != "pass" or review["capture_report_sha256"] != sha(report_path) or review["runtime_sha256"] != runtime or review["native_acceptance"] is not False:
        raise ValueError("Exact separately recorded browser visual review required")
    captures = {row["id"]: row for row in report["captures"]}
    inspections = {row["id"]: row for row in review["screens"]}
    if len(captures) != 7 or set(captures) != REQUIRED or set(inspections) != REQUIRED:
        raise ValueError("All seven current media routes must be captured and reviewed")
    for relative, expected in report["sources_after"].items():
        if sha(local(ROOT / relative)) != expected:
            raise ValueError("Capture source drift: " + relative)
    for relative, expected in report["build_files"].items():
        if sha(local(report_path.parent / "build" / relative)) != expected:
            raise ValueError("Capture build drift: " + relative)
    for row in captures.values():
        inspected = inspections[row["id"]]
        path = local(ROOT / row["path"])
        if not row["marker_verified"] or sha(path) != row["sha256"] or inspected["sha256"] != row["sha256"] or inspected["reviewed_for_website"] is not True:
            raise ValueError("Unreviewed or changed route capture")
    packet.mkdir(parents=True)
    old = json.loads((MEDIA / "manifest.json").read_text())
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
    for id_, row in sorted(captures.items()):
        filename = id_ + "-" + row["sha256"][:12] + ".png"
        shutil.copyfile(ROOT / row["path"], MEDIA / filename)
        if sha(MEDIA / filename) != row["sha256"]:
            raise ValueError("Published screenshot differs from inspected capture")
        screens.append({"id": id_, "file": filename, "capture": row["path"], "sha256": row["sha256"],
                        "width": row["width"], "height": row["height"], "reviewed_for_website": True,
                        "capture_kind": "browser_flutter_fixture", "alt": alt[id_], "app_route": row["app_route"],
                        "platform": "Chromium browser", "theme": "dark", "text_scale": 1.0, "data": "synthetic example data"})
    provenance = {"status": "pass", "kind": "browser_flutter_fixture", "runtime_sha256": runtime,
                  "native_capture_passed": False, "scope": report["scope"],
                  "capture_report": (packet / "capture-report.json").relative_to(ROOT).as_posix(),
                  "capture_report_sha256": sha(packet / "capture-report.json"),
                  "visual_review": (packet / "visual-review.json").relative_to(ROOT).as_posix(),
                  "visual_review_sha256": sha(packet / "visual-review.json"), "captures": list(captures.values())}
    version = re.search(r"(?m)^version:\s*([^\s#]+)", (ROOT / "pubspec.yaml").read_text())
    if not version:
        raise ValueError("Current pubspec version is required")
    manifest = {"schema_version": 2, "generated_at": report["finished_at"], "runtime_sha256": runtime,
                "runtime_fingerprint_version": 3, "app_version": version.group(1), "scope": report["scope"], "screens": screens}
    write_json(MEDIA / "manifest.json", manifest)
    write_json(MEDIA / "capture-provenance.json", provenance)
    old_paths = {"web/public/app-screens/" + row["file"] for row in old["screens"]}
    lines = [line for line in approved.read_text().splitlines() if line.split("  ", 1)[1] not in old_paths]
    lines.extend(row["sha256"] + "  web/public/app-screens/" + row["file"] for row in screens)
    approved.write_text("\n".join(sorted(lines, key=lambda line: line.split("  ", 1)[1])) + "\n")
    for row in old["screens"]:
        if row["file"] not in {screen["file"] for screen in screens}:
            (MEDIA / row["file"]).unlink()
    subprocess.run(["ruby", "-r", "./scripts/public_app_media", "-e", "puts PublicAppMedia.new(Dir.pwd).screens.keys.join(',')"], cwd=ROOT, check=True)
    write_json(packet / "publication.json", {"status": "pass", "scope": "Byte-identical reviewed browser interface previews; native acceptance remains open.",
                                            "native_capture_passed": False, "runtime_sha256": runtime,
                                            "published": {row["file"]: row["sha256"] for row in screens},
                                            "old_media_preserved": {row["file"]: row["sha256"] for row in old["screens"]}})
    print("Published reviewed browser previews; previous native media preserved.")


if __name__ == "__main__":
    main()
