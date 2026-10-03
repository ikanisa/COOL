#!/usr/bin/env python3
"""Exercise release secret transport without calling Supabase or a provider."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
TOKEN = "sbp_test_transport_123"
HOOK = "v1,whsec_AbC123+/="
CAPTCHA = "captcha_transport_456"
PG_SCHEME = "postgresql://"

MOCK_CURL = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import stat
import sys

args = sys.argv[1:]
config = Path(args[args.index("--config") + 1])
output = Path(args[args.index("-o") + 1]) if "-o" in args else None
body = sys.stdin.read() if "@-" in args else ""
log_dir = Path(os.environ["MOCK_LOG_DIR"])
index = len(list(log_dir.glob("curl-*.json")))
record = {
    "argv": args,
    "config_path": str(config),
    "config_mode": stat.S_IMODE(config.stat().st_mode),
    "config": config.read_text(),
    "body": body,
}
(log_dir / f"curl-{index:02d}.json").write_text(json.dumps(record))
if os.environ.get("MOCK_CURL_FAIL") == "1":
    sys.exit(7)

status = "200"
response = "[]"
if "/config/auth" in " ".join(args):
    if os.environ.get("MOCK_CURL_402") == "1" and '"password_hibp_enabled":true' in body:
        status = "402"
        response = "{}"
    else:
        response = body
if output:
    output.write_text(response)
    response = ""
if "-w" in args:
    response += "\n" + status if "/database/query" in " ".join(args) else status
sys.stdout.write(response)
'''

MOCK_SUPABASE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import stat
import sys

args = sys.argv[1:]
if args == ["--version"]:
    print("2.114.0")
    sys.exit(0)
env_file = Path(args[args.index("--env-file") + 1])
record = {
    "argv": args,
    "env_path": str(env_file),
    "env_mode": stat.S_IMODE(env_file.stat().st_mode),
    "env_content": env_file.read_text(),
}
(Path(os.environ["MOCK_LOG_DIR"]) / "supabase.json").write_text(json.dumps(record))
'''

MOCK_PSQL = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import stat
import sys

service_file = Path(os.environ["PGSERVICEFILE"])
password_file = Path(os.environ["PGPASSFILE"]) if "PGPASSFILE" in os.environ else None
record = {
    "argv": sys.argv[1:],
    "service_path": str(service_file),
    "service_mode": stat.S_IMODE(service_file.stat().st_mode),
    "service_content": service_file.read_text(),
    "password_path": str(password_file) if password_file else None,
    "password_mode": stat.S_IMODE(password_file.stat().st_mode) if password_file else None,
    "password_content": password_file.read_text() if password_file else None,
}
(Path(os.environ["MOCK_LOG_DIR"]) / "psql.json").write_text(json.dumps(record))
if os.environ.get("MOCK_PSQL_FAIL") == "1":
    sys.exit(9)
print("connected")
'''


class SupabaseSecretTransportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / "log"
        self.log.mkdir()
        self.mock_bin = self.root / "bin"
        self.mock_bin.mkdir()
        self._executable(self.mock_bin / "curl", MOCK_CURL)
        self._executable(self.mock_bin / "mock-supabase", MOCK_SUPABASE)
        self._executable(self.mock_bin / "mock-psql", MOCK_PSQL)
        self.env = os.environ.copy()
        self.env.update(
            {
                "PATH": str(self.mock_bin) + os.pathsep + self.env["PATH"],
                "TMPDIR": str(self.root),
                "MOCK_LOG_DIR": str(self.log),
                "SUPABASE_BIN": str(self.mock_bin / "mock-supabase"),
                "PSQL_BIN": str(self.mock_bin / "mock-psql"),
                "SUPABASE_ACCESS_TOKEN": TOKEN,
                "SUPABASE_PROJECT_REF": "abcdefghijklmnopqrst",
                "SUPABASE_URL": "https://abcdefghijklmnopqrst.supabase.co",
                "SEND_SMS_HOOK_SECRET": HOOK,
                "AUTH_CAPTCHA_SECRET": CAPTCHA,
                "AUTH_CAPTCHA_PROVIDER": "turnstile",
                "AUTH_CAPTCHA_SITE_KEY": "site_key_test",
                "MOCK_CURL_402": "1",
            }
        )

    @staticmethod
    def _executable(path, contents):
        path.write_text(contents)
        path.chmod(0o700)

    def _curl_records(self):
        return [json.loads(path.read_text()) for path in sorted(self.log.glob("curl-*.json"))]

    def test_auth_config_and_secret_retries_keep_values_out_of_argv(self):
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in (
            "supabase_apply_auth_hardening.sh",
            "supabase_cli_helpers.sh",
            "load_dotenv_strict.sh",
        ):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        shutil.copy2(ROOT / ".supabase-cli-version", self.root / ".supabase-cli-version")

        run = subprocess.run(
            ["bash", str(scripts / "supabase_apply_auth_hardening.sh")],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertNotIn(HOOK, run.stdout + run.stderr)
        self.assertNotIn(CAPTCHA, run.stdout + run.stderr)

        supabase = json.loads((self.log / "supabase.json").read_text())
        self.assertEqual(supabase["env_mode"], 0o600)
        self.assertEqual(supabase["env_content"], f"SEND_SMS_HOOK_SECRET={HOOK}\n")
        self.assertNotIn(HOOK, " ".join(supabase["argv"]))
        self.assertFalse(Path(supabase["env_path"]).exists())

        calls = self._curl_records()
        self.assertEqual(len(calls), 2)
        self.assertIn('"password_hibp_enabled":true', calls[0]["body"])
        self.assertNotIn('"password_hibp_enabled"', calls[1]["body"])
        for call in calls:
            payload = json.loads(call["body"])
            self.assertTrue(payload["external_email_enabled"])
            self.assertTrue(payload["external_phone_enabled"])
            self.assertFalse(payload["mailer_autoconfirm"])
            self.assertFalse(payload["mailer_allow_unverified_email_sign_ins"])
            self.assertEqual(payload["mailer_otp_length"], 6)
            self.assertEqual(payload["mailer_otp_exp"], 600)
            self.assertEqual(payload["smtp_max_frequency"], 60)
            self.assertEqual(call["config_mode"], 0o600)
            self.assertEqual(call["config"], f'header = "Authorization: Bearer {TOKEN}"\n')
            self.assertIn(HOOK, call["body"])
            self.assertIn(CAPTCHA, call["body"])
            argv = " ".join(call["argv"])
            self.assertNotIn(TOKEN, argv)
            self.assertNotIn(HOOK, argv)
            self.assertNotIn(CAPTCHA, argv)
            self.assertIn("@-", call["argv"])
            self.assertFalse(Path(call["config_path"]).exists())

    def test_management_query_uses_stdin_and_rejects_header_injection(self):
        helper = ROOT / "scripts/supabase_cli_helpers.sh"
        command = ". \"$1\"; supabase_management_query \"select 'private_query_789';\""
        run = subprocess.run(
            ["bash", "-c", command, "bash", str(helper)],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(run.stdout), [])
        call = self._curl_records()[0]
        self.assertIn("private_query_789", call["body"])
        self.assertNotIn("private_query_789", " ".join(call["argv"]))
        self.assertNotIn(TOKEN, " ".join(call["argv"]))
        self.assertEqual(call["config_mode"], 0o600)
        self.assertFalse(Path(call["config_path"]).exists())

        bad_env = self.env.copy()
        bad_env["SUPABASE_ACCESS_TOKEN"] = TOKEN + '"\nheader = "X-Injected: yes'
        rejected = subprocess.run(
            ["bash", "-c", command, "bash", str(helper)],
            cwd=self.root,
            env=bad_env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(len(self._curl_records()), 1)

    def test_direct_database_url_is_only_in_owner_only_service_file(self):
        helper = ROOT / "scripts/supabase_cli_helpers.sh"
        database_url = (
            f"{PG_SCHEME}test_user:db_test_secret%21@localhost:5432/test_db"
            "?sslmode=require&connect_timeout=5"
        )
        env = self.env.copy()
        env["DATABASE_URL"] = database_url
        run = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; collect_psql_url_service "$DATABASE_URL" -Atq -c "select 1"',
                "bash",
                str(helper),
            ],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("connected", run.stdout)
        record = json.loads((self.log / "psql.json").read_text())
        self.assertEqual(record["argv"], ["service=collect_readiness", "-Atq", "-c", "select 1"])
        self.assertEqual(record["service_mode"], 0o600)
        self.assertNotIn("db_test_secret", record["service_content"])
        self.assertEqual(record["password_mode"], 0o600)
        self.assertEqual(record["password_content"], "*:*:*:*:db_test_secret!\n")
        self.assertIn("sslmode=require", record["service_content"])
        self.assertNotIn("db_test_secret", " ".join(record["argv"]))
        self.assertFalse(Path(record["service_path"]).exists())
        self.assertFalse(Path(record["password_path"]).exists())

        env["DATABASE_URL"] += "&unsupported_option=x"
        rejected = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; collect_psql_url_service "$DATABASE_URL" -Atq',
                "bash",
                str(helper),
            ],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("Unsupported PostgreSQL URI option", rejected.stderr)

        env["DATABASE_URL"] = PG_SCHEME + "u:private_invalid_secret[bad@host/db"
        malformed = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; collect_psql_url_service "$DATABASE_URL" -Atq',
                "bash",
                str(helper),
            ],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(malformed.returncode, 0)
        self.assertNotIn("private_invalid_secret", malformed.stderr)

        env["DATABASE_URL"] = PG_SCHEME + "test_user:trailing%20@localhost/test_db"
        trailing = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; collect_psql_url_service "$DATABASE_URL" -Atq',
                "bash",
                str(helper),
            ],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(trailing.returncode, 0, trailing.stderr)
        trailing_record = json.loads((self.log / "psql.json").read_text())
        self.assertEqual(trailing_record["password_content"], "*:*:*:*:trailing \n")

        env["DATABASE_URL"] = PG_SCHEME + "test_user:ipv6_secret@[::1]:5432/test_db"
        ipv6 = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; collect_psql_url_service "$DATABASE_URL" -Atq',
                "bash",
                str(helper),
            ],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(ipv6.returncode, 0, ipv6.stderr)
        ipv6_record = json.loads((self.log / "psql.json").read_text())
        self.assertIn("host=::1\n", ipv6_record["service_content"])

    def test_readiness_source_does_not_pass_auth_config_or_password_to_argv(self):
        readiness = (ROOT / "scripts/supabase_production_readiness.sh").read_text()
        self.assertNotIn('ruby - "$auth_config"', readiness)
        self.assertNotIn('psql_cli "$READINESS_DATABASE_URL"', readiness)
        self.assertNotIn('-H "x-hook-secret: $SEND_SMS_HOOK_SECRET"', readiness)
        self.assertIn('ruby - "$auth_config_file"', readiness)
        self.assertIn('collect_psql_url_service "$READINESS_DATABASE_URL"', readiness)

    def test_failure_paths_remove_secret_files(self):
        helper = ROOT / "scripts/supabase_cli_helpers.sh"
        curl_env = self.env.copy()
        curl_env["MOCK_CURL_FAIL"] = "1"
        failed_curl = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; supabase_management_curl -sS https://api.supabase.com/mock',
                "bash",
                str(helper),
            ],
            cwd=self.root,
            env=curl_env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(failed_curl.returncode, 0)
        self.assertNotIn("unbound variable", failed_curl.stderr)
        self.assertFalse(Path(self._curl_records()[0]["config_path"]).exists())

        psql_env = self.env.copy()
        psql_env["MOCK_PSQL_FAIL"] = "1"
        psql_env["DATABASE_URL"] = PG_SCHEME + "test_user:db_test_secret@localhost/test_db"
        failed_psql = subprocess.run(
            [
                "bash",
                "-c",
                '. "$1"; collect_psql_url_service "$DATABASE_URL" -Atq',
                "bash",
                str(helper),
            ],
            cwd=self.root,
            env=psql_env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(failed_psql.returncode, 0)
        self.assertNotIn("unbound variable", failed_psql.stderr)
        record = json.loads((self.log / "psql.json").read_text())
        self.assertFalse(Path(record["service_path"]).exists())
        self.assertFalse(Path(record["password_path"]).exists())


if __name__ == "__main__":
    unittest.main()
