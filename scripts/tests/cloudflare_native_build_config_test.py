#!/usr/bin/env python3
"""Exercise real release wrappers with isolated compiler/signing substitutes.

These prove configuration and refusal behavior, never native/signing acceptance.
"""
import contextlib
import hashlib
import io
import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
API = "https://platform-admin.collect.ikanisa.com"
PROJECT = "https://rrlduytparvsjfmegalh.supabase.co"
KEY = "sb_publishable_syntheticPublicKey1234"
SITE_KEY = "1x00000000000000000000AA"
PUBLIC = "https://collect.ikanisa.com"
ADMIN = "https://platform-admin.collect.ikanisa.com"


class NativeConfigurationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="collect-native-config-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for relative in ("scripts/qa", "scripts/audits", "android", "fastlane", "tmp"):
            (self.root / relative).mkdir(parents=True)
        for relative in ("scripts/android_play_store_build.sh", "scripts/ios_app_store_build.sh",
                         "scripts/audits/collect_release_build.rb", "scripts/qa/native_build_config.py", "scripts/android_release_signing_preflight.sh",
                         "scripts/google_play_optimization_gate.sh", "fastlane/Fastfile"):
            shutil.copy2(ROOT / relative, self.root / relative)
        (self.root / "pubspec.yaml").write_text("name: synthetic_config_fixture\nversion: 1.0.8+65\n")
        (self.root / "scripts/qa/native_build_provenance.rb").write_text(
            "require 'json'\n"
            "File.open('provenance-events.jsonl','a'){|f|f.puts(JSON.generate(ARGV))}\n"
            "puts 'synthetic-source-observation' if ARGV.first=='begin'\n")
        path = self.root / "android/gradlew"
        path.write_text("#!/usr/bin/env python3\n" + r'''import json,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
with (root/'gradle-observations.jsonl').open('a') as f:f.write(json.dumps(sys.argv[1:])+'\n')
if ':app:printReleaseSigningCertificateStatus' in sys.argv:
 print(json.dumps({'status':'pass','message':'Synthetic signing task substitute'}))
''')
        path.chmod(0o700)
        (self.root / "scripts/android_release_signing_preflight.sh").chmod(0o700)
        self.compiler = self.root / "compiler-substitute"
        self.compiler.write_text("#!/usr/bin/env python3\n" + r'''
import json,os,sys,zipfile
from pathlib import Path
args=sys.argv[1:];root=Path.cwd()
config=Path(args[args.index('--dart-define-from-file')+1])
with (root/'compiler-observations.jsonl').open('a') as record:
 record.write(json.dumps({'args':args,'defines':json.loads(config.read_text()),
                          'temporary_path':str(config),'mode':config.stat().st_mode&0o777})+'\n')
kind=args[1]
path,member={'apk':('build/app/outputs/flutter-apk/app-production-release.apk','lib/arm64-v8a/libapp.so'),
 'appbundle':('build/app/outputs/bundle/productionRelease/app-production-release.aab','base/lib/arm64-v8a/libapp.so'),
 'ipa':('build/ios/ipa/Collect.ipa','Payload/Collect.app/Frameworks/App.framework/App')}[kind]
artifact=root/path;artifact.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(artifact,'w',compression=zipfile.ZIP_STORED) as archive:
 values=json.loads(config.read_text())
 expected=[values[k] for k in ['SUPABASE_URL','SUPABASE_API_URL','SUPABASE_PUBLISHABLE_KEY'] if k!=os.environ.get('FIXTURE_OMIT_CONFIG')]
 if os.environ.get('FIXTURE_BINARY_URL'):expected[1]=os.environ['FIXTURE_BINARY_URL']
 archive.writestr(member,b'SYNTHETIC COMPILER SUBSTITUTE\0'+b'\0'.join(v.encode() for v in expected)+b'\0'+os.urandom(1_010_000))
 if os.environ.get('FIXTURE_QA_MARKER')=='1':archive.writestr('assets/collect-local-unsigned-qa.json','{}')
''')
        self.compiler.chmod(0o700)
        self.env = {"PATH": os.environ["PATH"], "TMPDIR": str(self.root / "tmp"),
                    "FLUTTER_BIN": str(self.compiler), "SUPABASE_URL": PROJECT,
                    "SUPABASE_API_URL": API, "SUPABASE_PUBLISHABLE_KEY": KEY,
                    "AUTH_CAPTCHA_SITE_KEY": SITE_KEY,
                    "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER": "123456789012",
                    # Retired provider input must never enter compiled defines.
                    "COLLECT_PRIVATE_TEST_KEY": "synthetic-private-value"}

    def run_wrapper(self, platform, *args, **extra):
        return subprocess.run(["bash", "scripts/" + platform + "_" +
                               ("play_store_build.sh" if platform == "android" else "app_store_build.sh"), *args],
                              cwd=self.root, env={**self.env, **extra}, text=True,
                              capture_output=True, timeout=20)

    def observations(self):
        path = self.root / "compiler-observations.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_android_public_config_artifact_target_and_cleanup(self):
        result = self.run_wrapper("android")
        self.assertEqual(result.returncode, 0, result.stderr)
        records = self.observations()
        self.assertEqual([r["args"][1] for r in records], ["apk", "appbundle"])
        for record in records:
            self.assert_configuration(record, apns=False)
        manifest = json.loads((self.root / ".cache/android_play_store_build/1.0.8+65.json").read_text())
        self.assertEqual(manifest["production_api_url"], API)
        self.assertEqual(manifest["backend"], "supabase")
        self.assertEqual(manifest["supabase_project_url"], PROJECT)
        import base64
        gradle_calls = [json.loads(line) for line in (self.root/"gradle-observations.jsonl").read_text().splitlines()]
        self.assertEqual(len(gradle_calls), 2)
        self.assertIn(":app:clean", gradle_calls[0])
        self.assertIn(":app:printReleaseSigningCertificateStatus", gradle_calls[1])
        for arguments in gradle_calls:
            encoded = next(line.split("=", 1)[1] for line in arguments if line.startswith("-Pdart-defines="))
            native = dict(base64.b64decode(value).decode().split("=", 1) for value in encoded.split(","))
            self.assertEqual(native, records[0]["defines"])
        expected_profile = hashlib.sha256(json.dumps(records[0]["defines"],sort_keys=True,separators=(",",":")).encode()).hexdigest()
        self.assertEqual(manifest["public_runtime_config_sha256"],expected_profile)
        self.assertNotIn("synthetic-private-value", json.dumps(manifest))
        self.assertFalse((self.root / ".dart_tool/collect-android-play-store-build.lock").exists())
        events = (self.root / "provenance-events.jsonl").read_text().splitlines()
        self.assertEqual(json.loads(events[-1])[0:2], ["finish", "android"])

    def test_ios_configuration_matches_reviewed_runtime_hash(self):
        result = self.run_wrapper("ios")
        self.assertEqual(result.returncode, 0, result.stderr)
        [record] = self.observations()
        self.assert_configuration(record, apns=True)
        spec = importlib.util.spec_from_file_location("native_config_ios_guard", ROOT / "scripts/qa/ios_delivery_guard.py")
        guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(guard)
        expected = hashlib.sha256(json.dumps(record["defines"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        from unittest.mock import patch
        with patch.dict(os.environ, self.env, clear=True):
            self.assertEqual(guard.runtime_configuration_sha256(self.root), expected)

    def test_fastlane_and_wrapper_use_identical_public_configuration(self):
        result = self.run_wrapper("ios")
        self.assertEqual(result.returncode, 0, result.stderr)
        code = """
module UI
  def self.user_error!(message); raise message; end
end
def default_platform(_name); end
def desc(_text); end
def platform(_name); yield; end
def lane(_name, &_block); end
load ARGV.fetch(0)
file = collect_native_public_defines
begin
  puts File.read(file.path)
ensure
  file.unlink
end
"""
        result = subprocess.run(["ruby", "-e", code, str(self.root / "fastlane/Fastfile")],
                                cwd=self.root, env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), self.observations()[0]["defines"])
        result = subprocess.run(["ruby", "-e", code, str(self.root / "fastlane/Fastfile")],
                                cwd=self.root, env=self.env | {"SUPABASE_PUBLISHABLE_KEY": ""},
                                capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid public Supabase", result.stderr)

    def assert_configuration(self, record, *, apns):
        defines = record["defines"]
        self.assertEqual(defines["COLLECT_BUILD_VERSION"], "1.0.8+65")
        self.assertEqual(defines["COLLECT_API_URL"], API)
        self.assertEqual(defines["COLLECT_BACKEND"], "supabase")
        self.assertEqual(defines["SUPABASE_URL"], PROJECT)
        self.assertEqual(defines["SUPABASE_API_URL"], API)
        self.assertEqual(defines["SUPABASE_PUBLISHABLE_KEY"], KEY)
        self.assertEqual(defines["AUTH_CAPTCHA_SITE_KEY"], SITE_KEY)
        self.assertEqual(defines["GOOGLE_AUTH_ENABLED"], "false")
        self.assertEqual(defines["COLLECT_GOOGLE_AUTH_ENABLED"], "false")
        self.assertEqual(defines["ENABLE_SMS_READER"], "false" if apns else "true")
        self.assertEqual(defines["ENABLE_ANDROID_SMS_ACCESS"], "false" if apns else "true")
        self.assertEqual(defines["APP_PUBLIC_URL"], PUBLIC)
        self.assertEqual(defines["ADMIN_APP_URL"], ADMIN)
        self.assertEqual(defines["AUTH_CAPTCHA_ENABLED"], "true")
        self.assertEqual(defines["AUTH_CAPTCHA_PROVIDER"], "turnstile")
        self.assertEqual(defines["APP_ENVIRONMENT"], "production")
        self.assertEqual(defines["ENABLE_ADMIN_PANEL"], "false")
        self.assertEqual(defines["COLLECT_MOBILE_EVIDENCE_MODE"], "false")
        self.assertEqual("APNS_ENVIRONMENT" in defines, apns)
        if apns:
            self.assertEqual(defines["APNS_ENVIRONMENT"], "production")
        self.assertEqual({key for key in defines if "KEY" in key},
                         {"SUPABASE_PUBLISHABLE_KEY", "AUTH_CAPTCHA_SITE_KEY"})
        self.assertNotIn("synthetic-private-value", json.dumps(defines))
        self.assertEqual(record["mode"], 0o600)
        self.assertFalse(Path(record["temporary_path"]).exists())

    def test_missing_or_wrong_public_configuration_never_invokes_compiler(self):
        for platform in ("android", "ios"):
            for changes in ({"SUPABASE_URL": ""}, {"SUPABASE_URL": "https://other.supabase.co"},
                            {"SUPABASE_PUBLISHABLE_KEY": ""}, {"SUPABASE_PUBLISHABLE_KEY": "sb_secret_syntheticPrivate"},
                            {"SUPABASE_API_URL": ""}, {"SUPABASE_API_URL": "http://platform-admin.collect.ikanisa.com"},
                            {"SUPABASE_API_URL": "https://retired.invalid"}, {"SUPABASE_API_URL": PROJECT},
                            {"AUTH_CAPTCHA_SITE_KEY": ""}, {"AUTH_CAPTCHA_ENABLED": "yes"},
                            {"AUTH_CAPTCHA_ENABLED": "false"}, {"AUTH_CAPTCHA_ENABLED": "false", "SUPABASE_API_URL": PROJECT, "AUTH_CAPTCHA_SITE_KEY": ""},
                            {"AUTH_CAPTCHA_PROVIDER": "other"}, {"GOOGLE_AUTH_ENABLED": "yes"},
                            {"COLLECT_GOOGLE_AUTH_ENABLED": "true", "GOOGLE_AUTH_ENABLED": "false"},
                            {"COLLECT_BACKEND": "cloudflare"}, {"COLLECT_BACKEND": ""},
                            {"COLLECT_API_URL": "https://api.collect.ikanisa.com"}):
                with self.subTest(platform=platform, changes=changes):
                    result = self.run_wrapper(platform, **changes)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(self.observations(), [])

    def test_native_and_shared_google_flags_are_forwarded_to_both_consumers(self):
        for source, key in (("lib/core/cloudflare/auth_alternative_gateway.dart", "COLLECT_GOOGLE_AUTH_ENABLED"),
                            ("lib/admin/core/cloudflare_admin_session.dart", "GOOGLE_AUTH_ENABLED"),
                            ("lib/admin/core/admin_account_pages.dart", "GOOGLE_AUTH_ENABLED")):
            self.assertRegex((ROOT/source).read_text(),r"bool\.fromEnvironment\(\s*'"+re.escape(key)+"'")
        for platform in ("android", "ios"):
            result = self.run_wrapper(platform, COLLECT_GOOGLE_AUTH_ENABLED="true")
            self.assertEqual(result.returncode, 0, result.stderr)
        for record in self.observations():
            self.assertEqual(record["defines"]["GOOGLE_AUTH_ENABLED"], "true")
            self.assertEqual(record["defines"]["COLLECT_GOOGLE_AUTH_ENABLED"], "true")
            self.assertEqual(record["defines"]["AUTH_CAPTCHA_ENABLED"], "true")
            self.assertEqual(record["defines"]["AUTH_CAPTCHA_PROVIDER"], "turnstile")
            self.assertEqual(record["defines"]["AUTH_CAPTCHA_SITE_KEY"], SITE_KEY)

    def test_real_signing_preflight_rejects_inconsistent_profile_before_gradle(self):
        result = self.run_wrapper("android")
        self.assertEqual(result.returncode,0,result.stderr)
        profile = dict(self.observations()[0]["defines"])
        profile["COLLECT_GOOGLE_AUTH_ENABLED"] = "true"
        path = self.root/"inconsistent-profile.json"
        path.write_text(json.dumps(profile))
        prior = (self.root/"gradle-observations.jsonl").read_bytes()
        result = subprocess.run(["bash","scripts/android_release_signing_preflight.sh","--public-defines",str(path)],
                                cwd=self.root,env=self.env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.root/"gradle-observations.jsonl").read_bytes(),prior)

    def runtime_gate(self, **extra):
        text = (ROOT/"scripts/google_play_optimization_gate.sh").read_text()
        functions = text[text.index("def run(*cmd)"):text.index("def http_probe(url)")]
        block = text[text.index("# Derive the same reviewed public profile"):text.index('checks["sixteen_kb_alignment"]')]
        code = "require 'json'; require 'digest'; require 'open3';\n" + functions + r'''
def check(status,message,extra={});{'status'=>status,'message'=>message}.merge(extra);end
root=Dir.pwd;pubspec=File.read('pubspec.yaml');checks={}
apk={'exists'=>true,'path'=>File.join(root,'build/app/outputs/flutter-apk/app-production-release.apk')}
aab={'exists'=>true,'path'=>File.join(root,'build/app/outputs/bundle/productionRelease/app-production-release.aab')}
actual_apk_sha256=Digest::SHA256.file(apk['path']).hexdigest
actual_aab_sha256=Digest::SHA256.file(aab['path']).hexdigest
''' + block + "\nputs JSON.generate(checks.fetch('production_runtime_config'))\n"
        result = subprocess.run(["ruby","-e",code],cwd=self.root,env=self.env|extra,capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)
        return json.loads(result.stdout)

    def test_actual_play_runtime_reader_binds_same_profile_and_artifacts(self):
        result=self.run_wrapper("android")
        self.assertEqual(result.returncode,0,result.stderr)
        observed=self.runtime_gate()
        self.assertEqual(observed["status"],"pass")
        self.assertTrue(observed["build_profile_and_artifacts_bound"])
        changed=self.runtime_gate(SUPABASE_PUBLISHABLE_KEY="sb_publishable_differentPublicKey1234")
        self.assertEqual(changed["status"],"fail")
        self.assertFalse(changed["build_profile_and_artifacts_bound"])
        artifact=self.root/"build/app/outputs/bundle/productionRelease/app-production-release.aab"
        with artifact.open("ab") as stream:stream.write(b"changed synthetic artifact")
        observed=self.runtime_gate()
        self.assertEqual(observed["status"],"fail")
        self.assertFalse(observed["build_profile_and_artifacts_bound"])

    def test_actual_play_runtime_reader_rejects_missing_key_and_legacy_url(self):
        result=self.run_wrapper("android")
        self.assertEqual(result.returncode,0,result.stderr)
        import zipfile
        artifact=self.root/"build/app/outputs/bundle/productionRelease/app-production-release.aab"
        with zipfile.ZipFile(artifact,"w") as archive:
            archive.writestr("base/lib/arm64-v8a/libapp.so",(PROJECT+"\0"+API+"\0https://api.collect.ikanisa.com").encode())
        manifest_path=self.root/".cache/android_play_store_build/1.0.8+65.json"
        manifest=json.loads(manifest_path.read_text())
        manifest["artifacts"]["aab"]["sha256"]=hashlib.sha256(artifact.read_bytes()).hexdigest()
        manifest_path.write_text(json.dumps(manifest))
        observed=self.runtime_gate()
        self.assertEqual(observed["status"],"fail")
        self.assertTrue(observed["build_profile_and_artifacts_bound"])
        self.assertFalse(observed["aab_runtime_config"])

    def test_changed_link_targets_never_invoke_compiler(self):
        for platform in ("android", "ios"):
            for key in ("APP_PUBLIC_URL", "ADMIN_APP_URL"):
                with self.subTest(platform=platform, key=key):
                    result = self.run_wrapper(platform, **{key: "https://other.invalid"})
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("reviewed HTTPS production targets", result.stderr)
                    self.assertEqual(self.observations(), [])

    def test_extra_arguments_cannot_override_guarded_defines(self):
        for platform in ("android", "ios"):
            result = self.run_wrapper(platform, "--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true")
            self.assertEqual(result.returncode, 2)
            self.assertIn("accepts no extra Flutter arguments", result.stderr)
            self.assertEqual(self.observations(), [])

    def test_android_qa_marker_is_not_a_store_artifact(self):
        result = self.run_wrapper("android", FIXTURE_QA_MARKER="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Local unsigned QA marker is forbidden", result.stderr)
        self.assertEqual(len(self.observations()), 1)
        self.assertFalse((self.root / ".dart_tool/collect-android-play-store-build.lock").exists())

    def test_packaged_target_mismatch_fails_closed(self):
        for platform in ("android", "ios"):
            result = self.run_wrapper(platform, FIXTURE_BINARY_URL="https://other.invalid")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("reviewed Supabase runtime configuration", result.stderr)
        self.assertTrue(all(not Path(r["temporary_path"]).exists() for r in self.observations()))
        events = [json.loads(line) for line in (self.root / "provenance-events.jsonl").read_text().splitlines()]
        self.assertTrue(all(event[0] != "finish" for event in events))

    def test_missing_packaged_project_or_publishable_key_is_rejected(self):
        for platform in ("android", "ios"):
            for key in ("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"):
                result = self.run_wrapper(platform, FIXTURE_OMIT_CONFIG=key)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("reviewed Supabase runtime configuration", result.stderr)

    def test_interactive_adapter_rejects_keys_and_unreviewed_targets(self):
        code = ("require './scripts/audits/collect_release_build'; require 'json'; "
                "begin; puts JSON.generate(CollectReleaseBuild.environment(JSON.parse(STDIN.read))); "
                "rescue; exit 2; end")
        valid = {"supabase_url": PROJECT, "supabase_api_url": API,
                 "supabase_publishable_key": KEY, "auth_captcha_site_key": SITE_KEY}
        for value, accepted in [(valid, True), (valid | {"public_url": PUBLIC, "admin_url": ADMIN}, True),
                                (valid | {"service_key": "synthetic"}, False),
                                (valid | {"supabase_url": "https://other.invalid"}, False),
                                (valid | {"supabase_publishable_key": "sb_secret_synthetic"}, False),
                                ({"api_url": "https://api.collect.ikanisa.com"}, False)]:
            result = subprocess.run(["ruby", "-e", code], cwd=self.root, input=json.dumps(value),
                                    env=self.env, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0 if accepted else 2)
            if accepted:
                self.assertEqual(json.loads(result.stdout)["SUPABASE_API_URL"], API)
                self.assertEqual(json.loads(result.stdout)["COLLECT_BACKEND"], "supabase")


class NativeBuildVersionTest(unittest.TestCase):
    """Pure Python source/profile tests; never invokes a compiler or child."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="collect-native-version-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.pubspec = self.root / "pubspec.yaml"
        self.pubspec.write_text("name: synthetic_config_fixture\nversion: 1.0.8+65\n")
        spec = importlib.util.spec_from_file_location("native_version_fixture", ROOT / "scripts/qa/native_build_config.py")
        self.config = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.config)
        self.env = {"SUPABASE_URL": PROJECT, "SUPABASE_API_URL": API,
                    "SUPABASE_PUBLISHABLE_KEY": KEY, "AUTH_CAPTCHA_SITE_KEY": SITE_KEY}

    def profile(self, platform="android", **changes):
        return self.config.configuration(self.env | changes, platform, self.pubspec)

    def test_android_and_ios_emit_same_exact_source_version(self):
        for platform in ("android", "ios"):
            profile = self.profile(platform)
            self.assertEqual(profile["COLLECT_BUILD_VERSION"], "1.0.8+65")
            self.assertEqual(profile["COLLECT_BACKEND"], "supabase")
            self.assertEqual(profile["APP_ENVIRONMENT"], "production")
            self.assertNotIn("COLLECT_" + platform.upper() + "_BUILD_NAME", profile)

    def test_default_source_is_helper_tree_and_not_working_directory(self):
        with patch.object(self.config, "__file__", str(self.root / "scripts/qa/native_build_config.py")), \
                patch.object(Path, "cwd", side_effect=AssertionError("cwd must not select version")):
            self.assertEqual(self.config.configuration(self.env, "ios")["COLLECT_BUILD_VERSION"], "1.0.8+65")

    def test_source_change_changes_profile_identity(self):
        old = json.dumps(self.profile(), sort_keys=True)
        self.pubspec.write_text("name: synthetic\nversion: 2.1.3+66\n")
        new = self.profile()
        self.assertEqual(new["COLLECT_BUILD_VERSION"], "2.1.3+66")
        self.assertNotEqual(hashlib.sha256(old.encode()).hexdigest(),
                            hashlib.sha256(json.dumps(new, sort_keys=True).encode()).hexdigest())

    def test_exact_diagnostic_and_platform_overrides_are_allowed(self):
        for platform in ("android", "ios"):
            self.assertEqual(self.profile(platform, **{"COLLECT_BUILD_VERSION": "1.0.8+65",
                "COLLECT_" + platform.upper() + "_BUILD_NAME": "1.0.8",
                "COLLECT_" + platform.upper() + "_BUILD_NUMBER": "65"}), self.profile(platform))

    def test_mismatched_platform_name_is_refused(self):
        for platform in ("android", "ios"):
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                self.profile(platform, **{"COLLECT_" + platform.upper() + "_BUILD_NAME": "1.0.9"})

    def test_mismatched_platform_number_is_refused(self):
        for platform in ("android", "ios"):
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                self.profile(platform, **{"COLLECT_" + platform.upper() + "_BUILD_NUMBER": "66"})

    def test_mismatched_diagnostic_version_is_refused(self):
        for platform in ("android", "ios"):
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                self.profile(platform, COLLECT_BUILD_VERSION="1.0.8+66")

    def test_invalid_or_secret_shaped_overrides_are_not_echoed(self):
        for platform in ("android", "ios"):
            for name in ("COLLECT_BUILD_VERSION", "COLLECT_" + platform.upper() + "_BUILD_NAME",
                         "COLLECT_" + platform.upper() + "_BUILD_NUMBER"):
                for value in ("", "unknown", "synthetic-private-value", "sb_secret_fixture", "1.0.8+65\n", "1.0.8+65 x", None, 65):
                    with self.subTest(platform=platform, name=name, value_type=type(value).__name__):
                        with self.assertRaises(ValueError) as error:
                            self.profile(platform, **{name: value})
                        self.assertEqual(str(error.exception), "Native release build overrides must match the source pubspec version")

    def test_missing_or_ambiguous_source_version_is_refused(self):
        for text in ("name: synthetic\n", "version: 1.0.8+65\nversion: 2.0.0+2\n", "  version: 1.0.8+65\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.pubspec.write_text(text)
                self.profile()

    def test_invalid_source_version_cannot_become_an_unknown_diagnostic(self):
        values = ("1.0.8", "1.0.8+0", "1.0.8+-1", "1.0.8+065", "01.0.8+65", "1.0+65", "1.0.8-beta+65",
                  "1.0.8+2147483648", "1.0.8+1 # comment", "'1.0.8+65'", "synthetic-private-value", "١.0.8+65",
                  "1" * 33 + ".0.8+65")
        for value in values:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.pubspec.write_text("version: " + value + "\n")
                self.profile()

    def test_missing_symlink_directory_and_oversize_sources_are_refused(self):
        self.pubspec.unlink()
        with self.assertRaises(ValueError): self.profile()
        target = self.root / "other.yaml"; target.write_text("version: 1.0.8+65\n")
        self.pubspec.symlink_to(target)
        with self.assertRaises(ValueError): self.profile()
        self.pubspec.unlink(); self.pubspec.mkdir()
        with self.assertRaises(ValueError): self.profile()
        self.pubspec.rmdir(); self.pubspec.write_bytes(b"x" * (1024**2 + 1))
        with self.assertRaises(ValueError): self.profile()

    def test_existing_backend_captcha_origin_and_google_refusals_remain(self):
        bad = ({"COLLECT_BACKEND": "cloudflare"}, {"SUPABASE_URL": "https://other.supabase.co"},
               {"SUPABASE_URL": "http://rrlduytparvsjfmegalh.supabase.co"},
               {"SUPABASE_API_URL": PROJECT}, {"SUPABASE_API_URL": "https://other.invalid"},
               {"SUPABASE_PUBLISHABLE_KEY": "sb_secret_fixture"}, {"AUTH_CAPTCHA_ENABLED": "false"},
               {"AUTH_CAPTCHA_PROVIDER": "other"}, {"AUTH_CAPTCHA_SITE_KEY": ""},
               {"GOOGLE_AUTH_ENABLED": "invalid"}, {"GOOGLE_AUTH_ENABLED": "false", "COLLECT_GOOGLE_AUTH_ENABLED": "true"},
               {"APP_PUBLIC_URL": "https://other.invalid"}, {"ADMIN_APP_URL": "https://other.invalid"},
               {"COLLECT_API_URL": "https://api.collect.ikanisa.com"})
        for platform in ("android", "ios"):
            for changes in bad:
                with self.subTest(platform=platform, keys=sorted(changes)), self.assertRaises(ValueError):
                    self.profile(platform, **changes)

    def cli(self, args):
        with patch.object(self.config, "__file__", str(self.root / "scripts/qa/native_build_config.py")), \
                patch.object(sys, "argv", ["native_build_config.py", *args]), patch.dict(os.environ, self.env, clear=True):
            self.config.main()

    def test_cli_generate_and_validate_exact_profile_without_child_process(self):
        path = self.root / "profile.json"
        for platform in ("android", "ios"):
            self.cli([platform, "--defines-output", str(path)])
            self.assertEqual(json.loads(path.read_text()), self.profile(platform))
            self.cli([platform, "--validate-defines", str(path)])

    def test_cli_rejects_missing_changed_or_secret_diagnostic_field_without_echo(self):
        for mutation in (None, "1.0.8+66", "synthetic-private-value"):
            profile = self.profile()
            if mutation is None: del profile["COLLECT_BUILD_VERSION"]
            else: profile["COLLECT_BUILD_VERSION"] = mutation
            path = self.root / "profile.json"; path.write_text(json.dumps(profile))
            error = io.StringIO()
            with contextlib.redirect_stderr(error), self.assertRaises(SystemExit) as exit:
                self.cli(["android", "--validate-defines", str(path)])
            self.assertEqual(exit.exception.code, 2)
            self.assertNotIn("synthetic-private-value", error.getvalue())

    def test_ios_approval_profile_hash_uses_selected_candidate_version(self):
        spec = importlib.util.spec_from_file_location("ios_version_guard_fixture", ROOT / "scripts/qa/ios_delivery_guard.py")
        guard = importlib.util.module_from_spec(spec); spec.loader.exec_module(guard)
        with patch.dict(os.environ, self.env, clear=True):
            first = guard.runtime_configuration_sha256(self.root)
            expected = hashlib.sha256(json.dumps(self.profile("ios"), sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            self.assertEqual(first, expected)
            self.pubspec.write_text("version: 2.1.3+66\n")
            self.assertNotEqual(guard.runtime_configuration_sha256(self.root), first)
            self.pubspec.write_text("version: synthetic-private-value\n")
            with self.assertRaises(guard.GuardError) as error:
                guard.runtime_configuration_sha256(self.root)
            self.assertEqual(str(error.exception), "IOS_PUBLIC_BUILD_CONFIGURATION_WRONG")


if __name__ == "__main__":
    unittest.main()
