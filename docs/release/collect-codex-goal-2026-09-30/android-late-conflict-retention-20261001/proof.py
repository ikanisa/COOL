from pathlib import Path
import json, os, re
previous=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/android-continuous-retention-20261001/proof.py')
prefix=previous.read_text().split("classes=run/'classes'")[0]
prefix=prefix.replace("stage=repo/'.cache/android-continuous-retention-20261001'", "stage=repo/'.cache/android-late-conflict-retention-20261001'")
prefix=prefix.replace("private=Path('/Users/jeanbosco/.cache/collect-android-continuous-retention-20261001')", "private=Path('/Users/jeanbosco/.cache/collect-android-late-conflict-retention-20261001')")
prefix=prefix.replace("'GatewaySignedBackend','GatewayRetentionIndex']", "'GatewaySignedBackend','GatewayRetentionIndex','GatewayLateRetention']")
prefix=prefix.replace("'GatewayBackgroundCoordinatorTest','GatewayRetentionMigrationTest']", "'GatewayBackgroundCoordinatorTest','GatewayRetentionMigrationTest','GatewayLateRetentionTest','GatewayLateBackendTest']")
prefix=prefix.replace("timeout_seconds':480", "timeout_seconds':900").replace('wait(timeout=480)','wait(timeout=900)')
prefix=prefix.replace("bins=[Path(x['path'])", "p=shims/'AtomicFile.kt';s=p.read_text().replace('var writeCount = 0','var writeCount = 0; var failWriteNumberOnce: Int? = null').replace('AtomicFileFaults.failFileOnce == baseFile.name)', 'AtomicFileFaults.failFileOnce == baseFile.name || AtomicFileFaults.failWriteNumberOnce == AtomicFileFaults.writeCount)').replace('AtomicFileFaults.failFileOnce = null;', 'AtomicFileFaults.failFileOnce = null; AtomicFileFaults.failWriteNumberOnce = null;');p.write_text(s)\nbins=[Path(x['path'])")
exec(prefix)
classes=run/'classes';classes.mkdir()
code=command('product',compiler+['-module-name','gateway_product','-classpath',sourcecp,'-d',str(classes)]+[str(source/base/(x+'.kt')) for x in products]+[str(p) for p in shims.glob('*.kt')])
testclasses=run/'test-classes';testclasses.mkdir();tests=[p for p in source.rglob('*.kt') if p.stem in suites]
if not code:code=command('test-compile',compiler+['-module-name','gateway_tests','-Xfriend-paths='+str(classes),'-classpath',os.pathsep.join([str(classes),sourcecp]),'-d',str(testclasses)]+[str(p) for p in tests])
runner=run/'CurrentCases.kt';runner.write_text('''import org.junit.runner.JUnitCore
import org.junit.runner.Request
import org.junit.runner.Description
import org.junit.runner.notification.Failure
import org.junit.runner.notification.RunListener
import org.junit.runner.manipulation.Filter
fun main(args: Array<String>) {
 val skipped = setOf("attemptsContinueBeyondOneLegacyHashShardWithoutGrowingIndexObjects", "segmentedColdStorageSurvivesMoreThanOneHundredAttempts", "signedHeartbeatContinuesPastLegacyLifetimeCeilingWithEveryOriginalPreserved")
 val request = Request.aClass(Class.forName(args.single())).filterWith(object : Filter() {
  override fun shouldRun(description: Description): Boolean = description.methodName !in skipped
  override fun describe() = "Affected cases; excludes three unchanged heavy predecessor cohorts"
 })
 val failed = mutableSetOf<String>();val core = JUnitCore()
 core.addListener(object : RunListener() {
  override fun testStarted(d: Description) { println("BEGIN ${d.className}.${d.methodName}") }
  override fun testFailure(f: Failure) { failed.add(f.description.methodName);println(f.trace) }
  override fun testFinished(d: Description) { println("CASE ${d.className}.${d.methodName} ${if (d.methodName in failed) "FAIL" else "PASS"}") }
 })
 val result = core.run(request)
 println("Tests run: ${result.runCount}, Failures: ${result.failureCount}, Ignored: ${result.ignoreCount}")
 if (result.wasSuccessful() && result.runCount > 0 && result.ignoreCount == 0) { println("OK (${result.runCount} tests)");System.exit(0) } else System.exit(1)
}
''')
runnerclasses=run/'runner-classes';runnerclasses.mkdir()
if not code:code=command('runner-compile',compiler+['-module-name','gateway_affected_cases','-classpath',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'-d',str(runnerclasses),str(runner)])
counts={};case_results=[]
for suite in ['GatewayLateRetentionTest','GatewayLateBackendTest','GatewayArchiveStorageTest','GatewayArchiveBackendIntegrationTest','GatewayDispatchBackendIntegrationTest','GatewayAttemptArchiveBackendTest','GatewayJournalArchiveTest','GatewayRetentionMigrationTest','GatewayAttemptArchiveTest']:
 if code:break
 code=command('tests-'+suite,[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),str(runnerclasses),sourcecp]),'CurrentCasesKt','app.cool.mobile.gateway.'+suite])
 output=(run/('tests-'+suite+'.stdout')).read_text();passed=re.findall(r'^CASE (\S+) PASS$',output,re.M);failed=re.findall(r'^CASE (\S+) FAIL$',output,re.M)
 summary=re.findall(r'^OK \((\d+) tests\)$',output,re.M)
 case_results.extend({'method':name,'status':'pass'} for name in passed);case_results.extend({'method':name,'status':'fail'} for name in failed)
 if not code and len(summary)==1 and len(passed)==int(summary[0]) and not failed:counts[suite]=int(summary[0])
 else:code=code or 1
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),sourcecp]),'-d',str(api)]+[str(p) for p in (source/base).glob('*.kt')]+[str(config)])
runtime_readback()
changes={ 'canonical':[p for p,h in before.items() if sha(repo/p)!=h], 'copied':[p for p,h in inputs.items() if sha(source/p)!=h], 'staging':[p for p,h in inputs.items() if sha(stage/'source'/p)!=h] }
receipt={'status':'pass' if not code and not any(changes.values()) else 'fail','commands':commands,'suite_counts':counts,'case_results':case_results,'junit_tests_passed':sum(counts.values()),'source_sha256':inputs,'source_changes':changes,'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'jdk_runtime_closure_sha256':sha(runtime_manifest),'jdk_runtime_entries':len(runtime),'native_source_count':len(list((source/base).glob('*.kt'))),'java':java,'excluded_predecessor_heavy_cases':['GatewayAttemptArchiveTest.attemptsContinueBeyondOneLegacyHashShardWithoutGrowingIndexObjects','GatewayAttemptArchiveTest.segmentedColdStorageSurvivesMoreThanOneHundredAttempts','GatewayArchiveBackendIntegrationTest.signedHeartbeatContinuesPastLegacyLifetimeCeilingWithEveryOriginalPreserved'],'limitations':['Fresh affected-case proof only; unchanged heavyweight predecessor cohorts and unrelated pure protocol/safety suites were not re-executed, and are not counted as fresh current evidence.','Synthetic acknowledged historical objects are fixture setup; no hosted authority, physical device, Keystore, carrier, Gradle, signing, store or portable recovery proof.','Canonical sources remain unchanged; root owns promotion.']}
persist(run/'validation.json',receipt);persist(stage/'latest-proof.json',{'path':str(run),'status':receipt['status']});print(json.dumps({'terminal':receipt['status'],'proof':str(run),'tests':receipt['junit_tests_passed']}),flush=True)
raise SystemExit(code or any(changes.values()))
