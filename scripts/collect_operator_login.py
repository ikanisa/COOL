#!/usr/bin/env python3
"""Run the existing Collect login/preflight with its configured local profile.

Only user-invoked `request` sends an OTP. Secret values remain in the process
environment and the existing dedicated Keychain helper, never CLI arguments.
"""
import os
from pathlib import Path
import subprocess
import sys
import tomllib


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"request", "verify", "check"}:
        print("Usage: python3 scripts/collect_operator_login.py request|verify|check", file=sys.stderr)
        return 2
    try:
        codex_config_root = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
        with (codex_config_root / "config.toml").open("rb") as handle:
            profile = tomllib.load(handle)["mcp_servers"]["collect-notifications"]
        project_root = Path(__file__).resolve().parent.parent
        bridge = project_root / "tools" / "collect-notification-mcp"
        if Path(profile["cwd"]).resolve() != bridge.resolve():
            raise ValueError("Profile refers to a different checkout")
        environment = os.environ.copy()
        environment.update(profile.get("env", {}))
        if sys.argv[1] == "check":
            script_args = [str(bridge / "src" / "stdio_preflight.ts"), "--operations"]
        else:
            script_args = [str(bridge / "src" / "operator_login.ts"), sys.argv[1]]
        return subprocess.run(
            [profile["command"], "--experimental-strip-types", *script_args],
            cwd=bridge,
            env=environment,
            check=False,
        ).returncode
    except Exception:
        print("Collect operator setup could not start. Check the local collect-notifications profile and Keychain helper. No credential was printed.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
