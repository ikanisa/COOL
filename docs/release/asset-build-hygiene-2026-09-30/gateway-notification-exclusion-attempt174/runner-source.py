import hashlib,importlib.util,json,os,shutil,subprocess,time,xml.etree.ElementTree as ET
from pathlib import Path
R=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
E=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt126-gateway')
P=R/'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt174'
PRIOR=R/'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt173'
SDK=R/'.cache/flutter-sdk-isolated-asset-attempt136'
JDK=Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
prior=json.loads((PRIOR/'release-scoped-readback.json').read_text());assert prior['status']=='partial_pass' and prior['gateway_release_lint_pass']
(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
saved=(P/'before-marker-order.gradle.kts').read_text()
old='''    tasks.matching {
        it.name == "preProductionReleaseBuild" || it.name == "preInternal_gatewayReleaseBuild"
    }.configureEach { dependsOn(marker) }'''
new='''    val markerPreBuildNames = listOf("Production", "Internal_gateway").flatMap { flavor ->
        android.buildTypes.map { type ->
            "pre${flavor}${type.name.replaceFirstChar { it.uppercase() }}Build"
        }
    }.toSet()
    tasks.matching { it.name in markerPreBuildNames }.configureEach { dependsOn(marker) }'''
assert saved.count(old)==1
current=R/'android/app/build.gradle.kts';assert current.read_text()==saved.replace(old,new)
target=E/'android/app/build.gradle.kts';assert target.read_bytes()==(P/'before-marker-order.gradle.kts').read_bytes()
(P/'preserved-export-before-marker-order.gradle.kts').write_bytes(target.read_bytes())
shutil.copy2(current,target);source_sha=sha(current);assert sha(target)==source_sha
(P/'marker-order-source-delta.json').write_text(json.dumps({'previous_sha256':hashlib.sha256(saved.encode()).hexdigest(),'current_sha256':source_sha,'only_source_delta':'Inside collectUnsignedLocalQa, marker preBuild dependency now covers each existing production/Gateway build type; previously only Release. Marker payload/directory, release dependency, plugin relocation, generated registrants, permissions and default signing remain byte-identical.','previous_release_dependency_retained':True,'production_and_gateway_build_types':['debug','profile','release']},indent=2)+'\n')
root_inputs=json.loads((PRIOR/'frozen-root-inputs.json').read_text());root_inputs['android/app/build.gradle.kts']=source_sha
assert all(sha(E/n)==h for n,h in root_inputs.items()),'Export input changed before JVM continuation'
(P/'frozen-173-source-plus-marker-delta.json').write_text(json.dumps(root_inputs,indent=2,sort_keys=True)+'\n')
spec=importlib.util.spec_from_file_location('scope174',E/'scripts/qa/native_source_export.py');scope=importlib.util.module_from_spec(spec);spec.loader.exec_module(scope)
def map_inputs():
 names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=E).decode().split(chr(0))
 return {n:sha(E/n) for n in sorted(set(names)) if n and scope.selected(n) and (E/n).is_file() and not (E/n).is_symlink()}
before=map_inputs();(P/'all-selected-export-inputs-before.json').write_text(json.dumps(before,indent=2,sort_keys=True)+'\n')
apk=E/'build/app/outputs/apk/internal_gateway/release/app-internal_gateway-release-unsigned.apk';assert sha(apk)==prior['apk']['sha256']
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update({'CI':'true','JAVA_HOME':str(JDK),'FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(R/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']})
args=['./gradlew',':app:testInternal_gatewayDebugUnitTest','-Ptarget=lib/main_gateway.dart','-PcollectUnsignedLocalQa=true','--offline','--no-daemon']
print('START Debug JVM continuation',flush=True);start=time.monotonic()
with (P/'gateway-debug-jvm.stdout').open('wb') as out,(P/'gateway-debug-jvm.stderr').open('wb') as err:
 code=subprocess.run(args,cwd=E/'android',env=env,stdout=out,stderr=err).returncode
execution={'status':'pass' if code==0 else 'fail','argv':args,'exit_code':code,'elapsed_seconds':round(time.monotonic()-start,2),'stdout_sha256':sha(P/'gateway-debug-jvm.stdout'),'stderr_sha256':sha(P/'gateway-debug-jvm.stderr')}
(P/'execution.json').write_text(json.dumps(execution,indent=2)+'\n');print('END Debug JVM',code,flush=True)
if code!=0:raise SystemExit(1)
files=list((E/'build/app/test-results/testInternal_gatewayDebugUnitTest').glob('TEST-*.xml'))
results=[{k:ET.parse(f).getroot().get(k) for k in ['name','tests','failures','errors','skipped']} for f in files]
assert files and all(x['failures']==x['errors']==x['skipped']=='0' for x in results)
(P/'jvm-test-results').mkdir()
for f in files:shutil.copy2(f,P/'jvm-test-results'/f.name)
(P/'jvm-tests.json').write_text(json.dumps(results,indent=2)+'\n')
assert map_inputs()==before,'Export selected source added, removed or changed'
assert sha(current)==source_sha,'Owned Gradle source changed'
assert sha(apk)==prior['apk']['sha256'],'Passed Release APK changed during Debug-only continuation'
original=E/'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java';assert sha(original)=='52d3ce636d308a5e39c95bb917407a46d6bad42c9f95a3073a44a0155f683bcd'
debug=E/'build/app/generated/collectPluginRegistrants/internal_gatewayDebug/io/flutter/plugins/GeneratedPluginRegistrant.java'
assert all(v not in debug.read_text() for v in ['FlutterLocalNotificationsPlugin','FlutterFirebaseMessagingPlugin']) and 'FlutterFirebaseCorePlugin' in debug.read_text()
root_drift={n:{'frozen':h,'current':sha(R/n) if (R/n).is_file() else None} for n,h in root_inputs.items() if not (R/n).is_file() or sha(R/n)!=h}
(P/'live-root-drift-after.json').write_text(json.dumps(root_drift,indent=2)+'\n')
assert not any(n.startswith(('lib/','assets/','android/','third_party/')) or n in {'pubspec.yaml','pubspec.lock'} for n in root_drift),'Compiled runtime input drift'
report={'status':'pass','source_delta_sha256':sha(P/'marker-order-source-delta.json'),'release173_scoped_acceptance_sha256':sha(PRIOR/'release-scoped-readback.json'),'release173_apk_unchanged':True,'apk':prior['apk'],'jvm_cases':sum(int(x['tests']) for x in results),'jvm_failures_errors_skips':0,'debug_registrant_omits_both_notifications_and_retains_firebase_core':True,'original_tool_registrant_unchanged':True,'all_selected_export_inputs_unchanged':True,'live_root_drift':root_drift,'scope':'Complete E3 from passed173 Gateway Release assemble/lint/dependency/registrant/Inter/unsigned APK plus this Debug JVM continuation with exact QA-marker ordering-only Gradle delta. No repeated release build/lint/graphs, production/iOS, full whole-repository semantic, provider, physical-device, signing or store claim.'}
(P/'verification.json').write_text(json.dumps(report,indent=2)+'\n');print('E3 PASS JVM',report['jvm_cases'],flush=True)
