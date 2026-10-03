from pathlib import Path
import subprocess,shutil,json,hashlib,sys,time,os,datetime
s=Path(__file__).resolve().parent;r=s/'runtime';mode=sys.argv[1];out=s/'proofs'/sys.argv[2];out.mkdir(parents=True,exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name in ['lib','test']:
 for p in (s/name).rglob('*'):
  if p.is_file():d=r/p.relative_to(s);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
source={str(p.relative_to(s)):sha(p)for name in ['lib','test','integration']for p in (s/name).rglob('*')if p.is_file()}
for rel in source:
 d=out/'source-copies'/rel;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(s/rel,d)
(out/'source.json').write_text(json.dumps(source,indent=2,sort_keys=True)+'\n')
shutil.copy2(Path(__file__),out/'executed-runner.py')
paths=[p for name in ['lib','test','third_party','assets']for p in (r/name).rglob('*')if p.is_file() and not any(part in ['build','.git','.dart_tool']for part in p.relative_to(r).parts)] + [r/x for x in ['pubspec.yaml','pubspec.lock','analysis_options.yaml','.flutter-plugins-dependencies','.dart_tool/package_config.json','.dart_tool/package_graph.json']if(r/x).is_file()]
closure={str(p.relative_to(r)):{'sha256':sha(p),'resolved_path':str(p.resolve()),'symlink_target':str(p.readlink())if p.is_symlink()else None}for p in paths}
(out/'runtime-closure.json').write_text(json.dumps(closure,indent=2,sort_keys=True)+'\n')
deps=json.loads((s/'dependency-equivalence.json').read_text());dep=[]
for e in deps['entries']:
 if e['path'].endswith('/Google Chrome'):continue
 p=Path(e['path']);d={'path':str(p),'sha256':sha(p),'resolved_path':str(p.resolve()),'symlink_target':str(p.readlink())if p.is_symlink()else None};assert d['sha256']==e['sha256']and d['resolved_path']==e['resolved_path']and d['symlink_target']==e['symlink_target'];dep.append(d)
(out/'dependencies.json').write_text(json.dumps(dep,indent=2,sort_keys=True)+'\n')
flutter='/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter';tests=['test/admin_governed_settings_eligibility_test.dart','test/admin_governed_settings_eligibility_widget_test.dart']if mode=='acceptance'else['test/admin_governed_settings_eligibility_test.dart']if mode=='vm'else['test/admin_governed_settings_eligibility_widget_test.dart']
cmd=[flutter,'test','--no-pub','--concurrency=1','--reporter=expanded']+tests
if mode=='analysis':cmd=[flutter,'analyze','--no-pub']+[str(p.relative_to(r))for p in(r/'lib/admin/core').glob('admin_governed_settings*.dart')]+['lib/admin/core/admin_runtime.dart','lib/admin/core/admin_repository_base.dart','lib/admin/admin_router.dart','test/admin_governed_settings_eligibility_test.dart','test/admin_governed_settings_eligibility_widget_test.dart','test/support/settings_eligibility_fixture.dart','test/support/settings_fixture.dart']
res={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':cmd,'cwd':str(r),'mode':mode,'source_sha256':sha(out/'source.json'),'runtime_closure_sha256':sha(out/'runtime-closure.json'),'dependencies_sha256':sha(out/'dependencies.json'),'tools':{'runner':sha(out/'executed-runner.py'),'python_path':sys.executable,'python':sha(Path(sys.executable)),'flutter':sha(Path(flutter)),'dart':sha(Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart'))},'prior_runtime_scope':'current canonical lib overlay frozen in current-canonical-overlay-inputs.json with9 staged governedSettingsmodules','exit_code':None}
(out/'result.json').write_text(json.dumps(res,indent=2)+'\n')
start=time.monotonic()
with(out/'stdout.log').open('w')as stdout,(out/'stderr.log').open('w')as stderr:
 c=subprocess.run(cmd,cwd=r,stdout=stdout,stderr=stderr,timeout=180)
res.update(exit_code=c.returncode,elapsed_seconds=time.monotonic()-start,completed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),source_unchanged=all(sha(s/k)==v for k,v in source.items()),runtime_unchanged=all(sha(r/k)==v['sha256']for k,v in closure.items()),dependencies_unchanged=all(sha(Path(d['path']))==d['sha256']for d in dep))
(out/'result.json').write_text(json.dumps(res,indent=2)+'\n');print(json.dumps(res));print((out/'stdout.log').read_text()[-10000:]);print((out/'stderr.log').read_text()[-3000:]);sys.exit(c.returncode)
