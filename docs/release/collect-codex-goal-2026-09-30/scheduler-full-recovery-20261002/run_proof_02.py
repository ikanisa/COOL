from pathlib import Path
import hashlib, json, os, subprocess, time

root = Path(__file__).resolve().parent
repository = root.parent.parent
workspace = root / 'workspace'
project = workspace / 'tools/collect-notification-mcp'
output = root / 'proof-final-02'
output.mkdir(mode=0o700)
node = Path('/Volumes/PRO-G40/Development/Node/bin/node')

def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1048576), b''):
            result.update(data)
    return result.hexdigest()

def freeze():
    entries, links = {}, {}
    for base in [workspace, (project / 'node_modules').resolve()]:
        for directory, folders, files in os.walk(base, followlinks=False):
            for name in folders[:]:
                path = Path(directory) / name
                if path.is_symlink():
                    links[str(path)] = os.readlink(path)
                    folders.remove(name)
            for name in files:
                path = Path(directory) / name
                if path.is_symlink():
                    links[str(path)] = os.readlink(path)
                else:
                    entries[str(path)] = digest(path)
    for path in [node, Path('/usr/bin/python3').resolve()]:
        entries[str(path)] = digest(path)
    return {'files': entries, 'links': links}

before = freeze()
(output / 'inputs-before.json').write_text(json.dumps(before, indent=2) + '\n')
env = {'PATH': str(node.parent) + ':/usr/bin:/bin', 'LANG': 'C'}
commands = [
    ('typecheck', [str(node), 'node_modules/typescript/bin/tsc', '--noEmit']),
    ('cases', [str(node), '--experimental-strip-types', '--test',
               'src/unattended_recovery.test.ts', 'src/unattended_scheduler_control.test.ts']),
]
results = []
for name, argv in commands:
    started = time.time()
    with (output / (name + '.stdout')).open('wb') as stdout, (output / (name + '.stderr')).open('wb') as stderr:
        result = subprocess.run(argv, cwd=project, env=env, stdout=stdout, stderr=stderr)
    results.append({'name': name, 'argv': argv, 'exit_code': result.returncode, 'elapsed_seconds': time.time() - started})
    print(json.dumps(results[-1]), flush=True)
    if result.returncode:
        break
after = freeze()
(output / 'inputs-after.json').write_text(json.dumps(after, indent=2) + '\n')
drift = [key for section in before for key in set(before[section]) | set(after[section]) if before[section].get(key) != after[section].get(key)]
baseline = json.loads((root / 'canonical-baseline.json').read_text())
canonical_drift = [path for path, expected in baseline.items() if not (repository / path).is_file() or digest(repository / path) != expected]
summary = {'status': 'pass' if len(results) == 2 and all(item['exit_code'] == 0 for item in results) and not drift else 'fail',
           'commands': results, 'input_drift': drift, 'canonical_baseline_drift': canonical_drift,
           'inputs_sha256': digest(output / 'inputs-before.json'), 'private_staging_only': True}
(output / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary), flush=True)
