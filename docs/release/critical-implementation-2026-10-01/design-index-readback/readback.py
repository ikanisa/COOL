#!/usr/bin/env python3
"""Read retained design packet hashes against current bytes; never refresh packets.

This checks only manifest entries and retained artifacts. Changed importers and
new source graphs require current candidate compilation/review; matched historic
entries cannot certify current rendering, accessibility, rights or publication.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parents[4]
PACKETS = "docs/release/revolut-design/verification/current-20261001/"
MEDIA = "docs/release/revolut-design/verification/final-member-media-20261001/"
SHA = re.compile(r"[0-9a-f]{64}\Z")


def digest(path: Path) -> str | None:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def read(name: str) -> dict:
    return json.loads((ROOT / name).read_text())


def compare(entries: dict[str, str], base: Path = ROOT) -> dict:
    if not entries or any(not SHA.fullmatch(value) for value in entries.values()):
        raise ValueError("Incomplete or malformed retained input manifest")
    rows = []
    for name, expected in sorted(entries.items()):
        path = Path(name) if Path(name).is_absolute() else base / name
        actual = digest(path)
        rows.append({"path": name, "expected_sha256": expected,
                     "actual_sha256": actual,
                     "status": "matched" if actual == expected else "missing" if actual is None else "changed"})
    drift = [row for row in rows if row["status"] != "matched"]
    return {"entry_count": len(rows), "matched_count": len(rows) - len(drift),
            "changed_count": sum(row["status"] == "changed" for row in drift),
            "missing_count": sum(row["status"] == "missing" for row in drift),
            "status": "retained_entries_match" if not drift else "current_drift_or_missing",
            "current_source_drift": drift}


def graph(name: str, key: str, base: Path = ROOT) -> dict:
    result = compare(read(name)[key], base)
    return {"manifest": name, "manifest_sha256": digest(ROOT / name),
            "manifest_key": key, **result}


def image_entries(value) -> dict[str, str]:
    result = {}
    if isinstance(value, dict):
        if isinstance(value.get("path"), str) and SHA.fullmatch(str(value.get("sha256", ""))):
            result[value["path"]] = value["sha256"]
        for item in value.values():
            result.update(image_entries(item))
    elif isinstance(value, list):
        for item in value:
            result.update(image_entries(item))
    return result


def catalogue(source: str, name: str, brackets: str) -> list[str]:
    text = (ROOT / source).read_text()
    expression = rf"const\s+{name}\s*=\s*<String>\{brackets[0]}(.*?)\{brackets[1]};"
    matches = re.findall(expression, text, re.S)
    if len(matches) != 1:
        raise ValueError(f"Ambiguous route declaration {source}:{name}")
    values = re.findall(r"'([^']+)'", matches[0])
    rest = re.sub(r"'[^']+'|[\s,]", "", matches[0])
    if rest or len(values) != len(set(values)):
        raise ValueError(f"Dynamic or duplicate route declaration {source}:{name}")
    return values


def routes() -> dict:
    inventory = read("docs/release/revolut-design/route-inventory.json")
    checks = []
    for surface, source, name, brackets in [
        ("member_app", "lib/app/router.dart", "collectRoutePaths", "[]"),
        ("admin", "lib/admin/admin_router.dart", "adminRoutePaths", "[]"),
        ("public_flutter_fallback", "lib/features/landing/public_page_content.dart", "publicWebsitePaths", "{}"),
    ]:
        actual = catalogue(source, name, brackets)
        declared = inventory["surfaces"][surface]
        checks.append({"surface": surface, "route_count": len(actual),
                       "ordered_catalogue_equal": declared["routes"] == actual,
                       "declared_count_equal": declared["route_count"] == len(actual)})
    execution = subprocess.run([
        "ruby", "-rjson", "-r./scripts/qa/public_static_routes", "-e",
        "puts JSON.generate(PublicStaticRoutes.extract(File.read(ARGV.fetch(0))))",
        "scripts/public_static_site_build.rb",
    ], cwd=ROOT, capture_output=True, text=True, check=True)
    actual = json.loads(execution.stdout)
    public = inventory["surfaces"]["public_website"]
    html = [{key: value for key, value in row.items() if key in ("path", "kind", "primary_route")}
            for row in actual if row["kind"] in ("page", "alias", "share_landing")]
    redirects = [{key: value for key, value in row.items() if key in ("path", "redirect_target", "redirect_status")}
                 for row in actual if row["kind"] == "redirect_pattern"]
    checks.append({"surface": "public_website", "route_count": len(html),
                   "ordered_catalogue_equal": public["routes"] == html,
                   "declared_count_equal": public["generated_html_route_count"] == len(html),
                   "redirect_count": len(redirects),
                   "redirects_equal": public["redirect_patterns"] == redirects and public["redirect_pattern_count"] == len(redirects)})
    consumer_name = "docs/release/critical-implementation-2026-10-01/route-inventory-consumer.json"
    consumer = read(consumer_name)
    consumer_ok = consumer["exit_code"] == 0 and consumer["source_unchanged"] is True and digest(ROOT / consumer["log"]) == consumer["log_sha256"]
    return {"status": "pass" if consumer_ok and all(row["ordered_catalogue_equal"] and row["declared_count_equal"] and row.get("redirects_equal", True) for row in checks) else "fail",
            "declaration_checks": checks, "source_binding": compare(inventory["source_sha256"]),
            "existing_runtime_route_factory_consumer": {"path": consumer_name, "sha256": digest(ROOT / consumer_name),
                                                       "passed": consumer_ok, "frozen_input_count": len(consumer["source_before"]),
                                                       "current_source_readback": compare(consumer["source_after"])},
            "scope": "JSON catalogues equal current source declarations; separate existing three-test consumer verifies actual registered route factories. State/role/platform visual acceptance remains unverified."}


def self_test() -> dict:
    with tempfile.TemporaryDirectory() as directory:
        base = Path(directory)
        (base / "source").write_text("reviewed")
        expected = {"source": digest(base / "source")}
        assert compare(expected, base)["matched_count"] == 1
        (base / "source").write_text("changed")
        assert compare(expected, base)["changed_count"] == 1
        (base / "source").unlink()
        assert compare(expected, base)["missing_count"] == 1
        try:
            compare({"source": "bad"}, base)
        except ValueError:
            pass
        else:
            raise AssertionError("Malformed digest accepted")
    return {"status": "pass", "checks": ["matching source", "changed source", "missing source", "malformed digest"]}


def main() -> dict:
    mobile = read(PACKETS + "mobile-route-state-final.json")
    native = read(PACKETS + "native-capture-report.json")
    public = read(PACKETS + "public-complete-browser-execution.json")
    media = read(MEDIA + "capture-report.json")
    old_content = read("docs/release/critical-implementation-2026-10-01/legal-batch1/before.json")["contract"]
    current_content = read("docs/release/public-website-current-content-contract.json")
    manifests = {
        "member_app": graph(PACKETS + "mobile-inputs-before.json", "inputs"),
        "admin": graph(PACKETS + "admin-current-source-binding.json", "actual_current_project_inputs"),
        "native_ios": graph(PACKETS + "native-compiled-input-binding.json", "source_sha256"),
        "member_browser_media": graph(MEDIA + "capture-report.json", "sources_before"),
        "public_content": {"manifest": "docs/release/critical-implementation-2026-10-01/legal-batch1/before.json",
                           "manifest_sha256": digest(ROOT / "docs/release/critical-implementation-2026-10-01/legal-batch1/before.json"),
                           "manifest_key": "contract.reviewed_source_sha256",
                           **compare(old_content["reviewed_source_sha256"])},
    }
    external = {
        "admin": graph(PACKETS + "admin-current-source-binding.json", "actual_external_compiler_inputs"),
        "native_ios": graph(PACKETS + "native-compiled-input-binding.json", "external_dependency_sha256"),
        "mobile_sdk": {"manifest": PACKETS + "mobile-route-state-final.json", **compare(mobile["sdk_inputs"])},
    }
    package_config = ROOT / ".dart_tool/package_config.json"
    package_roots = {package["name"]: package["rootUri"] for package in json.loads(package_config.read_text())["packages"]}
    icon_fonts = {}
    for name, expected in mobile["package_icon_fonts"].items():
        package, relative = name.removeprefix("package:").split("/", 1)
        uri = urlparse(urljoin(package_config.as_uri(), package_roots[package]))
        if uri.scheme != "file":
            raise ValueError("Non-file package font root")
        icon_fonts[str(Path(unquote(uri.path)) / relative)] = expected
    external["mobile_package_icon_fonts"] = {"manifest": PACKETS + "mobile-route-state-final.json",
                                             "current_package_config_sha256": digest(package_config), **compare(icon_fonts)}
    artifacts = {
        "member_app_captures": {"manifest": PACKETS + "mobile-route-state-final.json", **compare(image_entries(mobile["variants"]))},
        "admin_captures": {"manifest": PACKETS + "admin-independent-visual-review.json", **compare(image_entries(read(PACKETS + "admin-independent-visual-review.json")["images"]))},
        "native_captures": {"manifest": PACKETS + "native-capture-report.json", **compare(image_entries(native["captures"]))},
        "native_retained_bundle": {"manifest": PACKETS + "native-capture-report.json", "base": native["retained_bundle"], **compare(native["bundle_manifest"], ROOT / native["retained_bundle"])},
        "public_retained_build": {"manifest": PACKETS + "public-complete-browser-execution.json", "base": read(PACKETS + "public-complete-quality.json")["build_dir"], **compare(public["artifact_files"], ROOT / read(PACKETS + "public-complete-quality.json")["build_dir"])},
        "member_browser_media_captures": {"manifest": MEDIA + "capture-report.json", **compare(image_entries(media["captures"]))},
    }
    for descriptor in [*external.values(), *artifacts.values()]:
        descriptor["manifest_sha256"] = digest(ROOT / descriptor["manifest"])
    current_legal_binding = compare(current_content["reviewed_source_sha256"])
    return {"schema_version": 1, "recorded_at": datetime.now(timezone.utc).isoformat(),
            "status": "readback_complete_current_visual_acceptance_unverified",
            "design_authority": "revolut-design", "source_manifests": manifests,
            "external_compiler_manifests": external, "retained_artifacts": artifacts,
            "route_inventory": routes(), "self_checks": self_test(),
            "current_legal_content_source_binding": current_legal_binding,
            "current_legal_comparison": {"path": current_content["current_comparison_file"], "sha256": current_content["current_comparison_sha256"]},
            "font_rights": {"status": "unverified", "scope": "Aeonik Pro web/app distribution rights remain unresolved; metadata and file presence do not establish licence rights."},
            "limits": ["Readback compares every listed retained entry, not a freshly compiled current import graph or added-file census.",
                       "Retained artifact hashes preserve dated observations; source drift blocks promotion to a current candidate pass.",
                       "Public packet has a 55-file artifact inventory and six-input content binding, not a complete current generator/transitive input manifest.",
                       "No screenshots, browser/native/state matrices, device speech tasks, builds, hosted checks or visual comparison were executed.",
                       "Original installed native equality and network counts remain dated observations; installed bundle/device state is not re-read here.",
                       "No legal, font-rights, publication or whole-product fidelity approval is inferred."]}


if __name__ == "__main__":
    print(json.dumps(self_test() if "--self-test" in sys.argv else main(), indent=2))
