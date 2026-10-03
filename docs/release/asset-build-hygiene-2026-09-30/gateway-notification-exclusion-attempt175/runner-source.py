import hashlib,json,os,shutil,subprocess,time,xml.etree.ElementTree as ET,re
from pathlib import Path
R=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
E=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt126-gateway')
P=R/'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt175'
A174=R/'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt174'
A173=R/'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt173'
JDK=Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home')
SDK=R/'.cache/flutter-sdk-isolated-asset-attempt136'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(P/'runner-source.py').write_bytes(Path(__file__).read_bytes())
old=(P/'before-json-test-runtime.gradle.kts').read_text()
needle='    testImplementation("junit:junit:4.13.2")\n'
replacement=needle+'    // Gateway JVM contracts need real JSON; Android\'s mockable API throws.\n    add("testInternal_gatewayImplementation", "org.json:json:20250517")\n'
assert old.count(needle)==1
current=R/'android/app/build.gradle.kts';assert current.read_text()==old.replace(needle,replacement)
target=E/'android/app/build.gradle.kts';assert target.read_text()==old
(P/'export-before-json.gradle.kts').write_bytes(target.read_bytes());shutil.copy2(current,target)
current_sha=sha(current);assert sha(target)==current_sha
frozen=json.loads((A173/'frozen-root-inputs.json').read_text());frozen['android/app/build.gradle.kts']=current_sha
assert all((E/n).is_file() and sha(E/n)==h for n,h in frozen.items()),'Frozen173/174 export drift; no current-source overlay permitted'
source_delta={'before_sha256':hashlib.sha256(old.encode()).hexdigest(),'after_sha256':current_sha,'coordinate':'org.json:json:20250517','configuration':'testInternal_gatewayImplementation','only_delta':'Pinned realJSON test dependency and explanation inside existing dependencies block; no runtime configuration, permission, suppression, source/test or Release build delta.'}
(P/'json-test-source-delta.json').write_text(json.dumps(source_delta,indent=2)+'\n')
failed=json.loads((A174/'jvm-failure-root-cause.json').read_text());assert len(failed)==48
selection=[(x['suite'],x['case']) for x in failed];assert len(set(selection))==48
(P/'selected-tests.json').write_text(json.dumps(selection,indent=2)+'\n')
json_input=json.loads((P/'cached-json-coordinate.json').read_text());expected_json_sha=json_input['cached_artifact_sha256']
init=P/'json-runtime-proof.init.gradle'
init.write_text('''import groovy.json.JsonOutput
import java.security.MessageDigest
import org.gradle.api.tasks.testing.Test
gradle.projectsEvaluated {
    def app = rootProject.findProject(':app')
    if (app == null) return
    app.tasks.withType(Test).configureEach {
        if (name == 'testInternal_gatewayDebugUnitTest') {
            jvmArgs('-Xlog:class+load=info:file=PACKET/jvm-class-load-%p.log')
            doFirst {
                def jsonJars = classpath.files.findAll { it.name == 'json-20250517.jar' }
                assert jsonJars.size() == 1 : 'Expected one pinned realJSON test artifact'
                def hash = MessageDigest.getInstance('SHA-256').digest(jsonJars[0].bytes).encodeHex().toString()
                assert hash == 'JSON_SHA' : 'Actual test JSON artifact differs from standalone bound runtime'
                def jsonTest = app.configurations.getByName('testInternal_gatewayImplementation').dependencies.findAll { it.group == 'org.json' && it.name == 'json' }
                assert jsonTest.size() == 1 && jsonTest[0].version == '20250517'
                def runtimeJson = app.configurations.getByName('internal_gatewayReleaseRuntimeClasspath').allDependencies.findAll { it.group == 'org.json' && it.name == 'json' }
                assert runtimeJson.empty : 'Test JSON leaked into Release runtime declarations'
                new File('PACKET/actual-json-test-classpath.json').text = JsonOutput.prettyPrint(JsonOutput.toJson([
                    task: name, coordinate: 'org.json:json:20250517', configuration: 'testInternal_gatewayImplementation',
                    artifact: jsonJars[0].absolutePath, sha256: hash, runtime_declarations_absent: true,
                    mockable_android_jars: classpath.files.findAll { it.name.contains('mockable') }.collect { it.absolutePath }
                ])) + '\\n'
            }
        }
    }
}
'''.replace('PACKET',str(P)).replace('JSON_SHA',expected_json_sha))
artifact=json.loads((A173/'release-scoped-readback.json').read_text())['apk'];apk=E/'build/app/outputs/apk/internal_gateway/release/app-internal_gateway-release-unsigned.apk';assert sha(apk)==artifact['sha256']
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update({'CI':'true','JAVA_HOME':str(JDK),'FLUTTER_SUPPRESS_ANALYTICS':'true','PUB_CACHE':str(R/'.cache/pub-cache-hygiene-20260930'),'PATH':str(SDK/'bin')+':/Users/jeanbosco/.local/bin:'+env['PATH']})
args=['./gradlew','-I',str(init),':app:testInternal_gatewayDebugUnitTest']
for suite,case in selection:args+=['--tests',suite+'.'+case]
args+=['-Ptarget=lib/main_gateway.dart','-PcollectUnsignedLocalQa=true','--offline','--no-daemon']
print('START48 affected Gateway JVM cases',flush=True);start=time.monotonic()
with (P/'gateway-json-jvm.stdout').open('wb') as out,(P/'gateway-json-jvm.stderr').open('wb') as err:code=subprocess.run(args,cwd=E/'android',env=env,stdout=out,stderr=err).returncode
execution={'status':'pass' if code==0 else 'fail','argv':args,'exit_code':code,'elapsed_seconds':round(time.monotonic()-start,2),'stdout_sha256':sha(P/'gateway-json-jvm.stdout'),'stderr_sha256':sha(P/'gateway-json-jvm.stderr')}
(P/'execution.json').write_text(json.dumps(execution,indent=2)+'\n');print('END48 JVM',code,flush=True)
files=list((E/'build/app/test-results/testInternal_gatewayDebugUnitTest').glob('TEST-*.xml'));results=[];observed=[]
(P/'jvm-test-results').mkdir()
for f in files:
 x=ET.parse(f).getroot();results.append({k:x.get(k) for k in ['name','tests','failures','errors','skipped']})
 observed += [(x.get('name'),c.get('name')) for c in x.findall('testcase')]
 shutil.copy2(f,P/'jvm-test-results'/f.name)
counts={k:sum(int(x[k]) for x in results) for k in ['tests','failures','errors','skipped']}
(P/'jvm-tests.json').write_text(json.dumps({'suites':results,'counts':counts,'exact_selected_cases_observed':sorted(observed)==sorted(selection)},indent=2)+'\n')
if code!=0:raise SystemExit(1)
assert counts=={'tests':48,'failures':0,'errors':0,'skipped':0} and sorted(observed)==sorted(selection)
logs=list(P.glob('jvm-class-load-*.log'));assert logs
origins=[line for f in logs for line in f.read_text().splitlines() if re.search(r'\bclass,load\]\s+org\.json\.JSONObject\s+source:',line)]
assert origins and all('json-20250517.jar' in line and 'mockable' not in line for line in origins),origins
(P/'actual-json-class-origins.json').write_text(json.dumps({'status':'pass','origins':origins,'class_log_sha256':{f.name:sha(f) for f in logs}},indent=2)+'\n')
assert sha(apk)==artifact['sha256'],'Passed173 Release artifact changed'
assert sha(current)==current_sha==sha(target),'Owned Gradle changed'
assert all((E/n).is_file() and sha(E/n)==h for n,h in frozen.items()),'Frozen native export source drift'
final_native={n:h for n,h in frozen.items() if n.startswith('android/app/src/internal_gateway/') or n in {'android/app/build.gradle.kts','android/gradle/CollectPluginRegistrant.java','lib/main_gateway.dart'}}
(P/'final-export-native-hashes.json').write_text(json.dumps(final_native,indent=2,sort_keys=True)+'\n')
report={'status':'pass','affected_jvm_tests':48,'failures_errors_skips':0,'exact_48_case_selection_verified':True,'real_json_class_loaded_in_actual_test_jvm':True,'json_coordinate':'org.json:json:20250517','json_artifact_sha256':expected_json_sha,'json_gateway_test_only_not_release_runtime':True,'previous174_50_passing_controls_reused':True,'release173_artifact_lint_graph_font_proof_reused':True,'release_apk_unchanged':artifact,'owned_gradle_sha256':current_sha,'all_frozen173_native_inputs_unchanged_except_174_marker_and_175_test_dependency':True,'minimal_frozen_candidate_overlay':['android/app/build.gradle.kts from this exact export; all other captured173 sources unchanged'],'scope':'Complete captured E3 acceptance via173 Release assemble/lint/graphs/registrants/Inter/unsigned APK plus17450 unaffected JVM passes and17548 affected realJSON cases. Shared latest Gateway/backend/MCP source may differ and is not overlaid or certified; no new Release/lint/prod/iOS or broad graph run.'}
(P/'verification.json').write_text(json.dumps(report,indent=2)+'\n');print('E3 targeted JSON PASS48',flush=True)
