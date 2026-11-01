import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .admin_hosting_metadata import validate_metadata
from .deployment_profile import canonical_profile, profile_sha256


class AdminHostingMetadataTests(unittest.TestCase):
    def fixture(self):
        profile = {"format": "collect.deployment.v1", "id": "collect-qualification", "mode": "self_hosted",
                   "environment": "qualification", "supabase_origin": "https://supabase.collect.example",
                   "member_api_origin": "https://api.collect.example", "admin_origin": "https://admin.collect.example",
                   "public_origin": "https://collect.example", "google_callback_origin": "https://admin.collect.example"}
        return {"deployment_profile": profile, "deployment_profile_sha256": profile_sha256(profile),
                "supabase_hosting": "self_hosted", "supabase_auth_issuer": profile["supabase_origin"] + "/auth/v1",
                "supabase_project_ref": None, "purpose": "qualification", "environment": "qualification",
                "admin_origin": profile["admin_origin"], "qualification_complete": False, "shipping_candidate": False}

    def test_reviewed_explicit_profile_and_legacy_managed_identity(self):
        validate_metadata(self.fixture())
        validate_metadata({"supabase_project_ref": "rrlduytparvsjfmegalh"})
        for value in ({}, {"supabase_project_ref": "other"}, {"supabase_project_ref": None}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_metadata(value)

    def test_changed_hash_host_mode_issuer_and_partial_identity_are_rejected(self):
        for key, value in (("deployment_profile_sha256", "0" * 64), ("supabase_hosting", "managed"),
                           ("supabase_project_ref", "rrlduytparvsjfmegalh"),
                           ("supabase_auth_issuer", "http://api-gw:8000/auth/v1"),
                           ("environment", "production"), ("shipping_candidate", True),
                           ("qualification_complete", True), ("admin_origin", "https://other.collect.example")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_metadata(self.fixture() | {key: value})
        partial = self.fixture()
        del partial["deployment_profile_sha256"]
        with self.assertRaises(ValueError):
            validate_metadata(partial)
        insecure = self.fixture()
        insecure["deployment_profile"]["supabase_origin"] = "http://supabase.collect.example"
        with self.assertRaises(ValueError):
            validate_metadata(insecure)

    def test_expected_build_profile_cannot_be_replaced_by_another_valid_profile(self):
        value = self.fixture()
        env = {"COLLECT_DEPLOYMENT_PROFILE": canonical_profile(value["deployment_profile"]),
               "COLLECT_DEPLOYMENT_PROFILE_SHA256": value["deployment_profile_sha256"]}
        validate_metadata(value, env)
        changed = copy.deepcopy(value)
        changed["deployment_profile"]["public_origin"] = "https://elsewhere.collect.example"
        changed["deployment_profile_sha256"] = profile_sha256(changed["deployment_profile"])
        with self.assertRaises(ValueError):
            validate_metadata(changed, env)
        with self.assertRaises(ValueError):
            validate_metadata({"supabase_project_ref": "rrlduytparvsjfmegalh"}, env)

    def test_hosting_gate_invokes_identity_validation_for_actual_artifact(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            version = self.fixture() | {"backend": "supabase", "authentication": "supabase_auth_cookie_with_email_verification",
                                       "admin_transport": "same_origin_static_proxy", "supabase_schema_sha256": "a" * 64,
                                       "legacy_data_import_required": True, "supabase_qualification_complete": False}
            (target / "version.json").write_text(json.dumps(version))
            def run():
                return subprocess.run(["bash", str(root / "scripts/admin_pwa_hosting_gate.sh")],
                                      env={"PATH": __import__("os").environ["PATH"], "ADMIN_PWA_BUILD_DIR": str(target)},
                                      capture_output=True, text=True)
            observed = run()
            self.assertNotEqual(observed.returncode, 0)  # Other PWA files deliberately absent.
            self.assertNotIn("Supabase build requires project", observed.stdout + observed.stderr)
            version["deployment_profile_sha256"] = "f" * 64
            (target / "version.json").write_text(json.dumps(version))
            observed = run()
            self.assertIn("Supabase build requires project", observed.stdout + observed.stderr)


if __name__ == "__main__":
    unittest.main()
