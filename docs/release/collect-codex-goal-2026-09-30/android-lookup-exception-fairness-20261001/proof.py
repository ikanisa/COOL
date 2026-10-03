from pathlib import Path
import json, os, re
previous=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/android-continuous-retention-20261001/proof.py')
prefix=previous.read_text().split("classes=run/'classes'")[0]
prefix=prefix.replace("stage=repo/'.cache/android-continuous-retention-20261001'", "stage=repo/'.cache/android-lookup-exception-fairness-20261001'")
prefix=prefix.replace("private=Path('/Users/jeanbosco/.cache/collect-android-continuous-retention-20261001')", "private=Path('/Users/jeanbosco/.cache/collect-android-lookup-exception-fairness-20261001')")
prefix=prefix.replace("'GatewaySignedBackend','GatewayRetentionIndex']", "'GatewaySignedBackend','GatewayRetentionIndex','GatewayLateRetention']")
prefix=prefix.replace("'GatewayBackgroundCoordinatorTest','GatewayRetentionMigrationTest']", "'GatewayBackgroundCoordinatorTest','GatewayRetentionMigrationTest','GatewayLateRetentionTest','GatewayLateBackendTest']")
prefix=prefix.replace("timeout_seconds':480", "timeout_seconds':900").replace('wait(timeout=480)','wait(timeout=900)')
prefix=prefix.replace("bins=[Path(x['path'])", "p=shims/'AtomicFile.kt';s=p.read_text().replace('var writeCount = 0','var writeCount = 0; var failWriteNumberOnce: Int? = null').replace('AtomicFileFaults.failFileOnce == baseFile.name)', 'AtomicFileFaults.failFileOnce == baseFile.name || AtomicFileFaults.failWriteNumberOnce == AtomicFileFaults.writeCount)').replace('AtomicFileFaults.failFileOnce = null;', 'AtomicFileFaults.failFileOnce = null; AtomicFileFaults.failWriteNumberOnce = null;');p.write_text(s)\nbins=[Path(x['path'])")
prefix=prefix.replace("before=json.loads((stage/'canonical-before.json').read_text())", "before=json.loads((stage/'base-association.json').read_text())['source_sha256']")
exec(prefix)
baseline=Path('/Users/jeanbosco/.cache/collect-android-late-conflict-retention-20261001/attempt-3')
base_packet=repo/'.cache/android-late-conflict-retention-20261001/accepted-packet'
base_result=json.loads((baseline/'validation.json').read_text())
if base_result['status']!='pass':raise RuntimeError('Baseline not accepted')
changed={'android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway/GatewaySignedBackend.kt','android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway/GatewayTransport.kt'}
for name,digest in base_result['source_sha256'].items():
 if sha(baseline/'source'/name)!=digest or sha(base_packet/'source'/name)!=digest:raise RuntimeError('Baseline source drift '+name)
 if name not in changed and sha(source/name)!=digest:raise RuntimeError('Unexpected source delta '+name)
artifacts=json.loads((base_packet/'compiled-artifacts.json').read_text())
for name,item in artifacts.items():
 if name.startswith('classes/') or name.startswith('test-classes/'):
  if sha(Path(item['path']))!=item['sha256']:raise RuntimeError('Reusable artifact drift '+name)
classes=run/'classes';shutil.copytree(baseline/'classes',classes)
# Remove only the replaced caller/transport bytecode; retain exact unaffected artifacts.
removed=[]
for p in (classes/'app/cool/mobile/gateway').glob('*.class'):
 if p.name.startswith('GatewaySignedBackend') or p.name.startswith('GatewayHttpsTransport'):removed.append(str(p.relative_to(classes)));p.unlink()
persist(run/'reused-baseline-association.json',{'base_validation_sha256':sha(baseline/'validation.json'),'base_manifest_sha256':sha(base_packet/'MANIFEST.json'),'source_sha256':base_result['source_sha256'],'compiled_artifacts':{k:v for k,v in artifacts.items() if k.startswith('classes/') or k.startswith('test-classes/')},'replaced_class_files':removed,'excluded_baseline_test_claims':True})
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
code=command('affected-product-compile',compiler+['-module-name','gateway_lookup_delta','-Xfriend-paths='+str(baseline/'classes'),'-classpath',os.pathsep.join([str(baseline/'classes'),sourcecp]),'-d',str(classes)]+[str(source/p) for p in sorted(changed)])
testclasses=run/'test-classes';shutil.copytree(baseline/'test-classes',testclasses)
newtest=source/'android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway/GatewayLookupFairnessTest.kt'
if not code:code=command('affected-test-compile',compiler+['-module-name','gateway_lookup_tests','-Xfriend-paths='+str(classes)+','+str(testclasses),'-classpath',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'-d',str(testclasses),str(newtest)])
runner=run/'CurrentCases.kt';shutil.copyfile(baseline/'CurrentCases.kt',runner);runnerclasses=run/'runner-classes';shutil.copytree(baseline/'runner-classes',runnerclasses)
counts={};case_results=[]
for suite in ['GatewayLookupFairnessTest','GatewayLateBackendTest','GatewayArchiveBackendIntegrationTest','GatewayDispatchBackendIntegrationTest','GatewayAttemptArchiveBackendTest']:
 if code:break
 name='tests-'+suite
 code=command(name,[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),str(runnerclasses),sourcecp]),'CurrentCasesKt','app.cool.mobile.gateway.'+suite])
 output=(run/(name+'.stdout')).read_text();passed=re.findall(r'^CASE (\S+) PASS$',output,re.M);failed=re.findall(r'^CASE (\S+) FAIL$',output,re.M);summary=re.findall(r'^OK \((\d+) tests\)$',output,re.M)
 case_results.extend({'method':m,'status':'pass','command':name} for m in passed);case_results.extend({'method':m,'status':'fail','command':name} for m in failed)
 if not code and len(summary)==1 and len(passed)==int(summary[0]) and not failed:counts[suite]=int(summary[0])
 else:code=code or 1
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),sourcecp]),'-d',str(api)]+[str(p) for p in (source/base).glob('*.kt')]+[str(config)])
runtime_readback()
changes={'copied':[p for p,h in inputs.items() if sha(source/p)!=h],'staging':[p for p,h in inputs.items() if sha(stage/'source'/p)!=h],'base_packet':[p for p,h in base_result['source_sha256'].items() if sha(base_packet/'source'/p)!=h]}
receipt={'status':'pass' if not code and not any(changes.values()) else 'fail','commands':commands,'suite_counts':counts,'case_results':case_results,'junit_tests_passed':sum(counts.values()),'source_sha256':inputs,'source_changes':changes,'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'jdk_runtime_closure_sha256':sha(runtime_manifest),'jdk_runtime_entries':len(runtime),'native_source_count':len(list((source/base).glob('*.kt'))),'java':java,'reused_baseline_association_sha256':sha(run/'reused-baseline-association.json'),'limitations':['Fresh focused caller proof only; preceding storage/heavy cohorts are unchanged and not counted as fresh current results.','Only two production classes and one new test class recompiled; unchanged product/test/runner artifacts hash-bound to accepted baseline.','No canonical mutation or physical-device/provider/Gradle/signing/store/live proof.']}
persist(run/'validation.json',receipt);persist(stage/'latest-proof.json',{'path':str(run),'status':receipt['status']});print(json.dumps({'terminal':receipt['status'],'proof':str(run),'tests':receipt['junit_tests_passed']}),flush=True)
raise SystemExit(code or any(changes.values()))
