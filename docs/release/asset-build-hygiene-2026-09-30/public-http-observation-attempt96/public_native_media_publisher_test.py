"""Synthetic publication-input regressions. These fixtures are not app evidence."""
import base64
import importlib.util
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).parents[1] / "assets/publish_public_app_media.py"
spec = importlib.util.spec_from_file_location("publisher", MODULE)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1kAAAAASUVORK5CYII=")


class NativePublisherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.prior_root = publisher.ROOT
        publisher.ROOT = self.root
        self.out = self.root / ".cache/native"
        self.out.mkdir(parents=True)
        self.source = self.root / "isolated-source"
        self.inputs = {"lib/app.dart": "synthetic native source", "test_driver/integration_test.dart": "synthetic driver"}
        self.hashes = {}
        for path, text in self.inputs.items():
            for base in (self.root, self.source):
                target = base / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
            self.hashes[path] = publisher.sha(self.root / path)
        self.retained, self.installed = self.out / "retained/Collect.app", self.out / "installed/Collect.app"
        for bundle in (self.retained, self.installed):
            bundle.mkdir(parents=True)
            (bundle / "Info.plist").write_text("synthetic test bundle metadata")
        self.log = "collect_native_media:complete:7:network-attempts=0\n"
        self.captures = []
        for name, route in publisher.APP_ROUTES.items():
            image = self.out / (name + ".png")
            image.write_bytes(PNG + name.encode())
            self.captures.append({"id": name, "app_route": route, "marker": name, "marker_verified": True,
                                  "path": image.relative_to(self.root).as_posix(), "sha256": publisher.sha(image), "width": 1, "height": 1,
                                  "capture_kind": "native_ios_fixture", "platform": "iOS Simulator", "theme": "dark", "text_scale": 1.0})
            self.log += "collect_native_media:pass:" + name + ":" + route + ":" + name + "\n"
        self.commands = []
        for name in ("native-build", "native-drive", "installed-bundle"):
            stdout, stderr = self.out / (name + ".stdout"), self.out / (name + ".stderr")
            stdout.write_text(self.log if name == "native-drive" else "synthetic completed command")
            stderr.write_text("")
            self.commands.append({"name": name, "exit_code": 0, "stdout_sha256": publisher.sha(stdout), "stderr_sha256": publisher.sha(stderr)})
        self.runtime = "a" * 64
        self.binding = {"kind": "native_capture_source_binding_review", "status": "pass", "runtime_sha256": self.runtime,
                        "runtime_matches_capture": True, "native_input_checkout_changes": [], "native_input_export_changes": [],
                        "post_export_checkout_changes": ["test/unused_test.dart"], "export_source_changes_during_build": [],
                        "native_capture_inputs": self.hashes, "native_capture_input_count": len(self.hashes)}
        publisher.write_json(self.out / "source-export-final.json", {"destination": str(self.source), "source_sha256": self.hashes})
        publisher.write_json(self.out / "driver-source-binding.json", {"path": "test_driver/integration_test.dart", "sha256": self.hashes["test_driver/integration_test.dart"]})
        self.raw = {"kind": "native_ios_fixture", "status": "failed", "native_capture_passed": False,
                    "scope": "Synthetic native publication-input regression", "finished_at": "2026-09-30T12:00:00Z",
                    "installed_matches_retained_bundle": True, "source_files_unchanged_before_build": True,
                    "runtime_before_sha256": self.runtime, "runtime_after_sha256": self.runtime,
                    "provider_calls": 0, "hosted_calls": 0, "database_calls": 0,
                    "commands": self.commands, "captures": self.captures, "errors": ["Source drift during native capture"],
                    "source": str(self.source), "retained_bundle": self.retained.relative_to(self.root).as_posix(),
                    "installed_bundle": str(self.installed), "bundle_manifest": publisher.file_manifest(self.retained)}
        self.report_path, self.review_path = self.out / "current-binding.json", self.out / "visual-review.json"
        self.save()

    def tearDown(self):
        publisher.ROOT = self.prior_root
        self.temp.cleanup()

    def save(self):
        raw_path, binding_path = self.out / "raw.json", self.out / "binding.json"
        publisher.write_json(raw_path, self.raw)
        publisher.write_json(binding_path, self.binding)
        report = dict(self.raw, status="captured_pending_visual_review", native_capture_passed=True, errors=[],
                      raw_run_errors_retained=self.raw["errors"], native_capture_inputs_unchanged=True,
                      raw_capture_report=raw_path.relative_to(self.root).as_posix(), raw_capture_report_sha256=publisher.sha(raw_path),
                      source_binding_review=binding_path.relative_to(self.root).as_posix(), source_binding_review_sha256=publisher.sha(binding_path))
        publisher.write_json(self.report_path, report)
        review = {"status": "pass", "native_acceptance": False, "runtime_sha256": self.runtime,
                  "capture_report_sha256": publisher.sha(self.report_path),
                  "screens": [{"id": row["id"], "sha256": row["sha256"], "reviewed_for_website": True} for row in self.captures]}
        publisher.write_json(self.review_path, review)

    def validate(self):
        return publisher.validate_capture(self.report_path, self.review_path, self.runtime)

    def test_reviewed_unused_test_drift_preserves_native_binding(self):
        result = self.validate()
        self.assertEqual(set(result[2]), publisher.REQUIRED)
        self.assertIn("source_binding_review", result[3])

    def test_compilation_input_change_is_rejected(self):
        (self.root / "lib/app.dart").write_text("changed native input")
        with self.assertRaisesRegex(ValueError, "source drift"):
            self.validate()

    def test_native_drift_cannot_be_labelled_unused(self):
        self.binding["post_export_checkout_changes"] = ["lib/app.dart"]
        self.save()
        with self.assertRaisesRegex(ValueError, "incorrectly exempted"):
            self.validate()

    def test_installed_bundle_mismatch_is_rejected(self):
        (self.installed / "Info.plist").write_text("changed installed app")
        with self.assertRaisesRegex(ValueError, "bundle differs"):
            self.validate()

    def test_failed_native_build_is_rejected(self):
        self.commands[0]["exit_code"] = 1
        self.save()
        with self.assertRaisesRegex(ValueError, "command failed"):
            self.validate()

    def test_no_network_marker_is_required(self):
        drive = self.out / "native-drive.stdout"
        drive.write_text(self.log.replace("network-attempts=0", "network-attempts=1"))
        self.commands[1]["stdout_sha256"] = publisher.sha(drive)
        self.save()
        with self.assertRaisesRegex(ValueError, "no-network"):
            self.validate()

    def test_hash_bound_review_rejects_uninspected_image(self):
        review = json.loads(self.review_path.read_text())
        review["screens"][0]["reviewed_for_website"] = False
        publisher.write_json(self.review_path, review)
        with self.assertRaisesRegex(ValueError, "Unreviewed"):
            self.validate()

    def test_replaced_image_after_review_is_rejected(self):
        (self.root / self.captures[0]["path"]).write_bytes(PNG)
        with self.assertRaisesRegex(ValueError, "changed route capture"):
            self.validate()

    def test_omitted_native_input_is_rejected(self):
        self.binding["native_capture_inputs"] = {"test_driver/integration_test.dart": self.hashes["test_driver/integration_test.dart"]}
        self.binding["native_capture_input_count"] = 1
        self.save()
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.validate()

    def test_corrected_binding_cannot_change_network_claim(self):
        report = json.loads(self.report_path.read_text())
        self.raw["provider_calls"] = 1
        publisher.write_json(self.out / "raw.json", self.raw)
        report["raw_capture_report_sha256"] = publisher.sha(self.out / "raw.json")
        publisher.write_json(self.report_path, report)
        review = json.loads(self.review_path.read_text())
        review["capture_report_sha256"] = publisher.sha(self.report_path)
        publisher.write_json(self.review_path, review)
        with self.assertRaisesRegex(ValueError, "changed actual"):
            self.validate()

    def browser_fixture(self):
        captures = [dict(row, platform="Chromium browser") for row in self.captures]
        for row in captures:
            row.pop("capture_kind")  # Actual browser capture schema declares kind once.
        build = {}
        for name in ("main.dart.js", "flutter_bootstrap.js"):
            target = self.out / "build" / name
            target.parent.mkdir(exist_ok=True)
            target.write_text("synthetic compiled browser bytes " + name)
            build[name] = publisher.sha(target)
        build_hash = hashlib.sha256(json.dumps(build, separators=(",", ":")).encode()).hexdigest()
        sources = {"lib/app.dart": self.hashes["lib/app.dart"]}
        report = {"kind": "browser_flutter_fixture", "status": "captured_pending_visual_review", "runtime_before_sha256": self.runtime,
                  "scope": "Synthetic browser publication-input regression", "finished_at": "2026-09-30T12:00:00Z",
                  "runtime_after_sha256": self.runtime, "sources_before": sources, "sources_after": sources,
                  "sources_unchanged": True, "errors": [], "external_requests": [], "remote_resources_blocked_before_http": True,
                  "provider_calls": 0, "hosted_calls": 0, "database_calls": 0, "commands": [{"name": "flutter-build", "exit_code": 0}],
                  "captures": captures, "build_files": build, "build_manifest_sha256": build_hash, "served_resources": build.copy()}
        publisher.write_json(self.report_path, report)
        review = json.loads(self.review_path.read_text())
        review.update(capture_report_sha256=publisher.sha(self.report_path), build_manifest_sha256=build_hash)
        publisher.write_json(self.review_path, review)
        return report, review

    def test_strict_browser_branch_keeps_its_original_capture_schema(self):
        self.browser_fixture()
        self.assertEqual(self.validate()[0]["kind"], "browser_flutter_fixture")

    def test_browser_changed_served_artifact_is_rejected(self):
        report, review = self.browser_fixture()
        report["served_resources"]["main.dart.js"] = "b" * 64
        publisher.write_json(self.report_path, report)
        review["capture_report_sha256"] = publisher.sha(self.report_path)
        publisher.write_json(self.review_path, review)
        with self.assertRaisesRegex(ValueError, "build/served/review"):
            self.validate()


if __name__ == "__main__":
    unittest.main()
