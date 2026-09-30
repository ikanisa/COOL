#!/usr/bin/env python3
"""Retain source-bound local Admin session/action verification, without services."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TESTS = [
    "test/admin_action_session_test.dart",
    "test/admin_action_contracts_test.dart",
    "test/admin_action_ui_session_test.dart",
    "test/admin_overview_totals_test.dart",
    "test/admin_platform_access_test.dart",
    "test/admin_reason_dialog_focus_test.dart",
    "test/admin_reconciliation_ui_test.dart",
    "test/admin_route_access_test.dart",
    "test/features/runtime_component_contract_test.dart",
]
ANALYSIS = [
    "lib/admin/core/admin_runtime.dart",
    "lib/admin/core/admin_auth_guard.dart",
    "lib/admin/core/admin_action_contracts.dart",
    "lib/admin/core/admin_overview_runtime.dart",
    "lib/admin/core/admin_detail_runtime.dart",
    "lib/admin/core/admin_group_runtime.dart",
    "lib/admin/core/admin_payee_runtime.dart",
    "lib/admin/core/admin_list_runtime.dart",
    "lib/admin/core/admin_platform_access.dart",
    "lib/admin/shared/components/admin_confirm_dialog.dart",
    *TESTS[:4],
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    # Include the entire runtime Dart tree, not just files named on the CLI.
    paths = set(ROOT.glob("lib/**/*.dart"))
    paths.update(ROOT / name for name in TESTS)
    paths.update(ROOT.glob("assets/typefaces/*"))
    paths.update(
        ROOT / name
        for name in [
            "pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json",
            "scripts/tests/verify_admin_session_actions.py",
        ]
    )
    return {
        str(path.relative_to(ROOT)): digest(path)
        for path in sorted(paths)
        if path.is_file()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", required=True, type=Path)
    parser.add_argument("--pub-cache", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    flutter = args.flutter.resolve(strict=True)
    pub_cache = args.pub_cache.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)  # Never overwrite prior evidence.
    env = os.environ.copy()
    env["PUB_CACHE"] = str(pub_cache)
    before = sources()
    (output / "sources-before.json").write_text(json.dumps(before, indent=2) + "\n")
    commands = [
        ("runtime", [str(flutter), "--version", "--machine"]),
        ("tests", [str(flutter), "test", "--no-pub", "--reporter", "expanded", *TESTS]),
        ("analysis", [str(flutter), "analyze", "--no-pub", *ANALYSIS]),
    ]
    results = []
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    for name, argv in commands:
        with (output / f"{name}.stdout").open("wb") as stdout, (
            output / f"{name}.stderr"
        ).open("wb") as stderr:
            run = subprocess.run(argv, cwd=ROOT, env=env, stdout=stdout, stderr=stderr)
        results.append({
            "name": name, "argv": argv, "exit_code": run.returncode,
            "stdout_sha256": digest(output / f"{name}.stdout"),
            "stderr_sha256": digest(output / f"{name}.stderr"),
        })
        print(json.dumps({"command": name, "exit_code": run.returncode}), flush=True)
    after = sources()
    unchanged = before == after
    passed = unchanged and all(result["exit_code"] == 0 for result in results)
    manifest = {
        "schema_version": 1, "started_at_utc": started,
        "completed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "base_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "source_hashes_before": before, "source_hashes_after": after,
        "source_unchanged": unchanged, "commands": results, "passed": passed,
        "database_calls": 0, "provider_calls": 0, "hosted_calls": 0,
        "scope": "Admin session/action contracts and named route/widget regression tests",
        "exclusions": [
            "Actual hosted Auth/provider transactions and deployed browser behavior",
            "Whole-system acceptance and visual reference parity",
            "Migration143/144 runtime verification and browser reload recovery",
            "Every Admin operation's complete route/action/state matrix",
        ],
    }
    (output / "validation.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # Preserve precisely tested code for comparison after later source changes.
    for name, checksum in before.items():
        source = ROOT / name
        if unchanged and digest(source) == checksum:
            snapshot = output / "source-snapshot" / name
            snapshot.parent.mkdir(parents=True, exist_ok=True)
            snapshot.write_bytes(source.read_bytes())
    print(json.dumps({"passed": passed, "source_unchanged": unchanged, "source_count": len(before)}))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
