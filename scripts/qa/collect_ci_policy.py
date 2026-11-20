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


LEGACY_JOBS = ('cloudflare-backend', 'cloudflare-platform')
RETIRED_ADMIN_JOBS = {'admin-legacy-preview-build', 'admin-cloudflare-candidate'}
RETIRED = '${{ false }}'
CURRENT_CONSUMERS = (
    ('deploy/platform-admin', 'npm ci --ignore-scripts --no-audit --no-fund'),
    ('${{ github.workspace }}', 'node --test deploy/platform-admin/test/human-parent.test.mjs deploy/platform-admin/test/human-parent-bundle.test.mjs'),
    ('tools/notification-operator', 'node --test --test-concurrency=1 test/operator.test.mjs test/mcp.test.mjs test/transport.test.mjs test/auth.test.mjs'),
    ('tools/collect-admin-mcp', 'npm run check\nnpm test'),
    ('${{ github.workspace }}', 'python3 -m unittest scripts.tests.test_admin_cloudflare_assets -v\nnode --test scripts/tests/admin_cloudflare_retirement_worker_test.mjs\nnode --test scripts/tests/admin_entry_test.mjs deploy/admin-entry/pages/test.mjs'),
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
            or re.search(r'cloudflare-platform-(?:test|dev|migrate-local)\b|admin_cloudflare_build\.sh|main_admin(?:_cloudflare)?\.dart|recovery17_ci\.mjs|(?:recovery12|recovery13|recovery15|momo_release_candidate)_test\.mjs|atomic_d1_restore_test\.mjs|operation_inventory\.mjs', command))



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
                    "admin-web/**",
                    "deploy/platform-api/**/*.js",
                    "deploy/platform-admin/**/*.js",
                    "deploy/managed-sms/**",
                    "supabase/functions/**/*.js",
                    "supabase/functions/**/*.mjs",
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
    for name in RETIRED_ADMIN_JOBS.intersection(jobs):
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
    shipping = jobs.get('admin-platform-candidate', {})
    if set(shipping.get('needs', [])) != {'repo-hygiene', 'admin-web-build', 'supabase-platform', 'supabase-admin-consumers'}:
        fail('ci.yml', 'CI_SHIPPING_PLATFORM_DEPENDENCY_REQUIRED', 'admin-platform-candidate')

    def required_step(step):
        return 'if' not in step and step.get('continue-on-error', False) is False

    artifact = 'admin-platform-pwa-candidate'
    verify = 'node admin-web/scripts/build-admin.mjs verify-ci'
    shipping_steps = shipping.get('steps', [])
    downloads = [step for step in shipping_steps if str(step.get('uses', '')).startswith('actions/download-artifact@')]
    verifying = [step for step in shipping_steps if step.get('run', '').strip() == verify and required_step(step)]
    if (len(downloads) != 1 or downloads[0].get('with') != {'name': artifact, 'path': 'build'}
            or not required_step(downloads[0]) or len(verifying) != 1
            or shipping_steps.index(downloads[0]) >= shipping_steps.index(verifying[0])):
        fail('ci.yml', 'CI_SHIPPING_PLATFORM_ARTIFACT_REQUIRED', 'admin-platform-candidate')

    build = jobs.get('admin-web-build', {})
    build_steps = build.get('steps', [])
    uploads = [step for step in build_steps if str(step.get('uses', '')).startswith('actions/upload-artifact@')]
    if (len(uploads) != 1 or not required_step(uploads[0])
            or uploads[0].get('with', {}).get('name') != artifact
            or uploads[0].get('with', {}).get('include-hidden-files') is not True
            or uploads[0].get('with', {}).get('if-no-files-found') != 'error'
            or set(uploads[0].get('with', {}).get('path', '').splitlines()) != {'build/admin-web/', 'build/admin-web.json'}):
        fail('ci.yml', 'CI_SHIPPING_PLATFORM_INPUT_REQUIRED', 'admin-web-build')
    builds = [step for step in build_steps
              if step.get('run', '').strip().splitlines() == [
                  'bash scripts/admin_pwa_release_build.sh', verify, 'bash scripts/admin_pwa_hosting_gate.sh --json',
              ] and required_step(step)]
    install = [step for step in build_steps
               if step.get('run', '') == 'npm ci --prefix admin-web --no-audit --no-fund' and required_step(step)]
    browser = [step for step in build_steps if required_step(step) and step.get('run', '').strip().splitlines() == [
        'admin-web/node_modules/.bin/playwright-core install --with-deps --no-shell chromium',
        'node admin-web/scripts/build-admin.mjs fixture',
        'node admin-web/tests/browser/smoke.mjs build/admin-web-fixture',
    ]]
    if len(browser) != 1 or len(install) != 1 or len(builds) != 1 or not (
            build_steps.index(install[0]) < build_steps.index(browser[0]) < build_steps.index(builds[0])):
        fail('ci.yml', 'CI_COMPILED_ADMIN_BROWSER_REQUIRED', 'admin-web-build')
    if (len(builds) != 1 or len(install) != 1 or len(uploads) != 1 or
            'if' in build or build.get('continue-on-error', False) is not False or
            not build_steps.index(install[0]) < build_steps.index(builds[0]) < build_steps.index(uploads[0]) or
            any(legacy_execution(step.get('run', ''), step.get('working-directory', '.')) or
                'flutter-action@' in step.get('uses', '') or 'flutter build web' in step.get('run', '')
                for step in build_steps)):
        fail('ci.yml', 'CI_SHIPPING_PLATFORM_BUILD_REQUIRED', 'admin-web-build')
    if (len(builds) != 1 or len(verifying) != 1 or
            builds[0].get('env', {}).get('COLLECT_BACKEND') != 'supabase' or
            builds[0].get('env') != verifying[0].get('env')):
        fail('ci.yml', 'CI_SUPABASE_CANDIDATE_SELECTION_REQUIRED', 'admin-web-build')
    findings.extend(validate_current_supabase_qualification(workflows))
    return findings


CURRENT_TRANSFER_MAKE_COMMAND = 'output="$$(mktemp "$${TMPDIR:-/tmp}/collect-current-transfer.XXXXXXXX")" || exit 1; trap \'rm -f -- "$$output"\' EXIT; node --test --test-concurrency=1 --test-timeout=180000 --test-reporter=tap scripts/supabase/current-pg-transfer/reconcile.test.mjs scripts/supabase/current-pg-transfer/identity-mapping/identity.test.mjs scripts/supabase/managed-cloud-migrations/provider-ca.test.mjs scripts/supabase/managed-cloud-migrations/operator.test.mjs scripts/supabase/managed-cloud-migrations/operator-pg.test.mjs scripts/supabase/managed-cloud-migrations/event-trigger-preimage.test.mjs scripts/supabase/managed-cloud-migrations/migration-postconditions.test.mjs scripts/supabase/current-pg-transfer/batch-transfer/quarantine.test.mjs scripts/supabase/current-pg-transfer/test-support/lifecycle.test.mjs scripts/supabase/device-commissioning/fixture.test.mjs scripts/supabase/current-pg-transfer/object-transfer/transfer.test.mjs scripts/supabase/current-pg-transfer/object-transfer/scope-rebind.test.mjs scripts/supabase/current-pg-transfer/object-transfer/supabase-adapter.test.mjs scripts/supabase/current-pg-transfer/business-import/import.test.mjs scripts/supabase/current-pg-transfer/financial-inventory/inventory.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/consistency.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/native-readiness-v3/diagnostic.test.mjs scripts/supabase/current-pg-transfer/financial-import/import.test.mjs scripts/supabase/current-pg-transfer/native-sms-import/import.test.mjs scripts/supabase/retention-convergence/user-id-forward.test.mjs scripts/supabase/retention-convergence/ordered-chain-fixture.test.mjs scripts/supabase/retention-convergence/history-plan.test.mjs scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.test.mjs scripts/supabase/retention-convergence/deferred-mfa/history-proposal.test.mjs supabase/functions/_shared/tests/burimunsi/native-sms-ledger.test.mjs supabase/managed-deployment-identity/bind-managed-pg17.test.mjs scripts/supabase/device-commissioning/synthetic-transport.test.mjs supabase/managed-cloud-stopped-recovery/evidence.test.mjs > "$$output" 2>&1; result=$$?; cat "$$output"; test "$$result" -eq 0 && grep -qx \'# tests [1-9][0-9]*\' "$$output" && grep -qx \'# fail 0\' "$$output" && grep -qx \'# cancelled 0\' "$$output" && grep -qx \'# skipped 0\' "$$output" && grep -qx \'# todo 0\' "$$output" && for expected in \'isolated PostgreSQL reconciliation\' \'managed reconciliation admits only the pinned target, TLS root and verified peer\' \'connected clients with startup options are refused\' \'owner-approved identity mapping holds both existing principals\' \'encrypted quarantine on disposable PostgreSQL 17\' \'SIGTERM stops a confirmed server before removing its fixture\' \'provider database CA is a valid self-signed root with the pinned DER fingerprint\' \'canonical input, exact project and clean environment are required before connecting\' \'CLI reports or reconciles commit with closed-stdout\' \'commissioning receipt transaction fixture\' \'exact immutable ciphertext is copied once with encrypted durable intent and receipt\' \'synthetic owner rebind reproduces Storage fingerprints while preserving ciphertext identity\' \'actual adapter reads, creates once and verifies synthetic protected bytes\' \'HTTPS client rejects a self-signed loopback server\' \'mutating an approved plan cannot redirect import or lost-ack reconciliation\' \'count-only financial graph inventory on owned PostgreSQL 17\' \'financial consistency is aggregate-only and read-only on owned PostgreSQL 17\' \'selected native source prerequisites are aggregate-only on owned PostgreSQL 17\' \'synthetic posted financial graphs transfer atomically with cloud-primary mapping\' \'synthetic accepted native SMS history and posted financial graph\' \'forward-only retention user ID correction on owned PostgreSQL 17\' \'synthetic full chain refuses divergent originals and runs pinned candidates without writing history\' \'history candidate keeps divergent originals unrecorded and uses distinct ordered versions\' \'all pinned non-WIP predecessors execute in order while both MFA sources remain absent\' \'deferred proposal keeps every non-WIP source action without inventing history\' \'a coherently mapped replay with an existing complete financial link performs no second write\' \'managed candidate on native PostgreSQL 17 without a postgres superuser\' \'a correctly serialized v2-style digest cannot authorize the v3 executor\' \'diagnostics rechecks after history insertion\' \'notification rechecks after history insertion\' \'signed commissioning transport with durable synthetic PostgreSQL receipts\' \'managed stopped-work evidence remains non-authorizing with synthetic PG snapshots\'; do grep -Eq "^[[:space:]]*ok [0-9]+ - $$expected$$" "$$output" || exit 1; done'
CURRENT_PROFILE_CONDITION = "needs.select-profile.outputs.profile == 'current-managed-cloud'"
SELECTED_SOURCE = '${{ needs.select-profile.outputs.source_sha }}'
CURRENT_NATIVE_JOB = 'current-managed-native'
CURRENT_NATIVE_MAKE_COMMAND = 'node scripts/supabase/cloud-release/initial-account-bootstrap.test.mjs'
CURRENT_NATIVE_COMMAND = r'''set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
node_bin="$(command -v node)"
gosu postgres test -x "$node_bin"
gosu postgres test -r scripts/supabase/cloud-release/initial-account-bootstrap.test.mjs
timeout --signal=TERM --kill-after=30s 180s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  COLLECT_SYNTHETIC_PG_BIN="$pg_bin_dir" \
  "$node_bin" scripts/supabase/cloud-release/initial-account-bootstrap.test.mjs'''
CURRENT_CLOUD_IDENTITY_COMMAND = (
    'node --test scripts/supabase/deployment-profile.test.mjs scripts/supabase/cloud-release/retained-source.test.mjs'
)
CURRENT_HTTP_NATIVE_COMMAND = '''set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
node_bin="$(command -v node)"
gosu postgres test -x "$node_bin"
gosu postgres test -r scripts/supabase/testing/http-admission-pg/qualify.mjs
"$node_bin" --test scripts/supabase/testing/managed-nonce-pg/report.test.mjs
timeout --signal=TERM --kill-after=120s 300s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  COLLECT_HTTP_ADMISSION_PG_QUALIFY=true \\
  COLLECT_HTTP_ADMISSION_PG_BIN_DIR="$pg_bin_dir" \\
  COLLECT_HTTP_ADMISSION_PG_TMP_ROOT=/tmp \\
  "$node_bin" scripts/supabase/testing/http-admission-pg/qualify.mjs'''
CURRENT_BURI_NATIVE_COMMAND = '''set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
node_bin="$(command -v node)"
gosu postgres test -x "$node_bin"
gosu postgres test -r scripts/supabase/testing/buri-isolated-pg/qualify.mjs
timeout --signal=TERM --kill-after=120s 180s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  COLLECT_BURI_TEST_PG_QUALIFY=true \\
  COLLECT_BURI_TEST_PG_BIN_DIR="$pg_bin_dir" \\
  COLLECT_BURI_TEST_TMP_ROOT=/tmp \\
  "$node_bin" scripts/supabase/testing/buri-isolated-pg/qualify.mjs
timeout --signal=TERM --kill-after=120s 75s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  COLLECT_BURI_TEST_PG_QUALIFY=true \\
  COLLECT_BURI_TEST_PG_BIN_DIR="$pg_bin_dir" \\
  COLLECT_BURI_TEST_TMP_ROOT=/tmp \\
  "$node_bin" --test-reporter=tap scripts/supabase/testing/buri-isolated-pg/interrupt.test.mjs'''
CURRENT_NONCE_NATIVE_COMMAND = '''set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
node_bin="$(command -v node)"
gosu postgres test -x "$node_bin"
gosu postgres test -r scripts/supabase/testing/managed-nonce-pg/qualify.mjs
"$node_bin" --test scripts/supabase/testing/managed-nonce-pg/report.test.mjs
timeout --signal=TERM --kill-after=120s 300s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  COLLECT_INGRESS_TEST_PG_BIN_DIR="$pg_bin_dir" \\
  "$node_bin" scripts/supabase/testing/managed-nonce-pg/qualify.mjs'''
CURRENT_PORTABILITY_NATIVE_COMMAND = '''set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
gosu postgres test -r scripts/supabase/managed-migration-portability/test_portability.py
timeout --signal=TERM --kill-after=5s 120s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  COLLECT_PORTABILITY_PG_BIN="$pg_bin_dir" PYTHONDONTWRITEBYTECODE=1 \\
  python3 scripts/supabase/managed-migration-portability/test_portability.py'''
CURRENT_NATIVE_CONTAINER_PREREQ = '''set -eu
test "$(id -u)" -eq 0
export DEBIAN_FRONTEND=noninteractive
timeout --signal=TERM --kill-after=5s 150s apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update
timeout --signal=TERM --kill-after=5s 150s apt-get -o Dpkg::Use-Pty=0 --yes --no-install-recommends --no-upgrade install ca-certificates git python3 tar gzip xz-utils openssl
command -v gosu >/dev/null
command -v initdb >/dev/null
command -v pg_ctl >/dev/null
command -v psql >/dev/null
command -v openssl >/dev/null'''
CURRENT_TRANSFER_NATIVE_COMMAND = '''set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
node_bin="$(command -v node)"
gosu postgres test -x "$node_bin"
gosu postgres test -x /usr/bin/openssl
for test_file in scripts/supabase/current-pg-transfer/reconcile.test.mjs scripts/supabase/current-pg-transfer/identity-mapping/identity.test.mjs scripts/supabase/managed-cloud-migrations/provider-ca.test.mjs scripts/supabase/managed-cloud-migrations/operator.test.mjs scripts/supabase/managed-cloud-migrations/operator-pg.test.mjs scripts/supabase/managed-cloud-migrations/event-trigger-preimage.test.mjs scripts/supabase/managed-cloud-migrations/migration-postconditions.test.mjs scripts/supabase/current-pg-transfer/batch-transfer/quarantine.test.mjs scripts/supabase/current-pg-transfer/test-support/lifecycle.test.mjs scripts/supabase/device-commissioning/fixture.test.mjs scripts/supabase/current-pg-transfer/object-transfer/transfer.test.mjs scripts/supabase/current-pg-transfer/object-transfer/scope-rebind.test.mjs scripts/supabase/current-pg-transfer/object-transfer/supabase-adapter.test.mjs scripts/supabase/current-pg-transfer/business-import/import.test.mjs scripts/supabase/current-pg-transfer/financial-inventory/inventory.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/consistency.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/native-readiness-v3/diagnostic.test.mjs scripts/supabase/current-pg-transfer/financial-import/import.test.mjs scripts/supabase/current-pg-transfer/native-sms-import/import.test.mjs scripts/supabase/retention-convergence/user-id-forward.test.mjs scripts/supabase/retention-convergence/ordered-chain-fixture.test.mjs scripts/supabase/retention-convergence/history-plan.test.mjs scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.test.mjs scripts/supabase/retention-convergence/deferred-mfa/history-proposal.test.mjs supabase/functions/_shared/tests/burimunsi/native-sms-ledger.test.mjs supabase/managed-deployment-identity/bind-managed-pg17.test.mjs scripts/supabase/device-commissioning/synthetic-transport.test.mjs supabase/managed-cloud-stopped-recovery/evidence.test.mjs; do gosu postgres test -r "$test_file"; done
output="$(mktemp /tmp/collect-current-transfer.XXXXXXXX)"
trap 'rm -f -- "$output"' EXIT
if ! timeout --signal=TERM --kill-after=120s 600s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/tmp COLLECT_SYNTHETIC_PG_BIN="$pg_bin_dir" \\
  "$node_bin" --test --test-concurrency=1 --test-timeout=180000 --test-reporter=tap scripts/supabase/current-pg-transfer/reconcile.test.mjs scripts/supabase/current-pg-transfer/identity-mapping/identity.test.mjs scripts/supabase/managed-cloud-migrations/provider-ca.test.mjs scripts/supabase/managed-cloud-migrations/operator.test.mjs scripts/supabase/managed-cloud-migrations/operator-pg.test.mjs scripts/supabase/managed-cloud-migrations/event-trigger-preimage.test.mjs scripts/supabase/managed-cloud-migrations/migration-postconditions.test.mjs scripts/supabase/current-pg-transfer/batch-transfer/quarantine.test.mjs scripts/supabase/current-pg-transfer/test-support/lifecycle.test.mjs scripts/supabase/device-commissioning/fixture.test.mjs scripts/supabase/current-pg-transfer/object-transfer/transfer.test.mjs scripts/supabase/current-pg-transfer/object-transfer/scope-rebind.test.mjs scripts/supabase/current-pg-transfer/object-transfer/supabase-adapter.test.mjs scripts/supabase/current-pg-transfer/business-import/import.test.mjs scripts/supabase/current-pg-transfer/financial-inventory/inventory.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/consistency.test.mjs scripts/supabase/current-pg-transfer/financial-consistency/native-readiness-v3/diagnostic.test.mjs scripts/supabase/current-pg-transfer/financial-import/import.test.mjs scripts/supabase/current-pg-transfer/native-sms-import/import.test.mjs scripts/supabase/retention-convergence/user-id-forward.test.mjs scripts/supabase/retention-convergence/ordered-chain-fixture.test.mjs scripts/supabase/retention-convergence/history-plan.test.mjs scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.test.mjs scripts/supabase/retention-convergence/deferred-mfa/history-proposal.test.mjs supabase/functions/_shared/tests/burimunsi/native-sms-ledger.test.mjs supabase/managed-deployment-identity/bind-managed-pg17.test.mjs scripts/supabase/device-commissioning/synthetic-transport.test.mjs supabase/managed-cloud-stopped-recovery/evidence.test.mjs > "$output" 2>&1; then cat "$output"; exit 1; fi
cat "$output"
grep -qx '# tests [1-9][0-9]*' "$output"
grep -qx '# fail 0' "$output"
grep -qx '# cancelled 0' "$output"
grep -qx '# skipped 0' "$output"
grep -qx '# todo 0' "$output"
for expected in 'isolated PostgreSQL reconciliation' 'managed reconciliation admits only the pinned target, TLS root and verified peer' 'connected clients with startup options are refused' 'owner-approved identity mapping holds both existing principals' 'encrypted quarantine on disposable PostgreSQL 17' 'SIGTERM stops a confirmed server before removing its fixture' 'provider database CA is a valid self-signed root with the pinned DER fingerprint' 'canonical input, exact project and clean environment are required before connecting' 'CLI reports or reconciles commit with closed-stdout' 'commissioning receipt transaction fixture' 'exact immutable ciphertext is copied once with encrypted durable intent and receipt' 'synthetic owner rebind reproduces Storage fingerprints while preserving ciphertext identity' 'actual adapter reads, creates once and verifies synthetic protected bytes' 'HTTPS client rejects a self-signed loopback server' 'mutating an approved plan cannot redirect import or lost-ack reconciliation' 'count-only financial graph inventory on owned PostgreSQL 17' 'financial consistency is aggregate-only and read-only on owned PostgreSQL 17' 'selected native source prerequisites are aggregate-only on owned PostgreSQL 17' 'synthetic posted financial graphs transfer atomically with cloud-primary mapping' 'synthetic accepted native SMS history and posted financial graph' 'forward-only retention user ID correction on owned PostgreSQL 17' 'synthetic full chain refuses divergent originals and runs pinned candidates without writing history' 'history candidate keeps divergent originals unrecorded and uses distinct ordered versions' 'all pinned non-WIP predecessors execute in order while both MFA sources remain absent' 'deferred proposal keeps every non-WIP source action without inventing history' 'a coherently mapped replay with an existing complete financial link performs no second write' 'managed candidate on native PostgreSQL 17 without a postgres superuser' 'a correctly serialized v2-style digest cannot authorize the v3 executor' 'diagnostics rechecks after history insertion' 'notification rechecks after history insertion' 'signed commissioning transport with durable synthetic PostgreSQL receipts' 'managed stopped-work evidence remains non-authorizing with synthetic PG snapshots'; do grep -Eq "^[[:space:]]*ok [0-9]+ - $expected$" "$output" || exit 1; done'''
CURRENT_SMS_NATIVE_COMMAND = '''set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
gosu postgres test -x "$COLLECT_DENO"
gosu postgres test -r test/local-postgres-fixture.ts
sms_deno_cache="$(mktemp -d /tmp/collect-sms-ci-deno-XXXXXXXX)"
trap 'rm -rf -- "$sms_deno_cache"' EXIT
chown postgres "$sms_deno_cache"
timeout --signal=TERM --kill-after=30s 120s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  DENO_DIR="$sms_deno_cache" DENO_TLS_CA_STORE=system \\
  "$COLLECT_DENO" cache --frozen-lockfile --lock=deno.lock --node-modules-dir=none test/local-postgres-fixture.ts
timeout --signal=TERM --kill-after=120s 180s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  COLLECT_SMS_TEST_PG_BIN="$pg_bin_dir" COLLECT_SMS_TEST_DENO_BIN="$COLLECT_DENO" \\
  COLLECT_SMS_TEST_DENO_DIR="$sms_deno_cache" ./test/run-local-postgres.sh
timeout --signal=TERM --kill-after=120s 180s gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
  COLLECT_SMS_TEST_PG_BIN="$pg_bin_dir" python3 test/signal-cleanup.test.py'''
CURRENT_SMS_SOURCE_COMMAND = 'python3 test/verify_source_tests_test.py && python3 test/verify_source_tests.py'
CURRENT_EMAIL_HANDLER_COMMAND = '"$COLLECT_DENO" test --frozen --lock=deno.lock _shared/tests/email-jobs.test.ts'
CURRENT_EMAIL_HANDLER_MAKE_COMMAND = 'cd supabase/functions && "$${COLLECT_DENO:-deno}" test --frozen --lock=deno.lock _shared/tests/email-jobs.test.ts'
CURRENT_COMMISSIONING_DENO_MAKE_COMMAND = 'output="$$(mktemp "$${TMPDIR:-/tmp}/collect-commission-deno.XXXXXXXX")" || exit 1; trap \'rm -f -- "$$output"\' EXIT; "$${COLLECT_DENO:-deno}" --version | grep -Eq \'^deno 2[.]9[.]6 \' || exit 1; "$${COLLECT_DENO:-deno}" test --frozen --lock=supabase/functions/deno.lock --reporter=tap scripts/supabase/device-commissioning/edge-smoke.test.ts > "$$output" 2>&1; result=$$?; cat "$$output"; test "$$result" -eq 0 && grep -Fqx \'ok 1 - synthetic Edge request signs and verifies commissioning receipt and acknowledgement\' "$$output" && grep -Fqx \'1..1\' "$$output"'
CURRENT_COMMISSIONING_DENO_COMMAND = 'set -eu\n"$COLLECT_DENO" --version | grep -Eq \'^deno 2[.]9[.]6 \'\noutput="$(mktemp /tmp/collect-commission-deno.XXXXXXXX)"\ntrap \'rm -f -- "$output"\' EXIT\nif ! "$COLLECT_DENO" test --frozen --lock=supabase/functions/deno.lock --reporter=tap scripts/supabase/device-commissioning/edge-smoke.test.ts > "$output" 2>&1; then cat "$output"; exit 1; fi\ncat "$output"\ngrep -Fqx \'ok 1 - synthetic Edge request signs and verifies commissioning receipt and acknowledgement\' "$output"\ngrep -Fqx \'1..1\' "$output"'
CURRENT_SOURCE_COMMANDS = (
    'python3 supabase/schema-src/generate_baseline.py --check',
    'node --test scripts/supabase/data-contracts.test.mjs',
    'python3 -m unittest scripts.supabase.test_cutover_gate scripts.supabase.test_admin_build_config scripts.tests.client_diagnostic_identity_test',
    'python3 -m unittest scripts.supabase.test_cloud_migration_preflight',
    'python3 -m unittest scripts.supabase.test_aggregate_inventory_reconcile',
    'python3 -m unittest scripts.supabase.test_catalogue_reconciliation',
    'python3 -m unittest scripts.supabase.test_catalogue_capture',
    'node --test --test-concurrency=1 scripts/supabase/testing/cloud-binder-fixture.test.mjs',
    'python3 -m unittest scripts.supabase.testing.test_qualification_source_manifest',
    'node --test deploy/managed-native-ingress/worker.test.mjs',
    'node --test deploy/managed-native-ingress/handler-integration/cloud-only-handler-integration.test.mjs',
    'node --test --test-concurrency=1 supabase/managed-native-ingress/nonce-ledger.test.mjs',
    'node --test --test-concurrency=1 supabase/managed-deployment-identity/bind-managed.test.mjs',
    'node --test scripts/supabase/testing/buri-isolated-pg/report.test.mjs',
    CURRENT_SMS_SOURCE_COMMAND,
    CURRENT_EMAIL_HANDLER_COMMAND,
    CURRENT_COMMISSIONING_DENO_COMMAND,
    'node --test scripts/supabase/atomic_cloud_migration.test.mjs',
    'node --test scripts/supabase/managed-storage-archive-v2/*.test.mjs',
    'node --test scripts/supabase/cloud-data-transfer/compile.test.mjs scripts/supabase/cloud-data-transfer/existing-storage.test.mjs',
    CURRENT_CLOUD_IDENTITY_COMMAND,
    'node scripts/supabase/run_edge_node_tests.mjs',
    'node --test deploy/platform-admin/test/backend-selection.test.mjs deploy/platform-admin/test/supabase-transport.test.mjs',
    'node --test test/supabase-free-transport.test.mjs test/local-challenge-parent.test.mjs',
    '"$COLLECT_DENO" task check',
)


def validate_current_supabase_qualification(workflows: dict[str, dict]) -> list[dict[str, str]]:
    """Require current Cloud source contracts and synthetic PostgreSQL qualification.

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
    dispatch = events.get('workflow_dispatch', {}) if isinstance(events, dict) else {}
    profile_input = dispatch.get('inputs', {}).get('qualification_profile', {}) if isinstance(dispatch, dict) else {}
    if (profile_input.get('default') != 'current-managed-cloud'
            or profile_input.get('options') != ['current-managed-cloud', 'historical-standard',
                                                 'historical-current14', 'historical-current16']):
        fail('select-profile')
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
            "assert historical or profile == 'current-managed-cloud'",
        )
        if (step.get('env', {}).get('PROFILE') != "${{ inputs.qualification_profile || 'current-managed-cloud' }}"
                or step.get('env', {}).get('REVIEWED_SHA') != '${{ inputs.reviewed_historical_commit }}'
                or any(line not in command for line in required)):
            fail('select-profile')
    current_names = ('current-source-contracts', CURRENT_NATIVE_JOB)
    for name in current_names:
        job = jobs.get(name, {})
        needs = job.get('needs', [])
        needs = [needs] if isinstance(needs, str) else needs
        if (set(needs) != {'select-profile'} or job.get('if') != CURRENT_PROFILE_CONDITION
                or job.get('continue-on-error', False) is not False):
            fail(name)
        checkout = [step for step in job.get('steps', []) if str(step.get('uses', '')).startswith('actions/checkout@')]
        if len(checkout) != 1 or checkout[0].get('with', {}).get('ref') != SELECTED_SOURCE or 'if' in checkout[0]:
            fail(name)
    source = jobs.get('current-source-contracts', {})
    if source.get('env', {}).get('COLLECT_DENO') != '${{ github.workspace }}/scripts/supabase/node_modules/@deno/linux-x64-glibc/deno':
        fail('current-source-contracts')
    source_steps = source.get('steps', [])
    for command in CURRENT_SOURCE_COMMANDS:
        matches = [step for step in source_steps if step.get('run', '').strip() == command]
        if (len(matches) != 1 or 'if' in matches[0]
                or matches[0].get('continue-on-error', False) is not False):
            fail('current-source-contracts')
        elif command == CURRENT_SMS_SOURCE_COMMAND and matches[0].get('working-directory') != 'deploy/managed-sms':
            fail('current-source-contracts')
        elif command == CURRENT_COMMISSIONING_DENO_COMMAND and matches[0].get('working-directory', '.') != '.':
            fail('current-source-contracts')
        elif command == CURRENT_EMAIL_HANDLER_COMMAND and matches[0].get('working-directory') != 'supabase/functions':
            fail('current-source-contracts')
    for required in ('scripts/supabase/testing/current16-integration.test.mjs',
                     'scripts/supabase/jobs-config-contracts.test.mjs'):
        matches = [step for step in source_steps if required in step.get('run', '')]
        if (len(matches) != 1 or 'if' in matches[0] or '||' in matches[0].get('run', '')
                or matches[0].get('continue-on-error', False) is not False):
            fail('current-source-contracts')
    native = jobs.get(CURRENT_NATIVE_JOB, {})
    expected = {
        'COLLECT_CI_SYNTHETIC': 'true',
        'COLLECT_DENO': '${{ github.workspace }}/scripts/supabase/node_modules/@deno/linux-x64-glibc/deno',
        'DENO_TLS_CA_STORE': 'system',
    }
    if native.get('env', {}) != expected:
        fail(CURRENT_NATIVE_JOB)
    native_steps = native.get('steps', [])
    prerequisites = [step for step in native_steps if step.get('run', '').strip() == CURRENT_NATIVE_CONTAINER_PREREQ]
    transfer_steps = [step for step in native_steps if step.get('run', '').strip() == CURRENT_TRANSFER_NATIVE_COMMAND]
    if (len(prerequisites) != 1 or 'if' in prerequisites[0]
            or prerequisites[0].get('continue-on-error', False) is not False
            or len(transfer_steps) != 1 or native_steps.index(prerequisites[0]) >= native_steps.index(transfer_steps[0])):
        fail(CURRENT_NATIVE_JOB)
    for command in (
        CURRENT_HTTP_NATIVE_COMMAND, CURRENT_BURI_NATIVE_COMMAND, CURRENT_NONCE_NATIVE_COMMAND,
        CURRENT_PORTABILITY_NATIVE_COMMAND, CURRENT_TRANSFER_NATIVE_COMMAND, CURRENT_SMS_NATIVE_COMMAND,
        CURRENT_NATIVE_COMMAND,
    ):
        matches = [step for step in native_steps if step.get('run', '').strip() == command]
        if len(matches) != 1 or 'if' in matches[0] or matches[0].get('continue-on-error', False) is not False:
            fail(CURRENT_NATIVE_JOB)
        elif command == CURRENT_SMS_NATIVE_COMMAND and matches[0].get('working-directory') != 'deploy/managed-sms':
            fail(CURRENT_NATIVE_JOB)
    # The owned Cloud fixtures report via the job log. Raw fixture files are
    # never published by this job.
    if any(str(step.get('uses', '')).startswith('actions/upload-artifact@') for step in native_steps):
        fail(CURRENT_NATIVE_JOB)
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
                                      '$(MAKE) supabase-current-transfer-test',
                                      '$(MAKE) supabase-admin-consumers-test']):
        findings.append({'workflow': 'Makefile', 'job': 'supabase-test',
                         'code': 'CI_CURRENT_MAKE_QUALIFICATION_REQUIRED'})
    for name, expected in (
        ('supabase-current-native', [CURRENT_NATIVE_MAKE_COMMAND]),
        ('supabase-current-transfer-test', ['test "$$(id -u)" -ne 0',
                                           'test -n "$${COLLECT_SYNTHETIC_PG_BIN:-}"',
                                           'test "$$(cd "$$COLLECT_SYNTHETIC_PG_BIN" && pwd -P)" = "$$COLLECT_SYNTHETIC_PG_BIN"',
                                           'command -v openssl >/dev/null',
                                           CURRENT_TRANSFER_MAKE_COMMAND]),
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
        'node --test scripts/supabase/cloud-data-transfer/compile.test.mjs scripts/supabase/cloud-data-transfer/existing-storage.test.mjs',
        CURRENT_CLOUD_IDENTITY_COMMAND,
        'node --test --test-concurrency=1 scripts/supabase/testing/cloud-binder-fixture.test.mjs',
    'python3 -m unittest scripts.supabase.testing.test_qualification_source_manifest',
    'node --test deploy/managed-native-ingress/worker.test.mjs',
        'node --test deploy/managed-native-ingress/handler-integration/cloud-only-handler-integration.test.mjs',
        'cd deploy/managed-sms && python3 test/verify_source_tests_test.py && python3 test/verify_source_tests.py',
        CURRENT_COMMISSIONING_DENO_MAKE_COMMAND,
        CURRENT_EMAIL_HANDLER_MAKE_COMMAND,
        'cd supabase/functions && "$${COLLECT_DENO:-deno}" task check',
    )
    if (count != 1 or any(commands.count(command) != 1 for command in required)
            or any(legacy_execution(command, '.') for command in commands)):
        findings.append({'workflow': 'Makefile', 'job': 'supabase-source-test',
                         'code': 'CI_CURRENT_MAKE_SOURCE_REQUIRED'})
    return findings


def retired_admin_sources(root: Path) -> list[dict[str, str]]:
    paths = list((root / "lib").glob("main*admin*.dart"))
    for name in ("lib/admin", "test/admin"):
        directory = root / name
        if directory.is_symlink():
            paths.append(directory)
        elif directory.is_dir():
            paths.extend(path for path in directory.rglob("*") if path.is_file() or path.is_symlink())
    return [
        {"workflow": "source", "job": path.relative_to(root).as_posix(), "code": "CI_FLUTTER_ADMIN_SOURCE_RETIRED"}
        for path in sorted(paths)
    ]


def inspect(root: Path) -> dict:
    folder = root / ".github/workflows"
    paths = workflow_paths(folder)
    if not paths:
        raise PolicyInputError("CI_POLICY_WORKFLOWS_MISSING")
    workflows = {path.name: read_workflow(path) for path in paths}
    findings = validate_workflows(workflows)
    findings.extend(retired_admin_sources(root))
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
