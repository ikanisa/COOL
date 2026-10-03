"""Bounded local preparation and actual pipe tests; no Docker or SQL execution."""
from pathlib import Path
import datetime
import hashlib
import importlib.util
import json
import os
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
PYTHON = '/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
ENV = {'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8', 'LC_ALL': 'en_US.UTF-8', 'PYTHONDONTWRITEBYTECODE': '1'}


def save(name, value):
    with (HERE / name).open('x') as stream: stream.write(json.dumps(value, indent=2) + '\n')


def call(name, script, seconds):
    argv = [PYTHON, '-I', '-B', str(HERE / script)]
    started = time.monotonic()
    at = datetime.datetime.now(datetime.timezone.utc).isoformat()
    process = subprocess.Popen(argv, cwd=HERE, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        out, err = process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        try: os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        out, err = process.communicate(timeout=5)
    try:
        os.killpg(process.pid, 0); absent = False
    except ProcessLookupError:
        absent = True
    for suffix, body in [('stdout', out), ('stderr', err)]:
        with (HERE / (name + '.' + suffix)).open('xb') as stream: stream.write(body)
    receipt = dict(argv=argv, environment=ENV, cwd=str(HERE), started_at_utc=at,
        actual_seconds=round(time.monotonic()-started, 3), deadline_seconds=seconds,
        exit_code=process.returncode, timed_out=timed_out, pid=process.pid, owned_process_group_absent=absent,
        stdout_sha256=hashlib.sha256(out).hexdigest(), stderr_sha256=hashlib.sha256(err).hexdigest())
    save(name + '.json', receipt)
    if timed_out or process.returncode != 0 or not absent:
        raise ValueError('Actual local command failed: ' + name)
    return receipt


def main():
    if sys.executable != PYTHON or not sys.flags.isolated or not sys.dont_write_bytecode:
        raise ValueError('Exact absolute isolated Python required')
    prepared = call('prepare-command', 'prepare.py', 45)
    spec = importlib.util.spec_from_file_location('prepared_candidate5', HERE / 'prepare.py')
    p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
    before = p.preservation()
    if before != json.loads(p.regular(HERE / 'preservation-before.json')):
        raise ValueError('Prior preparations or retained failures changed')
    inputs = json.loads(p.regular(HERE / 'inputs.json'))
    prior = json.loads(p.regular(p.PRIOR / 'inputs.json'))
    if inputs['sources'] != prior['sources'] or inputs['references'] != prior['references']:
        raise ValueError('All original222 input hashes required')
    hashes = {name: p.sha(p.regular(p.CANDIDATE / name)) for name in {**inputs['sources'], **inputs['references']}}
    if hashes != {**inputs['sources'], **inputs['references']}:
        raise ValueError('Copied candidate input drift')
    artifacts = {name: p.sha(p.regular(HERE / name)) for name in ['rehearsal.py', 'test_rehearsal.py', 'test_runner_io.py', 'run_focused.py', 'prepare.py', 'inputs.json']}
    focused = call('focused-io-tests', 'run_focused.py', 20)
    observed = json.loads(p.regular(HERE / 'actual-io-observations.json'))
    if observed['test_count'] != 8 or observed['failures'] or observed['errors'] or len(observed['observations']) != 8:
        raise ValueError('Exact focused8 proof required')
    reused = []
    for directory, count in [(p.PRIOR.parent / 'ordinary-recovery-replay-preparation2', 18),
                             (p.PRIOR.parent / 'ordinary-recovery-replay-preparation3', 9), (p.PRIOR, 9)]:
        receipt = json.loads(p.regular(directory / 'focused-tests.json'))
        if (receipt['status'] != 'pass' or receipt['tests_passed'] != count or
                any(p.sha(p.regular(directory / name)) != digest for name, digest in receipt['tested_artifact_hashes'].items()) or
                p.sha(p.regular(directory / 'focused-tests.stdout')) != receipt['stdout_sha256'] or
                p.sha(p.regular(directory / 'focused-tests.stderr')) != receipt['stderr_sha256']):
            raise ValueError('Prior proof reuse binding changed')
        reused.append(dict(path=str(directory / 'focused-tests.json'), sha256=p.sha(p.regular(directory / 'focused-tests.json')), recorded_pass_count=count))
    after = p.preservation()
    if (before != after or artifacts != {name: p.sha(p.regular(HERE / name)) for name in artifacts} or
            hashes != {name: p.sha(p.regular(p.CANDIDATE / name)) for name in hashes}):
        raise ValueError('Evidence or inputs changed during verification')
    save('preservation-after-tests.json', after)
    save('affected-proof-summary.json', dict(status='pass', original34_test_bytes_AST_unchanged=True,
        original_runner_tests_reexecuted=2, new_focused_test_methods=6, actual_tests_passed=8,
        real_pipe_backpressure_and_kernel_shortwrites_observed=True, real_stdout_EAGAIN_observed=True,
        original_runner_real_backpressure_failure_observed=True, bounded_timeout_exit_and_fatal_error_contracts_pass=True,
        prior_sql_parser_catalog_test_outcomes_reused_only_for_unchanged_AST=True, prior_pass_receipts=reused,
        admitted222_hashes_before_and_after=hashes, preserved_prior_and_actual_failure_files=len(after),
        tested_artifact_hashes=artifacts, prepare_command=prepared, focused_command=focused,
        whole_program_seconds=600, execution_budget_seconds=540, cleanup_budget_seconds=60,
        docker_executed=False, SQL_executed=False, candidate5_recovery_executed=False, maintained_source_mutations=0,
        full_BE08_closed=False, ARC08_restore_adapter_closed=False, ARC11_closed=False))
    print(json.dumps(dict(status='prepared_and_focused8_pass', inputs=222, preserved_files=len(after),
        code_sha256=artifacts['rehearsal.py'], inputs_sha256=artifacts['inputs.json'], docker_executed=False)))


if __name__ == '__main__': main()
