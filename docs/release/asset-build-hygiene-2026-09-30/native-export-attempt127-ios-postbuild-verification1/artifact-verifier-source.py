import hashlib,json,os,plistlib,subprocess,importlib.util
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt127-ios-postbuild-verification1';EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt127-ios');APP=EXPORT/'build/ios/DerivedData/Build/Products/Release-production-iphoneos/Collect.app'
assert APP.is_dir();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not (P/'artifact-verification.json').exists()
build=json.loads((P/'execution.json').read_text());assert build['status']=='pass'
for c in build['commands']:
 assert c['exit_code']==0
 for stream in ('stdout','stderr'):assert sha(P/(c['name']+'.'+stream))==c[stream+'_sha256']
assert '** BUILD SUCCEEDED **' in (P/'unsigned-ios-build.stdout').read_text()

info=plistlib.loads((APP/'Info.plist').read_bytes());assert info['CFBundleIdentifier']=='app.cool.mobile' and info['CFBundleShortVersionString']=='1.2.4' and info['CFBundleVersion']=='23';assert info['DTPlatformName']=='iphoneos'
assert not (APP/'embedded.mobileprovision').exists() and not (APP/'_CodeSignature').exists()
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG'}};env['DEVELOPER_DIR']='/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer'
commands=[]
for n,args in [('app-signature',['codesign','--verify','--strict','--deep',str(APP)]),('app-signature-details',['codesign','--display','--verbose=4',str(APP)]),('app-platform',['xcrun','vtool','-show-build',str(APP/info['CFBundleExecutable'])])]:
 r=subprocess.run(args,env=env,capture_output=True);(P/(n+'.stdout')).write_bytes(r.stdout);(P/(n+'.stderr')).write_bytes(r.stderr);commands.append({'name':n,'command':args,'exit_code':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if n.startswith('app-signature'):assert r.returncode!=0 and 'not signed' in (r.stdout+r.stderr).decode().lower()
 else:assert r.returncode==0 and 'platform IOS' in r.stdout.decode()
files={};symlinks={}
for f in sorted(APP.rglob('*')):
 if f.is_symlink():
  assert f.resolve().is_relative_to(APP.resolve());symlinks[f.relative_to(APP).as_posix()]=os.readlink(f)
 elif f.is_file():files[f.relative_to(APP).as_posix()]={'sha256':sha(f),'bytes':f.stat().st_size}
manifest={'files':files,'symlinks':symlinks};(P/'bundle-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
export_manifest=json.loads((P/'source-export.json').read_text());source=export_manifest['source_sha256'];inputs=export_manifest['clone_inputs_sha256'];changes={n:{'before_sha256':h,'after_sha256':sha(EXPORT/n) if (EXPORT/n).is_file() else None} for n,h in inputs.items() if not (EXPORT/n).is_file() or sha(EXPORT/n)!=h}
assert not changes,'Build changed a declared exported source'
original_binds=['.dart_tool/package_config.json','.flutter-plugins-dependencies','ios/Flutter/Generated.xcconfig','ios/Flutter/flutter_export_environment.sh','ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift','ios/Pods/Manifest.lock']
generated={n:sha(EXPORT/n) for n in original_binds if (EXPORT/n).is_file()};assert '.dart_tool/package_config.json' in generated and 'ios/Flutter/Generated.xcconfig' in generated
(P/'generated-bindings.json').write_text(json.dumps({'scope':'Generated public package/plugin and pinned local toolchain bindings; no ignored private source copied','sha256':generated},indent=2)+'\n')
spec=importlib.util.spec_from_file_location('bound_export_scope',EXPORT/'scripts/qa/native_source_export.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
current_names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
current={n:sha(ROOT/n) for n in sorted(set(current_names)) if n and (module.selected(n) or n.startswith('scripts/') or n in {'Makefile','.gitignore'}) and (ROOT/n).is_file() and not (ROOT/n).is_symlink()}
checkout_drift={n:{'before_sha256':inputs.get(n),'after_sha256':current.get(n)} for n in sorted(inputs.keys()|current.keys()) if inputs.get(n)!=current.get(n)}
package_spec=importlib.util.spec_from_file_location('native_package_verification',P/'resolved_native_package_inputs.py');package_module=importlib.util.module_from_spec(package_spec);package_spec.loader.exec_module(package_module)
package_binding=json.loads((P/'resolved-package-inputs-before.json').read_text());package_check=package_module.verify(package_binding,EXPORT)
assert package_check['status']=='pass','Resolved compiler/plugin input drift during artifact verification'
(P/'resolved-package-inputs-artifact-verification.json').write_text(json.dumps(package_check,indent=2)+'\n')
report={'resolved_package_binding_sha256':sha(P/'resolved-package-inputs-before.json'),'resolved_package_verification_sha256':sha(P/'resolved-package-inputs-artifact-verification.json'),'resolved_package_inputs_unchanged':True,'original_checkout_drift':checkout_drift,'current_checkout_acceptance':not checkout_drift,'build_execution_sha256':sha(P/'execution.json'),'status':'pass','kind':'local_unsigned_ios_qa_artifact','bundle':str(APP),'bundle_file_count':len(files),'bundle_regular_file_bytes':sum(x['bytes'] for x in files.values()),'bundle_manifest_sha256':sha(P/'bundle-manifest.json'),'main_executable_sha256':sha(APP/info['CFBundleExecutable']),'bundle_identifier':info['CFBundleIdentifier'],'version':'1.2.4+23','sdk':info['DTSDKName'],'compiled_platform':'iOS device arm64, generic destination','root_bundle_unsigned_verified':True,'embedded_provisioning_profile_absent':True,'declared_exported_sources_unchanged':True,'source_file_count':len(source),'commands':commands,'marker':{'kind':'local_unsigned_native_qa','signing':False,'store_acceptance':False,'provider_configuration':False},'scope':'Actual retained source export including all three forks, complete compilation and unsigned artifact inspection; no device/simulator, native visual, signed store, provider or current whole-runtime acceptance'}
report.update({'total_bound_input_count':len(inputs),'declared_exported_sources_and_tooling_unchanged':True,'scope_drift_includes_additions_and_deletions':True})
runtime_roots=('lib/','assets/','licenses/','android/','ios/','third_party/','web/')
runtime_files={'pubspec.yaml','pubspec.lock','.metadata','.fvmrc','.dvmrc','scripts/android_play_store_build.sh','scripts/android_release_signing_preflight.sh','scripts/ios_app_store_build.sh','scripts/qa/native_build_provenance.rb'}
runtime_drift={n:d for n,d in checkout_drift.items() if n.startswith(runtime_roots) or n in runtime_files}
report.update({'application_and_native_input_checkout_drift':runtime_drift,'application_and_native_inputs_current':not runtime_drift,'other_declared_input_drift':{n:d for n,d in checkout_drift.items() if n not in runtime_drift},'currentness_scope':'All drift is retained. SQL/QA/test scripts are separate from application/native/build-caller inputs; no whole-repository currentness claim.'})
generated_spec=importlib.util.spec_from_file_location('actual_generated_artifact_inputs',P/'swift_generated_plugin_inputs.py');generated_module=importlib.util.module_from_spec(generated_spec);generated_spec.loader.exec_module(generated_module)
generated_binding=json.loads((P/'generated-compiler-inputs-before.json').read_text());generated_check=generated_module.verify(generated_binding,EXPORT);assert generated_check['status']=='pass'
report.update({'actual_generated_compiler_inputs_unchanged':True,'generated_compiler_binding_sha256':sha(P/'generated-compiler-inputs-before.json'),'swift_prelaunch_binding_sha256':sha(ROOT/'docs/release/asset-build-hygiene-2026-09-30/swift-package-source-observation-attempt131/pre_build.json'),'swift_after_build_binding_sha256':sha(ROOT/'docs/release/asset-build-hygiene-2026-09-30/swift-package-source-observation-attempt131/after_build.json')})
binary_spec=importlib.util.spec_from_file_location('actual_binary_artifact_inputs',P/'swift_cached_artifact_inputs.py');binary_module=importlib.util.module_from_spec(binary_spec);binary_spec.loader.exec_module(binary_module)
binary_binding=json.loads((P/'cached-binary-inputs-before.json').read_text());binary_check=binary_module.verify(binary_binding);assert binary_check['status']=='pass'
(P/'cached-binary-inputs-artifact-verification.json').write_text(json.dumps(binary_check,indent=2,sort_keys=True)+'\n')
report.update({'actual_cached_binary_inputs_unchanged':True,'cached_binary_binding_sha256':sha(P/'cached-binary-inputs-before.json'),'cached_binary_verification_sha256':sha(P/'cached-binary-inputs-artifact-verification.json')})
report.update({'postbuild_control_binding_sha256':sha(P/'postbuild-control-binding.json'),'actual_compilation_reused_without_input_changes':True,'original_failed_postbuild_verifier_retained':True,'corrected_verifier_source_sha256':sha(P/'swift_cached_artifact_inputs.py')})
(P/'artifact-verification.json').write_text(json.dumps(report,indent=2)+'\n');(APP.parent/'collect-local-unsigned-ios-qa.json').write_text(json.dumps({'marker':report['marker'],'artifact_verification_sha256':sha(P/'artifact-verification.json'),'bundle_manifest_sha256':report['bundle_manifest_sha256'],'source_export_sha256':sha(P/'source-export.json')},indent=2)+'\n');print(json.dumps({k:report[k] for k in ['status','bundle_file_count','bundle_regular_file_bytes','main_executable_sha256','declared_exported_sources_unchanged']}))
