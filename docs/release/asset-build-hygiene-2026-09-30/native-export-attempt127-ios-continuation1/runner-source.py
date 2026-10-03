import hashlib,json,os,subprocess,time,shutil,importlib.util
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PARENT=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios'
PACKET=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios-continuation1'
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
# Copy only cached resolver entries; preserve the freshly generated local plugin
# copy already in this directory. Do not nest a stale SourcePackages directory.
old_cache=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt18-ios/build/ios/SourcePackages')
# Retain every actual config-generated resolver component in this task export.
# Then import the exact previously pinned cache into the now-vacant paths.
preserved_cache=EXPORT/'build/ios/configured-resolver-before-cache-import'
assert not preserved_cache.exists();preserved_cache.mkdir()
configured_inventory={}
for component in ['artifacts','checkouts','repositories','workspace-state.json']:
 target=cache/component
 if target.exists():
  entries={}
  if target.is_dir():
   for child in sorted(target.rglob('*')):
    name=child.relative_to(target).as_posix()
    if child.is_symlink():entries[name]={'symlink':os.readlink(child)}
    elif child.is_file():entries[name]={'sha256':sha(child),'bytes':child.stat().st_size,'mode':child.stat().st_mode & 0o777}
  else:entries['.']={'sha256':sha(target),'bytes':target.stat().st_size,'mode':target.stat().st_mode & 0o777}
  configured_inventory[component]={'path':str(preserved_cache/component),'entries':entries}
  shutil.move(str(target),str(preserved_cache/component))
 assert not target.exists()
 run('copy-pinned-'+component.replace('.','-'),['cp','-cR',str(old_cache/component),str(target)])
(PACKET/'configured-resolver-preservation.json').write_text(json.dumps({'status':'preserved','source_config_packet':str(PARENT),'before_compilation':True,'components':configured_inventory,'scope':'Generated local resolver cache only; all pre-configuration source/locks and the newly generated local plugin directory remain intact'},indent=2,sort_keys=True)+'\n')
pins=json.loads((EXPORT/'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins'];observed={}
for pin in pins:
 checkout=cache/'checkouts'/pin['identity'];actual=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],env=ENV,text=True).strip();assert actual==pin['state']['revision'],pin['identity'];observed[pin['identity']]={'revision':actual,'version':pin['state'].get('version')}
(PACKET/'swift-package-cache-verification.json').write_text(json.dumps({'scope':'Local cached checkouts compared with exact lock revisions before actual Xcode build; no provider data or new version resolution','checkouts':observed},indent=2)+'\n')
# Bind copied binary XCFramework compiler paths to this export, not old18.
BINARY_TOOL='scripts/qa/swift_cached_artifact_inputs.py'
binary_proof_path=ROOT/'docs/release/asset-build-hygiene-2026-09-30/swift-cached-artifact-inputs-root169/validation.json'
binary_proof=json.loads(binary_proof_path.read_text())
assert binary_proof['status']=='pass' and sha(EXPORT/BINARY_TOOL)==binary_proof['source_sha256'][BINARY_TOOL] and sha(ROOT/BINARY_TOOL)==binary_proof['source_sha256'][BINARY_TOOL]
shutil.copy2(EXPORT/BINARY_TOOL,PACKET/'swift_cached_artifact_inputs.py')
binary_spec=importlib.util.spec_from_file_location('actual_swift_binary_inputs',PACKET/'swift_cached_artifact_inputs.py');binary_module=importlib.util.module_from_spec(binary_spec);binary_spec.loader.exec_module(binary_module)
binary_binding=binary_module.bind(EXPORT,old_cache)
(PACKET/'cached-binary-inputs-before.json').write_text(json.dumps(binary_binding,indent=2,sort_keys=True)+'\n')
(PACKET/'cached-binary-tool-binding.json').write_text(json.dumps({'source_sha256':sha(PACKET/'swift_cached_artifact_inputs.py'),'accepted17_test_receipt_sha256':sha(binary_proof_path),'scope':'Exact cached binary bytes/modes/internal symlinks and guarded workspace metadata path relocation before Xcode; recorded archive checksums are not download authenticity.'},indent=2)+'\n')
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
