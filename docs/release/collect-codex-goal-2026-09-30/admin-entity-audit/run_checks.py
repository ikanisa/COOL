#!/usr/bin/env python3
"""Scoped synthetic UI checks; uses installed Flutter with no pub or hosted calls."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
FLUTTER = Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter')
DART = FLUTTER.parent / 'cache/dart-sdk/bin/dart'

def now():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def binding(extra):
    patterns = (
        'lib/admin/core/admin_entity_audit*.dart',
        'test/admin_entity_audit*.dart',
        'test/fixtures/admin_entity_audit/*',
        'contracts/collect-operator-entity-audit-v1*',
        'docs/release/collect-codex-goal-2026-09-30/joined-operator-audit/sql-attempt5/observed-*.json',
    )
    paths = {p for pattern in patterns for p in ROOT.glob(pattern)}
    paths.update(ROOT / p for p in (
        'lib/admin/core/admin_repository_base.dart', 'lib/admin/core/admin_runtime.dart',
        'lib/admin/core/admin_shadow_runs.dart', 'lib/admin/admin_router.dart',
        'lib/admin/core/admin_automations_page.dart',
        'lib/admin/core/admin_auth_guard.dart', 'lib/admin/core/admin_models.dart',
        'lib/core/data/exact_json_values.dart', 'lib/app/theme/collect_theme.dart',
        'lib/app/theme/collect_tokens.dart', 'lib/app/theme/app_theme.dart',
        'test/support/admin_entity_audit_fixture.dart', 'test/admin_action_session_test.dart',
        'test/admin_shadow_runs_test.dart', 'test/admin_shadow_runs_repository_test.dart',
        'supabase/migrations/20261001001457_joined_operator_audit.sql',
        'pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
    ))
    paths.update(ROOT / p for p in extra)
    # Bind transitive local Dart imports/parts; external packages remain pinned
    # by the installed package configuration and pubspec lock.
    pending = [p for p in paths if p.suffix == '.dart' and p.is_file()]
    visited = set()
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        for reference in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", path.read_text()):
            if reference.startswith('package:collect_app/'):
                dependency = ROOT / 'lib' / reference.removeprefix('package:collect_app/')
            elif ':' in reference:
                continue
            else:
                dependency = (path.parent / reference).resolve()
            if dependency.is_relative_to(ROOT) and dependency.is_file():
                paths.add(dependency)
                if dependency.suffix == '.dart':
                    pending.append(dependency)
    paths.add(Path(__file__))
    return {str(p.relative_to(ROOT)): {'sha256': sha(p), 'bytes': p.stat().st_size}
            for p in sorted(paths) if p.is_file()}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', required=True)
    parser.add_argument('--mode', choices=('analyze', 'test', 'capture'), required=True)
    parser.add_argument('paths', nargs='+')
    args = parser.parse_args()
    output = PACKET / args.name
    output.mkdir(exist_ok=False)
    before = binding(args.paths)
    (output / 'source-before.json').write_text(json.dumps(before, indent=2, sort_keys=True) + '\n')
    command = [str(FLUTTER), 'analyze', '--no-pub'] if args.mode == 'analyze' else [
        str(FLUTTER), 'test', '--no-pub', '--timeout', '30s', '--reporter', 'expanded']
    if args.mode == 'capture':
        command.extend(['--plain-name', 'dark and light local audit captures'])
    command.extend(args.paths)
    environment = {key: os.environ[key] for key in ('HOME', 'PATH', 'TMPDIR', 'LANG')
                   if key in os.environ}
    environment.update({'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
                        'DART_SUPPRESS_ANALYTICS': 'true'})
    if args.mode == 'capture':
        environment['COLLECT_ENTITY_AUDIT_CAPTURE'] = str(output)
    started = now()
    with (output / 'check.log').open('wb') as log:
        result = subprocess.run(command, cwd=ROOT, env=environment, stdout=log,
                                stderr=subprocess.STDOUT, timeout=300, check=False)
    after = binding(args.paths)
    (output / 'source-after.json').write_text(json.dumps(after, indent=2, sort_keys=True) + '\n')
    completed_log = (output / 'check.log').read_text(errors='replace')
    complete = 'No issues found!' in completed_log if args.mode == 'analyze' else 'All tests passed!' in completed_log
    receipt = {'command': command, 'cwd': str(ROOT), 'exit_code': result.returncode,
               'check_completed_successfully': result.returncode == 0 and complete,
               'started_at_utc': started, 'finished_at_utc': now(),
               'selected_source_unchanged': before == after,
               'source_file_count': len(before), 'log_sha256': sha(output / 'check.log'),
               'dart_binary_sha256': sha(DART), 'runner_sha256': sha(Path(__file__)),
               'dependency_resolution': 'installed package_config; --no-pub',
               'scope': 'Synthetic isolated SQL outputs, mock SDK transport and local widgets.',
               'hosted_auth_or_backend_calls_requested': False, 'live_sends_requested': False,
               'production_acceptance': False}
    (output / 'result.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps(receipt, sort_keys=True))
    raise SystemExit(result.returncode or (0 if before == after and complete else 2))

if __name__ == '__main__':
    main()
