from pathlib import Path
import json,hashlib,os,shutil,subprocess,time,re,signal,atexit
repo=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');stage=repo/'.cache/android-complete-recovery-20261001'
private=stage/'proof-workspace';private.mkdir(exist_ok=True)
run=private/('attempt-'+str(len(list(private.glob('attempt-*')))+1));run.mkdir()
source=run/'source';shutil.copytree(stage/'source',source)
baseline=Path('/Users/jeanbosco/.cache/collect-android-lookup-exception-fairness-20261001/attempt-2')
packet=repo/'.cache/android-lookup-exception-fairness-20261001/accepted-packet'
old=json.loads(Path('/Users/jeanbosco/.cache/collect-android-native-proof-20261001/staging.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def persist(path,value):
 temp=path.with_suffix(path.suffix+'.new')
 with temp.open('w') as s:s.write(json.dumps(value,indent=2)+'\n');s.flush();os.fsync(s.fileno())
 os.replace(temp,path)
inputs={str(p.relative_to(source)):sha(p) for p in source.rglob('*') if p.is_file()}
base=json.loads((stage/'base-association.json').read_text()); prior=json.loads((packet/'final-source-association.json').read_text())
accepted=json.loads((packet/'validation.json').read_text())
if accepted['status']!='pass' or sha(packet/'MANIFEST.json')!=base['fairness_manifest_sha256']:raise RuntimeError('Baseline not accepted')
for name,digest in base['source_sha256'].items():
 if sha(repo/name)!=digest:raise RuntimeError('Canonical source drift '+name)
 if (packet/'source'/name).exists() and sha(packet/'source'/name)!=digest:raise RuntimeError('Baseline canonical binding drift '+name)
shims=run/'shims';shutil.copytree(packet/'shims',shims)
shims.chmod(0o700)
if (shims/'Build.kt').exists():(shims/'Build.kt').chmod(0o600)
(shims/'Build.kt').write_text('package android.os\nobject Build { object VERSION { const val SDK_INT = 36 } }\n')
bins=[Path(x['path']) for x in old['staged_binaries'].values()];deps=bins[:9];java=old['java'];sourcecp=os.pathsep.join(str(deps[i]) for i in (1,4,6,7,8))
compiler=[java,'-Xms64m','-Xmx1g','-XX:ActiveProcessorCount=2','-cp',os.pathsep.join(map(str,deps)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17']
for original,entry in old['staged_binaries'].items():
 if sha(Path(entry['path']))!=entry['sha256'] or sha(Path(original))!=entry['sha256']:raise RuntimeError('Dependency drift '+original)
runtime_manifest=packet/'jdk-runtime-closure.json';runtime=json.loads(runtime_manifest.read_text());jdk=Path(old['jdk_root'])
if sha(runtime_manifest)!=old['jdk_runtime_closure_sha256']:raise RuntimeError('Runtime binding drift')
def runtime_readback():
 entries={str(p.relative_to(jdk)):p for p in jdk.rglob('*')}
 if set(entries)!=set(runtime):raise RuntimeError('Runtime closure drift')
 for name,item in runtime.items():
  p=entries[name]
  if item['kind']=='file':
   if p.is_symlink() or sha(p)!=item['sha256'] or oct(p.stat().st_mode&0o777)!=item['mode']:raise RuntimeError('Runtime file drift '+name)
  elif item['kind']=='symlink':
   if not p.is_symlink() or os.readlink(p)!=item['target'] or not p.resolve(strict=True).is_relative_to(jdk.resolve()):raise RuntimeError('Runtime link drift')
  elif p.is_symlink() or not p.is_dir() or oct(p.stat().st_mode&0o777)!=item['mode']:raise RuntimeError('Runtime directory drift')
runtime_readback();shutil.copyfile(runtime_manifest,run/'jdk-runtime-closure.json')
commands=[]
def command(name,args):
 record={'name':name,'argv':args,'status':'running','timeout_seconds':900};commands.append(record);persist(run/'commands.json',commands)
 print(json.dumps({'stage':name,'running':True,'proof':str(run)}),flush=True);start=time.monotonic();caught=None;timeout=False
 out=run/(name+'.stdout');err=run/(name+'.stderr')
 with out.open('wb') as o,err.open('wb') as e:
  process=subprocess.Popen(args,stdout=o,stderr=e,cwd=run,env={'PATH':os.defpath,'HOME':str(private),'TMPDIR':str(run),'LANG':'C.UTF-8'},start_new_session=True)
  record.update(pid=process.pid,process_group=process.pid);persist(run/'commands.json',commands)
  try:process.wait(timeout=900)
  except subprocess.TimeoutExpired:
   timeout=True;os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=10)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
  except BaseException as ex:caught=ex
  finally:
   if process.poll() is None:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
   o.flush();e.flush();os.fsync(o.fileno());os.fsync(e.fileno())
 record.update(status='interrupted' if caught else 'timeout' if timeout else 'terminal',exit_code=process.returncode,wall_seconds=time.monotonic()-start,stdout_sha256=sha(out),stderr_sha256=sha(err),owned_child_reaped=process.poll() is not None)
 persist(run/'commands.json',commands);print(json.dumps({k:v for k,v in record.items() if k!='argv'}),flush=True)
 if caught:raise caught
 return process.returncode or (124 if timeout else 0)
def interrupted():
 if not (run/'validation.json').exists():persist(run/'validation.json',{'status':'fail','reason':'interrupted_or_exception','commands':commands,'source_sha256':inputs});persist(stage/'latest-proof.json',{'path':str(run),'status':'fail'})
atexit.register(interrupted)
def stop(signum,frame):raise InterruptedError('Owned runner interrupted')
signal.signal(signal.SIGTERM,stop)
basepath=Path('android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway')
products=['GatewayJournal','GatewayJournalArchive','GatewayEncryptedStore','GatewayCrypto','GatewayAttemptArchive','GatewayAttemptArchiveWire','GatewayDispatch','GatewayDispatchWire','GatewayBackgroundCoordinator','GatewayInstalledEnrollment','GatewayWire','GatewayTransport','GatewayRadioObservation','GatewayDeviceIdentity','GatewaySignedBackend','GatewayRetentionIndex','GatewayLateRetention','GatewayRecovery']
classes=run/'classes';classes.mkdir();code=command('product',compiler+['-module-name','gateway_product','-classpath',sourcecp,'-d',str(classes)]+[str(source/basepath/(x+'.kt')) for x in products]+[str(p) for p in shims.glob('*.kt')])
# Fixture source is compiled for setup only; its preceding expensive cohorts are
# not repeated or counted in this focused recovery proof.
testclasses=run/'test-classes';testclasses.mkdir();testbase=Path('android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway')
if not code:code=command('test-compile',compiler+['-module-name','gateway_tests','-Xfriend-paths='+str(classes),'-classpath',os.pathsep.join([str(classes),sourcecp]),'-d',str(testclasses)]+[str(source/testbase/(x+'.kt')) for x in ['GatewayLateRetentionTest','GatewayRecoveryTest','GatewayRecoveryHistoryTest','GatewayLookupFairnessTest','GatewayArchiveStorageTest','GatewayDispatchBackendIntegrationTest']])
runner=run/'CurrentCases.kt';shutil.copyfile(packet/'CurrentCases.kt',runner);runnerclasses=run/'runner-classes';runnerclasses.mkdir()
if not code:code=command('runner',compiler+['-classpath',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'-d',str(runnerclasses),str(runner)])
counts={};cases=[]
for suite in ['GatewayRecoveryTest','GatewayRecoveryHistoryTest','GatewayLookupFairnessTest','GatewayArchiveStorageTest','GatewayDispatchBackendIntegrationTest']:
 if code:break
 name='tests-'+suite;code=command(name,[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),str(runnerclasses),sourcecp]),'CurrentCasesKt','app.cool.mobile.gateway.'+suite])
 output=(run/(name+'.stdout')).read_text();passed=re.findall(r'^CASE (\S+) PASS$',output,re.M);failed=re.findall(r'^CASE (\S+) FAIL$',output,re.M);summary=re.findall(r'^OK \((\d+) tests\)$',output,re.M)
 cases.extend({'method':m,'status':'pass','command':name} for m in passed);cases.extend({'method':m,'status':'fail','command':name} for m in failed)
 if not code and len(summary)==1 and len(passed)==int(summary[0]) and not failed:counts[suite]=int(summary[0])
 else:code=code or 1
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),sourcecp]),'-d',str(api)]+[str(p) for p in (source/basepath).glob('*.kt')]+[str(config)])
runtime_readback();changes={'copied':[p for p,h in inputs.items() if sha(source/p)!=h],'stage':[p for p,h in inputs.items() if sha(stage/'source'/p)!=h],'canonical':[p for p,h in base['source_sha256'].items() if sha(repo/p)!=h]}
result={'status':'pass' if not code and not any(changes.values()) else 'fail','commands':commands,'suite_counts':counts,'case_results':cases,'junit_tests_passed':sum(counts.values()),'source_sha256':inputs,'source_changes':changes,'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'jdk_runtime_closure_sha256':sha(runtime_manifest),'jdk_runtime_entries':len(runtime),'native_source_count':len(list((source/basepath).glob('*.kt'))),'java':java,'limitations':['Offline encryption/filesystem/HTTPS seams. No portable Android Keystore recovery, real device, Gradle packaging, signing or hosted proof.','Streaming snapshot/validation scales in total duration and disk with evidence; export holds process/CycleGate until finished and supports cancellation. Recovery tooling requires Android API26.']}
persist(run/'validation.json',result);persist(stage/'latest-proof.json',{'path':str(run),'status':result['status']});print(json.dumps({'terminal':result['status'],'proof':str(run),'tests':result['junit_tests_passed']}),flush=True)
raise SystemExit(code or any(changes.values()))
