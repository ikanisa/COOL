import hashlib,json,os,subprocess,time,zipfile,xml.etree.ElementTree as ET,shutil
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE=ROOT/'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt23'
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt28-android-remaining'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt23')
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt23';ANDROID=Path('/Users/jeanbosco/Library/Android/sdk')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
prior=json.loads((BASE/'execution.json').read_text());assert any(c['name']=='format-check' and c['exit_code']==0 for c in prior['commands']),'Formatter must pass before native compilation'
source=json.loads((BASE/'source-export.json').read_text())['source_sha256'];assert all(sha(EXPORT/n)==h for n,h in source.items())
P.mkdir(parents=True,exist_ok=False);(P/'runner-source.py').write_bytes(Path(__file__).read_bytes());shutil.copy2(BASE/'source-export.json',P/'source-export.json')
ENV={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
ENV.update({'JAVA_HOME':'/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home','CI':'true','FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+ENV['PATH']})
(EXPORT/'android/local.properties').write_text('sdk.dir='+str(ANDROID)+'\nflutter.sdk='+str(SDK)+'\nflutter.buildMode=release\nflutter.versionName=1.2.4\nflutter.versionCode=23\n')
(P/'generated-inputs.json').write_text(json.dumps({'android/local.properties':sha(EXPORT/'android/local.properties'),'source_export_sha256':sha(P/'source-export.json'),'tooling_acceptance_sha256':sha(BASE/'execution.json'),'scope':'Public pinned local SDK configuration derived in isolated export; no private signing/provider files'},indent=2)+'\n')
commands=[]
def write(status,extra=None):
 (P/'execution.json').write_text(json.dumps({'status':status,'commands':commands,'scope':'Actual immutable source export unsigned local Android production-flavour build; no provider, signing, device or store acceptance',**(extra or {})},indent=2)+'\n')
def run(name,args,cwd=EXPORT/'android',expected=0):
 print('START',name,flush=True);start=time.time()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:r=subprocess.run(args,cwd=cwd,env=ENV,stdout=out,stderr=err)
 row={'name':name,'command':args,'exit_code':r.returncode,'elapsed_seconds':round(time.time()-start,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))};commands.append(row);write('running' if r.returncode==expected else 'fail');print('END',name,r.returncode,flush=True)
 if r.returncode!=expected:raise SystemExit(r.returncode if r.returncode>0 else 1)
run('java-version',[str(Path(ENV['JAVA_HOME'])/'bin/java'),'-version'],EXPORT)
PREVIOUS=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt26-android'
retained=json.loads((PREVIOUS/'execution.json').read_text())
completed=[c for c in retained['commands'] if c['name']=='unsigned-android-build' and c['exit_code']==0]
assert len(completed)==1
for stream in ('stdout','stderr'):
 assert sha(PREVIOUS/('unsigned-android-build.'+stream))==completed[0][stream+'_sha256']
 shutil.copy2(PREVIOUS/('unsigned-android-build.'+stream),P/('unsigned-android-build.'+stream))
commands.append({**completed[0],'retained_from':str(PREVIOUS.relative_to(ROOT)),'reexecuted':False})
(P/'continuation.json').write_text(json.dumps({'prior_runner_handle':'36026','handle_revalidation':'Unknown process id','owned_process_revalidation':'No native export runner or Gradle process live','retained_successful_build':True,'prior_lint_terminal_result_missing':True,'scope':'Resume remaining local checks only; no rebuild or inferred prior lint success'},indent=2)+'\n')
write('running')
run('production-native-lint',['./gradlew',':app:lintProductionRelease','--offline','--no-daemon'])
run('dev-native-jvm',['./gradlew',':app:testDevDebugUnitTest','--offline','--no-daemon'])
apk=EXPORT/'build/app/outputs/apk/production/release/app-production-release-unsigned.apk'
if not apk.is_file():
 candidates=list((EXPORT/'build/app/outputs').rglob('*production*release*.apk'));assert len(candidates)==1,candidates;apk=candidates[0]
with zipfile.ZipFile(apk) as z:
 assert z.testzip() is None
 marker_names=[n for n in z.namelist() if n.endswith('collect-local-unsigned-qa.json')];assert len(marker_names)==1,marker_names
 marker=json.loads(z.read(marker_names[0]));assert marker.get('kind')=='local_unsigned_native_qa' and marker.get('signing') is False and marker.get('store_acceptance') is False
build_tools=ANDROID/'build-tools/37.0.0';assert build_tools.is_dir()
run('apk-signature',[str(build_tools/'apksigner'),'verify','--verbose',str(apk)],EXPORT,expected=1)
run('apk-manifest',[str(build_tools/'aapt2'),'dump','badging',str(apk)],EXPORT)
manifest=(P/'apk-manifest.stdout').read_text();assert "name='app.cool.mobile'" in manifest and 'android.permission.WRITE_EXTERNAL_STORAGE' not in manifest and 'android.permission.READ_EXTERNAL_STORAGE' not in manifest
lint=EXPORT/'build/app/reports/lint-results-productionRelease.xml';tree=ET.parse(lint);issues=[{'id':x.get('id'),'severity':x.get('severity'),'message':x.get('message'),'locations':[dict(y.attrib) for y in x.findall('location')]} for x in tree.getroot().findall('issue')];assert not any(x['severity'] in {'Error','Fatal'} for x in issues);shutil.copy2(lint,P/lint.name)
(P/'lint-warning-inventory.json').write_text(json.dumps(issues,indent=2)+'\n')
testfiles=list((EXPORT/'build/app/test-results/testDevDebugUnitTest').glob('TEST-*.xml'));results=[{k:ET.parse(f).getroot().get(k) for k in ['name','tests','failures','errors','skipped']} for f in testfiles];assert testfiles and all(x['failures']==x['errors']==x['skipped']=='0' for x in results)
(P/'jvm-test-results').mkdir()
for f in testfiles:shutil.copy2(f,P/'jvm-test-results'/f.name)
(P/'jvm-tests.json').write_text(json.dumps(results,indent=2)+'\n')
changes={n:{'before':h,'after':sha(EXPORT/n) if (EXPORT/n).is_file() else None} for n,h in source.items() if not (EXPORT/n).is_file() or sha(EXPORT/n)!=h};assert not changes,changes
checkout_drift={n:{'before':h,'after':sha(ROOT/n) if (ROOT/n).is_file() else None} for n,h in source.items() if not (ROOT/n).is_file() or sha(ROOT/n)!=h}
artifact={'status':'pass','kind':'local_unsigned_android_qa_artifact','path':str(apk),'sha256':sha(apk),'bytes':apk.stat().st_size,'zip_integrity_verified':True,'qa_marker':marker,'actual_unsigned_rejection_verified':True,'declared_exported_sources_unchanged':True,'source_file_count':len(source),'original_checkout_drift':checkout_drift,'current_checkout_acceptance':not checkout_drift,'lint_warning_count':len(issues),'jvm_test_count':sum(int(x['tests']) for x in results),'scope':'Actual source-bound isolated build and local checks; warning dispositions, current checkout drift and physical/provider/signing/store acceptance remain separate'}
(P/'apk-verification.json').write_text(json.dumps(artifact,indent=2)+'\n');write('pass',{'artifact_verification_sha256':sha(P/'apk-verification.json')});print('ANDROID PASS',flush=True)
