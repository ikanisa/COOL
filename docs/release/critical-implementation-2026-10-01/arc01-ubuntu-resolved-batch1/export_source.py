#!/usr/bin/env python3
"""Freeze the full maintained Dart inventory and canonical Pub input declarations."""
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
BOUNDARY = json.loads((OUT / 'preparation-attempt1/private-boundary.json').read_text())
PRIVATE = Path(BOUNDARY['private_root'])
ATTEMPT = OUT / 'source-export-attempt1'
ATTEMPT.mkdir(exist_ok=False)
CHECKOUT = PRIVATE / 'checkout'
CHECKOUT.mkdir(exist_ok=False)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, data):
    (ATTEMPT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


try:
    raw = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others',
                                  '--exclude-standard', '--', '*.dart'], cwd=ROOT, timeout=30)
    with gzip.open(ATTEMPT / 'original-git-dart-inventory.nul.gz', 'wb') as stream:
        stream.write(raw)
    paths = sorted(set(x.decode() for x in raw.split(b'\0') if x))
    existing = [x for x in paths if (ROOT / x).is_file()]
    dart = [x for x in existing if not x.startswith('docs/release/')]
    configs = {'.fvmrc', '.gitignore', 'Makefile', '.github/workflows/ci.yml',
               'scripts/qa/dart_format.rb', 'pubspec.yaml', 'pubspec.lock',
               'analysis_options.yaml', 'third_party/gotrue/UPSTREAM-SHA256.json'}
    for path in dart:
        parent = (ROOT / path).parent
        while parent != ROOT:
            for name in ('pubspec.yaml', 'analysis_options.yaml'):
                if (parent / name).is_file():
                    configs.add(str((parent / name).relative_to(ROOT)))
            parent = parent.parent
    # Genuine local dependency package inputs, including native/plugin manifests.
    # Only Git-visible existing public source is exported, never caches or .git.
    fork_raw = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others',
                                       '--exclude-standard', '--', 'third_party/file_saver',
                                       'third_party/firebase_messaging', 'third_party/gotrue'],
                                      cwd=ROOT, timeout=30)
    forks = set(x.decode() for x in fork_raw.split(b'\0') if x
                and (ROOT / x.decode()).is_file())
    for path in forks:
        parts = Path(path).parts
        if any(part in ('.git', '.dart_tool', '.pub-cache', 'build', '.env')
               or part.startswith('.env.') for part in parts):
            raise RuntimeError('Forbidden generated/credential path in package inventory')
    inputs = sorted(set(dart) | configs | forks)
    if any((ROOT / path).is_symlink() or not (ROOT / path).resolve().is_relative_to(ROOT)
           for path in inputs):
        raise RuntimeError('Unexpected input link or checkout escape')
    before = {path: sha(ROOT / path) for path in inputs}
    write('root-inputs-before.json', before)
    for path in inputs:
        target = CHECKOUT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / path, target)
        if sha(target) != before[path]:
            raise RuntimeError('Copied source mismatch: ' + path)
    after = {path: sha(ROOT / path) for path in inputs}
    write('root-inputs-after-export.json', after)
    if after != before:
        raise RuntimeError('Root source changed during strict export')
    upstream = json.loads((CHECKOUT / 'third_party/gotrue/UPSTREAM-SHA256.json').read_text())
    exclusions = [path for path in dart if path.startswith('third_party/gotrue/')
                  and upstream.get(path.removeprefix('third_party/gotrue/')) == before[path]]
    applicable = sorted(set(dart) - set(exclusions))
    write('source-inventory.json', {'at_utc': now(), 'private_checkout': str(CHECKOUT),
          'root_checkout': str(ROOT), 'copied_input_sha256': before,
          'private_copy_sha256': {path: sha(CHECKOUT / path) for path in inputs},
          'git_visible_dart_paths': len(paths), 'existing_dart_paths': len(existing),
          'docs_snapshot_exclusions': len(existing) - len(dart),
          'non_docs_dart_paths': dart, 'hash_identical_upstream_exclusions': exclusions,
          'applicable_formatter_paths': applicable, 'local_dependency_input_paths': sorted(forks),
          'private_candidate_mutated': False, 'root_source_mutated': False,
          'canonical_pub_bootstrap_executed': False})
    print(json.dumps({'inputs': len(inputs), 'applicable_dart': len(applicable),
                      'checkout': str(CHECKOUT), 'root_copy_readback_equal': before == after}, indent=2))
except Exception as error:
    write('failure.json', {'at_utc': now(), 'type': type(error).__name__, 'error': str(error),
                          'private_checkout': str(CHECKOUT), 'root_source_mutated': False})
    raise
