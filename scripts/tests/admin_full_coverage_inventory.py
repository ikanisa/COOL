#!/usr/bin/env python3
"""Source-only declared Admin inventory. Test references are never test results."""
import argparse
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
ROUTE_RPCS = {
    '/admin/login': ['Auth.signInWithOtp', 'Auth.verifyOTP', 'admin_current_user'],
    '/admin/denied': [], '/admin': ['admin_overview', 'admin_receipt_overview_v1',
        'admin_system_health', 'collect-notification-operator'],
    '/admin/groups': ['admin_list_collections'],
    '/admin/groups/:id': ['admin_get_collection'],
    '/admin/users': ['admin_list_non_member_users'],
    '/admin/users/:id': ['admin_get_user'],
    '/admin/members': ['admin_list_members'],
    '/admin/members/:id': ['admin_get_member_record'],
    '/admin/payees': ['admin_list_collect_payees'],
    '/admin/transactions': ['admin_list_collect_transactions'],
    '/admin/transactions/:id': ['admin_get_collect_transaction', 'admin_get_collect_investigation_v1'],
    '/admin/reconciliations': ['admin_list_collect_reconciliations', 'list_payment_reconciliations_v2', 'get_payment_reconciliation_v2'],
    '/admin/ledgers': ['admin_list_collect_ledgers'],
    '/admin/sms-receipts': ['admin_list_hybrid_sms_receipts'],
    '/admin/sms-receipts/:id': ['admin_get_hybrid_sms_receipt', 'admin_get_collect_investigation_v1'],
    '/admin/notifications': ['admin_list_notifications'],
    '/admin/notifications/:id': ['admin_get_notification'],
    '/admin/sms-gateway': ['admin_list_gateway_devices_v1', 'admin_get_gateway_owner_request_v1'],
    '/admin/exceptions': ['admin_list_operational_exceptions_v2',
        'admin_get_operational_exception_action_v2',
        'admin_get_receipt_deferral_exception_v1',
        'admin_get_exception_workflow_v1', 'admin_get_exception_workflow_request_v1',
        'admin_list_exception_escalation_inbox_v1'],
    '/admin/audit-logs': ['admin_list_audit_logs'],
    '/admin/audit-logs/entity/:kind/:id': ['admin_get_operator_entity_audit_v1'],
    '/admin/settings': ['admin_list_settings'],
    '/admin/feature-flags': ['admin_list_feature_flags'],
    '/admin/system-health': ['admin_system_health'],
    '/admin/automations': ['admin_system_health', 'collect-notification-operator', 'list_collect_shadow_runs_v1',
        'admin_get_unattended_operating_policy_v1', 'admin_get_receipt_operations_policy_v2',
        'admin_get_receipt_operations_owner_request_v2', 'admin_get_receipt_exception_worker_health_v1'],
    '/admin/admin-users': ['admin_list_admin_users'],
    '/admin/admin-users/:id': ['admin_get_admin_user'],
}
ACTIVE_ACTIONS = {
    'admin_create_platform_public_group': ['/admin/groups'],
    'admin_create_collect_payee': ['/admin/payees'],
    'admin_update_collect_payee': ['/admin/payees'],
    'admin_set_collect_payee_status': ['/admin/payees'],
    'admin_set_group_active': ['/admin/groups/:id'],
    'admin_update_collection_support_status': ['/admin/groups/:id'],
    'admin_update_platform_public_group_metadata': ['/admin/groups/:id'],
    'admin_record_operator_note': ['/admin/groups/:id', '/admin/users/:id'],
    'admin_retry_notification': ['/admin/notifications/:id'],
    'admin_inspect_unstarted_receipt_v1': ['/admin/transactions/:id', '/admin/sms-receipts/:id'],
    'admin_get_unstarted_receipt_action_v1': ['/admin/transactions/:id', '/admin/sms-receipts/:id'],
    'admin_cancel_unstarted_receipt_v1': ['/admin/transactions/:id', '/admin/sms-receipts/:id'],
    'admin_reveal_raw_sms': ['/admin/transactions/:id'],
    'admin_get_operator_approval_v1': ['/admin/users/:id', '/admin/admin-users/:id'],
    'admin_approve_email_operator_v1': ['/admin/users/:id', '/admin/admin-users/:id'],
    'admin_revoke_email_operator_v1': ['/admin/users/:id', '/admin/admin-users/:id'],
    **{f'admin_{action}_gateway_device_v1': ['/admin/sms-gateway']
       for action in ['enroll', 'activate', 'revoke']},
    'admin_act_operational_exception_v1': ['/admin/exceptions'],
    'admin_act_exception_workflow_v1': ['/admin/exceptions'],
    # This records a durable read acknowledgement before opening the evidence.
    'admin_read_exception_escalation_v1': ['/admin/exceptions'],
    'admin_configure_receipt_operations_v2': ['/admin/automations'],
    'admin_stop_receipt_operations_v2': ['/admin/automations'],
    'admin_approve_whatsapp': ['/admin/users/:id', '/admin/admin-users/:id'],
    'admin_revoke_whatsapp_approval': ['/admin/users/:id', '/admin/admin-users/:id'],
    'admin_set_user_access': ['/admin/users/:id', '/admin/admin-users/:id'],
    'admin_set_feature_flag_v2': ['/admin/feature-flags'],
    'propose_payment_reconciliation_v2': ['/admin/reconciliations'],
    'approve_payment_reconciliation_v2': ['/admin/reconciliations'],
    'reconciliation-finalize': ['/admin/reconciliations'],
    'prepare-roster-import': ['/admin/groups', '/admin/groups/:id'],
    **{name: ['/admin/groups', '/admin/groups/:id'] for name in [
        'admin_review_roster_import', 'admin_commit_roster_import', 'admin_get_roster_import',
        'admin_save_roster_import_draft', 'admin_recover_roster_import',
        'admin_stage_roster_import_intent', 'admin_execute_roster_import_intent',
        'admin_list_interrupted_roster_imports', 'admin_inspect_interrupted_roster_import',
        'admin_get_interrupted_roster_commit_status', 'admin_transfer_interrupted_roster_import',
        'admin_get_roster_transfer_status']},
}
EDGE_OPERATIONS = {
    'collect-notification-operator': {
        'operation': 'health', 'routes': ['/admin', '/admin/automations'],
        'required_permission': 'notifications.read',
        'receipt_contract': 'lib/admin/core/admin_sms_queue_health.dart',
    },
}
SUPPORT_RPCS = {'admin_current_user', 'admin_get_queue_sla', 'admin_runtime_config', 'collect-notification-operator',
                'admin_list_country_scoped', 'admin_list_platform_payee_candidates'}
READ_ONLY_ACTION_MAP = {'admin_inspect_unstarted_receipt_v1', 'admin_get_unstarted_receipt_action_v1',
    'admin_get_operator_approval_v1', 'admin_get_roster_import',
    'admin_recover_roster_import', 'admin_list_interrupted_roster_imports',
    'admin_inspect_interrupted_roster_import', 'admin_get_interrupted_roster_commit_status',
    'admin_get_roster_transfer_status'}
TYPED_READ_CONTRACTS = {
    'admin_get_operator_approval_v1': 'lib/admin/core/admin_operator_approval.dart',
    'admin_inspect_unstarted_receipt_v1': 'lib/admin/core/admin_receipt_cancel_models.dart',
    'admin_get_unstarted_receipt_action_v1': 'lib/admin/core/admin_receipt_cancel_models.dart',
    'admin_get_operator_entity_audit_v1': 'lib/admin/core/admin_entity_audit.dart',
    'admin_get_unattended_operating_policy_v1': 'lib/admin/core/admin_operating_policy_models.dart',
    'admin_receipt_overview_v1': 'lib/admin/core/admin_receipt_overview.dart',
    'admin_get_collect_investigation_v1': 'lib/admin/core/admin_investigation.dart',
    'admin_list_gateway_devices_v1': 'lib/admin/core/admin_gateway_models.dart',
    'admin_get_gateway_owner_request_v1': 'lib/admin/core/admin_gateway_models.dart',
    'admin_list_operational_exceptions_v2': 'lib/admin/core/admin_exception_models.dart',
    'admin_get_operational_exception_action_v2': 'lib/admin/core/admin_exception_models.dart',
    'admin_get_receipt_deferral_exception_v1': 'lib/admin/core/admin_receipt_deferral_models.dart',
    'admin_get_exception_workflow_v1': 'lib/admin/core/admin_exception_workflow_models.dart',
    'admin_get_exception_workflow_request_v1': 'lib/admin/core/admin_exception_workflow_models.dart',
    'admin_list_exception_escalation_inbox_v1': 'lib/admin/core/admin_exception_workflow_models.dart',
    'admin_get_receipt_operations_policy_v2': 'lib/admin/core/admin_receipt_operations_models.dart',
    'admin_get_receipt_operations_owner_request_v2': 'lib/admin/core/admin_receipt_operations_models.dart',
    'admin_get_receipt_exception_worker_health_v1': 'lib/admin/core/admin_receipt_worker_health.dart',
    'admin_system_health': 'lib/admin/core/admin_operational_health.dart',
    'collect-notification-operator': 'lib/admin/core/admin_sms_queue_health.dart',
    'list_collect_shadow_runs_v1': 'lib/admin/core/admin_shadow_runs.dart',
}
TYPED_ACTION_CONTRACTS = {
    'admin_act_exception_workflow_v1': 'lib/admin/core/admin_exception_workflow_models.dart',
    'admin_read_exception_escalation_v1': 'lib/admin/core/admin_exception_workflow_card.dart',
    'admin_configure_receipt_operations_v2': 'lib/admin/core/admin_receipt_operations_models.dart',
    'admin_stop_receipt_operations_v2': 'lib/admin/core/admin_receipt_operations_models.dart',
}
SDK_OPERATIONS = {'signInWithOtp', 'verifyOTP', 'signOut', 'getAuthenticatorAssuranceLevel',
                  'listFactors', 'challenge', 'verify'}


def sha(value):
    return hashlib.sha256(value).hexdigest()


def mask_comments(source):
    # Preserve character offsets and quoted strings, including raw/triple Dart
    # strings; comments cannot inflate the endpoint/provider declaration set.
    pattern = re.compile(r'''r?(?:"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)|//[^\n]*|/\*[\s\S]*?\*/''')
    return pattern.sub(lambda m: re.sub(r'[^\n]', ' ', m.group()) if m.group().startswith(('/',)) else m.group(), source)


def line(source, pos):
    return source.count('\n', 0, pos) + 1


def named_declarations(source):
    # Lexical declaration evidence only; not a Dart reachability/AST proof.
    pattern = re.compile(r'^\s*(?:(?:static|late|final|const|abstract|external|factory)\s+)*(?:[\w<>?,.(){}:\s]+?\s+)?([A-Za-z_]\w*)(?:<[^()\n]+>)?\s*\(', re.M)
    output = []
    for match in pattern.finditer(source):
        name = match[1]
        if name in {'if', 'for', 'while', 'switch', 'catch', 'assert', 'return', 'throw', 'super'}:
            continue
        start = source.find('(', match.start(), match.end())
        depth = 0
        end = start
        quoted = None
        escape = False
        while end < len(source):
            ch = source[end]
            if quoted:
                if escape: escape = False
                elif ch == '\\': escape = True
                elif ch == quoted: quoted = None
            elif ch in ('"', "'"): quoted = ch
            elif ch == '(': depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0: break
            end += 1
        following = source[end + 1:end + 80].lstrip()
        if re.match(r'(?:async\*?\s*)?(?:\{|=>)', following):
            output.append({'name': name, 'line': line(source, match.start(1))})
    return output


def capture(output):
    admin = sorted(ROOT.glob('lib/admin/**/*.dart'))
    tests = sorted(set(ROOT.glob('test/**/*admin*.dart')) |
                   {ROOT / 'test/shared/notification_preference_runtime_test.dart',
                    ROOT / 'test/features/notification_preferences_recovery_ui_test.dart'})
    migrations = sorted(ROOT.glob('supabase/migrations/*.sql'))
    files = admin + tests + migrations + [pathlib.Path(__file__).resolve()]
    raw = {str(p.relative_to(ROOT)): p.read_bytes() for p in files}
    sources = {name: sha(value) for name, value in raw.items()}
    symbols, providers, dialogs, callbacks, calls, declarations = {}, [], [], [], [], []
    quoted = re.compile(r'''[\x27"]([A-Za-z_][a-zA-Z0-9_-]*)[\x27"]''')
    for path in admin:
        name = str(path.relative_to(ROOT))
        text = raw[name].decode()
        clean = mask_comments(text)
        fixture_only = path.name in {'admin_evidence_mode.dart', 'admin_review_credentials.dart'}
        for m in quoted.finditer(clean):
            if m[1].startswith('admin_') or m[1] in ACTIVE_ACTIONS or m[1] in EDGE_OPERATIONS or m[1].endswith('_payment_reconciliation_v2') or m[1] in {'list_payment_reconciliations_v2', 'list_collect_shadow_runs_v1'}:
                symbols.setdefault(m[1], []).append({'file': name, 'line': line(clean, m.start()), 'fixture_only': fixture_only})
        if fixture_only: continue
        for m in re.finditer(r'\bfinal\s+(\w+Provider)\s*=', clean):
            providers.append({'name': m[1], 'file': name, 'line': line(clean, m.start()), 'expression': clean[m.end():m.end()+180].strip()})
        for m in re.finditer(r'\b(showDialog|showAdmin\w*Dialog)\s*(?:<[^>]+>)?\s*\(', clean):
            dialogs.append({'symbol': m[1], 'file': name, 'line': line(clean, m.start())})
        for m in re.finditer(r'\b(onPressed|onTap|onSelected|onReveal|onRetry|onDone|onChanged|onInvalidate)\s*:', clean):
            callbacks.append({'event': m[1], 'file': name, 'line': line(clean, m.start()), 'expression': clean[m.end():m.end()+150].strip()})
        for m in re.finditer(r'\b(action|rpc|rpcMap|recoveryRpc|invoke|detail|list|currentIdentity|overviewMetrics|queueSla|runtimeConfig|prepareRosterImport|proposePaymentReconciliation|approvePaymentReconciliation|finalizePaymentReconciliation|signInWithOtp|verifyOTP|signOut|listFactors|challenge|verify|getAuthenticatorAssuranceLevel)\s*(?:<[^>]+>)?\s*\(', clean):
            calls.append({'symbol': m[1], 'file': name, 'line': line(clean, m.start()), 'expression': clean[m.end():m.end()+240].strip()})
        declarations.extend({'file': name, **d} for d in named_declarations(clean))
    definitions = {}
    for path in migrations:
        name = str(path.relative_to(ROOT))
        text = raw[name].decode()
        matches = list(re.finditer(r'create\s+(?:or\s+replace\s+)?function\s+(?:(\w+)\.)?(\w+)\s*\(', text, re.I))
        for index, m in enumerate(matches):
            tail = text[m.start():matches[index+1].start() if index+1 < len(matches) else len(text)]
            tag = re.search(r'\$[a-zA-Z0-9_]*\$', tail)
            if tag:
                end = tail.find(tag[0], tag.end())
                body = tail[:end + len(tag[0])] if end >= 0 else tail
            else: body = tail[:2000]
            definitions[m[2]] = {'schema': m[1] or 'public', 'file': name, 'line': line(text, m.start()),
                'definition_sha256': sha(body.encode()),
                'permission_literals': sorted(set(re.findall(r"assert_admin_permission\('([^']+)'\)", body))),
                'source_only': True, 'overload_resolution_verified': False}
    router = mask_comments(raw['lib/admin/admin_router.dart'].decode())
    route_block = re.search(r'const adminRoutePaths\s*=\s*<String>\[([\s\S]*?)\];', router)[1]
    routes = re.findall(r"'([^']+)'", route_block)
    route_gap = sorted(set(routes) ^ set(ROUTE_RPCS))
    endpoints = []
    active = set(ACTIVE_ACTIONS) | SUPPORT_RPCS | {rpc for values in ROUTE_RPCS.values() for rpc in values if rpc.startswith('admin_') or rpc.endswith('_v2') or rpc == 'list_collect_shadow_runs_v1'}
    contracts = mask_comments(raw['lib/admin/core/admin_action_contracts.dart'].decode())
    ack_branches = {}
    for branch in re.finditer(r"((?:'admin_[a-z0-9_]+'\s*(?:\|\|\s*)?)+)=>\s*([\s\S]*?)(?=\n    '(?:admin_)|\n    _ =>)", contracts):
        keys = re.search(r"keys\(\s*'([^']+)'\s*,?\s*\)", branch[2])
        for name in re.findall(r"'(admin_[a-z0-9_]+)'", branch[1]):
            ack_branches[name] = {'exact_keys': keys[1].split() if keys else None,
                'validation_excerpt': branch[2].strip(), 'source': 'lib/admin/core/admin_action_contracts.dart',
                'line': line(contracts, branch.start())}
    read_contracts = mask_comments(raw['lib/admin/core/admin_read_contracts.dart'].decode())
    exact_details = set(re.findall(r"^  '(admin_get_[a-z0-9_]+)': \{", read_contracts, re.M))
    exact_reads = exact_details | {'admin_get_collect_transaction', 'admin_current_user',
                                 'admin_overview', 'admin_runtime_config'}
    for rpc in sorted(set(symbols) | active):
        references = symbols.get(rpc, [])
        if rpc not in definitions and rpc not in ACTIVE_ACTIONS and rpc not in EDGE_OPERATIONS: continue
        statuses = ('active_read_support' if rpc in READ_ONLY_ACTION_MAP else
                    'active_action' if rpc in ACTIVE_ACTIONS else
                    'active_read_support' if rpc in active else 'declared_legacy_or_unrouted_requires_reachability_review')
        endpoints.append({'name': rpc, 'classification': statuses, 'references': references,
            'transport': 'Edge function' if rpc in EDGE_OPERATIONS or rpc in {'prepare-roster-import', 'reconciliation-finalize'} else 'PostgREST RPC',
            'edge_operation': EDGE_OPERATIONS.get(rpc),
            'typed_read_contract_source': TYPED_READ_CONTRACTS.get(rpc),
            'typed_action_contract_source': TYPED_ACTION_CONTRACTS.get(rpc),
            'routes': ACTIVE_ACTIONS.get(rpc, [r for r, values in ROUTE_RPCS.items() if rpc in values]),
            'generic_action_ack_branch': bool(re.search(r"'" + re.escape(rpc) + r"'", contracts)),
            'ack_validation': ack_branches.get(rpc, {'mechanism':
                'typed intent/receipt or durable read acknowledgement; current dispatch, session and persisted audit require named acceptance' if rpc in TYPED_ACTION_CONTRACTS else
                'AdminGatewayOwnerIntent + AdminGatewayActionReceipt: exact request, action, target, UTC timestamp and immutable replay receipt' if rpc.endswith('_gateway_device_v1') else
                'typed roster models/recovery receipts' if 'roster_' in rpc or rpc == 'prepare-roster-import' else
                'typed reconciliation model/API methods; unknown-key rejection requires separate review' if 'reconciliation' in rpc else
                'typed versioned read envelope, exact fields and bounded values; observed execution is tracked separately' if rpc in TYPED_READ_CONTRACTS else
                'strict typed read/record/actor contract in admin_read_contracts.dart; dated scoped SDK acceptance and actual SQL compatibility tracked separately' if rpc in exact_reads else
                'generic map/model read; no per-operation exact field contract currently proven'}),
            'session_fence': {'mechanism': 'SupabaseAdminRosterGateway' if 'roster_' in rpc or rpc == 'prepare-roster-import' else
                'AdminRepository._withSession + AdminRequestSession + provider/dialog generation',
                'pinned_authorization': 'captured dispatch Bearer; request remains bound to original user/session',
                'A_B_A': 'sticky Auth stream invalidation', 'Auth_error_done': 'sticky invalidation',
                'expiry': 'constructor claim/SDK expiry + timer + before/after-await; dated GAP-A06 and actual wall-clock SDK probe acceptance; final protocol source binding tracked separately' if 'roster_' in rpc or rpc == 'prepare-roster-import' else
                'adminSessionKey exp check + AdminSessionController timer; selected SDK source tests'},
            'latest_source_definition': definitions.get(rpc),
            'test_source_references': [str(p.relative_to(ROOT)) for p in tests if rpc in raw[str(p.relative_to(ROOT))].decode()],
            'audit_runtime_verified': False, 'complete_state_matrix_verified': False})
    read_evidence = {'allowed': 'declared source; selected dated synthetic tests',
        'denied': 'admin_route_access_test.dart common signed-out/non-Admin/no-capability loops; dated synthetic execution',
        'loading': 'source widget state; per-route current acceptance pending',
        'empty': 'source widget state; per-route current acceptance pending',
        'failure': 'admin_route_access_test.dart common retry loop; dated synthetic execution',
        'revoked': 'partial selected tests; complete per-route/action matrix pending',
        'session': 'shared pinned session/generation/expiry/Auth error+done; selected actual SDK fixtures',
        'audit': 'source SQL only in this inventory; real audit persistence acceptance pending per active action'}
    auth_evidence = {'allowed': 'Admin login/denied route source; selected login-recovery synthetic tests',
        'denied': 'auth route source; protected-route loops do not cover this route',
        'loading': 'source widget; current per-route evidence pending', 'empty': 'not a record queue',
        'failure': 'selected login-recovery synthetic tests', 'revoked': 'authorization source only in this inventory',
        'session': 'Auth SDK plus shared controller; GAP-A05 actual storage-barrier failure and dated fixed acceptance; final web SDK fork binding tracked separately',
        'audit': 'no UI audit persistence claim'}
    shell = mask_comments('\n'.join(raw[name].decode() for name in [
        'lib/admin/admin_shell.dart', 'lib/admin/admin_shell_navigation.dart']))
    nav_permissions = dict(re.findall(r"_AdminNavDestination\(\s*'[^']+'\s*,\s*Icons\.\w+\s*,\s*'([^']+)'\s*,\s*'([^']+)'", shell))
    def permission(route):
        matches = [base for base in nav_permissions if route == base or route.startswith(base + '/')]
        return nav_permissions[max(matches, key=len)] if matches else None
    inventory = {
        'source_only': True, 'database_called': False, 'provider_called': False,
        'method': 'comment-aware lexical source inventory with explicit active router/action dispatch map; internal declaration list is discovery, not AST/reachability proof',
        'routes': [{'path': r, 'rpcs': ROUTE_RPCS.get(r, []), 'baseline_permission': permission(r),
                    'additional_permissions': ['system_health.read'] if r == '/admin/sms-gateway'
                        else ['notifications.read', 'system_health.read'] if r == '/admin/exceptions'
                        else ['notifications.read', 'system_health.read', 'payments.read (receipt/exception kinds)']
                            if r == '/admin/audit-logs/entity/:kind/:id' else [],
                    'conditional_owner_surfaces': ['Entity action history requires current platform_owner, audit.read and kind-dependent capabilities']
                        if r == '/admin/audit-logs/entity/:kind/:id'
                        else ['Receipt cancellation: current platform_owner with payments.read, notifications.read, system_health.read; notifications.manage to cancel']
                            if r in {'/admin/transactions/:id', '/admin/sms-receipts/:id'}
                        else ['Unattended preparation policy requires current platform_owner, notifications.read and system_health.read; no execution control']
                            if r == '/admin/automations' else [],
                    'state_evidence': auth_evidence if r in {'/admin/login', '/admin/denied'} else read_evidence} for r in routes],
        'route_mapping_gaps': route_gap, 'endpoints': endpoints, 'sdk_operation_symbols': sorted(SDK_OPERATIONS),
        'providers': providers, 'dialog_sites': dialogs, 'callbacks': callbacks,
        'api_call_sites': calls, 'named_declaration_discovery': declarations,
        'export_flow': {'active_export_control_found': False, 'note': 'Source contains Dart export directives only; no active export/download operation or export RPC call. Availability is not claimed.'},
        'sources': sources,
    }
    after = {name: sha((ROOT / name).read_bytes()) for name in sources}
    inventory['source_unchanged_during_capture'] = after == sources
    output.mkdir(parents=True, exist_ok=False)
    for name, data in raw.items():
        copy = output / 'sources' / name
        copy.parent.mkdir(parents=True, exist_ok=True)
        copy.write_bytes(data)
    (output / 'inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    summary = {'passed': not route_gap and after == sources, 'routes': len(routes), 'endpoints': len(endpoints),
        'active_endpoints': sum(e['classification'].startswith('active') for e in endpoints),
        'providers': len(providers), 'dialogs': len(dialogs), 'callbacks': len(callbacks),
        'api_call_sites': len(calls), 'declaration_discovery': len(declarations), 'sources': len(sources),
        'source_unchanged': after == sources, 'inventory_sha256': sha((output / 'inventory.json').read_bytes()),
        'complete_Admin_acceptance': False}
    (output / 'validation.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    raise SystemExit(capture(parser.parse_args().output.resolve()))
