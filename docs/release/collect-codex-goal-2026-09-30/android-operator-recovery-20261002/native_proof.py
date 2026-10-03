from pathlib import Path
import json,hashlib,subprocess,os,time,shutil,re,signal
r=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');s=r/'.cache/android-recovery-operator-workflow-20261001';p=r/'.cache/android-complete-recovery-20261001/accepted-packet';run=s/('native-attempt-'+str(len(list(s.glob('native-attempt-*')))+1));run.mkdir()
sha=lambda x:hashlib.sha256(Path(x).read_bytes()).hexdigest()
old=json.loads(Path('/Users/jeanbosco/.cache/collect-android-native-proof-20261001/staging.json').read_text());v=json.loads((p/'validation.json').read_text());base=json.loads((s/'baseline.json').read_text());art=json.loads((p/'compiled-artifacts.json').read_text())
assert v['status']=='pass' and sha(p/'MANIFEST.json')==base['accepted_core_manifest_sha256']
for item in art.values():assert sha(item['path'])==item['sha256']
for orig,item in old['staged_binaries'].items():assert sha(orig)==item['sha256'] and sha(item['path'])==item['sha256']
jdk=Path(old['jdk_root']);closure=json.loads((p/'jdk-runtime-closure.json').read_text())
for name,item in closure.items():
 x=jdk/name
 if item['kind']=='file':assert not x.is_symlink() and sha(x)==item['sha256'] and oct(x.stat().st_mode&0o777)==item['mode']
 elif item['kind']=='symlink':assert x.is_symlink() and os.readlink(x)==item['target']
 else:assert x.is_dir() and not x.is_symlink() and oct(x.stat().st_mode&0o777)==item['mode']
source=run/'source';shutil.copytree(s/'source',source)
inputs={str(x.relative_to(source)):sha(x) for x in (source/'android').rglob('*') if x.is_file()};(run/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
core=Path(art['classes/META-INF/gateway_product.kotlin_module']['path']).parents[1];testcore=next(Path(x['path']).parents[len(Path(k).parts)-2] for k,x in art.items() if k.startswith('test-classes/') and k.endswith('GatewayLateFixture.class'))
runnercore=next(Path(x['path']).parent for k,x in art.items() if k=='runner-classes/CurrentCasesKt.class')
bins=[Path(x['path']) for x in old['staged_binaries'].values()];deps=bins[:9];java=old['java'];cp=os.pathsep.join(str(deps[i]) for i in (1,4,6,7,8));compiler=[java,'-Xmx1g','-XX:ActiveProcessorCount=2','-cp',os.pathsep.join(map(str,deps)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17'];commands=[]
def command(name,args):
 out=run/(name+'.stdout');err=run/(name+'.stderr');entry={'name':name,'argv':args,'status':'running'};commands.append(entry);(run/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');print(name,flush=True)
 with out.open('wb') as o,err.open('wb') as e:
  proc=subprocess.Popen(args,stdout=o,stderr=e,cwd=run,env={'PATH':os.defpath,'HOME':str(run),'LANG':'C.UTF-8'},start_new_session=True);entry['pid']=proc.pid;start=time.monotonic()
  try:proc.wait(timeout=600)
  except BaseException:
   os.killpg(proc.pid,signal.SIGKILL);proc.wait();raise
 entry.update(status='terminal',exit_code=proc.returncode,owned_child_reaped=True,wall_seconds=time.monotonic()-start,stdout_sha256=sha(out),stderr_sha256=sha(err));(run/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');print(name,proc.returncode,flush=True);return proc.returncode
b=Path('android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway');tb=Path('android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway');new=run/'classes';new.mkdir();tests=run/'test-classes';tests.mkdir()
prior=None
if '--api-only' in __import__('sys').argv:
 prior=json.loads((s/'native-attempt-1/validation.json').read_text())
 for name in ['transfer-compile','test-compile','transfer-tests']:
  c=next(x for x in prior['commands'] if x['name']==name);assert c['exit_code']==0 and c['owned_child_reaped']
  assert sha(s/'native-attempt-1'/(name+'.stdout'))==c['stdout_sha256'] and sha(s/'native-attempt-1'/(name+'.stderr'))==c['stderr_sha256']
 for name,value in prior['source_sha256'].items():
  if name.startswith('android/') and not name.endswith('GatewayRecoveryOperator.kt'):assert sha(source/name)==value
 code=0
else:
 code=command('transfer-compile',compiler+['-module-name','gateway_transfer','-Xfriend-paths='+str(core),'-classpath',str(core)+os.pathsep+cp,'-d',str(new),str(source/b/'GatewayRecoveryTransfer.kt'),str(source/b/'GatewayRecoveryPause.kt'),str(source/b/'GatewayRecoveryAdmission.kt')])
 if not code:code=command('test-compile',compiler+['-module-name','gateway_transfer_tests','-Xfriend-paths='+','.join(map(str,[core,new,testcore])),'-classpath',os.pathsep.join([str(core),str(new),str(testcore),cp]),'-d',str(tests),str(source/tb/'GatewayRecoveryTransferTest.kt')])
 if not code:code=command('transfer-tests',[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(core),str(new),str(testcore),str(tests),str(runnercore),cp]),'CurrentCasesKt','app.cool.mobile.gateway.GatewayRecoveryTransferTest'])
if not code:
 api=run/'api-classes';api.mkdir();config=run/'BuildConfig.kt';config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
 code=command('android36-api',compiler+['-classpath',os.pathsep.join([str(bins[9]),str(bins[11]),str(bins[12]),cp]),'-d',str(api)]+[str(x) for x in (source/b).glob('*.kt')]+[str(config)])
changes=[name for name,value in inputs.items() if sha(source/name)!=value or sha(s/'source'/name)!=value]
cases=prior['fresh_cases'] if prior else []
if (run/'transfer-tests.stdout').exists():cases=re.findall(r'^CASE (\S+) PASS$',(run/'transfer-tests.stdout').read_text(),re.M)
result={'status':'pass' if not code and len(cases)==11 and not changes else 'fail','commands':commands,'reused_focused_test_proof':str(s/'native-attempt-1/validation.json') if prior else None,'reused_focused_test_proof_sha256':sha(s/'native-attempt-1/validation.json') if prior else None,'fresh_cases':cases,'fresh_case_count':len(cases),'native_api_source_count':len(list((source/b).glob('*.kt'))),'source_sha256':inputs,'source_changes':changes,'accepted_core_manifest_sha256':sha(p/'MANIFEST.json'),'reused_compiled_artifacts_sha256':sha(p/'compiled-artifacts.json'),'verified_reused_artifact_count':len(art),'binary_sha256':old['binary_sha256'],'jdk_runtime_closure_sha256':sha(p/'jdk-runtime-closure.json'),'jdk_runtime_entries':len(closure),'limitations':['Same-key offline JVM crypto and API compile; no physical device, SAF provider durability, Keystore or Gradle/signing qualification.','Core accepted40 cases are not repeated or counted; unchanged source-bound compiled fixture/core/runner artifacts reused.']}
(run/'validation.json').write_text(json.dumps(result,indent=2)+'\n');(s/'native-latest.json').write_text(json.dumps({'path':str(run),'status':result['status']})+'\n');print(json.dumps({'terminal':result['status'],'path':str(run),'fresh_cases':len(cases)}),flush=True)
raise SystemExit(0 if result['status']=='pass' else 1)
