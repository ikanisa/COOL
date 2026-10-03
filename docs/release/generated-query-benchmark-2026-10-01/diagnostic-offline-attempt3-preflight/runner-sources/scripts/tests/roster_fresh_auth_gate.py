#!/usr/bin/env python3
"""Execute current Auth/roster acceptance from a copied, source-bound export.

No database target or credentials are accepted. SQL receipts, when supplied,
are static root-produced evidence consumed by the reviewed Dart test.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import traceback
import urllib.parse

ROOT = Path(__file__).resolve().parents[2]
TESTS = [
    'test/core/browser_auth_memory_test.dart',
    'test/core/supabase_session_persistence_test.dart',
    'test/admin_roster_fresh_auth_test.dart',
    'test/admin_roster_calendar_test.dart',
    'test/admin_roster_import_test.dart',
    'test/admin_roster_reload_test.dart',
    'test/admin_roster_dialog_test.dart',
    'test/admin_roster_gateway_expiry_test.dart',
    'test/admin_roster_transport_test.dart',
    'test/admin_roster_fresh_auth_sql_receipts_test.dart',
    'test/admin_roster_authority_scope_test.dart',
]
OWNED_ANALYSIS = [
    'lib/core/supabase/browser_auth_memory.dart',
    'lib/core/supabase/browser_auth_storage_web.dart',
    'lib/core/supabase/browser_auth_storage_stub.dart',
    'lib/core/supabase/supabase_module.dart',
    'lib/admin/core/admin_roster_models.dart',
    'lib/admin/core/admin_roster_import.dart',
    'lib/admin/core/admin_roster_dialog.dart',
    'third_party/gotrue/lib',
    'tool/qa/browser_auth_reference_fixture.dart',
    'tool/qa/roster_fresh_auth_browser_fixture.dart',
    *TESTS,
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files():
    result = set()
    for directory in ['lib', 'test', 'assets', 'web', 'third_party']:
        for p in (ROOT / directory).rglob('*'):
            if p.is_file() and not p.is_symlink():
                if directory == 'third_party' and ('example' in p.parts or 'test' in p.parts):
                    continue  # Preserved upstream test cohorts are not executed by this gate.
                if any(x in p.parts for x in ['build', '.dart_tool', '.gradle', 'Pods']):
                    continue
                result.add(p)
    result.update(ROOT / name for name in [
        'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.fvmrc',
        '.dart_tool/package_config.json', '.dart_tool/package_graph.json', '.dart_tool/version',
        '.flutter-plugins-dependencies', 'tool/qa/browser_auth_reference_fixture.dart',
        'scripts/qa/browser_auth_reference/validate.mjs',
        'scripts/qa/browser_auth_reference/roster_dialog.mjs',
        'tool/qa/roster_fresh_auth_browser_fixture.dart',
        'supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql',
        'scripts/tests/roster_fresh_auth_recovery_uat.sql',
        'scripts/tests/roster_fresh_auth_gate.py',
    ])
    return sorted(result)


def hashes(files, root):
    return {str(p.relative_to(root)): sha(p) for p in files}


def command(name, argv, cwd, packet, *, environment=None, timeout=180):
    # A runner owns only its newly spawned child. Unexpected exit/timeout is
    # retained as failure, never represented as another passing attempt.
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    monotonic = time.monotonic()
    timed_out = False
    termination_errors = []
    with (packet / f'{name}.stdout').open('wb') as stdout, \
         (packet / f'{name}.stderr').open('wb') as stderr:
        process = subprocess.Popen(argv, cwd=cwd, env=environment,
                                   stdout=stdout, stderr=stderr,
                                   start_new_session=True)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Target only the group created above. A terminal parent does not
            # prove all of its compiler/test children have also exited.
            for sig in [signal.SIGTERM, signal.SIGKILL]:
                try:
                    os.killpg(process.pid, sig)
                except OSError as error:
                    if error.errno != 3:
                        termination_errors.append({'signal': sig.name, 'errno': error.errno})
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    pass
            stderr.write(b'\nOwned command observation limit exceeded; attempt failed.\n')
    code = 124 if timed_out else process.returncode
    return {'name': name, 'argv': argv, 'started_utc': started,
            'exit_code': code, 'timed_out': timed_out,
            'owned_process_group': process.pid,
            'parent_exit_confirmed': process.poll() is not None,
            'termination_errors': termination_errors,
            'seconds': round(time.monotonic() - monotonic, 3),
            'stdout_sha256': sha(packet / f'{name}.stdout'),
            'stderr_sha256': sha(packet / f'{name}.stderr')}


def machine_summary(path):
    started, finished, hidden = {}, {}, set()
    done, errors = None, []
    if path.exists():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                errors.append(f'invalid_event_line_{number}')
                continue
            kind = event.get('type')
            if kind == 'testStart':
                test = event['test']
                started[test['id']] = {'name': test['name'], 'source': test.get('url')}
            elif kind == 'testDone':
                identity = event['testID']
                if identity in finished:
                    errors.append(f'duplicate_test_completion_{identity}')
                finished[identity] = event
                if event.get('hidden'):
                    hidden.add(identity)
            elif kind == 'done':
                done = event.get('success')
    actual = {key: value for key, value in finished.items() if key not in hidden}
    return {'runner_completed_successfully': done is True,
            'passed': sum(v.get('result') == 'success' and not v.get('skipped') for v in actual.values()),
            'failed': sum(v.get('result') == 'failure' for v in actual.values()),
            'errors': sum(v.get('result') == 'error' for v in actual.values()),
            'skipped': sum(bool(v.get('skipped')) for v in actual.values()),
            'named_results': [{'name': started.get(key, {}).get('name'),
                               'source': started.get(key, {}).get('source'),
                               'result': value.get('result'),
                               'skipped': bool(value.get('skipped'))}
                              for key, value in actual.items()],
            'unfinished': [started[key] for key in sorted(set(started) - set(finished))],
            'event_errors': errors}


def actual_sql149_test_passed(summary):
    named = [event for event in summary['named_results']
             if event['name'] == 'actual149 fresh recovery receipts agree with every client decoder']
    return (len(named) == 1 and named[0]['result'] == 'success'
            and not named[0]['skipped'] and summary['runner_completed_successfully']
            and not summary['event_errors'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--node', default='node')
    parser.add_argument('--sql-receipts', type=Path)
    parser.add_argument('--normal-admin-browser', action='store_true')
    parser.add_argument('--test-timeout', type=int, default=900)
    args = parser.parse_args()
    if not 1 <= args.test_timeout <= 1800:
        parser.error('--test-timeout must be within 1..1800 seconds')
    if args.normal_admin_browser and not args.sql_receipts:
        parser.error('--normal-admin-browser requires actual --sql-receipts')
    packet = args.output.resolve()
    if not packet.is_relative_to(ROOT / 'docs/release'):
        parser.error('A fresh repository release packet directory is required')
    packet.mkdir(parents=True, exist_ok=False)
    export = packet / 'source-export'
    export.mkdir()
    files = source_files()
    receipt_input = None
    defines = []
    if args.sql_receipts:
        receipt_path = args.sql_receipts.resolve(strict=True)
        result_path = receipt_path.parent / 'result.json'
        result = json.loads(result_path.read_text())
        if (result['status'] != 'pass' or not result['unchanged']
                or result['sql_return_code'] != 0 or result['failures']
                or result['stdout_sha256'] != sha(receipt_path)
                or result['reviewed_source_sha256'] != sha(ROOT / 'scripts/tests/roster_fresh_auth_recovery_uat.sql')
                or result['identity']['latest'] != '20260930170000'):
            raise RuntimeError('Actual149 receipt provenance failed')
        copied_receipt = packet / 'actual-sql149.stdout'
        copied_receipt.write_bytes(receipt_path.read_bytes())
        (packet / 'actual-sql149.result.json').write_bytes(result_path.read_bytes())
        defines = [f'--dart-define=ROSTER_FRESH_SQL_RECEIPTS={copied_receipt}']
        receipt_input = {'source_stdout': str(receipt_path), 'stdout_sha256': sha(copied_receipt),
                         'result_sha256': sha(result_path), 'sql_executed_here': False}
    before = hashes(files, ROOT)
    for p in files:
        target = export / p.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        content = p.read_bytes()
        if hashlib.sha256(content).hexdigest() != before[str(p.relative_to(ROOT))]:
            raise RuntimeError('Source changed during immutable export: ' + str(p.relative_to(ROOT)))
        target.write_bytes(content)
    # Hosted package sources are immutable copied inputs too. SDK packages
    # remain under the pinned toolchain and their library bytes are bound.
    config = json.loads((export / '.dart_tool/package_config.json').read_text())
    dependencies = {}
    sdk_files = []
    sdk_roots = {}
    for package in config['packages']:
        uri = package['rootUri']
        if not uri.startswith('file:'):
            continue  # collect_app and controlled forks resolve within export.
        source = Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path))
        if package['name'] in ['flutter', 'flutter_test', 'flutter_localizations',
                               'integration_test', 'sky_engine', 'flutter_web_plugins']:
            sdk_roots[package['name']] = source
            sdk_files.extend(p for p in (source / 'lib').rglob('*') if p.is_file())
            if (source / 'pubspec.yaml').is_file():
                sdk_files.append(source / 'pubspec.yaml')
            continue
        target = export / '.qa_dependencies' / package['name']
        target.mkdir(parents=True)
        copied = []
        for p in sorted(source.rglob('*')):
            if p.is_file() and not any(cohort in p.relative_to(source).parts
                for cohort in ['example', 'test', 'doc', '.git', '.dart_tool',
                               'build', '.gradle', 'Pods']):
                dst = target / p.relative_to(source)
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(p.read_bytes())
                copied.append(p)
        if any(sha(p) != sha(target / p.relative_to(source)) for p in copied):
            raise RuntimeError('Dependency changed during immutable copy: ' + package['name'])
        dependencies[package['name']] = {'source_root': str(source),
            'files': {str(p.relative_to(source)): sha(p) for p in copied}}
        package['rootUri'] = target.as_uri()
    plugin_path = export / '.flutter-plugins-dependencies'
    plugins = json.loads(plugin_path.read_text())
    for entries in plugins.get('plugins', {}).values():
        for plugin in entries:
            owned = export / 'third_party' / plugin['name']
            dependency = export / '.qa_dependencies' / plugin['name']
            if owned.exists():
                plugin['path'] = str(owned) + '/'
            elif dependency.exists():
                plugin['path'] = str(dependency) + '/'
            elif plugin['name'] in sdk_roots:
                plugin['path'] = str(sdk_roots[plugin['name']]) + '/'
            else:
                raise RuntimeError('Uncopied plugin input: ' + plugin['name'])
    plugin_path.write_text(json.dumps(plugins, indent=2) + '\n')
    original_config_sha = before['.dart_tool/package_config.json']
    (export / '.dart_tool/package_config.json').write_text(json.dumps(config, indent=2) + '\n')
    export_files = sorted(p for p in export.rglob('*') if p.is_file())
    export_before = hashes(export_files, export)
    sdk_before = {str(p): sha(p) for p in sorted(set(sdk_files))}
    (packet / 'inputs.json').write_text(json.dumps({'source': before,
        'copied_dependencies': dependencies, 'sdk_library_inputs': sdk_before,
        'original_package_config_sha256': original_config_sha,
        'rebased_export_package_config_sha256': sha(export / '.dart_tool/package_config.json'),
        'export': export_before}, indent=2) + '\n')
    flutter = Path(args.flutter).resolve(strict=True)
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    fixture = packet / 'browser-auth-fixture.js'
    browser_packet = packet / 'browser'
    normal_browser_packet = packet / 'normal-admin-browser'
    normal_web = packet / 'normal-admin-web'
    environment = os.environ.copy()
    environment.update(COLLECT_AUTH_REFERENCE_PACKET=str(browser_packet),
                       COLLECT_AUTH_REFERENCE_BUNDLE=str(fixture))
    if args.normal_admin_browser:
        environment.update(COLLECT_ROSTER_BROWSER_PACKET=str(normal_browser_packet),
                           COLLECT_ROSTER_BROWSER_WEB=str(normal_web),
                           COLLECT_ROSTER_BROWSER_SQL_RECEIPTS=str(copied_receipt))
    commands = []
    machine_log = packet / 'tests.machine.jsonl'
    steps = [
        ('toolchain', [str(flutter), '--version', '--machine'], 30),
        ('tests', [str(flutter), 'test', '--no-pub', '--concurrency=1', *defines,
                   *TESTS, '--reporter', 'expanded',
                   f'--file-reporter=json:{machine_log}'], args.test_timeout),
        ('analysis', [str(dart), 'analyze', *OWNED_ANALYSIS], 120),
        ('browser-compile', [str(dart), 'compile', 'js', '-O2',
                             'tool/qa/browser_auth_reference_fixture.dart',
                             '-o', str(fixture)], 90),
        ('browser', [args.node, 'scripts/qa/browser_auth_reference/validate.mjs'], 120),
    ]
    if args.normal_admin_browser:
        steps += [
            ('normal-browser-build', [str(flutter), 'build', 'web', '--no-pub',
              '--no-web-resources-cdn', '--no-wasm-dry-run', '--target',
              'tool/qa/roster_fresh_auth_browser_fixture.dart', '--output', str(normal_web)], 600),
            ('normal-browser', [args.node, 'scripts/qa/browser_auth_reference/roster_dialog.mjs'], 180),
        ]
    web_before = None
    for name, argv, timeout in steps:
        result = command(name, argv, export, packet, environment=environment, timeout=timeout)
        commands.append(result)
        if name == 'normal-browser-build' and result['exit_code'] == 0:
            web_before = hashes(sorted(p for p in normal_web.rglob('*') if p.is_file()), normal_web)
        if result['exit_code'] != 0:
            break
    # Generated build/config outputs are excluded from the original export
    # manifest; every originally copied input is re-read and must match.
    export_after = hashes([export / p for p in export_before], export)
    root_after = hashes(source_files(), ROOT)
    sdk_after = {p: sha(Path(p)) for p in sdk_before}
    counts = re.findall(r'\+(\d+)(?:\s+~\d+)?: All tests passed!',
                        (packet / 'tests.stdout').read_text() if (packet / 'tests.stdout').exists() else '')
    browser = json.loads((browser_packet / 'report.json').read_text()) if (browser_packet / 'report.json').exists() else None
    normal_browser = (json.loads((normal_browser_packet / 'report.json').read_text())
                      if (normal_browser_packet / 'report.json').exists() else None)
    web_after = (hashes(sorted(p for p in normal_web.rglob('*') if p.is_file()), normal_web)
                 if normal_web.is_dir() else None)
    version = json.loads((packet / 'toolchain.stdout').read_text())
    machine = machine_summary(machine_log)
    passed = (len(commands) == len(steps) and all(c['exit_code'] == 0 for c in commands)
              and counts and version['frameworkVersion'] == '3.44.4'
              and machine['runner_completed_successfully']
              and machine['passed'] == int(counts[-1])
              and not any(machine[k] for k in ['failed', 'errors', 'unfinished', 'event_errors'])
              and export_before == export_after and sdk_before == sdk_after
              and browser is not None and browser['status'] == 'pass' and browser['bundle_unchanged'])
    normal_passed = (args.normal_admin_browser and normal_browser is not None
                     and normal_browser['status'] == 'pass'
                     and normal_browser['sql149_receipt_unchanged']
                     and web_before is not None and web_before == web_after)
    if args.normal_admin_browser:
        passed = passed and normal_passed
    report = {'status': 'pass' if passed else 'fail', 'commands': commands,
        'test_count': int(counts[-1]) if counts else None,
        'immutable_export_unchanged': export_before == export_after,
        'sdk_libraries_unchanged': sdk_before == sdk_after,
        'live_source_unchanged': before == root_after,
        'live_source_drift': [p for p in sorted(set(before) | set(root_after)) if before.get(p) != root_after.get(p)],
        'inputs_sha256': sha(packet / 'inputs.json'),
        'export_source_count': len(export_before),
        'browser_report_sha256': sha(browser_packet / 'report.json') if browser else None,
        'actual_sql149_receipt_input': receipt_input,
        'machine_summary': machine,
        'database_calls': 0, 'provider_calls': 0, 'hosted_calls': 0,
        'normal_admin_recovery_browser_verified': bool(normal_passed),
        'normal_admin_browser_report_sha256': sha(normal_browser_packet / 'report.json') if normal_browser else None,
        'normal_admin_web_inputs': web_before,
        'normal_admin_web_unchanged': web_before is not None and web_before == web_after,
        'actual_sql149_receipts_verified': bool(receipt_input and actual_sql149_test_passed(machine)),
        'whole_L01_complete': False,
        'scope': ('Copied current roster/Auth Dart tests, real vendored SDK Chrome privacy fixture and production Supabase initialization/actual Admin dialog against SQL149-shaped loopback transport'
                  if args.normal_admin_browser else 'Copied current roster/Auth Dart tests and real vendored SDK Chrome loopback privacy fixture; not normal Admin149 integration')}
    (packet / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'test_count', 'immutable_export_unchanged', 'live_source_unchanged']}))
    return 0 if passed else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception:
        # Setup failures are retained even before the first command/manifest.
        if '--output' in sys.argv:
            target = Path(sys.argv[sys.argv.index('--output') + 1]).resolve()
            if target.is_relative_to(ROOT / 'docs/release') and target.is_dir():
                (target / 'setup-error.txt').write_text(traceback.format_exc())
                if not (target / 'validation.json').exists():
                    (target / 'validation.json').write_text(json.dumps({
                        'status': 'fail', 'phase': 'export_setup',
                        'commands': [], 'application_tests_executed': False,
                        'database_calls': 0, 'provider_calls': 0,
                        'setup_error_sha256': sha(target / 'setup-error.txt'),
                        'whole_L01_complete': False}, indent=2) + '\n')
        raise
