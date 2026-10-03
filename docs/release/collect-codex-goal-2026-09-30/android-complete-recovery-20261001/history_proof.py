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
base_run=stage/'proof-workspace/attempt-6';base_result=json.loads((base_run/'validation.json').read_text())
if base_result['status']!='pass':raise RuntimeError('Preceding recovery proof not accepted')
consumer='scripts/tests/android_gateway_attempt_archive_jvm.py'
for name,digest in base_result['source_sha256'].items():
 if name!=consumer and sha(source/name)!=digest:raise RuntimeError('Unchanged proven input drift '+name)
 if sha(base_run/'source'/name)!=digest:raise RuntimeError('Preceding source drift '+name)
artifacts={str(p.relative_to(base_run)):sha(p) for folder in ('classes','test-classes','runner-classes','api-classes') for p in (base_run/folder).rglob('*') if p.is_file()}
for name,digest in artifacts.items():
 if sha(base_run/name)!=digest:raise RuntimeError('Preceding artifact drift')
# Exact current API/product inputs and terminal receipts remain unchanged.
for receipt in base_result['commands']:
 if receipt['status']!='terminal' or receipt['exit_code']!=0 or not receipt['owned_child_reaped']:raise RuntimeError('Nonterminal preceding command')
 if sha(base_run/(receipt['name']+'.stdout'))!=receipt['stdout_sha256'] or sha(base_run/(receipt['name']+'.stderr'))!=receipt['stderr_sha256']:raise RuntimeError('Terminal output drift')
import ast
old_ast=ast.parse((base_run/'source'/consumer).read_text());new_ast=ast.parse((source/consumer).read_text())
class RemoveAdded(ast.NodeTransformer):
 def visit_List(self,node):node.elts=[x for x in node.elts if not(isinstance(x,ast.Constant) and x.value in {'GatewayRecoveryTest','GatewayRecoveryHistoryTest'})];return self.generic_visit(node)
 def visit_Tuple(self,node):node.elts=[x for x in node.elts if not(isinstance(x,ast.Constant) and x.value=='GatewayRecovery')];return self.generic_visit(node)
if ast.dump(old_ast,include_attributes=False)!=ast.dump(RemoveAdded().visit(new_ast),include_attributes=False):raise RuntimeError('Unexpected consumer delta')
persist(run/'composed-source-association.json',{'base_validation_sha256':sha(base_run/'validation.json'),'base_commands':base_result['commands'],'source_sha256':base_result['source_sha256'],'compiled_artifacts':artifacts,'current_all25_native_API_inputs_unchanged':True,'consumer_ast_delta':'exact two suite additions in full/focus + GatewayRecovery product addition','new_history_test': 'GatewayRecoveryHistoryTest','preceding_cases_reused':base_result['junit_tests_passed']})
classes=run/'classes';testclasses=run/'test-classes';runnerclasses=run/'runner-classes';api=run/'api-classes'
for folder in ('classes','test-classes','runner-classes','api-classes'):shutil.copytree(base_run/folder,run/folder)
newtest=source/'android/app/src/testInternal_gateway_archiveJvm/kotlin/app/cool/mobile/gateway/GatewayRecoveryHistoryTest.kt'
code=command('history-test-compile',compiler+['-module-name','gateway_tests','-Xfriend-paths='+str(classes)+','+str(testclasses),'-classpath',os.pathsep.join([str(classes),str(testclasses),sourcecp]),'-d',str(testclasses),str(newtest)])
counts=dict(base_result['suite_counts']);cases=[dict(x,provenance='terminal unchanged attempt-6 exact source/artifact/runtime binding') for x in base_result['case_results']]
if not code:
 name='tests-GatewayRecoveryHistoryTest';code=command(name,[java,'-ea','-Xmx512m','-cp',os.pathsep.join([str(classes),str(testclasses),str(runnerclasses),sourcecp]),'CurrentCasesKt','app.cool.mobile.gateway.GatewayRecoveryHistoryTest'])
 output=(run/(name+'.stdout')).read_text();passed=re.findall(r'^CASE (\S+) PASS$',output,re.M);failed=re.findall(r'^CASE (\S+) FAIL$',output,re.M);summary=re.findall(r'^OK \((\d+) tests\)$',output,re.M)
 cases.extend({'method':m,'status':'pass','command':name} for m in passed);cases.extend({'method':m,'status':'fail','command':name} for m in failed)
 if not code and len(summary)==1 and len(passed)==int(summary[0]) and not failed:counts['GatewayRecoveryHistoryTest']=int(summary[0])
 else:code=code or 1
runtime_readback();changes={'copied':[p for p,h in inputs.items() if sha(source/p)!=h],'stage':[p for p,h in inputs.items() if sha(stage/'source'/p)!=h],'canonical':[p for p,h in base['source_sha256'].items() if sha(repo/p)!=h]}
result={'status':'pass' if not code and not any(changes.values()) else 'fail','commands':commands,'suite_counts':counts,'case_results':cases,'junit_tests_passed':sum(counts.values()),'source_sha256':inputs,'source_changes':changes,'shim_sha256':{p.name:sha(p) for p in shims.glob('*.kt')},'binary_sha256':old['binary_sha256'],'jdk_runtime_closure_sha256':sha(runtime_manifest),'jdk_runtime_entries':len(runtime),'native_source_count':25,'java':java,'composed_source_association_sha256':sha(run/'composed-source-association.json'),'all25_native_api_compilation_reused_exact_inputs':True,'limitations':base_result['limitations']+['36 current cases and all25-native API compilation reused from terminal attempt-6 through unchanged full source/runtime/artifact binding; only 3 added history cases run in extension.']}
persist(run/'validation.json',result);persist(stage/'latest-proof.json',{'path':str(run),'status':result['status']});print(json.dumps({'terminal':result['status'],'proof':str(run),'tests':result['junit_tests_passed']}),flush=True)
raise SystemExit(code or any(changes.values()))
