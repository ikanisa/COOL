from pathlib import Path
import json, hashlib, os, shutil, subprocess, time, re
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
base=Path('android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway');suites=['GatewayAttemptArchiveTest','GatewayAttemptArchiveBackendTest','GatewayJournalArchiveTest','GatewayArchiveStorageTest','GatewaySafetyTest','GatewayDispatchBackendIntegrationTest','GatewayArchiveBackendIntegrationTest','GatewayDispatchWireTest','GatewayBackgroundCoordinatorTest']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs={str(p.relative_to(source)):sha(p) for p in source.rglob('*') if p.is_file()};before=json.loads((stage/'canonical-before.json').read_text());commands=[]
def command(name,args):
 t=time.monotonic();out=run/(name+'.stdout');err=run/(name+'.stderr');print(json.dumps({'stage':name,'running':True,'proof':str(run)}),flush=True)
 with out.open('wb') as o,err.open('wb') as e:
  result=subprocess.run(args,stdout=o,stderr=e,cwd=run,env={'PATH':os.defpath,'HOME':str(private),'TMPDIR':str(run),'LANG':'C.UTF-8'},timeout=480,start_new_session=True)
 commands.append({'name':name,'argv':args,'exit_code':result.returncode,'wall_seconds':time.monotonic()-t,'stdout_sha256':sha(out),'stderr_sha256':sha(err)})
 print(json.dumps({k:v for k,v in commands[-1].items() if k != 'argv'}),flush=True)
 return result.returncode
classes=run/'classes';classes.mkdir();code=command('product',compiler+['-module-name','gateway_product','-classpath',sourcecp,'-d',str(classes)]+[str(source/base/(x+'.kt')) for x in products]+[str(p) for p in shims.glob('*.kt')])
tests=[p for p in source.rglob('*.kt') if p.stem in suites];testclasses=run/'test-classes';testclasses.mkdir()
if not code:code=command('test-compile',compiler+['-module-name','gateway_tests','-Xfriend-paths='+str(classes),'-classpath',os.pathsep.join([str(classes),sourcecp]),'-d',str(testclasses)]+[str(p) for p in tests])
test_counts={}
for suite in ['GatewayArchiveStorageTest','GatewayArchiveBackendIntegrationTest','GatewayDispatchBackendIntegrationTest','GatewayAttemptArchiveBackendTest','GatewayJournalArchiveTest','GatewaySafetyTest','GatewayDispatchWireTest','GatewayBackgroundCoordinatorTest','GatewayAttemptArchiveTest']:
 if code:break
 code=command('tests-'+suite,[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'org.junit.runner.JUnitCore','app.cool.mobile.gateway.'+suite])
 match=re.findall(r'^OK \((\d+) tests\)$',(run/('tests-'+suite+'.stdout')).read_text(),re.M)
 if not code and len(match)==1:test_counts[suite]=int(match[0])
 else:code=code or 1
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),sourcecp]),'-d',str(api)]+[str(p) for p in (source/base).glob('*.kt')]+[str(config)])
changed=[p for p,h in before.items() if sha(repo/p)!=h];stagedchanged=[p for p,h in inputs.items() if sha(source/p)!=h]
result={'status':'pass' if code==0 and not changed and not stagedchanged else 'fail','commands':commands,'junit_tests_passed':sum(test_counts.values()),'suite_counts':test_counts,'canonical_changes':changed,'staged_changes':stagedchanged,'source_sha256':inputs,'canonical_before_sha256':sha(stage/'canonical-before.json'),'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'java':java,'limitations':['Staged implementation only; canonical checkout not integrated.','Offline filesystem/backend seams; no physical device, Keystore, carrier or hosted proof.','No continuous late-conflict paging or portable export/key recovery in this slice.']}
(run/'validation.json').write_text(json.dumps(result,indent=2)+'\n');(stage/'latest-proof.json').write_text(json.dumps({'path':str(run),'status':result['status']})+'\n');print(json.dumps({'terminal':result['status'],'proof':str(run)}),flush=True)
raise SystemExit(code or bool(changed) or bool(stagedchanged))
