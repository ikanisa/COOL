from pathlib import Path
import datetime, hashlib, json, os, shutil, subprocess, sys, time

stage = Path(__file__).resolve().parent
root = stage.parents[2]
runtime = stage / 'runtime'
mode, attempt = sys.argv[1:3]
out = stage / 'proofs' / attempt
out.mkdir(parents=True, exist_ok=False)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
for name in ['lib', 'test']:
    for p in (stage / name).rglob('*'):
        if p.is_file():
            d = runtime / p.relative_to(stage)
            d.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, d)
source = {str(p.relative_to(stage)): sha(p) for name in ['lib', 'test', 'integration'] for p in (stage / name).rglob('*') if p.is_file()}
for rel in source:
    d = out / 'source-copies' / rel
    d.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(stage / rel, d)
(out / 'source.json').write_text(json.dumps(source, indent=2, sort_keys=True) + '\n')
shutil.copy2(Path(__file__), out / 'executed-runner.py')
paths = [p for name in ['lib', 'test', 'third_party', 'assets'] for p in (runtime / name).rglob('*') if p.is_file() and not any(part in ['build', '.git', '.dart_tool'] for part in p.relative_to(runtime).parts)]
paths += [runtime / x for x in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.flutter-plugins-dependencies', '.dart_tool/package_config.json', '.dart_tool/package_graph.json'] if (runtime / x).is_file()]
closure = {str(p.relative_to(runtime)): {'sha256': sha(p), 'resolved_path': str(p.resolve()), 'symlink_target': str(p.readlink()) if p.is_symlink() else None} for p in paths}
(out / 'runtime-closure.json').write_text(json.dumps(closure, indent=2, sort_keys=True) + '\n')
deps = json.loads((root / '.cache/admin-governed-settings-ui-20261001/dependency-equivalence.json').read_text())
dep = []
for e in deps['entries']:
    p = Path(e['path'])
    if '/Google Chrome Framework.framework/Versions/' in str(p):
        p = Path('/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/Current/Google Chrome Framework').resolve()
    dep.append({'path': str(p), 'sha256': sha(p), 'resolved_path': str(p.resolve()), 'symlink_target': str(p.readlink()) if p.is_symlink() else None})
(out / 'dependencies.json').write_text(json.dumps(dep, indent=2, sort_keys=True) + '\n')
flutter = '/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
tests = ['test/admin_receipt_successor_models_test.dart', 'test/admin_receipt_successor_sdk_controller_test.dart', 'test/admin_receipt_successor_view_test.dart', 'test/admin_receipt_successor_host_test.dart']
command = [flutter, 'test', '--no-pub', '--concurrency=1', '--reporter=expanded'] + tests
if mode == 'analysis':
    command = [flutter, 'analyze', '--no-pub'] + [str(p.relative_to(runtime)) for p in (runtime / 'lib/admin/core').glob('admin_receipt_successor*.dart')] + [str(p.relative_to(runtime)) for p in (runtime / 'test').rglob('*.dart')]
if mode == 'browser':
    command = [flutter, 'test', '--no-pub', '--platform=chrome', '--concurrency=1', '--reporter=expanded', 'test/admin_receipt_successor_checkpoint_browser_test.dart']
if mode == 'capture':
    command = [flutter, 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', '--plain-name', 'operator review exposes headings, labelled reason and keyboard dismissal with actual rendered captures', 'test/admin_receipt_successor_view_test.dart']
env = os.environ.copy()
env['CHROME_EXECUTABLE'] = '/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
result = {'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'command': command, 'cwd': str(runtime), 'mode': mode, 'source_sha256': sha(out / 'source.json'), 'runtime_closure_sha256': sha(out / 'runtime-closure.json'), 'dependencies_sha256': sha(out / 'dependencies.json'), 'tools': {'runner': sha(out / 'executed-runner.py'), 'python_path': sys.executable, 'python': sha(Path(sys.executable)), 'flutter': sha(Path(flutter)), 'dart': sha(Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart'))}, 'exit_code': None}
(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
start = time.monotonic()
with (out / 'stdout.log').open('w') as stdout, (out / 'stderr.log').open('w') as stderr:
    c = subprocess.run(command, cwd=runtime, stdout=stdout, stderr=stderr, env=env, timeout=240)
result.update(exit_code=c.returncode, elapsed_seconds=time.monotonic() - start, completed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), source_unchanged=all(sha(stage / k) == v for k, v in source.items()), runtime_unchanged=all(sha(runtime / k) == v['sha256'] and str((runtime / k).resolve()) == v['resolved_path'] for k, v in closure.items()), dependencies_unchanged=all(sha(Path(d['path'])) == d['sha256'] and str(Path(d['path']).resolve()) == d['resolved_path'] for d in dep))
(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
print((out / 'stdout.log').read_text()[-15000:])
print((out / 'stderr.log').read_text()[-5000:])
sys.exit(c.returncode)
