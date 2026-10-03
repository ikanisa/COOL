#!/usr/bin/env python3
"""Report observed Admin test cases; never infer whole-system acceptance."""
import argparse
import hashlib
import json
import pathlib
import re
from urllib.parse import unquote, urlparse

# Reviewed aliases are restricted to their actual declaring test source.
# Source references alone are recorded separately and are never execution proof.
OPERATION_ALIASES = {
    'prepare-roster-import': {
        'test/admin_roster_gateway_expiry_test.dart': [
            r'^actual SDK dispatch and awaited expiry prepare pins token '],
    },
    'admin_receipt_overview_v1': {
        'test/admin_receipt_overview_test.dart': [r'^SDK request and session fence '],
    },
    'propose_payment_reconciliation_v2': {
        'test/admin_reconciliation_repository_test.dart': [r'^propose ', r'^proposal '],
    },
    'approve_payment_reconciliation_v2': {
        'test/admin_reconciliation_repository_test.dart': [r'^approve ', r'^approval '],
    },
    'reconciliation-finalize': {
        'test/admin_reconciliation_repository_test.dart': [r'^finalize ', r'^finalization ',
            r'^validates .* acknowledgment', r'^rejects malformed finality ',
            r'^reversed acknowledgment', r'^finalization rejects ',
            r'^denial never invokes a fallback endpoint'],
    },
    'collect-notification-operator': {
        'test/admin_declared_read_dispatch_test.dart': [r'^collect-notification-operator\.health '],
        'test/admin_sms_queue_repository_test.dart': [r'^queue health uses ',
            r'^malformed queue response ', r'^replacement same-user session '],
    },
    'list_collect_shadow_runs_v1': {
        'test/admin_shadow_runs_repository_test.dart': [r'^history calls ',
            r'^invalid window ', r'^isolated backend observation ', r'^corrupt ',
            r'^replacement same-user session '],
    },
}

# Each alias is tied to the real SDK assertions in its named declaring file.
OPERATION_ALIASES.update({
    'admin_get_operator_entity_audit_v1': {
        'test/admin_entity_audit_repository_test.dart': [r'^real pinned SDK reads actual ', r'^real SDK preserves paired cursor '],
        'test/admin_entity_audit_authority_test.dart': [r'^(?:shadow|gateway|supervisor|exception|receipt) entity history provider '],
    },
    'admin_inspect_unstarted_receipt_v1': {
        'test/admin_receipt_cancel_sdk_authority_test.dart': [r'^inspection receipt provider ', r'^inspection receipt private providers '],
    },
    'admin_get_unstarted_receipt_action_v1': {
        'test/admin_receipt_cancel_sdk_authority_test.dart': [r'^lookup receipt provider ', r'^lookup receipt private providers '],
    },
    'admin_cancel_unstarted_receipt_v1': {
        'test/admin_receipt_cancel_sdk_authority_test.dart': [r'^production cancellation card with actual SDK (?:confirmed matching SDK ACK|uncertain SDK |departed SDK ACK)'],
    },
    'admin_get_unattended_operating_policy_v1': {
        'test/admin_operating_policy_runtime_test.dart': [r'^actual SDK binds no-argument policy RPC ', r'^actual SDK rejects fabricated dispatch ', r'^actual SDK does not automatically retry policy ', r'^SDK suppresses departed same-owner response ', r'^provider '],
    },
})

PROVIDER_CONSUMER_TESTS = {
    'adminAuthStateProvider': ['test/admin_realtime_sdk_provider_test.dart'],
    'adminEntityAuditProvider': ['test/admin_entity_audit_authority_test.dart',
        'test/admin_entity_audit_page_test.dart', 'test/admin_declared_route_states_test.dart'],
    'adminReceiptCancelInspectionProvider': ['test/admin_receipt_cancel_sdk_authority_test.dart',
        'test/admin_receipt_cancel_card_test.dart'],
    'adminReceiptCancelLookupProvider': ['test/admin_receipt_cancel_sdk_authority_test.dart',
        'test/admin_receipt_cancel_card_test.dart'],
    'adminReceiptCancelCheckpointStoreProvider': ['test/admin_receipt_cancel_card_test.dart',
        'test/admin_receipt_cancel_sdk_authority_test.dart',
        'test/admin_receipt_cancel_checkpoint_browser_test.dart'],
    'adminOperatingPolicyProvider': ['test/admin_operating_policy_runtime_test.dart'],
    'adminSmsQueueHealthProvider': ['test/admin_automations_test.dart'],
    'adminAutomationHealthProvider': ['test/admin_automations_test.dart'],
    'adminDetailRecordProvider': ['test/admin_value_screen_integrity_test.dart',
        'test/admin_declared_route_states_test.dart',
        'test/admin_private_provider_authority_test.dart'],
    'adminRuntimeConfigProvider': ['test/admin_private_provider_authority_test.dart',
        'test/admin_feature_flag_runtime_test.dart'],
    'adminReceiptOverviewProvider': ['test/admin_receipt_overview_test.dart'],
    'adminOverviewOperationalHealthProvider': ['test/admin_receipt_overview_test.dart'],
    'adminOverviewSmsHealthProvider': ['test/admin_receipt_overview_test.dart'],
    'adminInvestigationProvider': ['test/admin_investigation_test.dart'],
    'adminGatewayDevicesProvider': ['test/admin_gateway_sdk_state_matrix_test.dart',
        'test/admin_gateway_page_test.dart', 'test/admin_declared_route_states_test.dart'],
    'adminGatewayRequestProvider': ['test/admin_gateway_sdk_state_matrix_test.dart',
        'test/admin_gateway_page_test.dart'],
    'adminGatewayCheckpointStoreProvider': ['test/admin_gateway_checkpoint_test.dart',
        'test/admin_gateway_checkpoint_browser_test.dart',
        'test/admin_gateway_page_test.dart', 'test/admin_gateway_action_ui_sdk_test.dart'],
    'adminExceptionCheckpointStoreProvider': ['test/admin_exception_page_test.dart',
        'test/admin_exception_checkpoint_browser_test.dart'],
    'adminExceptionInboxProvider': ['test/admin_exception_sdk_provider_state_test.dart',
        'test/admin_exception_page_test.dart', 'test/admin_declared_route_states_test.dart'],
    'adminExceptionLookupProvider': ['test/admin_exception_sdk_provider_state_test.dart',
        'test/admin_exception_page_test.dart'],
    '_adminIdentityRevisionProvider': ['test/admin_custom_action_ui_test.dart',
        'test/admin_permission_refresh_test.dart', 'test/admin_roster_authority_scope_test.dart'],
    '_adminQueueViewStatesProvider': ['test/admin_data_sync_test.dart',
        'test/admin_list_paging_test.dart', 'test/admin_realtime_stability_test.dart'],
    '_adminOverviewWorkspaceProvider': ['test/admin_overview_totals_test.dart',
        'test/admin_data_sync_test.dart', 'test/admin_declared_route_states_test.dart'],
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet', required=True, type=pathlib.Path)
    parser.add_argument('--inventory', required=True, type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    packet, output = args.packet.resolve(), args.output.resolve()
    gate = json.loads((packet / 'acceptance/validation.json').read_text())
    wrapper = json.loads((packet / 'validation.json').read_text())
    source_inventory = json.loads(args.inventory.read_text())
    export = pathlib.Path(wrapper['source_export'])
    bound = json.loads((packet / 'export-before.json').read_text())
    source_differences = [name for name, digest in source_inventory['sources'].items()
                          if name in bound and bound[name] != digest]
    machine_path = packet / 'acceptance/tests.machine.jsonl'
    def observed_cases(path, platform):
        starts, finishes = {}, {}
        if not path.exists():
            return []
        for line in path.read_text().splitlines():
            event = json.loads(line)
            if event.get('type') == 'testStart':
                starts[event['test']['id']] = event['test']
            elif event.get('type') == 'testDone':
                finishes[event['testID']] = event
        cases = []
        for identity, end in finishes.items():
            if end.get('hidden'):
                continue
            start = starts.get(identity, {})
            # Generated widget cases retain their application declaration in
            # root_url. Browser and VM test IDs belong to separate runners.
            uri = urlparse(start.get('root_url') or start.get('url') or '')
            path = pathlib.Path(unquote(uri.path)) if uri.scheme == 'file' else None
            try:
                source = str(path.relative_to(export)) if path else None
            except ValueError:
                source = str(path)
            cases.append({'test_id': identity, 'execution_platform': platform,
                          'name': start.get('name'), 'source': source,
                          'source_sha256': bound.get(source),
                          'line': start.get('root_line') or start.get('line'),
                          'result': end.get('result'), 'skipped': bool(end.get('skipped'))})
        return cases
    browser_machine_path = packet / 'acceptance/browser-checkpoint.machine.jsonl'
    observed = observed_cases(machine_path, 'vm')
    browser_observed = observed_cases(browser_machine_path, 'chrome')
    observed += browser_observed
    test_sources = {case['source']: (export / case['source']).read_text()
                    for case in observed if case['source'] in bound}

    def successful(name):
        return any(case['name'] == name and case['result'] == 'success'
                   and not case['skipped'] for case in observed)

    patterns = {
        'allowed': 'allowed {route} uses its declared data provider',
        'loading': 'loading {route} cannot present pending records',
        'empty': 'empty {route} is explicit after a successful read',
        'revoked': 'revoked {route} removes previously authorized content',
        'signed_out': 'signed-out deep link {route} stays at login without data',
        'non_admin': 'non-Admin deep link {route} denies before reading records',
        'no_capability': 'an identity without capabilities cannot open {route}',
        'failure_retry': 'record request failure on {route} can retry in place',
    }
    routes = []
    for route in source_inventory['routes']:
        path = route['path']
        if path in {'/admin/login', '/admin/denied'}:
            continue
        states = {}
        for state, pattern in patterns.items():
            if state == 'empty' and path in {'/admin/system-health', '/admin/automations'}:
                states[state] = {'applicable': False, 'reason': 'Required measurement receipt, not a record queue.'}
            else:
                name = pattern.format(route=path)
                states[state] = {'applicable': True, 'test': name,
                                 'observed_pass': successful(name)}
        routes.append({'path': path, 'baseline_permission': route['baseline_permission'],
                       'additional_permissions': route.get('additional_permissions', []),
                       'states': states, 'actual_runtime_navigation_verified': False})
    # Reviewed titles are finite, source-bound expectations. They supplement
    # the older custom-form matrix without implying all action/UI states.
    def reviewed_states(source, names):
        return [{'test': name, 'source': source,
                 'observed_pass': any(case['source'] == source
                    and (case['name'] == name or
                         (case['name'] or '').endswith(' ' + name))
                    and case['result'] == 'success' and not case['skipped']
                    for case in observed)} for name in names]

    gateway_operations = ['admin_list_gateway_devices_v1',
        'admin_get_gateway_owner_request_v1', 'admin_enroll_gateway_device_v1',
        'admin_activate_gateway_device_v1', 'admin_revoke_gateway_device_v1']
    gateway_sdk_source = 'test/admin_gateway_sdk_state_matrix_test.dart'
    gateway_states = []
    for operation in gateway_operations:
        names = [f'{operation} actual SDK exact target body and captured Bearer',
            *[f'{operation} actual SDK {failure} has no fallback or mutation retry'
              for failure in ['denied', '503', 'lost response', 'missing receipt',
                              'extra private field']],
            *[f'{operation} actual SDK suppresses replaced session switchBack={back}'
              for back in ['false', 'true']],
            f'{operation} actual SDK same-session refresh preserves pinned request token',
            f'{operation} actual SDK signed-out caller makes no request']
        if operation in gateway_operations[:2]:
            names += [*[f'{operation} production provider denies missing {capability} before SDK dispatch'
                        for capability in ['notifications.read', 'system_health.read']],
                f'{operation} production provider waits for current identity before SDK dispatch',
                *[f'{operation} production provider redacts {code} service failure'
                  for code in ['42501', 'PGRST202']],
                *[f'{operation} production provider suppresses late SDK read after {departure}'
                  for departure in ['permission loss', 'identity loading', 'identity error']]]
        gateway_states += reviewed_states(gateway_sdk_source, names)
    gateway_dialog_states = []
    for action in ['enroll', 'activate', 'revoke']:
        titles = [f'{action} production dialog SDK success validates exact intent before refresh',
            *[f'{action} production dialog SDK {behavior} {departure}{suffix}'
              for departure in ['permission', 'role', 'loading', 'error',
                                'repository', 'session', 'A-B-A']
              for behavior, suffix in [('clears', ' draft without write'),
                                       ('suppresses late ACK after', '')]],
            *[f'{action} production dialog SDK {outcome} redacts and preserves uncertainty'
              for outcome in ['denied', '503', 'lost', 'wrong-request',
                              'private-extra', *(['wrong-device'] if action != 'enroll' else [])]],
            f'{action} production dialog SDK fresh actor permission denial prevents write']
        gateway_dialog_states += reviewed_states('test/admin_gateway_action_ui_sdk_test.dart', titles)
    private_authority_states = []
    for operation in ['admin_runtime_config', 'admin_get_collection', 'admin_get_user',
                      'admin_get_member_record', 'admin_get_collect_transaction',
                      'admin_get_hybrid_sms_receipt', 'admin_get_notification',
                      'admin_get_admin_user', 'admin_system_health']:
        capability = operation != 'admin_runtime_config'
        titles = [f'{operation} current authority provider pins exact target and SDK bearer',
            *[f'{operation} current authority provider denies {denial} before private SDK read'
              for denial in ['absent identity', *(['missing permission'] if capability else [])]],
            f'{operation} current authority provider waits for identity before private SDK read',
            *[f'{operation} current authority provider suppresses late private SDK read after {departure}'
              for departure in ['absent identity', 'identity loading', 'identity error',
                                *(['permission loss'] if capability else [])]]]
        private_authority_states += reviewed_states('test/admin_private_provider_authority_test.dart', titles)
    private_loaded_detail_states = reviewed_states('test/admin_private_provider_authority_test.dart', [
        f'{operation} production detail hides loaded private content after {departure}'
        for operation in ['admin_get_collection', 'admin_get_member_record']
        for departure in ['permission loss', 'absent identity', 'identity loading',
                          'identity error', 'session replacement', 'A-B-A', 'signed out']])
    exception_sdk_states = []
    for operation in ['admin_list_operational_exceptions_v2',
                      'admin_get_operational_exception_action_v2']:
        titles = [f'{operation} actual SDK exact target body and captured Bearer',
            *[f'{operation} actual SDK {failure} has no fallback or mutation retry'
              for failure in ['denied', '503', 'lost response', 'missing receipt', 'extra private field']],
            *[f'{operation} actual SDK suppresses replaced session switchBack={back}'
              for back in ['false', 'true']],
            f'{operation} actual SDK same-session refresh preserves pinned request token',
            f'{operation} actual SDK signed-out caller makes no request',
            *[f'{operation} production provider denies missing {capability} before SDK dispatch'
              for capability in ['payments.read', 'notifications.read', 'system_health.read']],
            f'{operation} production provider waits for current identity before SDK dispatch',
            *[f'{operation} production provider redacts {code} service failure'
              for code in ['42501', 'PGRST202']],
            *[f'{operation} production provider suppresses late SDK read after {departure}'
              for departure in ['permission loss', 'identity loading', 'identity error']]]
        exception_sdk_states += reviewed_states('test/admin_exception_sdk_provider_state_test.dart', titles)
    checkpoint_states = reviewed_states('test/admin_gateway_checkpoint_test.dart', [
        'bounded checkpoint contains only reviewed nonsensitive references, never the SPKI or replay parameters',
        'fixed project and purpose owner binding differs from another actor',
        *[f'strict checkpoint rejects altered {field}' for field in
          ['version', 'owner_digest', 'action', 'request_id', 'installation_id',
           'device_id', 'key_sha256', 'signing_certificate_sha256', 'public_key_spki_base64']],
        'oversized bookmark and missing change-device identity are rejected',
        'recorded recovery binds all reviewed fingerprints and original action without recreating a mutation'])
    checkpoint_page_states = reviewed_states('test/admin_gateway_page_test.dart', [
        'verified nonsensitive original checkpoint precedes enrollment and exact receipt clears it',
        *[f'recovery {failure} blocks enrollment without exposing storage errors'
          for failure in ['readback corruption', 'write failure']],
        *[f'unconfirmed enrollment survives fresh same-owner sign-in and {state} lookup never clears or replays it'
          for state in ['busy', 'unknown']],
        'old pending response after session replacement cannot remove persisted reviewed request',
        'another owner cannot expose or automatically look up the retained original gateway request',
        'known recorded receipt with failed checkpoint clear stays protected until storage recovers',
        'a changed stored original request cannot be removed by a different completed response',
        *[f'desktop {theme} restored gateway checkpoint synthetic capture' for theme in ['light', 'dark']]])
    browser_checkpoint_states = []
    for source, title in {
        'test/admin_receipt_cancel_checkpoint_browser_test.dart':
            'actual same-tab storage persists exact original intent across adapter recreation and isolates owners',
        'test/admin_exception_checkpoint_browser_test.dart':
            'real browser sessionStorage retains only owner-bound same-tab reviewed references across adapter recreation',
        'test/admin_gateway_checkpoint_browser_test.dart':
            'real same-tab browser adapter retains reviewed fingerprints after recreation and isolates owners',
        'test/admin_roster_bookmark_browser_test.dart':
            'actual browser sessionStorage retains only bounded schema references across adapter recreation',
    }.items():
        browser_checkpoint_states += reviewed_states(source, [title])
    approval_sdk_source = 'test/admin_operator_approval_sdk_matrix_test.dart'
    approval_states = []
    for operation in ['admin_get_operator_approval_v1',
                      'admin_approve_email_operator_v1',
                      'admin_revoke_email_operator_v1']:
        approval_states += reviewed_states(approval_sdk_source, [
            f'{operation} pins current Bearer exact target request and receipt',
            *[f'{operation} rejects {corrupt} receipt without false acceptance'
              for corrupt in ['missing', 'wrong-target', 'private-extra']],
            *[f'{operation} {failure} is one SDK dispatch with no fallback'
              for failure in ['permission', '503', 'network']],
            *[f'{operation} suppresses departed session response A-B-A={back}'
              for back in ['false', 'true']],
            f'{operation} signed out cannot dispatch'])
    approval_panel_states = reviewed_states(approval_sdk_source,
        [*[f'email approval production SDK panel {state}' for state in
           ['success', 'cancel', 'invalid', 'denied', 'uncertain',
            'permission-loss', 'late-session']],
         'email revocation production SDK panel selects exact operation'])
    # Finite source-bound events for the newer active surfaces and L20 consumers.
    # Reporting the entire observed cohort is not a declaration of every state.
    current_cohort_sources = {
        'entity_history_sdk_authority': 'test/admin_entity_audit_authority_test.dart',
        'entity_history_production_page': 'test/admin_entity_audit_page_test.dart',
        'receipt_sdk_authority_ack_uncertainty': 'test/admin_receipt_cancel_sdk_authority_test.dart',
        'receipt_production_card': 'test/admin_receipt_cancel_card_test.dart',
        'unattended_preparation_policy_sdk_and_card': 'test/admin_operating_policy_runtime_test.dart',
        'feature_flag_runtime_ack_and_session': 'test/admin_feature_flag_runtime_test.dart',
        'notification_preference_sdk_and_session': 'test/shared/notification_preference_runtime_test.dart',
        'notification_settings_production_recovery': 'test/features/notification_preferences_recovery_ui_test.dart',
    }
    current_active_cohorts = {
        label: {
            'source': source, 'source_sha256': bound.get(source),
            'cases': [case for case in observed if case['source'] == source],
            'all_surface_states_verified': False,
            'server_audit_verified': False,
        }
        for label, source in current_cohort_sources.items()
    }
    endpoints = []
    custom_names = {
        'createGroup': 'admin_create_platform_public_group',
        'createPayee': 'admin_create_collect_payee',
        'editPayee': 'admin_update_collect_payee',
        'deactivatePayee': 'admin_set_collect_payee_status',
        'activatePayee': 'admin_set_collect_payee_status',
        'deactivateGroup': 'admin_set_group_active',
        'activateGroup': 'admin_set_group_active',
        'approveGroup': 'admin_update_collection_support_status',
        'rejectGroup': 'admin_update_collection_support_status',
        'metadata': 'admin_update_platform_public_group_metadata',
        'note': 'admin_record_operator_note',
        'profileNote': 'admin_record_operator_note',
        'featureFlag': 'admin_set_feature_flag_v2',
    }
    custom_states = ['success', 'cancel', 'invalid', 'revoked-draft',
                     'role-draft', 'loading-draft', 'error-draft', 'session-draft',
                     'late-ack', 'unknown-ack', 'denied']
    custom_actions = [{
        'ui_action': ui, 'operation': rpc,
        'states': {state: {'test': f'{ui} production UI {state}',
                          'observed_pass': successful(f'{ui} production UI {state}')}
                   for state in custom_states},
        'proof': 'Actual production widget and locked SDK with synthetic HTTP; exact request, captured Bearer, ACK parsing and sticky authority fence.',
        'server_audit_verified': False,
    } for ui, rpc in custom_names.items()]
    for endpoint in source_inventory['endpoints']:
        if not endpoint['classification'].startswith('active'):
            continue
        name = endpoint['name']
        literal = re.compile(r'(?<![\w-])' + re.escape(name) + r'(?![\w-])')
        named = [case for case in observed if literal.search(case['name'] or '')]
        aliases = [case for case in observed
                   if any(re.search(pattern, case['name'] or '') for pattern in
                          OPERATION_ALIASES.get(name, {}).get(case['source'], []))
                   and case not in named]
        wrapper_cases = []
        if name == 'admin_list_country_scoped':
            # The declared SDK loop asserts its real wire endpoint/body. Its
            # test title retains the product queue RPC selected in p_rpc_name.
            read_source = (export / 'test/admin_declared_read_dispatch_test.dart').read_text()
            wrapper_rpcs = re.findall(r"'(admin_list_[a-z_]+)'", read_source)
            wrapper_cases = [case for case in observed if case['source'] ==
                'test/admin_declared_read_dispatch_test.dart' and
                any((case['name'] or '').startswith(rpc + ' ') for rpc in wrapper_rpcs)]
            # Only the queues whose production call selects this wrapper.
            runtime_source = (export / 'lib/admin/core/admin_runtime.dart').read_text()
            scoped_switch = re.search(r'bool adminRpcUsesCountryScope\([^;]+?;', runtime_source)
            scoped_names = set(re.findall(r"'(admin_list_[a-z_]+)'",
                                          scoped_switch[0] if scoped_switch else ''))
            wrapper_cases = [case for case in wrapper_cases if any(
                (case['name'] or '').startswith(rpc + ' ') for rpc in scoped_names)]
        associated = named + aliases + wrapper_cases
        endpoints.append({'name': name, 'classification': endpoint['classification'],
                          'transport': endpoint.get('transport'), 'routes': endpoint['routes'],
                          'individually_named_cases': named,
                          'reviewed_alias_cases': aliases,
                          'reviewed_wrapper_cases': wrapper_cases,
                          'reviewed_alias_patterns': OPERATION_ALIASES.get(name, {}),
                          'observed_passing_operation_cases': sum(case['result'] == 'success'
                              and not case['skipped'] for case in associated),
                          'source_test_references': endpoint['test_source_references'],
                          'observed_custom_ui_actions': [action for action in custom_actions
                                                         if action['operation'] == name],
                          'source_reference_is_execution_proof': False,
                          'all_ui_action_states_verified': False,
                          'persisted_audit_verified': False})
    providers = []
    for provider in source_inventory['providers']:
        name = provider['name']
        references = sorted({case['source'] for case in observed
            if case['source'] and case['source'] in bound
            and re.search(r'\b' + re.escape(name) + r'\b',
                          test_sources[case['source']])})
        indirect = PROVIDER_CONSUMER_TESTS.get(name, [])
        cases = [case for case in observed if case['source'] in set(references + indirect)]
        providers.append({**provider,
            'source_sha256': bound.get(provider['file']),
            'direct_test_source_references': references,
            'reviewed_indirect_consumer_test_sources': indirect,
            'observed_reference_cohort_cases': cases,
            'observed_passing_reference_cohort_cases': sum(case['result'] == 'success'
                and not case['skipped'] for case in cases),
            'proof': 'Observed execution of source-bound tests which reference this provider, or reviewed production consumers. A cohort case is not an isolated assertion of every provider state.',
            'all_provider_states_verified': False})
    states = [value for route in routes for value in route['states'].values() if value['applicable']]
    report = {
        'scope': 'Observed exported-source SDK and widget tests. SQL receipts are retained parser inputs; no SQL, hosted provider, live navigation or persisted audit was executed by this gate.',
        'aggregate_client_gate_passed': wrapper['passed'],
        'full_Admin_acceptance': False,
        'inventory_source_matches_tested_shared_inputs': not source_differences,
        'inventory_tested_input_differences': source_differences,
        'source_export_unchanged': wrapper['export_source_unchanged'],
        'transport_dependencies_unchanged': wrapper.get('transport_dependencies_unchanged'),
        'transport_dependencies_sha256': wrapper.get('transport_dependencies_sha256'),
        'machine_summary': gate['machine_summary'],
        'browser_checkpoint_gate_passed': gate.get('browser_checkpoint_passed'),
        'browser_checkpoint_machine_summary': gate.get('browser_checkpoint_machine_summary'),
        'browser_checkpoint_machine_sha256': sha(browser_machine_path) if browser_machine_path.exists() else None,
        'packet': str(packet), 'inventory': str(args.inventory.resolve()),
        'machine_sha256': sha(machine_path), 'inventory_sha256': sha(args.inventory),
        'acceptance_sha256': sha(packet / 'acceptance/validation.json'),
        'wrapper_sha256': sha(packet / 'validation.json'),
        'reporter_source_sha256': sha(pathlib.Path(__file__)),
        'actual_read_receipt_sha256': wrapper['receipt_sha256'],
        'protected_routes': routes, 'active_endpoints': endpoints,
        'providers': providers,
        'active_endpoints_without_named_or_reviewed_alias_pass': [value['name']
            for value in endpoints if not value['observed_passing_operation_cases']],
        'providers_without_observed_reference_cohort_pass': [value['name']
            for value in providers if not value['observed_passing_reference_cohort_cases']],
        'roster_actual149_decoder_passed': gate.get('actual_roster_sql149_decoder_passed'),
        'dated_roster_sql149_receipt': wrapper.get('dated_roster_sql149_receipt'),
        'custom_ui_actions': custom_actions,
        'typed_gateway_sdk_and_provider_states': gateway_states,
        'typed_gateway_production_dialog_states': gateway_dialog_states,
        'typed_private_authority_provider_states': private_authority_states,
        'typed_loaded_private_detail_states': private_loaded_detail_states,
        'typed_exception_sdk_and_provider_states': exception_sdk_states,
        'typed_gateway_checkpoint_states': checkpoint_states,
        'typed_gateway_checkpoint_page_states': checkpoint_page_states,
        'typed_actual_browser_checkpoint_states': browser_checkpoint_states,
        'typed_email_approval_sdk_states': approval_states,
        'typed_email_approval_production_panel_states': approval_panel_states,
        'current_active_source_bound_cohorts': current_active_cohorts,
        'settings_surface_boundary': 'Admin /settings reads admin_list_settings. Admin feature-flag changes are in /feature-flags with reason/ACK/session tests. Member NotificationSettingsScreen uses the separately declared production preference-recovery cohort; no Admin preference editor is invented.',
        'typed_state_matrix_scope': 'Source-bound finite SDK/provider/panel assertions; mock HTTP runs the locked SDK. TimeoutException is synthetic loss, not network retransmission proof. Dated Gateway DTO observations are decoder inputs, not current server installation. These cohorts do not certify every dialog/action or server state.',
        'required_custom_ui_state_cases': len(custom_actions) * len(custom_states),
        'observed_passing_custom_ui_state_cases': sum(state['observed_pass']
            for action in custom_actions for state in action['states'].values()),
        'inventory_inputs_excluded_from_client_export': [name for name in source_inventory['sources']
                                                       if name not in bound],
        'required_route_state_cases': len(states),
        'observed_passing_route_state_cases': sum(state['observed_pass'] for state in states),
        'public_auth_routes': ['/admin/login', '/admin/denied'],
        'auth_and_session_cases': [case for case in observed if case['source'] in {
            'test/admin_login_recovery_test.dart', 'test/admin_logout_lifecycle_test.dart',
            'test/admin_action_session_test.dart', 'test/admin_session_scope_test.dart',
            'test/admin_action_ui_session_test.dart'}],
        'all_observed_cases': observed,
        'declared_test_exclusions': [{
            'source': 'test/admin_roster_sql_receipts_test.dart',
            'source_sha256': bound.get('test/admin_roster_sql_receipts_test.dart'),
            'reason': 'Historical PostgreSQL142 parser cohort requires its distinct dated receipts. The current required actual149 decoder has separate mandatory acceptance; no database runs here.',
        }],
        'remaining_proof': [
            'Current installed navigation/server identity is verified by root-owned packets; route fixtures do not prove current database installation.',
            'Independent financial step-up, platform-access and roster UI proof are in their named cases and separate packets; listed custom widget states are not a whole Admin visual claim.',
            'Root-owned server authorization races, exact execution and persisted audit per active action.',
            'Dated actual149 recovery decoder is a copied parser input when included; normal browser and current server recovery proof remain separately bound.',
            'Required Revolut comparator, interaction and visual evidence per surface.',
        ],
    }
    output.mkdir(parents=True, exist_ok=False)
    (output / 'matrix.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['# Admin observed client matrix', '', report['scope'], '',
             f"Aggregate client gate passed: **{wrapper['passed']}**. Full Admin acceptance: **false**.", '',
             f"Protected route state cases: **{report['observed_passing_route_state_cases']}/{len(states)}** observed passes.", '',
             '| Route | Allowed | Loading | Empty | Revoked | Signed out | Non Admin | No capability | Retry |',
             '| --- | --- | --- | --- | --- | --- | --- | --- | --- |']
    for route in routes:
        marks = [('N/A' if not state['applicable'] else 'PASS' if state['observed_pass'] else 'PENDING')
                 for state in route['states'].values()]
        lines.append('| ' + route['path'] + ' | ' + ' | '.join(marks) + ' |')
    lines += ['', '## Observed custom action states', '',
              f"**{report['observed_passing_custom_ui_state_cases']}/{report['required_custom_ui_state_cases']}** observed passes using actual production widgets and the locked SDK against synthetic HTTP.", '',
              '| UI action | Operation | Passing states |',
              '| --- | --- | --- |']
    for action in custom_actions:
        count = sum(state['observed_pass'] for state in action['states'].values())
        lines.append(f"| {action['ui_action']} | {action['operation']} | {count}/{len(custom_states)} |")
    lines += ['', '## Typed SDK, provider and approval-panel states', '',
              '| Cohort | Observed finite states |', '| --- | --- |']
    for label, cases in [('Gateway SDK and providers', gateway_states),
                         ('Gateway production SDK dialogs', gateway_dialog_states),
                         ('Private authority SDK providers', private_authority_states),
                         ('Loaded private production detail', private_loaded_detail_states),
                         ('Exceptions SDK and providers', exception_sdk_states),
                         ('Gateway checkpoint decoder', checkpoint_states),
                         ('Gateway checkpoint production page', checkpoint_page_states),
                         ('Actual Chrome checkpoint adapters', browser_checkpoint_states),
                         ('Email approval SDK', approval_states),
                         ('Email approval production panel', approval_panel_states)]:
        lines.append(f"| {label} | {sum(case['observed_pass'] for case in cases)}/{len(cases)} |")
    lines += ['', '## Current active consumer cohorts', '',
              '| Consumer cohort | Passing finite events | Source |',
              '| --- | --- | --- |']
    for label, cohort in current_active_cohorts.items():
        passing = sum(case['result'] == 'success' and not case['skipped']
                      for case in cohort['cases'])
        lines.append(f"| {label} | {passing}/{len(cohort['cases'])} | {cohort['source']} |")
    lines += ['', report['settings_surface_boundary'], '',
              report['typed_state_matrix_scope'], '',
              '## Coverage associations and limits', '',
        f"Active endpoints: **{len(endpoints)}**. Endpoints with no named or reviewed alias passing case: **{len(report['active_endpoints_without_named_or_reviewed_alias_pass'])}**.", '',
        'Operation aliases are reviewed against their declaring test source; source string references alone are not execution proof. Provider reference cohorts record direct references and reviewed indirect production consumers, with every state still independently bounded.', '',
        '- Operation association gaps: ' + ', '.join(report['active_endpoints_without_named_or_reviewed_alias_pass']),
        '- Provider association gaps: ' + ', '.join(report['providers_without_observed_reference_cohort_pass']),
        '- Dated actual149 decoder passed: ' + str(report['roster_actual149_decoder_passed']),
        '- Browser-only roster storage/reload scenarios are covered by their separate actual browser packet, not the VM gate.']
    lines += ['', '## Remaining proof', '', *['- ' + value for value in report['remaining_proof']], '',
              'Each case, exact test source hash, packet hash, active endpoint and source mismatch is retained in matrix.json. Endpoint names in test titles and source references do not certify every UI or server state.']
    (output / 'README.md').write_text('\n'.join(lines) + '\n')
    print(json.dumps({key: report[key] for key in ['aggregate_client_gate_passed',
        'full_Admin_acceptance', 'inventory_source_matches_tested_shared_inputs',
        'required_route_state_cases', 'observed_passing_route_state_cases',
        'required_custom_ui_state_cases', 'observed_passing_custom_ui_state_cases']}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
