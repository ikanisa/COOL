#!/usr/bin/env python3
"""Deliver externally approved export bytes; never create an approval.

Hash/metadata agreement does not authenticate a human or attest the hosted
compiler. Protected authorized review and hosted acceptance remain separate.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlparse
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent))
import collect_release_candidate as candidate
import postgres_admission

BASE_FILES = {
    '.supabase-cli-version', '.dvmrc', 'supabase/config.toml',
    'supabase/functions/deno.lock', 'contracts/edge-functions.json',
    'scripts/supabase_deploy.sh', 'scripts/supabase_cli_helpers.sh',
    'scripts/load_dotenv_strict.sh', 'scripts/edge_function_inventory.sh',
    'scripts/edge_function_inventory.rb', 'scripts/qa/backend_release_delivery.py',
    'scripts/qa/collect_release_candidate.py', 'scripts/qa/postgres_admission.py',
    'scripts/migrations/validate_supabase_migrations.sh',
}
READINESS_FILES = {
    'scripts/supabase_production_readiness.sh', 'scripts/supabase_schema_inventory.sh',
    'scripts/audits/collect_index_inventory.rb', 'scripts/supabase_advisors_gate.sh',
    'scripts/supabase_advisors_warning_inventory.sh', 'scripts/collect_linked_uat.sh',
    'scripts/rwanda_momo_readiness_uat.sql', 'scripts/collect_admin_security_uat.sh',
}
OPERATIONS = ('migrations', 'retired_functions', 'edge_functions', 'strict_production_readiness')
HASH = re.compile(r'[a-f0-9]{64}')
REF = re.compile(r'[a-z0-9]{20}')
HISTORY_QUERY = 'select version, name from supabase_migrations.schema_migrations order by version;'
LIMIT = 2 * 1024 * 1024
MANAGEMENT_GUARD = '\n'.join([
    '. "$1"',
    'supabase_management_curl() {',
    '  "$COLLECT_BACKEND_PYTHON" -B "$COLLECT_BACKEND_GUARD_HELPER" guard --before-database-request --launcher-root "$COLLECT_BACKEND_LAUNCHER_ROOT" --execution-root "$COLLECT_BACKEND_EXECUTION_ROOT" || return $?',
    '  collect_curl_secret_header Authorization "Bearer $SUPABASE_ACCESS_TOKEN" --max-time 60 "$@"',
    '}',
])


class Blocked(ValueError):
    pass


def unique(items):
    result = {}
    for key, value in items:
        if key in result:
            raise Blocked('DEPLOY_DUPLICATE_JSON_KEY')
        result[key] = value
    return result


def json_data(raw):
    try:
        return json.loads(raw, object_pairs_hook=unique)
    except (ValueError, UnicodeError) as error:
        raise Blocked('DEPLOY_JSON_INVALID') from error


def checked_path(path):
    result = Path(path).absolute()
    if any(p.is_symlink() for p in (result, *result.parents)):
        raise Blocked('DEPLOY_SYMLINK_REFUSED')
    return result


def external_bytes(path):
    path = checked_path(path)
    return candidate.regular_bytes(path.parent, path.name)[0]


def entry(root, name):
    data, mode = candidate.regular_bytes(root, name)
    return {'sha256': candidate.sha(data), 'bytes': len(data), 'mode': mode}


def backend_files(manifest):
    files = manifest['source_files']
    if not BASE_FILES <= files.keys() or not any(n.startswith('supabase/migrations/') and n.endswith('.sql') for n in files):
        raise Blocked('DEPLOY_BACKEND_INPUTS_INCOMPLETE')
    return {n: v for n, v in files.items() if n.startswith('supabase/') or n in BASE_FILES | READINESS_FILES}


def current_backend(root):
    names = set(BASE_FILES) | {n for n in READINESS_FILES if (root / n).exists()}
    for parent, dirs, files in os.walk(root / 'supabase', followlinks=False):
        rel = Path(parent).relative_to(root)
        # Worktree link state is never imported. Reviewed candidate source has
        # no .temp exception; execution metadata has its own narrow validator.
        if rel.as_posix() == 'supabase':
            dirs[:] = [d for d in dirs if d != '.temp']
        if any((Path(parent) / n).is_symlink() for n in dirs):
            raise Blocked('DEPLOY_SYMLINK_REFUSED')
        names.update((rel / n).as_posix() for n in files)
    return {n: entry(root, n) for n in sorted(names)}


def verified_export(path, expected):
    if not HASH.fullmatch(expected or ''):
        raise Blocked('DEPLOY_MANIFEST_HASH_REQUIRED')
    report = candidate.verify_candidate(checked_path(path), expected_manifest_sha256=expected)
    if report['status'] != 'pass':
        raise Blocked('DEPLOY_CANDIDATE_DIRTY_OR_INCOMPLETE')
    manifest = json_data(external_bytes(Path(path) / candidate.MANIFEST))
    if manifest.get('retain_source_drift') or manifest.get('capture_classification') != 'strict_unapproved_source_export':
        raise Blocked('DEPLOY_NON_ATOMIC_CANDIDATE_REFUSED')
    return manifest


def instant(text):
    try:
        value = dt.datetime.fromisoformat(text.replace('Z', '+00:00'))
        if value.utcoffset() != dt.timedelta(0):
            raise ValueError()
        return value
    except (AttributeError, TypeError, ValueError) as error:
        raise Blocked('DEPLOY_APPROVAL_TIME_INVALID') from error


def approval_record(args, manifest, backend):
    raw = external_bytes(args.approval)
    if len(raw) > 65536 or not HASH.fullmatch(args.approval_sha256 or '') or candidate.sha(raw) != args.approval_sha256:
        raise Blocked('DEPLOY_APPROVAL_HASH_CHANGED_OR_UNBOUND')
    value = json_data(raw)
    keys = {'schema_version', 'kind', 'approval_id', 'reviewer', 'approved_at_utc', 'expires_at_utc',
            'candidate_manifest_sha256', 'backend_manifest_sha256', 'target', 'purpose', 'operations', 'toolchain'}
    if not isinstance(value, dict) or set(value) != keys or value['schema_version'] != 1 or value['kind'] != 'collect_backend_deployment_approval':
        raise Blocked('DEPLOY_APPROVAL_SCHEMA_INVALID')
    try:
        uuid.UUID(value['approval_id'])
    except (ValueError, AttributeError, TypeError) as error:
        raise Blocked('DEPLOY_APPROVAL_ID_INVALID') from error
    reviewer = value['reviewer']
    if not isinstance(reviewer, str) or not 1 <= len(reviewer.strip()) <= 160 or any(ord(c) < 32 for c in reviewer):
        raise Blocked('DEPLOY_REVIEWER_METADATA_REQUIRED')
    now = dt.datetime.now(dt.timezone.utc)
    approved, expires = instant(value['approved_at_utc']), instant(value['expires_at_utc'])
    if approved > now or expires <= now or not dt.timedelta(0) < expires - approved <= dt.timedelta(hours=24):
        raise Blocked('DEPLOY_APPROVAL_EXPIRED_OR_FUTURE')
    if value['candidate_manifest_sha256'] != args.manifest_sha256 or value['backend_manifest_sha256'] != candidate.sha(candidate.canonical(backend)):
        raise Blocked('DEPLOY_APPROVAL_SOURCE_BINDING_WRONG')
    target = value['target']
    if not isinstance(target, dict) or set(target) != {'project_ref', 'url', 'environment'}:
        raise Blocked('DEPLOY_TARGET_INVALID')
    ref, url, environment = target['project_ref'], target['url'], target['environment']
    if not isinstance(ref, str) or not REF.fullmatch(ref) or url != f'https://{ref}.supabase.co' or environment not in {'staging', 'production'}:
        raise Blocked('DEPLOY_TARGET_INVALID')
    observed = (os.environ.get('SUPABASE_PROJECT_REF'), os.environ.get('SUPABASE_URL', '').rstrip('/'), args.environment, os.environ.get('CONFIRM_SUPABASE_DEPLOY'))
    if observed != (ref, url, environment, ref):
        raise Blocked('DEPLOY_TARGET_OR_ENVIRONMENT_DOES_NOT_MATCH_APPROVAL')
    if value['purpose'] not in {'staging_rollout', 'remediation', 'production_release'} or value['purpose'] == 'staging_rollout' and environment != 'staging':
        raise Blocked('DEPLOY_PURPOSE_INVALID')
    ops = value['operations']
    if not isinstance(ops, list) or not ops or ops != [op for op in OPERATIONS if op in ops] or any(op not in OPERATIONS for op in ops):
        raise Blocked('DEPLOY_OPERATION_SCOPE_INVALID')
    if 'strict_production_readiness' in ops and (environment != 'production' or not READINESS_FILES <= manifest['source_files'].keys()):
        raise Blocked('DEPLOY_STRICT_READINESS_SCOPE_INVALID')
    return value


def runtime_metadata(stage, ref):
    root = stage / 'supabase/.temp'
    allowed = {'project-ref', 'pooler-url', 'linked-project.json', 'postgres-version', 'rest-version',
               'gotrue-version', 'storage-version', 'storage-migration', 'cli-latest'}
    if not root.is_dir() or root.is_symlink():
        raise Blocked('DEPLOY_RUNTIME_LINK_INVALID')
    for path in root.iterdir():
        if path.name not in allowed or not path.is_file() or path.is_symlink():
            raise Blocked('DEPLOY_RUNTIME_METADATA_UNLISTED')
        raw = external_bytes(path)
        if len(raw) > 16384:
            raise Blocked('DEPLOY_RUNTIME_METADATA_INVALID')
        text = raw.decode('utf-8').strip()
        if path.name == 'project-ref' and text != ref:
            raise Blocked('DEPLOY_RUNTIME_TARGET_CHANGED')
        elif path.name == 'pooler-url':
            p = urlparse(text)
            bound = p.hostname == f'db.{ref}.supabase.co' or ((p.hostname or '').endswith('.pooler.supabase.com') and p.username == f'postgres.{ref}')
            if p.scheme not in {'postgres', 'postgresql'} or not bound or p.password or p.query or p.fragment or p.path != '/postgres':
                raise Blocked('DEPLOY_RUNTIME_TARGET_CHANGED')
        elif path.name == 'linked-project.json':
            value = json_data(raw)
            if not isinstance(value, dict) or set(value) - {'ref', 'name', 'organization_id', 'organization_slug'} or value.get('ref') != ref:
                raise Blocked('DEPLOY_RUNTIME_TARGET_CHANGED')
        elif path.name not in {'project-ref', 'pooler-url'} and not re.fullmatch(r'[A-Za-z0-9._+:/-]{0,160}', text):
            raise Blocked('DEPLOY_RUNTIME_METADATA_INVALID')


def database_target(url, ref):
    parsed = urlparse(url)
    bound = parsed.hostname == f'db.{ref}.supabase.co' or ((parsed.hostname or '').endswith('.pooler.supabase.com') and parsed.username == f'postgres.{ref}')
    if parsed.scheme not in {'postgres', 'postgresql'} or not bound or parsed.path != '/postgres' or parsed.fragment:
        raise Blocked('DEPLOY_DATABASE_TARGET_INVALID')


class Delivery:
    def __init__(self, args):
        self.args, self.stage, self.manifest, self.backend, self.approval = args, None, None, None, None
        self.launcher, self.source = checked_path(args.launcher_root), checked_path(args.candidate)
        self.record_path = checked_path(args.receipt)
        self.record_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(self.record_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        os.close(fd)
        self.record = {'schema_version': 1, 'kind': 'collect_backend_delivery_receipt', 'attempt_id': str(uuid.uuid4()),
                       'started_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'status': 'preflight',
                       'candidate_manifest_sha256': args.manifest_sha256, 'approval_sha256': args.approval_sha256,
                       'operations': [], 'readback': {}, 'human_identity_authenticated': False,
                       'production_release_accepted': False, 'automatic_retries': 0}
        self.pg = None
        self.save()

    def save(self):
        fd = os.open(self.record_path, os.O_WRONLY | os.O_TRUNC | getattr(os, 'O_NOFOLLOW', 0))
        with os.fdopen(fd, 'wb') as handle:
            handle.write(candidate.canonical(self.record)); handle.flush(); os.fsync(handle.fileno())

    def guard(self):
        verified_export(self.source, self.args.manifest_sha256)
        if self.backend != current_backend(self.launcher):
            raise Blocked('DEPLOY_CURRENT_BACKEND_SOURCE_CHANGED')
        if approval_record(self.args, self.manifest, self.backend) != self.approval:
            raise Blocked('DEPLOY_APPROVAL_CHANGED')
        for name, path in self.tools.items():
            if candidate.sha(path.read_bytes()) != self.approval['toolchain'][name]['binary_sha256']:
                raise Blocked('DEPLOY_TOOL_CHANGED')
        if self.pg is not None:
            self.pg.guard()
        if self.stage:
            runtime_metadata(self.stage, self.approval['target']['project_ref'])
            report = candidate.verify_candidate(self.stage, expected_manifest_sha256=self.args.manifest_sha256)
            changes = [r for r in report['changes'] if not (r['reason'] == 'candidate_unlisted_file' and r['path'].startswith('supabase/.temp/') and '/' not in r['path'][len('supabase/.temp/'):])]
            if changes:
                raise Blocked('DEPLOY_EXECUTION_EXPORT_CHANGED')

    def command(self, name, argv, mutating=False, timeout=180, check=True):
        self.guard()
        if mutating and self.pg is not None:
            self.admit_server()
            self.guard()
        if len(self.record['operations']) >= 128:
            raise Blocked('DEPLOY_OPERATION_LIMIT')
        op = {'name': name, 'mutating': mutating, 'status': 'started', 'started_at_utc': dt.datetime.now(dt.timezone.utc).isoformat()}
        self.record['operations'].append(op); self.save(); started = time.monotonic()
        try:
            with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
                p = subprocess.Popen(argv, cwd=self.stage, env=self.env, stdout=stdout, stderr=stderr, start_new_session=True)
                try:
                    code = p.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGKILL); p.wait()
                    raise Blocked('DEPLOY_OPERATION_TIMEOUT')
                stdout.seek(0); stderr.seek(0)
                data, errors = stdout.read(LIMIT + 1), stderr.read(LIMIT + 1)
                if max(len(data), len(errors)) > LIMIT:
                    raise Blocked('DEPLOY_OPERATION_OUTPUT_LIMIT')
            op.update(exit_code=code, output_sha256=candidate.sha(data + errors), output_bytes=len(data) + len(errors), status='acknowledged' if not code else 'failed')
        except (OSError, Blocked) as error:
            op.update(status='uncertain' if mutating else 'failed', error=str(error) if isinstance(error, Blocked) else 'DEPLOY_COMMAND_UNAVAILABLE')
            raise
        finally:
            op['elapsed_seconds'] = round(time.monotonic() - started, 3); self.save()
        if code and check:
            if mutating:
                op['remote_effects'] = 'unknown_until_readback; earlier operations may remain committed'; self.save()
            raise Blocked('DEPLOY_OPERATION_FAILED:' + name)
        return code, data, errors

    def cli(self, name, args, **kwargs):
        return self.command(name, ['bash', '-c', '. "$1"; shift; supabase_cli "$@"', 'bash', str(self.stage / 'scripts/supabase_cli_helpers.sh'), *args], **kwargs)

    def management(self, name, query):
        return self.command(name, ['bash', '-c', MANAGEMENT_GUARD + '\nsupabase_management_query "$2"', 'bash', str(self.stage / 'scripts/supabase_cli_helpers.sh'), query])

    def admit_server(self):
        # This is a target-bound remote SELECT, not local evidence of a server.
        _, raw, _ = self.management('postgres_server_compatibility', postgres_admission.SERVER_QUERY)
        self.record['readback']['postgresql'] = self.pg.management_rows(raw, self.approval['target']['project_ref'])
        self.save()

    def guard_server_transport(self):
        # Recheck immediately before each Management API query (including each
        # migration in a fallback batch). Use the reviewed helper without its
        # recursive transport guard for this exact read-only observation.
        self.guard()
        ref = self.approval['target']['project_ref']
        self.pg.project(ref)
        script = '. "$1"; supabase_management_curl() { collect_curl_secret_header Authorization "Bearer $SUPABASE_ACCESS_TOKEN" --connect-timeout 5 --max-time 20 "$@"; }; supabase_management_query "$2"'
        code, raw = postgres_admission.bounded(['bash', '-c', script, 'bash', str(self.stage / 'scripts/supabase_cli_helpers.sh'), postgres_admission.SERVER_QUERY], os.environ.copy(), self.pg.value['timeouts']['server_seconds'], limit=16384)
        if code:
            raise postgres_admission.Refused('PG_SERVER_OBSERVATION_FAILED')
        self.pg.management_rows(raw, ref)
        self.guard()

    def history(self, name):
        _, raw, _ = self.management(name, HISTORY_QUERY); rows = json_data(raw)
        if not isinstance(rows, list) or any(not isinstance(r, dict) or set(r) != {'version', 'name'} or not isinstance(r['version'], str) or not isinstance(r['name'], str) for r in rows):
            raise Blocked('DEPLOY_MIGRATION_READBACK_INVALID')
        versions = [r['version'] for r in rows]
        if len(set(versions)) != len(versions) or versions != sorted(versions):
            raise Blocked('DEPLOY_MIGRATION_READBACK_INVALID')
        return rows

    def readback(self, final, scope=None):
        ops = scope if scope is not None else self.approval['operations']
        if 'migrations' in ops:
            rows = self.history('migration_readback')
            expected = [{'version': p.name.split('_', 1)[0], 'name': p.name.split('_', 1)[1][:-4]} for p in sorted((self.stage / 'supabase/migrations').glob('*.sql'))]
            self.record['readback']['migrations'] = {'matches_candidate': rows == expected, 'versions': [r['version'] for r in rows]}; self.save()
            if final and rows != expected:
                raise Blocked('DEPLOY_MIGRATION_READBACK_MISMATCH')
        if {'edge_functions', 'retired_functions'} & set(ops):
            _, raw, _ = self.cli('function_readback', ['functions', 'list', '--project-ref', self.approval['target']['project_ref'], '-o', 'json'])
            rows = json_data(raw)
            if not isinstance(rows, list) or any(not isinstance(r, dict) or not isinstance(r.get('name'), str) or not isinstance(r.get('verify_jwt'), bool) for r in rows):
                raise Blocked('DEPLOY_FUNCTION_READBACK_INVALID')
            observed = {r['name']: r['verify_jwt'] for r in rows}
            if len(observed) != len(rows):
                raise Blocked('DEPLOY_FUNCTION_READBACK_INVALID')
            expected = {r['name']: r['verify_jwt'] for r in self.edge['functions']}
            matches = ('edge_functions' not in ops or all(observed.get(n) == mode for n, mode in expected.items())) and ('retired_functions' not in ops or not set(observed) & set(self.edge['retired']))
            self.record['readback']['functions'] = {'matches_candidate_scope': matches, 'observed_auth_modes': observed}; self.save()
            if final and not matches:
                raise Blocked('DEPLOY_FUNCTION_READBACK_MISMATCH')

    def execute(self):
        self.command('edge_inventory', ['ruby', str(self.stage / 'scripts/edge_function_inventory.rb'), 'auth-check'])
        self.command('migration_validation', ['bash', str(self.stage / 'scripts/migrations/validate_supabase_migrations.sh')])
        indexes = ['supabase/functions/' + row['name'] + '/index.ts' for row in self.edge['functions']]
        self.command('frozen_cached_handler_closure', [str(self.tools['deno']), 'test', '--no-run', '--no-config', '--cached-only', '--no-prompt', '--frozen', '--lock=supabase/functions/deno.lock', *indexes])
        ref, ops = self.approval['target']['project_ref'], self.approval['operations']
        if self.pg is not None:
            self.admit_server()
        _, raw, _ = self.cli('project_visibility', ['projects', 'list', '-o', 'json']); projects = json_data(raw)
        if not isinstance(projects, list) or not any(isinstance(p, dict) and ref in (p.get('id'), p.get('ref')) for p in projects):
            raise Blocked('DEPLOY_PROJECT_NOT_VISIBLE')
        if 'migrations' in ops:
            self.cli('isolated_target_link', ['link', '--project-ref', ref])
            before = self.history('migration_pre_readback')
            versions = [p.name.split('_', 1)[0] for p in sorted((self.stage / 'supabase/migrations').glob('*.sql'))]
            if any(r['version'] not in versions for r in before):
                raise Blocked('DEPLOY_REMOTE_HISTORY_OUTSIDE_CANDIDATE')
            self.record['migration_versions_before'] = [r['version'] for r in before]
            code, stdout, stderr = self.cli('migration_dry_run', ['db', 'push', '--dry-run', '--skip-vault'], check=False)
            if not code:
                self.cli('migration_apply_direct', ['db', 'push', '--skip-vault'], mutating=True)
            elif any(token in stdout + stderr for token in (b'tenant allow_list', b'EADDRNOTALLOWED', b'failed to connect to postgres')):
                self.command('migration_apply_management', ['bash', '-c', MANAGEMENT_GUARD + '\nsupabase_management_apply_pending_migrations "$2"', 'bash', str(self.stage / 'scripts/supabase_cli_helpers.sh'), str(self.stage / 'supabase/migrations')], mutating=True)
            else:
                raise Blocked('DEPLOY_MIGRATION_DRY_RUN_REFUSED')
            self.readback(final=True, scope=['migrations'])
        if 'retired_functions' in ops:
            _, raw, _ = self.cli('retired_function_inventory', ['functions', 'list', '--project-ref', ref, '-o', 'json']); rows = json_data(raw)
            if not isinstance(rows, list) or any(not isinstance(r, dict) or not isinstance(r.get('name'), str) for r in rows):
                raise Blocked('DEPLOY_FUNCTION_INVENTORY_INVALID')
            present = {row['name'] for row in rows}
            for name in self.edge['retired']:
                if name in present:
                    self.cli('delete_retired:' + name, ['functions', 'delete', name, '--project-ref', ref, '--yes'], mutating=True)
        if 'edge_functions' in ops:
            for row in self.edge['functions']:
                flags = [] if row['verify_jwt'] else ['--no-verify-jwt']
                self.cli('deploy_function:' + row['name'], ['functions', 'deploy', row['name'], '--project-ref', ref, *flags], mutating=True)
        self.readback(final=True)
        if 'strict_production_readiness' in ops:
            self.env['SUPABASE_READY_STRICT_PLATFORM'] = '1'
            self.command('strict_production_readiness_including_rollback_uat', ['bash', str(self.stage / 'scripts/supabase_production_readiness.sh')], mutating=True, timeout=600)

    def run(self):
        try:
            self.manifest = verified_export(self.source, self.args.manifest_sha256)
            self.backend = backend_files(self.manifest)
            self.approval = approval_record(self.args, self.manifest, self.backend)
            self.tools = {}
            declared = self.approval['toolchain']
            database_scope = bool({'migrations', 'strict_production_readiness'} & set(self.approval['operations']))
            required_tools = {'supabase', 'supabase_go', 'deno'} | ({'postgresql'} if database_scope else set())
            if not isinstance(declared, dict) or set(declared) != required_tools:
                raise Blocked('DEPLOY_TOOLCHAIN_BINDING_INVALID')
            for name, pin_file, override in [('supabase', '.supabase-cli-version', 'SUPABASE_BIN'),
                                            ('supabase_go', '.supabase-cli-version', 'SUPABASE_GO_BINARY'),
                                            ('deno', '.dvmrc', 'DENO_BIN')]:
                if name == 'supabase_go':
                    suffix = '.exe' if self.tools['supabase'].suffix == '.exe' else ''
                    selected = os.environ.get(override) or str(self.tools['supabase'].with_name('supabase-go' + suffix))
                    if not Path(selected).is_file():
                        raise Blocked('DEPLOY_SUPABASE_COMPANION_MISSING')
                else:
                    selected = os.environ.get(override) or shutil.which(name)
                if not selected:
                    raise Blocked('DEPLOY_TOOL_MISSING')
                path = Path(selected).resolve(strict=True)
                pin = external_bytes(self.source / pin_file).decode().strip()
                if not path.is_file() or not os.access(path, os.X_OK) or not re.fullmatch(r'\d+\.\d+\.\d+', pin) or declared[name] != {'version': pin, 'binary_sha256': candidate.sha(path.read_bytes())}:
                    raise Blocked('DEPLOY_TOOLCHAIN_BINDING_INVALID')
                p = subprocess.run([str(path), '--version'], capture_output=True, timeout=10)
                text = p.stdout.decode('utf-8', errors='replace').strip()
                matches = text.splitlines()[0] == 'deno ' + pin if name == 'deno' and text else text == pin
                if p.returncode or not matches:
                    raise Blocked('DEPLOY_CLI_OR_DENO_DOES_NOT_MATCH_REPOSITORY_VERSION')
                self.tools[name] = path
            if database_scope:
                self.pg = postgres_admission.Admission.from_environment(operation='migration' if 'migrations' in self.approval['operations'] else 'query')
                if declared['postgresql'] != {'manifest_sha256': self.pg.expected}:
                    raise Blocked('DEPLOY_POSTGRES_MANIFEST_BINDING_INVALID')
                self.pg.project(self.approval['target']['project_ref'])
            self.edge = json_data(external_bytes(self.source / 'contracts/edge-functions.json'))
            credential_names = ['SUPABASE_ACCESS_TOKEN']
            if {'migrations', 'strict_production_readiness'} & set(self.approval['operations']):
                credential_names.append('SUPABASE_DB_PASSWORD')
            if 'strict_production_readiness' in self.approval['operations']:
                credential_names.append('DATABASE_URL')
            if any(not os.environ.get(n) for n in credential_names):
                raise Blocked('DEPLOY_CREDENTIAL_ENVIRONMENT_MISSING')
            if 'strict_production_readiness' in self.approval['operations']:
                for name in ('DATABASE_URL', 'DATABASE_POOLER_URL', 'SUPABASE_READINESS_DATABASE_URL'):
                    if os.environ.get(name):
                        database_target(os.environ[name], self.approval['target']['project_ref'])
            if any(os.environ.get(n) for n in ('SUPABASE_API_URL', 'SUPABASE_DB_HOST', 'SUPABASE_WORKDIR', 'SUPABASE_CONFIG')):
                raise Blocked('DEPLOY_UNBOUND_ENDPOINT_OVERRIDE')
            self.env = os.environ.copy()
            for name in list(self.env):
                if name in {'BASH_ENV', 'ENV', 'PYTHONPATH', 'PYTHONHOME', 'LD_PRELOAD'} or name.startswith('DYLD_'):
                    self.env.pop(name)
            self.env.update(SUPABASE_BIN=str(self.tools['supabase']), SUPABASE_GO_BINARY=str(self.tools['supabase_go']), DENO_BIN=str(self.tools['deno']), COLLECT_SKIP_DOTENV='1', PYTHONDONTWRITEBYTECODE='1')
            self.env.update({('COLLECT_BACKEND_' + name.upper()): str(getattr(self.args, name)) for name in ('candidate', 'manifest_sha256', 'approval', 'approval_sha256', 'environment', 'receipt')})
            self.guard()
            self.record.update(status='running', target=self.approval['target'], approved_operations=self.approval['operations'], approval_id=self.approval['approval_id'], backend_manifest_sha256=self.approval['backend_manifest_sha256'], toolchain=declared)
            self.save()
            with tempfile.TemporaryDirectory(prefix='.collect-backend-execution-', dir=self.record_path.parent) as work:
                self.stage = Path(work)
                for name, expected in self.manifest['source_files'].items():
                    data, mode = candidate.regular_bytes(self.source, name)
                    if {'sha256': candidate.sha(data), 'bytes': len(data), 'mode': mode} != expected:
                        raise Blocked('DEPLOY_COPY_SOURCE_CHANGED')
                    path = self.stage / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data); path.chmod(mode)
                (self.stage / candidate.MANIFEST).write_bytes(external_bytes(self.source / candidate.MANIFEST))
                (self.stage / 'supabase/.temp').mkdir(mode=0o700)
                (self.stage / 'supabase/.temp/project-ref').write_text(self.approval['target']['project_ref'])
                self.env.update(COLLECT_BACKEND_PYTHON=sys.executable, COLLECT_BACKEND_GUARD_HELPER=str(self.stage / 'scripts/qa/backend_release_delivery.py'), COLLECT_BACKEND_LAUNCHER_ROOT=str(self.launcher), COLLECT_BACKEND_EXECUTION_ROOT=str(self.stage))
                self.record['execution'] = {'source': 'private verified copy of reviewed export', 'runtime_metadata': 'generated target-bound link plus explicitly validated CLI cache names', 'worktree_executed': False}; self.save()
                try:
                    self.execute()
                except (Blocked, candidate.ReleaseError, postgres_admission.Refused, OSError) as error:
                    self.record.update(status='partial_or_failed', error=str(error) if isinstance(error, (Blocked, candidate.ReleaseError, postgres_admission.Refused)) else 'DEPLOY_IO_FAILURE')
                    if any(op['mutating'] for op in self.record['operations']):
                        try:
                            self.readback(final=False)
                        except (Blocked, candidate.ReleaseError, postgres_admission.Refused, OSError) as read_error:
                            self.record['readback']['reconciliation'] = 'unavailable_or_blocked:' + (str(read_error) if isinstance(read_error, (Blocked, candidate.ReleaseError, postgres_admission.Refused)) else 'DEPLOY_IO_FAILURE')
                    else:
                        self.record['readback']['reconciliation'] = 'not_needed; no mutation attempted'
                    self.save(); raise
            self.record['status'] = 'delivered_and_read_back'
            return 0
        except (Blocked, candidate.ReleaseError, postgres_admission.Refused, OSError, subprocess.SubprocessError, KeyError, TypeError, UnicodeError) as error:
            if self.record['status'] == 'preflight': self.record['status'] = 'preflight_blocked'
            elif self.record['status'] != 'partial_or_failed': self.record['status'] = 'blocked'
            self.record['error'] = str(error) if isinstance(error, (Blocked, candidate.ReleaseError, postgres_admission.Refused)) else 'DEPLOY_INVALID_INPUT_OR_LOCAL_TOOL'
            print('[supabase-deploy][FAIL] ' + self.record['error'], file=sys.stderr)
            return 1
        finally:
            self.record['finished_at_utc'] = dt.datetime.now(dt.timezone.utc).isoformat(); self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['describe', 'run', 'guard'])
    for name in ('candidate', 'manifest_sha256', 'approval', 'approval_sha256', 'environment', 'receipt'):
        parser.add_argument('--' + name.replace('_', '-'), default=os.environ.get('COLLECT_BACKEND_' + name.upper()))
    parser.add_argument('--launcher-root', default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument('--execution-root')
    parser.add_argument('--before-database-request', action='store_true')
    args = parser.parse_args()
    if not args.candidate or not args.manifest_sha256:
        parser.error('Reviewed export and independently retained manifest hash are required')
    if args.action == 'describe':
        try:
            manifest = verified_export(args.candidate, args.manifest_sha256); backend = backend_files(manifest)
            print(json.dumps({'candidate_manifest_sha256': args.manifest_sha256, 'backend_manifest_sha256': candidate.sha(candidate.canonical(backend)), 'backend_file_count': len(backend), 'operations_available': list(OPERATIONS), 'approvals_created': False}, indent=2))
            return 0
        except (Blocked, candidate.ReleaseError, postgres_admission.Refused, OSError) as error:
            print(str(error), file=sys.stderr); return 1
    if not all((args.approval, args.approval_sha256, args.environment, args.receipt)):
        parser.error('Approval record/hash, environment and fresh receipt path are required')
    if args.action == 'guard':
        try:
            delivery = Delivery.__new__(Delivery)
            delivery.args = args
            delivery.source = checked_path(args.candidate)
            delivery.launcher = checked_path(args.launcher_root)
            delivery.stage = checked_path(args.execution_root)
            delivery.manifest = verified_export(delivery.source, args.manifest_sha256)
            delivery.backend = backend_files(delivery.manifest)
            delivery.approval = approval_record(args, delivery.manifest, delivery.backend)
            delivery.pg = None
            if {'migrations', 'strict_production_readiness'} & set(delivery.approval['operations']):
                delivery.pg = postgres_admission.Admission.from_environment(operation='migration' if 'migrations' in delivery.approval['operations'] else 'query')
                if delivery.approval['toolchain'].get('postgresql') != {'manifest_sha256': delivery.pg.expected}:
                    raise Blocked('DEPLOY_POSTGRES_MANIFEST_BINDING_INVALID')
                delivery.pg.project(delivery.approval['target']['project_ref'])
            delivery.tools = {name: Path(os.environ[key]).resolve(strict=True) for name, key in [('supabase', 'SUPABASE_BIN'), ('supabase_go', 'SUPABASE_GO_BINARY'), ('deno', 'DENO_BIN')]}
            delivery.guard()
            if args.before_database_request:
                if delivery.pg is None:
                    raise Blocked('DEPLOY_DATABASE_SCOPE_REQUIRED')
                delivery.guard_server_transport()
            return 0
        except (Blocked, candidate.ReleaseError, postgres_admission.Refused, OSError, TypeError, KeyError) as error:
            print(str(error) if isinstance(error, (Blocked, candidate.ReleaseError, postgres_admission.Refused)) else 'DEPLOY_GUARD_INVALID', file=sys.stderr)
            return 1
    try:
        return Delivery(args).run()
    except (Blocked, OSError) as error:
        print('[supabase-deploy][FAIL] ' + (str(error) if isinstance(error, Blocked) else 'DEPLOY_FRESH_RECEIPT_REQUIRED'), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
