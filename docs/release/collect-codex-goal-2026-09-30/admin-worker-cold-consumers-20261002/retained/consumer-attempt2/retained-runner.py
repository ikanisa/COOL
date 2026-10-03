from pathlib import Path
import datetime, hashlib, json, os, subprocess, sys, urllib.parse

STAGE = Path(__file__).resolve().parent
APP = STAGE / 'validation-app'
FLUTTER = Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter')
CAPTURE = json.loads((STAGE / 'CAPTURE.json').read_text())

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1048576), b''):
            h.update(data)
    return h.hexdigest()

def snapshot():
    paths = set()
    for dirname in ['lib', 'test', 'assets', 'third_party']:
        paths.update(p for p in (APP / dirname).rglob('*') if p.is_file())
    paths.update(APP / name for name in ['pubspec.yaml', 'pubspec.lock',
        'analysis_options.yaml', '.dart_tool/package_config.json',
        '.dart_tool/package_graph.json'])
    # Bind pinned dependency source/assets as well as its resolved package map.
    for entry in json.loads((APP / '.dart_tool/package_config.json').read_text())['packages']:
        raw = entry['rootUri']
        root = Path(urllib.parse.unquote(urllib.parse.urlparse(raw).path)) if raw.startswith('file:') else (APP / '.dart_tool' / raw).resolve()
        if entry['name'] == 'collect_app':
            continue
        for dirname in ['lib', 'assets', 'fonts']:
            paths.update(p for p in (root / dirname).rglob('*') if p.is_file())
        for name in ['pubspec.yaml', 'pubspec.lock']:
            if (root / name).is_file(): paths.add(root / name)
    toolroot = FLUTTER.parent.parent
    paths.update([FLUTTER, toolroot / 'bin/internal/shared.sh',
        toolroot / 'bin/cache/flutter_tools.snapshot',
        toolroot / 'bin/cache/dart-sdk/bin/dart',
        toolroot / 'bin/cache/dart-sdk/bin/dartaotruntime',
        toolroot / 'bin/cache/dart-sdk/bin/snapshots/dartdev_aot.dart.snapshot',
        Path(sys.executable).resolve(), Path(__file__).resolve(),
        STAGE / 'CAPTURE.json', STAGE / 'canonical-package_config.json',
        STAGE / '700-FIXTURE_INDEX.json'])
    paths.update(p for p in (toolroot / 'bin/cache/artifacts/engine').rglob('*')
        if p.is_file() and (p.name in ['flutter_tester', 'icudtl.dat', 'frontend_server_aot.dart.snapshot']
            or p.suffix == '.dill'))
    paths.update(p for p in (toolroot / 'bin/cache/artifacts/material_fonts').rglob('*') if p.is_file())
    # Compiler core files are inputs; mutable build/cache outputs are excluded.
    paths.update(p for p in (toolroot / 'bin/cache/dart-sdk/lib').rglob('*') if p.is_file())
    return {str(p): digest(p) for p in sorted(paths)}

def main():
    n = 1
    while (STAGE / ('consumer-attempt' + str(n))).exists(): n += 1
    report = STAGE / ('consumer-attempt' + str(n))
    report.mkdir()
    canonical_before = {p: digest(Path(p)) for p in CAPTURE['source_bindings']}
    if canonical_before != CAPTURE['source_bindings']:
        raise RuntimeError('Canonical or sealed fixture changed since fresh capture')
    before = snapshot()
    (report / 'inputs-before.json').write_text(json.dumps(before, indent=2, sort_keys=True) + '\n')
    cmd = [str(FLUTTER), 'test', '--no-pub', '--reporter', 'json',
        'test/admin_worker_cold_consumer_test.dart']
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    env = os.environ.copy()
    env.update({'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
        'COLD_CONSUMER_OBSERVATIONS': str(report / 'observed-sdk-requests.json')})
    with (report / 'stdout.log').open('w') as out, (report / 'stderr.log').open('w') as err:
        p = subprocess.run(cmd, cwd=APP, env=env, stdout=out, stderr=err, timeout=240)
    after = snapshot()
    canonical_after = {p: digest(Path(p)) for p in CAPTURE['source_bindings']}
    events = []
    for line in (report / 'stdout.log').read_text().splitlines():
        try: value = json.loads(line)
        except json.JSONDecodeError: continue
        if isinstance(value, dict): events.append(value)
    starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    completed = [dict(test=starts.get(e['testID'], {}), result=e['result'])
        for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
    done = [e for e in events if e.get('type') == 'done']
    (report / 'machine-events.json').write_text(json.dumps(events, indent=2) + '\n')
    (report / 'inputs-after.json').write_text(json.dumps(after, indent=2, sort_keys=True) + '\n')
    result = dict(command=cmd, cwd=str(APP), started_at=started,
        finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        exit_code=p.returncode, source_tool_dependency_fixture_inputs=len(before),
        all_inputs_unchanged=before == after,
        canonical_fixture_inputs=len(canonical_before),
        canonical_fixture_unchanged=canonical_before == canonical_after,
        terminal=done[-1] if done else None, cases=completed,
        scope='Actual current canonical Admin repository/provider/cards with exact SQL12 outputs via synthetic authenticated Supabase MockClient HTTP adapter; no hosted PostgREST/GoTrue acceptance',
        prior_model14_duplicated=False, production_source_changed=False)
    (report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'cases'}, indent=2))
    print('Distinct terminal cases:', len(completed))
    if p.returncode:
        for e in events:
            if e.get('type') == 'error': print(json.dumps(e))
        print((report / 'stderr.log').read_text()[-6000:])
    return p.returncode or (0 if before == after and canonical_before == canonical_after and done and done[-1].get('success') else 1)

if __name__ == '__main__': sys.exit(main())
