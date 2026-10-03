from pathlib import Path
import datetime, hashlib, json, os, shutil, subprocess, sys, time

stage = Path(__file__).resolve().parent
root = stage.parents[1]
app = stage / 'validation-app'
packet = root / '.cache/receipt-successor-workflows-20261001/accepted-successor-admin-current1'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
mode, attempt = sys.argv[1:3]
out = stage / 'proofs' / attempt
out.mkdir(parents=True, exist_ok=False)
prep = json.loads((stage / 'root-preparation-current.json').read_text())
canonical = json.loads((packet / 'canonical-current2-inputs.json').read_text())
canonical.update(prep['legacy_inputs'])
assert all(sha(root / k) == v for k, v in canonical.items())
for src in (stage / 'source').rglob('*'):
    if src.is_file():
        dst = app / src.relative_to(stage / 'source')
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
source = {str(p.relative_to(stage / 'source')): sha(p) for p in (stage / 'source').rglob('*') if p.is_file()}
for name in source:
    dst = out / 'root-source' / name
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(stage / 'source' / name, dst)
shutil.copy2(Path(__file__), out / 'executed-runner.py')
paths = [p for name in ['lib', 'test', 'third_party', 'assets', 'docs'] for p in (app / name).rglob('*') if p.is_file() and not any(part in ['build', '.git', '.dart_tool'] for part in p.relative_to(app).parts)]
paths += [app / x for x in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.flutter-plugins-dependencies', '.dart_tool/package_config.json', '.dart_tool/package_graph.json'] if (app / x).is_file()]
runtime = {str(p.relative_to(app)): {'sha256': sha(p), 'resolved_path': str(p.resolve()), 'symlink_target': str(p.readlink()) if p.is_symlink() else None} for p in paths}
deps = json.loads((packet / 'dependencies/map.json').read_text())
assert all(sha(Path(d['path'])) == d['sha256'] and str(Path(d['path']).resolve()) == d['resolved_path'] for d in deps)
tools = json.loads((packet / 'tools/map.json').read_text())
assert all(sha(Path(d['path'])) == d['sha256'] for d in tools.values())
tools['actual_runner_python'] = {'path': sys.executable, 'sha256': sha(Path(sys.executable))}
for name, value in [('source', source), ('canonical', canonical), ('runtime', runtime), ('dependencies', deps), ('tools', tools)]:
    (out / (name + '.json')).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
flutter = tools['flutter']['path']
command = [flutter, 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', '--dart-define=COLLECT_CAPTURE_SUCCESSOR_INTEGRATION=true', 'test/admin_receipt_successor_integration_test.dart', 'test/admin_investigation_view_test.dart']
if mode == 'analysis':
    command = [flutter, 'analyze', '--no-pub', 'lib/admin/core/admin_investigation_view.dart', 'test/admin_receipt_successor_integration_test.dart']
result = {'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'command': command, 'cwd': str(app), 'mode': mode, 'source_sha256': sha(out / 'source.json'), 'runtime_sha256': sha(out / 'runtime.json'), 'dependencies_sha256': sha(out / 'dependencies.json'), 'canonical_sha256': sha(out / 'canonical.json'), 'tools_sha256': sha(out / 'tools.json'), 'exit_code': None}
(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
start = time.monotonic()
with (out / 'stdout.log').open('w') as stdout, (out / 'stderr.log').open('w') as stderr:
    completed = subprocess.run(command, cwd=app, stdout=stdout, stderr=stderr, timeout=300)
result.update(exit_code=completed.returncode, elapsed_seconds=time.monotonic()-start, completed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), source_unchanged=all(sha(stage / 'source' / k) == v for k,v in source.items()), canonical_unchanged=all(sha(root/k)==v for k,v in canonical.items()), runtime_unchanged=all(sha(app/k)==v['sha256'] and str((app/k).resolve())==v['resolved_path'] for k,v in runtime.items()), dependencies_unchanged=all(sha(Path(d['path']))==d['sha256'] and str(Path(d['path']).resolve())==d['resolved_path'] for d in deps), tools_unchanged=all(sha(Path(d['path']))==d['sha256'] for d in tools.values()))
result['accepted'] = completed.returncode == 0 and all(result[x] for x in ['source_unchanged','canonical_unchanged','runtime_unchanged','dependencies_unchanged','tools_unchanged']) and ('All tests passed!' in (out/'stdout.log').read_text() if mode != 'analysis' else 'No issues found!' in (out/'stdout.log').read_text())
(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
if mode != 'analysis':
    for p in (app/'proof-artifacts').glob('root-review-*.png'):
        dest=out/'proof-artifacts'/p.name
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(p,dest)
print(json.dumps(result))
print((out/'stdout.log').read_text()[-16000:])
print((out/'stderr.log').read_text()[-3000:])
sys.exit(0 if result['accepted'] else 1)
