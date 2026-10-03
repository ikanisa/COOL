from pathlib import Path
import datetime,hashlib,json,os,shutil,subprocess,sys,time
root=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');stage=Path(__file__).resolve().parent.parent;runtime=stage/'runtime';mode,attempt=sys.argv[1:3];out=stage.parent/'proof/admin'/attempt;out.mkdir(parents=True,exist_ok=False);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base=root/'.cache/receipt-successor-workflows-20261001/slice10_execution_read/runtime'
# Reuse pinned package resolution, material/fonts and current canonical source.
# Runtime inputs are copied once; subsequent scopes refresh only owned source.
if not runtime.exists():
 runtime.mkdir();(runtime/'.dart_tool').mkdir()
 for d in ['third_party','assets']:shutil.copytree(base/d,runtime/d,symlinks=True)
 for n in ['pubspec.yaml','pubspec.lock','analysis_options.yaml','.flutter-plugins-dependencies','.dart_tool/package_config.json','.dart_tool/package_graph.json']:
  src=base/n
  if src.exists():shutil.copy2(src,runtime/n)
shutil.copytree(root/'lib',runtime/'lib',dirs_exist_ok=True)
for d in ['lib','test']:shutil.copytree(stage/d,runtime/d,dirs_exist_ok=True)
canonical={str(p.relative_to(root)):sha(p)for p in(root/'lib').rglob('*.dart')}
source={str(p.relative_to(stage)):sha(p)for d in['lib','test','fixtures']for p in(stage/d).rglob('*')if p.is_file()}
for rel in source:
 dst=out/'source'/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(stage/rel,dst)
shutil.copy2(Path(__file__),out/'executed-runner.py')
closure={str(p.relative_to(runtime)):{'sha256':sha(p),'resolved_path':str(p.resolve()),'symlink_target':str(p.readlink())if p.is_symlink()else None}for d in['lib','test','assets','third_party']for p in(runtime/d).rglob('*')if p.is_file()}
for rel in['pubspec.yaml','pubspec.lock','analysis_options.yaml','.dart_tool/package_config.json','.dart_tool/package_graph.json','.flutter-plugins-dependencies']:
 p=runtime/rel
 if p.exists():closure[rel]={'sha256':sha(p),'resolved_path':str(p.resolve()),'symlink_target':None}
dep=[]
for e in json.loads((root/'.cache/admin-governed-settings-ui-20261001/dependency-equivalence.json').read_text())['entries']:
 p=Path(e['path'])
 if '/Google Chrome Framework.framework/Versions/'in str(p):p=Path('/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/Current/Google Chrome Framework').resolve()
 dep.append({'path':str(p),'sha256':sha(p),'resolved_path':str(p.resolve()),'symlink_target':str(p.readlink())if p.is_symlink()else None})
for n,v in [('source.json',source),('runtime-closure.json',closure),('canonical.json',canonical),('dependencies.json',dep)]: (out/n).write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
flutter='/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter';tests=['test/admin_sender_retention_models_test.dart','test/admin_sender_retention_controller_test.dart','test/admin_sender_retention_view_test.dart'];cmd=[flutter,'test','--no-pub','--concurrency=1','--reporter=expanded']+tests
if mode=='widget':cmd=[flutter,'test','--no-pub','--concurrency=1','--reporter=expanded','test/admin_sender_retention_view_test.dart']
if mode=='analysis':cmd=[flutter,'analyze','--no-pub']+[str(p.relative_to(runtime))for p in(runtime/'lib/admin/core').glob('admin_sender*.dart')]+[str(p.relative_to(runtime))for p in(runtime/'test').rglob('*.dart')]
if mode=='browser':cmd=[flutter,'test','--no-pub','--platform=chrome','--concurrency=1','--reporter=expanded','test/admin_sender_retention_models_test.dart','test/admin_sender_retention_browser_test.dart']
if mode=='browser_store':cmd=[flutter,'test','--no-pub','--platform=chrome','--concurrency=1','--reporter=expanded','test/admin_sender_retention_browser_test.dart']
if mode=='analysis_store':cmd=[flutter,'analyze','--no-pub','lib/admin/core/admin_sender_retention_checkpoint_web.dart','test/admin_sender_retention_browser_test.dart']
if mode=='vm_contract':cmd=[flutter,'test','--no-pub','--concurrency=1','--reporter=expanded','test/admin_sender_retention_models_test.dart','test/admin_sender_retention_controller_test.dart']
if mode=='analysis_contract':cmd=[flutter,'analyze','--no-pub','lib/admin/core/admin_sender_retention_models.dart','lib/admin/core/admin_sender_retention_sdk.dart','lib/admin/core/admin_sender_retention_controller.dart','test/admin_sender_retention_models_test.dart','test/admin_sender_retention_controller_test.dart']
env=os.environ.copy();env['CHROME_EXECUTABLE']='/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
result=dict(started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),mode=mode,command=cmd,cwd=str(runtime),source_sha256=sha(out/'source.json'),closure_sha256=sha(out/'runtime-closure.json'),dependencies_sha256=sha(out/'dependencies.json'),canonical_sha256=sha(out/'canonical.json'),tools={'runner':sha(out/'executed-runner.py'),'python':sha(Path(sys.executable)),'flutter':sha(Path(flutter)),'dart':sha(Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart'))},exit_code=None)
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
with(out/'stdout.log').open('w')as stdout,(out/'stderr.log').open('w')as stderr:c=subprocess.run(cmd,cwd=runtime,stdout=stdout,stderr=stderr,env=env,timeout=240)
result.update(exit_code=c.returncode,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),source_unchanged=all(sha(stage/p)==v for p,v in source.items()),runtime_unchanged=all(sha(runtime/p)==v['sha256']and str((runtime/p).resolve())==v['resolved_path']for p,v in closure.items()),canonical_unchanged=all(sha(root/p)==v for p,v in canonical.items()),dependencies_unchanged=all(sha(Path(v['path']))==v['sha256']and str(Path(v['path']).resolve())==v['resolved_path']for v in dep))
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));print((out/'stdout.log').read_text()[-8000:]);print((out/'stderr.log').read_text()[-3500:]);sys.exit(c.returncode)
