#!/usr/bin/env python3
"""Private unapplied data proposal; refuses pending actual epoch/outcome fields."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
READER=HERE/'proposed/scripts/audits/collect_current_evidence_index.py'
READER_SHA='447c8c053e90824b440204b302354b3545e7a8aca63a1077ce99c45081f90119'
BASELINE='docs/release/revolut-design/current-candidate-evidence-index.json'
SUMMARY='docs/release/revolut-design/acceptance-status.json'
ANDROID3='android/settings.gradle.kts'
READER_PATHS={'scripts/audits/collect_current_evidence_index.py','scripts/tests/collect_current_evidence_index_test.py'}
MAPPER_PATHS={'scripts/audits/collect_schema_domain_map.py','scripts/tests/collect_schema_domain_map_test.py'}
REQUIRED=('recorded_at_utc','new_root_fence','new_APP_manifest','android3_overlay',
          'android3_settings_after_pointer','archived_android3_settings')
CURRENT_AAB_REQUIRED=('AAB_outcome','AAB_source_fence','AAB_source_identity_pointer',
                      'AAB_source_domain','AAB_result_pointer','AAB_observed_result',
                      'AAB_built_pointer','AAB_claimed_built')

def sha(raw):return hashlib.sha256(raw).hexdigest()
def encoded(value):return (json.dumps(value,indent=2,sort_keys=True)+'\n').encode()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--inputs',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();root=args.root.resolve();inputs=json.loads(args.inputs.read_bytes())
    pending=[key for key in REQUIRED if inputs.get(key) is None]
    current_aab=inputs.get('AAB_outcome') is not None
    if current_aab:pending.extend(key for key in CURRENT_AAB_REQUIRED if inputs.get(key) is None)
    if pending:
        print(json.dumps({'status':'pending-actual-inputs-refused','missing_fields':pending,
                          'maintained_writes':False,'reader_grants_closure':False},sort_keys=True));return 2
    if sha(READER.read_bytes())!=READER_SHA:raise ValueError('Proposed reader bytes changed')
    spec=importlib.util.spec_from_file_location('private_refresh_reader',READER)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);reader=module.Reader()
    def read(record):
        raw=reader.read(root,record['path'])
        if (sha(raw),len(raw))!=(record['sha256'],record['bytes']):raise ValueError('Actual supplied document fence mismatch: '+record['path'])
        return module.json_value(raw)
    def record(path,raw,content='json'):
        return {'path':path.relative_to(root).as_posix(),'bytes':len(raw),'sha256':sha(raw),'content':content}
    index=module.json_value((HERE/'before'/BASELINE).read_bytes())
    summary=module.json_value((HERE/'before'/SUMMARY).read_bytes())
    additions=module.json_value((HERE/'known-additions.json').read_bytes())
    # Known completed packets are inputs, never generated substitutes for future evidence.
    for item in additions['documents'].values():
        raw=reader.read(root,item['path'])
        if (sha(raw),len(raw))!=(item['sha256'],item['bytes']):raise ValueError('Known completed packet drift')
    old_root=read(additions['documents']['PD12-reviewed-root-fence-epoch1c55'])
    old_projection=read(index['documents']['current-projection'])
    new_root=read(inputs['new_root_fence']);app=read(inputs['new_APP_manifest']);overlay=read(inputs['android3_overlay'])
    previous=old_root['source_files_identity'];current=new_root['source_files_identity']
    if set(current)!=set(previous) or len(current)!=2563:
        raise ValueError('Selected source membership changed; explicit scope review required')
    changed={path for path in current if current[path]['sha256']!=previous[path]['sha256']}
    if changed!=MAPPER_PATHS|READER_PATHS|{ANDROID3}:
        raise ValueError('Unexpected source delta relative to recorded1c55; no unobserved modification exemption')
    literal=read(additions['documents']['BE08-literal-readback'])
    for row in literal['applied_write_boundary']:
        if current[row['path']]['sha256']!=row['sha256'] or previous[row['path']]['sha256']!=row['preserved_before_sha256']:
            raise ValueError('Actual mapper integration/source fence disagreement')
    reader_integration=read(additions['documents']['PD12-decision-reader-integration'])
    for row in reader_integration['owned_files']:
        if current[row['path']]['sha256']!=row['after_sha256'] or previous[row['path']]['sha256']!=row['before_sha256']:
            raise ValueError('Actual reader integration/source fence disagreement')
    if current[ANDROID3]['sha256']!=module.pointer(overlay,inputs['android3_settings_after_pointer']):
        raise ValueError('Actual Android3 overlay/source fence disagreement')
    archived_settings=inputs['archived_android3_settings'];raw=reader.read(root,archived_settings['path'])
    if (sha(raw),len(raw))!=(archived_settings['sha256'],archived_settings['bytes']):raise ValueError('Retained Android3 original fence mismatch')
    app_scope=read(index['documents']['app-scope'])['source_files_exact']
    if archived_settings['sha256']!=app_scope[ANDROID3]['sha256']:raise ValueError('Retained settings do not equal archived execution source')
    if set(app['source_files'])!=set(app_scope) or app['file_count']!=2561:
        raise ValueError('Current APP manifest selected membership changed')
    tooling=set(old_projection['named_tooling5_actual_current_leaf_fences'])
    if {path for path in app_scope if path not in tooling}!=set(old_projection['known_captured_inputs_without_named_tooling5']):
        raise ValueError('Original declared known2556 scope differs')
    for path,row in app['source_files'].items():
        if row['sha256']!=(app_scope[path]['sha256'] if path in tooling else current[path]['sha256']):
            raise ValueError('Current APP/root or unchanged archived-tooling membership binding differs')
    artifacts=[];actual=expected_identity=None
    if current_aab:
        outcome=read(inputs['AAB_outcome']);aab_source=read(inputs['AAB_source_fence'])
        expected_identity={'private-app':app['source_manifest_sha256'],'root-source':new_root['source_manifest_sha256']}.get(inputs['AAB_source_domain'])
        if expected_identity is None or module.pointer(aab_source,inputs['AAB_source_identity_pointer'])!=expected_identity:
            raise ValueError('Actual current AAB evidence is not bound to the supplied source epoch')
        actual=module.pointer(outcome,inputs['AAB_result_pointer'])
        if type(actual)!=type(inputs['AAB_observed_result']) or actual!=inputs['AAB_observed_result']:
            raise ValueError('Actual current AAB outcome value differs')
        if type(inputs['AAB_claimed_built']) is not bool or module.pointer(outcome,inputs['AAB_built_pointer']) is not inputs['AAB_claimed_built']:
            raise ValueError('Actual current AAB built state differs or is unknown')
        artifacts=inputs.get('AAB_artifacts',[])
        if inputs['AAB_claimed_built'] and not artifacts:raise ValueError('Built AAB requires actual retained artifact bytes')
    for item in artifacts:
        raw=reader.read(root,item['path'])
        if (sha(raw),len(raw))!=(item['sha256'],item['bytes']):raise ValueError('Retained AAB artifact bytes differ')
    output=args.output.absolute()
    if output.resolve()!=output or not output.is_relative_to(root):raise ValueError('Fresh output must be physical and inside workspace')
    output.mkdir(mode=0o700,parents=False,exist_ok=False)
    def write(name,value):
        raw=encoded(value);path=output/name
        with path.open('xb') as stream:stream.write(raw)
        return record(path,raw)
    projection=copy.deepcopy(old_projection)
    projection['actual_current_root_source_manifest_sha256']=new_root['source_manifest_sha256']
    projection['actual_current_root_source_file_count']=len(current)
    projection['actual_current_APP_source_manifest_sha256']=app['source_manifest_sha256']
    projection['current_known_captured_input_fences']={path:current[path] for path in sorted(app_scope) if path not in tooling}
    projection['named_tooling5_actual_current_leaf_fences']={path:current[path] for path in sorted(tooling)}
    original_android={'android/app/build.gradle.kts','android/build.gradle.kts',ANDROID3}
    projection['archived_private_APP_inputs_without_reviewed_Android3']={path:row for path,row in app_scope.items() if path not in original_android}
    projection['archived_Android3_settings_retained_bytes']={archived_settings['path']:dict(archived_settings)}
    packet=read(additions['documents']['BE08-literal-artifacts'])
    projection['BE08_prior_tooling2_retained_fences']={
        'docs/release/critical-implementation-2026-10-01/be08-literal-replacement-integration1/'+row['path']:dict(row)
        for row in packet['files'] if row['path'].startswith('before/scripts/')}
    # Map values may not carry their own path in the maintained reader's manifest contract.
    for row in projection['BE08_prior_tooling2_retained_fences'].values():row.pop('path',None)
    for row in projection['archived_Android3_settings_retained_bytes'].values():row.pop('path',None)
    projection['scope']='Exact later selected2563 root and current privateAPP2561; archivedabf and reviewed1c55 remain separate. No whole graph/physicalSDK/current native/visual/provider/package acceptance.'
    projection_record=write('source-domains.json',projection)
    index['documents'].update(additions['documents']);index['documents'].update({
        'current-root-source-fence':inputs['new_root_fence'],'current-projection':projection_record,
        'refresh-source-domains':projection_record,'Android3-overlay':inputs['android3_overlay'],
        'current-APP-manifest':inputs['new_APP_manifest']})
    if current_aab:index['documents'].update({'latest-AAB-outcome':inputs['AAB_outcome'],'latest-AAB-source-fence':inputs['AAB_source_fence']})
    index['file_sets'].update(additions['file_sets'])
    index['file_sets']['app-authored2561'].update({'pointer':'/archived_private_APP_inputs_without_reviewed_Android3','expected_count':2558,
        'scope':'Archivedabf2558 live unchanged rows; three preserved original Android rows compose original2561. No current native acceptance.'})
    index['file_sets']['current-known-captured2556'].update({'pointer':'/current_known_captured_input_fences','digest_overrides':{},
        'scope':'Exact later known2556 subset derived from actual selected2563; five tooling + reader/test2 are separately bound, not silently excluded.'})
    index['file_sets']['current-declared-selected2563']['scope']='Actual supplied later selected2563 root fence; captured list scope only, not a complete repository/compiler/OS graph.'
    index['file_sets']['separate-named-tooling5']['scope']='Actual five current tooling leaves: BE08 latest2 bound to69-test receipt; ARC03 unchanged3 bound to its22+3 tests. Original bytes/diffs and previous57-test mapper epoch retained.'
    index['file_sets']['archived-abf-vs-current-liveAPP2561']['scope']='Historicalabf expectations compared directly with actual later liveAPP; retain every observed Android/source drift without converting it into current PASS.'
    def source_set(document,pointer,count,resource,scope,domain):
        return {'document':document,'pointer':pointer,'shape':'map-metadata','expected_count':count,'resource':resource,'prefix':'','role':'source','binding_domain':domain,'closed_inventory':None,'scope':scope}
    index['file_sets']['archived-Android3-original']=source_set('refresh-source-domains','/archived_Android3_settings_retained_bytes',1,'workspace','Exact retained original settings row composing archivedabf2561.','archived-tested-candidate')
    index['file_sets']['current-liveAPP2561']=source_set('current-APP-manifest','/source_files',2561,'app-copy','Exact current captured liveAPP2561 bytes; no whole current native suite or packaging/security acceptance.','current-relevant-listed-inputs')
    index['facts'].extend(additions['facts']);index['evidence'].extend(additions['evidence'])
    actual_facts=[
        ('later-APP-manifest-identity','current-APP-manifest','/source_manifest_sha256',app['source_manifest_sha256']),
        ('Android3-actual-settings-hash','Android3-overlay',inputs['android3_settings_after_pointer'],current[ANDROID3]['sha256'])]
    if current_aab:actual_facts.extend([
        ('latest-AAB-actual-source-identity','latest-AAB-source-fence',inputs['AAB_source_identity_pointer'],expected_identity),
        ('latest-AAB-actual-built-state','latest-AAB-outcome',inputs['AAB_built_pointer'],inputs['AAB_claimed_built'])])
    for name,document,pointer,expected in actual_facts:
        index['facts'].append({'id':name,'kind':'json-pointer','document':document,'pointer':pointer,'expected':expected})
    for item in index['evidence']:
        if item['id']=='BE08-actual-additive-tooling':
            item['context']='historical-prior57-test-mapper-epoch';item['file_sets']=['BE08-prior-tooling2-retained','BE08-actual17leaves']
        if 'app-authored2561' in item['file_sets']:
            item['file_sets'].append('archived-Android3-original')
            item['limitations'].append('Later Android3 settings and tooling revisions remain separate from originalabf completed consumer outcomes; no whole current native/application acceptance is inferred.')
        if item['id']=='current-relevant-known-inputs':
            item['scope']='Actual supplied later known2556 rows, named tooling5 and reader/test2 compose selected2563; privateAPP2561 is separately captured. No whole current repository/compiler/native/visual/provider acceptance.'
        if item['id']=='PD12-actual-index-readback':
            item['context']='historical-original-current-index-epoch1c55';item['file_sets']=[]
            item['scope']='Retained original101-fact/26-set reader result and two observed Android2 drift rows; later live source binding is a separate actual run.'
    for fact in index['facts']:
        if fact['document']=='current-root-source-fence' and fact['pointer']=='/source_manifest_sha256':fact['expected']=new_root['source_manifest_sha256']
        if fact['id']=='live-current-summary-root-source':fact['expected']=new_root['source_manifest_sha256']
        if fact['id']=='live-summary-actual-verification-state':fact['expected']='pending_actual_current_epoch_readback'
    index['scope_relations'].extend([
        {'original_document':'current-root-source-fence','original_pointer':'/source_files_identity','projected_document':'refresh-source-domains','projected_pointer':'/current_known_captured_input_fences','excluded_exact_paths':sorted(tooling|READER_PATHS)},
        {'original_document':'app-scope','original_pointer':'/source_files_exact','projected_document':'refresh-source-domains','projected_pointer':'/archived_private_APP_inputs_without_reviewed_Android3','excluded_exact_paths':sorted(original_android)}])
    index['candidate'].update({'id':'later-selected2563-'+new_root['source_manifest_sha256'][:16]+'-retaining-archivedabf-and-reviewed1c55',
        'current_declared_source_manifest_sha256':new_root['source_manifest_sha256'],'current_declared_source_file_count':2563,
        'current_APP_source_manifest_sha256':app['source_manifest_sha256'],
        'source_scope':'Archivedabf completed consumers, original reviewed1c55 closure, and later actual selected root/APP are distinct.',
        'scope_binding_model':'Actual later known2556 + named tooling5 + reader/test2 compose selected2563; actual privateAPP2561 and retained original Android3 composition are separately bound.'})
    index['reader_grants_closure']=False;index['PD12_closed']=False
    index['integrator_original_criterion_decision']=additions['integrator_original_criterion_decision']
    index['recorded_at_utc']=inputs['recorded_at_utc'];index['integration_state']='pending-actual-current-epoch-readback'
    index['pending_areas'].append({'area':'later current epoch reader/manual decision','state':'pending-root-actual-readback-and-manual-review','reason':'Original scoped decision remains reviewed1c55 only; no later closure decision or reader result is invented.'})
    if not current_aab:index['pending_areas'].append({'area':'current later epoch native package','state':'pending-actual-package','reason':'Last actual AAB9 failure remains dated at its recorded epoch. Later source/R8/settings/cache scopes do not create an AAB result; source index refresh proceeds with packaging unverified.'})
    current_summary=summary['current_candidate_index']
    current_summary['historical_binding_readback_epoch1c55']=current_summary.pop('actual_binding_readback')
    current_summary.update({'reader_grants_closure':False,'PD12_closed':False,
        'integrator_original_criterion_decision':additions['integrator_original_criterion_decision'],
        'index_binding_verification':'pending_actual_current_epoch_readback',
        'current_declared_source_manifest_sha256':new_root['source_manifest_sha256'],
        'current_declared_source_file_count':2563,'current_APP_source_manifest_sha256':app['source_manifest_sha256'],
        'scope':'Original1114/41 and native12/20 remain archivedabf; original PD12 decision remains recorded1c55. Later root/APP named source scope is supplied exactly; actual refreshed reader/manual review pending. Visual/font/provider/release/complete package acceptance remains unverified.'})
    summary['current_source_currency_note']='Archivedabf, scoped original1c55 decision and later actual selected root/currentAPP are separate epochs. Historical results remain intact; no reader grants closure.'
    summary_raw=encoded(summary);(output/'acceptance-status.json').write_bytes(summary_raw)
    index['documents']['live-current-acceptance-summary']={'path':SUMMARY,'bytes':len(summary_raw),'sha256':sha(summary_raw),'content':'json'}
    if current_aab:
        artifacts_record=write('latest-AAB-retained-artifacts.json',{'artifacts':artifacts})
        index['documents']['latest-AAB-retained-artifacts']=artifacts_record
        index['file_sets']['latest-AAB-retained-bytes']={'document':'latest-AAB-retained-artifacts','pointer':'/artifacts','shape':'list-metadata','expected_count':len(artifacts),'resource':'workspace','prefix':'','role':'artifact','binding_domain':'captured-artifact','closed_inventory':None,'scope':'Actual retained AAB artifacts only if supplied; no complete packaged SBOM/security/licence/release acceptance.'}
        index['evidence'].append({'id':'latest-actual-AAB-outcome','observed_result':actual,'result_binding':{'document':'latest-AAB-outcome','pointer':inputs['AAB_result_pointer']},'context':'later-actual-source-epoch','validation_status':'retained-independent-scoped-readback','independent_receipt':'latest-AAB-outcome','file_sets':['current-liveAPP2561','latest-AAB-retained-bytes'],'supersedes':[],
            'scope':'Exact root supplied current AAB outcome and source fence; retained bytes are checked only if actually supplied.','limitations':['No future outcome or artifact invented; complete packaged SBOM and licence/security/release acceptance remain unverified.']})
    write('current-candidate-evidence-index.json',index)
    write('refresh-plan-readback.json',{'status':'PRIVATE_UNAPPLIED_DATA_PREPARATION','original26_sets_retained':all(k in index['file_sets'] for k in module.json_value((HERE/'before'/BASELINE).read_bytes())['file_sets']),
        'file_sets':len(index['file_sets']),'facts':len(index['facts']),'epoch':new_root['source_manifest_sha256'],'reader_grants_closure':False,
        'external_integrator_cli_pins':additions['external_integrator_cli_pins'],'actual_new_reader_run':False,'later_manual_integrator_decision':False,'current_AAB_result_supplied':current_aab,'historical_AAB9_retained':True,'maintained_writes':False})
    return 0

if __name__=='__main__':raise SystemExit(main())
