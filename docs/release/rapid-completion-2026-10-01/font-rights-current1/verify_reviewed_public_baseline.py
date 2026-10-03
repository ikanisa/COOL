#!/usr/bin/env python3
"""Replay only the reviewed public golden and its exact manifest consistency."""
import hashlib,json,os,shutil,sys
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');sys.path.insert(0,str(ROOT/'scripts/tests'))
import admin_read_gateway_gate as G
OUT=Path(__file__).resolve().parent;EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-font-rights-current1');SDK=ROOT/'.cache/flutter-sdk-isolated-gateway-motion-root192'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
baseline='test/goldens/baselines/public_home_desktop.png';manifest='test/goldens/GOLDEN_MANIFEST.sha256'
expected='42cdb1152ed2f6b392d2eb465cc7ada88de1b6e54eaa796fe757137a4636bbf4'
assert sha(ROOT/baseline)==expected==sha(OUT/'golden-candidate/public_home_desktop.png')
changed={n:sha(ROOT/n)for n in [baseline,manifest]}
for name,digest in changed.items():
    shutil.copy2(ROOT/name,EXPORT/name);assert sha(EXPORT/name)==digest and sha(ROOT/name)==digest
before=json.loads((OUT/'changed-and-direct-consumed-inputs-before.json').read_text())
assert all(sha(ROOT/n)==h for n,h in before.items())
save(OUT/'reviewed-public-overlay.json',{'inputs_sha256':changed,'candidate_identical':True,'only_two_publication_files_overlaid':True,'other_twelve_baselines_not_changed':True})
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),PATH=str(SDK/'bin')+':'+env['PATH'])
argv=[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--name=historical golden manifest covers every baseline exactly|public website compares historical desktop baseline','--file-reporter=json:'+str(OUT/'reviewed-public.machine.jsonl'),'test/goldens/collect_core_surfaces_golden_test.dart']
print('START reviewed-public-and-manifest-only',flush=True);old=dict(os.environ)
try:
    os.environ.clear();os.environ.update(env);r=G.run_command(argv,EXPORT,OUT/'reviewed-public-and-manifest-only.log',600)
finally:os.environ.clear();os.environ.update(old)
save(OUT/'reviewed-public-execution.json',r);print('END reviewed-public-and-manifest-only',r['exit_code'],flush=True)
summary=G.machine_summary(OUT/'reviewed-public.machine.jsonl')
guard={**before,**changed}
source_drift={n:{'before':h,'after':sha(ROOT/n)if(ROOT/n).is_file()else None}for n,h in guard.items()if not(ROOT/n).is_file()or sha(ROOT/n)!=h}
export_drift={n:{'before':h,'after':sha(EXPORT/n)if(EXPORT/n).is_file()else None}for n,h in guard.items()if not(EXPORT/n).is_file()or sha(EXPORT/n)!=h}
passed=r['exit_code']==0 and summary['runner_completed_successfully'] and summary['passed']==2 and not any(summary[n]for n in ['failed','errors','unfinished','event_errors'])and not source_drift and not export_drift
save(OUT/'final-validation.json',{'status':'pass'if passed else'fail','machine_summary':summary,'command':r,'publication_sha256':changed,'public_candidate_sha256':expected,'precision_tolerance':0.0005,'source_drift':source_drift,'export_drift':export_drift,'prior_packet_sha256':sha(OUT/'validation.json'),'original_public_mismatch_preserved':True,'root_visual_review':'public-golden-review.json','other_twelve_goldens_not_executed':True,'no_other_tests_or_builds_executed':True,'scope':'Only reviewed actual Inter public golden and complete13-file manifest integrity. Earlier landing8/single-font1/Ruby case results are retained; no complete surface/native comparator or release-binary font package claim.'})
print('RESULT',passed,flush=True);raise SystemExit(0 if passed else 1)
