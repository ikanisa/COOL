from pathlib import Path
import json,hashlib,shutil,subprocess,os,time,datetime,sys
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
label=sys.argv[1]if len(sys.argv)>1 else 'current-integration'
STAGE=ROOT/('.cache/settings-current-integration-proof-20261001-'+label)
OUT=ROOT/'docs/release/collect-codex-goal-2026-09-30/admin-governed-settings-ui-20261001'/label
FLUTTER='/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
CHROME='/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
def sha(p):
 h=hashlib.sha256()
 with Path(p).open('rb')as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def save(p,d):p.write_text(json.dumps(d,indent=2)+'\n')
assert not STAGE.exists()and not OUT.exists();STAGE.mkdir();OUT.mkdir()
runtime=STAGE/'runtime';runtime.mkdir();source={}
for n in ['lib','test','assets','third_party']:
 shutil.copytree(ROOT/n,runtime/n,ignore=shutil.ignore_patterns('build','.dart_tool','__pycache__','.git'))
 for p in (runtime/n).rglob('*'):
  if p.is_file():source[str(p.relative_to(runtime))]=sha(p)
for n in ['pubspec.yaml','pubspec.lock','analysis_options.yaml','.flutter-plugins-dependencies','AGENTS.md']:
 shutil.copy2(ROOT/n,runtime/n);source[n]=sha(runtime/n)
(runtime/'.dart_tool').mkdir()
for name in ['package_config.json','package_graph.json']:
 shutil.copy2(ROOT/'.dart_tool'/name,runtime/'.dart_tool'/name);source['.dart_tool/'+name]=sha(runtime/'.dart_tool'/name)
save(OUT/'source-before.json',source)
deps=json.loads((ROOT/'.cache/admin-governed-settings-ui-20261001/accepted-v2-baseline-current1/dependency-equivalence.json').read_text())['entries']
before={e['path']:{'sha256':sha(e['path']),'resolved_path':str(Path(e['path']).resolve()),'symlink_target':os.readlink(e['path'])if Path(e['path']).is_symlink()else None}for e in deps};save(OUT/'dependencies-before.json',before)
for path,d in before.items():
 e=next(e for e in deps if e['path']==path)
 assert d['sha256']==e['expected_sha256']or path==CHROME
 assert d['resolved_path']==e['resolved_path']and d['symlink_target']==e['symlink_target']
commands=[('sdk',[FLUTTER,'test','--no-pub','--concurrency=1','--reporter=expanded','test/admin_governed_settings_sdk_test.dart']),('widgets',[FLUTTER,'test','--no-pub','--concurrency=1','--reporter=expanded','test/admin_governed_settings_widget_test.dart']),('browser',[FLUTTER,'test','--no-pub','--platform=chrome','--concurrency=1','--reporter=expanded','test/admin_governed_settings_checkpoint_browser_test.dart']),('analysis',[FLUTTER,'analyze','--no-pub']+[str(p.relative_to(runtime))for p in sorted((runtime/'lib/admin/core').glob('admin_governed_settings*.dart'))]+['lib/admin/core/admin_runtime.dart','lib/admin/core/admin_repository_base.dart','lib/admin/core/admin_receipt_repository.dart','lib/admin/core/admin_exception_repository.dart','lib/admin/admin_router.dart','lib/admin/admin_shell.dart']+[str(p.relative_to(runtime))for p in sorted((runtime/'test').glob('admin_governed_settings*.dart'))]+['test/support/settings_fixture.dart'])]
results=[];env=os.environ.copy();env['CHROME_EXECUTABLE']=CHROME
for name,args in commands:
 begin=datetime.datetime.now(datetime.timezone.utc).isoformat();started=time.monotonic()
 with (OUT/(name+'.stdout')).open('w')as stdout,(OUT/(name+'.stderr')).open('w')as stderr:
  child=subprocess.Popen(args,cwd=runtime,env=env,stdout=stdout,stderr=stderr,start_new_session=True)
  try:code=child.wait(timeout=180)
  except subprocess.TimeoutExpired:
   import signal
   os.killpg(child.pid,signal.SIGTERM);code=child.wait(timeout=10)
   raise
 result={'name':name,'argv':args,'cwd':str(runtime),'pid':child.pid,'started_at':begin,'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'elapsed_seconds':time.monotonic()-started,'exit_code':code,'owned_child_reaped':True,'stdout_sha256':sha(OUT/(name+'.stdout')),'stderr_sha256':sha(OUT/(name+'.stderr')),'source_manifest_sha256':sha(OUT/'source-before.json')}
 results.append(result);save(OUT/(name+'.json'),result);print(name,code,flush=True)
 if code:print((OUT/(name+'.stdout')).read_text()[-5000:],flush=True);sys.exit(code)
after={e['path']:{'sha256':sha(e['path']),'resolved_path':str(Path(e['path']).resolve()),'symlink_target':os.readlink(e['path'])if Path(e['path']).is_symlink()else None}for e in deps};save(OUT/'dependencies-after.json',after);assert before==after
source_after={rel:sha(runtime/rel)for rel in source};save(OUT/'source-after.json',source_after);assert source==source_after
canonical_deltas={rel:{'proved_sha256':h,'current_sha256':sha(ROOT/rel)if(ROOT/rel).is_file()else None}for rel,h in source.items()if not(ROOT/rel).is_file()or sha(ROOT/rel)!=h};save(OUT/'canonical-deltas-after.json',canonical_deltas)
assert not canonical_deltas,canonical_deltas
save(OUT/'result.json',{'status':'passed','commands':results,'sources':len(source),'dependencies':len(before),'source_unchanged':True,'dependency_unchanged':True,'canonical_source_unchanged':True,'scope':'current rebased Settings SDK/widget/browser/analyzer; not complete Admin or release acceptance'})
print('PASS current integration',len(source),'sources',len(before),'dependencies',flush=True)
