#!/usr/bin/env python3
"""Narrow licensed Inter fallback verification in a prior APFS source clone."""
import hashlib,json,os,shutil,sys
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
sys.path.insert(0,str(ROOT/'scripts/tests'))
import admin_read_gateway_gate as G
OUT=Path(__file__).resolve().parent
PARENT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-essential-admin-checkpoint-scrub-current4')
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-font-rights-current1')
SDK=ROOT/'.cache/flutter-sdk-isolated-gateway-motion-root192'
DELTAS=['pubspec.yaml','lib/app/theme/collect_runtime_typography.dart','web/public/revolut.css','scripts/public_static_site_build.rb','assets/marketing/SOURCE.json','test/goldens/collect_core_surfaces_golden_test.dart','test/admin_roster_dialog_test.dart','test/admin_reconciliation_ui_test.dart','test/features/runtime_component_contract_test.dart','test/landing_page_test.dart','assets/typefaces/Inter-Variable.ttf','assets/typefaces/OFL-Inter.txt']
DART=[n for n in DELTAS if n.endswith('.dart')]
REMOVED=['assets/typefaces/AeonikPro-Medium.ttf','assets/typefaces/AeonikPro-Regular.ttf']
CONSUMED=DELTAS+['pubspec.lock','scripts/qa/public_static_routes.rb','scripts/tests/public_static_routes_test.rb','docs/release/public-website-content-baseline.json','lib/app/theme/collect_runtime_assets.dart','lib/features/landing/public_marketing_theme.dart','lib/features/landing/collect_landing_page.dart','lib/features/landing/public_navigation_footer.dart','lib/app/theme/collect_typography.dart']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
assert EXPORT.exists() and PARENT.exists() and not (OUT/'validation.json').exists()
assert (PARENT/'pubspec.yaml').read_text().split('\nflutter:\n')[0]==(ROOT/'pubspec.yaml').read_text().split('\nflutter:\n')[0]
before={n:sha(ROOT/n)for n in CONSUMED if(ROOT/n).is_file()}
save(OUT/'changed-and-direct-consumed-inputs-before.json',before)
for name in DELTAS:
    destination=EXPORT/name;destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/name,destination)
    assert sha(destination)==before[name] and sha(ROOT/name)==before[name],name
removed=[]
for name in REMOVED:
    assert not(ROOT/name).exists(),name
    path=EXPORT/name
    if path.exists():removed.append({'path':name,'retained_parent_sha256':sha(PARENT/name),'export_removed_sha256':sha(path)});path.unlink()
export_binding={n:sha(EXPORT/n)for n in before if(EXPORT/n).is_file()}
save(OUT/'export-overlay.json',{'parent':str(PARENT),'export':str(EXPORT),'sequential_overlaid_files':DELTAS,'removed_from_clone_only':removed,'consumed_export_sha256':export_binding,'dependency_prefix_unchanged':True,'pub_reresolution_executed':False})
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),PATH=str(SDK/'bin')+':'+env['PATH'])
commands=[]
def run(name,argv):
    print('START',name,flush=True);previous=dict(os.environ)
    try:
        os.environ.clear();os.environ.update(env)
        result=G.run_command(argv,EXPORT,OUT/(name+'.log'),600)
    finally:os.environ.clear();os.environ.update(previous)
    commands.append({'name':name,**result});save(OUT/'execution.json',{'commands':commands})
    print('END',name,result['exit_code'],flush=True);assert result['exit_code']==0,name
run('toolchain',[str(SDK/'bin/flutter'),'--version','--machine'])
version=json.loads((OUT/'toolchain.log').read_text())
assert version['frameworkVersion']=='3.44.4' and version['dartSdkVersion']=='3.12.2' and version['frameworkRevision']=='ad70ec4617166f1c38e5d2bfd388af71fda14f06'
run('nonwriting-format',[str(SDK/'bin/cache/dart-sdk/bin/dart'),'format','--output=none','--set-exit-if-changed',*DART])
run('selected-analysis',[str(SDK/'bin/cache/dart-sdk/bin/dart'),'analyze','--fatal-infos',*DART])
run('landing-actual-inter',[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--file-reporter=json:'+str(OUT/'landing.machine.jsonl'),'test/landing_page_test.dart'])
run('single-font-contract',[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--plain-name=Collect bundles licensed Inter for product and marketing roles','--file-reporter=json:'+str(OUT/'font-contract.machine.jsonl'),'test/features/runtime_component_contract_test.dart'])
run('ruby-syntax',['ruby','-c','scripts/public_static_site_build.rb'])
run('single-static-source-route-case',['ruby','scripts/tests/public_static_routes_test.rb','--name=test_repository_static_routes_match_product_baseline_and_include_entry_paths'])
summaries={n:G.machine_summary(OUT/file)for n,file in [('landing','landing.machine.jsonl'),('font_contract','font-contract.machine.jsonl')]}
source_drift={n:{'before':h,'after':sha(ROOT/n)if(ROOT/n).is_file()else None}for n,h in before.items()if not(ROOT/n).is_file()or sha(ROOT/n)!=h}
export_drift={n:{'before':h,'after':sha(EXPORT/n)if(EXPORT/n).is_file()else None}for n,h in export_binding.items()if not(EXPORT/n).is_file()or sha(EXPORT/n)!=h}
staged=EXPORT/'build/unit_test_assets/assets/typefaces/Inter-Variable.ttf'
assert staged.is_file() and sha(staged)==before['assets/typefaces/Inter-Variable.ttf']
passed=not source_drift and not export_drift and all(s['runner_completed_successfully'] and not any(s[n]for n in ['failed','errors','unfinished','event_errors'])for s in summaries.values())
save(OUT/'validation.json',{'status':'pass'if passed else'fail','commands':commands,'machine_summaries':summaries,'changed_source_input_count':len(DELTAS),'consumed_named_input_count':len(before),'source_drift':source_drift,'export_drift':export_drift,'actual_inter_test_asset_sha256':sha(staged),'license_sha256':before['assets/typefaces/OFL-Inter.txt'],'unlicensed_source_fonts_removed_from_clone':removed,'only_single_runtime_contract_test_executed':True,'goldens_executed':False,'goldens_regenerated':False,'browser_builds':False,'native_builds':False,'static_website_build_executed':False,'sql_executed':False,'authority_check_owned_by_root':True,'scope':'Actual licensed Inter landing widget behavior including compact200percent and one font contract; selected changed-Dart analyzer/formatter; Ruby syntax and one source-only static route baseline case. Unchanged prior source/export dependency bindings reused; no whole-repository currentness, native visual comparator fidelity, release font packaging, broad resource inventory or full surface acceptance claim.'})
print('RESULT',passed,flush=True);raise SystemExit(0 if passed else 1)
