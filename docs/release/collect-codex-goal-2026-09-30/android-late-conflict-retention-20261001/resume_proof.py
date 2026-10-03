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
previous_run=private/'attempt-1'
observation=json.loads((previous_run/'interrupted-observation.json').read_text())
if observation['status']!='interrupted_not_accepted' or observation['source_changes']:raise RuntimeError('Original interruption association invalid')
# Reuse only the terminal product compile; tests changed in one explicitly bounded fixture.
product_receipt=next(c for c in observation['commands'] if c['name']=='product')
if product_receipt['status']!='terminal' or product_receipt['exit_code']!=0 or not product_receipt['owned_child_reaped']:raise RuntimeError('No terminal product compile')
product_paths=[Path(p) for p in product_receipt['argv'] if p.endswith('.kt')]
for p in product_paths:
 relative=p.relative_to(previous_run)
 current=run/relative
 expected=observation['source_sha256'].get(str(relative.relative_to('source'))) if relative.parts[0]=='source' else sha(p)
 if sha(p)!=expected or sha(current)!=expected:raise RuntimeError('Reused product input drift: '+str(relative))
classes=run/'classes';shutil.copytree(previous_run/'classes',classes)
artifact_map={}
for name,digest in observation['compiled_artifacts_sha256'].items():
 if name.startswith('classes/'):
  if sha(previous_run/name)!=digest or sha(run/name)!=digest:raise RuntimeError('Reused product artifact drift: '+name)
  artifact_map[name]=digest
persist(run/'reused-product-association.json',{'terminal_product_receipt':product_receipt,'original_observation_sha256':sha(previous_run/'interrupted-observation.json'),'artifact_sha256':artifact_map,'source_binding':{str(p.relative_to(previous_run)):sha(p) for p in product_paths}})
code=0
# Own every child terminal receipt, including interruption and timeout cleanup.
def command(name,args):
 t=time.monotonic();out=run/(name+'.stdout');err=run/(name+'.stderr');print(json.dumps({'stage':name,'running':True,'proof':str(run)}),flush=True)
 record={'name':name,'argv':args,'status':'running','timeout_seconds':900};commands.append(record);persist(run/'commands.json',commands)
 caught=None;timed_out=False
 with out.open('wb') as o,err.open('wb') as e:
  process=subprocess.Popen(args,stdout=o,stderr=e,cwd=run,env={'PATH':os.defpath,'HOME':str(private),'TMPDIR':str(run),'LANG':'C.UTF-8'},start_new_session=True)
  record.update(pid=process.pid,process_group=process.pid);persist(run/'commands.json',commands)
  try:process.wait(timeout=900)
  except subprocess.TimeoutExpired:
   timed_out=True;os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=10)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
  except BaseException as error:caught=error
  finally:
   if process.poll() is None:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
   o.flush();e.flush();os.fsync(o.fileno());os.fsync(e.fileno())
 record.update(status='interrupted' if caught else 'timeout' if timed_out else 'terminal',exit_code=process.returncode,wall_seconds=time.monotonic()-t,stdout_sha256=sha(out),stderr_sha256=sha(err),owned_child_reaped=process.poll() is not None)
 persist(run/'commands.json',commands);print(json.dumps({k:v for k,v in record.items() if k!='argv'}),flush=True)
 if caught:raise caught
 return process.returncode or (124 if timed_out else 0)
testclasses=run/'test-classes';testclasses.mkdir();tests=[p for p in source.rglob('*.kt') if p.stem in suites]
code=command('test-compile',compiler+['-module-name','gateway_tests','-Xfriend-paths='+str(classes),'-classpath',os.pathsep.join([str(classes),sourcecp]),'-d',str(testclasses)]+[str(p) for p in tests])
runner=run/'CurrentCases.kt';runner.write_text('''import org.junit.runner.JUnitCore
import org.junit.runner.Request
import org.junit.runner.Description
import org.junit.runner.notification.Failure
import org.junit.runner.notification.RunListener
import org.junit.runner.manipulation.Filter
fun main(args: Array<String>) {
 val skipped = setOf("attemptsContinueBeyondOneLegacyHashShardWithoutGrowingIndexObjects", "segmentedColdStorageSurvivesMoreThanOneHundredAttempts", "signedHeartbeatContinuesPastLegacyLifetimeCeilingWithEveryOriginalPreserved")
 val klass=Class.forName(args[0])
 val request = if(args.size==2) Request.method(klass,args[1]) else Request.aClass(klass).filterWith(object : Filter() {
  override fun shouldRun(d: Description): Boolean = d.methodName !in skipped
  override fun describe() = "Affected cases; excludes three unchanged heavy predecessor cohorts"
 })
 val failed = mutableSetOf<String>();val core = JUnitCore()
 core.addListener(object : RunListener() {
  override fun testStarted(d: Description) { println("BEGIN ${d.className}.${d.methodName}") }
  override fun testFailure(f: Failure) { failed.add(f.description.methodName);println(f.trace) }
  override fun testFinished(d: Description) { println("CASE ${d.className}.${d.methodName} ${if (d.methodName in failed) "FAIL" else "PASS"}") }
 })
 val result=core.run(request)
 println("Tests run: ${result.runCount}, Failures: ${result.failureCount}, Ignored: ${result.ignoreCount}")
 if(result.wasSuccessful() && result.runCount>0 && result.ignoreCount==0) { println("OK (${result.runCount} tests)");System.exit(0) } else System.exit(1)
}
''')
runnerclasses=run/'runner-classes';runnerclasses.mkdir()
if not code:code=command('runner-compile',compiler+['-module-name','gateway_affected_cases','-classpath',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'-d',str(runnerclasses),str(runner)])
counts={};case_results=[]
methods=re.findall(r'@Test fun (\w+)\(', (source/'android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway/GatewayLateRetentionTest.kt').read_text())
work=[('GatewayLateRetentionTest',m) for m in methods]+[(s,None) for s in ['GatewayLateBackendTest','GatewayArchiveStorageTest','GatewayArchiveBackendIntegrationTest','GatewayDispatchBackendIntegrationTest','GatewayAttemptArchiveBackendTest','GatewayJournalArchiveTest','GatewayRetentionMigrationTest','GatewayAttemptArchiveTest']]
for suite,method in work:
 if code:break
 name='tests-'+suite+('-'+method if method else '')
 args=[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),str(runnerclasses),sourcecp]),'CurrentCasesKt','app.cool.mobile.gateway.'+suite]+([method] if method else [])
 code=command(name,args)
 output=(run/(name+'.stdout')).read_text();passed=re.findall(r'^CASE (\S+) PASS$',output,re.M);failed=re.findall(r'^CASE (\S+) FAIL$',output,re.M);summary=re.findall(r'^OK \((\d+) tests\)$',output,re.M)
 case_results.extend({'method':m,'status':'pass','command':name} for m in passed);case_results.extend({'method':m,'status':'fail','command':name} for m in failed)
 if not code and len(summary)==1 and len(passed)==int(summary[0]) and not failed:counts[suite]=counts.get(suite,0)+int(summary[0])
 else:code=code or 1
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),sourcecp]),'-d',str(api)]+[str(p) for p in (source/base).glob('*.kt')]+[str(config)])
runtime_readback()
changes={'canonical':[p for p,h in before.items() if sha(repo/p)!=h], 'copied':[p for p,h in inputs.items() if sha(source/p)!=h], 'staging':[p for p,h in inputs.items() if sha(stage/'source'/p)!=h]}
receipt={'status':'pass' if not code and not any(changes.values()) else 'fail','commands':commands,'suite_counts':counts,'case_results':case_results,'junit_tests_passed':sum(counts.values()),'source_sha256':inputs,'source_changes':changes,'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'jdk_runtime_closure_sha256':sha(runtime_manifest),'jdk_runtime_entries':len(runtime),'native_source_count':len(list((source/base).glob('*.kt'))),'java':java,'reused_product_association_sha256':sha(run/'reused-product-association.json'),'limitations':['Fresh109 affected-case proof only; three unchanged heavyweight predecessor cohorts and unrelated pure protocol/safety suites are excluded, not counted as fresh current evidence.','Synthetic authenticated historical fixture admission does not prove hosted authority, physical device, Keystore, carrier, Gradle, signing, store or portable recovery.','Canonical sources remain unchanged; root owns promotion.','Attempt1 interrupted native command is preserved as non-acceptance evidence; its terminal product compile is reused with exact source/shim/dependency/artifact binding.']}
persist(run/'validation.json',receipt);persist(stage/'latest-proof.json',{'path':str(run),'status':receipt['status']});print(json.dumps({'terminal':receipt['status'],'proof':str(run),'tests':receipt['junit_tests_passed']}),flush=True)
raise SystemExit(code or any(changes.values()))
