from pathlib import Path
import hashlib, json, re, shutil, sys

s = Path(__file__).resolve().parent
root = s.parents[2]
p = s.parent / 'accepted-successor-admin-current1'
p.mkdir(exist_ok=False)
sha = lambda file: hashlib.sha256(file.read_bytes()).hexdigest()
read = lambda file: json.loads(file.read_text())
checks = {name: read(s / 'proofs' / name / 'result.json') for name in ['acceptance-current1', 'analysis-current1', 'browser-attempt1']}
for result in checks.values():
    assert result['exit_code'] == 0
    assert all(result[k] for k in ['source_unchanged', 'runtime_unchanged', 'dependencies_unchanged'])
assert '+21: All tests passed!' in (s / 'proofs/acceptance-current1/stdout.log').read_text()
assert '+2: All tests passed!' in (s / 'proofs/browser-attempt1/stdout.log').read_text()
assert 'No issues found!' in (s / 'proofs/analysis-current1/stdout.log').read_text()
for key in ['source_sha256','runtime_closure_sha256','dependencies_sha256']:
    assert checks['acceptance-current1'][key] == checks['analysis-current1'][key]
current = read(s / 'proofs/acceptance-current1/runtime-closure.json')
external = read(s / 'proofs/acceptance-current1/dependencies.json')
assert checks['browser-attempt1']['dependencies_sha256'] == checks['acceptance-current1']['dependencies_sha256']
assert all(sha(s / 'runtime' / rel) == data['sha256'] for rel,data in current.items())
assert all(sha(Path(e['path'])) == e['sha256'] and str(Path(e['path']).resolve()) == e['resolved_path'] for e in external)
canonical = read(s / 'canonical-current2-inputs.json')
assert all(sha(root / rel) == h for rel,h in canonical.items())
consumed = {}
def graph(entry):
    todo=[entry]; done=set()
    while todo:
        rel=todo.pop()
        if rel in done: continue
        done.add(rel); file=s / 'runtime' / rel
        assert file.is_file(), rel
        for directive in re.findall(r'^\s*(?:import|export|part)\s+[^;]+;',file.read_text(),re.M):
            if directive.strip().startswith('part of'): continue
            for name in re.findall(r"'([^']+)'",directive):
                if name.startswith('package:collect_app/'): target='lib/'+name.split('/',1)[1]
                elif name.startswith(('dart:','package:')): continue
                else: target=(file.parent/name).resolve().relative_to((s/'runtime').resolve()).as_posix()
                if target not in done:todo.append(target)
    return done
browser_graph=graph('test/admin_receipt_successor_checkpoint_browser_test.dart')
old_browser=read(s/'proofs/browser-attempt1/runtime-closure.json')
assert len(browser_graph)==7
assert all(current[rel]==old_browser[rel] for rel in browser_graph)
for name in ['lib','test']:
    for file in (s / name).rglob('*'):
        if file.is_file():
            rel=file.relative_to(s); dest=p / 'source' / rel
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
promotion={file.relative_to(p/'source').as_posix():sha(file) for file in (p/'source').rglob('*') if file.is_file()}
assert len(promotion)==21
(p/'promotion-manifest.json').write_text(json.dumps(promotion,indent=2,sort_keys=True)+'\n')
for rel,data in current.items():
    dest=p/'runtime-inputs'/rel;dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(s/'runtime'/rel,dest)
for rel,h in promotion.items():
    if rel.endswith('.dart'): consumed.update({v:current[v]['sha256'] for v in graph(rel)})
(p/'consumed-dart-closure-current.json').write_text(json.dumps(consumed,indent=2,sort_keys=True)+'\n')
(p/'browser-reuse-association.json').write_text(json.dumps({'source_command':'proofs/browser-attempt1/result.json','current_command':'proofs/acceptance-current1/result.json','browser_local_inputs':{rel:current[rel]['sha256']for rel in sorted(browser_graph)},'local_input_count':7,'external_dependency_vector_equal':True,'actual_case_count':2,'reason':'Only other VM/widget/transitive logger/startup files changed; browser checkpoint graph and exact current Chrome binaries remain unchanged.'},indent=2)+'\n')
depmap=[]
for e in external:
    dest=p/'dependencies/by-sha256'/e['sha256']
    if not dest.exists():dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(Path(e['path']),dest)
    depmap.append(dict(e,packet_blob=str(dest.relative_to(p))))
(p/'dependencies/map.json').write_text(json.dumps(depmap,indent=2,sort_keys=True)+'\n')
for name in ['proofs','integration','proof-artifacts']:
    shutil.copytree(s/name,p/name)
for file in ['run_checks.py','seal.py','canonical-overlay-inputs.json','canonical-overlay-current-inputs.json','canonical-refresh-telemetry.json','canonical-current2-inputs.json','canonical-current2-refresh.json','canonical-current2-post-check.json','canonical-before-seal-deltas.json','lint-fix.stdout','lint-fix.stderr']:
    if(s/file).is_file():shutil.copy2(s/file,p/file)
skill=Path('/Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design')
for rel in ['SKILL.md','references/brand-adaptation.md','references/DESIGN.md','references/web-patterns.md','references/component-contracts.md']:
    dest=p/'selected-skill'/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(skill/rel,dest)
assert sha(skill/'SKILL.md')=='0941cf390b2e77d605ee4877f960440688166534341ae2a3239a990d40127c50'
tools={}
for label,file in [('python',Path(sys.executable)),('dart',Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart')),('flutter',Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'))]:
    dest=p/'tools'/label;dest.parent.mkdir(exist_ok=True);shutil.copy2(file,dest);tools[label]={'path':str(file),'resolved_path':str(file.resolve()),'sha256':sha(file)}
(p/'tools/map.json').write_text(json.dumps(tools,indent=2)+'\n')
receipts={'acceptance-current1':{'session_id':19672,'initial_chunk':'db47ce','terminal_chunk':'50530a','exit_code':0,'actual_cases':21},'analysis-current1':{'session_id':45515,'initial_chunk':'2b6e5a','terminal_chunk':'f33c88','exit_code':0,'analysis_items':14},'browser-attempt1':{'session_id':50749,'initial_chunk':'e0852f','terminal_chunk':'73011e','exit_code':0,'actual_cases':2},'capture-tail1':{'session_id':99314,'initial_chunk':'855b66','terminal_chunk':'cdc844','exit_code':0,'actual_cases':1,'superseded_by':'acceptance-current1'},'acceptance-attempt4':{'session_id':70755,'initial_chunk':'40bb2e','terminal_chunk':'44bbfd','exit_code':1,'not_accepted':True},'acceptance-attempt3':{'session_id':82515,'initial_chunk':'687615','terminal_chunk':'3b2457','exit_code':0,'not_accepted':True,'reason':'Owned SIGINT interruption; no All tests passed output; explicit interrupted.json retained'},'acceptance-attempt2':{'session_id':22762,'initial_chunk':'3740c7','terminal_chunk':'814d81','exit_code':0,'actual_cases':20,'superseded_by':'acceptance-current1'},'acceptance-attempt1':{'session_id':84524,'initial_chunk':'1255a0','terminal_chunk':'1f3a1e','exit_code':1},'analysis-attempt2':{'session_id':36664,'initial_chunk':'934f82','terminal_chunk':'a9a6c3','exit_code':1},'analysis-attempt3':{'session_id':24561,'initial_chunk':'843fe4','terminal_chunk':'6d526e','exit_code':1},'analysis-attempt4':{'session_id':88970,'initial_chunk':'cacccc','terminal_chunk':'198ba6','exit_code':0,'superseded_by':'analysis-current1'},'analysis-attempt5':{'session_id':29693,'initial_chunk':'d76604','terminal_chunk':'c0ecb0','exit_code':1}}
(p/'terminal-receipts.json').write_text(json.dumps(receipts,indent=2)+'\n')
verification={'status':'sealed_for_root_review','promotion_files':len(promotion),'actual_new_cases':23,'cases':{'VM_SDK_models_controller_widgets_host':21,'actual_current_Chrome_checkpoint':2},'analysis':{'items':14,'result':'No issues found','exit_code':0},'acceptance_result_sha256':sha(p/'proofs/acceptance-current1/result.json'),'analysis_result_sha256':sha(p/'proofs/analysis-current1/result.json'),'browser_result_sha256':sha(p/'proofs/browser-attempt1/result.json'),'same_final_VM_analysis_source':checks['acceptance-current1']['source_sha256'],'same_final_VM_analysis_runtime':checks['acceptance-current1']['runtime_closure_sha256'],'dependencies':{'entries':len(external),'vector':checks['acceptance-current1']['dependencies_sha256'],'current_browser_reuse':'browser-reuse-association.json'},'runtime_files':len(current),'actual_consumed_Dart_files':len(consumed),'canonical_bindings_checked_before_after':len(canonical),'canonical_drift':False,'failure_retention':'Raw prior commands/source copies/results retained, including incomplete exit0 interrupted run. No superseded or partial case counts added.','fixture_producers':'integration/FIXTURE_PRODUCERS.json','integration_note':'integration/ROOT_INTEGRATION.md','scope':'Admin closure/exact immutable approval/revocation/history/original-request recovery, bound actual repository no-retry adapter. Root owns canonical investigation hook.','no_execution_authority':True,'selected_design_authority_sha256':sha(skill/'SKILL.md'),'rendered_artifact':'proof-artifacts/receipt-review-1440.png','visual_limits':'Actual local Inter/geometry capture and named heading/key/2x compact states. Material icon font substitution in widget harness remains; authenticated comparator/reader/full route acceptance unverified. Root runs make authority after promotion.','hosted':False,'device':False,'SMS':False,'production_release':'not_accepted'}
(p/'verification.json').write_text(json.dumps(verification,indent=2)+'\n')
manifest={file.relative_to(p).as_posix():sha(file)for file in p.rglob('*')if file.is_file()}
(p/'MANIFEST.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print(json.dumps({'packet':str(p),'members':len(manifest),'manifest_sha256':sha(p/'MANIFEST.json'),'verification_sha256':sha(p/'verification.json'),'promotion_files':len(promotion),'actual_new_cases':23}))
