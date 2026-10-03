#!/usr/bin/env python3
"""Use config-only's actual locked resolver cache; preserve failed copy guard."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

R = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
C = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930')
E = C / 'export-native-current-local-20261001-resumption1-ios'
P = R / 'docs/release/asset-build-hygiene-2026-09-30/native-current-local-20261001-resumption1/ios'
SDK = R / '.cache/flutter-sdk-isolated-asset-attempt28'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def module(name):
    spec = importlib.util.spec_from_file_location(name, E / ('scripts/qa/' + name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value
assert not (P / 'execution-continuation1.json').exists()
prior = json.loads((P / 'execution.json').read_text())
assert prior['status'] == 'fail' and prior['error'] == 'artifacts'
assert any(row['name'] == 'unsigned-ios-config' and row['exit_code'] == 0 for row in prior['commands'])
shutil.copy2(__file__, P / 'continuation1-runner-source.py')
source = json.loads((P / 'source-export.json').read_text())['source_sha256']
extras = json.loads((P / 'additional-tooling-inputs.json').read_text())['source_sha256']
assert all(sha(E / name) == digest for name, digest in {**source, **extras}.items())
cache = E / 'build/ios/SourcePackages'
shutil.copy2(cache / 'workspace-state.json', P / 'resolver-workspace-state-before.json')
generated = module('swift_generated_plugin_inputs')
package = module('resolved_native_package_inputs')
binary = module('swift_cached_artifact_inputs')
generated_binding = json.loads((P / 'generated-compiler-inputs-before.json').read_text())
package_binding = json.loads((P / 'resolved-package-inputs-before.json').read_text())
env = {k: v for k, v in os.environ.items() if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DEVELOPER_DIR='/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer',
           PUB_CACHE=str(R / '.cache/pub-cache-hygiene-20260930'), PATH=str(SDK / 'bin') + ':/Users/jeanbosco/.local/bin:' + env['PATH'])
pins = json.loads((E / 'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins']
checkouts = {}
for pin in pins:
    path = cache / 'checkouts' / pin['identity']
    revision = subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], env=env, text=True).strip()
    assert revision == pin['state']['revision'], pin['identity']
    names = subprocess.check_output(['git', '-C', str(path), 'ls-files', '-z'], env=env).decode().split('\0')
    regular = {name: sha(path / name) for name in names if name and (path / name).is_file() and not (path / name).is_symlink()}
    symlinks = {name: os.readlink(path / name) for name in names if name and (path / name).is_symlink()}
    checkouts[pin['identity']] = {'revision': revision, 'regular_source_sha256': regular, 'symlinks': symlinks}
write(P / 'swift-checkouts-before.json', checkouts)
binding = binary.bind(E, cache, generated_binding)
write(P / 'cached-binary-inputs-before.json', binding)
write(P / 'cache-preparation-correction.json', {'preserved_failed_execution_sha256': sha(P / 'execution.json'),
      'resolver_state_before_sha256': sha(P / 'resolver-workspace-state-before.json'),
      'cached_binary_binding_sha256': sha(P / 'cached-binary-inputs-before.json'),
      'scope': 'Config-only already resolved locked13 checkouts/9 binary artifacts in this fresh export. Validate/bind that complete actual cache with accepted helper instead of replacing it with another cache. No Flutter config, pub, resolver or native compilation repeated.'})
commands = list(prior['commands'])
argv = ['xcrun', 'xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'production', '-configuration', 'Release-production',
        '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS', '-derivedDataPath', str(E / 'build/ios/DerivedData'),
        '-clonedSourcePackagesDirPath', str(cache), '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution', '-skipPackageUpdates',
        '-jobs', '2', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_IDENTITY=', 'DEVELOPMENT_TEAM=', 'build']
write(P / 'execution-continuation1.json', {'status': 'running', 'pid': os.getpid(), 'stage': 'unsigned-ios-build', 'commands': commands})
print('START unsigned-ios-build', flush=True)
started = time.monotonic()
with (P / 'unsigned-ios-build.stdout').open('wb') as out, (P / 'unsigned-ios-build.stderr').open('wb') as err:
    result = subprocess.run(argv, cwd=E, env=env, stdout=out, stderr=err)
commands.append({'name': 'unsigned-ios-build', 'command': argv, 'exit_code': result.returncode, 'elapsed_seconds': round(time.monotonic() - started, 2),
                 'stdout_sha256': sha(P / 'unsigned-ios-build.stdout'), 'stderr_sha256': sha(P / 'unsigned-ios-build.stderr')})
write(P / 'execution-continuation1.json', {'status': 'running' if result.returncode == 0 else 'fail', 'commands': commands})
assert result.returncode == 0, 'Actual Xcode build failed'
for name, receipt in [('resolved-package-inputs-after', package.verify(package_binding, E)),
                      ('generated-compiler-inputs-after', generated.verify(generated_binding, E)),
                      ('cached-binary-inputs-after', binary.verify(binding))]:
    write(P / (name + '.json'), receipt)
    assert receipt['status'] == 'pass', name
for identity, row in checkouts.items():
    path = cache / 'checkouts' / identity
    assert all(sha(path / name) == digest for name, digest in row['regular_source_sha256'].items()), identity
    assert all(os.readlink(path / name) == target for name, target in row['symlinks'].items()), identity
assert all(sha(E / name) == digest for name, digest in {**source, **extras}.items())
write(P / 'source-after.json', {'working_copy_drift': [], 'checkouts_compiler_sources_unchanged': True, 'checked_input_count': len(source) + len(extras)})
write(P / 'execution-continuation1.json', {'status': 'pass', 'commands': commands, 'preserved_failed_execution_sha256': sha(P / 'execution.json'),
      'scope': 'Single actual unsigned Xcode compilation of frozen current candidate after truthful binding of existing config-only resolver cache; earlier copy-preparation failure preserved.'})
print('IOS TERMINAL PASS', flush=True)
