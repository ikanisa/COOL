#!/usr/bin/env python3
"""Affected checkpoint-only acceptance after the privacy correction."""
import hashlib,json,os,shutil,sys
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
sys.path.insert(0,str(ROOT/'scripts/tests'))
import final_flutter_acceptance as F
import admin_read_gateway_gate as G
OUT=ROOT/'docs/release/rapid-completion-2026-10-01/admin-checkpoint-current2'
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-essential-admin-checkpoint-current2')
SDK=ROOT/'.cache/flutter-sdk-isolated-gateway-motion-root192'
CHANGED=['lib/admin/core/admin_exception_workflow_models.dart','lib/admin/core/admin_exception_workflow_card.dart','test/admin_exception_workflow_test.dart']
FILTER='checkpoint privacy|checkpoint recovery|a fresh negative lookup before expiry|persisted reviewed assignment|unknown response survives widget|storage failure prevents|session replacement during identity recheck'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
assert not OUT.exists() and not EXPORT.exists()
OUT.mkdir(mode=0o700);(OUT/'runner-source.py').write_bytes(Path(__file__).read_bytes())
before=F.declared_files();save(OUT/'source-before.json',before)
for name,digest in before.items():
    target=EXPORT/name;target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/name,target)
    assert sha(target)==digest and sha(ROOT/name)==digest,name
save(OUT/'source-export.json',{'export':str(EXPORT),'inputs_sha256':before})
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),PATH=str(SDK/'bin')+':'+env['PATH'])
commands=[]
def run(name,argv):
    print('START',name,flush=True);prior=dict(os.environ)
    try:
        os.environ.clear();os.environ.update(env)
        result=G.run_command(argv,EXPORT,OUT/(name+'.log'),900)
    finally:os.environ.clear();os.environ.update(prior)
    commands.append({'name':name,**result});save(OUT/'execution.json',{'commands':commands})
    print('END',name,result['exit_code'],flush=True);assert result['exit_code']==0,name
run('toolchain',[str(SDK/'bin/flutter'),'--version','--machine'])
v=json.loads((OUT/'toolchain.log').read_text())
assert v['frameworkVersion']=='3.44.4' and v['dartSdkVersion']=='3.12.2' and v['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06'
run('pub',[str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'])
assert sha(EXPORT/'pubspec.lock')==before['pubspec.lock']
run('format',[str(SDK/'bin/cache/dart-sdk/bin/dart'),'format','--output=none','--set-exit-if-changed',*CHANGED])
run('selected-analysis',[str(SDK/'bin/cache/dart-sdk/bin/dart'),'analyze','--fatal-infos',*CHANGED])
run('affected-checkpoint-tests',[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--name='+FILTER,'--file-reporter=json:'+str(OUT/'tests.machine.jsonl'),'test/admin_exception_workflow_test.dart'])
summary=G.machine_summary(OUT/'tests.machine.jsonl')
guard={name:digest for name,digest in before.items()if name.startswith(('lib/','third_party/')) or name in ['test/admin_exception_workflow_test.dart','pubspec.yaml','pubspec.lock','.fvmrc']}
drift={name:{'before':digest,'after':sha(ROOT/name)if(ROOT/name).is_file()else None}for name,digest in guard.items()if not(ROOT/name).is_file()or sha(ROOT/name)!=digest}
export_drift=[name for name,digest in before.items()if not(EXPORT/name).is_file()or sha(EXPORT/name)!=digest]
passed=not drift and not export_drift and summary['runner_completed_successfully'] and not any(summary[name]for name in ['failed','errors','unfinished','event_errors'])
save(OUT/'validation.json',{'status':'pass'if passed else'fail','commands':commands,'machine_summary':summary,'test_file':'test/admin_exception_workflow_test.dart','name_filter':FILTER,'changed_files':CHANGED,'runtime_guard_input_count':len(guard),'source_drift':drift,'export_drift':export_drift,'checkpoint_version':2,'operator_uuid_persisted':False,'legacy_actor_bearing_checkpoint_accepted':False,'sql_executed':False,'browser_builds':False,'native_builds':False,'provider_credentials_supplied':False,'scope':'New checkpoint privacy/recovery tests plus directly affected persistence, uncertain-action recovery, storage failure and current-identity step-up cases; shared confirm/list runtime root changes captured. Prior83-test packet remains captured-source evidence; this is not complete E1 acceptance.'})
print('RESULT',passed,flush=True);raise SystemExit(0 if passed else 1)
