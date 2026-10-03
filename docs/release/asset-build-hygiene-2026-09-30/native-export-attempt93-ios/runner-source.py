import hashlib,json,os,subprocess,time,shutil
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PACKET=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt93-ios'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt93-ios')
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt28'
FLUTTER=str(SDK/'bin/flutter')
ENV={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
ENV.update({'CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','DEVELOPER_DIR':'/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'COCOAPODS_DISABLE_STATS':'true','CP_HOME_DIR':str(EXPORT.parent/'cocoapods-attempt93-home'),'CP_CACHE_DIR':str(EXPORT.parent/'cocoapods-attempt93-cache'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+ENV['PATH']})
PACKET.mkdir(parents=True,exist_ok=False)
runner=Path(__file__).read_bytes();(PACKET/'runner-source.py').write_bytes(runner)
(PACKET/'environment-scope.json').write_text(json.dumps({'inherited_environment_names':sorted(k for k in os.environ if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}),'private_provider_signing_environment_supplied':False,'pinned_flutter':FLUTTER,'xcode_path':ENV['DEVELOPER_DIR'],'pub_cache':ENV['PUB_CACHE'],'cocoapods_home':ENV['CP_HOME_DIR'],'cocoapods_cache':ENV['CP_CACHE_DIR'],'runner_sha256':hashlib.sha256(runner).hexdigest()},indent=2)+'\n')
commands=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(name,argv,cwd=EXPORT,expected=0):
 print('START',name,flush=True);start=time.time()
 with (PACKET/(name+'.stdout')).open('wb') as out,(PACKET/(name+'.stderr')).open('wb') as err:
  code=subprocess.run(argv,cwd=cwd,env=ENV,stdout=out,stderr=err).returncode
 rec={'name':name,'command':argv,'exit_code':code,'elapsed_seconds':round(time.time()-start,2),'stdout_sha256':sha(PACKET/(name+'.stdout')),'stderr_sha256':sha(PACKET/(name+'.stderr'))};commands.append(rec)
 (PACKET/'execution.json').write_text(json.dumps({'status':'running' if code==expected else 'failed','commands':commands,'scope':'Isolated source-only unsigned iOS QA compilation; no credentials, signed store/provider/device acceptance'},indent=2)+'\n')
 print('END',name,code,flush=True)
 if code!=expected:raise SystemExit(code if code>0 else 1)
BASE=ROOT/'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt83'
BOUND=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt83')
prior=json.loads((BASE/'execution.json').read_text());assert prior['status']=='pass','Bound source tooling must pass before native clone'
assert all(any(c['name']==name and c['exit_code']==0 for c in prior['commands']) for name in ['format-check','fatal-analyzer','public-copy-responsive-regressions']),'Required bound source gate is absent'
manifest=json.loads((BASE/'source-export.json').read_text());assert not EXPORT.exists()
inputs={**manifest['source_sha256'],**json.loads((BASE/'additional-public-tooling-source.json').read_text())['sha256']}
for n,h in sorted(inputs.items()):
 origin=BOUND/n;assert origin.is_file() and sha(origin)==h,'Bound source changed: '+n
 target=EXPORT/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(origin,target);assert sha(target)==h
clone={**manifest,'destination':str(EXPORT),'kind':'independent_clone_of_one_bound_application_source','parent_source_export_sha256':sha(BASE/'source-export.json'),'parent_source_export':str(BASE/'source-export.json'),'clone_inputs_sha256':inputs}
(PACKET/'source-export.json').write_text(json.dumps(clone,indent=2,sort_keys=True)+'\n')
run('export-git-init',['git','init','-q'])
run('flutter-version',[FLUTTER,'--version','--machine'])
version=json.loads((PACKET/'flutter-version.stdout').read_text());assert version['frameworkVersion']=='3.44.4' and version['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06' and version['dartSdkVersion']=='3.12.2'
run('xcode-version',['xcrun','xcodebuild','-version'])
run('pub-enforce',[FLUTTER,'pub','get','--offline','--enforce-lockfile'])
# Additional native compiler/package source binding has its own accepted pure proof.
import importlib.util
PACKAGE_TOOL = 'scripts/qa/resolved_native_package_inputs.py'
package_proof_path = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/resolved-native-inputs-attempt90/validation.json'
package_proof = json.loads(package_proof_path.read_text())
assert package_proof['status'] == 'pass' and sha(ROOT / PACKAGE_TOOL) == package_proof['source_sha256'][PACKAGE_TOOL]
shutil.copy2(ROOT / PACKAGE_TOOL, PACKET / 'resolved_native_package_inputs.py')
package_spec = importlib.util.spec_from_file_location('native_package_inputs', PACKET / 'resolved_native_package_inputs.py')
package_module = importlib.util.module_from_spec(package_spec); package_spec.loader.exec_module(package_module)
package_binding = package_module.bind(EXPORT, SDK, ROOT / '.cache/pub-cache-hygiene-20260930')
(PACKET / 'resolved-package-inputs-before.json').write_text(json.dumps(package_binding, indent=2, sort_keys=True) + '\n')
(PACKET / 'resolved-package-tool-binding.json').write_text(json.dumps({'tool_sha256': sha(PACKET / 'resolved_native_package_inputs.py'), 'accepted_test_packet_sha256': sha(package_proof_path), 'scope': 'Actual additional helper source, accepted13 pure regressions and immutable native package bindings; no application source change'}, indent=2) + '\n')
print('RESOLVED PACKAGE INPUTS BOUND', len(package_binding['packages']), sum(len(row['files']) for row in package_binding['packages'].values()), flush=True)
run('unsigned-ios-config',[FLUTTER,'build','ios','--release','--flavor','production','--no-codesign','--no-pub','--config-only'])
source=json.loads((PACKET/'source-export.json').read_text())['source_sha256']
lock_names=['pubspec.lock','ios/Podfile.lock','ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved','ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']
locks={n:{'before_sha256':source[n],'after_sha256':sha(EXPORT/n)} for n in lock_names}
(PACKET/'configuration-lock-comparison.json').write_text(json.dumps(locks,indent=2)+'\n')
assert all(d['before_sha256']==d['after_sha256'] for d in locks.values()),'Configuration changed an approved lock'
cache=EXPORT/'build/ios/SourcePackages';cache.parent.mkdir(parents=True,exist_ok=True)
run('copy-pinned-source-packages',['cp','-cR','/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt18-ios/build/ios/SourcePackages',str(cache)])
pins=json.loads((EXPORT/'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins'];observed={}
for pin in pins:
 checkout=cache/'checkouts'/pin['identity'];actual=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],env=ENV,text=True).strip();assert actual==pin['state']['revision'],pin['identity'];observed[pin['identity']]={'revision':actual,'version':pin['state'].get('version')}
(PACKET/'swift-package-cache-verification.json').write_text(json.dumps({'scope':'Local cached checkouts compared with exact lock revisions before actual Xcode build; no provider data or new version resolution','checkouts':observed},indent=2)+'\n')
run('unsigned-ios-build',['xcrun','xcodebuild','-workspace','ios/Runner.xcworkspace','-scheme','production','-configuration','Release-production','-sdk','iphoneos','-destination','generic/platform=iOS','-derivedDataPath',str(EXPORT/'build/ios/DerivedData'),'-clonedSourcePackagesDirPath',str(EXPORT/'build/ios/SourcePackages'),'-onlyUsePackageVersionsFromResolvedFile','-disableAutomaticPackageResolution','-skipPackageUpdates','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGNING_IDENTITY=','DEVELOPMENT_TEAM=','build'])
package_check = package_module.verify(package_binding, EXPORT)
(PACKET / 'resolved-package-inputs-after.json').write_text(json.dumps(package_check, indent=2, sort_keys=True) + '\n')
assert package_check['status'] == 'pass', 'Actual resolved compiler/plugin package input drift'
(PACKET/'execution.json').write_text(json.dumps({'status':'pass','commands':commands,'scope':'Isolated source-only unsigned iOS QA compilation; no credentials, signed store/provider/device acceptance'},indent=2)+'\n')
print('IOS BUILD PASS',flush=True)
