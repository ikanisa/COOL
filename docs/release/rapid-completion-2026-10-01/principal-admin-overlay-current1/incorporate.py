from pathlib import Path
import hashlib,json,subprocess,shutil
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');OUT=ROOT/'docs/release/rapid-completion-2026-10-01/principal-admin-overlay-current1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
runtime=['lib/admin/core/'+n+'.dart'for n in ['admin_automations_page','admin_repository_base','admin_runtime','admin_receipt_principal_checkpoint_stub','admin_receipt_principal_checkpoint_web','admin_receipt_principal_runtime','admin_receipt_principal_card','admin_receipt_principal_models','admin_receipt_principal_checkpoint','admin_receipt_principal_controller']]
tests=['test/'+n+'.dart'for n in ['admin_receipt_principal_models_test','admin_receipt_principal_recovery_test','admin_receipt_principal_integration_test','admin_receipt_principal_browser_test','admin_exception_workflow_sdk_test','admin_declared_route_states_test']]
fixture_names=['activate-lookup','activate','enroll-input','enroll-lookup','enroll','identity-active','identity-expired-active','identity-pages','identity-revoked','in-progress','not-recorded','revoke-expired-active','revoke-expired-pending','revoke-input','revoke-lookup','revoke']
fixtures=['docs/release/collect-codex-goal-2026-09-30/receipt-operations-enrollment-workflow-20261001/sql/attempt3/observed-'+n+'-v3.json'for n in fixture_names]
inputs={n:sha(ROOT/n)for n in [*runtime,*tests,*fixtures]}
(OUT/'current-first-read.json').write_text(json.dumps({'inputs_sha256':inputs,'scope':'Fresh current read after two peer files changed since earlier delta; no runtime writes'},indent=2)+'\n')
p=ROOT/'scripts/tests/admin_matrix_acceptance.py';g=ROOT/'scripts/tests/admin_read_gateway_gate.py'
for file in[p,g]:
 target=OUT/(file.name+'.before');assert not target.exists();shutil.copy2(file,target)
s=p.read_text();marker='\nCONFIG += CURRENT_ADMIN_DECODER_INPUTS\n';assert s.count(marker)==1
principal="""
# Exact principal v3 observed JSON projection inputs; fail closed if any is
# absent. These fixtures establish client decoding only, not fresh SQL proof.
CURRENT_ADMIN_DECODER_INPUTS += tuple(
    'docs/release/collect-codex-goal-2026-09-30/'
    'receipt-operations-enrollment-workflow-20261001/sql/attempt3/'
    f'observed-{name}-v3.json'
    for name in (
        'activate-lookup', 'activate', 'enroll-input', 'enroll-lookup', 'enroll',
        'identity-active', 'identity-expired-active', 'identity-pages',
        'identity-revoked', 'in-progress', 'not-recorded',
        'revoke-expired-active', 'revoke-expired-pending', 'revoke-input',
        'revoke-lookup', 'revoke',
    )
)
"""
assert sha(p)==sha(OUT/(p.name+'.before'));p.write_text(s.replace(marker,'\n'+principal+marker))
s=g.read_text();marker='BROWSER_CHECKPOINT_CASES = {';assert s.count(marker)==1;s=s.replace(marker,"TESTS += ['test/admin_receipt_principal_models_test.dart',\n          'test/admin_receipt_principal_recovery_test.dart',\n          'test/admin_receipt_principal_integration_test.dart']\n"+marker)
a=s.index('\n\n\ndef digest(path):',s.index('BROWSER_CHECKPOINT_CASES'))
new="""
# This enabled principal browser cohort contains ten cases, unlike the five
# one-case checkpoint cohorts. Require every named execution explicitly.
BROWSER_PRINCIPAL_CASES = {
    'test/admin_receipt_principal_browser_test.dart': (
        'real store reload uses original lookup only and retains resolved bytes',
        'actual lock serializes exact-UUID concurrent publication and prevents overwrite',
        'actual lock refuses distinct pending revoke UUIDs for one target',
        'urgent different-target revoke can publish alongside original activation',
        'authority-lost queued publication acquires no permission to write',
        'five-second aborted lock acquisition never publishes after eventual release',
        'controller timeout closes queued publication before lock becomes available',
        'changed-original actual browser bytes fail closed on reload',
        'changed-marker actual browser bytes fail closed on reload',
        'orphan-marker actual browser bytes fail closed on reload',
    ),
}
BROWSER_TEST_FILES = (*BROWSER_CHECKPOINT_CASES, *BROWSER_PRINCIPAL_CASES)
BROWSER_REQUIRED_CASE_NAMES = (*BROWSER_CHECKPOINT_CASES.values(),
    *(name for names in BROWSER_PRINCIPAL_CASES.values() for name in names))
"""
s=s[:a]+'\n'+new+s[a:];s=s.replace("'--platform=chrome', *BROWSER_CHECKPOINT_CASES,","'--platform=chrome', *BROWSER_TEST_FILES,");s=s.replace("browser_machine['passed'] == len(BROWSER_CHECKPOINT_CASES)","browser_machine['passed'] == len(BROWSER_REQUIRED_CASE_NAMES)");s=s.replace('for title in BROWSER_CHECKPOINT_CASES.values())','for title in BROWSER_REQUIRED_CASE_NAMES)');needle="              'required_browser_checkpoint_cases': BROWSER_CHECKPOINT_CASES if args.browser_checkpoint else {},";assert s.count(needle)==1;s=s.replace(needle,needle+"\n              'required_browser_principal_cases': BROWSER_PRINCIPAL_CASES if args.browser_checkpoint else {},")
assert sha(g)==sha(OUT/(g.name+'.before'));g.write_text(s)
for file in[p,g]:(OUT/(file.name+'.diff')).write_text(subprocess.run(['diff','-u',str(OUT/(file.name+'.before')),str(file)],capture_output=True,text=True).stdout)
result=subprocess.run(['python3','-m','unittest','scripts.tests.test_admin_read_gateway_runner'],cwd=ROOT,capture_output=True,text=True)
(OUT/'current-tool-tests.stdout').write_text(result.stdout);(OUT/'current-tool-tests.stderr').write_text(result.stderr)
second={n:sha(ROOT/n)for n in inputs};drift=[n for n in inputs if inputs[n]!=second[n]]
(OUT/'stable-second-read.json').write_text(json.dumps({'inputs_sha256':second,'drift_from_fresh_first_read':drift,'stable':not drift,'tool_tests_exit_code':result.returncode,'mapping_is_execution_proof':False},indent=2)+'\n');print('TOOLS',result.returncode,'DRIFT',drift,flush=True)
raise SystemExit(0 if not drift and result.returncode==0 else 1)
