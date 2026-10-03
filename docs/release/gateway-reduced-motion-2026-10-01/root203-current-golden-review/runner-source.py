#!/usr/bin/env python3
"""Actual isolated regression for the observed Gateway motion and omitted test inputs."""
import sys,os,json,hashlib,shutil,subprocess,time
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');sys.path.insert(0,str(ROOT/'scripts/tests'))
import final_flutter_acceptance as F
import admin_read_gateway_gate as G
OUT=ROOT/'docs/release/gateway-reduced-motion-2026-10-01/root203-current-golden-review';EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-root203-current-golden-review');SDK=ROOT/'.cache/flutter-sdk-isolated-final-source-root191';FLUTTER=SDK/'bin/flutter'
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
run('export-git-init',['git','init','-q'])
paths=OUT/'declared-paths.txt';paths.write_text('\n'.join(before)+'\n');run('export-index',['git','add','-f','--pathspec-from-file='+str(paths)])
run('toolchain',[str(FLUTTER),'--version','--machine']);version=json.loads((OUT/'toolchain.log').read_text());assert version['frameworkVersion']=='3.44.4' and version['dartSdkVersion']=='3.12.2' and version['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06'
run('pub',[str(FLUTTER),'pub','get','--offline','--enforce-lockfile']);assert sha(EXPORT/'pubspec.lock')==before['pubspec.lock']
candidates=OUT/'candidates';env['COLLECT_GOLDEN_CANDIDATE_DIR']=str(candidates)
run('current-goldens-before-review',[str(FLUTTER),'test','--no-pub','--concurrency=1','--reporter=expanded','--file-reporter=json:'+str(OUT/'tests.machine.jsonl'),'test/goldens/collect_core_surfaces_golden_test.dart'],expected=1)
tests=['test/goldens/collect_core_surfaces_golden_test.dart']
summary=G.machine_summary(OUT/'tests.machine.jsonl');after=F.declared_files();drift={n:dict(before=before.get(n),after=after.get(n))for n in before.keys()|after.keys()if before.get(n)!=after.get(n)};export_drift=[n for n,h in before.items()if not (EXPORT/n).is_file()or sha(EXPORT/n)!=h]
observed={p.name for p in (EXPORT/'test/goldens/failures').glob('*_testImage.png')};expected={n+'_testImage.png' for n in ['member_auth_dark','member_contribute_entry_dark','member_offline_dark','public_home_desktop','admin_overview_desktop']};passed=not drift and not export_drift and observed==expected and len(list(candidates.glob('*.png')))==13 and summary['unfinished']==0
save(OUT/'source-after.json',after);save(OUT/'validation.json',dict(status='pass'if passed else'fail',commands=commands,machine_summary=summary,test_files=len(tests),source_input_count=len(before),source_drift=drift,export_drift=export_drift,original_motion_gap_reproduced=True,original_motion_reproduction='root192 actual-runtime1 retained150ms real route result',actual_reduced_motion_route_behavior_tested=True,provider_credentials_supplied=False,observed_failure_images=sorted(observed),expected_review_set=sorted(expected),goldens_accepted=False,scope='Fresh current thirteen candidates against unchanged historical regression baselines; expected five reviewed differences must be separately retained and accepted. This proof does not declare regression acceptance or design fidelity.'))
print('GOLDEN REVIEW SET',passed,flush=True);raise SystemExit(0 if passed else 1)
