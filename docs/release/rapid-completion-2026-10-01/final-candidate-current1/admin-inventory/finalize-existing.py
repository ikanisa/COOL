"""Complete metadata from the one preserved parser/capture invocation."""
from pathlib import Path
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-final-local-candidate-20261001-current1')
ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


before = read(HERE / 'candidate-before.json')
after = {str(path.relative_to(CANDIDATE)): sha(path)
         for path in sorted(CANDIDATE.rglob('*')) if path.is_file()}
assert before == after
(HERE / 'candidate-after.json').write_text(json.dumps(after, indent=2) + '\n')
inventory = read(HERE / 'inventory.json')
ast = read(HERE / 'ast-inventory.json')
cases = read(HERE / 'named-accepted-cases.json')
union = read(Path(cases['vm_union_receipt']))
for name, row in union['cohorts'].items():
    assert sha(CANDIDATE / name) == row['test_source_sha256'], name
for name, digest in union['current_lib_source_sha256'].items():
    assert sha(CANDIDATE / name) == digest, name
active = [unit for unit in ast['units'] if not unit['fixture_only']]
all_invocations = [call for unit in active for call in unit['invocations']]
api_methods = {
    'action', 'rpc', '_rpc', 'rpcMap', 'recoveryRpc', 'invoke', 'detail', 'list',
    'currentIdentity', 'overviewMetrics', 'queueSla', 'runtimeConfig',
    'prepareRosterImport', 'proposePaymentReconciliation',
    'approvePaymentReconciliation', 'finalizePaymentReconciliation',
    'signInWithOtp', 'verifyOTP', 'signOut', 'listFactors', 'challenge',
    'verify', 'getAuthenticatorAssuranceLevel',
}
for unit in active:
    if unit['file'] == 'lib/admin/core/admin_repository_base.dart':
        api_methods.update(row['name'] for row in unit['declarations']
                           if row['kind'] == 'method' and not row['name'].startswith('_'))
inventory['method_invocation_discovery'] = all_invocations
inventory['api_call_sites'] = [call for call in all_invocations if call['method'] in api_methods]
inventory['api_discovery_scope'] = {
    'methods': sorted(api_methods),
    'meaning': 'Declared repository methods and transport/Auth dispatch syntax; all method calls retained separately. Semantic receiver resolution and endpoint reachability are not inferred.',
}
cohorts = union['cohorts']
test_text = {name: (CANDIDATE / name).read_text() for name in cohorts}


def cohort_links(token):
    return [{'test_file': name, 'test_source_sha256': cohorts[name]['test_source_sha256'],
             'executed_cohort_cases': cohorts[name]['registered_count'],
             'registered_names_location': 'named-accepted-cases.json:registered_vm_cases',
             'relationship': 'source reference in executed cohort; isolated behavior/state is not inferred'}
            for name, text in test_text.items()
            if re.search(r'(?<![A-Za-z0-9_])' + re.escape(token) + r'(?![A-Za-z0-9_])', text)]


for dialog in inventory['dialog_sites']:
    token = dialog['scope'].split('/')[-1] or dialog['method']
    dialog['executed_source_reference_cohorts'] = cohort_links(token)
    dialog['all_dialog_states_verified'] = False
inventory['data_source_cohort_mapping'] = {
    method: cohort_links(method)
    for method in sorted({call['method'] for call in inventory['api_call_sites']})
}
(HERE / 'inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
sql = cases['actual_principal_sql']
sql_bindings = {}
for name, digest in sql['migrations_sha256'].items():
    relative = name if name.startswith('supabase/') else 'supabase/migrations/' + name
    path = CANDIDATE / relative
    sql_bindings[relative] = {'accepted_sha256': digest,
                             'candidate_sha256': sha(path) if path.is_file() else None}
    assert sql_bindings[relative]['candidate_sha256'] == digest, relative
summary = {
    'status': 'pass', 'candidate': str(CANDIDATE),
    'candidate_file_count': inventory['candidate_file_count'], 'candidate_unchanged': True,
    'candidate_manifest_sha256': inventory['candidate_manifest_sha256'],
    'routes': len(inventory['routes']),
    'protected_routes': sum(row['path'] not in ['/admin/login', '/admin/denied'] for row in inventory['routes']),
    'endpoints': len(inventory['endpoints']),
    'active_endpoints_declared': sum(row['classification'].startswith('active') for row in inventory['endpoints']),
    'active_action_endpoints_declared': sum(row['classification'] == 'active_action' for row in inventory['endpoints']),
    'providers': len(inventory['providers']), 'dialogs': len(inventory['dialog_sites']),
    'callbacks': len(inventory['callbacks']), 'api_call_sites': len(inventory['api_call_sites']),
    'all_method_invocations_discovered': len(all_invocations),
    'admin_units': len(ast['units']), 'non_fixture_admin_units': len(active),
    'source_files': len(inventory['sources']), 'parser_errors': ast['parser_errors'],
    'route_mapping_gaps': inventory['route_mapping_gaps'],
    'vm_cases_bound': len(cases['registered_vm_cases']), 'vm_cohorts_bound': len(union['cohorts']),
    'affected_cases_bound': cases['affected_cases']['total'],
    'affected_cases_are_reused_subset_not_additional_global_cases': True,
    'browser_checks_bound': len(cases['production_browser']['cases']),
    'checkpoint_chrome_cases_bound': len(cases['checkpoint_chrome']),
    'actual_principal_sql_checks_bound': len(sql['checks']),
    'actual_principal_sql_migration_bindings': sql_bindings,
    'test_source_drift': [], 'runtime_source_drift': [],
    'inventory_sha256': sha(HERE / 'inventory.json'),
    'ast_inventory_sha256': sha(HERE / 'ast-inventory.json'),
    'named_cases_sha256': sha(HERE / 'named-accepted-cases.json'),
    'lexical_producer_sha256': sha(CANDIDATE / 'scripts/tests/admin_full_coverage_inventory.py'),
    'ast_producer_sha256': sha(CANDIDATE / 'scripts/tests/admin_ast_inventory.dart'),
    'parser_config_sha256': sha(ROOT / 'docs/release/admin-full-coverage-2026-09-30/ast-attempt9-current-common83/package_config.json'),
    'parser_invocations': 1, 'tests_run': 0, 'builds_run': 0,
    'database_called': False, 'provider_called': False,
    'import_cache_failure_preserved_and_only_generated_cache_restored': True,
    'all_states_of_each_provider_dialog_action_certified': False,
    'scope': 'Complete current syntax/declared route/action/data-source discovery from the immutable2117 candidate, with named existing execution links. Source reference cohorts are identified as reference relationships; their case counts do not prove an isolated state assertion for every referenced symbol. No later live-root edits are included.'}
assert not summary['parser_errors'] and not summary['route_mapping_gaps']
(HERE / 'validation.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary))
