#!/usr/bin/env python3
"""Finish the missing Ruby fixture and capture only the affected public golden."""
import hashlib,json,os,shutil,sys
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');sys.path.insert(0,str(ROOT/'scripts/tests'))
import admin_read_gateway_gate as G
OUT=Path(__file__).resolve().parent;EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-font-rights-current1');SDK=ROOT/'.cache/flutter-sdk-isolated-gateway-motion-root192'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
before=json.loads((OUT/'changed-and-direct-consumed-inputs-before.json').read_text())
binding=json.loads((OUT/'export-overlay.json').read_text())['consumed_export_sha256']
fixture='docs/release/public-website-content-baseline.json'
assert sha(ROOT/fixture)==before[fixture] and not(EXPORT/fixture).exists()
(EXPORT/fixture).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/fixture,EXPORT/fixture)
assert sha(EXPORT/fixture)==before[fixture]
binding[fixture]=before[fixture]
save(OUT/'fixture-binding.json',{'path':fixture,'root_sha256':before[fixture],'export_sha256':sha(EXPORT/fixture),'original_failure':'single-static-source-route-case.log','correction':'Copied only the missing named historical fixture; passing Flutter/font/syntax checks are not repeated.'})
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),PATH=str(SDK/'bin')+':'+env['PATH'])
commands=[]
def run(name,argv,expected):
    print('START',name,flush=True);old=dict(os.environ)
    try:
        os.environ.clear();os.environ.update(env);r=G.run_command(argv,EXPORT,OUT/(name+'.log'),600)
    finally:os.environ.clear();os.environ.update(old)
    commands.append({'name':name,'expected_exit':expected,**r});save(OUT/'completion-execution.json',{'commands':commands})
    print('END',name,r['exit_code'],flush=True);assert r['exit_code']==expected,name
run('single-static-source-route-case-fixture-corrected',['ruby','scripts/tests/public_static_routes_test.rb','--name=test_repository_static_routes_match_product_baseline_and_include_entry_paths'],0)
baseline='test/goldens/baselines/public_home_desktop.png';manifest='test/goldens/GOLDEN_MANIFEST.sha256'
golden_before={n:sha(EXPORT/n)for n in [baseline,manifest]}
env['COLLECT_GOLDEN_CANDIDATE_DIR']=str(OUT/'golden-candidate')
run('single-public-inter-golden-candidate',[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--plain-name=public website compares historical desktop baseline','--file-reporter=json:'+str(OUT/'public-candidate.machine.jsonl'),'test/goldens/collect_core_surfaces_golden_test.dart'],1)
candidate=OUT/'golden-candidate/public_home_desktop.png';assert candidate.is_file()
assert all(sha(EXPORT/n)==h for n,h in golden_before.items())
summaries={n:G.machine_summary(OUT/file)for n,file in [('landing','landing.machine.jsonl'),('font_contract','font-contract.machine.jsonl'),('public_candidate','public-candidate.machine.jsonl')]}
source_drift={n:{'before':h,'after':sha(ROOT/n)if(ROOT/n).is_file()else None}for n,h in before.items()if not(ROOT/n).is_file()or sha(ROOT/n)!=h}
export_drift={n:{'before':h,'after':sha(EXPORT/n)if(EXPORT/n).is_file()else None}for n,h in binding.items()if not(EXPORT/n).is_file()or sha(EXPORT/n)!=h}
inter=EXPORT/'build/unit_test_assets/assets/typefaces/Inter-Variable.ttf';assert sha(inter)==before['assets/typefaces/Inter-Variable.ttf']
passed=not source_drift and not export_drift and all(s['runner_completed_successfully'] and not any(s[n]for n in ['failed','errors','unfinished','event_errors'])for k,s in summaries.items()if k!='public_candidate')
save(OUT/'validation.json',{'status':'pass_pending_public_golden_review'if passed else'fail','machine_summaries':summaries,'prior_commands':json.loads((OUT/'execution.json').read_text())['commands'],'completion_commands':commands,'source_drift':source_drift,'export_drift':export_drift,'actual_inter_test_asset_sha256':sha(inter),'license_sha256':before['assets/typefaces/OFL-Inter.txt'],'public_golden_candidate':str(candidate),'public_golden_candidate_sha256':sha(candidate),'public_golden_expected_mismatch_preserved':True,'baseline_and_manifest_unchanged':golden_before,'original_missing_ruby_fixture_failure_preserved':True,'broad_suites_executed':False,'goldens_regenerated':False,'browser_native_static_builds_sql_executed':False,'scope':'Actual8 Inter landing tests, single font contract and corrected single source-only Ruby route case; one expected public golden mismatch captured for root visual review. No old successful check repeated. No full surface/native comparator or release packaging claim.'})
print('CANDIDATE',str(candidate),flush=True);print('RESULT',passed,flush=True)
raise SystemExit(0 if passed else 1)
