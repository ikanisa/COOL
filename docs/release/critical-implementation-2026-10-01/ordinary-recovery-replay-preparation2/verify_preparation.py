#!/usr/bin/env python3
"""Bound focused tests and seal a prepared proposal; never call Docker."""
from pathlib import Path
import datetime
import difflib
import importlib.util
import json
import os
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
PYTHON = '/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
ENV = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def main():
    if sys.executable != PYTHON or not sys.flags.isolated or not sys.dont_write_bytecode:
        raise ValueError('Exact isolated absolute interpreter required')
    p = load('prepare_candidate2', HERE / 'prepare.py')
    r = load('recovery_candidate2', HERE / 'rehearsal.py')
    before = p.preservation()
    frozen_before = json.loads(p.regular(HERE / 'preservation-before.json'))
    if before != frozen_before:
        raise ValueError('Immutable candidate1 or failure inputs changed')
    inputs = json.loads(p.regular(HERE / 'inputs.json'))
    original = json.loads(p.regular(p.PRIOR / 'inputs.json'))
    if inputs['sources'] != original['sources'] or inputs['references'] != original['references']:
        raise ValueError('Admitted216+4 hashes changed')
    admitted = {**inputs['sources'], **inputs['references']}
    def frozen():
        hashes = {name: p.sha(p.regular(p.CANDIDATE / name)) for name in admitted}
        if hashes != admitted or any(p.regular(p.ROOT / name) != p.regular(p.CANDIDATE / name) for name in inputs['sources']):
            raise ValueError('Admitted input changed')
        return hashes
    initial = frozen()
    tests = p.test_asts(HERE / 'test_rehearsal.py'); old = p.test_asts(p.PRIOR / 'test_rehearsal.py')
    if len(tests) != 18 or len(old) != 10 or any(tests.get(k) != v for k, v in old.items()):
        raise ValueError('Exact18 with original10 AST required')
    artifacts = {name: p.sha(p.regular(HERE / name)) for name in ['rehearsal.py','test_rehearsal.py','inputs.json','source-role-globals.json']}
    argv = [PYTHON, '-I', '-B', str(HERE / 'test_rehearsal.py'), '-v']
    previous = HERE / 'focused-tests.json'
    if previous.exists():
        receipt = json.loads(p.regular(previous))
        out, err = p.regular(HERE / 'focused-tests.stdout'), p.regular(HERE / 'focused-tests.stderr')
        if (receipt['status'] != 'pass' or receipt['argv'] != argv or receipt['environment'] != ENV or
                receipt['tested_artifact_hashes'] != artifacts or
                receipt['admitted220_hashes_before_and_after'] != initial or
                receipt['stdout_sha256'] != p.sha(out) or receipt['stderr_sha256'] != p.sha(err)):
            raise ValueError('Existing focused-test proof cannot be reused')
        timed_out, exit_code, elapsed = receipt['timed_out'], receipt['exit_code'], receipt['elapsed_seconds']
    else:
        started = time.monotonic()
        process = subprocess.Popen(argv, cwd=p.ROOT, env=ENV, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        timed_out = False
        try:
            out, err = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            timed_out = True; os.killpg(process.pid, signal.SIGKILL); out, err = process.communicate(timeout=5)
        elapsed, exit_code = time.monotonic() - started, process.returncode
        (HERE / 'focused-tests.stdout').write_bytes(out)
        (HERE / 'focused-tests.stderr').write_bytes(err)
    if len(out) > 1024**2 or len(err) > 1024**2:
        raise ValueError('Bounded focused test output required')
    import re
    if timed_out or exit_code or not re.search(rb'Ran 18 tests in .*\n\nOK\n', err):
        raise ValueError('Actual18 tests must pass')
    after = p.preservation()
    if after != before or frozen() != initial or artifacts != {name:p.sha(p.regular(HERE / name)) for name in artifacts}:
        raise ValueError('Inputs changed during focused tests')
    (HERE / 'preservation-after.json').write_text(json.dumps(after, indent=2) + '\n')
    query = r.role_inventory_query(p.regular(p.CANDIDATE / r.CATALOG).decode())
    (HERE / 'role-globals-query.sql').write_text(query)
    (HERE / 'source-role-prerequisite.sql').write_text(r.SOURCE_ROLE_SQL + '\n')
    source_globals = json.loads(p.regular(HERE / 'source-role-globals.json'))
    r.restore_role_plan(source_globals, source_globals)
    receipt = dict(kind='collect_recovery_candidate2_focused_tests', status='pass',
        at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), argv=argv, environment=ENV,
        cwd=str(p.ROOT), exit_code=exit_code, timed_out=timed_out,
        timeout_seconds=20, elapsed_seconds=elapsed, tests_passed=18,
        original10_test_AST_unchanged=True, stdout_sha256=p.sha(out), stderr_sha256=p.sha(err),
        tested_artifact_hashes=artifacts, admitted220_hashes_before_and_after=initial,
        immutable149_prior_and_failed_execution_hashes_unchanged=(before == after),
        prior_and_failed_execution_file_count=len(after), role_count=30, membership_count=23, setting_count=8,
        source_role_row=r.SOURCE_ROLE, source_role_sql_sha256=p.sha((r.SOURCE_ROLE_SQL+'\n').encode()),
        role_query_sha256=p.sha(query.encode()), docker_executed=False, maintained_source_mutations=0,
        full_BE08_closed=False, ARC08_closed=False, ARC11_closed=False)
    (HERE / 'focused-tests.json').write_text(json.dumps(receipt, indent=2) + '\n')
    matrix = json.loads(p.regular(p.PRIOR / 'command-scope-matrix.json'))
    def replace(value):
        if isinstance(value, str):
            return value.replace('ordinary-recovery-replay-preparation1', 'ordinary-recovery-replay-preparation2').replace('20261002-candidate1','20261002-candidate2').replace('committed-recovery1','committed-recovery2')
        if isinstance(value, list): return [replace(v) for v in value]
        if isinstance(value, dict): return {k:replace(v) for k,v in value.items()}
        return value
    matrix = replace(matrix)
    matrix['code_sha256'] = artifacts['rehearsal.py']; matrix['inputs_sha256'] = artifacts['inputs.json']
    matrix['review_record_schema']['code_sha256'] = artifacts['rehearsal.py']
    matrix['review_record_schema']['inputs_sha256'] = artifacts['inputs.json']
    matrix['proposed_execution_argv'].insert(1, '-I')
    role_scope = dict(stage='readonly_source_and_restore_role_globals',
        query=query, query_sha256=p.sha(query.encode()), exact_frozen_catalog_expressions=True,
        role='postgres NOSUPERUSER; read-only repeatable read before pg_restore',
        source_role_count=30, source_membership_count=23, source_settings_count=8,
        unknown_missing_extra_or_differing_role_attrs_memberships_settings_refused=True)
    role_create = dict(stage='target_exact_source_role_prerequisite', sql=r.SOURCE_ROLE_SQL,
        sql_sha256=p.sha(r.SOURCE_ROLE_SQL.encode()), exact_observed_source_role=r.SOURCE_ROLE,
        role='supabase_admin; exact local synthetic-only source global; before pg_restore',
        allowed_missing_roles=[r.SOURCE_ROLE[0]], no_SQL_if_already_exact=True,
        image_fixture_complete=False, single_database_dump_excludes_source_role_globals=True,
        all30_roles_memberships_settings_rechecked_before_archive_restore=True)
    for index,row in enumerate(matrix['sql_input_and_authority_matrix']):
        if row['stage'] == 'target_restore_prerequisites':
            row['inputs'][0] = 'exact admitted image globals plus only observed source supabase_functions_admin prerequisite; complete readonly30-role/23-membership/8-setting equality before pg_restore'
            matrix['sql_input_and_authority_matrix'][index+1:index+1] = [role_scope, role_create]
            break
    matrix['source_role_global_prerequisite'] = role_create
    matrix['retained_failure_readback_sha256'] = inputs['lineage']['failed_execution_readback_sha256']
    (HERE / 'command-scope-matrix.json').write_text(json.dumps(matrix, indent=2) + '\n')
    for name in ['rehearsal.py','test_rehearsal.py']:
        diff = ''.join(difflib.unified_diff(p.regular(p.PRIOR/name).decode().splitlines(True),
            p.regular(HERE/name).decode().splitlines(True), fromfile='preparation1/'+name, tofile='preparation2/'+name))
        (HERE / (name + '.diff')).write_text(diff)
    # Seal the completed private proposal after actual tests and immutable readback.
    rows = [dict(path=path.name, bytes=len(body), sha256=p.sha(body))
        for path in sorted(HERE.iterdir()) if path.is_file() and path.name not in ['packet-files.json','SHA256SUMS']
        for body in [p.regular(path)]]
    (HERE / 'packet-files.json').write_text(json.dumps(dict(status='prepared_only', docker_executed=False,
        files=rows), indent=2) + '\n')
    (HERE / 'SHA256SUMS').write_text(''.join(row['sha256']+'  '+row['path']+'\n' for row in rows))
    for row in rows:
        if p.sha(p.regular(HERE / row['path'])) != row['sha256']:
            raise ValueError('Final proposal seal readback failed')
    print(json.dumps(dict(status='prepared_and_focused_tests_pass', tests=18, input_count=220,
        preserved_files=len(after), code_sha256=artifacts['rehearsal.py'], inputs_sha256=artifacts['inputs.json'],
        packet_sha256=p.sha(p.regular(HERE / 'packet-files.json')), sealed_leaves=len(rows),
        docker_executed=False, full_BE08_closed=False)))


if __name__ == '__main__':
    main()
