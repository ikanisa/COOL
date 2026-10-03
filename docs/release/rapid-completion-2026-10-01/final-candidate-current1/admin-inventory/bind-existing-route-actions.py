#!/usr/bin/env python3
"""Semantic links to already executed cases. No tests, builds or source edits."""
from pathlib import Path
import hashlib
import json
import re

ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT=Path(__file__).resolve().parent
FROZEN=Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-final-local-candidate-20261001-current1')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
load=lambda p:json.loads(Path(p).read_bytes())
inventory=load(OUT/'inventory.json')
union_path=ROOT/'docs/release/rapid-completion-2026-10-01/full-flutter-accepted-union1/validation.json'
union=load(union_path)
assert union['status']=='pass'

def cohort(file, pattern=None):
    item=union['cohorts'][file]
    assert sha(FROZEN/file)==item['test_source_sha256']
    names=[c['name']for c in item['cases']if not c.get('skipped') and c['result']=='success'
           and (pattern is None or re.search(pattern,c['name'],re.I))]
    return dict(file=file,test_source_sha256=item['test_source_sha256'],receipt=item['packet'],
                executed_case_names=names,case_count=len(names))

routes=[]
for r in inventory['routes']:
    route=r['path']
    pattern=re.escape(route)+r'(?=\s|$)'
    named=cohort('test/admin_declared_route_states_test.dart',pattern)
    access=cohort('test/admin_route_access_test.dart',pattern)
    states={}
    for state in ['allowed','loading','failure','empty','revoked']:
        names=[n for n in named['executed_case_names']if n.startswith(state+' ')]
        states[state]=dict(applicable=route not in ['/admin/login','/admin/denied'],
                           executed_cases=names,accepted=bool(names))
    app=[]
    if route in ['/admin/system-health','/admin/automations']:
        states['empty']=dict(applicable=False,accepted=None,
            reason='Singleton contract: a successful resolved singleton has no empty record-list state.')
        files=(['test/admin_operational_health_test.dart','test/admin_receipt_worker_health_test.dart']
            if route=='/admin/system-health' else ['test/admin_operating_policy_runtime_test.dart',
            'test/admin_receipt_principal_integration_test.dart','test/admin_receipt_principal_recovery_test.dart'])
        app=[cohort(f)for f in files]
    if route=='/admin/login':
        app=[cohort(f)for f in ['test/admin_email_login_test.dart','test/admin_operator_approval_sdk_matrix_test.dart']]
    if route=='/admin/denied':
        app=[cohort('test/admin_route_access_test.dart',r'denied|capabilit|non-Admin')]
    required=[v for v in states.values()if v['applicable']]
    assert all(v['accepted']for v in required),(route,states)
    assert len(r['browser_state_execution'])==2 and all(x['status']=='pass'for x in r['browser_state_execution'])
    routes.append(dict(path=route,baseline_permission=r['baseline_permission'],
        additional_permissions=r.get('additional_permissions',[]),states=states,
        named_route_cohort=named,denial_retry_cohort=access,app_specific_state_cohorts=app,
        executed_current_browser_states=r['browser_state_execution'],
        accepted_applicable_route_states=True))

proof_paths={
 'generic12':'docs/release/rapid-completion-2026-10-01/final-candidate-current1/generic-action-audits/attempt4-json-scalar-contract/result.json',
 'sensitive126':'docs/release/import-export-protection-2026-10-01/sensitive-current18-unicode-attempt3-integrated/result.json',
 'roster25':'docs/release/rapid-completion-2026-10-01/e1-roster-final-email-current1/attempt5-exact-inspection-contract/result.json',
 'feature108':'docs/release/runtime-controls-2026-10-01/current21-full26-races-attempt1/result.json',
 'cancel14':'docs/release/runtime-controls-2026-10-01/current21-cancellation-positive-attempt3-joined-contract/result.json',
 'gateway84':'docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat/result.json',
 'exception144':'docs/release/collect-codex-goal-2026-09-30/operational-exceptions/sql-attempt7/result.json',
 'workflow41':'docs/release/collect-codex-goal-2026-09-30/exception-lifecycle-20261001/attempt6/result.json',
 'principal92':'docs/release/collect-codex-goal-2026-09-30/receipt-operations-enrollment-workflow-20261001/sql/attempt3/result.json',
 'operations84':'docs/release/collect-codex-goal-2026-09-30/receipt-operational-authority-20261001/accepted-sql-attempt7/result.json',
 'approval68':'docs/release/collect-codex-goal-2026-09-30/email-auth/sql-attempt8/result.json',
 'invitation40':'docs/release/import-export-protection-2026-09-30/invitation-installed154-attempt6-function-name-binding/result.json',
}
proofs={}
for key,rel in proof_paths.items():
    path=ROOT/rel;body=load(path)
    assert body['status']=='pass',(key,body['status'])
    cases=body.get('cases',body.get('checks',[]))
    names=[]
    for c in cases:
        assert c.get('status','pass')=='pass' and c.get('passed',True),(key,c)
        names.append(c['name'])
    # Only explicit matching captured input hashes are recorded here. Static
    # function references never become an executed audit assertion.
    matched={}
    def match(v):
        if isinstance(v,dict):
            for k,x in v.items():
                if isinstance(x,str)and re.fullmatch('[0-9a-f]{64}',x):
                    rel=k if k.startswith('supabase/')else 'supabase/migrations/'+k
                    p=FROZEN/rel
                    if p.is_file()and sha(p)==x:matched[rel]=x
                match(x)
        elif isinstance(v,list):
            for x in v:match(x)
    match(body)
    proofs[key]=dict(receipt=rel,sha256=sha(path),status='pass',actual_executed_case_names=names,
                    exact_matching_candidate_migration_inputs=matched)

custom={
 'admin_create_collect_payee':['createPayee'], 'admin_update_collect_payee':['editPayee'],
 'admin_set_collect_payee_status':['activatePayee','deactivatePayee'],
 'admin_create_platform_public_group':['createGroup'], 'admin_set_group_active':['activateGroup','deactivateGroup'],
 'admin_update_collection_support_status':['approveGroup','rejectGroup'],
 'admin_update_platform_public_group_metadata':['metadata'], 'admin_record_operator_note':['note','profileNote'],
 'admin_set_feature_flag_v2':['featureFlag'],
}
generic=load(ROOT/proof_paths['generic12'])
actions=[]

def select_sql(key,pattern):
    names=[n for n in proofs[key]['actual_executed_case_names']if re.search(pattern,n,re.I)]
    assert names,(key,pattern)
    return dict(receipt_id=key,actual_executed_result_cases=names)

for endpoint in inventory['endpoints']:
    if endpoint['classification']!='active_action':continue
    name=endpoint['name'];clients=[];durable=[];classification='enabled_mutation_or_durable_ack'
    note=None
    if name in custom:
        clients=[cohort('test/admin_custom_action_ui_test.dart',r'^(?:'+ '|'.join(custom[name])+r') production UI'),
                 cohort('test/admin_action_contracts_test.dart',re.escape(name))]
    if name in generic['actions']:
        durable=[select_sql('generic12',re.escape(name)+r' exact durable|reconciliation-finalize exact durable')]
        if name=='reconciliation-finalize':
            clients=[cohort('test/admin_reconciliation_repository_test.dart'),cohort('test/admin_reconciliation_ui_test.dart'),
                cohort('test/admin_reconciliation_step_up_test.dart')]
            note='Authenticated exact-checker authorizer and service-only SQL finalizer are executed. Edge HTTP delivery/deployment remains external.'
        elif 'reconciliation' in name:
            clients=[cohort('test/admin_reconciliation_repository_test.dart'),cohort('test/admin_reconciliation_ui_test.dart'),
                cohort('test/admin_reconciliation_step_up_test.dart')]
        elif name=='admin_set_user_access':
            clients=[cohort('test/admin_operator_approval_test.dart'),cohort('test/admin_operator_approval_sdk_matrix_test.dart')]
    elif name in ['admin_reveal_raw_sms','admin_retry_notification']:
        clients=[cohort('test/admin_action_ui_session_test.dart'),cohort('test/admin_action_contracts_test.dart',re.escape(name))]
        durable=[select_sql('sensitive126',r'audit|retry preserves|queued retry|current email-approved')]
    elif name=='admin_set_feature_flag_v2':
        clients.append(cohort('test/admin_feature_flag_runtime_test.dart'))
        durable=[select_sql('feature108',r'^feature_flags ')]
    elif name in ['admin_approve_email_operator_v1','admin_revoke_email_operator_v1']:
        clients=[cohort('test/admin_operator_approval_test.dart'),cohort('test/admin_operator_approval_sdk_matrix_test.dart')]
        durable=[select_sql('approval68',r'email approval replay preserves age|different email account revocation|actual Admin identity')]
    elif name in ['admin_approve_whatsapp','admin_revoke_whatsapp_approval']:
        classification='legacy_compatibility_control_disabled_by_current_email_mode'
        clients=[cohort('test/admin_operator_approval_test.dart',r'legacy-disabled|fallback|provider|exact server')]
        durable=[select_sql('approval68',r'email mode read explicitly disables legacy|stale legacy approval|queued legacy approval|legacy phone fallback')]
        note='These remain declared compatibility RPCs. The current email-only UI explicitly disables legacy controls; this row asserts denial/current mode, not a new successful WhatsApp action.'
    elif name in ['admin_enroll_gateway_device_v1','admin_activate_gateway_device_v1','admin_revoke_gateway_device_v1']:
        clients=[cohort('test/admin_gateway_action_ui_sdk_test.dart'),cohort('test/admin_gateway_sdk_state_matrix_test.dart'),
            cohort('test/admin_gateway_repository_test.dart'),cohort('test/admin_gateway_page_test.dart')]
        durable=[select_sql('gateway84',r'original owner reconciles exact enrollment|activation uncertainty read|last owner action is actual immutable revocation|revocation reconciliation')]
        note='Auditable result is the immutable original owner request receipt; enrollment/activation is not dispatch, physical possession, carrier or delivery evidence.'
    elif name in ['admin_enroll_receipt_operations_identity_v3','admin_activate_receipt_operations_identity_v3','admin_revoke_receipt_operations_identity_v3']:
        clients=[cohort('test/admin_receipt_principal_integration_test.dart'),cohort('test/admin_receipt_principal_recovery_test.dart')]
        pattern=(r'enrollment exact receipt|exact live-deadline duplicate|original enrollment lookup' if 'enroll_'in name
                 else r'activation exact receipt|activation can be recovered' if 'activate_'in name
                 else r'v3 revoke receipt|private v3 revoke input|same actor fresh session recovers exact original v3 revoke|immutable workflow')
        durable=[select_sql('principal92',pattern)]
    elif name in ['admin_configure_receipt_operations_v2','admin_stop_receipt_operations_v2']:
        clients=[cohort('test/admin_operating_policy_runtime_test.dart')]
        # The exact existing operations runtime cohort is included separately.
        clients += [cohort(f)for f in union['cohorts']if 'receipt_operations' in f or 'operational_authority' in f]
        durable=[select_sql('operations84',r'owner original request lookup|owner configure replay' if 'configure_'in name else r'stop lookup returns exact immutable|current human owner|stop')]
        note='Durable owner configure/stop result, expiry and revision are asserted. No sender/device authority is inferred.'
    elif name=='admin_cancel_unstarted_receipt_v1':
        clients=[cohort('test/admin_receipt_cancel_card_test.dart'),cohort('test/admin_receipt_cancel_sdk_authority_test.dart'),
            cohort('test/admin_receipt_cancel_repository_test.dart')]
        durable=[select_sql('cancel14',r'stored cancellation audit|original replay|joined current audit')]
    elif name=='admin_act_operational_exception_v1':
        clients=[cohort('test/admin_exception_sdk_provider_state_test.dart'),cohort('test/admin_exception_page_test.dart'),
            cohort('test/admin_exception_repository_test.dart')]
        durable=[select_sql('exception144',r'acknowledgement receipt explicitly|exact action replay|unknown response can be reconciled|exception_actions evidence is immutable')]
    elif name in ['admin_act_exception_workflow_v1','admin_read_exception_escalation_v1']:
        clients=[cohort('test/admin_exception_workflow_sdk_test.dart'),cohort('test/admin_exception_workflow_test.dart')]
        durable=[select_sql('workflow41',r'exact request replay|unknown response reconciles|exception_workflow_requests immutable|exception_inbox_reads immutable|read acknowledgement|read ACK|read ack')]
    elif name in ['admin_save_roster_import_draft','admin_review_roster_import','admin_commit_roster_import',
                  'admin_stage_roster_import_intent','admin_execute_roster_import_intent','admin_transfer_interrupted_roster_import','prepare-roster-import']:
        clients=[cohort('test/admin_roster_import_test.dart'),cohort('test/admin_roster_transport_test.dart'),
            cohort('test/admin_roster_declared_read_dispatch_test.dart'),cohort('test/admin_roster_authority_scope_test.dart')]
        durable=[select_sql('roster25',r'changed draft CAS|saved review intent|saved commit intent|durable import audit|explicit commit replay|email recovery transfer exact ACK|exact transfer replay')]
        if name=='prepare-roster-import':
            clients += [cohort('test/admin_roster_upload_admission_test.dart'),cohort('test/admin_roster_xlsx_preflight_test.dart')]
            note='Actual SDK multipart/size/hash/target and parser admission are client proof; final durable source/review/hash audit is SQL proof. External image/AI extraction and deployed Edge invocation are excluded.'
    else:
        raise AssertionError('Unmapped declared action: '+name)
    assert clients and all(c['case_count']>0 for c in clients),(name,clients)
    assert durable,name
    source=endpoint.get('latest_source_definition')
    row=dict(endpoint=name,routes=endpoint['routes'],classification=classification,
        actual_executed_client_cohorts=clients,actual_auditable_result_receipts=durable,
        source_definition_reference=source,source_reference_is_audit_assertion=False,
        practical_enabled_flow_evidence_bound=True)
    if name in generic['actions']:row['actual_current185_action']=generic['actions'][name]
    if note:row['scope_note']=note
    actions.append(row)

assert len(routes)==28 and len(actions)==38
result=dict(kind='immutable_final_candidate_semantic_route_action_acceptance',status='pass_scoped',
    candidate=str(FROZEN),inventory_sha256=sha(OUT/'inventory.json'),
    whole_vm_union_receipt=str(union_path.relative_to(ROOT)),whole_vm_union_sha256=sha(union_path),
    route_count=28,protected_route_count=26,queue_empty_route_count=24,
    singleton_empty_not_applicable_routes=['/admin/system-health','/admin/automations'],
    declared_action_count=38,generic_current185_actual_action_count=12,
    all_applicable_declared_route_states_have_named_executed_cases=True,
    all_declared_actions_have_practical_current_candidate_evidence=True,
    meaningful_unmet_enabled_action_audit_criteria=[],routes=routes,actions=actions,receipt_catalog=proofs,
    output_invitation_scope=dict(active_admin_csv_export=False,excluded_legacy_export_endpoints=16,
        actual_qr_copy_share_save_client_receipt='docs/release/import-export-protection-2026-09-30/invitation-save-final-attempt15/validation.json',
        durable_minimized_invitation_audit_receipt_id='invitation40',physical_device_share_save_verified=False),
    limits=['No blanket Cartesian product assertion for every provider/dialog/state. Only named cases and their assertions are accepted.',
      'Static mapping metadata is not runtime execution or a durable audit assertion.',
      'Immutable owner request receipts establish auditability for their asserted business outcomes; no generic audit_logs row is invented.',
      'Two legacy WhatsApp action declarations are disabled by current email mode; denial/current-mode proof is linked instead of successful legacy mutation.',
      'Singleton health/automations have app-specific resolved/unavailable/stale states; generic record-list empty is not applicable.',
      'Sensitive financial/provider/device/delivery conclusions are bounded by each linked SQL/client receipt.',
      'Current means the tested immutable2117 candidate. Later live Admin/MCP/storage changes remain outside this acceptance.',
      'Actual current production browser proves local route/PWA lifecycle against loopback synthetic email authority; hosted production approval remains external.'])
(OUT/'route-action-acceptance.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(dict(status=result['status'],routes=len(routes),actions=len(actions),
    exact_current185_generic_actions=12,remaining_meaningful_action_audit_gaps=[],
    sha256=sha(OUT/'route-action-acceptance.json'))))
