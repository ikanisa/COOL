from pathlib import Path
import json, re, shutil, hashlib, os
stage_path=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/android-continuous-retention-20261001')
exec((stage_path/'proof.py').read_text().split("classes=run/'classes'")[0])
prior=Path('/Users/jeanbosco/.cache/collect-android-continuous-retention-20261001/attempt-7')
previous=json.loads((prior/'validation.json').read_text())
failed_method='callbackReceiptAcknowledgementsStayHotUntilActualAttemptArchiveClosesThem'
test_path='android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway/GatewayAttemptArchiveTest.kt'
old_source=(prior/'source'/test_path).read_text();new_source=(source/test_path).read_text()
a=old_source.index('    @Test fun '+failed_method);b=old_source.index('    @Test fun continuousV1CallbackReceipts',a)
na=new_source.index('    @Test fun '+failed_method);nb=new_source.index('    @Test fun continuousV1CallbackReceipts',na)
if old_source[:a]+old_source[b:]!=new_source[:na]+new_source[nb:]:raise RuntimeError('Fixture delta escapes affected method')
changes=[p for p,h in previous['source_sha256'].items() if inputs.get(p)!=h]
if changes!=[test_path] or set(inputs)!=set(previous['source_sha256']):raise RuntimeError('Unexpected source delta')
for p,h in previous['source_sha256'].items():
 if sha(prior/'source'/p)!=h:raise RuntimeError('Prior source proof drift')
if previous['canonical_changes'] or previous['staged_changes'] or previous['staging_source_changes']:raise RuntimeError('Prior source drift')
if previous['shim_sha256']!={p.name:sha(p) for p in shims.glob('*.kt')}:raise RuntimeError('Shim drift')
for c in previous['commands']:
 if c['status']!='terminal' or c['owned_child_reaped'] is not True:raise RuntimeError('Prior command not terminal')
 for stream in ('stdout','stderr'):
  if sha(prior/(c['name']+'.'+stream))!=c[stream+'_sha256']:raise RuntimeError('Prior output drift')
last=previous['commands'][-1];output=(prior/(last['name']+'.stdout')).read_text()
if last['name']!='tests-GatewayAttemptArchiveTest' or last['exit_code']!=1 or not re.search(r'Tests run: 37,\s+Failures: 1\s*$',output):raise RuntimeError('Prior full suite summary differs')
if re.findall(r'^\d+\) (\w+)\(app.cool.mobile.gateway.GatewayAttemptArchiveTest\)$',output,re.M)!=[failed_method]:raise RuntimeError('Unexpected failed method')
names=re.findall(r'@Test fun (\w+)\(',old_source)
if len(names)!=37 or len(set(names))!=37:raise RuntimeError('Prior method inventory differs')
for c in previous['commands'][:-1]:
 if c['exit_code']!=0:raise RuntimeError('Prior retained command failed')
classes=run/'classes';shutil.copytree(prior/'classes',classes)
compiled={str(p.relative_to(classes)):sha(p) for p in classes.rglob('*') if p.is_file()}
testclasses=run/'test-classes';testclasses.mkdir();tests=[p for p in source.rglob('*.kt') if p.stem in suites]
code=command('current-test-compile',compiler+['-module-name','gateway_tests','-Xfriend-paths='+str(classes),'-classpath',os.pathsep.join([str(classes),sourcecp]),'-d',str(testclasses)]+[str(p) for p in tests])
runner=run/'CorrectedCaseRunner.kt';runner.write_text('''import org.junit.runner.JUnitCore
import org.junit.runner.Request
fun main() {
 val result = JUnitCore().run(Request.method(app.cool.mobile.gateway.GatewayAttemptArchiveTest::class.java, "callbackReceiptAcknowledgementsStayHotUntilActualAttemptArchiveClosesThem"))
 for (failure in result.failures) println(failure.trace)
 println("Tests run: ${result.runCount}, Failures: ${result.failureCount}, Ignored: ${result.ignoreCount}")
 if (result.wasSuccessful() && result.runCount == 1 && result.ignoreCount == 0) { println("OK (1 tests)");System.exit(0) } else System.exit(1)
}
''')
runnerclasses=run/'runner-classes';runnerclasses.mkdir()
if not code:code=command('case-runner-compile',compiler+['-module-name','gateway_corrected_case','-classpath',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'-d',str(runnerclasses),str(runner)])
if not code:code=command('corrected-callback-closure-case',[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),str(runnerclasses),sourcecp]),'CorrectedCaseRunnerKt'])
if not code:
 result=(run/'corrected-callback-closure-case.stdout').read_text()
 if not re.search(r'^OK \(1 tests\)$',result,re.M):code=1
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),sourcecp]),'-d',str(api)]+[str(p) for p in (source/base).glob('*.kt')]+[str(config)])
runtime_readback()
changed=[p for p,h in before.items() if sha(repo/p)!=h];stagedchanged=[p for p,h in inputs.items() if sha(source/p)!=h];stagechanged=[p for p,h in inputs.items() if sha(stage/'source'/p)!=h]
compiledchanged=[p for p,h in compiled.items() if sha(classes/p)!=h or sha(prior/'classes'/p)!=h]
receipt={'status':'pass' if not code and not changed and not stagedchanged and not stagechanged and not compiledchanged else 'fail','acceptance_kind':'composed current source acceptance','prior_validation_sha256':sha(prior/'validation.json'),'prior_proof':str(prior),'retained_commands':previous['commands'][:-1],'retained_passing_suites':previous['suite_counts'],'retained_attempt_passing_methods':[n for n in names if n!=failed_method],'retained_attempt_method_count':36,'corrected_method':failed_method,'changed_source':[test_path],'unchanged_test_class_outside_method_sha256':hashlib.sha256((old_source[:a]+old_source[b:]).encode()).hexdigest(),'commands':commands,'junit_tests_passed':sum(previous['suite_counts'].values())+37 if not code else sum(previous['suite_counts'].values())+36,'full_current_suite_reexecuted':False,'current_corrected_case_tests':1 if not code else 0,'jvm_suite_count':10,'native_source_count':len(list((source/base).glob('*.kt'))),'canonical_changes':changed,'staged_changes':stagedchanged,'staging_source_changes':stagechanged,'compiled_product_changes':compiledchanged,'source_sha256':inputs,'canonical_before_sha256':sha(stage/'canonical-before.json'),'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'jdk_runtime_closure_sha256':sha(runtime_manifest),'jdk_runtime_entries':len(runtime),'compiled_product_sha256':compiled,'java':java,'limitations':['Composed acceptance: nine unchanged passing suites plus 36 unchanged passing methods from terminal failed attempt-7, corrected case recompiled/executed on current source and current Android36 API compile.','Canonical promotion has not occurred.','Offline filesystem/backend seams; no physical device, Keystore, carrier, hosted, Gradle or signing proof.','No continuous late-conflict paging, portable export/key recovery or v1 terminal-authority implementation in this slice.']}
persist(run/'validation.json',receipt);persist(stage/'latest-proof.json',{'path':str(run),'status':receipt['status']});print(json.dumps({'terminal':receipt['status'],'proof':str(run),'tests':receipt['junit_tests_passed'],'kind':receipt['acceptance_kind']}),flush=True)
raise SystemExit(code or bool(changed) or bool(stagedchanged) or bool(stagechanged) or bool(compiledchanged))
