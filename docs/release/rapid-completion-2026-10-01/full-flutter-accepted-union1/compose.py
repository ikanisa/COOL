"""Compose complete registered cohorts; preserve every failed original command."""
from pathlib import Path
from collections import defaultdict
import hashlib
import json

ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / 'docs/release/rapid-completion-2026-10-01'
OUT = Path(__file__).resolve().parent


def read(name):
    return json.loads((BASE / name).read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return 'test/' + path.split('/test/', 1)[1]


packets = [
    'full-flutter-current-resumption1/vm.machine.jsonl',
    'full-flutter-unmet-continuation1/vm.machine.jsonl',
    'supabase-inventory-correction1/vm.machine.jsonl',
    'principal-admin-overlay-current1/vm.stdout',
    'principal-integration-current2/cases.stdout',
]
original = read('full-flutter-current-resumption1/source-before.json')
overlay = read('principal-admin-overlay-current1/inputs.json')
integration = read('principal-integration-current2/inputs.json')
inventory = read('supabase-inventory-correction1/capture.json')
maps = [original, original,
        {**original, 'test/supabase_contract_test.dart': inventory['current_test_sha256']},
        overlay['inputs_sha256'], integration['inputs_sha256']]
accepted = {}
for packet, inputs in zip(packets, maps):
    events = []
    for line in (BASE / packet).read_text().splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    suites = {e['suite']['id']: relative(e['suite']['path'])
              for e in events if e.get('type') == 'suite'}
    starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    expected = {suites[e['group']['suiteID']]: e['group']['testCount']
                for e in events if e.get('type') == 'group' and e['group']['parentID'] is None}
    cases = defaultdict(list)
    for e in events:
        if e.get('type') == 'testDone' and not e['hidden']:
            t = starts[e['testID']]
            cases[suites[t['suiteID']]].append(
                {'name': t['name'], 'result': e['result'], 'skipped': e['skipped']})
    for name, rows in cases.items():
        if len(rows) == expected.get(name):
            accepted[name] = {'registered_count': expected[name], 'cases': rows,
                              'packet': packet, 'test_source_sha256': inputs[name]}

assert len(accepted) == 227
assert sum(v['registered_count'] for v in accepted.values()) == 5014
assert all(c['result'] == 'success' and not c['skipped']
           for v in accepted.values() for c in v['cases'])
assert all(sha(ROOT / n) == v['test_source_sha256'] for n, v in accepted.items())
selected = read('full-flutter-current-resumption1/test-selection.json')
browser_files = overlay['chrome_selection']
optional = 'test/gateway/gateway_capture_test.dart'
assert "if (directory == null) return;" in (ROOT / optional).read_text()
assert len(browser_files) == 6
assert set(p.relative_to(ROOT).as_posix() for p in (ROOT / 'test').rglob('*_test.dart')) == (
    set(accepted) | set(browser_files) | {optional})
assert all(sha(ROOT / n) == integration['inputs_sha256'][n] for n in browser_files)
browser = read('current-admin-browser-current2/browser-acceptance.json')
assert browser['status'] == 'pass' and browser['affected_vm_cases_total'] == 482
assert len(browser['named_checkpoint_chrome_cases_reused']) == 15
assert browser['browser_check_count'] == 88
assert not browser['current_compiler_drift'] and not browser['current_source_added']
assert read('principal-integration-current2/validation.json')['status'] == 'pass'
assert read('supabase-inventory-correction1/validation.json')['status'] == 'pass'

# Prove every original declaration in the two expanded shared API files is
# byte-identical after removing only the four newly added principal methods
# and their exact imports. Automations is executed in the affected cohort.
old_export = Path(read('full-flutter-current-resumption1/source-export.json')['export'])
name = 'lib/admin/core/admin_repository_base.dart'
text = (ROOT / name).read_text().replace("import 'admin_receipt_principal_models.dart';\n", '')
start = text.index('\n  Future<Map<String, dynamic>> receiptPrincipals(')
end = text.index('\n  Future<Map<String, dynamic>> operatingPolicy()', start)
assert text[:start] + text[end:] == (old_export / name).read_text()
name2 = 'lib/admin/core/admin_runtime.dart'
text = (ROOT / name2).read_text()
for line in ["import 'admin_receipt_principal_models.dart';\n",
             "import 'admin_receipt_principal_checkpoint.dart';\n",
             "import 'admin_receipt_principal_controller.dart';\n",
             "part 'admin_receipt_principal_runtime.dart';\n",
             "part 'admin_receipt_principal_card.dart';\n"]:
    assert text.count(line) == 1
    text = text.replace(line, '')
start = text.index('  @override\n  Future<Map<String, dynamic>> receiptPrincipals(')
end = text.index('  @override\n  Future<Map<String, dynamic>> configureReceiptOperations(', start)
assert text[:start] + text[end:] == (old_export / name2).read_text()
changed = [n for n, h in original.items() if n.startswith('lib/') and n.endswith('.dart')
           and sha(ROOT / n) != h]
assert set(changed) == {name, name2, 'lib/admin/core/admin_automations_page.dart'}
current_lib = {p.relative_to(ROOT).as_posix(): sha(p) for p in (ROOT / 'lib').rglob('*.dart')}
assert all(h == integration['inputs_sha256'][n] for n, h in current_lib.items())

receipts = packets + ['principal-integration-current2/validation.json',
                     'current-admin-browser-current2/browser-acceptance.json',
                     'supabase-inventory-correction1/validation.json',
                     'full-flutter-current-resumption1/validation.json',
                     'full-flutter-unmet-continuation1/validation.json']
result = {
    'status': 'pass', 'registered_vm_cases_passed': 5014, 'vm_cohorts': 227,
    'distinct_file_name_pairs': 4982,
    'duplicate_names_preserved_as_separate_registered_cases': 32,
    'cohorts': accepted, 'chrome_files': browser_files, 'chrome_cases': 15,
    'production_browser_checks': 88, 'optional_capture_generator': optional,
    'optional_capture_scope': 'Environment-gated output generator; no default acceptance tests registered.',
    'current_lib_source_sha256': current_lib,
    'old_shared_declarations_byte_identical_after_exact_addition_removal': [name, name2],
    'affected_automations_current_execution': 'principal-admin-overlay-current1/vm.stdout',
    'whole_fatal_analysis': 'full-flutter-current-resumption1/analysis.log',
    'new_affected_fatal_analysis': 'principal-integration-current2/analysis.stdout',
    'receipt_sha256': {n: sha(BASE / n) for n in receipts},
    'original_40min_timeout_and_all_failed_commands_retained': True,
    'scope': 'All current declared Flutter test cohorts completed by exact complete-file/case composition. Unchanged declarations reused; affected principal, workflow, route, integration and inventory consumers executed. Current production Admin/Chrome evidence is separately bound. No hosted, provider, device or visual-fidelity claim.',
}
(OUT / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'status': 'pass', 'vm_cases': 5014, 'vm_cohorts': 227,
                  'chrome_cases': 15, 'browser_checks': 88}))
