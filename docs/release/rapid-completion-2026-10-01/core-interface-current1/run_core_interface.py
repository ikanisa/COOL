#!/usr/bin/env python3
"""Only affected current member header/search and existing Admin/keyboard cases."""
import hashlib,json,os,shutil,sys
from pathlib import Path
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');sys.path.insert(0,str(ROOT/'scripts/tests'))
import admin_read_gateway_gate as G
OUT=Path(__file__).resolve().parent
PARENT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-font-rights-current1')
EXPORT=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-core-interface-current1')
SDK=ROOT/'.cache/flutter-sdk-isolated-gateway-motion-root192'
FILES=['lib/features/status/group_members_screen.dart','lib/features/collections/collection_detail_screen.dart','lib/shared/widgets/collect_top_chrome.dart','lib/app/theme/collect_runtime_typography.dart','lib/app/theme/collect_typography.dart','lib/app/theme/collect_theme.dart','lib/shared/widgets/collect_components.dart','lib/shared/repositories/collect_repository.dart','lib/app/router.dart','pubspec.yaml','pubspec.lock','assets/typefaces/Inter-Variable.ttf','assets/typefaces/OFL-Inter.txt','test/features/shared_chrome_accessibility_test.dart','test/admin_header_accessibility_test.dart','test/features/collect_surface_keyboard_focus_test.dart','test/fixtures/collect_repository_fixture.dart','lib/admin/admin_shell.dart','lib/admin/admin_app.dart']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
assert EXPORT.exists() and not(OUT/'validation.json').exists()
before={n:sha(ROOT/n)for n in FILES};overlay=[]
assert (EXPORT/'pubspec.yaml').read_text().split('\nflutter:\n')[0]==(ROOT/'pubspec.yaml').read_text().split('\nflutter:\n')[0]
for name,digest in before.items():
    if not(EXPORT/name).is_file()or sha(EXPORT/name)!=digest:
        overlay.append(name);(EXPORT/name).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,EXPORT/name)
    assert sha(EXPORT/name)==digest and sha(ROOT/name)==digest,name
save(OUT/'current-source-export-bindings.json',{'parent':str(PARENT),'export':str(EXPORT),'root_and_export_sha256':before,'sequential_overlaid_files':overlay,'dependency_prefix_unchanged':True,'no_pub_resolution_required':True})
env={k:v for k,v in os.environ.items()if k in {'HOME','USER','LOGNAME','SHELL','PATH','TMPDIR','LANG','LC_ALL','LC_CTYPE'}}
env.update(CI='true',FLUTTER_SUPPRESS_ANALYTICS='true',PUB_CACHE=str(ROOT/'.cache/pub-cache-hygiene-20260930'),PATH=str(SDK/'bin')+':'+env['PATH'])
commands=[]
def run(name,argv):
    print('START',name,flush=True);old=dict(os.environ)
    try:
        os.environ.clear();os.environ.update(env);r=G.run_command(argv,EXPORT,OUT/(name+'.log'),600)
    finally:os.environ.clear();os.environ.update(old)
    commands.append({'name':name,**r});save(OUT/'execution.json',{'commands':commands});print('END',name,r['exit_code'],flush=True);assert r['exit_code']==0,name
changed_dart=[n for n in overlay if n.endswith('.dart')]
if changed_dart:run('selected-changed-analysis',[str(SDK/'bin/cache/dart-sdk/bin/dart'),'analyze','--fatal-infos',*changed_dart])
run('shared-core-only',[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--name=Group header and confirmed hero|quick action words stay whole|bottom navigation retains|Members search keeps focus','--file-reporter=json:'+str(OUT/'shared.machine.jsonl'),'test/features/shared_chrome_accessibility_test.dart'])
run('admin-header-only',[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--file-reporter=json:'+str(OUT/'admin-header.machine.jsonl'),'test/admin_header_accessibility_test.dart'])
run('keyboard-five-only',[str(SDK/'bin/flutter'),'test','--no-pub','--concurrency=1','--reporter=expanded','--file-reporter=json:'+str(OUT/'keyboard.machine.jsonl'),'test/features/collect_surface_keyboard_focus_test.dart'])
summaries={name:G.machine_summary(OUT/file)for name,file in [('shared','shared.machine.jsonl'),('admin_header','admin-header.machine.jsonl'),('keyboard','keyboard.machine.jsonl')]}
assert [summaries[n]['passed']for n in ['shared','admin_header','keyboard']]==[7,1,5]
source_drift={n:{'before':h,'after':sha(ROOT/n)if(ROOT/n).is_file()else None}for n,h in before.items()if not(ROOT/n).is_file()or sha(ROOT/n)!=h}
export_drift={n:{'before':h,'after':sha(EXPORT/n)if(EXPORT/n).is_file()else None}for n,h in before.items()if not(EXPORT/n).is_file()or sha(EXPORT/n)!=h}
passed=not source_drift and not export_drift and all(s['runner_completed_successfully']and not any(s[n]for n in ['failed','errors','unfinished','event_errors'])for s in summaries.values())
save(OUT/'validation.json',{'status':'pass'if passed else'fail','commands':commands,'machine_summaries':summaries,'total_passed':13,'source_drift':source_drift,'export_drift':export_drift,'sequential_overlaid_files':overlay,'selected_analyzer_repeated':bool(changed_dart),'selected_analyzer_reason':'Only actual root/export Dart drift requires analysis; all named consumed inputs matched current Inter clone before these checks.','shared_test_name_filter':'Group header and confirmed hero|quick action words stay whole|bottom navigation retains|Members search keeps focus','changed_core_views':['lib/features/status/group_members_screen.dart','lib/features/collections/collection_detail_screen.dart'],'actual_inter_loaded_in_shared_and_keyboard_tests':True,'golden_tests_executed':False,'browser_native_static_builds_executed':False,'sql_executed':False,'pub_resolution_repeated':False,'scope':'Only current core member group headers/actions/navigation and Members search at compact/enlarged text; existing Admin header semantics/target sizes; five actual keyboard card/row focus cases. No broad shared27/interface120 suite, full surface/native comparator acceptance or provider/device release claim.'})
print('RESULT',passed,flush=True);raise SystemExit(0 if passed else 1)
