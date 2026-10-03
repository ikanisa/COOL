"""Inventory the frozen candidate and bind existing named evidence; no tests."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
HERE = Path(__file__).resolve().parent
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-final-local-candidate-20261001-current1')
RAPID = ROOT / 'docs/release/rapid-completion-2026-10-01'
SDK = ROOT / '.cache/flutter-sdk-isolated-admin-browser-current1'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def emit(name, value):
    (HERE / name).write_text(json.dumps(value, indent=2) + '\n')


def candidate_hashes():
    return {str(path.relative_to(CANDIDATE)): sha(path)
            for path in sorted(CANDIDATE.rglob('*')) if path.is_file()}


before = candidate_hashes()
manifest = read(CANDIDATE / '.collect-release-candidate.json')
emit('candidate-before.json', before)
# Existing pinned parser configuration is reused without pub/get or app builds.
parser_packet = ROOT / 'docs/release/admin-full-coverage-2026-09-30/ast-attempt9-current-common83'
configuration = parser_packet / 'package_config.json'
parser_source = CANDIDATE / 'scripts/tests/admin_ast_inventory.dart'
argv = [str(SDK / 'bin/dart'), '--packages=' + str(configuration), str(parser_source), str(CANDIDATE)]
run = subprocess.run(argv, cwd=HERE, capture_output=True, text=True, timeout=120)
(HERE / 'ast.stdout').write_text(run.stdout)
(HERE / 'ast.stderr').write_text(run.stderr)
assert run.returncode == 0, 'Existing source parser failed; inspect preserved output'
ast = json.loads(run.stdout)
assert not ast['parser_errors']
emit('ast-inventory.json', ast)
active_units = [unit for unit in ast['units'] if not unit['fixture_only']]

# Reuse the existing lexical producer. Its documented dispatch tables receive
# only the source-proven principal family which arrived after its last capture.
producer = CANDIDATE / 'scripts/tests/admin_full_coverage_inventory.py'
spec = importlib.util.spec_from_file_location('candidate_admin_inventory', producer)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.ROOT = CANDIDATE
principal_reads = ['admin_list_receipt_operations_identities_v3',
                   'admin_get_receipt_operations_identity_v3',
                   'admin_get_receipt_operations_enrollment_request_v3']
principal_actions = ['admin_' + action + '_receipt_operations_identity_v3'
                     for action in ['enroll', 'activate', 'revoke']]
module.ROUTE_RPCS['/admin/automations'] += principal_reads
module.ACTIVE_ACTIONS.update({name: ['/admin/automations'] for name in principal_actions})
module.TYPED_READ_CONTRACTS.update({name: 'lib/admin/core/admin_receipt_principal_models.dart'
                                  for name in principal_reads})
module.TYPED_ACTION_CONTRACTS.update({name: 'lib/admin/core/admin_receipt_principal_models.dart'
                                    for name in principal_actions})
assert module.capture(HERE / 'source-discovery') == 0
inventory = read(HERE / 'source-discovery/inventory.json')

union_path = RAPID / 'full-flutter-accepted-union1/validation.json'
union = read(union_path)
assert union['status'] == 'pass' and union['registered_vm_cases_passed'] == 5014
integration_path = RAPID / 'principal-integration-current2/validation.json'
integration = read(integration_path)
assert integration['status'] == 'pass'
browser_path = RAPID / 'current-admin-browser-current2/browser-acceptance.json'
browser = read(browser_path)
assert browser['status'] == 'pass'
sql_path = ROOT / 'docs/release/collect-codex-goal-2026-09-30/receipt-operations-enrollment-workflow-20261001/sql/attempt3/result.json'
sql = read(sql_path)
assert sql['status'] == 'pass' and len(sql['checks']) == 92

cohorts = union['cohorts']
test_drift = [name for name, row in cohorts.items()
              if not (CANDIDATE / name).is_file()
              or sha(CANDIDATE / name) != row['test_source_sha256']]
runtime_drift = [name for name, digest in union['current_lib_source_sha256'].items()
                 if not (CANDIDATE / name).is_file() or sha(CANDIDATE / name) != digest]
assert not test_drift and not runtime_drift, (test_drift, runtime_drift)
vm_cases = [{'test_file': name, 'test_source_sha256': row['test_source_sha256'],
             'packet': row['packet'], **case}
            for name, row in cohorts.items() for case in row['cases']]
assert len(vm_cases) == 5014 and all(case['result'] == 'success' and not case['skipped'] for case in vm_cases)
emit('named-accepted-cases.json', {
    'vm_union_receipt': str(union_path), 'vm_union_sha256': sha(union_path),
    'registered_vm_cases': vm_cases,
    'affected_cases': {'receipt': str(integration_path), 'sha256': sha(integration_path),
                       'executed_integration': integration['cases'],
                       'unchanged_reused_case_names': integration['prior_remaining_cases'],
                       'total': integration['count'] + integration['prior_remaining_cases_reused']},
    'checkpoint_chrome': integration['prior_chrome_named_cases_passed'],
    'production_browser': {'receipt': str(browser_path), 'sha256': sha(browser_path),
                           'cases': browser['named_browser_checks']},
    'actual_principal_sql': {'receipt': str(sql_path), 'sha256': sha(sql_path),
                             'checks': sql['checks'], 'migrations_sha256': sql['migrations_sha256'],
                             'scope': sql['scope']},
    'scope': 'Executed named cases copied from accepted receipts, not executions performed by this inventory generator. Per-symbol references below identify executed test cohorts, not isolated assertions of every symbol/state.'})

test_text = {name: (CANDIDATE / name).read_text() for name in cohorts}


def references(token):
    return [{'test_file': name, 'test_source_sha256': cohorts[name]['test_source_sha256'],
             'executed_cohort_cases': cohorts[name]['registered_count'],
             'registered_names': [case['name'] for case in cohorts[name]['cases']],
             'relationship': 'source reference in an executed source-bound cohort; per-state assertion is not inferred'}
            for name, text in test_text.items()
            if re.search(r'(?<![A-Za-z0-9_])' + re.escape(token) + r'(?![A-Za-z0-9_])', text)]


for row in inventory['routes']:
    route = row['path']
    row['browser_state_execution'] = [state for state in browser['route_states'] if state['pattern'] == route]
    row['named_route_vm_cases'] = [{'test_file': case['test_file'], 'name': case['name'],
                                   'result': case['result']}
                                  for case in vm_cases if case['test_file'] in {
                                      'test/admin_declared_route_states_test.dart', 'test/admin_route_access_test.dart'}
                                  and re.search(re.escape(route) + r'(?=\s|$)', case['name'])]
    row['state_evidence'] = {
        'executed_browser': 'Signed-out and synthetic email-owner route state: exact rows linked here',
        'executed_vm': 'Only the named per-route cases linked here establish the states asserted by those cases',
        'remaining_limit': 'Browser synthetic empty/unavailable/denied data is not populated production SQL or visual comparator acceptance; generic source references are not state execution'}
for endpoint in inventory['endpoints']:
    endpoint['executed_source_reference_cohorts'] = references(endpoint['name'])
    if endpoint['name'] in principal_actions + principal_reads:
        endpoint['principal_family_evidence'] = {
            'integration_receipt': str(integration_path), 'integration_sha256': sha(integration_path),
            'named_current_family_cases': [case['name'] for case in integration['cases']],
            'actual_sql_receipt': str(sql_path), 'actual_sql_sha256': sha(sql_path),
            'per_endpoint_all_states_claimed': False}
inventory['providers'] = [{**provider, 'source_sha256': sha(CANDIDATE / provider['file']),
                          'executed_source_reference_cohorts': references(provider['name']),
                          'all_provider_states_verified': False}
                         for unit in active_units for provider in unit['providers']]
inventory['dialog_sites'] = [dialog for unit in active_units for dialog in unit['dialogs']]
inventory['callbacks'] = [callback for unit in active_units for callback in unit['callbacks']]
inventory['api_call_sites'] = [call for unit in active_units for call in unit['invocations']]
inventory['ast_declarations'] = [declaration for unit in active_units for declaration in unit['declarations']]
inventory['candidate'] = str(CANDIDATE)
inventory['candidate_manifest_sha256'] = sha(CANDIDATE / '.collect-release-candidate.json')
inventory['candidate_file_count'] = manifest['file_count']
inventory['method'] += '; full current syntax AST replaces lexical provider/dialog/callback/API lists, no semantic reachability claim'
inventory['principal_dynamic_dispatch'] = {
    'source': 'lib/admin/core/admin_receipt_principal_models.dart',
    'expression': "'admin_${name}_receipt_operations_identity_v3'",
    'expanded_enumerated_targets': principal_actions,
    'route': '/admin/automations',
    'evidence': 'Source enum family plus executed actual SDK enroll/activate/revoke assertions; not source-only acceptance'}
inventory['evidence_receipts'] = {'union': str(union_path), 'integration': str(integration_path),
                                  'browser': str(browser_path), 'principal_sql': str(sql_path),
                                  'named_cases': str(HERE / 'named-accepted-cases.json')}
emit('inventory.json', inventory)
after = candidate_hashes()
emit('candidate-after.json', after)
assert before == after, 'Frozen candidate was changed'
summary = {'status': 'pass', 'candidate': str(CANDIDATE), 'candidate_file_count': manifest['file_count'],
           'candidate_unchanged': True, 'routes': len(inventory['routes']),
           'protected_routes': sum(row['path'] not in ['/admin/login', '/admin/denied'] for row in inventory['routes']),
           'endpoints': len(inventory['endpoints']),
           'active_endpoints_declared': sum(row['classification'].startswith('active') for row in inventory['endpoints']),
           'active_action_endpoints_declared': sum(row['classification'] == 'active_action' for row in inventory['endpoints']),
           'providers': len(inventory['providers']), 'dialogs': len(inventory['dialog_sites']),
           'callbacks': len(inventory['callbacks']), 'api_invocations': len(inventory['api_call_sites']),
           'admin_units': len(ast['units']), 'non_fixture_admin_units': len(active_units),
           'source_files': len(inventory['sources']), 'parser_errors': [], 'route_mapping_gaps': inventory['route_mapping_gaps'],
           'vm_cases_bound': len(vm_cases), 'vm_cohorts_bound': len(cohorts),
           'affected_cases_bound': integration['count'] + integration['prior_remaining_cases_reused'],
           'browser_checks_bound': len(browser['named_browser_checks']),
           'checkpoint_chrome_cases_bound': len(integration['prior_chrome_named_cases_passed']),
           'actual_principal_sql_checks_bound': len(sql['checks']),
           'test_source_drift': test_drift, 'runtime_source_drift': runtime_drift,
           'inventory_sha256': sha(HERE / 'inventory.json'), 'ast_inventory_sha256': sha(HERE / 'ast-inventory.json'),
           'named_cases_sha256': sha(HERE / 'named-accepted-cases.json'),
           'parser_command': argv, 'parser_config_sha256': sha(configuration),
           'lexical_producer_sha256': sha(producer), 'ast_producer_sha256': sha(parser_source),
           'tests_run': 0, 'builds_run': 0, 'database_called': False, 'provider_called': False,
           'all_states_of_each_provider_dialog_action_certified': False,
           'scope': 'Current route/action/data-source syntax inventory plus explicit existing named execution mapping. Source references and lexical active classifications are declared discovery, never new runtime acceptance. Original suite failures are retained outside the accepted union.'}
emit('validation.json', summary)
print(json.dumps(summary))
