#!/usr/bin/env python3
"""Preflight by default; --run executes the declared Flutter checks, never deploys.

Run in a quiescent, dependency-resolved full checkout with its installed SDK.
No package resolution, SDK installation, formatting writes or source repair is
performed. Tool subprocesses may write their normal build/cache outputs. A
matching version is evidence of reported SDK compatibility, not SDK attestation.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
from typing import Any
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parents[2]
SCOPE_PATH = 'scripts/qa/candidate_check_scope.json'
CHECKOUT_FILES = ('pubspec.yaml', 'pubspec.lock', '.fvmrc', '.dart_tool/package_config.json')
VERSION = re.compile(r'(?<![\w.])(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?![\w.-])')


class Blocked(ValueError):
    """A missing, invalid, or changed validation prerequisite."""


def unique_object(items: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in items:
        if key in result:
            raise Blocked(f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_file(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or '\\' in relative:
        raise Blocked('Invalid relative check path')
    rel = PurePosixPath(relative)
    if rel.is_absolute() or '..' in rel.parts or rel.as_posix() != relative:
        raise Blocked(f'Unsafe relative path: {relative}')
    path = root / relative
    for parent in (path, *path.parents):
        if parent == root:
            break
        if parent.is_symlink():
            raise Blocked(f'Symlink not followed: {relative}')
    if not path.is_file():
        raise Blocked(f'Required checkout file is missing: {relative}')
    return path


def check_scope(root: Path) -> tuple[list[str], list[str]]:
    scope = read_json(checked_file(root, SCOPE_PATH))
    if not isinstance(scope, dict) or scope.get('schema_version') != 1:
        raise Blocked('Unsupported check-scope schema')
    result: list[list[str]] = []
    for key in ('format_targets', 'widget_tests'):
        rows = scope.get(key)
        if not isinstance(rows, list) or not rows or any(not isinstance(p, str) for p in rows):
            raise Blocked(f'Empty or malformed {key}')
        if len(rows) != len(set(rows)):
            raise Blocked(f'Duplicate path in {key}')
        for rel in rows:
            if not rel.startswith(('lib/', 'test/')) or not rel.endswith('.dart'):
                raise Blocked(f'Out-of-scope Dart target: {rel}')
            if key == 'widget_tests' and (not rel.startswith('test/') or not rel.endswith('_test.dart')):
                raise Blocked(f'Invalid test path: {rel}')
            checked_file(root, rel)
        result.append(rows)
    if not set(result[1]).issubset(result[0]):
        raise Blocked('Every declared test must also receive a format check')
    return result[0], result[1]


def package_directory(config_file: Path, row: dict[str, Any]) -> Path:
    uri = row.get('rootUri')
    if not isinstance(uri, str) or not uri:
        raise Blocked('A package root URI is absent')
    parsed = urlparse(urljoin(config_file.as_uri(), uri))
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or parsed.query or parsed.fragment:
        raise Blocked('Only local resolved package roots are accepted')
    path = Path(unquote(parsed.path)).resolve(strict=True)
    if not path.is_dir():
        raise Blocked('Resolved package root is not a directory')
    return path


def prerequisites(root: Path) -> str:
    for rel in CHECKOUT_FILES:
        checked_file(root, rel)
    if not re.search(r'^name:\s*collect_app\s*(?:#.*)?$', (root / 'pubspec.yaml').read_text(), re.M):
        raise Blocked('This is not the collect_app package')
    if not (root / 'pubspec.lock').read_bytes().strip():
        raise Blocked('Dependency lockfile is empty')
    pin = read_json(root / '.fvmrc')
    expected = pin.get('flutter') if isinstance(pin, dict) else None
    if not isinstance(expected, str) or not VERSION.fullmatch(expected):
        raise Blocked('Checkout must declare an exact Flutter version in .fvmrc')
    config_file = root / '.dart_tool/package_config.json'
    config = read_json(config_file)
    rows = config.get('packages') if isinstance(config, dict) else None
    if not isinstance(config, dict) or config.get('configVersion') != 2 or not isinstance(rows, list):
        raise Blocked('Resolved package configuration is malformed')
    by_name: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get('name'), str) or not row['name']:
            raise Blocked('Malformed package entry')
        if row['name'] in by_name:
            raise Blocked('Duplicate package name in resolved configuration')
        by_name[row['name']] = row
    for name in ('collect_app', 'flutter', 'flutter_test'):
        if name not in by_name:
            raise Blocked(f'Resolved package configuration lacks {name}')
        path = package_directory(config_file, by_name[name])
        if name == 'collect_app' and path != root:
            raise Blocked('Resolved collect_app points to another checkout')
    return expected


def executable(value: str) -> str:
    found = shutil.which(value)
    if found is None:
        raise Blocked(f'Executable is unavailable: {value}')
    return str(Path(found).resolve())


def execute(args: list[str], root: Path, timeout: float) -> subprocess.CompletedProcess[str]:
    # Never shell-interpret paths or tool output. The user's SDK is an explicit
    # trust boundary; matching version output does not authenticate its binary.
    return subprocess.run(args, cwd=root, text=True, capture_output=True,
                          timeout=timeout, check=False)


def verify_unchanged(root: Path, hashes: dict[str, str]) -> None:
    for rel, expected in hashes.items():
        if digest(checked_file(root, rel)) != expected:
            raise Blocked(f'Validation input changed during checks: {rel}')


def validate(root: Path, *, run: bool = False, flutter: str = 'flutter',
             dart: str = 'dart', timeout: float = 600) -> tuple[dict[str, Any], int]:
    report: dict[str, Any] = {
        'schema_version': 1,
        'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'mode': 'run' if run else 'check', 'status': 'blocked',
        'application_checks_started': [], 'application_checks_completed': [],
        'stage_results': [], 'application_checks_passed': False,
        'design_acceptance': 'not_assessed', 'release_authorized': False,
        'package_resolution_performed': False, 'source_repair_performed': False,
    }
    hashes: dict[str, str] = {}
    root = root.resolve()
    try:
        if not math.isfinite(timeout) or timeout <= 0:
            raise Blocked('Timeout must be a positive finite number')
        format_targets, tests = check_scope(root)
        expected = prerequisites(root)
        protected = [*CHECKOUT_FILES, SCOPE_PATH, *format_targets]
        hashes = {rel: digest(checked_file(root, rel)) for rel in protected}
        flutter_bin, dart_bin = executable(flutter), executable(dart)
        version_result = execute([flutter_bin, '--version', '--machine'], root, min(timeout, 30))
        if version_result.returncode != 0:
            raise Blocked('Flutter version probe failed')
        versions = json.loads(version_result.stdout, object_pairs_hook=unique_object)
        if not isinstance(versions, dict) or versions.get('frameworkVersion') != expected:
            raise Blocked('Flutter SDK does not match the checkout pin')
        sdk_dart = versions.get('dartSdkVersion')
        dart_result = execute([dart_bin, '--version'], root, min(timeout, 30))
        actual_dart = VERSION.search(dart_result.stdout + '\n' + dart_result.stderr)
        reported_dart = VERSION.search(sdk_dart) if isinstance(sdk_dart, str) else None
        if dart_result.returncode or not actual_dart or not reported_dart or actual_dart[1] != reported_dart[1]:
            raise Blocked('Dart executable version does not match the Flutter-reported Dart SDK')
        verify_unchanged(root, hashes)
        report.update(flutter_version=expected, dart_version=actual_dart[1],
                      format_target_count=len(format_targets), widget_test_files=len(tests))
        commands = [
            ('format', [dart_bin, 'format', '--output=none', '--set-exit-if-changed', *format_targets]),
            ('analyze', [flutter_bin, 'analyze', '--no-pub', '--fatal-infos']),
            ('test', [flutter_bin, 'test', '--no-pub', *tests]),
        ]
        report['planned_commands'] = {name: command for name, command in commands}
        if not run:
            report['status'] = 'ready_not_executed'
            return report, 0
        for name, command in commands:
            verify_unchanged(root, hashes)
            report['application_checks_started'].append(name)
            result = execute(command, root, timeout)
            report['stage_results'].append({
                'name': name, 'exit_code': result.returncode,
                'stdout': result.stdout, 'stderr': result.stderr,
            })
            verify_unchanged(root, hashes)
            if result.returncode != 0:
                report.update(status='failed', reason=f'{name} returned a nonzero exit code')
                return report, result.returncode if result.returncode > 0 else 1
            report['application_checks_completed'].append(name)
        report.update(status='passed', application_checks_passed=True,
                      validation_input_hashes_unchanged=True)
        return report, 0
    except (OSError, ValueError, TypeError, KeyError, subprocess.TimeoutExpired) as error:
        report.update(status='failed' if report['application_checks_started'] else 'blocked',
                      reason=str(error))
        return report, 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=ROOT)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--run', action='store_true')
    mode.add_argument('--check', action='store_true')
    parser.add_argument('--timeout', type=float, default=600)
    args = parser.parse_args()
    report, code = validate(args.repo, run=args.run, timeout=args.timeout,
                            flutter=os.environ.get('FLUTTER_BIN', 'flutter'),
                            dart=os.environ.get('DART_BIN', 'dart'))
    print(json.dumps(report, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
