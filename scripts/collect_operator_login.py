#!/usr/bin/env python3
"""Run Collect login, reads and an explicit manual shadow check locally.

Only user-invoked `request` sends an OTP. Secret values remain in the process
environment and the existing dedicated Keychain helper, never CLI arguments.
Shadow commands require a retained request UUID for safe reconciliation.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tomllib


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    ordinary = mode in {"request", "verify", "check"} and len(sys.argv) == 2
    shadow = mode in {"shadow", "shadow-status"} and len(sys.argv) == 4 and sys.argv[2] == "--request-id"
    if shadow:
        shadow = re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", sys.argv[3]) is not None
    if not ordinary and not shadow:
        print("Usage: python3 scripts/collect_operator_login.py request|verify|check OR shadow|shadow-status --request-id UUID", file=sys.stderr)
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
        if mode == "check":
            script_args = [str(bridge / "src" / "stdio_preflight.ts"), "--operations"]
        elif shadow:
            script_args = [str(bridge / "src" / "shadow_supervisor.ts"),
                           "--once" if mode == "shadow" else "--status",
                           "--request-id", sys.argv[3].lower()]
        else:
            script_args = [str(bridge / "src" / "operator_login.ts"), mode]
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
