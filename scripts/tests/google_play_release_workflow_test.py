#!/usr/bin/env python3
"""Exercise the real Play phase policy and publisher with isolated transports.

All bundles, account observations and HTTP responses here are synthetic. These
tests prove local control flow, never Google approval or external delivery.
"""
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone

ROOT = Path(__file__).resolve().parents[2]
AAB = "build/app/outputs/bundle/productionRelease/app-production-release.aab"
APK = "build/app/outputs/flutter-apk/app-production-release.apk"
PACKET = "docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json"


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
            code = "require 'json'; def check(s,m,e={});{'status'=>s}.merge(e);end;checks={};package=JSON.parse(ARGV[0]);\n" + policy + "\nputs JSON.generate(checks)"
            result = subprocess.run(["ruby", "-e", code, json.dumps({"compile_sdk": sdk, "target_sdk": sdk})],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["target_api"]["status"], expected)

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
