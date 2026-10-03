#!/usr/bin/env python3
"""Actual isolated regression for the observed Gateway motion and omitted test inputs."""
import sys,os,json,hashlib,shutil,subprocess,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');sys.path.insert(0,str(ROOT/'scripts/tests'))
import final_flutter_acceptance as F
import admin_read_gateway_gate as G
OUT=ROOT/'docs/release/gateway-reduced-motion-2026-10-01/root192-correction/actual-runtime1';EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-root192-motion');SDK=ROOT/'.cache/flutter-sdk-isolated-gateway-motion-root192';FLUTTER=SDK/'bin/flutter'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
assert not OUT.exists() and not EXPORT.exists();OUT.mkdir(mode=0o700);(OUT/'runner-source.py').write_bytes(Path(__file__).read_bytes());before=F.declared_files();save(OUT/'source-before.json',before)
for n,h in before.items():
 target=EXPORT/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,target);assert sha(target)==h and sha(ROOT/n)==h,n
save(OUT/'source-export.json',dict(export=str(EXPORT),inputs_sha256=before))
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}};env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),PATH=str(SDK/'bin')+':'+env['PATH'])
commands=[]
def run(name,argv,expected=0):
 print('START',name,flush=True)
 previous=dict(os.environ)
 try:
  os.environ.clear();os.environ.update(env);r=G.run_command(argv,EXPORT,OUT/(name+'.log'),1200)
 finally:os.environ.clear();os.environ.update(previous)
 commands.append(dict(name=name,expected_exit=expected,**r));save(OUT/'execution.json',dict(status='running',commands=commands));print('END',name,r['exit_code'],flush=True);assert r['exit_code']==expected,name
run('toolchain',[str(FLUTTER),'--version','--machine']);version=json.loads((OUT/'toolchain.log').read_text());assert version['frameworkVersion']=='3.44.4' and version['dartSdkVersion']=='3.12.2' and version['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06'
run('pub',[str(FLUTTER),'pub','get','--offline','--enforce-lockfile']);assert sha(EXPORT/'pubspec.lock')==before['pubspec.lock']
run('format-changed',[str(SDK/'bin/cache/dart-sdk/bin/dart'),'format','--output=none','--set-exit-if-changed','lib/gateway/gateway_app.dart','test/gateway/gateway_enrollment_lifecycle_test.dart'])
corrected=(EXPORT/'lib/gateway/gateway_app.dart').read_bytes();original=OUT.parent/'gateway_app.before.dart';(EXPORT/'lib/gateway/gateway_app.dart').write_bytes(original.read_bytes())
try:run('original-motion-reproduction',[str(FLUTTER),'test','--no-pub','--reporter=expanded','--plain-name=reduced motion removes both real enrollment route transitions','test/gateway/gateway_enrollment_lifecycle_test.dart'],expected=1)
finally:(EXPORT/'lib/gateway/gateway_app.dart').write_bytes(corrected)
assert 'Actual: <0:00:00.150000>' in (OUT/'original-motion-reproduction.log').read_text() or 'Actual: <0:00:00.200000>' in (OUT/'original-motion-reproduction.log').read_text()
run('fatal-analysis',[str(FLUTTER),'analyze','--no-pub','--fatal-infos','--fatal-warnings'])
tests=['test/app_shell_test.dart','test/security_hygiene_test.dart','test/release_docs_test.dart','test/features/runtime_component_contract_test.dart','test/admin_receipt_content_v2_test.dart']+sorted(str(p.relative_to(EXPORT))for p in (EXPORT/'test/gateway').glob('*_test.dart'))
save(OUT/'test-selection.json',tests)
run('changed-and-omitted-regressions',[str(FLUTTER),'test','--no-pub','--concurrency=2','--reporter=expanded','--file-reporter=json:'+str(OUT/'tests.machine.jsonl'),*tests])
summary=G.machine_summary(OUT/'tests.machine.jsonl');after=F.declared_files();drift={n:dict(before=before.get(n),after=after.get(n))for n in before.keys()|after.keys()if before.get(n)!=after.get(n)};export_drift=[n for n,h in before.items()if not (EXPORT/n).is_file()or sha(EXPORT/n)!=h]
passed=not drift and not export_drift and summary['runner_completed_successfully'] and not any(summary[n]for n in ['failed','errors','unfinished','event_errors'])
save(OUT/'source-after.json',after);save(OUT/'validation.json',dict(status='pass'if passed else'fail',commands=commands,machine_summary=summary,test_files=len(tests),source_input_count=len(before),source_drift=drift,export_drift=export_drift,original_motion_gap_reproduced=True,actual_reduced_motion_route_behavior_tested=True,provider_credentials_supplied=False,scope='Full affected app-shell/security/release/runtime contract files, all Gateway files and new peer receipt decoder file; isolated declared current source. Native Gateway compilation and complete current browser/native release acceptance remain separate.'))
print('RESULT',passed,flush=True);raise SystemExit(0 if passed else 1)
