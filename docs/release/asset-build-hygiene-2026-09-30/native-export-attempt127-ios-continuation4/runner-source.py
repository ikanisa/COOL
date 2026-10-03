import hashlib,json,os,subprocess,time,shutil,importlib.util
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PARENT=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios'
PACKET=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios-continuation4'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt127-ios')
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt28'
ENV={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
ENV.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','DEVELOPER_DIR':'/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'COCOAPODS_DISABLE_STATS':'true','CP_HOME_DIR':str(EXPORT.parent/'cocoapods-attempt127-home'),'CP_CACHE_DIR':str(EXPORT.parent/'cocoapods-attempt127-cache'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+ENV['PATH']})
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
prior=json.loads((PARENT/'execution.json').read_text());failed=json.loads((PARENT/'wrapper-failure-root.json').read_text())
assert failed['observed_terminal_exit_code']==1 and failed['xcode_compilation_executed'] is False
assert [c['name'] for c in prior['commands']]==['export-git-init','flutter-version','xcode-version','pub-enforce','unsigned-ios-config']
assert all(c['exit_code']==0 for c in prior['commands'])
for c in prior['commands']:
 for stream in ('stdout','stderr'):assert sha(PARENT/(c['name']+'.'+stream))==c[stream+'_sha256']
manifest=json.loads((PARENT/'source-export.json').read_text());source=manifest['source_sha256'];inputs=manifest['clone_inputs_sha256']
assert all((EXPORT/n).is_file() and sha(EXPORT/n)==h for n,h in inputs.items())
PACKET.mkdir(exist_ok=False);(PACKET/'runner-source.py').write_bytes(Path(__file__).read_bytes())
for name in ['source-export.json','environment-scope.json','resolved-package-inputs-before.json','resolved-package-tool-binding.json','resolved_native_package_inputs.py','generated-compiler-inputs-before.json','generated-compiler-tool-binding.json','swift_generated_plugin_inputs.py','configuration-lock-comparison.json']:
 shutil.copy2(PARENT/name,PACKET/name)
(PACKET/'prior-config-binding.json').write_text(json.dumps({'status':'reused_unchanged_configuration','prior_execution_sha256':sha(PARENT/'execution.json'),'prior_failed_wrapper_sha256':sha(PARENT/'wrapper-failure-root.json'),'prior_runner_sha256':sha(PARENT/'runner-source.py'),'commands_reexecuted':False,'prior_actual_commands':prior['commands'],'config_logs':{c['name']:{stream:sha(PARENT/(c['name']+'.'+stream)) for stream in ('stdout','stderr')} for c in prior['commands']}},indent=2)+'\n')
def load_module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
package_module=load_module('retained_native_packages',PACKET/'resolved_native_package_inputs.py')
package_binding=json.loads((PACKET/'resolved-package-inputs-before.json').read_text())
assert package_module.verify(package_binding,EXPORT)['status']=='pass'
generated_module=load_module('retained_generated_inputs',PACKET/'swift_generated_plugin_inputs.py')
generated_binding=json.loads((PACKET/'generated-compiler-inputs-before.json').read_text())
assert generated_module.verify(generated_binding,EXPORT)['status']=='pass'
locks=json.loads((PACKET/'configuration-lock-comparison.json').read_text())
assert all(d['before_sha256']==d['after_sha256']==sha(EXPORT/n) for n,d in locks.items())
commands=[]
def run(name,argv,cwd=EXPORT,expected=0):
 print('START',name,flush=True);start=time.time()
 with (PACKET/(name+'.stdout')).open('wb') as out,(PACKET/(name+'.stderr')).open('wb') as err:
  code=subprocess.run(argv,cwd=cwd,env=ENV,stdout=out,stderr=err).returncode
 commands.append({'name':name,'command':argv,'exit_code':code,'elapsed_seconds':round(time.time()-start,2),'stdout_sha256':sha(PACKET/(name+'.stdout')),'stderr_sha256':sha(PACKET/(name+'.stderr'))})
 (PACKET/'execution.json').write_text(json.dumps({'status':'running' if code==expected else 'failed','commands':commands,'prior_config_binding_sha256':sha(PACKET/'prior-config-binding.json'),'scope':'Actual unsigned source-bound iOS build continued after unchanged retained config-only; original failed prebuild packet preserved'},indent=2)+'\n')
 print('END',name,code,flush=True)
 if code!=expected:raise SystemExit(code if code>0 else 1)
cache=EXPORT/'build/ios/SourcePackages'
old_cache=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt18-ios/build/ios/SourcePackages')
previous=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios-continuation1'
assert json.loads((previous/'wrapper-failure-root.json').read_text())['xcode_compilation_executed'] is False
shutil.copy2(previous/'configured-resolver-preservation.json',PACKET/'configured-resolver-preservation.json')
(PACKET/'previous-cache-import-binding.json').write_text(json.dumps({'prior_failed_packet':str(previous),'failure_sha256':sha(previous/'wrapper-failure-root.json'),'actual_import_execution_sha256':sha(previous/'execution.json'),'preserved_generated_cache_sha256':sha(previous/'configured-resolver-preservation.json'),'copy_reexecuted':False},indent=2)+'\n')
pins=json.loads((EXPORT/'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins'];observed={}
for pin in pins:
 checkout=cache/'checkouts'/pin['identity'];actual=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],env=ENV,text=True).strip();assert actual==pin['state']['revision'],pin['identity'];observed[pin['identity']]={'revision':actual,'version':pin['state'].get('version')}
(PACKET/'swift-package-cache-verification.json').write_text(json.dumps({'scope':'Local cached checkouts compared with exact lock revisions before actual Xcode build; no provider data or new version resolution','checkouts':observed},indent=2)+'\n')
# Bind copied binary XCFramework compiler paths to this export, not old18.
BINARY_TOOL='scripts/qa/swift_cached_artifact_inputs.py'
binary_proof_path=ROOT/'docs/release/asset-build-hygiene-2026-09-30/swift-cached-artifact-inputs-root173-complete-workspace/validation.json'
binary_proof=json.loads(binary_proof_path.read_text())
assert binary_proof['status']=='pass' and binary_proof['tests']==30 and sha(ROOT/BINARY_TOOL)==binary_proof['source_sha256'][BINARY_TOOL]
shutil.copy2(ROOT/BINARY_TOOL,PACKET/'swift_cached_artifact_inputs.py')
binary_spec=importlib.util.spec_from_file_location('actual_swift_binary_inputs',PACKET/'swift_cached_artifact_inputs.py');binary_module=importlib.util.module_from_spec(binary_spec);binary_spec.loader.exec_module(binary_module)
# macOS cp -cR applied the default umask to 56 symbolic-link modes.
# Correct only those copied link objects, preserving every byte and target.
current_artifacts=EXPORT/'build/ios/SourcePackages/artifacts'
current_tree=binary_module.artifact_tree(current_artifacts)
prior_tree=binary_module.artifact_tree(old_cache/'artifacts')
assert set(current_tree)==set(prior_tree)
mode_corrections=[]
for name in sorted(current_tree):
 current,prior=current_tree[name],prior_tree[name]
 if current==prior:continue
 assert current['kind']==prior['kind']=='symlink'
 assert {k:v for k,v in current.items() if k!='mode'}=={k:v for k,v in prior.items() if k!='mode'}
 assert current['mode']==0o755 and prior['mode']==0o777
 path=current_artifacts/name;assert path.is_symlink()
 os.lchmod(path,prior['mode'])
 mode_corrections.append({'path':name,'before_mode':current['mode'],'after_mode':prior['mode'],'target':prior['target']})
assert binary_module.artifact_tree(current_artifacts)==prior_tree
(PACKET/'copied-symlink-mode-correction.json').write_text(json.dumps({'status':'pass','exact_copied_tree_matches_preserved_cache':True,'binary_bytes_and_symlink_targets_changed':False,'corrections':mode_corrections,'scope':'Task-owned copied cache links only; strict byte/mode/path binding retained'},indent=2)+'\n')
binary_binding=binary_module.bind(EXPORT,old_cache,generated_binding)
(PACKET/'cached-binary-inputs-before.json').write_text(json.dumps(binary_binding,indent=2,sort_keys=True)+'\n')
(PACKET/'cached-binary-tool-binding.json').write_text(json.dumps({'source_sha256':sha(PACKET/'swift_cached_artifact_inputs.py'),'accepted30_test_receipt_sha256':sha(binary_proof_path),'scope':'Exact cached binary and generated current compiler inputs with guarded local and binary metadata relocation before Xcode; recorded archive checksums are not download authenticity.'},indent=2)+'\n')
print('ACTUAL CACHED BINARY INPUTS BOUND',len(binary_binding['relocations']),binary_binding['regular_file_count'],flush=True)
SPM_OBSERVER=ROOT/'.cache/observe-swift-package-source-attempt131.py'
shutil.copy2(SPM_OBSERVER,PACKET/'spm-observer-source.py')
ENV['COLLECT_SPM_OBSERVATION_PHASE']='pre_build'
run('swift-pinned-inputs-prebuild',['python3',str(PACKET/'spm-observer-source.py')],ROOT)
run('unsigned-ios-build',['xcrun','xcodebuild','-workspace','ios/Runner.xcworkspace','-scheme','production','-configuration','Release-production','-sdk','iphoneos','-destination','generic/platform=iOS','-derivedDataPath',str(EXPORT/'build/ios/DerivedData'),'-clonedSourcePackagesDirPath',str(EXPORT/'build/ios/SourcePackages'),'-onlyUsePackageVersionsFromResolvedFile','-disableAutomaticPackageResolution','-skipPackageUpdates','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGNING_IDENTITY=','DEVELOPMENT_TEAM=','build'])
ENV['COLLECT_SPM_OBSERVATION_PHASE']='after_build'
run('swift-pinned-inputs-afterbuild',['python3',str(PACKET/'spm-observer-source.py')],ROOT)
binary_check=binary_module.verify(binary_binding)
(PACKET/'cached-binary-inputs-after.json').write_text(json.dumps(binary_check,indent=2,sort_keys=True)+'\n');assert binary_check['status']=='pass'
generated_check=generated_module.verify(generated_binding,EXPORT)
(PACKET/'generated-compiler-inputs-after.json').write_text(json.dumps(generated_check,indent=2,sort_keys=True)+'\n');assert generated_check['status']=='pass','Actual generated native compiler input drift'
package_check = package_module.verify(package_binding, EXPORT)
(PACKET / 'resolved-package-inputs-after.json').write_text(json.dumps(package_check, indent=2, sort_keys=True) + '\n')
assert package_check['status'] == 'pass', 'Actual resolved compiler/plugin package input drift'
(PACKET/'execution.json').write_text(json.dumps({'status':'pass','commands':commands,'scope':'Isolated source-only unsigned iOS QA compilation; no credentials, signed store/provider/device acceptance'},indent=2)+'\n')
print('IOS BUILD PASS',flush=True)
