#!/usr/bin/env python3
"""Copy the exact admitted candidate1 inputs; preserve its execution evidence."""
from pathlib import Path
import ast
import hashlib
import json
import stat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PRIOR = HERE.parent / 'ordinary-recovery-replay-preparation1'
FAILURE = HERE.parent / 'ordinary-recovery-replay-execution1/readback.json'
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate2')


def sha(body):
    return hashlib.sha256(body).hexdigest()


def regular(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Unsubstituted input required: ' + str(path))
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError('Regular single-link input required: ' + str(path))
    body = path.read_bytes()
    after = path.lstat()
    if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
        raise ValueError('Input changed during read')
    return body


def test_asts(path):
    return {n.name: ast.dump(n, include_attributes=False) for n in ast.walk(ast.parse(regular(path)))
            if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}


def preservation():
    old = json.loads(regular(PRIOR / 'packet-files.json'))
    for row in old['files']:
        body = regular(PRIOR / row['path'])
        if len(body) != row['bytes'] or sha(body) != row['sha256']:
            raise ValueError('Candidate1 seal drift: ' + row['path'])
    rows = {str(path): sha(regular(path)) for path in sorted(PRIOR.iterdir()) if path.is_file()}
    failure_body = regular(FAILURE)
    failed = json.loads(failure_body)
    if (failed['status'] != 'failed' or failed['passed_cases'] != 11 or
            not failed['all_owned_containers_removed'] or
            'role "supabase_functions_admin" does not exist' not in failed['first_failure']):
        raise ValueError('Exact retained candidate1 failure required')
    actual = Path(failed['actual_output_root'])
    if len(failed['verified_files']) != 137:
        raise ValueError('Exact 137-file failed execution cohort required')
    rows[str(FAILURE)] = sha(failure_body)
    for row in failed['verified_files']:
        path = actual / row['path']
        body = regular(path)
        if len(body) != row['bytes'] or sha(body) != row['sha256']:
            raise ValueError('Failed execution input drift: ' + row['path'])
        rows[str(path)] = sha(body)
    return rows


def main():
    if CANDIDATE.exists() or (HERE / 'inputs.json').exists():
        raise ValueError('Fresh candidate2 and manifest required')
    before = preservation()
    prior = json.loads(regular(PRIOR / 'inputs.json'))
    old_candidate = Path(prior['candidate'])
    if len(prior['sources']) != 216 or len(prior['references']) != 4:
        raise ValueError('Exact 216+4 admitted cohort required')
    names = {str(p.relative_to(old_candidate)) for p in (old_candidate / 'supabase/migrations').glob('*.sql')}
    if names != {p for p in prior['sources'] if p.startswith('supabase/migrations/')} or len(names) != 209:
        raise ValueError('Exact original209 migration set required')
    admitted = {**prior['sources'], **prior['references']}
    # Verify every byte before creating/copying any candidate2 input.
    bodies = {}
    for name, digest in admitted.items():
        body = regular(old_candidate / name)
        if sha(body) != digest or (name in prior['sources'] and regular(ROOT / name) != body):
            raise ValueError('Admitted source drift: ' + name)
        bodies[name] = body
    CANDIDATE.mkdir(parents=True, mode=0o700)
    for name, body in bodies.items():
        path = CANDIDATE / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body); path.chmod(0o600)
    manifest = dict(prior, candidate=str(CANDIDATE), status='prepared_only', execution_done=False,
        lineage=dict(candidate1_inputs_sha256=sha(regular(PRIOR / 'inputs.json')),
                     candidate1_packet_sha256=sha(regular(PRIOR / 'packet-files.json')),
                     failed_execution_readback_sha256=sha(regular(FAILURE)),
                     failed_execution_actual_files=137,
                     source_role_global_prerequisite='supabase_functions_admin',
                     image_fixture_complete=False))
    (HERE / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    predecessor = json.loads(bodies['reference/observed-output/ordinary_populated/predecessor-effective-catalog.json'])
    globals_ = {key: predecessor[key] for key in ('roles', 'memberships', 'settings')}
    if (len(globals_['roles']), len(globals_['memberships']), len(globals_['settings'])) != (30, 23, 8):
        raise ValueError('Exact frozen role-global cohort required')
    (HERE / 'source-role-globals.json').write_text(json.dumps(globals_, indent=2) + '\n')
    (HERE / 'retained-failure-readback.json').write_bytes(regular(FAILURE))
    original_tests = test_asts(PRIOR / 'test_rehearsal.py')
    candidate_tests = test_asts(HERE / 'test_rehearsal.py')
    if len(original_tests) != 10 or any(candidate_tests.get(k) != v for k, v in original_tests.items()):
        raise ValueError('Original10 test AST changed')
    after = preservation()
    if before != after:
        raise ValueError('Immutable candidate1 or actual failure bytes changed')
    (HERE / 'preservation-before.json').write_text(json.dumps(before, indent=2) + '\n')
    (HERE / 'preparation-readback.json').write_text(json.dumps(dict(status='pass',
        copied_input_hashes={name: sha(regular(CANDIDATE / name)) for name in admitted},
        admitted_input_count=220, migration_count=209, original10_test_AST_unchanged=True,
        immutable_prior_and_failed_execution_hashes=after, old_inputs_unchanged=True,
        whole_deadline_seconds=600, docker_executed=False, maintained_source_mutations=0), indent=2) + '\n')
    print(json.dumps(dict(status='prepared_only', copied_inputs=220, original_migrations=209,
                         preserved_failure_files=137, docker_executed=False)))


if __name__ == '__main__':
    main()
