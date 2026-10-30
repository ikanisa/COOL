import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from .admin_build_config import BASELINE, PROJECT_ORIGIN, QUALIFICATION_ORIGIN, configuration

class AdminBuildConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.migration = self.root / "supabase/migrations" / BASELINE
        self.migration.parent.mkdir(parents=True)
        self.migration.write_text("-- synthetic build fixture\nselect 1;\n")
        self.env = {"COLLECT_BACKEND": "supabase", "SUPABASE_URL": PROJECT_ORIGIN,
                    "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_public_fixture_only"}

    def test_supabase_default_uses_nominated_public_configuration_without_secrets(self):
        env = self.env | {"SUPABASE_SERVICE_ROLE_KEY": "fixture-secret"}
        del env["COLLECT_BACKEND"]
        defines, metadata = configuration(env, self.root)
        self.assertEqual(metadata["backend"], "supabase")
        self.assertEqual(defines["SUPABASE_URL"], PROJECT_ORIGIN)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", defines)

    def test_missing_default_supabase_configuration_fails_closed(self):
        with self.assertRaises(ValueError):
            configuration({}, self.root)

    def test_legacy_configuration_requires_explicit_backend_selection(self):
        defines, metadata = configuration({"COLLECT_BACKEND": "cloudflare",
                                          "SUPABASE_SERVICE_ROLE_KEY": "fixture-secret"}, self.root)
        self.assertEqual(metadata["backend"], "cloudflare")
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", defines)
        self.assertNotIn("SUPABASE_URL", defines)

    def test_supabase_is_same_origin_bound_and_unqualified(self):
        defines, metadata = configuration(self.env, self.root)
        self.assertEqual(defines["SUPABASE_ADMIN_API_URL"], defines["ADMIN_APP_URL"])
        self.assertEqual(metadata["authentication"], "supabase_auth_cookie_with_email_verification")
        self.assertTrue(metadata["legacy_data_import_required"])
        self.assertFalse(metadata["supabase_qualification_complete"])
        self.assertFalse(metadata["operating_actions_available"])
        self.assertEqual(len(metadata["supabase_schema_sha256"]), 64)

    def test_wrong_project_cross_origin_and_secret_key_are_rejected(self):
        for changes in ({"SUPABASE_URL":"https://other.supabase.co"},
                        {"SUPABASE_ADMIN_API_URL":PROJECT_ORIGIN},
                        {"SUPABASE_API_URL":"https://admin.collect.ikanisa.com"},
                        {"SUPABASE_PUBLISHABLE_KEY":"sb_secret_fixture"},
                        {"ADMIN_APP_URL":"https://attacker.invalid"},
                        {"COLLECT_BACKEND":"unknown"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                configuration(self.env | changes, self.root)

    def test_empty_or_changed_migration_cannot_reuse_identity(self):
        _, before = configuration(self.env, self.root)
        self.migration.write_text("-- changed fixture\nselect 2;\n")
        _, after = configuration(self.env, self.root)
        self.assertNotEqual(before["supabase_schema_sha256"], after["supabase_schema_sha256"])
        self.migration.write_text("")
        with self.assertRaises(ValueError):
            configuration(self.env, self.root)

    def test_additive_migrations_are_bound_and_empty_or_symlink_sources_refused(self):
        _, before = configuration(self.env, self.root)
        additional = self.migration.parent / '20261020135932_collect_runtime_role_and_function_paths.sql'
        additional.write_text('-- synthetic additive fixture\nselect 2;\n')
        _, after = configuration(self.env, self.root)
        self.assertEqual(before['supabase_schema_sha256'], after['supabase_schema_sha256'])
        self.assertNotEqual(before['supabase_migration_chain_sha256'], after['supabase_migration_chain_sha256'])
        self.assertEqual([item['name'] for item in after['supabase_migrations']], [BASELINE, additional.name])
        additional.write_text('')
        with self.assertRaises(ValueError):
            configuration(self.env, self.root)
        additional.unlink()
        additional.symlink_to(self.migration)
        with self.assertRaises(ValueError):
            configuration(self.env, self.root)

    def test_captcha_public_configuration_is_explicit_and_validated(self):
        defines, _ = configuration(self.env, self.root)
        self.assertEqual(defines["AUTH_CAPTCHA_ENABLED"], "false")
        enabled = self.env | {"AUTH_CAPTCHA_ENABLED":"true", "AUTH_CAPTCHA_SITE_KEY":"1x00000000000000000000AA"}
        defines, _ = configuration(enabled, self.root)
        self.assertEqual(defines["AUTH_CAPTCHA_ENABLED"], "true")
        self.assertEqual(defines["AUTH_CAPTCHA_PROVIDER"], "turnstile")
        self.assertEqual(defines["AUTH_CAPTCHA_SITE_KEY"], enabled["AUTH_CAPTCHA_SITE_KEY"])
        for changes in ({"AUTH_CAPTCHA_ENABLED":"yes"}, {"AUTH_CAPTCHA_SITE_KEY":""},
                        {"AUTH_CAPTCHA_PROVIDER":"unknown"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                configuration(enabled | changes, self.root)

    def test_google_is_disabled_unless_explicit_public_release_flag(self):
        defines, _ = configuration(self.env, self.root)
        self.assertEqual(defines["GOOGLE_AUTH_ENABLED"], "false")
        defines, _ = configuration(self.env | {"GOOGLE_AUTH_ENABLED":"true"}, self.root)
        self.assertEqual(defines["GOOGLE_AUTH_ENABLED"], "true")
        with self.assertRaises(ValueError):
            configuration(self.env | {"GOOGLE_AUTH_ENABLED":"enabled"}, self.root)

    def qualification_environment(self):
        return self.env | {"ADMIN_APP_URL": QUALIFICATION_ORIGIN,
                           "SUPABASE_API_URL": QUALIFICATION_ORIGIN,
                           "SUPABASE_ADMIN_API_URL": QUALIFICATION_ORIGIN,
                           "AUTH_CAPTCHA_ENABLED": "true",
                           "AUTH_CAPTCHA_SITE_KEY": "synthetic_qualification_public_site_key"}

    def copy_builder(self):
        source = Path(__file__).resolve().with_name("admin_build_config.py")
        target = self.root / "scripts/supabase/admin_build_config.py"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        return target

    def test_qualification_is_explicit_and_does_not_change_ordinary_shipping(self):
        _, shipping = configuration(self.env, self.root)
        self.assertNotIn("purpose", shipping)
        self.assertNotIn("shipping_candidate", shipping)
        for magic in ({}, {"QUALIFICATION": "true", "COLLECT_ADMIN_QUALIFICATION": "true"}):
            with self.subTest(magic=magic), self.assertRaises(ValueError):
                configuration(self.qualification_environment() | magic, self.root)
        with self.assertRaises(ValueError):
            configuration(self.qualification_environment() | {"COLLECT_BACKEND": "cloudflare"}, self.root)

    def test_qualification_profile_has_truthful_nonshipping_metadata(self):
        defines, metadata = configuration(self.qualification_environment(), self.root, qualification=True)
        self.assertEqual(defines["COLLECT_BACKEND"], "supabase")
        self.assertEqual(defines["SUPABASE_URL"], PROJECT_ORIGIN)
        for key in ("ADMIN_APP_URL", "SUPABASE_API_URL", "SUPABASE_ADMIN_API_URL"):
            self.assertEqual(defines[key], QUALIFICATION_ORIGIN)
        self.assertEqual(defines["APP_ENVIRONMENT"], "qualification")
        self.assertEqual(defines["AUTH_CAPTCHA_ENABLED"], "true")
        self.assertEqual(metadata["purpose"], "qualification")
        self.assertEqual(metadata["environment"], "qualification")
        self.assertEqual(metadata["admin_origin"], QUALIFICATION_ORIGIN)
        self.assertIs(metadata["qualification_complete"], False)
        self.assertIs(metadata["supabase_qualification_complete"], False)
        self.assertIs(metadata["shipping_candidate"], False)
        self.assertNotIn("source_commit", metadata)
        self.assertNotIn("source_dirty", metadata)

    def test_qualification_refuses_other_hosts_backends_secrets_or_disabled_captcha(self):
        for changes in ({"COLLECT_BACKEND": "cloudflare"},
                        {"ADMIN_APP_URL": "https://platform-admin.collect.ikanisa.com"},
                        {"ADMIN_APP_URL": "https://other-qa.collect.ikanisa.com"},
                        {"SUPABASE_URL": "https://other.supabase.co"},
                        {"SUPABASE_API_URL": PROJECT_ORIGIN},
                        {"SUPABASE_ADMIN_API_URL": "https://platform-admin.collect.ikanisa.com"},
                        {"SUPABASE_PUBLISHABLE_KEY": ""},
                        {"SUPABASE_PUBLISHABLE_KEY": "sb_secret_synthetic"},
                        {"AUTH_CAPTCHA_ENABLED": "false"},
                        {"AUTH_CAPTCHA_PROVIDER": "other"},
                        {"AUTH_CAPTCHA_SITE_KEY": ""}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                configuration(self.qualification_environment() | changes, self.root, qualification=True)

    def test_actual_cli_requires_qualification_flag_and_retains_false_completion(self):
        builder = self.copy_builder()
        defines = self.root / "public-defines.json"
        metadata = self.root / "public-metadata.json"
        command = [sys.executable, "-B", str(builder), "--defines-output", str(defines),
                   "--metadata-output", str(metadata)]
        env = {"PATH": os.environ["PATH"], **self.qualification_environment(),
               "COLLECT_ADMIN_QUALIFICATION": "true"}
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(defines.exists())
        self.assertFalse(metadata.exists())
        result = subprocess.run(command + ["--qualification"], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(defines.read_text())["ADMIN_APP_URL"], QUALIFICATION_ORIGIN)
        self.assertIs(json.loads(metadata.read_text())["shipping_candidate"], False)
        self.assertNotIn("source_dirty", json.loads(metadata.read_text()))

    def test_pwa_caller_forwards_only_an_explicit_qualification_flag(self):
        self.copy_builder()
        source = Path(__file__).resolve().parents[1] / "admin_pwa_release_build.sh"
        wrapper = self.root / "scripts/admin_pwa_release_build.sh"
        shutil.copy2(source, wrapper)
        (self.root / "scripts/qa").mkdir(parents=True, exist_ok=True)
        shutil.copy2(source.parent / "qa/client_diagnostic_identity.py",
                     self.root / "scripts/qa/client_diagnostic_identity.py")
        (self.root / "lib").mkdir(exist_ok=True)
        (self.root / "lib/main_admin_cloudflare.dart").write_text("void main() {}\n")
        (self.root / "pubspec.yaml").write_text("name: synthetic_admin\nversion: 1.0.8+65\n")
        (self.root / "pubspec.lock").write_text("packages: {}\n")
        compiler = self.root / "fake-compiler"
        compiler.write_text("#!" + sys.executable + "\n" + r'''import json,os,sys
from pathlib import Path
config=next(value.split("=",1)[1] for value in sys.argv if value.startswith("--dart-define-from-file="))
Path("compiler-observation.json").write_text(json.dumps({"args":sys.argv[1:],"defines":json.loads(Path(config).read_text()),"metadata":json.loads(Path(os.environ["COLLECT_ADMIN_BUILD_METADATA"]).read_text())}))
raise SystemExit(61)
''')
        compiler.chmod(0o700)
        env = {"PATH": os.environ["PATH"], **self.qualification_environment(),
               "FLUTTER": str(compiler), "COLLECT_ADMIN_QUALIFICATION": "true"}
        observation = self.root / "compiler-observation.json"
        for arguments in ([], ["--qualification", "--extra"], ["--dart-define=QUALIFICATION=true"]):
            result = subprocess.run(["bash", str(wrapper), *arguments], cwd=self.root,
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(observation.exists())
        result = subprocess.run(["bash", str(wrapper), "--qualification"], cwd=self.root,
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 61, result.stderr)
        record = json.loads(observation.read_text())
        self.assertEqual(record["defines"]["ADMIN_APP_URL"], QUALIFICATION_ORIGIN)
        self.assertEqual(record["metadata"]["purpose"], "qualification")
        self.assertIs(record["metadata"]["shipping_candidate"], False)
        self.assertNotIn("source_commit", record["metadata"])
        self.assertEqual(record["defines"]["COLLECT_BUILD_VERSION"], "1.0.8+65")
        self.assertRegex(record["defines"]["COLLECT_BUILD_SOURCE_ID"], r"^[a-f0-9]{64}$")
        self.assertEqual(record["metadata"]["diagnostics_source_revision"],
                         record["defines"]["COLLECT_BUILD_SOURCE_ID"])

        observation.unlink()
        production = "https://platform-admin.collect.ikanisa.com"
        result = subprocess.run(["bash", str(wrapper)], cwd=self.root,
                                env=env | {"ADMIN_APP_URL": production,
                                           "SUPABASE_API_URL": production,
                                           "SUPABASE_ADMIN_API_URL": production},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 61, result.stderr)
        shipping = json.loads(observation.read_text())
        self.assertEqual(shipping["defines"]["ADMIN_APP_URL"], production)
        self.assertEqual(shipping["defines"]["APP_ENVIRONMENT"], "supabase-platform")
        self.assertNotIn("purpose", shipping["metadata"])
        self.assertNotIn("shipping_candidate", shipping["metadata"])

if __name__ == "__main__":
    unittest.main()
