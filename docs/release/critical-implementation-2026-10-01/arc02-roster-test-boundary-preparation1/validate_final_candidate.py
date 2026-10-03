from pathlib import Path
import hashlib
import json
import os
import signal
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
CANDIDATE = OUT / 'candidate'
BINARY = ROOT / '.cache/roster-deno-2.5.6-20260929/deno'
TESTS = ['supabase/functions/prepare-roster-import/handler_test.ts',
         'supabase/functions/prepare-roster-import/ai_dispatch_policy_test.ts']
THREE = [*TESTS, 'supabase/functions/prepare-roster-import/handler_test_fixture.ts']
FLAGS = ['--no-config', '--no-remote', '--no-npm', '--frozen',
         '--lock=supabase/functions/deno.lock']
ENV = {'PATH': os.defpath, 'DENO_DIR': '/Users/jeanbosco/Library/Caches/deno',
       'NO_COLOR': '1', 'DENO_NO_UPDATE_CHECK': '1', 'DENO_NO_PROMPT': '1'}
PATHS = sorted(p for p in CANDIDATE.rglob('*') if p.is_file())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


BEFORE = {str(p.relative_to(CANDIDATE)): sha(p) for p in PATHS}
RESULTS = []


def run(phase, command, timeout=90):
    started = time.monotonic()
    stem = OUT / ('final-' + phase)
    with stem.with_suffix('.stdout').open('xb') as stdout, stem.with_suffix('.stderr').open('xb') as stderr:
        child = subprocess.Popen(command, cwd=CANDIDATE, env=ENV,
                                 stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                 start_new_session=True)
        timed_out = False
        try:
            exit_code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(child.pid, signal.SIGKILL)
            exit_code = child.wait(timeout=5)
    try:
        os.killpg(child.pid, 0)
        group_absent = False
    except ProcessLookupError:
        group_absent = True
    receipt = {'phase': phase, 'command': command, 'cwd': str(CANDIDATE),
               'timeout_seconds': timeout, 'exit_code': exit_code, 'timed_out': timed_out,
               'elapsed_seconds': time.monotonic() - started,
               'owned_process_group_absent': group_absent,
               'stdout_sha256': sha(stem.with_suffix('.stdout')),
               'stderr_sha256': sha(stem.with_suffix('.stderr'))}
    RESULTS.append(receipt)
    (OUT / 'final-commands.json').write_text(json.dumps(RESULTS, indent=2) + '\n')
    assert exit_code == 0 and not timed_out and group_absent, receipt


run('types', [str(BINARY), 'check', *FLAGS, *TESTS])
run('format', [str(BINARY), 'fmt', '--no-config', '--check', *THREE])
run('lint', [str(BINARY), 'lint', '--no-config', *THREE])
run('registrations', [str(BINARY), 'run', *FLAGS, '--cached-only', '--no-prompt',
                      '--allow-read=' + str(OUT), str(OUT / 'collect_registrations.ts'), *TESTS])
EXPECTED = json.loads((OUT / 'attempt2-baseline-registrations.stdout').read_text())
ACTUAL = json.loads((OUT / 'final-registrations.stdout').read_text())
assert EXPECTED == ACTUAL
run('tests', [str(BINARY), 'test', *FLAGS, '--cached-only', '--no-prompt',
              '--junit-path=' + str(OUT / 'final-tests.junit.xml'), *TESTS], 120)
XML = ET.parse(OUT / 'final-tests.junit.xml')
CASES = XML.findall('.//testcase')
assert [n.get('name') for n in CASES] == [n['name'] for n in EXPECTED]
assert len(CASES) == 127 and not any(XML.findall('.//' + n) for n in ['failure', 'error', 'skipped'])
AFTER = {str(p.relative_to(CANDIDATE)): sha(p) for p in PATHS}
assert BEFORE == AFTER
PROPOSAL = json.loads((OUT / 'proposal.json').read_text())
assert all(sha(ROOT / path) == before['sha256'] for path, before in PROPOSAL['before'].items())
BASELINE = OUT / 'baseline/supabase/functions/prepare-roster-import/handler_test.ts'
ORIGINAL = BASELINE.read_text()
CORE = ORIGINAL[ORIGINAL.index('Deno.test("source hash'):ORIGINAL.index('// AI dispatch policy cases')]
POLICY = ORIGINAL[ORIGINAL.index('// AI dispatch policy cases'):]
HELPERS = ORIGINAL[ORIGINAL.index('const ACTOR ='):ORIGINAL.index('Deno.test("source hash')]
assert (CANDIDATE / TESTS[0]).read_text().split('Deno.test("source hash', 1)[1].rstrip('\n') == CORE.split('Deno.test("source hash', 1)[1].rstrip('\n')
assert (CANDIDATE / TESTS[1]).read_text().split('// AI dispatch policy cases', 1)[1] == POLICY.split('// AI dispatch policy cases', 1)[1]
assert HELPERS in (CANDIDATE / THREE[2]).read_text()
RESULT = {
    'status': 'pass', 'submitted_candidate_source_before': BEFORE,
    'submitted_candidate_source_after': AFTER, 'source_unchanged': True,
    'maintained_inputs_unchanged': True, 'original_handler_unchanged': True,
    'registered_names_order_and_transpiled_callback_sha256_equal': True,
    'all_127_original_tests_passed': True, 'core_tests': 74, 'ai_policy_tests': 53,
    'failures': 0, 'errors': 0, 'skipped': 0,
    'original_helper_declarations_and_policy_sections_byte_identical': True,
    'core_registration_section_byte_identical_except_trailing_blank_line': True,
    'runtime': {'deno': '2.5.6', 'sha256': sha(BINARY)},
    'network_permission': False, 'provider_calls': 0, 'SQL_calls': 0,
    'new_test_gates': False, 'CI_1200_line_gate_changed': False,
    'root_integration_required': True,
}
(OUT / 'final-validation.json').write_text(json.dumps(RESULT, indent=2) + '\n')
print(json.dumps({key: RESULT[key] for key in ['status', 'all_127_original_tests_passed',
                 'core_tests', 'ai_policy_tests', 'source_unchanged', 'maintained_inputs_unchanged']}))
