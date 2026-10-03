import hashlib,json,os,shutil,subprocess,time,xml.etree.ElementTree as ET,zipfile
from pathlib import Path
R=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');E=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt126-gateway')
C=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-essential-source-candidate-20261001')
P=R/'docs/release/asset-build-hygiene-2026-09-30/gateway-final-native-candidate-attempt176'
A175=R/'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt175'
J=Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home');SDK=R/'.cache/flutter-sdk-isolated-asset-attempt136';A=Path('/Users/jeanbosco/Library/Android/sdk/build-tools/37.0.0')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
inputs=json.loads((P/'final-flat-native-inputs.json').read_text());assert all(sha(E/n)==h for n,h in inputs.items())
# Only native security sources changed. Explicitly reuse the accepted unchanged
# Flutter outputs instead of running Flutter/pub on this final native continuation.
flutter={str(p.relative_to(E)):sha(p) for p in (E/'build/app/intermediates/flutter').rglob('*') if p.is_file()}
assert flutter and any(n.endswith('app.so') for n in flutter) and any('flutter_assets' in n for n in flutter)
(P/'reused-flutter-output-inputs.json').write_text(json.dumps(flutter,indent=2,sort_keys=True)+'\n')
init=P/'json-runtime-proof.init.gradle';init.write_text((A175/'json-runtime-proof.init.gradle').read_text().replace(str(A175),str(P)))
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update({'CI':'true','JAVA_HOME':str(J),'FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(R/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']})
commands=[]
def run(name,args,cwd=E/'android',expected=0):
 print('START',name,flush=True);s=time.monotonic()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:q=subprocess.run(args,cwd=cwd,env=env,stdout=out,stderr=err)
 entry={'name':name,'argv':[str(x) for x in args],'exit_code':q.returncode,'elapsed_seconds':round(time.monotonic()-s,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))};commands.append(entry)
 (P/'execution.json').write_text(json.dumps({'status':'running' if q.returncode==expected else 'fail','commands':commands},indent=2)+'\n');print('END',name,q.returncode,flush=True)
 if q.returncode!=expected:raise SystemExit(1)
run('final-native-security',['./gradlew','-I',str(init),':app:assembleInternal_gatewayRelease',':app:lintInternal_gatewayRelease',':app:testInternal_gatewayDebugUnitTest','--tests','app.cool.mobile.gateway.GatewaySafetyTest','--tests','app.cool.mobile.gateway.GatewayDispatchArmTest','-x',':app:compileFlutterBuildInternal_gatewayRelease','-x',':app:compileFlutterBuildInternal_gatewayDebug','-Ptarget=lib/main_gateway.dart','-PcollectUnsignedLocalQa=true','--offline','--no-daemon'])
run('existing-dispatch-archive-harness',['python3',str(E/'scripts/tests/android_gateway_dispatch_jvm.py'),'--packet',str(P/'standalone-dispatch-archive')],E)
harness=json.loads((P/'standalone-dispatch-archive/validation.json').read_text());assert harness['status']=='pass'
for n,h in harness['source_sha256'].items():
 if n.startswith('android/'):assert sha(E/n)==h and sha(C/n)==h,n
files=list((E/'build/app/test-results/testInternal_gatewayDebugUnitTest').glob('TEST-*.xml'));counts={k:0 for k in ['tests','failures','errors','skipped']};suites=[]
(P/'jvm-test-results').mkdir()
for f in files:
 x=ET.parse(f).getroot();suites.append(x.get('name'));assert x.get('name') in {'app.cool.mobile.gateway.GatewaySafetyTest','app.cool.mobile.gateway.GatewayDispatchArmTest'}
 for k in counts:counts[k]+=int(x.get(k))
 shutil.copy2(f,P/'jvm-test-results'/f.name)
assert counts['tests']>0 and counts['failures']==counts['errors']==counts['skipped']==0
(P/'jvm-tests.json').write_text(json.dumps({'counts':counts,'suites':suites},indent=2)+'\n')
lint=E/'build/app/reports/lint-results-internal_gatewayRelease.xml';issues=[dict(x.attrib) for x in ET.parse(lint).getroot().findall('issue')];assert not any(x['severity'] in ['Error','Fatal'] or x['id']=='NotificationPermission' for x in issues);shutil.copy2(lint,P/lint.name)
(P/'lint-warnings.json').write_text(json.dumps(issues,indent=2)+'\n')
apk=E/'build/app/outputs/apk/internal_gateway/release/app-internal_gateway-release-unsigned.apk'
with zipfile.ZipFile(apk) as z:
 assert z.testzip() is None and not any('aeonik' in n.lower() for n in z.namelist())
 fm=z.read('assets/flutter_assets/FontManifest.json');assert b'Inter' in fm and b'Aeonik' not in fm
 inter=z.read('assets/flutter_assets/assets/typefaces/Inter-Variable.ttf');assert hashlib.sha256(inter).hexdigest()==sha(E/'assets/typefaces/Inter-Variable.ttf')
 marker=json.loads(z.read('assets/collect-local-unsigned-qa.json'));assert marker['signing'] is False
 dex=[n for n in z.namelist() if n.endswith('.dex')];assert dex
 assert all(all(v not in z.read(n) for v in [b'FlutterLocalNotificationsPlugin',b'FlutterFirebaseMessagingPlugin',b'com/dexterous/flutterlocalnotifications/',b'com/google/firebase/messaging/']) for n in dex)
run('final-apk-manifest',[A/'aapt2','dump','badging',apk],E)
b=(P/'final-apk-manifest.stdout').read_text();assert "name='app.cool.mobile.gateway'" in b and 'GatewayActivity' in b and 'android.permission.POST_NOTIFICATIONS' not in b
run('final-apk-unsigned',[A/'apksigner','verify','--verbose',apk],E,expected=1)
sig=(P/'final-apk-unsigned.stdout').read_text()+(P/'final-apk-unsigned.stderr').read_text();assert 'DOES NOT VERIFY' in sig and 'Missing META-INF/MANIFEST.MF' in sig
assert all(sha(E/n)==h for n,h in inputs.items()),'Frozen final native source changed'
for n,h in inputs.items():
 if n!='android/app/build.gradle.kts':assert sha(C/n)==h,n
assert all(sha(E/n)==h for n,h in flutter.items()),'Reused Flutter output changed'
assert 'compileFlutterBuildInternal_gateway' not in '\n'.join(line for line in (P/'final-native-security.stdout').read_text().splitlines() if line.startswith('> Task '))
flat={n:sha(E/n) for n in inputs};(P/'final-flat-native-inputs-after.json').write_text(json.dumps(flat,indent=2,sort_keys=True)+'\n')
saved=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/artifacts-final-gateway-attempt176');saved.mkdir(exist_ok=False);shutil.copy2(apk,saved/apk.name);assert sha(saved/apk.name)==sha(apk)
report={'status':'pass','final_flat_native_inputs':str(P/'final-flat-native-inputs-after.json'),'all_80_candidate_android_inputs_match_except_owned_gradle':True,'owned_gradle_sha256':sha(E/'android/app/build.gradle.kts'),'standalone_harness_sha256':sha(P/'standalone-dispatch-archive/validation.json'),'actual_gateway_jvm_counts':counts,'lint_errors':0,'lint_warnings':sum(x['severity']=='Warning' for x in issues),'unchanged_flutter_outputs_reused_no_flutter_pub_graph_rerun':True,'apk':{'path':str(saved/apk.name),'sha256':sha(apk),'bytes':apk.stat().st_size,'unsigned_verified':True,'post_notifications_absent':True,'aeonik_absent':True,'inter_sha256':hashlib.sha256(inter).hexdigest(),'qa_marker':marker},'previous175_exact48_and174_50_controls_remain_separate':True,'scope':'Final captured stronger native candidate plus owned marker/notification/testJSON Gradle adapter: incremental Gateway APK/lint, affected safety/arm JVM and existing standalone realJSON/SIM/fresh-clock/V2/AndroidAPI harness. No shared-runtime edit, unrelated peer overlay, production/iOS/device/provider/signing/store or whole-live-repository claim.'}
(P/'verification.json').write_text(json.dumps(report,indent=2)+'\n');(P/'execution.json').write_text(json.dumps({'status':'pass','commands':commands,'verification_sha256':sha(P/'verification.json')},indent=2)+'\n');print('FINAL NATIVE CANDIDATE PASS',counts['tests'],flush=True)
