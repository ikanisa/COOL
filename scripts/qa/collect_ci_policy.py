#!/usr/bin/env python3
"""Read-only checks for the declared CI boundary; not hosted enforcement proof."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess


class PolicyInputError(ValueError):
    pass


def read_workflow(path: Path) -> dict:
    # Ruby/Psych is already needed by the repository's CI gates. Use its safe
    # parser rather than installing a parser or interpreting workflow text.
    ruby = shutil.which("ruby")
    if ruby is None:
        raise PolicyInputError("CI_POLICY_RUBY_REQUIRED")
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 262144:
        raise PolicyInputError("CI_POLICY_WORKFLOW_INPUT_INVALID")
    script = (
        "require 'yaml'; require 'json'; "
        "value=YAML.safe_load(STDIN.read, permitted_classes: [], permitted_symbols: [], aliases: false); "
        "raise 'shape' unless value.is_a?(Hash); STDOUT.write(JSON.generate(value))"
    )
    try:
        result = subprocess.run(
            [ruby, "-e", script], input=path.read_text(), text=True,
            capture_output=True, timeout=15, check=False,
        )
        if result.returncode != 0:
            raise PolicyInputError("CI_POLICY_YAML_INVALID")
        parsed = json.loads(result.stdout)
        if not isinstance(parsed, dict):
            raise PolicyInputError("CI_POLICY_YAML_INVALID")
        return parsed
    except (OSError, UnicodeError, subprocess.TimeoutExpired, json.JSONDecodeError):
        raise PolicyInputError("CI_POLICY_YAML_INVALID") from None


def validate_workflows(workflows: dict[str, dict]) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []

    def fail(path: str, code: str, job: str = "") -> None:
        findings.append({"workflow": path, "job": job, "code": code})

    for path, workflow in sorted(workflows.items()):
        events = workflow.get("on", workflow.get("true", {}))
        if isinstance(events, str):
            events = {events: None}
        elif isinstance(events, list):
            events = dict.fromkeys(events)
        if not isinstance(events, dict) or not events:
            fail(path, "CI_EVENTS_REQUIRED")
            events = {}
        if "pull_request_target" in events:
            fail(path, "CI_PRIVILEGED_PR_TRIGGER_FORBIDDEN")
        permissions = workflow.get("permissions")
        if not isinstance(permissions, dict) or permissions.get("contents") != "read":
            fail(path, "CI_DEFAULT_CONTENTS_READ_REQUIRED")
        jobs = workflow.get("jobs")
        if not isinstance(jobs, dict) or not jobs:
            fail(path, "CI_JOBS_REQUIRED")
            continue
        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                fail(path, "CI_JOB_SHAPE_INVALID", str(job_name))
                continue
            timeout = job.get("timeout-minutes")
            if type(timeout) is not int or not 1 <= timeout <= 60:
                fail(path, "CI_JOB_DEADLINE_REQUIRED", job_name)
            for step in job.get("steps", []):
                if not isinstance(step, dict):
                    fail(path, "CI_STEP_SHAPE_INVALID", job_name)
                    continue
                action = step.get("uses")
                if action is None:
                    continue
                if not isinstance(action, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}", action):
                    fail(path, "CI_ACTION_COMMIT_PIN_REQUIRED", job_name)
                if isinstance(action, str) and action.startswith("actions/checkout@"):
                    inputs = step.get("with", {})
                    if not isinstance(inputs, dict) or inputs.get("persist-credentials") is not False:
                        fail(path, "CI_CHECKOUT_CREDENTIAL_PERSISTENCE_FORBIDDEN", job_name)
        if path.endswith("codeql.yml"):
            for event in ("push", "pull_request"):
                config = events.get(event)
                paths = config.get("paths", []) if isinstance(config, dict) else []
                if not isinstance(paths, list) or not {
                    "tools/collect-notification-mcp/**",
                    "tools/collect-notification-mcp/pnpm-lock.yaml",
                }.issubset(set(paths)):
                    fail(path, "CI_CODEQL_BRIDGE_AND_LOCK_TRIGGER_REQUIRED", event)
    ci = workflows.get("ci.yml", {})
    lane = ci.get("jobs", {}).get("notification-operator", {})
    steps = lane.get("steps", [])
    runs = [s.get("run", "") for s in steps if isinstance(s, dict)]
    if lane.get("defaults", {}).get("run", {}).get("working-directory") != "tools/collect-notification-mcp" or not all(
        command in runs for command in ("pnpm install --frozen-lockfile --ignore-scripts", "pnpm check", "pnpm test")
    ):
        fail("ci.yml", "CI_BRIDGE_FROZEN_CHECK_AND_TEST_REQUIRED", "notification-operator")
    node = [s for s in steps if isinstance(s, dict) and str(s.get("uses", "")).startswith("actions/setup-node@")]
    if len(node) != 1 or node[0].get("with", {}).get("node-version") != "24.19.0":
        fail("ci.yml", "CI_BRIDGE_NODE_PIN_REQUIRED", "notification-operator")
    if "npm install --global pnpm@10.33.2 --ignore-scripts" not in runs:
        fail("ci.yml", "CI_BRIDGE_PACKAGE_MANAGER_PIN_REQUIRED", "notification-operator")
    return findings


def inspect(root: Path) -> dict:
    folder = root / ".github/workflows"
    paths = sorted(folder.glob("*.yml"))
    if not paths:
        raise PolicyInputError("CI_POLICY_WORKFLOWS_MISSING")
    workflows = {path.name: read_workflow(path) for path in paths}
    findings = validate_workflows(workflows)
    return {
        "status": "pass" if not findings else "fail",
        "workflow_count": len(workflows), "findings": findings,
        "scope": "Declared local checkout, action pin, deadline and MCP CI wiring only.",
        "hosted_enforcement_verified": False,
        "security_scan_execution_verified": False,
        "remote_settings_changed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        report = inspect(args.root)
    except PolicyInputError as error:
        report = {"status": "blocked", "code": str(error), "hosted_enforcement_verified": False}
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
