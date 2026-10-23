#!/usr/bin/env python3
"""Read-only checks for the declared CI boundary; not hosted enforcement proof."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import struct


class PolicyInputError(ValueError):
    pass


def appledouble_sidecar(path: Path) -> bool:
    """Recognize observed AppleDouble v2 metadata, never a prefix-only exemption.

    Native file inspection identifies the retained metadata as AppleDouble.
    Require its binary magic/version and a complete, bounded entry table in
    addition to the ._ name. Malformed files retain normal reference checks.
    """
    if not path.name.startswith('._') or path.is_symlink():
        return False
    try:
        size = path.stat().st_size
        with path.open('rb') as handle:
            header = handle.read(26)
            if len(header) != 26:
                return False
            magic, version, _, count = struct.unpack('>II16sH', header)
            table_end = 26 + count * 12
            if (magic, version) != (0x00051607, 0x00020000) or not count or table_end > size:
                return False
            table = handle.read(count * 12)
        if len(table) != count * 12:
            return False
        ids = set()
        spans = []
        for index in range(count):
            entry_id, offset, length = struct.unpack_from('>III', table, index * 12)
            if not entry_id or entry_id in ids or offset < table_end or offset + length > size:
                return False
            ids.add(entry_id)
            if length:
                spans.append((offset, offset + length))
        spans.sort()
        return all(left[1] <= right[0] for left, right in zip(spans, spans[1:]))
    except (OSError, struct.error):
        return False

def workflow_paths(folder: Path) -> list[Path]:
    # Only structurally verified binary metadata is excluded. Text, malformed
    # sidecars and aliases retain ordinary fail-closed workflow validation.
    return sorted(path for pattern in ("*.yml", "*.yaml")
                  for path in folder.glob(pattern) if not appledouble_sidecar(path))


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


LEGACY_JOBS = ('cloudflare-backend', 'cloudflare-platform',
               'admin-legacy-preview-build', 'admin-cloudflare-candidate')
RETIRED = '${{ false }}'
CURRENT_CONSUMERS = (
    ('deploy/platform-admin', 'npm ci --ignore-scripts --no-audit --no-fund'),
    ('${{ github.workspace }}', 'node --test deploy/platform-admin/test/human-parent.test.mjs deploy/platform-admin/test/human-parent-bundle.test.mjs'),
    ('tools/notification-operator', 'node --test --test-concurrency=1 test/operator.test.mjs test/mcp.test.mjs test/transport.test.mjs test/auth.test.mjs'),
    ('tools/collect-admin-mcp', 'npm run check\nnpm test'),
    ('${{ github.workspace }}', 'python3 -m unittest scripts.tests.test_admin_cloudflare_source scripts.tests.test_admin_cloudflare_artifact scripts.tests.test_admin_cloudflare_assets scripts.tests.test_admin_cloudflare_preflight -v\nnode --test scripts/tests/admin_cloudflare_retirement_worker_test.mjs'),
)
CURRENT_MAKE_COMMANDS = (
    'cd deploy/platform-admin && npm ci --ignore-scripts --no-audit --no-fund',
    'node --test deploy/platform-admin/test/*.test.mjs',
    'cd tools/collect-admin-mcp && npm run check && npm test',
    'cd tools/notification-operator && node --test --test-concurrency=1 test/operator.test.mjs test/mcp.test.mjs test/transport.test.mjs test/auth.test.mjs',
)


def legacy_execution(command, cwd):
    # Exact known obsolete execution families, not a ban on recovered source
    # paths: current Supabase/admission fixtures live under platform-api/test.
    return (cwd in ('deploy/platform-api', 'deploy/admin-api')
            or re.search(r'(?:cd\s+|--prefix[ =]+)deploy/(?:platform|admin)-api\b', command)
            or re.search(r'cloudflare-platform-(?:test|dev|migrate-local)\b|admin_cloudflare_build\.sh|recovery17_ci\.mjs|(?:recovery12|recovery13|recovery15|momo_release_candidate)_test\.mjs|atomic_d1_restore_test\.mjs|operation_inventory\.mjs', command))


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
                    "deploy/platform-api/**/*.js",
                    "deploy/platform-admin/**/*.js",
                    "supabase/functions/**/*.js",
                    "supabase/functions/**/*.ts",
                    "deploy/platform-supabase-free/**/*.js",
                    "deploy/platform-supabase-free/**/*.mjs",
                }.issubset(set(paths)):
                    fail(path, "CI_CODEQL_PLATFORM_TRIGGER_REQUIRED", event)
    ci = workflows.get("ci.yml", {})
    jobs = ci.get('jobs', {})
    for name in LEGACY_JOBS:
        if jobs.get(name, {}).get('if') != RETIRED:
            fail('ci.yml', 'CI_LEGACY_AUTOMATIC_EXECUTION_FORBIDDEN', name)
    for filename, workflow in workflows.items():
        for name, job in workflow.get('jobs', {}).items():
            if job.get('if') == RETIRED:
                continue
            default = job.get('defaults', {}).get('run', {}).get('working-directory', '.')
            for step in job.get('steps', []):
                if legacy_execution(step.get('run', ''), step.get('working-directory', default)):
                    fail(filename, 'CI_LEGACY_AUTOMATIC_EXECUTION_FORBIDDEN', name)
    lane = jobs.get('supabase-admin-consumers', {})
    steps = lane.get('steps', [])
    if ('if' in lane or 'needs' in lane or 'defaults' in lane
            or lane.get('continue-on-error', False) is not False):
        fail('ci.yml', 'CI_CURRENT_CONSUMER_JOB_REQUIRED', 'supabase-admin-consumers')
    nodes = [step for step in steps if str(step.get('uses', '')).startswith('actions/setup-node@')]
    if (len(nodes) != 1 or nodes[0].get('with', {}).get('node-version') != '24.19.0'
            or 'if' in nodes[0] or nodes[0].get('continue-on-error', False) is not False):
        fail('ci.yml', 'CI_CURRENT_CONSUMER_NODE_PIN_REQUIRED', 'supabase-admin-consumers')
    for cwd, command in CURRENT_CONSUMERS:
        matches = [(name, step, job) for name, job in jobs.items() if job.get('if') != RETIRED
                   for step in job.get('steps', []) if step.get('run', '').strip() == command
                   and (name == 'supabase-admin-consumers' or step.get('working-directory',
                        job.get('defaults', {}).get('run', {}).get('working-directory', '.')) == cwd)]
        if (len(matches) != 1 or matches[0][0] != 'supabase-admin-consumers'
                or matches[0][1].get('working-directory', '.') != cwd
                or 'if' in matches[0][1]
                or matches[0][1].get('continue-on-error', False) is not False):
            fail('ci.yml', 'CI_CURRENT_CONSUMER_HOOK_REQUIRED', 'supabase-admin-consumers')
    runs = [step.get('run', '').strip() for step in steps]
    install, parent = CURRENT_CONSUMERS[0][1], CURRENT_CONSUMERS[1][1]
    if (install not in runs or parent not in runs or runs.index(install) >= runs.index(parent)
            or len(nodes) != 1 or steps.index(nodes[0]) >= runs.index(install)):
        fail('ci.yml', 'CI_CURRENT_CONSUMER_INSTALL_ORDER_REQUIRED', 'supabase-admin-consumers')
    # These are distinct runtimes. The retained preview email/Core/Gateway
    # lane cannot establish acceptance of the password-cookie platform PWA.
    jobs = ci.get('jobs', {})
    shipping = jobs.get('admin-platform-candidate', {})
    if set(shipping.get('needs', [])) != {'repo-hygiene', 'admin-web-build', 'supabase-platform', 'supabase-admin-consumers'}:
        fail('ci.yml', 'CI_SHIPPING_PLATFORM_DEPENDENCY_REQUIRED', 'admin-platform-candidate')
    shipping_steps = shipping.get('steps', [])
    downloads = [s.get('with', {}).get('name') for s in shipping_steps
                 if isinstance(s, dict) and str(s.get('uses', '')).startswith('actions/download-artifact@')]
    commands = '\n'.join(str(s.get('run', '')) for s in shipping_steps if isinstance(s, dict))
    if downloads != ['admin-platform-pwa-candidate'] or 'python3 scripts/admin_platform_candidate.py ' not in commands:
        fail('ci.yml', 'CI_SHIPPING_PLATFORM_ARTIFACT_REQUIRED', 'admin-platform-candidate')
    build_steps = jobs.get('admin-web-build', {}).get('steps', [])
    builds = '\n'.join(str(s.get('run', '')) for s in build_steps if isinstance(s, dict))
    if 'bash scripts/admin_pwa_release_build.sh' not in builds or 'scripts/admin_cloudflare_build.sh' in builds:
        fail('ci.yml', 'CI_SHIPPING_PLATFORM_BUILD_REQUIRED', 'admin-web-build')
    backend_steps = [step for step in build_steps if 'bash scripts/admin_pwa_release_build.sh' in str(step.get('run', '')) or 'PY_PLATFORM_IDENTITY' in str(step.get('run', ''))]
    if (len(backend_steps) != 2 or any(step.get('env', {}).get('COLLECT_BACKEND') != 'supabase' for step in backend_steps)
            or shipping.get('env', {}).get('COLLECT_BACKEND') != 'supabase' or '--backend "$COLLECT_BACKEND"' not in commands):
        fail('ci.yml', 'CI_SUPABASE_CANDIDATE_SELECTION_REQUIRED', 'admin-web-build')
    supabase = jobs.get('supabase-platform', {})
    standalone = workflows.get('supabase.yml', {}).get('jobs', {}).get('local-qualification', {})
    required_supabase = {
        'python3 supabase/schema-src/generate_baseline.py --check',
        'node scripts/supabase/test_schema.mjs',
        'COLLECT_TEST_PG_URL="$COLLECT_GOOGLE_TEST_DATABASE_URL" node scripts/supabase/test_schema.mjs',
        'node --test scripts/supabase/data_stage.test.mjs scripts/supabase/data_promote.test.mjs',
        'python3 -m unittest scripts.supabase.test_cutover_gate scripts.supabase.test_admin_build_config',
        '"$COLLECT_DENO" task check', '"$COLLECT_DENO" task test',
        'node --test test/supabase-free-transport.test.mjs',
        'node --test test/local-challenge-parent.test.mjs',
        'node --test scripts/supabase/jobs_test.mjs',
    }
    hooks = supabase.get('steps', [])
    selected = [step for step in hooks if step.get('run') in required_supabase]
    env = supabase.get('env', {})
    expected_databases = {
        'COLLECT_TEST_PG_URL':'collect_schema_test', 'COLLECT_TEST_DATABASE_URL':'collect_edge_test',
        'COLLECT_GOOGLE_TEST_DATABASE_URL':'collect_google_test',
        'COLLECT_ADMIN_HISTORY_TEST_DATABASE_URL':'collect_admin_history_test',
        'COLLECT_IMPORT_TEST_DATABASE_URL':'collect_import_test',
        'COLLECT_PRIVATE_RETENTION_TEST_DATABASE_URL':'collect_private_retention_test',
        'COLLECT_MFA_TEST_DATABASE_URL':'collect_mfa_test',
        'COLLECT_RECEIPT_FACTS_TEST_DATABASE_URL':'collect_receipt_facts_test',
        'COLLECT_SMS_CONTENT_TEST_DATABASE_URL':'collect_sms_content_test',
        'COLLECT_JOBS_TEST_DATABASE_URL':'collect_jobs_test',
        'COLLECT_GROUPS_TEST_DATABASE_URL':'collect_groups_test',
    }
    if (not standalone or standalone != supabase or 'if' in supabase or
            supabase.get('continue-on-error', False) is not False or
            len(selected) != len(required_supabase) or
            {step.get('run') for step in selected} != required_supabase or
            any('if' in step or step.get('continue-on-error', False) is not False for step in selected) or
            any(env.get(key) != 'postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/' + name
                for key, name in expected_databases.items())):
        fail('ci.yml', 'CI_SUPABASE_QUALIFICATION_REQUIRED', 'supabase-platform')
    return findings


def validate_legacy_makefile_history(contents: str) -> list[dict[str, str]]:
    """Explicit historical reader only; not called by current inspect/shipping."""
    commands = []
    targets = 0
    active = False
    for line in contents.splitlines():
        if line.startswith("cloudflare-platform-test:"):
            targets += 1
            active = True
            continue
        if active and line.startswith("\t"):
            commands.append(line.strip().removeprefix("@"))
        elif line.strip() and not line.startswith("#"):
            active = False
    findings = []
    for version in (12, 13):
        if targets != 1 or f"node --test scripts/tests/recovery{version}_test.mjs" not in commands:
            findings.append({"workflow": "Makefile", "job": "cloudflare-platform-test",
                             "code": f"CI_PLATFORM_MAKE_RECOVERY{version}_REQUIRED"})
    for filename, code in (("recovery15_test.mjs", "CI_PLATFORM_MAKE_RECOVERY15_REQUIRED"),
                           ("momo_release_candidate_test.mjs", "CI_PLATFORM_MAKE_MOMO_CANDIDATE_REQUIRED")):
        if targets != 1 or commands.count(f"node --test scripts/tests/{filename}") != 1:
            findings.append({"workflow": "Makefile", "job": "cloudflare-platform-test", "code": code})
    return findings


def validate_platform_makefile(contents: str) -> list[dict[str, str]]:
    """Validate only current Supabase consumer/qualification Make wiring."""
    findings = []
    def target_commands(name):
        selected, count, inside = [], 0, False
        for line in contents.splitlines():
            if line.startswith(name + ':'):
                count += 1
                # Dependencies must not silently execute another backend.
                inside = True
                if line != name + ':':
                    selected.append('UNEXPECTED_DEPENDENCY')
            elif inside and line.startswith('\t'):
                selected.append(line.strip().removeprefix('@'))
            elif line.strip() and not line.startswith('#'):
                inside = False
        return count, selected
    count, current = target_commands('supabase-admin-consumers-test')
    if count != 1 or tuple(current) != CURRENT_MAKE_COMMANDS:
        findings.append({'workflow': 'Makefile', 'job': 'supabase-admin-consumers-test',
                         'code': 'CI_CURRENT_MAKE_CONSUMERS_REQUIRED'})
    count, qualification = target_commands('supabase-test')
    if (count != 1 or qualification.count('$(MAKE) supabase-admin-consumers-test') != 1
            or any(legacy_execution(command, '.') for command in qualification)):
        findings.append({'workflow': 'Makefile', 'job': 'supabase-test',
                         'code': 'CI_CURRENT_MAKE_QUALIFICATION_REQUIRED'})
    return findings


def inspect(root: Path) -> dict:
    folder = root / ".github/workflows"
    paths = workflow_paths(folder)
    if not paths:
        raise PolicyInputError("CI_POLICY_WORKFLOWS_MISSING")
    workflows = {path.name: read_workflow(path) for path in paths}
    findings = validate_workflows(workflows)
    makefile = root / "Makefile"
    if makefile.is_symlink() or not makefile.is_file() or makefile.stat().st_size > 262144:
        raise PolicyInputError("CI_POLICY_MAKEFILE_INPUT_INVALID")
    findings.extend(validate_platform_makefile(makefile.read_text()))
    return {
        "status": "pass" if not findings else "fail",
        "workflow_count": len(workflows), "findings": findings,
        "scope": "Declared current Supabase CI/Make and automatic legacy retirement; local wiring only.",
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
