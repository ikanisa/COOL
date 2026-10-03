import hashlib,importlib.util,json,os,re,shutil,subprocess,time,zipfile,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt126-gateway')
P=ROOT/'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt169'
PARENT=ROOT/'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt126-gateway'
SDK=ROOT/'.cache/flutter-sdk-isolated-asset-attempt136'
JDK=Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home')
ANDROID=Path('/Users/jeanbosco/Library/Android/sdk')
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
assert json.loads((P/'pure-adapter-validation.json').read_text())['status']=='pass'
assert json.loads((PARENT/'execution.json').read_text())['status']=='fail'
(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
manifest=json.loads((PARENT/'source-export.json').read_text())
parent_inputs=manifest['clone_inputs_sha256']
prior={n:sha(EXPORT/n) if (EXPORT/n).is_file() else None for n in parent_inputs}
(P/'actual-export-before.json').write_text(json.dumps(prior,indent=2,sort_keys=True)+'\n')
(P/'parent-export-drift-before.json').write_text(json.dumps({n:{'parent':h,'actual_before':prior[n]} for n,h in parent_inputs.items() if h!=prior[n]},indent=2)+'\n')
(P/'parent-execution-before.json').write_bytes((PARENT/'execution.json').read_bytes())
owned=['android/app/build.gradle.kts','android/gradle/CollectPluginRegistrant.java','scripts/qa/gateway_notification_dependencies.init.gradle']
owned_hashes={n:sha(ROOT/n) for n in owned}
(P/'owned-source-before.json').write_text(json.dumps(owned_hashes,indent=2)+'\n')
(P/'preserved-export-source').mkdir(exist_ok=False)
for n,h in owned_hashes.items():
 origin=ROOT/n;target=EXPORT/n
 if target.exists():
  saved=P/'preserved-export-source'/n;saved.parent.mkdir(parents=True,exist_ok=True);saved.write_bytes(target.read_bytes())
 target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(origin,target)
 assert sha(target)==h and sha(origin)==h,n
source={**{n:h for n,h in prior.items() if h is not None},**owned_hashes}
original_registrant=EXPORT/'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
registrant_before=sha(original_registrant)
commands=[]
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update({'CI':'true','JAVA_HOME':str(JDK),'FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(ROOT/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']})
def run(name,argv,cwd=EXPORT/'android',expected=0):
 print('START',name,flush=True);start=time.monotonic()
 with (P/(name+'.stdout')).open('wb') as out,(P/(name+'.stderr')).open('wb') as err:
  code=subprocess.run(argv,cwd=cwd,env=env,stdout=out,stderr=err).returncode
 commands.append({'name':name,'argv':argv,'exit_code':code,'elapsed_seconds':round(time.monotonic()-start,2),'stdout_sha256':sha(P/(name+'.stdout')),'stderr_sha256':sha(P/(name+'.stderr'))})
 (P/'execution.json').write_text(json.dumps({'status':'running' if code==expected else 'fail','commands':commands},indent=2)+'\n')
 print('END',name,code,flush=True)
 if code!=expected:raise SystemExit(code if code>0 else 1)
run('gateway-native-sequence',['./gradlew','-I',str(EXPORT/'scripts/qa/gateway_notification_dependencies.init.gradle'),':app:assembleInternal_gatewayRelease',':app:lintInternal_gatewayRelease',':app:testInternal_gatewayDebugUnitTest',':app:generateCollectProductionReleasePluginRegistrant',':app:verifyCollectGatewayNotificationDependencies','-Ptarget=lib/main_gateway.dart','-PcollectUnsignedLocalQa=true','--offline','--no-daemon'])
assert sha(original_registrant)==registrant_before,'Tool-generated original changed'
normal=EXPORT/'build/app/generated/collectPluginRegistrants/productionRelease/io/flutter/plugins/GeneratedPluginRegistrant.java'
gateway=EXPORT/'build/app/generated/collectPluginRegistrants/internal_gatewayRelease/io/flutter/plugins/GeneratedPluginRegistrant.java'
assert normal.read_bytes()==original_registrant.read_bytes(),'NonGateway generated registration differs'
assert b'flutter_local_notifications' not in gateway.read_bytes() and b'FlutterLocalNotificationsPlugin' not in gateway.read_bytes()
assert b'SharePlusPlugin' in gateway.read_bytes() and b'FlutterFirebaseCorePlugin' in gateway.read_bytes()
for label,path in [('non-gateway',normal),('gateway',gateway)]:shutil.copy2(path,P/(label+'-GeneratedPluginRegistrant.java'))
output=(P/'gateway-native-sequence.stdout').read_text();captures=re.findall(r'COLLECT_GATEWAY_NOTIFICATION_DEPENDENCIES_BEGIN\s*(.*?)\s*COLLECT_GATEWAY_NOTIFICATION_DEPENDENCIES_END',output,re.S);assert len(captures)==1
(P/'dependency-verification.json').write_text(json.dumps(json.loads(captures[0]),indent=2)+'\n')
classes=EXPORT/'build/app/intermediates/javac/internal_gatewayRelease/compileInternal_gatewayReleaseJavaWithJavac/classes'
assert classes.is_dir(),str(classes)
run('compiled-gateway-registrant',[str(JDK/'bin/javap'),'-classpath',str(classes),'-c','io.flutter.plugins.GeneratedPluginRegistrant'],EXPORT)
compiled=(P/'compiled-gateway-registrant.stdout').read_text();assert 'FlutterLocalNotificationsPlugin' not in compiled and 'SharePlusPlugin' in compiled
lint=EXPORT/'build/app/reports/lint-results-internal_gatewayRelease.xml';issues=[{'id':x.get('id'),'severity':x.get('severity'),'message':x.get('message'),'locations':[dict(y.attrib) for y in x.findall('location')]} for x in ET.parse(lint).getroot().findall('issue')];assert not any(x['severity'] in {'Error','Fatal'} for x in issues);assert not any(x['id']=='NotificationPermission' for x in issues);shutil.copy2(lint,P/lint.name)
(P/'lint-warning-inventory.json').write_text(json.dumps(issues,indent=2)+'\n')
testfiles=list((EXPORT/'build/app/test-results/testInternal_gatewayDebugUnitTest').glob('TEST-*.xml'));results=[{k:ET.parse(f).getroot().get(k) for k in ['name','tests','failures','errors','skipped']} for f in testfiles];assert testfiles and all(x['failures']==x['errors']==x['skipped']=='0' for x in results)
(P/'jvm-test-results').mkdir()
for f in testfiles:shutil.copy2(f,P/'jvm-test-results'/f.name)
(P/'jvm-tests.json').write_text(json.dumps(results,indent=2)+'\n')
apk=EXPORT/'build/app/outputs/apk/internal_gateway/release/app-internal_gateway-release-unsigned.apk';assert apk.is_file()
with zipfile.ZipFile(apk) as z:
 assert z.testzip() is None
 marker=json.loads(z.read('assets/collect-local-unsigned-qa.json'));assert marker['signing'] is False
 dex=[n for n in z.namelist() if n.endswith('.dex')];assert dex
 for n in dex:
  data=z.read(n);assert b'com/dexterous/flutterlocalnotifications/' not in data and b'FlutterLocalNotificationsPlugin' not in data and b'flutter_local_notifications' not in data
run('gateway-manifest',[str(ANDROID/'build-tools/37.0.0/aapt2'),'dump','badging',str(apk)],EXPORT)
badging=(P/'gateway-manifest.stdout').read_text();assert "name='app.cool.mobile.gateway'" in badging and 'GatewayActivity' in badging
assert 'android.permission.POST_NOTIFICATIONS' not in badging
for name in ['SEND_SMS','READ_PHONE_STATE','ACCESS_NETWORK_STATE']:assert 'android.permission.'+name in badging
run('gateway-unsigned-verification',[str(ANDROID/'build-tools/37.0.0/apksigner'),'verify','--verbose',str(apk)],EXPORT,expected=1)
sig=(P/'gateway-unsigned-verification.stdout').read_text()+(P/'gateway-unsigned-verification.stderr').read_text();assert 'DOES NOT VERIFY' in sig and 'Missing META-INF/MANIFEST.MF' in sig
for n,h in source.items():assert (EXPORT/n).is_file() and sha(EXPORT/n)==h,'Export source drift: '+n
assert all(sha(ROOT/n)==h for n,h in owned_hashes.items()),'Owned original source drift'
helper=PARENT/'resolved_native_package_inputs.py';spec=importlib.util.spec_from_file_location('e3_bound_native_packages',helper);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
packages=module.verify(json.loads((PARENT/'resolved-package-inputs-before.json').read_text()),EXPORT);assert packages['status']=='pass'
(P/'resolved-package-inputs-after.json').write_text(json.dumps(packages,indent=2)+'\n')
report={'status':'pass','commands':commands,'owned_source_sha256':owned_hashes,'parent_execution_sha256':sha(P/'parent-execution-before.json'),'prior_actual_export_sha256':sha(P/'actual-export-before.json'),'all_actual_export_inputs_unchanged_except_declared_owned_adapter':True,'original_tool_generated_registrant_sha256':registrant_before,'non_gateway_generated_registrant_byte_identical':True,'gateway_native_plugin_absent_from_both_dependency_graphs_and_compiled_registrant':True,'gateway_notification_dex_package_absent':True,'post_notifications_permission_absent':True,'lint_errors':0,'lint_warnings':len(issues),'jvm_cases':sum(int(x['tests']) for x in results),'jvm_failures_errors_skips':0,'apk_sha256':sha(apk),'apk_bytes':apk.stat().st_size,'apk_unsigned_verified':True,'scope':'Narrow E3 repository adapter and retained-cache Gateway build/lint/JVM/dependency/registrant/APK acceptance. Other cached application source and prior drift are explicit; no current whole-source, production/iOS/device/signing/store/provider or complete warning/SBOM claim.'}
(P/'verification.json').write_text(json.dumps(report,indent=2)+'\n');(P/'execution.json').write_text(json.dumps({'status':'pass','commands':commands,'verification_sha256':sha(P/'verification.json')},indent=2)+'\n');print('E3 GATEWAY PASS',report['jvm_cases'],flush=True)
