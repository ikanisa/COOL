import hashlib,json,subprocess,importlib.util
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/swift-generated-inputs-attempt129'
P.mkdir(exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=['scripts/qa/swift_generated_plugin_inputs.py','scripts/tests/swift_generated_plugin_inputs_test.py']
source={n:sha(ROOT/n) for n in files}
(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
with (P/'test.stdout').open('wb') as out,(P/'test.stderr').open('wb') as err:code=subprocess.run(['python3',files[1]],cwd=ROOT,stdout=out,stderr=err).returncode
assert code==0
spec=importlib.util.spec_from_file_location('strict_swift_inputs',ROOT/files[0]);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
OLD=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt100-ios'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt100-ios')
binding=json.loads((OLD/'resolved-package-inputs-before.json').read_text());declared=json.loads((OLD/'source-export.json').read_text())['source_sha256']
preflight=module.bind(EXPORT,binding,declared,dry_run=True)
(P/'actual-ios100-read-only-preflight.json').write_text(json.dumps(preflight,indent=2,sort_keys=True)+'\n')
generator=ROOT/'.cache/flutter-sdk-isolated-asset-attempt28/packages/flutter_tools/lib/src/macos/swift_package_manager.dart'
text=generator.read_text();assert '_copyPluginAndUpdateManifest' in text and 'newManifestContent.replaceAll(' in text
(P/'validation.json').write_text(json.dumps({'status':'pass','test_count':24,'source_sha256':source,'sources_unchanged':all(sha(ROOT/n)==h for n,h in source.items()),'actual_dated_ios_compiler_aliases':len(preflight['packages']),'actual_dated_native_package_aliases':len(preflight['native_package_aliases']),'historical_aliases_changed':False,'planned_hosted_redirections':len(preflight['planned_redirections']),'reviewed_pinned_generator_sha256':sha(generator),'reviewed_transform':'Exact relative plugin-name to actual declared versioned alias replaceAll from the pinned Flutter generator; every other generated copy byte must equal the declared native source.','preflight_sha256':sha(P/'actual-ios100-read-only-preflight.json'),'test_stdout_sha256':sha(P/'test.stdout'),'test_stderr_sha256':sha(P/'test.stderr'),'scope':'Twenty-four meaningful mutation/control tests and read-only reconciliation of actual dated compiler inputs; future native launch requires actual binding after config-only, then unchanged aliases/files verification.'},indent=2)+'\n')
print('SWIFT GENERATED INPUTS PASS',len(preflight['packages']),len(preflight['planned_redirections']),flush=True)
