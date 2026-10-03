from pathlib import Path
import subprocess,shutil,json,hashlib,sys,time,os
stage=Path(__file__).resolve().parent;runtime=stage/'runtime';label=sys.argv[1];out=stage/'proofs'/label;out.mkdir(parents=True,exist_ok=False)
for name in ['lib','test']:
 for p in (stage/name).rglob('*'):
  if p.is_file():target=runtime/p.relative_to(stage);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
source={str(p.relative_to(stage)):hashlib.sha256(p.read_bytes()).hexdigest()for name in ['lib','test','integration']for p in (stage/name).rglob('*')if p.is_file()};
for rel in source:
 target=out/'source-copies'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(stage/rel,target)
(out/'source.json').write_text(json.dumps(source,indent=2)+'\n')
flutter='/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
mode=sys.argv[2]if len(sys.argv)>2 else 'tests';command=[flutter,'test','--no-pub','--concurrency=1','--reporter=expanded','test/admin_governed_settings_models_test.dart','test/admin_governed_settings_controller_test.dart','test/admin_governed_settings_sdk_test.dart']if mode=='tests' else [flutter,'analyze','--no-pub','lib/admin/core/admin_governed_settings_models.dart','lib/admin/core/admin_governed_settings_sdk.dart','lib/admin/core/admin_governed_settings_checkpoint.dart','lib/admin/core/admin_governed_settings_checkpoint_web.dart','lib/admin/core/admin_governed_settings_controller.dart','lib/admin/core/admin_runtime.dart','lib/admin/admin_router.dart','test/admin_governed_settings_models_test.dart','test/admin_governed_settings_controller_test.dart','test/admin_governed_settings_sdk_test.dart']
if mode=='analyze':command=[flutter,'analyze','--no-pub']+[str(p.relative_to(runtime))for p in (runtime/'lib/admin/core').glob('admin_governed_settings*.dart')]+['lib/admin/core/admin_runtime.dart','lib/admin/core/admin_repository_base.dart','lib/admin/admin_router.dart']+[str(p.relative_to(runtime))for p in (runtime/'test').glob('admin_governed_settings*.dart')]+['test/support/settings_fixture.dart']
if mode=='widgets':command=[flutter,'test','--no-pub','--concurrency=1','--reporter=expanded','test/admin_governed_settings_widget_test.dart']
env=os.environ.copy()
if mode=='browser':
 command=[flutter,'test','--no-pub','--platform=chrome','--concurrency=1','--reporter=expanded','test/admin_governed_settings_checkpoint_browser_test.dart'];env['CHROME_EXECUTABLE']='/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
start=time.monotonic();r=subprocess.run(command,cwd=runtime,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180);(out/'output.log').write_text(r.stdout);result={'command':command,'cwd':str(runtime),'exit_code':r.returncode,'elapsed_seconds':time.monotonic()-start,'source_sha256':hashlib.sha256((out/'source.json').read_bytes()).hexdigest()};(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));print(r.stdout[-6000:]);sys.exit(r.returncode)
