#!/usr/bin/env python3
"""Retain actual scoped logout/auth-consumer checks with before/after inputs."""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[4]
BASE = pathlib.Path(__file__).resolve().parent
OUT = BASE / sys.argv[1]
OUT.mkdir(exist_ok=False)
FLUTTER = '/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
OWN_TEST = 'test/features/privacy/privacy_logout_integration_test.dart'
TESTS = [OWN_TEST, 'test/shared/repository_session_fencing_test.dart',
         'test/features/auth_error_recovery_test.dart']
SOURCES = [
    'lib/features/privacy/privacy_request_screen.dart',
    'lib/shared/repositories/collect_repository.dart',
    'lib/shared/repositories/collect_repository_providers.dart',
    'lib/features/status/account_legal_screens.dart',
    'lib/features/auth/widgets/auth_otp_entry.dart',
    'lib/app/router.dart', OWN_TEST,
]


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def inventory():
    paths = list(ROOT.glob('lib/**/*.dart'))
    paths += [ROOT / p for p in TESTS + [
        'test/features/privacy/privacy_test_support.dart',
        'pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
        'Makefile', 'AGENTS.md', 'scripts/qa/revolut_design_authority.py',
        'docs/release/revolut-design/authority.json',
        'assets/typefaces/Inter-Variable.ttf',
    ]]
    paths += [pathlib.Path(__file__), pathlib.Path(
        '/Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md')]
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    config_uri = (ROOT / '.dart_tool/package_config.json').as_uri()
    for package in config['packages']:
        if package['name'] not in {'gotrue', 'supabase', 'supabase_flutter', 'http'}:
            continue
        uri = urllib.parse.urljoin(config_uri, package['rootUri'])
        package_root = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path))
        paths += list(package_root.glob('lib/**/*.dart'))
        paths += [package_root / 'pubspec.yaml']
    return {str(p): digest(p) for p in sorted(set(paths))}


before = inventory()
write('inputs-before.json', before)
for name, expected in before.items():
    path = pathlib.Path(name)
    if path.is_relative_to(ROOT):
        destination = OUT / 'captured-source' / path.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
        if digest(destination) != expected:
            raise RuntimeError('Source changed during capture')
commands = [
    [FLUTTER, '--version', '--machine'],
    [FLUTTER, 'analyze', '--no-pub', '--fatal-infos', *SOURCES],
    [FLUTTER, 'test', '--no-pub', '--reporter', 'json', *TESTS],
    ['make', 'revolut-design-authority'],
]
started = stamp()
results = []
for index, command in enumerate(commands):
    log = OUT / f'command-{index}.log'
    began = stamp()
    with log.open('wb') as output:
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=600)
            exit_code = result.returncode
        except subprocess.TimeoutExpired:
            exit_code = 'timeout'
    results.append({'argv': command, 'started_at_utc': began,
                    'ended_at_utc': stamp(), 'exit_code': exit_code,
                    'log': log.name, 'sha256': digest(log)})
    print(json.dumps({'command': index, 'exit_code': exit_code}), flush=True)
after = inventory()
write('inputs-after.json', after)
drift = {key: {'before': before.get(key), 'after': after.get(key)}
         for key in sorted(set(before) | set(after))
         if before.get(key) != after.get(key)}
events = []
for line in (OUT / 'command-2.log').read_text(errors='replace').splitlines():
    try:
        event = json.loads(line)
        if isinstance(event, dict):
            events.append(event)
    except ValueError:
        pass
done = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
complete = [e for e in events if e.get('type') == 'done']
passed = sum(e.get('result') == 'success' and not e.get('skipped') for e in done)
failed = sum(e.get('result') in ('failure', 'error') for e in done)
skipped = sum(bool(e.get('skipped')) for e in done)
ok = all(r['exit_code'] == 0 for r in results) and not drift and bool(complete)
summary = {
    'status': 'pass' if ok else 'fail', 'started_at_utc': started,
    'completed_at_utc': stamp(), 'commands': results,
    'input_count': len(before), 'source_drift': drift,
    'visible_tests': len(done), 'passed': passed, 'failed': failed,
    'skipped': skipped, 'runner_done': complete,
    'scope': 'Actual default repository/provider logout fence, local session preservation and affected OTP error/reflow checks with synthetic SDK/network/native fixtures. No live provider, physical-device, full candidate, erasure or visual fidelity acceptance.',
    'hosted_accepted': False, 'physical_device_accepted': False,
    'erasure_completed': False, 'visual_fidelity_accepted': False,
    'production_ready': False,
}
write('result.json', summary)
print(json.dumps(summary, indent=2))
sys.exit(0 if ok else 1)
