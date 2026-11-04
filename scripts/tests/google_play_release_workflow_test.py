#!/usr/bin/env python3
"""Exercise the real Play phase policy and publisher with isolated transports.

All bundles, account observations and HTTP responses here are synthetic. These
tests prove local control flow, never Google approval or external delivery.
"""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import zipfile
from datetime import datetime, timedelta, timezone

ROOT = Path(__file__).resolve().parents[2]
AAB = "build/app/outputs/bundle/productionRelease/app-production-release.aab"
APK = "build/app/outputs/flutter-apk/app-production-release.apk"
PACKET = "docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json"

fixture_spec = importlib.util.spec_from_file_location(
    "android_metadata_fixtures", ROOT / "scripts/tests/native_artifact_metadata_test.py")
fixtures = importlib.util.module_from_spec(fixture_spec)
fixture_spec.loader.exec_module(fixtures)


def synthetic_bundle(path, permissions=('android.permission.RECEIVE_SMS',),
                     *, package='app.cool.mobile', version='1.2.4', code=23,
                     extra_module=False, wrong_name_id=False, duplicate_manifest=False,
                     permission_qualifier=False, compile_sdk=36, min_sdk=24, target_sdk=36,
                     receiver_name='.receiver_sms.CollectSmsReceiver', receiver_enabled=True,
                     receiver_exported=True, receiver_permission='android.permission.BROADCAST_SMS',
                     receiver_action='android.provider.Telephony.SMS_RECEIVED', application_enabled=True):
    """Build a tiny synthetic AAB with actual AAPT protobuf field encodings."""
    root = fixtures.metadata._one(fixtures.metadata._proto(
        fixtures.aab_manifest(package=package, name=version, code=code)), 1)

    def android_attr(name, value, resource, compiled=b''):
        return (fixtures.message(1, fixtures.ANDROID.encode()) + fixtures.message(2, name.encode())
                + fixtures.message(3, str(value).encode()) + fixtures.scalar(5, resource)
                + (fixtures.message(6, compiled) if compiled else b''))

    def integer(value):
        return fixtures.message(7, fixtures.scalar(6, value))

    def boolean(value):
        return fixtures.message(7, fixtures.scalar(8, int(value)))

    root += fixtures.message(4, android_attr('compileSdkVersion', compile_sdk, 16844146, integer(compile_sdk)))
    sdk = (fixtures.message(3, b'uses-sdk')
           + fixtures.message(4, android_attr('minSdkVersion', min_sdk, 16843276, integer(min_sdk)))
           + fixtures.message(4, android_attr('targetSdkVersion', target_sdk, 16843376, integer(target_sdk))))
    root += fixtures.message(5, fixtures.message(1, sdk))
    for index, permission in enumerate(permissions):
        tag, permission = permission if isinstance(permission, tuple) else ('uses-permission', permission)
        attr = (fixtures.message(1, fixtures.ANDROID.encode()) + fixtures.message(2, b'name')
                + fixtures.message(3, permission.encode())
                + fixtures.scalar(5, 1 if wrong_name_id and index == 0 else 16842755))
        qualifier = (fixtures.message(1, fixtures.ANDROID.encode()) + fixtures.message(2, b'maxSdkVersion')
                     + fixtures.message(3, b'22') + fixtures.scalar(5, 16843377))
        element = (fixtures.message(3, tag.encode()) + fixtures.message(4, attr)
                   + (fixtures.message(4, qualifier) if permission_qualifier and index == 0 else b''))
        root += fixtures.message(5, fixtures.message(1, element))
    action = fixtures.message(3, b'action') + fixtures.message(4, android_attr('name', receiver_action, 16842755))
    intent = fixtures.message(3, b'intent-filter') + fixtures.message(5, fixtures.message(1, action))
    receiver = (fixtures.message(3, b'receiver')
                + fixtures.message(4, android_attr('name', receiver_name, 16842755))
                + fixtures.message(4, android_attr('permission', receiver_permission, 16842758))
                + fixtures.message(4, android_attr('enabled', str(receiver_enabled).lower(), 16842766, boolean(receiver_enabled)))
                + fixtures.message(4, android_attr('exported', str(receiver_exported).lower(), 16842768, boolean(receiver_exported)))
                + fixtures.message(5, fixtures.message(1, intent)))
    app = (fixtures.message(3, b'application')
           + fixtures.message(4, android_attr('enabled', str(application_enabled).lower(), 16842766, boolean(application_enabled)))
           + fixtures.message(5, fixtures.message(1, receiver)))
    root += fixtures.message(5, fixtures.message(1, app))
    manifest = fixtures.message(1, root)
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('base/manifest/AndroidManifest.xml', manifest)
        if extra_module:
            archive.writestr('other/manifest/AndroidManifest.xml', manifest)
        if duplicate_manifest:
            archive.writestr('base/manifest/androidmanifest.xml', manifest)


class PlayWorkflowTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="collect-play-workflow-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for relative in ("scripts", "docs/release", ".cache", "fastlane/metadata/android/en-US/changelogs"):
            (self.root / relative).mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/google_play_production_upload.sh", self.root / "scripts")
        (self.root / "pubspec.yaml").write_text("name: synthetic_play_fixture\nversion: 1.2.4+23\n")
        (self.root / "fastlane/metadata/android/en-US/changelogs/23.txt").write_text("Synthetic fixture release notes.\n")
        for relative in (APK, AAB):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"SYNTHETIC TEST ARTIFACT ONLY " + relative.encode())
            os.utime(path, (time.time() - 5, time.time() - 5))
        self.aab_hash = hashlib.sha256((self.root / AAB).read_bytes()).hexdigest()
        self.apk_hash = hashlib.sha256((self.root / APK).read_bytes()).hexdigest()
        evidence = self.root / "docs/release/synthetic-console-capture.json"
        evidence.write_text('{"synthetic_fixture":true}\n')
        observed = {
            "status": "pass", "reviewer": "Synthetic test operator",
            "package_name": "app.cool.mobile", "artifact_version": "1.2.4+23",
            "aab_sha256": self.aab_hash, "apk_sha256": self.apk_hash,
            "observed_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "evidence_reference": "docs/release/synthetic-console-capture.json",
            "evidence_sha256": hashlib.sha256(evidence.read_bytes()).hexdigest(),
            "managed_publishing_enabled": True, "review_status": "approved",
            "production_countries": ["RW"],
        }
        surfaces = ("publishing_overview", "production_track", "app_content", "store_listing",
                    "deep_links", "android_vitals", "pre_launch_report", "app_integrity", "device_catalog")
        self.packet = {
            "app_content": {"permissions": {
                "production_permissions": ["android.permission.RECEIVE_SMS"],
                "sms_permissions_declaration_status": "required_pending_play_approval"}},
            "play_console_surfaces": {s: {"observation": copy.deepcopy(observed)} for s in surfaces},
        }
        self.save_packet()
        self.write_script("release_go_preflight.sh", '''#!/bin/bash
printf 'preflight\n' >> .cache/gates.log
exit "${TEST_PREFLIGHT_EXIT:-0}"
''')
        self.write_script("google_play_optimization_gate.sh", '''#!/bin/bash
printf 'gate %s\n' "$*" >> .cache/gates.log
if [[ "${TEST_CHANGE_AAB:-0}" == 1 ]]; then printf 'changed' >> build/app/outputs/bundle/productionRelease/app-production-release.aab; fi
if [[ "${TEST_CHANGE_PACKET:-0}" == 1 ]]; then printf '\n' >> docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json; fi
exit "${TEST_GATE_EXIT:-0}"
''')
        self.write_script("google_play_console_audit_packet.sh", '''#!/bin/bash
printf 'packet %s\n' "$*" >> .cache/gates.log
exit "${TEST_PACKET_EXIT:-0}"
''')
        transport = self.root / "synthetic_transport.rb"
        transport.write_text(r'''
require 'net/http'
require 'json'
require 'digest'
class Net::HTTP
  def self.start(address,port,*args,**options)
    raise 'Synthetic start requires a block' unless block_given?
    yield new(address,port)
  end
  def get(path)
    request(Net::HTTP::Get.new(path))
  end
  def request(request)
    if address == 'collect.ikanisa.com'
      return Class.new {
        def code; '200'; end
        def body; 'synthetic policy response'; end
        def [](_); 'application/json'; end
      }.new
    end
    raise 'Unexpected transport target' unless address == 'androidpublisher.googleapis.com'
    uri = request.uri
    body = request.body.to_s
    decoded = body.empty? || uri.path.end_with?('/bundles') ? nil : JSON.parse(body)
    File.open('.cache/transport.jsonl','a') { |f| f.puts(JSON.generate({method:request.method,path:uri.path,query:uri.query,body:decoded})) }
    payload = case
    when request.method == 'POST' && uri.path.end_with?('/edits')
      {'id'=>'synthetic-edit'}
    when request.method == 'GET' && uri.path.include?('/tracks/')
      JSON.parse(ENV.fetch('TEST_TRACK_JSON'))
    when request.method == 'GET' && uri.path.end_with?('/bundles')
      {'bundles'=>[{'versionCode'=>23,'sha256'=>ENV.fetch('TEST_REMOTE_SHA')}]}
    when request.method == 'POST' && uri.path.end_with?('/bundles')
      {'versionCode'=>ENV.fetch('TEST_UPLOAD_VERSION','23').to_i,'sha256'=>Digest::SHA256.hexdigest(body)}
    when request.method == 'PUT' && uri.path.include?('/tracks/')
      decoded
    when request.method == 'POST' && uri.path.end_with?(':commit')
      raise Net::ReadTimeout if ENV['TEST_COMMIT_TIMEOUT']=='1'
      {'id'=>'synthetic-edit'}
    when request.method == 'DELETE'
      {}
    else
      raise 'Unexpected synthetic request'
    end
    Struct.new(:code,:body).new('200',JSON.generate(payload))
  end
end
''')
        self.env = {"PATH": os.environ["PATH"], "RUBYOPT": "-r" + str(transport),
                    "ANDROID_PUBLISHER_ACCESS_TOKEN": "SYNTHETIC-DO-NOT-LOG-TOKEN",
                    "TEST_REMOTE_SHA": self.aab_hash,
                    "TEST_TRACK_JSON": json.dumps({"track": "production", "releases": []})}

    def write_script(self, name, source):
        path = self.root / "scripts" / name
        path.write_text(source)
        path.chmod(0o700)

    def save_packet(self):
        (self.root / PACKET).write_text(json.dumps(self.packet))

    def run_upload(self, *args, **env):
        self.save_packet()
        return subprocess.run(["bash", "scripts/google_play_production_upload.sh", *args, "--json"],
                              cwd=self.root, env=self.env | env, capture_output=True, text=True, timeout=20)

    def requests(self):
        path = self.root / ".cache/transport.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def track(self, status="draft", **extra):
        return json.dumps({"track": "production", "releases": [
            {"name": "existing unrelated rollout", "versionCodes": ["22"], "status": "inProgress", "userFraction": .1},
            {"name": "fixture target", "versionCodes": ["23"], "status": status,
             "releaseNotes": [{"language": "en-US", "text": "Already inspected fixture note"}], **extra}]})

    def phase_checks(self, phase):
        self.save_packet()
        source = (ROOT / "scripts/google_play_optimization_gate.sh").read_text()
        sms_policy = source[source.index("sms_declaration_status = console_audit_packet"):source.index('checks["android_app_links"]')]
        policy = sms_policy + source[source.index("required_console_surfaces = {"):source.index("blocked = checks.select")]
        prelude = r'''
require 'json'; require 'digest'; require 'time'
def check(status,message,extra={}); {'status'=>status,'message'=>message}.merge(extra); end
root=Dir.pwd; phase=ARGV.fetch(0); checks={}; pubspec=File.read('pubspec.yaml')
console_audit_packet=JSON.parse(File.read('docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json'))
apk={'exists'=>true,'path'=>File.join(root,'build/app/outputs/flutter-apk/app-production-release.apk')}
aab={'exists'=>true,'path'=>File.join(root,'build/app/outputs/bundle/productionRelease/app-production-release.aab')}
actual_apk_sha256=Digest::SHA256.file(apk['path']).hexdigest
actual_aab_sha256=Digest::SHA256.file(aab['path']).hexdigest
'''
        result = subprocess.run(["ruby", "-e", prelude + policy + "\nputs JSON.generate(checks)", phase],
                                cwd=self.root, env={"PATH": os.environ["PATH"]}, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def use_real_packet_validator(self):
        """Supply isolated fixture inputs for every unchanged packet check."""
        shutil.copy2(ROOT / "scripts/google_play_console_audit_packet.sh", self.root / "scripts")
        base = json.loads((ROOT / PACKET).read_text())
        base["play_console_surfaces"].update(self.packet["play_console_surfaces"])
        # Retain required audit prompts while adding the synthetic observations.
        for key, value in json.loads((ROOT / PACKET).read_text())["play_console_surfaces"].items():
            base["play_console_surfaces"][key].update(value)
        base["app_content"]["permissions"].update(self.packet["app_content"]["permissions"])
        base["target_release"].update({"version_name": "1.2.4", "version_code": 23,
                                       "apk_path": APK, "aab_path": AAB,
                                       "apk_sha256": self.apk_hash, "aab_sha256": self.aab_hash})
        assets = base["store_listing"]["assets"]
        for key in ("brand_icon_source", "play_store_icon"):
            relative = assets[key]
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        launcher = self.root / "fixture-launcher.png"
        launcher.write_bytes(b"SYNTHETIC LAUNCHER FIXTURE")
        assets["launcher_icon"] = launcher.name
        assets["launcher_icon_sha256"] = hashlib.sha256(launcher.read_bytes()).hexdigest()
        feature = self.root / "fixture-feature.png"
        feature.write_bytes(b"SYNTHETIC FEATURE FIXTURE")
        assets["feature_graphic"] = {"status": "approved_official_asset", "path": "fixture-feature.png",
                                     "sha256": hashlib.sha256(feature.read_bytes()).hexdigest()}
        screenshots = self.root / "fixture-screenshots"
        screenshots.mkdir()
        hashes = {}
        for number in range(2):
            path = screenshots / f"{number}.png"
            path.write_bytes(b"SYNTHETIC SCREENSHOT FIXTURE " + str(number).encode())
            hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        assets["phone_screenshots"] = {"status": "current_product_capture", "source": "synthetic_native_product_capture",
                                      "path": "fixture-screenshots", "minimum_required": 2, "sha256": hashes}
        self.packet = base
        self.save_packet()

    def run_fastlane(self, options, execute=False):
        shutil.copy2(ROOT / "fastlane/Fastfile", self.root / "fastlane/Fastfile")
        dsl = r'''
require 'json'
module UI; def self.user_error!(message); raise message; end; end
def default_platform(*); end
def desc(*); end
def platform(name); @platform=name; yield; end
def lane(name,&block); (@lanes||={})[[@platform,name]]=block; end
def sh(command)
  (@commands||=[]) << command
  if ENV['TEST_EXECUTE_LANE']=='1'
    raise 'Lane command failed' unless system(command,out:File::NULL,err:File::NULL)
  end
end
load 'fastlane/Fastfile'
options=JSON.parse(ARGV[0],symbolize_names:true)
@lanes.fetch([:android,:play_production_submit]).call(options)
puts JSON.generate(@commands)
'''
        return subprocess.run(["ruby", "-e", dsl, json.dumps(options)], cwd=self.root,
                              env=self.env | {"GOOGLE_PLAY_SERVICE_ACCOUNT_JSON": "synthetic",
                                              "TEST_EXECUTE_LANE": "1" if execute else "0"},
                              capture_output=True, text=True, timeout=20)

    def test_default_is_local_draft_preparation_without_network(self):
        result = self.run_upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual((data["phase"], data["release"]["status"]), ("prepare", "draft"))
        self.assertFalse(data["production_availability_verified"])
        self.assertEqual(self.requests(), [])

    def test_submit_requires_explicit_mutating_phase(self):
        for args in (("--submit",), ("--submit", "--phase", "prepare")):
            with self.subTest(args=args):
                result = self.run_upload(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("requires explicit --phase", result.stderr)
        self.assertEqual(self.requests(), [])

    def test_upload_is_draft_preserves_other_releases_and_never_touches_testing(self):
        previous = {"versionCodes": ["22"], "status": "inProgress", "userFraction": .15}
        result = self.run_upload("--submit", "--phase", "upload", TEST_TRACK_JSON=json.dumps({"track":"production","releases":[previous]}))
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "draft_committed")
        requests = self.requests()
        releases = next(r["body"]["releases"] for r in requests if r["method"] == "PUT")
        self.assertEqual(releases[0], previous)
        self.assertEqual(releases[1]["status"], "draft")
        self.assertTrue(all("/tracks/internal" not in r["path"] for r in requests))
        commit = next(r for r in requests if r["path"].endswith(":commit"))
        self.assertIn("changesNotSentForReview=true", commit["query"])
        self.assertIn("changesInReviewBehavior=ERROR_IF_IN_REVIEW", commit["query"])
        self.assertIsNone(commit["body"])
        self.assertNotIn("SYNTHETIC-DO-NOT-LOG-TOKEN", result.stdout + result.stderr)
        self.assertIn("gate --phase upload --json", (self.root / ".cache/gates.log").read_text())

    def test_preflight_and_gate_failure_prevent_any_publisher_request(self):
        for env in ({"TEST_PREFLIGHT_EXIT": "1"}, {"TEST_PACKET_EXIT": "99"}, {"TEST_GATE_EXIT": "99"}):
            with self.subTest(env=env):
                result = self.run_upload("--submit", "--phase", "upload", **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.requests(), [])

    def test_artifact_or_packet_change_during_gate_prevents_publisher_request(self):
        for env in ({"TEST_CHANGE_AAB": "1"}, {"TEST_CHANGE_PACKET": "1"}):
            with self.subTest(env=env):
                result = self.run_upload("--submit", "--phase", "upload", **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.requests(), [])

    def test_environment_cannot_force_completed_upload_or_internal_replacement(self):
        for env in ({"STATUS": "completed"}, {"REPLACE_INTERNAL_RESTRICTED_ARTIFACTS": "true"}, {"USER_FRACTION": ".2"}):
            with self.subTest(env=env):
                result = self.run_upload("--submit", "--phase", "upload", **env)
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.requests(), [])

    def test_review_uses_existing_draft_and_validates_remote_digest_without_reupload(self):
        result = self.run_upload("--submit", "--phase", "review", TEST_TRACK_JSON=self.track())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "review_change_committed")
        self.assertFalse(any(r["method"] == "POST" and r["path"].endswith("/bundles") for r in self.requests()))
        commit = next(r for r in self.requests() if r["path"].endswith(":commit"))
        self.assertNotIn("changesNotSentForReview", commit["query"])

    def test_review_rejects_wrong_remote_bundle_and_repeated_review(self):
        for env in ({"TEST_TRACK_JSON": self.track(), "TEST_REMOTE_SHA": "0" * 64},
                    {"TEST_TRACK_JSON": self.track("completed")}):
            with self.subTest(env=env):
                result = self.run_upload("--submit", "--phase", "review", **env)
                self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(r["method"] == "PUT" or r["path"].endswith(":commit") for r in self.requests()))

    def test_rollout_requires_fraction_or_explicit_full_choice_and_sms_approval(self):
        result = self.run_upload("--submit", "--phase", "rollout")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("explicit USER_FRACTION", result.stderr)
        for fraction in ("0", "1", "NaN", "Infinity", "-0.1"):
            result = self.run_upload("--submit", "--phase", "rollout", USER_FRACTION=fraction)
            self.assertNotEqual(result.returncode, 0)
        result = self.run_upload("--submit", "--phase", "rollout", "--full-rollout", TEST_TRACK_JSON=self.track("completed"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sms_declaration_invalid_for_phase", result.stdout)
        self.assertEqual(self.requests(), [])

    def test_explicit_approved_full_rollout_is_the_only_rollout_completed_choice(self):
        self.packet["app_content"]["permissions"]["sms_permissions_declaration_status"] = "approved_for_core_functionality"
        result = self.run_upload("--submit", "--phase", "rollout", "--full-rollout", TEST_TRACK_JSON=self.track("inProgress", userFraction=.05))
        self.assertEqual(result.returncode, 0, result.stderr)
        release = next(r["body"]["releases"][-1] for r in self.requests() if r["method"] == "PUT")
        self.assertEqual(release["status"], "completed")
        self.assertNotIn("userFraction", release)
        self.assertFalse(json.loads(result.stdout)["production_availability_verified"])

    def test_review_and_rollout_preserve_inspected_remote_metadata(self):
        self.packet["app_content"]["permissions"]["sms_permissions_declaration_status"] = "approved_for_core_functionality"
        for phase, status, args in (("review", "draft", []), ("rollout", "inProgress", ["--full-rollout"])):
            with self.subTest(phase=phase):
                remote = json.loads(self.track(status))
                expected = remote["releases"][-1]
                result = self.run_upload("--submit", "--phase", phase, *args,
                                         TEST_TRACK_JSON=json.dumps(remote),
                                         RELEASE_NAME="Unreviewed injected name", RELEASE_NOTES="Unreviewed injected note")
                self.assertEqual(result.returncode, 0, result.stderr)
                release = [r["body"]["releases"][-1] for r in self.requests() if r["method"] == "PUT"][-1]
                self.assertEqual(release["name"], expected["name"])
                self.assertEqual(release["releaseNotes"], expected["releaseNotes"])

    def test_mutations_remain_pinned_to_package_track_and_canonical_artifact(self):
        for env in ({"PACKAGE_NAME": "other.app"}, {"TRACK": "internal"}, {"AAB_PATH": "pubspec.yaml"}):
            with self.subTest(env=env):
                result = self.run_upload("--submit", "--phase", "upload", **env)
                self.assertNotEqual(result.returncode, 0)
        path = self.root / AAB
        path.unlink(); path.symlink_to(self.root / APK)
        result = self.run_upload("--submit", "--phase", "upload")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.requests(), [])

    def test_upload_mismatched_version_is_rejected_before_track_update(self):
        result = self.run_upload("--submit", "--phase", "upload", TEST_UPLOAD_VERSION="24")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(r["method"] == "PUT" or r["path"].endswith(":commit") for r in self.requests()))

    def test_approved_staged_rollout_keeps_rwanda_scope_and_requires_live_readback(self):
        self.packet["app_content"]["permissions"]["sms_permissions_declaration_status"] = "approved_for_core_functionality"
        result = self.run_upload("--submit", "--phase", "rollout", USER_FRACTION=".05", TEST_TRACK_JSON=self.track("completed"))
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertFalse(data["production_availability_verified"])
        release = next(r["body"]["releases"][-1] for r in self.requests() if r["method"] == "PUT")
        self.assertEqual((release["status"], release["userFraction"]), ("inProgress", .05))
        self.assertEqual(release["countryTargeting"], {"countries": ["RW"], "includeRestOfWorld": False})

    def test_lost_commit_response_is_unknown_and_is_not_deleted_or_retried(self):
        result = self.run_upload("--submit", "--phase", "upload", TEST_COMMIT_TIMEOUT="1")
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "commit_outcome_unknown")
        self.assertTrue(data["reconcile_before_retry"])
        self.assertEqual(sum(r["path"].endswith(":commit") for r in self.requests()), 1)
        self.assertFalse(any(r["method"] == "DELETE" for r in self.requests()))

    def test_prepare_and_upload_defer_console_audit_and_allow_pending_sms_decision(self):
        self.packet["play_console_surfaces"] = {}
        for phase in ("prepare", "upload"):
            checks = self.phase_checks(phase)
            self.assertEqual(checks["play_console_surface_audit_required"]["status"], "deferred")
            self.assertEqual(checks["restricted_sms_declaration"]["status"], "pass")

    def test_review_accepts_current_captured_evidence_while_sms_decision_pending(self):
        del self.packet["play_console_surfaces"]["android_vitals"]
        checks = self.phase_checks("review")
        self.assertEqual(checks["play_console_surface_audit_required"]["status"], "pass")
        self.assertEqual(checks["restricted_sms_declaration"]["status"], "pass")

    def test_review_blocks_missing_managed_publishing_changed_country_and_missing_capture(self):
        for field, value, expected in (("managed_publishing_enabled", False, "managed_publishing"),
                                       ("production_countries", ["RW", "UG"], "production_countries")):
            with self.subTest(field=field):
                old = self.packet["play_console_surfaces"]["publishing_overview"]["observation"][field]
                self.packet["play_console_surfaces"]["publishing_overview"]["observation"][field] = value
                checks = self.phase_checks("review")
                self.assertIn(expected, checks["play_console_surface_audit_required"]["blockers"])
                self.packet["play_console_surfaces"]["publishing_overview"]["observation"][field] = old
        del self.packet["play_console_surfaces"]["pre_launch_report"]["observation"]
        checks = self.phase_checks("review")
        self.assertIn("pre_launch_report", checks["play_console_surface_audit_required"]["blockers"])

    def test_phase_evidence_rejects_wrong_hash_stale_future_or_changed_capture(self):
        observation = self.packet["play_console_surfaces"]["publishing_overview"]["observation"]
        original = copy.deepcopy(observation)
        mutations = (("aab_sha256", "0" * 64),
                     ("observed_at", (datetime.now(timezone.utc) - timedelta(days=2)).isoformat().replace("+00:00", "Z")),
                     ("observed_at", (datetime.now(timezone.utc) + timedelta(days=1)).isoformat().replace("+00:00", "Z")),
                     ("evidence_sha256", "0" * 64), ("evidence_reference", "../outside-capture.json"))
        for field, value in mutations:
            with self.subTest(field=field, value=value):
                observation.clear(); observation.update(original); observation[field] = value
                checks = self.phase_checks("review")
                self.assertEqual(checks["play_console_surface_audit_required"]["status"], "blocked")

    def test_rollout_needs_current_google_and_sms_approval(self):
        self.packet["play_console_surfaces"]["publishing_overview"]["observation"]["review_status"] = "in_review"
        checks = self.phase_checks("rollout")
        self.assertIn("google_review", checks["play_console_surface_audit_required"]["blockers"])
        self.assertEqual(checks["restricted_sms_declaration"]["status"], "blocked")
        self.packet["play_console_surfaces"]["publishing_overview"]["observation"]["review_status"] = "approved"
        self.packet["app_content"]["permissions"]["sms_permissions_declaration_status"] = "approved_for_core_functionality"
        checks = self.phase_checks("rollout")
        self.assertTrue(all(c["status"] == "pass" for c in checks.values()))

    def test_api_35_cannot_pass_current_target_api_gate(self):
        source = (ROOT / "scripts/google_play_optimization_gate.sh").read_text()
        policy = source[source.index('checks["target_api"] ='):source.index('checks["sms_device_compatibility"]')]
        for sdk, expected in ((35, "blocked"), (36, "pass")):
            code = "require 'json'; def check(s,m,e={});{'status'=>s}.merge(e);end;checks={};badging={'status'=>0};package=JSON.parse(ARGV[0]);\n" + policy + "\nputs JSON.generate(checks)"
            result = subprocess.run(["ruby", "-e", code, json.dumps({"compile_sdk": sdk, "target_sdk": sdk})],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["target_api"]["status"], expected)

    def test_failed_or_malformed_aapt_badging_cannot_pass_release_checks(self):
        source = (ROOT / "scripts/google_play_optimization_gate.sh").read_text()
        parser = source[source.index("def badging_integer"):source.index("# Select one explicit")]
        assignment = source[source.index("package = parse_badging("):source.index("zipalign_16k =")]
        identity = source[source.index('checks["package_identity"] ='):source.index('checks["sms_device_compatibility"]')]
        permissions = source[source.index('checks["production_permissions"] ='):source.index("sms_declaration_status =")]
        code = r'''
require 'json'; require 'digest'
def check(status,message,extra={}); {'status'=>status}.merge(extra); end
''' + parser + r'''
badging=JSON.parse(ARGV.fetch(0));checks={}
apk_tree={'status'=>0,'stdout'=>"  E: manifest (line=1)\n    E: uses-permission (line=2)\n      A: android:name(0x01010003)=\"android.permission.RECEIVE_SMS\" (Raw: \"android.permission.RECEIVE_SMS\")\n"}
''' + assignment + r'''
restricted_sms=%w[android.permission.READ_SMS android.permission.RECEIVE_SMS android.permission.SEND_SMS android.permission.BROADCAST_SMS android.permission.READ_CALL_LOG]
main_restricted=['android.permission.RECEIVE_SMS'];expected_apk_restricted=main_restricted
production_declares_receive=true;production_declares_read=false;receiver_declares_receive=true;receiver_declares_read=true;sms_receiver_protected=true
apk_restricted=Array(package['permissions']) & restricted_sms
aab={'path'=>'build/app/outputs/bundle/productionRelease/app-production-release.aab'}
actual_aab_sha256=Digest::SHA256.file(aab['path']).hexdigest
apk_badging_stable=true;apk_badging_after_sha256='synthetic-apk-hash';actual_apk_sha256=apk_badging_after_sha256
aab_permissions={'status'=>'pass','artifact_sha256'=>actual_aab_sha256,'restricted_permissions'=>expected_apk_restricted,
 'actual'=>{'package'=>'app.cool.mobile','version_name'=>'1.2.4','version_code'=>23},
 'runtime'=>{'compile_sdk'=>36,'min_sdk'=>24,'target_sdk'=>36,'sms_receiver'=>'protected_enabled_exported_with_sms_received_filter'}}
''' + identity + permissions + "\nputs JSON.generate(checks)"
        valid = ("package: name='app.cool.mobile' versionCode='23' versionName='1.2.4' compileSdkVersion='36'\n"
                 "sdkVersion:'24'\ntargetSdkVersion:'36'\nuses-permission: name='android.permission.RECEIVE_SMS'\n")
        cases = (
            (0, valid, ("pass", "pass", "pass")),
            (23, valid, ("fail", "blocked", "fail")),
            (0, valid.replace("versionCode='23'", "versionCode='23junk'"), ("fail", "pass", "fail")),
            (0, valid.replace("compileSdkVersion='36'", "compileSdkVersion='36junk'"), ("pass", "blocked", "fail")),
            (0, valid.replace("targetSdkVersion:'36'", "targetSdkVersion:'36junk'"), ("pass", "blocked", "fail")),
            (0, valid + "uses-permission: name='android.permission.READ_CALL_LOG'\n", ("pass", "pass", "fail")),
            (0, valid + "uses-permission: name='android.permission.READ_SMS'\n", ("pass", "pass", "fail")),
            (0, valid + "uses-permission-sdk-23: name='android.permission.READ_SMS'\n", ("pass", "pass", "fail")),
            (0, valid + "uses-permission-sdk-m: name='android.permission.READ_CALL_LOG'\n", ("pass", "pass", "fail")),
        )
        for status, stdout, expected in cases:
            with self.subTest(status=status, stdout=stdout):
                result = subprocess.run(["ruby", "-e", code, json.dumps({"status": status, "stdout": stdout})],
                                        cwd=self.root, env=self.env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                checks = json.loads(result.stdout)
                self.assertEqual(tuple(checks[name]["status"] for name in
                                       ("package_identity", "target_api", "production_permissions")), expected)

    def test_build_tools_resolver_requires_one_sdk_and_exact_version(self):
        source = (ROOT / "scripts/google_play_optimization_gate.sh").read_text()
        resolver = source[source.index("def resolve_android_build_tools"):source.index("\npubspec =")]
        code = "require 'digest'; require 'json';\n" + resolver + "\nputs JSON.generate(resolve_android_build_tools(Dir.pwd))"
        sdk = self.root / "android-sdk"
        tools = sdk / "build-tools" / "36.0.0"
        tools.mkdir(parents=True)
        (tools / "source.properties").write_text("Pkg.Revision=36.0.0\n")
        for name in ("aapt", "zipalign"):
            tool = tools / name
            tool.write_text("#!/bin/sh\nexit 0\n")
            tool.chmod(0o700)

        def resolve(**overrides):
            env = self.env | {"ANDROID_HOME": str(sdk), "ANDROID_SDK_ROOT": str(sdk)} | overrides
            result = subprocess.run(["ruby", "-e", code], cwd=self.root, env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)

        result = resolve()
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["version"], "36.0.0")
        self.assertEqual(result["aapt_sha256"], hashlib.sha256((tools / "aapt").read_bytes()).hexdigest())
        self.assertEqual(result["zipalign_sha256"], hashlib.sha256((tools / "zipalign").read_bytes()).hexdigest())
        other = self.root / "other-sdk"
        other.mkdir()
        shutil.copytree(sdk / "build-tools", other / "build-tools")
        self.assertEqual(resolve(ANDROID_SDK_ROOT=str(other))["reason"], "conflicting_sdk_roots")
        self.assertEqual(resolve(COLLECT_ANDROID_BUILD_TOOLS_VERSION="35.0.0")["reason"], "invalid_build_tools_version")
        self.assertEqual(resolve(COLLECT_ANDROID_BUILD_TOOLS_VERSION="36.1.0")["reason"], "build_tools_unavailable")
        redirected = self.root / "redirected-sdk"
        outside = self.root / "outside-build-tools"
        redirected.mkdir()
        outside.mkdir()
        (redirected / "build-tools").symlink_to(outside, target_is_directory=True)
        self.assertEqual(resolve(ANDROID_HOME=str(redirected), ANDROID_SDK_ROOT=str(redirected))["reason"],
                         "build_tools_root_outside_sdk")

        properties = self.root / "android/local.properties"
        properties.parent.mkdir(exist_ok=True)
        properties.write_text(f"# synthetic Gradle SDK selection\nsdk.dir={sdk}\n")
        local_result = resolve()
        self.assertEqual(local_result["status"], "pass")
        self.assertEqual(local_result["local_properties_sha256"], hashlib.sha256(properties.read_bytes()).hexdigest())
        self.assertEqual(resolve(ANDROID_HOME="", ANDROID_SDK_ROOT="")["sdk_root"], str(sdk.resolve()))
        properties.write_text(f"sdk.dir={os.path.relpath(sdk, properties.parent)}\n")
        self.assertEqual(resolve()["status"], "pass")
        for tilde in ("~", "~collect_nonexistent"):
            literal = properties.parent / tilde
            literal.mkdir()
            (literal / "sdk").symlink_to(sdk, target_is_directory=True)
            properties.write_text(f"sdk.dir={tilde}/sdk\n")
            self.assertEqual(resolve()["sdk_root"], str(sdk.resolve()))
        outside = self.root / "sdk-link-target"
        (outside / "child").mkdir(parents=True)
        (outside / "sdk").symlink_to(sdk, target_is_directory=True)
        (properties.parent / "link").symlink_to(outside / "child", target_is_directory=True)
        (properties.parent / "sdk").symlink_to(other, target_is_directory=True)
        properties.write_text("sdk.dir=link/../sdk\n")
        self.assertEqual(resolve(ANDROID_HOME="", ANDROID_SDK_ROOT="")["sdk_root"], str(sdk.resolve()))
        properties.write_text(f"sdk.dir={other}\n")
        self.assertEqual(resolve()["reason"], "conflicting_sdk_roots")
        properties.write_text(f"sdk.dir={sdk}\nsdk.dir={other}\n")
        self.assertEqual(resolve()["reason"], "local_properties_ambiguous")
        properties.write_text(f"sdk.dir={sdk}\ns\\u0064k.dir={other}\n")
        self.assertEqual(resolve()["reason"], "local_properties_unsupported")
        properties.write_text(f"android.dir={other}\n")
        self.assertEqual(resolve()["reason"], "local_properties_unsupported")
        properties.write_bytes(b"")
        empty_result = resolve()
        self.assertEqual(empty_result["status"], "pass")
        self.assertEqual(empty_result["local_properties_sha256"], hashlib.sha256(b"").hexdigest())
        properties.unlink()
        relative_sdk = os.path.relpath(sdk, properties.parent)
        self.assertEqual(resolve(ANDROID_HOME=relative_sdk, ANDROID_SDK_ROOT=relative_sdk)["sdk_root"], str(sdk.resolve()))
        self.assertEqual(resolve(ANDROID_HOME="~/sdk", ANDROID_SDK_ROOT="~collect_nonexistent/sdk")["sdk_root"], str(sdk.resolve()))
        self.assertEqual(resolve(ANDROID_HOME="", ANDROID_SDK_ROOT="")["reason"], "missing_sdk_root")
        os.mkfifo(properties)
        self.assertEqual(resolve()["reason"], "local_properties_unavailable")
        properties.unlink()
        properties.symlink_to(self.root / "missing-local-properties")
        self.assertEqual(resolve()["reason"], "local_properties_unavailable")
        properties.unlink()
        (tools / "source.properties").write_text("Pkg.Revision=36.1.0\n")
        self.assertEqual(resolve()["reason"], "build_tools_revision_mismatch")

    def test_full_play_gate_refuses_failed_aapt_with_plausible_output(self):
        shutil.copy2(ROOT / "scripts/google_play_optimization_gate.sh", self.root / "scripts")
        shutil.copy2(ROOT / "scripts/android_manifest_permissions.rb", self.root / "scripts")
        qa = self.root / 'scripts/qa'
        qa.mkdir()
        for name in ('android_aab_permissions.py', 'native_artifact_metadata.py'):
            shutil.copy2(ROOT / 'scripts/qa' / name, qa)
        (qa / 'native_build_config.py').write_text(
            "import pathlib,sys\npathlib.Path('.cache/candidate-mode.log').write_text(' '.join(sys.argv[1:]))\nsys.exit(1)\n")
        synthetic_bundle(self.root / AAB)
        sdk = self.root / "android-sdk"
        tools = sdk / "build-tools" / "36.0.0"
        tools.mkdir(parents=True)
        (tools / "source.properties").write_text("Pkg.Revision=36.0.0\n")
        (tools / "aapt").write_text('#!/bin/sh\nif [ "${FAKE_AAPT_CHANGE_APK:-0}" = 1 ]; then printf changed >> "$3"; fi\nif [ "$2" = xmltree ]; then printf "%s" "$FAKE_AAPT_XML"; else printf "%s" "$FAKE_AAPT_STDOUT"; fi\nexit "$FAKE_AAPT_RC"\n')
        (tools / "zipalign").write_text("#!/bin/sh\nexit 0\n")
        for name in ("aapt", "zipalign"):
            (tools / name).chmod(0o700)
        android_ns = 'xmlns:android="http://schemas.android.com/apk/res/android"'
        receiver = ('<application><receiver android:name="app.cool.mobile.receiver_sms.CollectSmsReceiver" '
                    'android:permission="android.permission.BROADCAST_SMS"/></application>')
        permission = '<uses-permission android:name="android.permission.RECEIVE_SMS"/>'
        feature = '<uses-feature android:name="android.hardware.telephony" android:required="false"/>'
        manifests = {
            "main": f"<manifest {android_ns}>{permission}{feature}{receiver}</manifest>",
            "production": f"<manifest {android_ns}/>",
            "internal_receiver": (ROOT / 'android/app/src/internal_receiver/AndroidManifest.xml').read_text(),
        }
        for flavor, content in manifests.items():
            path = self.root / "android/app/src" / flavor / "AndroidManifest.xml"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        valid = ("package: name='app.cool.mobile' versionCode='23' versionName='1.2.4' compileSdkVersion='36'\n"
                 "sdkVersion:'24'\ntargetSdkVersion:'36'\nuses-permission: name='android.permission.RECEIVE_SMS'\n")
        self.env['FAKE_AAPT_XML'] = ('  E: manifest (line=1)\n    E: uses-permission (line=2)\n'
                                     '      A: android:name(0x01010003)="android.permission.RECEIVE_SMS" '
                                     '(Raw: "android.permission.RECEIVE_SMS")\n')
        for exit_code, expected in ((0, ("pass", "pass", "pass")), (23, ("fail", "blocked", "fail"))):
            with self.subTest(exit_code=exit_code):
                env = self.env | {"ANDROID_HOME": str(sdk), "ANDROID_SDK_ROOT": str(sdk), "TMPDIR": str(self.root),
                                  "FAKE_AAPT_STDOUT": valid, "FAKE_AAPT_RC": str(exit_code)}
                result = subprocess.run(["bash", "scripts/google_play_optimization_gate.sh", "--json", "--phase", "prepare"],
                                        cwd=self.root, env=env, capture_output=True, text=True, timeout=30)
                self.assertIn(result.returncode, (1, 99), result.stderr)  # unrelated synthetic release gates remain incomplete
                checks = json.loads(result.stdout)["checks"]
                self.assertEqual(checks["android_build_tools"]["status"], "pass")
                self.assertEqual(tuple(checks[name]["status"] for name in
                                       ("package_identity", "target_api", "production_permissions")), expected)
                self.assertIn('--store-candidate', (self.root / '.cache/candidate-mode.log').read_text())

        # The actual internal flavor requests READ_SMS. A production APK with
        # the expected permission still cannot compensate for a bad AAB.
        for aab_kwargs, aapt_suffix in (
                ({'permissions': ('android.permission.RECEIVE_SMS', 'android.permission.READ_SMS')}, ''),
                ({'extra_module': True}, ''),
                ({'permission_qualifier': True}, ''),
                ({'min_sdk': 23}, ''),
                ({'target_sdk': 37}, ''),
                ({'receiver_exported': False}, ''),
                ({}, "uses-permission: name='android.permission.READ_CALL_LOG'\n"),
                ({}, "uses-permission-sdk-23: name='android.permission.READ_SMS'\n")):
            with self.subTest(aab_kwargs=aab_kwargs, aapt_suffix=aapt_suffix):
                synthetic_bundle(self.root / AAB, **aab_kwargs)
                env = self.env | {'ANDROID_HOME': str(sdk), 'ANDROID_SDK_ROOT': str(sdk), 'TMPDIR': str(self.root),
                                  'FAKE_AAPT_STDOUT': valid + aapt_suffix, 'FAKE_AAPT_RC': '0'}
                result = subprocess.run(['bash', 'scripts/google_play_optimization_gate.sh', '--json', '--phase', 'prepare'],
                                        cwd=self.root, env=env, capture_output=True, text=True, timeout=30)
                self.assertIn(result.returncode, (1, 99), result.stderr)
                self.assertEqual(json.loads(result.stdout)['checks']['production_permissions']['status'], 'fail')

        synthetic_bundle(self.root / AAB)
        env = self.env | {'ANDROID_HOME': str(sdk), 'ANDROID_SDK_ROOT': str(sdk), 'TMPDIR': str(self.root),
                          'FAKE_AAPT_STDOUT': valid, 'FAKE_AAPT_RC': '0',
                          'FAKE_AAPT_XML': self.env['FAKE_AAPT_XML'] +
                          '      A: android:requiredFeature(0x01010554)="example.feature" (Raw: "example.feature")\n'}
        result = subprocess.run(['bash', 'scripts/google_play_optimization_gate.sh', '--json', '--phase', 'prepare'],
                                cwd=self.root, env=env, capture_output=True, text=True, timeout=30)
        self.assertIn(result.returncode, (1, 99), result.stderr)
        self.assertEqual(json.loads(result.stdout)['checks']['production_permissions']['status'], 'fail')

        synthetic_bundle(self.root / AAB)
        env = self.env | {'ANDROID_HOME': str(sdk), 'ANDROID_SDK_ROOT': str(sdk), 'TMPDIR': str(self.root),
                          'FAKE_AAPT_STDOUT': valid, 'FAKE_AAPT_RC': '0', 'FAKE_AAPT_CHANGE_APK': '1'}
        result = subprocess.run(['bash', 'scripts/google_play_optimization_gate.sh', '--json', '--phase', 'prepare'],
                                cwd=self.root, env=env, capture_output=True, text=True, timeout=30)
        self.assertIn(result.returncode, (1, 99), result.stderr)
        checks = json.loads(result.stdout)['checks']
        self.assertEqual(checks['package_identity']['status'], 'fail')
        self.assertEqual(checks['production_permissions']['status'], 'fail')

        synthetic_bundle(self.root / AAB)
        # A forged or stale inspection for a different bundle must not count.
        (qa / 'android_aab_permissions.py').write_text("""import json
print(json.dumps({'status':'pass','artifact_sha256':'0'*64,'restricted_permissions':['android.permission.RECEIVE_SMS'],
                  'actual':{'package':'app.cool.mobile','version_name':'1.2.4','version_code':23},
                  'runtime':{'compile_sdk':36,'min_sdk':24,'target_sdk':36,'sms_receiver':'protected_enabled_exported_with_sms_received_filter'}}))
""")
        env = self.env | {'ANDROID_HOME': str(sdk), 'ANDROID_SDK_ROOT': str(sdk), 'TMPDIR': str(self.root),
                          'FAKE_AAPT_STDOUT': valid, 'FAKE_AAPT_RC': '0'}
        result = subprocess.run(['bash', 'scripts/google_play_optimization_gate.sh', '--json', '--phase', 'prepare'],
                                cwd=self.root, env=env, capture_output=True, text=True, timeout=30)
        self.assertIn(result.returncode, (1, 99), result.stderr)
        self.assertEqual(json.loads(result.stdout)['checks']['production_permissions']['status'], 'fail')

    def test_aab_permissions_bind_production_identity_and_artifact(self):
        aab = self.root / AAB
        inspector = ROOT / 'scripts/qa/android_aab_permissions.py'

        def inspect(**kwargs):
            synthetic_bundle(aab, **kwargs)
            result = subprocess.run(['python3', str(inspector), '--artifact', str(aab),
                                     '--pubspec', str(self.root / 'pubspec.yaml')],
                                    env={'PATH': os.environ['PATH'], 'PYTHONDONTWRITEBYTECODE': '1'},
                                    capture_output=True, text=True, timeout=10)
            return result.returncode, json.loads(result.stdout)

        code, result = inspect()
        self.assertEqual(code, 0)
        self.assertEqual(result['status'], 'pass')
        self.assertEqual(result['artifact_sha256'], hashlib.sha256(aab.read_bytes()).hexdigest())
        self.assertEqual(result['actual'], {'package': 'app.cool.mobile', 'version_name': '1.2.4',
                                           'version_code': 23})
        self.assertEqual(result['runtime'], {'compile_sdk': 36, 'min_sdk': 24, 'target_sdk': 36,
                                            'sms_receiver': 'protected_enabled_exported_with_sms_received_filter'})
        self.assertFalse(result['signature_or_release_approval'])
        cases = (
            {'permissions': ('android.permission.RECEIVE_SMS', 'android.permission.READ_SMS')},
            {'permissions': ('android.permission.RECEIVE_SMS', ('uses-permission-sdk-23', 'android.permission.READ_SMS'))},
            {'permissions': ('android.permission.RECEIVE_SMS', 'android.permission.READ_CALL_LOG')},
            {'permissions': ('android.permission.RECEIVE_SMS', 'android.permission.RECEIVE_WAP_PUSH')},
            {'permissions': ()},
            {'permissions': ('android.permission.RECEIVE_SMS', 'android.permission.RECEIVE_SMS')},
            {'permissions': (('uses-permission-sdk-23', 'android.permission.RECEIVE_SMS'),)},
            {'package': 'app.cool.mobile.receiver'},
            {'version': '1.2.3'},
            {'code': 22},
            {'compile_sdk': 35},
            {'min_sdk': 37},
            {'target_sdk': 35},
            {'receiver_name': '.receiver_sms.OtherReceiver'},
            {'receiver_enabled': False},
            {'receiver_exported': False},
            {'receiver_permission': 'android.permission.INTERNET'},
            {'receiver_action': 'android.intent.action.BOOT_COMPLETED'},
            {'application_enabled': False},
            {'extra_module': True},
            {'wrong_name_id': True},
            {'permission_qualifier': True},
            {'duplicate_manifest': True},
        )
        for case in cases:
            with self.subTest(case=case):
                code, result = inspect(**case)
                self.assertEqual(code, 1)
                self.assertEqual(result['status'], 'fail')

        aab.write_bytes(b'NOT A BUNDLE')
        failed = subprocess.run(['python3', str(inspector), '--artifact', str(aab),
                                 '--pubspec', str(self.root / 'pubspec.yaml')],
                                env={'PATH': os.environ['PATH'], 'PYTHONDONTWRITEBYTECODE': '1'},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(json.loads(failed.stdout)['status'], 'fail')

    def test_sdk_generated_synthetic_manifests_match_permission_readers(self):
        # This compiles only a temporary synthetic manifest, never the app.
        sdk = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
                   or str(Path.home() / 'Library/Android/sdk'))
        tools = sdk / 'build-tools/36.0.0'
        aapt2, aapt, android_jar = tools / 'aapt2', tools / 'aapt', sdk / 'platforms/android-36/android.jar'
        if not all(path.is_file() for path in (aapt2, aapt, android_jar)):
            self.skipTest('Android SDK 36 and Build Tools 36.0.0 are needed for the synthetic manifest fixture')
        inspector = ROOT / 'scripts/qa/android_aab_permissions.py'
        source = (ROOT / 'scripts/google_play_optimization_gate.sh').read_text()
        parser = source[source.index('def badging_integer'):source.index('# Select one explicit')]
        env = {'PATH': os.environ['PATH'], 'HOME': str(self.root), 'TMPDIR': str(self.root),
               'PYTHONDONTWRITEBYTECODE': '1'}
        cases = (
            ('plain', '', '', True, False, {}),
            ('explicit_true', '', '', True, False, {'app_enabled': 'true', 'receiver_enabled': 'true'}),
            ('read', '', '<uses-permission-sdk-23 android:name="android.permission.READ_SMS"/>', True, True, {}),
            ('maximum', ' android:maxSdkVersion="22"', '', False, False, {}),
            ('minimum', ' android:minSdkVersion="35"', '', False, False, {}),
            ('required', ' android:requiredFeature="example.feature"', '', False, False, {}),
            ('forbidden', ' android:requiredNotFeature="example.feature"', '', False, False, {}),
            ('flags', ' android:usesPermissionFlags="neverForLocation"', '', False, False, {}),
            ('app_disabled', '', '', True, False, {'app_enabled': 'false'}),
            ('receiver_disabled', '', '', True, False, {'receiver_enabled': 'false'}),
            ('receiver_unexported', '', '', True, False, {'exported': 'false'}),
            ('receiver_unprotected', '', '', True, False, {'permission': 'android.permission.INTERNET'}),
            ('receiver_wrong_action', '', '', True, False, {'action': 'android.intent.action.BOOT_COMPLETED'}),
            ('receiver_conditional_filter', '', '', True, False, {'filter_extra': '<category android:name="example.category"/>'}),
            ('old_target', '', '', True, False, {'target': '35'}),
        )
        for label, qualifier, extra, unqualified, add_read, overrides in cases:
            with self.subTest(case=label):
                app_enabled = (' android:enabled="' + overrides['app_enabled'] + '"') if 'app_enabled' in overrides else ''
                receiver_enabled = (' android:enabled="' + overrides['receiver_enabled'] + '"') if 'receiver_enabled' in overrides else ''
                manifest = self.root / 'SyntheticManifest.xml'
                manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
                                    'package="app.cool.mobile" android:versionCode="23" android:versionName="1.2.4">'
                                    '<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="' + overrides.get('target', '36') + '"/>'
                                    '<uses-permission android:name="android.permission.RECEIVE_SMS"' + qualifier + '/>' + extra +
                                    '<application android:label="Synthetic"' + app_enabled + '>'
                                    '<receiver android:name=".receiver_sms.CollectSmsReceiver" '
                                    'android:exported="' + overrides.get('exported', 'true') + '" android:permission="' +
                                    overrides.get('permission', 'android.permission.BROADCAST_SMS') + '"' + receiver_enabled + '>'
                                    '<intent-filter><action android:name="' + overrides.get('action', 'android.provider.Telephony.SMS_RECEIVED') + '"/>' +
                                    overrides.get('filter_extra', '') +
                                    '</intent-filter></receiver></application></manifest>')
                linked = self.root / 'synthetic-proto.zip'
                subprocess.run([str(aapt2), 'link', '--proto-format', '-I', str(android_jar),
                                '--manifest', str(manifest), '-o', str(linked)], cwd=self.root, env=env,
                               check=True, capture_output=True, timeout=20)
                with zipfile.ZipFile(linked) as archive:
                    compiled = archive.read('AndroidManifest.xml')
                with zipfile.ZipFile(self.root / AAB, 'w') as archive:
                    archive.writestr('base/manifest/AndroidManifest.xml', compiled)
                result = subprocess.run(['python3', str(inspector), '--artifact', str(self.root / AAB),
                                         '--pubspec', str(self.root / 'pubspec.yaml')], cwd=self.root, env=env,
                                        capture_output=True, text=True, timeout=10)
                expected_code = 0 if label in ('plain', 'explicit_true') else 1
                self.assertEqual(result.returncode, expected_code, result.stdout + result.stderr)
                self.assertEqual(json.loads(result.stdout)['status'], 'pass' if expected_code == 0 else 'fail')

                apk = self.root / 'synthetic.apk'
                subprocess.run([str(aapt2), 'link', '-I', str(android_jar), '--manifest', str(manifest),
                                '-o', str(apk)], cwd=self.root, env=env, check=True, capture_output=True, timeout=20)
                badging = subprocess.run([str(aapt), 'dump', 'badging', str(apk)], cwd=self.root, env=env,
                                        check=True, capture_output=True, text=True, timeout=10)
                tree = subprocess.run([str(aapt), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'],
                                      cwd=self.root, env=env, check=True, capture_output=True, text=True, timeout=10)
                parsed = subprocess.run(['ruby', '-e', "require 'json';\n" + parser +
                                         "\ndata=JSON.parse(STDIN.read); puts JSON.generate({'permissions'=>parse_badging(data.fetch('badging'))['permissions'], 'unqualified'=>unqualified_apk_receive_sms?(data.fetch('tree'))})"],
                                        input=json.dumps({'badging': badging.stdout, 'tree': tree.stdout}), cwd=self.root, env=env,
                                        capture_output=True, text=True, timeout=10, check=True)
                parsed_tree = json.loads(parsed.stdout)
                permissions = parsed_tree['permissions']
                self.assertIn('android.permission.RECEIVE_SMS', permissions)
                self.assertEqual('android.permission.READ_SMS' in permissions, add_read)
                self.assertEqual(parsed_tree['unqualified'], unqualified)

    def test_fastlane_submission_routes_only_through_canonical_phase_wrapper(self):
        for options, phase in (({}, "upload"), ({"phase": "review"}, "review"),
                               ({"phase": "rollout", "full_rollout": True}, "rollout")):
            with self.subTest(options=options):
                result = self.run_fastlane(options)
                self.assertEqual(result.returncode, 0, result.stderr)
                commands = json.loads(result.stdout)
                self.assertIn("--submit --phase " + phase, commands[-1])
                self.assertTrue(commands[-1].endswith(" --full-rollout") if options.get("full_rollout") else "--full-rollout" not in commands[-1])
                self.assertFalse(any("supply" in c for c in commands))

    def test_real_packet_validator_accepts_pending_upload_review_but_blocks_rollout(self):
        self.use_real_packet_validator()
        for phase, code in (("prepare", 0), ("upload", 0), ("review", 0), ("rollout", 99)):
            with self.subTest(phase=phase):
                result = subprocess.run(["bash", "scripts/google_play_console_audit_packet.sh", "--phase", phase, "--json"],
                                        cwd=self.root, env=self.env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, code, result.stderr + result.stdout)
        self.packet["app_content"]["permissions"]["production_permissions"].append("android.permission.READ_SMS")
        self.save_packet()
        result = subprocess.run(["bash", "scripts/google_play_console_audit_packet.sh", "--phase", "upload", "--json"],
                                cwd=self.root, env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn("permissions_scope", json.loads(result.stdout)["failure_keys"])

    def test_fastlane_executes_real_packet_and_publisher_for_pending_upload_and_review(self):
        self.use_real_packet_validator()
        self.write_script("google_play_metadata_export.sh", "#!/bin/bash\nexit 0\n")
        result = self.run_fastlane({}, execute=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(r["path"].endswith(":commit") for r in self.requests()))
        self.env["TEST_TRACK_JSON"] = self.track()
        result = self.run_fastlane({"phase": "review"}, execute=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        commits = [r for r in self.requests() if r["path"].endswith(":commit")]
        self.assertEqual(len(commits), 2)

    def test_fastlane_preserves_real_packet_failure_before_any_publisher_request(self):
        self.use_real_packet_validator()
        self.write_script("google_play_metadata_export.sh", "#!/bin/bash\nexit 0\n")
        self.packet["store_listing"]["full_description"] = "x" * 4001
        self.save_packet()
        result = self.run_fastlane({}, execute=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.requests(), [])


if __name__ == "__main__":
    unittest.main()
