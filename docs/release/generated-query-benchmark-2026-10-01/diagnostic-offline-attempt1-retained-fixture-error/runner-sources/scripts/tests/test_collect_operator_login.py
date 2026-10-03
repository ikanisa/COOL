"""Exercise the local wrapper without Keychain, network or subprocess actions."""
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "collect_operator_login_under_test", ROOT / "scripts/collect_operator_login.py"
)
wrapper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wrapper)
REQUEST = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"


class CollectOperatorLoginTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.config_root = Path(self.folder.name)
        self.bridge = ROOT / "tools/collect-notification-mcp"
        self.write_profile(self.bridge)
        self.environment = patch.dict(os.environ, {"CODEX_HOME": self.folder.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def write_profile(self, cwd):
        # Synthetic values only; the test never loads the host profile.
        (self.config_root / "config.toml").write_text(
            '[mcp_servers.collect-notifications]\n'
            'command = "/synthetic/node"\n'
            f'cwd = "{cwd}"\n'
            '[mcp_servers.collect-notifications.env]\n'
            'COLLECT_OPERATOR_SESSION_RENEWAL = "keychain"\n'
        )

    def invoke(self, *args):
        with patch.object(wrapper.sys, "argv", ["wrapper", *args]), patch.object(
            wrapper.subprocess, "run"
        ) as run, patch("sys.stderr", new_callable=io.StringIO) as stderr:
            run.return_value.returncode = 7
            result = wrapper.main()
            return result, run.call_args, stderr.getvalue()

    def test_shadow_routes_only_fixed_cli_with_retained_normalized_id(self):
        for mode, flag in [("shadow", "--once"), ("shadow-status", "--status")]:
            with self.subTest(mode=mode):
                result, call, error = self.invoke(mode, "--request-id", REQUEST)
                self.assertEqual(result, 7)
                self.assertEqual(error, "")
                self.assertEqual(call.args[0], [
                    "/synthetic/node", "--experimental-strip-types",
                    str(self.bridge / "src/shadow_supervisor.ts"),
                    flag, "--request-id", REQUEST.lower(),
                ])
                self.assertEqual(call.kwargs["cwd"], self.bridge)
                self.assertFalse(call.kwargs["check"])
                self.assertNotIn("shell", call.kwargs)
                self.assertEqual(call.kwargs["env"]["COLLECT_OPERATOR_SESSION_RENEWAL"], "keychain")

    def test_existing_login_and_read_commands_keep_fixed_routes(self):
        for mode in ["request", "verify", "check"]:
            with self.subTest(mode=mode):
                result, call, _ = self.invoke(mode)
                suffix = ["stdio_preflight.ts", "--operations"] if mode == "check" else ["operator_login.ts", mode]
                self.assertEqual(result, 7)
                self.assertEqual(call.args[0][-2:], [str(self.bridge / "src" / suffix[0]), suffix[1]])

    def test_extra_arguments_and_invalid_id_never_spawn_or_echo_input(self):
        for args in [(), ("shadow",), ("shadow", "--request-id", "PRIVATE_CANARY"),
                     ("shadow", "--request-id", REQUEST, "--retry"),
                     ("request", "--request-id", REQUEST),
                     ("shadow-status", "--once", REQUEST), ("delete",)]:
            with self.subTest(args=args):
                result, call, error = self.invoke(*args)
                self.assertEqual(result, 2)
                self.assertIsNone(call)
                self.assertNotIn("PRIVATE_CANARY", error)

    def test_other_checkout_profile_never_spawns(self):
        self.write_profile(self.config_root / "other-checkout")
        result, call, error = self.invoke("shadow", "--request-id", REQUEST)
        self.assertEqual(result, 2)
        self.assertIsNone(call)
        self.assertIn("No credential was printed", error)

    def test_missing_profile_never_spawns(self):
        (self.config_root / "config.toml").unlink()
        result, call, error = self.invoke("shadow-status", "--request-id", REQUEST)
        self.assertEqual(result, 2)
        self.assertIsNone(call)
        self.assertIn("No credential was printed", error)

    def test_subprocess_failure_is_sanitized(self):
        with patch.object(wrapper.sys, "argv", ["wrapper", "check"]), patch.object(
            wrapper.subprocess, "run", side_effect=RuntimeError("PRIVATE_CANARY")
        ), patch("sys.stderr", new_callable=io.StringIO) as stderr:
            self.assertEqual(wrapper.main(), 2)
            self.assertNotIn("PRIVATE_CANARY", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
