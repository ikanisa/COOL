import hashlib,json,os,plistlib,subprocess
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt28-ios';EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt28-ios');APP=EXPORT/'build/ios/DerivedData/Build/Products/Release-production-iphoneos/Collect.app'
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
source=json.loads((P/'source-export.json').read_text())['source_sha256'];changes={n:{'before_sha256':h,'after_sha256':sha(EXPORT/n) if (EXPORT/n).is_file() else None} for n,h in source.items() if not (EXPORT/n).is_file() or sha(EXPORT/n)!=h}
assert not changes,'Build changed a declared exported source'
original_binds=['.dart_tool/package_config.json','.flutter-plugins-dependencies','ios/Flutter/Generated.xcconfig','ios/Flutter/flutter_export_environment.sh','ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift','ios/Pods/Manifest.lock']
generated={n:sha(EXPORT/n) for n in original_binds if (EXPORT/n).is_file()};assert '.dart_tool/package_config.json' in generated and 'ios/Flutter/Generated.xcconfig' in generated
(P/'generated-bindings.json').write_text(json.dumps({'scope':'Generated public package/plugin and pinned local toolchain bindings; no ignored private source copied','sha256':generated},indent=2)+'\n')
checkout_drift={n:{'before_sha256':h,'after_sha256':sha(ROOT/n) if (ROOT/n).is_file() else None} for n,h in source.items() if not (ROOT/n).is_file() or sha(ROOT/n)!=h}
report={'original_checkout_drift':checkout_drift,'current_checkout_acceptance':not checkout_drift,'build_execution_sha256':sha(P/'execution.json'),'status':'pass','kind':'local_unsigned_ios_qa_artifact','bundle':str(APP),'bundle_file_count':len(files),'bundle_regular_file_bytes':sum(x['bytes'] for x in files.values()),'bundle_manifest_sha256':sha(P/'bundle-manifest.json'),'main_executable_sha256':sha(APP/info['CFBundleExecutable']),'bundle_identifier':info['CFBundleIdentifier'],'version':'1.2.4+23','sdk':info['DTSDKName'],'compiled_platform':'iOS device arm64, generic destination','root_bundle_unsigned_verified':True,'embedded_provisioning_profile_absent':True,'declared_exported_sources_unchanged':True,'source_file_count':len(source),'commands':commands,'marker':{'kind':'local_unsigned_native_qa','signing':False,'store_acceptance':False,'provider_configuration':False},'scope':'Actual retained source export including all three forks, complete compilation and unsigned artifact inspection; no device/simulator, native visual, signed store, provider or current whole-runtime acceptance'}
(P/'artifact-verification.json').write_text(json.dumps(report,indent=2)+'\n');(APP.parent/'collect-local-unsigned-ios-qa.json').write_text(json.dumps({'marker':report['marker'],'artifact_verification_sha256':sha(P/'artifact-verification.json'),'bundle_manifest_sha256':report['bundle_manifest_sha256'],'source_export_sha256':sha(P/'source-export.json')},indent=2)+'\n');print(json.dumps({k:report[k] for k in ['status','bundle_file_count','bundle_regular_file_bytes','main_executable_sha256','declared_exported_sources_unchanged']}))
