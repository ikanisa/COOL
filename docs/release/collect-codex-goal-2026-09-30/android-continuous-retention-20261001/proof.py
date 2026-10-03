from pathlib import Path
import json, hashlib, os, shutil, subprocess, time, re, signal, traceback, atexit
repo=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL'); stage=repo/'.cache/android-continuous-retention-20261001'
old=json.loads(Path('/Users/jeanbosco/.cache/collect-android-native-proof-20261001/staging.json').read_text())
private=Path('/Users/jeanbosco/.cache/collect-android-continuous-retention-20261001');private.mkdir(mode=0o700,exist_ok=True)
run=private/('attempt-'+str(len(list(private.glob('attempt-*')))+1));run.mkdir(mode=0o700)
source=run/'source';shutil.copytree(stage/'source',source);shims=run/'shims';shutil.copytree(Path(old['shim_root']),shims)
# Add deterministic write-boundary fault controls only to the offline shim.
p=shims/'AtomicFile.kt';p.chmod(0o600);s=p.read_text().replace('var failFinishOnce = false','var failFinishOnce = false; var failFileOnce: String? = null; var writeCount = 0').replace('if (AtomicFileFaults.failFinishOnce) {','AtomicFileFaults.writeCount++; if (AtomicFileFaults.failFinishOnce || AtomicFileFaults.failFileOnce == baseFile.name) { AtomicFileFaults.failFileOnce = null;');p.write_text(s)
bins=[Path(x['path']) for x in old['staged_binaries'].values()];deps=bins[:9];java=old['java'];sourcecp=os.pathsep.join(str(deps[i]) for i in (1,4,6,7,8))
compiler=[java,'-Xms64m','-Xmx1g','-XX:ActiveProcessorCount=2','-cp',os.pathsep.join(map(str,deps)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17']
products=['GatewayJournal','GatewayJournalArchive','GatewayEncryptedStore','GatewayCrypto','GatewayAttemptArchive','GatewayAttemptArchiveWire','GatewayDispatch','GatewayDispatchWire','GatewayBackgroundCoordinator','GatewayInstalledEnrollment','GatewayWire','GatewayTransport','GatewayRadioObservation','GatewayDeviceIdentity','GatewaySignedBackend','GatewayRetentionIndex']
base=Path('android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway');suites=['GatewayAttemptArchiveTest','GatewayAttemptArchiveBackendTest','GatewayJournalArchiveTest','GatewayArchiveStorageTest','GatewaySafetyTest','GatewayDispatchBackendIntegrationTest','GatewayArchiveBackendIntegrationTest','GatewayDispatchWireTest','GatewayBackgroundCoordinatorTest','GatewayRetentionMigrationTest']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs={str(p.relative_to(source)):sha(p) for p in source.rglob('*') if p.is_file()};before=json.loads((stage/'canonical-before.json').read_text());commands=[]
def persist(path,value):
 temp=path.with_suffix(path.suffix+'.new')
 with temp.open('w') as stream:
  stream.write(json.dumps(value,indent=2)+'\n');stream.flush();os.fsync(stream.fileno())
 os.replace(temp,path)

def command(name,args):
 t=time.monotonic();out=run/(name+'.stdout');err=run/(name+'.stderr');print(json.dumps({'stage':name,'running':True,'proof':str(run)}),flush=True)
 record={'name':name,'argv':args,'status':'running','timeout_seconds':480}
 commands.append(record);persist(run/'commands.json',commands)
 with out.open('wb') as o,err.open('wb') as e:
  process=subprocess.Popen(args,stdout=o,stderr=e,cwd=run,env={'PATH':os.defpath,'HOME':str(private),'TMPDIR':str(run),'LANG':'C.UTF-8'},start_new_session=True)
  record.update(pid=process.pid,process_group=process.pid);persist(run/'commands.json',commands)
  timed_out=False
  try:
   process.wait(timeout=480)
  except subprocess.TimeoutExpired:
   timed_out=True
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=10)
   except subprocess.TimeoutExpired:
    os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
  finally:
   if process.poll() is None:
    os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
   o.flush();e.flush();os.fsync(o.fileno());os.fsync(e.fileno())
 record.update(status='timeout' if timed_out else 'terminal',exit_code=process.returncode,wall_seconds=time.monotonic()-t,stdout_sha256=sha(out),stderr_sha256=sha(err),owned_child_reaped=process.poll() is not None)
 persist(run/'commands.json',commands)
 print(json.dumps({k:v for k,v in record.items() if k != 'argv'}),flush=True)
 return process.returncode or (124 if timed_out else 0)

# Verify the exact private toolchain before executing any compiler/JUnit child.
for original,entry in old['staged_binaries'].items():
 if sha(Path(entry['path']))!=entry['sha256'] or sha(Path(original))!=entry['sha256']:raise RuntimeError('Dependency byte drift: '+original)
runtime_manifest=repo/'docs/release/collect-codex-goal-2026-09-30/android-attempt-archive-native-arm64-20261001/jdk-runtime-closure.json'
if sha(runtime_manifest)!=old['jdk_runtime_closure_sha256']:raise RuntimeError('JDK runtime manifest drift')
runtime=json.loads(runtime_manifest.read_text());jdk=Path(old['jdk_root'])
def runtime_readback():
 entries={str(p.relative_to(jdk)):p for p in jdk.rglob('*')}
 if set(entries)!=set(runtime):raise RuntimeError('JDK closure path drift')
 for name,entry in runtime.items():
  p=entries[name]
  if entry['kind']=='file':
   if p.is_symlink() or not p.is_file() or sha(p)!=entry['sha256'] or oct(p.stat().st_mode & 0o777)!=entry['mode']:raise RuntimeError('JDK runtime byte/mode drift')
  elif entry['kind']=='symlink':
   if not p.is_symlink() or os.readlink(p)!=entry['target'] or not p.resolve(strict=True).is_relative_to(jdk.resolve()):raise RuntimeError('JDK runtime link drift')
  elif p.is_symlink() or not p.is_dir() or oct(p.stat().st_mode & 0o777)!=entry['mode']:raise RuntimeError('JDK runtime directory drift')
runtime_readback();shutil.copyfile(runtime_manifest,run/'jdk-runtime-closure.json')
def interrupted_terminal():
 if not (run/'validation.json').exists():
  result={'status':'fail','reason':'runner_interrupted_or_exception','commands':commands,'source_sha256':inputs,'accepted':False}
  persist(run/'validation.json',result);persist(stage/'latest-proof.json',{'path':str(run),'status':'fail'})
atexit.register(interrupted_terminal)
def stop_owned(signum,frame):raise InterruptedError('Owned runner interrupted')
signal.signal(signal.SIGTERM,stop_owned)
classes=run/'classes';classes.mkdir();code=command('product',compiler+['-module-name','gateway_product','-classpath',sourcecp,'-d',str(classes)]+[str(source/base/(x+'.kt')) for x in products]+[str(p) for p in shims.glob('*.kt')])
tests=[p for p in source.rglob('*.kt') if p.stem in suites];testclasses=run/'test-classes';testclasses.mkdir()
if not code:code=command('test-compile',compiler+['-module-name','gateway_tests','-Xfriend-paths='+str(classes),'-classpath',os.pathsep.join([str(classes),sourcecp]),'-d',str(testclasses)]+[str(p) for p in tests])
test_counts={}
for suite in ['GatewayArchiveStorageTest','GatewayArchiveBackendIntegrationTest','GatewayDispatchBackendIntegrationTest','GatewayAttemptArchiveBackendTest','GatewayJournalArchiveTest','GatewaySafetyTest','GatewayDispatchWireTest','GatewayBackgroundCoordinatorTest','GatewayRetentionMigrationTest','GatewayAttemptArchiveTest']:
 if code:break
 code=command('tests-'+suite,[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'org.junit.runner.JUnitCore','app.cool.mobile.gateway.'+suite])
 match=re.findall(r'^OK \((\d+) tests\)$',(run/('tests-'+suite+'.stdout')).read_text(),re.M)
 if not code and len(match)==1:test_counts[suite]=int(match[0])
 else:code=code or 1
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),sourcecp]),'-d',str(api)]+[str(p) for p in (source/base).glob('*.kt')]+[str(config)])
runtime_readback()
changed=[p for p,h in before.items() if sha(repo/p)!=h];stagedchanged=[p for p,h in inputs.items() if sha(source/p)!=h];stagechanged=[p for p,h in inputs.items() if sha(stage/'source'/p)!=h]
result={'status':'pass' if code==0 and not changed and not stagedchanged and not stagechanged else 'fail','commands':commands,'junit_tests_passed':sum(test_counts.values()),'suite_counts':test_counts,'canonical_changes':changed,'staged_changes':stagedchanged,'staging_source_changes':stagechanged,'jdk_runtime_closure_sha256':sha(runtime_manifest),'jdk_runtime_entries':len(runtime),'native_source_count':len(list((source/base).glob('*.kt'))),'jvm_suite_count':len(test_counts),'source_sha256':inputs,'canonical_before_sha256':sha(stage/'canonical-before.json'),'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'java':java,'limitations':['Staged implementation only; canonical checkout not integrated.','Offline filesystem/backend seams; no physical device, Keystore, carrier or hosted proof.','No continuous late-conflict paging or portable export/key recovery in this slice.']}
(run/'validation.json').write_text(json.dumps(result,indent=2)+'\n');(stage/'latest-proof.json').write_text(json.dumps({'path':str(run),'status':result['status']})+'\n');print(json.dumps({'terminal':result['status'],'proof':str(run)}),flush=True)
raise SystemExit(code or bool(changed) or bool(stagedchanged) or bool(stagechanged))
