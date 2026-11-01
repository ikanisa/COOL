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



# https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#context-availability
# Job env permits github/needs/strategy/matrix/vars/secrets/inputs. These known
# contexts are unavailable there; jobs is restricted to reusable-workflow output.
JOB_ENV_UNAVAILABLE_CONTEXTS = frozenset({'env', 'job', 'jobs', 'runner', 'steps'})
EXPRESSION_IDENTIFIER = re.compile(r'[A-Za-z_][A-Za-z0-9_-]*')


def job_env_unavailable_contexts(value: object) -> set[str]:
    """Find unavailable root references in interpolated job-env expressions.

    This is a focused lexical check, not a GitHub expression syntax/type parser.
    Single-quoted literals (with doubled quote escapes) and member names are
    skipped, while grouped roots, function arguments and dynamic indexes are
    scanned. A quoted '}}' cannot hide the rest of an expression. Other syntax
    and context-placement rules still belong to GitHub/actionlint validation.
    """
    unavailable: set[str] = set()
    if not isinstance(value, str):
        return unavailable
    position = 0
    while position < len(value):
        start = value.find('${{', position)
        if start < 0:
            break
        position, previous = start + 3, None
        while position < len(value):
            if value.startswith('}}', position):
                position += 2
                break
            character = value[position]
            if character.isspace():
                position += 1
                continue
            if character == "'":
                position += 1
                while position < len(value):
                    if value[position] != "'":
                        position += 1
                        continue
                    position += 1
                    if position < len(value) and value[position] == "'":
                        position += 1
                        continue
                    break
                previous = 'literal'
                continue
            identifier = EXPRESSION_IDENTIFIER.match(value, position)
            if identifier:
                name = identifier.group().lower()
                if previous != '.' and name in JOB_ENV_UNAVAILABLE_CONTEXTS:
                    unavailable.add(name)
                position, previous = identifier.end(), 'identifier'
            else:
                position, previous = position + 1, character
    return unavailable


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
            job_env = job.get("env", {})
            env_values = job_env.values() if isinstance(job_env, dict) else (job_env,)
            if any(job_env_unavailable_contexts(value) for value in env_values):
                fail(path, "CI_JOB_ENV_CONTEXT_UNAVAILABLE", job_name)
            timeout = job.get("timeout-minutes")
            reusable = job.get('uses')
            if reusable is not None:
                # Same-revision local calls inherit the called jobs' explicitly
                # validated deadlines. GitHub does not permit timeout-minutes
                # on a reusable-workflow caller job.
                if (path != 'ci.yml' or job_name != 'supabase-platform'
                        or reusable != './.github/workflows/supabase.yml'
                        or any(key in job for key in ('timeout-minutes', 'steps', 'runs-on'))):
                    fail(path, 'CI_REUSABLE_WORKFLOW_BOUNDARY_INVALID', job_name)
            elif type(timeout) is not int or not 1 <= timeout <= 60:
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
    findings.extend(validate_current_supabase_qualification(workflows))
    return findings


CURRENT_PROFILE_CONDITION = "needs.select-profile.outputs.profile == 'current-self-hosted'"
SELECTED_SOURCE = '${{ needs.select-profile.outputs.source_sha }}'
CURRENT_NATIVE_COMMAND = 'timeout --signal=TERM --kill-after=10s 900s node scripts/supabase/testing/current-self-hosted-native.mjs'
CURRENT_DART_COMMAND = 'flutter test --no-pub --concurrency=1 --tags=integration --dart-define-from-file="$RUNNER_TEMP/collect-current-selfhost-history-defines.json" test/self_hosted_member_history_sql_receipts_test.dart'
CURRENT_SOURCE_COMMANDS = (
    'python3 supabase/schema-src/generate_baseline.py --check',
    'node --test scripts/supabase/data-contracts.test.mjs',
    'python3 -m unittest scripts.supabase.test_cutover_gate scripts.supabase.test_admin_build_config scripts.tests.client_diagnostic_identity_test',
    'node scripts/supabase/run_edge_node_tests.mjs',
    'node --test deploy/platform-admin/test/backend-selection.test.mjs deploy/platform-admin/test/supabase-transport.test.mjs',
    'node --test test/supabase-free-transport.test.mjs test/local-challenge-parent.test.mjs',
    '"$COLLECT_DENO" task check',
)


def validate_current_supabase_qualification(workflows: dict[str, dict]) -> list[dict[str, str]]:
    """Require the current full-chain native proof and its actual Dart consumer.

    Historical packets remain available only against an explicitly selected
    immutable historical checkout. A historical pass cannot replace this job.
    """
    findings = []
    def fail(job, code='CI_SUPABASE_QUALIFICATION_REQUIRED'):
        findings.append({'workflow': 'supabase.yml', 'job': job, 'code': code})
    caller = workflows.get('ci.yml', {}).get('jobs', {}).get('supabase-platform', {})
    if (caller.get('uses') != './.github/workflows/supabase.yml'
            or set(caller) - {'name', 'uses'}):
        findings.append({'workflow': 'ci.yml', 'job': 'supabase-platform', 'code': 'CI_SUPABASE_QUALIFICATION_REQUIRED'})
    workflow = workflows.get('supabase.yml', {})
    events = workflow.get('on', workflow.get('true', {}))
    if not isinstance(events, dict) or 'workflow_call' not in events:
        fail('supabase-platform')
    jobs = workflow.get('jobs', {})
    select = jobs.get('select-profile', {})
    selected = [step for step in select.get('steps', []) if step.get('id') == 'source']
    if ('if' in select or 'needs' in select or select.get('continue-on-error', False) is not False
            or len(selected) != 1 or any(key in selected[0] for key in ('if', 'continue-on-error'))):
        fail('select-profile')
    else:
        step = selected[0]
        command = step.get('run', '')
        required = (
            "source = os.environ.get('REVIEWED_SHA', '') if historical else os.environ['GITHUB_SHA']",
            "assert re.fullmatch(r'[a-f0-9]{40}', source)",
            "assert not historical or os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch'",
            "assert not os.environ.get('REVIEWED_SHA')",
            "assert historical or profile == 'current-self-hosted'",
        )
        if (step.get('env', {}).get('PROFILE') != "${{ inputs.qualification_profile || 'current-self-hosted' }}"
                or step.get('env', {}).get('REVIEWED_SHA') != '${{ inputs.reviewed_historical_commit }}'
                or any(line not in command for line in required)):
            fail('select-profile')
    current_names = ('current-source-contracts', 'current-self-hosted-native', 'current-self-hosted-history-dart')
    for name in current_names:
        job = jobs.get(name, {})
        needs = job.get('needs', [])
        needs = [needs] if isinstance(needs, str) else needs
        required_needs = {'select-profile', 'current-self-hosted-native'} if name.endswith('history-dart') else {'select-profile'}
        if (set(needs) != required_needs or job.get('if') != CURRENT_PROFILE_CONDITION
                or job.get('continue-on-error', False) is not False):
            fail(name)
        checkout = [step for step in job.get('steps', []) if str(step.get('uses', '')).startswith('actions/checkout@')]
        if len(checkout) != 1 or checkout[0].get('with', {}).get('ref') != SELECTED_SOURCE or 'if' in checkout[0]:
            fail(name)
    source = jobs.get('current-source-contracts', {})
    source_steps = source.get('steps', [])
    for command in CURRENT_SOURCE_COMMANDS:
        matches = [step for step in source_steps if step.get('run', '').strip() == command]
        if (len(matches) != 1 or 'if' in matches[0]
                or matches[0].get('continue-on-error', False) is not False):
            fail('current-source-contracts')
    source_commands = '\n'.join(step.get('run', '') for step in source_steps)
    for required in ('scripts/supabase/testing/current16-integration.test.mjs',
                     'scripts/supabase/testing/current-self-hosted-native.test.mjs',
                     'scripts/supabase/testing/self-hosted-member-history.test.mjs',
                     'scripts/supabase/jobs-config-contracts.test.mjs',
                     'scripts/supabase/email_jobs_operator.test.mjs',
                     'deploy/self-hosted/*.test.mjs',
                     'scripts.self_hosted.test_operations.Configuration'):
        matches = [step for step in source_steps if required in step.get('run', '')]
        if (len(matches) != 1 or 'if' in matches[0] or '||' in matches[0].get('run', '')
                or matches[0].get('continue-on-error', False) is not False):
            fail('current-source-contracts')
    native = jobs.get('current-self-hosted-native', {})
    env = native.get('env', {})
    expected = {
        'COLLECT_CI_SYNTHETIC': 'true', 'COLLECT_NATIVE_PROFILE': 'control-concurrency',
        'COLLECT_TEST_PG_URL': 'postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/collect_schema_test',
        'COLLECT_FENCE_ADMIN_DATABASE_URL': 'postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/postgres',
        'COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL': 'postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/postgres',
    }
    if any(env.get(key) != value for key, value in expected.items()):
        fail('current-self-hosted-native')
    for name, command in (('current-self-hosted-native', CURRENT_NATIVE_COMMAND),
                          ('current-self-hosted-history-dart', CURRENT_DART_COMMAND)):
        steps = jobs.get(name, {}).get('steps', [])
        matches = [step for step in steps if step.get('run', '').strip() == command]
        if len(matches) != 1 or 'if' in matches[0] or matches[0].get('continue-on-error', False) is not False:
            fail(name)
    native_steps = native.get('steps', [])
    runs = [step.get('run', '') for step in native_steps]
    start = 'sh scripts/supabase/testing/ci-native-postgres.sh start'
    warming = [step for step in native_steps if 'self-hosted-control-concurrency.ts' in step.get('run', '')]
    if (start not in runs or CURRENT_NATIVE_COMMAND not in runs or runs.index(start) >= runs.index(CURRENT_NATIVE_COMMAND)
            or len(warming) != 1 or '--frozen' not in warming[0].get('run', '') or '--no-lock' in warming[0].get('run', '')
            or 'if' in warming[0] or warming[0].get('continue-on-error', False) is not False):
        fail('current-self-hosted-native')
    uploads = [step for step in native_steps if str(step.get('uses', '')).startswith('actions/upload-artifact@')]
    if len(uploads) != 1:
        fail('current-self-hosted-native')
    else:
        upload = uploads[0]
        paths = upload.get('with', {}).get('path', '').splitlines()
        if (upload.get('if') != 'always()' or upload.get('with', {}).get('if-no-files-found') != 'error'
                or any('private' in path.lower() or '**' in path for path in paths if not path.startswith('!'))
                or not any(path.endswith('/RESULT.json') for path in paths)
                or not any(path.endswith('/history/ACTUAL-HISTORY-PACKET.json') for path in paths)):
            fail('current-self-hosted-native')
    history_steps = jobs.get('current-self-hosted-history-dart', {}).get('steps', [])
    admits = [step for step in history_steps if 'node scripts/supabase/testing/admit-self-hosted-history.mjs ' in step.get('run', '')]
    if len(admits) != 1 or 'if' in admits[0] or admits[0].get('continue-on-error', False) is not False:
        fail('current-self-hosted-history-dart')
    historical = {'local-qualification': 'historical-standard', 'control-concurrency-native': 'historical-standard',
                  'stopped-admission-lifecycle-native': 'historical-current14', 'current14-member-history-dart': 'historical-current14',
                  'current16-integration-native': 'historical-current16'}
    for name, profile in historical.items():
        job = jobs.get(name, {})
        if not job:
            fail(name, 'CI_HISTORICAL_SOURCE_REQUIRED');continue
        checkout = [step for step in job.get('steps', []) if str(step.get('uses', '')).startswith('actions/checkout@')]
        if (job.get('if') != "needs.select-profile.outputs.profile == '" + profile + "'"
                or len(checkout) != 1 or checkout[0].get('with', {}).get('ref') != SELECTED_SOURCE):
            fail(name, 'CI_HISTORICAL_SOURCE_REQUIRED')
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
    if (count != 1 or qualification != ['$(MAKE) supabase-source-test',
                                      '$(MAKE) supabase-current-native',
                                      '$(MAKE) supabase-admin-consumers-test']):
        findings.append({'workflow': 'Makefile', 'job': 'supabase-test',
                         'code': 'CI_CURRENT_MAKE_QUALIFICATION_REQUIRED'})
    for name, expected in (
        ('supabase-current-native', ['node scripts/supabase/testing/current-self-hosted-native.mjs']),
        ('supabase-schema-test', ['$(MAKE) supabase-current-native']),
    ):
        count, commands = target_commands(name)
        if count != 1 or commands != expected:
            findings.append({'workflow': 'Makefile', 'job': name,
                             'code': 'CI_CURRENT_MAKE_NATIVE_REQUIRED'})
    count, commands = target_commands('supabase-source-test')
    required = (
        'python3 supabase/schema-src/generate_baseline.py --check',
        'node scripts/supabase/run_edge_node_tests.mjs',
        'cd supabase/functions && "$${COLLECT_DENO:-deno}" task check',
    )
    if (count != 1 or any(commands.count(command) != 1 for command in required)
            or any(legacy_execution(command, '.') for command in commands)):
        findings.append({'workflow': 'Makefile', 'job': 'supabase-source-test',
                         'code': 'CI_CURRENT_MAKE_SOURCE_REQUIRED'})
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
